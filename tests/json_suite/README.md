# Optional JSON parser corpus

`parsing.tar.gz` contains the unchanged 318 `test_parsing/*.json` inputs from
[nst/JSONTestSuite at 1ef36fa01286573e846ac449e8683f8833c5b26a](https://github.com/nst/JSONTestSuite/tree/1ef36fa01286573e846ac449e8683f8833c5b26a/test_parsing).
The accompanying MIT [license](LICENSE) is retained. The archive uses sorted
basenames, mode 0644, zero timestamps and gzip mtime zero; its SHA-256 is
`31d35123cfbff5adbdeda4b397df235b81666927e955b5f19b006526490d1b69`.

Run from the repository root inside the Nix development shell, after building
the compiler and runtime:

```sh
zig-out/bin/linea build tests/json_suite/validate.lin -o /tmp/linea-json-validator
python3 tests/json_suite/run.py /tmp/linea-json-validator
```

The runner makes no network requests and does not run as part of the default
whole-repository graph. It verifies the archive hash and complete, unique
classification before execution. Each native process has a five-second timeout;
crashes, file failures and usage failures cannot count as valid rejection.

[classification.tsv](classification.tsv) records the policy for every input.
`y_` inputs are accepted except the two duplicate-key objects: Linea rejects
repeated decoded member names. `n_` inputs are rejected. Of the upstream
implementation-dependent `i_` inputs, valid number tokens are accepted without
Float64 conversion; malformed Unicode/UTF-8, a leading BOM and the 500-container
input are rejected. Parsing uses the normal public default limits.
