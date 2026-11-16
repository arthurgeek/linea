const std = @import("std");
const testing = std.testing;

const Interval = struct { lower: u64, upper: u64, censored: bool };
const Counts = struct {
    started: u64,
    retired: u64,
    initially_eligible: u64,
    current_eligible: u64,
    peak_eligible: u64,
    initially_then_restricted: u64,
    never_eligible: u64,
    guard_requests: u64,
    first_restrictions: u64,
    transfers: u64,
    ever_transferred: u64,
    eligibility_checks: u64,
    claim_attempts: u64,
    commit_attempts: u64,
    active_claims: u64,
    ref_entry: u64,
    ref_affinity: u64,
    ref_state: u64,
    ref_source: u64,
    ref_reservation: u64,
    ref_target: u64,
    ref_empty: u64,
    ref_quota: u64,
    normalization_attempts: u64,
    normalization_busy: u64,
};
const Report = struct { counts: Counts, resolution_ns: u64, sample_count: usize = 2, runnable_to_ready: [2]Interval, ready_to_claim: [2]Interval, claim_to_resume: [2]Interval };

const Event = struct { carrier: u64, lower: u64, upper: u64 };

fn elapsed(start: Event, end: Event, resolution: u64) !Interval {
    if (end.upper < start.lower) return error.ClockOrder;
    // Widen by one reported clock quantum at each endpoint. Overlap and
    // equal-tick observations are censored, never exact zero-latency claims.
    const uncertainty = std.math.mul(u64, resolution, 2) catch return error.BadTrace;
    const lower = (end.lower -| start.upper) -| uncertainty;
    return .{
        .lower = lower,
        .upper = std.math.add(u64, end.upper - start.lower, uncertainty) catch return error.BadTrace,
        .censored = lower == 0,
    };
}

fn number(text: ?[]const u8) !u64 {
    return std.fmt.parseInt(u64, text orelse return error.BadTrace, 10) catch return error.BadTrace;
}

fn readCounts(line: []const u8) !Counts {
    var fields = std.mem.tokenizeAny(u8, line, " \t\r");
    if (!std.mem.eql(u8, fields.next() orelse return error.BadTrace, "counts")) return error.BadTrace;
    var counts: Counts = undefined;
    var seen: u64 = 0;
    while (fields.next()) |field| {
        const equal = std.mem.indexOfScalar(u8, field, '=') orelse return error.BadTrace;
        var found = false;
        inline for (std.meta.fields(Counts), 0..) |member, i| {
            if (std.mem.eql(u8, field[0..equal], member.name)) {
                const bit = @as(u64, 1) << i;
                if (seen & bit != 0) return error.DuplicateCounter;
                @field(counts, member.name) = try number(field[equal + 1 ..]);
                seen |= bit;
                found = true;
            }
        }
        if (!found) return error.UnknownCounter;
    }
    if (seen != (@as(u64, 1) << std.meta.fields(Counts).len) - 1) return error.MissingCounter;
    return counts;
}

fn inspectTrace(text: []const u8) !Report {
    return inspectPopulation(text, .round_trip);
}

