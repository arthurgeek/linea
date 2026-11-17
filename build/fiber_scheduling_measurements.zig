const std = @import("std");
const testing = std.testing;
const metrics = @import("fiber_migration_metrics.zig");

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
    const stealing = std.mem.eql(u8, control, "stealing");
    // A thief can move a fresh context before its first observation. Only
    // non-stealing controls have a fixed observed initial distribution.
    if (!stealing and observation.first_count != (if (distributed) @as(u64, 16) else 32)) return error.WrongPlacement;
    const bound = std.mem.eql(u8, workload, "affinity");
    const pinned = bound or std.mem.eql(u8, control, "pinned") or std.mem.eql(u8, control, "placement");
    if (pinned and observation.moves != 0) return error.UnexpectedTransfer;
    if (std.mem.eql(u8, control, "forced") and !bound and observation.moves == 0) return error.MissingTransfer;
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
    try testing.expectError(error.MissingTransfer, validate(success, "imbalanced", "forced", 91));
    _ = try validate(success, "imbalanced", "stealing", 91);
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

fn populations(result: std.process.RunResult, workload: []const u8, control: []const u8, checksum: ?u64) !struct { observation: Observation, counts: metrics.Counts } {
    var plain = result;
    plain.stderr = &.{};
    const observation = try validate(plain, workload, control, checksum);
    var lines = std.mem.tokenizeScalar(u8, result.stderr, '\n');
    var last: ?metrics.Counts = null;
    while (lines.next()) |line| {
        const counts = try metrics.readCounts(line);
        if (last) |previous| {
            if (counts.started < previous.started or counts.retired < previous.retired)
                return error.RegressedPopulation;
        }
        if (counts.retired > counts.started) return error.BadPopulation;
        last = counts;
    }
    const counts = last orelse return error.MissingPopulation;
    if (counts.started != observation.tasks or counts.retired != observation.tasks or
        counts.current_eligible != 0 or counts.active_claims != 0 or
        counts.initially_eligible > counts.started or
        counts.never_eligible != counts.started - counts.initially_eligible or
        counts.peak_eligible > counts.initially_eligible or
        counts.initially_then_restricted > counts.initially_eligible or
        counts.first_restrictions > counts.started or counts.guard_requests < counts.first_restrictions or
        counts.ever_transferred > counts.initially_eligible or
        counts.transfers < counts.ever_transferred) return error.BadPopulation;
    const pinned = std.mem.eql(u8, control, "pinned") or std.mem.eql(u8, control, "placement");
    if (pinned) {
        if (counts.initially_eligible != 0 or counts.transfers != 0) return error.BadPopulation;
    } else if (counts.initially_eligible != observation.tasks) return error.BadPopulation;
    if (std.mem.eql(u8, workload, "affinity") and counts.first_restrictions != observation.tasks)
        return error.BadPopulation;
    if (std.mem.eql(u8, control, "forced") and !std.mem.eql(u8, workload, "affinity") and counts.transfers == 0)
        return error.MissingTransfer;
    return .{ .observation = observation, .counts = counts };
}

test "diagnostic populations cannot be inferred from timing observations" {
    const plain = std.process.RunResult{ .term = .{ .exited = 0 }, .stdout = @constCast(example), .stderr = &.{} };
    try testing.expectError(error.MissingPopulation, populations(plain, "imbalanced", "pinned", 91));
    var malformed = plain;
    malformed.stderr = @constCast("counts started=32\n");
    try testing.expectError(error.MissingCounter, populations(malformed, "imbalanced", "pinned", 91));
}

test "diagnostic populations require a complete retired workload and monotonic snapshots" {
    var counts = std.mem.zeroes(metrics.Counts);
    counts.started = 32;
    counts.retired = 32;
    counts.never_eligible = 32;
    var text: std.Io.Writer.Allocating = .init(testing.allocator);
    defer text.deinit();
    try text.writer.writeAll("counts");
    inline for (std.meta.fields(metrics.Counts)) |field|
        try text.writer.print(" {s}={d}", .{ field.name, @field(counts, field.name) });
    try text.writer.writeByte('\n');
    const result = std.process.RunResult{ .term = .{ .exited = 0 }, .stdout = @constCast(example), .stderr = text.written() };
    try testing.expectEqual(@as(u64, 32), (try populations(result, "imbalanced", "pinned", 91)).counts.retired);
    const incomplete = try std.mem.replaceOwned(u8, testing.allocator, text.written(), "retired=32", "retired=31");
    defer testing.allocator.free(incomplete);
    var bad = result;
    bad.stderr = incomplete;
    try testing.expectError(error.BadPopulation, populations(bad, "imbalanced", "pinned", 91));
    const earlier = try std.mem.replaceOwned(u8, testing.allocator, text.written(), "started=32", "started=31");
    defer testing.allocator.free(earlier);
    const regressed = try std.mem.concat(testing.allocator, u8, &.{ text.written(), earlier });
    defer testing.allocator.free(regressed);
    bad.stderr = regressed;
    try testing.expectError(error.RegressedPopulation, populations(bad, "imbalanced", "pinned", 91));
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.arena.allocator();
    const args = try init.minimal.args.toSlice(gpa);
    if (args.len != 6) return error.ExpectedModeAndFourBinaries;
    const measure = std.mem.eql(u8, args[1], "--measure");
    const diagnose = std.mem.eql(u8, args[1], "--populations");
    if (!measure and !diagnose and !std.mem.eql(u8, args[1], "--check")) return error.BadMode;
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    if (measure) try output.interface.writeAll("workload\ttrial\tcontrol\ttasks\tchecksum\twall_ns\tadmission_ns\tyield_ns\tmaximum_ns\tmoves\tfirst_count\n");
    if (diagnose) {
        try output.interface.writeAll("workload\tcontrol");
        inline for (std.meta.fields(metrics.Counts)) |field| try output.interface.print("\t{s}", .{field.name});
        try output.interface.writeByte('\n');
    }
    for (workloads) |workload| {
        var checksum: ?u64 = null;
        for (controls, 0..) |control, i| {
            if (diagnose) {
                const result = try std.process.run(gpa, init.io, .{
                    .argv = &.{ args[i + 2], workload, control },
                    .stdout_limit = .limited(4096),
                    .stderr_limit = .limited(256 << 10),
                    .timeout = .{ .duration = .{ .raw = .fromSeconds(60), .clock = .awake } },
                });
                defer gpa.free(result.stdout);
                defer gpa.free(result.stderr);
                const diagnostic = try populations(result, workload, control, checksum);
                checksum = diagnostic.observation.checksum;
                try output.interface.print("{s}\t{s}", .{ workload, control });
                inline for (std.meta.fields(metrics.Counts)) |field| try output.interface.print("\t{d}", .{@field(diagnostic.counts, field.name)});
                try output.interface.writeByte('\n');
                continue;
            }
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
