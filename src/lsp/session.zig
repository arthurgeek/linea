const std = @import("std");
const lsp = @import("lsp");
const server = @import("server.zig");
const uri = @import("uri.zig");
const loader = @import("../driver/loader.zig");
const test_library = @import("../driver/test_library.zig");

threadlocal var replay_log_writer: ?*std.Io.Writer = null;

fn replayLogErr(comptime format: []const u8, args: anytype) void {
    const writer = replay_log_writer orelse @panic("missing replay log writer");
    writer.print("error: " ++ format ++ "\n", args) catch
        @panic("write to an in-memory log cannot fail");
}

/// A `lsp.Transport` backed by a fixed script rather than a pipe: each read
/// hands out the script's next non-blank line, and each write is appended to
/// `out`. What a session golden is about is what the server answers, and
/// driving it through the same `Transport` interface a real client would
/// means the golden covers dispatch and response serialization, not just a
/// handler called directly.
const ScriptTransport = struct {
    transport: lsp.Transport,
    lines: std.mem.SplitIterator(u8, .scalar),
    out: *std.Io.Writer,

    fn init(requests: []const u8, out: *std.Io.Writer) ScriptTransport {
        return .{
            .transport = .{ .vtable = &.{
                .readJsonMessage = readJsonMessage,
                .writeJsonMessage = writeJsonMessage,
            } },
            .lines = std.mem.splitScalar(u8, requests, '\n'),
            .out = out,
        };
    }

    /// The script's next request, or `error.EndOfStream` once it is
    /// exhausted -- the same error a real transport reports at end of input,
    /// which is what lets a script omit a trailing `exit` notification.
    fn readJsonMessage(
        transport: *lsp.Transport,
        io: std.Io,
        allocator: std.mem.Allocator,
    ) lsp.Transport.ReadError![]u8 {
        _ = io;
        const self: *ScriptTransport = @fieldParentPtr("transport", transport);
        while (self.lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \r\t");
            if (trimmed.len == 0) continue;
            return try allocator.dupe(u8, trimmed);
        }
        return error.EndOfStream;
    }

    fn writeJsonMessage(
        transport: *lsp.Transport,
        io: std.Io,
        json_message: []const u8,
    ) lsp.Transport.WriteError!void {
        _ = io;
        const self: *ScriptTransport = @fieldParentPtr("transport", transport);
        self.out.writeAll(json_message) catch @panic("write to an in-memory buffer cannot fail");
        self.out.writeByte('\n') catch @panic("write to an in-memory buffer cannot fail");
    }
};

/// Replays a script of newline-delimited JSON-RPC requests against a server
/// rooted at `dir`, writing each response as one line.
///
/// Drives the real `lsp.basic_server.run` loop over an in-process transport
/// rather than a subprocess: a subprocess would add framing, scheduling and a
/// second failure mode to a test that is asking about neither, while an
/// in-process `Transport` still exercises the same dispatch a pipe would.
///
/// The script need not end with an `exit` notification -- `run` reads past
/// the last request looking for another, the script reports that as
/// `error.EndOfStream`, and that is where replay stops.
///
/// Returns the status the process would have left with, which is the
/// handler's own answer and not a second reading of the script.
pub fn replay(
    gpa: std.mem.Allocator,
    io: std.Io,
    /// The checked standard library the server resumes each module from.
    library: *const loader.CheckedLibrary,
    dir: []const u8,
    requests: []const u8,
    w: *std.Io.Writer,
    log_writer: ?*std.Io.Writer,
) !u8 {
    const script_text = try rewriteUris(gpa, requests, dir, .absolute);
    defer gpa.free(script_text);

    var answers: std.Io.Writer.Allocating = .init(gpa);
    defer answers.deinit();

    var script = ScriptTransport.init(script_text, &answers.writer);
    var handler: server.Handler = .{
        .gpa = gpa,
        .region_backing = gpa,
        .library = library,
        .io = io,
        .transport = &script.transport,
        // The case's own directory, which is the workspace a script names
        // files in. Without it the search for a program's manifest would rise
        // out of the corpus and into whatever sits above the checkout. Owned,
        // as the one `initialize` replaces it with is.
        .root = try gpa.dupe(u8, dir),
        .documents = .{ .gpa = gpa },
    };
    defer handler.deinit();
    if (log_writer) |captured| {
        replay_log_writer = captured;
        defer replay_log_writer = null;
        lsp.basic_server.run(io, gpa, &script.transport, &handler, replayLogErr) catch |err| switch (err) {
            error.EndOfStream => {},
            else => return err,
        };
    } else {
        lsp.basic_server.run(io, gpa, &script.transport, &handler, std.log.err) catch |err| switch (err) {
            error.EndOfStream => {},
            else => return err,
        };
    }

    const stable = try rewriteUris(gpa, answers.written(), dir, .relative);
    defer gpa.free(stable);
    try w.writeAll(stable);
    return handler.exitStatus();
}