fn inspectPopulation(text: []const u8, expectation: Expectation) !Report {
    var lines = std.mem.splitScalar(u8, text, '\n');
    const header = lines.next() orelse return error.BadTrace;
    const prefix = "migration-trace-v1 units=ns dropped=";
    if (!std.mem.startsWith(u8, header, prefix)) return error.BadTrace;
    const tail = header[prefix.len..];
    const split = std.mem.indexOfScalar(u8, tail, ' ') orelse return error.BadTrace;
    if (try number(tail[0..split]) != 0) return error.DroppedEvents;
    const resolution_prefix = " resolution_ns=";
    if (!std.mem.startsWith(u8, tail[split..], resolution_prefix)) return error.BadTrace;
    const resolution = try number(tail[split + resolution_prefix.len ..]);
    if (resolution == 0) return error.BadTrace;
    var events: [2][4]?Event = .{ @splat(null), @splat(null) };
    var fiber: ?u64 = null;
    var counters: ?Counts = null;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "counts ")) {
            if (counters != null) return error.DuplicateCounter;
            counters = try readCounts(line);
            continue;
        }
        var fields = std.mem.tokenizeAny(u8, line, " \t\r");
        const stage = fields.next() orelse return error.BadTrace;
        const phase: usize = if (std.mem.eql(u8, stage, "R")) 0 else if (std.mem.eql(u8, stage, "N")) 1 else if (std.mem.eql(u8, stage, "C")) 2 else if (std.mem.eql(u8, stage, "X")) 3 else return error.BadTrace;
        const identity = try number(fields.next());
        if (identity == 0) return error.MixedFiber;
        if (fiber) |first| {
            if (identity != first) return error.MixedFiber;
        } else fiber = identity;
        const epoch = try number(fields.next());
        if (epoch < 1 or epoch > 2) return error.BadEpoch;
        const carrier = try number(fields.next());
        const lower = try number(fields.next());
        const upper = try number(fields.next());
        if (fields.next() != null or carrier > 1) return error.BadTrace;
        if (lower > upper) return error.ClockOrder;
        const slot = &events[@intCast(epoch - 1)][phase];
        if (slot.* != null) return error.DuplicateStage;
        slot.* = .{ .carrier = carrier, .lower = lower, .upper = upper };
    }
    var report: Report = undefined;
    const counts = counters orelse return error.MissingCounter;
    if (expectation == .pinned or expectation == .unproven) {
        const unknown = expectation == .pinned;
        if (counts.started != 1 or counts.retired != 1 or counts.current_eligible != 0 or
            counts.initially_eligible != @intFromBool(unknown) or counts.peak_eligible != @intFromBool(unknown) or
            counts.never_eligible != @intFromBool(!unknown) or counts.transfers != 0 or counts.ever_transferred != 0 or
            counts.active_claims != 0 or counts.claim_attempts < 2 or counts.commit_attempts != 0 or
            counts.first_restrictions != @intFromBool(unknown) or
            counts.initially_then_restricted != @intFromBool(unknown) or
            (if (unknown) counts.ref_affinity < 2 or counts.guard_requests == 0 else counts.ref_entry < 2 or counts.guard_requests != 0))
            return error.CounterMismatch;
        for (events) |epoch| {
            if (epoch[0] == null) return error.MissingStage;
            for (epoch[1..]) |stage| if (stage != null) return error.UnexpectedTransfer;
        }
        if (events[0][0].?.carrier != events[1][0].?.carrier) return error.UnexpectedTransfer;
        _ = try elapsed(events[0][0].?, events[1][0].?, resolution);
        const empty: [2]Interval = @splat(.{ .lower = 0, .upper = 0, .censored = true });
        return .{ .counts = counts, .resolution_ns = resolution, .sample_count = 0, .runnable_to_ready = empty, .ready_to_claim = empty, .claim_to_resume = empty };
    }
    report.sample_count = 2;
    if (counts.started != 1 or counts.retired != 1 or counts.initially_eligible != 1 or
        counts.current_eligible != 0 or counts.peak_eligible != 1 or counts.never_eligible != 0 or
        counts.transfers != 2 or counts.ever_transferred != 1 or counts.active_claims != 0 or
        counts.first_restrictions > counts.guard_requests or counts.first_restrictions > 1 or
        counts.initially_then_restricted != counts.first_restrictions or
        counts.eligibility_checks < 4 or counts.claim_attempts < 2 or counts.commit_attempts < 2 or
        counts.normalization_busy > counts.normalization_attempts) return error.CounterMismatch;
    report.counts = counts;
    report.resolution_ns = resolution;
    for (events, 0..) |epoch, i| {
        for (epoch) |stage| if (stage == null) return error.MissingStage;
        const r = epoch[0].?;
        const n = epoch[1].?;
        const c = epoch[2].?;
        const x = epoch[3].?;
        if (r.carrier != n.carrier or n.carrier != c.carrier) return error.SourceCarrierChanged;
        if (c.carrier == x.carrier) return error.NoCarrierTransfer;
        report.runnable_to_ready[i] = try elapsed(r, n, resolution);
        report.ready_to_claim[i] = try elapsed(n, c, resolution);
        report.claim_to_resume[i] = try elapsed(c, x, resolution);
    }
    if (events[1][0].?.carrier != events[0][3].?.carrier or events[1][3].?.carrier != events[0][0].?.carrier)
        return error.BadRoundTrip;
    _ = try elapsed(events[0][3].?, events[1][0].?, resolution);
    return report;
}

