//! `linea fmt` — rewrite source in canonical form, in place.

const std = @import("std");

const driver = @import("driver.zig");
const cli = @import("../support/cli.zig");
const corpus = @import("../support/corpus.zig");
const diff = @import("../support/diff.zig");
const fmt = @import("../fmt/fmt.zig");
const render = @import("../diagnostics/render.zig");
const render_json = @import("../diagnostics/render_json.zig");
const source_mod = @import("../support/source.zig");
const FileTable = source_mod.FileTable;
const Sink = @import("../diagnostics/sink.zig").Sink;

pub fn run(
    gpa: std.mem.Allocator,
    io: std.Io,
    args: []const []const u8,
    stderr: *std.Io.Writer,
) !u8 {
    var color: driver.ColorArg = .auto;
    var error_format: driver.ErrorFormat = .human;
    var use_stdin = false;
    var check_only = false;
    var paths: std.ArrayList([]const u8) = .empty;

    const cmd = driver.spec.find("fmt").?;
    var it: cli.Iterator = .{ .spec = driver.spec, .command = cmd, .args = args };
    while (it.next()) |item| switch (item) {
        .operand => |p| try paths.append(gpa, p),
        .option => |o| {
            if (std.mem.eql(u8, o.name, "--stdin")) {
                use_stdin = true;
            } else if (std.mem.eql(u8, o.name, "--check")) {
                check_only = true;
            } else if (std.mem.eql(u8, o.name, "--color")) {
                color = driver.parseColor(o.value) orelse {
                    try stderr.writeAll("error: invalid --color value\n");
                    return driver.exit_usage;
                };
            } else if (std.mem.eql(u8, o.name, "--error-format")) {
                error_format = std.meta.stringToEnum(driver.ErrorFormat, o.value) orelse {
                    try stderr.writeAll("error: invalid --error-format value\n");
                    return driver.exit_usage;
                };
            }
        },
    };
    if (it.problem) |problem| {
        try problem.report(stderr);
        try driver.spec.writeCommandUsage(stderr, cmd);
        return driver.exit_usage;
    }

    // A bare `linea fmt` is a usage error rather than an implicit `.`: the
    // shortest possible command should not be a recursive in-place rewrite of
    // everything below the working directory.
    if (use_stdin == (paths.items.len > 0)) {
        try driver.spec.writeCommandUsage(stderr, cmd);
        return driver.exit_usage;
    }

    const stdout_file = std.Io.File.stdout();
    var stdout: driver.Out = .{};
    const stdout_w = stdout.open(io, stdout_file);
    defer stdout.flush() catch {};

    const use_color: render.Color = switch (color) {
        .always => .always,
        .never => .never,
        .auto => if (stdout_file.isTty(io) catch false) .always else .never,
    };

    // Two different answers, which one flag could not give. `failed` is a file
    // that could not be read or could not be parsed; `differs` is a file whose
    // formatting is not what it should be. Writing one out is success, so only
    // `--check` is entitled to report a difference as a failure -- otherwise
    // `linea fmt src && git add -A` never reaches its second half.
    var failed = false;
    var differs = false;

    if (use_stdin) {
        var table: FileTable = .empty;
        defer table.deinit(gpa);
        var sink = Sink.init(gpa);

        var stdin_reader = std.Io.File.stdin().reader(io, &.{});
        // A pipe carries no size to check before reading, so the same cap a
        // file answers to is applied to what arrives. This is the one route
        // into the compiler that a size on disk does not already bound, and
        // the one an editor uses.
        const text = source_mod.readWithin(gpa, &stdin_reader.interface, source_mod.max_bytes, 0) catch |e| {
            try stderr.print("error: cannot read stdin: {s}\n", .{@errorName(e)});
            return driver.exit_io;
        };
        // Reading stdin means no file is being described, and a diagnostic
        // naming a path this invocation never opened is worse than one naming
        // none: an editor would happily jump to it.
        const formatted = try formatText(gpa, "<stdin>", text, &table, &sink, stderr) orelse {
            try reportDiagnostics(gpa, &table, &sink, stderr, use_color, error_format);
            return driver.exit_diagnostics;
        };
        // Nothing is written on a parse error, rather than a partial buffer: an
        // editor pipes its buffer through this, and half a file is worse than
        // none.
        try stdout_w.writeAll(formatted);
        return driver.exit_ok;
    }

    var files: std.ArrayList([]const u8) = .empty;
    for (paths.items) |p| try collectLineaFiles(gpa, io, p, &files);

    for (files.items) |p| {
        // A sink of its own per file. Sharing one would make the first file
        // that does not parse refuse every file after it, since what the sink
        // reports is whether anything at all has gone wrong.
        var table: FileTable = .empty;
        defer table.deinit(gpa);
        var sink = Sink.init(gpa);

        const text = source_mod.readFileAlloc(io, gpa, p) catch |e| {
            try stderr.print("error: cannot read {s}: {s}\n", .{ p, @errorName(e) });
            failed = true;
            continue;
        };
        const formatted = try formatText(gpa, p, text, &table, &sink, stderr) orelse {
            try reportDiagnostics(gpa, &table, &sink, stderr, use_color, error_format);
            failed = true;
            continue;
        };
        if (std.mem.eql(u8, formatted, text)) continue;
        differs = true;

        if (check_only) {
            const before = try diff.splitLines(gpa, text);
            const after = try diff.splitLines(gpa, formatted);
            const edits = try diff.diff(gpa, before, after);
            try diff.writeUnified(stdout_w, p, edits, .{
                .color = use_color == .always,
            });
            continue;
        }
        const out_file = try std.Io.Dir.cwd().createFile(io, p, .{});
        defer out_file.close(io);
        var out: driver.Out = .{};
        try out.open(io, out_file).writeAll(formatted);
        try out.flush();
    }

    return if (failed or (check_only and differs)) driver.exit_diagnostics else driver.exit_ok;
}

