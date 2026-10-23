const std = @import("std");
const testing = std.testing;

/// A declaration the compiler calls from code it generated.
pub const Call = struct {
    /// The library module holding it, which is how it is found: a generated
    /// call names a module and a name, never a binding something resolved.
    module: []const u8,
    name: []const u8,
};

/// Every declaration generated code calls.
///
/// Two passes need this and they need it for opposite reasons. Lowering reads it
/// to find what a generated call names. The unused rule reads it to know that a
/// declaration nothing in its own module calls is nonetheless reached — and
/// without that, each of these would have to be `pub` to escape being unused,
/// which is a name in the library's public surface that no program should call,
/// there because of a lookup rather than because of a decision.
///
/// So the table is what lets them be private, and private is what makes them
/// unreachable by construction rather than by whether anything can import the
/// module holding them.
///
/// Here rather than beside either reader, because a list one pass owns and
/// another mirrors is the drift this compiler keeps finding: a name added to
/// lowering and not to the exemption is a library that stops compiling, and a
/// name removed from lowering and not from the exemption is a declaration that
/// silently stops being checked for use.
pub const table = [_]Call{
    .{ .module = "mem", .name = "linea_arg_count" },
    .{ .module = "mem", .name = "linea_arg_at" },
    .{ .module = "mem", .name = "linea_arg_len" },
    .{ .module = "mem", .name = "linea_env_count" },
    .{ .module = "mem", .name = "linea_env_at" },
    .{ .module = "mem", .name = "linea_env_len" },
    .{ .module = "mem", .name = "linea_errno" },
    .{ .module = "core", .name = "report" },
    .{ .module = "core", .name = "ran" },
    .{ .module = "testing", .name = "selected" },
    .{ .module = "testing", .name = "no_such_test" },
    .{ .module = "fmt", .name = "interpolate_display" },
    .{ .module = "fmt", .name = "interpolate_debug" },
    .{ .module = "fmt", .name = "interpolate_integer" },
    .{ .module = "fmt", .name = "interpolate_float" },
    .{ .module = "fmt", .name = "interpolate_float32" },
};

/// Whether generated code calls a declaration of this name in this module.
pub fn holds(module: []const u8, name: []const u8) bool {
    for (table) |c| {
        if (std.mem.eql(u8, c.module, module) and std.mem.eql(u8, c.name, name)) return true;
    }
    return false;
}

test "a generated call names a module and a name" {
    try testing.expect(holds("core", "report"));
    try testing.expect(holds("testing", "no_such_test"));

    // The module is part of the identity. A program's own `report` is not this
    // one, and neither is a library declaration of the same name elsewhere.
    try testing.expect(!holds("testing", "report"));
    try testing.expect(!holds("text", "report"));
    try testing.expect(!holds("io", "println"));
}

test "what generated code calls is not in the library's public surface" {
    // Private, and reachable by the compiler anyway: a generated call names a
    // module and a name rather than resolving a binding, so visibility never
    // enters into finding one. What visibility decides is whether a program can
    // write the name, and the answer for every one of these is no.
    //
    // Read out of the library's own source, because the alternative is a
    // comment asserting it. A `pub` here would be a declaration in every
    // importer's reach that exists to be called by the compiler.
    for (table) |c| {
        const declared = declarationOf(c.module, c.name) orelse {
            std.debug.print("the library declares no `{s}.{s}`\n", .{ c.module, c.name });
            return error.TestUnexpectedResult;
        };

        if (std.mem.startsWith(u8, declared, "pub ")) {
            std.debug.print(
                "`{s}.{s}` is `pub`, so a program that imports `{s}` can call it\n",
                .{ c.module, c.name, c.module },
            );
            return error.TestUnexpectedResult;
        }
    }
}

/// The line declaring `name` in `module`, or null where nothing does.
///
/// A module is a directory and a directory holds several files, so every file
/// of it is searched: which file a declaration sits in is not something the
/// table says or should.
fn declarationOf(module: []const u8, name: []const u8) ?[]const u8 {
    for (@import("library_manifest").files) |f| {
        const slash = std.mem.lastIndexOfScalar(u8, f.path, '/') orelse continue;
        const dir = f.path[0..slash];
        const at = std.mem.lastIndexOfScalar(u8, dir, '/') orelse continue;
        if (!std.mem.eql(u8, dir[at + 1 ..], module)) continue;

        var lines = std.mem.splitScalar(u8, f.text, '\n');
        while (lines.next()) |line| {
            const fn_at = std.mem.indexOf(u8, line, "fn ") orelse continue;
            const rest = line[fn_at + 3 ..];
            if (!std.mem.startsWith(u8, rest, name)) continue;

            const after = rest[name.len..];
            if (after.len == 0) continue;
            switch (after[0]) {
                '(', '[' => return line,
                else => continue,
            }
        }
    }
    return null;
}