const counts_line = "counts started=1 retired=1 initially_eligible=1 current_eligible=0 peak_eligible=1 initially_then_restricted=0 never_eligible=0 guard_requests=0 first_restrictions=0 transfers=2 ever_transferred=1 eligibility_checks=4 claim_attempts=2 commit_attempts=2 active_claims=0 ref_entry=0 ref_affinity=0 ref_state=0 ref_source=0 ref_reservation=0 ref_target=0 ref_empty=0 ref_quota=0 normalization_attempts=0 normalization_busy=0\n";

const complete_trace =
    \\migration-trace-v1 units=ns dropped=0 resolution_ns=1
    \\R 1 1 0 100 110
    \\N 1 1 0 120 130
    \\C 1 1 0 140 150
    \\X 1 1 1 180 190
    \\R 1 2 1 200 210
    \\N 1 2 1 220 230
    \\C 1 2 1 240 250
    \\X 1 2 0 280 290
    \\
++ counts_line;

test "migration intervals retain lower upper and population denominators" {
    const report = try inspectTrace(complete_trace);
    try testing.expectEqual(@as(u64, 8), report.runnable_to_ready[0].lower);
    try testing.expectEqual(@as(u64, 32), report.runnable_to_ready[0].upper);
    try testing.expectEqual(@as(u64, 28), report.claim_to_resume[1].lower);
    try testing.expectEqual(@as(u64, 52), report.claim_to_resume[1].upper);
    try testing.expect(!report.ready_to_claim[1].censored);
}

test "overlapping clock brackets are censored instead of reported as negative time" {
    const trace = try std.mem.replaceOwned(u8, testing.allocator, complete_trace, "120 130", "105 130");
    defer testing.allocator.free(trace);
    const report = try inspectTrace(trace);
    try testing.expectEqual(@as(u64, 0), report.runnable_to_ready[0].lower);
    try testing.expectEqual(@as(u64, 32), report.runnable_to_ready[0].upper);
    try testing.expect(report.runnable_to_ready[0].censored);
}

test "a different fiber cannot provide the destination resume observation" {
    const trace = try std.mem.replaceOwned(u8, testing.allocator, complete_trace, "X 1 1", "X 2 1");
    defer testing.allocator.free(trace);
    try testing.expectError(error.MixedFiber, inspectTrace(trace));
}

test "same-carrier observations cannot masquerade as a transfer" {
    const trace = try std.mem.replaceOwned(u8, testing.allocator, complete_trace, "X 1 1 1", "X 1 1 0");
    defer testing.allocator.free(trace);
    try testing.expectError(error.NoCarrierTransfer, inspectTrace(trace));
}

test "missing or dropped events cannot become complete timing evidence" {
    const dropped = try std.mem.replaceOwned(u8, testing.allocator, complete_trace, "dropped=0", "dropped=1");
    defer testing.allocator.free(dropped);
    try testing.expectError(error.DroppedEvents, inspectTrace(dropped));
    const missing = try std.mem.replaceOwned(u8, testing.allocator, complete_trace, "N 1 1 0 120 130\n", "");
    defer testing.allocator.free(missing);
    try testing.expectError(error.MissingStage, inspectTrace(missing));
}

test "equal clock ticks are resolution censored rather than exact zero" {
    const trace = try std.mem.replaceOwned(u8, testing.allocator, complete_trace, "120 130", "110 110");
    defer testing.allocator.free(trace);
    const report = try inspectTrace(trace);
    try testing.expectEqual(@as(u64, 0), report.runnable_to_ready[0].lower);
    try testing.expectEqual(@as(u64, 12), report.runnable_to_ready[0].upper);
    try testing.expect(report.runnable_to_ready[0].censored);
}

test "zero-transfer counters cannot masquerade as a migrating population" {
    const trace = try std.mem.replaceOwned(u8, testing.allocator, complete_trace, "transfers=2", "transfers=0");
    defer testing.allocator.free(trace);
    try testing.expectError(error.CounterMismatch, inspectTrace(trace));
}

