const std = @import("std");
const testing = std.testing;

const Source = @import("../support/source.zig").Source;
const readFileAlloc = @import("../support/source.zig").readFileAlloc;
const Sink = @import("../diagnostics/sink.zig").Sink;
const Interner = @import("../support/interner.zig").Interner;
const tokenize = @import("../lexer/lexer.zig").tokenize;
const parse = @import("../parser/parser.zig").parse;
const TokenId = @import("../lexer/token.zig").TokenId;
const Ast = @import("../syntax/ast.zig").Ast;
const node = @import("../syntax/node.zig");
const token = @import("../lexer/token.zig");
const ExprId = node.ExprId;
const resolve_mod = @import("../sema/resolve.zig");
const resolve = resolve_mod.resolve;
const resolveTree = resolve_mod.resolveTree;
const Resolution = resolve_mod.Resolution;
const BindingId = resolve_mod.BindingId;
const typecheck = @import("../sema/typecheck.zig").typecheck;
const typecheckTree = @import("../sema/typecheck.zig").typecheckTree;
const Typing = @import("../sema/types.zig").Typing;
const CallIndex = @import("../sema/types.zig").CallIndex;
const namesAVariant = @import("../sema/typecheck.zig").namesAVariant;
const isCatchAll = @import("../sema/typecheck.zig").isCatchAll;
const selectsFromAValue = @import("../sema/typecheck.zig").selectsFromAValue;
const fieldBase = @import("../sema/typecheck.zig").fieldBase;
const checkOwnership = @import("../ownership/check.zig").check;
const loader = @import("../driver/loader.zig");
const FileTable = @import("../support/source.zig").FileTable;
const FileId = @import("../support/source.zig").FileId;
const ProgramKind = @import("../syntax/program.zig").Kind;

/// A change to a program that must stop it compiling.
///
/// The rewrites in `transform.zig` run the other way: they preserve meaning,
/// so the program is its own expectation and a disagreement is a bug. That
/// direction cannot find a check the compiler never makes — a program the
/// compiler wrongly accepts is rewritten into another it wrongly accepts, and
/// the two agree.
///
/// This is the direction that can. A mutation is built to be ill-formed, so
/// silence is the failure, and no golden records it: the mutation names the
/// rule its result must break, and the rule is read out of the diagnostic.
pub const Mutation = enum {
    /// Renames one variant reference to a name no enum declares.
    unknown_variant,
    /// Renames one field reference to a name its type does not have.
    unknown_field,
    /// Renames one name reached through a type to one that type does not
    /// declare.
    unknown_member,
    /// Deletes one statement that gives a linear value away.
    dropped_disposal,
    /// Deletes one member of a trait implementation, leaving a signature the
    /// trait declares with no body anywhere.
    dropped_implementation,
    /// Deletes a concrete implementation that discharges one structural
    /// template component requirement.
    dropped_component_implementation,
    /// Replaces one closed component-requirement argument with an unapplied
    /// generic constructor.
    opened_component_requirement_argument,
    /// Deletes one bound from a generic derive that proves a component
    /// requirement.
    dropped_derive_bound,
    /// Deletes one bound from a structural template member's type parameter.
    dropped_template_member_bound,
    /// Replaces one structural template member bound with another trait.
    replaced_template_member_bound,
    /// Rewrites the entry point's return type to one an exit status is not.
    wrong_entry_type,
    /// Repeats one statement that gives a linear value away, so the value is
    /// given away twice.
    repeated_disposal,
    /// Copies the linear value one statement is about to give away.
    copied_disposal,
    /// Puts one statement that gives a linear value away behind a condition,
    /// so one path through the join disposes of it and the other does not.
    conditional_disposal,
    /// Declares a copyable type holding a linear one.
    copyable_holds_linear,
    /// Gives the construct a disposal hands its value to a second operand that
    /// leaves, so control goes between the value being given up and the call
    /// receiving it.
    abrupt_after_a_transfer,
    /// Deletes the `phantom` one declaration spells, leaving a parameter
    /// nothing names.
    dropped_phantom,
    /// Respells a covering match arm's `..=` to `..`, uncovering the value
    /// that made the arm above it reach the type's top.
    narrowed_range,
    /// Tightens a newtype's `where it in lo..=hi` clause to just past the
    /// literal a construction in the same program proved it with.
    narrowed_refinement,
    /// Sums the value a destructuring `let` takes apart with itself, so the
    /// operator reaches a newtype value whose type carries none of its own.
    summed_newtype,

    /// The rule the mutated program must break.
    pub fn rule(self: Mutation) []const u8 {
        return switch (self) {
            .unknown_variant => "N-Variant",
            .unknown_field => "T-UnknownField",
            .unknown_member => "N-Variant",
            .dropped_disposal => "O-Leak",
            .dropped_implementation => "T-Impl",
            .dropped_component_implementation, .dropped_derive_bound => "T-Derive",
            .opened_component_requirement_argument,
            .dropped_template_member_bound,
            .replaced_template_member_bound,
            => "T-Template",
            .wrong_entry_type => "S-Entry",
            .repeated_disposal => "O-Move",
            .copied_disposal => "O-Copy",
            .conditional_disposal => "O-Merge",
            .copyable_holds_linear => "O-Universe",
            .abrupt_after_a_transfer => "O-Uncommitted",
            // Stripping the modifier leaves a parameter nothing names, and
            // the rule that says so is the one `phantom` exists to satisfy.
            .dropped_phantom => "N-Unused",
            // The value the flag used to include is now a gap over the
            // scrutinee's type, which is exactly what names it.
            .narrowed_range => "T-Cover",
            // The same rule construction discharges against, whether what
            // it finds is a value the range excludes or, moved far enough,
            // a range that excludes everything.
            .narrowed_refinement => "T-Refine",
            // A name over a base inherits none of its operators, and this is
            // the rule that says so.
            .summed_newtype => "T-Operands",
            // A lending walk is the traversal and the projection together, and
            // this is the rule that names the half that is missing.
        };
    }

    /// The fewest generated programs this must reach, as a share of how many
    /// there are.
    ///
    /// A share rather than a count, which is what makes it a statement about
    /// coverage instead of about `-Dprograms`: the corpus floors above are
    /// absolute because the corpus is fixed, and this one cannot be, because
    /// the population it measures is set on the command line.
    ///
    /// It exists because the corpus half was the smaller half. Scheduling a
    /// disposal with `defer` cost five mutations six generated programs each
    /// and one corpus program each, and only the corpus number was compared
    /// against anything.
    pub fn generatedFloor(self: Mutation) u32 {
        return switch (self) {
            .unknown_variant => 80,
            .unknown_field => 65,
            // Reached only where a program names a member through a type,
            // which most generated ones do not: three of thirty-two when this
            // was written, two now.
            //
            // Lowered from 6 when the generator gained a covering match over
            // ranges: one more statement production shifts every choice
            // after it, so the programs a fixed seed draws are different
            // programs, and this one's share fell with nothing at it having
            // got worse. Measured at 3.1% of 32 and 1.6% of 64, and set
            // under both.
            //
            // A share is the wrong unit here and this floor is written low
            // because of it: the count the generator reaches is two whatever
            // the sample, so the share falls as the sample grows with nothing
            // about the mutation changing. It reads as a share until the
            // generator writes members often enough for one to mean something.
            .unknown_member => 1,
            // Lowered from 50, which was calibrated at 32 programs and sat
            // above what any larger sample reads: the base before the float
            // forms measures the same 49.6% at 256 that the stream with them
            // does, program for program, because the flags that shape a
            // program draw before any choice the floats touched. Measured at
            // 53.1% of 128 and 49.6% of 256 on both streams, set under both.
            .dropped_disposal => 48,
            .dropped_implementation => 35,
            .dropped_component_implementation => 90,
            .opened_component_requirement_argument => 40,
            .dropped_derive_bound => 90,
            .dropped_template_member_bound, .replaced_template_member_bound => 90,
            // Every generated program declares an entry point.
            .wrong_entry_type => 90,
            // The two below are the shapes a scheduled disposal cannot take:
            // repeating one is [O-DeferDead] and leaving from inside one is
            // [S-Defer], so both skip a `defer` and reach the programs whose
            // disposal is written where it runs.
            //
            // Lowered from 35 three times over, for the same reason each
            // time and not because the mutation got worse at anything: the
            // generator's covering match, the argument a call may name, and
            // the newtype block each draw a decision or two more than what
            // stood there before, so every choice after them lands somewhere
            // else and the programs are different programs. Measured with all
            // three in the stream.
            .repeated_disposal => 25,
            .copied_disposal => 38,
            .conditional_disposal => 38,
            // Lowered from 50 with `dropped_disposal`, for its reason: the
            // old number was above what even its own base reads at 256.
            // Measured at 53.1% of 128 and 49.6% of 256 on both streams,
            // set under both.
            .copyable_holds_linear => 48,
            // Lowered from 35 when the generator gained compound assignment.
            // Not because the mutation got worse at anything: it needs a value
            // given up into a call, and the generator now writes a reading
            // operand where it used to write a consuming one -- and, more than
            // that, one more decision per assignable place shifts every choice
            // after it, so the programs are different programs. Measured at
            // 32.0% of 128 and 31.3% of 256 then; lowered again at the next
            // 256-seed measurement, which reads 25.4% on the stream before
            // the float forms and 25.8% with them -- the stream did not
            // move, the old number was calibrated at a smaller sample.
            // Measured at 29.7% of 128, set under every reading.
            .abrupt_after_a_transfer => 25,
            // Every generated program that declares the generic block carries
            // `GP`, which is about half of them.
            .dropped_phantom => 10,
            // Lowered from 35 when the generator gained the newtype block and
            // again when a call's argument gained a name: each draws a
            // decision or two more, so every choice after it lands somewhere
            // else and the programs a fixed seed draws are different
            // programs. An arm holding one value also no longer counts -- the
            // narrowing skips it rather than empty it. Measured at 28.1% of
            // 32 and 25.0% of 64 with all of that in the stream; set under
            // both.
            .narrowed_range => 24,
            // Reached wherever the generator declares the newtype, which is
            // a coin flip -- and every program that declares it also
            // constructs it with a literal the refinement was written to
            // accept, so declaring it is the whole of what this needs.
            // Measured at 40.6% of 32 and 46.9% of 64; set under both.
            .narrowed_refinement => 35,
            // Reached wherever the generator declares the newtype block,
            // which is a coin flip -- every such program writes `_fromNewtype`
            // and `_fromNewtypeMatch`, and each destructures a read of the
            // value the block just constructed, so declaring the block is the
            // whole of what this needs. Measured on its own, not read off
            // `narrowed_refinement`: 40.6% of 32 and 46.9% of 64, the same
            // percentages because both mutations are reached by the same
            // condition. Set under both.
            .summed_newtype => 35,
        };
    }

    /// The other rules the mutated program is allowed to cite.
    ///
    /// Empty for a mutation that breaks its rule and nothing else, which is
    /// where every mutation starts. A rule is added here only when the one
    /// mistake the mutation makes is genuinely visible twice -- a later pass
    /// reporting the same hole from where it stands -- and never to quiet a
    /// second mistake the mutation happened to make, because a mutation that
    /// makes two is no longer evidence about either.
    ///
    /// The set bounds the citations; it does not require them. Which members
    /// appear depends on the program mutated, so demanding all of them would
    /// forbid the programs that provoke only one.
    pub fn cascade(self: Mutation) []const []const u8 {
        return switch (self) {
            // An expression naming a variant that does not exist has no type,
            // and the type checker says so where it stands: [T-Infer] where
            // nothing else determines the type, [T-Mismatch] where the position
            // fixes one the hole cannot answer to. Both are the renamed name,
            // read by the pass after the one that reported it.
            .unknown_variant => &.{ "T-Infer", "T-Mismatch" },
            // As above, on the other answer: a selection of a field the type
            // does not have is an expression with no type.
            .unknown_field => &.{"T-Infer"},
            // The same hole, plus the reference that is no longer there:
            // misspelling a member can leave its declaration unused.
            .unknown_member => &.{ "T-Infer", "N-Unused" },
            // The deleted statement was the value's only consumer, so the
            // binding that held it is left with nothing reading it and the
            // function that took it with nothing calling it. Both are the same
            // absent statement, seen by the pass that counts references rather
            // than the one that counts obligations.
            .dropped_disposal => &.{"N-Unused"},
            // As above: the deleted member was the only reference to whatever
            // its body used, so the deletion is reported a second time as a
            // declaration or imported module nothing names.
            .dropped_implementation => &.{ "N-Unused", "M-Unused" },
            .dropped_component_implementation,
            .opened_component_requirement_argument,
            .dropped_derive_bound,
            .dropped_template_member_bound,
            .replaced_template_member_bound,
            => &.{},
            // The return type is what the body is checked against, so rewriting
            // it necessarily re-checks the body -- and a body that answers with
            // an exit status no longer answers to the signature above it. One
            // edit, seen as the signature the language fixes and as the body
            // that no longer meets it.
            // And [T-Bound] for the same reason one step further on. Where the
            // body's tail is a call through a trait, what the call is asked
            // for is what settles the trait's arguments -- so rewriting the
            // return type names a different implementation, and the one the
            // program wrote is no longer the one it asks for. Still the single
            // edit, seen by the rule that settles those arguments rather than
            // by the one that compares two types.
            .wrong_entry_type => &.{ "T-Mismatch", "T-Bound" },
            .repeated_disposal => &.{},
            .copied_disposal => &.{},
            // A conditional take may also invalidate an observation on the
            // path that takes its owner.
            .conditional_disposal => &.{"O-Borrow"},
            .copyable_holds_linear => &.{},
            // Nothing beside it. The value is still given away exactly once
            // and still to the same function, so the transfer is reported
            // once -- and a scope holding another linear value beside it is a
            // scope this mutation is not aimed at, because control leaving
            // there abandons that one too. `owesSomethingElse` is what keeps
            // the mutant to one mistake, rather than a citation admitted here
            // and admitted over the whole corpus with it.
            .abrupt_after_a_transfer => &.{},
            // Removing an identity-only annotation changes no owned parts.
            .dropped_phantom => &.{},
            // Nothing beside it. The bound moves and the arm it belongs to
            // is what covered the value, so what stops covering it is
            // reported once, where the walk finds the gap.
            .narrowed_range => &.{},
            // Nothing beside it. The construction this targets is the only
            // place the moved bound is asked about, so the one edit is
            // reported once, at the one call that discharges against it.
            .narrowed_refinement => &.{},
            // Nothing beside it. The fresh binding is read exactly where the
            // operator is written and nowhere else, so the one mistake is
            // reported once, where the checker stops on the poisoned sum;
            // the pattern below it binds nothing further to go wrong about.
            .summed_newtype => &.{},
        };
    }

    /// What the mutation asserts, for a failure to read as a sentence.
    pub fn why(self: Mutation) []const u8 {
        return switch (self) {
            .unknown_variant => "a variant name no enum declares is rejected",
            .unknown_field => "a field name the type does not have is rejected",
            .unknown_member => "a name the type does not declare is rejected",
            .dropped_disposal => "a linear value nothing disposes of is rejected",
            .dropped_implementation => "an implementation missing one of its trait's operations is rejected",
            .dropped_component_implementation => "a derive whose concrete component implementation was removed is rejected",
            .opened_component_requirement_argument => "an open component requirement argument is rejected at the template",
            .dropped_derive_bound => "a generic derive no longer proving a component requirement is rejected",
            .dropped_template_member_bound => "a template member no longer carrying one signature bound is rejected",
            .replaced_template_member_bound => "a template member carrying a different bound from its signature is rejected",
            .wrong_entry_type => "an entry point returning something other than `UInt8` is rejected",
            .repeated_disposal => "a linear value given away twice is rejected",
            .copied_disposal => "a copy of a linear value is rejected",
            .conditional_disposal => "paths disagreeing about a linear value are rejected",
            .copyable_holds_linear => "a copyable type holding a linear one is rejected",
            .abrupt_after_a_transfer => "a value given up into a call control leaves before starting is rejected",
            .dropped_phantom => "a parameter no longer declared `phantom` is rejected",
            .narrowed_range => "a covering match narrowed by one is rejected",
            .narrowed_refinement => "a construction the narrowed range no longer proves is rejected",
            .summed_newtype => "an operator applied to a newtype value is rejected",
        };
    }

    /// The mutated program, or null where this program has nothing to mutate.
    pub fn apply(
        self: Mutation,
        gpa: std.mem.Allocator,
        ast: *const Ast,
        res: *const Resolution,
        types_of: *const Typing,
        text: []const u8,
    ) !?[]const u8 {
        // Which record the checker holds for each call. Every mutation built
        // on a disposal reads a call's arguments in the order the callee
        // declares its parameters, and only the checker knows that order --
        // an argument may name the parameter it fills, so the written order
        // and the declared order are two orders.
        const calls = &types_of.call_index;

        return switch (self) {
            .unknown_variant => unknownVariant(gpa, ast, res, text),
            .unknown_field => unknownField(gpa, ast, types_of, text),
            .unknown_member => unknownMember(gpa, ast, res, text),
            .dropped_disposal => droppedDisposal(gpa, ast, res, types_of, calls, text),
            .dropped_implementation => droppedImplementation(gpa, ast, text),
            .dropped_component_implementation => droppedComponentImplementation(gpa, ast, text),
            .opened_component_requirement_argument => openedComponentRequirementArgument(gpa, ast, text),
            .dropped_derive_bound => droppedDeriveBound(gpa, ast, text),
            .dropped_template_member_bound => droppedTemplateMemberBound(gpa, ast, text),
            .replaced_template_member_bound => replacedTemplateMemberBound(gpa, ast, text),
            .wrong_entry_type => wrongEntryType(gpa, ast, text),
            .repeated_disposal => repeatedDisposal(gpa, ast, res, types_of, calls, text),
            .copied_disposal => copiedDisposal(gpa, ast, res, types_of, calls, text),
            .conditional_disposal => conditionalDisposal(gpa, ast, res, types_of, calls, text),
            .copyable_holds_linear => copyableHoldsLinear(gpa, ast, text),
            .abrupt_after_a_transfer => abruptAfterATransfer(gpa, ast, res, types_of, calls, text),
            .dropped_phantom => droppedPhantom(gpa, ast, text),
            .narrowed_range => narrowedRange(gpa, ast, text),
            .narrowed_refinement => narrowedRefinement(gpa, ast, res, text),
            .summed_newtype => summedNewtype(gpa, ast, types_of, text),
        };
    }
};

