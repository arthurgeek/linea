const std = @import("std");
const testing = std.testing;

const Test = @import("../sema/resolve.zig").Resolution.Test;
const toolchain = @import("toolchain.zig");

/// What one test's child process said.
const Outcome = struct {
    /// The name the test is known by, which is what selected it and what the
    /// transcript prints. Borrowed from the resolution that spelled it.
    qualified_name: []const u8,
    passed: bool,
    /// What the child wrote to standard error, which is where a failure
    /// explains itself. Empty for a test that passed.
    detail: []const u8,
};

/// How much of what a test wrote is kept.
///
/// A bound rather than everything, because a test that loops printing would
/// otherwise take the runner's memory instead of being reported as a test that
/// misbehaved -- and what is read from the tail of a runaway is not the part
/// that says what went wrong.
const output_kept: usize = 64 << 10;

/// The process group every test binary of one run joins, which dies with the
/// runner however the runner ends.
///
/// A holder process leads the group for the whole run, so a test binary always
/// has a live group to join however the tests before it ended. The holder reads
/// a pipe only the runner holds; when the runner exits or is killed, even by
/// SIGKILL, the read ends and the holder kills the whole group. The group is
/// not the terminal's foreground one, so an interrupt typed at the terminal
/// reaches the runner alone, and the runner's end is what stops the tests. No
/// handler is installed, so a signal the runner inherited as ignored stays
/// ignored. A test that has forked but not yet joined when the group dies
/// fails to join it and never runs.
const TestGroup = struct {
    holder: std.process.Child,

    fn open(io: std.Io) !TestGroup {
        return .{ .holder = try std.process.spawn(io, .{
            .argv = &.{ "/bin/sh", "-c", "read -r _; kill -KILL 0", "linea-test-group" },
            .stdin = .pipe,
            .stdout = .ignore,
            .stderr = .ignore,
            .pgid = 0,
        }) };
    }

    fn pgid(self: *const TestGroup) std.posix.pid_t {
        return self.holder.id.?;
    }

    /// Ends the group once every test has been waited for: the holder then
    /// kills only itself.
    fn close(self: *TestGroup, io: std.Io) void {
        if (self.holder.stdin) |stdin| {
            stdin.close(io);
            self.holder.stdin = null;
        }
        _ = self.holder.wait(io) catch {};
    }
};

const TestResult = struct { term: std.process.Child.Term, stderr: []const u8 };

/// Runs one test binary in the run's process group and keeps what it wrote to
/// standard error, bounded by `output_kept`. Standard output is read and
/// dropped: what a test writes there is its own.
fn runTest(gpa: std.mem.Allocator, io: std.Io, argv: []const []const u8, group: std.posix.pid_t) !TestResult {
    var child = try std.process.spawn(io, .{
        .argv = argv,
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .pipe,
        .pgid = group,
    });
    defer child.kill(io);

    var buffer: std.Io.File.MultiReader.Buffer(2) = undefined;
    var streams: std.Io.File.MultiReader = undefined;
    streams.init(gpa, io, buffer.toStreams(), &.{ child.stdout.?, child.stderr.? });
    defer streams.deinit();

    while (streams.fill(64, .none)) |_| {
        if (streams.reader(0).buffered().len > output_kept) return error.StreamTooLong;
        if (streams.reader(1).buffered().len > output_kept) return error.StreamTooLong;
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => |e| return e,
    }
    try streams.checkAnyError();
    const term = try child.wait(io);
    return .{ .term = term, .stderr = try streams.toOwnedSlice(1) };
}

/// Whether a child's result satisfies its declaration.
///
/// An ordinary test passes only by returning zero. A trap-expected test passes
/// only on the abort signal accompanied by the runtime's source-located trap
/// report; a returned error or an unrelated crash therefore remains a failure.
fn passedWith(expects_trap: bool, term: std.process.Child.Term, detail: []const u8) bool {
    if (!expects_trap) return switch (term) {
        .exited => |code| code == 0,
        else => false,
    };

    return switch (term) {
        .signal => |signal| signal == .ABRT and isRuntimeTrap(detail),
        else => false,
    };
}

