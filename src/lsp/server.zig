const std = @import("std");
const lsp = @import("lsp");
const Documents = @import("documents.zig").Documents;
const loader = @import("../driver/loader.zig");
const slow_tests = @import("../support/slow_tests.zig");
const analysis = @import("analysis.zig");
const publish = @import("publish.zig");
const tokens = @import("tokens.zig");
const symbols = @import("symbols.zig");
const workspace = @import("workspace.zig");
const fix = @import("fix.zig");
const folding = @import("folding.zig");
const hints = @import("hints.zig");
const definition = @import("definition.zig");
const references = @import("references.zig");
const rename = @import("rename.zig");
const name_case = @import("../support/name_case.zig");
const hover = @import("hover.zig");
const completion = @import("completion.zig");
const uri_mod = @import("uri.zig");
const fmt = @import("../fmt/fmt.zig");
const Sink = @import("../diagnostics/sink.zig").Sink;
const source_mod = @import("../support/source.zig");
const test_library = @import("../driver/test_library.zig");
const Source = source_mod.Source;

/// The language server's method table.
///
/// `lsp.basic_server.run` reads the framing, parses each message into the
/// protocol's generated types, and calls the method here named for whatever
/// arrived: a public function named `textDocument/didOpen` answers that
/// notification, and so on. A method this struct does not declare is
/// answered automatically -- `null` for a request, silence for a
/// notification -- so a capability is added by adding one method here and
/// widening what `initialize` advertises to match. Nothing here switches on
/// a method name by hand; that dispatch belongs to the generated protocol
/// types, not to an opinion of this module's.
/// A path written as a glob that matches it and nothing else: each character
/// a glob reads as a pattern is put in a class of its own, `[*]`, which every
/// glob the protocol's clients read takes as that character.
fn globLiteral(gpa: std.mem.Allocator, path: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (path) |c| switch (c) {
        '*', '?', '[', ']', '{', '}' => try out.appendSlice(gpa, &.{ '[', c, ']' }),
        else => try out.append(gpa, c),
    };
    return out.toOwnedSlice(gpa);
}

test "a watched path's glob characters match only themselves" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("page[[]1[]].txt", try globLiteral(arena.allocator(), "page[1].txt"));
    try std.testing.expectEqualStrings("a[*][?][{]b[}]", try globLiteral(arena.allocator(), "a*?{b}"));
    try std.testing.expectEqualStrings("templates/page.html", try globLiteral(arena.allocator(), "templates/page.html"));
}