/// Renames the first variant reference to a name nothing declares.
///
/// Both spellings are reached: `Colour.Red` and `.Red` name a variant at the
/// same token, so one replacement covers the form that carries its enum and
/// the form that takes it from context. That is the point — the two are
/// checked by different code, and only a program that is wrong can show
/// whether both do the checking.
fn unknownVariant(gpa: std.mem.Allocator, ast: *const Ast, res: *const Resolution, text: []const u8) !?[]const u8 {
    // A name the program cannot already have declared, so the mutation cannot
    // accidentally land on something real.
    const fresh = "_Zz";
    if (std.mem.indexOf(u8, text, fresh) != null) return null;

    for (0..ast.exprCount()) |i| {
        const id = ExprId.at(@intCast(i));
        if (!namesAVariant(ast, res, id)) continue;

        const at = ast.tokenSpan(ast.exprMain(id));
        const out = try std.mem.concat(gpa, u8, &.{ text[0..at.start], fresh, text[at.end..] });
        return out;
    }
    return null;
}

/// Renames the first field reference to a name nothing declares.
///
/// The checker identifies actual field projections, excluding variants and
/// method calls that share the same source shape.
fn unknownField(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    types_of: *const Typing,
    text: []const u8,
) !?[]const u8 {
    const fresh = "_Zz";
    if (std.mem.indexOf(u8, text, fresh) != null) return null;

    for (0..ast.exprCount()) |i| {
        const id = ExprId.at(@intCast(i));
        if (ast.exprTag(id) != .field) continue;
        // A method name can be its declaration's sole use. Removing it would
        // also produce an unused-declaration error, outside this mutation.
        if (types_of.placeProjection(id) == null) continue;

        const at = ast.tokenSpan(ast.exprMain(id));
        const out = try std.mem.concat(gpa, u8, &.{ text[0..at.start], fresh, text[at.end..] });
        return out;
    }
    return null;
}

/// Renames the first name reached through a type to one it does not declare.
///
/// A type is a namespace, so this is the rule that says a name reached through
/// one has to be there. Nothing else in the suite can show it: a program that
/// spells the name right cannot tell a lookup that checks from one that
/// answers whatever it is asked.
fn unknownMember(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    res: *const Resolution,
    text: []const u8,
) !?[]const u8 {
    const fresh = "_Zz";
    if (std.mem.indexOf(u8, text, fresh) != null) return null;

    for (0..ast.exprCount()) |i| {
        const id = ExprId.at(@intCast(i));
        if (ast.exprTag(id) != .field) continue;
        if (namesAVariant(ast, res, id)) continue;
        if (selectsFromAValue(ast, res, id)) continue;
        // A module's name is checked by a different rule with its own message,
        // and so is a primitive's -- nobody declares one, so a name it does not
        // hold is undefined rather than a variant that is not there. A name
        // that reached nothing names no namespace this tree can see.
        const base = res.targetOf(ast.unaryOperand(id));
        if (base == BindingId.none) continue;
        if (res.kindOf(base) != .declared_type) continue;
        if (isHandedAPlace(ast, res, id)) continue;

        const at = ast.tokenSpan(ast.exprMain(id));
        return try std.mem.concat(gpa, u8, &.{ text[0..at.start], fresh, text[at.end..] });
    }
    return null;
}

/// Whether an expression is called with an argument that names a binding.
///
/// A callee nobody declared has no parameter list, so what its arguments are
/// handed over as is a question with no answer -- and the passes that read
/// conventions answer it out of a fallback. Where the argument is a value built
/// in the call, that answer cannot be seen: a temporary is used once under
/// either convention. Where it names a binding it can be. The binding reads as
/// taken and then used again, and a borrow of one reads as a write through
/// something that permits none -- neither report about the program, both about
/// what the compiler assumed in place of a declaration it never found.
///
/// A borrow needs no test of its own, because `&x` names `x` inside itself.
fn isHandedAPlace(ast: *const Ast, res: *const Resolution, id: ExprId) bool {
    for (0..ast.exprCount()) |i| {
        const c = ExprId.at(@intCast(i));
        if (ast.exprTag(c) != .call) continue;
        if (ast.call(c).callee != id) continue;

        for (ast.call(c).args) |a| {
            const at = ast.exprSpan(a);
            for (0..ast.exprCount()) |j| {
                const inner = ExprId.at(@intCast(j));
                if (ast.exprTag(inner) != .name_ref) continue;
                const span = ast.exprSpan(inner);
                if (span.start < at.start or span.end > at.end) continue;
                if (res.targetOf(inner) != BindingId.none) return true;
            }
        }
        return false;
    }
    return false;
}

/// Deletes the statement that hands a linear value to something that takes it.
///
/// The direction nothing else in the suite can go. Every accepting case shows
/// that a program which disposes of its values compiles; only a program that
/// stops disposing of one can show that the compiler noticed. And it is the
/// rule that has to hold *per path*, which is the part a reader most doubts.
///
/// A `let` counts as well as a bare call, and that is where nearly every
/// disposal is: an `expr_stmt` may only hold a Unit value, so a function that
/// takes a linear value and answers something can be called from a `let` and
/// from nowhere else. While this looked at bare calls alone it reached three
/// programs in the corpus and none of the generated ones -- so [O-Leak], which
/// is the whole of what linearity buys, was the least-checked rule the
/// compiler has.
fn droppedDisposal(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    res: *const Resolution,
    types_of: *const Typing,
    calls: *const CallIndex,
    text: []const u8,
) !?[]const u8 {
    for (0..ast.stmtCount()) |i| {
        const s = node.StmtId.at(@intCast(i));
        // A linear binding whose release is scheduled by `defer let` is
        // disposed of by the keyword, so the disposal to drop is the schedule:
        // written `let`, the value is held to the end of the block.
        if (ast.stmtTag(s) == .let_decl and ast.stmtIsDeferredBinding(s)) {
            const b = res.bindingOf(s);
            if (b.index() >= res.bindingCount() or !types_of.mustConsume(types_of.bindingType(b))) continue;
            return try std.mem.concat(gpa, u8, &.{
                text[0..ast.tokenSpan(ast.stmtTokens(s).start).start],
                text[ast.tokenSpan(ast.stmtMain(s)).start..],
            });
        }
        switch (ast.stmtTag(s)) {
            .expr_stmt, .defer_stmt => {},
            // The binding goes with the statement, so a name still reading it
            // would be reported missing instead. That rejection says nothing
            // about disposal, and a mutation that names a rule has to break
            // that one.
            .let_decl => if (isRead(ast, res, res.bindingOf(s))) continue,
            .let_destructure, .let_read_destructure, .defer_release, .err => continue,
        }
        // Cutting the statement of a `defer let` would drop the binding the
        // release is scheduled for; the schedule is dropped above instead.
        if (ast.stmtTag(s) == .let_decl and ast.stmtIsDeferredBinding(s)) continue;

        const call = ast.stmtData(s).init;
        if (call == node.ExprId.none) continue;
        if (ast.exprTag(call) != .call) continue;

        const normal = calls.callOf(types_of, call) orelse continue;
        const d = switch (normal.target) {
            .declared => |decl| decl,
            .closure_recovery, .array_view, .array_length, .closure, .indirect, .generic_callable, .erased => continue,
        };

        const params = ast.declParams(d);
        const args = argumentsInOrder(types_of, calls, call, params) orelse continue;
        if (!givesAnythingLinear(types_of, params, args)) continue;

        const at = ast.stmtSpan(s);
        return try std.mem.concat(gpa, u8, &.{
            text[0..at.start],
            text[endOfStatement(ast, text, s)..],
        });
    }
    return null;
}

/// A statement that hands a named linear binding to something that takes it.
///
/// The three mutations below all turn on there being one value carrying one
/// obligation, so the argument has to be the binding itself and not a value
/// built in the call: a temporary handed over twice is two values given away
/// once each, and a program that does that is not wrong about anything.
const Disposal = struct {
    stmt: node.StmtId,
    /// The argument naming the binding.
    arg: ExprId,
    /// What the statement calls.
    callee: node.DeclId,
};

/// The first disposal, or null where the program makes none.
fn firstDisposal(
    ast: *const Ast,
    res: *const Resolution,
    types_of: *const Typing,
    calls: *const CallIndex,
) ?Disposal {
    return disposalFrom(ast, res, types_of, calls, 0);
}

/// The first disposal at or after a statement, or null where there is none.
///
/// Every statement form that can hold one, because the corpus writes all of
/// them: a function that answers something has to be called from a `let`, since
/// an `expr_stmt` may hold nothing but a Unit value, while one answering `()` is
/// called as a statement of its own -- or scheduled with `defer`, which is a
/// disposal placed somewhere else rather than a different kind of thing.
fn disposalFrom(
    ast: *const Ast,
    res: *const Resolution,
    types_of: *const Typing,
    calls: *const CallIndex,
    from: usize,
) ?Disposal {
    for (from..ast.stmtCount()) |i| {
        const s = node.StmtId.at(@intCast(i));
        switch (ast.stmtTag(s)) {
            .let_decl, .expr_stmt, .defer_stmt => {},
            .let_destructure, .let_read_destructure, .defer_release, .err => continue,
        }
        // The binding is what schedules the release, so cutting or repeating
        // its statement changes what is released rather than what disposes.
        if (ast.stmtTag(s) == .let_decl and ast.stmtIsDeferredBinding(s)) continue;

        const call = ast.stmtData(s).init;
        if (call == node.ExprId.none) continue;
        if (ast.exprTag(call) != .call) continue;

        const normal = calls.callOf(types_of, call) orelse continue;
        const d = switch (normal.target) {
            .declared => |decl| decl,
            .closure_recovery, .array_view, .array_length, .closure, .indirect, .generic_callable, .erased => continue,
        };

        const params = ast.declParams(d);
        const args = argumentsInOrder(types_of, calls, call, params) orelse continue;

        for (params, args) |p, a| {
            if (!givesAwaySomethingLinear(types_of, p, a)) continue;
            if (ast.exprTag(a) != .name_ref) continue;
            const b = res.targetOf(a);
            if (b == BindingId.none) continue;
            if (disposedElsewhere(ast, res, types_of, calls, b, s)) continue;
            return .{ .stmt = s, .arg = a, .callee = d };
        }
    }
    return null;
}

/// Whether some other statement also gives this binding away.
///
/// Every mutation built on a disposal assumes it is the only one: deleting it
/// is a leak, repeating it is a double move, putting it behind a condition
/// makes the paths disagree. None of those is true of a value disposed of
/// twice, which is what a schedule cancelled on one path is -- one disposal
/// where control leaves and one where it does not, both written, exactly one
/// of them running. A mutation aimed at such a pair reports [O-Move] beside
/// the rule it claims, and a mutant making two mistakes is evidence about
/// neither.
fn disposedElsewhere(
    ast: *const Ast,
    res: *const Resolution,
    types_of: *const Typing,
    calls: *const CallIndex,
    b: BindingId,
    besides: node.StmtId,
) bool {
    var at_stmt: usize = 0;
    while (at_stmt < ast.stmtCount()) {
        const s = node.StmtId.at(@intCast(at_stmt));
        at_stmt += 1;
        if (s == besides) continue;
        switch (ast.stmtTag(s)) {
            .let_decl, .expr_stmt, .defer_stmt => {},
            .let_destructure, .let_read_destructure, .defer_release, .err => continue,
        }
        // The binding is what schedules the release, so cutting or repeating
        // its statement changes what is released rather than what disposes.
        if (ast.stmtTag(s) == .let_decl and ast.stmtIsDeferredBinding(s)) continue;

        const call = ast.stmtData(s).init;
        if (call == node.ExprId.none) continue;
        if (ast.exprTag(call) != .call) continue;

        const normal = calls.callOf(types_of, call) orelse continue;
        const d = switch (normal.target) {
            .declared => |decl| decl,
            .closure_recovery, .array_view, .array_length, .closure, .indirect, .generic_callable, .erased => continue,
        };

        const params = ast.declParams(d);
        const args = argumentsInOrder(types_of, calls, call, params) orelse continue;

        for (params, args) |p, a| {
            if (!givesAwaySomethingLinear(types_of, p, a)) continue;
            if (ast.exprTag(a) != .name_ref) continue;
            if (res.targetOf(a) == b) return true;
        }
    }
    return false;
}

