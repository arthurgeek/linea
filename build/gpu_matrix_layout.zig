//! Generate the optional column-major layout comparison from production MLIR.
const std = @import("std");

pub fn columnMajor(gpa: std.mem.Allocator, row: []const u8) ![]u8 {
    const header = "      %row = spirv.UDiv %i, %columns : i32\n" ++
        "      %column = spirv.UMod %i, %columns : i32\n" ++
        "      %base = spirv.IMul %row, %inner : i32";
    const column_header = "      %rows = spirv.UDiv %n, %columns : i32\n" ++
        "      %row = spirv.UMod %i, %rows : i32\n" ++
        "      %column = spirv.UDiv %i, %rows : i32\n" ++
        "      %base = spirv.IMul %column, %inner : i32";
    const body = "        %ai = spirv.IAdd %base, %k : i32\n" ++
        "        %bbase = spirv.IMul %k, %columns : i32\n" ++
        "        %bi = spirv.IAdd %bbase, %column : i32";
    const column_body = "        %abase = spirv.IMul %k, %rows : i32\n" ++
        "        %ai = spirv.IAdd %abase, %row : i32\n" ++
        "        %bi = spirv.IAdd %base, %k : i32";
    if (std.mem.count(u8, row, header) != 1 or std.mem.count(u8, row, body) != 1)
        return error.UnrecognizedMatrixIndexing;
    const with_header = try std.mem.replaceOwned(u8, gpa, row, header, column_header);
    defer gpa.free(with_header);
    return std.mem.replaceOwned(u8, gpa, with_header, body, column_body);
}

pub fn main(init: std.process.Init) !u8 {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 3) {
        std.debug.print("usage: gpu-matrix-layout <row MLIR> <column MLIR>\n", .{});
        return 2;
    }
    const row = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], init.arena.allocator(), .limited(64 << 20));
    const column = columnMajor(init.arena.allocator(), row) catch |err| {
        std.debug.print("matrix layout benchmark must match production indexing: {s}\n", .{@errorName(err)});
        return 1;
    };
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[2], .data = column });
    return 0;
}

test "matrix layout transformation refuses changed or repeated indexing" {
    try std.testing.expectError(error.UnrecognizedMatrixIndexing, columnMajor(std.testing.allocator, "unrelated MLIR"));
    const row =
        "      %row = spirv.UDiv %i, %columns : i32\n" ++
        "      %column = spirv.UMod %i, %columns : i32\n" ++
        "      %base = spirv.IMul %row, %inner : i32\n" ++
        "        %ai = spirv.IAdd %base, %k : i32\n" ++
        "        %bbase = spirv.IMul %k, %columns : i32\n" ++
        "        %bi = spirv.IAdd %bbase, %column : i32\n" ++
        "        %product = spirv.FunctionCall @linea_f32_mul(%left, %right) : (i32, i32) -> i32\n";
    const column = try columnMajor(std.testing.allocator, row);
    defer std.testing.allocator.free(column);
    try std.testing.expect(std.mem.indexOf(u8, column, "%rows = spirv.UDiv %n, %columns") != null);
    try std.testing.expect(std.mem.indexOf(u8, column, "%ai = spirv.IAdd %abase, %row") != null);
    try std.testing.expect(std.mem.indexOf(u8, column, "%bi = spirv.IAdd %base, %k") != null);
    try std.testing.expect(std.mem.endsWith(u8, column, "        %product = spirv.FunctionCall @linea_f32_mul(%left, %right) : (i32, i32) -> i32\n"));
    try std.testing.expectError(error.UnrecognizedMatrixIndexing, columnMajor(std.testing.allocator, row ++ row));
}