pub const Handler = struct {
    gpa: std.mem.Allocator,
    /// Backing for each retained Analysis, distinct from message/index storage.
    region_backing: std.mem.Allocator,
    /// The standard library, checked once for the session. Every module the
    /// server checks resumes from it, so an edit costs a check of the module
    /// and not of the library as well. Borrowed: it outlives the handler.
    library: *const loader.CheckedLibrary,
    io: std.Io,
    /// Where a notification the server starts is written. Held here because
    /// the loop hands a handler the message it read and nothing else, and
    /// diagnostics are not an answer to a request: they arrive when the
    /// document changed, which is a sentence the server begins.
    transport: *lsp.Transport,
    /// The directory the client opened, and the highest the search for a
    /// program's manifest rises. Empty until `initialize` says, which is
    /// before any document can arrive. Unbounded, a manifest above the
    /// workspace would make every file in it part of somebody else's
    /// program.
    ///
    /// Owned, because it outlives the message that carried it. Empty is not
    /// an allocation, which is what `setRoot` reads it as.
    root: []const u8 = "",
    /// How a position's `character` field counts. Negotiated in `initialize`
    /// from what the client offers; a later capability converts a byte
    /// offset through `lsp.offsets` using exactly this field.
    offset_encoding: lsp.offsets.Encoding = .@"utf-16",
    /// What the editor has open, which the three `textDocument/did*`
    /// notifications keep current.
    documents: Documents,
    /// Whether the client asked for a shutdown before telling the server to
    /// go. The two are one handshake: `exit` after `shutdown` is the ending
    /// both sides agreed on, and `exit` without it ends a session the server
    /// was in the middle of.
    shutdown_asked: bool = false,
    /// Whether the client said `exit`. A session that ended because the pipe
    /// closed did not, which the protocol does not describe and this server
    /// treats as the client having gone away rather than as a failure.
    exit_asked: bool = false,
    /// The module checked most recently, held so that the requests arriving
    /// between two edits cost one check between them rather than one each.
    /// An editor asks for hints on every scroll and an outline on every jump
    /// into a file, and neither changes anything.
    ///
    /// **Bound: one analysis.** A second module replaces this one rather than
    /// joining it, so what a session holds is one module's check however long
    /// it runs and however many files it visits. The bound holds because
    /// nothing here can add a second entry: `check` assigns the field, and it
    /// releases whatever the field held first.
    ///
    /// **Invalidation: the module, not the file.** The key is the entry
    /// `loader.entryOf` resolves a path to, which is the module, so a change
    /// to any file of it drops the analysis of all of it. Keyed by the file a
    /// request named, an edit to a sibling would leave the answer standing --
    /// and a sibling decides it, since a module's files see each other's
    /// declarations and monomorphisation settles a type in one file from a
    /// call in another.
    ///
    /// What can move an answer is a document changing, and every path that
    /// changes one invalidates before it answers -- including a file edited
    /// outside the editor, which the client's watch reports and which drops
    /// the analysis of the module that holds it.
    cached: ?Cached = null,
    /// The analysis of a file of a root no import of its program reaches,
    /// checked with its module as the entry, held beside the program's in
    /// `cached`: deciding that the program does not reach the file reads the
    /// program's analysis, and keeping both means an edit in such a file
    /// costs one check, not the program's again as well.
    alone: ?Cached = null,
    /// What each check last reported for each file it reached, by the
    /// check's key: a program's entry, or the module a file no import reaches
    /// was checked as. A file is published with the union of what every key
    /// reaching it reported, so a check that stops reaching a file takes back
    /// only its own diagnostics, and what an editor shows for a file is what
    /// every check of it reports, whichever ran last.
    ///
    /// **Bound:** the files each key last reached, over the keys the session
    /// has published; publishing one file reads each key once.
    reported: std.StringArrayHashMapUnmanaged(Reported) = .empty,
    /// What every program under the workspace exports, held for the session.
    ///
    /// Built on the first request that reads it, so a session that never asks
    /// never pays for it, and held afterwards because rebuilding it is a walk
    /// of the workspace.
    ///
    /// Disposable derived data. Nothing the compiler decides is read from
    /// here: what a name means is the resolver's answer over the program it
    /// was given, and this holds names from files that program does not
    /// include. That is what makes it safe for this to be stale between a
    /// change and the notification that reports it.
    ///
    /// **Bound: one index, of one workspace.** The root is what it was built
    /// over, so replacing the root releases it -- `initialize` may arrive
    /// twice, and an index of the directory the client has left answers about
    /// programs the session can no longer see.
    index: ?workspace.Index = null,
    /// Whether the client can be asked to watch files, read off the
    /// capabilities `initialize` carried. A capability the client did not
    /// grant is not one to assume.
    watch_offered: bool = false,
    /// Whether the client reads `${1:a}` as a tab stop, read off the
    /// capabilities `initialize` carried. A client that did not say so writes
    /// the placeholder syntax into the buffer verbatim, so it is offered the
    /// name alone.
    snippets: completion.Snippets = .unsupported,
    /// The id of the registration request the server sent, until the client
    /// answers it. A reply carrying any other id answers a request this server
    /// did not send, and settles nothing about the watch.
    watch_asked: ?i64 = null,
    /// Whether the client is watching the workspace's files for this server.
    ///
    /// What it decides is whether the registration is sent again: a session
    /// may be initialized twice, and a client already watching must not be
    /// asked to register the same id a second time.
    watching: bool = false,
    /// How many requests the server has sent the client, which is what names
    /// the next one. The two directions number their requests independently,
    /// so nothing here has to avoid an id the client chose.
    sent: i64 = 0,
    /// The files the client was last asked to watch because the held analysis
    /// embeds them. Owned.
    embeds_watched: std.ArrayList([]const u8) = .empty,

    /// The name the file watch is registered under. The client keys the
    /// registration by it, which is what an unregistration would name.
    const watch_registration = "linea.watchedFiles";
    /// The name the watch of the files the held analysis embeds is registered
    /// under, replaced as the set of files changes.
    const embeds_registration = "linea.embeddedFiles";

    /// One module's analysis with the module it is of.
    /// One check's last report: its program's entry, and for each file it
    /// reached, the diagnostics it reported there as the JSON a client is
    /// sent. Everything, the key it is held under included, lives in `arena`.
    const Reported = struct {
        arena: std.heap.ArenaAllocator,
        entry: []const u8,
        /// The path the check is run again from: the entry for a program's
        /// check, and the open document it was made for for a module's.
        asked: []const u8,
        /// Whether this is a module's check rather than its program's.
        module: bool,
        files: std.StringArrayHashMapUnmanaged([]const []const u8) = .empty,
    };

    const Cached = struct {
        /// The entry the analysis was checked from. Owned, because the
        /// resolution it was copied from lives on a message's arena.
        entry: []u8,
        /// The module checked as the entry, where the analysis is of a file
        /// no import of its program reaches; null for the program itself.
        /// Owned, as `entry` is.
        module: ?[]u8 = null,
        of: analysis.Analysis,
    };

    /// What `initialize` advertises. Read by the same call that checks it
    /// against the methods this struct implements, so the two cannot drift
    /// apart the way a second, independently written literal could.
    const capabilities: lsp.types.ServerCapabilities = .{
        .textDocumentSync = .{ .text_document_sync_options = .{
            .openClose = true,
            .change = .Full,
        } },
        .semanticTokensProvider = .{ .semantic_tokens_options = .{
            .legend = tokens.legend,
            .full = .{ .bool = true },
        } },
        .documentFormattingProvider = .{ .bool = true },
        .documentSymbolProvider = .{ .bool = true },
        .foldingRangeProvider = .{ .bool = true },
        // Written out rather than as a bare `true`, which the protocol reads
        // as offering `inlayHint/resolve` too. A hint here carries everything
        // it has the moment it is sent, so there is nothing to resolve.
        .inlayHintProvider = .{ .inlay_hint_options = .{ .resolveProvider = false } },
        .definitionProvider = .{ .bool = true },
        .hoverProvider = .{ .bool = true },
        .referencesProvider = .{ .bool = true },
        .documentHighlightProvider = .{ .bool = true },
        // Written as a bare `true`, which the protocol reads as offering
        // `textDocument/rename` alone. A `prepareRename` would tell a client
        // in advance which names are refused, and every reason one is refused
        // here is a reason `rename` itself gives -- a second place deciding it
        // could disagree with the answer that does the work.
        .renameProvider = .{ .bool = true },
        // The kinds written out rather than a bare `true`, so a client
        // asking only for refactorings does not ask this server at all. A
        // quick fix is the whole of what it offers: every action it answers
        // resolves a diagnostic the client handed back.
        .codeActionProvider = .{ .code_action_options = .{ .codeActionKinds = &.{.quickfix} } },
        // Written out rather than as a bare `true`, which the protocol reads as
        // offering `completionItem/resolve` too. An item carries everything it
        // has the moment it is sent -- a type the analysis already holds -- so
        // there is nothing a round trip could add.
        .completionProvider = .{ .resolveProvider = false },
    };

    pub fn initialize(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.InitializeParams,
    ) !lsp.types.InitializeResult {
        _ = arena;
        handler.offset_encoding = negotiatedEncoding(params.capabilities);
        handler.watch_offered = watchesFiles(params.capabilities);
        handler.snippets = readsSnippets(params.capabilities);
        const root_uri = if (params.workspaceFolders) |folders|
            (if (folders.len > 0) folders[0].uri else params.rootUri)
        else
            params.rootUri;
        // Held for the session, so it outlives this message's arena.
        if (root_uri) |uri| handler.setRoot(try uri_mod.pathOf(handler.gpa, uri));

        // Advertises exactly the methods this struct implements: a
        // capability offered here with no method to answer it fails the
        // build rather than the client, and a method answered here with no
        // capability advertising it fails the same way.
        comptime lsp.basic_server.validateServerCapabilities(Handler, capabilities);

        // The one capability that is not a constant, because it is the
        // client's own answer coming back. A server that omits it is read as
        // reporting UTF-16, so a client offering UTF-8 first counted every
        // column after the first non-ASCII byte on a line in the wrong units
        // and said nothing was wrong.
        var advertised = capabilities;
        advertised.positionEncoding = switch (handler.offset_encoding) {
            .@"utf-8" => .@"utf-8",
            .@"utf-16" => .@"utf-16",
            .@"utf-32" => .@"utf-32",
        };
        return .{ .capabilities = advertised };
    }

    /// The client asking the server to wind down, which it answers with
    /// nothing. Nothing is released here: the process is about to end, and a
    /// server that freed its state and then answered another request would be
    /// answering from nothing.
    ///
    /// Declared rather than left to the automatic `null`, because whether it
    /// arrived is what decides the status `exit` leaves with.
    pub fn shutdown(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: void,
    ) ?void {
        _ = arena;
        _ = params;
        handler.shutdown_asked = true;
        return null;
    }

    /// The client telling the server to go.
    ///
    /// Declared so that the loop's dispatch reaches it: the loop ends the
    /// session on a notification it recognises, and it recognises exactly the
    /// methods this struct declares. Undeclared, `exit` arrived at the
    /// catch-all, the loop read on, and a client that kept the pipe open
    /// across a restart left the old server running.
    pub fn exit(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: void,
    ) void {
        _ = arena;
        _ = params;
        handler.exit_asked = true;
    }

    /// What the process leaves with.
    ///
    /// The protocol asks for a failing status where `exit` arrived without a
    /// `shutdown` before it: the client ended a session the server was in the
    /// middle of, and a supervisor is entitled to know the difference.
    pub fn exitStatus(handler: *const Handler) u8 {
        return if (handler.exit_asked and !handler.shutdown_asked) 1 else 0;
    }

    /// The client has finished processing the `initialize` response and is
    /// ready for the server to talk first.
    ///
    /// Which is what this is for: a registration is a request, and a request
    /// sent from `initialize` would reach a client still waiting for the
    /// answer to its own.
    pub fn initialized(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.InitializedParams,
    ) !void {
        _ = params;
        try handler.watchFiles(arena);
    }

    /// A reply to a request the server sent the client.
    ///
    /// The one request this server sends is the file-watch registration, and
    /// this reply is how it learns whether the client took it. Matched by id,
    /// because a client may answer a request this server did not send -- and
    /// reading that as the registration's answer would record a watch nobody
    /// granted, leaving the index quietly stale for the session.
    pub fn onResponse(
        handler: *Handler,
        arena: std.mem.Allocator,
        response: lsp.JsonRPCMessage.Response,
    ) void {
        _ = arena;
        const asked = handler.watch_asked orelse return;
        const answered = response.id orelse return;
        if (!lsp.types.ID.eql(answered, .{ .number = asked })) return;

        handler.watch_asked = null;
        handler.watching = switch (response.result_or_error) {
            .result => true,
            .@"error" => false,
        };
    }

    /// A file under the workspace changed outside the editor.
    ///
    /// What the named files contribute to the index is replaced, and nothing
    /// else is: a changed source file is never a walk. An analysis affected by
    /// a changed file is dropped so the next request checks it again;
    /// publishing from here instead would check one module
    /// per notification, and a checkout delivers one notification per file it
    /// touched. A changed manifest is the exception on both counts: the
    /// index is dropped whole and walked again by the request that next reads
    /// it, and the held program is checked and published once.
    ///
    /// **Bound: the files the notification names.** Per file, invalidation
    /// checks the loaded files and module directories. A prepared export index
    /// also resolves the owning program, lexes and parses the changed text,
    /// and compares its exports in one index pass before replacing changed
    /// rows. An index that was never built needs no refresh work.
    pub fn @"workspace/didChangeWatchedFiles"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.workspace.did_change_watched_files.Params,
    ) !void {
        // A file the held program embeds, and a manifest, are nothing a
        // document event follows the change of: what the editor shows is
        // checked again and published from here, or it stays as it was. An
        // embedded file belongs to the held program, which is published once
        // however many of its files the notification names. A manifest may
        // decide what any program holds, whichever is held when the
        // notification arrives and wherever in it the manifest is named, so
        // the program of every open document is published.
        var republish: ?[]const u8 = null;
        var manifest_changed = false;
        for (params.changes) |change| {
            const path = try uri_mod.pathOf(arena, change.uri);
            if (republish == null) republish = try handler.embeddedBy(arena, path);
            if (std.mem.eql(u8, std.fs.path.basename(path), loader.manifest_name)) manifest_changed = true;
            try handler.invalidate(arena, path);
            try handler.freshen(arena, path);
        }
        if (manifest_changed) return handler.reportOpen(arena);
        if (republish) |entry| try handler.refresh(arena, entry, true);
        // A source changed on disk is what every check that read it reads
        // again.
        for (params.changes) |change| {
            const path = try uri_mod.pathOf(arena, change.uri);
            if (std.mem.endsWith(u8, path, ".lin")) try handler.refresh(arena, path, false);
        }
    }

    pub fn @"textDocument/didOpen"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.TextDocument.DidOpenParams,
    ) !void {
        const document = params.textDocument;
        const path = try uri_mod.pathOf(arena, document.uri);
        const change = try handler.documents.set(path, document.text);
        if (!handler.cachedTextMatches(path, document.text)) try handler.invalidate(arena, path);
        if (change != .unchanged) try handler.freshen(arena, path);
        try handler.refresh(arena, path, true);
    }

    /// Full-text sync only, so `contentChanges` holds whole documents -- the
    /// shape `initialize` advertised is the only one a compliant client sends.
    /// Applied in order, the last whole document is the text.
    ///
    /// The notification is validated before anything changes, and refused
    /// whole: a document `didOpen` never opened is `error.DocumentNotOpen`, and
    /// a change naming the region it replaces is `error.PartialChangeUnsupported`,
    /// which this server cannot apply. Applied in part, or to a document opened
    /// by the change itself, the text the server held would no longer be the
    /// text the editor held, and everything below would republish diagnostics
    /// about a document nobody was looking at.
    pub fn @"textDocument/didChange"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.TextDocument.DidChangeParams,
    ) !void {
        const path = try uri_mod.pathOf(arena, params.textDocument.uri);
        if (!handler.documents.open.contains(path)) return error.DocumentNotOpen;
        var last: ?[]const u8 = null;
        for (params.contentChanges) |change| switch (change) {
            .text_document_content_change_whole_document => |whole| last = whole.text,
            .text_document_content_change_partial => return error.PartialChangeUnsupported,
        };
        const changed = if (last) |whole| (try handler.documents.set(path, whole)) != .unchanged else false;
        const text = handler.documents.open.get(path).?;
        if (!handler.cachedTextMatches(path, text)) try handler.invalidate(arena, path);
        if (changed) try handler.freshen(arena, path);
        try handler.refresh(arena, path, true);
    }

    pub fn @"textDocument/didClose"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.TextDocument.DidCloseParams,
    ) !void {
        const path = try uri_mod.pathOf(arena, params.textDocument.uri);
        handler.documents.close(path);
        // The buffer is gone, so the module now reads that file from disk, and
        // so does what the index holds for it. What the disk's text reports is
        // published, since an editor still shows what the buffer's did.
        try handler.invalidate(arena, path);
        try handler.freshen(arena, path);
        try handler.refresh(arena, path, true);
    }

    /// The kind the lexer gave every token of a document.
    ///
    /// `null` where the document names a file the module does not hold, which
    /// is what the protocol says when a server has nothing to report about a
    /// document rather than nothing to say about its tokens.
    pub fn @"textDocument/semanticTokens/full"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.semantic_tokens.Params,
    ) !?lsp.types.semantic_tokens.Result {
        const path = try uri_mod.pathOf(arena, params.textDocument.uri);
        const checked = try handler.check(arena, path);
        const file = checked.fileNamed(path) orelse return null;
        return .{ .data = try tokens.forFile(arena, checked, file, handler.offset_encoding) };
    }

    /// The document laid out again, as one edit replacing the whole of it.
    ///
    /// What canonical Linea is, is `fmt`'s answer and nothing here lays
    /// anything out. Whether a text may be laid out again at all is the same
    /// answer: a file that does not parse has no faithful printing, and a
    /// server that formatted one anyway would write out whatever the parser's
    /// recovery produced -- over the buffer someone is typing into.
    ///
    /// One edit rather than a diff. A diff would be a second opinion about
    /// what changed, and the whole text is what `fmt` produced.
    ///
    /// Costs one parse of the document and one of the result, and no check of
    /// its module: how a file is laid out is a question about its syntax, and
    /// a file whose module does not compile still formats.
    pub fn @"textDocument/formatting"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.document_formatting.Params,
    ) !?[]const lsp.types.TextEdit {
        const path = try uri_mod.pathOf(arena, params.textDocument.uri);
        const text = try handler.textOf(arena, path) orelse return null;

        var sink = Sink.init(arena);
        const source: Source = .{ .path = path, .text = text };
        const formatting = try fmt.formatSource(arena, &source, .from(0), &sink);
        const formatted = formatting.text orelse return null;

        const edits = try arena.alloc(lsp.types.TextEdit, 1);
        edits[0] = .{
            .range = .{
                .start = .{ .line = 0, .character = 0 },
                .end = lsp.offsets.indexToPosition(text, text.len, handler.offset_encoding),
            },
            .newText = formatted,
        };
        return edits;
    }

    /// Every declaration written in the document, in the order it was
    /// written.
    ///
    /// `null` where the document names a file the module does not hold, which
    /// is what the protocol says when a server has nothing to report about a
    /// document rather than an empty outline for it.
    pub fn @"textDocument/documentSymbol"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.DocumentSymbol.Params,
    ) !?lsp.types.DocumentSymbol.Result {
        const path = try uri_mod.pathOf(arena, params.textDocument.uri);
        const checked = try handler.check(arena, path);
        const file = checked.fileNamed(path) orelse return null;
        return .{ .document_symbols = try symbols.forFile(arena, checked, file, handler.offset_encoding) };
    }

    /// Every region of the document a client may collapse.
    ///
    /// `null` where the document names a file the module does not hold, for
    /// the reason the outline answers it.
    pub fn @"textDocument/foldingRange"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.FoldingRange.Params,
    ) !?[]const lsp.types.FoldingRange {
        const path = try uri_mod.pathOf(arena, params.textDocument.uri);
        const checked = try handler.check(arena, path);
        const file = checked.fileNamed(path) orelse return null;
        return try folding.forFile(arena, checked, file, handler.offset_encoding);
    }

    /// The type of every binding in the document whose type the source did
    /// not write.
    ///
    /// `null` where the document names a file the module does not hold, for
    /// the reason the outline answers it.
    pub fn @"textDocument/inlayHint"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.InlayHint.Params,
    ) !?[]const lsp.types.InlayHint {
        const path = try uri_mod.pathOf(arena, params.textDocument.uri);
        const checked = try handler.check(arena, path);
        const file = checked.fileNamed(path) orelse return null;
        return try hints.forFile(arena, checked, file, params.range, handler.offset_encoding);
    }

    /// Where the name under the cursor was declared.
    ///
    /// `null` where the document names a file the module does not hold, and
    /// where what the cursor sits on names nothing -- which the protocol does
    /// not distinguish and neither does a client, since both mean there is
    /// nowhere to go.
    pub fn @"textDocument/definition"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.Definition.Params,
    ) !?lsp.types.Definition.Result {
        const path = try uri_mod.pathOf(arena, params.textDocument.uri);
        const checked = try handler.check(arena, path);
        const file = checked.fileNamed(path) orelse return null;

        const found = try definition.forPosition(
            arena,
            handler.io,
            checked,
            file,
            params.position,
            handler.offset_encoding,
            handler.root,
        ) orelse return null;
        return .{ .definition = .{ .location = found } };
    }

    /// Everywhere the name under the cursor is written.
    ///
    /// `null` where the document names a file the module does not hold, and
    /// where what the cursor sits on names nothing -- which the protocol does
    /// not distinguish and neither does a client.
    ///
    /// The program the server sees is the one rooted at the file the editor
    /// opened. A sibling program importing this module is not in it, so its
    /// uses are not among these.
    pub fn @"textDocument/references"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.reference.Params,
    ) !?[]const lsp.types.Location {
        const path = try uri_mod.pathOf(arena, params.textDocument.uri);
        const checked = try handler.check(arena, path);
        const file = checked.fileNamed(path) orelse return null;

        return references.forPosition(
            arena,
            handler.io,
            checked,
            file,
            params.position,
            handler.offset_encoding,
            handler.root,
            params.context.includeDeclaration,
            null,
        );
    }

    /// Everywhere the name under the cursor is written in this document.
    ///
    /// The same answer `references` gives, narrowed to the file the request
    /// named: what a name reaches is one question, and a second walk to answer
    /// it here could highlight what following the name would not.
    ///
    /// Every site carries a range and no kind. A kind separates reading a name
    /// from writing to it, and nothing in this compiler decides that per use --
    /// so the protocol's default of "an occurrence" is what these are.
    pub fn @"textDocument/documentHighlight"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.DocumentHighlight.Params,
    ) !?[]const lsp.types.DocumentHighlight {
        const path = try uri_mod.pathOf(arena, params.textDocument.uri);
        const checked = try handler.check(arena, path);
        const file = checked.fileNamed(path) orelse return null;

        // The declaration is included: a reader highlighting a name expects
        // the one that introduced it to light up with the rest.
        const found = try references.forPosition(
            arena,
            handler.io,
            checked,
            file,
            params.position,
            handler.offset_encoding,
            handler.root,
            true,
            file,
        ) orelse return null;

        const out = try arena.alloc(lsp.types.DocumentHighlight, found.len);
        for (out, found) |*o, l| o.* = .{ .range = l.range };
        return out;
    }

    /// The name under the cursor, changed everywhere it is written.
    ///
    /// `null` where the document names a file the module does not hold, and
    /// where what the cursor sits on names nothing -- which is not a refusal
    /// but the same "nothing to do here" `definition` answers.
    ///
    /// A refusal is an error response, which is what the protocol asks for: a
    /// client shows the message, and every one of them says which of the
    /// reasons it was. The alternative is answering an empty edit, which a
    /// client applies in silence.
    ///
    /// Every program of the workspace holding the file that declares the
    /// name is renamed with it and checked with the edits applied, so a
    /// library two programs depend on is renamed for both or neither.
    pub fn @"textDocument/rename"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.rename.Params,
    ) !?lsp.types.WorkspaceEdit {
        const path = try uri_mod.pathOf(arena, params.textDocument.uri);
        const checked = try handler.check(arena, path);
        const file = checked.fileNamed(path) orelse return null;

        var others = try handler.otherPrograms(arena, checked);
        defer {
            for (others.analysed.items) |*other| other.deinit();
            others.analysed.deinit(arena);
        }
        const programs = try arena.alloc(*const analysis.Analysis, others.analysed.items.len + 1);
        programs[0] = checked;
        for (others.analysed.items, programs[1..]) |*other, *slot| slot.* = other;

        var refused_kind: ?name_case.Kind = null;
        var unloaded: ?rename.Unloaded = null;
        return rename.across(
            arena,
            handler.io,
            programs,
            others.unanalysed.items,
            file,
            params.position,
            handler.offset_encoding,
            handler.root,
            params.newName,
            &refused_kind,
            &unloaded,
        ) catch |err| {
            // The program the rename cannot check, and why, beside the
            // refusal: what the reader has to fix before renaming.
            if (unloaded) |program| {
                try handler.transport.writeNotification(
                    handler.io,
                    arena,
                    "window/showMessage",
                    lsp.types.window.ShowMessageParams,
                    .{ .type = .Error, .message = try std.fmt.allocPrint(arena, "the program at `{s}` reaches this name and does not load: {s}", .{ program.entry, program.reason }) },
                    .{ .emit_null_optional_fields = false },
                );
            }
            // A refusal carries only its name, so the kind and the respelling
            // [N-Case] would offer are shown beside it.
            if (refused_kind) |kind| {
                try handler.transport.writeNotification(
                    handler.io,
                    arena,
                    "window/showMessage",
                    lsp.types.window.ShowMessageParams,
                    .{ .type = .Error, .message = try rename.caseRefusal(arena, kind, params.newName) },
                    .{ .emit_null_optional_fields = false },
                );
            }
            return err;
        };
    }

    /// What can be done about the diagnostics the client is showing here.
    ///
    /// The diagnostics come from the request rather than from a check of the
    /// module: they are what the client is showing, which is what the reader
    /// asked about, and answering about diagnostics the client has not seen
    /// would offer a fix for a problem nobody is looking at.
    ///
    /// `null` where the document names a file the module does not hold, for
    /// the reason the outline answers it.
    pub fn @"textDocument/codeAction"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.CodeAction.Params,
    ) !?[]const lsp.types.CodeAction.Result {
        const path = try uri_mod.pathOf(arena, params.textDocument.uri);
        const checked = try handler.check(arena, path);
        const file = checked.fileNamed(path) orelse return null;

        return try fix.forFile(
            arena,
            checked,
            file,
            params.textDocument.uri,
            params.context.diagnostics,
            handler.offset_encoding,
        );
    }

    /// What the compiler settled about what the cursor sits on.
    ///
    /// `null` where the document names a file the module does not hold, and
    /// where nothing at the cursor has a type.
    pub fn @"textDocument/hover"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.Hover.Params,
    ) !?lsp.types.Hover {
        const path = try uri_mod.pathOf(arena, params.textDocument.uri);
        const checked = try handler.check(arena, path);
        const file = checked.fileNamed(path) orelse return null;

        return hover.forPosition(arena, checked, file, params.position, handler.offset_encoding);
    }

    /// What could be written where the cursor is.
    ///
    /// `null` where the document names a file the module does not hold, for the
    /// reason the outline answers it. Everywhere else there is an answer, and
    /// usually the text does not parse: that is the state a completion is asked
    /// from, and a server silent until it does is silent when it was asked.
    pub fn @"textDocument/completion"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.completion.Params,
    ) !?lsp.types.completion.Result {
        const path = try uri_mod.pathOf(arena, params.textDocument.uri);
        const checked = try handler.check(arena, path);
        const file = checked.fileNamed(path) orelse return null;
        const query = try (try handler.indexOf()).query();

        return completion.forPosition(
            arena,
            checked,
            file,
            params.position,
            handler.offset_encoding,
            query,
            try handler.entryFor(arena, path),
            handler.snippets,
        );
    }

    /// What the document currently says, which is the editor's buffer where
    /// it has one and the file otherwise.
    ///
    /// A capability about one file rather than about a module reads this
    /// instead of loading one: the module's own substitution is
    /// `Documents.filesFor`, and both go through `open` so a saved file and an
    /// unsaved buffer cannot be answered for differently.
    fn textOf(handler: *Handler, arena: std.mem.Allocator, path: []const u8) !?[]const u8 {
        if (handler.documents.open.get(path)) |buffer| return buffer;
        return source_mod.readFileAlloc(handler.io, arena, path) catch null;
    }

    /// The module a document belongs to, checked.
    ///
    /// The program its root makes, wherever that program holds the document.
    /// A file the root's source holds that no import of the program reaches
    /// is checked as `linea check` checks it when named: from the program's
    /// root, with the file's module as the entry. Analysed only with the
    /// program, it would be analysed by nothing, and an editor would show no
    /// diagnostic for it.
    ///
    /// Costs one check of the program, one more for such a file, or nothing
    /// where the analysis held is already the one asked about. The result is
    /// borrowed from the handler and stays valid until the next document
    /// changes; `arena` carries only what the resolution needed.
    fn check(handler: *Handler, arena: std.mem.Allocator, path: []const u8) !*const analysis.Analysis {
        const root = try handler.rootFor(arena, path);
        const entry = root.entry;
        const named = try loader.canonical(arena, loader.trimmedEntry(path));
        const module: ?[]const u8 = if (sourceHolds(entry, named)) std.fs.path.dirname(named) orelse "" else null;
        const program = if (handler.cached) |*held|
            (if (std.mem.eql(u8, held.entry, entry)) &held.of else try handler.checkAs(arena, root, null))
        else
            try handler.checkAs(arena, root, null);
        if (module == null or program.fileNamed(path) != null) return program;
        if (handler.alone) |*held| {
            if (std.mem.eql(u8, held.entry, entry) and std.mem.eql(u8, held.module.?, module.?)) return &held.of;
        }
        return handler.checkAs(arena, root, module);
    }

    /// Checks `root`, with `module` as the entry where one is named, and
    /// holds the answer in place of what was held in its slot: the program's
    /// in `cached`, a module's in `alone`.
    fn checkAs(handler: *Handler, arena: std.mem.Allocator, root: loader.Root, module: ?[]const u8) !*const analysis.Analysis {
        // Everything below is released here until the held analysis owns it,
        // and by `drop` after.
        var held = false;
        const files = try handler.documents.filesFor(arena, handler.io, root, .open_and_manifests);

        // The analysis copies what it was given, so the buffers above are the
        // caller's business from here and the message's arena may reclaim
        // them whenever it likes.
        var fresh = try analysis.onDisk(handler.gpa, handler.region_backing, handler.library, files, root.entry, module, handler.io);
        errdefer if (!held) fresh.deinit();
        const key = try handler.gpa.dupe(u8, root.entry);
        errdefer if (!held) handler.gpa.free(key);
        const held_module: ?[]u8 = if (module) |dir| try handler.gpa.dupe(u8, dir) else null;

        const slot = if (module == null) &handler.cached else &handler.alone;
        handler.release(slot);
        slot.* = .{ .entry = key, .module = held_module, .of = fresh };
        held = true;
        try handler.watchEmbeds(arena, &slot.*.?.of);
        return &slot.*.?.of;
    }

    /// What every program of the workspace but `checked`'s is, for a rename.
    const OtherPrograms = struct {
        /// Each checked with the documents the editor holds; one that loads
        /// with errors is kept, and `rename.across` decides.
        analysed: std.ArrayList(analysis.Analysis) = .empty,
        /// The directory of each program that could not be analysed: a
        /// manifest the index could not resolve, or a root or files that
        /// could not be read.
        unanalysed: std.ArrayList([]const u8) = .empty,
    };

    /// Every program of the workspace but the one `checked` is, for a rename
    /// to find the ones it reaches. Held apart from the cached slots, which
    /// hold `checked` itself.
    ///
    /// Costs one check per program the workspace holds.
    fn otherPrograms(handler: *Handler, arena: std.mem.Allocator, checked: *const analysis.Analysis) !OtherPrograms {
        var others: OtherPrograms = .{};
        errdefer {
            for (others.analysed.items) |*other| other.deinit();
            others.analysed.deinit(arena);
        }
        const index = try handler.indexOf();
        try others.unanalysed.appendSlice(arena, index.unresolved);
        const own = try loader.identityOf(arena, handler.io, checked.made_from.entry);
        for (index.programs) |entry| {
            if (std.mem.eql(u8, try loader.identityOf(arena, handler.io, entry), own)) continue;
            const root = loader.rootOf(arena, handler.io, entry, .as_named, handler.root) catch |err| switch (err) {
                error.OutOfMemory => return err,
                else => {
                    try others.unanalysed.append(arena, entry);
                    continue;
                },
            };
            const files = handler.documents.filesFor(arena, handler.io, root, .open_and_manifests) catch |err| switch (err) {
                error.OutOfMemory => return err,
                else => {
                    try others.unanalysed.append(arena, entry);
                    continue;
                },
            };
            const other = analysis.onDisk(handler.gpa, handler.region_backing, handler.library, files, root.entry, null, handler.io) catch |err| switch (err) {
                error.OutOfMemory => return err,
                else => {
                    try others.unanalysed.append(arena, entry);
                    continue;
                },
            };
            others.analysed.append(arena, other) catch |err| {
                var dropped = other;
                dropped.deinit();
                return err;
            };
        }
        return others;
    }

    /// Whether `file`, spelled canonically, is a `.lin` file inside the source
    /// root `entry` names; an entry that is a file holds nothing else.
    fn sourceHolds(entry: []const u8, file: []const u8) bool {
        if (std.mem.endsWith(u8, entry, ".lin") or !std.mem.endsWith(u8, file, ".lin")) return false;
        const dir = std.fs.path.dirname(file) orelse "";
        if (entry.len == 0) return true;
        if (!std.mem.startsWith(u8, dir, entry)) return false;
        return dir.len == entry.len or dir[entry.len] == '/';
    }

    /// Releases everything the session holds: the workspace it was told about,
    /// the documents the editor opened, and the analysis of the last module
    /// asked about.
    ///
    /// A server is one process per session and the exit is close behind, which
    /// is why none of this used to be released -- and it is also why a leak
    /// here is invisible until something else runs a session, which the corpus
    /// now does once per case.
    pub fn deinit(handler: *Handler) void {
        handler.drop();
        for (handler.reported.values()) |*kept| kept.arena.deinit();
        handler.reported.deinit(handler.gpa);
        for (handler.embeds_watched.items) |path| handler.gpa.free(path);
        handler.embeds_watched.deinit(handler.gpa);
        handler.documents.deinit();
        handler.setRoot("");
    }

    /// Replaces the workspace root, releasing what it held. `initialize` may
    /// arrive twice, and what the first one held is nobody else's.
    ///
    /// The index goes with it, because an index is of one workspace: what it
    /// holds was found by walking the root being replaced.
    fn setRoot(handler: *Handler, path: []const u8) void {
        if (handler.index) |*held| {
            held.deinit();
            handler.index = null;
        }
        if (handler.root.len > 0) handler.gpa.free(handler.root);
        handler.root = path;
    }

    /// What the workspace exports, built if this is the first ask.
    ///
    /// Costs one walk of the workspace and one lex and parse of each open
    /// document the first time, and nothing after it. Borrowed from the
    /// handler, and valid until the root is replaced.
    ///
    /// A workspace nobody has named holds no programs, so this reached before
    /// `initialize` says which directory the client opened is an index of
    /// nothing rather than an index of wherever the editor started the server.
    fn indexOf(handler: *Handler) !*workspace.Index {
        if (handler.index == null) {
            handler.index = try workspace.Index.build(handler.gpa, handler.io, handler.root);
            // The walk reads files, and an open document is what its buffer
            // says: each is indexed again from the buffer, as an edit after
            // the build would be.
            var open = handler.documents.open.iterator();
            while (open.next()) |document| {
                try handler.index.?.reindex(handler.io, document.key_ptr.*, document.value_ptr.*);
            }
        }
        return &handler.index.?;
    }

    /// Replaces what one file contributes to the index, from whatever that
    /// file now says.
    ///
    /// Nothing where the index has not been built. It is built on the first
    /// request that reads it, and building it here would make every keystroke
    /// pay for a walk a session may never ask for.
    ///
    /// What the file says is `textOf` -- the editor's buffer where there is
    /// one and the file otherwise -- so an edit is seen before it is saved,
    /// and a file that has gone from disk contributes nothing. Going through
    /// the same reader every other capability answers from is what stops the
    /// index disagreeing with them about what a file currently holds.
    ///
    /// Costs one lex and parse of the file and one pass over the index.
    fn freshen(handler: *Handler, arena: std.mem.Allocator, path: []const u8) !void {
        const index = if (handler.index) |*held| held else return;
        const text = try handler.textOf(arena, path) orelse "";
        try index.reindex(handler.io, path, text);
    }

    /// Asks the client to say when a `.lin` file or a manifest under the
    /// workspace changes outside the editor.
    ///
    /// The protocol has no static way for a server to ask for file events, so
    /// registering for them is the only way to be told -- which is why a
    /// client that cannot register leaves the index as fresh as the buffers
    /// the editor has open and no fresher.
    ///
    /// The pattern is a plain glob rather than one relative to a workspace
    /// folder, so a session told about a second workspace does not have to
    /// register again. Watching wider than the index costs a resolution and
    /// nothing else: a notification about a file no indexed program holds
    /// leaves the index as it was.
    ///
    /// Costs one message, sent at most once while the client has it, and
    /// again only if the client refused.
    fn watchFiles(handler: *Handler, arena: std.mem.Allocator) !void {
        if (!handler.watch_offered) return;
        if (handler.watching or handler.watch_asked != null) return;

        // The options a registration carries are whatever the method being
        // registered defines, so the protocol types them as any JSON value.
        // Source files, and the manifests that say which files a program
        // holds, what it depends on and what it may declare.
        var watchers: std.json.Array = .init(arena);
        for ([_][]const u8{ "**/*.lin", "**/" ++ loader.manifest_name }) |pattern| {
            var watcher: std.json.ObjectMap = .empty;
            try watcher.put(arena, "globPattern", .{ .string = pattern });
            try watchers.append(.{ .object = watcher });
        }
        var options: std.json.ObjectMap = .empty;
        try options.put(arena, "watchers", .{ .array = watchers });

        const id = handler.sent + 1;
        try handler.transport.writeRequest(
            handler.io,
            arena,
            .{ .number = id },
            "client/registerCapability",
            lsp.types.Registration.Params,
            .{ .registrations = &.{.{
                .id = watch_registration,
                .method = "workspace/didChangeWatchedFiles",
                .registerOptions = .{ .object = options },
            }} },
            .{ .emit_null_optional_fields = false },
        );
        // Recorded after the write, so a request that never left is not one
        // the server waits on an answer to.
        handler.sent = id;
        handler.watch_asked = id;
    }

    /// Asks the client to say when a file the held analysis embeds changes, as
    /// it says for a `.lin` file. An embedded file may be named anything, so
    /// the files are watched by their own paths, under a registration of their
    /// own that is replaced whenever the program comes to embed other files.
    ///
    /// Costs nothing where the client offers no watching or the analysis
    /// embeds the files already watched, and otherwise one unregistration and
    /// one registration, each one message.
    fn watchEmbeds(handler: *Handler, arena: std.mem.Allocator, held: *const analysis.Analysis) !void {
        if (!handler.watch_offered) return;
        var paths: std.ArrayList([]const u8) = .empty;
        for (held.program.embeds.watched) |path| try paths.append(arena, path);
        if (paths.items.len == handler.embeds_watched.items.len) {
            for (paths.items, handler.embeds_watched.items) |now, before| {
                if (!std.mem.eql(u8, now, before)) break;
            } else return;
        }

        if (handler.embeds_watched.items.len > 0) {
            const id = handler.sent + 1;
            try handler.transport.writeRequest(
                handler.io,
                arena,
                .{ .number = id },
                "client/unregisterCapability",
                lsp.types.Unregistration.Params,
                .{ .unregisterations = &.{.{ .id = embeds_registration, .method = "workspace/didChangeWatchedFiles" }} },
                .{ .emit_null_optional_fields = false },
            );
            handler.sent = id;
        }
        for (handler.embeds_watched.items) |path| handler.gpa.free(path);
        handler.embeds_watched.clearRetainingCapacity();
        if (paths.items.len == 0) return;

        var watchers: std.json.Array = .init(arena);
        for (paths.items) |path| {
            // A pattern ending in the path from the workspace, as the `.lin`
            // watch is a pattern rather than a location: the file under any
            // folder the client opened matches it.
            const inside = handler.root.len > 0 and path.len > handler.root.len and
                std.mem.startsWith(u8, path, handler.root) and path[handler.root.len] == '/';
            const relative = if (inside) path[handler.root.len + 1 ..] else std.fs.path.basename(path);
            var watcher: std.json.ObjectMap = .empty;
            try watcher.put(arena, "globPattern", .{ .string = try std.mem.concat(arena, u8, &.{ "**/", try globLiteral(arena, relative) }) });
            try watchers.append(.{ .object = watcher });
        }
        var options: std.json.ObjectMap = .empty;
        try options.put(arena, "watchers", .{ .array = watchers });
        const id = handler.sent + 1;
        try handler.transport.writeRequest(
            handler.io,
            arena,
            .{ .number = id },
            "client/registerCapability",
            lsp.types.Registration.Params,
            .{ .registrations = &.{.{
                .id = embeds_registration,
                .method = "workspace/didChangeWatchedFiles",
                .registerOptions = .{ .object = options },
            }} },
            .{ .emit_null_optional_fields = false },
        );
        handler.sent = id;
        try handler.embeds_watched.ensureTotalCapacity(handler.gpa, paths.items.len);
        for (paths.items) |path| handler.embeds_watched.appendAssumeCapacity(try handler.gpa.dupe(u8, path));
    }

    /// Releases the held analyses, so the next request checks again.
    fn drop(handler: *Handler) void {
        handler.release(&handler.cached);
        handler.release(&handler.alone);
    }

    fn release(handler: *Handler, slot: *?Cached) void {
        if (slot.*) |*held| {
            held.of.deinit();
            handler.gpa.free(held.entry);
            if (held.module) |dir| handler.gpa.free(dir);
            slot.* = null;
        }
    }

    /// Whether the held analyses already describe these exact document bytes:
    /// one holds the file, and none holds other text for it.
    fn cachedTextMatches(handler: *const Handler, path: []const u8, text: []const u8) bool {
        var holds = false;
        for ([_]?Cached{ handler.cached, handler.alone }) |slot| {
            const held = slot orelse continue;
            const file = held.of.fileNamed(path) orelse continue;
            if (!std.mem.eql(u8, held.of.table.get(file).text, text)) return false;
            holds = true;
        }
        return holds;
    }

    /// The entry of a held analysis that embeds `path`, read or not, or
    /// null. Copied into `arena`, since invalidating releases the analysis.
    fn embeddedBy(handler: *Handler, arena: std.mem.Allocator, path: []const u8) !?[]const u8 {
        const named = try loader.canonical(arena, loader.trimmedEntry(path));
        for ([_]?Cached{ handler.cached, handler.alone }) |slot| {
            const held = slot orelse continue;
            for (held.of.program.embeds.watched) |watched| {
                if (std.mem.eql(u8, watched, named)) return try arena.dupe(u8, held.entry);
            }
        }
        return null;
    }

    /// Checks and publishes the program of every document the editor has
    /// open, each program once, in the order of the documents' paths so a
    /// session reads the same whatever order they were opened in.
    ///
    /// **Bound:** the open documents, sorted, and one check per program
    /// among them; then one resolution per remembered program that was not
    /// among them.
    fn reportOpen(handler: *Handler, arena: std.mem.Allocator) !void {
        var paths: std.ArrayList([]const u8) = .empty;
        var open = handler.documents.open.keyIterator();
        while (open.next()) |path| try paths.append(arena, path.*);
        std.mem.sort([]const u8, paths.items, {}, struct {
            fn before(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.before);

        var published: std.StringHashMapUnmanaged(void) = .empty;
        for (paths.items) |path| {
            const entry = (try handler.rootFor(arena, path)).entry;
            if ((try published.getOrPut(arena, entry)).found_existing) continue;
            try handler.refresh(arena, path, true);
        }

        // A manifest decides which program a file belongs to. A program
        // that was not checked again, and whose files now resolve to another
        // program or to none, is one the change did away with: what it was
        // last published with is taken down. One no document is open in,
        // that its files still resolve to, keeps what it showed.
        var gone: std.ArrayList([]const u8) = .empty;
        var kept = handler.reported.iterator();
        while (kept.next()) |held| {
            const key = held.key_ptr.*;
            if (published.contains(key)) continue;
            const files = held.value_ptr.files.keys();
            if (files.len != 0) {
                const now = handler.rootFor(arena, files[0]) catch null;
                if (now) |root| if (std.mem.eql(u8, root.entry, held.value_ptr.entry)) continue;
            }
            try gone.append(arena, try arena.dupe(u8, key));
        }
        std.mem.sort([]const u8, gone.items, {}, struct {
            fn before(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.before);
        for (gone.items) |key| _ = try handler.withdraw(arena, key, true);
    }

    /// Drops an analysis when a loaded file or a loaded module's sibling changes.
    ///
    /// The loader's module directories include namespace dependencies on files
    /// that do not yet exist. An erroneous analysis conservatively observes
    /// every edit in its program, because a new module can satisfy an import
    /// that failed before. Clean unrelated modules leave semantic storage held;
    /// their export index is refreshed independently by the notification.
    ///
    /// Bound: one program-file scan and one module-directory scan, plus
    /// resolution of the changed path's program when errors were reported.
    /// No dependency index is rebuilt; a changed manifest drops it.
    fn invalidate(handler: *Handler, arena: std.mem.Allocator, path: []const u8) !void {
        const named = try loader.canonical(arena, loader.trimmedEntry(path));
        // A manifest decides where a program's files sit, which libraries it
        // depends on and which modules may declare `extern`, for its own
        // program and for every program that depends on it. Which of the
        // held analysis and the index it reaches is not worked out: both are
        // dropped, and each is built again by the next request that reads it.
        if (std.mem.eql(u8, std.fs.path.basename(named), loader.manifest_name)) {
            handler.drop();
            if (handler.index) |*index| {
                index.deinit();
                handler.index = null;
            }
            return;
        }
        if (try handler.stale(arena, &handler.cached, named)) handler.release(&handler.cached);
        if (try handler.stale(arena, &handler.alone, named)) handler.release(&handler.alone);
    }

    /// Whether the analysis in `slot` may answer differently once `named`
    /// changed: it holds the file, embeds it, holds the module directory it
    /// sits in, or reported errors a new file of its program could answer.
    fn stale(handler: *Handler, arena: std.mem.Allocator, slot: *const ?Cached, named: []const u8) !bool {
        const held = slot.* orelse return false;
        if (held.of.fileNamed(named) != null) return true;
        // A file the program embeds is as much its input as a source is, and
        // so is one it names that could not be read.
        for (held.of.program.embeds.watched) |watched| {
            if (std.mem.eql(u8, watched, named)) return true;
        }
        const directory = std.fs.path.dirname(named) orelse ".";
        for (held.of.program.modules) |module| {
            if (std.mem.eql(u8, module.dir, directory)) return true;
        }
        if (held.of.sink.hasErrors()) {
            const entry = try handler.entryFor(arena, named);
            if (std.mem.eql(u8, held.entry, entry)) return true;
        }
        return false;
    }

    /// Which program a document belongs to, or the document itself where the
    /// project will not resolve to one.
    ///
    /// Which program an opened file belongs to is the loader's rule and not
    /// this module's. An editor cannot say whether it means the file or the
    /// program the file sits in -- it has only the file -- so it says so, and
    /// the same function a command line goes through answers.
    ///
    /// A project that will not read is the one place the two callers differ. A
    /// compilation stops at a manifest that is not JSON, because the program
    /// it was told to build is not the one on disk. A session has a document
    /// on screen either way, and stopping meant the editor was told nothing at
    /// all -- no diagnostics, no outline, and no sentence saying why. So the
    /// file stands on its own, which is where a file no program holds already
    /// lands.
    ///
    /// Asked in one place, because what `check` keys an analysis by has to be
    /// what `invalidate` looks for.
    fn entryFor(handler: *Handler, arena: std.mem.Allocator, path: []const u8) ![]const u8 {
        return (try handler.rootFor(arena, path)).entry;
    }

    /// The root a document belongs to and the manifest that identified it,
    /// from one walk. Where the manifest will not read, the file stands on
    /// its own, as `entryFor` describes.
    fn rootFor(handler: *Handler, arena: std.mem.Allocator, path: []const u8) !loader.Root {
        return loader.rootOf(arena, handler.io, path, .its_program, handler.root) catch |err| switch (err) {
            error.OutOfMemory => err,
            else => .{ .entry = try loader.canonical(arena, loader.trimmedEntry(path)) },
        };
    }

    /// Brings what is published up to date after `path` changed, so each
    /// file shows the union of what every check currently reaching it reports
    /// as of that check's latest run.
    ///
    /// A document's own change (`own`) runs the check `path` belongs to, then
    /// every check whose last report reached `path`: no other check read it,
    /// so no other answer moved. A change on disk, which an editor sends for
    /// a file it may not hold open, runs the program's check of `path`'s root
    /// first, wherever a document of the root is open or that check ran
    /// before, since the file may be one the program's imports now reach or
    /// no longer reach; then every check that reached `path`, and the check
    /// of every open document of the root. A program's check that now loads a
    /// module withdraws that module's own check; one that stops reaching an
    /// open document leaves it to its module's check, which runs. A module's
    /// check exists only for an open document no program reaches, and a
    /// program's check reports once it reaches an open document.
    ///
    /// Every file is published, not only the edited one: a module's files see
    /// each other's declarations, so a change in one moves the diagnostics in
    /// its siblings. A file with nothing wrong is published as an empty list,
    /// which is how the protocol says a file is clean.
    ///
    /// **Bound:** each check key runs once, its key decided before it runs
    /// (`keyOf`), over the keys that reached `path` and the open documents of
    /// its root.
    fn refresh(handler: *Handler, arena: std.mem.Allocator, path: []const u8, own: bool) !void {
        const entry = (try handler.rootFor(arena, path)).entry;
        var open: std.ArrayList([]const u8) = .empty;
        var documents = handler.documents.open.keyIterator();
        while (documents.next()) |document| {
            if (std.mem.eql(u8, (try handler.rootFor(arena, document.*)).entry, entry)) try open.append(arena, document.*);
        }
        std.mem.sort([]const u8, open.items, {}, struct {
            fn before(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.before);

        var asked: std.ArrayList([]const u8) = .empty;
        if (own) try asked.append(arena, path);
        if (!own and (open.items.len != 0 or handler.reported.contains(entry))) try asked.append(arena, entry);
        for (handler.reported.values()) |*kept| {
            if (kept.files.contains(path)) try asked.append(arena, try arena.dupe(u8, kept.asked));
        }
        if (!own) try asked.appendSlice(arena, open.items);

        var ran: std.StringHashMapUnmanaged(void) = .empty;
        var i: usize = 0;
        while (i < asked.items.len) : (i += 1) {
            if (ran.contains(try handler.keyOf(arena, asked.items[i]))) continue;
            try handler.report(arena, asked.items[i], &ran, &asked);
        }
    }

    /// The key of the check `path` belongs to, decided without running it:
    /// its root's entry where the program's latest report reached `path` or
    /// the root's source does not hold it, and its module's directory
    /// otherwise. `refresh` runs the program's check before any module's, so
    /// within one refresh that report is current.
    fn keyOf(handler: *Handler, arena: std.mem.Allocator, path: []const u8) ![]const u8 {
        const entry = (try handler.rootFor(arena, path)).entry;
        const named = try loader.canonical(arena, loader.trimmedEntry(path));
        if (!sourceHolds(entry, named)) return entry;
        if (handler.reported.get(entry)) |program| {
            if (program.files.contains(path)) return entry;
        }
        return std.fs.path.dirname(named) orelse "";
    }

    /// Runs the check `path` belongs to and publishes what changed, once per
    /// key in `ran`, adding to `asked` each open document it lets go.
    fn report(
        handler: *Handler,
        arena: std.mem.Allocator,
        path: []const u8,
        ran: *std.StringHashMapUnmanaged(void),
        asked: *std.ArrayList([]const u8),
    ) !void {
        const checked = try handler.check(arena, path);
        const entry = (try handler.rootFor(arena, path)).entry;
        const module = if (handler.alone) |*held| (if (&held.of == checked) held.module else null) else null;
        const key = try arena.dupe(u8, module orelse entry);
        if ((try ran.getOrPut(arena, key)).found_existing) return;

        // A module's check of a document no longer open is nobody's, and
        // what it reported is taken back; another open document of the module
        // asks for it again.
        if (module != null and !handler.documents.open.contains(path)) {
            const reopened = try handler.withdraw(arena, key, true);
            for (reopened) |other| if (handler.documents.open.contains(other)) try asked.append(arena, other);
            return;
        }

        // A program's check that has never reported, and reaches no open
        // document, is no check any document asked for.
        if (module == null and !handler.reported.contains(key)) {
            var reaches_open = false;
            var documents = handler.documents.open.keyIterator();
            while (documents.next()) |document| {
                if (checked.fileNamed(document.*) != null) reaches_open = true;
            }
            if (!reaches_open) return;
        }

        var fresh: Reported = .{ .arena = .init(handler.gpa), .entry = undefined, .asked = undefined, .module = module != null };
        errdefer fresh.arena.deinit();
        const keep = fresh.arena.allocator();
        fresh.entry = try keep.dupe(u8, entry);
        fresh.asked = try keep.dupe(u8, if (module != null) path else entry);
        const owned_key = try keep.dupe(u8, key);

        const publication = try publish.Publication.init(arena, checked);
        var it = publish.files(&checked.program);
        while (it.next()) |file| {
            const diagnostics = try publication.forFile(arena, file, handler.offset_encoding);
            const texts = try keep.alloc([]const u8, diagnostics.len);
            for (diagnostics, texts) |d, *text| text.* = try std.json.Stringify.valueAlloc(keep, d, .{ .emit_null_optional_fields = false });
            const file_path = checked.table.get(file).path;
            if (fresh.files.contains(file_path)) continue;
            try fresh.files.put(keep, try keep.dupe(u8, file_path), texts);
        }

        // What this key reported before for a file it no longer reaches is
        // taken back; a file it reported nothing for shows the same as before.
        // An open document it let go is its module's to check.
        var left: std.ArrayList([]const u8) = .empty;
        if (handler.reported.get(key)) |before| {
            for (before.files.keys(), before.files.values()) |file_path, texts| {
                if (fresh.files.contains(file_path)) continue;
                if (module == null and handler.documents.open.contains(file_path)) try asked.append(arena, try arena.dupe(u8, file_path));
                if (texts.len != 0) try left.append(arena, try arena.dupe(u8, file_path));
            }
        }

        // A module's check exists while no program reaches the module: the
        // program's check that now loads it takes it back before publishing.
        var gone: std.ArrayList([]const u8) = .empty;
        if (module == null) {
            for (handler.reported.keys(), handler.reported.values()) |other, *kept| {
                if (!kept.module or !std.mem.eql(u8, kept.entry, entry)) continue;
                if (loadsModule(checked, other)) try gone.append(arena, try arena.dupe(u8, other));
            }
        }
        var withdrawn: std.ArrayList([]const u8) = .empty;
        for (gone.items) |other| try withdrawn.appendSlice(arena, try handler.withdraw(arena, other, false));

        try handler.hold(owned_key, fresh);
        for (handler.reported.get(key).?.files.keys()) |file_path| try handler.publishUnion(arena, file_path);
        for (left.items) |file_path| try handler.publishUnion(arena, file_path);
        for (withdrawn.items) |file_path| {
            if (!handler.reported.get(key).?.files.contains(file_path)) try handler.publishUnion(arena, file_path);
        }
    }

    /// Whether `checked` loads the module in directory `dir`.
    fn loadsModule(checked: *const analysis.Analysis, dir: []const u8) bool {
        for (checked.program.modules) |m| {
            if (std.mem.eql(u8, m.dir, dir)) return true;
        }
        return false;
    }

    /// Holds `report` under `key` in place of what was held there.
    fn hold(handler: *Handler, key: []const u8, report_held: Reported) !void {
        if (handler.reported.fetchOrderedRemove(key)) |old| {
            var released = old.value;
            released.arena.deinit();
        }
        try handler.reported.put(handler.gpa, key, report_held);
    }

    /// Withdraws everything `key` reported, and returns every file it reached.
    /// Where `publish_now`, each file it reported something for is published
    /// with what the keys left still report.
    fn withdraw(handler: *Handler, arena: std.mem.Allocator, key: []const u8, publish_now: bool) ![]const []const u8 {
        var removed = handler.reported.fetchOrderedRemove(key) orelse return &.{};
        defer removed.value.arena.deinit();
        var reached: std.ArrayList([]const u8) = .empty;
        for (removed.value.files.keys(), removed.value.files.values()) |file_path, texts| {
            try reached.append(arena, try arena.dupe(u8, file_path));
            if (publish_now and texts.len != 0) try handler.publishUnion(arena, file_path);
        }
        return reached.items;
    }

    /// Publishes `file` with the union of what every key reports for it, in
    /// the order the keys were last reported, a diagnostic another key
    /// already reported written once.
    fn publishUnion(handler: *Handler, arena: std.mem.Allocator, file: []const u8) !void {
        var seen: std.StringHashMapUnmanaged(void) = .empty;
        var out: std.ArrayList(lsp.types.Diagnostic) = .empty;
        for (handler.reported.values()) |*kept| {
            const texts = kept.files.get(file) orelse continue;
            for (texts) |text| {
                if (seen.contains(text)) continue;
                try out.append(arena, try std.json.parseFromSliceLeaky(lsp.types.Diagnostic, arena, text, .{ .ignore_unknown_fields = true }));
            }
            for (texts) |text| try seen.put(arena, text, {});
        }
        try handler.publishFor(arena, file, out.items);
    }

    fn publishFor(handler: *Handler, arena: std.mem.Allocator, path: []const u8, diagnostics: []const lsp.types.Diagnostic) !void {
        try handler.transport.writeNotification(
            handler.io,
            arena,
            "textDocument/publishDiagnostics",
            lsp.types.publish_diagnostics.Params,
            .{
                .uri = try uri_mod.uriOf(arena, path),
                .diagnostics = diagnostics,
            },
            .{ .emit_null_optional_fields = false },
        );
    }
};

/// Whether the client can be asked to watch files on the server's behalf.
///
/// A client that does not support dynamic registration cannot be asked at all,
/// and the protocol offers no other way to say a server wants file events.
/// Such a session is not broken: the index is then as fresh as the buffers the
/// editor has open, which is everything that client tells the server about.
fn watchesFiles(capabilities: lsp.types.ClientCapabilities) bool {
    const in_workspace = capabilities.workspace orelse return false;
    const watched = in_workspace.didChangeWatchedFiles orelse return false;
    return watched.dynamicRegistration orelse false;
}

/// Whether the client reads a completion's text as a snippet, which is what
/// decides whether an accepted function writes the call or the name.
///
/// A capability and not an assumption: a client that did not advertise it
/// writes `${1:a}` into the buffer as it stands, so the offer it gets is the
/// bare name -- which is what it can accept and what the parameter hints say
/// the rest of once the call is written.
fn readsSnippets(capabilities: lsp.types.ClientCapabilities) completion.Snippets {
    const document = capabilities.textDocument orelse return .unsupported;
    const offered = document.completion orelse return .unsupported;
    const item = offered.completionItem orelse return .unsupported;
    return if (item.snippetSupport orelse false) .supported else .unsupported;
}

/// The encoding this server reports positions in, chosen from what the
/// client offers in `general.positionEncodings`, in the decreasing
/// preference the client sent them. A client offering none, or none this
/// server recognises, gets the encoding every client and server must
/// support.
fn negotiatedEncoding(capabilities: lsp.types.ClientCapabilities) lsp.offsets.Encoding {
    const general = capabilities.general orelse return .@"utf-16";
    const offered = general.positionEncodings orelse return .@"utf-16";
    for (offered) |encoding| switch (encoding) {
        .@"utf-8" => return .@"utf-8",
        .@"utf-16" => return .@"utf-16",
        .@"utf-32" => return .@"utf-32",
        .custom_value => {},
    };
    return .@"utf-16";
}

/// Serves the Language Server Protocol on standard input and output.
pub fn serve(gpa: std.mem.Allocator, region_backing: std.mem.Allocator, io: std.Io) !u8 {
    const library = try loader.CheckedLibrary.init(gpa);
    defer library.deinit();
    var read_buffer: [4096]u8 = undefined;
    var stdio_transport: lsp.Transport.Stdio = .init(&read_buffer, .stdin(), .stdout());
    var handler: Handler = .{
        .gpa = gpa,
        .region_backing = region_backing,
        .library = library,
        .io = io,
        .transport = &stdio_transport.transport,
        .documents = .{ .gpa = gpa },
    };
    defer handler.deinit();
    // A client that closes the pipe has ended the session, which is what an
    // editor killed mid-run does and is not a failure to report: `run` returns
    // on `exit`, and end of input is the same ending arriving without it.
    lsp.basic_server.run(io, gpa, &stdio_transport.transport, &handler, std.log.err) catch |err| switch (err) {
        error.EndOfStream => {},
        else => return err,
    };
    return handler.exitStatus();
}

test "workspace folders take precedence over rootUri" {
    const gpa = std.testing.allocator;
    var handler: Handler = .{
        .gpa = gpa,
        .region_backing = gpa,
        .library = test_library.get(),
        .io = std.testing.io,
        .transport = undefined,
        .documents = .{ .gpa = gpa },
    };
    defer handler.deinit();
    _ = try handler.initialize(gpa, .{
        .capabilities = .{},
        .rootUri = "file:///fallback",
        .workspaceFolders = &.{.{ .uri = "file:///workspace", .name = "workspace" }},
    });
    try std.testing.expectEqualStrings("/workspace", handler.root);
    _ = try handler.initialize(gpa, .{
        .capabilities = .{},
        .rootUri = "file:///fallback",
        .workspaceFolders = &.{},
    });
    try std.testing.expectEqualStrings("/fallback", handler.root);
}

test "a rootUri workspace index is built on the first ask and held for the session" {
    const gpa = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "linea.json", .data = "{}" });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "main.lin",
        .data = "pub fn opened() -> UInt8 { 1 }\n",
    });

    const root = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer gpa.free(root);
    var handler: Handler = .{
        .gpa = gpa,
        .region_backing = gpa,
        .library = test_library.get(),
        .io = std.testing.io,
        // Nothing below sends anything: no message is answered here.
        .transport = undefined,
        .documents = .{ .gpa = gpa },
    };
    defer handler.deinit();

    const root_uri = try uri_mod.uriOf(gpa, root);
    defer gpa.free(root_uri);
    _ = try handler.initialize(gpa, .{ .capabilities = .{}, .rootUri = root_uri });

    // Nothing has asked yet, so nothing has been walked.
    try std.testing.expect(handler.index == null);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    const main = try std.fs.path.join(arena.allocator(), &.{ root, "main.lin" });
    const program = try handler.entryFor(arena.allocator(), main);

    const first = try handler.indexOf();
    try std.testing.expectEqual(@as(usize, 1), first.offers(program, "").len);

    // A file appearing on disk after the index was built is a file the index
    // does not know about, because it was built once and is held rather than
    // walked again for the next request.
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "later.lin",
        .data = "pub fn later() -> UInt8 { 2 }\n",
    });
    const again = try handler.indexOf();
    try std.testing.expectEqual(@as(usize, 1), again.offers(program, "").len);
}

