# Inputs the fuzzer found

One file per input, raw bytes, in the directory of the property it broke.

CI uploads failed fuzz artifacts for thirty days. Preserve each crashing input
here so it remains a regression test after that artifact expires.

**An input goes in with the fix, in the same commit**, and stays after the fix
lands. It is a regression test, and it is also seed material: the fuzzer starts
from these rather than from noise, so the next search begins where the last one
found something.

`corpus.zig` names each input and says what it broke, which a filename cannot
carry. The entries are replayed twice over: handed to the fuzzer as seed
material, and walked by an ordinary test in the normal test suite — a
regression that only fails in CI is one somebody finds after they have moved
on.
