//! The checked standard library the unit tests share.
//!
//! A language server checks the library once for its session and resumes each
//! module from it; a test of the server's answers does the same. Checking the
//! library is most of what one analysis costs, so a test binary that built one
//! per test would check it several hundred times over.
//!
//! Built on first use and never released: it lives as long as the test
//! process, and its allocations are outside every test's leak check.

const std = @import("std");
const loader = @import("loader.zig");

var shared: ?*loader.CheckedLibrary = null;

/// The library every test resumes from. Tests run one at a time, so the first
/// caller builds it and every later one reads it.
pub fn get() *const loader.CheckedLibrary {
    if (shared) |library| return library;
    const library = loader.CheckedLibrary.init(std.heap.smp_allocator) catch |err|
        std.debug.panic("the standard library does not check: {s}", .{@errorName(err)});
    shared = library;
    return library;
}