/// Whether standard error ends in the source location every language trap
/// reports. The trap taxonomy stays in the runtime; the runner recognises its
/// stable envelope rather than duplicating every trap kind.
fn isRuntimeTrap(detail: []const u8) bool {
    const report_at = std.mem.lastIndexOf(u8, detail, "linea: ") orelse return false;
    const message = std.mem.trimEnd(u8, detail[report_at..], "\r\n");

    const at = std.mem.lastIndexOf(u8, message, " at ") orelse return false;
    const location = message[at + " at ".len ..];
    const column_at = std.mem.lastIndexOfScalar(u8, location, ':') orelse return false;
    if (column_at + 1 == location.len) return false;
    const before_column = location[0..column_at];
    const line_at = std.mem.lastIndexOfScalar(u8, before_column, ':') orelse return false;
    if (line_at == 0 or line_at + 1 == before_column.len) return false;

    const line = std.fmt.parseUnsigned(usize, before_column[line_at + 1 ..], 10) catch return false;
    const column = std.fmt.parseUnsigned(usize, location[column_at + 1 ..], 10) catch return false;
    return line != 0 and column != 0;
}

/// Runs and reports every test, up to `jobs` at a time, and returns whether all passed.
///
/// One child per test, because a test that traps takes its process with it and
/// nothing else's result is lost. The parallelism is here rather than in the
/// language: the driver already spawns the MLIR tools, `cc` and a built program, so
/// running several children is something it does anyway, and Linea gains no
/// threads and no question about what a lend means across one.
///
/// The order results come back in is not the order they are presented in. That
/// is the transcript's, and deliberately not this function's to know: workers
/// say which test they finished, and what that makes due is decided there.
pub fn run(
    gpa: std.mem.Allocator,
    io: std.Io,
    binary: []const u8,
    tests: []const Test,
    jobs: usize,
    root: []const u8,
    w: *std.Io.Writer,
) !bool {
    // Nothing failed, so the run succeeds, as `go test` does for a package
    // with no tests; the line says why nothing ran.
    if (tests.len == 0) {
        try w.print("no tests found in {s}\n", .{root});
        try w.flush();
        return true;
    }
    const out = try gpa.alloc(Outcome, tests.len);
    defer gpa.free(out);
    for (out, tests) |*o, t| o.* = .{ .qualified_name = t.qualified_name, .passed = false, .detail = "" };
    var script = try Transcript.init(gpa, out, w, io);
    defer script.deinit(gpa);

    // Named the way every other spawn names a built program, because a bare
    // name is a PATH search and `test std` builds one.
    const spawn_as = try toolchain.spawnName(gpa, binary);
    defer gpa.free(spawn_as);

    const workers = @max(1, @min(jobs, tests.len));

    var group = try TestGroup.open(io);
    defer group.close(io);

    // One arena per worker, because what a child said is allocated while it is
    // read and several are read at once. Sharing an allocator across them would
    // make a runner whose job is to report failures a program that has one.
    const arenas = try gpa.alloc(std.heap.ArenaAllocator, workers);
    defer gpa.free(arenas);
    for (arenas) |*a| a.* = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer for (arenas) |*a| a.deinit();

    // A second arena per worker, holding only what survives its test: the
    // first is reset around each child and cannot keep anything. Per worker
    // rather than shared, because several are written at once and an allocator
    // between them would need a lock this has no other use for.
    const retained = try gpa.alloc(std.heap.ArenaAllocator, workers);
    defer gpa.free(retained);
    for (retained) |*a| a.* = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer for (retained) |*a| a.deinit();

    const Work = struct {
        fn go(
            io_: std.Io,
            binary_: []const u8,
            tests_: []const Test,
            out_: []Outcome,
            script_: *Transcript,
            arena: *std.heap.ArenaAllocator,
            /// Where a failure's detail is copied to, which outlives the arena
            /// the child was read into. Thread-safe because each worker holds
            /// its own.
            kept: std.mem.Allocator,
            me: usize,
            of: usize,
            group_: std.posix.pid_t,
        ) void {
            var at = me;
            while (at < tests_.len) : (at += of) {
                // Reset per test, so what a worker holds is sized by one test
                // rather than by every test it will ever run. A child's output
                // is bounded; the sum of every child's is not.
                _ = arena.reset(.{ .retain_with_limit = 64 << 10 });
                const a = arena.allocator();
                // Captured, unlike a program `run` executes, whose streams are
                // the user's. Here a failure has to be printed under the name
                // of the test it belongs to, and several children are writing
                // at once -- so what each said is held until its line is due.
                // Bounded, because a test that loops printing would otherwise
                // take the runner's memory rather than being reported as a test
                // that misbehaved. Standard output is asked for and dropped:
                // what a test writes there is its own, and letting it reach the
                // transcript would mix it into results a runner is reading.
                const result = runTest(a, io_, &.{ binary_, tests_[at].qualified_name }, group_) catch {
                    out_[at].passed = false;
                    out_[at].detail = "the test could not be run";
                    // A transcript that cannot be written is not a test that
                    // failed, and there is nowhere left to report it anyway.
                    script_.completed(at) catch {};
                    continue;
                };
                out_[at].passed = passedWith(tests_[at].expects_trap, result.term, result.stderr);
                out_[at].detail = if (out_[at].passed)
                    ""
                else switch (result.term) {
                    .exited => |code| if (tests_[at].expects_trap and code == 0)
                        "expected the test to trap"
                    else
                        (kept.dupe(u8, result.stderr) catch ""),
                    else => kept.dupe(u8, result.stderr) catch "",
                };
                script_.completed(at) catch {};
            }
        }
    };

    if (workers == 1) {
        Work.go(io, spawn_as, tests, out, &script, &arenas[0], retained[0].allocator(), 0, 1, group.pgid());
    } else {
        const threads = try gpa.alloc(std.Thread, workers);
        defer gpa.free(threads);

        // Every thread that started is joined, including when a later spawn
        // fails. Returning from the middle would run the arenas' `deinit` and
        // free `out` underneath threads still writing into both -- a
        // use-after-free reached by nothing worse than the host declining to
        // start a thread, in the one function here that starts any.
        var started: usize = 0;
        while (started < workers) : (started += 1) {
            threads[started] = std.Thread.spawn(.{}, Work.go, .{ io, spawn_as, tests, out, &script, &arenas[started], retained[started].allocator(), started, workers, group.pgid() }) catch break;
        }
        for (threads[0..started]) |t| t.join();

        // What the threads that never started would have run. A host too busy
        // to start one is not a reason to report tests nobody ran.
        var at = started;
        while (at < workers) : (at += 1) Work.go(io, spawn_as, tests, out, &script, &arenas[at], retained[at].allocator(), at, workers, group.pgid());
    }

    try script.finish();

    for (out) |o| if (!o.passed) return false;
    return true;
}