/// Where a statement ends in the source, semicolon and all.
///
/// A statement's extent stops at its expression; what separates it from the
/// next is the semicolon, so a mutation that moved or deleted a statement
/// without it would make a syntax error rather than a program.
fn endOfStatement(ast: *const Ast, text: []const u8, s: node.StmtId) usize {
    var end = ast.stmtSpan(s).end;
    while (end < text.len and (text[end] == ' ' or text[end] == '\t')) end += 1;
    if (end < text.len and text[end] == ';') end += 1;
    return end;
}

/// What separates a statement inserted before another from that other one.
///
/// A newline and the same indentation where the statement it precedes begins
/// its line, and a single space where it does not: a newline ends a statement,
/// so something has to come between the two, and copying a line prefix that
/// held code would repeat that code as well.
fn lineGap(gpa: std.mem.Allocator, text: []const u8, start: usize) ![]const u8 {
    var line = start;
    while (line > 0 and text[line - 1] != '\n') line -= 1;
    for (text[line..start]) |c| {
        if (c != ' ' and c != '\t') return " ";
    }
    return try std.mem.concat(gpa, u8, &.{ "\n", text[line..start] });
}

/// Repeats the statement that hands a linear value away.
///
/// The value is then taken twice, which is a double free. Nothing else in the
/// suite goes here: an accepted program takes each value once, and a rewrite
/// of one takes it once too.
///
/// [O-Loop] is the rule this could otherwise reach, and it cannot: a move in a
/// loop body of a binding declared outside it is rejected, so in a program that
/// was accepted the binding is declared inside, and a second move where the
/// first one sits cannot be outside what the first one was inside.
///
/// What the repeat must not do is create an obligation of its own, which is why
/// the disposal it picks is one that answers with nothing linear. A call
/// answering another linear value is a value's next stop and not its last, and
/// repeating one binds a second value the program has nowhere to give away --
/// so the leak the mutation invented would be reported beside the double move
/// it claims, and neither citation would be evidence about the other.
fn repeatedDisposal(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    res: *const Resolution,
    types_of: *const Typing,
    calls: *const CallIndex,
    text: []const u8,
) !?[]const u8 {
    var at_stmt: usize = 0;
    const d = while (disposalFrom(ast, res, types_of, calls, at_stmt)) |candidate| {
        at_stmt = candidate.stmt.index() + 1;
        if (answersSomethingLinear(ast, types_of, candidate)) continue;
        // A schedule repeated is not a move repeated. Both placements reach the
        // same exit, the second written runs first and takes the value, and the
        // first is then a `defer` that cannot fire -- [O-DeferDead], which is a
        // different rule than this mutation claims.
        if (ast.stmtTag(candidate.stmt) == .defer_stmt) continue;
        break candidate;
    } else return null;

    const at = ast.stmtSpan(d.stmt);
    const end = endOfStatement(ast, text, d.stmt);
    const gap = try lineGap(gpa, text, at.start);

    // A statement that binds nothing is repeated as it stands.
    if (ast.stmtTag(d.stmt) == .expr_stmt) {
        return try std.mem.concat(gpa, u8, &.{
            text[0..end], gap, text[at.start..],
        });
    }

    // One that binds a name gets a name of its own. Repeated verbatim it would
    // declare the binding a second time, and that is a different rule.
    const fresh = "_zzr";
    if (std.mem.indexOf(u8, text, fresh) != null) return null;

    const name = ast.tokenSpan(ast.stmtData(d.stmt).name);
    return try std.mem.concat(gpa, u8, &.{
        text[0..name.start],
        fresh,
        text[name.end..end],
        gap,
        text[at.start..],
    });
}

/// Copies the linear value the next statement hands away.
///
/// Placed before the disposal rather than replacing it, so the value is still
/// handed away exactly once and the copy is the only thing wrong. It is read
/// again below, so the copy is not a dead one; the right-hand side of a `let`
/// consumes, so it is not a copy in a reading position either.
///
/// The binding carries no annotation on purpose. A rejected copy has no type,
/// so the binding has none and nothing is obliged to consume it -- while an
/// annotation would name the linear type and leave a second value leaked.
fn copiedDisposal(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    res: *const Resolution,
    types_of: *const Typing,
    calls: *const CallIndex,
    text: []const u8,
) !?[]const u8 {
    const fresh = "_zzc";
    if (std.mem.indexOf(u8, text, fresh) != null) return null;

    const d = firstDisposal(ast, res, types_of, calls) orelse return null;
    const at = ast.stmtSpan(d.stmt);
    const arg = ast.exprSpan(d.arg);

    return try std.mem.concat(gpa, u8, &.{
        text[0..at.start],
        "let ",
        fresh,
        " = copy(",
        text[arg.start..arg.end],
        ");",
        try lineGap(gpa, text, at.start),
        text[at.start..],
    });
}

/// Puts the statement that hands a linear value away behind a condition.
///
/// One path through the join then consumes the value and the other leaves it
/// held, which has no safe answer: calling it moved makes one path leak and
/// calling it held frees the other twice. It is the rule a reader most doubts,
/// because it is reported where nothing is written rather than at a use.
///
/// The condition is a literal. Which way it leads is not the question -- the
/// analysis is over paths and not over values, and a condition read from the
/// program would drag whatever it names into the block.
fn conditionalDisposal(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    res: *const Resolution,
    types_of: *const Typing,
    calls: *const CallIndex,
    text: []const u8,
) !?[]const u8 {
    const d = firstDisposal(ast, res, types_of, calls) orelse return null;

    // The block takes the binding with it, so a name still reading it would be
    // reported missing instead. That rejection says nothing about the paths.
    if (ast.stmtTag(d.stmt) == .let_decl and isRead(ast, res, res.bindingOf(d.stmt))) return null;

    const at = ast.stmtSpan(d.stmt);
    const end = endOfStatement(ast, text, d.stmt);
    const inner = text[at.start..end];

    // A newline ends a statement, and the block puts one statement where a
    // whole line used to be -- so the two inside it are separated in the one
    // way that survives being written on a single line.
    return try std.mem.concat(gpa, u8, &.{
        text[0..at.start],
        "if true { ",
        inner,
        if (std.mem.endsWith(u8, inner, ";")) " };" else "; };",
        text[end..],
    });
}

/// Declares a copyable type holding a linear one.
///
/// An affine wrapper may hold a linear value and inherits its settlement
/// obligation. An explicit copyable wrapper cannot grant duplication of that
/// same value. The mutation adds that incompatible declaration policy.
///
/// A declaration added rather than an existing one changed: giving a field of
/// a type already in use a different type would be rejected everywhere that
/// type is built, and none of those rejections is about universes.
fn copyableHoldsLinear(gpa: std.mem.Allocator, ast: *const Ast, text: []const u8) !?[]const u8 {
    const fresh = "_ZzHolds";
    if (std.mem.indexOf(u8, text, fresh) != null) return null;

    for (0..ast.declCount()) |i| {
        const d = node.DeclId.at(@intCast(i));
        switch (ast.declTag(d)) {
            .enum_, .struct_ => {},
            else => continue,
        }
        if (ast.declOwnershipPolicy(d) != .linear) continue;
        // A generic type named without its arguments is a different rule.
        if (ast.declTypeParams(d).len != 0) continue;
        if (ast.tokenTag(ast.declName(d)) != .identifier) continue;

        return try std.mem.concat(gpa, u8, &.{
            text,
            "\n@copyable struct ",
            fresh,
            " { _f: ",
            ast.tokenText(ast.declName(d)),
            " }\n",
        });
    }
    return null;
}

/// Gives the construct a disposal hands its value to an operand that leaves.
///
/// `[O-Uncommitted]` holds over a window nothing else in the suite can widen:
/// between a named Linear value being given up and the construct receiving it,
/// which is closed by the operand written next. So the mutation needs a
/// construct taking two values, one naming the binding and one leaving after
/// it -- and no program the compiler accepts holds that shape the safe way
/// round. Written the other way, with the operand that leaves first, the
/// binding the later operand would have given away is still held where control
/// goes, which is [O-Leak]: swapping two operands of an accepted program
/// therefore produces one the compiler is right to accept, and asserting
/// otherwise blames it for the harness's mistake.
///
/// So the construct is supplied rather than found. The wrapper does what the
/// call site already did -- takes the value and hands it to the same function
/// -- and the whole of the difference is the operand beside it, which leaves
/// before the wrapper is entered. The value is still given away exactly once,
/// to the same callee, so the one thing the program is now wrong about is
/// where control was when the transfer closed.
///
/// A `return` rather than a `break`, because a `break` written as an operand
/// leaves only the loops between it and the one it names: the construct around
/// it receives its values the moment the loop yields, so an injected `break`
/// would need an injected loop, and a move inside a loop body of a binding
/// declared outside it is [O-Loop] instead.
fn abruptAfterATransfer(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    res: *const Resolution,
    types_of: *const Typing,
    calls: *const CallIndex,
    text: []const u8,
) !?[]const u8 {
    const fresh = "_zzafter";
    if (std.mem.indexOf(u8, text, fresh) != null) return null;

    const d = lastDisposal(ast, res, types_of, calls) orelse return null;

    // The wrapper is a declaration of its own, so the signature it mirrors has
    // to be one a declaration can carry: a member of an `impl` and a generic
    // function are reached by more than a name, and a type written with
    // arguments is an instantiation whose name is not what was written.
    if (ast.memberOwner(d.callee) != TokenId.none) return null;
    if (ast.declTypeParams(d.callee).len != 0) return null;
    const params = ast.declParams(d.callee);
    // One parameter, so the wrapper takes what the call site had to give.
    // Passing on a second value would mean a second linear argument left
    // behind, and a value nothing takes is [O-Leak] rather than this.
    if (params.len != 1) return null;
    if (params[0].written.args.len() != 0) return null;
    if (ast.declReturnArgs(d.callee).len() != 0) return null;

    // Spelled by the pass that settles what a type is, rather than from the
    // token an annotation begins with: `()` is written with two of those, and
    // a call handing a value to something that answers with it is ordinary.
    // A name in angle brackets is the spelling of a type there is no name for,
    // which is a program this cannot write a wrapper against.
    const takes = types_of.nameOf(types_of.exprType(d.arg));
    const answers = types_of.nameOf(types_of.declReturn(d.callee));
    if (takes.len == 0 or takes[0] == '<') return null;
    if (answers.len == 0 or answers[0] == '<') return null;
    // Abbreviated diagnostic names cannot form a source annotation.
    if (std.mem.indexOf(u8, takes, "…") != null or std.mem.indexOf(u8, answers, "…") != null) return null;

    // `return 0` leaves the function the transfer is written in, so zero has
    // to be a value of what that function answers with.
    //
    // The domain is asked first, because `holds` alone is the wrong question
    // here: poison holds every value, so that an expression already reported
    // is not reported again for its range. That makes an unresolved answer
    // read as "zero fits", and the mutation writes `return 0` into a function
    // answering something else -- a mutant carrying a type error beside the
    // rule it was built to provoke, which is a mutant that proves nothing.
    const owner = enclosingFunction(ast, d.arg) orelse return null;
    const answered = types_of.declReturn(owner);
    if (types_of.get(answered) != .integer) return null;
    if (!types_of.holds(answered, 0)) return null;

    const callee = ast.call(ast.stmtData(d.stmt).init).callee;
    const at = ast.exprSpan(callee);
    const arg = ast.exprSpan(d.arg);

    return try std.mem.concat(gpa, u8, &.{
        text[0..at.start],
        fresh,
        text[at.end..arg.end],
        // After the argument rather than before the closing parenthesis: what
        // separates the two is whatever the author wrote, trailing comma and
        // line break included.
        ", return 0",
        text[arg.end..],
        "\nfn ",
        fresh,
        "(sink _a: ",
        takes,
        // A callee returning `()` writes no result, and so does its wrapper.
        if (types_of.declReturn(d.callee) == .unit) ", _b: UInt8)" else ", _b: UInt8) -> ",
        if (types_of.declReturn(d.callee) == .unit) "" else answers,
        " { ",
        ast.exprText(callee),
        "(_a) }\n",
    });
}

/// The last disposal outside a loop, or null where the program makes none.
///
/// The last rather than the first, because control leaves from it: a transfer
/// written after this one would be skipped, and a value the program gives away
/// there would be held where the function exits. That is [O-Leak], reported
/// beside the rule this claims, and neither citation would be evidence about
/// the other.
///
/// Outside a loop for the same reason one step further on. A loop body's later
/// statements are what its earlier ones are written for -- the counter it
/// copies is read by the test at the head and by the write at the foot -- so
/// leaving from inside one makes a copy that was live a copy of something
/// nothing reads. [O-CopyDead] is then reported beside this rule, about a
/// `copy` the program wrote for a purpose the mutation removed.
/// Not a scheduled one, one step further still. A `defer` runs where control
/// leaves, so a `return` written into what it schedules leaves from inside a
/// scope exit -- [S-Defer], reported beside the rule this claims, about a jump
/// the mutation invented rather than about the transfer it was aimed at.
///
/// And not one the scope still owes something else at, which is the same
/// reason a third time and the one the transferred value cannot answer for
/// itself: see `owesSomethingElse`.
fn lastDisposal(
    ast: *const Ast,
    res: *const Resolution,
    types_of: *const Typing,
    calls: *const CallIndex,
) ?Disposal {
    var found: ?Disposal = null;
    var at_stmt: usize = 0;
    while (disposalFrom(ast, res, types_of, calls, at_stmt)) |candidate| {
        at_stmt = candidate.stmt.index() + 1;
        if (ast.stmtTag(candidate.stmt) == .defer_stmt) continue;
        if (isInsideALoop(ast, candidate.arg)) continue;
        if (owesSomethingElse(ast, res, types_of, candidate)) continue;
        found = candidate;
    }
    return found;
}

/// Whether the scope a transfer is written in still holds a linear value
/// besides the one it transfers.
///
/// Control leaving a scope abandons every linear value that scope is still
/// holding, so an early exit written where a second obligation is outstanding
/// leaks that one as well as leaving the transfer uncommitted. One edit making
/// two mistakes is evidence about neither, which is why the selection answers
/// this rather than the verdict tolerating what it produces: a rule the
/// mutation may cite is a rule it may cite over the whole corpus, so admitting
/// the leak here would admit a spurious one everywhere.
///
/// Outstanding is read off the mentions. A linear value is given away exactly
/// once, so a binding declared before this statement and named at or after it
/// is one the scope has yet to discharge -- and one named only before it is
/// one already gone. A binding declared after the statement is not held where
/// control leaves from it, and the transferred value itself is the obligation
/// the mutation is about.
///
/// **Bound:** one walk of the program's expressions, as the two questions
/// beside it are.
fn owesSomethingElse(
    ast: *const Ast,
    res: *const Resolution,
    types_of: *const Typing,
    d: Disposal,
) bool {
    const owner = enclosingFunction(ast, d.arg) orelse return false;
    const body = ast.exprSpan(ast.declBody(owner));
    const at = ast.stmtSpan(d.stmt);
    const transferred = res.targetOf(d.arg);

    for (0..ast.exprCount()) |i| {
        const e = ExprId.at(@intCast(i));
        if (ast.exprTag(e) != .name_ref) continue;
        const span = ast.exprSpan(e);
        if (span.start < at.start or span.start < body.start or span.end > body.end) continue;
        const b = res.targetOf(e);
        if (b == BindingId.none or b == transferred) continue;
        if (!types_of.mustConsume(types_of.exprType(e))) continue;
        const declared = res.declaringToken(b);
        if (declared == TokenId.none) continue;
        if (ast.tokenSpan(declared).start >= at.start) continue;
        return true;
    }
    return false;
}

