# 23. One symbol space, resolved in two phases

Status: Accepted — 2026-07-26

## Context

The Stage 1 design deferred symbol and scope representation to Stage 3, and
functions are what make it due. Two assumptions the resolver rested on both
break, and neither breaks gently.

**A name had to be declared before it was used.** A binding's initialiser was
resolved before the binding became visible, so a reference to a name not yet
declared was undefined. Functions need the opposite: a call to a function
defined further down the file must resolve, or declaration order becomes
significant and mutual recursion is impossible.

**Scopes were one stack.** A block remembered a mark and truncated back to it,
which is right for blocks nested in one another and wrong for functions: a body
must not see the locals of whatever was resolved before it. That failure mode
does not fail — it resolves to the wrong thing, and lowering then reads the
wrong slot.

## Decision

### One space, not two

A `BindingId` names a local, a parameter or a function, and the kind is a
property of the symbol rather than of the table it came from.

A scope chain has to hold all three, and a lookup should not have to know which
kind it seeks before it knows what it found. Because the kind is recorded,
calling a local and using a function as an operand are both diagnosed, rather
than being states the representation cannot express.

The handle keeps the name `BindingId` rather than becoming `SymbolId`. A
declaration binds a name as much as a `let` does, and the type was already
documented as naming what a handle means rather than where it currently lives.

### Two phases

Phase one enters every declaration into the module scope. Nothing inside any
declaration is examined, so a name's position among the declarations stops
mattering. Forward references and mutual recursion follow from this and need no
rule of their own.

Phase two resolves each body against a chain holding the module scope and that
function's own parameters and locals.

### The floor is a truncation

Between functions the visible chain is cut back to the module scope. Functions
do not nest, so that truncation is exactly the floor a body needs, and a
separate scope-tree with `ScopeId` would express nothing more.

### No function type

A call reads its signature from the declaration. Nothing can hold a function as
a value, so a structural function type would have no expression to describe.
First-class functions would introduce one, and that is the change that would
make this decision worth revisiting.

## Consequences

An uncalled function is an error. [ADR 0014](0014-unused-declarations-are-errors.md)
says an unused declaration is an error and a function is a declaration; `main`
is exempt because the runtime calls it, and a leading `_` is exempt as
everywhere else. A language with modules would exempt what it exports; until
Linea has modules, the unused rule stands in for the export rule.

A second declaration of a name is reported at the second, and the first keeps
the name, so later references mean something rather than compounding one
mistake into many.

The lookup is a backward scan over the visible chain. That is linear in the
depth of the scope and was measured against nothing, because it is compared
against the alternative rather than against a target: a hash map per scope
costs an allocation per block, and blocks are numerous and shallow. If a
program appears whose scopes are deep enough to matter, this is a decision to
revisit with evidence rather than in advance.

## Alternatives considered

**Separate `BindingId` and `FunctionId` spaces.** More typed, and each lookup
would have to search two tables and decide which answer wins — which is the
shadowing rule, written twice. Rejected: one space states the rule once.

**A scope tree with `ScopeId` and parent links.** The general answer, and what
closures will need, because a closure's body sees an enclosing function's
locals and truncation cannot express that. Rejected now: with no nesting it is
the same behaviour with an indirection, and building it before there is
something to nest would be guessing at what the nesting looks like.

**Resolve in one pass with a fixup list.** Unresolved names recorded and
revisited once all declarations are known. Rejected: it produces the same
answers with a second mechanism, and a diagnostic for an undefined name would
have to be deferred and re-ordered to keep reports in source order.

**Keep declaration order significant.** Simplest, and C's answer before
prototypes. Rejected: mutual recursion becomes unexpressible, and the order of
declarations in a file stops being the author's to choose.
