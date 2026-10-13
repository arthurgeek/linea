//! Cram-style transcript cases: shell commands with their expected output
//! inline. A line beginning `  $ ` is a command, `  > ` continues it, the
//! two-space-indented lines after it are its combined output, `  [N]` records
//! a non-zero exit status, and every other line is prose. The file is its own
//! golden: rendering what ran over the same prose gives the file to compare.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const toolchain = @import("../driver/toolchain.zig");
const hermeticRun = @import("process.zig").run;

pub const Step = struct {
    command: []const u8,
    /// Combined standard output and standard error, each line ending in `\n`.
    expected: []const u8,
    exit: u8,
};

pub const Piece = union(enum) {
    /// Lines kept verbatim, newlines included.
    prose: []const u8,
    step: Step,
};

pub const Transcript = struct {
    pieces: []const Piece,

    pub fn deinit(self: *Transcript, gpa: Allocator) void {
        for (self.pieces) |piece| switch (piece) {
            .prose => |text| gpa.free(text),
            .step => |step| {
                gpa.free(step.command);
                gpa.free(step.expected);
            },
        };
        gpa.free(self.pieces);
        self.* = undefined;
    }

    fn steps(self: Transcript) usize {
        var n: usize = 0;
        for (self.pieces) |piece| n += @intFromBool(piece == .step);
        return n;
    }
};

const command_prefix = "  $ ";
const continuation_prefix = "  > ";
const output_prefix = "  ";

/// Whether `text` holds any command line. A command case without one runs
/// nothing, so the runner refuses it.
pub fn isTranscript(text: []const u8) bool {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, command_prefix)) return true;
    }
    return false;
}

test "a transcript is told by its command lines" {
    try std.testing.expect(isTranscript("Prose.\n\n  $ echo hi\n"));
    try std.testing.expect(!isTranscript("run tests/cmd/a.lin\n"));
    try std.testing.expect(!isTranscript("$ echo unindented\n"));
}

/// The exit status a `  [N]` line records, or null for any other line.
fn exitLine(line: []const u8) ?u8 {
    if (!std.mem.startsWith(u8, line, "  [") or !std.mem.endsWith(u8, line, "]")) return null;
    return std.fmt.parseInt(u8, line[3 .. line.len - 1], 10) catch null;
}

/// Whether `line` would be read as output of an open step.
fn isOutputLine(line: []const u8) bool {
    return std.mem.startsWith(u8, line, output_prefix) and !std.mem.startsWith(u8, line, command_prefix);
}

fn closeProse(gpa: Allocator, pieces: *std.ArrayList(Piece), text: []const u8, start: *?usize, end: usize) !void {
    const from = start.* orelse return;
    start.* = null;
    const prose = try gpa.dupe(u8, text[from..end]);
    errdefer gpa.free(prose);
    try pieces.append(gpa, .{ .prose = prose });
}

fn closeStep(
    gpa: Allocator,
    pieces: *std.ArrayList(Piece),
    command: *std.ArrayList(u8),
    output: *std.ArrayList(u8),
    exit: *u8,
) !void {
    const owned_command = try gpa.dupe(u8, command.items);
    errdefer gpa.free(owned_command);
    const owned_output = try gpa.dupe(u8, output.items);
    errdefer gpa.free(owned_output);
    try pieces.append(gpa, .{ .step = .{ .command = owned_command, .expected = owned_output, .exit = exit.* } });
    command.clearRetainingCapacity();
    output.clearRetainingCapacity();
    exit.* = 0;
}

