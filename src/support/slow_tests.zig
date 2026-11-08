//! Whether this unit-test binary runs the tests named `slow:`.
//!
//! A test is named `slow:` when it takes ten seconds or more in a Debug unit
//! binary. `-Dslow-tests=false` builds the binary with those tests skipped,
//! for the Debug `check` lane, which leaves them to the ReleaseSafe run of the
//! same tests in `optimised`. Every other build runs them.
//!
//! This file is the one reader of the `test_options` module.

const run_slow_tests = @import("test_options").slow_tests;

/// Skip the calling test when the binary was built with `-Dslow-tests=false`.
/// It is the first statement of every test named `slow:`, and nothing else
/// names it; `build.zig` holds the two to each other.
pub fn skipUnlessRun() error{SkipZigTest}!void {
    if (!run_slow_tests) return error.SkipZigTest;
}
