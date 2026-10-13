//! The command line, described once.
//!
//! Usage text and option validation are generated from the same table, so a
//! command cannot advertise an option it rejects or accept one it does not
//! document. That is the whole reason this exists: the two were separate lists
//! before, and an option applying to one command was silently tolerated by
//! every other.
//!
//! Deliberately not a general argument parser. Every option here is `--name`,
//! `--name=value`, or a short flag taking the next argument, and the matching
//! is a handful of comparisons. What was missing was never parsing power -- it
//! was saying which options belong to which command.

const std = @import("std");
const testing = std.testing;

pub const Arity = enum {
    /// Present or absent: `--keep`.
    flag,
    /// Takes a value, written `--name=value` or as the following argument.
    value,
};

pub const Option = struct {
    name: []const u8,
    arity: Arity,
    /// Shown after the name in usage: `<path>`, `auto|always|never`.
    metavar: []const u8 = "",
    help: []const u8,

    fn width(self: Option) usize {
        return self.name.len + if (self.metavar.len == 0)
            0
        else
            self.metavar.len + 1;
    }
};

pub const Command = struct {
    /// What the command is, for a caller dispatching on it.
    ///
    /// A tag rather than the name, so a dispatch is a switch the compiler
    /// checks for exhaustiveness instead of a run of string comparisons that
    /// restate this table. A command added to the table and to nothing else
    /// used to compile and do nothing.
    tag: Tag,
    name: []const u8,
    /// What it takes besides options: `<file>`, `<path>...`.
    operand: []const u8,
    help: []const u8,
    options: []const Option = &.{},
    /// Whether this command accepts the shared diagnostic options.
    common_options: bool = true,
    /// A debugging aid rather than part of the compiler's contract. Listed
    /// apart in usage, under a heading saying its output may change.
    debug: bool = false,
    /// Whether a bare `--` ends this command's arguments and hands the rest to
    /// whatever it runs.
    ///
    /// Declared per command rather than accepted everywhere, because for a
    /// command that runs nothing there is nobody to hand them to: `--` would be
    /// an operand it silently ignored. The words after it are not parsed at
    /// all, which is the point -- a program's own `-v` is its business, and a
    /// compiler that read it would take it.
    passthrough: bool = false,
};

/// Every command the compiler offers. The spelling lives in the table beside
/// it; this is what a dispatch matches on.
pub const Tag = enum {
    run,
    check,
    emit_mlir,
    build,
    @"test",
    fmt,
    lsp,
    init,
    dump_tokens,
    dump_ast,
    dump_expanded,
    dump_mir,
    dump_inferred,
    dump_mono,
    dump_asm,
};

pub const Spec = struct {
    commands: []const Command,
    /// Shared options for commands that accept diagnostic configuration.
    common: []const Option,

    pub fn find(self: Spec, name: []const u8) ?*const Command {
        for (self.commands) |*c| {
            if (std.mem.eql(u8, c.name, name)) return c;
        }
        return null;
    }

    /// Which command declares an option, if any does. What makes "`check` does
    /// not take `-o`" possible rather than a flat "unknown option".
    pub fn declaredBy(self: Spec, option: []const u8) ?*const Command {
        for (self.commands) |*c| {
            for (c.options) |o| {
                if (std.mem.eql(u8, o.name, option)) return c;
            }
        }
        return null;
    }

    /// Help for one command alone. What a user gets when that command was
    /// named but used wrongly: the whole list would bury the one line they
    /// need.
    pub fn writeCommandUsage(
        self: Spec,
        w: *std.Io.Writer,
        cmd: *const Command,
    ) std.Io.Writer.Error!void {
        try w.print("usage: linea {s}", .{cmd.name});
        if (cmd.operand.len > 0) try w.print(" {s}", .{cmd.operand});
        if (cmd.options.len > 0 or (cmd.common_options and self.common.len > 0))
            try w.writeAll(" [options]");
        try w.print("\n\n{s}\n", .{cmd.help});
        if (cmd.options.len > 0) {
            try w.writeAll("\noptions:\n");
            for (cmd.options) |o| try writeOption(w, o, 2, 28);
        }
        if (cmd.common_options and self.common.len > 0) {
            try w.writeAll("\ncommon:\n");
            for (self.common) |o| try writeOption(w, o, 2, 28);
        }
    }

    pub fn writeUsage(self: Spec, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.writeAll("usage: linea <command> [options]\n\ncommands:\n");
        for (self.commands) |c| {
            if (c.debug) continue;
            try writeCommandLine(w, c);
        }

        var any_debug = false;
        for (self.commands) |c| any_debug = any_debug or c.debug;
        if (any_debug) {
            try w.writeAll("\ndebugging (output has no stability guarantee):\n");
            for (self.commands) |c| {
                if (!c.debug) continue;
                try writeCommandLine(w, c);
            }
        }

        try w.writeAll("\ncommon:\n");
        for (self.common) |o| try writeOption(w, o, 2, 28);
    }
};

