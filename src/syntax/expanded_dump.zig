const std = @import("std");

const ExpandedProgram = @import("expanded_program.zig").ExpandedProgram;
const Module = @import("program.zig").Module;

/// Prints immutable generated virtual files in their stored expansion order.
/// Both this dump and later materialization consume the same rows; neither
/// reconstructs source from derive declarations.
pub fn dumpExpanded(
    expanded: *const ExpandedProgram,
    modules: []const Module,
    writer: *std.Io.Writer,
) std.Io.Writer.Error!void {
    for (0..expanded.generatedSourceCount()) |index| {
        if (index != 0) try writer.writeByte('\n');
        const source = expanded.generatedSource(@intCast(index));
        const module = modules[source.module.index()].name;
        try writer.writeAll("// === ");
        if (module.len != 0) {
            try writer.writeAll(module);
            try writer.writeByte('/');
        }
        try writer.writeAll(source.path);
        try writer.writeAll(" ===\n");
        try writer.print("// origin: derive {d}", .{source.origin.derive.index()});
        if (source.origin.derive_trait != .none) {
            try writer.print(", trait token {d}", .{source.origin.derive_trait.index()});
        }
        try writer.writeByte('\n');
        try writer.writeAll(source.text);
        if (source.text.len == 0 or source.text[source.text.len - 1] != '\n') try writer.writeByte('\n');
    }
}