/// The transcript, written in fully-qualified name order as results come in.
///
/// Ordered by name and never by what finished first. The two agree on a fast
/// machine and under a rewrite that reverses declarations, and part company the
/// moment two tests take different amounts of time -- so a transcript printed in
/// the order children exited would be right until it was mysteriously not, and
/// its output would depend on a scheduler nobody is reading.
///
/// Written as results arrive rather than at the end, which changes when the
/// bytes appear and not what they are: a result is due the moment every name
/// before it has been written, and is written then. So a suite reports as it
/// goes and a golden records what it always did.
///
/// The cost is named rather than hidden: a slow test early in the order holds
/// back results already in hand. That is what buying an order a reader and a
/// golden can both rely on costs, and the alternative is output that depends on
/// which child the host happened to schedule first.
const Transcript = struct {
    outcomes: []const Outcome,
    /// Indices into `outcomes`, by name: the order lines are due in.
    order: []usize,
    /// Which outcomes have completed, indexed as `outcomes` is.
    ready: []bool,
    /// How far along `order` the writing has reached.
    at: usize = 0,
    passed: usize = 0,
    failed: usize = 0,
    w: *std.Io.Writer,
    io: std.Io,
    /// Several workers finish at once and each may make a run of results due,
    /// so the cursor, the flags, the counts and the writer move together or not
    /// at all.
    ///
    /// Held across a write and a flush, which is a syscall -- so a worker that
    /// finished while another is writing waits for that write and not for a
    /// test. Uncancelable, because a worker reporting what its child did has
    /// nowhere to abandon the report to.
    lock: std.Io.Mutex = .init,

    fn init(
        gpa: std.mem.Allocator,
        outcomes: []const Outcome,
        w: *std.Io.Writer,
        io: std.Io,
    ) !Transcript {
        const order = try gpa.alloc(usize, outcomes.len);
        errdefer gpa.free(order);
        for (order, 0..) |*o, i| o.* = i;
        std.mem.sort(usize, order, outcomes, struct {
            fn before(all: []const Outcome, a: usize, b: usize) bool {
                return std.mem.lessThan(u8, all[a].qualified_name, all[b].qualified_name);
            }
        }.before);

        const ready = try gpa.alloc(bool, outcomes.len);
        errdefer gpa.free(ready);
        @memset(ready, false);

        return .{
            .outcomes = outcomes,
            .order = order,
            .ready = ready,
            .w = w,
            .io = io,
        };
    }

    fn deinit(self: *Transcript, gpa: std.mem.Allocator) void {
        gpa.free(self.order);
        gpa.free(self.ready);
        self.* = undefined;
    }

    /// Records that the outcome at `index` is in hand, writing whatever that
    /// makes due -- which is nothing at all where a name before it is still
    /// running, and a run of results where several were waiting on this one.
    fn completed(self: *Transcript, index: usize) std.Io.Writer.Error!void {
        self.lock.lockUncancelable(self.io);
        defer self.lock.unlock(self.io);

        self.ready[index] = true;
        while (self.at < self.order.len and self.ready[self.order[self.at]]) : (self.at += 1) {
            const o = self.outcomes[self.order[self.at]];
            if (o.passed) self.passed += 1 else self.failed += 1;
            try writeResult(self.w, o);
        }
        // Flushed per result rather than at the end, because a transcript
        // written as it goes and buffered to the end is the one it replaced.
        try self.w.flush();
    }

    /// The count, once every result has been written. `testsReported` in
    /// `build/source.zig` reads this line, so a change to it changes that.
    fn finish(self: *Transcript) std.Io.Writer.Error!void {
        self.lock.lockUncancelable(self.io);
        defer self.lock.unlock(self.io);

        try self.w.print("\n{d} passed, {d} failed\n", .{ self.passed, self.failed });
        try self.w.flush();
    }
};

