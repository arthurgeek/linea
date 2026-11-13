"""Observe intentionally blocked or aborting fixture processes, then reap them."""
import os
import resource
import selectors
import signal
import subprocess
import sys
import time

resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
mode = sys.argv[2]
process = subprocess.Popen([sys.argv[1]], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
try:
    if mode == "terminal":
        output, _ = process.communicate(timeout=60)
        assert process.returncode == -signal.SIGABRT, output.decode(errors="replace")
        lines = output.splitlines()
        # Reject every unexpected line, including sanitizer/storage reports
        # that an otherwise expected abort could conceal from the runner.
        assert len(lines) == 1 and lines[0].startswith(b"linea: panic: EXPLICIT_TERMINAL_POLICY_NO_NORMAL_SETTLEMENT at "), output.decode(errors="replace")
        print("terminal policy observed; no normal settlement claimed")
    else:
        selector = selectors.DefaultSelector()
        selector.register(process.stdout, selectors.EVENT_READ)
        output = bytearray()
        deadline = time.monotonic() + 60
        marker = b"JOIN_ATTEMPT"
        while marker not in output:
            assert time.monotonic() < deadline, bytes(output).decode(errors="replace")
            events = selector.select(timeout=0.1)
            for key, _ in events:
                chunk = os.read(key.fileobj.fileno(), 4096)
                assert chunk, bytes(output).decode(errors="replace")
                output.extend(chunk)
        selector.close()
        assert process.poll() is None, bytes(output).decode(errors="replace")
        # A join-attempt marker alone does not establish a blocked join.
        # Let an erroneous return reach the immediate forbidden outcome.
        try:
            tail, _ = process.communicate(timeout=1)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            tail, _ = process.communicate(timeout=10)
        else:
            raise AssertionError((bytes(output) + tail).decode(errors="replace"))
        output.extend(tail)
        assert bytes(output).splitlines() == [b"UNRELATED_FIBER_PROGRESS", marker], bytes(output).decode(errors="replace")
        print("unrelated fiber progressed; native call and join remain blocked")
finally:
    if process.poll() is None:
        os.killpg(process.pid, signal.SIGKILL)
    process.wait()