/// A transport that answers nothing and keeps everything written to it.
///
/// A unit case drives the handler directly rather than through the loop, so
/// there is nothing to read -- but a case about what the server *asks* the
/// client needs somewhere for the asking to land.
const Recorder = struct {
    transport: lsp.Transport,
    gpa: std.mem.Allocator,
    written: std.ArrayList(u8) = .empty,

    fn init(gpa: std.mem.Allocator) Recorder {
        return .{
            .transport = .{ .vtable = &.{
                .readJsonMessage = readJsonMessage,
                .writeJsonMessage = writeJsonMessage,
            } },
            .gpa = gpa,
        };
    }

    fn deinit(self: *Recorder) void {
        self.written.deinit(self.gpa);
    }

    fn readJsonMessage(
        transport: *lsp.Transport,
        io: std.Io,
        allocator: std.mem.Allocator,
    ) lsp.Transport.ReadError![]u8 {
        _ = transport;
        _ = io;
        _ = allocator;
        return error.EndOfStream;
    }

    fn writeJsonMessage(
        transport: *lsp.Transport,
        io: std.Io,
        json_message: []const u8,
    ) lsp.Transport.WriteError!void {
        _ = io;
        const self: *Recorder = @fieldParentPtr("transport", transport);
        self.written.appendSlice(self.gpa, json_message) catch
            @panic("a write to an in-memory buffer cannot fail");
        self.written.append(self.gpa, '\n') catch
            @panic("a write to an in-memory buffer cannot fail");
    }
};