/// Whether an expression is written inside a loop body.
fn isInsideALoop(ast: *const Ast, id: ExprId) bool {
    const at = ast.exprSpan(id);
    for (0..ast.exprCount()) |i| {
        const e = ExprId.at(@intCast(i));
        switch (ast.exprTag(e)) {
            .loop_, .while_ => {},
            else => continue,
        }
        const span = ast.exprSpan(e);
        if (at.start >= span.start and at.end <= span.end) return true;
    }
    return false;
}

/// The function an expression is written inside, or null where it is in none.
///
/// By extent, which is what a mutation editing text has: functions do not
/// nest, so the one whose body spans this expression is the only one that
/// does.
fn enclosingFunction(ast: *const Ast, id: ExprId) ?node.DeclId {
    const at = ast.exprSpan(id);
    for (0..ast.declCount()) |i| {
        const d = node.DeclId.at(@intCast(i));
        if (ast.declTag(d) != .function) continue;
        const body = ast.declBody(d);
        if (body == ExprId.none) continue;
        const span = ast.exprSpan(body);
        if (at.start >= span.start and at.end <= span.end) return d;
    }
    return null;
}

/// Deletes one member of a trait implementation.
///
/// A bound admitting the type promises the operation exists, and a call
/// through the trait would reach nothing -- so the hole is a rule rather than
/// a program that merely does less. Deleted whole, from the start of its own
/// extent to the end of it, which is what leaves an `impl` that parses.
///
/// The member rather than the whole `impl`: deleting the block would take the
/// implementation with it, and a type that implements nothing breaks whatever
/// bound admitted it instead. That is a different rule, already covered.
/// Deletes the `phantom` one declaration spells, leaving a parameter nothing
/// names. What refuses the mutant is the rule the modifier exists to satisfy:
/// an unused declaration is an error, and `phantom` was the declaration that
/// said the disuse is the type system reading.
fn droppedPhantom(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    text: []const u8,
) !?[]const u8 {
    for (0..ast.declCount()) |i| {
        const d = node.DeclId.at(@intCast(i));
        for (ast.declTypeParams(d)) |p| {
            if (!p.phantom) continue;
            const at = ast.tokenSpan(p.name);
            const head = std.mem.lastIndexOf(u8, text[0..at.start], "phantom") orelse continue;
            // Only spacing may sit between the keyword and the name, or the
            // match belongs to some other spelling of the word.
            const gap = text[head + "phantom".len .. at.start];
            if (std.mem.trim(u8, gap, " \t\n").len != 0) continue;
            return try std.mem.concat(gpa, u8, &.{ text[0..head], text[at.start..] });
        }
    }
    return null;
}

/// Respells the first `..=` found in a covering match's arms to `..`.
///
/// A match with a `_` is left alone: the wildcard still answers for the value
/// the flag stops covering, so nothing becomes a gap and the rejection this
/// mutation exists to provoke never arrives. Every arm an accepted match
/// holds already covers a disjoint interval -- two that overlapped would be
/// `[T-Unreachable]` -- so the one value an inclusive arm's flag adds is
/// covered by that arm alone, and losing the flag uncovers exactly that
/// value.
///
/// Only a pattern's `..=`, never an expression's: `3..=7` and `3..7` are two
/// values of the same type, and the checker refuses neither -- narrowing one
/// would mutate an accepted program into another it is right to accept, which
/// answers for no rule at all.
fn narrowedRange(gpa: std.mem.Allocator, ast: *const Ast, text: []const u8) !?[]const u8 {
    for (0..ast.exprCount()) |i| {
        const id = ExprId.at(@intCast(i));
        if (!ast.exprTag(id).isMatch()) continue;

        const args = ast.call(id).args;
        var has_wildcard = false;
        var j: usize = 0;
        while (j < args.len) : (j += 2) {
            if (isCatchAll(ast, args[j])) has_wildcard = true;
        }
        if (has_wildcard) continue;

        j = 0;
        while (j < args.len) : (j += 2) {
            const pattern = args[j];
            if (ast.exprTag(pattern) != .range) continue;
            if (!ast.rangeInclusive(pattern)) continue;

            // An arm holding one value respells to an empty one, and an empty
            // arm is [T-Unreachable] before the match is uncovering -- a
            // rejection under a different rule than the one this claims. The
            // flag on any other arm covers one value on its own, which is the
            // premise the narrowing rests on.
            const ends = ast.rangeEnds(pattern);
            const lo_at = ast.exprExtent(ends.lhs);
            const hi_at = ast.exprExtent(ends.rhs);
            const lo = std.fmt.parseInt(i128, text[lo_at.start..lo_at.end], 10) catch null;
            const hi = std.fmt.parseInt(i128, text[hi_at.start..hi_at.end], 10) catch null;
            if (lo != null and lo == hi) continue;

            const at = ast.tokenSpan(ast.exprMain(pattern));
            std.debug.assert(std.mem.eql(u8, text[at.start..at.end], "..="));
            return try std.mem.concat(gpa, u8, &.{ text[0..at.start], "..", text[at.end..] });
        }
    }
    return null;
}

/// Tightens a newtype's `where it in lo..=hi` clause to just past the first
/// literal a direct construction in this program proves it with.
///
/// The literal is read back out of the construction rather than assumed --
/// what the corpus happens to prove and what a clause happens to admit are
/// two numbers this reads, not one this writes down, the same discipline
/// `droppedPhantom` and `narrowedRange` hold to. Only a non-fallible call
/// with one literal argument counts: `Name?(e)` asks nothing of the operand's
/// value, and a call whose argument is not a literal proves nothing this can
/// read back -- neither is evidence the moved bound excludes anything.
fn narrowedRefinement(gpa: std.mem.Allocator, ast: *const Ast, res: *const Resolution, text: []const u8) !?[]const u8 {
    for (0..ast.exprCount()) |i| {
        const id = ExprId.at(@intCast(i));
        if (ast.exprTag(id) != .call) continue;
        if (ast.callFallible(id)) continue;

        const c = ast.call(id);
        if (c.args.len != 1) continue;
        if (ast.exprTag(c.args[0]) != .int_literal) continue;

        // Which newtype a call constructs, through the lookup the resolver
        // already answers it with: a second reading of what a construction is
        // would be a second answer, and the two would disagree about exactly
        // the calls nobody wrote.
        const decl = resolve_mod.constructionOf(ast, res, id) orelse continue;
        const r = ast.newtypeRefinement(decl) orelse continue;
        if (r.lo_token == TokenId.none) continue;

        const arg_at = ast.tokenSpan(ast.exprMain(c.args[0]));
        const value = std.fmt.parseInt(u64, text[arg_at.start..arg_at.end], 10) catch continue;

        // The whole bound is replaced, sign and all: a lower bound written
        // `-40` has its digits at one span and its minus at another, and
        // rewriting only the digits moves the bound to `-1`, which narrows
        // nothing.
        const digits_at = ast.tokenSpan(r.lo_token);
        const from = if (r.lo_minus == TokenId.none) digits_at.start else ast.tokenSpan(r.lo_minus).start;
        const new_lo = try std.fmt.allocPrint(gpa, "{d}", .{value + 1});
        return try std.mem.concat(gpa, u8, &.{ text[0..from], new_lo, text[digits_at.end..] });
    }
    return null;
}

/// Binds the value a destructuring `let` takes apart to a fresh name, and
/// sums that name with itself in the destructure's own initialiser, wherever
/// the value is a newtype.
///
/// `[T-Operands]` refuses an operator over a newtype whatever the base is --
/// a name over a base inherits none of its operators -- so the site needs
/// nothing about the base, only that the value is one at all. Read the way
/// `checkNewtypePattern` itself reads it: which type a pattern takes apart is
/// settled by the initialiser's own settled type, not by resolving the
/// pattern's head, so `types_of.get` on `init`'s type is the one lookup this
/// asks rather than a second guess at what the pattern spells. The same
/// lookup identifies the newtype itself. Its representation does not grant
/// the built-in integer evidence required by arithmetic.
///
/// A fresh name summed with itself, and not the initialiser with a literal
/// appended: `Percent(50) + 1` also reaches `[T-Operands]`, but not through
/// the arithmetic type check. The right operand is checked against the left's
/// settled type, and a newtype's own `TypeId` has no integer bounds, so
/// `checkIntegerValue` refuses the literal on that mismatch before
/// `checkBinary` ever asks whether arithmetic holds -- the same rule code,
/// reached by a different routine, so a regression in the arithmetic type check
/// itself would go unnoticed behind a literal operand. A second read of the
/// same binding has no such shortcut: its type already matches exactly, so
/// the right operand passes and the left is what the arithmetic type check is
/// actually asked about -- the same shape the hand-written cases pin,
/// `a + b`, on the one name this can be sure is there.
///
/// The initialiser, whatever expression it is, and not a construction found
/// by a blind walk: a generated program constructs a newtype through one
/// binding and destructures a read of it through another, so a mutation that
/// only reached a destructure applied directly to `N(lit)` found nothing to
/// mutate in either. `checkDestructure` passes no expected type into a
/// `.call` pattern's initialiser -- the pattern names what is being taken
/// apart, so nothing outside asks the value to already be a particular type
/// -- and that holds whatever the initialiser is checked to, which is what
/// keeps the fresh binding's own type inferred rather than mismatched against
/// an outer one.
///
/// Restrict the duplicated input to Copyable newtypes. Otherwise the invented
/// second use could introduce an ownership error unrelated to this mutation.
fn summedNewtype(gpa: std.mem.Allocator, ast: *const Ast, types_of: *const Typing, text: []const u8) !?[]const u8 {
    const fresh = "_zzsum";
    if (std.mem.indexOf(u8, text, fresh) != null) return null;

    for (0..ast.stmtCount()) |i| {
        const s = node.StmtId.at(@intCast(i));
        if (ast.stmtTag(s) != .let_destructure) continue;

        const pattern = ast.stmtData(s).pattern;
        if (pattern == ExprId.none or ast.exprTag(pattern) != .call) continue;

        const init = ast.stmtData(s).init;
        if (init == ExprId.none) continue;
        const t = types_of.exprType(init);
        if (types_of.get(t) != .newtype) continue;
        if (!types_of.mayCopy(t)) continue;

        const stmt_at = ast.stmtSpan(s);
        const init_at = ast.exprExtent(init);
        const gap = try lineGap(gpa, text, stmt_at.start);

        return try std.mem.concat(gpa, u8, &.{
            text[0..stmt_at.start],
            "let ",
            fresh,
            " = ",
            text[init_at.start..init_at.end],
            ";",
            gap,
            text[stmt_at.start..init_at.start],
            fresh,
            " + ",
            fresh,
            text[init_at.end..],
        });
    }
    return null;
}

fn templateRanges(gpa: std.mem.Allocator, ast: *const Ast) !std.ArrayList(token.TokenRange) {
    var templates: std.ArrayList(token.TokenRange) = .empty;
    errdefer templates.deinit(gpa);
    for (0..ast.declCount()) |i| {
        const declaration = node.DeclId.at(@intCast(i));
        if (ast.declTag(declaration) == .template_impl) {
            try templates.append(gpa, ast.declTokens(declaration));
        }
    }
    std.mem.sortUnstable(token.TokenRange, templates.items, {}, struct {
        fn before(_: void, lhs: token.TokenRange, rhs: token.TokenRange) bool {
            return lhs.start.index() < rhs.start.index();
        }
    }.before);
    return templates;
}

fn withinTemplate(templates: []const token.TokenRange, declaration: token.TokenRange) bool {
    const at = declaration.start.index();
    var lo: usize = 0;
    var hi = templates.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        if (templates[mid].start.index() <= at) lo = mid + 1 else hi = mid;
    }
    return lo > 0 and at < templates[lo - 1].end.index();
}

fn droppedImplementation(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    text: []const u8,
) !?[]const u8 {
    var templates = try templateRanges(gpa, ast);
    defer templates.deinit(gpa);

    for (0..ast.declCount()) |i| {
        const d = node.DeclId.at(@intCast(i));
        if (ast.declTag(d) != .function) continue;
        if (ast.declTrait(d) == token.TokenId.none) continue;
        if (ast.declBody(d) == node.ExprId.none) continue;
        if (withinTemplate(templates.items, ast.declTokens(d))) continue;

        // The extent runs from the member's first token, which is `fn` or the
        // `pub` before it, to one past its last.
        const r = ast.declTokens(d);
        const from = ast.tokenSpan(r.start).start;
        const to = ast.tokenSpan(token.TokenId.at(r.end.index() - 1)).end;
        return try std.mem.concat(gpa, u8, &.{ text[0..from], text[to..] });
    }
    return null;
}

fn droppedTemplateMemberBound(gpa: std.mem.Allocator, ast: *const Ast, text: []const u8) !?[]const u8 {
    var templates = try templateRanges(gpa, ast);
    defer templates.deinit(gpa);

    for (0..ast.declCount()) |i| {
        const d = node.DeclId.at(@intCast(i));
        if (ast.declTag(d) != .function or !withinTemplate(templates.items, ast.declTokens(d))) continue;
        for (ast.declTypeParams(d)) |parameter| {
            const bounds = ast.boundsOf(parameter);
            if (bounds.len == 0 or bounds[0].kind != .named) continue;

            const from = if (bounds.len == 1)
                ast.tokenSpan(parameter.name).end
            else
                ast.tokenSpan(bounds[0].named.name).start;
            const to = if (bounds.len > 1)
                ast.tokenSpan(bounds[1].named.name).start
            else blk: {
                var depth: u32 = 0;
                var tok = token.TokenId.at(parameter.name.index() + 1);
                while (tok.index() < ast.declTokens(d).end.index()) : (tok = token.TokenId.at(tok.index() + 1)) {
                    switch (ast.tokenTag(tok)) {
                        .l_bracket => depth += 1,
                        .r_bracket => {
                            if (depth == 0) break :blk ast.tokenSpan(tok).start;
                            depth -= 1;
                        },
                        .comma => if (depth == 0) break :blk ast.tokenSpan(tok).start,
                        else => {},
                    }
                }
                return null;
            };
            return @as(?[]const u8, try std.mem.concat(gpa, u8, &.{ text[0..from], text[to..] }));
        }
    }
    return null;
}

