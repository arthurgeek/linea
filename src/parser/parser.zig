const std = @import("std");
const cloneColumns = @import("../support/columns.zig").cloneExact;
const tracy = @import("../support/tracy.zig");
const testing = std.testing;

const Span = @import("../support/span.zig").Span;
const source_mod = @import("../support/source.zig");
const Source = source_mod.Source;
const FileId = source_mod.FileId;
const Sink = @import("../diagnostics/sink.zig").Sink;
const Interner = @import("../support/interner.zig").Interner;
const StringId = @import("../support/interner.zig").StringId;
const Code = @import("../diagnostics/diagnostic.zig").Code;
const Label = @import("../diagnostics/diagnostic.zig").Label;
const lexer_mod = @import("../lexer/lexer.zig");
const tokenize = lexer_mod.tokenize;
const tokenizeInto = lexer_mod.tokenizeInto;
const token = @import("../lexer/token.zig");
const Tag = token.Tag;
const TokenId = token.TokenId;
const TokenRange = token.TokenRange;
const TokenList = token.TokenList;
const Cursor = @import("cursor.zig").Cursor;
const ast_mod = @import("../syntax/ast.zig");
const Ast = ast_mod.Ast;
const FilePart = ast_mod.FilePart;
const dumpAst = @import("../syntax/dump.zig").dumpAst;
const node = @import("../syntax/node.zig");
const format_spec = @import("../syntax/format_spec.zig");
const Expr = node.Expr;
const ExprId = node.ExprId;
const StmtId = node.StmtId;

/// The help for a parenthesised type or expression holding one component and
/// a trailing comma, and the one for a tuple holding too many of either.
const one_component_help = "`(x)` groups `x`; drop the comma, or add a second component";
const too_many_help = "give a struct names past eight parts";
const remove_written_unit = "remove `-> ()`";
const omitted_unit_label = "a function writing no result returns `()`";

const delimiter_unknown = std.math.maxInt(u32);
const delimiter_invalid = delimiter_unknown - 1;

/// Parses a token stream into a syntax tree.
///
/// Cannot fail on malformed input: unparseable regions become `err` nodes and
/// the tree is always complete. The only errors are allocation failures.
/// Consumes `tokens`, including on allocation failure.
pub fn parse(
    gpa: std.mem.Allocator,
    source: *const Source,
    file: FileId,
    tokens: TokenList,
    sink: *Sink,
) std.mem.Allocator.Error!Ast {
    const zone = tracy.beginZone(@src(), "parse");
    defer zone.end();

    var builder = Ast.Builder.init(gpa);
    errdefer builder.deinit();

    {
        var owned_tokens = tokens;
        errdefer owned_tokens.deinit(gpa);
        const delimiter_ends = try gpa.alloc(u32, tokens.len);
        defer gpa.free(delimiter_ends);
        @memset(delimiter_ends, delimiter_unknown);

        var p: Parser = .{
            .gpa = gpa,
            .cursor = Cursor.init(tokens.slice(), source.text, 0, @intCast(tokens.len)),
            .builder = &builder,
            .sink = sink,
            .file = file,
            .delimiter_base = 0,
            .delimiter_ends = delimiter_ends,
        };
        try p.parseProgram();
    }
    return builder.finishOne(source.path, source.text, file, tokens);
}

/// Builds one tree out of several modules, each of several files.
///
/// A compilation is one tree rather than one per module for the same reason a
/// module is one tree rather than one per file: ids that run across the whole
/// thing let every later pass stay a walk over a representation, and the
/// boundaries that matter are recorded as ranges rather than as separate
/// arenas a pass would have to be taught about.
///
/// Modules arrive one at a time because which module comes next is read from
/// the imports of the one just parsed.
/// One file of a module: its bytes, and the id the file table gave them.
///
/// One value rather than two lists that have to line up. A `FilePart` pairs
/// the two for every span the tree goes on to hold, so a caller that lined
/// them up wrongly would hand every later pass an offset into the wrong file
/// -- and the only thing that said they agreed was an assert on their length.
pub const ParsedFile = struct {
    file: FileId,
    source: Source,
};

pub const Modules = struct {
    gpa: std.mem.Allocator,
    sink: *Sink,
    interner: *Interner,
    builder: Ast.Builder,
    tokens: TokenList = .empty,
    parts: std.ArrayList(FilePart) = .empty,

    pub fn init(gpa: std.mem.Allocator, sink: *Sink, interner: *Interner) Modules {
        return .{
            .gpa = gpa,
            .sink = sink,
            .interner = interner,
            .builder = Ast.Builder.init(gpa),
        };
    }

    /// Starts with an immutable source tree whose IDs remain an exact prefix.
    pub fn initPrefix(
        gpa: std.mem.Allocator,
        sink: *Sink,
        interner: *Interner,
        source: *const Ast,
    ) std.mem.Allocator.Error!Modules {
        var out: Modules = .{
            .gpa = gpa,
            .sink = sink,
            .interner = interner,
            .builder = try Ast.Builder.initPrefix(gpa, source),
        };
        errdefer out.deinit();

        out.tokens = try cloneColumns(token.Token, gpa, source.tokens);
        try out.parts.appendSlice(gpa, source.parts);
        return out;
    }

    /// Appends a cached generated suffix after all destination source syntax.
    /// Both trees share their source prefix and the complete cached interner.
    /// Generated source bytes are borrowed and must outlive the resulting AST.
    pub fn appendGenerated(self: *Modules, source: *const Ast, expanded: *const Ast) std.mem.Allocator.Error!@import("../syntax/relocation.zig").Relocation {
        const relocation_mod = @import("../syntax/relocation.zig");
        var destination = self.view();
        const relocation: relocation_mod.Relocation = .{ .source = relocation_mod.Mark.of(source), .destination = relocation_mod.Mark.of(&destination) };
        inline for (@typeInfo(Ast).@"struct".fields) |field| {
            const start = @field(relocation.source, field.name);
            const column = @field(expanded, field.name);
            if (comptime std.mem.eql(u8, field.name, "tokens")) {
                for (start..column.len) |i| try self.tokens.append(self.gpa, column.get(i));
            } else if (comptime std.mem.eql(u8, field.name, "parts")) {
                for (column[start..]) |row| try self.parts.append(self.gpa, relocation.value(row));
            } else if (comptime std.mem.eql(u8, field.name, "exprs") or std.mem.eql(u8, field.name, "stmts") or std.mem.eql(u8, field.name, "decls")) {
                for (start..column.len) |i| try @field(self.builder, field.name).append(self.gpa, relocation.value(column.get(i)));
            } else if (comptime std.mem.eql(u8, field.name, "extra")) {
                try self.builder.extra.appendSlice(self.gpa, column[start..]);
            } else {
                for (column[start..]) |row| try @field(self.builder, field.name).append(self.gpa, relocation.value(row));
            }
        }
        for (relocation.source.exprs..expanded.exprs.len) |i| relocation.extra(expanded.exprs.get(i), expanded.extra, self.builder.extra.items);
        return relocation;
    }

    pub fn deinit(self: *Modules) void {
        self.builder.deinit();
        self.tokens.deinit(self.gpa);
        self.parts.deinit(self.gpa);
    }

    /// Parses one module's files, and returns the declarations they added.
    pub fn add(
        self: *Modules,
        files: []const ParsedFile,
    ) std.mem.Allocator.Error!node.DeclRange {
        std.debug.assert(files.len > 0);

        const zone = tracy.beginZone(@src(), "parse.add");
        defer zone.end();

        const first = self.builder.declMark();
        const from = self.parts.items.len;

        var at: u32 = if (from == 0) 0 else self.parts.items[from - 1].token_end;
        for (files) |*f| {
            try tokenizeInto(self.gpa, &f.source, f.file, self.sink, self.interner, &self.tokens);
            try self.parts.append(self.gpa, .{
                .file = f.file,
                .path = f.source.path,
                .source = f.source.text,
                .token_start = at,
                .token_end = @intCast(self.tokens.len),
                // Filled in by the parse below, which is what decides them.
                .decl_start = 0,
                .decl_end = 0,
                .stmt_start = 0,
                .stmt_end = 0,
                .expr_start = 0,
                .expr_end = 0,
            });
            // Each file's stream ends in its own `eof`, which is where its
            // parse stops; the next file's first token is the one after it.
            at = @intCast(self.tokens.len);
        }

        const z_parse = tracy.beginZone(@src(), "parse");
        defer z_parse.end();
        for (self.parts.items[from..], files) |*part, *f| {
            part.decl_start = self.builder.declMark();
            part.stmt_start = self.builder.stmtMark();
            part.expr_start = self.builder.exprMark();

            const delimiter_ends = try self.gpa.alloc(u32, part.token_end - part.token_start);
            defer self.gpa.free(delimiter_ends);
            @memset(delimiter_ends, delimiter_unknown);
            var p: Parser = .{
                .gpa = self.gpa,
                .cursor = Cursor.init(self.tokens.slice(), f.source.text, part.token_start, part.token_end),
                .builder = &self.builder,
                .sink = self.sink,
                .file = part.file,
                .delimiter_base = part.token_start,
                .delimiter_ends = delimiter_ends,
            };
            try p.parseProgram();

            // What this file added, which is every node the builder took
            // while its tokens were being read.
            part.decl_end = self.builder.declMark();
            part.stmt_end = self.builder.stmtMark();
            part.expr_end = self.builder.exprMark();
        }

        return .{ .start = first, .end = self.builder.declMark() };
    }

    /// What has been parsed so far, read-only.
    ///
    /// Borrowed, and valid only until the next `add`: every field is a slice
    /// into storage that still grows. This exists so the loader can read the
    /// imports of the module it just parsed with the same accessors every
    /// later pass uses, rather than a second set that could disagree. Never
    /// deinit one.
    pub fn view(self: *Modules) Ast {
        return .{
            .parts = self.parts.items,
            .tokens = self.tokens.slice(),
            .exprs = self.builder.exprs.slice(),
            .stmts = self.builder.stmts.slice(),
            .blocks = self.builder.blocks.items,
            .block_stmts = self.builder.block_stmts.items,
            .decls = self.builder.decls.slice(),
            .decl_attribute_groups = self.builder.decl_attribute_groups.items,
            .params = self.builder.params.items,
            .captures = self.builder.captures.items,
            .type_params = self.builder.type_params.items,
            .bounds = self.builder.bounds.items,
            .where_predicates = self.builder.where_predicates.items,
            .contracts = self.builder.contracts.items,
            .contract_steps = self.builder.contract_steps.items,
            .derive_traits = self.builder.derive_traits.items,
            .attribute_items = self.builder.attribute_items.items,
            .attribute_groups = self.builder.attribute_groups.items,
            .template_requirements = self.builder.template_requirements.items,
            .type_refs = self.builder.type_refs.items,
            .callable_types = self.builder.callable_types.items,
            .variants = self.builder.variants.items,
            .fields = self.builder.fields.items,
            .extra = self.builder.extra.items,
            .call_names = self.builder.call_names.items,
            .interpolation_formats = self.builder.interpolation_formats.items,
            .struct_literal_heads = self.builder.struct_literal_heads.items,
            .bracket_types = self.builder.bracket_types.items,
        };
    }

    /// Hands the tree over. The builder is empty afterwards, so a `deinit`
    /// that still runs -- a `defer` set up before the tree was wanted -- frees
    /// nothing the tree now owns.
    pub fn finish(self: *Modules) std.mem.Allocator.Error!Ast {
        const zone = tracy.beginZone(@src(), "parse.finish");
        defer zone.end();

        const parts = try self.parts.toOwnedSlice(self.gpa);
        errdefer self.gpa.free(parts);

        const tokens = self.tokens;
        self.tokens = .empty;
        return self.builder.finish(parts, tokens);
    }
};

/// Binding power of a binary operator; zero means the token is not one.
fn precedence(tag: Tag) u8 {
    return switch (tag) {
        // `..` and `..=` bind loosest of all: an end is a whole computation,
        // so a range is never an operand of another operator without
        // parentheses.
        .dot_dot, .dot_dot_equal => 1,
        // `||` binds next loosest and `&&` after it, so `a < b && c < d`
        // groups the comparisons first and `a && b || c` is `(a && b) || c`.
        .pipe_pipe => 2,
        .ampersand_ampersand => 3,
        // Comparison binds looser than arithmetic, so `a + 1 < b` groups the
        // arithmetic first.
        .equal_equal, .bang_equal, .less, .less_equal, .greater, .greater_equal => 4,
        .plus, .minus => 5,
        .star, .slash, .percent => 6,
        else => 0,
    };
}

/// Whether a token opens a range.
fn isRangeOp(tag: Tag) bool {
    return tag == .dot_dot or tag == .dot_dot_equal;
}

fn binaryTag(tag: Tag) Expr.Tag {
    return switch (tag) {
        .plus => .add,
        .minus => .sub,
        .star => .mul,
        .slash => .div,
        .percent => .rem,
        .ampersand_ampersand => .logical_and,
        .pipe_pipe => .logical_or,
        .equal_equal => .eq,
        .bang_equal => .ne,
        .less => .lt,
        .less_equal => .le,
        .greater => .gt,
        .greater_equal => .ge,
        else => unreachable,
    };
}

/// Whether a token is a comparison, which is what makes a chain of them a
/// syntax error rather than a comparison against a `Bool`.
fn isComparison(tag: Tag) bool {
    return switch (tag) {
        .equal_equal, .bang_equal, .less, .less_equal, .greater, .greater_equal => true,
        else => false,
    };
}

/// The deepest an expression, or a written type, may nest.
///
/// Chosen an order of magnitude below where any build mode runs out of stack,
/// so the limit is the same number everywhere rather than a property of how
/// the compiler was built. Nothing written by hand comes near it, and a
/// generator that does has found a bug in itself.
///
/// What is bounded is the height of the tree the parser hands on, not the
/// frames it spent building it: the two differ wherever a form is read in a
/// loop and built upwards. Bounding the tree bounds every later pass, each of
/// which walks the same shape and recurses the same way.
pub const max_nesting = node.max_tree_height;

const Parser = struct {
    gpa: std.mem.Allocator,
    cursor: Cursor,
    builder: *Ast.Builder,
    sink: *Sink,
    /// Which file this parse is of, so a diagnostic raised anywhere in the
    /// recursive descent names it without being handed it.
    file: FileId,
    /// Matching delimiter endpoints for this file, populated lazily. A scan
    /// records every nested pair it crosses, so lookahead over nested generic
    /// arguments visits each token once rather than once per possible head.
    delimiter_base: u32,
    delimiter_ends: []u32,
    /// The entry point's declared return type, or `.none` for a bare program.
    /// How many levels are open above what is being read. Recursive descent
    /// uses one stack frame per level, and the stack is a resource the
    /// language does not describe, so the bound is stated here rather than
    /// discovered by exhausting it.
    depth: u32 = 0,
    /// The deepest `depth` reached inside the subtree being measured. A form
    /// read in a loop is built above operands already finished, so how tall
    /// its tree is cannot be read off the frames still open: this is what
    /// carries a finished operand's height back to the loop stacking levels
    /// on top of it.
    deepest: u32 = 0,
    written_type_depth: u32 = 0,
    /// Whether the written type about to be read is a declaration's result,
    /// whose selection a line break may split. Nothing in a declaration's
    /// position opens with `.`, so a line that does is read with the type and
    /// refused once, instead of leaving the declaration without a body and
    /// the next line as no declaration.
    result_may_split: bool = false,
    /// Whether the bound has already been reported. One nesting error is the
    /// whole of what a reader can act on; the rest would name the same place.
    reported_nesting: bool = false,
    /// How many index brackets are open around what is being read.
    ///
    /// `^k` is written where an index is and nowhere else, so the position is
    /// what admits it: outside a bracket the caret begins no expression and
    /// gets the answer every token that begins none gets. Counted rather than
    /// flagged, because a bracket may be written inside another one.
    indexes: u32 = 0,
    /// Whether this is the outer, undelimited expression in a control header.
    /// Its following brace opens the control body. `parseFull` clears this
    /// while it reads, and every delimited position reads through it, so a
    /// literal inside an argument, group, arm, interpolation, `copy(...)` or
    /// `panic(...)` keeps its ordinary meaning.
    control_header: bool = false,
    /// The refinement clause being read, while one is being read.
    ///
    /// A clause is written on the line its `where` opens and reads no
    /// further, so a token demanded past that line is not one the clause is
    /// missing: the line break ended the declaration. Held here rather than
    /// checked at each position of the clause, so every position -- the one
    /// inside a bound among them, and any a later clause form brings --
    /// answers for the break through the one rule.
    clause: ?Clause = null,
    /// A contract-list comma left for an enclosing parameter/type list or
    /// lambda body. Its token identity distinguishes it from later commas.
    pending_contract_comma: TokenId = .none,
    pending_contract_index: usize = 0,
    /// The statement being read, and the `{` of the block holding it; see
    /// `endStatement`, which measures a skipped tail against them.
    statement: StatementLine = .{},
    /// The last line end `lineEndAfter` found: no line break lies in
    /// `source[from..end]`, and `end` is a break or the end of the source.
    /// Kept for the whole parse, so the skips of many statements on one line
    /// scan that line once rather than once each.
    line_end: ?LineEnd = null,

    const LineEnd = struct { from: usize, end: usize };

    /// Where a statement sits, for measuring the closers a skip meets.
    ///
    /// `indent` is the leading whitespace of the line the statement starts
    /// on when the statement begins that line. A statement written after
    /// something else on its line keeps the indentation of the statement
    /// before it in its block, or of the statement holding its block when it
    /// is the first. `begins_line` says the statement begins its line.
    const StatementLine = struct {
        start: TokenId = .none,
        indent: []const u8 = "",
        open: TokenId = .none,
        begins_line: bool = true,
    };

    fn delimiterEnd(self: *Parser, open: TokenId) ?TokenId {
        const slot = open.index() - self.delimiter_base;
        const known = self.delimiter_ends[slot];
        if (known != delimiter_unknown) return if (known == delimiter_invalid) null else TokenId.at(known);

        var openings: [max_nesting]u32 = undefined;
        var kinds: [max_nesting]Tag = undefined;
        var depth: usize = 0;
        var i = open.index();
        while (i < self.cursor.tags.len) : (i += 1) {
            const tag = self.cursor.tags[i];
            switch (tag) {
                .l_paren, .l_bracket, .l_brace => {
                    if (depth == max_nesting) break;
                    openings[depth] = @intCast(i);
                    kinds[depth] = tag;
                    depth += 1;
                },
                .r_paren, .r_bracket, .r_brace => {
                    if (depth == 0) break;
                    const want: Tag = switch (tag) {
                        .r_paren => .l_paren,
                        .r_bracket => .l_bracket,
                        .r_brace => .l_brace,
                        else => unreachable,
                    };
                    if (kinds[depth - 1] != want) break;
                    depth -= 1;
                    self.delimiter_ends[openings[depth] - self.delimiter_base] = @intCast(i);
                    if (depth == 0) return TokenId.at(i);
                },
                .eof => break,
                else => {},
            }
        }
        for (openings[0..depth]) |opening| self.delimiter_ends[opening - self.delimiter_base] = delimiter_invalid;
        return null;
    }

    fn startsNamedStructLiteral(self: *Parser) bool {
        if (self.control_header or !self.cursor.at(.identifier)) return false;
        var cursor = self.cursor;
        _ = cursor.advance();
        while (!cursor.precededByNewline() and cursor.eat(.dot) != null) {
            if (cursor.eat(.identifier) == null) return false;
        }
        if (!cursor.precededByNewline() and cursor.at(.l_bracket)) {
            const close = self.delimiterEnd(cursor.current()) orelse return false;
            cursor.seek(@intCast(close.index() + 1));
        }
        return !cursor.precededByNewline() and cursor.at(.l_brace);
    }

    /// A refinement clause's region, and what has been said about leaving it.
    const Clause = struct {
        /// The first token past the line the clause is written on.
        end: u32,
        /// Whether the break has been reported. The break is one mistake
        /// however many of the clause's positions then find nothing.
        reported: bool = false,
    };

    /// The height of the expression being read, which is not the number of
    /// frames open while reading it.
    ///
    /// A chain of operators, or of `.` suffixes, is read in a loop: each turn
    /// builds a node above operands already finished, so the tree grows a
    /// level while the frame count stands still. The limit is on the tree
    /// every later pass walks, so a loop that stacks a level counts it here,
    /// against the same number `depth` is checked against.
    const Measure = struct {
        parser: *Parser,
        /// The level this expression sits at, which its height is measured
        /// from.
        base: u32,
        /// The enclosing measurement, which this one's height folds back into.
        outer: u32,
        height: u32 = 0,

        fn begin(parser: *Parser) Measure {
            const m: Measure = .{
                .parser = parser,
                .base = parser.depth,
                .outer = parser.deepest,
            };
            parser.deepest = parser.depth;
            return m;
        }

        /// Takes in the operand just read, and readies the next one.
        fn operand(self: *Measure) void {
            self.height = @max(self.height, self.parser.deepest - self.base);
            self.parser.deepest = self.base;
        }

        /// One level built above everything read so far. False where that
        /// level would be past the limit.
        fn wrap(self: *Measure) bool {
            self.height += 1;
            return self.base + self.height <= max_nesting;
        }

        fn finish(self: *Measure) void {
            self.parser.deepest = @max(self.outer, self.base + self.height);
        }
    };

    fn rangeFrom(self: *const Parser, start: TokenId) TokenRange {
        return .{ .start = start, .end = self.cursor.current() };
    }

    /// A program is a list of declarations.
    ///
    /// Which of them is the entry point is a question about names, so it is
    /// the resolver's rather than the parser's: here a declaration is a
    /// declaration.
    fn parseProgram(self: *Parser) !void {
        while (!self.cursor.atEnd()) {
            var attributes = try self.parseAttributes();
            while (self.atBareAttributeWord()) {
                try self.reportBareAttributeWord(false);
            }
            // The visibility prefix is read here rather than in each rule, so
            // a declaration form added later cannot forget to accept one.
            const at = if (attributes.first != .none) attributes.first else self.cursor.current();
            // These occupy one slot rather than modifying one another: each is
            // one answer to how far the declaration's name reaches.
            const visibility: node.Visibility = if (self.cursor.eat(.keyword_pub) != null)
                .pub_
            else if (self.cursor.eat(.keyword_internal) != null)
                .internal_
            else
                .private;

            // A modifier rather than a fourth visibility, for the reason
            // `linear` is a modifier: who may name a declaration and whether a
            // linker publishes it are two questions, and `pub export` says one
            // of each.
            const is_export = self.cursor.eat(.keyword_export) != null;

            // Attributes and the removed policy prefixes written after the
            // visibility are read so the declaration keeps both, and reported
            // with the order that is accepted.
            while (self.atBareAttributeWord()) {
                try self.reportBareAttributeWord(true);
            }
            if (self.cursor.at(.at_sign)) {
                try self.reportAt(.s_entry, self.cursor.current(), "attributes precede the visibility", "move the attribute before `pub`, `internal` or `export`");
                try self.continueAttributes(&attributes);
            }

            // Ownership policy is independent of declaration visibility.
            const policy = attributes.policy;

            // `test` is a modifier on a function rather than a declaration form
            // of its own. What it settles is who writes the call and whether
            // the declaration is emitted; everything else about it is a
            // function's, so it is read here with the other prefixes and
            // refused below wherever it would say nothing.
            const is_test = self.cursor.eat(.keyword_test) != null;
            const expects_trap = is_test and self.cursor.eat(.keyword_trap) != null;
            const default_at = if (self.atDefaultImplementation()) self.cursor.advance() else TokenId.none;

            if (self.cursor.at(.keyword_impl) or self.cursor.at(.keyword_template)) {
                const is_template = self.cursor.at(.keyword_template);
                // An `impl` declares no name, so there is nothing for `pub` to
                // export and nothing for `linear` to describe: a modifier here
                // was read and dropped, which is the shape of a mistake that
                // never says anything. Each member carries its own visibility.
                if (is_test) {
                    // Its own rule and its own name: an `impl` declares no body
                    // to run, which is what [S-Test] says about every form the
                    // modifier does not reach.
                    try self.reportAt(
                        .s_test,
                        at,
                        "only a function is a test",
                        "an impl declares no body to run",
                    );
                }
                if (attributes.recognized) {
                    try self.reportAt(
                        .s_entry,
                        attributes.first,
                        "attributes attach only to a type declaration",
                        "an impl is behaviour, not a nominal type declaration",
                    );
                }
                if (visibility != .private or is_export) {
                    try self.reportAt(
                        .s_entry,
                        at,
                        "an impl takes no visibility, ownership or export modifier",
                        "a modifier belongs on the type, or on a member",
                    );
                }
                const d = try self.parseImpl(is_template, default_at);
                self.builder.markAttributeGroups(d, attributes.groups);
                continue;
            }

            if (self.cursor.at(.keyword_derive)) {
                if (attributes.recognized) {
                    try self.reportAt(
                        .s_entry,
                        attributes.first,
                        "attributes attach only to a type declaration",
                        "a standalone derive is an implementation request, not a nominal type declaration",
                    );
                }
                if (is_test or visibility != .private or is_export) {
                    try self.reportAt(
                        .s_entry,
                        at,
                        "a derive request takes no modifier",
                        "the generated implementation has the trait's visibility",
                    );
                }
                const d = try self.parseDerive();
                self.builder.markAttributeGroups(d, attributes.groups);
                continue;
            }

            // Whether what follows is the one form a test may be, read before
            // the dispatch consumes it.
            const at_function = self.cursor.at(.keyword_fn);

            const declared: ?node.DeclId = if (self.cursor.at(.keyword_fn))
                try self.parseFunction(if (is_test) .test_ else .top_level)
            else if (self.cursor.at(.keyword_extern))
                try self.parseExtern()
            else if (self.cursor.at(.keyword_trait))
                try self.parseTrait()
            else if (self.cursor.at(.keyword_import))
                try self.parseImport()
            else if (self.cursor.at(.keyword_use))
                try self.parseUse()
            else if (self.cursor.at(.keyword_enum))
                try self.parseEnum()
            else if (self.cursor.at(.keyword_struct))
                try self.parseStruct()
            else if (self.cursor.at(.keyword_let))
                try self.parseConstant()
            else if (self.atNewtype())
                try self.parseNewtype()
            else if (self.atAlias())
                try self.parseAlias()
            else
                null;

            if (declared) |d| {
                self.builder.markAttributeGroups(d, attributes.groups);
                const type_target = switch (self.builder.decls.items(.tag)[d.index()]) {
                    .struct_, .enum_, .newtype => true,
                    else => false,
                };
                if (attributes.recognized and !type_target) {
                    try self.reportAt(.s_entry, attributes.first, "attributes attach only to a type declaration", "place them before a struct, enum, or newtype");
                }
                if (attributes.carrier != .none and self.builder.decls.items(.tag)[d.index()] == .newtype) {
                    try self.reportAt(.s_entry, attributes.carrier, "a carrier is a struct or an enum", "a newtype names one existing type; mark a struct or an enum instead");
                }
                if (type_target) self.builder.markAttachedDeriveTraits(d, attributes.derive_traits);
                if (type_target and attributes.sealed) {
                    if (visibility != .private) {
                        try self.reportAt(.s_entry, attributes.first, "opaque does not combine with another visibility", "remove `pub` or `internal`");
                    }
                    self.builder.markVisibility(d, .opaque_, at);
                } else {
                    self.builder.markVisibility(d, visibility, at);
                }
                if (is_test and !at_function) {
                    try self.reportAt(
                        .s_test,
                        at,
                        "only a function is a test",
                        "a test is a body the compiler runs, and this declares none",
                    );
                } else if (is_test and visibility != .private) {
                    // Nothing in the language may name a test: the compiler
                    // writes the only call to one. So exporting it names an
                    // export no import can reach.
                    try self.reportAt(
                        .s_test,
                        at,
                        "a test declares no visibility",
                        "the compiler writes the only call to a test, so nothing can import it",
                    );
                }
                self.builder.markOwnershipPolicy(d, policy);
                // As written, not as accepted. A modifier the language
                // refuses is still a token the source holds, and the formatter
                // reprints what was written -- one recorded only where it is
                // legal is one the formatter deletes, which turns a refused
                // program into a different program.
                self.builder.markTest(d, is_test);
                self.builder.markExpectedTrap(d, expects_trap);
                self.builder.markExport(d, is_export);
                continue;
            }

            if (attributes.recognized) {
                try self.reportAt(
                    .s_entry,
                    attributes.first,
                    "an attribute requires a nominal type declaration",
                    "write a struct, enum, or newtype after this attribute",
                );
            } else if (attributes.first != .none and self.cursor.atEnd()) {
                // The attribute already reported that it names nothing.
            } else {
                try self.reportAt(
                    .s_entry,
                    at,
                    "a program is a list of declarations",
                    "expected `fn` here",
                );
            }
            // Skip to the next declaration rather than the next token, so one
            // stray region does not report once per token it contains.
            while (!self.cursor.atEnd() and !self.atDeclaration()) {
                _ = self.cursor.advance();
            }
        }
    }

    /// Whether the cursor sits on an attribute word written without its `@`.
    fn atBareAttributeWord(self: *const Parser) bool {
        return self.cursor.at(.keyword_opaque) or self.cursor.at(.keyword_linear) or
            self.cursor.at(.keyword_copyable) or self.cursor.at(.keyword_carrier);
    }

    /// Reports a bare attribute word and steps over it. Every word
    /// `atDeclaration` accepts as a declaration start is consumed by
    /// `parseProgram`, so recovery always makes progress.
    fn reportBareAttributeWord(self: *Parser, after_visibility: bool) !void {
        const carrier = self.cursor.at(.keyword_carrier);
        const word = self.cursor.advance();
        if (carrier) {
            const help = if (after_visibility) "write `@` before this word, ahead of the visibility" else "write `@` before this word";
            return self.reportAt(.s_entry, word, "carrier is a declaration attribute", help);
        }
        const help = if (after_visibility) "write `@` before this policy, ahead of the visibility" else "write `@` before this policy";
        try self.reportAt(.s_entry, word, "type policies are declaration attributes", help);
    }

    const ParsedAttributes = struct {
        first: TokenId = .none,
        groups: node.AttributeGroupRange = node.AttributeGroupRange.empty,
        policy: node.OwnershipPolicy = .affine,
        sealed: bool = false,
        derive_traits: node.DeriveTraitRange = node.DeriveTraitRange.empty,
        /// Whether any item named a closed attribute. An attribute that named
        /// nothing is already reported, so its target is not judged again.
        recognized: bool = false,
        saw_linear: bool = false,
        saw_copyable: bool = false,
        /// The `carrier` item, where one was written.
        carrier: TokenId = .none,
    };

    fn parseAttributes(self: *Parser) !ParsedAttributes {
        var result: ParsedAttributes = .{};
        try self.continueAttributes(&result);
        return result;
    }

    /// Reads attribute groups into `result`, extending what earlier groups of
    /// the same declaration recorded. Groups written after the visibility are
    /// reported by the caller and still modify the declaration, so they are
    /// read by this same routine rather than merged field by field.
    fn continueAttributes(self: *Parser, result: *ParsedAttributes) !void {
        const group_start = if (result.first == .none) self.builder.attributeGroupMark() else result.groups.start;
        const exclusive_reported = result.saw_linear and result.saw_copyable;
        while (self.cursor.at(.at_sign)) {
            const at = self.cursor.advance();
            if (result.first == .none) result.first = at;
            const item_start = self.builder.attributeItemMark();
            const open = self.cursor.eat(.l_paren) orelse TokenId.none;
            if (open != .none and self.cursor.at(.r_paren)) {
                try self.reportAt(.s_entry, open, "an attribute group is not empty", "name at least one closed attribute");
            }
            if (open == .none and (self.cursor.atEnd() or self.atDeclaration()) and !self.atAttributeItem() and !self.cursor.at(.keyword_derive)) {
                try self.reportAt(.s_entry, at, "expected an attribute name after `@`", "use `opaque`, `linear`, `copyable`, `carrier`, or `derive(...)`");
                try self.builder.addAttributeItem(.{
                    .kind = .unknown,
                    .name = at,
                    .tokens = .{ .start = at, .end = self.cursor.current() },
                    .derive_traits = .empty,
                });
            }
            while (!self.cursor.atEnd() and (open == .none or !self.cursor.at(.r_paren))) {
                if (open == .none and self.builder.attributeItemMark() != item_start) break;
                if (open != .none and self.atDeclaration() and !self.atGroupedAttributeItem()) break;
                const item_at = self.cursor.current();
                var kind: node.AttributeItemKind = .unknown;
                var traits = node.DeriveTraitRange.empty;
                if (self.cursor.eat(.keyword_opaque) != null) {
                    kind = .opaque_;
                    if (result.sealed) try self.reportAt(.s_entry, item_at, "an attribute is written once", "remove the repeated `opaque`");
                    result.sealed = true;
                } else if (self.cursor.eat(.keyword_linear) != null) {
                    kind = .linear;
                    if (result.saw_linear) try self.reportAt(.s_entry, item_at, "an attribute is written once", "remove the repeated `linear`");
                    result.saw_linear = true;
                    result.policy = .linear;
                } else if (self.cursor.eat(.keyword_copyable) != null) {
                    kind = .copyable;
                    if (result.saw_copyable) try self.reportAt(.s_entry, item_at, "an attribute is written once", "remove the repeated `copyable`");
                    result.saw_copyable = true;
                    result.policy = .copyable;
                } else if (self.cursor.eat(.keyword_carrier) != null) {
                    kind = .carrier;
                    if (result.carrier != .none) try self.reportAt(.s_entry, item_at, "an attribute is written once", "remove the repeated `carrier`");
                    if (result.carrier == .none) result.carrier = item_at;
                } else if (self.cursor.eat(.keyword_derive) != null) {
                    kind = .derive;
                    if (!self.cursor.at(.l_paren)) {
                        try self.reportAt(.s_params, item_at, "derive attributes carry a parenthesized trait list", "write `derive(Trait)`");
                    } else {
                        const parsed = try self.parseDeriveTraits();
                        traits = parsed.range;
                        if (traits.len() != 0) {
                            if (result.derive_traits.len() == 0) result.derive_traits.start = traits.start;
                            result.derive_traits.end = traits.end;
                        }
                        if (traits.len() == 0) try self.reportAt(.t_derive, item_at, "a derive request is not empty", "name at least one trait");
                    }
                } else {
                    try self.reportAt(.s_entry, item_at, "attribute names are closed", "use `opaque`, `linear`, `copyable`, `carrier`, or `derive(...)`");
                    // The rest of this item is part of the refused name, up to
                    // the separator or the group's end.
                    if (!self.cursor.at(.comma) and !self.cursor.at(.r_paren) and !self.cursor.atEnd()) _ = self.cursor.advance();
                    if (open != .none) {
                        while (!self.cursor.atEnd() and !self.cursor.at(.comma) and !self.cursor.at(.r_paren) and !self.atDeclaration()) _ = self.cursor.advance();
                    }
                }
                if (kind != .unknown) result.recognized = true;
                try self.builder.addAttributeItem(.{
                    .kind = kind,
                    .name = item_at,
                    .tokens = .{ .start = item_at, .end = self.cursor.current() },
                    .derive_traits = traits,
                });
                if (open == .none) break;
                if (self.cursor.eat(.comma) == null) {
                    // Only another item makes a missing comma the problem;
                    // otherwise the group is what is left unclosed.
                    if (!self.atGroupedAttributeItem()) break;
                    try self.reportAt(.s_params, self.cursor.current(), "expected `,` between attributes", "separate grouped attributes with commas");
                }
            }
            var close = TokenId.none;
            if (open != .none) close = self.cursor.eat(.r_paren) orelse missing: {
                try self.reportAt(.s_params, self.cursor.current(), "expected `)`", "an attribute group closes before its declaration");
                break :missing TokenId.none;
            };
            try self.builder.addAttributeGroup(.{
                .at = at,
                .open = open,
                .close = close,
                .items = .{ .start = item_start, .end = self.builder.attributeItemMark() },
                .tokens = .{ .start = at, .end = self.cursor.current() },
            });
        }
        if (result.saw_linear and result.saw_copyable and !exclusive_reported) {
            try self.reportAt(.s_entry, result.first, "linear and copyable are exclusive", "choose one ownership policy");
        }
        result.groups = .{ .start = group_start, .end = self.builder.attributeGroupMark() };
    }

    fn atAttributeItem(self: *const Parser) bool {
        return self.cursor.at(.keyword_opaque) or
            self.cursor.at(.keyword_linear) or
            self.cursor.at(.keyword_copyable) or
            self.cursor.at(.keyword_carrier) or
            (self.cursor.at(.keyword_derive) and self.cursor.peekAt(1) == .l_paren);
    }

    /// An item inside `@(...)`. A `derive` that the group's `,` or `)`
    /// follows is the attribute missing its trait list, not a standalone
    /// derive request.
    fn atGroupedAttributeItem(self: *const Parser) bool {
        if (self.atAttributeItem()) return true;
        if (!self.cursor.at(.keyword_derive)) return false;
        const next = self.cursor.peekAt(1);
        return next == .r_paren or next == .comma;
    }

    /// Whether a function is being written where a type's parts belong.
    ///
    /// A type declaration is its representation, which is exactly what
    /// `opaque` seals; what a type can do is written in an `impl`, which may
    /// sit in any file of the module. One question each.
    fn atMember(self: *const Parser) bool {
        return switch (self.cursor.peek()) {
            .keyword_fn, .keyword_pub, .keyword_internal, .keyword_impl, .keyword_trait, .keyword_extern => true,
            else => false,
        };
    }

    /// Reports and steps over what a type's braces hold before, or instead
    /// of, one of its parts, so the parts written after it are still read.
    ///
    /// An attribute and a visibility belong to the declaration, so each is
    /// reported and the part it precedes is read as written. A member belongs
    /// to an `impl`, so it is reported and skipped whole: through its body's
    /// braces where it has one, otherwise to the comma or brace that ends the
    /// position it took or to the end of its line. True where a member was
    /// skipped and no part follows in this position.
    fn stepOverTypeIntruders(self: *Parser, code: Code, holds: []const u8) std.mem.Allocator.Error!bool {
        while (true) {
            if (self.cursor.at(.at_sign)) {
                try self.reportAt(.s_entry, self.cursor.current(), "attributes precede the type declaration", "move this attribute above the declaration");
                _ = self.cursor.advance();
                if (self.cursor.at(.l_paren)) {
                    self.skipBalanced();
                } else if (!self.cursor.atEnd() and !self.cursor.at(.r_brace)) {
                    _ = self.cursor.advance();
                    if (self.cursor.at(.l_paren)) self.skipBalanced();
                }
                continue;
            }
            if ((self.cursor.at(.keyword_pub) or self.cursor.at(.keyword_internal)) and self.cursor.peekAt(1) == .identifier) {
                try self.reportAt(code, self.cursor.current(), "a type's parts take the type's visibility", "remove this visibility");
                _ = self.cursor.advance();
                continue;
            }
            if (!self.atMember()) return false;

            const member = self.cursor.current();
            try self.reportAt(code, member, holds, "a function belongs to an `impl`");
            while (!self.cursor.atEnd() and !self.cursor.at(.comma) and !self.cursor.at(.r_brace)) {
                // A member without a body ends with its line, as a
                // declaration does.
                if (self.cursor.current() != member and self.cursor.precededByNewline()) break;
                if (self.cursor.at(.l_brace)) {
                    self.skipBalanced();
                    break;
                }
                if (self.cursor.at(.l_paren) or self.cursor.at(.l_bracket)) {
                    self.skipBalanced();
                    continue;
                }
                _ = self.cursor.advance();
            }
            _ = self.cursor.eat(.comma);
            return true;
        }
    }

    /// Steps over the delimited run the cursor is at, through its matching
    /// closer, or to the end where it is never closed.
    fn skipBalanced(self: *Parser) void {
        if (self.delimiterEnd(self.cursor.current())) |close| {
            self.cursor.seek(@intCast(close.index() + 1));
            return;
        }
        while (!self.cursor.atEnd()) _ = self.cursor.advance();
    }

    /// `impl Name { ... }`: the behaviour of a type, written outside it.
    ///
    /// The braces after `struct` or `enum` hold the representation and nothing
    /// else, which is what `opaque` seals -- putting members there too would
    /// invite the reading that it seals them as well, and it does not: a
    /// member carries its own visibility.
    ///
    /// A type may have any number of these, in any file of its module, so a
    /// type's behaviour is split across files exactly as a module is.
    fn parseImpl(self: *Parser, is_template: bool, default_at: TokenId) std.mem.Allocator.Error!node.DeclId {
        const start = if (default_at != .none) default_at else self.cursor.current();
        _ = self.cursor.advance();
        if (is_template and self.cursor.eat(.keyword_impl) == null) {
            try self.reportAt(.s_entry, self.cursor.current(), "expected `impl` after `template`", "a structural template is an impl recipe");
        }

        // Before the head, in the grammar a function's use. An implementation
        // stands for a family of head types, and the parameters are what the
        // head is applied to -- so they are read before the thing that applies
        // them, and are in scope in everything written after.
        const type_params = try self.parseTypeParams(.refused);

        var trait_ref: node.TraitRef = .{};
        var head: node.TypeRef = undefined;
        if (is_template) {
            trait_ref = try self.parseTraitRef("expected a trait name after `impl`", "a template names the trait it generates");
            head = .{ .at = trait_ref.name, .name = trait_ref.name, .args = trait_ref.args };
        } else if (self.cursor.at(.l_paren) or self.cursor.at(.keyword_borrow)) {
            head = try self.parseImplementationHead(true, false);
            if (self.cursor.eat(.keyword_for) != null) {
                try self.reportAt(.s_name, head.at, "expected a trait name before `for`", "only a named trait may precede `for`");
                trait_ref = .{ .name = head.name };
                head = try self.parseImplementationHead(true, true);
            }
        } else {
            const first = try self.parseTraitRef("expected a type name after `impl`", "an impl names the type it belongs to");
            if (self.cursor.eat(.keyword_for) != null) {
                trait_ref = first;
                head = try self.parseImplementationHead(true, true);
            } else {
                const first_name = if (first.path.len() == 0) first.name else first.path.start;
                if (first.path.len() != 0) {
                    try self.reportAt(.s_name, first.name, "an implementation head is a bare type name", "qualify the trait before `for`, not the implementing type");
                }
                head = .{ .at = first_name, .name = first_name, .args = first.args };
            }
        }
        const of = head.at;
        if (default_at != .none and trait_ref.name == .none) {
            try self.reportAt(.s_entry, default_at, "a default implementation must name a trait", "write the trait before `for`");
        }

        if (!is_template) {
            const parameter_head = head.kind == .named and head.args.len() == 0 and blk: {
                for (self.builder.typeParams(type_params)) |parameter| {
                    if (std.mem.eql(u8, self.cursor.textOf(head.name), self.cursor.textOf(parameter.name))) break :blk true;
                }
                break :blk false;
            };
            if (!parameter_head) {
                if (trait_ref.name == .none)
                    try self.refuseAnInherentHeadThatLeavesAParameterOpen(head, type_params)
                else
                    _ = try self.refuseAHeadThatIsNotItsParameters(.t_impl, head, type_params, true);
            }
        }

        var where_at = TokenId.none;
        var where_predicates = node.WherePredicateRange.empty;
        var template_requirements = node.TemplateRequirementRange.empty;
        if (self.cursor.eat(.keyword_where)) |at| {
            where_at = at;
            if (is_template) {
                template_requirements = try self.parseTemplateRequirements();
            } else {
                where_predicates = try self.parseWherePredicates();
            }
        }

        if (self.atDelegation()) {
            const via = self.cursor.advance();
            const target = try self.parseDelegationTarget();
            if (is_template) try self.reportAt(.s_entry, via, "a template does not delegate through a field", "write delegation on an implementation of a type");
            if (default_at != .none) try self.reportAt(.s_entry, via, "a default implementation cannot delegate through a field", "write a body for the default implementation");
            try self.endBodilessDecl("a delegated implementation ends after its field");
            const d = try self.implDecl(if (is_template) .template_impl else .impl_, start, head, trait_ref, type_params, where_at, where_predicates, template_requirements);
            self.builder.markDelegation(d, via, target);
            return d;
        }

        if (self.cursor.eat(.l_brace) == null) {
            try self.reportAt(.s_brace, self.cursor.current(), "expected `{`", "an impl lists what the type can do");
            return self.implDecl(if (is_template) .template_impl else .impl_, start, head, trait_ref, type_params, where_at, where_predicates, template_requirements);
        }

        while (!self.cursor.atEnd() and !self.cursor.at(.r_brace)) {
            const before = self.cursor.current();

            const at = self.cursor.current();
            const visibility: node.Visibility = if (self.cursor.eat(.keyword_pub) != null)
                .pub_
            else if (self.cursor.eat(.keyword_internal) != null)
                .internal_
            else
                .private;

            // Read here for the reason `test` is, and refused for one of its
            // own: a foreign entry point is named by the module that declares
            // it, and a member is reached through the type it belongs to.
            if (self.cursor.eat(.keyword_export) != null) {
                try self.reportAt(
                    .s_export,
                    at,
                    "an export does not sit in an impl",
                    "an impl holds what its type or its trait declares, and an export names a module's own entry point",
                );
            }

            // Read here so the member that carries it is refused by its own
            // rule. Left to the dispatch below, `test` is a word no member form
            // begins with, and what a reader is told is that an impl holds
            // functions -- true, and not what they got wrong.
            if (self.cursor.eat(.keyword_test) != null) {
                _ = self.cursor.eat(.keyword_trap);
                try self.reportAt(
                    .s_test,
                    at,
                    "a test does not sit in an impl",
                    "an impl holds what its type or its trait declares, and the compiler calls a test",
                );
            }

            const settles_a_type = self.atAssociatedType();
            const declares_a_traversal = self.atTraversal();

            const declared: ?node.DeclId = if (self.cursor.at(.keyword_fn))
                try self.parseFunction(.member)
            else if (self.atProjection())
                try self.parseProjection(.required)
            else if (self.atTraversal())
                try self.parseTraversal()
            else if (self.cursor.at(.keyword_let))
                try self.parseConstant()
            else if (settles_a_type)
                try self.parseAssociatedType(.answered)
            else
                null;

            if (settles_a_type) {
                // A declared type is a member of a trait, so an implementation
                // naming none has nothing to settle: written here it answers
                // no declaration, and is reached through neither namespace.
                if (trait_ref.name == TokenId.none) {
                    try self.reportAt(
                        .s_entry,
                        at,
                        "an inherent impl holds functions and constants",
                        "a declared type is a trait's, and this impl names no trait",
                    );
                }
                // No visibility of its own, for the reason a signature has
                // none: what an implementation supplies is the trait's, and is
                // reachable wherever the trait is.
                if (visibility != .private) {
                    try self.reportAt(
                        .s_entry,
                        at,
                        "a settled type carries no visibility",
                        "it is reachable wherever the trait it settles is",
                    );
                }
            }

            if (declares_a_traversal) {
                // A traversal answers no trait: it says how the type's own
                // places are walked, which is the type's to say and nobody
                // else's. Written under a trait it would be a member the trait
                // never declared, reachable through a namespace nothing looks
                // in.
                if (trait_ref.name != TokenId.none) {
                    try self.reportAt(
                        .s_entry,
                        at,
                        "a traversal is the type's own",
                        "write it in an impl naming only the type, which is where a walk looks for it",
                    );
                }
                // No visibility of its own, because nothing names it: a walk
                // finds it through the type, and a walk over a type reaches it
                // wherever the type does.
                if (visibility != .private) {
                    try self.reportAt(
                        .s_entry,
                        at,
                        "a traversal carries no visibility",
                        "a walk finds it through the type rather than by name",
                    );
                }
            }

            if (declared) |d| {
                self.builder.markVisibility(d, visibility, at);
                self.builder.markOwner(d, of);
                self.builder.markTrait(d, trait_ref);
            } else {
                try self.reportAt(.s_entry, at, "an impl holds functions, projections, traversals, constants and types", "expected `fn`, `proj`, `trav`, `let` or `type` here");
                while (!self.cursor.atEnd() and !self.cursor.at(.r_brace) and
                    !self.cursor.at(.keyword_fn) and !self.cursor.at(.keyword_let) and
                    !self.atProjection() and !self.atTraversal() and !self.atAssociatedType())
                {
                    _ = self.cursor.advance();
                }
            }

            if (self.cursor.current() == before) _ = self.cursor.advance();
        }

        if (self.cursor.eat(.r_brace) == null) {
            try self.reportAt(.s_brace, self.cursor.current(), "expected `}`", "this impl is never closed");
        }
        return self.implDecl(if (is_template) .template_impl else .impl_, start, head, trait_ref, type_params, where_at, where_predicates, template_requirements);
    }

    /// A bare or module-qualified trait name and the arguments applied to it.
    fn parseTraitRef(self: *Parser, expected: []const u8, why: []const u8) std.mem.Allocator.Error!node.TraitRef {
        const first = self.cursor.current();
        if (self.cursor.eat(.identifier) == null) {
            try self.reportAt(.s_name, first, expected, why);
            return .{ .name = first };
        }

        var name = first;
        var last = first;
        var qualified = false;
        while (!self.pathEndsAtALineBreak() and self.cursor.eat(.dot) != null) {
            qualified = true;
            last = self.cursor.previousToken();
            name = self.cursor.current();
            if (self.cursor.eat(.identifier) == null) {
                try self.reportAt(.s_name, name, "expected a trait name after `.`", "a trait path ends at a name");
                break;
            }
            last = name;
        }

        return .{
            .name = name,
            .path = if (qualified) .{ .start = first, .end = TokenId.at(last.index() + 1) } else .empty,
            .args = if (self.cursor.at(.l_bracket)) try self.parseTypeArgs() else .empty,
        };
    }

    /// The named, Unit, tuple, borrow or callable type an implementation head
    /// may contain.
    ///
    /// A head is a complete written type even though it admits fewer forms than
    /// an annotation: arrays have no declaring module and are not coherence
    /// constructors source can implement. A callable type heads only the
    /// implementation of a trait, after `for`; the resolver admits it in the
    /// trait's own module alone.
    fn parseImplementationHead(
        self: *Parser,
        allow_unit: bool,
        after_for: bool,
    ) std.mem.Allocator.Error!node.TypeRef {
        const at = self.cursor.current();
        if (self.cursor.at(.identifier)) {
            _ = self.cursor.advance();
            return .{
                .at = at,
                .name = at,
                .args = if (self.cursor.at(.l_bracket)) try self.parseTypeArgs() else .empty,
            };
        }
        if (self.cursor.at(.keyword_borrow)) return self.parseWrittenType();
        if (after_for and self.startsCallableType()) return self.parseCallableType();
        if (allow_unit and self.cursor.at(.l_paren)) {
            const head = try self.parseUnitType();
            try self.refuseAGroupedHead(head, if (after_for) "an implementation names the type that satisfies the trait" else "an impl names the type it belongs to");
            return head;
        }

        try self.reportAt(
            .s_name,
            at,
            if (after_for) "expected a type name after `for`" else "expected a type name after `impl`",
            if (after_for) "an implementation names the type that satisfies the trait" else "an impl names the type it belongs to",
        );
        return .{ .at = at, .name = at };
    }

    /// A head written in parentheses is unit or a tuple, each a type of its
    /// own. `(T)` groups a type and names none, and no pass reads a name out
    /// of a group, so it is refused where it is written.
    fn refuseAGroupedHead(self: *Parser, head: node.TypeRef, label: []const u8) !void {
        if (head.kind != .grouped) return;
        try self.reportAt(.s_name, head.at, "expected a type name, `()` or a tuple; `(T)` groups a type", label);
    }

    test "a grouped type is refused as an implementation or derive head" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();

        try testing.expectEqualSlices(?Code, &.{.s_name}, try codesOf(gpa, "trait Show {}\nimpl Show for (UInt8) {}\nfn main() -> UInt8 { 0 }\n"));
        try testing.expectEqualSlices(?Code, &.{.s_name}, try codesOf(gpa, "impl (UInt8) {}\nfn main() -> UInt8 { 0 }\n"));
        try testing.expectEqualSlices(?Code, &.{.s_name}, try codesOf(gpa, "derive[A] Debug for (A)\nfn main() -> UInt8 { 0 }\n"));
        // A grouped tuple is refused the same way, and a head that names
        // nothing is not also held to applying its parameters.
        try testing.expectEqualSlices(?Code, &.{.s_name}, try codesOf(gpa, "trait Show {}\nimpl[A, B] Show for ((A, B)) {}\nfn main() -> UInt8 { 0 }\n"));
        try testing.expectEqualSlices(?Code, &.{.s_name}, try codesOf(gpa, "derive[A, B] Debug for ((A, B))\nfn main() -> UInt8 { 0 }\n"));
        // Unit and a tuple are heads of their own.
        try testing.expectEqualSlices(?Code, &.{}, try codesOf(gpa, "trait Show {}\nimpl Show for () {}\nimpl Show for (UInt8, Bool) {}\nfn main() -> UInt8 { 0 }\n"));
    }

    test "a callable type heads a trait implementation and no other impl" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();

        try testing.expectEqualSlices(?Code, &.{}, try codesOf(gpa, "trait Show {}\nimpl Show for fn(a: UInt8) -> UInt8 {}\nimpl Show for inout fn(inout a: UInt8) where carries() {}\nfn main() -> UInt8 { 0 }\n"));
        // An inherent block names a type and a derive names one the compiler
        // generates for, so neither takes a callable type.
        try testing.expect((try codesOf(gpa, "impl fn(a: UInt8) -> UInt8 {}\nfn main() -> UInt8 { 0 }\n")).len != 0);
    }

    /// A type's own implementation applies its constructor to types: each
    /// declared parameter stands alone in exactly one position, and every
    /// other position is a type naming no parameter, as `impl[P] Router[P, ()]`
    /// is. Its members belong to the instantiations the head matches, and a
    /// member name is declared once per constructor, so no two members compete
    /// for one call; a trait's coherence, which keys on the constructor, is
    /// what keeps a trait implementation's head to its bare parameters.
    ///
    /// A parameter is found where a name stands in a type's position, the
    /// place a bare name resolves to the parameter it spells; the member half
    /// of `mem.SystemAllocator` is not such a place. **Bound:** the head's
    /// written types once per declared parameter.
    fn refuseAnInherentHeadThatLeavesAParameterOpen(
        self: *Parser,
        head: node.TypeRef,
        type_params: node.TypeParamRange,
    ) !void {
        const declared = self.builder.typeParams(type_params);
        if (declared.len == 0) return;

        const applied = self.builder.typeArgs(head.args);
        var valid = applied.len != 0;
        for (declared) |parameter| {
            if (!valid) break;
            const spelling = self.cursor.textOf(parameter.name);
            var alone: usize = 0;
            var named: usize = 0;
            for (applied) |argument| {
                if (argument.kind == .named and argument.args.len() == 0 and argument.name != .none and
                    std.mem.eql(u8, self.cursor.textOf(argument.name), spelling)) alone += 1;
                named += self.typeNames(argument, spelling);
            }
            valid = alone == 1 and named == 1;
        }
        if (valid) return;

        try self.reportAt(
            .t_impl,
            head.at,
            "a type's own implementation applies its constructor to each of its parameters once",
            "write each parameter alone as one argument, and fix the other arguments to types that name no parameter",
        );
    }

    /// How many times `spelling` stands in a type's position inside `ref`: as
    /// a name, an argument, the base of a selection, or a callable's parameter
    /// or result type.
    fn typeNames(self: *Parser, ref: node.TypeRef, spelling: []const u8) usize {
        var count: usize = 0;
        switch (ref.kind) {
            .named => if (ref.name != .none and std.mem.eql(u8, self.cursor.textOf(ref.name), spelling)) {
                count += 1;
            },
            .selection => if (ref.base != .none) {
                count += self.typeNames(self.builder.type_refs.items[ref.base.index()], spelling);
            },
            .callable => if (ref.callable != .none) {
                const signature = self.builder.callable_types.items[ref.callable.index()];
                for (self.builder.params.items[signature.params.start..signature.params.end]) |param| {
                    count += self.typeNames(param.written, spelling);
                }
                count += self.typeNames(signature.result, spelling);
            },
            else => {},
        }
        for (self.builder.typeArgs(ref.args)) |argument| count += self.typeNames(argument, spelling);
        return count;
    }

    /// Generic receiver arguments are distinct bare parameters in declaration
    /// order. Trait keys may determine parameters absent from the receiver;
    /// inherent implementations must determine every parameter from it.
    fn refuseAHeadThatIsNotItsParameters(
        self: *Parser,
        code: Code,
        head: node.TypeRef,
        type_params: node.TypeParamRange,
        allow_subset: bool,
    ) !bool {
        // A grouped head names nothing, and was refused where it was written;
        // what it applies is not a further question.
        if (head.kind == .grouped) return false;
        const declared = self.builder.typeParams(type_params);
        if (declared.len == 0) return true;

        const applied = self.builder.typeArgs(head.args);
        var next: usize = 0;
        var valid = allow_subset or applied.len == declared.len;
        for (applied) |argument| {
            if (argument.kind != .named or argument.args.len() != 0 or argument.name == .none) {
                valid = false;
                break;
            }
            while (next < declared.len and !std.mem.eql(u8, self.cursor.textOf(argument.name), self.cursor.textOf(declared[next].name))) : (next += 1) {}
            if (next == declared.len) {
                valid = false;
                break;
            }
            next += 1;
        }
        if (valid) return true;

        try self.reportAt(
            code,
            head.at,
            if (code == .t_derive)
                "a derive's head is the constructor applied to its own parameters"
            else
                "an implementation's head is the constructor applied to its own parameters",
            if (allow_subset)
                "receiver arguments are distinct bare parameters in declaration order"
            else
                "each parameter appears here once, in the order it was declared",
        );
        return false;
    }

    const ParsedDeriveTraits = struct {
        range: node.DeriveTraitRange,
        open: TokenId = .none,
        close: TokenId = .none,
    };

    fn parseDeriveTraits(self: *Parser) std.mem.Allocator.Error!ParsedDeriveTraits {
        const start = self.builder.deriveTraitMark();
        const open = self.cursor.eat(.l_paren) orelse TokenId.none;

        while (!self.cursor.atEnd() and (open == .none or !self.cursor.at(.r_paren))) {
            if (open != .none and self.atDeclaration()) break;
            const before = self.cursor.current();
            const ref = try self.parseTraitRef("expected a trait name after `derive`", "a derive request names each capability it generates");
            if (self.cursor.current() == before) break;
            try self.builder.addDeriveTrait(.{
                .ref = ref,
                .tokens = .{ .start = if (ref.path.len() == 0) ref.name else ref.path.start, .end = self.cursor.current() },
            });

            if (open == .none or self.cursor.eat(.comma) == null) break;
        }

        var close = TokenId.none;
        if (open != .none) {
            close = self.cursor.eat(.r_paren) orelse value: {
                try self.reportAt(.s_params, self.cursor.current(), "expected `)`", "a grouped derive closes its trait list");
                break :value TokenId.none;
            };
        }
        return .{
            .range = .{ .start = start, .end = self.builder.deriveTraitMark() },
            .open = open,
            .close = close,
        };
    }

    fn parseDerive(self: *Parser) std.mem.Allocator.Error!node.DeclId {
        const start = self.cursor.advance();
        const type_params = try self.parseTypeParams(.refused);
        const traits = try self.parseDeriveTraits();
        const has_for = self.cursor.eat(.keyword_for) != null;
        if (!has_for) {
            try self.reportAt(.s_entry, self.cursor.current(), "expected `for`", "a derive request names the type receiving the implementation");
        }

        const target = self.cursor.current();
        const target_is_boundary = !has_for and self.atDeclaration();
        var head: node.TypeRef = .{ .at = target, .name = target };
        if (target_is_boundary) {
            try self.reportAt(.s_name, target, "expected a type name after `for`", "a derive request names its target type");
        } else if (self.cursor.at(.l_paren)) {
            // A tuple target is read as an implementation head's is, and the
            // request then derives for the tuple's declaration.
            head = try self.parseUnitType();
            try self.refuseAGroupedHead(head, "a derive request names its target type");
        } else {
            if (self.cursor.eat(.identifier) == null) {
                try self.reportAt(.s_name, target, "expected a type name after `for`", "a derive request names its target type");
            }
            if (self.cursor.at(.l_bracket)) head.args = try self.parseTypeArgs();
        }
        var head_valid = !target_is_boundary;
        if (!target_is_boundary) {
            head_valid = try self.refuseAHeadThatIsNotItsParameters(.t_derive, head, type_params, true);
        }

        var where_at = TokenId.none;
        var where_predicates = node.WherePredicateRange.empty;
        if (!self.cursor.precededByNewline()) {
            if (self.cursor.eat(.keyword_where)) |at| {
                where_at = at;
                where_predicates = try self.parseWherePredicates();
            }
        }

        try self.endBodilessDecl("this derive request ends here");
        return self.builder.addDecl(.{
            .tag = .derive_impl,
            .main_token = start,
            .token_range = self.rangeFrom(start),
            .name = head.at,
            .head_args = head.args,
            .head_kind = head.kind,
            .type_params = type_params,
            .derive_traits = traits.range,
            .derive_syntax = .{
                .group_open = traits.open,
                .group_close = traits.close,
                .head_valid = head_valid,
            },
            .where_at = where_at,
            .where_predicates = where_predicates,
            .params = .{ .start = 0, .end = 0 },
            .returns = .{ .name = .none },
            .body = .none,
            .variants = .{ .start = 0, .end = 0 },
        });
    }

    test "a derive request's target may be a tuple of its own parameters" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();

        const ground = try parseProgramText(arena.allocator(),
            \\derive Debug for (UInt8, Bool)
            \\fn main() -> UInt8 { 0 }
        );
        try testing.expectEqual(@as(u32, 0), ground.errors);
        try testing.expect(std.mem.indexOf(u8, ground.dump, "decl derive_impl single \"(UInt8, Bool)\"") != null);

        const generic = try parseProgramText(arena.allocator(),
            \\derive[A, B] (Debug, Equatable) for (A, B) where A: Debug
            \\fn main() -> UInt8 { 0 }
        );
        try testing.expectEqual(@as(u32, 0), generic.errors);
        try testing.expect(std.mem.indexOf(u8, generic.dump, "decl derive_impl grouped \"(A, B)\"") != null);

        // A component that is not one of the derive's own parameters is
        // refused as a head argument naming none is.
        try testing.expectEqualSlices(?Code, &.{.t_derive}, try codesOf(arena.allocator(), "derive[A] Debug for (A, UInt8)\nfn main() -> UInt8 { 0 }\n"));
    }

    /// `trait Name { fn f(…) -> T }`.
    ///
    /// Its signatures are owned by it, exactly as an `impl`'s members are owned
    /// by the type they belong to -- so a trait's namespace is the mechanism a
    /// type's already is, and nothing downstream needs a case for it.
    fn parseTrait(self: *Parser) std.mem.Allocator.Error!node.DeclId {
        const start = self.cursor.current();
        _ = self.cursor.advance();

        const name = self.cursor.current();
        _ = try self.expectName(.s_name, "expected a name after `trait`", "a trait declares a name");

        // A trait may be generic on its own account, which is what lets one
        // relate two types. Its parameters are in scope in every signature it
        // declares, so they are read before the brace those are written after.
        const type_params = try self.parseTypeParams(.refused);

        // The reader every other bound position uses, so a trait's own bound is
        // a `+`-separated list without a second grammar for it, and a trait
        // named twice in one is one bound on the reading a type parameter's
        // duplicate already gets.
        const bounds = try self.parseBounds();

        var where_at = TokenId.none;
        var where_predicates = node.WherePredicateRange.empty;
        if (self.cursor.eat(.keyword_where)) |at| {
            where_at = at;
            where_predicates = try self.parseWherePredicates();
        }

        if (self.cursor.eat(.l_brace) == null) {
            try self.reportAt(.s_brace, self.cursor.current(), "expected `{`", "a trait lists what it requires");
            return self.traitDecl(start, name, type_params, bounds, where_at, where_predicates);
        }

        while (!self.cursor.atEnd() and !self.cursor.at(.r_brace)) {
            const before = self.cursor.current();
            const at = self.cursor.current();

            const declared: ?node.DeclId = if (self.cursor.at(.keyword_fn))
                try self.parseSignature()
            else if (self.atProjection())
                try self.parseProjection(.signature)
            else if (self.atAssociatedType())
                try self.parseAssociatedType(.asked)
            else
                null;

            if (declared) |d| {
                // No visibility of its own. Every signature is reachable
                // wherever the trait is -- a trait with a requirement nobody
                // outside could see would be one nobody outside could
                // implement -- so `pub` on one would say nothing.
                self.builder.markOwner(d, name);
            } else {
                try self.reportAt(.s_entry, at, "a trait holds signatures, projections and types", "expected `fn`, `proj` or `type` here");
                while (!self.cursor.atEnd() and !self.cursor.at(.r_brace) and
                    !self.cursor.at(.keyword_fn) and !self.atProjection() and !self.atAssociatedType())
                {
                    _ = self.cursor.advance();
                }
            }

            if (self.cursor.current() == before) _ = self.cursor.advance();
        }

        if (self.cursor.eat(.r_brace) == null) {
            try self.reportAt(.s_brace, self.cursor.current(), "expected `}`", "this trait is never closed");
        }
        return self.traitDecl(start, name, type_params, bounds, where_at, where_predicates);
    }

    /// Whether a member begins with `type`.
    ///
    /// `type` is not in the keyword table. Inside a trait or an implementation
    /// a member begins with `fn`, `let` or `type` and with nothing else, so
    /// the position tells one from a name -- and reserving the word would cost
    /// every program that wanted an ordinary noun for a binding.
    ///
    /// The name after it is what makes it a member: a lone `type` is a name
    /// written where no member can begin, and is reported as one.
    fn atAssociatedType(self: *const Parser) bool {
        return self.atContextualMember(token.contextual_words.declared_type);
    }

    /// Whether a member begins with `proj`.
    ///
    /// Contextual for the reason `type` is, and read the same way: the word
    /// followed by the name it introduces. A lone `proj` is a name written
    /// where no member can begin, and the braces it sits in report it as that.
    fn atProjection(self: *const Parser) bool {
        return self.atContextualMember(token.contextual_words.projection);
    }

    fn atDelegation(self: *const Parser) bool {
        return self.cursor.at(.identifier) and std.mem.eql(u8, self.cursor.textOf(self.cursor.current()), token.contextual_words.delegation);
    }

    fn parseDelegationTarget(self: *Parser) !TokenId {
        const next_declaration = self.cursor.precededByNewline() and
            (self.atDeclaration() or self.atAssociatedType() or self.atProjection() or self.atTraversal());
        if (!next_declaration) {
            if (self.cursor.eat(.identifier)) |field| return field;
        }
        try self.reportAt(.s_name, self.cursor.current(), "expected a stored field after `via`", "delegation names one direct field");
        return .none;
    }

    /// Whether a member begins with `trav`.
    ///
    /// Contextual for the reason `proj` is, and read by the same routine: the
    /// word followed by the name it introduces.
    fn atTraversal(self: *const Parser) bool {
        return self.atContextualMember(token.contextual_words.traversal);
    }

    /// A contextual word standing where a member begins, followed by the name
    /// that member declares.
    ///
    /// One reader, because a word is a keyword here only by its position and
    /// two readings of "here" would put one word in a position the other did
    /// not -- which the recovery loops, asking the same question a second time,
    /// are exactly where it would show.
    fn atContextualMember(self: *const Parser, word: []const u8) bool {
        if (!self.cursor.at(.identifier)) return false;
        if (!std.mem.eql(u8, self.cursor.textOf(self.cursor.current()), word)) return false;
        return self.cursor.peekAt(1) == .identifier;
    }

    /// Whether `default` begins a default implementation here.
    ///
    /// `default` is a contextual word: before `impl` it marks a fallback
    /// implementation, and anywhere else it is a name, which is what lets a
    /// trait declare `fn default() -> Self`.
    fn atDefaultImplementation(self: *const Parser) bool {
        if (!self.cursor.at(.identifier)) return false;
        if (!std.mem.eql(u8, self.cursor.textOf(self.cursor.current()), token.contextual_words.default_implementation)) return false;
        return self.cursor.peekAt(1) == .keyword_impl;
    }

    /// Which braces a declared type is being read in, and so what it may say.
    const TypeMember = enum {
        /// A trait's. The type is asked for here and settled elsewhere.
        asked,
        /// An implementation of a trait's. The type is settled here.
        answered,
    };

    /// `type Item` in a trait, and `type Item = UInt8` in an implementation of
    /// it.
    ///
    /// One routine for both sides, because a member is what a trait declares
    /// and what an implementation supplies. Reading them apart would be two
    /// grammars for one form, and the two would come to disagree about what it
    /// is -- so the side is a parameter and the difference is one report.
    fn parseAssociatedType(self: *Parser, side: TypeMember) std.mem.Allocator.Error!node.DeclId {
        const start = self.cursor.advance();

        // The name is what said this was a member at all, so there is one to
        // take: a lone `type` is a name written where no member can begin, and
        // the braces this sits in report it as that.
        const name = self.cursor.advance();

        const at_colon = self.cursor.current();
        const bounds = try self.parseBounds();

        var settled: node.TypeRef = .{ .name = .none };
        const at_equal = self.cursor.current();
        if (self.cursor.eat(.equal) != null) settled = try self.parseWrittenType();

        // Read and then refused, rather than left unparsed: what follows the
        // `=` is a written type wherever it is, and a reader that stopped here
        // would report the rest of it as a second mistake.
        if (side == .asked and settled.wasWritten()) {
            try self.reportAt(
                .s_entry,
                at_equal,
                "a trait declares a type and does not settle it",
                "an implementation says what it is",
            );
        }

        // The mirror of the refusal above. What a settling must satisfy is
        // the trait's to say, so a bound written on the answering side would
        // be a requirement the implementation wrote for itself: nothing reads
        // it, and nothing outside could rely on it.
        if (side == .answered and bounds.len() != 0) {
            try self.reportAt(
                .s_entry,
                at_colon,
                "a settled type carries no bound",
                "the trait that declares it says what it requires",
            );
        }

        try self.endBodilessDecl("this declared type ends here");

        return self.builder.addDecl(.{
            .tag = .associated_type,
            .main_token = start,
            .token_range = self.rangeFrom(start),
            .name = name,
            .params = .{ .start = 0, .end = 0 },
            .bounds = bounds,
            .returns = settled,
            .body = .none,
            .variants = .{ .start = 0, .end = 0 },
        });
    }

    fn traitDecl(
        self: *Parser,
        start: TokenId,
        name: TokenId,
        type_params: node.TypeParamRange,
        bounds: node.BoundRange,
        where_at: TokenId,
        where_predicates: node.WherePredicateRange,
    ) std.mem.Allocator.Error!node.DeclId {
        return self.builder.addDecl(.{
            .tag = .trait_,
            .main_token = start,
            .token_range = self.rangeFrom(start),
            .name = name,
            .type_params = type_params,
            .bounds = bounds,
            .where_at = where_at,
            .where_predicates = where_predicates,
            .params = .{ .start = 0, .end = 0 },
            .returns = .{ .name = .none },
            .body = .none,
            .variants = .{ .start = 0, .end = 0 },
        });
    }

    fn implDecl(
        self: *Parser,
        tag: node.Decl.Tag,
        start: TokenId,
        head: node.TypeRef,
        trait_ref: node.TraitRef,
        type_params: node.TypeParamRange,
        where_at: TokenId,
        where_predicates: node.WherePredicateRange,
        template_requirements: node.TemplateRequirementRange,
    ) std.mem.Allocator.Error!node.DeclId {
        // A callable head is kept whole as the one argument of its declaration:
        // its signature lives in the callable-type table, which a declaration's
        // own columns have no field for.
        var head_args = head.args;
        if (head.kind == .callable) {
            const first = self.builder.typeRefMark();
            try self.builder.addTypeRef(head);
            head_args = .{ .start = first, .end = first + 1 };
        }
        return self.builder.addDecl(.{
            .tag = tag,
            .main_token = start,
            .token_range = self.rangeFrom(start),
            .name = head.at,
            .head_args = head_args,
            .head_kind = head.kind,
            .type_params = type_params,
            .trait_ref = trait_ref,
            .where_at = where_at,
            .where_predicates = where_predicates,
            .template_requirements = template_requirements,
            .params = .{ .start = 0, .end = 0 },
            .returns = .{ .name = .none },
            .body = .none,
            .variants = .{ .start = 0, .end = 0 },
        });
    }

    /// Whether the cursor sits where a declaration can begin. One place, so
    /// recovery and dispatch cannot disagree about what a declaration is.
    fn atDeclaration(self: *const Parser) bool {
        if (self.atDefaultImplementation()) return true;
        return switch (self.cursor.peek()) {
            .keyword_pub,
            .keyword_internal,
            .keyword_export,
            .at_sign,
            .keyword_opaque,
            .keyword_linear,
            .keyword_copyable,
            .keyword_carrier,
            .keyword_test,
            .keyword_template,
            .keyword_derive,
            .keyword_impl,
            .keyword_fn,
            .keyword_import,
            .keyword_use,
            .keyword_enum,
            .keyword_struct,
            .keyword_let,
            => true,
            // `type` and `alias` are not keywords, so recovery asks the same
            // question dispatch does rather than falling through to a token
            // switch that cannot see them.
            else => self.atNewtype() or self.atAlias(),
        };
    }

    /// A dotted path, and the element its name comes from.
    ///
    /// One routine, because `import` and `use` write the same thing and had
    /// come to read it two ways. A path element is a name and a name can end a
    /// statement, so the newline after one ends the declaration rather than
    /// reaching down a line for another element -- and left out of the `use`
    /// loop, a re-export swallowed the line below it and exported whatever it
    /// found there.
    ///
    /// The range ends at the last element rather than at whatever the cursor
    /// reached. The cursor skips trivia, so a range taken from it runs to the
    /// next declaration and swallows the comments between -- which the
    /// formatter then had to undo by re-scanning the tokens for the tight end.
    const Path = struct { range: TokenRange, last: TokenId };

    fn parsePath(self: *Parser, comptime what: []const u8, comptime missing: []const u8) !Path {
        const path_start = self.cursor.current();
        var last = self.cursor.current();
        if (self.cursor.eat(.identifier)) |first| {
            last = first;
            while (!self.pathEndsAtALineBreak() and self.cursor.eat(.dot) != null) {
                const seg = self.cursor.current();
                if (self.cursor.eat(.identifier) == null) {
                    try self.reportAt(.s_name, seg, "expected a name after `.`", "a path element is a name");
                    break;
                }
                last = seg;
            }
        } else {
            try self.reportAt(.s_name, path_start, "expected a path after `" ++ what ++ "`", missing);
        }
        return .{
            .range = .{ .start = path_start, .end = TokenId.at(last.index() + 1) },
            .last = last,
        };
    }

    /// `import a.b;`, or `import a.b as c;`.
    ///
    /// The dots separate directories, not namespaces: `util.hash` names the
    /// directory `util/hash` beside the importing module and loads nothing
    /// called `util`. What the import binds is the last element, or the alias
    /// where one is given.
    fn parseImport(self: *Parser) !node.DeclId {
        const start = self.cursor.current();
        _ = self.cursor.advance(); // import

        const parsed = try self.parsePath("import", "an import names a directory");
        const path = parsed.range;

        // The alias replaces the last element as the name this file uses, which
        // is the only way two paths ending in the same element can both be
        // imported here.
        var name = parsed.last;
        if (!self.finishedAtALineBreak() and self.cursor.eat(.keyword_as) != null) {
            const alias = try self.expectName(.s_name, "expected a name after `as`", "an alias is a name");
            if (alias != .none) {
                name = alias;
            }
        }

        // An import ends where a statement does: at a `;`, at the newline
        // after it, or at the end of the file. It is a declaration rather than
        // a statement, but nothing about that makes a different terminator
        // worth learning.
        const separated = self.cursor.eat(.semicolon) != null;
        if (!separated) {
            if (!self.cursor.precededByNewline() and !self.cursor.atEnd()) {
                try self.reportAt(
                    .s_separator,
                    self.cursor.current(),
                    "expected `;` or a newline",
                    "this import ends here",
                );
            }
            try self.noteContinuation();
        }

        return self.builder.addDecl(.{
            .tag = .import_,
            .main_token = start,
            .token_range = self.rangeFrom(start),
            .name = name,
            .params = .{ .start = 0, .end = 0 },
            .returns = .{ .name = .none },
            .body = .none,
            .variants = .{ .start = 0, .end = 0 },
            .path = path,
        });
    }

    /// `pub use m.Name;`.
    ///
    /// The last element is a declaration in the module the rest names, which
    /// is what makes this different from an import: an import binds a module
    /// and this binds something inside one. What it binds it under is that
    /// last element, so a re-export cannot rename what it re-exports.
    fn parseUse(self: *Parser) !node.DeclId {
        const start = self.cursor.current();
        _ = self.cursor.advance(); // use

        const parsed = try self.parsePath("use", "a re-export names a declaration");
        const path = parsed.range;
        const last = parsed.last;

        // A re-export ends where an import does, and for the same reason: a
        // newline ends a statement, and a declaration is not worth a second
        // terminator to learn.
        const separated = self.cursor.eat(.semicolon) != null;
        if (!separated) {
            if (!self.cursor.precededByNewline() and !self.cursor.atEnd()) {
                try self.reportAt(
                    .s_separator,
                    self.cursor.current(),
                    "expected `;` or a newline",
                    "this re-export ends here",
                );
            }
            try self.noteContinuation();
        }

        return self.builder.addDecl(.{
            .tag = .use_,
            .main_token = start,
            .token_range = self.rangeFrom(start),
            .name = last,
            .params = .{ .start = 0, .end = 0 },
            .returns = .{ .name = .none },
            .body = .none,
            .variants = .{ .start = 0, .end = 0 },
            .path = path,
        });
    }

    /// `enum Name { A, B }`. Declares a type rather than a value, so it has no
    /// parameters, no return type and no body.
    fn parseEnum(self: *Parser) !node.DeclId {
        const start = self.cursor.current();
        _ = self.cursor.advance(); // enum

        const name = self.cursor.current();
        _ = try self.expectName(.s_name, "expected a name after `enum`", "an enum needs a name");
        const type_params = try self.parseTypeParams(.admitted);

        var where_at = TokenId.none;
        var where_predicates = node.WherePredicateRange.empty;
        if (self.cursor.eat(.keyword_where)) |at| {
            where_at = at;
            where_predicates = try self.parseWherePredicates();
        }

        const first = self.builder.variantMark();
        if (self.cursor.eat(.l_brace) == null) {
            try self.reportAt(.s_enum, self.cursor.current(), "expected `{`", "an enum lists its variants");
        } else {
            while (!self.cursor.atEnd() and !self.cursor.at(.r_brace)) {
                const before = self.cursor.current();

                if (try self.stepOverTypeIntruders(.s_enum, "an enum lists its variants, and `impl Name { .. }` holds what it can do")) continue;
                if (self.cursor.at(.r_brace)) break;

                // A keyword taken in a variant's name declares no variant, so
                // its payload is read and nothing asks for the variant again.
                const vname = try self.expectName(.s_enum, "expected a variant name", "a variant is a name");
                if (vname != .none) {
                    const fields = try self.parsePayload();
                    if (self.cursor.tags[vname.index()] == .identifier) try self.builder.addVariant(.{ .name = vname, .fields = fields });
                }

                // A trailing comma is allowed: a variant list is edited a line
                // at a time, and the last line should not be special.
                if (self.cursor.eat(.comma) == null) break;

                // Recovery that consumes nothing would loop forever, the same
                // way a statement sequence would.
                if (self.cursor.current() == before) _ = self.cursor.advance();
            }

            if (self.cursor.eat(.r_brace) == null) {
                try self.reportAt(.s_enum, self.cursor.current(), "expected `}`", "this enum is never closed");
            }
        }

        return self.builder.addDecl(.{
            .tag = .enum_,
            .main_token = start,
            .token_range = self.rangeFrom(start),
            .name = name,
            .params = .{ .start = 0, .end = 0 },
            .type_params = type_params,
            .where_at = where_at,
            .where_predicates = where_predicates,
            .returns = .{ .name = .none },
            .body = .none,
            .variants = .{ .start = first, .end = self.builder.variantMark() },
        });
    }

    /// What a variant carries, as a run of fields.
    ///
    /// Spelled like a call because a variant is constructed like one, and a
    /// grammar that declares an alternative one way and builds it another
    /// makes a reader learn two shapes for one thing.
    fn parsePayload(self: *Parser) !node.FieldRange {
        const start = self.builder.fieldMark();
        if (self.cursor.eat(.l_paren) == null) return .{ .start = start, .end = start };

        while (!self.cursor.atEnd() and !self.cursor.at(.r_paren)) {
            const before = self.cursor.current();

            const ty = self.cursor.current();
            if (self.cursor.at(.identifier) or self.cursor.at(.l_bracket) or
                self.cursor.at(.keyword_fn) or self.cursor.at(.keyword_borrow) or self.cursor.at(.l_paren))
            {
                // Positional, so no name -- what a variant carries is reached
                // by matching rather than by naming.
                const written = try self.parseWrittenType();
                try self.builder.addField(.{
                    .written = written,
                    .type_end = self.justPassed(),
                });
            } else {
                try self.reportAt(.s_type, ty, "expected a type", "a variant carries values of some type");
            }

            if (self.cursor.eat(.comma) == null) break;
            if (self.cursor.current() == before) _ = self.cursor.advance();
        }

        if (self.cursor.eat(.r_paren) == null) {
            try self.reportAt(.s_enum, self.cursor.current(), "expected `)`", "this payload is never closed");
        }
        return .{ .start = start, .end = self.builder.fieldMark() };
    }

    /// `struct Name { x: T, y: U }`.
    ///
    /// Declares a type as named parts. Like an enum it has no body and no
    /// parameters, and unlike one its parts are named: a field is reached by
    /// naming it, so the name is what a reader writes rather than a position
    /// they count.
    fn parseStruct(self: *Parser) !node.DeclId {
        const start = self.cursor.current();
        _ = self.cursor.advance(); // struct

        const name = self.cursor.current();
        _ = try self.expectName(.s_name, "expected a name after `struct`", "a struct needs a name");
        const type_params = try self.parseTypeParams(.admitted);

        var where_at = TokenId.none;
        var where_predicates = node.WherePredicateRange.empty;
        if (self.cursor.eat(.keyword_where)) |at| {
            where_at = at;
            where_predicates = try self.parseWherePredicates();
        }

        const first = self.builder.fieldMark();
        if (self.cursor.eat(.l_brace) == null) {
            try self.reportAt(.s_struct, self.cursor.current(), "expected `{`", "a struct lists its fields");
        } else {
            while (!self.cursor.atEnd() and !self.cursor.at(.r_brace)) {
                const before = self.cursor.current();

                if (try self.stepOverTypeIntruders(.s_struct, "a struct holds its fields, and `impl Name { .. }` holds what it can do")) continue;
                if (self.cursor.at(.r_brace)) break;

                const fname = try self.expectName(.s_field, "expected a field name", "a field is a name and a type");
                if (fname == .none) {} else if (self.cursor.eat(.colon) == null) {
                    try self.reportAt(.s_field, self.cursor.current(), "expected `:`", "a field is always annotated");
                } else {
                    const ty = self.cursor.current();
                    if (self.cursor.at(.identifier) or self.cursor.at(.l_bracket) or self.startsCallableType() or
                        self.cursor.at(.keyword_borrow) or self.cursor.at(.l_paren))
                    {
                        const written = try self.parseWrittenType();
                        // A keyword taken in the field's name declares no
                        // field, so no literal is asked to give it a value.
                        if (self.cursor.tags[fname.index()] == .identifier) try self.builder.addField(.{
                            .name = fname,
                            .written = written,
                            .type_end = self.justPassed(),
                        });
                    } else {
                        try self.reportAt(.s_type, ty, "expected a type", "a `:` introduces a type");
                    }
                }

                // A trailing comma is allowed: a field list is edited a line
                // at a time, and the last line should not be special.
                if (self.cursor.eat(.comma) == null) break;

                // Recovery that consumes nothing would loop forever.
                if (self.cursor.current() == before) _ = self.cursor.advance();
            }

            if (self.cursor.eat(.r_brace) == null) {
                try self.reportAt(.s_struct, self.cursor.current(), "expected `}`", "this struct is never closed");
            }
        }

        return self.builder.addDecl(.{
            .tag = .struct_,
            .main_token = start,
            .token_range = self.rangeFrom(start),
            .name = name,
            .params = .{ .start = 0, .end = 0 },
            .type_params = type_params,
            .where_at = where_at,
            .where_predicates = where_predicates,
            .returns = .{ .name = .none },
            .body = .none,
            .variants = .{ .start = 0, .end = 0 },
            .fields = .{ .start = first, .end = self.builder.fieldMark() },
        });
    }

    /// Whether a module-level declaration begins with `type`.
    ///
    /// `type` is not in the keyword table, exactly as it is not before a
    /// trait's or an implementation's declared type: a module-level
    /// declaration begins with `fn`, `extern`, `trait`, `import`, `use`,
    /// `enum`, `struct`, `let` or `impl`, and with nothing else, so position
    /// alone tells `type Name = Base` from an ordinary name written where no
    /// declaration can begin. The same reading `atAssociatedType` gives at a
    /// different position in the grammar, so the two forms cannot collide:
    /// one is read only inside a trait's or an implementation's braces, and
    /// this one only at the top of a file.
    fn atNewtype(self: *const Parser) bool {
        if (!self.cursor.at(.identifier)) return false;
        const word = token.contextual_words.declared_type;
        if (!std.mem.eql(u8, self.cursor.textOf(self.cursor.current()), word)) return false;
        return self.cursor.peekAt(1) == .identifier;
    }

    /// `type Name = Base`, and `type Name = Base where it in lo..=hi`.
    ///
    /// A distinct nominal type over one base: same representation, a
    /// different contract. No braces, because nothing new is represented --
    /// a type's braces hold its representation and nothing else, and this
    /// declares none of its own.
    fn parseNewtype(self: *Parser) std.mem.Allocator.Error!node.DeclId {
        const start = self.cursor.current();
        _ = self.cursor.advance(); // type

        // `atNewtype` already confirmed an identifier sits here.
        const name = self.cursor.advance();

        if (self.cursor.eat(.equal) == null) {
            try self.reportAt(.s_equals, self.cursor.current(), "expected `=`", "a newtype is declared over a base type");
        }

        const base = try self.parseWrittenType();

        var refinement: ?node.Refinement = null;
        // A reserved word cannot begin a statement, so seeing `where` here --
        // on this line or, past a line break, on the next -- can only be this
        // clause continuing the head. No lookahead past the break is needed:
        // the token itself already decides it.
        if (self.cursor.at(.keyword_where)) refinement = try self.parseRefinement();

        try self.endBodilessDecl("this declaration ends here");

        return self.builder.addDecl(.{
            .tag = .newtype,
            .main_token = start,
            .token_range = self.rangeFrom(start),
            .name = name,
            .params = .{ .start = 0, .end = 0 },
            .returns = base,
            .body = .none,
            .variants = .{ .start = 0, .end = 0 },
            .has_refinement = refinement != null,
            .refinement_at = if (refinement) |r| r.at else .none,
            .refinement_lo_minus = if (refinement) |r| r.lo_minus else .none,
            .refinement_lo = if (refinement) |r| r.lo_token else .none,
            .refinement_hi_minus = if (refinement) |r| r.hi_minus else .none,
            .refinement_hi = if (refinement) |r| r.hi_token else .none,
            .refinement_inclusive = if (refinement) |r| r.inclusive else false,
        });
    }

    /// Whether the cursor stands at `alias Name`: the contextual word, then a
    /// name. Read by position exactly as `type Name` is, because a module-level
    /// declaration begins with a keyword and nothing else.
    fn atAlias(self: *const Parser) bool {
        if (!self.cursor.at(.identifier)) return false;
        const word = token.contextual_words.type_alias;
        if (!std.mem.eql(u8, self.cursor.textOf(self.cursor.current()), word)) return false;
        return self.cursor.peekAt(1) == .identifier;
    }

    /// `alias Name = Type`, and `alias Name[T] = Type`.
    ///
    /// Another name for a written type. It declares no representation, so
    /// it takes no braces and no refinement: a clause narrowing what a type
    /// admits makes a new type, which is what `type` declares.
    fn parseAlias(self: *Parser) std.mem.Allocator.Error!node.DeclId {
        const start = self.cursor.current();
        _ = self.cursor.advance(); // alias

        // `atAlias` already confirmed an identifier sits here.
        const name = self.cursor.advance();
        const type_params = try self.parseTypeParams(.admitted);

        if (self.cursor.eat(.equal) == null) {
            try self.reportAt(.s_equals, self.cursor.current(), "expected `=`", "an alias names the type written after `=`");
        }

        const named = try self.parseWrittenType();

        try self.endBodilessDecl("this alias ends here");

        return self.builder.addDecl(.{
            .tag = .alias,
            .main_token = start,
            .token_range = self.rangeFrom(start),
            .name = name,
            .params = .{ .start = 0, .end = 0 },
            .returns = named,
            .body = .none,
            .variants = .{ .start = 0, .end = 0 },
            .type_params = type_params,
        });
    }

    /// `where it in lo..=hi`, called with the cursor already at `where`.
    ///
    /// A malformed clause reports through the shapes a written type and a
    /// range already report through -- [S-Type] for a missing structural
    /// word, [S-Range] for a bound that is not a literal -- rather than a
    /// rule of its own: nothing about a refinement's grammar is new, it is a
    /// range with a name in front.
    ///
    /// The one line break the clause admits is the one before `where`,
    /// already spent by the caller before this is reached: `parseNewtype`
    /// commits to the clause on the token alone, not on whether a break came
    /// first. The rest of the clause is the line `where` opens, and it is
    /// read from a cursor that ends where that line does -- so a break past
    /// `where` ends the declaration wherever it falls, at one of these
    /// positions, inside a bound, or at a position a later clause form adds,
    /// through the one rule rather than through a check written at each. A
    /// clause a break cut short is a clause nobody wrote: what it holds is
    /// recorded as missing rather than as the range the tokens before the
    /// break would make.
    fn parseRefinement(self: *Parser) std.mem.Allocator.Error!node.Refinement {
        const at = self.cursor.advance(); // where

        const nothing: node.Refinement = .{
            .at = at,
            .lo_minus = .none,
            .lo_token = .none,
            .hi_minus = .none,
            .hi_token = .none,
            .inclusive = false,
        };
        var out = nothing;

        const line_end = self.cursor.lineEnd();
        const whole = self.cursor.narrowTo(line_end);
        self.clause = .{ .end = line_end };
        defer {
            self.cursor.widen(whole);
            self.clause = null;
        }

        const it = self.cursor.current();
        if (self.cursor.at(.identifier) and std.mem.eql(u8, self.cursor.textOf(it), "it")) {
            _ = self.cursor.advance();
        } else {
            try self.reportAt(.s_type, it, "expected `it`", "a refinement names its value `it`");
        }

        if (self.cursor.eat(.keyword_in) == null) {
            try self.reportAt(
                .s_type,
                self.cursor.current(),
                "expected `in`",
                "a refinement states the range its value lies in",
            );
        }

        const lo = try self.parseBound();
        out.lo_minus = lo.minus;
        out.lo_token = lo.digits;

        if (isRangeOp(self.cursor.peek())) {
            out.inclusive = self.cursor.peek() == .dot_dot_equal;
            _ = self.cursor.advance();
        } else {
            try self.reportAt(.s_range, self.cursor.current(), "expected `..` or `..=`", "a refinement is a range");
        }

        const hi = try self.parseBound();
        out.hi_minus = hi.minus;
        out.hi_token = hi.digits;

        if (self.clause.?.reported) return nothing;
        return out;
    }

    /// A bound: an integer literal, and the `-` that may precede it.
    ///
    /// One routine, because a bound is one thing written in two places. Read
    /// separately, a range pattern's took its sign and a refinement clause's
    /// did not -- so `-40..=40` was an ordinary pattern and a clause the
    /// parser could not read at all, which then folded to an empty range over
    /// a base whose values are mostly negative.
    ///
    /// The digits are `.none` where none were written, which is what the
    /// caller records for a clause it could not fully read.
    fn parseBound(self: *Parser) std.mem.Allocator.Error!node.Bound {
        const minus = if (self.cursor.at(.minus)) self.cursor.advance() else TokenId.none;

        const digits = self.cursor.current();
        if (self.cursor.eat(.int_literal) == null) {
            try self.reportAt(
                .s_range,
                digits,
                if (minus == TokenId.none) "expected a number" else "expected a number after `-`",
                "a bound is a literal, and a `-` before it negates one",
            );
            return .{ .minus = minus, .digits = TokenId.none };
        }

        return .{ .minus = minus, .digits = digits };
    }

    /// A module or implementation binds a constant, with an optional type.
    /// Its initializer determines the type when no annotation is written.
    fn parseConstant(self: *Parser) std.mem.Allocator.Error!node.DeclId {
        const start = self.cursor.current();
        _ = self.cursor.advance(); // let

        const name = self.cursor.current();
        _ = try self.expectName(.s_name, "expected a name after `let`", "a constant is bound to a name");

        var written: node.TypeRef = .{ .name = .none };
        if (self.cursor.eat(.colon) != null) {
            written = try self.parseWrittenType();
        }

        if (self.cursor.eat(.equal) == null) {
            try self.reportAt(.s_equals, self.cursor.current(), "expected `=`", "a constant is given a value");
        }
        const init_expr = try self.parseInitializer();

        // A constant is a binding, so it ends where one does. One routine for
        // both, or a `;` written here would answer a rule stated somewhere
        // else.
        try self.endBinding(init_expr);

        return self.builder.addDecl(.{
            .tag = .constant,
            .main_token = start,
            .token_range = self.rangeFrom(start),
            .name = name,
            .params = .{ .start = 0, .end = 0 },
            .returns = written,
            .body = .none,
            .init = init_expr,
            .variants = .{ .start = 0, .end = 0 },
        });
    }

    /// `trav positions = 0..4`, in a type's own implementation.
    ///
    /// Its optional read receiver supplies the walked value to the positions
    /// expression. The iterator type is inferred from that expression.
    fn parseTraversal(self: *Parser) std.mem.Allocator.Error!node.DeclId {
        const start = self.cursor.advance();

        // The name is what said this was a member at all, so there is one to
        // take: a lone `trav` is a name written where no member can begin, and
        // the braces this sits in report it as that.
        const name = self.cursor.advance();
        const params = if (self.cursor.at(.l_paren)) try self.parseParams() else node.ParamRange{ .start = 0, .end = 0 };

        if (self.atDelegation()) {
            const via = self.cursor.advance();
            const target = try self.parseDelegationTarget();
            if (params.start != params.end) try self.reportAt(.s_entry, via, "a forwarded traversal declares no receiver", "the array supplies fixed positions without a receiver");
            try self.endBodilessDecl("a forwarded traversal ends after its field");
            return self.builder.addDecl(.{
                .tag = .traversal_,
                .main_token = start,
                .token_range = self.rangeFrom(start),
                .name = name,
                .params = params,
                .returns = .{ .name = .none },
                .body = .none,
                .variants = .{ .start = 0, .end = 0 },
                .delegation = .{ .via = via, .target = target },
            });
        }

        if (self.cursor.eat(.equal) == null) {
            try self.reportAt(.s_equals, self.cursor.current(), "expected `=`", "a traversal is given the positions it runs through");
        }
        const init_expr = try self.parseFull();

        // A traversal binds a name to an expression, so it ends where a
        // binding does. One routine for both, or a `;` written here would
        // answer a rule stated somewhere else.
        try self.endBinding(init_expr);

        return self.builder.addDecl(.{
            .tag = .traversal_,
            .main_token = start,
            .token_range = self.rangeFrom(start),
            .name = name,
            .params = params,
            .returns = .{ .name = .none },
            .body = .none,
            .init = init_expr,
            .variants = .{ .start = 0, .end = 0 },
        });
    }

    /// `fn name(params) -> Type { body }`, or `fn name(params) { body }` for
    /// one that returns nothing. A function with a body, which is every one outside a trait.
    fn parseFunction(self: *Parser, site: Site) !node.DeclId {
        return self.parseCallable(.required, .function, site);
    }

    /// A signature: the same header, ended by a newline rather than a body.
    /// The one declaration form that carries no code.
    fn parseSignature(self: *Parser) !node.DeclId {
        return self.parseCallable(.signature, .function, .member);
    }

    /// An `extern fn`, which names a symbol and declares no body.
    fn parseExtern(self: *Parser) !node.DeclId {
        // Past `extern`, so that what follows is the `fn` every other callable
        // starts at and one reader of a signature serves all three.
        _ = self.cursor.advance();
        return self.parseCallable(.external, .function, .member);
    }

    /// `proj at(inout self: Self, i: I) -> Elem`, with a body where an
    /// implementation writes one and without where a trait declares one.
    ///
    /// The same header a function writes, read by the same routine: what a
    /// projection differs in is what its braces mean, and that is settled where
    /// the body is judged rather than where it is read.
    fn parseProjection(self: *Parser, body_rule: Body) !node.DeclId {
        return self.parseCallable(body_rule, .projection, .member);
    }

    /// What a callable does about a body.
    ///
    /// Three answers rather than a flag, because the third is not the second:
    /// a trait's signature is never called, and an `extern` is called and
    /// defined somewhere this compiler did not compile.
    const Body = enum { required, signature, external };

    /// Where a callable is declared, which decides what an omitted result
    /// means and so what a refused `-> ()` should become: a test answers its
    /// default `Result`, and a top-level `main` may be the entry point, which
    /// answers its exit status.
    const Site = enum { member, top_level, test_ };

    /// Which member form is being read, which decides the word it begins with
    /// and the tag it is recorded under. Not what it does about a body: a
    /// projection is declared without one and supplied with one, exactly as a
    /// function is.
    const Callable = enum {
        function,
        projection,

        fn wantsAName(self: Callable) []const u8 {
            return switch (self) {
                .function => "expected a name after `fn`",
                .projection => "expected a name after `proj`",
            };
        }

        fn needsAName(self: Callable) []const u8 {
            return switch (self) {
                .function => "a function needs a name",
                .projection => "a projection needs a name",
            };
        }

        fn needsABody(self: Callable) []const u8 {
            return switch (self) {
                .function => "a function needs a body",
                .projection => "a projection needs a body",
            };
        }
    };

    /// `-> ()` after a callable's parameters, refused by [S-UnitResult]: a
    /// callable that returns nothing writes no result type, so `()` there is
    /// a second spelling of the omitted one. Consumes the `()` and answers
    /// whether it was there, leaving the result unwritten either way.
    ///
    /// Only the unit type written whole. `-> ((), ())` and
    /// `-> Result[(), E]` are results that hold a unit, not unit itself.
    fn refuseWrittenUnit(self: *Parser, arrow: TokenId, label: []const u8, help: []const u8, before_where: ?[]const u8) !bool {
        // `()` inside any number of grouping parentheses, `(())` included:
        // every `(` before the first `)`, then as many `)`.
        var opens: u32 = 0;
        while (self.cursor.peekAt(opens) == .l_paren) opens += 1;
        if (opens == 0) return false;
        for (0..opens) |i| if (self.cursor.peekAt(opens + @as(u32, @intCast(i))) != .r_paren) return false;
        // A lambda writing contracts keeps its arrow before `where`.
        const said = if (before_where != null and self.cursor.peekAt(2 * opens) == .keyword_where) before_where.? else help;
        for (0..2 * opens - 1) |_| _ = self.cursor.advance();
        const close = self.cursor.advance();
        const labels = try self.sink.arena.alloc(Label, 1);
        labels[0] = .{
            .file = self.file,
            .span = Span.merge(self.cursor.spanAt(arrow), self.cursor.spanAt(close)),
            .message = label,
            .style = .primary,
        };
        try self.sink.add(.{
            .severity = .err,
            .code = .s_unit_result,
            .message = "a function that returns nothing writes no result type",
            .labels = labels,
            .notes = try self.sink.arena.dupe([]const u8, &.{said}),
        });
        return true;
    }

    test "a written unit result is refused wherever a result is written, and nothing holding a unit is" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();

        const refused = [_][]const u8{
            "fn f() -> () {}\n",
            "fn f() -> () where carries() {}\n",
            "fn f() -> (()) {}\n",
            "trait T { fn f(self: Self) -> () }\n",
            "extern fn f(at: UInt64) -> ()\n",
            "fn f(_g: fn(x: UInt8) -> ()) {}\n",
            "fn f() { let _g = |x: UInt8| -> () { x } }\n",
            "test fn f() -> () {}\n",
        };
        for (refused) |text| {
            try testing.expectEqualSlices(?Code, &.{.s_unit_result}, try codesOf(gpa, text));
        }

        const accepted = [_][]const u8{
            "fn f() {}\n",
            "fn f() where carries() {}\n",
            "trait T { fn f(self: Self) }\n",
            "extern fn f(at: UInt64)\n",
            "fn f(_g: fn(x: UInt8), _h: inout fn(inout x: UInt8) where carries()) {}\n",
            "fn f() -> ((), ()) { ((), ()) }\n",
            "fn f() -> Result[(), UInt8] { .Ok(()) }\n",
            "fn f() { let _g = |x: UInt8| -> where carries() { x } }\n",
        };
        for (accepted) |text| {
            try testing.expectEqualSlices(?Code, &.{}, try codesOf(gpa, text));
        }

        // A lambda writing contracts keeps its arrow, so only `()` goes,
        // however many parentheses group it.
        for ([_][]const u8{ "()", "(())" }) |unit| {
            const text = try std.fmt.allocPrint(gpa, "fn f() {{ let _g = |x: UInt8| -> {s} where carries() {{ x }} }}\n", .{unit});
            const source: Source = .{ .path = "t.lin", .text = text };
            var sink = Sink.init(gpa);
            var interner: Interner = .empty;
            const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
            _ = try parse(gpa, &source, .from(0), tokens, &sink);
            try testing.expectEqual(@as(usize, 1), sink.items().len);
            try testing.expectEqualStrings("remove `()`; the `->` stays before `where`", sink.items()[0].notes[0]);
        }
    }

    test "a projection still writes the type of the place it names" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        try testing.expectEqualSlices(?Code, &.{.s_type}, try codesOf(arena.allocator(), "trait T { proj at(inout self: Self) }\n"));
    }

    fn parseCallable(self: *Parser, body_rule: Body, kind: Callable, site: Site) !node.DeclId {
        const wants_body = body_rule == .required;
        const start = self.cursor.current();
        _ = self.cursor.advance(); // fn, or proj

        const name = self.cursor.current();
        _ = try self.expectName(.s_name, kind.wantsAName(), kind.needsAName());

        const type_params = try self.parseTypeParams(.admitted);
        const params = try self.parseParams();

        var returns: node.TypeRef = .{ .name = .none };
        var return_type: TokenId = .none;
        if (self.cursor.eat(.arrow)) |arrow| {
            return_type = self.cursor.current();
            // A `main` at the top of a file may be the entry point, whose
            // result is its exit status, so the help says both what removing
            // `-> ()` gives and what an entry point writes. Which file is the
            // root is not known here.
            const main = site == .top_level and self.cursor.tags[name.index()] == .identifier and
                std.mem.eql(u8, self.cursor.textOf(name), "main");
            const label = if (site == .test_) "a test writing no result answers `Result[(), testing.Failure]`" else omitted_unit_label;
            const help = if (main) "remove `-> ()`, or write `-> UInt8` if this `main` is the program's entry point" else remove_written_unit;
            if (kind == .function and try self.refuseWrittenUnit(arrow, label, help, null)) {
                // Read as the omitted form it should have been, so the rest of
                // the declaration is checked as a function returning `()`. A
                // `main`'s is read as a refused result instead, so an entry
                // point is not refused a second time by [S-Entry].
                if (main) returns = .{ .at = arrow, .name = .none };
            } else if (self.cursor.at(.identifier) or self.cursor.at(.l_bracket) or
                self.cursor.at(.l_paren) or self.cursor.at(.keyword_fn) or self.cursor.at(.keyword_borrow))
            {
                // Which type the name reaches is a question about names, so the
                // parser records what was written and the checker answers it.
                // Through the one reader, `()` included: a second place that
                // knew how to spell a type was a second grammar of them.
                self.result_may_split = true;
                returns = try self.parseWrittenType();
            } else {
                try self.reportAt(.s_type, return_type, "expected a type", "a `->` introduces the return type");
                returns = .{ .at = return_type, .name = .none };
            }
        } else if (kind == .projection) {
            // A function that writes no result returns `()`, and a test
            // answers its default `Result`. A projection names a place, and a
            // place has a type that has to be written.
            try self.reportAt(.s_type, self.cursor.current(), "expected `->`", "a projection declares the type of the place it names");
        }

        const where_clause = try self.parseFunctionWhere();
        const contracts = where_clause.contracts;
        const where_at = where_clause.at;
        const where_predicates = where_clause.predicates;

        var body: ExprId = .none;
        var provided = false;
        if (wants_body) {
            if (self.cursor.at(.l_brace)) {
                body = try self.parseBraced("this body is never closed");
            } else {
                try self.reportAt(.s_brace, self.cursor.current(), "expected `{`", kind.needsABody());
            }
        } else if (body_rule == .signature and kind == .function and self.cursor.at(.l_brace)) {
            // A trait's operation written with its body, which every type
            // implementing the trait offers.
            body = try self.parseBraced("this body is never closed");
            provided = true;
        } else if (self.cursor.at(.l_brace)) {
            // A body where none belongs. Read and discarded rather than left
            // for the enclosing loop to trip over: recovery is what lets the
            // declarations after this one still be read.
            if (body_rule == .external) try self.reportAt(
                .s_extern,
                self.cursor.current(),
                "an `extern` has no body",
                "it names a symbol the runtime provides, and declaring one here would define a second",
            ) else try self.reportAt(
                .s_entry,
                self.cursor.current(),
                "a trait's projection has no body",
                "each implementation says which place it names",
            );
            _ = try self.parseBraced("this body is never closed");
        } else {
            try self.endBodilessDecl(
                if (body_rule == .external) "this declaration ends here" else "this signature ends here",
            );
        }

        return self.builder.addDecl(.{
            .tag = if (wants_body and body == ExprId.none)
                .err
            else switch (kind) {
                .function => .function,
                .projection => .projection,
            },
            .origin = if (body_rule == .external) .external else if (provided) .provided else .written,
            .main_token = start,
            .token_range = self.rangeFrom(start),
            .name = name,
            .params = params,
            .type_params = type_params,
            .where_predicates = where_predicates,
            .where_at = where_at,
            .returns = returns,
            .contracts = contracts,
            .body = body,
            .variants = .{ .start = 0, .end = 0 },
        });
    }

    fn parseContractPath(self: *Parser) !node.ContractPath {
        const start = self.cursor.current();
        const first: u32 = @intCast(self.builder.contract_steps.items.len);
        const parsed = try self.parseContractProjection();
        return .{
            .written = .{ .start = start, .end = parsed.end },
            .root = parsed.root,
            .steps = .{ .start = first, .end = @intCast(self.builder.contract_steps.items.len) },
        };
    }

    const ContractProjection = struct { root: TokenId, end: TokenId };

    /// Prefix dereferences follow their operand's postfix fields in the settled
    /// path. Parentheses retain their spelling without creating value expressions.
    fn parseContractProjection(self: *Parser) std.mem.Allocator.Error!ContractProjection {
        const start = self.cursor.current();
        if (self.depth == max_nesting) {
            try self.refuseToDescend(start, "this contract path nests too deeply");
            return .{ .root = .none, .end = self.cursor.current() };
        }
        self.depth += 1;
        self.deepest = @max(self.deepest, self.depth);
        defer self.depth -= 1;

        if (self.cursor.eat(.star)) |at| {
            const operand = try self.parseContractProjection();
            try self.builder.contract_steps.append(self.gpa, .{ .dereference = at });
            return operand;
        }
        var parsed: ContractProjection = if (self.cursor.eat(.l_paren) != null) grouped: {
            var inner = try self.parseContractProjection();
            if (self.cursor.eat(.r_paren)) |close| {
                inner.end = TokenId.at(close.index() + 1);
            } else {
                try self.reportAt(.s_bracket, self.cursor.current(), "expected `)`", "a grouped contract path ends here");
            }
            break :grouped inner;
        } else named: {
            const head = self.cursor.eat(.identifier) orelse {
                try self.reportAt(.s_name, start, "expected a parameter name", "a contract names a parameter or its projections");
                return .{ .root = .none, .end = start };
            };
            break :named .{ .root = head, .end = TokenId.at(head.index() + 1) };
        };
        while (self.cursor.eat(.dot) != null) {
            const at = self.cursor.current();
            const field = self.cursor.eat(.identifier) orelse {
                try self.reportAt(.s_name, at, "expected a field name", "a contract path names a field after the dot");
                break;
            };
            try self.builder.contract_steps.append(self.gpa, .{ .field = field });
            parsed.end = TokenId.at(field.index() + 1);
        }
        return parsed;
    }

    fn atContract(self: *const Parser) bool {
        return switch (self.cursor.peek()) {
            .keyword_borrows, .keyword_carries, .keyword_retains => true,
            else => false,
        };
    }

    fn parseContract(self: *Parser, contracts: *std.ArrayList(node.Contract)) !void {
        const at = self.cursor.current();
        const kind: @FieldType(node.Contract, "kind") = switch (self.cursor.peek()) {
            .keyword_borrows => .borrows,
            .keyword_carries => .carries,
            .keyword_retains => .retains,
            else => unreachable,
        };
        _ = self.cursor.advance();
        if (self.cursor.eat(.l_paren) == null) {
            try self.reportAt(.s_bracket, self.cursor.current(), "expected `(`", "a contract lists its sources in parentheses");
            return;
        }
        if (kind == .carries and self.cursor.at(.r_paren)) {
            try contracts.append(self.gpa, .{ .kind = kind, .at = at, .source = .empty });
        }
        var target: node.ContractPath = .empty;
        if (kind != .retains and self.cursor.eat(.dot) != null) {
            target = try self.parseContractPath();
            if (self.cursor.eat(.colon) == null) {
                try self.reportAt(.s_type, self.cursor.current(), "expected `:`", "a result target precedes its sources");
            }
        }
        var destination: node.ContractPath = .empty;
        if (kind == .retains) {
            destination = try self.parseContractPath();
            if (self.cursor.eat(.colon) == null) {
                try self.reportAt(.s_type, self.cursor.current(), "expected `:`", "retention names a destination before its sources");
            }
        }
        const source_start = contracts.items.len;
        while (!self.cursor.atEnd() and !self.cursor.at(.r_paren)) {
            const borrows_source = kind == .retains and self.cursor.eat(.keyword_borrow) != null;
            const source = try self.parseContractPath();
            try contracts.append(self.gpa, .{ .kind = kind, .at = at, .source = source, .target = target, .destination = destination, .borrows_source = borrows_source });
            if (self.cursor.eat(.comma) == null) break;
        }
        if (contracts.items.len == source_start and (kind != .carries or target.root != .none)) {
            try self.reportAt(.s_name, self.cursor.current(), "expected a contract source", "only `carries()` may omit its sources");
        }
        if (self.cursor.eat(.r_paren) == null) {
            try self.reportAt(.s_bracket, self.cursor.current(), "expected `)`", "a contract's source list ends here");
            return;
        }
    }

    // A callable type can end inside another comma-separated list. Leave
    // its separator in place when another type or parameter follows it.
    fn commaEndsContracts(self: *Parser) bool {
        const saved = self.cursor;
        defer self.cursor = saved;
        _ = self.cursor.advance();
        return switch (self.cursor.peek()) {
            .l_brace,
            .eof,
            .semicolon,
            .equal,
            .colon,
            .plus,
            .keyword_where,
            => true,
            // An unnamed fn starts another callable type; a named fn starts
            // the next declaration after the type containing these contracts.
            .keyword_fn => self.cursor.peekAt(1) == .identifier,
            else => self.atDeclaration(),
        };
    }

    fn consumePendingContractComma(self: *Parser) void {
        if (self.cursor.current() != self.pending_contract_comma) return;
        self.builder.contracts.items[self.pending_contract_index].trailing_comma = self.cursor.current();
        _ = self.cursor.eat(.comma);
    }

    fn parseContracts(self: *Parser) !node.ContractRange {
        var pending_comma: TokenId = .none;
        var contracts: std.ArrayList(node.Contract) = .empty;
        defer contracts.deinit(self.gpa);
        if (self.cursor.at(.keyword_where) and switch (self.cursor.peekAt(1)) {
            .keyword_borrows, .keyword_carries, .keyword_retains => true,
            else => false,
        }) {
            _ = self.cursor.advance();
            while (self.atContract()) {
                try self.parseContract(&contracts);
                if (!self.cursor.at(.comma)) break;
                const next_is_contract = switch (self.cursor.peekAt(1)) {
                    .keyword_borrows, .keyword_carries, .keyword_retains => true,
                    else => false,
                };
                if (!next_is_contract) {
                    if (self.commaEndsContracts()) {
                        if (contracts.items.len > 0) contracts.items[contracts.items.len - 1].trailing_comma = self.cursor.current();
                        _ = self.cursor.advance();
                    } else {
                        pending_comma = self.cursor.current();
                    }
                    break;
                }
                _ = self.cursor.advance();
            }
        }
        const start: u32 = @intCast(self.builder.contracts.items.len);
        try self.builder.contracts.appendSlice(self.gpa, contracts.items);
        if (pending_comma != .none and contracts.items.len > 0) {
            self.pending_contract_comma = pending_comma;
            self.pending_contract_index = self.builder.contracts.items.len - 1;
        }
        return .{ .start = start, .end = @intCast(self.builder.contracts.items.len) };
    }

    const FunctionWhere = struct {
        at: TokenId = .none,
        contracts: node.ContractRange = .{},
        predicates: node.WherePredicateRange = .empty,
    };

    fn parseFunctionWhere(self: *Parser) !FunctionWhere {
        const at = self.cursor.eat(.keyword_where) orelse return .{};
        var contracts: std.ArrayList(node.Contract) = .empty;
        defer contracts.deinit(self.gpa);
        const predicate_start = self.builder.wherePredicateMark();
        var count: usize = 0;
        while (!self.cursor.atEnd() and !self.cursor.at(.l_brace) and !self.cursor.at(.r_brace)) {
            if (self.atContract()) {
                try self.parseContract(&contracts);
            } else {
                try self.parseWherePredicate();
            }
            count += 1;
            if (self.cursor.eat(.comma) == null) break;
            if (self.cursor.precededByNewline() and self.atDeclaration()) break;
        }
        if (count == 0) try self.reportAt(.s_type, self.cursor.current(), "expected a where item", "a `where` clause contains a contract or type predicate");
        const contract_start: u32 = @intCast(self.builder.contracts.items.len);
        try self.builder.contracts.appendSlice(self.gpa, contracts.items);
        return .{
            .at = at,
            .contracts = .{ .start = contract_start, .end = @intCast(self.builder.contracts.items.len) },
            .predicates = .{ .start = predicate_start, .end = self.builder.wherePredicateMark() },
        };
    }

    fn parseWherePredicate(self: *Parser) !void {
        const subject = try self.parseWrittenType();
        if (!self.cursor.at(.colon)) {
            try self.reportAt(.s_type, self.cursor.current(), "expected `:`", "a where predicate bounds its subject");
        }
        const bounds = try self.parseBounds();
        try self.builder.addWherePredicate(.{ .subject = subject, .bounds = bounds });
    }

    /// The comma-delimited predicates after a declaration head.
    fn parseWherePredicates(self: *Parser) !node.WherePredicateRange {
        const start = self.builder.wherePredicateMark();
        while (!self.cursor.atEnd() and !self.cursor.at(.l_brace) and !self.cursor.at(.r_brace)) {
            try self.parseWherePredicate();
            if (self.cursor.eat(.comma) == null) break;
            if (self.atDelegation() and self.cursor.peekAt(1) == .identifier) break;
            if (self.cursor.precededByNewline() and self.atDeclaration()) break;
        }
        const end = self.builder.wherePredicateMark();
        if (end == start) {
            try self.reportAt(
                .s_type,
                self.cursor.current(),
                "expected a type",
                "a `where` clause contains at least one predicate",
            );
        }
        return .{ .start = start, .end = end };
    }

    /// Where a declaration with no body ends: at a newline, at the brace that
    /// closes what holds it, or at the `;` that separates two sharing a line.
    ///
    /// One routine for every such declaration, because there is one rule.
    /// A member form added to the language reads its own end by calling this,
    /// rather than growing a second answer that agrees with this one until it
    /// does not -- which is how a form came to end wherever it liked while `;`
    /// after it was refused.
    fn endBodilessDecl(self: *Parser, ends: []const u8) !void {
        if (self.cursor.eat(.semicolon) != null) return;
        if (!self.cursor.precededByNewline() and !self.cursor.atEnd() and !self.cursor.at(.r_brace)) {
            try self.reportAt(
                .s_separator,
                self.cursor.current(),
                "expected `;` or a newline",
                ends,
            );
        }
        try self.noteContinuation();
    }

    /// The token the cursor has just moved past, which is the last one of
    /// whatever was read immediately before.
    fn justPassed(self: *const Parser) TokenId {
        if (self.cursor.index == 0) return .none;
        return TokenId.at(self.cursor.index - 1);
    }

    /// `[u8, Handle[T]]`, after a written type.
    ///
    /// Recursive, because an argument is a written type in its own right.
    /// Returns an empty range where no bracket follows, which is every
    /// annotation that names a type taking no arguments.
    ///
    /// A written type is read by the same recursion an expression is, and
    /// spends a stack frame the same way, so it is bounded by the same number
    /// rather than by a second one that has to be remembered.
    /// A written type, in whichever form it was written.
    ///
    /// **Every written type in the language enters the compiler here.** This is
    /// the grammar of types rather than a helper beside it, so a form added to
    /// the language is added here and nowhere else.
    ///
    /// One reader, because there is one grammar. Each site used to eat a name
    /// and then ask for arguments, which is the same three lines a dozen times
    /// -- and a form with no name at all could not have been added to twelve
    /// places without one of them being missed.
    fn parseWrittenType(self: *Parser) std.mem.Allocator.Error!node.TypeRef {
        const may_split = self.result_may_split;
        self.result_may_split = false;
        const outer_deepest = self.deepest;
        const root_type = self.written_type_depth == 0;
        self.written_type_depth += 1;
        defer self.written_type_depth -= 1;
        var measure = Measure.begin(self);
        defer {
            measure.operand();
            measure.finish();
            if (root_type) self.deepest = outer_deepest;
        }
        if (self.cursor.at(.keyword_borrow)) {
            const at = self.cursor.current();
            if (self.depth == max_nesting) {
                try self.refuseToDescend(at, "this borrow type nests too deeply");
                return .{ .at = at, .name = .none };
            }
            self.depth += 1;
            if (self.written_type_depth != 0) self.deepest = @max(self.deepest, self.depth);
            defer self.depth -= 1;
            _ = self.cursor.advance();
            const referent = try self.parseWrittenType();
            const start = self.builder.typeRefMark();
            try self.builder.addTypeRef(referent);
            return .{ .kind = .borrow, .at = at, .name = .none, .args = .{ .start = start, .end = start + 1 } };
        }
        var base = if (self.cursor.at(.l_bracket))
            try self.parseArrayType()
        else if (self.cursor.at(.l_paren))
            try self.parseUnitType()
        else if (self.startsCallableType())
            try self.parseCallableType()
        else
            try self.parseNamedType();
        measure.operand();
        var reported_split = false;
        while (self.cursor.at(.dot)) {
            if (self.pathEndsAtALineBreak()) {
                if (!may_split or self.cursor.peekAt(1) != .identifier) break;
                if (!reported_split) {
                    reported_split = true;
                    try self.reportAt(
                        .s_separator,
                        self.cursor.current(),
                        "a line break ends a result type",
                        "move this selection to the end of the line above",
                    );
                }
            }
            const dot = self.cursor.advance();
            const selected = self.cursor.current();
            if (!measure.wrap()) {
                try self.refuseToDescend(selected, "this selected type nests too deeply");
                return .{ .at = base.at, .name = .none };
            }
            const name = self.cursor.eat(.identifier) orelse blk: {
                try self.reportAt(.s_type, selected, "expected a name", "a selected type names a member after the dot");
                break :blk TokenId.none;
            };
            const arguments = if (name != .none) try self.parseTypeArgs() else node.TypeRefRange.empty;
            measure.operand();
            const base_id = node.TypeRefId.at(self.builder.typeRefMark());
            try self.builder.addTypeRef(base);
            base = .{ .kind = .selection, .at = base.at, .name = name, .base = base_id, .dot = dot, .args = arguments };
            if (name == .none) break;
        }
        // Only the author knows whether the line below was meant as part of
        // the type, so the type the declaration was read with is none at all:
        // either reading checked on would refuse what follows a second time,
        // for a mistake already reported here.
        if (reported_split) return .{ .at = base.at, .name = .none };
        return base;
    }

    fn parseNamedType(self: *Parser) std.mem.Allocator.Error!node.TypeRef {
        const head = self.cursor.current();
        if (!self.cursor.at(.identifier)) {
            const introduces: []const u8 = if (self.cursor.previousTag() == .equal)
                "an `=` settles a declared type"
            else
                "a `:` introduces a type";
            try self.reportAt(.s_type, head, "expected a type", introduces);
            return .{ .at = head, .name = .none };
        }
        _ = self.cursor.advance();
        return .{ .at = head, .name = head, .args = try self.parseTypeArgs() };
    }

    fn startsCallableType(self: *const Parser) bool {
        return self.cursor.at(.keyword_fn) or
            ((self.cursor.at(.keyword_read) or self.cursor.at(.keyword_inout) or self.cursor.at(.keyword_sink)) and self.cursor.peekAt(1) == .keyword_fn);
    }

    fn parseCallableType(self: *Parser) std.mem.Allocator.Error!node.TypeRef {
        const at = self.cursor.current();
        if (self.depth == max_nesting) {
            try self.refuseToDescend(at, "this callable type nests too deeply");
            return .{ .at = at, .name = .none };
        }
        self.depth += 1;
        if (self.written_type_depth != 0) self.deepest = @max(self.deepest, self.depth);
        defer self.depth -= 1;

        var invocation_token = TokenId.none;
        const invocation: node.Convention = switch (self.cursor.peek()) {
            .keyword_read, .keyword_inout, .keyword_sink => blk: {
                invocation_token = self.cursor.advance();
                break :blk switch (self.cursor.tags[invocation_token.index()]) {
                    .keyword_inout => .inout,
                    .keyword_sink => .sink,
                    else => .read,
                };
            },
            else => .read,
        };
        _ = self.cursor.advance();
        const params = try self.parseParams();
        // No `->` is a callable type returning `()`, as it is for a function.
        var result: node.TypeRef = .{ .name = .none };
        if (self.cursor.eat(.arrow)) |arrow| {
            if (!try self.refuseWrittenUnit(arrow, omitted_unit_label, remove_written_unit, null)) result = try self.parseWrittenType();
        }
        const contracts = try self.parseContracts();
        const callable = try self.builder.addCallableType(.{ .at = at, .invocation = invocation, .invocation_token = invocation_token, .params = params, .result = result, .contracts = contracts });
        return .{ .kind = .callable, .at = at, .name = .none, .callable = callable };
    }

    /// `()`, the type of a value with nothing in it.
    ///
    /// Recorded as the `(` that opens it rather than as a name, because there
    /// is no name: it is punctuation, no module declares it, and the checker
    /// reads the token's tag rather than looking anything up.
    ///
    /// Read here rather than at the one place that used to need it. A return
    /// type was that place, on the reasoning that a parameter or a binding of
    /// this type would carry no value -- true, and it stopped covering the
    /// case the moment a type argument could be one. `Result[(), IoError]` is
    /// what a call answers when it can fail and has nothing to report on
    /// success, and there is no other way to spell it.
    fn parseUnitType(self: *Parser) std.mem.Allocator.Error!node.TypeRef {
        const open = self.cursor.current();
        _ = self.cursor.advance();
        if (self.cursor.eat(.r_paren) != null) return .{ .at = open, .name = open };
        if (self.depth == max_nesting) {
            // The skip stops before the `)` this `(` opened, which closes the
            // refused type rather than whatever encloses it.
            try self.refuseToDescend(open, "this grouped type nests too deeply");
            _ = self.cursor.eat(.r_paren);
            return .{ .at = open, .name = .none };
        }
        self.depth += 1;
        if (self.written_type_depth != 0) self.deepest = @max(self.deepest, self.depth);
        defer self.depth -= 1;
        const inner = try self.parseWrittenType();
        // A comma after the inner type makes a tuple type, unless it is the
        // trailing comma of a callable type's contracts and closes the group.
        if (self.cursor.at(.comma) and !self.closesContracts()) return self.parseTupleType(open, inner);
        self.consumePendingContractComma();
        const close = self.cursor.eat(.r_paren) orelse blk: {
            try self.reportAt(.s_paren, self.cursor.current(), "expected `)`", "a grouped type ends here");
            break :blk self.justPassed();
        };
        const start = self.builder.typeRefMark();
        try self.builder.addTypeRef(inner);
        return .{ .kind = .grouped, .at = open, .name = close, .args = .{ .start = start, .end = start + 1 } };
    }

    /// Whether the current comma is a callable type's trailing contract comma
    /// with the `)` of an enclosing group or tuple type right after it.
    fn closesContracts(self: *const Parser) bool {
        return self.cursor.current() == self.pending_contract_comma and self.cursor.peekAt(1) == .r_paren;
    }

    /// The rest of `(A, B, …)`, from the comma after its first component.
    /// Already one level below the `(`, which `parseUnitType` counted.
    fn parseTupleType(self: *Parser, open: TokenId, first: node.TypeRef) std.mem.Allocator.Error!node.TypeRef {
        // Components are read before the range is claimed, because a nested
        // type appends to the same table and would otherwise land inside this
        // run.
        var components: std.ArrayList(node.TypeRef) = .empty;
        defer components.deinit(self.gpa);
        try components.append(self.gpa, first);

        while (self.cursor.eat(.comma) != null) {
            if (self.cursor.at(.r_paren) or self.cursor.atEnd()) break;
            try components.append(self.gpa, try self.parseWrittenType());
            if (self.closesContracts()) self.consumePendingContractComma();
        }

        if (self.cursor.eat(.r_paren) != null) {
            try self.checkTupleArity(open, components.items.len, one_component_help);
        } else if (!try self.skipPastMissingComma(open, "a tuple type separates its components with commas")) {
            try self.reportAt(.s_paren, self.cursor.current(), "expected `)`", "a tuple type ends here");
        }

        const start: u32 = @intCast(self.builder.typeRefMark());
        for (components.items) |component| try self.builder.addTypeRef(component);
        const end: u32 = @intCast(self.builder.typeRefMark());
        return .{ .kind = .tuple, .at = open, .name = .none, .args = .{ .start = start, .end = end } };
    }

    test "a tuple type is read after its first comma, and a malformed one is one report" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();

        // A callable type's trailing contract comma before `)` closes a group.
        try testing.expectEqualSlices(?Code, &.{}, try codesOf(gpa, "fn f(_p: (UInt8, (Bool, Str),), _g: (fn() -> UInt8 where\n    carries(),\n)) -> UInt8 { 0 }\n"));

        const refused = [_][]const u8{ "(UInt8,)", "(A, A, A, A, A, A, A, A, A)", "(UInt8, Bool Str)" };
        for (refused) |written| {
            const text = try std.fmt.allocPrint(gpa, "fn f(_p: {s}) -> UInt8 {{ 0 }}\n", .{written});
            try testing.expectEqualSlices(?Code, &.{.s_tuple}, try codesOf(gpa, text));
        }

        // An unclosed tuple or grouped type is a parenthesis never closed.
        for ([_][]const u8{ "(UInt8, UInt8", "(UInt8" }) |written| {
            const text = try std.fmt.allocPrint(gpa, "fn f() -> UInt8 {{\n    let _p: {s} = 1\n    0\n}}\n", .{written});
            try testing.expectEqualSlices(?Code, &.{.s_paren}, try codesOf(gpa, text));
        }
    }

    /// `[T; N]`. The element is one entry in the range a named type's arguments
    /// use, so nothing nests differently than it already did.
    fn parseArrayType(self: *Parser) std.mem.Allocator.Error!node.TypeRef {
        const open = self.cursor.current();
        if (self.depth == max_nesting) {
            try self.refuseToDescend(open, "this type nests too deeply");
            return .{ .at = open, .name = .none };
        }
        self.depth += 1;
        if (self.written_type_depth != 0) self.deepest = @max(self.deepest, self.depth);
        defer self.depth -= 1;

        _ = self.cursor.advance();

        // The element is read before the range is claimed, for the reason an
        // argument is: it appends to the same table and would otherwise land
        // inside its own parent's run.
        const element = try self.parseWrittenType();
        const start: u32 = @intCast(self.builder.typeRefMark());
        try self.builder.addTypeRef(element);
        const args: node.TypeRefRange = .{ .start = start, .end = start + 1 };

        if (self.cursor.eat(.semicolon) == null) {
            try self.reportAt(
                .s_bracket,
                self.cursor.current(),
                "expected `;`",
                "an array type is written `[T; N]`",
            );
            return .{ .kind = .array, .at = open, .name = .none, .args = args };
        }

        const inferred_length: TokenId = if (self.cursor.at(.identifier) and
            std.mem.eql(u8, self.cursor.textOf(self.cursor.current()), "_"))
            self.cursor.advance()
        else
            .none;
        const length = if (inferred_length == .none) try self.parseFull() else ExprId.none;

        if (self.cursor.eat(.r_bracket) == null) {
            try self.reportAt(
                .s_bracket,
                self.cursor.current(),
                "expected `]`",
                "an array type is written `[T; N]`",
            );
        }

        return .{ .kind = .array, .at = open, .name = .none, .args = args, .length = length, .inferred_length = inferred_length };
    }

    fn parseTypeArgs(self: *Parser) std.mem.Allocator.Error!node.TypeRefRange {
        if (!self.cursor.at(.l_bracket)) return node.TypeRefRange.empty;
        if (self.depth == max_nesting) {
            try self.refuseToDescend(self.cursor.current(), "this type nests too deeply");
            return node.TypeRefRange.empty;
        }
        // Type measurements are isolated from enclosing expression heights.
        self.depth += 1;
        if (self.written_type_depth != 0) self.deepest = @max(self.deepest, self.depth);
        defer self.depth -= 1;

        const open = self.cursor.advance();

        // Children are read before the range is claimed, because a nested
        // argument appends to the same table and would otherwise land inside
        // its parent's run.
        var written: std.ArrayList(node.TypeRef) = .empty;
        defer written.deinit(self.gpa);

        while (!self.cursor.atEnd() and !self.cursor.at(.r_bracket)) {
            const name = self.cursor.current();
            if (!self.cursor.at(.identifier) and !self.cursor.at(.l_bracket) and
                !self.cursor.at(.l_paren) and !self.startsCallableType() and !self.cursor.at(.keyword_borrow))
            {
                try self.reportAt(.s_type, name, "expected a type", "an argument is a type");
                // The argument stands as a missing type, so later passes see
                // the list's length without reporting the same argument again.
                // What remains of a balanced list is part of this mistake.
                try written.append(self.gpa, .{ .at = name, .name = .none });
                if (self.delimiterEnd(open)) |close| self.cursor.seek(@intCast(close.index()));
                break;
            }
            // Through the one reader, so an argument is whatever a type is.
            // Reading a head and its own arguments here was a second grammar
            // of types, and it did not know the form that has no head.
            try written.append(self.gpa, try self.parseWrittenType());
            if (self.cursor.eat(.comma) == null) break;
        }

        if (self.cursor.eat(.r_bracket) == null) {
            try self.reportAt(.s_type, self.cursor.current(), "expected `]`", "an argument list is closed");
        }

        const start = self.builder.typeRefMark();
        for (written.items) |r| try self.builder.addTypeRef(r);
        return .{ .start = start, .end = self.builder.typeRefMark() };
    }

    /// `[T]`, `[T: Copyable + Weigh]`, or `[A: Allocator = SystemAllocator]`,
    /// after a declaration's name.
    ///
    /// Each bound is recorded as a name and the arguments written after it.
    /// Whether the name is a universe or a trait is a question about names, and
    /// the parser answers none of those -- the resolver classifies the list,
    /// exactly as it decides whether a selection is a field or a variant.
    ///
    /// A default is a type written after the bounds. It is recorded only where
    /// `defaults` admits one, trails every parameter without one and names no
    /// parameter of this list, and each way of breaking that is [T-ArgumentDefault]
    /// reported here: the rule is about the list, and the list is read once.
    fn parseTypeParams(self: *Parser, defaults: DefaultsAdmitted) !node.TypeParamRange {
        const start = self.builder.typeParamMark();
        if (!self.cursor.at(.l_bracket)) return .{ .start = start, .end = start };
        _ = self.cursor.advance();

        var defaulted: ?TokenId = null;
        while (!self.cursor.atEnd() and !self.cursor.at(.r_bracket)) {
            // Before the name, the way every modifier in the language sits
            // before what it modifies. Whether it may be said here at all is
            // the resolver's question, which knows what the parameter names.
            const phantom = self.cursor.eat(.keyword_phantom) != null;
            const at = self.cursor.current();
            const name = try self.expectName(.s_name, "expected a name", "a type parameter is a name");
            if (name == .none) break;
            // A keyword taken in a name's place declares no parameter, so
            // nothing reports it unused or asks what it stands for.
            if (self.cursor.tags[at.index()] != .identifier) {
                _ = try self.parseBounds();
                if (self.cursor.eat(.comma) == null) break;
                continue;
            }

            const bounds = try self.parseBounds();
            var default: node.TypeRef = .{ .name = .none };
            if (self.cursor.at(.equal)) {
                const equal = self.cursor.advance();
                const written = try self.parseWrittenType();
                if (defaults == .refused) {
                    try self.reportAt(
                        .t_argument_default,
                        equal,
                        "only a struct, an enum or an alias gives a type parameter a default",
                        "this declaration's type arguments are written or settled by a call",
                    );
                } else {
                    default = written;
                    if (defaulted == null) defaulted = name;
                }
            } else if (defaulted != null) {
                try self.reportAt(
                    .t_argument_default,
                    name,
                    "a type parameter without a default cannot follow one that has a default",
                    "give it a default, or declare it before the defaulted parameters",
                );
            }

            try self.builder.addTypeParam(.{
                .name = name,
                .bounds = bounds,
                .phantom = phantom,
                .default = default,
            });

            if (self.cursor.eat(.comma) == null) break;
        }

        if (self.cursor.eat(.r_bracket) == null) {
            try self.reportAt(.s_params, self.cursor.current(), "expected `]`", "a type parameter list is closed");
        }

        try self.refuseDefaultsNamingAParameter(.{ .start = start, .end = self.builder.typeParamMark() });
        return .{ .start = start, .end = self.builder.typeParamMark() };
    }

    /// Whether a declaration's type parameter list may give a parameter a
    /// default type argument.
    const DefaultsAdmitted = enum { admitted, refused };

    /// [T-ArgumentDefault] for a default that names a parameter of its own
    /// list: a default is a type read where the declaration is, so it fills an
    /// omission the same way whatever the other arguments are.
    ///
    /// **Bound:** the list's parameters once per default written in it.
    fn refuseDefaultsNamingAParameter(self: *Parser, range: node.TypeParamRange) !void {
        const declared = self.builder.typeParams(range);
        for (declared) |parameter| {
            if (!parameter.default.wasWritten()) continue;
            for (declared) |other| {
                if (self.typeNames(parameter.default, self.cursor.textOf(other.name)) == 0) continue;
                try self.reportAt(
                    .t_argument_default,
                    parameter.default.at,
                    "a default is a type that names no type parameter",
                    "this names a parameter of the same list",
                );
                break;
            }
        }
    }

    /// `: A + B` after a name, and the empty range where no `:` follows.
    ///
    /// One reader for every position a bound is written in -- a type parameter
    /// and a trait's declared type -- because a bound is one form. Two readers
    /// would be two grammars for it, and the second position would inherit
    /// nothing a later one gains.
    ///
    /// **Bound:** the names written after the `:`.
    fn parseBounds(self: *Parser) !node.BoundRange {
        const start = self.builder.boundMark();
        if (self.cursor.eat(.colon) == null) return .{ .start = start, .end = start };

        return self.parseBoundList(start);
    }

    fn parseBoundList(self: *Parser, start: u32) !node.BoundRange {
        while (!self.cursor.atEnd()) {
            const bound = self.cursor.current();
            if (self.atTemplateRequirementBoundary()) {
                try self.reportAt(.s_name, bound, "expected a name", "a bound names a universe or a trait");
                break;
            }
            if (self.startsCallableType()) {
                const callable = try self.parseCallableType();
                try self.builder.addBound(.{ .kind = .callable, .callable = callable.callable });
            } else if (self.cursor.at(.identifier)) {
                try self.builder.addBound(.{ .named = try self.parseTraitRef("expected a name", "a bound names a universe or a trait") });
            } else {
                try self.reportAt(.s_name, bound, "expected a name", "a bound names a universe or a trait");
                break;
            }
            if (self.cursor.eat(.plus) == null) break;
        }
        return .{ .start = start, .end = self.builder.boundMark() };
    }

    fn atTemplateRequirementBoundary(self: *const Parser) bool {
        if (!self.atDeclaration()) return false;
        return !self.cursor.at(.keyword_fn) or self.cursor.peekAt(1) != .l_paren;
    }

    /// Template-only requirements written after `where`.
    fn parseTemplateRequirements(self: *Parser) !node.TemplateRequirementRange {
        const start = self.builder.templateRequirementMark();

        while (!self.cursor.atEnd() and !self.cursor.at(.l_brace) and
            !self.cursor.at(.r_brace) and !self.atTemplateRequirementBoundary())
        {
            const reflect = self.cursor.current();
            if (self.cursor.eat(.keyword_reflect) == null) {
                try self.reportAt(.s_name, reflect, "expected `reflect.components`", "a template requirement applies a bound to every reflected component");
                break;
            }
            if (self.cursor.eat(.dot) == null) {
                try self.reportAt(.s_entry, self.cursor.current(), "expected `.` after `reflect`", "a template requirement names `reflect.components`");
            }

            const selector = self.cursor.current();
            const selector_text = self.cursor.textOf(selector);
            const kind: node.TemplateRequirement.Kind = if (self.cursor.eat(.identifier) == null)
                .components
            else if (std.mem.eql(u8, selector_text, "components"))
                .components
            else if (std.mem.eql(u8, selector_text, "supertraits"))
                .derived_supertraits
            else if (std.mem.eql(u8, selector_text, "target"))
                .target
            else blk: {
                try self.reportAt(.s_name, selector, "expected `components`, `supertraits`, or `target`", "a template requirement names structural evidence");
                break :blk .components;
            };

            var bounds = node.BoundRange.empty;
            var target_shape: node.TemplateRequirement.TargetShape = .struct_;
            if (self.cursor.eat(.colon) != null) switch (kind) {
                .components => {
                    const bound_start = self.builder.boundMark();
                    if (self.atTemplateRequirementBoundary()) {
                        try self.reportAt(.s_name, self.cursor.current(), "expected a name", "a bound names a universe or a trait");
                    } else {
                        bounds = try self.parseBoundList(bound_start);
                    }
                },
                .target => {
                    const shape = self.cursor.current();
                    if (self.cursor.eat(.keyword_struct) != null) {
                        target_shape = .struct_;
                    } else if (self.cursor.eat(.keyword_enum) != null) {
                        target_shape = .enum_;
                    } else if (self.cursor.at(.identifier) and std.mem.eql(u8, self.cursor.textOf(shape), token.contextual_words.declared_type)) {
                        _ = self.cursor.advance();
                        target_shape = .newtype;
                    } else {
                        try self.reportAt(.s_name, shape, "expected `struct`, `enum`, or `type`", "a target requirement names a declaration kind");
                    }
                },
                .derived_supertraits => {
                    const derived = self.cursor.current();
                    if (self.cursor.eat(.identifier) == null or
                        !std.mem.eql(u8, self.cursor.textOf(derived), "derived"))
                    {
                        try self.reportAt(.s_name, derived, "expected `derived`", "a structural-supertrait requirement asks for derived evidence");
                    }
                },
            } else {
                try self.reportAt(.s_entry, self.cursor.current(), "expected `:`", "a template requirement names the structural evidence it needs");
                while (!self.cursor.atEnd() and !self.cursor.at(.comma) and
                    !self.cursor.at(.l_brace) and !self.cursor.at(.r_brace) and
                    !self.atTemplateRequirementBoundary())
                {
                    _ = self.cursor.advance();
                }
            }
            try self.builder.addTemplateRequirement(.{
                .kind = kind,
                .reflect = reflect,
                .selector = selector,
                .bounds = bounds,
                .target_shape = target_shape,
            });

            if (self.cursor.eat(.comma) == null) break;
        }

        return .{ .start = start, .end = self.builder.templateRequirementMark() };
    }

    /// A parameter list. Every parameter is annotated, and a trailing `read`
    /// parameter may carry a default -- checked and recorded here rather than
    /// left for a later pass, since both rules are about the shape of this
    /// list and nothing past it needs to see a violation to react to it.
    const ParamDelimiter = enum { parens, pipes };
    const ParamTypes = enum { required, optional };

    fn parseParams(self: *Parser) !node.ParamRange {
        return self.parseParameterRun(.parens, .required);
    }

    fn parseParameterRun(self: *Parser, delimiter: ParamDelimiter, annotations: ParamTypes) !node.ParamRange {
        const open: Tag = if (delimiter == .parens) .l_paren else .pipe;
        const close: Tag = if (delimiter == .parens) .r_paren else .pipe;
        if (self.cursor.eat(open) == null) {
            try self.reportAt(
                if (delimiter == .pipes) .s_lambda else .s_params,
                self.cursor.current(),
                if (delimiter == .pipes) "expected `|`" else "expected `(`",
                if (delimiter == .pipes) "a lambda declares its parameters between pipes" else "a function declares its parameters",
            );
            const start = self.builder.paramMark();
            return .{ .start = start, .end = start };
        }

        var parsed: std.ArrayList(node.Param) = .empty;
        defer parsed.deinit(self.gpa);

        // The `=` of the most recently defaulted parameter, so a parameter
        // with none can point back at what obligated it: [S-Default]'s suffix
        // rule is about the pair, and the earlier token is the one a reader
        // needs to see to understand why the later parameter is a problem.
        var last_default: ?TokenId = null;

        while (!self.cursor.atEnd() and !self.cursor.at(close)) {
            const before = self.cursor.current();

            const convention: node.Convention = if (self.cursor.eat(.keyword_inout) != null)
                .inout
            else if (self.cursor.eat(.keyword_sink) != null)
                .sink
            else blk: {
                _ = self.cursor.eat(.keyword_read);
                break :blk .read;
            };

            const pname_at = self.cursor.current();
            var pattern = ExprId.none;
            var argument = ExprId.none;
            var pname = TokenId.none;
            var recovered = false;
            if (self.cursor.at(.l_paren)) {
                if (delimiter == .pipes) {
                    pattern = try self.parseTuplePattern();
                    argument = try self.builder.addLiteral(.param_argument, pname_at, self.rangeFrom(pname_at));
                } else {
                    // A declaration parameter's name is the label a call
                    // writes, so a pattern has none. Skip the pattern and
                    // read the `:` and the type after it as usual.
                    try self.reportAt(
                        .s_params,
                        pname_at,
                        "a parameter is a name",
                        "a declaration parameter's name is the label a call writes; take the pair apart in the body",
                    );
                    if (self.delimiterEnd(pname_at)) |end| self.cursor.seek(@intCast(end.index() + 1));
                    recovered = true;
                }
            } else {
                pname = try self.expectName(.s_params, "expected a parameter name", "a parameter is a name and a type");
            }

            var written: node.TypeRef = .{ .name = .none };
            if (self.cursor.eat(.colon) != null) {
                written = try self.parseWrittenType();
            } else if (annotations == .required) {
                try self.reportAt(.s_params, self.cursor.current(), "expected `:`", "a parameter is always annotated");
                recovered = true;
            }

            var default: ExprId = ExprId.none;
            const eq = self.cursor.current();
            if (self.cursor.eat(.equal) != null) {
                default = try self.parseFull();
                if (convention == .inout) {
                    try self.reportAt(
                        .s_default,
                        eq,
                        "only a `read` or `sink` parameter may carry a default",
                        "this parameter is `inout`",
                    );
                }
                last_default = eq;
            } else if (last_default) |at| {
                try self.reportAt(
                    .s_default,
                    at,
                    "defaulted parameters form a suffix",
                    "a parameter after this one has no default",
                );
                // Cleared rather than left set: the gap between the default
                // and this parameter has been reported once, and every
                // undefaulted parameter after this one is the same gap, not
                // a new one.
                last_default = null;
            }

            try parsed.append(self.gpa, .{
                .name = if (pname != .none) pname else pname_at,
                .pattern = pattern,
                .argument = argument,
                .written = written,
                .convention = convention,
                .default = default,
                .recovered = recovered,
            });
            if (self.cursor.eat(.comma) == null) break;

            // Recovery that consumes nothing would loop forever, the same way
            // a statement sequence would.
            if (self.cursor.current() == before) _ = self.cursor.advance();
        }

        if (self.cursor.eat(close) == null) {
            try self.reportAt(
                if (delimiter == .pipes) .s_lambda else .s_params,
                self.cursor.current(),
                if (delimiter == .pipes) "expected `|`" else "expected `)`",
                if (delimiter == .pipes) "this lambda parameter list is never closed" else "this parameter list is never closed",
            );
        }
        const start = self.builder.paramMark();
        for (parsed.items) |param| try self.builder.addParam(param);
        return .{ .start = start, .end = self.builder.paramMark() };
    }

    test parseParameterRun {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        const source: Source = .{ .path = "t.lin", .text = "fn main() -> UInt8 { |sink (i, x), n: UInt8| i }\n" ++
            "fn plain() -> UInt8 { |(a, b)| a }" };
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        const ast = try parse(gpa, &source, .from(0), tokens, &sink);
        try testing.expectEqual(@as(u32, 0), sink.error_count);

        const piped = ast.lambda(ast.blockOf(ast.declBody(node.DeclId.at(0))).tail);
        try testing.expectEqual(@as(usize, 2), piped.params.len);
        try testing.expect(piped.params[0].pattern != ExprId.none);
        try testing.expectEqual(Expr.Tag.tuple_pattern, ast.exprTag(piped.params[0].pattern));
        try testing.expectEqual(@as(usize, 2), ast.call(piped.params[0].pattern).args.len);
        try testing.expectEqual(Tag.l_paren, ast.tokenTag(piped.params[0].name));
        try testing.expectEqual(node.Convention.sink, piped.params[0].convention);
        try testing.expectEqual(Expr.Tag.param_argument, ast.exprTag(piped.params[0].argument));
        try testing.expectEqual(ExprId.none, piped.params[1].pattern);
        try testing.expectEqual(ExprId.none, piped.params[1].argument);
        try testing.expect(piped.params[1].name != TokenId.none);

        const defaulted = ast.lambda(ast.blockOf(ast.declBody(node.DeclId.at(1))).tail);
        try testing.expectEqual(node.Convention.read, defaulted.params[0].convention);
        try testing.expect(defaulted.params[0].pattern != ExprId.none);
    }

    test "a walk over every expression meets a pattern parameter's argument once, and every name reference has an identifier" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        const source: Source = .{ .path = "t.lin", .text = "fn main() -> UInt8 { |sink (i, x), n: UInt8| i + n }" };
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        const ast = try parse(gpa, &source, .from(0), tokens, &sink);
        try testing.expectEqual(@as(u32, 0), sink.error_count);

        const lambda = ast.lambda(ast.blockOf(ast.declBody(node.DeclId.at(0))).tail);
        var arguments: usize = 0;
        for (0..ast.exprCount()) |index| {
            const id = ExprId.at(@intCast(index));
            switch (ast.exprTag(id)) {
                .param_argument => {
                    arguments += 1;
                    try testing.expectEqual(lambda.params[0].argument, id);
                    try testing.expectEqual(Tag.l_paren, ast.tokenTag(ast.exprMain(id)));
                    try testing.expect(ast.refersToBinding(id));
                },
                .name_ref => try testing.expectEqual(Tag.identifier, ast.tokenTag(ast.exprMain(id))),
                else => {},
            }
        }
        try testing.expectEqual(@as(usize, 1), arguments);
    }

    test "a declaration parameter is a name, and the refusal recovers at its colon" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const codes = try codesOf(gpa, "fn f((a, b): (UInt8, UInt8), c: UInt8) -> UInt8 { c }");
        try testing.expectEqual(@as(usize, 1), codes.len);
        try testing.expectEqual(@as(?Code, .s_params), codes[0]);
    }

    fn parseLambda(self: *Parser) std.mem.Allocator.Error!ExprId {
        const start = self.cursor.current();
        var invocation_token = TokenId.none;
        const invocation: node.Convention = switch (self.cursor.peek()) {
            .keyword_read, .keyword_inout, .keyword_sink => blk: {
                invocation_token = self.cursor.advance();
                break :blk switch (self.cursor.tags[invocation_token.index()]) {
                    .keyword_inout => .inout,
                    .keyword_sink => .sink,
                    else => .read,
                };
            },
            else => .read,
        };
        var captures: std.ArrayList(node.Capture) = .empty;
        defer captures.deinit(self.gpa);
        const capture_open = self.cursor.eat(.l_bracket) orelse TokenId.none;
        if (invocation_token != .none and capture_open == .none)
            try self.reportAt(.s_lambda, self.cursor.current(), "expected a capture list after the invocation mode", "write `[]` for an empty capture list");
        var capture_close = TokenId.none;
        if (capture_open != .none) {
            while (!self.cursor.atEnd() and !self.cursor.at(.r_bracket) and !self.cursor.at(.pipe) and !self.cursor.at(.pipe_pipe)) {
                var convention_token = TokenId.none;
                const convention: node.Convention = switch (self.cursor.peek()) {
                    .keyword_read, .keyword_sink, .keyword_inout => blk: {
                        convention_token = self.cursor.advance();
                        break :blk switch (self.cursor.tags[convention_token.index()]) {
                            .keyword_sink => .sink,
                            .keyword_inout => .inout,
                            else => .read,
                        };
                    },
                    else => .read,
                };
                const name = try self.expectName(.s_lambda, "expected a capture name", "a capture declares an alias for its source");
                if (name == .none) break;
                const equals = self.cursor.eat(.equal) orelse TokenId.none;
                const source = if (equals != .none) try self.parseFull() else try self.builder.addLiteral(.name_ref, name, self.rangeFrom(name));
                try captures.append(self.gpa, .{ .name = name, .source = source, .convention = convention, .convention_token = convention_token, .equals = equals });
                if (self.cursor.eat(.comma) == null) break;
            }
            capture_close = self.cursor.eat(.r_bracket) orelse TokenId.none;
            if (capture_close == .none) try self.reportAt(.s_lambda, self.cursor.current(), "expected `]`", "this capture list is never closed");
        }
        const open = self.cursor.current();

        var params: node.ParamRange = undefined;
        var close = open;
        if (self.cursor.at(.pipe_pipe)) {
            _ = self.cursor.advance();
            const mark = self.builder.paramMark();
            params = .{ .start = mark, .end = mark };
        } else {
            if (!self.cursor.at(.pipe)) {
                try self.reportAt(.s_lambda, open, "expected `|`", "a lambda opens its parameter list with `|`");
                return self.errExpr(start);
            }
            params = try self.parseParameterRun(.pipes, .optional);
            close = self.cursor.previousToken();
        }

        const result_arrow = self.cursor.eat(.arrow) orelse TokenId.none;
        var result: node.TypeRef = .{ .name = .none };
        var contracts: node.ContractRange = .{};
        if (result_arrow != .none) {
            // Without `where` after it, removing `-> ()` leaves the lambda's
            // result to its body; with one, the `->` stays to introduce it.
            if (!try self.refuseWrittenUnit(result_arrow, omitted_unit_label, remove_written_unit, "remove `()`; the `->` stays before `where`")) switch (self.cursor.peek()) {
                .keyword_where => {},
                else => result = try self.parseWrittenType(),
            };
            contracts = try self.parseContracts();
            // The body has not started, so this comma ends the lambda's
            // contract list rather than an enclosing argument or parameter.
            self.consumePendingContractComma();
        }
        if (self.cursor.atEnd() or self.cursor.at(.semicolon) or self.cursor.at(.r_brace)) {
            try self.reportAt(.s_lambda, self.cursor.current(), "expected a lambda body", "a lambda is followed by an expression or block");
            const body = try self.builder.addLiteral(.err, self.cursor.current(), self.rangeFrom(self.cursor.current()));
            return self.builder.addLambda(open, close, invocation_token, invocation, captures.items, capture_open, capture_close, self.rangeFrom(start), params, contracts, result, result_arrow, body);
        }
        const body = if (self.cursor.at(.l_brace))
            try self.parseBraced("this lambda body is never closed")
        else
            try self.parseFull();
        return self.builder.addLambda(open, close, invocation_token, invocation, captures.items, capture_open, capture_close, self.rangeFrom(start), params, contracts, result, result_arrow, body);
    }

    /// Whether a statement beginning with this token is a construct that ends
    /// in a block, and so ends the statement with it.
    ///
    /// Listed rather than inferred from the parsed expression: the decision is
    /// whether to keep parsing, and by the time there is an expression to
    /// classify the operator has already been consumed.
    fn opensWithABlock(tag: Tag) bool {
        return switch (tag) {
            .keyword_while, .keyword_for, .keyword_loop, .keyword_if, .keyword_match, .l_brace => true,
            else => false,
        };
    }

    /// The statements of a block, from `start` -- the `{` the caller consumed.
    ///
    /// The range begins at the brace and is closed past its partner by
    /// `parseBraced`, so a block's extent is the text a reader would select.
    /// A block whose extent excluded its own braces read as its contents,
    /// which is not a block: a rewrite that moved one dropped them.
    fn parseBody(self: *Parser, start: TokenId, terminator: Tag) !ExprId {
        const seq = try self.parseSequence(start, terminator);
        defer self.gpa.free(seq.stmts);

        const blk = try self.builder.addBlock(seq.stmts, seq.tail);
        return self.builder.addBlockExpr(start, self.rangeFrom(start), blk);
    }

    /// `{ ... }` as an expression: a function's body, an `if` arm, a `match`
    /// arm. One place, so a block's extent cannot differ by where it appears.
    fn parseBraced(self: *Parser, unclosed: []const u8) std.mem.Allocator.Error!ExprId {
        const open = self.cursor.current();
        if (self.cursor.eat(.l_brace) == null) {
            try self.reportAt(.s_brace, open, "expected `{`", unclosed);
            // The missing brace is the mistake, so what stands where the block
            // belongs is skipped without a second report.
            return self.skipMalformed(open);
        }

        const body = try self.parseBody(open, .r_brace);
        if (self.cursor.eat(.r_brace) == null) {
            try self.reportAt(.s_brace, open, "unclosed `{`", unclosed);
        }
        self.builder.endExpr(body, self.cursor.current());
        return body;
    }

    const Sequence = struct { stmts: []StmtId, tail: ExprId };

    /// Statements until `terminator`, then an optional trailing expression.
    /// The one place a statement sequence is parsed, so block and program
    /// recovery cannot drift apart.
    fn parseSequence(self: *Parser, open: TokenId, terminator: Tag) !Sequence {
        var stmts: std.ArrayList(StmtId) = .empty;
        errdefer stmts.deinit(self.gpa);

        var tail: ExprId = .none;

        const holding = self.statement;
        defer self.statement = holding;
        self.statement.open = open;

        while (!self.cursor.atEnd() and !self.cursor.at(terminator)) {
            const start = self.cursor.current();
            const indent = self.cursor.lineIndent(start);
            self.statement = .{
                .start = start,
                .indent = indent orelse self.statement.indent,
                .open = open,
                .begins_line = indent != null,
            };
            if (self.cursor.at(.keyword_let) or self.cursor.at(.keyword_var)) {
                try self.parseLet(&stmts, .none);
                continue;
            }
            if (self.cursor.at(.keyword_defer)) {
                try self.parseDefer(&stmts);
                continue;
            }
            // Anything else is an expression. It is the trailing one where the
            // block ends after it, and a statement otherwise -- which is what
            // lets a conditional be used for its effect and be followed by
            // more.
            const before = self.cursor.current();

            // A construct that ends in a block ends the statement with it.
            // `while c { } -(6)` is a loop and then an expression: reading the
            // `-` as subtraction makes the two one operation, which parses,
            // takes a loop's `()` as an operand, and reports a type error
            // several lines from what caused it. The same reasoning stops a
            // `(` after one being read as a call.
            const e = if (opensWithABlock(self.cursor.peek()))
                try self.parseUnary()
            else
                try self.parseFull();
            const separated = self.cursor.eat(.semicolon) != null;

            if (self.cursor.atEnd() or self.cursor.at(terminator)) {
                tail = e;
                break;
            }
            try self.endStatement(separated, e, "this statement ends here");

            // A recovery that consumes nothing would otherwise repeat forever:
            // the parser never fails, so a token it cannot use has to be
            // stepped over by whoever is looping.
            if (self.cursor.current() == before) {
                _ = self.cursor.advance();
                continue;
            }

            try stmts.append(self.gpa, try self.builder.addExprStmt(e));
        }

        return .{ .stmts = try stmts.toOwnedSlice(self.gpa), .tail = tail };
    }

    /// Whether what has been parsed is complete and a newline follows it.
    ///
    /// This is the whole of the rule that a newline ends a statement. It
    /// looks at the token before the break, and at the line after it only to
    /// ask whether it opens with a `.` and a lowercase name: such a line
    /// selects an operation or a field of the value above, and no statement
    /// begins that way, so it continues the expression -- `numbers` /
    /// `.filter(p)` / `.fold(0, add)` is one chain. Every other line after a
    /// token that can end an expression begins a statement, and an expression
    /// otherwise written across lines ends each line with the operator that
    /// carries it on.
    fn finishedAtALineBreak(self: *const Parser) bool {
        return self.cursor.precededByNewline() and endsAStatement(self.cursor.previousTag()) and !self.atLeadingSelection();
    }

    /// Whether a line break ends the path of a declaration or a written type
    /// here. A path is not an expression: a declaration's line holds its
    /// whole path, so a line opening with `.` below one never continues it,
    /// whatever case the name after the dot has, and a re-export does not
    /// reach down a line for the name it exports.
    fn pathEndsAtALineBreak(self: *const Parser) bool {
        return self.cursor.precededByNewline() and endsAStatement(self.cursor.previousTag());
    }

    /// Whether the current token opens a line that continues the one above,
    /// by the rule `Tag.continuesTheLine` states for the parser and the
    /// formatter alike.
    fn atLeadingSelection(self: *const Parser) bool {
        const next = self.cursor.ahead(1) orelse return false;
        return self.cursor.peek().continuesTheLine(self.cursor.tags[next.index()], self.cursor.textOf(next));
    }

    /// The tokens an expression can end with, and so the tokens a newline can
    /// follow to end a statement.
    ///
    /// Stated as what *can* end rather than what cannot, which keeps the list
    /// short and makes a token added later default to continuing the line --
    /// the safe direction, since a wrapped expression keeps working and the
    /// mistake is a parse error rather than a silent second statement.
    ///
    /// Every token an expression can end with is here: a name, `reflect`, a
    /// literal of each kind (an interpolated string ends at its closing
    /// quote), a closing `)`, `}` or `]`, a postfix `?`, and a bare jump.
    fn endsAStatement(tag: Tag) bool {
        return switch (tag) {
            .identifier,
            .keyword_reflect,
            .int_literal,
            .float_literal,
            .string_literal,
            .string_line,
            .str_close,
            .keyword_true,
            .keyword_false,
            .r_paren,
            .r_brace,
            .r_bracket,
            .question,
            .keyword_break,
            .keyword_continue,
            .keyword_return,
            => true,
            else => false,
        };
    }

    /// Tokens that may legitimately terminate an expression. An `err` node
    /// ends at the nearest one, which is what makes "recover at the smallest
    /// production whose end can be identified" mechanical rather than a
    /// judgement at each call site.
    fn inExprFollow(tag: Tag) bool {
        return switch (tag) {
            // The text after an interpolated expression ends it as well.
            .semicolon, .r_paren, .r_brace, .pipe, .str_mid, .str_close, .eof => true,
            else => false,
        };
    }

    /// Whether a token can begin a match arm's pattern. One list, because two
    /// gates read it and a copy each is how the lists drift.
    fn startsArmPattern(tag: Tag) bool {
        return switch (tag) {
            .identifier, .keyword_reflect, .int_literal, .string_literal, .minus, .l_paren => true,
            else => false,
        };
    }

    /// Whether an arm's pattern begins here. `(` begins a tuple pattern
    /// except as `()`, which the unit type's single value would make a test
    /// of nothing.
    fn atArmPattern(self: *const Parser) bool {
        if (self.cursor.at(.l_paren) and self.cursor.peekAt(1) == .r_paren) return false;
        return startsArmPattern(self.cursor.peek());
    }

    /// A pattern where a binder may stand: in a variant's or newtype's
    /// payload, in a tuple's component, or after a struct field's `:`.
    ///
    /// The production an arm's head uses, so a pattern reads one way at every
    /// depth, with two differences that follow from the position. A brace
    /// opens an inferred struct pattern, which an arm's head never begins
    /// with. A bare name is a name either way, and what it names is the
    /// checker's question: a lowercase one or `_` binds, a capitalised one is
    /// a variant ([N-Case]).
    ///
    /// A token no pattern begins with is reported where it stands and left for
    /// the enclosing list, whose separator or closer it may be. `()` is the
    /// exception: it is one mistake, so both of its tokens go with the report.
    fn parseSubPattern(self: *Parser) std.mem.Allocator.Error!ExprId {
        const at = self.cursor.current();
        if (self.cursor.at(.l_brace)) return self.parseStructPattern();
        // A keyword written where a binder belongs is a name that cannot be
        // one, which is the mistake to name rather than a missing pattern.
        // The part is an error node, so what checks the pattern takes it for
        // nothing rather than for a binder that matches everything.
        if (self.atKeywordName()) {
            _ = try self.expectName(.s_match, "expected a name", "a pattern binds what its variant carries");
            return self.builder.addLiteral(.err, at, self.rangeFrom(at));
        }
        if (self.cursor.at(.keyword_reflect) or !self.atArmPattern()) {
            try self.reportNoPattern(at);
            if (self.cursor.at(.l_paren) and self.cursor.peekAt(1) == .r_paren) {
                _ = self.cursor.advance();
                _ = self.cursor.advance();
            }
            return self.builder.addLiteral(.err, at, self.rangeFrom(at));
        }
        return self.parseArmPattern();
    }

    /// Where a statement may end, or the next one begin. Including the tokens
    /// that *start* a statement is what stops recovery from swallowing the
    /// statement after the broken one.
    fn atStatementBoundary(self: *const Parser) bool {
        return self.finishedAtALineBreak() or self.atStatementTokenBoundary();
    }

    /// Boundaries that remain meaningful before a production consumes a token.
    fn atStatementTokenBoundary(self: *const Parser) bool {
        return self.cursor.atEnd() or switch (self.cursor.peek()) {
            .semicolon, .keyword_let, .keyword_var, .r_brace, .keyword_fn => true,
            .keyword_break, .keyword_continue, .keyword_return => true,
            else => false,
        };
    }

    /// Takes the name a declaration or a binding introduces, and returns its
    /// token, or `.none` where no name is written.
    ///
    /// A reserved word on the same line is the usual reason a name is missing,
    /// so it is reported as the keyword it is and taken in the name's place:
    /// what follows parses as written instead of being reported again, and
    /// the declaration keeps a token with no name, as one missing its name
    /// does. `message` and `label` describe any other missing name.
    fn expectName(self: *Parser, code: Code, message: []const u8, label: []const u8) !TokenId {
        const at = self.cursor.current();
        if (self.cursor.eat(.identifier) != null) return at;
        if (self.atKeywordName()) {
            _ = self.cursor.advance();
            try self.sink.addError(
                code,
                self.file,
                self.cursor.spanAt(at),
                try std.fmt.allocPrint(self.sink.arena, "`{s}` is a keyword, and a keyword cannot be a name", .{self.cursor.textOf(at)}),
                "choose another name",
            );
            return at;
        }
        try self.reportAt(code, at, message, label);
        return .none;
    }

    /// Whether the current token is a reserved word standing where a name
    /// belongs: on the line that asked for the name, or at the start of a
    /// line and followed by what follows a field's or a variant's name.
    fn atKeywordName(self: *const Parser) bool {
        if (Tag.keywordFromLexeme(self.cursor.textOf(self.cursor.current())) == null) return false;
        if (!self.cursor.precededByNewline()) return true;
        return switch (self.cursor.peekAt(1)) {
            .colon, .comma, .l_paren => true,
            else => false,
        };
    }

    fn reportAt(
        self: *Parser,
        code: Code,
        at: TokenId,
        message: []const u8,
        label: []const u8,
    ) !void {
        // A refinement clause is written on the line its `where` opens, so a
        // token it demands past that line is not a token it is missing: the
        // break ended the declaration, and that is what is said -- once, and
        // at the token the clause did end after, whichever of the clause's
        // positions was the one to run out of line.
        if (self.clause) |*clause| {
            if (at != .none and at.index() >= clause.end) {
                if (clause.reported) return;
                clause.reported = true;
                return self.sink.addError(
                    .s_separator,
                    self.file,
                    self.cursor.spanAt(self.cursor.previousToken()),
                    "a line break ends this refinement clause",
                    "a refinement clause is written on the line `where` opens",
                );
            }
        }
        try self.sink.addError(code, self.file, self.cursor.spanAt(at), message, label);
    }

    /// Where a newline ended a statement and the next line opens with a token
    /// that could have continued it instead.
    ///
    /// `-`, `()` and `.` can: each begins a statement and each also continues
    /// an expression, so the line break is what decides between two readings
    /// that are both programs -- and only the author knows which was meant,
    /// which is why this is a note and not an error. Any other `(` is not
    /// noted: it opens the tail of every function returning a tuple, and a
    /// call split before an argument that is not Unit leaves a value nothing
    /// uses, which `[T-Discard]` refuses (`Tag.opensAContinuation`). A `.`
    /// can only before a name that is not capitalised: `.Ok(0)` and
    /// `.{ x = 1 }` select no operation or field, because those start with a
    /// lowercase letter. A line opening with `.` and a lowercase name
    /// continues an expression (`finishedAtALineBreak`), so it is noted only
    /// where the statement above ended anyway: after a declaration's path,
    /// which a line break always ends, and after an expression ending in a
    /// block, which takes no selection. The second is told to bind the value first, since ending
    /// the line with the `.` would not help.
    ///
    /// `{` is not among them. A named literal keeps its brace on the head's
    /// line, so a brace on the next line can only open a block. Noting it
    /// would fire on every ordinary one, and a note that is usually wrong is
    /// one nobody reads.
    ///
    /// It fires on the shape of the tokens rather than on the type of what
    /// they produce. A Unit value stands as a statement and a block's tail is
    /// its value, so a misread newline before `()`, or before `-` in a tail,
    /// leaves both halves legal, and no discarded value is reported to catch
    /// it.
    fn noteContinuation(self: *Parser) !void {
        if (!self.cursor.precededByNewline()) return;
        const opening = self.cursor.peek();
        const next = self.cursor.ahead(1);
        const next_tag: token.Tag = if (next) |t| self.cursor.tags[t.index()] else .eof;
        const next_text = if (next) |t| self.cursor.textOf(t) else "";
        if (!opening.opensAContinuation(next_tag, next_text)) return;
        if (opening.continuesTheLine(next_tag, next_text) and self.cursor.previousTag() == .r_brace) {
            return self.sink.addNote(
                .s_continuation,
                self.file,
                self.cursor.spanAt(self.cursor.current()),
                "the next line selects from the value above, and an expression ending in a block takes no selection",
                "bind the value with `let`, then select from the binding",
            );
        }
        const message = switch (self.cursor.peek()) {
            .minus => "the next line begins with `-`, which could have continued the expression above",
            .l_paren => "the next line begins with `()`, which could have called the expression above",
            .dot => "the next line begins with `.`, which could have continued the expression above",
            // Reached only if a token joins the set without a message of its
            // own. Saying less is right; saying nothing would drop the note.
            else => "the next line begins with a token that could have continued the expression above",
        };
        try self.sink.addNote(
            .s_continuation,
            self.file,
            self.cursor.spanAt(self.cursor.current()),
            message,
            "end the previous line with it if that was meant",
        );
    }

    /// `S { f: p, ... }`: a struct taken apart.
    ///
    /// The one place a struct pattern's fields are read, so a destructuring
    /// `let` and a `match` arm cannot drift apart about what a field list is.
    /// `{ f }` is shorthand for `{ f: f }`; `{ f: _ }` discards.
    fn parseStructPattern(self: *Parser) std.mem.Allocator.Error!ExprId {
        const start = self.cursor.current();
        const of = if (self.cursor.at(.identifier)) blk: {
            const head = try self.builder.addLiteral(.name_ref, start, self.rangeFrom(start));
            _ = self.cursor.advance();
            break :blk head;
        } else ExprId.none;

        var items: std.ArrayList(ExprId) = .empty;
        defer items.deinit(self.gpa);

        if (self.cursor.eat(.l_brace) == null) {
            try self.reportAt(.s_brace, self.cursor.current(), "expected `{`", "a struct pattern lists its fields");
            return self.errExpr(start);
        }

        while (!self.cursor.atEnd() and !self.cursor.at(.r_brace)) {
            const before = self.cursor.current();

            const field = self.cursor.current();
            if (self.cursor.eat(.identifier) == null) {
                try self.reportAt(.s_field, field, "expected a field name", "a struct pattern names every field");
                if (self.cursor.current() == before) _ = self.cursor.advance();
                continue;
            }
            try items.append(self.gpa, try self.builder.addLiteral(.name_ref, field, self.rangeFrom(field)));

            // `{ f }` binds the field to its own name, which is what a reader
            // writing one out would have written.
            if (self.cursor.eat(.colon) == null) {
                try items.append(self.gpa, try self.builder.addLiteral(.name_ref, field, self.rangeFrom(field)));
            } else {
                try items.append(self.gpa, try self.parseSubPattern());
            }

            if (self.cursor.eat(.comma) == null) break;
            if (self.cursor.current() == before) _ = self.cursor.advance();
        }

        if (self.cursor.eat(.r_brace) == null) {
            try self.reportAt(.s_brace, start, "expected `}`", "this struct pattern is never closed");
        }

        const e = try self.builder.addCall(start, self.rangeFrom(start), of, items.items, &.{});
        self.builder.retag(e, .struct_pattern);
        return e;
    }

    /// `N(n)`, at the head of a destructuring `let`: a newtype's base, read
    /// out under a name. Built the same way a match arm's payload pattern is,
    /// through the routine both share -- `N?(n)` reaches the same refusal
    /// there that it does here.
    fn parseNewtypePattern(self: *Parser) std.mem.Allocator.Error!ExprId {
        const at = self.cursor.current();
        _ = self.cursor.advance();
        const bare = try self.builder.addLiteral(.name_ref, at, self.rangeFrom(at));
        return self.parsePayloadPattern(at, bare);
    }

    /// `(a, b, …)`: a tuple taken apart by position, each component a
    /// pattern. The node is built whatever its arity, as a tuple literal's is.
    fn parseTuplePattern(self: *Parser) std.mem.Allocator.Error!ExprId {
        const open = self.cursor.current();
        _ = self.cursor.advance();

        var binders: std.ArrayList(ExprId) = .empty;
        defer binders.deinit(self.gpa);
        var refused = false;

        while (!self.cursor.atEnd() and !self.cursor.at(.r_paren)) {
            // A keyword part is reported and its token taken, so the
            // components after it parse as written and their binders are
            // declared. A token no pattern begins with is left where it
            // stands, and the list ends there.
            const keyword = self.atKeywordName();
            const component = try self.parseSubPattern();
            try binders.append(self.gpa, component);
            if (!keyword and self.builder.exprTag(component) == .err) {
                refused = true;
                break;
            }
            if (self.cursor.eat(.comma) == null) break;
        }

        // A pattern missing a comma or its `)` may hold more than was read,
        // and a component that is no pattern has already been reported, so
        // none of them has its arity judged. A keyword part is one
        // component, so a pattern holding one is judged.
        if (self.cursor.eat(.r_paren) != null) {
            if (!refused) try self.checkTupleArity(open, binders.items.len, switch (binders.items.len) {
                0 => "`()` has nothing to take apart",
                1 => "bind one value with `let a = …`",
                else => too_many_help,
            });
        } else if (refused and self.delimiterEnd(open) != null) {
            // What stopped the refused binder's skip is part of that one
            // mistake, so the pattern closes where it was written.
            self.cursor.seek(@intCast(self.delimiterEnd(open).?.index() + 1));
        } else if (refused or !try self.skipPastMissingComma(open, "a tuple pattern separates its binders with commas")) {
            try self.reportAt(.s_paren, open, "unclosed `(`", "this tuple pattern is never closed");
        }

        const id = try self.builder.addCall(open, self.rangeFrom(open), .none, binders.items, &.{});
        self.builder.retag(id, .tuple_pattern);
        return id;
    }

    test "a comma after the first component makes a tuple, and a lone comma is refused" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        const source: Source = .{ .path = "t.lin", .text = "fn f() -> UInt8 {\n" ++
            "    let (a, b) = (1, 2)\n" ++
            "    let g = (7)\n" ++
            "    let one = (7,)\n" ++
            "    0\n" ++
            "}" };
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        const ast = try parse(gpa, &source, .from(0), tokens, &sink);
        const stmts = ast.blockStmts(ast.blockOf(ast.declBody(node.DeclId.at(0))));
        try testing.expectEqual(@as(usize, 3), stmts.len);

        try testing.expectEqual(node.Stmt.Tag.let_destructure, ast.stmtTag(stmts[0]));
        const pattern = ast.stmtData(stmts[0]).pattern;
        try testing.expectEqual(Expr.Tag.tuple_pattern, ast.exprTag(pattern));
        try testing.expectEqual(@as(usize, 2), ast.call(pattern).args.len);
        const literal = ast.stmtData(stmts[0]).init;
        try testing.expectEqual(Expr.Tag.tuple_literal, ast.exprTag(literal));
        try testing.expectEqual(@as(usize, 2), ast.call(literal).args.len);

        try testing.expectEqual(Expr.Tag.grouped, ast.exprTag(ast.stmtData(stmts[1]).init));

        // The refused tuple is still built, at the `(` the report names.
        const one = ast.stmtData(stmts[2]).init;
        try testing.expectEqual(Expr.Tag.tuple_literal, ast.exprTag(one));
        try testing.expectEqual(@as(u32, 1), sink.error_count);
        const refusal = sink.list.items[0];
        try testing.expectEqual(Code.s_tuple, refusal.code.?);
        try testing.expectEqual(ast.tokenSpan(ast.exprMain(one)).start, refusal.primaryLabel().?.span.start);
    }

    test "a malformed tuple pattern is one report, and the statement after it still parses" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();

        const cases = [_]struct { text: []const u8, codes: []const ?Code }{
            .{ .text = "let read (a, _,) = p", .codes = &.{} },
            // A component is a pattern, so tuples nest and a literal is read
            // as one; whether it matches every value is the checker's.
            .{ .text = "let ((a, b), c) = x", .codes = &.{} },
            .{ .text = "let ((a, b)) = x", .codes = &.{.s_tuple} },
            .{ .text = "let (a, 1) = x", .codes = &.{} },
            .{ .text = "let (a, =) = x", .codes = &.{.s_match} },
            .{ .text = "let (a) = x", .codes = &.{.s_tuple} },
            .{ .text = "let (a,) = x", .codes = &.{.s_tuple} },
            .{ .text = "let () = x", .codes = &.{.s_tuple} },
            .{ .text = "let (a, b, c, d, e, f, g, h, i) = x", .codes = &.{.s_tuple} },
            // A missing comma is the one mistake: the `)` after it is found.
            .{ .text = "let (c d) = x", .codes = &.{.s_tuple} },
            .{ .text = "let (a, b = x", .codes = &.{.s_paren} },
        };
        for (cases) |case| {
            const text = try std.fmt.allocPrint(gpa, "fn f() -> UInt8 {{\n    {s}\n    let after = 0\n    after\n}}\n", .{case.text});
            try testing.expectEqualSlices(?Code, case.codes, try codesOf(gpa, text));
            const r = try parseWithDiagnostics(gpa, text);
            try testing.expectEqual(@as(usize, 1), std.mem.count(u8, r.dump, "let_decl"));
        }
    }

    /// Reports that no arm pattern begins at `at`, which is the token
    /// `startsArmPattern` refused.
    fn reportNoPattern(self: *Parser, at: TokenId) !void {
        // A multi-line literal's line runs to its end, so the `=>` after it
        // would be text; the same text quoted is a pattern.
        if (self.cursor.at(.string_line)) {
            return self.reportAt(.s_match, at, "a multi-line literal is not a pattern", "write this text as a quoted literal");
        }
        // The unit type has one value, so a pattern for it would test nothing.
        if (self.cursor.at(.l_paren) and self.cursor.peekAt(1) == .r_paren) {
            return self.reportAt(.s_match, at, "`()` is not a pattern", "the unit type has one value; write `_` to match it");
        }
        return self.reportAt(.s_match, at, "expected a pattern", "an arm begins with a variant, `_`, a number or a string");
    }

    /// One arm's pattern: a variant, a variant with binders, a struct, a
    /// literal, or a range.
    fn parseArmPattern(self: *Parser) std.mem.Allocator.Error!ExprId {
        const at = self.cursor.current();

        if (!self.atArmPattern()) {
            try self.reportNoPattern(at);
            return self.errExpr(at);
        }

        if (self.cursor.at(.l_paren)) return self.parseTuplePattern();

        if (self.cursor.at(.int_literal) or self.cursor.at(.string_literal) or self.cursor.at(.minus)) {
            return self.parsePatternBoundOrRange(at);
        }

        if (self.cursor.at(.keyword_reflect)) return self.parsePostfix(.none);

        if (self.cursor.eat(.identifier) == null) {
            return self.errExpr(at);
        }

        // A dotted name, or a range operator straight after the bare one, is
        // a range's lower bound -- a variant is never written either way.
        // Looked ahead for rather than carved into a second grammar, which is
        // what keeps `Name` and `Thing.top..=20` one production apiece.
        if (self.cursor.at(.dot) or isRangeOp(self.cursor.peek())) {
            self.cursor.index = at.index();
            return self.parsePatternBoundOrRange(at);
        }

        if (self.cursor.at(.l_brace)) {
            self.cursor.index = at.index();
            return self.parseStructPattern();
        }
        const bare = try self.builder.addLiteral(.name_ref, at, self.rangeFrom(at));
        return self.parsePayloadPattern(at, bare);
    }

    test "a tuple pattern is an arm's pattern, and a pattern stands wherever a binder does" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();

        const ok = "fn f(p: (UInt8, UInt8)) -> UInt8 {\n    match p {\n        (a, _) => a,\n    }\n}\n";
        try testing.expectEqualSlices(?Code, &.{}, try codesOf(gpa, ok));
        try testing.expect(std.mem.indexOf(u8, (try parseWithDiagnostics(gpa, ok)).dump, "tuple_pattern") != null);

        const cases = [_]struct { arm: []const u8, codes: []const ?Code }{
            .{ .arm = "() => 0,", .codes = &.{.s_match} },
            .{ .arm = "Some(()) => 0,", .codes = &.{.s_match} },
            .{ .arm = "Some((a, b)) => 0,", .codes = &.{} },
            .{ .arm = "Some(a, (b, c)) => 0,", .codes = &.{} },
            .{ .arm = "(a, (b, c)) => 0,", .codes = &.{} },
            .{ .arm = "S { f: (a, b) } => 0,", .codes = &.{} },
            .{ .arm = "Some(None) => 0,", .codes = &.{} },
            .{ .arm = "Ok(Point { x, y }) => 0,", .codes = &.{} },
            .{ .arm = "Reading { s, v: Some(x) } => 0,", .codes = &.{} },
            .{ .arm = "(Some(a), 0..=9) => 0,", .codes = &.{} },
            .{ .arm = "Err({ a, b }) => 0,", .codes = &.{} },
            .{ .arm = "Some(Some(-1)) => 0,", .codes = &.{} },
        };
        for (cases) |case| {
            const text = try std.fmt.allocPrint(gpa, "fn f(p: (UInt8, UInt8)) -> UInt8 {{\n    match p {{\n        {s}\n        _ => 1,\n    }}\n}}\n", .{case.arm});
            try testing.expectEqualSlices(?Code, case.codes, try codesOf(gpa, text));
        }
    }

    /// `N(n)`: what a variant or a newtype carries, taken apart under a
    /// name. Shared by a match arm and a destructuring `let`, so the two
    /// cannot read the shape two ways.
    ///
    /// `N?(n)` has no reading here. `?` marks a proven value's construction
    /// declining, and a pattern reads what a value already is -- the token
    /// that opens the fallible construction form names nothing a pattern
    /// could mean, so it is refused here rather than folded into a binder
    /// list nobody asked for.
    fn parsePayloadPattern(self: *Parser, at: TokenId, bare: ExprId) std.mem.Allocator.Error!ExprId {
        if (self.cursor.at(.question)) {
            try self.reportAt(
                .t_refine,
                self.cursor.current(),
                "a proven value has nothing to decline",
                "drop the `?`; a pattern reads what is already proven",
            );
            _ = self.cursor.advance();
        }
        return self.parseBinders(at, bare);
    }

    /// A literal, or a range built from two: `9`, `0..=9`, `0..=Thing.top`.
    ///
    /// [S-Range]'s non-associativity is the rule a range expression already
    /// enforces; a pattern's range shares it rather than restating it, so
    /// `0..9..18` is refused the same way in either position.
    fn parsePatternBoundOrRange(self: *Parser, start: TokenId) std.mem.Allocator.Error!ExprId {
        const lhs = try self.parsePatternBound();

        const op = self.cursor.peek();
        if (!isRangeOp(op)) return lhs;
        const op_token = self.cursor.current();
        _ = self.cursor.advance();

        const rhs = try self.parsePatternBound();

        const range = try self.builder.addRange(op_token, self.rangeFrom(start), lhs, rhs, op == .dot_dot_equal);

        if (isRangeOp(self.cursor.peek())) {
            try self.reportAt(
                .s_range,
                self.cursor.current(),
                "a range does not end a range",
                "neither association means anything",
            );
            _ = self.cursor.advance();
            // Reported once, above, rather than through `errExpr`, whose
            // generic "expected an expression" would say the same thing
            // twice. The dangling bound goes with its operator, so recovery
            // rests before the arrow and the arm machinery sees one mistake.
            if (self.cursor.peek() != .l_paren and startsArmPattern(self.cursor.peek())) _ = try self.parsePatternBound();
            return self.builder.addLiteral(.err, start, self.rangeFrom(start));
        }
        return range;
    }

    /// A range pattern's bound: an integer literal, a string literal, or a
    /// name -- bare, or a path to a declaration's constant, which is all
    /// the constant table ever answers. A string literal is parsed
    /// here exactly as it is anywhere else; whether it is one Unicode scalar
    /// is the checker's question, not the grammar's. Parsed the same way any
    /// name is and checked here instead of restricted in the grammar, so a
    /// bound that is none of these is `[S-Range]` naming what was written in
    /// its place.
    fn parsePatternBound(self: *Parser) std.mem.Allocator.Error!ExprId {
        const start = self.cursor.current();

        // A minus belongs to a bound the way it belongs to a literal
        // anywhere: a signed scrutinee's negative half is written directly,
        // not through a named constant. Through the same routine a
        // refinement's bound is read with, so one bound is one parser.
        if (self.cursor.at(.minus) or self.cursor.at(.int_literal)) {
            const bound = try self.parseBound();
            if (bound.digits == TokenId.none) {
                return self.builder.addLiteral(.err, start, self.rangeFrom(start));
            }
            const literal = try self.builder.addLiteral(.int_literal, bound.digits, self.rangeFrom(bound.digits));
            if (bound.minus == TokenId.none) return literal;
            return self.builder.addUnary(.negate, start, self.rangeFrom(start), literal);
        }

        if (self.cursor.at(.string_literal)) {
            _ = self.cursor.advance();
            return self.builder.addLiteral(.str_literal, start, self.rangeFrom(start));
        }

        if (self.cursor.eat(.identifier) != null) {
            var base = try self.builder.addLiteral(.name_ref, start, self.rangeFrom(start));
            while (self.cursor.at(.dot)) {
                _ = self.cursor.advance();
                const name = self.cursor.current();
                if (self.cursor.eat(.identifier) == null) {
                    try self.reportAt(.s_name, name, "expected a name after `.`", "a `.` selects a part");
                    break;
                }
                base = try self.builder.addUnary(.field, name, self.rangeFrom(start), base);
            }
            return base;
        }

        try self.reportAt(
            .s_range,
            start,
            "a range pattern's bound is a literal or a name",
            "not a literal or a name",
        );
        // Reported once, and the cursor stays put: whatever sits here is the
        // arm's own `=>` or `,` more often than not, and `errExpr`'s follow
        // set runs past both -- which deleted every arm after this one.
        return self.builder.addLiteral(.err, start, self.rangeFrom(start));
    }

    /// A binding, mutable or not. One production for both, because the two
    /// differ only in the keyword and in whether the name may be assigned
    /// again -- which is a rule about the name, not about the syntax.
    /// Where a binding ends, and what a separator written there answers.
    ///
    /// A binding ends at a `;`, at the newline after it, or at the brace
    /// closing the block it sits in. All three separate it from whatever
    /// follows; none is required where another is present.
    ///
    /// One routine, because `let x = e` and `let S { .. } = e` are one
    /// statement form with two spellings. The destructuring one had no tail at
    /// all -- it ate a `;` and returned -- so two statements written on one
    /// line raised no [S-Separator], and a next line beginning with `-` noted
    /// no continuation. The formatter reads that note to decide whether a
    /// written `;` is meaningful, so it kept one that answered nothing.
    fn endBinding(self: *Parser, init_expr: ExprId) !void {
        const separated = self.cursor.eat(.semicolon) != null;
        try self.endStatement(separated, init_expr, "this binding ends here");
    }

    /// Where a statement ends, and what a separator written there answers.
    ///
    /// [S-Separator] is a rule about statements, so every form of statement
    /// answers for it here rather than each deciding for itself. A binding
    /// enforced it and an expression statement did not, which left `a = 3 b =
    /// 4` accepted while `let a = 3 let b = 4` was refused -- one rule, two
    /// answers, and the formatter drew the boundary the parser declined to
    /// require.
    ///
    /// `produced` is what the statement parsed to. An expression already
    /// reported is why the separator is missing, so saying so as well
    /// describes one mistake twice.
    fn endStatement(self: *Parser, separated: bool, produced: ExprId, what: []const u8) !void {
        const ended = separated or
            self.cursor.precededByNewline() or
            self.cursor.at(.r_brace) or
            // `while c { .. } i` is two statements and reads as two: the block
            // that ends the first is a delimiter, so no separator is missing.
            self.cursor.precededByRBrace();
        if (!separated) try self.noteContinuation();
        if (ended or self.cursor.atEnd()) return;

        if (self.builder.exprTag(produced) != .err) {
            try self.reportAt(
                .s_separator,
                self.cursor.current(),
                "expected `;` or a newline",
                what,
            );
        }
        // A delimited run is skipped whole, so a `}` inside it closes only
        // what it opened there and not the block this statement is in. An
        // opener whose closer belongs to the block around the statement is
        // stepped over like any other token, so the skip still stops at the
        // next statement boundary rather than running past that block or to
        // the end of the file. `skippedCloserPairs` decides which closers
        // those are.
        while (!self.atStatementBoundary()) {
            const opens = self.cursor.at(.l_brace) or self.cursor.at(.l_paren) or self.cursor.at(.l_bracket);
            if (opens) if (self.delimiterEnd(self.cursor.current())) |close| if (self.skippedCloserPairs(close)) {
                self.skipBalanced();
                continue;
            };
            _ = self.cursor.advance();
        }
        _ = self.cursor.eat(.semicolon);
    }

    /// Whether `close` ends the run a skipped statement tail opened, rather
    /// than the block around the statement.
    ///
    /// Indentation is compared as text: a closer that begins its line pairs
    /// only when the statement's indentation is a prefix of the closer's, so
    /// a closer left of the statement, or one indented with other characters
    /// -- tabs against spaces -- belongs to an enclosing block.
    ///
    /// A closer after something else on its line pairs, except in a block
    /// opened on the statement's line, where the statement does not begin
    /// that line and the block's structural closer sits left of the
    /// statement. That block is missing a closer, and a closer on the `{`'s
    /// line is taken as the block's own.
    fn skippedCloserPairs(self: *Parser, close: TokenId) bool {
        const statement = self.statement;
        if (self.cursor.lineIndent(close)) |indent| return std.mem.startsWith(u8, indent, statement.indent);
        if (statement.begins_line or statement.open == .none) return true;
        if (self.delimiterEnd(statement.open)) |block_close| {
            const indent = self.cursor.lineIndent(block_close) orelse return true;
            if (std.mem.startsWith(u8, indent, statement.indent)) return true;
        }
        const end = self.lineEndAfter(self.cursor.spans[statement.open.index()].start);
        return self.cursor.spans[statement.start.index()].start > end or self.cursor.spans[close.index()].start > end;
    }

    /// Where the line holding `offset` ends: the first line break at or
    /// after it, or the end of the source.
    ///
    /// Answered from `line_end` when `offset` lies in the stretch it covers.
    /// An offset before that stretch scans only up to it, and extends it when
    /// no break lies between; any other offset scans to its own line's end.
    /// A line is therefore scanned once while queries stay on it, however
    /// many statements on it ask.
    fn lineEndAfter(self: *Parser, offset: usize) usize {
        const source = self.cursor.source;
        if (self.line_end) |known| {
            if (offset >= known.from and offset <= known.end) return known.end;
            if (offset < known.from) {
                if (std.mem.indexOfScalarPos(u8, source[0..known.from], offset, '\n')) |line_break| {
                    self.line_end = .{ .from = offset, .end = line_break };
                    return line_break;
                }
                self.line_end = .{ .from = offset, .end = known.end };
                return known.end;
            }
        }
        const end = std.mem.indexOfScalarPos(u8, source, offset, '\n') orelse source.len;
        self.line_end = .{ .from = offset, .end = end };
        return end;
    }

    test skippedCloserPairs {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();

        // The skip starts on the call's second line, and the `}` sits at the
        // indentation of the line the statement starts on: it closes the `{`
        // after `oops`, so the function ends where its own `}` is.
        const continued = try codesOf(gpa,
            \\fn main() -> UInt8 {
            \\    let total = add(1,
            \\            2) oops {
            \\        total
            \\    }
            \\    0
            \\}
            \\fn other() -> UInt8 { 0 }
        );
        try testing.expectEqualSlices(?Code, &.{.s_separator}, continued);

        // A `}` indented with spaces is not measured against a statement
        // indented with tabs, and one on the line of a one-line loop closes
        // that loop, whichever of the loop's statements the skip is in.
        for ([_][]const u8{
            "fn main() -> UInt8 {\n    for s in xs {\n\t\ts oops {\n    }\n    0\n}\nfn other() -> UInt8 { 0 }\n",
            "fn main() -> UInt8 {\n    for s in xs { s oops { }\n    0\n}\nfn other() -> UInt8 { 0 }\n",
            "fn main() -> UInt8 {\n    for s in xs { let a = s; a oops { }\n    0\n}\nfn other() -> UInt8 { 0 }\n",
        }) |text| {
            try testing.expectEqualSlices(?Code, &.{.s_separator}, try codesOf(gpa, text));
        }
    }

    /// `defer e`, which schedules `e` at every exit from the enclosing scope,
    /// and `defer let x = e`, the binding that schedules its own release.
    ///
    /// The expression is parsed as a statement's is and ends where one ends,
    /// so [S-Separator] answers for it through `endStatement` rather than
    /// through a rule of its own.
    fn parseDefer(self: *Parser, stmts: *std.ArrayList(StmtId)) !void {
        const at = self.cursor.current();
        _ = self.cursor.advance();

        if (self.cursor.at(.keyword_let) or self.cursor.at(.keyword_var)) {
            if (!self.cursor.precededByNewline()) return self.parseLet(stmts, at);
        }

        // Nothing to schedule. A `defer` running nothing at the scope's end is
        // what writing no `defer` already says, so the empty form is refused
        // rather than accepted as a statement with no effect.
        if (self.cursor.precededByNewline() or self.cursor.at(.r_brace) or self.cursor.at(.semicolon)) {
            try self.reportAt(
                .s_defer,
                at,
                "expected an expression after `defer`",
                "a `defer` schedules something to run",
            );
            return stmts.append(self.gpa, try self.builder.addStmt(.{
                .tag = .defer_stmt,
                .main_token = at,
                .token_range = self.rangeFrom(at),
                .data = .{ .name = .none, .annotation = .{ .name = .none }, .init = .none },
            }));
        }

        const scheduled = try self.parseFull();
        const separated = self.cursor.eat(.semicolon) != null;
        try self.endStatement(separated, scheduled, "this `defer` ends here");

        try stmts.append(self.gpa, try self.builder.addStmt(.{
            .tag = .defer_stmt,
            .main_token = at,
            .token_range = self.rangeFrom(at),
            .data = .{ .name = .none, .annotation = .{ .name = .none }, .init = scheduled },
        }));
    }

    /// `let`, `var` and a destructuring `let`, and `defer` before any of them
    /// where `deferred` is the `defer` token.
    ///
    /// `defer let x = e` appends two statements, the binding and then the
    /// `defer_release` that schedules `x.release()`. This is the one place the
    /// expansion is made: every later pass reads the pair as it reads the two
    /// statements a programmer could have written, and the formatter reads
    /// the pair back as the one form.
    fn parseLet(self: *Parser, stmts: *std.ArrayList(StmtId), deferred: TokenId) !void {
        const let_token = self.cursor.current();
        const first = if (deferred == .none) let_token else deferred;
        const keyword = self.cursor.peek().describe();
        const takes_apart = self.cursor.at(.keyword_let);
        _ = self.cursor.advance();
        // `read` marks a pattern that observes a place rather than taking a
        // value apart. It belongs to the pattern, so a plain name after it
        // is refused below and still parses as the binding it names.
        const read_token = self.cursor.eat(.keyword_read);

        // A brace starts an inferred struct pattern and a parenthesis a tuple
        // pattern. A named struct or newtype pattern puts `{`, `(` or `?`
        // after its head; an ordinary binding instead follows its name with
        // `=` or `:`.
        const destructures = self.cursor.at(.l_brace) or self.cursor.at(.l_paren) or (self.cursor.at(.identifier) and switch (self.cursor.peekAt(1)) {
            .l_brace, .l_paren, .question => true,
            else => false,
        });
        // Only where a name follows: with nothing there, the missing name is
        // the one mistake, and saying so as well describes it twice.
        if (read_token != null and !destructures and self.cursor.at(.identifier)) {
            try self.reportAt(
                .s_destructure,
                read_token.?,
                "`read` binds the parts of a pattern",
                "write a struct, newtype or tuple pattern after `let read`",
            );
        }
        // One name is bound and released: a pattern holds several values and a
        // `read` pattern owns none, so there is no one release the keyword could
        // mean. A `read` before a plain name is reported below, as it is for
        // `let`.
        if (deferred != .none and destructures) {
            try self.reportAt(
                .s_defer_let,
                read_token orelse self.cursor.current(),
                if (read_token != null) "`defer let` cannot bind by `read`" else "`defer let` binds one name",
                if (read_token != null)
                    "a `read` binding owns nothing to release; write `let read`"
                else
                    "take the value apart with `let`, then `defer` the release of each part that needs one",
            );
        }
        if (destructures) {
            // Only `let` takes a value apart. Accepting `var` here parsed to
            // the same node, so the keyword reached nothing and every binder
            // it bound was reported as declared with `let` -- a diagnostic
            // contradicting the line it points at.
            if (!takes_apart) {
                try self.reportAt(
                    .s_destructure,
                    let_token,
                    "use `let` to take a value apart",
                    "a destructuring binding is introduced by `let`",
                );
            }
            const pattern = if (self.cursor.at(.l_paren))
                try self.parseTuplePattern()
            else if (self.cursor.at(.l_brace) or self.cursor.peekAt(1) == .l_brace)
                try self.parseStructPattern()
            else
                try self.parseNewtypePattern();
            if (self.cursor.eat(.equal) == null) {
                try self.reportAt(.s_equals, self.cursor.current(), "expected `=`", "a destructuring `let` names what it takes apart");
            }
            // `read` before the place, where a lambda's invocation mode could
            // begin, is the pattern's marker written on the wrong side. A mode
            // is followed by its capture list. The recovered pattern reads, as
            // the marker asked.
            var reads = read_token != null;
            if (self.cursor.at(.keyword_read) and self.cursor.peekAt(1) != .l_bracket) {
                const misplaced = self.cursor.advance();
                try self.reportAt(
                    .s_destructure,
                    misplaced,
                    "`read` marks the pattern, not the place it reads",
                    "write `let read Pattern = place`",
                );
                reads = true;
            }
            const of = try self.parseInitializer();
            try self.endBinding(of);
            return stmts.append(self.gpa, try self.builder.addStmt(.{
                .tag = if (reads) .let_read_destructure else .let_destructure,
                .main_token = let_token,
                .token_range = self.rangeFrom(first),
                .data = .{ .name = .none, .annotation = .{ .name = .none }, .init = of, .pattern = pattern },
            }));
        }

        const name = self.cursor.current();
        // The message is built only when it is reported.
        if (self.cursor.at(.identifier))
            _ = self.cursor.advance()
        else
            _ = try self.expectName(.s_name, try std.fmt.allocPrint(self.sink.arena, "expected a name after {s}", .{keyword}), "a binding needs a name");

        var annotation: node.TypeRef = .{ .name = .none };
        if (self.cursor.eat(.colon) != null) annotation = try self.parseWrittenType();
        if (self.cursor.at(.equal)) {
            _ = self.cursor.advance();
        } else {
            try self.reportAt(.s_equals, self.cursor.current(), "expected `=`", "a binding needs an initialiser");
        }

        const written = try self.parseInitializer();
        // A refused `let read name` asked not to take the place, so the
        // recovered binding observes it instead of moving it, and a later use
        // of the place reports nothing further.
        const init_expr = if (read_token != null and !destructures and written != ExprId.none)
            try self.builder.addUnary(.borrow, read_token.?, self.rangeFrom(read_token.?), written)
        else
            written;

        try self.endBinding(init_expr);

        try stmts.append(self.gpa, try self.builder.addStmt(.{
            .tag = .let_decl,
            .main_token = let_token,
            .token_range = self.rangeFrom(first),
            .data = .{
                .name = name,
                .annotation = annotation,
                .init = init_expr,
            },
        }));

        // A refused `defer let read name` is `let`, so a release the keyword
        // refused is not scheduled on top of the report.
        if (deferred != .none and read_token == null and self.cursor.tags[name.index()] == .identifier) {
            const named: TokenRange = .{ .start = name, .end = TokenId.at(name.index() + 1) };
            const range: TokenRange = .{ .start = deferred, .end = named.end };
            const receiver = try self.builder.addLiteral(.name_ref, name, named);
            // The callee names no operation: it stands at `defer` and resolves
            // to nothing, and the checker finds `release` for the receiver's
            // type.
            const callee = try self.builder.addLiteral(.name_ref, deferred, .{ .start = deferred, .end = TokenId.at(deferred.index() + 1) });
            const release = try self.builder.addCall(deferred, range, callee, &.{receiver}, &.{});
            try stmts.append(self.gpa, try self.builder.addStmt(.{
                .tag = .defer_release,
                .main_token = deferred,
                .token_range = range,
                .data = .{ .name = .none, .annotation = .{ .name = .none }, .init = release },
            }));
        }
    }

    test parseLet {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        const source: Source = .{ .path = "t.lin", .text = "fn f() -> UInt8 {\n" ++
            "    defer let a = open()\n" ++
            "    defer var b: UInt8 = 1\n" ++
            "    defer let P { x } = make()\n" ++
            "    defer let read Q(n) = place\n" ++
            "    defer\n" ++
            "    let c = 2\n" ++
            "    0\n" ++
            "}" };
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        const ast = try parse(gpa, &source, .from(0), tokens, &sink);
        const stmts = ast.blockStmts(ast.blockOf(ast.declBody(node.DeclId.at(0))));
        const tags = [_]node.Stmt.Tag{
            .let_decl,        .defer_release,
            .let_decl,        .defer_release,
            .let_destructure, .let_read_destructure,
            .defer_stmt,      .let_decl,
        };
        try testing.expectEqual(tags.len, stmts.len);
        for (tags, stmts) |tag, s| try testing.expectEqual(tag, ast.stmtTag(s));

        // The binding begins at `defer` and keeps its own `let`, so the keyword
        // is read back from the tree rather than stored.
        try testing.expect(ast.stmtIsDeferredBinding(stmts[0]));
        try testing.expect(!ast.stmtIsMutable(stmts[0]));
        try testing.expect(ast.stmtIsMutable(stmts[2]));
        try testing.expect(!ast.stmtIsDeferredBinding(stmts[7]));
        try testing.expectEqualStrings("let a = open()", ast.stmtSpan(stmts[0]).slice(source.text)[6..]);

        // The release is a call on the binding's name that spells no operation,
        // and its tokens stop at the name so the initialiser is not inside it.
        const release = ast.stmtData(stmts[1]).init;
        try testing.expect(ast.callIsScheduledRelease(release));
        const receiver = ast.call(release).args[0];
        try testing.expectEqual(ast.stmtData(stmts[0]).name, ast.exprMain(receiver));
        try testing.expectEqualStrings("defer let a", ast.exprSpan(release).slice(source.text));
        try testing.expect(!ast.callIsScheduledRelease(ast.stmtData(stmts[0]).init));

        // A pattern and a `read` bind nothing a keyword could release: one
        // report each, and the `defer` before a line break is its own mistake.
        try testing.expectEqual(@as(u32, 3), sink.error_count);
        try testing.expectEqual(Code.s_defer_let, sink.list.items[0].code.?);
        try testing.expectEqual(Code.s_defer_let, sink.list.items[1].code.?);
        try testing.expectEqual(Code.s_defer, sink.list.items[2].code.?);
    }

    /// Parses a binding's initializer, and the `else` block that handles its
    /// failure where one follows.
    ///
    /// The `else` is found by `eatElse`, the rule an `if` uses, so it may begin
    /// the next line. An `if` initializer takes the first `else` itself, and a
    /// binding takes one: a second is reported once and skipped whole.
    ///
    /// A malformed binder is reported once. Everything after it up to the
    /// block is skipped, and a block missing after it is not reported again.
    fn parseInitializer(self: *Parser) std.mem.Allocator.Error!ExprId {
        const start = self.cursor.current();
        var m = Measure.begin(self);
        defer m.finish();

        const operand = try self.parseFull();
        m.operand();
        const at = self.eatElse() orelse return operand;

        var run: [2]ExprId = undefined;
        var n: usize = 0;
        var broken = false;
        if (self.cursor.at(.pipe_pipe)) {
            try self.reportAt(
                .s_let_else,
                self.cursor.current(),
                "expected a name between the bars",
                "write `else |error|`, or `else` alone where the failure carries nothing",
            );
            _ = self.cursor.advance();
            broken = true;
        } else if (self.cursor.eat(.pipe)) |bar| {
            const name = self.cursor.current();
            if (self.cursor.eat(.identifier) != null) {
                run[n] = try self.builder.addLiteral(.name_ref, name, self.rangeFrom(name));
                if (!self.cursor.at(.pipe)) {
                    try self.reportAt(.s_let_else, self.cursor.current(), "expected `|`", "an `else` binds one name between its bars");
                    broken = true;
                }
            } else {
                try self.reportAt(.s_name, bar, "expected a name after `|`", "`else` binds what a failure carries to one name");
                run[n] = try self.builder.addLiteral(.err, name, self.rangeFrom(name));
                broken = true;
            }
            n += 1;
            if (broken) self.skipBinder() else _ = self.cursor.advance();
        }
        const brace = self.cursor.current();
        run[n] = if (broken and !self.cursor.at(.l_brace))
            try self.builder.addLiteral(.err, brace, self.rangeFrom(brace))
        else
            try self.parseBraced("an `else` handles the failure in a block");
        n += 1;
        m.operand();
        if (!m.wrap()) return self.tooDeeplyNested(at);

        const e = try self.builder.addCall(at, self.rangeFrom(start), operand, run[0..n], &.{});
        self.builder.retag(e, .unwrap_else);

        if (self.cursor.at(.keyword_else)) {
            try self.reportAt(
                .s_let_else,
                self.cursor.current(),
                "a binding takes one `else`",
                "the `else` before this one already handles the failure",
            );
            _ = self.cursor.advance();
            if (self.cursor.eat(.pipe_pipe) == null and self.cursor.eat(.pipe) != null) {
                self.skipBinder();
            }
            if (self.cursor.at(.l_brace)) self.skipBalanced();
        }
        return e;
    }

    test parseInitializer {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        const source: Source = .{ .path = "t.lin", .text = "fn f() -> UInt8 {\n" ++
            "    let a = get() else |error| { 1 }\n" ++
            "    let b = find() else { return 2 }\n" ++
            "    let c = if ready { x } else { y } else { 3 }\n" ++
            "    let d = find()\n" ++
            "    else { 4 }\n" ++
            "    let e = if ready { x }\n" ++
            "    else { y }\n" ++
            "    let f = find() else |x y| { 5 } else { 6 }\n" ++
            "    0\n" ++
            "}" };
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        const ast = try parse(gpa, &source, .from(0), tokens, &sink);
        const stmts = ast.blockStmts(ast.blockOf(ast.declBody(node.DeclId.at(0))));
        try testing.expectEqual(@as(usize, 6), stmts.len);

        const bound = ast.unwrapElse(ast.stmtData(stmts[0]).init);
        try testing.expectEqual(Expr.Tag.call, ast.exprTag(bound.operand));
        try testing.expectEqualStrings("error", ast.tokenText(ast.exprMain(bound.binder)));
        try testing.expectEqual(Expr.Tag.block, ast.exprTag(bound.body));

        try testing.expectEqual(ExprId.none, ast.unwrapElse(ast.stmtData(stmts[1]).init).binder);
        // An `if` initializer takes the first `else`; the second is the binding's.
        try testing.expectEqual(Expr.Tag.conditional, ast.exprTag(ast.unwrapElse(ast.stmtData(stmts[2]).init).operand));
        // An `else` may begin the next line, for a binding as for an `if`.
        try testing.expectEqual(Expr.Tag.unwrap_else, ast.exprTag(ast.stmtData(stmts[3]).init));
        try testing.expectEqual(Expr.Tag.conditional, ast.exprTag(ast.stmtData(stmts[4]).init));

        // A binder with two names and a second `else` are one report each.
        try testing.expectEqual(Expr.Tag.unwrap_else, ast.exprTag(ast.stmtData(stmts[5]).init));
        try testing.expectEqual(@as(u32, 2), sink.error_count);
        try testing.expectEqual(Code.s_let_else, sink.list.items[0].code.?);
        try testing.expectEqual(Code.s_let_else, sink.list.items[1].code.?);
    }

    /// Skips the rest of a malformed binder: through its closing bar, or up to
    /// the block or the end of the line where it has none.
    fn skipBinder(self: *Parser) void {
        while (!self.cursor.atEnd() and !self.cursor.at(.pipe) and !self.cursor.at(.l_brace) and
            !self.cursor.precededByNewline()) _ = self.cursor.advance();
        if (self.cursor.at(.pipe) and !self.cursor.precededByNewline()) _ = self.cursor.advance();
    }

    /// Consumes an `else` that continues the construct before it, on the same
    /// line or at the start of the next.
    ///
    /// A newline ends a statement, but `else` cannot begin one, so a line
    /// opening with `else` has only one reading: it continues the nearest
    /// construct still able to take it. An `if` takes it before the binding
    /// around the `if` does, because the `if` is parsed first. `if` and a
    /// binding's `else` both ask here, so the two cannot disagree about where
    /// an `else` may be written.
    fn eatElse(self: *Parser) ?TokenId {
        return self.cursor.eat(.keyword_else);
    }

    /// A complete expression, which is the only place an assignment may
    /// appear.
    ///
    /// Assignment binds looser than every operator and does not chain. It is
    /// not in the precedence table because it is not an operator on values:
    /// its left side names a binding rather than producing one, and its own
    /// value is Unit, so `a = b = c` would be assigning Unit to `b` and is a
    /// syntax error rather than a rule the checker has to state.
    ///
    /// A compound assignment is read here for the same reasons and gets the
    /// same answers. `a += b + c` updates `a` by the sum, because everything
    /// binds tighter than this does, and `a += b += c` is the syntax error
    /// `a = b = c` is.
    ///
    /// Every complete expression other than a control header's own is read
    /// here, and each sits inside delimiters or is a statement of its own, so
    /// the header's claim on the next brace ends for its duration.
    fn parseFull(self: *Parser) std.mem.Allocator.Error!ExprId {
        const saved_header = self.control_header;
        self.control_header = false;
        defer self.control_header = saved_header;

        const start = self.cursor.current();
        var m = Measure.begin(self);
        defer m.finish();

        const lhs = try self.parseExpr(1);
        m.operand();
        const tag = assignmentAt(self.cursor.peek()) orelse return lhs;

        const op = self.cursor.current();
        _ = self.cursor.advance();
        const value = try self.parseExpr(1);
        m.operand();
        if (!m.wrap()) return self.tooDeeplyNested(op);
        return self.builder.addBinary(tag, op, self.rangeFrom(start), lhs, value);
    }

    fn parseControlHeader(self: *Parser) std.mem.Allocator.Error!ExprId {
        const saved = self.control_header;
        self.control_header = true;
        defer self.control_header = saved;
        return self.parseExpr(1);
    }

    /// Which assignment a token opens, if it opens one.
    fn assignmentAt(tag: Tag) ?node.Expr.Tag {
        return switch (tag) {
            .equal => .assign,
            .plus_equal => .add_assign,
            .minus_equal => .sub_assign,
            .star_equal => .mul_assign,
            .slash_equal => .div_assign,
            .percent_equal => .rem_assign,
            else => null,
        };
    }

    /// Precedence climbing. `min_prec` is the lowest binding power this call
    /// will consume, which is what makes left associativity fall out of
    /// recursing at one above the operator's own power.
    fn parseExpr(self: *Parser, min_prec: u8) std.mem.Allocator.Error!ExprId {
        // The chain folds left, so each operator consumed here builds a node
        // above everything read so far -- a level of tree that no further call
        // to `parseUnary` accounts for.
        var m = Measure.begin(self);
        defer m.finish();

        // `..b` and bare `..`: a range's own precedence is the loosest a call
        // to `parseExpr` ever admits, so seeing one here -- before an operand
        // was even attempted -- means the end before it was never written.
        // Compared against the table rather than spelled as a number, so a
        // renumbering cannot silently part the two.
        if (min_prec <= precedence(.dot_dot) and isRangeOp(self.cursor.peek())) {
            return self.openRangeEnd();
        }

        var lhs = try self.parseUnary();
        m.operand();

        while (true) {
            if (self.finishedAtALineBreak()) break;
            const op = self.cursor.peek();
            const prec = precedence(op);
            if (prec == 0 or prec < min_prec) break;

            const op_token = self.cursor.current();
            _ = self.cursor.advance();

            if (isRangeOp(op)) {
                const start = self.builder.exprStart(lhs);

                // `a..`: nothing follows the operator that could be its high
                // end, whether the line simply ends here or the next token
                // is one that can only close something else. A bare `{` is in
                // that set: it opens the body of whatever construct holds
                // this expression, and reading it as the end swallowed the
                // body and desynchronised past the enclosing function.
                if (inExprFollow(self.cursor.peek()) or self.cursor.peek() == .l_brace or self.cursor.precededByNewline()) {
                    try self.reportOpenRangeEnd(op_token);
                    return self.builder.addLiteral(.err, start, self.rangeFrom(start));
                }

                const rhs = try self.parseExpr(prec + 1);
                m.operand();
                if (!m.wrap()) return self.tooDeeplyNested(op_token);

                lhs = try self.builder.addRange(
                    op_token,
                    self.rangeFrom(start),
                    lhs,
                    rhs,
                    op == .dot_dot_equal,
                );

                // Non-associative: neither association a second `..`/`..=`
                // could mean is one anybody intends, so it is refused where
                // it is written rather than read either way.
                if (isRangeOp(self.cursor.peek())) {
                    try self.reportAt(
                        .s_range,
                        self.cursor.current(),
                        "a range does not end a range",
                        "neither association means anything",
                    );
                    _ = self.cursor.advance();
                    // Reported once, above, rather than through `errExpr`,
                    // whose generic "expected an expression" would say the
                    // same thing twice.
                    return self.builder.addLiteral(.err, start, self.rangeFrom(start));
                }
                continue;
            }

            const rhs = try self.parseExpr(prec + 1);
            m.operand();
            if (!m.wrap()) return self.tooDeeplyNested(op_token);

            const start = self.builder.exprStart(lhs);
            lhs = try self.builder.addBinary(
                binaryTag(op),
                op_token,
                self.rangeFrom(start),
                lhs,
                rhs,
            );

            // Comparison is non-associative: a second one at this level would
            // be comparing against the `Bool` the first produced, which is
            // never what anyone means.
            if (isComparison(op) and isComparison(self.cursor.peek())) {
                try self.sink.addError(
                    .s_chain,
                    self.file,
                    self.cursor.spanAt(self.cursor.current()),
                    "comparisons cannot be chained",
                    "compare one pair at a time",
                );
                _ = self.cursor.advance();
                return self.errExpr(start);
            }
        }

        return lhs;
    }

    fn parseUnary(self: *Parser) std.mem.Allocator.Error!ExprId {
        // Every expression descends through here exactly once, so this is
        // where descent is counted. What is stacked rather than descended
        // through is counted by the loop that stacks it.
        if (self.depth == max_nesting) return self.tooDeeplyNested(self.cursor.current());
        self.depth += 1;
        self.deepest = @max(self.deepest, self.depth);
        defer self.depth -= 1;

        if (self.cursor.at(.ampersand)) {
            const mark = self.cursor.current();
            _ = self.cursor.advance();
            return self.parsePostfix(mark);
        }
        if (self.cursor.at(.star)) {
            const at = self.cursor.current();
            _ = self.cursor.advance();
            const operand = try self.parseUnary();
            return self.builder.addUnary(.dereference, at, self.rangeFrom(at), operand);
        }
        if (self.cursor.at(.keyword_borrow)) {
            const at = self.cursor.current();
            _ = self.cursor.advance();
            const operand = try self.parseUnary();
            return self.builder.addUnary(.borrow, at, self.rangeFrom(at), operand);
        }
        if (self.cursor.at(.bang)) {
            const op = self.cursor.current();
            _ = self.cursor.advance();
            const operand = try self.parseUnary();
            return self.builder.addUnary(.not, op, self.rangeFrom(op), operand);
        }
        if (self.cursor.at(.minus)) {
            const op = self.cursor.current();
            _ = self.cursor.advance();
            const operand = try self.parseUnary();
            return self.builder.addUnary(.negate, op, self.rangeFrom(op), operand);
        }
        // Only where an index is being read. What it counts back by binds as
        // tightly as what a `-` negates, so `a[^k + 1]` counts back by `k` and
        // the addition is then over a value that counts, which the checker
        // refuses -- `a[^(k + 1)]` is the one that counts back by the sum.
        if (self.cursor.at(.caret) and self.indexes > 0) {
            const op = self.cursor.current();
            _ = self.cursor.advance();
            const operand = try self.parseUnary();
            return self.builder.addUnary(.from_end, op, self.rangeFrom(op), operand);
        }
        return self.parsePostfix(.none);
    }

    /// The expression that stands where one too deep was refused. `at` is the
    /// token whose level is the one over the limit, which for a form read in a
    /// loop is behind the cursor rather than under it.
    ///
    /// The node is built here rather than through `errExpr`, which reports a
    /// missing expression and skips to the nearest follow token. Neither
    /// applies: the expression is present, and skipping again would undo the
    /// balanced step that leaves the caller's delimiter in place.
    fn tooDeeplyNested(self: *Parser, at: TokenId) std.mem.Allocator.Error!ExprId {
        try self.refuseToDescend(at, "this expression nests too deeply");
        return self.builder.addLiteral(.err, at, self.rangeFrom(at));
    }

    /// Refuses to read further, and steps over what would have been read.
    ///
    /// The skip is balanced, so the delimiter the caller is waiting for is
    /// still where it expects one. Returning without consuming would leave a
    /// thousand frames each reporting the bracket it could not find, which
    /// describes one mistake a thousand times.
    fn refuseToDescend(self: *Parser, at: TokenId, what: []const u8) std.mem.Allocator.Error!void {
        if (!self.reported_nesting) {
            self.reported_nesting = true;
            try self.reportAt(
                .s_nesting,
                at,
                what,
                "the limit is 1000 levels",
            );
        }
        var depth: u32 = 0;
        while (!self.cursor.atEnd()) {
            switch (self.cursor.peek().nesting()) {
                1 => depth += 1,
                -1 => {
                    if (depth == 0) break;
                    depth -= 1;
                },
                else => {},
            }
            _ = self.cursor.advance();
        }
    }

    /// A primary expression, then whatever follows it.
    ///
    /// A `.` may follow anything that has a value, so this is a loop rather
    /// than a case in each production that happens to allow one. Methods land
    /// here too when they arrive: `p.translate(1)` is a selection followed by
    /// a call, which is the shape this already has.
    fn parsePostfix(self: *Parser, invocation_marker: TokenId) std.mem.Allocator.Error!ExprId {
        var start = self.cursor.current();
        var pending_marker = invocation_marker;

        // Every suffix wraps what precedes it, so this loop stacks levels the
        // same way an operator chain does and counts them the same way.
        var m = Measure.begin(self);
        defer m.finish();

        var named_head: ?node.TypeRef = null;
        var base = if (self.startsNamedStructLiteral()) blk: {
            const head = try self.parseWrittenType();
            const literal = try self.parseStructLiteral(start);
            try self.builder.markStructLiteralHead(literal, head);
            named_head = head;
            break :blk literal;
        } else if (pending_marker != .none and self.cursor.at(.star))
            try self.parseUnary()
        else
            try self.parsePrimary();
        m.operand();

        // Only something that denotes a value takes a suffix. A construct that
        // ends in a block does not: `while c { } (e)` is a loop and then an
        // expression, and reading the `(` as an argument list would make the
        // two one call -- which parses, and means something else entirely.
        if (!canBePostfixed(self.builder.exprTag(base))) return self.finishArgumentMarker(base, pending_marker);

        // Whether everything read so far is names and dots. A path is what a
        // head may be, and what a head may be is what decides the one form
        // below that reads a `?` as part of a call rather than as a suffix.
        // Tracked as it is read rather than walked back over: the loop is
        // where each suffix is known, and a walk would be a second reader of
        // the shape this one builds.
        var path = named_head == null and self.builder.exprTag(base) == .name_ref;

        while (true) {
            if (self.finishedAtALineBreak()) return self.finishArgumentMarker(base, pending_marker);
            if (self.cursor.at(.dot)) {
                const dot = self.cursor.current();
                _ = self.cursor.advance();
                const name = self.cursor.current();
                const named = self.cursor.eat(.identifier) != null;
                path = path and named;
                if (!named) {
                    try self.reportAt(.s_name, name, "expected a name after `.`", "a `.` selects a part");
                }
                if (!m.wrap()) return self.tooDeeplyNested(dot);
                base = try self.builder.addUnary(.field, name, self.rangeFrom(start), base);

                // A selection with no name is still a selection: the `.` was
                // written and what it selects from is complete, so throwing
                // the whole thing away would leave the tree with no record
                // that anything was selected -- and the value in front of the
                // dot unresolved and untyped, which is what an editor asked at
                // that point has to read.
                //
                // The chain stops here. The token standing where the name
                // belongs was not read, and going round again would read it as
                // a call or an index, which is this deciding it means something
                // nobody wrote.
                if (!named) return self.finishArgumentMarker(base, pending_marker);
                continue;
            }
            if (self.cursor.at(.l_paren)) {
                const paren = self.cursor.current();
                base = try self.parseCall(if (pending_marker != .none) pending_marker else start, base);
                if (pending_marker != .none) {
                    self.builder.markCall(base);
                    start = pending_marker;
                    pending_marker = .none;
                }
                path = false;
                m.operand();
                if (!m.wrap()) return self.tooDeeplyNested(paren);
                continue;
            }
            // A bracket after a value is an index. After a path, or directly
            // before a call after a name or a selection, it may instead hold a
            // function's type arguments. Which of the two it is depends on
            // what the head names, which is known only after resolution and,
            // for a method, after checking, so where the contents read both
            // ways both readings are kept.
            if (self.cursor.at(.l_bracket)) {
                const after_path = path;
                path = false;
                const open = self.cursor.current();
                const close = self.bracketMayHoldTypes(base, open, after_path);
                const types: TypeReading = if (close) |end| try self.tryTypeList(end) else .none;
                const idx = switch (types) {
                    .types => try self.tryIndex(open, close.?),
                    .none => try self.parseIndex(),
                    .too_deep => try self.skipTooDeepBracket(open, close.?),
                };
                if (!m.wrap()) return self.tooDeeplyNested(open);
                base = try self.builder.addBinary(.index, open, self.rangeFrom(start), base, idx);
                if (types == .types) try self.builder.addBracketTypes(base, types.types);
                continue;
            }
            // In this loop rather than a production of its own, which is what
            // makes `f()?.g()` and `a?.b?` compose without a rule per order.
            //
            // `Name?(e)` is the one exception: a call head is a name or a path
            // to one, so a path immediately followed by `?(` has exactly one
            // reading -- the fallible construction form -- and not `?`
            // applied to the path and the result called, which nothing a name
            // could name would ever produce. A newline between the `?` and the
            // `(` still ends the statement, the same as any other postfix.
            //
            // A path rather than a bare name, because a type is named through
            // the module declaring it as readily as by a word in scope, and
            // which spelling was used decides nothing about what is built.
            if (self.cursor.at(.question)) {
                const mark = self.cursor.current();
                const may_construct = path and self.cursor.peekAt(1) == .l_paren;
                _ = self.cursor.advance();
                if (may_construct and self.cursor.at(.l_paren) and !self.cursor.precededByNewline()) {
                    const paren = self.cursor.current();
                    base = try self.parseCall(if (pending_marker != .none) pending_marker else start, base);
                    if (pending_marker != .none) {
                        self.builder.markCall(base);
                        start = pending_marker;
                        pending_marker = .none;
                    }
                    path = false;
                    self.builder.markFallible(base);
                    m.operand();
                    if (!m.wrap()) return self.tooDeeplyNested(paren);
                    continue;
                }
                if (!m.wrap()) return self.tooDeeplyNested(mark);
                base = try self.builder.addUnary(.try_, mark, self.rangeFrom(start), base);
                path = false;
                continue;
            }
            return self.finishArgumentMarker(base, pending_marker);
        }
    }

    /// The index inside a bracket and the `]` that closes it, the cursor on
    /// the `[`.
    fn parseIndex(self: *Parser) std.mem.Allocator.Error!ExprId {
        _ = self.cursor.advance();
        self.indexes += 1;
        const idx = try self.parseFull();
        self.indexes -= 1;
        if (self.cursor.eat(.r_bracket) == null) {
            try self.reportAt(
                .s_bracket,
                self.cursor.current(),
                "expected `]`",
                "an index is written `a[i]`",
            );
        }
        return idx;
    }

    /// The `]` closing a bracket whose contents may be a function's type
    /// arguments, or null where the bracket can only index. A bracket after a
    /// name or a selection may, directly before a call's `(` on its line; a
    /// bracket after a path of names may without a call, since it can name a
    /// function as a value, `create[UInt8]`.
    fn bracketMayHoldTypes(self: *Parser, base: ExprId, open: TokenId, after_path: bool) ?TokenId {
        switch (self.builder.exprTag(base)) {
            .name_ref, .field => {},
            else => return null,
        }
        const close = self.delimiterEnd(open) orelse return null;
        if (after_path) return close;
        var after = self.cursor;
        after.seek(@intCast(close.index() + 1));
        if (after.precededByNewline() or !after.at(.l_paren)) return null;
        return close;
    }

    /// A reading of a bracket's contents that is kept only if it reads them
    /// whole, from the `[` through `close`, without a diagnostic. A reading
    /// that does not fit leaves no rows, no diagnostics and no parser state
    /// behind, and the cursor where it started.
    const Attempt = struct {
        saved: Parser,
        checkpoint: Ast.Builder.Checkpoint,
        quiet: Sink,
        /// Whether the reading ran past the nesting limit, which reading the
        /// same tokens another way would run past too.
        too_deep: bool = false,

        fn begin(self: *Attempt, parser: *Parser) void {
            self.* = .{ .saved = parser.*, .checkpoint = parser.builder.checkpoint(), .quiet = Sink.init(parser.sink.arena) };
            parser.sink = &self.quiet;
        }

        /// Whether the reading fits. A reading that does not is undone
        /// entirely. One that does keeps its rows, and keeps the parser past
        /// the `]` unless `rewind` asks for it back on the `[`.
        fn finish(self: *Attempt, parser: *Parser, close: TokenId, rewind: bool) bool {
            for (self.quiet.list.items) |said| {
                if (said.code == .s_nesting) self.too_deep = true;
            }
            var after = self.saved.cursor;
            after.seek(@intCast(close.index() + 1));
            const fits = self.quiet.list.items.len == 0 and parser.cursor.index == after.index;
            if (fits and !rewind) {
                parser.sink = self.saved.sink;
                return true;
            }
            parser.* = self.saved;
            if (!fits) parser.builder.rollback(self.checkpoint);
            return fits;
        }
    };

    const TypeReading = union(enum) {
        types: node.TypeRefRange,
        none,
        too_deep,
    };

    /// The bracket's contents as a nonempty list of written types, where they
    /// read as one. The cursor stays on the `[`.
    ///
    /// **Bound:** the attempt reads the bracket's contents once. A bracket
    /// that may hold types -- one before a call, or one after a path such as
    /// `items[i]` -- nested inside another is read again by each enclosing
    /// bracket's attempt, so nested brackets cost their contents times their
    /// nesting depth, and every bracket after a path is read twice. The depth is at most
    /// `max_nesting`, which `parseTypeArgs` and the expression parser enforce
    /// by refusing to descend further; a reading refused that way is
    /// `.too_deep`, and the bracket is not read again.
    fn tryTypeList(self: *Parser, close: TokenId) std.mem.Allocator.Error!TypeReading {
        var attempt: Attempt = undefined;
        attempt.begin(self);
        const args = try self.parseTypeArgs();
        if (!attempt.finish(self, close, true)) return if (attempt.too_deep) .too_deep else .none;
        if (args.len() == 0) return .none;
        return .{ .types = args };
    }

    /// A bracket whose type reading ran past the nesting limit. Reported once,
    /// as every bracket too deep is, and stepped over whole: reading it as an
    /// index would descend just as far and report each level it gave up on.
    fn skipTooDeepBracket(self: *Parser, open: TokenId, close: TokenId) std.mem.Allocator.Error!ExprId {
        if (!self.reported_nesting) {
            self.reported_nesting = true;
            try self.reportAt(.s_nesting, open, "this expression nests too deeply", "the limit is 1000 levels");
        }
        self.cursor.seek(@intCast(close.index() + 1));
        return self.builder.addLiteral(.err, open, .{ .start = open, .end = TokenId.at(close.index() + 1) });
    }

    /// The index reading of a bracket that also reads as types. Where the
    /// contents are no expression, the index is an error node nothing
    /// reports: whether that is a mistake depends on the head, which the
    /// checker reports once it knows.
    fn tryIndex(self: *Parser, open: TokenId, close: TokenId) std.mem.Allocator.Error!ExprId {
        var attempt: Attempt = undefined;
        attempt.begin(self);
        const idx = try self.parseIndex();
        if (attempt.finish(self, close, false)) return idx;
        self.cursor.seek(@intCast(close.index() + 1));
        return self.builder.addLiteral(.err, open, .{ .start = open, .end = TokenId.at(close.index() + 1) });
    }

    fn finishArgumentMarker(self: *Parser, base: ExprId, marker: TokenId) std.mem.Allocator.Error!ExprId {
        if (marker == .none) return base;
        return self.builder.addUnary(.marked, marker, self.rangeFrom(marker), base);
    }

    /// A braced block used as an arm.
    fn parseArm(self: *Parser) std.mem.Allocator.Error!ExprId {
        return self.parseBraced("an arm is a block");
    }

    /// `if c { … }` or `if c { … } else { … }`.
    ///
    /// The condition is brace-free: a `{` after it opens the arm, so there is
    /// no ambiguity between a condition and the block that follows it.
    fn parseConditional(self: *Parser) std.mem.Allocator.Error!ExprId {
        const start = self.cursor.current();
        _ = self.cursor.advance();

        const cond = try self.parseControlHeader();
        const then = try self.parseArm();

        const otherwise = if (self.eatElse() != null)
            try self.parseElseArm()
        else
            ExprId.none;

        return self.builder.addConditional(start, self.rangeFrom(start), cond, then, otherwise);
    }

    /// What follows `else`: a block, or another conditional.
    ///
    /// `else if` nests rather than chains. The tree is a conditional inside a
    /// conditional, which is exactly what it means, so no pass below needs a
    /// notion of a chain and the formatter prints the nesting back on the one
    /// line it was written on.
    ///
    /// Descent is counted here because it does not pass through `parseUnary`,
    /// where every other expression counts itself. A chain is flat in the
    /// source and deep in the tree, so an unbounded one would recurse as far
    /// as it is long.
    fn parseElseArm(self: *Parser) std.mem.Allocator.Error!ExprId {
        if (!self.cursor.at(.keyword_if)) return self.parseArm();

        if (self.depth == max_nesting) return self.tooDeeplyNested(self.cursor.current());
        self.depth += 1;
        self.deepest = @max(self.deepest, self.depth);
        defer self.depth -= 1;

        return self.parseConditional();
    }

    /// `while c { … }`. The condition is brace-free for the same reason a
    /// conditional's is: the `{` after it opens the body.
    fn parseWhile(self: *Parser) std.mem.Allocator.Error!ExprId {
        const start = self.cursor.current();
        _ = self.cursor.advance();

        const cond = try self.parseControlHeader();
        const body = try self.parseArm();

        return self.builder.addBinary(.while_, start, self.rangeFrom(start), cond, body);
    }

    /// `for x in xs { … }` or `for (i, x) in xs { … }`. The sequence is
    /// brace-free for the same reason a condition is: the `{` after it opens
    /// the body.
    ///
    /// The binder is a name, or a tuple pattern of names, and nothing else. An
    /// arbitrary pattern here would read as something to match each element
    /// against, which is a different feature and one the language does not
    /// have -- accepting one now would make adding it later a change in
    /// meaning rather than a change in what parses.
    ///
    /// Built call-shaped, with the sequence where a callee sits and the binder
    /// and the body in the run a call's arguments use: three children do not
    /// fit a payload holding two, and the run is where the third goes.
    fn parseFor(self: *Parser) std.mem.Allocator.Error!ExprId {
        const start = self.cursor.current();
        _ = self.cursor.advance();

        // `for read x` and `for inout x` observe the places rather than taking
        // them. The words are the ones a parameter uses for the same reason a
        // `match read`'s is: the binder is a lend, and `inout` is a lend the
        // body may write through.
        const walks: Expr.Tag = if (self.cursor.eat(.keyword_read) != null)
            .for_read
        else if (self.cursor.eat(.keyword_inout) != null)
            .for_inout
        else
            .for_;

        const at = self.cursor.current();
        const binder = if (self.cursor.at(.l_paren)) blk: {
            if (self.cursor.peekAt(1) != .r_paren) break :blk try self.parseTuplePattern();
            try self.reportNoPattern(at);
            _ = self.cursor.advance();
            _ = self.cursor.advance();
            break :blk try self.builder.addLiteral(.err, at, self.rangeFrom(at));
        } else blk: {
            const name = try self.expectName(.s_name, "expected a name", "a `for` binds each element to one name");
            break :blk if (name != .none)
                try self.builder.addLiteral(.name_ref, name, self.rangeFrom(name))
            else
                try self.errExpr(at);
        };

        if (self.cursor.eat(.keyword_in) == null) {
            try self.reportAt(.s_for, self.cursor.current(), "expected `in`", "a `for` names what it walks after `in`");
        }

        const sequence = try self.parseControlHeader();
        const body = try self.parseArm();

        const e = try self.builder.addCall(start, self.rangeFrom(start), sequence, &.{ binder, body }, &.{});
        self.builder.retag(e, walks);
        return e;
    }

    test "for (i, x) binds a tuple pattern, and an empty or malformed one is one report" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();

        for ([_][]const u8{ "for", "for read", "for inout" }) |head| {
            const text = try std.fmt.allocPrint(gpa, "fn f() -> UInt8 {{\n    let r = {s} (i, x) in xs {{}}\n    0\n}}\n", .{head});
            const source: Source = .{ .path = "t.lin", .text = text };
            var sink = Sink.init(gpa);
            var interner: Interner = .empty;
            const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
            const ast = try parse(gpa, &source, .from(0), tokens, &sink);
            const stmts = ast.blockStmts(ast.blockOf(ast.declBody(node.DeclId.at(0))));
            const walk = ast.stmtData(stmts[0]).init;
            const binder = ast.call(walk).args[0];
            try testing.expectEqual(Expr.Tag.tuple_pattern, ast.exprTag(binder));
            try testing.expectEqual(@as(usize, 2), ast.call(binder).args.len);
            try testing.expectEqual(@as(u32, 0), sink.error_count);
        }

        const cases = [_]struct { text: []const u8, codes: []const ?Code }{
            .{ .text = "for () in xs {}", .codes = &.{.s_match} },
            .{ .text = "for (i) in xs {}", .codes = &.{.s_tuple} },
            .{ .text = "for ((a, b), c) in xs {}", .codes = &.{} },
            .{ .text = "for (i, x in xs {}", .codes = &.{.s_paren} },
        };
        for (cases) |case| {
            const text = try std.fmt.allocPrint(gpa, "fn f() -> UInt8 {{\n    let r = {s}\n    let after = 0\n    after\n}}\n", .{case.text});
            try testing.expectEqualSlices(?Code, case.codes, try codesOf(gpa, text));
        }
        const helps = try helpsOf(gpa, "fn f() -> UInt8 {\n    for () in xs {}\n    0\n}\n");
        try testing.expectEqual(@as(usize, 1), helps.len);
        try testing.expectEqualStrings("the unit type has one value; write `_` to match it", helps[0]);
    }

    /// `loop { … }`. No condition: it ends only through `break`.
    fn parseLoop(self: *Parser) std.mem.Allocator.Error!ExprId {
        const start = self.cursor.current();
        _ = self.cursor.advance();
        const body = try self.parseArm();
        return self.builder.addUnary(.loop_, start, self.rangeFrom(start), body);
    }

    /// `break`, `break e`, or `continue`.
    ///
    /// A bare `break` is told from one carrying a value by what follows it: a
    /// token that can end an expression means there is none, and so does a
    /// newline. `break` and `}` are adjacent often enough that guessing wrong
    /// would be routine.
    ///
    /// The newline matters as much as the brace. A statement ends at one, and
    /// that has to include this statement -- otherwise `break` on one line and
    /// a statement on the next would read as `break` carrying that statement's
    /// value, which is what the `;` used to prevent and no longer does.
    fn parseJump(self: *Parser, tag: Expr.Tag) std.mem.Allocator.Error!ExprId {
        const start = self.cursor.current();
        _ = self.cursor.advance();

        if (tag == .continue_) {
            return self.builder.addLiteral(.continue_, start, self.rangeFrom(start));
        }

        const value = if (inExprFollow(self.cursor.peek()) or self.cursor.at(.comma) or self.cursor.precededByNewline())
            ExprId.none
        else
            try self.parseExpr(1);

        return self.builder.addUnary(tag, start, self.rangeFrom(start), value);
    }

    /// Parses a multi-line literal, which is a `\\` line and every `\\` line
    /// on the lines directly below it, as one `str_literal` whose range runs
    /// from the first line to the last.
    ///
    /// A line always runs to the end of its source line, so the next token is
    /// always on a later line; the literal takes it when it is another `\\`
    /// line. A blank line or a comment between two lines is refused rather
    /// than ending the literal, since the line below it could only be a
    /// second literal standing alone, and the literal carries on through it so
    /// that one mistake is one report. Anything else ends the literal, and the
    /// line break after its last line ends the statement as it does after any
    /// literal.
    fn parseStringLines(self: *Parser) std.mem.Allocator.Error!ExprId {
        const start = self.cursor.current();
        var last = self.cursor.advance();
        while (self.cursor.at(.string_line)) {
            const here = self.cursor.current();
            if (here.index() != last.index() + 1) {
                try self.reportAt(
                    .s_string,
                    TokenId.at(last.index() + 1),
                    "a comment interrupts a multi-line literal",
                    "move it above or below the literal",
                );
            } else if (self.cursor.newlinesBefore() > 1) {
                try self.reportAt(
                    .s_string,
                    here,
                    "a blank line interrupts a multi-line literal",
                    "the literal continues here; an empty line of text is written `\\\\`",
                );
            }
            last = self.cursor.advance();
        }
        return self.builder.addLiteral(.str_literal, start, .{ .start = start, .end = TokenId.at(last.index() + 1) });
    }

    /// `"a{x}b{y}c"`, whose pieces alternate text and value.
    ///
    /// The pieces are held as one run, `text, value, text, value, … text` --
    /// always odd, always beginning and ending with text, so nothing has to
    /// remember which kind sits at an index. A literal with no values at all
    /// never reaches here: the scanner gives that one token and it stays an
    /// ordinary literal.
    ///
    /// Each piece of text is a `str_literal` of its own, whose token is the
    /// `str_open`, `str_mid` or `str_close` it came from. That works because
    /// what a literal *means* is read by stripping a delimiter from each end,
    /// and all four spellings have one at each end.
    ///
    /// A construct rather than a rewrite into concatenation, for the reason
    /// [ADR 0067] gives for compound assignment: it carries evaluation order,
    /// and the formatter prints back what was written.
    fn parseInterpolation(self: *Parser) std.mem.Allocator.Error!ExprId {
        const start = self.cursor.current();

        var pieces: std.ArrayList(ExprId) = .empty;
        defer pieces.deinit(self.gpa);
        var formats: std.ArrayList(node.InterpolationFormat) = .empty;
        defer formats.deinit(self.gpa);

        while (true) {
            const piece = self.cursor.current();
            const closes = self.cursor.at(.str_close);
            _ = self.cursor.advance();
            try pieces.append(self.gpa, try self.builder.addLiteral(
                .str_literal,
                piece,
                .{ .start = piece, .end = TokenId.at(piece.index() + 1) },
            ));
            if (closes) break;

            // An empty interpolation has nothing to render and is a mistake
            // rather than an empty rendering, so it is reported where it was
            // written rather than becoming a piece that produces nothing.
            if (self.cursor.at(.str_mid) or self.cursor.at(.str_close)) {
                try self.reportAt(
                    .s_expr,
                    self.cursor.current(),
                    "an interpolation holds an expression",
                    "there is nothing between these braces",
                );
                try pieces.append(self.gpa, try self.builder.addLiteral(
                    .err,
                    self.cursor.current(),
                    .{ .start = self.cursor.current(), .end = self.cursor.current() },
                ));
                try formats.append(self.gpa, .display);
                continue;
            }

            try pieces.append(self.gpa, try self.parseFull());

            var format: node.InterpolationFormat = .display;
            if (self.cursor.at(.colon)) {
                const colon = self.cursor.advance();
                if (self.cursor.at(.format_spec)) {
                    const spec = self.cursor.advance();
                    switch (format_spec.parse(self.cursor.textOf(spec))) {
                        .format => |parsed| format = parsed,
                        .refused => |refusal| try self.reportAt(.s_format, spec, refusal.message, refusal.help),
                    }
                } else {
                    try self.reportAt(
                        .s_format,
                        colon,
                        "a colon in an interpolation begins a format spec",
                        "write the spec after `:`, as in `:>4` or `:?`, or remove the colon",
                    );
                }
            }
            try formats.append(self.gpa, format);

            if (!self.cursor.at(.str_mid) and !self.cursor.at(.str_close)) {
                try self.reportAt(
                    .s_string,
                    self.cursor.current(),
                    "expected `}`",
                    "this interpolation is never closed",
                );
                // The run still ends with text, so an error node stands in
                // for the text that would have closed it.
                try pieces.append(self.gpa, try self.builder.addLiteral(
                    .err,
                    self.cursor.current(),
                    .{ .start = self.cursor.current(), .end = self.cursor.current() },
                ));
                break;
            }
        }

        return self.builder.addInterpolation(start, self.rangeFrom(start), pieces.items, formats.items);
    }

    /// `f(a, b)`. The callee has already been parsed, because a name is a name
    /// until the `(` after it says otherwise.
    ///
    /// `f(a, b: 2)`. An argument may restate the parameter it fills: `name`
    /// is one token of lookahead -- an identifier immediately followed by
    /// `:` -- checked before `parseFull` runs, so `mutate(buffer: &scratch)`
    /// takes `buffer` as the name and parses `&scratch` as the value, and
    /// `f(a.b: 3)` never reads `a.b` as one (the `.` after `a` fails the
    /// lookahead, so the argument is positional and the `:` is left for
    /// recovery).
    ///
    /// Once an argument is named, every later argument is: a positional
    /// argument after a named one is `[S-Args]`, reported and kept, per the
    /// infallible frontend.
    fn parseCall(self: *Parser, start: TokenId, callee: ExprId) std.mem.Allocator.Error!ExprId {
        _ = self.cursor.advance(); // (

        var args: std.ArrayList(ExprId) = .empty;
        defer args.deinit(self.gpa);
        var names: std.ArrayList(TokenId) = .empty;
        defer names.deinit(self.gpa);
        var naming = false;

        while (!self.cursor.atEnd() and !self.cursor.at(.r_paren)) {
            const before = self.cursor.current();

            var name: TokenId = .none;
            if (self.cursor.at(.identifier) and self.cursor.peekAt(1) == .colon) {
                name = self.cursor.current();
                _ = self.cursor.advance();
                _ = self.cursor.advance(); // :
                naming = true;
            } else if (naming) {
                try self.reportAt(
                    .s_args,
                    self.cursor.current(),
                    "a positional argument follows a named one",
                    "name this argument, or move it before the names",
                );
            }

            try args.append(self.gpa, try self.parseFull());
            try names.append(self.gpa, name);

            if (self.cursor.eat(.comma) == null) break;
            if (self.cursor.current() == before) _ = self.cursor.advance();
        }

        if (self.cursor.eat(.r_paren) == null) {
            try self.reportAt(.s_paren, self.cursor.current(), "expected `)`", "this call is never closed");
        }
        return self.builder.addCall(start, self.rangeFrom(start), callee, args.items, names.items);
    }

    /// `copy(p)`, the only duplication in the language.
    ///
    /// Spelled like a call and is not one: what it takes is a place rather
    /// than a value, and there is no function it could be. Written out rather
    /// than inserted, so that writing one asserts something -- a copy that can
    /// appear without being written makes every written one say nothing.
    fn parseCopy(self: *Parser) std.mem.Allocator.Error!ExprId {
        const start = self.cursor.current();
        _ = self.cursor.advance();

        if (self.cursor.eat(.l_paren) == null) {
            try self.reportAt(.s_paren, self.cursor.current(), "expected `(`", "a copy names what it copies");
            return self.errExpr(start);
        }

        const of = try self.parseFull();
        if (self.cursor.eat(.r_paren) == null) {
            try self.reportAt(.s_paren, self.cursor.current(), "expected `)`", "this copy is never closed");
        }

        const e = try self.builder.addUnary(.copy_, start, self.rangeFrom(start), of);
        return e;
    }

    /// `panic(message)`, dedicated termination syntax rather than a call.
    fn parsePanic(self: *Parser) std.mem.Allocator.Error!ExprId {
        const start = self.cursor.current();
        _ = self.cursor.advance();

        if (self.cursor.eat(.l_paren) == null) {
            try self.reportAt(.s_paren, self.cursor.current(), "expected `(`", "a panic names its message");
            return self.errExpr(start);
        }

        const message = try self.parseFull();
        var valid = self.builder.exprTag(message) != .err;
        if (self.cursor.eat(.r_paren) == null) {
            try self.reportAt(.s_paren, self.cursor.current(), "expected `)`", "this panic is never closed");
            valid = false;
        }

        if (!valid) return self.builder.addLiteral(.err, start, self.rangeFrom(start));
        return self.builder.addUnary(.panic, start, self.rangeFrom(start), message);
    }

    /// `embed("path")` or `embed_bytes("path")`: a file the loader reads when
    /// the program is compiled. The loader reads the path before any name is
    /// resolved, so the argument is one quoted or raw string literal and
    /// nothing a name or a computation could stand for ([S-Embed]).
    ///
    /// The node is a leaf whose main token is that literal. A refused argument
    /// is skipped to its closing `)` without building nodes for it, so no
    /// expression the program cannot reach is left in the tree.
    fn parseEmbed(self: *Parser) std.mem.Allocator.Error!ExprId {
        const start = self.cursor.current();
        const bytes = self.cursor.peek() == .keyword_embed_bytes;
        const word = if (bytes) "embed_bytes" else "embed";
        _ = self.cursor.advance();

        if (self.cursor.eat(.l_paren) == null) {
            // The word alone is the error node, and whatever follows it is read
            // as what follows any operand, so one missing `(` is one report.
            try self.reportAt(.s_paren, self.cursor.current(), "expected `(`", "the file is named in parentheses");
            return self.builder.addLiteral(.err, start, self.rangeFrom(start));
        }

        const argument = self.cursor.current();
        if (self.cursor.peek() == .string_literal and self.cursor.peekAt(1) == .r_paren) {
            _ = self.cursor.advance();
            _ = self.cursor.advance();
            return self.builder.addLiteral(if (bytes) .embed_bytes else .embed, argument, self.rangeFrom(start));
        }

        const compiled = "the file is read when the program is compiled, so its path is written here";
        const label: []const u8 = switch (self.cursor.peek()) {
            .r_paren => "name the file here, as a string literal",
            .str_open => "an interpolated path is computed when the program runs, and the file is read before",
            .string_line => "a path is one line, written as a quoted string literal",
            .string_literal => if (self.cursor.peekAt(1) != .comma)
                compiled
            else if (self.cursor.peekAt(2) == .r_paren)
                "remove the comma after the path"
            else
                "one file is embedded at a time",
            else => compiled,
        };
        const message = try std.fmt.allocPrint(self.sink.arena, "`{s}` takes one string literal naming the file", .{word});

        // Past what was written, to the `)` that closes it.
        var depth: u32 = 0;
        var last = argument;
        while (true) {
            switch (self.cursor.peek()) {
                .eof => break,
                .l_paren, .l_bracket, .l_brace => depth += 1,
                .r_paren, .r_bracket, .r_brace => {
                    if (depth == 0) break;
                    depth -= 1;
                },
                else => {},
            }
            last = self.cursor.advance();
        }
        const written: TokenRange = .{ .start = argument, .end = if (last == argument and self.cursor.current() == argument) argument else TokenId.at(last.index() + 1) };
        const span = self.cursor.spanOf(written);
        try self.sink.addError(.s_embed, self.file, if (span.start == span.end) self.cursor.spanAt(self.cursor.current()) else span, message, label);
        if (self.cursor.eat(.r_paren) == null) {
            try self.reportAt(.s_paren, self.cursor.current(), "expected `)`", "this embed is never closed");
        }
        return self.builder.addLiteral(.err, start, self.rangeFrom(start));
    }

    /// `match e { P => body, … }`.
    ///
    /// A pattern is a name — a variant, or `_` — so it is parsed as one and
    /// read as a variant under the scrutinee's enum rather than as a value in
    /// scope. That is the distinction `Colour.Red` already draws against a
    /// bare name, and it is what lets an arm's pattern stay a `name_ref` when
    /// payloads make it carry binders.
    fn parseMatch(self: *Parser) std.mem.Allocator.Error!ExprId {
        const start = self.cursor.current();
        _ = self.cursor.advance();

        // `match read k` observes rather than takes apart. The word is the
        // same one a parameter uses for the same reason: it is a lend.
        const lends = self.cursor.eat(.keyword_read) != null;

        const scrutinee = try self.parseControlHeader();

        var items: std.ArrayList(ExprId) = .empty;
        defer items.deinit(self.gpa);

        if (self.cursor.eat(.l_brace) == null) {
            try self.reportAt(.s_brace, self.cursor.current(), "expected `{`", "a match lists its arms");
            return self.builder.addCall(start, self.rangeFrom(start), scrutinee, items.items, &.{});
        }

        while (!self.cursor.atEnd() and !self.cursor.at(.r_brace)) {
            const before = self.cursor.current();

            const pt = self.cursor.current();
            if (!self.atArmPattern()) {
                try self.reportNoPattern(pt);
                while (!self.cursor.atEnd() and !self.cursor.at(.r_brace) and self.cursor.eat(.comma) == null) {
                    _ = self.cursor.advance();
                }
                continue;
            }
            try items.append(self.gpa, try self.parseArmPattern());

            if (self.cursor.eat(.fat_arrow) == null) {
                try self.reportAt(.s_match, self.cursor.current(), "expected `=>`", "an arm separates its pattern from its body");
            }

            // An arm's body is a block or an expression, as an `if` arm's
            // already is. An empty block computes nothing and has the value
            // `()`, so `=> {}` is an arm that does nothing.
            try items.append(self.gpa, if (self.cursor.at(.l_brace))
                try self.parseBraced("this arm is never closed")
            else
                try self.parseFull());

            // A comma separates arms wherever they sit, and is optional only
            // after the last. What ends the list is the brace, so an arm's own
            // shape decides nothing about what may follow it -- which is the
            // rule every other delimited list already follows.
            if (self.cursor.eat(.comma) == null and !self.cursor.at(.r_brace)) {
                // A `\\` line takes the rest of its line, so a comma written
                // after an arm's multi-line body is text. The block form puts
                // the comma after the block's `}`.
                const label = if (self.cursor.previousTag() == .string_line)
                    "the arm above ends in a `\\\\` line, which runs to its end; write its body as a block: `=> {`, its lines, then `},`"
                else
                    "arms are separated by commas";
                try self.reportAt(.s_match, self.cursor.current(), "expected `,`", label);
            }
            if (self.cursor.current() == before) _ = self.cursor.advance();
        }

        if (self.cursor.eat(.r_brace) == null) {
            try self.reportAt(.s_match, self.cursor.current(), "expected `}`", "this match is never closed");
        }

        const e = try self.builder.addCall(start, self.rangeFrom(start), scrutinee, items.items, &.{});
        self.builder.retag(e, if (lends) .match_read else .match_);
        return e;
    }

    /// The patterns a variant's payload is taken apart with, or the pattern
    /// unchanged where it takes nothing apart.
    ///
    /// Each one is a pattern rather than an expression: an arbitrary
    /// expression here would read as a value to compare against, which is a
    /// different feature and one the language does not have.
    fn parseBinders(
        self: *Parser,
        start: TokenId,
        pattern: ExprId,
    ) std.mem.Allocator.Error!ExprId {
        if (self.cursor.eat(.l_paren) == null) return pattern;

        var names: std.ArrayList(ExprId) = .empty;
        defer names.deinit(self.gpa);

        while (!self.cursor.atEnd() and !self.cursor.at(.r_paren)) {
            const before = self.cursor.current();

            try names.append(self.gpa, try self.parseSubPattern());

            if (self.cursor.eat(.comma) == null) break;
            if (self.cursor.current() == before) _ = self.cursor.advance();
        }

        if (self.cursor.eat(.r_paren) == null) {
            try self.reportAt(.s_match, self.cursor.current(), "expected `)`", "this pattern is never closed");
        }

        // A binder list holds at least one name, which is what the grammar
        // spells. Written empty it is a pattern no rule below here reads as
        // one: `_()` took the catch-all branch on its text while the tag said
        // otherwise, so three passes read it as the catch-all and the fourth
        // did not -- and the editor grammars, which do spell the rule, could
        // not parse what this accepted.
        if (names.items.len == 0) {
            try self.reportAt(
                .s_match,
                start,
                "name what the variant carries, or drop the parentheses",
                "a pattern's binder list is never empty",
            );
        }
        return self.builder.addCall(start, self.rangeFrom(start), pattern, names.items, &.{});
    }

    /// Whether a `.` or a `(` after this expression belongs to it.
    ///
    /// Listed rather than caught by an `else`, so a tag added anywhere has to
    /// be classified before the build succeeds.
    fn canBePostfixed(tag: node.Expr.Tag) bool {
        return switch (tag) {
            // A literal is postfixed like a call's result is: `make().x` and
            // `[1, 2, 3][0]` both reach into something the expression itself
            // produced, and an index is the same kind of step as a field. An
            // interpolation is a value like any other, so `"{x}".length()`
            // reaches into one the same way. `copy(x)` closes at its `)` like
            // a call, so `copy(x).length()` applies the operation to the copy.
            .str_literal, .interp, .name_ref, .reflection_root, .field, .call, .lambda, .variant_ref, .struct_literal, .grouped, .index, .array_literal, .copy_, .tuple_literal => true,
            // `embed("x")` closes at its `)` like a call, so
            // `embed("x").length()` measures the file's text.
            .embed, .embed_bytes => true,
            .block,
            .conditional,
            .while_,
            .loop_,
            .match_,
            .match_read,
            .for_,
            .for_read,
            .for_inout,
            // `!f(x)` negates the call; `!f (x)` would be the same thing, so
            // nothing may attach to the negation itself.
            .not,
            .logical_and,
            .logical_or,
            .struct_pattern,
            .tuple_pattern,
            .param_argument,
            .borrow,
            .dereference,
            .panic,
            .assign,
            .add_assign,
            .sub_assign,
            .mul_assign,
            .div_assign,
            .rem_assign,
            .break_,
            .continue_,
            .return_,
            .marked,
            // Asked once, of what `parsePrimary` returned, and a `?` node is
            // only ever built inside the suffix loop -- so this arm is about
            // where a suffix may *start*, and a `?` never starts one.
            .try_,
            // Built around a finished initializer, never by `parsePrimary`.
            .unwrap_else,
            .negate,
            // `a[^k]` counts back by `k`, and a suffix after the caret belongs
            // to `k`: the caret is read around a finished operand, so nothing
            // attaches to the counting itself.
            .from_end,
            .int_literal,
            .float_literal,
            .bool_literal,
            .unit_literal,
            .add,
            .sub,
            .mul,
            .div,
            .rem,
            .eq,
            .ne,
            .lt,
            .le,
            .gt,
            .ge,
            .range,
            .err,
            => false,
        };
    }

    /// `Type { x = 1, y }` or `.{ x = 1, y, ..base }`.
    ///
    /// The names and the values sit in the side array in pairs, which is what
    /// a match's arms already do -- so no payload shape is added and the
    /// reader that walks a call's arguments walks these too. The base sits in
    /// the callee slot, which a literal has no other use for.
    ///
    /// The base comes last. An item written after it is reported once and
    /// still parsed, so a misplaced base costs one error rather than the rest
    /// of the literal.
    fn parseStructLiteral(self: *Parser, start: TokenId) std.mem.Allocator.Error!ExprId {
        _ = self.cursor.advance(); // {

        var items: std.ArrayList(ExprId) = .empty;
        defer items.deinit(self.gpa);
        var base = ExprId.none;
        var misplaced = false;

        while (!self.cursor.atEnd() and !self.cursor.at(.r_brace)) {
            const before = self.cursor.current();

            if (base != ExprId.none and !misplaced) {
                misplaced = true;
                try self.reportAt(.s_base_last, before, "the base of a structure literal comes last", "write this before `..`");
            }

            const dots = self.cursor.current();
            if (self.cursor.eat(.dot_dot) != null) {
                const value = try self.parseFull();
                if (base == ExprId.none) {
                    base = value;
                } else {
                    // A second base keeps its place in the tree behind a
                    // label that names no field, so its names are still
                    // resolved and reported like any value's.
                    try items.append(self.gpa, try self.builder.addLiteral(.err, dots, .{ .start = dots, .end = TokenId.at(@intCast(dots.index() + 1)) }));
                    try items.append(self.gpa, value);
                }
                if (self.cursor.eat(.comma) == null) break;
                continue;
            }

            // `.name = value`, the removed dotted spelling, is reported once
            // and then read as the field it names.
            if (self.cursor.at(.dot) and self.cursor.peekAt(1) == .identifier) {
                try self.reportAt(.s_field, self.cursor.current(), "expected a field name", "a literal names every field it gives");
                _ = self.cursor.advance();
            }
            const fname = self.cursor.current();
            const named = self.cursor.eat(.identifier) != null;
            if (!named) {
                // The value still pairs with a label, one that names no field,
                // so the fields after it keep their own names.
                try self.reportAt(.s_field, fname, "expected a field name", "a literal names every field it gives");
                try items.append(self.gpa, try self.builder.addLiteral(.err, fname, self.rangeFrom(fname)));
                _ = self.cursor.eat(.equal);
                try items.append(self.gpa, try self.parseFull());
            } else if (self.cursor.at(.comma) or self.cursor.at(.r_brace)) {
                try items.append(self.gpa, try self.builder.addLiteral(.name_ref, fname, self.rangeFrom(fname)));
                try items.append(self.gpa, try self.builder.addLiteral(.name_ref, fname, self.rangeFrom(fname)));
            } else {
                try items.append(self.gpa, try self.builder.addLiteral(.name_ref, fname, self.rangeFrom(fname)));
                if (self.cursor.eat(.equal) == null) {
                    try self.reportAt(.s_equals, self.cursor.current(), "expected `=`", "a field is given a value");
                }
                try items.append(self.gpa, try self.parseFull());
            }

            if (self.cursor.eat(.comma) == null) break;
            if (self.cursor.current() == before) _ = self.cursor.advance();
        }

        if (self.cursor.eat(.r_brace) == null) {
            try self.reportAt(.s_brace, self.cursor.current(), "expected `}`", "this literal is never closed");
        }

        const e = try self.builder.addCall(start, self.rangeFrom(start), base, items.items, &.{});
        self.builder.retag(e, .struct_literal);
        return e;
    }

    /// Scan only shorthand names and separators. An alias initializer or
    /// explicit convention before a name distinguishes captures from array elements,
    /// so nested expressions are never scanned again by this lookahead.
    fn startsCaptureLambda(self: *const Parser) bool {
        var cursor = self.cursor;
        _ = cursor.advance();
        while (!cursor.atEnd()) {
            if (cursor.at(.r_bracket)) {
                _ = cursor.advance();
                return cursor.at(.pipe) or cursor.at(.pipe_pipe);
            }
            if (cursor.at(.keyword_read) or cursor.at(.keyword_sink) or cursor.at(.keyword_inout))
                return cursor.peekAt(1) == .identifier;
            if (cursor.eat(.identifier) == null) return false;
            if (cursor.at(.equal)) return true;
            if (cursor.eat(.comma) == null) {
                if (!cursor.at(.r_bracket)) return false;
            }
        }
        return false;
    }

    /// `[a, b, c]`, whose type is the one expected of it.
    ///
    /// Built call-shaped and retagged, which is how a `match` is assembled
    /// too: same payload, same side array, and one arrangement rather than a
    /// second that could disagree about where a run of operands lives.
    fn parseArrayLiteral(self: *Parser) std.mem.Allocator.Error!ExprId {
        const start = self.cursor.current();
        _ = self.cursor.advance();

        var elements: std.ArrayList(ExprId) = .empty;
        defer elements.deinit(self.gpa);

        while (!self.cursor.at(.r_bracket) and !self.cursor.at(.eof)) {
            try elements.append(self.gpa, try self.parseFull());
            if (self.cursor.eat(.comma) == null) break;
        }

        if (self.cursor.eat(.r_bracket) == null) {
            try self.reportAt(
                .s_bracket,
                self.cursor.current(),
                "expected `]`",
                "an array literal is written `[a, b, c]`",
            );
        }

        const id = try self.builder.addCall(start, self.rangeFrom(start), .none, elements.items, &.{});
        self.builder.retag(id, .array_literal);
        return id;
    }

    fn parsePrimary(self: *Parser) std.mem.Allocator.Error!ExprId {
        const start = self.cursor.current();

        switch (self.cursor.peek()) {
            .pipe, .pipe_pipe, .keyword_read, .keyword_inout, .keyword_sink => return self.parseLambda(),
            .keyword_if => return self.parseConditional(),
            .l_bracket => return if (self.startsCaptureLambda()) self.parseLambda() else self.parseArrayLiteral(),
            .keyword_while => return self.parseWhile(),
            .keyword_for => return self.parseFor(),
            .keyword_match => return self.parseMatch(),
            .keyword_copy => return self.parseCopy(),
            .keyword_panic => return self.parsePanic(),
            .keyword_embed, .keyword_embed_bytes => return self.parseEmbed(),
            .keyword_loop => return self.parseLoop(),
            .keyword_break => return self.parseJump(.break_),
            .keyword_return => return self.parseJump(.return_),
            .keyword_continue => return self.parseJump(.continue_),

            .keyword_true, .keyword_false => {
                _ = self.cursor.advance();
                return self.builder.addLiteral(.bool_literal, start, self.rangeFrom(start));
            },

            .int_literal => {
                _ = self.cursor.advance();
                return self.builder.addLiteral(.int_literal, start, self.rangeFrom(start));
            },
            .float_literal => {
                _ = self.cursor.advance();
                return self.builder.addLiteral(.float_literal, start, self.rangeFrom(start));
            },
            .string_literal => {
                _ = self.cursor.advance();
                return self.builder.addLiteral(.str_literal, start, self.rangeFrom(start));
            },
            .str_open => return self.parseInterpolation(),
            .string_line => return self.parseStringLines(),
            .identifier => {
                _ = self.cursor.advance();
                return self.builder.addLiteral(.name_ref, start, self.rangeFrom(start));
            },
            .keyword_reflect => {
                _ = self.cursor.advance();
                return self.builder.addLiteral(.reflection_root, start, self.rangeFrom(start));
            },

            // `.Red` and `.{ … }`, where the type is the one expected here.
            // One rule rather than two: a leading `.` means the type comes
            // from context, and what follows says which part of it.
            .dot => {
                _ = self.cursor.advance();
                if (self.cursor.at(.l_brace)) return self.parseStructLiteral(start);

                const variant = self.cursor.current();
                if (self.cursor.eat(.identifier) == null) {
                    try self.reportAt(.s_name, variant, "expected a variant name or `{`", "a leading `.` selects one");
                    return self.errExpr(start);
                }
                return self.builder.addUnary(.variant_ref, variant, self.rangeFrom(start), ExprId.none);
            },

            // A block is an expression, and its value is its last one. It
            // reaches here rather than only through the constructs that take
            // one, so `{ let x = 1 ⏎ x }` may stand wherever a value may --
            // which is what the grammar says a block is.
            .l_brace => return self.parseBraced("this block is never closed"),

            .l_paren => {
                _ = self.cursor.advance();
                // `()` is the unit value, spelled as its type is.
                if (self.cursor.eat(.r_paren) != null) {
                    return self.builder.addLiteral(.unit_literal, start, self.rangeFrom(start));
                }
                const inner = try self.parseFull();
                // The comma decides: `(x)` groups, and `(x, y)` is a tuple.
                if (self.cursor.at(.comma)) return self.parseTupleLiteral(start, inner);
                if (self.cursor.eat(.r_paren) == null) {
                    try self.reportAt(.s_paren, start, "unclosed `(`", "this group is never closed");
                }
                return self.builder.addUnary(.grouped, start, self.rangeFrom(start), inner);
            },
            else => return self.errExpr(start),
        }
    }

    /// The rest of `(a, b, …)`, from the comma after its first component.
    ///
    /// A comma before the `)` is a trailing comma, so `(a,)` holds one
    /// component and is refused by the arity check rather than read as a
    /// group. The node is built whatever its arity, so the tree holds what
    /// was written.
    fn parseTupleLiteral(self: *Parser, open: TokenId, first: ExprId) std.mem.Allocator.Error!ExprId {
        var components: std.ArrayList(ExprId) = .empty;
        defer components.deinit(self.gpa);
        try components.append(self.gpa, first);

        while (self.cursor.eat(.comma) != null) {
            if (self.cursor.at(.r_paren) or self.cursor.atEnd()) break;
            try components.append(self.gpa, try self.parseFull());
        }

        // A tuple missing a comma or its `)` may hold more than was read, so
        // its arity is not judged.
        if (self.cursor.eat(.r_paren) != null) {
            try self.checkTupleArity(open, components.items.len, one_component_help);
        } else if (!try self.skipPastMissingComma(open, "a tuple separates its components with commas")) {
            try self.reportAt(.s_paren, open, "unclosed `(`", "this tuple is never closed");
        }

        const id = try self.builder.addCall(open, self.rangeFrom(open), .none, components.items, &.{});
        self.builder.retag(id, .tuple_literal);
        return id;
    }

    test "a tuple literal is read after its first comma, and a malformed one is one report" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();

        const cases = [_]struct { text: []const u8, codes: []const ?Code }{
            .{ .text = "let _t = (\n        1,\n        2,\n    )", .codes = &.{} },
            .{ .text = "let _t = (1, 2, 3, 4, 5, 6, 7, 8, 9)", .codes = &.{.s_tuple} },
            .{ .text = "let _t = (1, 2 3)", .codes = &.{.s_tuple} },
            .{ .text = "let _t = (1, 2", .codes = &.{.s_paren} },
        };
        for (cases) |case| {
            const text = try std.fmt.allocPrint(gpa, "fn f() -> UInt8 {{\n    {s}\n    let after = 0\n    after\n}}\n", .{case.text});
            try testing.expectEqualSlices(?Code, case.codes, try codesOf(gpa, text));
            const r = try parseWithDiagnostics(gpa, text);
            try testing.expectEqual(@as(usize, 2), std.mem.count(u8, r.dump, "let_decl"));
        }
    }

    /// Refuses a tuple of `count` components outside two to eight, at the
    /// `(` that opens it, with `few_help` for a count below two and the one
    /// help for a count above eight saying what to write instead. One report
    /// however far outside the bound, and the caller still builds the node,
    /// so a refused tuple costs one diagnostic.
    fn checkTupleArity(self: *Parser, open: TokenId, count: usize, few_help: []const u8) !void {
        if (node.isTupleArity(count)) return;
        try self.reportAt(.s_tuple, open, "a tuple has two to eight components", if (count < node.min_tuple_arity) few_help else too_many_help);
    }

    /// A tuple's component followed by neither `,` nor `)`. Where the `(` has
    /// a matching `)`, everything up to it is one mistake: reported here and
    /// skipped, so the tuple still closes where it was written. False where
    /// there is no such `)`, which leaves the tuple unclosed.
    fn skipPastMissingComma(self: *Parser, open: TokenId, help: []const u8) !bool {
        if (self.cursor.atEnd()) return false;
        const close = self.delimiterEnd(open) orelse return false;
        try self.reportAt(.s_tuple, self.cursor.current(), "expected `,` or `)`", help);
        self.cursor.seek(@intCast(close.index() + 1));
        return true;
    }

    test "each tuple refusal says what to write instead" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();

        const cases = [_]struct { text: []const u8, help: []const u8 }{
            .{ .text = "let _t = (7,)", .help = "`(x)` groups `x`; drop the comma, or add a second component" },
            .{ .text = "let _t = (1, 2, 3, 4, 5, 6, 7, 8, 9)", .help = "give a struct names past eight parts" },
            .{ .text = "let p: (UInt8,) = x", .help = "`(x)` groups `x`; drop the comma, or add a second component" },
            .{ .text = "let p: (A, A, A, A, A, A, A, A, A) = x", .help = "give a struct names past eight parts" },
            .{ .text = "let (a, 2 + 3) = x", .help = "a tuple pattern separates its binders with commas" },
            .{ .text = "let () = x", .help = "`()` has nothing to take apart" },
            .{ .text = "let (a) = x", .help = "bind one value with `let a = …`" },
            .{ .text = "let (a,) = x", .help = "bind one value with `let a = …`" },
            .{ .text = "let (a, b, c, d, e, f, g, h, i) = x", .help = "give a struct names past eight parts" },
            .{ .text = "let (c d) = x", .help = "a tuple pattern separates its binders with commas" },
            .{ .text = "let _t = (1, 2 3)", .help = "a tuple separates its components with commas" },
        };
        for (cases) |case| {
            const text = try std.fmt.allocPrint(gpa, "fn f() -> UInt8 {{\n    {s}\n    0\n}}\n", .{case.text});
            const helps = try helpsOf(gpa, text);
            try testing.expectEqual(@as(usize, 1), helps.len);
            try testing.expectEqualStrings(case.help, helps[0]);
        }
    }

    /// `..b`, `a..`, and bare `..`: an end has no consumer to give it meaning
    /// yet ([S-Range]). Reported once at `at` rather than through `errExpr`,
    /// whose generic "expected an expression" would say the same thing twice.
    fn reportOpenRangeEnd(self: *Parser, at: TokenId) !void {
        try self.reportAt(
            .s_range,
            at,
            "an open end awaits a consumer that gives it meaning",
            "`..b`, `a..`, and bare `..` have no consumer yet",
        );
    }

    /// `..b` and bare `..`: the lhs a range needs was never written. Consumes
    /// up to the nearest expression or statement boundary, preserving the
    /// statement after the missing endpoint.
    fn openRangeEnd(self: *Parser) std.mem.Allocator.Error!ExprId {
        const start = self.cursor.current();
        try self.reportOpenRangeEnd(start);
        _ = self.cursor.advance();
        while (!inExprFollow(self.cursor.peek()) and !self.atStatementBoundary()) {
            _ = self.cursor.advance();
        }
        return self.builder.addLiteral(.err, start, self.rangeFrom(start));
    }

    /// A region that could not be parsed.
    ///
    /// Consumes up to the nearest expression or statement boundary. A newline
    /// that ends a statement bounds the hole just as an explicit delimiter does.
    /// The parser never reaches past an unexpected token in search of an operand.
    fn errExpr(self: *Parser, start: TokenId) !ExprId {
        // An invalid token is a region the lexer has already diagnosed.
        // Reporting it again would describe one mistake twice, once as a byte
        // the lexer could not read and once as an expression that is missing
        // because of it.
        const already_diagnosed = self.cursor.peek() == .invalid;

        const e = try self.skipMalformed(start);
        const range = self.rangeFrom(start);
        if (!already_diagnosed) {
            try self.sink.addError(
                .s_expr,
                self.file,
                self.cursor.spanOf(range),
                "expected an expression",
                "this is not the start of an expression",
            );
        }
        return e;
    }

    /// Skips a region no production can read, from `start` to where an
    /// expression could end or a statement begin, and returns the error node
    /// covering it. Reports nothing: the caller has said what is wrong.
    fn skipMalformed(self: *Parser, start: TokenId) !ExprId {
        while (!inExprFollow(self.cursor.peek()) and !self.atStatementTokenBoundary()) {
            // A preceding statement's newline does not end this malformed
            // production before it has consumed any of its own tokens.
            if (self.cursor.current() != start and self.finishedAtALineBreak()) break;
            _ = self.cursor.advance();
        }
        return self.builder.addLiteral(.err, start, self.rangeFrom(start));
    }
};

// Makes every test build compile the tests `Parser` holds, including a build
// filtered to one of them, which would otherwise never look inside it.
comptime {
    _ = Parser;
}

fn parseToDump(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return (try parseWithDiagnostics(gpa, text)).dump;
}

const Parsed = struct { dump: []u8, errors: u32 };

/// Parses exactly the text given, for tests about what a program is.
fn parseProgramText(gpa: std.mem.Allocator, text: []const u8) !Parsed {
    const source: Source = .{ .path = "t.lin", .text = text };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);

    var out: std.Io.Writer.Allocating = .init(gpa);
    try dumpAst(&out.writer, &ast, @import("../syntax/program.zig").DeclarationSelection.all(ast.declCount()));
    return .{ .dump = out.written(), .errors = sink.error_count };
}

/// Parses a whole program. Text that does not begin a declaration is wrapped
/// in one, so a test about expression shape stays a test about expression
/// shape: an expression needs a function to live in, and saying so at every
/// call site would say it fifteen times.
fn parseWithDiagnostics(gpa: std.mem.Allocator, text: []const u8) !Parsed {
    const wrapped = if (std.mem.indexOf(u8, text, "fn ") != null)
        text
    else
        try std.fmt.allocPrint(gpa, "fn main() -> UInt8 {{ {s} }}", .{text});
    const source: Source = .{ .path = "t.lin", .text = wrapped };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);

    var out: std.Io.Writer.Allocating = .init(gpa);
    try dumpAst(&out.writer, &ast, @import("../syntax/program.zig").DeclarationSelection.all(ast.declCount()));
    return .{ .dump = out.written(), .errors = sink.error_count };
}

/// The rule name of every diagnostic a parse of `text` produced, in order.
/// A diagnostic carrying none is kept as `null` rather than dropped, so a test
/// asserting an exact list cannot pass because something unnamed slipped out.
fn codesOf(gpa: std.mem.Allocator, text: []const u8) ![]const ?Code {
    const source: Source = .{ .path = "t.lin", .text = text };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    _ = try parse(gpa, &source, .from(0), tokens, &sink);

    var codes: std.ArrayList(?Code) = .empty;
    for (sink.items()) |d| try codes.append(gpa, d.code);
    return codes.toOwnedSlice(gpa);
}

/// The primary label of every diagnostic a parse of `text` produced, in
/// order: what each report says to do.
fn helpsOf(gpa: std.mem.Allocator, text: []const u8) ![]const []const u8 {
    const source: Source = .{ .path = "t.lin", .text = text };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    _ = try parse(gpa, &source, .from(0), tokens, &sink);

    var helps: std.ArrayList([]const u8) = .empty;
    for (sink.items()) |d| try helps.append(gpa, if (d.primaryLabel()) |l| l.message else "");
    return helps.toOwnedSlice(gpa);
}

/// `open` repeated `n` times around `1`, closed by `close`, inside a `main`.
/// The wrappers stack, so the tree is `n + 1` tall.
fn nested(gpa: std.mem.Allocator, n: usize, open: []const u8, close: []const u8) ![]const u8 {
    var text: std.ArrayList(u8) = .empty;
    try text.appendSlice(gpa, "fn main() -> Int64 {\n    ");
    for (0..n) |_| try text.appendSlice(gpa, open);
    try text.appendSlice(gpa, "1");
    for (0..n) |_| try text.appendSlice(gpa, close);
    try text.appendSlice(gpa, "\n}\n");
    return text.toOwnedSlice(gpa);
}

/// `n` operands joined by `op`, inside a `main`. The chain folds left, so the
/// tree is `n` tall while the parse never nests more than a frame or two.
fn joined(gpa: std.mem.Allocator, n: usize, op: []const u8) ![]const u8 {
    var text: std.ArrayList(u8) = .empty;
    try text.appendSlice(gpa, "fn main() -> Int64 {\n    ");
    for (0..n) |i| {
        if (i != 0) try text.appendSlice(gpa, op);
        try text.appendSlice(gpa, "1");
    }
    try text.appendSlice(gpa, "\n}\n");
    return text.toOwnedSlice(gpa);
}

/// `x` under `n` `.f` suffixes, inside a `main`. Each suffix stacks a level
/// above the last, so the tree is `n + 1` tall.
fn suffixed(gpa: std.mem.Allocator, n: usize) ![]const u8 {
    var text: std.ArrayList(u8) = .empty;
    try text.appendSlice(gpa, "fn main() -> Int64 {\n    x");
    for (0..n) |_| try text.appendSlice(gpa, ".f");
    try text.appendSlice(gpa, "\n}\n");
    return text.toOwnedSlice(gpa);
}

/// A parameter annotated `Foo[Foo[…[u8]…]]`, whose written type is `n + 1`
/// levels of argument list deep.
fn nestedType(gpa: std.mem.Allocator, n: usize) ![]const u8 {
    var text: std.ArrayList(u8) = .empty;
    try text.appendSlice(gpa, "fn main(x: Foo");
    for (0..n) |_| try text.appendSlice(gpa, "[Foo");
    try text.appendSlice(gpa, "[UInt8]");
    for (0..n) |_| try text.appendSlice(gpa, "]");
    try text.appendSlice(gpa, ") -> Int64 { 1 }\n");
    return text.toOwnedSlice(gpa);
}

test "an expression at the nesting limit parses" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const codes = try codesOf(gpa, try nested(gpa, max_nesting - 1, "(", ")"));
    try testing.expectEqual(@as(usize, 0), codes.len);
}

test "an expression past the nesting limit is reported once, not crashed" {
    // Recursive descent uses a stack frame per level, and the stack is a
    // resource the language does not describe. Without the bound this aborted
    // somewhere between ten and fifteen thousand levels in a debug build, and
    // somewhere else in every other build -- a limit enforced by running out
    // rather than by a rule.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // One past the limit, so the pair with the test above pins the boundary
    // rather than bracketing it.
    for ([_]usize{ max_nesting, 50_000 }) |n| {
        const codes = try codesOf(gpa, try nested(gpa, n, "(", ")"));
        try testing.expectEqualSlices(?Code, &.{.s_nesting}, codes);
    }
}

test "a tuple nests to the limit a group does, and one past it is reported once" {
    // A tuple is one level, as a group is: its components are read one level
    // below the `(`, and the commas between them stack nothing.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    try testing.expectEqual(@as(usize, 0), (try codesOf(gpa, try nested(gpa, max_nesting - 1, "(1, ", ")"))).len);
    for ([_]usize{ max_nesting, 50_000 }) |n| {
        const codes = try codesOf(gpa, try nested(gpa, n, "(1, ", ")"));
        try testing.expectEqualSlices(?Code, &.{.s_nesting}, codes);
    }

    // A tuple type and a grouped type are each one level of written type, as
    // an argument list is: a parameter's type holds as many of any of them.
    // Past the limit the refused type still ends at its own `)`, so the types
    // enclosing it close where they were written.
    for ([_][]const u8{ "(UInt8, ", "(" }) |open| {
        try testing.expectEqual(@as(usize, 0), (try codesOf(gpa, try nestedParenType(gpa, max_nesting, open))).len);
        try testing.expectEqualSlices(?Code, &.{.s_nesting}, try codesOf(gpa, try nestedParenType(gpa, max_nesting + 1, open)));
    }
}

/// A parameter annotated with `n` parenthesised types around `UInt8`, each
/// opened by `open`: `(UInt8, (UInt8, …))` or `((…))`.
fn nestedParenType(gpa: std.mem.Allocator, n: usize, open: []const u8) ![]const u8 {
    var text: std.ArrayList(u8) = .empty;
    try text.appendSlice(gpa, "fn main(_x: ");
    for (0..n) |_| try text.appendSlice(gpa, open);
    try text.appendSlice(gpa, "UInt8");
    for (0..n) |_| try text.appendSlice(gpa, ")");
    try text.appendSlice(gpa, ") -> Int64 { 1 }\n");
    return text.toOwnedSlice(gpa);
}

test "brackets before calls past the nesting limit are reported once" {
    // Each bracket is read as types before it is read as an index; a type
    // reading that runs past the limit is the one report, rather than one
    // report per level the index reading would then give up on.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var inner: std.ArrayList(u8) = .empty;
    try inner.appendSlice(gpa, "0");
    for (0..400) |_| {
        const wrapped = try std.fmt.allocPrint(gpa, "g[[UInt8; {s}]](0)", .{inner.items});
        inner.clearRetainingCapacity();
        try inner.appendSlice(gpa, wrapped);
    }
    const text = try std.fmt.allocPrint(gpa, "fn main() -> UInt8 {{\n    {s}\n}}\n", .{inner.items});
    const codes = try codesOf(gpa, text);
    try testing.expectEqualSlices(?Code, &.{.s_nesting}, codes);
}

test "a chain of operators is bounded the same way" {
    // The count is kept where every expression passes through, so a form that
    // nests without a delimiter is bounded by the same rule rather than by a
    // second one that has to be remembered.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const codes = try codesOf(gpa, try nested(gpa, 50_000, "-", ""));
    try testing.expectEqualSlices(?Code, &.{.s_nesting}, codes);
}

test "a chain of binary operators is bounded by the tree it builds" {
    // A binary chain is read in a loop, one frame per operand, while the tree
    // it folds grows a level per operator. Counting frames bounds nothing
    // here: the tree reached the depth the later passes die at while the
    // parser was still two levels down.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Not a comparison: those are non-associative, so a chain of them is a
    // different diagnostic long before it is a deep one.
    for ([_][]const u8{ " + ", " * ", " && " }) |op| {
        const at = try codesOf(gpa, try joined(gpa, max_nesting, op));
        try testing.expectEqual(@as(usize, 0), at.len);

        const past = try codesOf(gpa, try joined(gpa, max_nesting + 1, op));
        try testing.expectEqualSlices(?Code, &.{.s_nesting}, past);
    }
}

test "a chain of selections is bounded by the tree it builds" {
    // The suffix loop stacks a `field` node per `.`, the same way the operator
    // loop stacks a binary one.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const at = try codesOf(gpa, try suffixed(gpa, max_nesting - 1));
    try testing.expectEqual(@as(usize, 0), at.len);

    const past = try codesOf(gpa, try suffixed(gpa, max_nesting));
    try testing.expectEqualSlices(?Code, &.{.s_nesting}, past);
}

test "an operand already read counts against the levels stacked above it" {
    // The height of a chain is the tallest operand plus the operators above
    // it, not the greater of the two. A count that only took the maximum
    // would accept a tree of a quarter million levels built from a thousand
    // chains of a thousand.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // `(1 + … + 1) + 1 + … + 1`: the parenthesised operand is `half + 1` tall
    // and every term after it stacks one more.
    const half = max_nesting / 2;
    var text: std.ArrayList(u8) = .empty;
    try text.appendSlice(gpa, "fn main() -> Int64 {\n    (");
    for (0..half) |i| {
        if (i != 0) try text.appendSlice(gpa, " + ");
        try text.appendSlice(gpa, "1");
    }
    try text.appendSlice(gpa, ")");
    const spare = max_nesting - (half + 1);
    for (0..spare) |_| try text.appendSlice(gpa, " + 1");

    const at = try codesOf(gpa, try std.fmt.allocPrint(gpa, "{s}\n}}\n", .{text.items}));
    try testing.expectEqual(@as(usize, 0), at.len);

    try text.appendSlice(gpa, " + 1");
    const past = try codesOf(gpa, try std.fmt.allocPrint(gpa, "{s}\n}}\n", .{text.items}));
    try testing.expectEqualSlices(?Code, &.{.s_nesting}, past);
}

test "a written type past the nesting limit is reported, not crashed" {
    // A written type is read by the same recursion an expression is and walked
    // by the same later passes, so it answers to the same number. Unbounded,
    // this ran the parser out of stack inside `parseTypeArgs`.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const at = try codesOf(gpa, try nestedType(gpa, max_nesting - 1));
    try testing.expectEqual(@as(usize, 0), at.len);

    for ([_]usize{ max_nesting, 50_000 }) |n| {
        const codes = try codesOf(gpa, try nestedType(gpa, n));
        try testing.expectEqualSlices(?Code, &.{.s_nesting}, codes);
    }
}

test "a callable type past the nesting limit remains dumpable" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var text: std.ArrayList(u8) = .empty;
    try text.appendSlice(gpa, "fn main(_outer: ");
    for (0..max_nesting + 1) |_| try text.appendSlice(gpa, "fn(read _x: ");
    try text.appendSlice(gpa, "UInt8");
    for (0..max_nesting + 1) |_| try text.appendSlice(gpa, ") -> UInt8");
    try text.appendSlice(gpa, ") -> UInt8 {\n    0\n}\n");

    const parsed = try parseWithDiagnostics(gpa, text.items);
    try testing.expect(parsed.errors >= 1);
}

test "a chain folded around a written type is not charged to the type" {
    // A type is counted from where it is written. What it is not counted
    // against is a level that nests nothing above it: a chain folds sideways
    // and no pass reading the type is inside it. Carrying the type's depth
    // back as though it were the operand's height made the two sum, and the
    // diagnostic then named the chain.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // A parenthesised block, so the chain has an operand a `let` can sit in;
    // the expression tree of that operand is a handful of levels whatever the
    // annotation says.
    const inChain = struct {
        fn f(a: std.mem.Allocator, deep_type: usize, terms: usize) ![]const u8 {
            var text: std.ArrayList(u8) = .empty;
            try text.appendSlice(a, "fn main() -> Int64 {\n    ({\n        let _x: Foo");
            for (0..deep_type) |_| try text.appendSlice(a, "[Foo");
            try text.appendSlice(a, "[UInt8]");
            for (0..deep_type) |_| try text.appendSlice(a, "]");
            try text.appendSlice(a, " = 1\n        1\n    })");
            for (0..terms) |_| try text.appendSlice(a, " + 1");
            try text.appendSlice(a, "\n}\n");
            return text.toOwnedSlice(a);
        }
    }.f;

    // Neither construct is within three hundred levels of the limit, and the
    // sum of the two is over it. Adding them refused this and named the chain.
    const codes = try codesOf(gpa, try inChain(gpa, 700, 400));
    try testing.expectEqual(@as(usize, 0), codes.len);

    // What the type is still charged for is what it is written inside: the
    // frames open above it are levels a later pass really does spend. Written
    // a few levels in, a type at the limit is over it -- and the diagnostic
    // names the type, whatever the chain around it is doing.
    const past = try codesOf(gpa, try inChain(gpa, max_nesting - 1, 400));
    try testing.expectEqualSlices(?Code, &.{.s_nesting}, past);
}

test "a missing operand becomes an err in that slot, not a lost statement" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try parseWithDiagnostics(arena.allocator(),
        \\fn main() -> UInt8 {
        \\    let x = 1 + ;
        \\    let y = 2;
        \\    2
        \\}
    );
    // The addition survives with an err right operand.
    try testing.expect(std.mem.indexOf(u8, r.dump, "add") != null);
    try testing.expect(std.mem.indexOf(u8, r.dump, "err") != null);
    // The following statement still parses.
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, r.dump, "let_decl"));
    try testing.expectEqual(@as(u32, 1), r.errors);
}

test "expression recovery preserves statements after a line break" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const source =
        \\fn main() -> UInt8 {
        \\    let first: UInt8 = 1 + / 2
        \\    let second: UInt8 = 3 + / 4
        \\    first + second
        \\}
    ;
    const parsed = try parseWithDiagnostics(gpa, source);
    try testing.expectEqual(@as(u32, 2), parsed.errors);
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, parsed.dump, "let_decl"));
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, parsed.dump, "name_ref"));
}

test "expression recovery preserves a following expression tail" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const parsed = try parseWithDiagnostics(arena.allocator(),
        \\fn main() -> UInt8 {
        \\    let first: UInt8 = 1 + / 2
        \\    first
        \\}
    );
    try testing.expectEqual(@as(u32, 1), parsed.errors);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, parsed.dump, "name_ref"));
}

test "expression recovery retains a malformed line after a complete statement" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    for ([_][]const u8{ "1\n/ 2", "1\n/ 2\n3", "1\n/ 2; 3", "1\n/ 2\nlet next = 3\nnext" }) |source| {
        const parsed = try parseWithDiagnostics(arena.allocator(), source);
        try testing.expectEqual(@as(u32, 1), parsed.errors);
        try testing.expectEqual(@as(usize, 1), std.mem.count(u8, parsed.dump, " err tokens "));
        try testing.expect(std.mem.indexOf(u8, parsed.dump, "\"2\"") == null);
        if (std.mem.indexOf(u8, source, "3") != null) {
            try testing.expect(std.mem.indexOf(u8, parsed.dump, "\"3\"") != null);
        }
    }
}

test "recovery never invents an operand" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // `a + / b` must not become add(a, b): the parser may not reach past `/`
    // looking for something that would fit.
    const r = try parseWithDiagnostics(arena.allocator(), "a + / b");
    try testing.expect(std.mem.indexOf(u8, r.dump, "err") != null);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, r.dump, "name_ref"));
}

test "an unclosed paren is bounded by end of input" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try parseWithDiagnostics(arena.allocator(), "(1 + ");
    try testing.expect(std.mem.indexOf(u8, r.dump, "grouped") != null);
    try testing.expect(r.errors >= 1);
}

test "one malformed region produces one diagnostic" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try parseWithDiagnostics(arena.allocator(), "fn main() -> UInt8 { let x = ; }");
    try testing.expectEqual(@as(u32, 1), r.errors);
}

test "a missing name is reported without losing the binding" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try parseWithDiagnostics(arena.allocator(), "let = 1;\nlet y = 2;\ny");
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, r.dump, "let_decl"));
    try testing.expect(r.errors >= 1);
}

test "a borrowed let pattern parses to the read destructuring statement" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try parseWithDiagnostics(arena.allocator(), "let read Label(raw) = label\nlet read { x, y: _ } = point\nlet Label(owned) = label\n0");
    try testing.expectEqual(@as(u32, 0), r.errors);
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, r.dump, "let_read_destructure"));
    try testing.expectEqual(@as(usize, 3), std.mem.count(u8, r.dump, "destructure"));
}

test "a borrowed let marker needs a pattern and a let" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // A name after `read` is refused and still binds, so what follows it
    // resolves; `var read` is refused as any destructuring `var` is.
    const named = try codesOf(arena.allocator(), "fn main() -> UInt8 {\n    let read other = 3\n    other\n}\n");
    try testing.expectEqualSlices(?Code, &.{.s_destructure}, named);
    const mutable = try codesOf(arena.allocator(), "fn main() -> UInt8 {\n    var read Point { x } = point\n    x\n}\n");
    try testing.expectEqualSlices(?Code, &.{.s_destructure}, mutable);

    const unnamed = try codesOf(arena.allocator(), "fn main() -> UInt8 {\n    let read = 3\n    0\n}\n");
    try testing.expectEqualSlices(?Code, &.{.s_name}, unnamed);

    const r = try parseWithDiagnostics(arena.allocator(), "let read other = 3\nother");
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, r.dump, "let_decl"));
}

test "a missing semicolon does not swallow the next statement" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try parseWithDiagnostics(arena.allocator(), "let x = 1\nlet y = 2;\ny");
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, r.dump, "let_decl"));
}

test "a binding whose initialiser was reported does not also want a semicolon" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // The unterminated string is the mistake; the missing semicolon is its
    // consequence, and reporting both describes one error twice.
    const r = try parseWithDiagnostics(arena.allocator(),
        \\fn main() -> UInt8 {
        \\    let s = "unterminated
        \\}
    );
    try testing.expectEqual(@as(u32, 1), r.errors);
}

test "a region the lexer already diagnosed is not diagnosed again" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // The lexer reports the invalid bytes; the parser must not also report a
    // missing expression caused by them.
    const r = try parseWithDiagnostics(arena.allocator(), "fn main() -> UInt8 { let x = ###; }");
    try testing.expectEqual(@as(u32, 1), r.errors);
    try testing.expect(std.mem.indexOf(u8, r.dump, "err") != null);
}

test "parsing terminates on adversarial input" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    for ([_][]const u8{ "((((", "+++", "let let let", ")))", "let = = =", "1 + + + 2", ";;;;", "let" }) |text| {
        const r = try parseWithDiagnostics(arena.allocator(), text);
        try testing.expect(r.dump.len > 0);
    }
}

test "an entry point with an annotated binding and a conversion" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // A conversion has no node of its own: it is a call, and which calls those
    // are is settled by what the callee name reaches.
    const got = try parseToDump(arena.allocator(),
        \\fn main() -> UInt8 {
        \\    let x: Int64 = 4;
        \\    UInt8(x) + 1
        \\}
    );
    try testing.expect(std.mem.indexOf(u8, got, "let_decl") != null);
    try testing.expect(std.mem.indexOf(u8, got, "call") != null);
}

test "a file that is not declarations is reported" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const r = try parseProgramText(arena.allocator(), "1 + 2");
    try testing.expectEqual(@as(u32, 1), r.errors);
    // Still a tree: the parser has no error path.
    try testing.expect(r.dump.len > 0);
}

test "a second declaration is a second declaration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // Once a program is a list, more than one declaration is the point rather
    // than a mistake.
    const r = try parseProgramText(arena.allocator(),
        \\fn main() -> UInt8 { 1 }
        \\fn other() -> UInt8 { 2 }
    );
    try testing.expectEqual(@as(u32, 0), r.errors);
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, r.dump, "decl function"));
}

test "an empty file parses to no declarations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // The parser has nothing to object to: that a program needs a `main` is a
    // rule about names, and the resolver reports it.
    const r = try parseProgramText(arena.allocator(), "");
    try testing.expectEqual(@as(u32, 0), r.errors);
    try testing.expectEqualStrings("program decls=0\n", r.dump);
}

test "recovery still bounds an error inside a braced body" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try parseWithDiagnostics(arena.allocator(),
        \\fn main() -> UInt8 {
        \\    let x = 1 + ;
        \\    2
        \\}
    );
    try testing.expectEqual(@as(u32, 1), r.errors);
    try testing.expect(std.mem.indexOf(u8, r.dump, "add") != null);
}

test "nested conversions parse" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const got = try parseToDump(arena.allocator(), "fn main() -> UInt8 { UInt8(Int64(4)) }");
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, got, "call"));
}

test "an unclosed body is reported and bounded" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const r = try parseWithDiagnostics(arena.allocator(), "fn main() -> UInt8 { 1 ");
    try testing.expect(r.errors >= 1);
    try testing.expect(r.dump.len > 0);
}

test "a bare block is an expression, not a region the parser cannot read" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try parseWithDiagnostics(arena.allocator(),
        \\fn main() -> UInt8 {
        \\    let a: UInt8 = {
        \\        let x: UInt8 = 1
        \\        x
        \\    }
        \\    a
        \\}
    );
    try testing.expectEqual(@as(u32, 0), r.errors);
    try testing.expect(std.mem.indexOf(u8, r.dump, "block") != null);
}

test "an unclosed bare block is reported, not swallowed" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try parseWithDiagnostics(arena.allocator(),
        \\fn main() -> UInt8 {
        \\    let a: UInt8 = {
        \\        1
        \\    a
        \\}
    );
    try testing.expect(r.errors >= 1);
}

test "a malformed statement does not swallow the closing brace" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const r = try parseWithDiagnostics(arena.allocator(),
        \\fn main() -> UInt8 {
        \\    let = 1
        \\    2
        \\}
    );
    // The binding has no name, so it is reported; recovery still stops at the
    // brace rather than consuming it and running the body into what follows.
    try testing.expect(r.errors >= 1);
    try testing.expect(std.mem.indexOf(u8, r.dump, "let_decl") != null);
}

test "multiplication binds tighter than addition" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const got = try parseToDump(arena.allocator(), "1 + 2 * 3");
    const add_at = std.mem.indexOf(u8, got, "add").?;
    const mul_at = std.mem.indexOf(u8, got, "mul").?;
    // The multiplication must be nested under the addition, not beside it.
    try testing.expect(add_at < mul_at);
}

test "addition is left associative" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // 1 - 2 - 3 parses as (1 - 2) - 3, so there are two subs and the deepest
    // literal on the right is 3.
    // Written out, so the extents are the real ones rather than the wrapper's.
    const r = try parseProgramText(arena.allocator(), "fn main() -> UInt8 { 1 - 2 - 3 }");
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, r.dump, "sub"));
    try testing.expect(std.mem.indexOf(u8, r.dump, "int_literal tokens 11..12 \"3\"") != null);
}

test "unary minus binds tighter than multiplication" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const got = try parseToDump(arena.allocator(), "-2 * 3");
    const mul_at = std.mem.indexOf(u8, got, "mul").?;
    const neg_at = std.mem.indexOf(u8, got, "negate").?;
    try testing.expect(mul_at < neg_at);
}

test "grouping survives into the tree" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const got = try parseToDump(arena.allocator(), "(1 + 2) * 3");
    try testing.expect(std.mem.indexOf(u8, got, "grouped") != null);
}

test "logical operators bind looser than comparison, and `!` tighter than both" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // `a < 2 && a > 0` groups the comparisons first; `!true && false` is
    // `(!true) && false`; and the whole thing is `(&&) || (&&)`.
    const got = try parseProgramText(gpa,
        \\fn main() -> UInt8 {
        \\    let a = 1;
        \\    let ok = a < 2 && a > 0 || !true && false;
        \\    if ok { 1 } else { 0 }
        \\}
    );
    try testing.expectEqual(@as(u32, 0), got.errors);
    try testing.expect(std.mem.indexOf(u8, got.dump, "logical_or") != null);
    try testing.expect(std.mem.indexOf(u8, got.dump, "logical_and") != null);
    try testing.expect(std.mem.indexOf(u8, got.dump, "not") != null);
}

test "a binding and a tail" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const got = try parseToDump(arena.allocator(), "let x = 42;\nx");
    try testing.expect(std.mem.indexOf(u8, got, "let_decl") != null);
    try testing.expect(std.mem.indexOf(u8, got, "name_ref") != null);
    try testing.expect(std.mem.startsWith(u8, got, "program decls="));
}

test "several bindings before the tail" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const got = try parseToDump(arena.allocator(), "let x = 1;\nlet y = 2;\nx + y");
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, got, "let_decl"));
    try testing.expect(std.mem.indexOf(u8, got, "add") != null);
}

/// The parser is total: it never fails, always returns a complete tree, and
/// always terminates. The last is the one a generator tests best -- a recovery
/// that consumes nothing loops forever, and no assertion catches that.
fn fuzzTotality(_: void, smith: *std.testing.Smith) anyerror!void {
    var buf: [256]u8 = undefined;
    const len = smith.slice(&buf);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const source: Source = .{ .path = "fuzz.lin", .text = buf[0..len] };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);

    // A tree always exists, however broken the input was, and every body it
    // does contain is a block.
    for (0..ast.declCount()) |i| {
        const body = ast.declBody(node.DeclId.at(@intCast(i)));
        if (body == ExprId.none) continue;
        try std.testing.expectEqual(node.Expr.Tag.block, ast.exprTag(body));
    }
}

test "fuzz: parsing any input terminates and yields a tree" {
    // Every input this property has ever failed on, replayed before any
    // new one is tried -- so a crash the fuzzer found once cannot come
    // back unnoticed, and a search starts where the last one got to.
    try std.testing.fuzz({}, fuzzTotality, .{ .corpus = @import("fuzz_corpus").parser });
}

test "every input the fuzzer found for this still passes" {
    // Replayed here as well as handed to the fuzzer, because the two run at
    // different times: a search runs nightly and on a push, and this runs
    // whenever anyone builds. A regression that only fails in CI is one
    // somebody finds after they have moved on.
    for (@import("fuzz_corpus").parser) |input| {
        var smith: std.testing.Smith = .{ .in = input };
        try fuzzTotality({}, &smith);
    }
}

test "a token that starts no expression does not stall the sequence" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // `)` may end an expression, so the recovery that looks for such a token
    // finds it immediately and consumes nothing. The loop over statements has
    // to step over it, or it re-parses the same token forever -- the parser
    // never fails, so nothing else will.
    //
    // A regression here does not fail: it hangs.
    for ([_][]const u8{
        "fn main() -> UInt8 { ) 0 }",
        "fn main() -> UInt8 { ; ; 0 }",
        "fn main() -> UInt8 { ) ) ) 0 }",
    }) |text| {
        const parsed = try parseWithDiagnostics(arena.allocator(), text);
        try testing.expect(parsed.dump.len > 0);
    }
}

test "a program may end without a tail" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const got = try parseToDump(arena.allocator(), "let x = 1;\n");
    try testing.expect(std.mem.indexOf(u8, got, "program decls=1") != null);
    try testing.expect(std.mem.indexOf(u8, got, "let_decl") != null);
}

test "empty input is an empty program" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try parseProgramText(arena.allocator(), "");
    try testing.expectEqualStrings("program decls=0\n", r.dump);
}

test "comments do not reach the tree" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const got = try parseToDump(arena.allocator(), "let x = 1; // note\nx");
    try testing.expect(std.mem.indexOf(u8, got, "comment") == null);
}

test "a binding is one production whether or not it is mutable" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const immutable = try parseWithDiagnostics(gpa, "fn main() -> UInt8 { let x: UInt8 = 1; x }");
    const mutable = try parseWithDiagnostics(gpa, "fn main() -> UInt8 { var x: UInt8 = 1; x }");
    try testing.expectEqual(@as(u32, 0), immutable.errors);
    try testing.expectEqual(@as(u32, 0), mutable.errors);
    // The two differ only in the keyword, so the trees are the same shape.
    try testing.expectEqualStrings(immutable.dump, mutable.dump);
}

test "a while holds its condition and its body" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try parseWithDiagnostics(arena.allocator(), "fn main() -> UInt8 { while false { } 0 }");
    try testing.expectEqual(@as(u32, 0), r.errors);
    try testing.expect(std.mem.indexOf(u8, r.dump, "while_") != null);
}

test "an assignment does not chain" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const one = try parseWithDiagnostics(gpa, "fn main() -> UInt8 { var x: UInt8 = 1; x = 2; x }");
    try testing.expectEqual(@as(u32, 0), one.errors);
    try testing.expect(std.mem.indexOf(u8, one.dump, "assign") != null);

    // Its value is Unit, so a second `=` would be assigning Unit. Rejected by
    // the grammar rather than left for the checker to explain.
    const chained = try parseWithDiagnostics(gpa, "fn main() -> UInt8 { var x: UInt8 = 1; var y: UInt8 = 2; x = y = 3; x }");
    try testing.expect(chained.errors > 0);
}

test "a program is a list of declarations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try parseWithDiagnostics(arena.allocator(),
        \\fn helper() -> UInt8 { 1 }
        \\fn main() -> UInt8 { 2 }
    );
    try testing.expectEqual(@as(u32, 0), r.errors);
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, r.dump, "decl function"));
}

test "parameters are named, typed and carry a convention" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try parseWithDiagnostics(arena.allocator(),
        \\fn f(a: UInt8, read b: Int64) -> UInt8 { a }
        \\fn main() -> UInt8 { f(1, 2) }
    );
    try testing.expectEqual(@as(u32, 0), r.errors);
    // `read` is the default, so writing it changes nothing about the tree.
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, r.dump, "param read"));
}

test "a parameter's default dumps as its child" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try parseWithDiagnostics(arena.allocator(),
        \\fn f(a: UInt8 = 1) -> UInt8 { a }
        \\fn main() -> UInt8 { f(1) }
    );
    try testing.expectEqual(@as(u32, 0), r.errors);
    // The default nests under the parameter it belongs to, one level deeper
    // than the parameter line itself.
    try testing.expect(std.mem.indexOf(
        u8,
        r.dump,
        "param read \"a\" : UInt8\n      expr %0 int_literal tokens 7..8 \"1\"\n",
    ) != null);
}

test "a default on an `inout` parameter is refused" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const codes = try codesOf(gpa, "fn f(inout a: UInt8 = 1) -> UInt8 { a }");
    try testing.expectEqualSlices(?Code, &.{.s_default}, codes);
}

test "a default on a `sink` parameter is kept" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const codes = try codesOf(gpa, "fn f(sink a: UInt8 = 1) -> UInt8 { a }");
    try testing.expectEqualSlices(?Code, &.{}, codes);
}

test "a defaulted parameter followed by an undefaulted one is refused" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const codes = try codesOf(gpa, "fn f(a: UInt8 = 1, b: UInt8) -> UInt8 { a }");
    try testing.expectEqualSlices(?Code, &.{.s_default}, codes);
}

test "one gap after a default reports once, however many parameters follow it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const codes = try codesOf(gpa, "fn f(a: UInt8 = 1, b: UInt8, c: UInt8) -> UInt8 { a }");
    try testing.expectEqualSlices(?Code, &.{.s_default}, codes);
}

test "a default with no expression recovers with an error node" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const r = try parseWithDiagnostics(gpa, "fn f(a: UInt8 = ) -> UInt8 { a }");
    try testing.expect(r.errors > 0);
    try testing.expect(std.mem.indexOf(u8, r.dump, "err") != null);
}

test "a call holds its callee and its arguments" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try parseWithDiagnostics(arena.allocator(), "fn main() -> UInt8 { f(1, 2) }");
    try testing.expect(std.mem.indexOf(u8, r.dump, "call") != null);
    // The callee and both arguments are children of the call.
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, r.dump, "name_ref"));
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, r.dump, "int_literal"));
}

test "a named argument dumps the parameter it names" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try parseWithDiagnostics(arena.allocator(), "fn main() -> UInt8 { f(a: 1, b: 2) }");
    try testing.expectEqual(@as(u32, 0), r.errors);
    try testing.expect(std.mem.indexOf(u8, r.dump, "name \"a\"") != null);
    try testing.expect(std.mem.indexOf(u8, r.dump, "name \"b\"") != null);
}

test "a positional argument dumps no name" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try parseWithDiagnostics(arena.allocator(), "fn main() -> UInt8 { f(1, b: 2) }");
    try testing.expectEqual(@as(u32, 0), r.errors);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, r.dump, "name \""));
    try testing.expect(std.mem.indexOf(u8, r.dump, "name \"b\"") != null);
}

test "a positional argument after a named one is refused" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const codes = try codesOf(gpa, "fn main() -> UInt8 { f(b: 2, 1) }");
    try testing.expectEqualSlices(?Code, &.{.s_args}, codes);

    // The call is still complete: both arguments were parsed and appended,
    // per the infallible frontend.
    const r = try parseWithDiagnostics(gpa, "fn main() -> UInt8 { f(b: 2, 1) }");
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, r.dump, "int_literal"));
}

test "a named argument with no value is an error node, and reports once" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const r = try parseWithDiagnostics(gpa, "fn main() -> UInt8 { f(x:) }");
    try testing.expectEqual(@as(u32, 1), r.errors);
    try testing.expect(std.mem.indexOf(u8, r.dump, "name \"x\"") != null);
    try testing.expect(std.mem.indexOf(u8, r.dump, "err") != null);
}

test "a dotted path is never read as an argument's name" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // `a.b` is a field access, not a bare identifier, so the lookahead
    // declines it: the argument is positional, `3` is left unparsed, and the
    // call and its enclosing block each report the token they expected and
    // did not find -- the same recovery any call missing a comma already
    // gets, undisturbed by this feature.
    const r = try parseWithDiagnostics(gpa, "fn main() -> UInt8 { f(a.b: 3) }");
    const codes = try codesOf(gpa, "fn main() -> UInt8 { f(a.b: 3) }");
    try testing.expectEqualSlices(?Code, &.{ .s_paren, .s_separator }, codes);
    try testing.expectEqual(@as(usize, 0), std.mem.count(u8, r.dump, "name \""));
}

test "a name without a call is still a name" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try parseWithDiagnostics(arena.allocator(), "fn main() -> UInt8 { let x: UInt8 = 1; x }");
    try testing.expectEqual(@as(u32, 0), r.errors);
    try testing.expect(std.mem.indexOf(u8, r.dump, "call") == null);
}

test "a malformed parameter list still yields a tree" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // The parser has no error path: this reports and keeps going, and the
    // declaration after it is still parsed.
    const r = try parseWithDiagnostics(arena.allocator(),
        \\fn f(a: ) -> UInt8 { 1 }
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expect(r.errors > 0);
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, r.dump, "decl "));
}

test "a stray region between declarations is reported once" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // Recovery skips to the next declaration rather than the next token, or a
    // run of rubbish reports once per token it contains.
    const r = try parseWithDiagnostics(arena.allocator(),
        \\1 + 2 * 3
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expectEqual(@as(u32, 1), r.errors);
}

test "an enum is a declaration beside a function" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try parseProgramText(arena.allocator(),
        \\enum Colour { Red, Green, Blue }
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expectEqual(@as(u32, 0), r.errors);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, r.dump, "decl enum_"));
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, r.dump, "decl function"));
    try testing.expectEqual(@as(usize, 3), std.mem.count(u8, r.dump, "variant "));
}

test "a variant carries a type" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try parseProgramText(arena.allocator(),
        \\enum Shape { Circle(UInt8), Square }
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expectEqual(@as(u32, 0), r.errors);
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, r.dump, "variant "));

    // Printed only where one was written, so a fieldless enum's tree reads
    // exactly as it did before payloads existed.
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, r.dump, "variant \"Circle\" : UInt8"));
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, r.dump, "variant \"Square\"\n"));
}

test "a variant with no closing paren still yields a tree" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try parseProgramText(arena.allocator(), "enum E { A(UInt8 }\nfn main() -> UInt8 { 0 }");
    try testing.expect(r.errors > 0);
    try testing.expect(std.mem.indexOf(u8, r.dump, "decl enum_") != null);
}

test "a variant is constructed by calling it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // `Shape.Circle(3)` is a call whose callee selects the variant, which is
    // the shape a call already has -- so nothing new reaches the tree. Which
    // of a field and a variant `Shape.Circle` is, the parser does not decide.
    const r = try parseProgramText(arena.allocator(),
        \\enum Shape { Circle(UInt8) }
        \\fn main() -> UInt8 { let _: Shape = Shape.Circle(3); 0 }
    );
    try testing.expectEqual(@as(u32, 0), r.errors);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, r.dump, "call"));
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, r.dump, "expr %1 field"));
}

test "a pattern binds what its variant carries" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // A pattern with binders is a call too: the variant is the callee and the
    // binders are the arguments.
    const r = try parseProgramText(arena.allocator(),
        \\enum Shape { Circle(UInt8), Square }
        \\fn main() -> UInt8 { match Shape.Square { Circle(n) => n, Square => 0 } }
    );
    try testing.expectEqual(@as(u32, 0), r.errors);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, r.dump, "match_"));
}

test "a trailing comma in a variant list is accepted" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try parseProgramText(arena.allocator(),
        \\enum Colour { Red, Green, }
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expectEqual(@as(u32, 0), r.errors);
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, r.dump, "variant "));
}

test "a malformed variant list still yields a tree" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // The parser has no error path: it reports and the declaration after it is
    // still parsed.
    const r = try parseProgramText(arena.allocator(),
        \\enum E { , }
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expect(r.errors > 0);
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, r.dump, "decl "));
}

test "a struct is a declaration beside a function and an enum" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try parseProgramText(arena.allocator(),
        \\struct Point { x: UInt8, y: UInt8 }
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expectEqual(@as(u32, 0), r.errors);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, r.dump, "decl struct_"));
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, r.dump, "field "));
}

test "a malformed field list still yields a tree" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try parseProgramText(arena.allocator(), "struct P { , }\nfn main() -> UInt8 { 0 }");
    try testing.expect(r.errors > 0);
    try testing.expect(std.mem.indexOf(u8, r.dump, "decl ") != null);
}

test "a trailing comma in a field list is accepted" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // A field list is edited a line at a time, and the last line is not
    // special -- the same reason a variant list allows one.
    const r = try parseProgramText(arena.allocator(),
        \\struct Point { x: UInt8, y: UInt8, }
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expectEqual(@as(u32, 0), r.errors);
}

test "an import records its path, and its name is the last element or the alias" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Readers coming from Java or C# expect `util.hash` to name something
    // inside a package `util`. It does not: the dots are path separators, and
    // nothing called `util` is introduced here or loaded at all.
    const got = try parseProgramText(gpa,
        \\import util.hash;
        \\import crypto.hash as ch;
        \\fn main() -> UInt8 { 1 }
    );
    try testing.expectEqual(@as(u32, 0), got.errors);
    try testing.expect(std.mem.indexOf(u8, got.dump, "decl import_ \"hash\"") != null);
    try testing.expect(std.mem.indexOf(u8, got.dump, "decl import_ \"ch\"") != null);
    try testing.expect(std.mem.indexOf(u8, got.dump, "path util hash") != null);
    try testing.expect(std.mem.indexOf(u8, got.dump, "path crypto hash") != null);
}

test "a file ending after an import is parsed beside a longer file" {
    // The first file's last line is ended by its own `eof`, and the next
    // significant token is the second file's, past a comment longer than the
    // whole first file. Reading that token against the first file's text is
    // what the continuation note must never do.
    const gpa = testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var sink = Sink.init(arena.allocator());
    var interner: Interner = .empty;
    defer interner.deinit(gpa);
    const files = [_]ParsedFile{
        .{ .file = .from(0), .source = .{ .path = "a.lin", .text = "import b\n" } },
        .{ .file = .from(1), .source = .{ .path = "b.lin", .text = "// The value this module offers, which the file above imports.\npub fn value() -> UInt8 {\n    let doubled = 2\n    doubled\n}\n" } },
    };
    var modules = Modules.init(gpa, &sink, &interner);
    defer modules.deinit();
    _ = try modules.add(&files);
    var ast = try modules.finish();
    defer ast.deinit(gpa);
    try testing.expectEqual(@as(u32, 2), ast.declCount());
    try testing.expectEqual(@as(usize, 0), sink.items().len);
}

test "a malformed import is diagnosed and the file keeps parsing" {
    // The parser has no error path: what follows a broken import must still
    // become declarations, or one typo would hide the rest of the file.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = try parseProgramText(gpa,
        \\import util.;
        \\fn main() -> UInt8 { 1 }
    );
    try testing.expect(got.errors > 0);
    try testing.expect(std.mem.indexOf(u8, got.dump, "decl function \"main\"") != null);
}

test "`pub` prefixes a declaration and reaches its text" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = try parseProgramText(gpa,
        \\pub fn f() -> UInt8 { 1 }
        \\pub struct S { x: UInt8 }
        \\pub enum E { A }
        \\fn main() -> UInt8 { 1 }
    );
    try testing.expectEqual(@as(u32, 0), got.errors);
    try testing.expect(std.mem.indexOf(u8, got.dump, "decl pub function \"f\" tokens 0..") != null);
    try testing.expect(std.mem.indexOf(u8, got.dump, "decl pub struct_ \"S\"") != null);
    try testing.expect(std.mem.indexOf(u8, got.dump, "decl pub enum_ \"E\"") != null);
    try testing.expect(std.mem.indexOf(u8, got.dump, "decl function \"main\"") != null);
}

test "`internal` prefixes a declaration and an inherent member" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = try parseProgramText(gpa,
        \\internal fn make(value: UInt8) -> Token { .{ value = value } }
        \\internal struct Token { value: UInt8 }
        \\internal let zero: UInt8 = 0
        \\struct Box { value: UInt8 }
        \\impl Box { internal fn value(self: Box) -> UInt8 { self.value } }
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expectEqual(@as(u32, 0), got.errors);
    try testing.expect(std.mem.indexOf(u8, got.dump, "decl internal function \"make\"") != null);
    try testing.expect(std.mem.indexOf(u8, got.dump, "decl internal struct_ \"Token\"") != null);
    try testing.expect(std.mem.indexOf(u8, got.dump, "decl internal constant \"zero\"") != null);
    try testing.expect(std.mem.indexOf(u8, got.dump, "decl internal function \"value\"") != null);
}

test "`internal` is refused where a declaration has no independent visibility" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const implemented = try parseProgramText(gpa,
        \\struct Token { value: UInt8 }
        \\internal impl Token {}
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expect(implemented.errors > 0);

    const derived = try parseProgramText(gpa,
        \\struct Token { value: UInt8 }
        \\internal derive Display for Token
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expect(derived.errors > 0);

    const tested = try parseProgramText(gpa,
        \\internal test fn token_works() {}
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expect(tested.errors > 0);
}

test "a `pub` that prefixes nothing is diagnosed once" {
    // Recovery has to know `pub` begins a declaration, or a stray one would be
    // skipped past and the declaration after it swallowed with it.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = try parseProgramText(gpa,
        \\pub ;
        \\fn main() -> UInt8 { 1 }
    );
    try testing.expectEqual(@as(u32, 1), got.errors);
    try testing.expect(std.mem.indexOf(u8, got.dump, "decl function \"main\"") != null);
}

test "a match arm may be a block, and holds more than one statement" {
    // No arm could hold two statements before this, which is a gap that
    // predates ownership -- an `if` arm was already a block.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = try parseProgramText(gpa,
        \\enum Colour { Red, Green }
        \\fn main() -> UInt8 {
        \\    let c: Colour = .Red;
        \\    match c {
        \\        Red => { let a = 1; a + 1 },
        \\        Green => 3,
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u32, 0), got.errors);
}

test "an empty arm body is a block with nothing in it" {
    // The arm this stage exists to write: `Forged(_) => {}` releases a linear
    // value by taking it apart and doing nothing with the parts.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = try parseProgramText(gpa,
        \\enum Colour { Red, Green }
        \\fn ignore(c: Colour) {
        \\    match c {
        \\        Red => {},
        \\        Green => {},
        \\    }
        \\}
        \\fn main() -> UInt8 { ignore(.Red); 1 }
    );
    try testing.expectEqual(@as(u32, 0), got.errors);
    try testing.expect(std.mem.indexOf(u8, got.dump, "block") != null);
}

test "a trailing comma after the last arm is optional and allowed" {
    // The separator between arms is required; the one after the last is not.
    // That is the rule every other delimited list follows, and it is what lets
    // the trailing comma mean something -- a marker only carries a choice
    // where both spellings are legal.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const without = try parseProgramText(gpa,
        \\enum Colour { Red, Green }
        \\fn main() -> UInt8 { let c: Colour = .Red; match c { Red => { 1 }, Green => { 2 } } }
    );
    const with = try parseProgramText(gpa,
        \\enum Colour { Red, Green }
        \\fn main() -> UInt8 { let c: Colour = .Red; match c { Red => { 1 }, Green => { 2 }, } }
    );
    try testing.expectEqual(@as(u32, 0), without.errors);
    try testing.expectEqual(@as(u32, 0), with.errors);
    // Node ids are handed out in parse order, so the same shape numbers the
    // same way. Token ranges differ because the two texts differ by a comma,
    // and comparing those would be comparing the inputs.
    try testing.expectEqualStrings(
        try withoutTokenRanges(gpa, without.dump),
        try withoutTokenRanges(gpa, with.dump),
    );
}

test "a missing comma between arms is diagnosed" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = try parseProgramText(gpa,
        \\enum Colour { Red, Green }
        \\fn weigh(c: Colour) -> UInt8 {
        \\    match c {
        \\        Red => { 1 }
        \\        Green => 2,
        \\    }
        \\}
        \\fn main() -> UInt8 { weigh(.Red) }
    );
    try testing.expectEqual(@as(u32, 1), got.errors);
}

test "the comma after the last arm is optional" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = try parseProgramText(gpa,
        \\enum Colour { Red, Green }
        \\fn weigh(c: Colour) -> UInt8 {
        \\    match c {
        \\        Red => { 1 },
        \\        Green => 2
        \\    }
        \\}
        \\fn main() -> UInt8 { weigh(.Red) }
    );
    try testing.expectEqual(@as(u32, 0), got.errors);
}

/// A dump with every ` tokens N..M` removed, for comparing two trees whose
/// sources differ in length.
fn withoutTokenRanges(gpa: std.mem.Allocator, dump: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var rest = dump;
    while (std.mem.indexOf(u8, rest, " tokens ")) |at| {
        try out.appendSlice(gpa, rest[0..at]);
        const after = rest[at + " tokens ".len ..];
        const end = std.mem.indexOfAny(u8, after, " \n") orelse after.len;
        rest = after[end..];
    }
    try out.appendSlice(gpa, rest);
    return out.items;
}

test "an unclosed arm block is diagnosed and the file keeps parsing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = try parseProgramText(gpa,
        \\enum Colour { Red }
        \\fn main() -> UInt8 { let c: Colour = .Red; match c { Red => { 1 } }
    );
    try testing.expect(got.errors > 0);
}

test "`sink` is a convention beside `read` and `inout`" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = try parseProgramText(gpa,
        \\fn release(sink n: UInt8) {}
        \\fn main() -> UInt8 { release(1); 2 }
    );
    try testing.expectEqual(@as(u32, 0), got.errors);
}

test "a declaration takes type parameters" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // On all three declaration forms, with bounds, and with a trailing comma
    // for the reason a field list allows one: a list is edited a line at a
    // time and the last line is not special.
    const got = try parseProgramText(gpa,
        \\enum Holder[T] { Empty(T) }
        \\struct Pair[A, B: Copyable,] { x: A, y: B }
        \\fn main() -> UInt8 { 1 }
    );
    try testing.expectEqual(@as(u32, 0), got.errors);
    try testing.expect(std.mem.indexOf(u8, got.dump, "type param \"T\"") != null);
    try testing.expect(std.mem.indexOf(u8, got.dump, "type param \"B\" : Copyable") != null);
}

test "general trailing where clauses are parsed on every generic declaration kind" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = try parseProgramText(gpa,
        \\struct Box[T] where T: Copyable { value: T }
        \\enum Maybe[T] where T: Copyable { None, Some(T) }
        \\trait Convert[T] where T: Copyable { fn convert(value: T) -> T }
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expectEqual(@as(u32, 0), got.errors);
    try testing.expectEqual(@as(usize, 3), std.mem.count(u8, got.dump, "where T : Copyable"));
}

test "default implementation parses its generic head and members" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const got = try parseProgramText(arena.allocator(),
        \\trait Source {}
        \\trait Query { type Item }
        \\default impl[T: Source] Query for T {
        \\    type Item = T
        \\    fn value(self: T) -> T { self }
        \\}
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expectEqual(@as(u32, 0), got.errors);
    try testing.expect(std.mem.indexOf(u8, got.dump, "decl impl_ \"T\"") != null);
    try testing.expect(std.mem.indexOf(u8, got.dump, "decl function \"main\"") != null);
}

test "default implementation modifier belongs to its declaration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const source: Source = .{
        .path = "defaults.lin",
        .text =
        \\default impl[T: Source] Query for T where T: Copyable { type Item = T }
        \\impl Query for Item { type Item = UInt8 }
        ,
    };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    const ast = try parse(gpa, &source, .from(0), tokens, &sink);
    try testing.expectEqual(@as(u32, 0), sink.error_count);

    var defaults: usize = 0;
    var ordinary: usize = 0;
    for (0..ast.declCount()) |i| {
        const id = node.DeclId.at(@intCast(i));
        if (ast.declTag(id) != .impl_) {
            try testing.expect(!ast.declIsDefault(id));
            continue;
        }
        if (ast.declIsDefault(id)) {
            defaults += 1;
            try testing.expectEqualStrings("default", ast.tokenText(ast.declTokens(id).start));
            try testing.expectEqual(@as(usize, 1), ast.declTypeParams(id).len);
            try testing.expectEqual(@as(usize, 1), ast.declWherePredicates(id).len);
        } else ordinary += 1;
    }
    try testing.expectEqual(@as(usize, 1), defaults);
    try testing.expectEqual(@as(usize, 1), ordinary);
}

test "a type parameter default is kept by a function, a struct, an enum and an alias and refused elsewhere" {
    const kept = [_][]const u8{
        "struct Shelf[T, A: Allocator = SystemAllocator] { items: Vec[T, A] }",
        "enum Choice[T, E = Str] { Some(T), Else(E) }",
        "alias Rack[T, A: Allocator = mem.SystemAllocator] = Shelf[T, A]",
        "fn first[T = UInt8](sink value: T = 1) -> T { value }",
    };
    for (kept) |declaration| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const source = try std.fmt.allocPrint(arena.allocator(), "{s}\nfn main() -> UInt8 {{ 0 }}\n", .{declaration});
        const got = try parseProgramText(arena.allocator(), source);
        try testing.expectEqual(@as(u32, 0), got.errors);
        try testing.expect(std.mem.indexOf(u8, got.dump, " = ") != null);
    }
    const refused = [_][]const u8{
        "trait Source[T = UInt8] { fn next(self: Self) -> T }",
        "impl[T = UInt8] Shelf[T] {}",
        "struct Pair[A = UInt8, B] { a: A, b: B }",
        "struct Pair[A, B = A] { a: A, b: B }",
    };
    for (refused) |declaration| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const source = try std.fmt.allocPrint(arena.allocator(), "{s}\nfn main() -> UInt8 {{ 0 }}\n", .{declaration});
        const got = try parseProgramText(arena.allocator(), source);
        try testing.expectEqual(@as(u32, 1), got.errors);
    }
}

test "default implementation modifier refuses other declaration forms and recovers" {
    const invalid = [_][]const u8{
        "default fn rejected() -> UInt8 { 0 }",
        "default struct Rejected {}",
        "default trait Rejected {}",
        "default impl[T] T {}",
        "default impl[T] Query for T via value",
        "default template impl Query {}",
        "template default impl Query {}",
        "default derive Query for Item",
        "default default impl[T] Query for T {}",
        "pub default impl[T] Query for T {}",
        "linear default impl[T] Query for T {}",
        "test default impl[T] Query for T {}",
    };
    for (invalid) |declaration| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const source = try std.fmt.allocPrint(arena.allocator(), "{s}\nfn main() -> UInt8 {{ 0 }}\n", .{declaration});
        const got = try parseProgramText(arena.allocator(), source);
        try testing.expect(got.errors > 0);
        try testing.expect(std.mem.indexOf(u8, got.dump, "decl function \"main\"") != null);
    }
}

test "a structural template is a distinct impl-shaped declaration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const got = try parseProgramText(arena.allocator(),
        \\trait Marker {}
        \\template impl Marker {}
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expectEqual(@as(u32, 0), got.errors);
    try testing.expect(std.mem.indexOf(u8, got.dump, "decl template_impl \"Marker\"") != null);
}

test "Unit is only an implementation head" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const got = try parseProgramText(arena.allocator(),
        \\struct Item {}
        \\impl () for Item {}
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expect(got.errors > 0);
    try testing.expect(std.mem.indexOf(u8, got.dump, "decl function \"main\"") != null);
}

test "qualified trait references parse in every trait position" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const got = try parseProgramText(arena.allocator(),
        \\trait Child: protocol.Parent {}
        \\template impl protocol.Marker {}
        \\struct Item {}
        \\derive protocol.Marker for Item
        \\impl protocol.Parent for Item {}
        \\fn accepts[T: protocol.Parent](_value: T) where T: protocol.Parent {}
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expectEqual(@as(u32, 0), got.errors);
}

test "parser records structural reflection" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const got = try parseProgramText(arena.allocator(),
        \\trait Fold { fn fold(self: Self) -> UInt8 }
        \\template impl Fold {
        \\    fn fold(self: Self) -> UInt8 {
        \\        match read self {
        \\            reflect.case => {
        \\                var total: UInt8 = 0
        \\                for component in reflect.components.reversed {
        \\                    total = total + component.of(self)
        \\                }
        \\                total
        \\            }
        \\        }
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u32, 0), got.errors);
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, got.dump, "reflection_root"));
    try testing.expect(std.mem.indexOf(u8, got.dump, "\"case\"") != null);
    try testing.expect(std.mem.indexOf(u8, got.dump, "\"components\"") != null);
    try testing.expect(std.mem.indexOf(u8, got.dump, "\"reversed\"") != null);
    try testing.expect(std.mem.indexOf(u8, got.dump, "\"of\"") != null);
}

test "a derive request is a distinct impl-space declaration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const got = try parseProgramText(arena.allocator(),
        \\struct Mark {}
        \\trait Debug {}
        \\derive Debug for Mark
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expectEqual(@as(u32, 0), got.errors);
    try testing.expect(std.mem.indexOf(u8, got.dump, "decl derive_impl single \"Mark\"") != null);
    try testing.expect(std.mem.indexOf(u8, got.dump, "trait Debug") != null);
}

test "grouped derive and template component requirement parse" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const text =
        \\trait Inspect {}
        \\trait Lookup[T] {}
        \\template impl Inspect
        \\where reflect.components: Inspect + Lookup[UInt64]
        \\{}
        \\struct Box[T] { value: T }
        \\derive[T: Inspect] (
        \\    Inspect,
        \\) for Box[T] where
        \\    T: Lookup[UInt64],
        \\fn main() -> UInt8 { 0 }
    ;
    const source: Source = .{ .path = "t.lin", .text = text };
    var sink = Sink.init(arena.allocator());
    var interner: Interner = .empty;
    const tokens = try tokenize(arena.allocator(), &source, .from(0), &sink, &interner);
    const ast = try parse(arena.allocator(), &source, .from(0), tokens, &sink);

    try testing.expectEqual(@as(u32, 0), sink.error_count);
    try testing.expectEqual(@as(usize, 1), ast.template_requirements.len);
    try testing.expectEqual(@as(usize, 1), ast.derive_traits.len);

    var template = node.DeclId.none;
    var derive = node.DeclId.none;
    for (0..ast.declCount()) |i| {
        const id = node.DeclId.at(@intCast(i));
        switch (ast.declTag(id)) {
            .template_impl => template = id,
            .derive_impl => derive = id,
            else => {},
        }
    }
    try testing.expect(template != .none);
    try testing.expect(derive != .none);
    const requirement = ast.templateRequirements(template)[0];
    try testing.expectEqual(node.TemplateRequirement.Kind.components, requirement.kind);
    try testing.expectEqualStrings("reflect", ast.tokenText(requirement.reflect));
    try testing.expectEqualStrings("components", ast.tokenText(requirement.selector));
    try testing.expectEqual(@as(usize, 2), ast.boundsIn(requirement.bounds).len);
    try testing.expect(ast.deriveIsGrouped(derive));
    try testing.expect(ast.deriveGroupOpen(derive) != .none);
    try testing.expect(ast.deriveGroupClose(derive) != .none);
    try testing.expectEqualStrings("Inspect", ast.tokenText(ast.deriveTraits(derive)[0].ref.name));
    try testing.expectEqual(@as(usize, 1), ast.declTypeParams(derive).len);
    try testing.expectEqual(@as(u32, 1), ast.declHead(derive).args.len());
    try testing.expectEqual(@as(usize, 1), ast.declWherePredicates(derive).len);
}

test "structural supertrait requirement parses as derived evidence" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const text =
        \\trait Base {}
        \\trait Law: Base {}
        \\template impl Law where reflect.supertraits: derived {}
        \\fn main() -> UInt8 { 0 }
    ;
    const source: Source = .{ .path = "t.lin", .text = text };
    var sink = Sink.init(arena.allocator());
    var interner: Interner = .empty;
    const tokens = try tokenize(arena.allocator(), &source, .from(0), &sink, &interner);
    const ast = try parse(arena.allocator(), &source, .from(0), tokens, &sink);

    try testing.expectEqual(@as(u32, 0), sink.error_count);
    try testing.expectEqual(@as(usize, 1), ast.template_requirements.len);
    const requirement = ast.template_requirements[0];
    try testing.expectEqual(node.TemplateRequirement.Kind.derived_supertraits, requirement.kind);
    try testing.expectEqualStrings("supertraits", ast.tokenText(requirement.selector));
    try testing.expectEqual(@as(u32, 0), requirement.bounds.len());
}

test "malformed structural source recovers at the next declaration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const got = try parseProgramText(arena.allocator(),
        \\trait Inspect {}
        \\template impl Inspect where reflect.components Inspect {}
        \\derive (Inspect, for Missing
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expect(got.errors > 0);
    try testing.expect(std.mem.indexOf(u8, got.dump, "decl template_impl \"Inspect\"") != null);
    try testing.expect(std.mem.indexOf(u8, got.dump, "decl derive_impl grouped \"Missing\"") != null);
    try testing.expect(std.mem.indexOf(u8, got.dump, "decl function \"main\"") != null);
}

test "a malformed template component requirement stops at a declaration boundary" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const got = try parseProgramText(arena.allocator(),
        \\trait Inspect {}
        \\template impl Inspect where reflect.components fn main() -> UInt8 { 0 }
    );
    try testing.expect(got.errors > 0);
    try testing.expect(std.mem.indexOf(u8, got.dump, "decl function \"main\"") != null);
}

test "a callable template component requirement remains a bound" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const got = try parseProgramText(arena.allocator(),
        \\trait Inspect {}
        \\template impl Inspect where reflect.components: fn(read value: UInt8) -> UInt8 {}
    );
    try testing.expectEqual(@as(u32, 0), got.errors);
}

test "a missing template component bound stops before a function declaration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const got = try parseProgramText(arena.allocator(),
        \\trait Inspect {}
        \\template impl Inspect where reflect.components:
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expect(got.errors > 0);
    try testing.expect(std.mem.indexOf(u8, got.dump, "decl function \"main\"") != null);
}

test "a trailing component bound plus stops before a function declaration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const got = try parseProgramText(arena.allocator(),
        \\trait Inspect {}
        \\template impl Inspect where reflect.components: Inspect + fn main() -> UInt8 { 0 }
    );
    try testing.expect(got.errors > 0);
    try testing.expect(std.mem.indexOf(u8, got.dump, "decl function \"main\"") != null);
}

test "an unclosed derive group stops before a contextual newtype declaration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const got = try parseProgramText(arena.allocator(),
        \\derive (Inspect,
        \\type Alias = UInt8
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expect(got.errors > 0);
    try testing.expect(std.mem.indexOf(u8, got.dump, "decl newtype \"Alias\"") != null);
    try testing.expect(std.mem.indexOf(u8, got.dump, "decl function \"main\"") != null);
}

test "a derive target named type precedes a contextual newtype declaration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const got = try parseProgramText(arena.allocator(),
        \\derive Inspect for type
        \\type Alias = UInt8
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expectEqual(@as(u32, 0), got.errors);
    try testing.expect(std.mem.indexOf(u8, got.dump, "decl derive_impl single \"type\"") != null);
    try testing.expect(std.mem.indexOf(u8, got.dump, "decl newtype \"Alias\"") != null);
}

test "source ids retain structural source tables through a module prefix" {
    const gpa = testing.allocator;
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    defer interner.deinit(gpa);

    const source: Source = .{
        .path = "source.lin",
        .text =
        \\template impl Inspect where reflect.components: Inspect {}
        \\derive (Inspect,) for Box
        \\default impl[T: Inspect] Query for T { type Item = T }
        \\
        ,
    };
    const files = [_]ParsedFile{.{ .file = .from(0), .source = source }};
    var source_modules = Modules.init(gpa, &sink, &interner);
    defer source_modules.deinit();
    _ = try source_modules.add(&files);
    var source_ast = try source_modules.finish();
    defer source_ast.deinit(gpa);

    try testing.expectEqual(@as(usize, 1), source_ast.derive_traits.len);
    try testing.expectEqual(@as(usize, 1), source_ast.template_requirements.len);

    var modules = try Modules.initPrefix(gpa, &sink, &interner, &source_ast);
    defer modules.deinit();
    const prefix = modules.view();
    try expectSourcePrefix(&source_ast, &prefix);
}

test "copying a source prefix releases partial columns on allocation failure" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    defer interner.deinit(gpa);
    const files = [_]ParsedFile{.{
        .file = .from(0),
        .source = .{
            .path = "source.lin",
            .text =
            \\struct Box[T: Copyable] { value: T, }
            \\fn make(input: UInt8) -> Box[UInt8] {
            \\    let value = copy(input)
            \\    .{ value = value }
            \\}
            ,
        },
    }};
    var parsed = Modules.init(gpa, &sink, &interner);
    defer parsed.deinit();
    _ = try parsed.add(&files);
    var source = try parsed.finish();
    defer source.deinit(gpa);
    try testing.expectEqual(@as(u32, 0), sink.error_count);

    const Attempt = struct {
        fn copy(allocator: std.mem.Allocator, diagnostics: *Sink, names: *Interner, ast: *const Ast) !void {
            var copied = try Modules.initPrefix(allocator, diagnostics, names, ast);
            defer copied.deinit();
            const view = copied.view();
            try expectSourcePrefix(ast, &view);
            try testing.expectEqual(ast.tokens.len, copied.tokens.capacity);
            try testing.expectEqual(ast.exprs.len, copied.builder.exprs.capacity);
            try testing.expectEqual(ast.stmts.len, copied.builder.stmts.capacity);
            try testing.expectEqual(ast.decls.len, copied.builder.decls.capacity);
            try testing.expect(ast.tokens.items(.tag).ptr != view.tokens.items(.tag).ptr);
            try testing.expect(ast.exprs.items(.tag).ptr != view.exprs.items(.tag).ptr);
            try testing.expect(ast.stmts.items(.tag).ptr != view.stmts.items(.tag).ptr);
            try testing.expect(ast.decls.items(.tag).ptr != view.decls.items(.tag).ptr);
        }
    };
    try testing.checkAllAllocationFailures(testing.allocator, Attempt.copy, .{ &sink, &interner, &source });
}

fn expectSourcePrefix(expected: *const Ast, actual: *const Ast) !void {
    try testing.expect(expected.parts.len <= actual.parts.len);
    try testing.expect(expected.tokens.len <= actual.tokens.len);
    try testing.expect(expected.exprs.len <= actual.exprs.len);
    try testing.expect(expected.stmts.len <= actual.stmts.len);
    try testing.expect(expected.blocks.len <= actual.blocks.len);
    try testing.expect(expected.block_stmts.len <= actual.block_stmts.len);
    try testing.expect(expected.decls.len <= actual.decls.len);
    try testing.expect(expected.params.len <= actual.params.len);
    try testing.expect(expected.type_params.len <= actual.type_params.len);
    try testing.expect(expected.bounds.len <= actual.bounds.len);
    try testing.expect(expected.where_predicates.len <= actual.where_predicates.len);
    try testing.expect(expected.derive_traits.len <= actual.derive_traits.len);
    try testing.expect(expected.template_requirements.len <= actual.template_requirements.len);
    try testing.expect(expected.type_refs.len <= actual.type_refs.len);
    try testing.expect(expected.callable_types.len <= actual.callable_types.len);
    try testing.expect(expected.variants.len <= actual.variants.len);
    try testing.expect(expected.fields.len <= actual.fields.len);
    try testing.expect(expected.extra.len <= actual.extra.len);
    try testing.expect(expected.call_names.len <= actual.call_names.len);
    try testing.expect(expected.interpolation_formats.len <= actual.interpolation_formats.len);
    try testing.expect(expected.struct_literal_heads.len <= actual.struct_literal_heads.len);

    for (expected.parts, actual.parts[0..expected.parts.len]) |want, got| {
        try testing.expectEqualDeep(want, got);
        try testing.expect(want.source.ptr == got.source.ptr);
    }
    for (0..expected.tokens.len) |i| {
        try testing.expectEqualDeep(expected.tokens.get(i), actual.tokens.get(i));
    }
    for (0..expected.exprs.len) |i| {
        const want = expected.exprs.get(i);
        const got = actual.exprs.get(i);
        try testing.expectEqual(want.tag, got.tag);
        try testing.expectEqual(want.main_token, got.main_token);
        try testing.expectEqualDeep(want.token_range, got.token_range);
        try testing.expectEqualDeep(want.call_flags, got.call_flags);
        switch (want.tag.payload()) {
            .none => {},
            .unary => try testing.expectEqualDeep(want.data.unary, got.data.unary),
            .binary => try testing.expectEqualDeep(want.data.binary, got.data.binary),
            .conditional => try testing.expectEqualDeep(want.data.conditional, got.data.conditional),
            .call => try testing.expectEqualDeep(want.data.call, got.data.call),
            .interpolation => try testing.expectEqualDeep(want.data.interpolation, got.data.interpolation),
            .lambda => try testing.expectEqualDeep(want.data.lambda, got.data.lambda),
            .block => try testing.expectEqual(want.data.block, got.data.block),
            .range => try testing.expectEqualDeep(want.data.range, got.data.range),
        }
    }
    for (0..expected.stmts.len) |i| {
        try testing.expectEqualDeep(expected.stmts.get(i), actual.stmts.get(i));
    }
    for (0..expected.decls.len) |i| {
        try testing.expectEqualDeep(expected.decls.get(i), actual.decls.get(i));
    }
    try testing.expectEqualDeep(expected.blocks, actual.blocks[0..expected.blocks.len]);
    try testing.expectEqualDeep(expected.block_stmts, actual.block_stmts[0..expected.block_stmts.len]);
    try testing.expectEqualDeep(expected.params, actual.params[0..expected.params.len]);
    try testing.expectEqualDeep(expected.type_params, actual.type_params[0..expected.type_params.len]);
    try testing.expectEqualDeep(expected.bounds, actual.bounds[0..expected.bounds.len]);
    try testing.expectEqualDeep(expected.where_predicates, actual.where_predicates[0..expected.where_predicates.len]);
    try testing.expectEqualDeep(expected.derive_traits, actual.derive_traits[0..expected.derive_traits.len]);
    try testing.expectEqualDeep(expected.template_requirements, actual.template_requirements[0..expected.template_requirements.len]);
    try testing.expectEqualDeep(expected.type_refs, actual.type_refs[0..expected.type_refs.len]);
    try testing.expectEqualDeep(expected.callable_types, actual.callable_types[0..expected.callable_types.len]);
    try testing.expectEqualDeep(expected.variants, actual.variants[0..expected.variants.len]);
    try testing.expectEqualDeep(expected.fields, actual.fields[0..expected.fields.len]);
    try testing.expectEqualDeep(expected.extra, actual.extra[0..expected.extra.len]);
    try testing.expectEqualDeep(expected.call_names, actual.call_names[0..expected.call_names.len]);
    try testing.expectEqualDeep(
        expected.interpolation_formats,
        actual.interpolation_formats[0..expected.interpolation_formats.len],
    );
    try testing.expectEqualDeep(
        expected.struct_literal_heads,
        actual.struct_literal_heads[0..expected.struct_literal_heads.len],
    );
}

test "source ids are a prefix when parsing several modules" {
    const gpa = testing.allocator;
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    defer interner.deinit(gpa);

    const source: Source = .{
        .path = "source.lin",
        .text =
        \\enum Source[T: Copyable] where T: Copyable {
        \\    Value(T),
        \\}
        \\fn build[F: fn(read value: UInt8) -> UInt8](f: F) -> Source[UInt8] where F: Copyable {
        \\    let made: Source[UInt8] = .Value(f(value: 1))
        \\    copy(made)
        \\}
        \\
        ,
    };
    const source_files = [_]ParsedFile{.{ .file = .from(0), .source = source }};
    var source_modules = Modules.init(gpa, &sink, &interner);
    defer source_modules.deinit();
    _ = try source_modules.add(&source_files);
    var source_ast = try source_modules.finish();
    defer source_ast.deinit(gpa);

    try testing.expect(source_ast.tokens.len > 0);
    try testing.expect(source_ast.exprs.len > 0);
    try testing.expect(source_ast.stmts.len > 0);
    try testing.expect(source_ast.blocks.len > 0);
    try testing.expect(source_ast.block_stmts.len > 0);
    try testing.expect(source_ast.decls.len > 0);
    try testing.expect(source_ast.params.len > 0);
    try testing.expect(source_ast.type_params.len > 0);
    try testing.expect(source_ast.bounds.len > 0);
    try testing.expect(source_ast.where_predicates.len > 0);
    try testing.expect(source_ast.type_refs.len > 0);
    try testing.expect(source_ast.callable_types.len > 0);
    try testing.expect(source_ast.variants.len > 0);
    try testing.expect(source_ast.fields.len > 0);
    try testing.expect(source_ast.extra.len > 0);
    try testing.expect(source_ast.call_names.len > 0);

    try testing.expectEqual(Tag.identifier, source_ast.tokenTag(.at(1)));
    try testing.expectEqual(Span{ .start = 5, .end = 11 }, source_ast.tokenSpan(.at(1)));
    try testing.expectEqual(StringId.at(0), source_ast.tokenName(.at(1)));
    try testing.expectEqual(TokenId.at(1), source_ast.declName(.at(0)));
    try testing.expectEqual(TokenId.at(3), source_ast.declTypeParams(.at(0))[0].name);
    try testing.expectEqual(TokenId.at(5), source_ast.bounds[0].named.name);
    try testing.expectEqual(TokenId.at(8), source_ast.declWherePredicates(.at(0))[0].subject.name);
    try testing.expectEqual(TokenId.at(12), source_ast.declVariants(.at(0))[0].name);
    try testing.expectEqual(TokenId.at(14), source_ast.variantFields(source_ast.declVariants(.at(0))[0])[0].written.name);
    try testing.expectEqual(TokenId.at(19), source_ast.declName(.at(1)));
    try testing.expectEqual(TokenId.at(26), source_ast.params[0].name);
    try testing.expectEqual(node.CallableTypeId.at(0), source_ast.bounds[2].callable);
    try testing.expectEqual(TokenId.at(23), source_ast.callable_types[0].at);
    try testing.expectEqual(TokenId.at(31), source_ast.callable_types[0].result.name);
    try testing.expectEqual(TokenId.at(34), source_ast.declParams(.at(1))[0].name);
    try testing.expectEqual(ExprId.at(7), source_ast.declBody(.at(1)));
    try testing.expectEqual(StmtId.at(0), source_ast.blockStmts(source_ast.blockOf(.at(7)))[0]);
    try testing.expectEqual(ExprId.at(4), source_ast.stmtData(.at(0)).init);
    try testing.expectEqual(ExprId.at(6), source_ast.blockOf(.at(7)).tail);
    try testing.expectEqual(ExprId.at(1), source_ast.call(.at(3)).callee);
    try testing.expectEqualSlices(ExprId, &.{ExprId.at(2)}, source_ast.call(.at(3)).args);
    try testing.expectEqualSlices(TokenId, &.{TokenId.at(61)}, source_ast.callNames(.at(3)));
    try testing.expectEqualSlices(ExprId, &.{ ExprId.at(1), ExprId.at(2), ExprId.at(1), ExprId.at(3) }, source_ast.extra);
    try testing.expectEqualSlices(TokenId, &.{ .none, .at(61), .none, .none }, source_ast.call_names);
    try testing.expectEqualDeep(FilePart{
        .file = .from(0),
        .path = source.path,
        .source = source.text,
        .token_start = 0,
        .token_end = 72,
        .decl_start = 0,
        .decl_end = 2,
        .stmt_start = 0,
        .stmt_end = 1,
        .expr_start = 0,
        .expr_end = 8,
    }, source_ast.parts[0]);

    var modules = try Modules.initPrefix(gpa, &sink, &interner, &source_ast);
    defer modules.deinit();

    try testing.expectEqual(source_ast.tokens.len, modules.tokens.len);
    try testing.expectEqual(source_ast.exprs.len, modules.builder.exprs.len);
    try testing.expectEqual(source_ast.stmts.len, modules.builder.stmts.len);
    try testing.expectEqual(source_ast.blocks.len, modules.builder.blocks.items.len);
    try testing.expectEqual(source_ast.block_stmts.len, modules.builder.block_stmts.items.len);
    try testing.expectEqual(source_ast.decls.len, modules.builder.decls.len);
    try testing.expectEqual(source_ast.params.len, modules.builder.params.items.len);
    try testing.expectEqual(source_ast.type_params.len, modules.builder.type_params.items.len);
    try testing.expectEqual(source_ast.bounds.len, modules.builder.bounds.items.len);
    try testing.expectEqual(source_ast.where_predicates.len, modules.builder.where_predicates.items.len);
    try testing.expectEqual(source_ast.derive_traits.len, modules.builder.derive_traits.items.len);
    try testing.expectEqual(source_ast.template_requirements.len, modules.builder.template_requirements.items.len);
    try testing.expectEqual(source_ast.type_refs.len, modules.builder.type_refs.items.len);
    try testing.expectEqual(source_ast.callable_types.len, modules.builder.callable_types.items.len);
    try testing.expectEqual(source_ast.variants.len, modules.builder.variants.items.len);
    try testing.expectEqual(source_ast.fields.len, modules.builder.fields.items.len);
    try testing.expectEqual(source_ast.extra.len, modules.builder.extra.items.len);
    try testing.expectEqual(source_ast.call_names.len, modules.builder.call_names.items.len);
    try testing.expectEqual(source_ast.parts.len, modules.parts.items.len);
    const prefix = modules.view();
    try expectSourcePrefix(&source_ast, &prefix);
    try testing.expect(source_ast.parts.ptr != modules.parts.items.ptr);
    try testing.expect(source_ast.tokens.items(.tag).ptr != modules.tokens.items(.tag).ptr);
    try testing.expect(source_ast.decls.items(.tag).ptr != modules.builder.decls.items(.tag).ptr);
    try testing.expect(source_ast.parts[0].source.ptr == modules.parts.items[0].source.ptr);
    try testing.expect(source_ast.parts[0].path.ptr == modules.parts.items[0].path.ptr);

    const generated: Source = .{ .path = "generated.lin", .text = "fn Generated() -> UInt8 { 1 }\n" };
    const generated_files = [_]ParsedFile{.{ .file = .from(1), .source = generated }};
    _ = try modules.add(&generated_files);
    var expanded = try modules.finish();
    defer expanded.deinit(gpa);

    try testing.expectEqual(@as(u32, 0), sink.error_count);
    try expectSourcePrefix(&source_ast, &expanded);
    try testing.expectEqualDeep(source_ast.parts[0], expanded.parts[0]);
    try testing.expectEqual(Tag.identifier, expanded.tokenTag(.at(1)));
    try testing.expectEqual(Span{ .start = 5, .end = 11 }, expanded.tokenSpan(.at(1)));
    try testing.expectEqual(StringId.at(0), expanded.tokenName(.at(1)));
    try testing.expectEqual(node.DeclId.at(0), node.DeclId.at(expanded.parts[0].decl_start));
    try testing.expectEqual(TokenId.at(1), expanded.declName(.at(0)));
    try testing.expectEqualDeep(FilePart{
        .file = .from(1),
        .path = generated.path,
        .source = generated.text,
        .token_start = 72,
        .token_end = 82,
        .decl_start = 2,
        .decl_end = 3,
        .stmt_start = 1,
        .stmt_end = 1,
        .expr_start = 8,
        .expr_end = 10,
    }, expanded.parts[1]);
    try testing.expectEqual(node.DeclId.at(2), node.DeclId.at(expanded.parts[1].decl_start));
    try testing.expectEqual(TokenId.at(73), expanded.declName(.at(2)));
}

test "a malformed general trailing where clause leaves the following declaration parseable" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = try parseProgramText(gpa,
        \\struct Box[T] where T Copyable { value: T }
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expect(got.errors > 0);
    try testing.expect(std.mem.indexOf(u8, got.dump, "decl function \"main\"") != null);
}

test "a trailing where clause requires a predicate" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const got = try parseProgramText(arena.allocator(), "fn main() -> UInt8 where { 0 }");
    try testing.expect(got.errors > 0);
}

test "a written type carries its arguments" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Wherever a type may be written: a field, a variant's payload, a
    // parameter, a return type and an annotation. An argument is a written
    // type in its own right, so a nested one needs no second shape.
    const got = try parseProgramText(gpa,
        \\struct Inner[T] { v: T }
        \\struct Outer[T] { held: Inner[T] }
        \\enum Maybe[T] { None, Some(Inner[T]) }
        \\fn take(a: Inner[UInt8]) -> Inner[UInt8] { a }
        \\fn main() -> UInt8 { let m: Maybe[Inner[UInt8]] = .None; 1 }
    );
    try testing.expect(std.mem.indexOf(u8, got.dump, "field \"held\" : Inner[T]") != null);
    try testing.expect(std.mem.indexOf(u8, got.dump, "variant \"Some\" : Inner[T]") != null);
    try testing.expect(std.mem.indexOf(u8, got.dump, "param read \"a\" : Inner[UInt8]") != null);
}

test "borrow and grouped types are valid nested arguments" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const codes = try codesOf(arena.allocator(),
        \\struct Pair[A, B] { first: A, second: B }
        \\fn accept(a: Pair[(), borrow UInt8], b: Pair[(UInt8), ()]) {}
    );
    try testing.expectEqual(@as(usize, 0), codes.len);
}

test "a bound list is names and nothing more" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Bounds retain their names. Resolution distinguishes a built-in
    // capability from a declared trait.
    const got = try parseProgramText(gpa,
        \\struct Pair[A: Copyable + Weigh] { x: A }
        \\fn main() -> UInt8 { let p: Pair = .{ x = 1 }; p.x }
    );
    try testing.expect(std.mem.indexOf(u8, got.dump, "type param \"A\" : Copyable + Weigh") != null);
}

test "a structural callable is a written type and a bound" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = try parseProgramText(gpa,
        \\fn apply[F: fn(read value: UInt8 = 2) -> UInt8](f: F) -> UInt8 { f() }
        \\fn keep(f: fn(read value: UInt8 = 2) -> UInt8) {}
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expectEqual(@as(u32, 0), got.errors);
    try testing.expect(std.mem.indexOf(u8, got.dump, "fn(read value: UInt8 = 2) -> UInt8") != null);
}

test "a trait declares a type and an implementation settles it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // One form on both sides, told apart by whether anything was settled: the
    // trait's side asks for a type and says nothing about what it is.
    const got = try parseProgramText(gpa,
        \\struct C { x: UInt8 }
        \\trait M { type Item }
        \\impl M for C { type Item = UInt8 }
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expect(std.mem.indexOf(u8, got.dump, "decl associated_type \"Item\"") != null);
    try testing.expect(std.mem.indexOf(u8, got.dump, "settles UInt8") != null);
}

test "a declared type carries bounds, and only on the side that asks" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // The bound list a type parameter takes, read by the same routine, so the
    // `+` chain and the diagnostic for a missing name come with the position
    // rather than being written again for it.
    const asked = try parseProgramText(gpa,
        \\trait I { type X }
        \\trait W { type Y }
        \\trait M { type Item: I + W }
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expectEqual(@as(u32, 0), asked.errors);
    try testing.expect(std.mem.indexOf(u8, asked.dump, "requires I + W") != null);

    // What a settling must satisfy is the trait's to say, so a bound written
    // where one is settled is refused.
    const answered = try parseProgramText(gpa,
        \\struct C { x: UInt8 }
        \\trait M { type Item: Copyable }
        \\impl M for C { type Item: Copyable = UInt8 }
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expect(answered.errors > 0);
}

test "a trait declares a projection and an implementation gives it a body" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // One header on both sides, told apart by the body: the trait's side is a
    // signature and ends at the line break, and the implementation's holds the
    // path a site becomes.
    const got = try parseProgramText(gpa,
        \\struct C { cells: [UInt8; 2] }
        \\trait I { proj at(inout self: Self, i: UInt64) -> UInt8 }
        \\impl I for C { proj at(inout self: C, i: UInt64) -> UInt8 { self.cells[i] } }
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expectEqual(@as(u32, 0), got.errors);
    try testing.expect(std.mem.indexOf(u8, got.dump, "decl projection \"at\"") != null);
    try testing.expect(std.mem.indexOf(u8, got.dump, "yields UInt8") != null);
}

test "`proj` is a member only where a name follows it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Contextual for the reason `type` is: the word binds like any other noun,
    // and a member begins with it only where a name comes next.
    const got = try parseProgramText(gpa,
        \\fn main() -> UInt8 { let proj: UInt8 = 3; proj }
    );
    try testing.expect(std.mem.indexOf(u8, got.dump, "\"proj\" : UInt8") != null);
    try testing.expect(std.mem.indexOf(u8, got.dump, "projection") == null);
}

test "`type` is a member only where a name follows it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // The word is not reserved, so it binds like any other noun. A member
    // begins with it only inside a trait's braces or an implementation's, and
    // only where a name comes next.
    const got = try parseProgramText(gpa,
        \\fn main() -> UInt8 { let type: UInt8 = 3; type }
    );
    try testing.expect(std.mem.indexOf(u8, got.dump, "\"type\" : UInt8") != null);
    try testing.expect(std.mem.indexOf(u8, got.dump, "associated_type") == null);
}

test "a declared type is written on one side and settled on the other" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // A trait that settled one would answer its own question, and which answer
    // the type had would be decided by whichever a reader reached first.
    const asked = try parseProgramText(gpa,
        \\trait M { type Item = UInt8 }
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expect(asked.errors > 0);

    // An implementation of a trait is where it is settled, and nothing is
    // reported there.
    const answered = try parseProgramText(gpa,
        \\struct C { x: UInt8 }
        \\trait M { type Item }
        \\impl M for C { type Item = UInt8 }
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expectEqual(@as(u32, 0), answered.errors);
}

test "an inherent impl settles no type, and a settled one takes no `pub`" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // A declared type is a trait's member, so an implementation naming no
    // trait has nothing to settle.
    const inherent = try parseProgramText(gpa,
        \\struct C { x: UInt8 }
        \\impl C { type Item = UInt8 }
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expect(inherent.errors > 0);

    // What an implementation supplies is the trait's and is reachable wherever
    // the trait is, so `pub` on one would say nothing.
    const exported = try parseProgramText(gpa,
        \\struct C { x: UInt8 }
        \\trait M { type Item }
        \\impl M for C { pub type Item = UInt8 }
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expect(exported.errors > 0);
}

test "written selections follow applied grouped and chained bases" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const got = try parseProgramText(arena.allocator(),
        \\fn first[T](_value: Box[T].Item) -> module.Box[T].Item { panic("unused") }
        \\fn second[T](_value: (Box[T]).Item.Next) -> [UInt8; 2].Item { panic("unused") }
        \\fn third[T](_value: (fn(read value: T) -> T).Item) {}
    );
    try testing.expectEqual(@as(u32, 0), got.errors);
    try testing.expect(std.mem.indexOf(u8, got.dump, "module.Box[T].Item") != null);
    try testing.expect(std.mem.indexOf(u8, got.dump, "(Box[T]).Item.Next") != null);
    try testing.expect(std.mem.indexOf(u8, got.dump, "[UInt8; 2].Item") != null);
}

test "written selection missing member preserves following declarations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const source: Source = .{ .path = "t.lin", .text =
        \\fn broken[T](_value: Box[T].) {}
        \\fn main() -> UInt8 { 0 }
    };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    try testing.expect(sink.hasErrors());
    const written = ast.params[0].written;
    try testing.expectEqual(node.TypeRef.Kind.selection, written.kind);
    try testing.expect(written.wasWritten());
    try testing.expectEqual(TokenId.none, written.name);
    try testing.expectEqual(Tag.dot, ast.tokenTag(written.dot));
    try testing.expectEqualStrings("Box", ast.tokenText(ast.selectionBase(written).name));
    try testing.expectEqualStrings("Box[T].", source.text[ast.writtenSpan(written).start..ast.writtenSpan(written).end]);
    try testing.expectEqual(@as(usize, 2), ast.decls.len);
}

test "written selection height includes its completed base" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var source: std.ArrayList(u8) = .empty;
    try source.appendSlice(gpa, "fn consume(_value: ");
    for (0..max_nesting / 2) |_| try source.appendSlice(gpa, "Box[");
    try source.appendSlice(gpa, "UInt8");
    for (0..max_nesting / 2) |_| try source.append(gpa, ']');
    for (0..max_nesting / 2 + 1) |_| try source.appendSlice(gpa, ".Item");
    try source.appendSlice(gpa, ") {}\nfn main() -> UInt8 { 0 }");
    const codes = try codesOf(gpa, source.items);
    const found = for (codes) |code| {
        if (code == .s_nesting) break true;
    } else false;
    try testing.expect(found);
}

test "a settled reference is a written type" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // `Self.Item` is read where any type may be written, and the whole run of
    // names is recorded. What it names is a question about names, asked where
    // every other one is.
    const got = try parseProgramText(gpa,
        \\trait M { type Item, fn of(s: Self) -> Self.Item }
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expect(std.mem.indexOf(u8, got.dump, "returns Self.Item") != null);
}

test "a test is a function carrying one modifier" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Nothing but the prefix distinguishes it. What follows is parsed by the
    // rule that parses every other function, which is the whole claim the
    // modifier makes.
    const plain = try parseProgramText(gpa,
        \\test fn a_thing_holds() -> Result[(), IoError] { return .Ok(()) }
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expectEqual(@as(u32, 0), plain.errors);

    // The compiler writes the only call to a test, so `pub` exports a name no
    // import can reach -- a modifier saying nothing, which is what an `impl`
    // modifier already breaks.
    const exported = try parseProgramText(gpa,
        \\pub test fn a_thing_holds() -> Result[(), IoError] { return .Ok(()) }
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expect(exported.errors > 0);

    // A type declares no body, so there is nothing for the compiler to run.
    const typed = try parseProgramText(gpa,
        \\test struct Box { x: UInt8 }
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expect(typed.errors > 0);

    // An `impl` declares no name and no body of its own either.
    const implemented = try parseProgramText(gpa,
        \\struct P { x: UInt8 }
        \\test impl P { pub fn get(p: P) -> UInt8 { copy(p.x) } }
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expect(implemented.errors > 0);
}

test "an impl takes no modifier" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Both were parsed into slots the `impl` branch never reads, so a modifier
    // here said nothing and nothing said so. An `impl` declares no name for
    // `pub` to export and no type for `linear` to describe.
    const marked = try parseProgramText(gpa,
        \\struct P { x: UInt8 }
        \\pub impl P { pub fn get(p: P) -> UInt8 { copy(p.x) } }
        \\fn main() -> UInt8 { let p: P = .{ x = 1 }; P.get(p) }
    );
    try testing.expect(marked.errors > 0);

    const linear = try parseProgramText(gpa,
        \\struct P { x: UInt8 }
        \\linear impl P { pub fn get(p: P) -> UInt8 { copy(p.x) } }
        \\fn main() -> UInt8 { let p: P = .{ x = 1 }; P.get(p) }
    );
    try testing.expect(linear.errors > 0);

    // The members carry their own, and the type carries its own.
    const plain = try parseProgramText(gpa,
        \\@linear
        \\struct P { x: UInt8 }
        \\impl P { pub fn get(p: P) -> UInt8 { copy(p.x) } }
        \\fn main() -> UInt8 { let p: P = .{ x = 1 }; P.get(p) }
    );
    try testing.expectEqual(@as(u32, 0), plain.errors);
}

test "`match read` is a tag of its own" {
    // A flag beside `match_` would make every pass that cares re-derive the
    // difference, and the pass that cares most is the one that has not been
    // written yet.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = try parseProgramText(gpa,
        \\enum Colour { Red, Green }
        \\fn look(c: Colour) -> UInt8 { match read c { Red => 1, Green => 2 } }
        \\fn main() -> UInt8 { look(.Red) }
    );
    try testing.expectEqual(@as(u32, 0), got.errors);
    try testing.expect(std.mem.indexOf(u8, got.dump, "match_read") != null);
    try testing.expect(std.mem.indexOf(u8, got.dump, "match_ ") == null);
}

test "a refinement clause ends at a break inside a bound" {
    // The clause is the line its `where` opens, so the boundary between a
    // bound's `-` and its digits is a break like any other in it.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const codes = try codesOf(gpa,
        \\pub type Percent = Int8 where it in -
        \\    5..=99
        \\
        \\fn main() -> UInt8 { 42 }
        \\
    );
    try testing.expectEqualSlices(?Code, &.{ .s_separator, .s_entry }, codes);
}

test "the end of the file ends a refinement clause the way a break does" {
    // What the file ends with cannot change what it reports: a clause the
    // last line runs out of is refused whether or not a newline follows it.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const without = try codesOf(gpa, "pub type Percent = UInt8 where");
    const with = try codesOf(gpa, "pub type Percent = UInt8 where\n");
    try testing.expectEqualSlices(?Code, &.{.s_separator}, without);
    try testing.expectEqualSlices(?Code, without, with);
}

test "an interpolation records each value's format" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const got = try parseProgramText(arena.allocator(),
        \\fn show(x: UInt8) -> Str { "{x} {x:?}" }
    );
    try testing.expectEqual(@as(u32, 0), got.errors);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, got.dump, "format display"));
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, got.dump, "format debug"));
}

test "an interpolation records the layout its format spec asks for" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const got = try parseProgramText(arena.allocator(),
        \\fn show(x: UInt8) -> Str { "{x:>4} {x:*^+6?}" }
    );
    try testing.expectEqual(@as(u32, 0), got.errors);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, got.dump, "format display >4"));
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, got.dump, "format debug *^+6?"));
}

test "an interpolation format spec is refused where it is empty or misspelled" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const codes = try codesOf(arena.allocator(),
        \\fn empty(x: UInt8) -> Str { "{x:}" }
        \\fn named(x: UInt8) -> Str { "{x:name}" }
        \\fn after() -> UInt8 { 0 }
    );
    try testing.expectEqualSlices(?Code, &.{ .s_format, .s_format }, codes);
}

test "a range pattern is read across a line break" {
    // A pattern is an expression and ends where one ends. The break a
    // refinement clause refuses is nothing to a range written in an arm, at
    // any of the boundaries a range has.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = try parseProgramText(gpa,
        \\fn classify(n: Int8) -> UInt8 {
        \\    match read n {
        \\        -
        \\        9..=-5 => 1,
        \\        0
        \\        ..=4 => 2,
        \\        5..=
        \\        9 => 3,
        \\        _ => 0,
        \\    }
        \\}
        \\
    );
    try testing.expectEqual(@as(u32, 0), got.errors);
    try testing.expectEqual(@as(usize, 3), std.mem.count(u8, got.dump, "range"));
}

test "a carrier mark attaches to a struct or an enum and is refused on a newtype" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const accepted = try parseProgramText(gpa,
        \\@carrier
        \\struct Session { user: Str }
        \\@(copyable, carrier)
        \\enum Visit { Page, Home }
    );
    try testing.expectEqual(@as(u32, 0), accepted.errors);
    const newtype = try parseProgramText(gpa,
        \\@carrier
        \\type Count = UInt8
    );
    try testing.expectEqual(@as(u32, 1), newtype.errors);
    const repeated = try parseProgramText(gpa,
        \\@(carrier, carrier)
        \\struct Session { user: Str }
    );
    try testing.expectEqual(@as(u32, 1), repeated.errors);
}

test "every word that starts a declaration is consumed when written bare" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const words = [_][]const u8{
        "pub",    "internal", "export", "opaque", "linear", "copyable", "carrier", "test", "template", "derive",
        "impl",   "fn",       "import", "use",    "enum",   "struct",   "let",     "type", "alias",    "trait",
        "extern", "default",  "@",
    };
    for (words) |word| {
        // Parsing returns only if recovery steps over the word.
        _ = try parseProgramText(gpa, word);
        const before_a_struct = try std.fmt.allocPrint(gpa, "{s} struct A {{ x: Str }}\n", .{word});
        _ = try parseProgramText(gpa, before_a_struct);
        const after_pub = try std.fmt.allocPrint(gpa, "pub {s} struct A {{ x: Str }}\n", .{word});
        _ = try parseProgramText(gpa, after_pub);
    }
    const bare = try parseProgramText(gpa, "carrier struct A { x: Str }\n");
    try testing.expectEqual(@as(u32, 1), bare.errors);
}

test "copyable declarations preserve policy and reject conflicting modifiers" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const accepted = try parseProgramText(gpa,
        \\@copyable
        \\struct Point { value: UInt8 }
        \\@copyable
        \\enum Switch { Off, On }
        \\@copyable
        \\type Counter = UInt64
    );
    try testing.expectEqual(@as(u32, 0), accepted.errors);
    try testing.expect(std.mem.indexOf(u8, accepted.dump, "decl copyable struct_") != null);
    const refused = try parseProgramText(gpa,
        \\@(linear, copyable)
        \\struct Point { value: UInt8 }
    );
    try testing.expect(refused.errors > 0);
}

test "a missing attribute comma preserves the remaining group and declaration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const got = try parseProgramText(arena.allocator(),
        \\@(copyable derive(Equatable))
        \\struct Point { value: UInt8 }
    );
    try testing.expectEqual(@as(u32, 1), got.errors);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, got.dump, "decl copyable struct_"));
    try testing.expectEqual(@as(usize, 0), std.mem.count(u8, got.dump, "decl derive_impl"));
}

test "attribute recovery preserves a following standalone derive" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const got = try parseProgramText(arena.allocator(),
        \\@(copyable
        \\derive Mark for Point
        \\struct Point { value: UInt8 }
    );
    try testing.expect(got.errors > 0);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, got.dump, "decl derive_impl"));
}

test "attribute recovery reports each malformed prefix once" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const cases = [_]struct { text: []const u8, message: []const u8, keeps: []const u8 }{
        .{ .text = "pub linear struct P { x: UInt8 }", .message = "type policies are declaration attributes", .keeps = "decl pub struct_" },
        .{ .text = "pub @linear\nstruct P { x: UInt8 }", .message = "attributes precede the visibility", .keeps = "decl pub linear struct_" },
        .{ .text = "@derive struct P { x: UInt8 }", .message = "derive attributes carry a parenthesized trait list", .keeps = "struct_" },
        .{ .text = "@(derive)\nstruct P { x: UInt8 }", .message = "derive attributes carry a parenthesized trait list", .keeps = "struct_" },
        .{ .text = "@(linear\nstruct P { x: UInt8 }", .message = "expected `)`", .keeps = "decl linear struct_" },
        .{ .text = "@(foo bar)\nstruct P { x: UInt8 }", .message = "attribute names are closed", .keeps = "struct_" },
        .{ .text = "@\nfn main() -> UInt8 { 0 }", .message = "expected an attribute name after `@`", .keeps = "\"main\"" },
        .{ .text = "fn main() -> UInt8 { 0 }\n@", .message = "expected an attribute name after `@`", .keeps = "\"main\"" },
    };
    for (cases) |case| {
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        const source: Source = .{ .path = "t.lin", .text = case.text };
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        _ = try parse(gpa, &source, .from(0), tokens, &sink);
        if (sink.items().len != 1) {
            for (sink.items()) |item| std.debug.print("{s}: {s}\n", .{ case.text, item.message });
        }
        try testing.expectEqual(@as(usize, 1), sink.items().len);
        try testing.expectEqualStrings(case.message, sink.items()[0].message);
        const got = try parseProgramText(gpa, case.text);
        if (std.mem.indexOf(u8, got.dump, case.keeps) == null) std.debug.print("{s}\n{s}\n", .{ case.text, got.dump });
        try testing.expect(std.mem.indexOf(u8, got.dump, case.keeps) != null);
    }
}

test "attributes after the visibility keep their policy and derives" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const source: Source = .{ .path = "t.lin", .text =
        \\@derive(Debug) pub @linear @derive(Equatable)
        \\struct P { x: UInt8 }
    };
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    const ast = try parse(gpa, &source, .from(0), tokens, &sink);
    try testing.expectEqual(@as(usize, 1), sink.items().len);
    try testing.expectEqualStrings("attributes precede the visibility", sink.items()[0].message);
    const d = for (0..ast.declCount()) |i| {
        const id = node.DeclId.at(@intCast(i));
        if (ast.declTag(id) == .struct_) break id;
    } else return error.TestUnexpectedResult;
    try testing.expectEqual(node.OwnershipPolicy.linear, ast.declOwnershipPolicy(d));
    try testing.expectEqual(node.Visibility.pub_, ast.declVisibility(d));
    try testing.expectEqual(@as(usize, 2), ast.attachedDeriveTraitRange(d).len());
}

test "a dangling attribute reports its missing nominal declaration once" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const source: Source = .{ .path = "t.lin", .text =
        \\fn main() -> UInt8 { 0 }
        \\@copyable
    };
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    _ = try parse(gpa, &source, .from(0), tokens, &sink);
    try testing.expectEqual(@as(usize, 1), sink.items().len);
    try testing.expectEqualStrings("an attribute requires a nominal type declaration", sink.items()[0].message);
}

test "record shorthand keeps distinct expressions over one written name" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const source: Source = .{ .path = "t.lin", .text = "fn make() -> Entry { .{ key, value = value } }" };
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    try testing.expectEqual(@as(u32, 0), sink.error_count);
    const value = ast.blockOf(ast.declBody(node.DeclId.at(0))).tail;
    const fields = ast.call(value).args;
    try testing.expectEqual(@as(usize, 4), fields.len);
    try testing.expect(fields[0] != fields[1]);
    try testing.expect(ast.fieldIsShorthand(fields[0], fields[1]));
    try testing.expectEqual(Expr.Tag.name_ref, ast.exprTag(fields[1]));
    try testing.expect(!ast.fieldIsShorthand(fields[2], fields[3]));
}

test "transparent observations preserve unary and postfix precedence" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const source: Source = .{ .path = "t.lin", .text = "fn first() -> UInt8 { *view.field }\nfn second() -> UInt8 { (*view).field }\nfn third() -> UInt8 { **view }" };
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    try testing.expectEqual(@as(u32, 0), sink.error_count);
    const first = ast.blockOf(ast.declBody(node.DeclId.at(0))).tail;
    try testing.expectEqual(Expr.Tag.dereference, ast.exprTag(first));
    try testing.expectEqual(Expr.Tag.field, ast.exprTag(ast.unaryOperand(first)));
    const second = ast.blockOf(ast.declBody(node.DeclId.at(1))).tail;
    try testing.expectEqual(Expr.Tag.field, ast.exprTag(second));
    const group = ast.unaryOperand(second);
    try testing.expectEqual(Expr.Tag.grouped, ast.exprTag(group));
    try testing.expectEqual(Expr.Tag.dereference, ast.exprTag(ast.unaryOperand(group)));
    const third = ast.blockOf(ast.declBody(node.DeclId.at(2))).tail;
    try testing.expectEqual(Expr.Tag.dereference, ast.exprTag(third));
    try testing.expectEqual(Expr.Tag.dereference, ast.exprTag(ast.unaryOperand(third)));
    var steps = ast.placeSteps(second);
    try testing.expectEqual(second, steps.next().?);
    try testing.expectEqual(ast.unaryOperand(group), steps.next().?);
    try testing.expectEqual(@as(?ExprId, null), steps.next());
}

test "transparent observation contract paths settle projection order" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const source: Source = .{ .path = "t.lin", .text = "fn inspect(view: borrow Holder) where carries(*view.item, (*view).item, **view) {}" };
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    try testing.expectEqual(@as(u32, 0), sink.error_count);
    const contracts = ast.declContracts(node.DeclId.at(0));
    try testing.expectEqual(@as(usize, 3), contracts.len);
    for (contracts) |contract| try testing.expectEqualStrings("view", ast.tokenText(contract.source.root));
    const first = ast.contractSteps(contracts[0].source);
    const second = ast.contractSteps(contracts[1].source);
    const third = ast.contractSteps(contracts[2].source);
    try testing.expectEqual(@as(usize, 2), first.len);
    try testing.expectEqual(@as(usize, 2), second.len);
    try testing.expectEqual(@as(usize, 2), third.len);
    try testing.expect(first[0] == .field and first[1] == .dereference);
    try testing.expect(second[0] == .dereference and second[1] == .field);
    try testing.expect(third[0] == .dereference and third[1] == .dereference);
}

test "transparent observation malformed contract paths recover" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const parsed = try parseProgramText(arena.allocator(), "fn broken(view: borrow UInt8) where carries(*) {}\nfn next() -> UInt8 { 0 }");
    try testing.expect(parsed.errors > 0);
    try testing.expect(std.mem.indexOf(u8, parsed.dump, "next") != null);
}

test "read capture defaults preserve explicit conventions and array expressions" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const source: Source = .{ .path = "t.lin", .text = "fn omitted() -> UInt8 { [item] || item }\n" ++
        "fn alias() -> UInt8 { [part = items[0]] || part }\n" ++
        "fn explicit() -> UInt8 { read [read item] || item }\n" ++
        "fn empty() -> UInt8 { [] || 0 }\n" ++
        "fn array() -> UInt8 { [item, other + 1] }" };
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    try testing.expectEqual(@as(u32, 0), sink.error_count);
    for (0..4) |i| {
        const expr = ast.blockOf(ast.declBody(node.DeclId.at(@intCast(i)))).tail;
        try testing.expectEqual(Expr.Tag.lambda, ast.exprTag(expr));
        const lambda = ast.lambda(expr);
        try testing.expectEqual(node.Convention.read, lambda.invocation);
        try testing.expectEqual(i == 2, lambda.invocation_token != .none);
        if (i != 3) {
            try testing.expectEqual(@as(usize, 1), lambda.captures.len);
            try testing.expectEqual(node.Convention.read, lambda.captures[0].convention);
            try testing.expectEqual(i == 2, lambda.captures[0].convention_token != .none);
        }
    }
    const array = ast.blockOf(ast.declBody(node.DeclId.at(4))).tail;
    try testing.expectEqual(Expr.Tag.array_literal, ast.exprTag(array));
}

test "read capture alias initializers parse nested arrays and lambdas" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const parsed = try parseProgramText(
        arena.allocator(),
        "fn nested() -> UInt8 { [part = [item][0], callback = [item] || item] || callback() + part }",
    );
    try testing.expectEqual(@as(u32, 0), parsed.errors);
    const malformed = try parseProgramText(arena.allocator(), "fn malformed() -> UInt8 { [item + 1] |value| value }");
    try testing.expect(malformed.errors > 0);
}

test "read capture syntax preserves arrays of explicitly moded lambdas" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    for ([_][]const u8{
        "fn values() -> UInt8 { [read [] || 0, read [] || 1] }",
        "fn values() -> UInt8 { [sink [] || 0] }",
        "fn values() -> UInt8 { [|| 0, || 1] }",
    }) |source| {
        const parsed = try parseProgramText(arena.allocator(), source);
        try testing.expectEqual(@as(u32, 0), parsed.errors);
        try testing.expect(std.mem.indexOf(u8, parsed.dump, "array_literal") != null);
    }
}

test "callable invocation modes parse in generic bounds" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const source: Source = .{ .path = "t.lin", .text = "fn apply[R: read fn() -> UInt8, M: inout fn() -> UInt8, S: sink fn() -> UInt8](r: R, inout m: M, sink s: S) -> UInt8 { r() + &m() + s() }" };
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    const ast = try parse(gpa, &source, .from(0), tokens, &sink);
    try testing.expectEqual(@as(u32, 0), sink.error_count);
    try testing.expectEqual(@as(usize, 3), ast.callable_types.len);
    for (ast.callable_types, [_]node.Convention{ .read, .inout, .sink }) |callable, invocation| {
        try testing.expectEqual(invocation, callable.invocation);
        try testing.expect(callable.invocation_token != .none);
    }
}

test "a call's marker binds before arithmetic and argument conventions" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const source: Source = .{ .path = "t.lin", .text = "fn arithmetic() -> UInt8 { &callback() + 1 }\n" ++
        "fn argument() -> UInt8 { assert_eq(&callback(), 1) }\n" ++
        "fn propagation() -> UInt8 { &callback()? }\n" ++
        "fn places() -> UInt8 { update(&(record.field), &items[0], &*view) }\n" ++
        "fn projection() -> UInt8 { &record.callback().field }\n" ++
        "fn indexed() -> UInt8 { &callbacks[0]() }\n" ++
        "fn receiver() -> UInt8 { &tally.counter.push(1).total() }" };
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    const ast = try parse(gpa, &source, .from(0), tokens, &sink);
    try testing.expectEqual(@as(u32, 0), sink.error_count);
    const arithmetic = ast.blockOf(ast.declBody(node.DeclId.at(0))).tail;
    try testing.expectEqual(Expr.Tag.add, ast.exprTag(arithmetic));
    try testing.expectEqual(Expr.Tag.call, ast.exprTag(ast.binary(arithmetic).lhs));
    try testing.expect(ast.callMarked(ast.binary(arithmetic).lhs));
    const argument = ast.blockOf(ast.declBody(node.DeclId.at(1))).tail;
    try testing.expectEqual(Expr.Tag.call, ast.exprTag(ast.call(argument).args[0]));
    try testing.expect(!ast.callMarked(argument));
    try testing.expect(ast.callMarked(ast.call(argument).args[0]));
    const propagation = ast.blockOf(ast.declBody(node.DeclId.at(2))).tail;
    try testing.expectEqual(Expr.Tag.try_, ast.exprTag(propagation));
    try testing.expectEqual(Expr.Tag.call, ast.exprTag(ast.unaryOperand(propagation)));
    try testing.expect(ast.callMarked(ast.unaryOperand(propagation)));
    const places = ast.blockOf(ast.declBody(node.DeclId.at(3))).tail;
    for (ast.call(places).args) |arg| try testing.expectEqual(Expr.Tag.marked, ast.exprTag(arg));
    const projection = ast.blockOf(ast.declBody(node.DeclId.at(4))).tail;
    try testing.expectEqual(Expr.Tag.field, ast.exprTag(projection));
    const projected_call = ast.unaryOperand(projection);
    try testing.expectEqual(Expr.Tag.call, ast.exprTag(projected_call));
    try testing.expect(ast.callMarked(projected_call));
    try testing.expectEqual(Expr.Tag.field, ast.exprTag(ast.call(projected_call).callee));
    const indexed = ast.blockOf(ast.declBody(node.DeclId.at(5))).tail;
    try testing.expect(ast.callMarked(indexed));
    try testing.expectEqual(Expr.Tag.index, ast.exprTag(ast.call(indexed).callee));
    // `&a.b.push(x).total()` marks the first call, whose callee selects
    // `push` from the place `a.b`; the call after it is unmarked.
    const outer = ast.blockOf(ast.declBody(node.DeclId.at(6))).tail;
    try testing.expect(!ast.callMarked(outer));
    const first = ast.unaryOperand(ast.call(outer).callee);
    try testing.expect(ast.callMarked(first));
    const push = ast.call(first).callee;
    try testing.expectEqualStrings("push", ast.tokenText(ast.exprMain(push)));
    try testing.expectEqual(Expr.Tag.field, ast.exprTag(ast.unaryOperand(push)));
}

test "lambda result annotations parse types and contracts after an arrow" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const source: Source = .{ .path = "contracts.lin", .text =
        \\fn main() -> UInt8 {
        \\    let inspect = [owner] |value: borrow UInt8| -> where carries(value), borrows(owner) value
        \\    let store = inout [sink held] |input: borrow UInt8| -> UInt8 where retains(held: input) { held = copy(input); 0 }
        \\    0
        \\}
    };
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    const ast = try parse(gpa, &source, .from(0), tokens, &sink);
    try testing.expectEqual(@as(u32, 0), sink.error_count);
    var found: usize = 0;
    for (ast.exprs.items(.tag), 0..) |tag, i| {
        if (tag != .lambda) continue;
        const lambda = ast.lambda(ExprId.at(@intCast(i)));
        const contracts = ast.contracts[lambda.contracts.start..lambda.contracts.end];
        try testing.expect(lambda.result_arrow != .none);
        try testing.expectEqual(found != 0, lambda.result.wasWritten());
        try testing.expectEqual(@as(usize, if (found == 0) 2 else 1), contracts.len);
        if (found == 0) {
            try testing.expectEqual(.carries, contracts[0].kind);
            try testing.expectEqual(.borrows, contracts[1].kind);
            try testing.expectEqualStrings("owner", ast.tokenText(contracts[1].source.root));
        } else {
            try testing.expectEqual(.retains, contracts[0].kind);
            try testing.expectEqualStrings("held", ast.tokenText(contracts[0].destination.root));
        }
        found += 1;
    }
    try testing.expectEqual(@as(usize, 2), found);
    var prefix = try Ast.Builder.initPrefix(gpa, &ast);
    defer prefix.deinit();
    try testing.expectEqualDeep(ast.contracts, prefix.contracts.items);
    try testing.expectEqualDeep(ast.contract_steps, prefix.contract_steps.items);
    try testing.expectEqualSlices(ExprId, ast.extra, prefix.extra.items);
}

test "lambda result annotations reject old contracts and recover malformed results" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const cases = [_][]const u8{
        "fn main() -> UInt8 { let f = || -> where carries(*) {}; 0 }\nfn next() -> UInt8 { 0 }",
        "fn main() -> UInt8 { let f = || carries(value) {}; 0 }\nfn next() -> UInt8 { 0 }",
        "fn main() -> UInt8 { let f = || -> {}; 0 }\nfn next() -> UInt8 { 0 }",
        "fn main() -> UInt8 { let f = || -> UInt8, 7; 0 }\nfn next() -> UInt8 { 0 }",
        "fn main() -> UInt8 { let f = || -> fn() -> UInt8, || 7; 0 }\nfn next() -> UInt8 { 0 }",
        "fn main() -> UInt8 { let f = || -> where borrows(value); 0 }\nfn next() -> UInt8 { 0 }",
    };
    for (cases) |source| {
        const parsed = try parseProgramText(arena.allocator(), source);
        try testing.expect(parsed.errors > 0);
        try testing.expect(std.mem.indexOf(u8, parsed.dump, "next") != null);
    }
}

test "lambda result annotations preserve explicit and inferred result types" {
    const cases = [_]struct { source: []const u8, written: bool, arrow: bool }{
        .{ .source = "fn main() -> UInt8 { let f = || { 0 }; f() }", .written = false, .arrow = false },
        .{ .source = "fn main() -> UInt8 { let f = [number] || -> where borrows(number) { borrow number }; 0 }", .written = false, .arrow = true },
        .{ .source = "fn main() -> UInt8 { let f = [number] || -> borrow UInt8 where borrows(number) { borrow number }; 0 }", .written = true, .arrow = true },
        .{ .source = "fn main() -> UInt8 { let f = || -> [UInt8; 2] { [1, 2] }; 0 }", .written = true, .arrow = true },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        const source: Source = .{ .path = "result.lin", .text = case.source };
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        const ast = try parse(gpa, &source, .from(0), tokens, &sink);
        try testing.expectEqual(@as(u32, 0), sink.error_count);
        var found: usize = 0;
        for (ast.exprs.items(.tag), 0..) |tag, i| {
            if (tag != .lambda) continue;
            const lambda = ast.lambda(ExprId.at(@intCast(i)));
            try testing.expectEqual(case.written, lambda.result.wasWritten());
            try testing.expectEqual(case.arrow, lambda.result_arrow != .none);
            found += 1;
        }
        try testing.expectEqual(@as(usize, 1), found);
    }
}

test "where contract lists share one separator with type predicates" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const parsed = try parseProgramText(arena.allocator(),
        \\fn observe[T](value: T) -> borrow T where borrows(value), T: Copyable { borrow value }
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expectEqual(@as(u32, 0), parsed.errors);
}

test "where contract lists attach to the nearest callable and reject bare clauses" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const cases = [_]struct { text: []const u8, valid: bool }{
        .{ .text = "fn make[T]() -> (fn(value: T) -> T where carries(value)) where T: Copyable {}", .valid = true },
        .{ .text = "fn make[T]() -> fn(value: T) -> T where T: Copyable {}", .valid = true },
        .{ .text = "fn make[T]() -> fn(value: T) -> T where carries(value) {}", .valid = true },
        .{ .text = "fn get(value: UInt8) -> UInt8 carries(value) { value }", .valid = false },
        .{ .text = "fn get(value: UInt8) -> UInt8 where carries(value) borrows(value) { value }", .valid = false },
        .{ .text = "fn get(cb: fn(value: UInt8) -> UInt8 carries(value)) {}", .valid = false },
    };
    for (cases) |case| {
        const parsed = try parseProgramText(arena.allocator(), case.text);
        try testing.expectEqual(case.valid, parsed.errors == 0);
    }
}

test "where contract lists keep nested callable contracts outside the function range" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const source: Source = .{ .path = "where.lin", .text =
        \\fn make[T](value: T) -> (fn(item: T) -> T where carries(item)) where carries(value), T: Copyable {}
    };
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    const ast = try parse(gpa, &source, .from(0), tokens, &sink);
    try testing.expectEqual(@as(u32, 0), sink.error_count);
    const function = node.DeclId.at(0);
    const outer = ast.declContracts(function);
    try testing.expectEqual(@as(usize, 1), outer.len);
    try testing.expectEqualStrings("value", ast.tokenText(outer[0].source.root));
    const callable = ast.callableType(ast.withoutTypeGroups(ast.declReturnRef(function)));
    const inner = ast.contracts[callable.contracts.start..callable.contracts.end];
    try testing.expectEqual(@as(usize, 1), inner.len);
    try testing.expectEqualStrings("item", ast.tokenText(inner[0].source.root));
    try testing.expectEqual(@as(usize, 1), ast.declWherePredicates(function).len);
}

test "where contract lists reject empty borrowing and retention sources" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const independent = try parseProgramText(arena.allocator(), "fn main() -> UInt8 { let callback = || -> where carries() 0; callback() }");
    try testing.expectEqual(@as(u32, 0), independent.errors);
    const cases = [_][]const u8{
        "fn main() -> UInt8 { let callback = || -> where borrows() 0; callback() }",
        "fn main() -> UInt8 { let callback = || -> where retains() 0; callback() }",
        "fn main() -> UInt8 { let callback = || -> where retains(value:) 0; callback() }",
        "fn main() -> UInt8 { let callback = || -> where carries(.Ok:) 0; callback() }",
    };
    for (cases) |source| {
        const parsed = try parseProgramText(arena.allocator(), source);
        try testing.expect(parsed.errors > 0);
    }
}

test "source contract trailing commas preserve enclosing boundaries" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const cases = [_][]const u8{
        "fn main() -> UInt8 { let callback = || -> where carries(), { 7 }; callback() }",
        "fn main() -> UInt8 { let callback = || -> UInt8 where carries(), 7; callback() }",
        "fn main() -> UInt8 { let callback = [owner] |value| -> where carries(value), borrows(owner), value; callback(7) }",
        "fn apply(callback: fn(value: UInt8) -> UInt8 where carries(value), other: UInt8) -> UInt8 { callback(other) }",
        "fn main() -> UInt8 { let callback: (fn() -> UInt8 where carries(),) = || 7; callback() }",
        "type Callback = fn() -> UInt8 where carries(),",
        "type Callback = fn() -> UInt8 where carries(),\nfn main() -> UInt8 { 0 }",
        "type Callback = fn() -> UInt8 where carries(),\ntype Other = UInt8",
        "type Pair = Wrapper[fn() -> UInt8 where carries(), fn() -> UInt8]",
        "fn main() -> UInt8 { let factory = || -> fn() -> UInt8 where carries(), || 7; factory()() }",
        "fn main() -> UInt8 { let factory = || -> fn() -> UInt8 where carries(), existing; factory()() }",
    };
    for (cases) |source| {
        const parsed = try parseProgramText(arena.allocator(), source);
        try testing.expectEqual(@as(u32, 0), parsed.errors);
    }
}

test "bare match arm jumps end at the arm comma" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const cases = [_][]const u8{
        "fn main() { loop { match item { None => break, Some(_) => continue, } } }",
        "fn main() { match item { None => return, Some(_) => {}, } }",
        "fn main() -> UInt8 { loop { match item { None => break 7, Some(_) => continue, } } }",
    };
    for (cases) |source| {
        const parsed = try parseProgramText(arena.allocator(), source);
        try testing.expectEqual(@as(u32, 0), parsed.errors);
    }
}

test "generated suffix relocation matches parsing after application source" {
    const gpa = testing.allocator;
    var diagnostic_arena = std.heap.ArenaAllocator.init(gpa);
    defer diagnostic_arena.deinit();
    var sink = Sink.init(diagnostic_arena.allocator());
    var interner: Interner = .empty;
    defer interner.deinit(gpa);
    var base = Modules.init(gpa, &sink, &interner);
    defer base.deinit();
    _ = try base.add(&.{.{ .file = @enumFromInt(0), .source = .{ .path = "library.lin", .text = "fn base(x: UInt8) -> UInt8 { x }" } }});
    var source = try base.finish();
    defer source.deinit(gpa);
    const generated: Source = .{
        .path = "generated.lin",
        .text = "@copyable\nstruct GeneratedBox[T] { value: T }\n" ++
            "fn boxed(x: UInt8) -> GeneratedBox[UInt8] { GeneratedBox[UInt8] { value = x } }\n" ++
            "fn generated(x: UInt8) -> UInt8 { let values = [x, 2]; let f = [x] |v: UInt8| -> UInt8 v + x; if x == 0 { f(values[0]) } else { 3 } }\n" ++
            "fn text(x: UInt8) -> Str { \"{x} {x:?}\" }\n" ++
            "fn range() -> UInt8 { let _r = 1..=3; 0 }\n" ++
            "impl Index[UInt64] for Board via scores\nimpl Board { trav positions via scores }\n" ++
            "fn selected[T](sink value: (Box[T]).Item.Next) { let _ = value }\n",
    };
    var cached = try Modules.initPrefix(gpa, &sink, &interner, &source);
    defer cached.deinit();
    _ = try cached.add(&.{.{ .file = @enumFromInt(1), .source = generated }});
    var expanded = try cached.finish();
    defer expanded.deinit(gpa);
    const saved_heads = try gpa.dupe(node.TypeRefId, expanded.struct_literal_heads);
    defer gpa.free(saved_heads);
    const saved_attribute_groups = try gpa.dupe(node.AttributeGroup, expanded.attribute_groups);
    defer gpa.free(saved_attribute_groups);
    var resumed = try Modules.initPrefix(gpa, &sink, &interner, &source);
    defer resumed.deinit();
    _ = try resumed.add(&.{.{ .file = @enumFromInt(1), .source = .{ .path = "application.lin", .text = "struct AppBox[T] { value: T }\nfn app(y: UInt8) -> UInt8 { let box = AppBox[UInt8] { value = y }; box.value }" } }});
    var before = resumed.view();
    var expected = try Modules.initPrefix(gpa, &sink, &interner, &before);
    defer expected.deinit();
    _ = try expected.add(&.{.{ .file = @enumFromInt(2), .source = generated }});
    const relocation = try resumed.appendGenerated(&source, &expanded);
    var actual = resumed.view();
    var want = expected.view();
    try testing.expect(!sink.hasErrors());
    try expectSourcePrefix(&want, &actual);
    try testing.expectEqualDeep(want.captures, actual.captures);
    try testing.expectEqualDeep(want.contracts, actual.contracts);
    try testing.expectEqualDeep(want.contract_steps, actual.contract_steps);
    try testing.expectEqualDeep(want.decl_attribute_groups, actual.decl_attribute_groups);
    try testing.expectEqualDeep(want.attribute_items, actual.attribute_items);
    try testing.expectEqualDeep(want.attribute_groups, actual.attribute_groups);
    try testing.expectEqualDeep(saved_heads, expanded.struct_literal_heads);
    try testing.expectEqualDeep(saved_attribute_groups, expanded.attribute_groups);
    const boundary: node.ParamRange = .{ .start = 0, .end = @intCast(source.params.len) };
    try testing.expectEqualDeep(boundary, relocation.value(boundary));
    try testing.expectEqual(ExprId.none, relocation.id(ExprId, .none));
}

test "named literal lookahead crosses nested type arguments once" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var source: std.ArrayList(u8) = .empty;
    try source.appendSlice(gpa, "fn main() -> UInt8 { let _value = ");
    for (0..400) |_| try source.appendSlice(gpa, "Cell[");
    try source.appendSlice(gpa, "UInt8");
    for (0..400) |_| try source.append(gpa, ']');
    try source.appendSlice(gpa, " { value = 1 }; 0 }");
    const parsed = try parseProgramText(gpa, source.items);
    try testing.expectEqual(@as(u32, 0), parsed.errors);
}

test "an index still takes exactly one expression" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const parsed = try parseProgramText(arena.allocator(), "fn main() -> UInt8 { let values = [1, 2]; values[0, 1] }");
    try testing.expect(parsed.errors > 0);
}

test "field delegation parses implementation and traversal without bodies" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const source: Source = .{ .path = "delegation.lin", .text =
        \\impl[T] index.Index[UInt64] for Board[T] where T: Copyable via scores
        \\impl Board { trav positions via scores }
        \\fn via() -> UInt8 { 0 }
    };
    var sink = Sink.init(gpa);
    var names: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &names);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    try testing.expect(!sink.hasErrors());
    try testing.expectEqual(@as(u32, 4), ast.declCount());
    var delegated: usize = 0;
    for (0..ast.declCount()) |i| {
        const d = node.DeclId.at(@intCast(i));
        if (ast.declVia(d) == .none) continue;
        delegated += 1;
        try testing.expectEqualStrings("scores", ast.tokenText(ast.declDelegation(d)));
        try testing.expectEqual(ExprId.none, ast.declInit(d));
        try testing.expectEqual(ExprId.none, ast.declBody(d));
    }
    try testing.expectEqual(@as(usize, 2), delegated);
}

test "field delegation missing target preserves later declarations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const source: Source = .{ .path = "delegation.lin", .text =
        \\impl Index[UInt64] for Board via
        \\fn next() -> UInt8 { 0 }
        \\impl Board { trav positions via
        \\fn member() -> UInt8 { 0 }
        \\}
    };
    var sink = Sink.init(gpa);
    var names: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &names);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    try testing.expect(sink.hasErrors());
    var functions: usize = 0;
    for (0..ast.declCount()) |i| {
        if (ast.declTag(.at(@intCast(i))) == .function) functions += 1;
    }
    try testing.expectEqual(@as(usize, 2), functions);
}

test "field delegation accepts contextual words as stored fields" {
    const cases = [_][]const u8{
        "impl Index[UInt64] for Board via type",
        "impl Index[UInt64] for Board via\nproj",
        "impl Board { trav positions via\ntrav }",
    };
    for (cases) |text| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const source: Source = .{ .path = "delegation.lin", .text = text };
        var sink = Sink.init(gpa);
        var names: Interner = .empty;
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &names);
        var ast = try parse(gpa, &source, .from(0), tokens, &sink);
        try testing.expect(!sink.hasErrors());
        for (0..ast.declCount()) |i| {
            const d = node.DeclId.at(@intCast(i));
            if (ast.declVia(d) != .none) try testing.expect(ast.declDelegation(d) != .none);
        }
    }
}

test "field delegation missing target preserves contextual declarations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const source: Source = .{ .path = "delegation.lin", .text =
        \\impl Index[UInt64] for Board via
        \\type Alias = UInt8
        \\impl Board {
        \\    trav positions via
        \\    trav other = 0..4
        \\    trav more via
        \\    type Item = UInt8
        \\    trav last via
        \\    proj at(self: Self, i: UInt64) -> UInt8 { self.scores[i] }
        \\}
    };
    var sink = Sink.init(gpa);
    var names: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &names);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    try testing.expect(sink.hasErrors());
    var preserved: usize = 0;
    var missing: usize = 0;
    for (0..ast.declCount()) |i| {
        const d = node.DeclId.at(@intCast(i));
        if (ast.declVia(d) != .none) {
            try testing.expectEqual(TokenId.none, ast.declDelegation(d));
            missing += 1;
        }
        const name = ast.declName(d);
        if (name == .none) continue;
        const text = ast.tokenText(name);
        for ([_][]const u8{ "Alias", "other", "Item", "at" }) |expected| {
            if (std.mem.eql(u8, text, expected)) preserved += 1;
        }
    }
    try testing.expectEqual(@as(usize, 4), missing);
    try testing.expectEqual(@as(usize, 4), preserved);
}

test "field delegation rejects added bodies receivers and field paths" {
    const cases = [_][]const u8{
        "impl Index[UInt64] for Board via scores {}\nfn next() -> UInt8 { 0 }",
        "impl Board { trav positions(self: Self) via scores }\nfn next() -> UInt8 { 0 }",
        "impl Board { trav positions via scores = 0..4 }\nfn next() -> UInt8 { 0 }",
        "impl Board { trav positions via scores {} }\nfn next() -> UInt8 { 0 }",
        "impl Index[UInt64] for Board via nested.scores\nfn next() -> UInt8 { 0 }",
    };
    for (cases) |text| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const source: Source = .{ .path = "delegation.lin", .text = text };
        var sink = Sink.init(gpa);
        var names: Interner = .empty;
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &names);
        var ast = try parse(gpa, &source, .from(0), tokens, &sink);
        try testing.expect(sink.hasErrors());
        var retained = false;
        for (0..ast.declCount()) |i| {
            const d = node.DeclId.at(@intCast(i));
            if (ast.declTag(d) == .function and std.mem.eql(u8, ast.tokenText(ast.declName(d)), "next")) retained = true;
        }
        try testing.expect(retained);
    }
}

test "field delegation accepts a trailing where comma before via" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const source: Source = .{ .path = "delegation.lin", .text =
        \\impl[T] Index[UInt64] for Board[T] where T: Copyable,
        \\via scores
    };
    var sink = Sink.init(gpa);
    var names: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &names);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    try testing.expect(!sink.hasErrors());
    try testing.expectEqual(@as(u32, 1), ast.declCount());
    try testing.expectEqual(@as(usize, 1), ast.declWherePredicates(.at(0)).len);
    try testing.expectEqualStrings("scores", ast.tokenText(ast.declDelegation(.at(0))));
}

test "string literal postfix chains retain their literal and interpolation nodes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const source: Source = .{ .path = "t.lin", .text =
        \\fn plain() -> UInt64 { "tea".to_owned_in(allocator).unwrap() }
        \\fn interpolated() -> UInt64 { "{value}".render(allocator).unwrap() }
    };
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    try testing.expectEqual(@as(u32, 0), sink.error_count);
    for ([_]Expr.Tag{ .str_literal, .interp }, 0..) |literal, index| {
        const outer = ast.blockOf(ast.declBody(node.DeclId.at(@intCast(index)))).tail;
        try testing.expectEqual(Expr.Tag.call, ast.exprTag(outer));
        const unwrap = ast.call(outer).callee;
        try testing.expectEqual(Expr.Tag.field, ast.exprTag(unwrap));
        const inner = ast.unaryOperand(unwrap);
        try testing.expectEqual(Expr.Tag.call, ast.exprTag(inner));
        const method = ast.call(inner).callee;
        try testing.expectEqual(Expr.Tag.field, ast.exprTag(method));
        try testing.expectEqual(literal, ast.exprTag(ast.unaryOperand(method)));
    }
}

test "string literal postfix preserves numeric restrictions and newline boundaries" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    for ([_][]const u8{ "7?", "1.5?", "true?" }) |source| {
        const got = try parseWithDiagnostics(gpa, source);
        try testing.expect(got.errors > 0);
    }
    const separated = try parseProgramText(gpa,
        \\fn plain() -> Str {
        \\    "tea"
        \\    .Some("coffee")
        \\}
    );
    try testing.expectEqual(@as(u32, 0), separated.errors);
}

test "inferred array lengths remain syntax rather than name expressions" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const parsed = try parseProgramText(arena.allocator(),
        \\fn main() -> UInt8 { let values: [[UInt8; _]; _] = [[1, 2]]; values[0][0] }
    );
    try testing.expectEqual(@as(u32, 0), parsed.errors);
    try testing.expect(std.mem.indexOf(u8, parsed.dump, "[[UInt8; _]; _]") != null);
    try testing.expect(std.mem.indexOf(u8, parsed.dump, "name_ref \"_\"") == null);
}
