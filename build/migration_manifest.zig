//! Derives artifact identity only. This tool never writes safety approvals.
const std = @import("std");
const contract = @import("migration_contract");
const sources = @import("runtime_sources");

pub fn main(init: std.process.Init) !void {
    const gpa = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(gpa);
    if (args.len != 8) return error.InvalidArguments;
    const archive = try std.Io.Dir.cwd().readFileAlloc(io, args[1], gpa, .unlimited);
    const config = try std.Io.Dir.cwd().readFileAlloc(io, args[3], gpa, .limited(1 << 20));
    const generated = try std.Io.Dir.cwd().readFileAlloc(io, args[4], gpa, .unlimited);
    var inputs: std.ArrayList(contract.Input) = .empty;
    try inputs.append(gpa, .{ .name = "migration_manifest.zig", .bytes = @embedFile("migration_manifest.zig") });
    try inputs.append(gpa, .{ .name = "migration_contract.zig", .bytes = @embedFile("migration_contract_source") });
    try inputs.append(gpa, .{ .name = "build.zig", .bytes = @embedFile("build_source") });
    for (sources.files) |file| try inputs.append(gpa, .{ .name = file.path, .bytes = file.text });
    try inputs.append(gpa, .{ .name = "linea_float.c", .bytes = generated });
    const registry = contract.sha256(@embedFile("runtime_registry"));
    const implementation = contract.implementationDigest(config, inputs.items);
    const archive_hash = contract.sha256(archive);
    const identity: contract.Identity = .{
        .archive_sha256 = &archive_hash,
        .registry_sha256 = &registry,
        .implementation_sha256 = &implementation,
        .target = args[5],
        .variant = std.meta.stringToEnum(contract.Variant, args[6]) orelse return error.InvalidVariant,
        .sanitizer = std.meta.stringToEnum(contract.Sanitizer, args[7]) orelse return error.InvalidSanitizer,
    };
    const bytes = try std.json.Stringify.valueAlloc(gpa, identity, .{ .whitespace = .indent_2 });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = args[2], .data = bytes });
}