pub fn parse(gpa: Allocator, text: []const u8) !Transcript {
    var pieces: std.ArrayList(Piece) = .empty;
    errdefer {
        var partial: Transcript = .{ .pieces = pieces.items };
        partial.deinit(gpa);
    }

    var command: std.ArrayList(u8) = .empty;
    defer command.deinit(gpa);
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(gpa);
    var exit: u8 = 0;
    // Whether a step is open, and whether its command still takes `  > ` lines.
    var open = false;
    var continuing = false;
    // Where the prose run being gathered starts in `text`.
    var prose_start: ?usize = null;

    var at: usize = 0;
    while (at < text.len) {
        const end = std.mem.indexOfScalarPos(u8, text, at, '\n') orelse text.len;
        const line = text[at..end];
        const next = @min(end + 1, text.len);
        defer at = next;

        if (std.mem.startsWith(u8, line, command_prefix)) {
            try closeProse(gpa, &pieces, text, &prose_start, at);
            if (open) try closeStep(gpa, &pieces, &command, &output, &exit);
            try command.appendSlice(gpa, line[command_prefix.len..]);
            open = true;
            continuing = true;
            continue;
        }
        if (open and continuing and std.mem.startsWith(u8, line, continuation_prefix)) {
            try command.append(gpa, '\n');
            try command.appendSlice(gpa, line[continuation_prefix.len..]);
            continue;
        }
        if (open and std.mem.startsWith(u8, line, output_prefix)) {
            continuing = false;
            // `  [N]` is the status only where no output line follows it, so
            // an output line reading `[N]` is still output.
            const rest = text[next..];
            const following = rest[0 .. std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len];
            if (exitLine(line)) |status| if (next == text.len or !isOutputLine(following)) {
                exit = status;
                continue;
            };
            try output.appendSlice(gpa, line[output_prefix.len..]);
            try output.append(gpa, '\n');
            continue;
        }
        if (open) {
            try closeStep(gpa, &pieces, &command, &output, &exit);
            open = false;
            continuing = false;
        }
        if (prose_start == null) prose_start = at;
    }
    if (open) try closeStep(gpa, &pieces, &command, &output, &exit);
    try closeProse(gpa, &pieces, text, &prose_start, text.len);
    return .{ .pieces = try pieces.toOwnedSlice(gpa) };
}

test "a transcript keeps prose and splits commands from their output" {
    const text =
        \\The greeting.
        \\
        \\  $ echo hi
        \\  hi
        \\  $ false
        \\  [1]
        \\
    ;
    var t = try parse(std.testing.allocator, text);
    defer t.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 3), t.pieces.len);
    try std.testing.expectEqualStrings("echo hi", t.pieces[1].step.command);
    try std.testing.expectEqualStrings("hi\n", t.pieces[1].step.expected);
    try std.testing.expectEqual(@as(u8, 1), t.pieces[2].step.exit);
}

test "a continuation line joins the command above it" {
    const text = "  $ printf '%s\\n' \\\n  > a\n  a\n";
    var t = try parse(std.testing.allocator, text);
    defer t.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("printf '%s\\n' \\\na", t.pieces[0].step.command);
}

test "an output line reading like a status is output while more output follows" {
    var t = try parse(std.testing.allocator, "  $ cat list\n  [1]\n  two\n");
    defer t.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("[1]\ntwo\n", t.pieces[0].step.expected);
    try std.testing.expectEqual(@as(u8, 0), t.pieces[0].step.exit);
}

test "an indented line after prose is prose" {
    var t = try parse(std.testing.allocator, "  $ true\nProse.\n  indented\n");
    defer t.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), t.pieces.len);
    try std.testing.expectEqualStrings("", t.pieces[0].step.expected);
    try std.testing.expectEqualStrings("Prose.\n  indented\n", t.pieces[1].prose);
}