/// A short option takes its value as the next argument; a long one joins it
/// with `=`. Which is which follows from the name, so neither the table nor a
/// caller has to say.
fn isShort(o: Option) bool {
    return o.name.len == 2 and o.name[0] == '-' and o.name[1] != '-';
}

fn separator(o: Option) []const u8 {
    return if (isShort(o)) " " else "=";
}

fn writeCommandLine(w: *std.Io.Writer, c: Command) std.Io.Writer.Error!void {
    try w.print("  {s} {s}", .{ c.name, c.operand });
    try pad(w, 2 + c.name.len + 1 + c.operand.len, 22);
    try w.print("{s}\n", .{c.help});
    for (c.options) |o| try writeOption(w, o, 6, 28);
}

fn writeOption(
    w: *std.Io.Writer,
    o: Option,
    indent: usize,
    to: usize,
) std.Io.Writer.Error!void {
    try w.splatByteAll(' ', indent);
    try w.writeAll(o.name);
    if (o.metavar.len > 0) try w.print("{s}{s}", .{ separator(o), o.metavar });
    try pad(w, indent + o.width(), to);
    try w.print("{s}\n", .{o.help});
}

fn pad(w: *std.Io.Writer, written: usize, to: usize) std.Io.Writer.Error!void {
    try w.splatByteAll(' ', if (written >= to) 1 else to - written);
}

pub const Item = union(enum) {
    operand: []const u8,
    option: struct { name: []const u8, value: []const u8 },
};

pub const Problem = union(enum) {
    unknown: []const u8,
    /// Declared, but by a different command. Both names are carried: the one
    /// the user typed is what the message must lead with, and the one that
    /// owns the option is what tells them where to put it.
    wrong_command: struct {
        option: []const u8,
        used_with: []const u8,
        belongs_to: []const u8,
    },
    missing_value: []const u8,
    unexpected_value: []const u8,

    pub fn report(self: Problem, w: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self) {
            .unknown => |name| try w.print("error: unknown option '{s}'\n", .{name}),
            .wrong_command => |x| try w.print(
                "error: `{s}` does not take `{s}` -- it belongs to `{s}`\n",
                .{ x.used_with, x.option, x.belongs_to },
            ),
            .missing_value => |name| try w.print("error: {s} needs a value\n", .{name}),
            .unexpected_value => |name| try w.print("error: {s} takes no value\n", .{name}),
        }
    }
};

/// Walks one command's arguments, resolving each against that command's
/// options and the common ones.
pub const Iterator = struct {
    spec: Spec,
    command: *const Command,
    args: []const []const u8,
    index: usize = 0,
    problem: ?Problem = null,
    /// What followed a bare `--`, for a command that declares a passthrough.
    ///
    /// Empty where none was written, which is not the same question as whether
    /// the separator appeared: `run p.lin --` hands over no arguments and is
    /// not a mistake. Nothing reads the difference today, and a caller that
    /// needs it should ask this iterator rather than scan the arguments again.
    rest: []const []const u8 = &.{},

    pub fn next(self: *Iterator) ?Item {
        if (self.index >= self.args.len) return null;
        const arg = self.args[self.index];
        self.index += 1;

        // Everything after the separator belongs to whatever the command runs,
        // so iteration ends here rather than reporting the words as operands.
        // Read before the `-` test below: `--` begins with one and is not an
        // option, and a lookup would report it unknown.
        if (self.command.passthrough and std.mem.eql(u8, arg, "--")) {
            self.rest = self.args[self.index..];
            self.index = self.args.len;
            return null;
        }

        if (arg.len == 0 or arg[0] != '-') return .{ .operand = arg };

        const name, const inline_value = split(arg);
        const found = self.lookup(name) orelse {
            // A single-letter option takes its value attached as well as
            // separated -- `-O2` is `-O 2` -- because that is how such a
            // flag is spelled everywhere else a user has typed one.
            if (name.len > 2 and name[1] != '-' and inline_value == null) {
                if (self.lookup(name[0..2])) |short| {
                    if (short.arity == .value) {
                        return .{ .option = .{ .name = name[0..2], .value = name[2..] } };
                    }
                }
            }
            self.problem = if (self.spec.declaredBy(name)) |c| .{
                .wrong_command = .{
                    .option = name,
                    .used_with = self.command.name,
                    .belongs_to = c.name,
                },
            } else .{ .unknown = name };
            return null;
        };

        if (found.arity == .flag) {
            if (inline_value != null) {
                self.problem = .{ .unexpected_value = name };
                return null;
            }
            return .{ .option = .{ .name = name, .value = "" } };
        }

        if (inline_value) |v| return .{ .option = .{ .name = name, .value = v } };
        if (self.index >= self.args.len) {
            self.problem = .{ .missing_value = name };
            return null;
        }
        const v = self.args[self.index];
        self.index += 1;
        return .{ .option = .{ .name = name, .value = v } };
    }

    fn lookup(self: *const Iterator, name: []const u8) ?Option {
        for (self.command.options) |o| {
            if (std.mem.eql(u8, o.name, name)) return o;
        }
        if (self.command.common_options) {
            for (self.spec.common) |o| {
                if (std.mem.eql(u8, o.name, name)) return o;
            }
        }
        return null;
    }
};

