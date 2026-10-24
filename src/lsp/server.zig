const std = @import("std");
const lsp = @import("lsp");
const Documents = @import("documents.zig").Documents;
const loader = @import("../driver/loader.zig");
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
    const Cached = struct {
        /// The entry the analysis was checked from. Owned, because the
        /// resolution it was copied from lives on a message's arena.
        entry: []u8,
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
    /// else is: a change on disk is never a walk. An analysis affected by a
    /// changed file is dropped so the next request checks it again;
    /// publishing from here instead would check one module
    /// per notification, and a checkout delivers one notification per file it
    /// touched.
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
        // A file the held program embeds is nothing an editor shows, so no
        // document event follows its change: the program is checked again and
        // published from here, once however many of its files the
        // notification names, or what the editor shows about it stays as it
        // was.
        var republish: ?[]const u8 = null;
        for (params.changes) |change| {
            const path = try uri_mod.pathOf(arena, change.uri);
            if (republish == null) republish = try handler.embeddedBy(arena, path);
            try handler.invalidate(arena, path);
            try handler.freshen(arena, path);
        }
        if (republish) |entry| try handler.report(arena, entry);
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
        try handler.report(arena, path);
    }

    /// Full-text sync only, so `contentChanges` holds exactly one whole
    /// document per notification -- the shape `initialize` advertised is the
    /// only one a compliant client sends.
    ///
    /// A change naming the region it replaces is one this server cannot apply,
    /// and it stops the notification. Dropped instead, the text the server
    /// held was no longer the text the editor held, and everything below
    /// republished diagnostics about a document nobody was looking at --
    /// confidently wrong rather than absent.
    pub fn @"textDocument/didChange"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.TextDocument.DidChangeParams,
    ) !void {
        const path = try uri_mod.pathOf(arena, params.textDocument.uri);
        var changed = false;
        for (params.contentChanges) |change| switch (change) {
            .text_document_content_change_whole_document => |whole| {
                changed = (try handler.documents.set(path, whole.text)) != .unchanged or changed;
            },
            .text_document_content_change_partial => return error.PartialChangeUnsupported,
        };
        const text = handler.documents.open.get(path).?;
        if (!handler.cachedTextMatches(path, text)) try handler.invalidate(arena, path);
        if (changed) try handler.freshen(arena, path);
        try handler.report(arena, path);
    }

    pub fn @"textDocument/didClose"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.TextDocument.DidCloseParams,
    ) !void {
        const path = try uri_mod.pathOf(arena, params.textDocument.uri);
        handler.documents.close(path);
        // The buffer is gone, so the module now reads that file from disk, and
        // so does what the index holds for it.
        try handler.invalidate(arena, path);
        try handler.freshen(arena, path);
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
    /// The program the server sees is the one rooted at the file the editor
    /// opened. A sibling program importing this module is not in it, so its
    /// uses are not among these and are left as they were.
    pub fn @"textDocument/rename"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.rename.Params,
    ) !?lsp.types.WorkspaceEdit {
        const path = try uri_mod.pathOf(arena, params.textDocument.uri);
        const checked = try handler.check(arena, path);
        const file = checked.fileNamed(path) orelse return null;

        var refused_kind: ?name_case.Kind = null;
        return rename.forPositionReporting(
            arena,
            handler.io,
            checked,
            file,
            params.position,
            handler.offset_encoding,
            handler.root,
            params.newName,
            &refused_kind,
        ) catch |err| {
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
    /// Costs one check of the module, or nothing where the module held is
    /// already the one asked about. The result is borrowed from the handler
    /// and stays valid until the next document changes; `arena` carries only
    /// what the resolution needed.
    fn check(handler: *Handler, arena: std.mem.Allocator, path: []const u8) !*const analysis.Analysis {
        const root = try handler.rootFor(arena, path);
        const entry = root.entry;
        if (handler.cached) |*held| {
            if (std.mem.eql(u8, held.entry, entry)) return &held.of;
        }

        const files = try handler.documents.filesFor(arena, handler.io, root);

        // The analysis copies what it was given, so the buffers above are the
        // caller's business from here and the message's arena may reclaim
        // them whenever it likes.
        var fresh = try analysis.onDisk(handler.gpa, handler.region_backing, handler.library, files, entry, handler.io);
        errdefer fresh.deinit();
        const key = try handler.gpa.dupe(u8, entry);

        handler.drop();
        handler.cached = .{ .entry = key, .of = fresh };
        try handler.watchEmbeds(arena, &handler.cached.?.of);
        return &handler.cached.?.of;
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
    /// Costs one walk of the workspace the first time and nothing after it.
    /// Borrowed from the handler, and valid until the root is replaced.
    ///
    /// A workspace nobody has named holds no programs, so this reached before
    /// `initialize` says which directory the client opened is an index of
    /// nothing rather than an index of wherever the editor started the server.
    fn indexOf(handler: *Handler) !*workspace.Index {
        if (handler.index == null) {
            handler.index = try workspace.Index.build(handler.gpa, handler.io, handler.root);
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

    /// Asks the client to say when a `.lin` file under the workspace changes
    /// outside the editor.
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
        var watcher: std.json.ObjectMap = .empty;
        try watcher.put(arena, "globPattern", .{ .string = "**/*.lin" });
        var watchers: std.json.Array = .init(arena);
        try watchers.append(.{ .object = watcher });
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

    /// Releases the held analysis, so the next request checks again.
    fn drop(handler: *Handler) void {
        if (handler.cached) |*held| {
            held.of.deinit();
            handler.gpa.free(held.entry);
            handler.cached = null;
        }
    }

    /// Whether the held analysis already describes these exact document bytes.
    fn cachedTextMatches(handler: *const Handler, path: []const u8, text: []const u8) bool {
        const held = if (handler.cached) |*cached| &cached.of else return false;
        const file = held.fileNamed(path) orelse return false;
        return std.mem.eql(u8, held.table.get(file).text, text);
    }

    /// The entry of the held program when it embeds `path`, read or not, or
    /// null. Copied into `arena`, since invalidating releases the analysis.
    fn embeddedBy(handler: *Handler, arena: std.mem.Allocator, path: []const u8) !?[]const u8 {
        const held = handler.cached orelse return null;
        const named = try loader.canonical(arena, loader.trimmedEntry(path));
        for (held.of.program.embeds.watched) |watched| {
            if (std.mem.eql(u8, watched, named)) return try arena.dupe(u8, held.entry);
        }
        return null;
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
    /// No dependency index is rebuilt.
    fn invalidate(handler: *Handler, arena: std.mem.Allocator, path: []const u8) !void {
        const held = handler.cached orelse return;
        const named = try loader.canonical(arena, loader.trimmedEntry(path));
        if (held.of.fileNamed(named) != null) {
            handler.drop();
            return;
        }
        // A file the program embeds is as much its input as a source is, and
        // so is one it names that could not be read.
        for (held.of.program.embeds.watched) |watched| {
            if (std.mem.eql(u8, watched, named)) {
                handler.drop();
                return;
            }
        }
        const directory = std.fs.path.dirname(named) orelse ".";
        for (held.of.program.modules) |module| {
            if (std.mem.eql(u8, module.dir, directory)) {
                handler.drop();
                return;
            }
        }
        if (held.of.sink.hasErrors()) {
            const entry = try handler.entryFor(arena, named);
            if (std.mem.eql(u8, held.entry, entry)) handler.drop();
        }
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

    /// Checks the module a document belongs to and tells the client what is
    /// wrong with every file of it.
    ///
    /// Every file, not the edited one: a module's files see each other's
    /// declarations, so a change in one moves the diagnostics in its
    /// siblings, and a server that published only what was typed in leaves
    /// the others showing what the program used to say. A file with nothing
    /// wrong is published as an empty list, which is how the protocol says a
    /// file is clean.
    ///
    /// Costs one check of the module, which is what the answer being right
    /// across files costs, plus one pass over each published file's
    /// diagnostics.
    fn report(handler: *Handler, arena: std.mem.Allocator, path: []const u8) !void {
        const checked = try handler.check(arena, path);

        const publication = try publish.Publication.init(arena, checked);
        var it = publish.files(&checked.program);
        while (it.next()) |file| {
            const diagnostics = try publication.forFile(arena, file, handler.offset_encoding);
            try handler.transport.writeNotification(
                handler.io,
                arena,
                "textDocument/publishDiagnostics",
                lsp.types.publish_diagnostics.Params,
                .{
                    .uri = try uri_mod.uriOf(arena, checked.table.get(file).path),
                    .diagnostics = diagnostics,
                },
                .{ .emit_null_optional_fields = false },
            );
        }
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
