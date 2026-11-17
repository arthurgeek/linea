const std = @import("std");
const testing = std.testing;

const Observation = struct {
    tasks: u64,
    checksum: u64,
    wall_ns: u64,
    admission_ns: u64,
    yield_ns: u64,
    maximum_ns: u64,
    moves: u64,
    first_count: u64,
};
const workloads = [_][]const u8{ "balanced", "imbalanced", "affinity", "locality" };
const controls = [_][]const u8{ "pinned", "placement", "forced", "stealing" };

fn parse(text: []const u8, workload: []const u8) !Observation {
    var words = std.mem.tokenizeAny(u8, text, " \t\r\n");
    if (!std.mem.eql(u8, words.next() orelse return error.BadObservation, "scheduling-v1")) return error.BadObservation;
    if (!std.mem.eql(u8, words.next() orelse return error.BadObservation, workload)) return error.WrongWorkload;
    var result: Observation = undefined;
    var seen: u16 = 0;
    while (words.next()) |word| {
        const at = std.mem.indexOfScalar(u8, word, '=') orelse return error.BadObservation;
        var found = false;
        inline for (std.meta.fields(Observation), 0..) |field, i| {
            if (std.mem.eql(u8, word[0..at], field.name)) {
                const bit = @as(u16, 1) << i;
                if (seen & bit != 0) return error.DuplicateField;
                @field(result, field.name) = std.fmt.parseInt(u64, word[at + 1 ..], 10) catch return error.BadObservation;
                seen |= bit;
                found = true;
            }
        }
        if (!found) return error.UnknownField;
    }
    if (seen != (@as(u16, 1) << std.meta.fields(Observation).len) - 1) return error.MissingField;
    if (result.tasks != 32 or result.checksum == 0 or result.wall_ns == 0 or
        result.first_count == 0 or result.first_count > result.tasks or
        result.moves > result.tasks * 8 or result.maximum_ns > result.yield_ns) return error.BadPopulation;
    return result;
}

fn validate(result: std.process.RunResult, workload: []const u8, control: []const u8, checksum: ?u64) !Observation {
    switch (result.term) {
        .exited => |code| if (code != 0) return error.ChildFailed,
        else => return error.ChildFailed,
    }
    if (result.stderr.len != 0) return error.UnexpectedOutput;
    const observation = try parse(result.stdout, workload);
    if (checksum) |expected| if (observation.checksum != expected) return error.ChecksumMismatch;
    const distributed = std.mem.eql(u8, workload, "balanced") or std.mem.eql(u8, control, "placement");
    if (observation.first_count != (if (distributed) @as(u64, 16) else 32)) return error.WrongPlacement;
    const bound = std.mem.eql(u8, workload, "affinity");
    const pinned = bound or std.mem.eql(u8, control, "pinned") or std.mem.eql(u8, control, "placement");
    if (pinned and observation.moves != 0) return error.UnexpectedTransfer;
    if (!pinned and !std.mem.eql(u8, workload, "balanced") and observation.moves == 0) return error.MissingTransfer;
    return observation;
}

const example = "scheduling-v1 imbalanced tasks=32 checksum=91 wall_ns=100 admission_ns=50 yield_ns=40 maximum_ns=20 moves=0 first_count=32\n";

test "scheduling observations require complete unique population fields" {
    try testing.expectEqual(@as(u64, 91), (try parse(example, "imbalanced")).checksum);
    try testing.expectError(error.WrongWorkload, parse(example, "balanced"));
    try testing.expectError(error.MissingField, parse("scheduling-v1 imbalanced tasks=32", "imbalanced"));
    try testing.expectError(error.DuplicateField, parse(example ++ " tasks=32", "imbalanced"));
    try testing.expectError(error.UnknownField, parse(example ++ " surprise=1", "imbalanced"));
    const impossible = try std.mem.replaceOwned(u8, testing.allocator, example, "maximum_ns=20", "maximum_ns=41");
    defer testing.allocator.free(impossible);
    try testing.expectError(error.BadPopulation, parse(impossible, "imbalanced"));
}

test "failed or malformed scheduling children never produce timing evidence" {
    const success = std.process.RunResult{ .term = .{ .exited = 0 }, .stdout = @constCast(example), .stderr = &.{} };
    _ = try validate(success, "imbalanced", "pinned", 91);
    try testing.expectError(error.ChecksumMismatch, validate(success, "imbalanced", "pinned", 92));
    try testing.expectError(error.MissingTransfer, validate(success, "imbalanced", "stealing", 91));
    try testing.expectError(error.WrongPlacement, validate(success, "imbalanced", "placement", 91));
    var failed = success;
    failed.term = .{ .exited = 1 };
    try testing.expectError(error.ChildFailed, validate(failed, "imbalanced", "pinned", null));
    failed = success;
    failed.stderr = @constCast("unexpected");
    try testing.expectError(error.UnexpectedOutput, validate(failed, "imbalanced", "pinned", null));
}

fn run(gpa: std.mem.Allocator, io: std.Io, binary: []const u8, workload: []const u8, control: []const u8, checksum: ?u64) !Observation {
    const result = try std.process.run(gpa, io, .{
        .argv = &.{ binary, workload, control },
        .stdout_limit = .limited(4096),
        .stderr_limit = .limited(4096),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(60), .clock = .awake } },
    });
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);
    return validate(result, workload, control, checksum);
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.arena.allocator();
    const args = try init.minimal.args.toSlice(gpa);
    if (args.len != 6) return error.ExpectedModeAndFourBinaries;
    const measure = std.mem.eql(u8, args[1], "--measure");
    if (!measure and !std.mem.eql(u8, args[1], "--check")) return error.BadMode;
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    if (measure) try output.interface.writeAll("workload\ttrial\tcontrol\ttasks\tchecksum\twall_ns\tadmission_ns\tyield_ns\tmaximum_ns\tmoves\tfirst_count\n");
    for (workloads) |workload| {
        var checksum: ?u64 = null;
        for (controls, 0..) |control, i| {
            const observation = try run(gpa, init.io, args[i + 2], workload, control, checksum);
            checksum = observation.checksum;
        }
        if (!measure) continue;
        // Rotate forward and reverse orders so each policy occupies every
        // position. Warmups above are checked but never enter the samples.
        for (0..8) |trial| {
            for (0..4) |position| {
                const i = if (trial % 2 == 0) (position + trial / 2) % 4 else (3 - position + trial / 2) % 4;
                const observation = try run(gpa, init.io, args[i + 2], workload, controls[i], checksum);
                try output.interface.print("{s}\t{d}\t{s}", .{ workload, trial, controls[i] });
                inline for (std.meta.fields(Observation)) |field| try output.interface.print("\t{d}", .{@field(observation, field.name)});
                try output.interface.writeByte('\n');
                try output.interface.flush();
            }
        }
    }
    try output.interface.flush();
}
