// Relative imports keep shared compiler files one module instance and one test.
comptime {
    _ = @import("main.zig");
    _ = @import("conformance_main.zig");
}