/// A workspace of one program on disk, and a handler rooted at it.
const Rooted = struct {
    dir: std.testing.TmpDir,
    handler: Handler,
    arena: std.heap.ArenaAllocator,

    /// One file of the workspace, at a path under its root.
    const File = struct { at: []const u8, text: []const u8 };

    fn init(gpa: std.mem.Allocator, text: []const u8) !Rooted {
        return initFiles(gpa, &.{.{ .at = "main.lin", .text = text }});
    }

    fn initFiles(gpa: std.mem.Allocator, files: []const File) !Rooted {
        var tmp = std.testing.tmpDir(.{ .iterate = true });
        errdefer tmp.cleanup();
        try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "linea.json", .data = "{}" });
        for (files) |f| {
            if (std.fs.path.dirname(f.at)) |parent| try tmp.dir.createDirPath(std.testing.io, parent);
            try tmp.dir.writeFile(std.testing.io, .{ .sub_path = f.at, .data = f.text });
        }

        return .{
            .dir = tmp,
            .handler = .{
                .gpa = gpa,
                .region_backing = gpa,
                .library = test_library.get(),
                .io = std.testing.io,
                .transport = undefined,
                .documents = .{ .gpa = gpa },
                .root = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}", .{tmp.sub_path}),
            },
            .arena = .init(gpa),
        };
    }

    fn deinit(self: *Rooted) void {
        self.handler.deinit();
        self.arena.deinit();
        self.dir.cleanup();
    }

    /// Opens the main file with `text`, as a client does before it sends a
    /// change to it.
    fn open(self: *Rooted, text: []const u8) !void {
        try self.handler.@"textDocument/didOpen"(self.arena.allocator(), .{ .textDocument = .{
            .uri = try self.main(),
            .languageId = .{ .custom_value = "linea" },
            .version = 1,
            .text = text,
        } });
    }

    /// The one file of the program, named the way a client names it.
    fn main(self: *Rooted) ![]const u8 {
        return self.pathAt("main.lin");
    }

    fn pathAt(self: *Rooted, at: []const u8) ![]const u8 {
        return std.fs.path.join(self.arena.allocator(), &.{ self.handler.root, at });
    }

    /// The names the index offers the program the workspace holds.
    fn offered(self: *Rooted) ![]const []const u8 {
        const a = self.arena.allocator();
        const program = try self.handler.entryFor(a, try self.main());
        const found = (try self.handler.indexOf()).offers(program, "");
        const out = try a.alloc([]const u8, found.len);
        for (out, found) |*name, e| name.* = e.name;
        return out;
    }

    /// The quick fixes the server offers for what it publishes about
    /// `main.lin`, which is the round trip a client makes: the diagnostics a
    /// code action request carries are the ones the client was shown.
    fn fixes(self: *Rooted) ![]const lsp.types.CodeAction.Result {
        return self.fixesFor("main.lin");
    }

    fn fixesFor(self: *Rooted, at: []const u8) ![]const lsp.types.CodeAction.Result {
        const a = self.arena.allocator();
        const path = try self.pathAt(at);
        const checked = try self.handler.check(a, path);
        const file = checked.fileNamed(path).?;
        const publication = try publish.Publication.init(a, checked);
        const diagnostics = try publication.forFile(a, file, self.handler.offset_encoding);

        return (try self.handler.@"textDocument/codeAction"(a, .{
            .textDocument = .{ .uri = path },
            .range = .{
                .start = .{ .line = 0, .character = 0 },
                .end = .{ .line = 0, .character = 0 },
            },
            .context = .{ .diagnostics = diagnostics },
        })).?;
    }

    /// What `main.lin` reads as once an offered action is applied to it.
    fn applied(self: *Rooted, action: lsp.types.CodeAction.Result) ![]const u8 {
        return self.appliedTo("main.lin", action);
    }

    fn appliedTo(self: *Rooted, at: []const u8, action: lsp.types.CodeAction.Result) ![]const u8 {
        const a = self.arena.allocator();
        const path = try self.pathAt(at);
        const text = (try self.handler.textOf(a, path)).?;
        const edits = action.code_action.edit.?.changes.?.map.get(path).?;
        return rename.applyTo(a, text, edits, self.handler.offset_encoding);
    }
};