test "counter populations require every declared denominator" {
    const trace = try std.mem.replaceOwned(u8, testing.allocator, complete_trace, " claim_attempts=2", "");
    defer testing.allocator.free(trace);
    try testing.expectError(error.MissingCounter, inspectTrace(trace));
}

test "a first restriction must leave the initially eligible population" {
    const guarded = try std.mem.replaceOwned(u8, testing.allocator, complete_trace, "guard_requests=0 first_restrictions=0", "guard_requests=1 first_restrictions=1");
    defer testing.allocator.free(guarded);
    try testing.expectError(error.CounterMismatch, inspectTrace(guarded));
}

test "refusal controls require actual rejected scheduling claims" {
    try testing.expectError(error.MissingRefusalEvidence, inspectTraceFor(complete_trace, .refusal_probes));
}

test "source contention requires real normalization retries" {
    try testing.expectError(error.MissingContentionEvidence, inspectTraceFor(complete_trace, .source_busy));
}

const pinned_trace =
    \\migration-trace-v1 units=ns dropped=0 resolution_ns=1000
    \\R 1 1 0 100 110
    \\R 1 2 0 200 210
    \\counts started=1 retired=1 initially_eligible=1 current_eligible=0 peak_eligible=1 initially_then_restricted=1 never_eligible=0 guard_requests=1 first_restrictions=1 transfers=0 ever_transferred=0 eligibility_checks=2 claim_attempts=2 commit_attempts=0 active_claims=0 ref_entry=0 ref_affinity=2 ref_state=0 ref_source=0 ref_reservation=0 ref_target=0 ref_empty=0 ref_quota=0 normalization_attempts=0 normalization_busy=0
;

test "pinned controls have populations but no migration timing samples" {
    const report = try inspectTraceFor(pinned_trace, .pinned);
    try testing.expectEqual(@as(usize, 0), report.sample_count);
    try testing.expectError(error.CounterMismatch, inspectTrace(pinned_trace));
    try testing.expectError(error.CounterMismatch, inspectTraceFor(pinned_trace, .unproven));
}

test "pinned controls reject an observed destination carrier change" {
    const trace = try std.mem.replaceOwned(u8, testing.allocator, pinned_trace, "R 1 2 0", "R 1 2 1");
    defer testing.allocator.free(trace);
    try testing.expectError(error.UnexpectedTransfer, inspectTraceFor(trace, .pinned));
}

const Expectation = enum { round_trip, refusal_probes, source_busy, pinned, unproven };

fn inspectTraceFor(text: []const u8, expectation: Expectation) !Report {
    const report = try inspectPopulation(text, expectation);
    switch (expectation) {
        .round_trip, .pinned, .unproven => {},
        .refusal_probes => if (report.counts.ref_state == 0 or report.counts.ref_source == 0 or
            report.counts.ref_reservation == 0 or report.counts.ref_target == 0) return error.MissingRefusalEvidence,
        .source_busy => if (report.counts.normalization_busy < 2) return error.MissingContentionEvidence,
    }
    return report;
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.arena.allocator();
    const args = try init.minimal.args.toSlice(gpa);
    if (args.len < 2 or args.len > 3) return error.ExpectedTracePath;
    const text = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], gpa, .limited(64 << 10));
    const expectation = if (args.len == 3) std.meta.stringToEnum(Expectation, args[2]) orelse return error.BadExpectation else .round_trip;
    const report = try inspectTraceFor(text, expectation);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try output.interface.print("clock_resolution_ns\t{d}\n", .{report.resolution_ns});
    try output.interface.writeAll("population_snapshot\tafter_retirement\n");
    inline for (std.meta.fields(Counts)) |member| {
        try output.interface.print("{s}\t{d}\n", .{ member.name, @field(report.counts, member.name) });
    }
    try output.interface.writeAll("interval\tsample\tlower_ns\tupper_ns\tcensored\n");
    inline for (.{ "runnable_to_ready", "ready_to_claim", "claim_to_resume" }) |name| {
        for (@field(report, name)[0..report.sample_count], 0..) |interval, sample| {
            try output.interface.print("{s}\t{d}\t{d}\t{d}\t{}\n", .{ name, sample, interval.lower, interval.upper, interval.censored });
        }
    }
    try output.interface.flush();
}