fn replacedTemplateMemberBound(gpa: std.mem.Allocator, ast: *const Ast, text: []const u8) !?[]const u8 {
    var templates = try templateRanges(gpa, ast);
    defer templates.deinit(gpa);

    for (0..ast.declCount()) |i| {
        const d = node.DeclId.at(@intCast(i));
        if (ast.declTag(d) != .function or !withinTemplate(templates.items, ast.declTokens(d))) continue;
        for (ast.declTypeParams(d)) |parameter| {
            const bounds = ast.boundsOf(parameter);
            if (bounds.len == 0 or bounds[0].kind != .named) continue;

            var replacement = token.TokenId.none;
            for (0..ast.declCount()) |candidate_index| {
                const candidate = node.DeclId.at(@intCast(candidate_index));
                if (ast.declTag(candidate) != .trait_ or ast.declTypeParams(candidate).len != 0) continue;
                const name = ast.declName(candidate);
                var already_bounded = false;
                for (bounds) |bound| {
                    if (bound.kind == .named and ast.tokenName(bound.named.name) == ast.tokenName(name)) {
                        already_bounded = true;
                        break;
                    }
                }
                if (!already_bounded) {
                    replacement = name;
                    break;
                }
            }
            if (replacement == token.TokenId.none) continue;

            const span = ast.tokenSpan(bounds[0].named.name);
            return @as(?[]const u8, try std.mem.concat(gpa, u8, &.{
                text[0..span.start],
                ast.tokenText(replacement),
                text[span.end..],
            }));
        }
    }
    return null;
}

fn droppedComponentImplementation(gpa: std.mem.Allocator, ast: *const Ast, text: []const u8) !?[]const u8 {
    var required: std.AutoHashMapUnmanaged(u32, void) = .empty;
    defer required.deinit(gpa);
    var targets: std.AutoHashMapUnmanaged(u32, void) = .empty;
    defer targets.deinit(gpa);
    var components: std.AutoHashMapUnmanaged(u32, void) = .empty;
    defer components.deinit(gpa);

    for (0..ast.declCount()) |i| {
        const d = node.DeclId.at(@intCast(i));
        switch (ast.declTag(d)) {
            .template_impl => for (ast.templateRequirements(d)) |requirement| {
                for (ast.boundsIn(requirement.bounds)) |bound| {
                    if (bound.kind != .named or bound.named.name == token.TokenId.none) continue;
                    try required.put(gpa, @intFromEnum(ast.tokenName(bound.named.name)), {});
                }
            },
            else => {},
        }
        if (ast.deriveRequestTraitRange(d).len() != 0)
            try targets.put(gpa, @intFromEnum(ast.tokenName(ast.declName(d))), {});
    }

    for (0..ast.declCount()) |i| {
        const d = node.DeclId.at(@intCast(i));
        const name = ast.declName(d);
        if (name == token.TokenId.none or !targets.contains(@intFromEnum(ast.tokenName(name)))) continue;
        switch (ast.declTag(d)) {
            .struct_ => for (ast.declFields(d)) |field| {
                const written = field.written;
                if (written.kind != .named or written.args.len() != 0) continue;
                var open = false;
                for (ast.declTypeParams(d)) |param| {
                    if (ast.tokenName(param.name) == ast.tokenName(written.name)) open = true;
                }
                if (!open) try components.put(gpa, @intFromEnum(ast.tokenName(written.name)), {});
            },
            .newtype => {
                const base = ast.declReturnRef(d);
                if (base.kind == .named and base.args.len() == 0) {
                    try components.put(gpa, @intFromEnum(ast.tokenName(base.name)), {});
                }
            },
            else => {},
        }
    }

    for (0..ast.declCount()) |i| {
        const d = node.DeclId.at(@intCast(i));
        if (ast.declTag(d) != .impl_ or ast.declTypeParams(d).len != 0) continue;
        const trait = ast.declTrait(d);
        if (trait == token.TokenId.none or !required.contains(@intFromEnum(ast.tokenName(trait)))) continue;
        if (!components.contains(@intFromEnum(ast.tokenName(ast.declName(d))))) continue;

        const span = ast.declSpan(d);
        return @as(?[]const u8, try std.mem.concat(gpa, u8, &.{ text[0..span.start], text[span.end..] }));
    }
    return null;
}

fn openedComponentRequirementArgument(gpa: std.mem.Allocator, ast: *const Ast, text: []const u8) !?[]const u8 {
    var replacement: ?token.TokenId = null;
    for (0..ast.declCount()) |i| {
        const d = node.DeclId.at(@intCast(i));
        switch (ast.declTag(d)) {
            .struct_, .enum_ => {},
            else => continue,
        }
        if (ast.declTypeParams(d).len == 0) continue;
        replacement = ast.declName(d);
        break;
    }
    const generic = replacement orelse return null;

    for (0..ast.declCount()) |i| {
        const d = node.DeclId.at(@intCast(i));
        if (ast.declTag(d) != .template_impl) continue;
        for (ast.templateRequirements(d)) |requirement| {
            for (ast.boundsIn(requirement.bounds)) |bound| {
                if (bound.kind != .named or bound.named.args.len() == 0) continue;
                const argument = ast.typeArgs(bound.named.args)[0];
                if (argument.kind != .named) continue;
                const span = ast.tokenSpan(argument.name);
                return @as(?[]const u8, try std.mem.concat(gpa, u8, &.{
                    text[0..span.start],
                    ast.tokenText(generic),
                    text[span.end..],
                }));
            }
        }
    }
    return null;
}

fn droppedDeriveBound(gpa: std.mem.Allocator, ast: *const Ast, text: []const u8) !?[]const u8 {
    var required: std.AutoHashMapUnmanaged(u32, void) = .empty;
    defer required.deinit(gpa);
    for (0..ast.declCount()) |i| {
        const d = node.DeclId.at(@intCast(i));
        if (ast.declTag(d) != .template_impl) continue;
        for (ast.templateRequirements(d)) |requirement| {
            for (ast.boundsIn(requirement.bounds)) |bound| {
                if (bound.kind != .named or bound.named.name == token.TokenId.none) continue;
                try required.put(gpa, @intFromEnum(ast.tokenName(bound.named.name)), {});
            }
        }
    }

    // Only a standalone request states its own environment. An attached one
    // requires each field type's implementation, so a bound its type declares
    // is not what proves the requirement.
    for (0..ast.declCount()) |i| {
        const d = node.DeclId.at(@intCast(i));
        if (ast.declTag(d) != .derive_impl or ast.deriveRequestTraitRange(d).len() == 0) continue;
        for (ast.declTypeParams(d)) |param| {
            const bounds = ast.boundsOf(param);
            for (bounds, 0..) |bound, at| {
                if (bound.kind != .named or bound.named.name == token.TokenId.none) continue;
                if (!required.contains(@intFromEnum(ast.tokenName(bound.named.name)))) continue;
                if (bounds.len > 1 and at + 1 == bounds.len) continue;

                const from: u32 = if (bounds.len == 1)
                    ast.tokenSpan(param.name).end
                else
                    ast.tokenSpan(bound.named.name).start;
                const to: u32 = if (bounds.len > 1)
                    ast.tokenSpan(bounds[at + 1].named.name).start
                else blk: {
                    var depth: u32 = 0;
                    var tok = token.TokenId.at(param.name.index() + 1);
                    while (tok.index() < ast.declTokens(d).end.index()) : (tok = token.TokenId.at(tok.index() + 1)) {
                        switch (ast.tokenTag(tok)) {
                            .l_bracket => depth += 1,
                            .r_bracket => {
                                if (depth == 0) break :blk ast.tokenSpan(tok).start;
                                depth -= 1;
                            },
                            .comma => if (depth == 0) break :blk ast.tokenSpan(tok).start,
                            else => {},
                        }
                    }
                    return null;
                };
                return @as(?[]const u8, try std.mem.concat(gpa, u8, &.{ text[0..from], text[to..] }));
            }
        }
    }
    return null;
}

/// Rewrites the entry point's return type to one an exit status is not.
///
/// The one mutation that needs nothing from the program it is given. Every
/// other here breaks a rule about a name the program wrote, so it has to find
/// one and can be defeated by a program that has none; this one is ill-formed
/// for the same reason in every program, because the entry point's signature is
/// fixed by the language rather than chosen by the author.
///
/// It exists because a rule name is not the unit of enforcement, and nothing
/// else in the suite can see that. `[S-Entry]` states four separable things --
/// that exactly one `main` is declared, what its signature is, that an `impl`
/// holds only functions, and that no modifier precedes one -- and for four
/// milestones the second was enforced by nothing while the corpus provoked the
/// first. Rule coverage read complete throughout, because it counts names the
/// compiler emits and the name was emitted. A clause that nothing enforces has
/// nothing to reach, so only a program built to break that clause can find it.
///
/// `Int64` rather than a structure: it needs no declaration, so the mutated
/// program differs from the one it came from in exactly the width of one token.
fn wrongEntryType(gpa: std.mem.Allocator, ast: *const Ast, text: []const u8) !?[]const u8 {
    for (0..ast.declCount()) |i| {
        const d = node.DeclId.at(@intCast(i));
        if (ast.declTag(d) != .function) continue;
        // A member of an `impl` is not the entry point however it is spelled.
        if (ast.memberOwner(d) != TokenId.none) continue;
        if (ast.tokenTag(ast.declName(d)) != .identifier) continue;
        if (!std.mem.eql(u8, ast.tokenText(ast.declName(d)), "main")) continue;

        const tok = ast.declReturnToken(d);
        if (tok == TokenId.none) continue;
        // A `main` already returning something else is a program this mutation
        // cannot make worse, and rewriting it would assert that the compiler
        // rejects what it was already rejecting.
        if (!std.mem.eql(u8, ast.tokenText(tok), "UInt8")) return null;

        const at = ast.tokenSpan(tok);
        return try std.mem.concat(gpa, u8, &.{ text[0..at.start], "Int64", text[at.end..] });
    }
    return null;
}

/// Whether anything in the program reads a binding.
///
/// A binding nothing resolved to answers `true`, which is the safe direction:
/// the question is whether deleting it is invisible, and an unknown answer is
/// not a yes.
fn isRead(ast: *const Ast, res: *const Resolution, b: BindingId) bool {
    if (b == BindingId.none) return true;
    for (0..ast.exprCount()) |i| {
        if (res.targetOf(ExprId.at(@intCast(i))) == b) return true;
    }
    return false;
}

/// Whether this argument hands a Linear value to a parameter that takes it.
///
/// Asked of what the argument settled to, rather than of the modifier on the
/// declaration its type names or of the universe its parameter assumes. All
/// three readings differ, and only the argument's is the value's own: a
/// `sink b: Box[Key]` is Linear with nothing on `Box` saying so, while a
/// `sink x: T` in a generic callee assumes Linear and is handed a `UInt8` here.
/// The obligation belongs to the value given away, so that is what is read --
/// a mutation built on either other reading produces a program the compiler
/// is right about, and the failure blames it for the harness's mistake.
fn givesAwaySomethingLinear(types_of: *const Typing, p: node.Param, a: ExprId) bool {
    // A parameter the call omitted. What fills it is a constant from the
    // declaration rather than an expression written here, so nothing is given
    // away in this position and no mutation of the statement is about it.
    if (a == ExprId.none) return false;
    if (p.convention != .sink) return false;
    return types_of.mustConsume(types_of.exprType(a));
}

/// Whether a call gives anything away at all.
fn givesAnythingLinear(
    types_of: *const Typing,
    params: []const node.Param,
    args: []const ExprId,
) bool {
    for (params, args) |p, a| {
        if (givesAwaySomethingLinear(types_of, p, a)) return true;
    }
    return false;
}

/// A call's arguments in the order its callee declares its parameters.
///
/// The checker's answer, read rather than worked out again, through the routine
/// every pass below reads it through. An argument may name the parameter it
/// fills, so the written order and the declared order are two orders, and
/// pairing each parameter with the argument written beside it reads a
/// convention off the wrong declaration -- which for these mutations means
/// asking whether the wrong value is the linear one. A postfix call is the same
/// question one position over: its receiver is a parameter the source never
/// spells, so a list read off the tree is short by one and lines up with
/// nothing.
///
/// Null where the two lists cannot be paired at all. A call whose count differs
/// from its declaration is a program the compiler already rejects, and a
/// mutation of one says nothing about the rule it claims.
fn argumentsInOrder(
    types_of: *const Typing,
    calls: *const CallIndex,
    call: ExprId,
    params: []const node.Param,
) ?[]const ExprId {
    const args = (calls.callOf(types_of, call) orelse return null).args;
    if (args.len != params.len) return null;
    return args;
}

/// Whether the value a statement produces carries an obligation.
///
/// The expression's own type, for the reason an argument's is read: a callee
/// returning `Box[Key]` answers with something Linear while its declaration
/// says nothing, and one returning a type parameter answers with whatever
/// this call settled it to.
fn answersSomethingLinear(
    ast: *const Ast,
    types_of: *const Typing,
    disposal: Disposal,
) bool {
    const answered = ast.stmtData(disposal.stmt).init;
    return answered != .none and types_of.mustConsume(types_of.exprType(answered));
}

/// Whether the compiler rejects a program, and what it said.
pub const Verdict = struct {
    rejected: bool,
    /// The rule names of the diagnostics that rejected it, space-separated.
    ///
    /// Errors alone. A note is a hazard described beside a rejection rather
    /// than a reason for one -- `[S-Continuation]` rides along with whatever
    /// was reported at a line break -- so counting it would make a mutation
    /// answer for a rule it did not break.
    text: []const u8,
};

pub fn verdictOf(gpa: std.mem.Allocator, text: []const u8, kind: ProgramKind) !Verdict {
    const sink = (try diagnose(gpa, text, kind)).sink;
    var codes: std.ArrayList(u8) = .empty;
    for (sink.list.items) |d| {
        if (d.severity != .err) continue;
        const code = d.code orelse continue;
        const name = code.ruleName();
        // One rule reported at several places is one rule broken. The set is
        // what the mutation answers for, so a citation already in it says
        // nothing further.
        if (cites(codes.items, name)) continue;
        try codes.appendSlice(gpa, name);
        try codes.append(gpa, ' ');
    }
    return .{ .rejected = sink.hasErrors(), .text = try codes.toOwnedSlice(gpa) };
}

/// What the compiler reports about one file of text, checked the way a case
/// of that kind is, through ownership. The one compilation every property
/// that edits a program and asks again shares, so a mutation and a help's
/// edit are judged by the same passes. The sink is allocated from `gpa`,
/// and `file` is the file the text was loaded as.
pub const Diagnosed = struct { sink: Sink, file: FileId };

pub fn diagnose(gpa: std.mem.Allocator, text: []const u8, kind: ProgramKind) !Diagnosed {
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;

    // Loaded rather than parsed, so a mutated program is compiled the way the
    // program it came from was. Without the library a name the prelude offers
    // resolves to nothing, and the mutation is reported as an undetermined
    // type rather than as the unknown variant it is.
    var table: FileTable = .empty;
    const one = [_]loader.InMemoryFile{.{ .path = "mutated.lin", .text = text }};
    var program = try loader.loadFromMemory(gpa, &table, &sink, &interner, "mutated.lin", &one, .program, true, .borrow);
    // Mutations preserve the root kind even though their one-file input
    // carries no manifest.
    program.kind = kind;
    const resolved = try resolve(gpa, &program, &interner, &sink, .program);
    var expanded = resolved.expanded;
    defer expanded.deinit(gpa);
    var res = resolved.resolution;
    defer res.deinit(gpa);
    var typing = try typecheck(gpa, &expanded, &res, &sink);
    defer typing.deinit(gpa);
    {
        var c = try checkOwnership(gpa, gpa, &expanded, &res, &typing, &sink);
        c.deinit(gpa);
    }
    return .{ .sink = sink, .file = program.primaryFile() };
}

