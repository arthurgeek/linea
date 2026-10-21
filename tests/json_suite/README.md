# Optional JSON parser corpus

`parsing.tar.gz` contains the unchanged 318 `test_parsing/*.json` inputs from
[nst/JSONTestSuite at 1ef36fa01286573e846ac449e8683f8833c5b26a](https://github.com/nst/JSONTestSuite/tree/1ef36fa01286573e846ac449e8683f8833c5b26a/test_parsing).
The accompanying MIT [license](LICENSE) is retained. The archive uses sorted
basenames, mode 0644, zero timestamps and gzip mtime zero; its SHA-256 is
`31d35123cfbff5adbdeda4b397df235b81666927e955b5f19b006526490d1b69`.

The corpus walk runs the suite through the transcript
[the_parser_classifies_every_suite_input.cmd](the_parser_classifies_every_suite_input.cmd),
so `zig build test` fails when any verdict disagrees with its class; it takes
about ten seconds, building the validator included. To run this suite alone
inside the Nix development shell:

```sh
zig build conformance -- tests/json_suite
```

The transcript needs only `sh`, `tar` and the validator, verifies that the
classification covers every archive member with no duplicates, and reports each
wrong verdict with the validator's reason. Crashes, file failures and usage
failures cannot count as valid rejection.

[classification.tsv](classification.tsv) records the policy for every input.
`y_` inputs are accepted except the two duplicate-key objects: Linea rejects
repeated decoded member names. `n_` inputs are rejected. Of the upstream
implementation-dependent `i_` inputs, valid number tokens are accepted without
Float64 conversion; malformed Unicode/UTF-8, a leading BOM and the 500-container
input are rejected. Parsing uses the normal public default limits.