/// The transcript's prose with each step's command followed by `actual`'s
/// output and status, in the transcript's own format. `actual` holds one
/// entry per step, in order.
pub fn render(gpa: Allocator, transcript: Transcript, actual: []const Step) ![]u8 {
    std.debug.assert(actual.len == transcript.steps());
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    var k: usize = 0;
    for (transcript.pieces) |piece| switch (piece) {
        .prose => |text| try w.writeAll(text),
        .step => |step| {
            var lines = std.mem.splitScalar(u8, step.command, '\n');
            try w.print("{s}{s}\n", .{ command_prefix, lines.first() });
            while (lines.next()) |line| try w.print("{s}{s}\n", .{ continuation_prefix, line });

            const ran = actual[k];
            k += 1;
            var output = ran.expected;
            while (output.len > 0) {
                const end = std.mem.indexOfScalar(u8, output, '\n') orelse output.len;
                try w.print("{s}{s}\n", .{ output_prefix, output[0..end] });
                output = output[@min(end + 1, output.len)..];
            }
            if (ran.exit != 0) try w.print("  [{d}]\n", .{ran.exit});
        },
    };
    return out.toOwnedSlice();
}

test "rendering an unchanged run reproduces the file byte for byte" {
    const text = "Prose.\n\n  $ echo hi\n  hi\n  $ false\n  [1]\n";
    var t = try parse(std.testing.allocator, text);
    defer t.deinit(std.testing.allocator);
    const out = try render(std.testing.allocator, t, &.{ .{ .command = "echo hi", .expected = "hi\n", .exit = 0 }, .{ .command = "false", .expected = "", .exit = 1 } });
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(text, out);
}

/// The first subcommand some step runs as `linea <subcommand>` that is one of
/// the commands a build may leave out (`optional`) and that the compiler under
/// test does not list in its `help`, or null when every step can run.
///
/// Read from the binary's own usage text rather than from the mode the runner
/// was built in: the runner may be built ReleaseSafe beside a Debug compiler,
/// and the compiler is what the transcript drives.
pub fn hiddenCommand(transcript: Transcript, help: []const u8, optional: *const fn ([]const u8) bool) ?[]const u8 {
    const separators = " \t\n;&|()";
    for (transcript.pieces) |piece| switch (piece) {
        .prose => {},
        .step => |step| {
            var words = std.mem.tokenizeAny(u8, step.command, separators);
            while (words.next()) |word| {
                if (!std.mem.eql(u8, word, "linea")) continue;
                const named = words.peek() orelse continue;
                if (optional(named) and !offers(help, named)) return named;
            }
        },
    };
    return null;
}

/// Whether some step builds or runs a program: `linea run`, `linea test` or
/// `linea build`, whose output a later step runs.
pub fn runsAProgram(transcript: Transcript) bool {
    const separators = " \t\n;&|()";
    for (transcript.pieces) |piece| switch (piece) {
        .prose => {},
        .step => |step| {
            var words = std.mem.tokenizeAny(u8, step.command, separators);
            while (words.next()) |word| {
                if (!std.mem.eql(u8, word, "linea")) continue;
                const named = words.peek() orelse continue;
                for ([_][]const u8{ "run", "test", "build" }) |runs| {
                    if (std.mem.eql(u8, named, runs)) return true;
                }
            }
        },
    };
    return false;
}

test "a transcript that builds or runs a program is told from one that does not" {
    var runs = try parse(std.testing.allocator, "  $ linea check a.lin\n  $ linea build a.lin -o a && ./a\n");
    defer runs.deinit(std.testing.allocator);
    try std.testing.expect(runsAProgram(runs));
    var checks = try parse(std.testing.allocator, "  $ linea check a.lin\n  $ linea fmt --check a.lin\n");
    defer checks.deinit(std.testing.allocator);
    try std.testing.expect(!runsAProgram(checks));
}

/// Whether `help` is usage text this can read: one listing `check`, which
/// every build offers. Anything else would read as a build hiding every
/// debugging aid, and pass each transcript naming one over unchecked.
pub fn isUsage(help: []const u8) bool {
    return offers(help, "check");
}

/// Whether a compiler's usage text lists `name` as a command: a command line
/// in it is indented by two spaces and begins with the command's name.
pub fn offers(help: []const u8, name: []const u8) bool {
    var lines = std.mem.splitScalar(u8, help, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "  ")) continue;
        const rest = line[2..];
        if (std.mem.startsWith(u8, rest, name) and (rest.len == name.len or rest[name.len] == ' ')) return true;
    }
    return false;
}

