#!/usr/bin/env python3
"""Run the pinned parser corpus against a compiled validate.lin executable."""
import argparse
import hashlib
from pathlib import Path
import subprocess
import tarfile
import tempfile


ARCHIVE_SHA256 = "31d35123cfbff5adbdeda4b397df235b81666927e955b5f19b006526490d1b69"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("validator", type=Path)
    args = parser.parse_args()
    validator = args.validator.resolve(strict=True)
    root = Path(__file__).resolve().parent
    archive = root / "parsing.tar.gz"
    if hashlib.sha256(archive.read_bytes()).hexdigest() != ARCHIVE_SHA256:
        raise SystemExit("pinned corpus checksum differs")
    classification = {}
    for row in (root / "classification.tsv").read_text().splitlines():
        if row.startswith("#"):
            continue
        name, expected, policy = row.split("\t")
        if name in classification or expected not in ("accept", "reject"):
            raise SystemExit(f"invalid classification: {row}")
        classification[name] = (expected, policy)
    failed = 0
    accepted = 0
    rejected = 0
    with tarfile.open(archive, "r:gz") as corpus, tempfile.TemporaryDirectory() as scratch:
        members = corpus.getmembers()
        if len({item.name for item in members}) != len(members):
            raise SystemExit("duplicate corpus member")
        if {item.name for item in members} != classification.keys():
            raise SystemExit("classification does not cover the complete corpus")
        target = Path(scratch) / "input.json"
        for item in members:
            if not item.isfile():
                raise SystemExit(f"unexpected corpus member: {item.name}")
            target.write_bytes(corpus.extractfile(item).read())
            expected, policy = classification[item.name]
            try:
                result = subprocess.run(
                    [str(validator), str(target)], capture_output=True, timeout=5,
                )
            except subprocess.TimeoutExpired:
                print(f"FAIL {item.name}: timeout")
                failed += 1
                continue
            expected_exit = 0 if expected == "accept" else 1
            if result.returncode != expected_exit:
                diagnostic = result.stderr.decode("utf-8", errors="replace").strip()
                print(f"FAIL {item.name}: exit {result.returncode}, expected {expected_exit} ({policy}); {diagnostic}")
                failed += 1
            elif expected == "accept":
                accepted += 1
            else:
                rejected += 1
    print(f"JSON corpus: {accepted} accepted, {rejected} rejected, {failed} failed")
    return int(failed != 0)


if __name__ == "__main__":
    raise SystemExit(main())