test "a session captures replay errors" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer gpa.free(dir);
    const asked =
        \\{
        \\
    ;
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    var logs: std.Io.Writer.Allocating = .init(gpa);
    defer logs.deinit();

    _ = try replay(gpa, std.testing.io, test_library.get(), dir, asked, &out.writer, &logs.writer);

    try std.testing.expectEqualStrings(
        "error: Failed to handle message: error.UnexpectedEndOfInput\n",
        logs.written(),
    );
    try std.testing.expectEqualStrings(
        "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32700,\"message\":\"UnexpectedEndOfInput\"}}\n",
        out.written(),
    );
}

test "a session releases the workspace the client named" {
    const gpa = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer gpa.free(dir);

    // Twice, because the second `initialize` replaces what the first held and
    // there is nobody else to release it.
    const asked =
        \\{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{},"workspaceFolders":[{"uri":"file:///tmp/one","name":"one"}]}}
        \\{"jsonrpc":"2.0","id":2,"method":"initialize","params":{"capabilities":{},"workspaceFolders":[{"uri":"file:///tmp/two","name":"two"}]}}
        \\
    ;

    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    _ = try replay(gpa, std.testing.io, test_library.get(), dir, asked, &out.writer, null);
}

test "a session ends where the client said to, and leaves with what it said" {
    const gpa = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "main.lin",
        .data = "fn main() -> UInt8 {\n    0\n}\n",
    });
    const dir = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer gpa.free(dir);

    const asked =
        \\{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}
        \\{"jsonrpc":"2.0","method":"exit"}
        \\{"jsonrpc":"2.0","id":2,"method":"shutdown"}
        \\
    ;

    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();

    // `exit` with no `shutdown` before it ends a session the server was in the
    // middle of, which the protocol asks it to leave saying.
    try std.testing.expectEqual(@as(u8, 1), try replay(gpa, std.testing.io, test_library.get(), dir, asked, &out.writer, null));

    // And the request after it was never read.
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "\"id\":2") == null);
}

/// A session ends whatever the client sent, and the corpus says over what.
///
/// The conformance runner asks this of every program it holds, with a script
/// each of those programs is well-formed for. This asks it of the other half:
/// the messages themselves are arbitrary bytes, so a truncated JSON value, a
/// method nobody implements and a `params` of the wrong shape all reach the
/// same loop a client does.
fn fuzzSession(_: void, smith: *std.testing.Smith) anyerror!void {
    var buf: [512]u8 = undefined;
    const len = smith.slice(&buf);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // A program for the messages to be about. A script that names no file is
    // still a session, but one that names this reaches everything behind the
    // door as well as the door.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "main.lin",
        .data = "fn main() -> UInt8 {\n    0\n}\n",
    });
    const dir = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}", .{tmp.sub_path});

    var out: std.Io.Writer.Allocating = .init(gpa);
    var logs: std.Io.Writer.Allocating = .init(gpa);
    _ = try replay(gpa, std.testing.io, test_library.get(), dir, buf[0..len], &out.writer, &logs.writer);
}

