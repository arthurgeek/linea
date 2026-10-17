const std = @import("std");
const testing = std.testing;
const Span = @import("../support/span.zig").Span;
const FileId = @import("../support/source.zig").FileId;

pub const Severity = enum {
    err,
    warning,
    note,

    pub fn text(self: Severity) []const u8 {
        return switch (self) {
            .err => "error",
            .warning => "warning",
            .note => "note",
        };
    }
};

/// The rule a diagnostic reports, named as `docs/linea-semantics.md` names it.
///
/// A code identifies what was broken, not which pass noticed. The prefix says
/// what the rule constrains: `S-` the grammar, `N-` names, `T-` types. `O-` is
/// reserved for ownership.
///
/// A name is never reused for a different rule. A rule that is removed leaves
/// its name behind rather than freeing it, since a name appears in whatever a
/// user has already written down.
pub const Code = enum {
    // Grammar. §2.
    s_entry,
    s_test,
    /// An `export` written on an impl member.
    s_export,
    /// An `extern` declaration written with a body.
    s_extern,
    /// An escape in a string literal that names nothing.
    s_escape,
    /// A source file that is not UTF-8.
    s_encoding,
    s_char,
    s_string,
    /// A format selector inside an interpolation other than `:?`.
    s_format,
    /// A float literal missing digits after its point or in its exponent.
    s_float,
    s_expr,
    s_name,
    s_type,
    /// `-> ()` written as a result: a callable that returns nothing writes no
    /// result type.
    s_unit_result,
    s_bracket,
    s_equals,
    s_destructure,
    s_separator,
    s_continuation,
    s_nesting,
    s_paren,
    /// A tuple written with fewer than two components or more than eight,
    /// or a tuple pattern binding something other than a name or `_`.
    s_tuple,
    s_brace,
    s_base_last,
    s_chain,
    s_break,
    s_params,
    s_mutation,
    s_enum,
    s_struct,
    s_field,
    s_match,
    /// A `for` written without the `in` that separates its binder from the
    /// sequence. A missing binder is [S-Name], which is what a missing name is
    /// anywhere.
    s_for,
    /// A binding's `else` whose binder is not one name between two bars, or a
    /// second `else` on one binding.
    s_let_else,
    /// A range's end is not a range: `..` and `..=` do not chain, and an open
    /// end is not written.
    s_range,
    /// A positional argument written after a named one.
    s_args,
    /// A default on a parameter that is not `read`, or a defaulted parameter
    /// followed by one with no default.
    s_default,
    s_lambda,

    // Names. §3.
    n_undefined,
    n_unused,
    n_immutable,
    n_duplicate,
    n_not_callable,
    n_not_a_value,
    n_aliased,
    /// Two traits a module can see declare one operation for one type, so the
    /// postfix form does not say which was meant.
    n_ambiguous,
    /// A trait's operation shadowed, for the postfix form, by the type's own.
    n_shadowed,
    n_variant,
    /// A declared name that does not start in the case its kind requires: a
    /// capital letter for a type, a trait, a variant or a type parameter, and
    /// a lowercase letter for every other name.
    n_case,
    /// An `impl` names something that is not a type. Its own rule rather than
    /// [N-Undefined], because the name is defined -- what is wrong is what it
    /// refers to, and saying "undefined" would send a reader looking for a
    /// declaration that is right there.
    m_impl,
    n_not_a_type,
    /// An alias written where a declaration is named rather than a type --
    /// a call, a path through it, an `impl` head -- or one that reaches
    /// itself through the type it names.
    n_type_alias,

    // Modules. §3.7.
    /// An import names nothing that can be loaded, names the reserved root, or
    /// closes a cycle in the module graph.
    m_import,
    /// A manifest's `dependencies` entry that names no library this root may
    /// depend on: a path holding no library, a name its library does not
    /// answer to, a cycle, one name for two libraries, or `extern` granted on
    /// one side only.
    m_dependency,
    /// An import nothing names. Its own rule rather than [N-Unused], because
    /// there is no `_` form to suggest: an import is removed.
    m_unused,
    /// A name reached across a module boundary that its own module does not
    /// export.
    m_vis,
    /// A library declares an entry point. Its own rule rather than [S-Entry],
    /// which asks whether a root must declare one: a library must not, and
    /// answering both through one name would make the rule mean "the entry
    /// point is wrong" without saying which way.
    m_entry,
    /// A sealed type's representation reached from outside the module that
    /// declares it: built, taken apart, or read into.
    m_opaque,
    /// An `extern` declaration outside the standard library.
    m_extern,
    /// An `export` that designates no single foreign entry point: a generic,
    /// or one written in a program.
    m_export,

    // Ownership. §5.
    /// A copyable declaration has a known noncopyable owned part.
    o_universe,
    o_capture,
    /// Using a binding that is moved or uninitialised, moving a place that is
    /// not a whole binding, or moving out of a `read` parameter. Use-after-free
    /// and double-free are the same check and so the same code.
    o_move,
    /// A Linear binding still live where its scope ends.
    o_leak,
    /// The paths into a join disagree about a Linear binding's state.
    o_merge,
    /// An `inout` parameter not initialised on some path to an exit.
    o_reinit,
    /// Control leaves while a value has been moved into a construct that has
    /// not completed, so the next reachable state holds a value nobody owns.
    o_defer_dead,
    o_uncommitted,
    /// An observation escapes its owner or the permitted callable sources.
    o_escapes,
    o_borrow,
    /// A value borrowing a temporary is used after the temporary's statement
    /// ends.
    o_temporary,
    /// A move inside a loop body, which would run more than once.
    o_loop,
    /// Explicit duplication of a type without Copyable permission.
    o_copy,
    /// Explicit copy of a concrete type that already has scalar snapshot reads.
    o_scalar_copy,
    /// A `for` whose iterator is Linear. A walk abandons its iterator where it
    /// ends, and abandoning a Linear value is what linearity forbids.
    o_linear_walk,
    /// A `for` over an array of a Linear element that control can leave before
    /// its last position. The places the walk never reached hold values nothing
    /// took.
    o_linear_tail,
    /// An operation overlapping a place some enclosing construct is lending:
    /// a write through it, or a second lend where either may write.
    o_lent,
    /// `copy` in a reading position, where nothing consumes and the copy has
    /// no effect.
    o_copy_read,
    /// `copy` whose source is never read again, so the copy has no effect.
    o_copy_dead,

    // Types. §4.
    t_mismatch,
    t_literal,
    t_convert,
    t_overflow,
    /// A binary operation's operands must agree, and arithmetic's are numbers.
    /// Two types agreeing is not enough: a structure, an enum and a `Bool` all
    /// agree with themselves and none of them is a number, so this reports
    /// what an operand holds rather than that the two differ -- which is
    /// [T-Mismatch], reported at the operand a context asked something of.
    t_operands,
    /// An expression whose type cannot be determined. A literal has a default
    /// and every other expression takes its type from its operands, so what
    /// reaches this is a type argument nothing settles -- a variant written
    /// with a leading `.` where no type is expected, or a parameter no
    /// argument and no payload names.
    t_infer,
    t_call,
    t_array_size,
    t_array_length,
    t_index,
    /// A recursive call instantiates its callee with type arguments larger
    /// than the ones it was given, so the instantiations it reaches never
    /// close and the program stands for infinitely many functions.
    t_poly_rec,
    /// A type argument does not satisfy its parameter's bounds, or a generic
    /// type was named with the wrong number of them. One rule: both are the
    /// question of whether what was supplied is what the parameter admits.
    t_bound,
    /// A format spec asks for a part the value's type does not take: a sign or
    /// zero padding on a value that is not a number, or a precision on one
    /// that is not a float.
    t_format,
    /// A trailing predicate must constrain a type that depends on an open
    /// parameter supplied by its declaration or enclosing generic scope.
    t_where,
    /// An implementation supplies exactly the operations its trait declares.
    t_impl,
    /// A structural template is not a valid recipe for its trait.
    t_template,
    /// A derive request cannot produce the implementation it names.
    t_derive,
    /// A structural reflection operation is used outside the lexical template
    /// context that gives its descriptor meaning.
    t_reflection,
    t_divide_by_zero,
    t_condition,
    /// A `for` walks a value that implements no `Sequence`, or one whose
    /// iterator implements no `Iterator`. Both are bounds the construct
    /// demands; that the iterator can be abandoned is a question about its
    /// settlement capability and is [O-LinearWalk].
    t_for,
    /// A lending `for` walks a value whose type carries no traversal, or no
    /// projection for a position to name a place through, or a traversal
    /// yielding something a projection is not indexed by. One rule, because
    /// the three are one demand: a lending walk needs the positions and the
    /// place each one stands for, and neither half is a walk without the
    /// other.
    t_lend,
    t_borrow_contract,
    t_arms,
    t_arity,
    /// An argument names a parameter the callee does not declare, or names one
    /// where no parameters exist at all -- a conversion, or a variant being
    /// built.
    t_unknown_parameter,
    /// A parameter is given twice: named twice, or named after the positional
    /// prefix already filled it.
    t_duplicate_parameter,
    /// A parameter no argument fills. Named rather than counted, which is the
    /// only phrasing that survives arguments arriving out of written order.
    t_missing_argument,
    /// A parameter's default is not a constant expression. Nothing runs where a
    /// parameter is declared, and a call that omits one receives a value rather
    /// than an expression to run, so a default the language cannot work out has
    /// nothing to give.
    t_default,
    /// A type parameter's default argument is written where it cannot be
    /// filled in: on a declaration other than a struct, an enum or an alias,
    /// before a parameter that has none, or naming a parameter of its own list.
    t_argument_default,
    /// A type written without the argument of a defaulted allocator parameter,
    /// inside a declaration that declares an allocator parameter of its own.
    t_defaulted_allocator,
    t_cover,
    t_variants,
    t_unreachable,
    /// A type holds itself inline, so computing its size requires its size.
    /// About layout rather than about recursion: a type that reaches itself
    /// through an indirection is well formed, and this rule outlives the one
    /// that forbids the payload.
    t_infinite_layout,
    /// A type is wider than the offsets an implementation records can reach,
    /// so it has no offset to place its parts at. A stated limit rather than
    /// arithmetic nobody checked: unstated, it is met as a slot smaller than
    /// the value it holds.
    l_size,
    /// The three make a family, and the family is the point: `private` and
    /// `ambiguous` will join it, and a set that reads alike is a set a reader
    /// can guess at.
    t_unknown_field,
    t_missing_field,
    t_duplicate_field,
    t_unused_base,
    /// A postfix call reaches an operation, and the receiver's type answers
    /// to none under the call's name.
    t_unknown_operation,
    t_discard,
    /// A `Result` bound to `_`. Discarding any other value is a deliberate act
    /// the language allows; discarding an explicit report of failure is the one
    /// thing `let _` may not do.
    t_discard_failure,
    /// A constant's initialiser is not a constant expression. Nothing runs
    /// where a constant is declared, so an initialiser the language cannot
    /// work out has no value to bind.
    t_const,
    s_defer,
    /// A `defer let` that does not bind one name to a value it schedules the
    /// release of: a pattern, or a `let read`.
    s_defer_let,
    /// A `defer let` whose type implements no `Release`, so the release it
    /// would schedule has no operation to run.
    t_defer_let,
    t_try,
    t_try_answer,
    /// A `let … else` over something other than an `Option` or a `Result`, or
    /// whose binder does not fit what the failure carries.
    t_let_else,
    /// An `extern` whose signature names something the language does not fix
    /// the representation of.
    t_extern,
    /// Two `extern` declarations of one symbol whose signatures disagree.
    t_extern_agreement,
    /// An `extern` in the runtime's `linea_` namespace whose symbol the
    /// runtime does not declare, or whose signature is not the runtime's.
    t_extern_runtime,
    /// An `export` whose signature holds a type that may not cross.
    t_export,
    /// A type parameter whose declaration says the wrong thing about what it
    /// is for: `phantom` where the parameter appears in a field, its absence
    /// where the parameter appears in none, or a bound on one no argument is
    /// ever seen to satisfy.
    t_phantom,
    /// A `proj` that is not a place: a body computing a value rather than
    /// naming one, a projection written where no trait declares one, a mode
    /// ceiling above the trait's, or an expansion that reaches itself. One
    /// rule, because each is a way of writing something that is not the place
    /// a projection is.
    t_projection,
    /// A range-indexed place used other than whole, or one whose bounds the
    /// checker cannot settle where the place is formed. One rule, because each
    /// is a way of naming something a range place is not: the place is a single
    /// place of the array type its bounds name, so a bound that settles to no
    /// number leaves no type to name, and a use narrower than the whole names
    /// no place the language defines.
    t_range_place,
    /// A newtype's refinement clause names a range no value could satisfy, a
    /// base the clause cannot be written over, or a construction whose value
    /// the clause does not admit -- one rule, because each is a way of
    /// writing a value the contract excludes.
    t_refine,

    /// How the rule is spelled in a diagnostic and in the semantics.
    pub fn ruleName(self: Code) []const u8 {
        return switch (self) {
            .s_entry => "S-Entry",
            .s_test => "S-Test",
            .s_export => "S-Export",
            .s_extern => "S-Extern",
            .s_escape => "S-Escape",
            .s_encoding => "S-Encoding",
            .s_char => "S-Char",
            .s_string => "S-String",
            .s_format => "S-Format",
            .s_float => "S-Float",
            .s_expr => "S-Expr",
            .s_name => "S-Name",
            .s_type => "S-Type",
            .s_unit_result => "S-UnitResult",
            .s_bracket => "S-Bracket",
            .s_equals => "S-Equals",
            .s_destructure => "S-Destructure",
            .s_separator => "S-Separator",
            .s_continuation => "S-Continuation",
            .s_nesting => "S-Nesting",
            .s_paren => "S-Paren",
            .s_tuple => "S-Tuple",
            .s_brace => "S-Brace",
            .s_base_last => "S-BaseLast",
            .s_chain => "S-Chain",
            .s_break => "S-Break",
            .s_params => "S-Params",
            .s_mutation => "S-Mutation",
            .s_enum => "S-Enum",
            .s_struct => "S-Struct",
            .s_field => "S-Field",
            .s_match => "S-Match",
            .s_for => "S-For",
            .s_let_else => "S-LetElse",
            .s_range => "S-Range",
            .s_args => "S-Args",
            .s_default => "S-Default",
            .s_lambda => "S-Lambda",
            .n_undefined => "N-Undefined",
            .n_unused => "N-Unused",
            .n_immutable => "N-Immutable",
            .n_duplicate => "N-Duplicate",
            .n_not_callable => "N-NotCallable",
            .n_not_a_value => "N-NotAValue",
            .n_aliased => "N-Aliased",
            .n_ambiguous => "N-Ambiguous",
            .n_shadowed => "N-Shadowed",
            .n_variant => "N-Variant",
            .n_case => "N-Case",
            .m_impl => "M-Impl",
            .n_not_a_type => "N-NotAType",
            .n_type_alias => "N-TypeAlias",
            .m_import => "M-Import",
            .m_dependency => "M-Dependency",
            .m_unused => "M-Unused",
            .m_vis => "M-Vis",
            .m_entry => "M-Entry",
            .m_opaque => "M-Opaque",
            .m_extern => "M-Extern",
            .m_export => "M-Export",
            .o_universe => "O-Universe",
            .o_capture => "O-Capture",
            .o_move => "O-Move",
            .o_leak => "O-Leak",
            .o_merge => "O-Merge",
            .o_reinit => "O-Reinit",
            .o_defer_dead => "O-DeferDead",
            .o_uncommitted => "O-Uncommitted",
            .o_escapes => "O-Escapes",
            .o_borrow => "O-Borrow",
            .o_temporary => "O-Temporary",
            .o_loop => "O-Loop",
            .o_copy => "O-Copy",
            .o_scalar_copy => "O-ScalarCopy",
            .o_linear_walk => "O-LinearWalk",
            .o_linear_tail => "O-LinearTail",
            .o_lent => "O-Lent",
            .o_copy_read => "O-CopyRead",
            .o_copy_dead => "O-CopyDead",
            .t_mismatch => "T-Mismatch",
            .t_literal => "T-Literal",
            .t_convert => "T-Convert",
            .t_overflow => "T-Overflow",
            .t_operands => "T-Operands",
            .t_infer => "T-Infer",
            .t_call => "T-Call",
            .t_array_size => "T-ArraySize",
            .t_array_length => "T-ArrayLength",
            .t_index => "T-Index",
            .t_bound => "T-Bound",
            .t_format => "T-Format",
            .t_where => "T-Where",
            .t_impl => "T-Impl",
            .t_template => "T-Template",
            .t_derive => "T-Derive",
            .t_reflection => "T-Reflection",
            .t_poly_rec => "T-PolyRec",
            .t_divide_by_zero => "T-DivideByZero",
            .t_condition => "T-Condition",
            .t_for => "T-For",
            .t_lend => "T-Lend",
            .t_borrow_contract => "T-BorrowContract",
            .t_arms => "T-Arms",
            .t_arity => "T-Arity",
            .t_unknown_parameter => "T-UnknownParameter",
            .t_duplicate_parameter => "T-DuplicateParameter",
            .t_missing_argument => "T-MissingArgument",
            .t_default => "T-Default",
            .t_argument_default => "T-ArgumentDefault",
            .t_defaulted_allocator => "T-DefaultedAllocator",
            .t_cover => "T-Cover",
            .t_variants => "T-Variants",
            .t_unreachable => "T-Unreachable",
            .t_infinite_layout => "T-InfiniteLayout",
            .l_size => "L-Size",
            .t_unknown_field => "T-UnknownField",
            .t_unknown_operation => "T-UnknownOperation",
            .t_missing_field => "T-MissingField",
            .t_duplicate_field => "T-DuplicateField",
            .t_unused_base => "T-UnusedBase",
            .t_discard => "T-Discard",
            .t_discard_failure => "T-DiscardFailure",
            .t_const => "T-Const",
            .s_defer => "S-Defer",
            .s_defer_let => "S-DeferLet",
            .t_defer_let => "T-DeferLet",
            .t_try => "T-Try",
            .t_try_answer => "T-TryAnswer",
            .t_let_else => "T-LetElse",
            .t_extern => "T-Extern",
            .t_extern_agreement => "T-ExternAgreement",
            .t_extern_runtime => "T-ExternRuntime",
            .t_export => "T-Export",
            .t_phantom => "T-Phantom",
            .t_projection => "T-Projection",
            .t_range_place => "T-RangePlace",
            .t_refine => "T-Refine",
        };
    }

    pub fn format(self: Code, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.writeAll(self.ruleName());
    }
};