/// `--name=value` split into its parts; the value is null where none was
/// joined on.
fn split(arg: []const u8) struct { []const u8, ?[]const u8 } {
    if (std.mem.indexOfScalar(u8, arg, '=')) |at| {
        return .{ arg[0..at], arg[at + 1 ..] };
    }
    return .{ arg, null };
}

const test_spec: Spec = .{
    .commands = &.{
        .{
            .tag = .build,
            .name = "build",
            .operand = "<file>",
            .help = "compile to an executable",
            .options = &.{
                .{ .name = "-o", .arity = .value, .metavar = "<path>", .help = "output path" },
                .{ .name = "-O", .arity = .value, .metavar = "0|2", .help = "optimisation level" },
                .{ .name = "--keep", .arity = .flag, .help = "keep intermediates" },
            },
        },
        .{ .tag = .check, .name = "check", .operand = "<file>", .help = "diagnostics only" },
    },
    .common = &.{
        .{
            .name = "--color",
            .arity = .value,
            .metavar = "auto|always|never",
            .help = "colour diagnostics",
        },
    },
};

fn iterate(cmd: []const u8, args: []const []const u8) Iterator {
    return .{ .spec = test_spec, .command = test_spec.find(cmd).?, .args = args };
}

test "an operand is distinguished from an option" {
    var it = iterate("check", &.{"main.lin"});
    try testing.expectEqualStrings("main.lin", it.next().?.operand);
    try testing.expect(it.next() == null);
    try testing.expect(it.problem == null);
}

test "an option belonging to another command names that command" {
    var it = iterate("check", &.{ "main.lin", "-o", "out" });
    _ = it.next();
    try testing.expect(it.next() == null);
    // The message must lead with the command the user typed, not the one that
    // owns the option.
    try testing.expectEqualStrings("check", it.problem.?.wrong_command.used_with);
    try testing.expectEqualStrings("build", it.problem.?.wrong_command.belongs_to);
    try testing.expectEqualStrings("-o", it.problem.?.wrong_command.option);
}

test "an option no command declares is unknown" {
    var it = iterate("check", &.{"--wat"});
    try testing.expect(it.next() == null);
    try testing.expectEqualStrings("--wat", it.problem.?.unknown);
}

test "a long option takes its value joined and a short one takes the next" {
    var it = iterate("build", &.{ "--color=never", "-o", "a.out" });
    const first = it.next().?.option;
    try testing.expectEqualStrings("--color", first.name);
    try testing.expectEqualStrings("never", first.value);
    const second = it.next().?.option;
    try testing.expectEqualStrings("-o", second.name);
    try testing.expectEqualStrings("a.out", second.value);
}

test "a short option takes its value attached" {
    var it = iterate("build", &.{ "-O2", "-oout" });
    const first = it.next().?.option;
    try testing.expectEqualStrings("-O", first.name);
    try testing.expectEqualStrings("2", first.value);
    const second = it.next().?.option;
    try testing.expectEqualStrings("-o", second.name);
    try testing.expectEqualStrings("out", second.value);
}

test "a value option at the end of the arguments is reported" {
    var it = iterate("build", &.{"-o"});
    try testing.expect(it.next() == null);
    try testing.expectEqualStrings("-o", it.problem.?.missing_value);
}

test "a flag rejects an attached value" {
    var it = iterate("build", &.{"--keep=false"});
    try testing.expect(it.next() == null);
    try testing.expectEqualStrings("--keep", it.problem.?.unexpected_value);
}

test "a common option is accepted by a command with diagnostic options" {
    var it = iterate("check", &.{"--color=always"});
    try testing.expectEqualStrings("always", it.next().?.option.value);
    try testing.expect(it.problem == null);
}

test "one command's help names only that command" {
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try test_spec.writeCommandUsage(&out.writer, test_spec.find("check").?);

    const text = out.written();
    try testing.expect(std.mem.indexOf(u8, text, "usage: linea check") != null);
    // `build`'s options are not this command's business.
    try testing.expect(std.mem.indexOf(u8, text, "--keep") == null);
    // Common options still are.
    try testing.expect(std.mem.indexOf(u8, text, "--color") != null);
}

test "usage lists each option under the command that takes it" {
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try test_spec.writeUsage(&out.writer);

    const text = out.written();
    // The property worth asserting: an option appears beneath its own command
    // rather than in a flat list, which is what the shared table buys.
    const build_at = std.mem.indexOf(u8, text, "build").?;
    const keep_at = std.mem.indexOf(u8, text, "--keep").?;
    const check_at = std.mem.indexOf(u8, text, "check").?;
    try testing.expect(build_at < keep_at);
    try testing.expect(keep_at < check_at);
}