/// Whether a space-separated list of rule names holds one.
///
/// Public because a verdict is read by more than the mutations: a property
/// that breaks a program of its own asks the same question of the same list,
/// and a second reading of it would differ on a name that is another's prefix.
pub fn cites(text: []const u8, name: []const u8) bool {
    var it = std.mem.tokenizeScalar(u8, text, ' ');
    while (it.next()) |cited| {
        if (std.mem.eql(u8, cited, name)) return true;
    }
    return false;
}

/// Whether a rejection is the one the mutation claims.
///
/// Two halves, and both are needed. The rule the mutation names has to be
/// cited, or the mutation is evidence about some rule it did not set out to
/// break. And every other rule cited has to be one the mutation declared it
/// cascades into, or the mutated program is wrong twice over and says nothing
/// about either rule -- which is exactly what asking only whether the rule
/// appears somewhere in the list cannot see.
pub fn asClaimed(v: Verdict, m: Mutation) bool {
    if (!v.rejected) return false;
    if (!cites(v.text, m.rule())) return false;

    var it = std.mem.tokenizeScalar(u8, v.text, ' ');
    while (it.next()) |name| {
        if (std.mem.eql(u8, name, m.rule())) continue;
        var declared = false;
        for (m.cascade()) |allowed| {
            if (std.mem.eql(u8, name, allowed)) declared = true;
        }
        if (!declared) return false;
    }
    return true;
}

/// What a mutation answers for, for a failure to read as a sentence.
pub fn expectation(gpa: std.mem.Allocator, m: Mutation) ![]const u8 {
    if (m.cascade().len == 0) return m.rule();

    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(gpa, m.rule());
    try out.appendSlice(gpa, ", and at most");
    for (m.cascade()) |name| {
        try out.append(gpa, ' ');
        try out.appendSlice(gpa, name);
    }
    return out.toOwnedSlice(gpa);
}

/// The mutation of a program, once the compiler has been seen to accept it.
///
/// A mutation is a change to a program that compiles. Applied to one already
/// rejected it asserts that the compiler still rejects what it was already
/// rejecting, and the rule cited is whatever the original was wrong about --
/// which reads as coverage and is none.
fn mutated(gpa: std.mem.Allocator, m: Mutation, text: []const u8) !?[]const u8 {
    try testing.expect(!(try verdictOf(gpa, text, .program)).rejected);

    const source: Source = .{ .path = "t.lin", .text = text };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    var res = try resolveTree(gpa, &ast, &sink);
    const types_of = try typecheckTree(gpa, &res, &sink);
    return m.apply(gpa, &ast, &res.resolution, &types_of, text);
}

test "a qualified variant renamed to nothing is rejected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const out = (try mutated(gpa, .unknown_variant,
        \\enum Colour { Red, Green }
        \\fn main() -> UInt8 { match Colour.Red { Red => 1, Green => 2 } }
    )).?;

    try testing.expect(asClaimed(try verdictOf(gpa, out, .program), .unknown_variant));
}

test "a variant from context renamed to nothing is rejected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // The form this mutation exists for. Taken on trust, `.Red` lowers to a
    // tag the enum does not have and the `match` it feeds answers with
    // whatever the slot held — a wrong answer no meaning-preserving rewrite
    // can reach, because both programs are wrong in the same way.
    //
    // The parameter is lent and the `match` reads rather than takes. A
    // mutation is a change to a program the compiler accepts, so one applied to
    // a program that was already rejected proves nothing about the change.
    const out = (try mutated(gpa, .unknown_variant,
        \\enum Colour { Red, Green }
        \\fn shade(c: Colour) -> UInt8 { match read c { Red => 1, Green => 2 } }
        \\fn main() -> UInt8 { shade(.Red) }
    )).?;

    try testing.expect(std.mem.indexOf(u8, out, "._Zz") != null);

    try testing.expect(asClaimed(try verdictOf(gpa, out, .program), .unknown_variant));
}

test "a refinement narrowed past its own top admits nothing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // The construction proves the clause with the value at the top of the
    // range, so the bound moves past it and the ends cross: `100..=99` admits
    // no value at all, which is the refusal the declaration meets rather than
    // the one the construction does. Written here because nothing in the
    // corpus constructs at the top of a range, so the branch is reached by no
    // program the walk sees.
    const out = (try mutated(gpa, .narrowed_refinement,
        \\type Percent = UInt8 where it in 0..=99
        \\fn main() -> UInt8 {
        \\    let Percent(n) = Percent(99)
        \\    n
        \\}
    )).?;

    try testing.expect(std.mem.indexOf(u8, out, "100..=99") != null);

    try testing.expect(asClaimed(try verdictOf(gpa, out, .program), .narrowed_refinement));
}

test "a newtype construction a destructure takes apart is summed with itself" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const out = (try mutated(gpa, .summed_newtype,
        \\@copyable type Percent = UInt8 where it in 0..=99
        \\fn main() -> UInt8 {
        \\    let Percent(n) = Percent(50)
        \\    n
        \\}
    )).?;

    try testing.expect(std.mem.indexOf(u8, out, "let _zzsum = Percent(50);") != null);
    try testing.expect(std.mem.indexOf(u8, out, "let Percent(n) = _zzsum + _zzsum") != null);

    try testing.expect(asClaimed(try verdictOf(gpa, out, .program), .summed_newtype));
}

test "a newtype over an enum is summed exactly as one over an integer is" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Arithmetic is refused because the value is a newtype, whatever its base
    // is -- so the mutation needs nothing from the base to land here.
    const out = (try mutated(gpa, .summed_newtype,
        \\@copyable enum Colour { Red, Green }
        \\@copyable type Hue = Colour
        \\fn main() -> UInt8 {
        \\    let Hue(c) = Hue(Colour.Red)
        \\    match c { Red => 1, Green => 2 }
        \\}
    )).?;

    try testing.expect(std.mem.indexOf(u8, out, "let _zzsum = Hue(Colour.Red);") != null);
    try testing.expect(std.mem.indexOf(u8, out, "let Hue(c) = _zzsum + _zzsum") != null);

    try testing.expect(asClaimed(try verdictOf(gpa, out, .program), .summed_newtype));
}

test "a newtype read before a destructure takes it apart is summed with itself" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // The shape a generated program actually writes: one binding constructs
    // the newtype and a later one destructures a read of it, so the value
    // being taken apart is a name rather than the construction itself.
    const out = (try mutated(gpa, .summed_newtype,
        \\@copyable type Percent = UInt8 where it in 0..=99
        \\fn main() -> UInt8 {
        \\    let p: Percent = Percent(50)
        \\    let Percent(n) = p
        \\    n
        \\}
    )).?;

    try testing.expect(std.mem.indexOf(u8, out, "let _zzsum = p;") != null);
    try testing.expect(std.mem.indexOf(u8, out, "let Percent(n) = _zzsum + _zzsum") != null);

    try testing.expect(asClaimed(try verdictOf(gpa, out, .program), .summed_newtype));
}

test "a destructure sharing a line with a trailing comment is still summed correctly" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Two statements share a line, so `lineGap` answers with a single space
    // rather than a newline, and the initialiser is trailed by a comment with
    // nothing else on its line -- the one combination where a splice cut at
    // `exprSpan` rather than `exprExtent` lands the second half of the
    // rewrite on the same line as the comment, which then comments it out.
    const out = (try mutated(gpa, .summed_newtype,
        \\@copyable type Percent = UInt8 where it in 0..=99
        \\fn viaLet(sink p: Percent) -> UInt8 {
        \\    let q: UInt8 = 1; let Percent(n) = p // read straight back
        \\    n + q
        \\}
        \\fn main() -> UInt8 {
        \\    viaLet(Percent(29))
        \\}
    )).?;

    try testing.expect(std.mem.indexOf(u8, out, "let Percent(n) = _zzsum + _zzsum") != null);
    try testing.expect(asClaimed(try verdictOf(gpa, out, .program), .summed_newtype));
}

test "a linear newtype is left alone, since a second read would move it twice" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    try testing.expect(try mutated(gpa, .summed_newtype,
        \\@linear type Ticket = UInt8
        \\fn main() -> UInt8 {
        \\    let Ticket(n) = Ticket(50)
        \\    n
        \\}
    ) == null);
}

test "a program with no newtype construction to sum is left alone" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    try testing.expect(try mutated(gpa, .summed_newtype, "fn main() -> UInt8 { 0 }") == null);
}

test "a program with no variant to rename is left alone" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    try testing.expect(try mutated(gpa, .unknown_variant, "fn main() -> UInt8 { 0 }") == null);
}

test "every mutation names a rule" {
    for (std.enums.values(Mutation)) |m| {
        try testing.expect(m.rule().len > 0);
        try testing.expect(m.why().len > 0);
    }
}

test "a cascade is other rules than the one the mutation names" {
    // A rule listed twice, or a rule that is the one the mutation already
    // requires, reads as a licence rather than as a consequence -- and the
    // half of the property that demands the rule would be satisfied by the
    // half that permits the rest.
    for (std.enums.values(Mutation)) |m| {
        for (m.cascade(), 0..) |name, i| {
            try testing.expect(!std.mem.eql(u8, name, m.rule()));
            for (m.cascade()[0..i]) |earlier| {
                try testing.expect(!std.mem.eql(u8, name, earlier));
            }
        }
    }
}

test "a verdict answers for the mutation only where it cites the rule and no other" {
    // The property's two halves, on made-up verdicts, because the point is
    // what the predicate does with a list of names rather than what any
    // program provokes.
    const claimed: Verdict = .{ .rejected = true, .text = "O-Move " };
    try testing.expect(asClaimed(claimed, .repeated_disposal));

    // Some other rule caught it. The mutation is evidence about a rule it did
    // not set out to break.
    const elsewhere: Verdict = .{ .rejected = true, .text = "O-Leak " };
    try testing.expect(!asClaimed(elsewhere, .repeated_disposal));

    // Its own rule and a second one. This is what containment cannot see: the
    // rule is in the list, and the program is wrong twice over.
    const twice: Verdict = .{ .rejected = true, .text = "O-Move O-Leak " };
    try testing.expect(!asClaimed(twice, .repeated_disposal));

    // The same list where the second rule is declared. A mutation answers for
    // what it wrote down and for nothing else, so the one that declares
    // [T-Infer] admits it and the one that does not is failed by it.
    const cascaded: Verdict = .{ .rejected = true, .text = "T-UnknownField T-Infer " };
    try testing.expect(asClaimed(cascaded, .unknown_field));
    try testing.expect(!asClaimed(.{ .rejected = true, .text = "O-Move T-Infer " }, .repeated_disposal));

    // Accepted. Nothing in a list of no names is the rule.
    try testing.expect(!asClaimed(.{ .rejected = false, .text = "" }, .repeated_disposal));
}

test "a disposal written as a let is deleted, and the value is then leaked" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // The shape every disposal has: a function that takes a linear value and
    // answers something can only be called from a `let`, because an
    // `expr_stmt` may hold nothing but a Unit value.
    const out = (try mutated(gpa, .dropped_disposal,
        \\@linear enum L0 { _W0(UInt8), _W1 }
        \\
        \\fn _dispose(sink held: L0) -> UInt8 {
        \\    match held { _W0(carried) => carried, _W1 => 1 }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let _l0: L0 = L0._W0(3);
        \\    let _n0: UInt8 = _dispose(_l0);
        \\    0
        \\}
    )).?;

    try testing.expect(std.mem.indexOf(u8, out, "_dispose(_l0)") == null);

    try testing.expect(asClaimed(try verdictOf(gpa, out, .program), .dropped_disposal));
}

test "a disposal that names its parameters is found by the parameter order" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // The linear value is written second and declared first, so which argument
    // gives it away is a question about the declaration and not about the
    // order the call spells. Read the other way round, the `sink` parameter is
    // paired with the `UInt8` beside it, nothing here gives anything linear
    // away, and this program has no disposal to mutate at all.
    const out = (try mutated(gpa, .dropped_disposal,
        \\@linear enum L0 { _W0(UInt8), _W1 }
        \\
        \\fn _dispose(sink held: L0, note: UInt8) -> UInt8 {
        \\    match held { _W0(carried) => carried + note, _W1 => note }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let _l0: L0 = L0._W0(3);
        \\    let _n0: UInt8 = _dispose(note: 1, held: _l0);
        \\    0
        \\}
    )).?;

    try testing.expect(std.mem.indexOf(u8, out, "_dispose(note: 1, held: _l0)") == null);

    try testing.expect(asClaimed(try verdictOf(gpa, out, .program), .dropped_disposal));
}

test "a postfix call is paired with the receiver its callee declares" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // A receiver is a parameter the source never spells, so the arguments a
    // postfix call writes are one short of what its callee declares. Taken off
    // the tree they line up with nothing -- and what a parameter is paired with
    // is what decides whether this call gives a linear value away.
    const text =
        \\struct P {
        \\    n: UInt8,
        \\}
        \\
        \\impl P {
        \\    fn span(self: Self, low: UInt8) -> UInt8 {
        \\        self.n + low
        \\    }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let p: P = .{ n = 1 }
        \\    p.span(2)
        \\}
    ;

    const source: Source = .{ .path = "t.lin", .text = text };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    var res = try resolveTree(gpa, &ast, &sink);
    const types_of = try typecheckTree(gpa, &res, &sink);
    try testing.expect(!sink.hasErrors());

    const calls = &types_of.call_index;

    const written = types_of.postfix[0];
    const args = argumentsInOrder(
        &types_of,
        calls,
        ExprId.at(written.call),
        ast.declParams(switch (calls.callOf(&types_of, ExprId.at(written.call)).?.target) {
            .declared => |decl| decl,
            .closure_recovery, .array_view, .array_length, .closure, .indirect, .generic_callable, .erased => unreachable,
        }),
    ).?;

    try testing.expectEqual(@as(usize, 2), args.len);
    try testing.expectEqualStrings("p", ast.exprText(args[0]));
    try testing.expectEqualStrings("2", ast.exprText(args[1]));
}

test "a disposal whose result something reads is left alone" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Deleting the statement deletes the binding, so a program that reads it
    // would be rejected for a name it cannot find -- which says nothing about
    // whether the value was disposed of, and would cite the wrong rule.
    try testing.expect(try mutated(gpa, .dropped_disposal,
        \\@linear enum L0 { _W0(UInt8), _W1 }
        \\
        \\fn _dispose(sink held: L0) -> UInt8 {
        \\    match held { _W0(carried) => carried, _W1 => 1 }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let _l0: L0 = L0._W0(3);
        \\    let n0: UInt8 = _dispose(_l0);
        \\    n0
        \\}
    ) == null);
}

test "a field renamed to nothing is rejected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const out = (try mutated(gpa, .unknown_field,
        \\struct Point { x: UInt8, y: UInt8 }
        \\fn main() -> UInt8 { let p: Point = .{ x = 1, y = 2 }; p.x + p.y }
    )).?;

    try testing.expect(asClaimed(try verdictOf(gpa, out, .program), .unknown_field));
}