/// The titles of the actions an answer holds, which is what a client shows.
fn titlesOf(gpa: std.mem.Allocator, found: []const lsp.types.CodeAction.Result) ![]const []const u8 {
    const out = try gpa.alloc([]const u8, found.len);
    for (out, found) |*title, action| title.* = action.code_action.title;
    return out;
}

test "an undefined name a module of the program is called is offered as that import" {
    var ws = try Rooted.initFiles(std.testing.allocator, &.{
        .{ .at = "main.lin", .text = "fn main() -> UInt8 {\n    ledger.size()\n}\n" },
        .{ .at = "ledger/l.lin", .text = "pub fn size() -> UInt8 { 7 }\n" },
    });
    defer ws.deinit();

    const found = try ws.fixes();
    try std.testing.expectEqual(@as(usize, 1), found.len);

    const action = found[0].code_action;
    try std.testing.expectEqualStrings("write `import ledger`: a module is reached through the import that names it", action.title);
    try std.testing.expectEqual(lsp.types.CodeAction.Kind.quickfix, action.kind.?);
    // The action names the diagnostic it resolves, which is what lets a client
    // clear the squiggle it was offered under.
    try std.testing.expectEqual(@as(usize, 1), action.diagnostics.?.len);
    try std.testing.expectEqualStrings("N-Undefined", action.diagnostics.?[0].code.?.string);

    try std.testing.expectEqualStrings(
        "import ledger\n\nfn main() -> UInt8 {\n    ledger.size()\n}\n",
        try ws.applied(found[0]),
    );
}

test "a nested module is offered a root-relative sibling import" {
    var ws = try Rooted.initFiles(std.testing.allocator, &.{
        .{ .at = "main.lin", .text = "import nested\n\nfn main() -> UInt8 { nested.value() }\n" },
        .{ .at = "nested/n.lin", .text = "pub fn value() -> UInt8 { ledger.size() }\n" },
        .{ .at = "ledger/l.lin", .text = "pub fn size() -> UInt8 { 7 }\n" },
    });
    defer ws.deinit();

    const found = try ws.fixesFor("nested/n.lin");
    try std.testing.expectEqual(@as(usize, 1), found.len);
    try std.testing.expectEqualStrings("write `import ledger`: a module is reached through the import that names it", found[0].code_action.title);
    try std.testing.expectEqualStrings(
        "import ledger\n\npub fn value() -> UInt8 { ledger.size() }\n",
        try ws.appliedTo("nested/n.lin", found[0]),
    );
}

test "a leaf two modules of the program share is offered as an import of each" {
    var ws = try Rooted.initFiles(std.testing.allocator, &.{
        .{ .at = "main.lin", .text = "fn main() -> UInt8 {\n    hash.digest()\n}\n" },
        .{ .at = "crypto/hash/h.lin", .text = "pub fn digest() -> UInt8 { 1 }\n" },
        .{ .at = "vault/hash/h.lin", .text = "pub fn digest() -> UInt8 { 2 }\n" },
    });
    defer ws.deinit();

    const found = try ws.fixes();
    const titles = try titlesOf(ws.arena.allocator(), found);
    try std.testing.expectEqual(@as(usize, 2), titles.len);

    // Two paths ending in the same element are two modules, and which of them
    // was meant is the reader's to say.
    try std.testing.expectEqualStrings("write `import crypto.hash`: a module is reached through the import that names it", titles[0]);
    try std.testing.expectEqualStrings("write `import vault.hash`: a module is reached through the import that names it", titles[1]);
}

test "a name a module exports but no module is called is offered no import" {
    var ws = try Rooted.initFiles(std.testing.allocator, &.{
        .{ .at = "main.lin", .text = "fn main() -> UInt8 {\n    size()\n}\n" },
        .{ .at = "ledger/l.lin", .text = "pub fn size() -> UInt8 { 7 }\n" },
    });
    defer ws.deinit();

    // What an import binds is the module, not what the module exports, so no
    // import written here makes a bare `size` name anything -- and one written
    // anyway would leave the name undefined and add an unused import beside it.
    try std.testing.expectEqual(@as(usize, 0), (try ws.fixes()).len);
}

test "a name the module already writes is offered no import" {
    var ws = try Rooted.initFiles(std.testing.allocator, &.{
        .{
            .at = "main.lin",
            .text = "import ledger\n\nfn main() -> UInt8 {\n    let m = ledger\n    m\n}\n",
        },
        .{ .at = "ledger/l.lin", .text = "pub fn size() -> UInt8 { 7 }\n" },
    });
    defer ws.deinit();

    // A module is a scope rather than a value, so naming one here reaches no
    // binding -- but the name is written in this module already, and a second
    // import of it collides with the first instead of binding anything.
    try std.testing.expectEqual(@as(usize, 0), (try ws.fixes()).len);
}