test "a step naming a command the compiler does not list is found" {
    const optionalDump = struct {
        fn optional(name: []const u8) bool {
            return std.mem.startsWith(u8, name, "dump-");
        }
    }.optional;
    const release_help = "usage: linea <command> [options]\n\ncommands:\n  check <path>        report diagnostics\n";
    const debug_help = release_help ++ "\ndebugging:\n  dump-ast <file>     print the syntax tree\n";
    var t = try parse(std.testing.allocator, "  $ linea check a.lin\n  $ x=1; linea dump-ast a.lin\n");
    defer t.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("dump-ast", hiddenCommand(t, release_help, optionalDump).?);
    try std.testing.expectEqual(@as(?[]const u8, null), hiddenCommand(t, debug_help, optionalDump));

    var none = try parse(std.testing.allocator, "  $ linea run a.lin\n");
    defer none.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(?[]const u8, null), hiddenCommand(none, release_help, optionalDump));
}

/// Where a transcript runs, and what its shell is handed.
pub const Environment = struct {
    /// The compiler, reached as `linea` on the shell's `PATH`.
    linea: []const u8,
    /// The checkout's absolute path, exported as `LINEA_ROOT` and written as
    /// `$LINEA_ROOT` wherever it appears in captured output.
    root: []const u8,
    /// An empty directory this case owns. It holds the script, the `linea`
    /// link, and the `work` directory the commands run in.
    directory: []const u8,
    environ: std.process.Environ,
    runtime: ?[]const u8,
    sanitize: ?[]const u8,
    timeout_seconds: u32 = default_timeout_seconds,
};

/// A deadline catches a hang, never a slow run, because a timing assertion
/// inside the suite fails on a busy machine. The slowest transcript,
/// `linea test std`, takes 18 s on an idle machine and was seen past 60 s at a
/// load average of 43, beside the corpus walk and other builds. Ten minutes is
/// ten times that; a case that truly hangs costs ten minutes to report. A
/// transcript that waits on something, such as a server binding its port,
/// bounds that wait itself and fails in seconds.
pub const default_timeout_seconds = 600;

/// The longest a transcript has been seen to take on a loaded machine.
const slowest_loaded_seconds = 60;

// The deadline sits an order of magnitude above the slowest loaded run.
comptime {
    std.debug.assert(default_timeout_seconds >= 10 * slowest_loaded_seconds);
}

/// The marker a step's status line starts with: the ASCII record separator,
/// which no command in a transcript prints.
const record_separator = '\x1e';

/// What a transcript's steps printed, one entry per step in order. Each
/// step's command is borrowed from the transcript that ran.
pub const Ran = struct {
    steps: []Step,
    /// Whether the shell outlived the deadline. The steps then hold what was
    /// printed before it, so a hung case still shows how far it got.
    timed_out: bool,

    pub fn deinit(self: Ran, gpa: Allocator) void {
        for (self.steps) |step| gpa.free(step.expected);
        gpa.free(self.steps);
    }
};