test "the field mutation preserves a method's only reference" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try testing.expect(try mutated(arena.allocator(), .unknown_field,
        \\struct Box { value: UInt8 }
        \\impl Box {
        \\    fn take(sink self: Self) -> UInt8 {
        \\        let Box { value } = self
        \\        value
        \\    }
        \\}
        \\fn main() -> UInt8 { let box: Box = .{ value = 7 }; box.take() }
    ) == null);
}

test "a parameter stripped of phantom changes no ownership obligations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const source =
        \\@linear struct Key {}
        \\@copyable struct Handle[phantom T] { x: UInt8 }
        \\fn main() -> UInt8 { let h: Handle[Key] = .{ x = 1 }; h.x + h.x }
    ;
    try testing.expect(!(try verdictOf(gpa, source, .program)).rejected);
    const out = (try mutated(gpa, .dropped_phantom, source)).?;
    const verdict = try verdictOf(gpa, out, .program);
    try testing.expect(asClaimed(verdict, .dropped_phantom));
    try testing.expectEqualStrings("N-Unused", std.mem.trim(u8, verdict.text, " "));

    // Ownership failures would indicate that unused identity arguments were
    // counted as owned fields. The mutation must not accept those failures.
    for ([_][]const u8{ "N-Unused O-Leak", "N-Unused O-Universe" }) |diagnostics| {
        try testing.expect(!asClaimed(.{ .rejected = true, .text = diagnostics }, .dropped_phantom));
    }
}

test "a covering match narrowed by one uncovers its top value" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const out = (try mutated(gpa, .narrowed_range,
        \\fn classify(b: UInt8) -> UInt8 {
        \\    match read b { 0..=127 => 1, 128..=255 => 2 }
        \\}
        \\fn main() -> UInt8 {
        \\    classify(200)
        \\}
    )).?;

    try testing.expect(std.mem.indexOf(u8, out, "0..127") != null);
    try testing.expect(asClaimed(try verdictOf(gpa, out, .program), .narrowed_range));
}

test "an arm holding one value is not the arm narrowed" {
    // `0..=0` respelled to `0..0` is an empty arm, and an empty arm is
    // [T-Unreachable] before the match is uncovering -- a different rule
    // than the one this mutation claims. The narrowing lands on the next
    // arm, whose flag still covers exactly one value on its own.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const out = (try mutated(gpa, .narrowed_range,
        \\fn classify(b: UInt8) -> UInt8 {
        \\    match read b { 0..=0 => 1, 1..=255 => 2 }
        \\}
        \\fn main() -> UInt8 {
        \\    classify(200)
        \\}
    )).?;

    try testing.expect(std.mem.indexOf(u8, out, "0..=0") != null);
    try testing.expect(std.mem.indexOf(u8, out, "1..255") != null);
    try testing.expect(asClaimed(try verdictOf(gpa, out, .program), .narrowed_range));
}

test "a wildcard beside a range arm is left alone" {
    // A `_` still answers for the value the flag stopped covering, so
    // narrowing here would produce a program the compiler is right to
    // accept -- and a mutation with nothing to change returns null rather
    // than assert that.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    try testing.expect((try mutated(gpa, .narrowed_range,
        \\fn main() -> UInt8 {
        \\    match 3 { 0..=127 => 1, _ => 2 }
        \\}
    )) == null);
}

test "a refinement narrowed past a proven construction is refused" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const out = (try mutated(gpa, .narrowed_refinement,
        \\type Percent = UInt8 where it in 0..=99
        \\fn wants(_p: Percent) -> UInt8 {
        \\    0
        \\}
        \\fn main() -> UInt8 {
        \\    wants(Percent(50))
        \\}
    )).?;

    try testing.expect(std.mem.indexOf(u8, out, "51..=99") != null);
    try testing.expect(asClaimed(try verdictOf(gpa, out, .program), .narrowed_refinement));
}

test "an unrefined newtype has no clause to narrow" {
    // Nothing about the declaration bounds a value, so there is no lower
    // bound to move past a construction and no [T-Refine] any edit could
    // provoke -- the mutation has nothing to change here.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    try testing.expect((try mutated(gpa, .narrowed_refinement,
        \\type Meters = UInt64
        \\fn wants(_m: Meters) -> UInt8 {
        \\    0
        \\}
        \\fn main() -> UInt8 {
        \\    wants(Meters(5))
        \\}
    )) == null);
}

test "a newtype reached only through the fallible form is not narrowed" {
    // `Percent?(50)` asks nothing of the operand's value, so there is no
    // proof here for the moved bound to fall past -- the construction the
    // mutation needs is the total form, and this program writes only the
    // one that declines.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    try testing.expect((try mutated(gpa, .narrowed_refinement,
        \\type Percent = UInt8 where it in 0..=99
        \\fn main() -> UInt8 {
        \\    let _o = Percent?(50)
        \\    0
        \\}
    )) == null);
}

test "a name on a value of a library's type is not renamed" {
    // The tree a mutation holds is the case file alone, so a receiver whose
    // type only the library settles has no fields this tree can see -- and a
    // library type may seal its representation, in which case the refusal is
    // the boundary's rule rather than the one this mutation answers for.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    try testing.expect((try mutated(gpa, .unknown_field,
        \\fn main() -> UInt8 {
        \\    let text: Str = "hi"
        \\    UInt8(text.length())
        \\}
    )) == null);
}

/// Whether the parser read a program without leaving an error node in it.
///
/// A mutation names one rule, and the runner reads the rule out of the
/// diagnostic -- so source that does not parse is a mutation rejected for a
/// rule other than the one it claimed, and the claim would still be counted.
fn parses(gpa: std.mem.Allocator, text: []const u8) !bool {
    const source: Source = .{ .path = "m.lin", .text = text };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);

    if (sink.hasErrors()) return false;
    for (0..ast.declCount()) |i| {
        if (ast.declTag(node.DeclId.at(@intCast(i))) == .err) return false;
    }
    for (0..ast.exprCount()) |i| {
        if (ast.exprTag(node.ExprId.at(@intCast(i))) == .err) return false;
    }
    return true;
}

test "an implementation with an operation deleted parses, and breaks the rule it names" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // The member is cut from its own first token to its own last, so what
    // surrounds it is untouched: the deletion has to leave an `impl` the
    // parser still reads, or the mutation is rejected for a syntax error and
    // counted as though the rule it names had been checked.
    //
    // Both shapes the cut can land in. Where the member is the only one, an
    // empty `impl` is left behind; where it is the first of two, the brace it
    // shares with the next has to survive.
    const one =
        \\struct Coins { count: UInt8 }
        \\trait Measure {
        \\    fn of(x: Self) -> UInt8
        \\}
        \\impl Measure for Coins {
        \\    fn of(x: Self) -> UInt8 { x.count }
        \\}
        \\fn main() -> UInt8 { let c: Coins = .{ count = 3 }; Measure.of(c) }
        \\
    ;
    const two =
        \\struct Coins { count: UInt8 }
        \\trait Measure {
        \\    fn of(x: Self) -> UInt8
        \\    fn twice(x: Self) -> UInt8
        \\}
        \\impl Measure for Coins {
        \\    fn of(x: Self) -> UInt8 { x.count }
        \\    fn twice(x: Self) -> UInt8 { x.count }
        \\}
        \\fn main() -> UInt8 { let c: Coins = .{ count = 3 }; Measure.twice(c) }
        \\
    ;

    for ([_][]const u8{ one, two }) |text| {
        try testing.expect(try parses(gpa, text));

        const out = (try mutated(gpa, .dropped_implementation, text)).?;
        try testing.expect(try parses(gpa, out));

        try testing.expect(asClaimed(try verdictOf(gpa, out, .program), .dropped_implementation));
    }
}

test "dropping an implementation can remove an imported module's only use" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const text =
        \\import std.io
        \\struct Mark {}
        \\trait Render { fn show(self: Self) }
        \\impl Render for Mark {
        \\    fn show(_self: Self) { io.eprint("") }
        \\}
        \\fn main() -> UInt8 { let mark: Mark = .{}; Render.show(mark); 0 }
    ;
    try testing.expect(!(try verdictOf(gpa, text, .program)).rejected);
    const changed = (try mutated(gpa, .dropped_implementation, text)).?;
    const verdict = try verdictOf(gpa, changed, .program);
    try testing.expect(cites(verdict.text, "M-Unused"));
    try testing.expect(asClaimed(verdict, .dropped_implementation));
}

test "an implementation with nothing of a trait in it is left alone" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // An inherent `impl` names no trait, so deleting a member of one leaves a
    // program that still compiles -- and a mutation whose result compiles is
    // reported as the compiler having missed something.
    try testing.expect(try mutated(gpa, .dropped_implementation,
        \\struct Coins { count: UInt8 }
        \\impl Coins {
        \\    fn of(x: Self) -> UInt8 { x.count }
        \\}
        \\fn main() -> UInt8 { let c: Coins = .{ count = 3 }; Coins.of(c) }
    ) == null);
}

test "a structural template is not an implementation to drop a member from" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try testing.expectEqual(@as(?[]const u8, null), try mutated(arena.allocator(), .dropped_implementation,
        \\trait Structural { fn value(self: Self) -> UInt8 }
        \\template impl Structural {
        \\    fn value(_self: Self) -> UInt8 { 7 }
        \\}
        \\struct Mark {}
        \\derive Structural for Mark
        \\fn main() -> UInt8 { 0 }
    ));
}

const template_member_bounds =
    \\trait First {}
    \\trait Second {}
    \\trait Structural {
    \\    fn value[T: First](self: Self, item: T) -> UInt8
    \\}
    \\template impl Structural {
    \\    fn value[X: First](_self: Self, _item: X) -> UInt8 { 7 }
    \\}
    \\impl First for UInt8 {}
    \\impl Second for UInt8 {}
    \\struct Item {}
    \\derive Structural for Item
    \\fn main() -> UInt8 {
    \\    let item: Item = .{}
    \\    Structural.value(item, UInt8(0))
    \\}
;

test "removing one template member bound is a template error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const out = (try mutated(gpa, .dropped_template_member_bound, template_member_bounds)).?;
    try testing.expect(std.mem.indexOf(u8, out, "fn value[X]") != null);
    try testing.expect(asClaimed(try verdictOf(gpa, out, .program), .dropped_template_member_bound));
}

test "replacing one template member bound is a template error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const out = (try mutated(gpa, .replaced_template_member_bound, template_member_bounds)).?;
    try testing.expect(std.mem.indexOf(u8, out, "fn value[X: Second]") != null);
    try testing.expect(asClaimed(try verdictOf(gpa, out, .program), .replaced_template_member_bound));
}

test "removing one concrete component implementation is a derive error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const out = (try mutated(gpa, .dropped_component_implementation,
        \\trait Required {}
        \\trait Ready {}
        \\template impl Ready where reflect.components: Required {}
        \\struct Box { value: UInt8 }
        \\impl Required for UInt8 {}
        \\derive Ready for Box
        \\fn main() -> UInt8 { let _box: Box = .{ value = 0 }; 0 }
    )).?;
    try testing.expect(std.mem.indexOf(u8, out, "impl Required for UInt8") == null);
    try testing.expect(asClaimed(try verdictOf(gpa, out, .program), .dropped_component_implementation));
}

test "opening one closed component requirement argument is a template error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const out = (try mutated(gpa, .opened_component_requirement_argument,
        \\trait Required[phantom I] {}
        \\trait Ready {}
        \\struct _Generic[T] { value: T }
        \\template impl Ready where reflect.components: Required[UInt8] {}
        \\struct Box { value: UInt8 }
        \\impl Required[UInt8] for UInt8 {}
        \\derive Ready for Box
        \\fn main() -> UInt8 { let _box: Box = .{ value = 0 }; 0 }
    )).?;
    try testing.expect(std.mem.indexOf(u8, out, "Required[_Generic]") != null);
    try testing.expect(asClaimed(try verdictOf(gpa, out, .program), .opened_component_requirement_argument));
}

test "removing one generic derive bound is a derive error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const out = (try mutated(gpa, .dropped_derive_bound,
        \\trait Required {}
        \\trait Ready {}
        \\template impl Ready where reflect.components: Required {}
        \\struct Box[T] { value: T }
        \\impl Required for UInt8 {}
        \\derive[T: Required] Ready for Box[T]
        \\fn main() -> UInt8 { let _box: Box[UInt8] = .{ value = 0 }; 0 }
    )).?;
    try testing.expect(std.mem.indexOf(u8, out, "T: Required") == null);
    try testing.expect(asClaimed(try verdictOf(gpa, out, .program), .dropped_derive_bound));
}

test "removing one attached derive component implementation is a derive error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const result = try mutated(gpa, .dropped_component_implementation,
        \\trait Required {}
        \\trait Ready {}
        \\template impl Ready where reflect.components: Required {}
        \\@derive(Ready)
        \\struct Box { value: UInt8 }
        \\impl Required for UInt8 {}
        \\fn main() -> UInt8 { let _box: Box = .{ value = 0 }; 0 }
    );
    try testing.expect(result != null);
    const out = result.?;
    try testing.expect(std.mem.indexOf(u8, out, "impl Required for UInt8") == null);
    try testing.expect(asClaimed(try verdictOf(gpa, out, .program), .dropped_component_implementation));
}

test "an attached derive's declared bound is not a derive bound to remove" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const result = try mutated(gpa, .dropped_derive_bound,
        \\trait Required {}
        \\trait Ready {}
        \\template impl Ready where reflect.components: Required {}
        \\@derive(Ready)
        \\struct Box[T: Required] { value: T }
        \\impl Required for UInt8 {}
        \\fn main() -> UInt8 { let _box: Box[UInt8] = .{ value = 0 }; 0 }
    );
    try testing.expect(result == null);
}

test "a variant is not renamed by the field mutation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // The two are one node, told apart by what the left side names. A mutation
    // that could not tell them apart would cite the wrong rule and fail for a
    // reason that has nothing to do with what it was checking.
    try testing.expect(try mutated(gpa, .unknown_field,
        \\enum Colour { Red, Green }
        \\fn main() -> UInt8 { match Colour.Red { Red => 1, Green => 2 } }
    ) == null);
}

/// A program that mints a linear value, lends it, and gives it away.
///
/// The shape the generator writes and the shape the mutations below are built
/// against: the value is named, so there is one obligation to break, and the
/// statement that discharges it binds a name nothing reads.
const disposes =
    \\@linear enum L0 { _W0(UInt8), _W1 }
    \\
    \\fn _dispose(sink held: L0) -> UInt8 {
    \\    match held { _W0(carried) => carried, _W1 => 1 }
    \\}
    \\
    \\fn main() -> UInt8 {
    \\    let _l0: L0 = L0._W0(3);
    \\    let _n0: UInt8 = _dispose(_l0);
    \\    0
    \\}
;

test "a disposal repeated takes the value twice" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const out = (try mutated(gpa, .repeated_disposal, disposes)).?;

    // The repeat binds a name of its own: repeated verbatim it would declare
    // `_n0` twice, and a duplicate name is a different rule.
    try testing.expect(std.mem.indexOf(u8, out, "let _zzr: UInt8 = _dispose(_l0);") != null);
    try testing.expect(std.mem.indexOf(u8, out, "let _n0: UInt8 = _dispose(_l0);") != null);

    try testing.expect(asClaimed(try verdictOf(gpa, out, .program), .repeated_disposal));
}