test "a name no module of the program is called is offered no import" {
    var ws = try Rooted.initFiles(std.testing.allocator, &.{
        .{ .at = "main.lin", .text = "fn main() -> UInt8 {\n    nope.size()\n}\n" },
        .{ .at = "ledger/l.lin", .text = "pub fn size() -> UInt8 { 7 }\n" },
    });
    defer ws.deinit();

    try std.testing.expectEqual(@as(usize, 0), (try ws.fixes()).len);
}

test "a diagnostic that is not an undefined name is offered nothing" {
    var ws = try Rooted.initFiles(std.testing.allocator, &.{
        .{
            .at = "main.lin",
            .text = "import ledger\n\nfn main() -> UInt8 {\n    ledger.size(1)\n}\n",
        },
        .{ .at = "ledger/l.lin", .text = "pub fn size() -> UInt8 { 7 }\n" },
    });
    defer ws.deinit();

    // Every name here reaches something, so what is left is an arity error --
    // a rule no import answers, and an action offered for it would be a fix
    // that does not fix.
    try std.testing.expectEqual(@as(usize, 0), (try ws.fixes()).len);
}

test "an import joins the imports the file already has" {
    var ws = try Rooted.initFiles(std.testing.allocator, &.{
        .{
            .at = "main.lin",
            .text = "import coins\n\nfn main() -> UInt8 {\n    coins.one() + ledger.size()\n}\n",
        },
        .{ .at = "coins/c.lin", .text = "pub fn one() -> UInt8 { 1 }\n" },
        .{ .at = "ledger/l.lin", .text = "pub fn size() -> UInt8 { 7 }\n" },
    });
    defer ws.deinit();

    const found = try ws.fixes();
    try std.testing.expectEqual(@as(usize, 1), found.len);

    // The grammar makes imports a prefix of the file, so a new one joins the
    // prefix rather than starting a second one.
    try std.testing.expectEqualStrings(
        "import coins\nimport ledger\n\nfn main() -> UInt8 {\n    coins.one() + ledger.size()\n}\n",
        try ws.applied(found[0]),
    );
}

test "a file with no imports takes one above what its first declaration is written with" {
    var ws = try Rooted.initFiles(std.testing.allocator, &.{
        .{
            .at = "main.lin",
            .text = "// What this program is for.\nfn main() -> UInt8 {\n    ledger.size()\n}\n",
        },
        .{ .at = "ledger/l.lin", .text = "pub fn size() -> UInt8 { 7 }\n" },
    });
    defer ws.deinit();

    const found = try ws.fixes();
    try std.testing.expectEqual(@as(usize, 1), found.len);

    // Above the comment block written directly on the declaration, because a
    // comment written directly above a declaration is written about it.
    try std.testing.expectEqualStrings(
        "import ledger\n\n// What this program is for.\nfn main() -> UInt8 {\n    ledger.size()\n}\n",
        try ws.applied(found[0]),
    );
}

test "a file changed on disk changes what the index offers" {
    var ws = try Rooted.init(std.testing.allocator, "pub fn before() -> UInt8 { 1 }\n");
    defer ws.deinit();

    const first = try ws.offered();
    try std.testing.expectEqual(@as(usize, 1), first.len);
    try std.testing.expectEqualStrings("before", first[0]);

    // Something that is not the editor rewrites the file, and the client's
    // watcher says so.
    try ws.dir.dir.writeFile(std.testing.io, .{
        .sub_path = "main.lin",
        .data = "pub fn after() -> UInt8 { 1 }\n",
    });
    try ws.handler.@"workspace/didChangeWatchedFiles"(ws.arena.allocator(), .{
        .changes = &.{.{ .uri = try ws.main(), .type = .Changed }},
    });

    const then = try ws.offered();
    try std.testing.expectEqual(@as(usize, 1), then.len);
    try std.testing.expectEqualStrings("after", then[0]);
}

test "a rename in a library two programs depend on edits both programs" {
    const program =
        \\import almanac
        \\
        \\fn main() -> UInt8 {
        \\    almanac.frost()
        \\}
        \\
    ;
    const dependent = "{ \"dependencies\": { \"almanac\": { \"path\": \"../almanac\" } } }";
    var ws = try Rooted.initFiles(std.testing.allocator, &.{
        .{ .at = "almanac/linea.json", .text = "{ \"kind\": \"library\", \"name\": \"almanac\" }" },
        .{ .at = "almanac/almanac.lin", .text = "pub fn frost() -> UInt8 { 1 }\n\npub fn thaw() -> UInt8 { frost() + 1 }\n" },
        .{ .at = "a/linea.json", .text = dependent },
        .{ .at = "a/main.lin", .text = program },
        .{ .at = "b/linea.json", .text = dependent },
        .{ .at = "b/main.lin", .text = program },
    });
    defer ws.deinit();
    // The workspace is the three projects and nothing above them.
    try ws.dir.dir.deleteFile(std.testing.io, "linea.json");
    const a = ws.arena.allocator();

    // From a use in one program, and from the declaration in the library.
    const asked = [_]struct { at: []const u8, line: u32, character: u32 }{
        .{ .at = "a/main.lin", .line = 3, .character = 12 },
        .{ .at = "almanac/almanac.lin", .line = 0, .character = 7 },
    };
    for (asked) |ask| {
        const edit = (try ws.handler.@"textDocument/rename"(a, .{
            .textDocument = .{ .uri = try ws.pathAt(ask.at) },
            .position = .{ .line = ask.line, .character = ask.character },
            .newName = "chill",
        })).?;
        const expected = [_]struct { path: []const u8, edits: usize }{
            .{ .path = "a/main.lin", .edits = 1 },
            .{ .path = "b/main.lin", .edits = 1 },
            .{ .path = "almanac/almanac.lin", .edits = 2 },
        };
        try std.testing.expectEqual(expected.len, edit.changes.?.map.count());
        for (expected) |want| {
            var it = edit.changes.?.map.iterator();
            const edits = while (it.next()) |entry| {
                if (std.mem.endsWith(u8, entry.key_ptr.*, want.path)) break entry.value_ptr.*;
            } else return error.TestExpectedEqual;
            try std.testing.expectEqual(want.edits, edits.len);
        }
    }
}

test "a rename in a shared library is offered beside a broken program that does not reach it" {
    const program =
        \\import almanac
        \\
        \\fn main() -> UInt8 {
        \\    almanac.frost()
        \\}
        \\
    ;
    const dependent = "{ \"dependencies\": { \"almanac\": { \"path\": \"../almanac\" } } }";
    var ws = try Rooted.initFiles(std.testing.allocator, &.{
        .{ .at = "almanac/linea.json", .text = "{ \"kind\": \"library\", \"name\": \"almanac\" }" },
        .{ .at = "almanac/almanac.lin", .text = "pub fn frost() -> UInt8 { 1 }\n" },
        .{ .at = "a/linea.json", .text = dependent },
        .{ .at = "a/main.lin", .text = program },
        // Depends on a library that is not there, and not on `almanac`.
        .{ .at = "broken/linea.json", .text = "{ \"dependencies\": { \"gone\": { \"path\": \"../gone\" } } }" },
        .{ .at = "broken/main.lin", .text = "fn main() -> UInt8 {\n    0\n}\n" },
    });
    defer ws.deinit();
    try ws.dir.dir.deleteFile(std.testing.io, "linea.json");
    const a = ws.arena.allocator();

    const edit = (try ws.handler.@"textDocument/rename"(a, .{
        .textDocument = .{ .uri = try ws.pathAt("a/main.lin") },
        .position = .{ .line = 3, .character = 12 },
        .newName = "chill",
    })).?;
    try std.testing.expectEqual(@as(usize, 2), edit.changes.?.map.count());
}

test "a rename in a shared library is refused where a program reaching it does not load, naming it" {
    const program =
        \\import almanac
        \\
        \\fn main() -> UInt8 {
        \\    almanac.frost()
        \\}
        \\
    ;
    var ws = try Rooted.initFiles(std.testing.allocator, &.{
        .{ .at = "almanac/linea.json", .text = "{ \"kind\": \"library\", \"name\": \"almanac\" }" },
        .{ .at = "almanac/almanac.lin", .text = "pub fn frost() -> UInt8 { 1 }\n" },
        .{ .at = "a/linea.json", .text = "{ \"dependencies\": { \"almanac\": { \"path\": \"../almanac\" } } }" },
        .{ .at = "a/main.lin", .text = program },
        // Depends on `almanac` and on a library that is not there.
        .{ .at = "broken/linea.json", .text = "{ \"dependencies\": { \"almanac\": { \"path\": \"../almanac\" }, \"gone\": { \"path\": \"../gone\" } } }" },
        .{ .at = "broken/main.lin", .text = program },
    });
    defer ws.deinit();
    try ws.dir.dir.deleteFile(std.testing.io, "linea.json");
    const a = ws.arena.allocator();
    var recorder = Recorder.init(std.testing.allocator);
    defer recorder.deinit();
    ws.handler.transport = &recorder.transport;

    try std.testing.expectError(rename.Refused.AProgramTheRenameReachesDoesNotLoad, ws.handler.@"textDocument/rename"(a, .{
        .textDocument = .{ .uri = try ws.pathAt("almanac/almanac.lin") },
        .position = .{ .line = 0, .character = 7 },
        .newName = "chill",
    }));
    try std.testing.expect(std.mem.indexOf(u8, recorder.written.items, "broken") != null);
    try std.testing.expect(std.mem.indexOf(u8, recorder.written.items, "does not load") != null);
}

test "a rename in a shared library is offered beside a program whose manifest cannot be read and that does not hold it" {
    var ws = try Rooted.initFiles(std.testing.allocator, &.{
        .{ .at = "almanac/linea.json", .text = "{ \"kind\": \"library\", \"name\": \"almanac\" }" },
        .{ .at = "almanac/almanac.lin", .text = "pub fn frost() -> UInt8 { 1 }\n" },
        .{ .at = "a/linea.json", .text = "{ \"dependencies\": { \"almanac\": { \"path\": \"../almanac\" } } }" },
        .{ .at = "a/main.lin", .text = "import almanac\n\nfn main() -> UInt8 {\n    almanac.frost()\n}\n" },
        // A manifest that will not parse names no library, so this program
        // holds nothing outside its own directory.
        .{ .at = "unread/linea.json", .text = "{ not json" },
        .{ .at = "unread/main.lin", .text = "fn main() -> UInt8 {\n    0\n}\n" },
    });
    defer ws.deinit();
    try ws.dir.dir.deleteFile(std.testing.io, "linea.json");
    const a = ws.arena.allocator();

    const edit = (try ws.handler.@"textDocument/rename"(a, .{
        .textDocument = .{ .uri = try ws.pathAt("a/main.lin") },
        .position = .{ .line = 3, .character = 12 },
        .newName = "chill",
    })).?;
    try std.testing.expectEqual(@as(usize, 2), edit.changes.?.map.count());
}

test "a rename in a shared library is refused where a program whose manifest cannot be read holds it, naming it" {
    var ws = try Rooted.initFiles(std.testing.allocator, &.{
        // The library sits inside a program whose manifest will not parse.
        .{ .at = "outer/linea.json", .text = "{ not json" },
        .{ .at = "outer/almanac/linea.json", .text = "{ \"kind\": \"library\", \"name\": \"almanac\" }" },
        .{ .at = "outer/almanac/almanac.lin", .text = "pub fn frost() -> UInt8 { 1 }\n" },
        .{ .at = "a/linea.json", .text = "{ \"dependencies\": { \"almanac\": { \"path\": \"../outer/almanac\" } } }" },
        .{ .at = "a/main.lin", .text = "import almanac\n\nfn main() -> UInt8 {\n    almanac.frost()\n}\n" },
    });
    defer ws.deinit();
    try ws.dir.dir.deleteFile(std.testing.io, "linea.json");
    const a = ws.arena.allocator();
    var recorder = Recorder.init(std.testing.allocator);
    defer recorder.deinit();
    ws.handler.transport = &recorder.transport;

    try std.testing.expectError(rename.Refused.AProgramTheRenameReachesDoesNotLoad, ws.handler.@"textDocument/rename"(a, .{
        .textDocument = .{ .uri = try ws.pathAt("a/main.lin") },
        .position = .{ .line = 3, .character = 12 },
        .newName = "chill",
    }));
    try std.testing.expect(std.mem.indexOf(u8, recorder.written.items, "outer") != null);
}

/// The almanac workspace with program `b` naming the library at `spelled`,
/// another path to the same directory, and the rename of `frost` from `a`.
/// Each document is edited once, at one URI, and `b` is among them.
fn expectRenamedThroughAnotherSpelling(ws: *Rooted, spelled: []const u8) !void {
    const a = ws.arena.allocator();
    const program =
        \\import almanac
        \\
        \\fn main() -> UInt8 {
        \\    almanac.frost()
        \\}
        \\
    ;
    try ws.dir.dir.createDirPath(std.testing.io, "b");
    try ws.dir.dir.writeFile(std.testing.io, .{ .sub_path = "b/main.lin", .data = program });
    try ws.dir.dir.writeFile(std.testing.io, .{ .sub_path = "b/linea.json", .data = try std.fmt.allocPrint(a, "{{ \"dependencies\": {{ \"almanac\": {{ \"path\": \"{s}\" }} }} }}", .{spelled}) });

    const edit = (try ws.handler.@"textDocument/rename"(a, .{
        .textDocument = .{ .uri = try ws.pathAt("a/main.lin") },
        .position = .{ .line = 3, .character = 12 },
        .newName = "chill",
    })).?;
    const expected = [_]struct { path: []const u8, edits: usize }{
        .{ .path = "a/main.lin", .edits = 1 },
        .{ .path = "b/main.lin", .edits = 1 },
        .{ .path = "almanac/almanac.lin", .edits = 2 },
    };
    try std.testing.expectEqual(expected.len, edit.changes.?.map.count());
    for (expected) |want| {
        var it = edit.changes.?.map.iterator();
        const edits = while (it.next()) |entry| {
            if (std.mem.endsWith(u8, entry.key_ptr.*, want.path)) break entry.value_ptr.*;
        } else return error.TestExpectedEqual;
        try std.testing.expectEqual(want.edits, edits.len);
    }
}

fn almanacWorkspace() !Rooted {
    var ws = try Rooted.initFiles(std.testing.allocator, &.{
        .{ .at = "almanac/linea.json", .text = "{ \"kind\": \"library\", \"name\": \"almanac\" }" },
        .{ .at = "almanac/almanac.lin", .text = "pub fn frost() -> UInt8 { 1 }\n\npub fn thaw() -> UInt8 { frost() + 1 }\n" },
        .{ .at = "a/linea.json", .text = "{ \"dependencies\": { \"almanac\": { \"path\": \"../almanac\" } } }" },
        .{ .at = "a/main.lin", .text = "import almanac\n\nfn main() -> UInt8 {\n    almanac.frost()\n}\n" },
    });
    errdefer ws.deinit();
    try ws.dir.dir.deleteFile(std.testing.io, "linea.json");
    return ws;
}

test "a rename in a shared library edits a program that names it through a symlink" {
    var ws = try almanacWorkspace();
    defer ws.deinit();
    try ws.dir.dir.symLink(std.testing.io, "almanac", "link", .{ .is_directory = true });
    try expectRenamedThroughAnotherSpelling(&ws, "../link");
}