/// Runs every command of `transcript` in one `/bin/sh`, so variables and
/// background jobs carry from one command to the next, and returns what each
/// printed and its status.
///
/// A step the shell never finished, because an earlier command ended the
/// shell or the deadline passed, reports status 255 and holds any output that
/// followed the last finished step. When the shell outlives
/// `timeout_seconds`, its whole process group is killed.
pub fn run(gpa: Allocator, io: Io, env: Environment, transcript: Transcript) !Ran {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const cwd = std.Io.Dir.cwd();

    const bin = try std.fs.path.join(arena, &.{ env.directory, "bin" });
    const work = try std.fs.path.join(arena, &.{ env.directory, "work" });
    const script_path = try std.fs.path.join(arena, &.{ env.directory, "script.sh" });
    try cwd.createDirPath(io, bin);
    try cwd.createDirPath(io, work);
    // A link named `linea` makes the compiler reachable under that name
    // whatever its file is called.
    const linea = try cwd.realPathFileAlloc(io, env.linea, arena);
    try cwd.symLink(io, linea, try std.fs.path.join(arena, &.{ bin, "linea" }), .{});

    var script: std.Io.Writer.Allocating = .init(arena);
    // Output and errors share one stream so they interleave as written. The
    // exit trap kills the shell's process group, so a background job still
    // running when the last command ends cannot hold the output pipe open.
    try script.writer.writeAll(
        \\exec 2>&1
        \\trap 'kill -KILL 0' EXIT
        \\linea_step() { printf '\036%d\n' "$1"; }
        \\
    );
    for (transcript.pieces) |piece| switch (piece) {
        .prose => {},
        .step => |step| try script.writer.print("{s}\nlinea_step $?\n", .{step.command}),
    };
    try cwd.writeFile(io, .{ .sub_path = script_path, .data = script.written() });

    var environ = try env.environ.createMap(arena);
    const path = if (environ.get("PATH")) |inherited|
        try std.mem.concat(arena, u8, &.{ bin, ":", inherited })
    else
        bin;
    try environ.put("PATH", path);
    try environ.put("LINEA_ROOT", env.root);
    // The commands run in `work`, so a relative runtime path would name a
    // file under it.
    if (env.runtime) |rt| try environ.put(toolchain.runtime_override, try cwd.realPathFileAlloc(io, rt, arena));
    if (env.sanitize) |name| try environ.put(toolchain.sanitize_override, name);

    var partial: []u8 = &.{};
    var timed_out = false;
    const combined = if (hermeticRun(arena, io, .{
        .argv = &.{ "/bin/sh", script_path },
        .environ_map = &environ,
        .cwd = .{ .path = work },
        .process_group = true,
        .timeout = .{ .deadline = .fromNow(io, .{
            .raw = .fromSeconds(env.timeout_seconds),
            .clock = .awake,
        }) },
        .partial = &partial,
    })) |result|
        try std.mem.concat(arena, u8, &.{ result.stdout, result.stderr })
    else |err| switch (err) {
        error.Timeout => timed_out: {
            timed_out = true;
            break :timed_out partial;
        },
        else => |e| return e,
    };

    const steps = try gpa.alloc(Step, transcript.steps());
    var filled: usize = 0;
    errdefer (Ran{ .steps = steps[0..filled], .timed_out = timed_out }).deinit(gpa);

    var k: usize = 0;
    var rest: []const u8 = combined;
    for (transcript.pieces) |piece| switch (piece) {
        .prose => {},
        .step => |step| {
            var output: []const u8 = rest;
            var exit: u8 = 255;
            if (std.mem.indexOfScalar(u8, rest, record_separator)) |marker| {
                output = rest[0..marker];
                const line_end = std.mem.indexOfScalarPos(u8, rest, marker, '\n') orelse rest.len;
                exit = std.fmt.parseInt(u8, rest[marker + 1 .. line_end], 10) catch 255;
                rest = rest[@min(line_end + 1, rest.len)..];
            } else {
                rest = "";
            }
            steps[k] = .{
                .command = step.command,
                .expected = try std.mem.replaceOwned(u8, gpa, output, env.root, "$LINEA_ROOT"),
                .exit = exit,
            };
            k += 1;
            filled = k;
        },
    };
    return .{ .steps = steps, .timed_out = timed_out };
}

test "commands share one shell and see the checkout root" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const directory = try tmp.dir.realPathFileAlloc(io, ".", gpa);
    defer gpa.free(directory);

    var t = try parse(gpa,
        \\  $ greeting=hi
        \\  $ linea "$greeting"
        \\  $ echo "$LINEA_ROOT/examples"
        \\  $ false
        \\
    );
    defer t.deinit(gpa);
    const ran = try run(gpa, io, .{
        .linea = "/bin/echo",
        .root = directory,
        .directory = directory,
        .environ = std.testing.environ,
        .runtime = null,
        .sanitize = null,
    }, t);
    defer ran.deinit(gpa);
    const steps = ran.steps;

    try std.testing.expect(!ran.timed_out);
    try std.testing.expectEqual(@as(usize, 4), steps.len);
    try std.testing.expectEqualStrings("", steps[0].expected);
    try std.testing.expectEqualStrings("hi\n", steps[1].expected);
    try std.testing.expectEqualStrings("$LINEA_ROOT/examples\n", steps[2].expected);
    try std.testing.expectEqual(@as(u8, 0), steps[2].exit);
    try std.testing.expectEqual(@as(u8, 1), steps[3].exit);
}