/// One result, as the transcript states it.
fn writeResult(w: *std.Io.Writer, o: Outcome) std.Io.Writer.Error!void {
    if (o.passed) {
        try w.print("ok    {s}\n", .{o.qualified_name});
        return;
    }
    try w.print("FAIL  {s}\n", .{o.qualified_name});

    // What the child said, indented under the name it belongs to. A failure
    // several tests deep in a transcript is read by looking for its name, and
    // detail that started at the margin would be indistinguishable from the
    // next line of results.
    var lines = std.mem.splitScalar(u8, std.mem.trimEnd(u8, o.detail, "\n"), '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        try w.print("        {s}\n", .{line});
    }
}

test "a child's status is read as success or failure and as nothing else" {
    // A test that returned a status of its own, one that trapped, and one a
    // signal killed are all failures, and the difference between them is on
    // standard error where it was already explained.
    try testing.expect(passedWith(false, .{ .exited = 0 }, ""));
    try testing.expect(!passedWith(false, .{ .exited = 1 }, "error: no"));
    try testing.expect(!passedWith(false, .{ .exited = 134 }, ""));
    try testing.expect(!passedWith(false, .{ .signal = .ABRT }, "linea: assertion failed at test.lin:1:1\n"));
}

test "an expected trap passes only for a source-located runtime abort" {
    const report = "linea: value out of range for its type at test.lin:3:7\n";
    try testing.expect(passedWith(true, .{ .signal = .ABRT }, report));
    try testing.expect(passedWith(true, .{ .signal = .ABRT }, "before\n" ++ report));
    try testing.expect(!passedWith(true, .{ .exited = 0 }, ""));
    try testing.expect(!passedWith(true, .{ .exited = 1 }, report));
    try testing.expect(!passedWith(true, .{ .signal = .SEGV }, report));
    try testing.expect(!passedWith(true, .{ .signal = .ABRT }, ""));
    try testing.expect(!passedWith(true, .{ .signal = .ABRT }, "linea: runtime failure\n"));
}