test "a rename in a shared library edits a program that names it in another case" {
    var ws = try almanacWorkspace();
    defer ws.deinit();
    // Only a file system that ignores case reaches `Almanac` at `almanac`.
    ws.dir.dir.access(std.testing.io, "ALMANAC/linea.json", .{}) catch return error.SkipZigTest;
    try expectRenamedThroughAnotherSpelling(&ws, "../Almanac");
}

test "a manifest changed on disk changes which files the program holds" {
    var ws = try Rooted.initFiles(std.testing.allocator, &.{
        .{ .at = "main.lin", .text = "pub fn here() -> UInt8 { 1 }\n" },
        .{ .at = "src/main.lin", .text = "pub fn there() -> UInt8 { 2 }\n" },
    });
    defer ws.deinit();
    const a = ws.arena.allocator();

    // The root's own file and the module `src` beside it are both the
    // program's.
    try std.testing.expectEqual(@as(usize, 2), (try ws.offered()).len);
    _ = try ws.handler.check(a, try ws.main());
    try std.testing.expect(ws.handler.cached != null);

    // The manifest now says the program's files sit under `src`. No source
    // file changed. The held program is the one to publish again.
    try ws.dir.dir.writeFile(std.testing.io, .{ .sub_path = "linea.json", .data = "{ \"source\": \"src\" }" });
    try ws.handler.invalidate(a, try ws.pathAt("linea.json"));

    // What was checked under the old manifest is not kept, and the file
    // above `src` is no longer one of the program's.
    try std.testing.expect(ws.handler.cached == null);
    const program = try ws.handler.entryFor(a, try ws.pathAt("src/main.lin"));
    const then = (try ws.handler.indexOf()).offers(program, "");
    try std.testing.expectEqual(@as(usize, 1), then.len);
    try std.testing.expectEqualStrings("there", then[0].name);
}

test "a file deleted on disk is offered no longer" {
    var ws = try Rooted.init(std.testing.allocator, "pub fn gone() -> UInt8 { 1 }\n");
    defer ws.deinit();

    try std.testing.expectEqual(@as(usize, 1), (try ws.offered()).len);

    try ws.dir.dir.deleteFile(std.testing.io, "main.lin");
    try ws.handler.@"workspace/didChangeWatchedFiles"(ws.arena.allocator(), .{
        .changes = &.{.{ .uri = try ws.main(), .type = .Deleted }},
    });

    // A name whose file is gone is a name no import can reach, so offering it
    // is offering an import that does not resolve.
    try std.testing.expectEqual(@as(usize, 0), (try ws.offered()).len);
}

test "an edit to an open buffer changes what the index offers before the file is saved" {
    var ws = try Rooted.init(std.testing.allocator, "pub fn before() -> UInt8 { 1 }\n");
    defer ws.deinit();

    var recorder = Recorder.init(std.testing.allocator);
    defer recorder.deinit();
    ws.handler.transport = &recorder.transport;

    try std.testing.expectEqualStrings("before", (try ws.offered())[0]);

    const a = ws.arena.allocator();
    try ws.open("pub fn before() -> UInt8 { 1 }\n");
    try ws.handler.@"textDocument/didChange"(a, .{
        .textDocument = .{ .uri = try ws.main(), .version = 2 },
        .contentChanges = &.{.{ .text_document_content_change_whole_document = .{
            .text = "pub fn after() -> UInt8 { 1 }\n",
        } }},
    });

    // The file on disk still says `before`, so what the index now offers can
    // only have come from the text the server already holds.
    const then = try ws.offered();
    try std.testing.expectEqual(@as(usize, 1), then.len);
    try std.testing.expectEqualStrings("after", then[0]);
}

test "an index built while a buffer is open holds what the buffer says" {
    var ws = try Rooted.init(std.testing.allocator, "pub fn before() -> UInt8 { 1 }\n");
    defer ws.deinit();

    var recorder = Recorder.init(std.testing.allocator);
    defer recorder.deinit();
    ws.handler.transport = &recorder.transport;

    // The edit arrives before anything asked for the index, and a changed
    // manifest drops an index that was built: either way the next ask walks
    // the files on disk, which still say `before`.
    const a = ws.arena.allocator();
    try ws.open("pub fn before() -> UInt8 { 1 }\n");
    try ws.handler.@"textDocument/didChange"(a, .{
        .textDocument = .{ .uri = try ws.main(), .version = 2 },
        .contentChanges = &.{.{ .text_document_content_change_whole_document = .{
            .text = "pub fn after() -> UInt8 { 1 }\n",
        } }},
    });

    const offered = try ws.offered();
    try std.testing.expectEqual(@as(usize, 1), offered.len);
    try std.testing.expectEqualStrings("after", offered[0]);
}

test "byte-identical open and change retain the checked module" {
    const text = "fn main() -> UInt8 { 0 }\n";
    var ws = try Rooted.init(std.testing.allocator, text);
    defer ws.deinit();

    var recorder = Recorder.init(std.testing.allocator);
    defer recorder.deinit();
    ws.handler.transport = &recorder.transport;

    const a = ws.arena.allocator();
    const path = try ws.main();
    const before = try ws.handler.check(a, path);
    const before_file = before.fileNamed(path).?;
    const before_text = before.table.get(before_file).text.ptr;

    try ws.handler.@"textDocument/didOpen"(a, .{ .textDocument = .{
        .uri = path,
        .languageId = .{ .custom_value = "linea" },
        .version = 1,
        .text = text,
    } });
    const opened = try ws.handler.check(a, path);
    try std.testing.expect(before_text == opened.table.get(opened.fileNamed(path).?).text.ptr);

    try ws.handler.@"textDocument/didChange"(a, .{
        .textDocument = .{ .uri = path, .version = 2 },
        .contentChanges = &.{.{ .text_document_content_change_whole_document = .{ .text = text } }},
    });
    const changed = try ws.handler.check(a, path);
    try std.testing.expect(before_text == changed.table.get(changed.fileNamed(path).?).text.ptr);
}

test "a client granting no file watching is asked for none, and its buffers are still seen" {
    var ws = try Rooted.init(std.testing.allocator, "pub fn before() -> UInt8 { 1 }\n");
    defer ws.deinit();

    var recorder = Recorder.init(std.testing.allocator);
    defer recorder.deinit();
    ws.handler.transport = &recorder.transport;

    const a = ws.arena.allocator();
    try ws.handler.initialized(a, .{});

    // A capability the client did not grant is not one to assume: asking a
    // client that cannot register to register is a request it answers with an
    // error, and the server would have spent the round trip to learn it.
    try std.testing.expectEqual(@as(usize, 0), recorder.written.items.len);

    try std.testing.expectEqualStrings("before", (try ws.offered())[0]);

    try ws.open("pub fn before() -> UInt8 { 1 }\n");
    try ws.handler.@"textDocument/didChange"(a, .{
        .textDocument = .{ .uri = try ws.main(), .version = 2 },
        .contentChanges = &.{.{ .text_document_content_change_whole_document = .{
            .text = "pub fn after() -> UInt8 { 1 }\n",
        } }},
    });

    // Degraded to what the open buffers say, which is the whole of what such a
    // client can be told -- and not broken.
    try std.testing.expectEqualStrings("after", (try ws.offered())[0]);
}

test "a change the server cannot apply leaves the document as it was" {
    const gpa = std.testing.allocator;

    var handler: Handler = .{
        .gpa = gpa,
        .region_backing = gpa,
        .library = test_library.get(),
        .io = std.testing.io,
        // Nothing below reaches it: the notification stops before anything is
        // published.
        .transport = undefined,
        .documents = .{ .gpa = gpa },
    };
    defer handler.deinit();

    const held = "fn main() -> UInt8 {\n    0\n}\n";
    _ = try handler.documents.set("main.lin", held);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    // A change naming the region it replaces, which is the shape a server
    // advertising full-document sync never asked for.
    try std.testing.expectError(error.PartialChangeUnsupported, handler.@"textDocument/didChange"(
        arena.allocator(),
        .{
            .textDocument = .{ .uri = "main.lin", .version = 2 },
            .contentChanges = &.{
                .{ .text_document_content_change_partial = .{
                    .range = .{
                        .start = .{ .line = 1, .character = 4 },
                        .end = .{ .line = 1, .character = 5 },
                    },
                    .text = "nope",
                } },
            },
        },
    ));

    // What the server holds is what it held. Applied as nothing and reported
    // anyway, it would have published diagnostics about a document the editor
    // had already replaced.
    try std.testing.expectEqualStrings(held, handler.documents.open.get("main.lin").?);
}

test "a change to a document nobody opened opens nothing" {
    const gpa = std.testing.allocator;

    var handler: Handler = .{
        .gpa = gpa,
        .region_backing = gpa,
        .library = test_library.get(),
        .io = std.testing.io,
        // The notification is refused before anything is published.
        .transport = undefined,
        .documents = .{ .gpa = gpa },
    };
    defer handler.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    try std.testing.expectError(error.DocumentNotOpen, handler.@"textDocument/didChange"(
        arena.allocator(),
        .{
            .textDocument = .{ .uri = "main.lin", .version = 2 },
            .contentChanges = &.{.{ .text_document_content_change_whole_document = .{
                .text = "fn main() -> UInt8 { 0 }\n",
            } }},
        },
    ));
    try std.testing.expectError(error.DocumentNotOpen, handler.@"textDocument/didChange"(
        arena.allocator(),
        .{ .textDocument = .{ .uri = "main.lin", .version = 3 }, .contentChanges = &.{} },
    ));

    // Only `didOpen` makes a buffer the server reads instead of the disk.
    try std.testing.expectEqual(@as(u32, 0), handler.documents.open.count());
}

test "a whole change followed by a partial one applies neither" {
    const gpa = std.testing.allocator;

    var handler: Handler = .{
        .gpa = gpa,
        .region_backing = gpa,
        .library = test_library.get(),
        .io = std.testing.io,
        .transport = undefined,
        .documents = .{ .gpa = gpa },
    };
    defer handler.deinit();

    const held = "fn main() -> UInt8 {\n    0\n}\n";
    _ = try handler.documents.set("main.lin", held);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    try std.testing.expectError(error.PartialChangeUnsupported, handler.@"textDocument/didChange"(
        arena.allocator(),
        .{
            .textDocument = .{ .uri = "main.lin", .version = 2 },
            .contentChanges = &.{
                .{ .text_document_content_change_whole_document = .{ .text = "fn main() -> UInt8 { 1 }\n" } },
                .{ .text_document_content_change_partial = .{
                    .range = .{
                        .start = .{ .line = 0, .character = 0 },
                        .end = .{ .line = 0, .character = 2 },
                    },
                    .text = "fun",
                } },
            },
        },
    ));

    // The notification is one transition: refused as a whole, the buffer and
    // every answer computed from it stay as they were.
    try std.testing.expectEqualStrings(held, handler.documents.open.get("main.lin").?);
}

test "unrelated watched files retain clean analysis while exports refresh" {
    var ws = try Rooted.initFiles(std.testing.allocator, &.{
        .{ .at = "main.lin", .text = "import dep\nfn main() -> UInt8 { dep.value() }\n" },
        .{ .at = "dep/item.lin", .text = "pub fn value() -> UInt8 { 1 }\n" },
        .{ .at = "unused/item.lin", .text = "pub fn before() -> UInt8 { 2 }\n" },
    });
    defer ws.deinit();
    const a = ws.arena.allocator();
    const path = try ws.main();
    const checked = try ws.handler.check(a, path);
    try std.testing.expect(!checked.sink.hasErrors());
    const original = checked.table.get(checked.fileNamed(path).?).text.ptr;
    _ = try ws.offered();
    try ws.dir.dir.writeFile(std.testing.io, .{ .sub_path = "unused/item.lin", .data = "pub fn after() -> UInt8 { 3 }\n" });
    try ws.handler.@"workspace/didChangeWatchedFiles"(a, .{ .changes = &.{.{ .uri = try ws.pathAt("unused/item.lin"), .type = .Changed }} });
    try std.testing.expect(ws.handler.cached != null);
    try std.testing.expect(original == ws.handler.cached.?.of.table.get(ws.handler.cached.?.of.fileNamed(path).?).text.ptr);
    const offered = try ws.offered();
    var saw_after = false;
    for (offered) |name| {
        try std.testing.expect(!std.mem.eql(u8, name, "before"));
        saw_after = saw_after or std.mem.eql(u8, name, "after");
    }
    try std.testing.expect(saw_after);

    try ws.dir.dir.writeFile(std.testing.io, .{ .sub_path = "unused/added.lin", .data = "pub fn added() -> UInt8 { 4 }\n" });
    try ws.handler.@"workspace/didChangeWatchedFiles"(a, .{ .changes = &.{.{ .uri = try ws.pathAt("unused/added.lin"), .type = .Created }} });
    try std.testing.expect(ws.handler.cached != null);
    try ws.dir.dir.deleteFile(std.testing.io, "unused/added.lin");
    try ws.handler.@"workspace/didChangeWatchedFiles"(a, .{ .changes = &.{.{ .uri = try ws.pathAt("unused/added.lin"), .type = .Deleted }} });
    try std.testing.expect(ws.handler.cached != null);
}

test "watched dependency changes and missing imports invalidate analysis" {
    var ws = try Rooted.initFiles(std.testing.allocator, &.{
        .{ .at = "main.lin", .text = "import dep\nfn main() -> UInt8 { dep.value() }\n" },
        .{ .at = "dep/item.lin", .text = "pub fn value() -> UInt8 { 1 }\n" },
        .{ .at = "unused/item.lin", .text = "pub fn other() -> UInt8 { 2 }\n" },
    });
    defer ws.deinit();
    const a = ws.arena.allocator();
    const main = try ws.main();
    _ = try ws.handler.check(a, main);
    // A new sibling contributes declarations even though its FileId did not
    // exist in the analysis being invalidated.
    try ws.dir.dir.writeFile(std.testing.io, .{ .sub_path = "dep/extra.lin", .data = "pub struct Extra {}\n" });
    try ws.handler.@"workspace/didChangeWatchedFiles"(a, .{ .changes = &.{.{ .uri = try ws.pathAt("dep/extra.lin"), .type = .Created }} });
    try std.testing.expect(ws.handler.cached == null);
    _ = try ws.handler.check(a, main);
    try ws.dir.dir.writeFile(std.testing.io, .{ .sub_path = "dep/item.lin", .data = "pub fn value() -> Bool { true }\n" });
    try ws.handler.@"workspace/didChangeWatchedFiles"(a, .{ .changes = &.{.{ .uri = try ws.pathAt("dep/item.lin"), .type = .Changed }} });
    try std.testing.expect(ws.handler.cached == null);
    const mismatch = try ws.handler.check(a, main);
    try std.testing.expect(mismatch.sink.hasErrors());
    // An erroneous analysis conservatively observes every same-program edit.
    try ws.handler.@"workspace/didChangeWatchedFiles"(a, .{ .changes = &.{.{ .uri = try ws.pathAt("unused/item.lin"), .type = .Changed }} });
    try std.testing.expect(ws.handler.cached == null);

    try ws.dir.dir.deleteFile(std.testing.io, "dep/item.lin");
    try ws.dir.dir.deleteFile(std.testing.io, "dep/extra.lin");
    try ws.dir.dir.deleteDir(std.testing.io, "dep");
    const missing = try ws.handler.check(a, main);
    try std.testing.expect(missing.sink.hasErrors());
    try ws.dir.dir.createDirPath(std.testing.io, "dep");
    try ws.dir.dir.writeFile(std.testing.io, .{ .sub_path = "dep/item.lin", .data = "pub fn value() -> UInt8 { 1 }\n" });
    try ws.handler.@"workspace/didChangeWatchedFiles"(a, .{ .changes = &.{.{ .uri = try ws.pathAt("dep/item.lin"), .type = .Created }} });
    try std.testing.expect(ws.handler.cached == null);
    const repaired = try ws.handler.check(a, main);
    try std.testing.expect(!repaired.sink.hasErrors());
}