pub const LabelStyle = enum { primary, secondary };

/// A span, the file it indexes into, and what to say about it.
///
/// `file` has no default. A default is how a pass silently attributes a
/// diagnostic to whichever file happened to be first, which is invisible until
/// a second file exists and then reads as a lexer bug.
pub const Label = struct {
    file: FileId,
    span: Span,
    message: []const u8,
    style: LabelStyle = .primary,
};

/// A single reported problem. Held as a plain struct rather than column-wise:
/// a handful exist per compilation and rendering touches every field of each,
/// so there is no bulk traversal for dense columns to pay off against.
pub const Diagnostic = struct {
    severity: Severity,
    code: ?Code = null,
    message: []const u8,
    labels: []const Label = &.{},
    notes: []const []const u8 = &.{},

    pub fn primaryLabel(self: *const Diagnostic) ?Label {
        for (self.labels) |l| {
            if (l.style == .primary) return l;
        }
        return null;
    }
};

test "every rule a diagnostic can name is defined in the semantics" {
    // A code is an index into the document, so a name with no prose behind it
    // is a reference to nothing. The bolded form is the definition; a bare
    // mention elsewhere is a cross-reference and would let a rule keep its
    // index after the text defining it was gone.
    const semantics = @embedFile("semantics");

    for (std.enums.values(Code)) |c| {
        var buf: [64]u8 = undefined;
        const needle = try std.fmt.bufPrint(&buf, "**[{s}]**", .{c.ruleName()});
        if (std.mem.indexOf(u8, semantics, needle) == null) {
            std.debug.print("{s} is emitted but not defined in docs/linea-semantics.md\n", .{c.ruleName()});
            return error.RuleNotDefined;
        }
    }
}

test "a code renders as the rule it names" {
    var buf: [32]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try w.print("{f}", .{Code.s_char});
    try testing.expectEqualStrings("S-Char", w.buffered());
}