/// Formats one text for the command line, or null where the result must not
/// be used.
///
/// Whether a text may be laid out again, and what it becomes, is `fmt`'s
/// answer. What is here is the part only a command line has: a note on
/// standard error about a hatch region that did not reopen, which an editor
/// has nowhere to show.
fn formatText(
    gpa: std.mem.Allocator,
    path: []const u8,
    text: []const u8,
    table: *FileTable,
    sink: *Sink,
    stderr: *std.Io.Writer,
) !?[]const u8 {
    const file = try table.add(gpa, .{ .path = path, .text = text });
    const formatting = try fmt.formatSource(gpa, table.get(file), file, sink);

    // Silence here means a declaration stays frozen and nothing says why.
    if (formatting.swallowed_marker) |at| {
        const line = std.mem.count(u8, text[0..at], "\n");
        try stderr.print(
            "note: {s}:{d}: `// linea fmt: on` does not close the region here," ++
                " which reaches to the end of the declaration around it\n",
            .{ path, line },
        );
    }

    return formatting.text;
}

fn reportDiagnostics(
    gpa: std.mem.Allocator,
    table: *FileTable,
    sink: *Sink,
    stderr: *std.Io.Writer,
    use_color: render.Color,
    error_format: driver.ErrorFormat,
) !void {
    if (sink.items().len == 0) return;
    try table.buildMaps(gpa);
    switch (error_format) {
        .human => try render.renderAll(stderr, table, sink, .{ .color = use_color }),
        .json => try render_json.renderAllJson(stderr, table, sink),
    }
}

/// Whether a file records what formatting does to it.
///
/// Such a file is written badly on purpose -- it is the input half of a case
/// whose `.fmt` golden is the output half -- so formatting it destroys the
/// case. The conformance suite already exempts these from the gate requiring
/// every other file to be formatted; this is the same rule, applied by the
/// command rather than by the suite, so that `linea fmt .` cannot quietly undo
/// what the goldens record.
///
/// Which stem the golden sits at is asked of `corpus`, because a case of
/// several files is named by its directory, an example's goldens sit under
/// `tests/examples/`, and the runner opens the golden under that name.
fn recordsItsOwnFormatting(gpa: std.mem.Allocator, io: std.Io, path: []const u8) bool {
    const stem = (corpus.goldenStemOf(gpa, path) catch return false) orelse return false;
    const golden = std.mem.concat(gpa, u8, &.{ stem, ".fmt" }) catch return false;
    const file = std.Io.Dir.cwd().openFile(io, golden, .{}) catch return false;
    file.close(io);
    return true;
}

/// Every `.lin` at or below a path. A directory is walked recursively; a file
/// is taken as given, whatever it is named. A file recording its own
/// formatting is skipped either way.
fn collectLineaFiles(
    gpa: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    out: *std.ArrayList([]const u8),
) !void {
    var dir = std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch {
        if (!recordsItsOwnFormatting(gpa, io, path)) try out.append(gpa, path);
        return;
    };
    defer dir.close(io);

    var walker = try dir.walk(gpa);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.basename, ".lin")) continue;
        const joined = try std.fs.path.join(gpa, &.{ path, entry.path });
        if (recordsItsOwnFormatting(gpa, io, joined)) continue;
        try out.append(gpa, joined);
    }
}
