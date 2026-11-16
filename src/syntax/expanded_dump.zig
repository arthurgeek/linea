const std = @import("std");

const ExpandedProgram = @import("expanded_program.zig").ExpandedProgram;
const Module = @import("program.zig").Module;

/// Prints generated virtual files in their stored expansion order, each as
/// `texts` holds it: the text checking settled, which later materialization
/// reloads too. Neither reconstructs source from derive declarations.
pub fn dumpExpanded(
    expanded: *const ExpandedProgram,
    modules: []const Module,
    texts: []const []const u8,
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
        const text = texts[index];
        try writer.writeAll(text);
        if (text.len == 0 or text[text.len - 1] != '\n') try writer.writeByte('\n');
    }
}