test "a file the program never reaches is not read, and one it reaches is read once" {
    // Comment lines, so each file is a program however long it is.
    const megabyte = "// " ++ "x" ** 60 ++ "\n";
    const reached = megabyte ** (1 << 14);
    const unreached = megabyte ** (1 << 15);
    var ws = try Rooted.initFiles(std.testing.allocator, &.{
        .{ .at = "main.lin", .text = "import kept\n\nfn main() -> UInt8 {\n    kept.size()\n}\n" },
        .{ .at = "kept/kept.lin", .text = reached ++ "pub fn size() -> UInt8 {\n    4\n}\n" },
        .{ .at = "notes/notes.lin", .text = unreached ++ "this is no program at all\n" },
    });
    defer ws.deinit();
    const a = ws.arena.allocator();

    const main_path = try ws.main();
    const listed_before = ws.arena.queryCapacity();
    const checked = try ws.handler.check(a, main_path);
    const listed = ws.arena.queryCapacity() - listed_before;

    // `notes` would not parse, and no import names it: nothing is reported
    // and it is no file of the program. `kept` is one, though the editor
    // never opened it.
    try std.testing.expectEqual(@as(usize, 0), checked.sink.items().len);
    try std.testing.expect(checked.fileNamed(try loader.canonical(a, try ws.pathAt("kept/kept.lin"))) != null);
    try std.testing.expect(checked.fileNamed(try loader.canonical(a, try ws.pathAt("notes/notes.lin"))) == null);

    // Listing the files read neither: what the request's arena grew by is
    // under either file's size. And the reached file is held once, though
    // two loads read the program: under twice its megabyte.
    try std.testing.expect(listed < reached.len);
    try std.testing.expect(checked.source_arena.queryCapacity() < 2 * reached.len);
    try std.testing.expect(checked.source_arena.queryCapacity() >= reached.len);
}

test "a program rewritten on disk while only a file it imports is open publishes its errors" {
    const gpa = std.testing.allocator;
    var ws = try Rooted.initFiles(gpa, &.{
        .{ .at = "main.lin", .text = "fn main() -> UInt8 {\n    0\n}\n" },
        .{ .at = "util/util.lin", .text = "pub fn value() -> UInt8 {\n    1\n}\n" },
    });
    defer ws.deinit();
    var recorder = Recorder.init(gpa);
    defer recorder.deinit();
    ws.handler.transport = &recorder.transport;

    const a = ws.arena.allocator();
    try ws.handler.@"textDocument/didOpen"(a, .{ .textDocument = .{
        .uri = try ws.pathAt("util/util.lin"),
        .languageId = .{ .custom_value = "linea" },
        .version = 1,
        .text = "pub fn value() -> UInt8 {\n    1\n}\n",
    } });
    // The program now imports `util`, which is open, and a `sub` that is not
    // there: what `linea check` reports for it is what the editor shows.
    try ws.dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.lin", .data = "import util\nimport sub\n\nfn main() -> UInt8 {\n    util.value()\n}\n" });
    try ws.handler.@"workspace/didChangeWatchedFiles"(a, .{ .changes = &.{.{ .uri = try ws.pathAt("main.lin"), .type = .Changed }} });

    const last = try lastPublished(a, recorder.written.items);
    const shown = last.get(try uri_mod.uriOf(a, try ws.pathAt("main.lin"))) orelse return error.TestExpectedPublished;
    const missing = for (shown) |d| {
        if (std.mem.indexOf(u8, d, "\"M-Import\"") != null) break true;
    } else false;
    try std.testing.expect(missing);
}

/// A small program held to the rule for what an editor is shown: each file's
/// published diagnostics are the union of what every check reaching it
/// reports, each as of its latest run. The checks are the program's, from its
/// root, and for each open document no import of the program reaches, its
/// module's, as `linea check` checks a file named alone.
const Workspace = struct {
    /// A chain of modules, each of which may import the next: the program,
    /// `lib`, `sub` and `util`. Each file's text is one of its variants, and
    /// any of them may be deleted from disk while closed.
    const paths = [_][]const u8{ "main.lin", "lib/l.lin", "sub/x.lin", "util/util.lin" };
    const imports = [_]?[]const u8{ "lib", "sub", "util", null };
    const functions = [_][]const u8{ "main", "low", "twice", "value" };
    const variant_count = [_]u8{ 4, 4, 4, 2 };
    /// Two spellings of one manifest, so rewriting it changes nothing it means.
    const manifests = [_][]const u8{ "{}", "{ \"kind\": \"program\" }" };

    /// Bit 0 of a variant imports the next module and calls it; bit 1, or bit
    /// 0 for the last module, makes the file's result the wrong type.
    fn text(gpa: std.mem.Allocator, file: usize, variant: u8) ![]u8 {
        const next = imports[file];
        const wrong = if (next == null) variant & 1 != 0 else variant & 2 != 0;
        const calls = next != null and variant & 1 != 0;
        var out: std.Io.Writer.Allocating = .init(gpa);
        errdefer out.deinit();
        const w = &out.writer;
        if (calls) try w.print("import {s}\n\n", .{next.?});
        try w.print("{s}fn {s}() -> UInt8 {{\n    ", .{ if (file == 0) "" else "pub ", functions[file] });
        if (wrong) try w.writeAll("true") else if (calls) try w.print("{s}.{s}()", .{ next.?, functions[file + 1] }) else try w.writeAll("1");
        try w.writeAll("\n}\n");
        return out.toOwnedSlice();
    }

    const Op = enum { open, change, close, save, disk, delete, recreate, manifest };
    const Step = struct { op: Op, file: usize, variant: u8 };
};

/// Each diagnostic the server last published for each file, by URI, as text.
fn lastPublished(gpa: std.mem.Allocator, written: []const u8) !std.StringHashMapUnmanaged([]const []const u8) {
    var last: std.StringHashMapUnmanaged([]const []const u8) = .empty;
    var lines = std.mem.splitScalar(u8, written, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const parsed = try std.json.parseFromSliceLeaky(std.json.Value, gpa, line, .{});
        const method = parsed.object.get("method") orelse continue;
        if (!std.mem.eql(u8, method.string, "textDocument/publishDiagnostics")) continue;
        const params = parsed.object.get("params").?.object;
        const listed = params.get("diagnostics").?.array.items;
        const texts = try gpa.alloc([]const u8, listed.len);
        for (listed, texts) |d, *t| t.* = try std.json.Stringify.valueAlloc(gpa, d, .{});
        try last.put(gpa, params.get("uri").?.string, texts);
    }
    return last;
}

/// What the rule says each file shows, by URI: the union over the program's
/// check and each open document's module check where the program does not
/// reach it, computed afresh from the texts the editor and the disk hold. A
/// file deleted from disk and not open is not among them.
///
/// The program's check counts once an open document it holds has been seen,
/// `program_seen`, which this sets: a check, once it ran, keeps what it
/// reported after its documents close, and none reports before it reaches
/// an open document.
fn expectedPublished(
    gpa: std.mem.Allocator,
    root: []const u8,
    manifest: []const u8,
    texts: []const ?[]const u8,
    open: []const bool,
    program_seen: *bool,
) !std.StringHashMapUnmanaged(std.StringArrayHashMapUnmanaged(void)) {
    var files: std.ArrayList(loader.InMemoryFile) = .empty;
    try files.append(gpa, .{ .path = try std.fs.path.join(gpa, &.{ root, loader.manifest_name }), .text = manifest });
    for (Workspace.paths, texts) |at, held| {
        const t = held orelse continue;
        try files.append(gpa, .{ .path = try std.fs.path.join(gpa, &.{ root, at }), .text = t });
    }

    var program = try analysis.onDisk(gpa, gpa, test_library.get(), files.items, root, null, std.testing.io);
    for (Workspace.paths, open) |at, is_open| {
        if (is_open and program.fileNamed(try std.fs.path.join(gpa, &.{ root, at })) != null) program_seen.* = true;
    }
    var checks: std.ArrayList(analysis.Analysis) = .empty;
    if (program_seen.*) try checks.append(gpa, program) else program.deinit();
    var modules: std.StringHashMapUnmanaged(void) = .empty;
    for (Workspace.paths, open) |at, is_open| {
        if (!is_open) continue;
        const path = try std.fs.path.join(gpa, &.{ root, at });
        if (program_seen.* and checks.items[0].fileNamed(path) != null) continue;
        const dir = std.fs.path.dirname(path).?;
        if ((try modules.getOrPut(gpa, dir)).found_existing) continue;
        try checks.append(gpa, try analysis.onDisk(gpa, gpa, test_library.get(), files.items, root, dir, std.testing.io));
    }

    var expected: std.StringHashMapUnmanaged(std.StringArrayHashMapUnmanaged(void)) = .empty;
    for (checks.items) |*checked| {
        defer checked.deinit();
        const publication = try publish.Publication.init(gpa, checked);
        var it = publish.files(&checked.program);
        while (it.next()) |file| {
            const uri = try uri_mod.uriOf(gpa, checked.table.get(file).path);
            const set = try expected.getOrPut(gpa, uri);
            if (!set.found_existing) set.value_ptr.* = .empty;
            for (try publication.forFile(gpa, file, .@"utf-16")) |d| {
                const once = try std.json.Stringify.valueAlloc(gpa, d, .{ .emit_null_optional_fields = false });
                const value = try std.json.parseFromSliceLeaky(std.json.Value, gpa, once, .{});
                try set.value_ptr.put(gpa, try std.json.Stringify.valueAlloc(gpa, value, .{}), {});
            }
        }
    }
    return expected;
}

fn lessText(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

test "slow: every file shows what each check reaching it reports, after any sequence of edits" {
    try slow_tests.skipUnlessRun();
    const gpa = std.testing.allocator;
    const sequences = 6;
    const steps_each = 12;
    const count = Workspace.paths.len;

    for (0..sequences) |seed| {
        var scratch = std.heap.ArenaAllocator.init(gpa);
        defer scratch.deinit();
        const s = scratch.allocator();
        var initial: [count]Rooted.File = undefined;
        var disk: [count]?[]const u8 = undefined;
        var buffer: [count]?[]const u8 = .{null} ** count;
        for (Workspace.paths, &initial, &disk, 0..) |at, *f, *held, file| {
            const t = try Workspace.text(s, file, 0);
            held.* = t;
            f.* = .{ .at = at, .text = t };
        }
        var manifest: usize = 0;
        var ws = try Rooted.initFiles(gpa, &initial);
        defer ws.deinit();
        var recorder = Recorder.init(gpa);
        defer recorder.deinit();
        ws.handler.transport = &recorder.transport;

        var program_seen = false;
        var prng = std.Random.DefaultPrng.init(seed);
        const random = prng.random();
        var steps: std.ArrayList(Workspace.Step) = .empty;
        for (0..steps_each) |_| {
            const file = random.uintLessThan(usize, count);
            const variant = random.uintLessThan(u8, Workspace.variant_count[file]);
            const op: Workspace.Op = if (random.uintLessThan(u8, 12) == 0)
                .manifest
            else if (buffer[file] != null)
                ([_]Workspace.Op{ .change, .close, .save })[random.uintLessThan(usize, 3)]
            else if (disk[file] == null)
                ([_]Workspace.Op{ .open, .recreate })[random.uintLessThan(usize, 2)]
            else
                ([_]Workspace.Op{ .open, .disk, .delete })[random.uintLessThan(usize, 3)];
            try steps.append(s, .{ .op = op, .file = file, .variant = variant });

            var step_arena = std.heap.ArenaAllocator.init(gpa);
            defer step_arena.deinit();
            const a = step_arena.allocator();
            const path = try ws.pathAt(Workspace.paths[file]);
            const written = try Workspace.text(s, file, variant);
            switch (op) {
                .open => {
                    buffer[file] = written;
                    try ws.handler.@"textDocument/didOpen"(a, .{ .textDocument = .{ .uri = path, .languageId = .{ .custom_value = "linea" }, .version = 1, .text = written } });
                },
                .change => {
                    buffer[file] = written;
                    try ws.handler.@"textDocument/didChange"(a, .{ .textDocument = .{ .uri = path, .version = 2 }, .contentChanges = &.{.{ .text_document_content_change_whole_document = .{ .text = written } }} });
                },
                .close => {
                    buffer[file] = null;
                    try ws.handler.@"textDocument/didClose"(a, .{ .textDocument = .{ .uri = path } });
                },
                .save, .disk, .recreate => {
                    const saved = if (op == .save) buffer[file].? else written;
                    const existed = disk[file] != null;
                    disk[file] = saved;
                    try ws.dir.dir.writeFile(std.testing.io, .{ .sub_path = Workspace.paths[file], .data = saved });
                    try ws.handler.@"workspace/didChangeWatchedFiles"(a, .{ .changes = &.{.{ .uri = path, .type = if (existed) .Changed else .Created }} });
                },
                .delete => {
                    disk[file] = null;
                    try ws.dir.dir.deleteFile(std.testing.io, Workspace.paths[file]);
                    try ws.handler.@"workspace/didChangeWatchedFiles"(a, .{ .changes = &.{.{ .uri = path, .type = .Deleted }} });
                },
                .manifest => {
                    manifest = 1 - manifest;
                    try ws.dir.dir.writeFile(std.testing.io, .{ .sub_path = loader.manifest_name, .data = Workspace.manifests[manifest] });
                    try ws.handler.@"workspace/didChangeWatchedFiles"(a, .{ .changes = &.{.{ .uri = try ws.pathAt(loader.manifest_name), .type = .Changed }} });
                },
            }

            var texts: [count]?[]const u8 = undefined;
            var open: [count]bool = undefined;
            for (&texts, &open, buffer, disk) |*t, *o, held, on_disk| {
                t.* = held orelse on_disk;
                o.* = held != null;
            }
            const expected = try expectedPublished(a, ws.handler.root, Workspace.manifests[manifest], &texts, &open, &program_seen);
            const got = try lastPublished(a, recorder.written.items);
            for (Workspace.paths) |at| {
                const uri = try uri_mod.uriOf(a, try ws.pathAt(at));
                const want = try a.dupe([]const u8, if (expected.get(uri)) |set| set.keys() else &.{});
                const have = try a.dupe([]const u8, got.get(uri) orelse &.{});
                std.mem.sort([]const u8, want, {}, lessText);
                std.mem.sort([]const u8, have, {}, lessText);
                const same = want.len == have.len and for (want, have) |w, h| {
                    if (!std.mem.eql(u8, w, h)) break false;
                } else true;
                if (same) continue;
                std.debug.print("seed {d}: after {d} step(s), `{s}` shows {d} diagnostic(s) where its checks report {d}\n", .{ seed, steps.items.len, at, have.len, want.len });
                for (steps.items) |st| std.debug.print("  {t} {s} variant {d}\n", .{ st.op, Workspace.paths[st.file], st.variant });
                for (want) |w| std.debug.print("  expected {s}\n", .{w});
                for (have) |h| std.debug.print("  published {s}\n", .{h});
                return error.TestExpectedEqual;
            }
        }
    }
}
