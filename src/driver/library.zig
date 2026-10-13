const std = @import("std");

const InMemoryFile = @import("loader.zig").InMemoryFile;

/// The standard library, carried in the binary rather than found on disk.
///
/// The default location of the `std` dependency every program has. Carried
/// rather than found, so what a compilation reaches cannot depend on what sits
/// beside the program being compiled. It holds the library's manifest as well
/// as its sources, so the copy says what it is exactly as the directory does.
///
/// The paths are the ones the loader reads: a module is a directory, and the
/// root of the library is the prelude because an import names a directory
/// below the module that writes it.
pub const files = blk: {
    const listed = @import("library_manifest").files;
    var out: [listed.len]InMemoryFile = undefined;
    for (listed, 0..) |f, i| out[i] = .{ .path = f.path, .text = f.text };
    break :blk out;
};

/// The directory the embedded copy's files are laid out under, which is where
/// its prelude module sits.
pub const prelude_dir = "std";

/// The name of the library every program depends on, which an import path
/// starting with it reaches. A root whose manifest gives this name is that
/// library, compiled as itself rather than beside a second copy.
pub const dependency_name = "std";