/// Fails unless the process whose pid `directory/job` records has exited.
fn expectJobKilled(io: Io, directory: std.Io.Dir) !void {
    var buffer: [64]u8 = undefined;
    const recorded = try directory.readFile(io, "job", &buffer);
    const job = try std.fmt.parseInt(std.posix.pid_t, std.mem.trim(u8, recorded, " \n"), 10);
    // A killed orphan is reaped by init, which may take a moment.
    var attempts: usize = 0;
    while (true) : (attempts += 1) {
        std.posix.kill(job, @enumFromInt(0)) catch |err| switch (err) {
            error.ProcessNotFound => return,
            else => return err,
        };
        if (attempts == 200) return error.JobSurvived;
        try io.sleep(.fromMilliseconds(10), .awake);
    }
}

test "a command past its deadline fails its case with what ran before it" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const directory = try tmp.dir.realPathFileAlloc(io, ".", gpa);
    defer gpa.free(directory);

    // The background job records its pid, so the test can see it was killed
    // with the shell rather than left holding the output pipe.
    var t = try parse(gpa,
        \\  $ echo started
        \\  $ sleep 30 & echo $! > ../job
        \\  $ echo waiting; sleep 5
        \\
    );
    defer t.deinit(gpa);
    const ran = try run(gpa, io, .{
        .linea = "/bin/echo",
        .root = directory,
        .directory = directory,
        .environ = std.testing.environ,
        .runtime = null,
        .sanitize = null,
        .timeout_seconds = 1,
    }, t);
    defer ran.deinit(gpa);

    try std.testing.expect(ran.timed_out);
    try std.testing.expectEqualStrings("started\n", ran.steps[0].expected);
    try std.testing.expectEqual(@as(u8, 0), ran.steps[1].exit);
    try std.testing.expectEqualStrings("waiting\n", ran.steps[2].expected);
    try std.testing.expectEqual(@as(u8, 255), ran.steps[2].exit);
    try expectJobKilled(io, tmp.dir);
}

test "a background job still running when the last command ends is killed" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const directory = try tmp.dir.realPathFileAlloc(io, ".", gpa);
    defer gpa.free(directory);

    var t = try parse(gpa,
        \\  $ sleep 30 & echo $! > ../job
        \\
    );
    defer t.deinit(gpa);
    const started = std.Io.Clock.awake.now(io);
    const ran = try run(gpa, io, .{
        .linea = "/bin/echo",
        .root = directory,
        .directory = directory,
        .environ = std.testing.environ,
        .runtime = null,
        .sanitize = null,
        .timeout_seconds = 20,
    }, t);
    defer ran.deinit(gpa);
    const elapsed = started.durationTo(std.Io.Clock.awake.now(io));

    try std.testing.expect(!ran.timed_out);
    try std.testing.expectEqual(@as(u8, 0), ran.steps[0].exit);
    try std.testing.expect(elapsed.toSeconds() < 5);
    try expectJobKilled(io, tmp.dir);
}

test "usage text is read only where it lists the commands every build offers" {
    try std.testing.expect(isUsage("usage: linea <command> [options]\n\ncommands:\n  check <path>        report diagnostics\n"));
    // A layout this cannot read would read as a build hiding every dump.
    try std.testing.expect(!isUsage(""));
    try std.testing.expect(!isUsage("commands:\ncheck <path>\n"));
}