test "a disposal answering nothing is repeated as it stands" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // The other statement form. A function answering `()` is called as a
    // statement of its own, and there is no binding to give a name to -- which
    // is the corpus's shape and not the generator's.
    const out = (try mutated(gpa, .repeated_disposal,
        \\@linear enum Key { Forged(UInt8) }
        \\
        \\fn release(sink k: Key) {
        \\    match k { Forged(_) => {} }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let a = Key.Forged(1)
        \\    release(a)
        \\    2
        \\}
    )).?;

    try testing.expect(std.mem.indexOf(u8, out, "release(a)\n    release(a)") != null);

    try testing.expect(asClaimed(try verdictOf(gpa, out, .program), .repeated_disposal));
}

test "a disposal of a value built in the call is left alone" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Two calls each building their own value give each away once, which is a
    // program that is right. The mutations here need one value with one
    // obligation, and that is what naming the argument guarantees.
    try testing.expect(try mutated(gpa, .repeated_disposal,
        \\@linear enum L0 { _W0(UInt8), _W1 }
        \\
        \\fn _dispose(sink held: L0) -> UInt8 {
        \\    match held { _W0(carried) => carried, _W1 => 1 }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let _n0: UInt8 = _dispose(L0._W0(3));
        \\    0
        \\}
    ) == null);
}

test "a disposal answering with another linear value is not the one repeated" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // `recut` takes a value and answers with another, so repeating the call
    // that binds `second` would bind a third the program has nowhere to give
    // away -- [O-Leak] beside the [O-Move] the mutation claims, and neither
    // citation evidence about the other. The disposal after it answers with a
    // number and is the one taken.
    const text =
        \\@linear enum Key { Forged(UInt8) }
        \\
        \\fn recut(sink k: Key) -> Key {
        \\    match k { Forged(n) => Key.Forged(n) }
        \\}
        \\
        \\fn burn(sink k: Key) -> UInt8 {
        \\    match k { Forged(n) => n }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let first: Key = .Forged(7)
        \\    let second: Key = recut(first)
        \\    let _spent: UInt8 = burn(second)
        \\    3
        \\}
    ;

    const out = (try mutated(gpa, .repeated_disposal, text)).?;
    try testing.expect(std.mem.indexOf(u8, out, "let _zzr: UInt8 = burn(second)") != null);
    try testing.expect(std.mem.indexOf(u8, out, "recut(first)\n") != null);
    try testing.expect(std.mem.indexOf(u8, out, "_zzr: Key") == null);

    try testing.expect(asClaimed(try verdictOf(gpa, out, .program), .repeated_disposal));
}

test "a program whose only disposal answers with a linear value is left alone" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Nothing here can be repeated without inventing a leak, so the mutation
    // declines rather than citing two rules at once.
    try testing.expect(try mutated(gpa, .repeated_disposal,
        \\@linear enum Key { Forged(UInt8) }
        \\
        \\fn recut(sink k: Key) -> Key {
        \\    match k { Forged(n) => Key.Forged(n) }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let first: Key = .Forged(7)
        \\    let second: Key = recut(first)
        \\    match second { Forged(n) => n }
        \\}
    ) == null);
}

test "a disposal answering with an owned carrier is not the one repeated" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    try testing.expect(try mutated(gpa, .repeated_disposal,
        \\@linear struct Pool { at: UInt64 }
        \\@linear struct Failure { at: UInt64 }
        \\@linear enum Outcome { Ready(Pool), Failed(Failure) }
        \\fn choose(sink failure: Failure) -> Outcome { .Failed(failure) }
        \\fn main() -> UInt8 {
        \\    let failure: Failure = .{ at = 0 }
        \\    let holder = choose(failure)
        \\    match holder {
        \\        Ready(pool) => { let Pool { at } = pool; UInt8(at) },
        \\        Failed(error) => { let Failure { at } = error; UInt8(at) },
        \\    }
        \\}
    ) == null);

    const ordinary = (try mutated(gpa, .repeated_disposal,
        \\@linear struct Failure { at: UInt64 }
        \\
        \\fn dispose(sink failure: Failure) -> UInt8 {
        \\    let Failure { at: n } = failure
        \\    UInt8(n)
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let failure: Failure = .{ at = 1 }
        \\    let n = dispose(failure)
        \\    n
        \\}
    )).?;
    try testing.expect(std.mem.indexOf(u8, ordinary, "let _zzr = dispose(failure)") != null);
    try testing.expect(asClaimed(try verdictOf(gpa, ordinary, .program), .repeated_disposal));
}

test "an unknown factory member leaves a later call's marks checked" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const text =
        \\struct Handle {}
        \\impl Handle {
        \\    fn open() -> Handle { .{} }
        \\    fn update(_self: Self, inout number: UInt64) { number += 1 }
        \\}
        \\fn main() -> UInt8 {
        \\    let handle = Handle.open()
        \\    var number: UInt64 = 0
        \\    handle.update(&number)
        \\    UInt8(number)
        \\}
    ;
    try testing.expect(!(try verdictOf(gpa, text, .program)).rejected);
    const changed = (try mutated(gpa, .unknown_member, text)).?;
    // A call whose receiver is poison still reads its `&` argument as a mark,
    // so the rejection cites only what the unknown member's cascade allows.
    try testing.expect(asClaimed(try verdictOf(gpa, changed, .program), .unknown_member));
}

test "a member handed a binding is not the one renamed" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // `Coins.of(coppers)` renamed leaves a call nobody declared holding a
    // binding read again beside it, and the ownership pass answers out of a
    // fallback: [O-Move], about the compiler's recovery rather than about the
    // program. `Coins.twice(2)` builds its argument in the call, so what the
    // missing declaration would have said about it cannot be seen.
    const out = (try mutated(gpa, .unknown_member,
        \\struct Coins { count: UInt8 }
        \\
        \\impl Coins {
        \\    fn of(x: Coins) -> UInt8 { x.count }
        \\    fn twice(n: UInt8) -> UInt8 { n * 2 }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let coppers: Coins = .{ count = 3 }
        \\    Coins.of(coppers) + Coins.of(coppers) + Coins.twice(2)
        \\}
    )).?;

    try testing.expect(std.mem.indexOf(u8, out, "Coins._Zz(2)") != null);
    try testing.expect(std.mem.indexOf(u8, out, "Coins._Zz(coppers)") == null);

    try testing.expect(asClaimed(try verdictOf(gpa, out, .program), .unknown_member));
}

test "a program whose every member call is handed a binding is left alone" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // The borrow needs no rule of its own: `&` names what it borrows, so a
    // call given one is a call given a binding.
    try testing.expect(try mutated(gpa, .unknown_member,
        \\struct Coins { count: UInt8 }
        \\
        \\impl Coins {
        \\    fn of(x: Coins) -> UInt8 { x.count }
        \\    fn bump(inout x: Coins) { x.count = 1 }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    var coppers: Coins = .{ count = 3 }
        \\    Coins.bump(&coppers)
        \\    Coins.of(coppers)
        \\}
    ) == null);
}

test "the value a disposal is about to take is copied" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const out = (try mutated(gpa, .copied_disposal, disposes)).?;

    // Before the disposal, so the value is still given away exactly once and
    // the source is still read below -- a copy of something moved is [O-Move]
    // and a copy nothing reads again is [O-CopyDead], and this is neither.
    try testing.expect(std.mem.indexOf(u8, out, "let _zzc = copy(_l0);") != null);
    try testing.expect(std.mem.indexOf(u8, out, "let _n0: UInt8 = _dispose(_l0);") != null);

    try testing.expect(asClaimed(try verdictOf(gpa, out, .program), .copied_disposal));
}

test "a disposal put behind a condition leaves the paths disagreeing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const out = (try mutated(gpa, .conditional_disposal, disposes)).?;

    try testing.expect(std.mem.indexOf(u8, out, "if true { let _n0: UInt8 = _dispose(_l0); };") != null);

    try testing.expect(asClaimed(try verdictOf(gpa, out, .program), .conditional_disposal));
}

test "a conditional disposal retains independent observation failures" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const out =
        \\@linear struct Owner { number: UInt8 }
        \\fn close(sink owner: Owner) -> UInt8 { let Owner { number } = owner; number }
        \\fn main() -> UInt8 {
        \\    let owner: Owner = .{ number = 1 }
        \\    let view = borrow owner
        \\    if true { let _closed = close(owner) };
        \\    view.number
        \\}
    ;
    const verdict = try verdictOf(gpa, out, .program);
    try testing.expect(verdict.rejected);
    try testing.expect(cites(verdict.text, "O-Borrow"));
    try testing.expect(cites(verdict.text, "O-Merge"));
    try testing.expect(asClaimed(verdict, .conditional_disposal));
}

test "a disposal whose result something reads stays where it is" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // The block would take the binding with it, and a reader left outside is
    // reported missing -- which says nothing about the paths.
    try testing.expect(try mutated(gpa, .conditional_disposal,
        \\@linear enum L0 { _W0(UInt8), _W1 }
        \\
        \\fn _dispose(sink held: L0) -> UInt8 {
        \\    match held { _W0(carried) => carried, _W1 => 1 }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let _l0: L0 = L0._W0(3);
        \\    let n0: UInt8 = _dispose(_l0);
        \\    n0
        \\}
    ) == null);
}

test "a copyable type is declared holding the linear one" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const affine = try std.mem.concat(gpa, u8, &.{ disposes, "\nstruct _AffineHolds { _f: L0 }\n" });
    try testing.expect(!(try verdictOf(gpa, affine, .program)).rejected);

    const out = (try mutated(gpa, .copyable_holds_linear, disposes)).?;

    try testing.expect(std.mem.indexOf(u8, out, "@copyable struct _ZzHolds { _f: L0 }") != null);

    try testing.expect(asClaimed(try verdictOf(gpa, out, .program), .copyable_holds_linear));
}

test "a disposal is given an operand that leaves before it starts" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const out = (try mutated(gpa, .abrupt_after_a_transfer, disposes)).?;

    // The value still goes to `_dispose`, by way of a wrapper that does what
    // the call site did. What the program is now wrong about is that control
    // leaves between `_l0` being given up and the wrapper being entered.
    try testing.expect(std.mem.indexOf(u8, out, "_zzafter(_l0, return 0)") != null);
    try testing.expect(std.mem.indexOf(u8, out, "fn _zzafter(sink _a: L0, _b: UInt8) -> UInt8 { _dispose(_a) }") != null);

    try testing.expect(asClaimed(try verdictOf(gpa, out, .program), .abrupt_after_a_transfer));
}

test "a transfer the scope still owes something else at is left alone" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // A second linear value, still held when the transfer runs and discharged
    // after it through a receiver rather than an argument -- so the transfer
    // is not the last obligation the scope owes. Control leaving there
    // abandons the second value, and a mutant leaking as well as failing to
    // commit answers for neither rule.
    const holding_another =
        \\@linear enum L0 { _W0(UInt8), _W1 }
        \\
        \\@linear struct P0 { at: UInt8 }
        \\
        \\fn _dispose(sink held: L0) -> UInt8 {
        \\    match held { _W0(carried) => carried, _W1 => 1 }
        \\}
        \\
        \\impl P0 {
        \\    fn _close(sink p: P0) -> UInt8 {
        \\        let P0 { at: a } = p
        \\        a
        \\    }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let _p: P0 = .{ at = 1 };
        \\    let _l0: L0 = L0._W0(3);
        \\    let _n0: UInt8 = _dispose(_l0);
        \\    let _n1: UInt8 = _p._close();
        \\    0
        \\}
    ;

    try testing.expect(try mutated(gpa, .abrupt_after_a_transfer, holding_another) == null);

    // What declining it is worth, asserted rather than assumed: closing the
    // pool before the transfer leaves the transfer as the only obligation the
    // scope owes, and the same program is then mutated and rejected citing
    // the one rule.
    const owing_nothing_else =
        \\@linear enum L0 { _W0(UInt8), _W1 }
        \\
        \\@linear struct P0 { at: UInt8 }
        \\
        \\fn _dispose(sink held: L0) -> UInt8 {
        \\    match held { _W0(carried) => carried, _W1 => 1 }
        \\}
        \\
        \\impl P0 {
        \\    fn _close(sink p: P0) -> UInt8 {
        \\        let P0 { at: a } = p
        \\        a
        \\    }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let _p: P0 = .{ at = 1 };
        \\    let _l0: L0 = L0._W0(3);
        \\    let _n1: UInt8 = _p._close();
        \\    let _n0: UInt8 = _dispose(_l0);
        \\    0
        \\}
    ;

    const out = (try mutated(gpa, .abrupt_after_a_transfer, owing_nothing_else)).?;
    const v = try verdictOf(gpa, out, .program);

    try testing.expect(!cites(v.text, "O-Leak"));
    try testing.expect(asClaimed(v, .abrupt_after_a_transfer));
}

test "the operand is written after the value, whatever separates the two" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // A statement form binding nothing, and a call written across lines with a
    // trailing comma. The operand goes after the argument rather than before
    // the parenthesis, so what the author wrote between them survives.
    const out = (try mutated(gpa, .abrupt_after_a_transfer,
        \\@linear enum Key { Forged(UInt8) }
        \\
        \\fn release(sink k: Key) {
        \\    match k { Forged(_) => {} }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let a = Key.Forged(1)
        \\    release(
        \\        a,
        \\    )
        \\    2
        \\}
    )).?;

    try testing.expect(std.mem.indexOf(u8, out, "a, return 0,\n    )") != null);

    try testing.expect(asClaimed(try verdictOf(gpa, out, .program), .abrupt_after_a_transfer));
}

test "a disposal whose callee takes more than the value is left alone" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // A wrapper taking one value cannot stand in for a callee taking two: the
    // second would be left with nothing taking it, which is [O-Leak] and says
    // nothing about where control was.
    try testing.expect(try mutated(gpa, .abrupt_after_a_transfer,
        \\@linear enum Key { Forged(UInt8) }
        \\
        \\fn use2(sink a: Key, sink b: Key) -> UInt8 {
        \\    match a { Forged(m) => match b { Forged(n) => m + n } }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let first: Key = .Forged(1)
        \\    let second: Key = .Forged(2)
        \\    use2(first, second)
        \\}
    ) == null);
}

test "a transfer in a function no integer answers for is left alone" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // The operand leaves the function the transfer is written in, so what it
    // carries has to be a value of what that function answers with. Where it
    // is not, the mutation would be rejected for a type it never claimed.
    try testing.expect(try mutated(gpa, .abrupt_after_a_transfer,
        \\@linear enum Key { Forged(UInt8) }
        \\
        \\fn release(sink k: Key) {
        \\    match k { Forged(_) => {} }
        \\}
        \\
        \\fn drop(sink k: Key) {
        \\    release(k)
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    drop(Key.Forged(1))
        \\    2
        \\}
    ) == null);
}

test "a program with no linear type has nothing to hold" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    try testing.expect(try mutated(gpa, .copyable_holds_linear,
        \\enum Colour { Red, Green }
        \\fn main() -> UInt8 { match Colour.Red { Red => 1, Green => 2 } }
    ) == null);
}
