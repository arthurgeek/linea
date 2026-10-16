# Errors the guide shows

Every diagnostic the compiler prints names the rule it enforces, such as
`error[O-Leak]`. This page lists each code the guide shows a real error, warning
or note for, where the guide first shows it, and the section of the [language
definition](../linea-semantics.md) that defines its rule. Search that section
for the code in brackets to reach the rule itself.

| Code | Kind | First shown in | Rule |
| --- | --- | --- | --- |
| `M-Embed` | error | Text: [Text from a file the program carries](08-text.md#text-from-a-file-the-program-carries) | [§3.7 Modules](../linea-semantics.md#37-modules), at `[M-Embed]` |
| `M-EmbedText` | error | Text: [Text from a file the program carries](08-text.md#text-from-a-file-the-program-carries) | [§3.7 Modules](../linea-semantics.md#37-modules), at `[M-EmbedText]` |
| `M-Extern` | error | Calling C: [Only a trusted module declares C](11-calling-c.md#only-a-trusted-module-declares-c) | [§3.9 Opaque types](../linea-semantics.md#39-opaque-types), at `[M-Extern]` |
| `M-Foreign` | error | Calling C: [`std.ffi` stays inside the trusted module](11-calling-c.md#stdffi-stays-inside-the-trusted-module) | [§3.9 Opaque types](../linea-semantics.md#39-opaque-types), at `[M-Foreign]` |
| `M-Opaque` | error | Copying, settling and sealing: [`@opaque`: only the module can make one](04-copying-settling-and-sealing.md#opaque-only-the-module-can-make-one) | [§3.9 Opaque types](../linea-semantics.md#39-opaque-types), at `[M-Opaque]` |
| `M-Unused` | error | Testing: [Helpers that tests share](10-testing.md#helpers-that-tests-share) | [§3.9 Opaque types](../linea-semantics.md#39-opaque-types), at `[M-Unused]` |
| `M-Vis` | error | Linea in an hour: [Modules](01-linea-in-an-hour.md#modules) | [§3.8 Visibility](../linea-semantics.md#38-visibility), at `[M-Vis]` |
| `N-Case` | error | Linea in an hour: [A name's case says what it names](01-linea-in-an-hour.md#a-names-case-says-what-it-names) | [§3 Names](../linea-semantics.md#3-names), at `[N-Case]` |
| `N-Immutable` | error | Linea in an hour: [`let` and `var`](01-linea-in-an-hour.md#let-and-var) | [§3 Names](../linea-semantics.md#3-names), at `[N-Immutable]` |
| `N-Shadowed` | warning | Calling things: [When the type and a trait both have the operation](02-calling-things.md#when-the-type-and-a-trait-both-have-the-operation) | [§3 Names](../linea-semantics.md#3-names), at `[N-Shadowed]` |
| `N-Unused` | error | Copying, settling and sealing: [Phantom types: a tag that is never stored](04-copying-settling-and-sealing.md#phantom-types-a-tag-that-is-never-stored) | [§3 Names](../linea-semantics.md#3-names), at `[N-Unused]` |
| `O-Borrow` | error | Calling things: [Why captures are written out](02-calling-things.md#why-captures-are-written-out) | [§5.5 What is checked](../linea-semantics.md#55-what-is-checked), at `[O-Borrow]` |
| `O-Capture` | error | Calling things: [Closures: functions that capture](02-calling-things.md#closures-functions-that-capture) | [§5.2 Matching](../linea-semantics.md#52-matching), at `[O-Capture]` |
| `O-Copy` | error | Copying, settling and sealing: [`copyable`: values that are safe to duplicate](04-copying-settling-and-sealing.md#copyable-values-that-are-safe-to-duplicate) | [§5.3 Copying](../linea-semantics.md#53-copying), at `[O-Copy]` |
| `O-DeferDead` | error | Copying, settling and sealing: [A `defer` and a move](04-copying-settling-and-sealing.md#a-defer-and-a-move) | [§4 Types](../linea-semantics.md#4-types), at `[O-DeferDead]` |
| `O-Escapes` | error | Borrowing: [What happens if you forget one](06-borrowing.md#what-happens-if-you-forget-one) | [§5.5 What is checked](../linea-semantics.md#55-what-is-checked), at `[O-Escapes]` |
| `O-Leak` | error | Linea in an hour: [`Vec`: a list that grows](01-linea-in-an-hour.md#vec-a-list-that-grows) | [§5.5 What is checked](../linea-semantics.md#55-what-is-checked), at `[O-Leak]` |
| `O-LinearWalk` | error | Iterating: [Draining, and walks that lend](05-iterating.md#draining-and-walks-that-lend) | [§5.3 Copying](../linea-semantics.md#53-copying), at `[O-LinearWalk]` |
| `O-Merge` | error | Copying, settling and sealing: [`linear`: values you must not forget](04-copying-settling-and-sealing.md#linear-values-you-must-not-forget) | [§5.5 What is checked](../linea-semantics.md#55-what-is-checked), at `[O-Merge]` |
| `O-Move` | error | Linea in an hour: [`read`, `inout` and `sink`](01-linea-in-an-hour.md#read-inout-and-sink) | [§5.5 What is checked](../linea-semantics.md#55-what-is-checked), at `[O-Move]` |
| `O-ScalarCopy` | error | Copying, settling and sealing: [Numbers and truth values copy themselves](04-copying-settling-and-sealing.md#numbers-and-truth-values-copy-themselves) | [§5.3 Copying](../linea-semantics.md#53-copying), at `[O-ScalarCopy]` |
| `O-Temporary` | error | Text: [A temporary lasts until the end of its statement](08-text.md#a-temporary-lasts-until-the-end-of-its-statement) | [§5.5 What is checked](../linea-semantics.md#55-what-is-checked), at `[O-Temporary]` |
| `O-Universe` | error | Copying, settling and sealing: [A copyable type can only hold copyable things](04-copying-settling-and-sealing.md#a-copyable-type-can-only-hold-copyable-things) | [§5.2 Matching](../linea-semantics.md#52-matching), at `[O-Universe]` |
| `S-Continuation` | note | Linea in an hour: [Where a statement ends](01-linea-in-an-hour.md#where-a-statement-ends) | [§2 Grammar](../linea-semantics.md#2-grammar), at `[S-Continuation]` |
| `S-Entry` | error | Linea in an hour: [`read`, `inout` and `sink`](01-linea-in-an-hour.md#read-inout-and-sink) | [§2 Grammar](../linea-semantics.md#2-grammar), at `[S-Entry]` |
| `S-Mutation` | error | Calling things: [`&` marks a receiver the call will change](02-calling-things.md#-marks-a-receiver-the-call-will-change) | [§2 Grammar](../linea-semantics.md#2-grammar), at `[S-Mutation]` |
| `S-Params` | error | Calling things: [A closure that takes a pair apart](02-calling-things.md#a-closure-that-takes-a-pair-apart) | [§2 Grammar](../linea-semantics.md#2-grammar), at `[S-Params]` |
| `S-Tuple` | error | Linea in an hour: [Tuples](01-linea-in-an-hour.md#tuples) | [§2 Grammar](../linea-semantics.md#2-grammar), at `[S-Tuple]` |
| `S-UnitResult` | error | Linea in an hour: [`read`, `inout` and `sink`](01-linea-in-an-hour.md#read-inout-and-sink) | [§2 Grammar](../linea-semantics.md#2-grammar), at `[S-UnitResult]` |
| `T-Arity` | error | Memory: [A function's `_in` form takes the allocator](07-memory.md#a-functions-_in-form-takes-the-allocator) | [§4 Types](../linea-semantics.md#4-types), at `[T-Arity]` |
| `T-BorrowContract` | error | Borrowing: [`borrows` — my result points into what you gave me](06-borrowing.md#borrows--my-result-points-into-what-you-gave-me) | [§5.5 What is checked](../linea-semantics.md#55-what-is-checked), at `[T-BorrowContract]` |
| `T-Bound` | error | Calling things: [`@derive` on a generic type](02-calling-things.md#derive-on-a-generic-type) | [§4 Types](../linea-semantics.md#4-types), at `[T-Bound]` |
| `T-Call` | error | Iterating: [Asking questions: `any`, `all` and `find`](05-iterating.md#asking-questions-any-all-and-find) | [§4 Types](../linea-semantics.md#4-types), at `[T-Call]` |
| `T-Cover` | error | Linea in an hour: [`match`](01-linea-in-an-hour.md#match) | [§4 Types](../linea-semantics.md#4-types), at `[T-Cover]` |
| `T-Default` | error | Errors: [A checked value as a default argument](03-errors.md#a-checked-value-as-a-default-argument) | [§4 Types](../linea-semantics.md#4-types), at `[T-Default]` |
| `T-DefaultedAllocator` | error | Memory: [The allocator is part of the type](07-memory.md#the-allocator-is-part-of-the-type) | [§4 Types](../linea-semantics.md#4-types), at `[T-DefaultedAllocator]` |
| `T-DeferLet` | error | Copying, settling and sealing: [`defer let`: bind a value and schedule its release](04-copying-settling-and-sealing.md#defer-let-bind-a-value-and-schedule-its-release) | [§4 Types](../linea-semantics.md#4-types), at `[T-DeferLet]` |
| `T-Derive` | error | Calling things: [`@derive`: implementations the compiler writes](02-calling-things.md#derive-implementations-the-compiler-writes) | [§4 Types](../linea-semantics.md#4-types), at `[T-Derive]` |
| `T-Discard` | error | Linea in an hour: [Where a statement ends](01-linea-in-an-hour.md#where-a-statement-ends) | [§4 Types](../linea-semantics.md#4-types), at `[T-Discard]` |
| `T-ExternCallback` | error | Calling C: [Callbacks: C calling Linea](11-calling-c.md#callbacks-c-calling-linea) | [§4 Types](../linea-semantics.md#4-types), at `[T-ExternCallback]` |
| `T-For` | error | Iterating: [Four ways to walk](05-iterating.md#four-ways-to-walk) | [§4 Types](../linea-semantics.md#4-types), at `[T-For]` |
| `T-Format` | error | Text: [Format specs: laying a value out](08-text.md#format-specs-laying-a-value-out) | [§2 Grammar](../linea-semantics.md#2-grammar), at `[T-Format]` |
| `T-Impl` | error | Text: [Reading text as a value](08-text.md#reading-text-as-a-value) | [§4 Types](../linea-semantics.md#4-types), at `[T-Impl]` |
| `T-Index` | error | Linea in an hour: [Arrays, views and collections](01-linea-in-an-hour.md#arrays-views-and-collections) | [§4 Types](../linea-semantics.md#4-types), at `[T-Index]` |
| `T-Infer` | error | Calling things: [Naming a type argument](02-calling-things.md#naming-a-type-argument) | [§4 Types](../linea-semantics.md#4-types), at `[T-Infer]` |
| `T-LetElse` | error | Errors: [`let … else`: bind the value, or handle the failure right there](03-errors.md#let--else-bind-the-value-or-handle-the-failure-right-there) | [§4 Types](../linea-semantics.md#4-types), at `[T-LetElse]` |
| `T-Literal` | error | Linea in an hour: [Values and their types](01-linea-in-an-hour.md#values-and-their-types) | [§4 Types](../linea-semantics.md#4-types), at `[T-Literal]` |
| `T-Mismatch` | error | Errors: [`let … else`: bind the value, or handle the failure right there](03-errors.md#let--else-bind-the-value-or-handle-the-failure-right-there) | [§4 Types](../linea-semantics.md#4-types), at `[T-Mismatch]` |
| `T-Operands` | error | Linea in an hour: [Values and their types](01-linea-in-an-hour.md#values-and-their-types) | [§4 Types](../linea-semantics.md#4-types), at `[T-Operands]` |
| `T-Overflow` | error | Linea in an hour: [Arithmetic is checked](01-linea-in-an-hour.md#arithmetic-is-checked) | [§4 Types](../linea-semantics.md#4-types), at `[T-Overflow]` |
| `T-Refine` | error | Errors: [Limiting the values](03-errors.md#limiting-the-values) | [§4 Types](../linea-semantics.md#4-types), at `[T-Refine]` |
| `T-Refutable` | error | Errors: [`let … else`: bind the value, or handle the failure right there](03-errors.md#let--else-bind-the-value-or-handle-the-failure-right-there) | [§4 Types](../linea-semantics.md#4-types), at `[T-Refutable]` |
| `T-TryAnswer` | error | Errors: [`?` converts errors with `From`](03-errors.md#-converts-errors-with-from) | [§4 Types](../linea-semantics.md#4-types), at `[T-TryAnswer]` |
| `T-UnknownOperation` | error | Calling things: [A dot call reaches operations, not free functions](02-calling-things.md#a-dot-call-reaches-operations-not-free-functions) | [§3 Names](../linea-semantics.md#3-names), at `[T-UnknownOperation]` |

## Named but not shown

The chapters name these codes without pasting an error for them.

| Code | Named in | Rule |
| --- | --- | --- |
| `N-Ambiguous` | Calling things: [When the type and a trait both have the operation](02-calling-things.md#when-the-type-and-a-trait-both-have-the-operation) | [§3 Names](../linea-semantics.md#3-names), at `[N-Ambiguous]` |

`zig build` checks this page against the chapters, and refuses to configure
while a code is missing from it or a row has gone stale. It then prints the
page as it should read.