/// The transcript a set of outcomes produces, completed in the given order.
///
/// Completion order is a parameter because it is the whole of what these are
/// about: what a worker finished when is the one thing a transcript must not
/// depend on, and a machine fast enough never produces the order that would
/// show it.
fn transcriptOf(gpa: std.mem.Allocator, outcomes: []const Outcome, finished: []const usize) ![]u8 {
    var threaded: std.Io.Threaded = .init(gpa, .{});
    defer threaded.deinit();

    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();

    var script = try Transcript.init(gpa, outcomes, &out.writer, threaded.io());
    defer script.deinit(gpa);

    for (finished) |i| try script.completed(i);
    try script.finish();
    return out.toOwnedSlice();
}

test "the transcript is name-ordered however the children finished" {
    // Completion order is neither declaration order nor name order, and an
    // implementation printing as each child exits agrees with all three until
    // two tests take different amounts of time. Finished here out of order on
    // purpose, because that is the case a fast machine never produces.
    const gpa = testing.allocator;

    const outcomes = [_]Outcome{
        .{ .qualified_name = "m.zebra", .passed = true, .detail = "" },
        .{ .qualified_name = "m.alpha", .passed = true, .detail = "" },
    };

    const text = try transcriptOf(gpa, &outcomes, &.{ 0, 1 });
    defer gpa.free(text);

    try testing.expect(std.mem.indexOf(u8, text, "m.alpha").? <
        std.mem.indexOf(u8, text, "m.zebra").?);
    try testing.expect(std.mem.indexOf(u8, text, "2 passed, 0 failed") != null);
}

test "a result is written the moment every name before it has been" {
    // What streaming buys, stated as the property that pays for it: a result
    // whose predecessors are all in hand is written, and one whose predecessor
    // is still running is not. Read by writing into the transcript and looking
    // at what has reached the buffer, which is what a reader would have seen.
    const gpa = testing.allocator;

    const outcomes = [_]Outcome{
        .{ .qualified_name = "m.zebra", .passed = true, .detail = "" },
        .{ .qualified_name = "m.alpha", .passed = true, .detail = "" },
    };

    var threaded: std.Io.Threaded = .init(gpa, .{});
    defer threaded.deinit();

    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();

    var script = try Transcript.init(gpa, &outcomes, &out.writer, threaded.io());
    defer script.deinit(gpa);

    // The later name finishes first, and nothing is due: `m.alpha` is still to
    // come and a transcript that printed `m.zebra` here would be in completion
    // order.
    try script.completed(0);
    try testing.expectEqualStrings("", out.written());

    // The earlier one finishing makes both due at once.
    try script.completed(1);
    try testing.expect(std.mem.indexOf(u8, out.written(), "m.alpha").? <
        std.mem.indexOf(u8, out.written(), "m.zebra").?);
}

test "a failure is printed under the name it belongs to" {
    const gpa = testing.allocator;

    const outcomes = [_]Outcome{
        .{ .qualified_name = "m.broke", .passed = false, .detail = "error: nope\n" },
    };

    const text = try transcriptOf(gpa, &outcomes, &.{0});
    defer gpa.free(text);

    try testing.expect(std.mem.indexOf(u8, text, "FAIL  m.broke") != null);
    try testing.expect(std.mem.indexOf(u8, text, "        error: nope") != null);
    try testing.expect(std.mem.indexOf(u8, text, "0 passed, 1 failed") != null);
}