test "fuzz: a session of any messages ends" {
    // Every input this property has ever failed on, replayed before any new
    // one is tried -- so a crash the fuzzer found once cannot come back
    // unnoticed, and a search starts where the last one got to.
    try std.testing.fuzz({}, fuzzSession, .{ .corpus = @import("fuzz_corpus").lsp });
}

test "every input the fuzzer found for a session still passes" {
    for (@import("fuzz_corpus").lsp) |input| {
        var smith: std.testing.Smith = .{ .in = input };
        try fuzzSession({}, &smith);
    }
}

/// Which way a message's file names are being spelled: as the absolute
/// `file://` URIs a client sends and a server answers, or as the names
/// relative to the case's own directory that a script and a golden hold.
const Spelling = enum { absolute, relative };

/// Every file name a JSON-RPC message carries, respelled.
///
/// A script and a golden name a file the way the case does -- `main.lin`,
/// beside the script that opens it -- because the case is the same bytes on
/// every machine and an absolute path is not. A client names it by an
/// absolute `file://` URI. Translating between the two here, rather than
/// writing either spelling into the other's file, keeps the server seeing
/// exactly what an editor sends while the golden stays comparable anywhere.
///
/// Which strings those are is decided by the direction, because the two
/// directions have different evidence. Going out, a script names files in
/// `"uri"` fields and nowhere else, and the names it writes are relative, so
/// nothing about the value marks it. Coming back, every file name the server
/// writes carries the scheme -- and one of them is not a field value at all: a
/// workspace edit is keyed by the document it changes, so the URI is an object
/// key. Matching the scheme rather than the field is what reaches it.
///
/// It goes through `uri.uriOf` and `uri.pathOf`, so the conversion a real
/// session depends on is the one every session case exercises rather than a
/// substitution that resembles it.
fn rewriteUris(
    gpa: std.mem.Allocator,
    message: []const u8,
    dir: []const u8,
    to: Spelling,
) ![]u8 {
    const field = "\"uri\"";
    const scheme = "\"file://";
    const opens: []const u8 = switch (to) {
        .absolute => field,
        .relative => scheme,
    };

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);

    var rest = message;
    while (std.mem.indexOf(u8, rest, opens)) |at| {
        // Where the name itself begins. Coming back, the match is the name's
        // own opening quote; going out, the field name is followed by a colon
        // whose spacing JSON puts no constraint on and a script is written by
        // hand -- matching the punctuation literally left a `"uri": "x"`
        // unrewritten, the server looking for a file named by a relative path,
        // and a case that published nothing while passing.
        var value_at = at + 1;
        if (to == .absolute) {
            value_at = at + field.len;
            while (value_at < rest.len and (rest[value_at] == ' ' or rest[value_at] == ':')) value_at += 1;
            if (value_at >= rest.len or rest[value_at] != '"') break;
            value_at += 1;
        }

        const end = std.mem.indexOfScalarPos(u8, rest, value_at, '"') orelse break;
        try out.appendSlice(gpa, rest[0..value_at]);

        const written = rest[value_at..end];
        switch (to) {
            .absolute => {
                const path = try std.fs.path.join(gpa, &.{ dir, written });
                defer gpa.free(path);
                const absolute = try uri.uriOf(gpa, path);
                defer gpa.free(absolute);
                try out.appendSlice(gpa, absolute);
            },
            .relative => {
                const path = try uri.pathOf(gpa, written);
                defer gpa.free(path);
                // Anything outside the case's directory keeps the name it
                // arrived under: a golden that silently shortened it would
                // hide a server answering about a file the case never named.
                try out.appendSlice(gpa, if (std.mem.startsWith(u8, path, dir) and path.len > dir.len)
                    path[dir.len + 1 ..]
                else
                    path);
            },
        }
        rest = rest[end..];
    }
    try out.appendSlice(gpa, rest);
    return out.toOwnedSlice(gpa);
}
