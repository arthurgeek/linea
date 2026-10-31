# The Linea language

This document defines Linea's language rules. The decision records under
`docs/adr/` give the rationale and the rejected alternatives; if they disagree
with this document, correct this document.

Every rule has a bracketed name. Diagnostics include that name, so
`error[T-Mismatch]` refers directly to the rule below.

Rule names are grouped by what they constrain:

| prefix | constrains |
| --- | --- |
| `S-` | the grammar: what is a well-formed program |
| `N-` | names: what a name refers to, and whether it is used |
| `M-` | modules: what crosses a boundary between them |
| `T-` | types: what a value is, and where it may go |
| `L-` | layout: where a value's parts sit |
| `O-` | ownership: where a value went, and whether it was disposed of |

---

## §1 Values

A value is a number, a truth value, a value with named or positional parts, a
value that is one of several alternatives, a callable, or Unit. Positional
parts suit a value whose context gives each part its meaning, such as the two
bounds a function returns; a domain concept takes named parts. Linea has no
general pointer or reference types. A structural callable contains one code
pointer. Opaque library values such as `Str` and `Buffer` can represent access
to storage outside the value. An erased closure, `mem.Closure[S, A]`, is such a
library value: it holds the code address it is entered through and the bytes
from allocator `A` its callable's environment was moved into ([O-Capture]).

Unit is the type of an expression that produces no result beyond completion: a
`while`, an assignment, or a body that reaches its end. Unit is a value, so the
rules below need no distinction between statement and expression position. It
is the tuple of no components ([T-Tuple]). The type and its one value are both
written `()` ([ADR 0188](adr/0188-the-unit-value-is-written-as-its-type.md)):
`.Ok(())` is a `Result[(), E]` that succeeded. An empty block, `{}`, computes
nothing, so its value is `()` as every block reaching its end without a tail
is; it is not another spelling of the value. A function that returns Unit
writes no result type, and `-> ()` is refused ([S-UnitResult]).

`Never` is an uppercase primitive and the type of an expression whose local
continuation is unreachable. It has no values. It is zero-sized and vacuously
Copyable; these properties do not let a program produce or observe a value of
it. It may appear in every type position, including a parameter, result, field,
payload, array, generic argument or callable signature.

A type containing `Never` otherwise follows its ordinary constructor. A struct
with a required `Never` field cannot be completed, because no field initialiser
can produce one. An enum may retain inhabited alternatives: `Option[Never]`
still has `None`, while its `Some` cannot be built. Match exhaustiveness is
over the variants the enum declares and does not infer inhabitance from payload
types.

Eight integer types, distinguished by width and signedness:

```
Int8   Int16   Int32   Int64
UInt8   UInt16   UInt32   UInt64
Bool
```

`Bool` has two values, written `true` and `false`, and no order. No conversion
to or from it is allowed: a condition must be a `Bool`, not an integer.

Two floating-point types, IEEE 754 binary floats: `Float64`, binary64, and
`Float32`, binary32
([ADR 0226](adr/0226-float32-is-a-second-binary-floating-point-width.md)).

Each has exactly one name. A type's **representation** is its width in bits,
and its **range** follows from the width and the signedness: `UInt8` holds
`0 ..= 255`, `Int8` holds `-128 ..= 127`.

An integer literal takes the integer type its uses settle, and `Int64` when
nothing does
([ADR 0152](adr/0152-an-integer-literals-type-is-settled-by-its-uses.md)).

A **struct** contains named parts, all present at once and accessed by name.
An **enum** contains one of several named alternatives, accessed by matching.
Both are declared, nominal and named; their literals refer to an already named
type.

Every type has copying and settlement **capabilities**, which govern the
permitted uses of its values ([§5](#5-ownership)).

## §2 Grammar

A file is a list of imports and declarations. A module is a directory of such
files ([§3.7](#37-modules)). Declaration order has no significance.

```
file         ::= import* declaration*
import       ::= "import" path ("as" name)?
path         ::= name ("." name)*

declaration  ::= visibility? "export"? (external | trait | reexport | constant | alias)
               | attribute* visibility? "export"? (function | typedecl) | impl | template_impl | derive_impl
visibility   ::= "pub" | "internal"
attribute    ::= "@" attribute_item | "@" "(" attribute_item ("," attribute_item)* ","? ")"
attribute_item ::= "opaque" | "linear" | "copyable" | "carrier" | "unshareable" | "derive" "(" trait_ref ("," trait_ref)* ","? ")"
constant     ::= "let" name (":" type_name)? "=" expression unwrap?
function     ::= ("test" "trap"?)? "fn" name generics? "(" parameters? ")" ("->" result)? function_where? block
signature    ::= "fn" name generics? "(" parameters? ")" ("->" result)? function_where?
external     ::= "extern" signature
projsig      ::= "proj" name generics? "(" parameters? ")" "->" result function_where?
result       ::= type_name
function_where ::= "where" function_where_item ("," function_where_item)* ","?
function_where_item ::= predicate | source_contract
source_where ::= "where" source_contract ("," source_contract)* ","?
lambda_result ::= "->" (result source_where? | source_where)
source_contract ::= "carries" "(" ")"
                  | ("borrows" | "carries") "(" (result_path ":")? paths ")"
                  | "retains" "(" path ":" retained_source ("," retained_source)* ","? ")"
retained_source ::= "borrow"? path
paths        ::= path ("," path)* ","?
result_path  ::= "." path
projection   ::= projsig block
traversal    ::= "trav" name ("(" parameters? ")")? "=" expression
              | "trav" name "via" name
typedecl     ::= "struct" name generics? where_clause? "{" fields? "}"
               | "enum" name generics? where_clause? "{" variants? "}"
               | "type" name "=" type_name refinement?
refinement   ::= "where" "it" "in" litbound rangeop litbound
litbound     ::= "-"? integer
trait        ::= "trait" name generics? (":" type_bound ("+" type_bound)*)? where_clause? "{" (signature | projsig | declared)* "}"
declared     ::= "type" name (":" type_bound ("+" type_bound)*)?
settled      ::= "type" name "=" type_name
reexport     ::= "use" path
alias        ::= "alias" name generics? "=" type_name
impl         ::= "impl" generics? impl_head where_clause? "{" ("pub"? (function | projection | constant) | traversal)* "}"
              | "impl" generics? trait_ref "for" impl_head where_clause? "{" ("pub"? (function | projection | constant) | settled)* "}"
              | "impl" generics? trait_ref "for" impl_head where_clause? "via" name
              | "default" "impl" generics trait_ref "for" name where_clause? "{" (function | settled)* "}"
impl_head    ::= name type_arguments? | "()" | "borrow" type_name | tuple_type
template_impl         ::= "template" "impl" generics? trait_ref template_requirements? "{" function* "}"
template_requirements ::= "where" template_requirement ("," template_requirement)* ","?
template_requirement  ::= "reflect" "." "components" ":" type_bound ("+" type_bound)*
                        | "reflect" "." "supertraits" ":" "derived"
                        | "reflect" "." "target" ":" ("struct" | "enum" | "type")
derive_impl           ::= "derive" generics? derive_traits "for" target_head where_clause?
derive_traits         ::= derive_trait | "(" derive_trait ("," derive_trait)* ","? ")"
derive_trait          ::= trait_ref
target_head           ::= name type_arguments? | tuple_type

generics     ::= "[" generic ("," generic)* ","? "]"
generic      ::= "phantom"? name (":" type_bound ("+" type_bound)*)? ("=" type_name)?
trait_ref    ::= name ("." name)* type_arguments?
type_bound   ::= trait_ref | callable_type
where_clause ::= "where" predicate ("," predicate)* ","?
predicate    ::= type_name ":" type_bound ("+" type_bound)*

parameters   ::= parameter ("," parameter)* ","?
parameter    ::= convention? name ":" type_name ("=" expression)?
lambda_params ::= lambda_param ("," lambda_param)* ","?
lambda_param ::= convention? (name | tuple_pattern) (":" type_name)? ("=" expression)?
capture_list ::= "[" (capture ("," capture)* ","?)? "]"
capture ::= convention? name ("=" expression)?
convention   ::= "read" | "inout" | "sink"

fields       ::= field ("," field)* ","?
field        ::= name ":" type_name
variants     ::= variant ("," variant)* ","?
variant      ::= name ("(" type_name ("," type_name)* ","? ")")?

block        ::= "{" statement* expression? "}"
statement    ::= binding | destructure | scheduled | expression | braced
binding      ::= ("let" | "var") name (":" type_name)? "=" expression unwrap?
destructure  ::= "let" "read"? name? "{" binders? "}" "=" expression unwrap?
              | "let" "read"? name "(" name ")" "=" expression unwrap?
              | "let" "read"? tuple_pattern "=" expression unwrap?
unwrap       ::= "else" ("|" name "|")? block
scheduled    ::= "defer" expression
binders      ::= binder ("," binder)* ","?
binder       ::= name (":" name)?
tuple_pattern ::= "(" binder_name "," binder_name ("," binder_name)* ","? ")"
binder_name  ::= name | "_"

expression   ::= literal | qualified | "(" expression ")" | tuple
              | "reflect"
              | "." name ("(" arguments ")")?
              | ".{" initialisers? "}"
              | name ("." name)* type_arguments? "{" initialisers? "}"
               | "-" expression
               | "copy" "(" expression ")"
               | "panic" "(" expression ")"
               | ("embed" | "embed_bytes") "(" string ")"
               | expression "." name
              | "!" expression
              | expression binop expression
              | expression cmpop expression
              | expression logop expression
              | expression rangeop expression
              | expression "(" arguments? ")"
              | expression type_arguments "(" arguments? ")"
              | name "?" "(" arguments? ")"
              | (convention? capture_list)? ("||" | "|" lambda_params? "|") lambda_result? (expression | block)
              | place assignop expression
              | "&" place
              | "borrow" place
              | "break" expression? | "continue" | "return" expression?
              | braced
braced       ::= ifexpr
              | "while" expression block
              | "for" ("read" | "inout")? (name | tuple_pattern) "in" expression block
              | "loop" block
              | "match" "read"? expression "{" arms "}"
              | block
ifexpr       ::= "if" expression block ("else" (block | ifexpr))?

arms         ::= arm ("," arm)* ","?
arm          ::= pattern "=>" expression
pattern      ::= name ("(" name ("," name)* ","? ")")?
              | name "{" binders "}"
              | "reflect" "." "case"
              | pattern_bound (rangeop pattern_bound)?
              | tuple_pattern
              | "_"
pattern_bound ::= litbound | string | qualified
tuple        ::= "(" expression "," expression ("," expression)* ","? ")"

place        ::= (name | expression "." "value") (("." name) | ("[" index "]"))*
index        ::= expression | "^" expression
qualified    ::= name ("." name)*
arguments    ::= argument ("," argument)* ","?
argument     ::= (name ":")? expression
initialisers ::= name ("=" expression)? ("," name ("=" expression)?)* ","?
literal      ::= integer | float | string | string_line+ | interpolation | "true" | "false" | "(" ")"
float        ::= digits "." digits exponent? | digits exponent
exponent     ::= ("e" | "E") ("+" | "-")? digits
interpolation ::= str_open interpolation_value (str_mid interpolation_value)* str_close
interpolation_value ::= expression (":" format_spec)?
format_spec  ::= (fill? align)? "+"? "0"? digits? ("." digits)? "?"?
fill         ::= a character other than "{", "}", "\", a quote, a tab
                 or a line break
align        ::= "<" | ">" | "^"
binop        ::= "+" | "-" | "*" | "/" | "%"
assignop     ::= "=" | "+=" | "-=" | "*=" | "/=" | "%="
cmpop        ::= "==" | "!=" | "<" | "<=" | ">" | ">="
logop        ::= "&&" | "||"
rangeop      ::= ".." | "..="
type_name    ::= "borrow" type_name | type_base ("." name type_arguments?)*
type_base    ::= name type_arguments? | "(" ")" | "(" type_name ")" | tuple_type
               | array_type | callable_type
tuple_type   ::= "(" type_name "," type_name ("," type_name)* ","? ")"
array_type   ::= "[" type_name ";" (expression | "_") "]"
callable_type ::= convention? "fn" "(" parameters? ")" ("->" result)? source_where?
type_arguments ::= "[" type_name ("," type_name)* ","? "]"
```

The grammar omits statement terminators. A line break separates statements
([S-Separator]); `;` separates statements on the same line. Inside an array
type, that token separates the element type from the length and ends no
statement. It appears nowhere else. An `import` uses the same terminators as a
statement, although it is a declaration.

Words quoted in the grammar are reserved and cannot be names, with the
exceptions below. This includes words used in only one grammatical position,
such as `read`, `copy`, `sink`, `embed`, `embed_bytes`, `impl`, `opaque`,
`linear`, `copyable` and `carrier`, so a reader can decide whether a name is
legal without knowing the parser's state.

`type`, `alias`, `proj`, `trav`, `it`, `via` and `default` are contextual
words, not reserved words.

`default` marks a default implementation when it immediately precedes `impl`
at the start of a declaration. Elsewhere it is a name, so the prelude's
`Default` trait declares `fn default() -> Self` and a program calls
`Default.default()`.

`it` names the value in a refinement clause. No other name is allowed for that
value. Outside a refinement clause, `it` is an ordinary name.

A refinement declaration allows a line break between its base and `where`.
Once `where` begins the clause, any line break ends the declaration: after
`where`, `it` or `in`, between a bound's `-` and its digits, at either end of
the range, or at any position introduced by a later clause form. Unlike
[S-Separator], this rule does not inspect the preceding token. End of file also
ends the clause. If a break interrupts an incomplete clause, that clause has no
range; the compiler reports the break as [S-Separator] and reads the following
text as a separate declaration.

`type` introduces a declaration at file scope, inside a trait, or inside an
implementation; in each position a following name distinguishes a declaration
from an ordinary use of the word. Elsewhere it is a name. `alias` introduces a
declaration at file scope when a name follows it, and is a name everywhere
else.

`proj` introduces a projection member in a trait or implementation; `trav`
introduces a traversal in an inherent implementation. Each is recognised in
member position when followed by a name. `via` introduces a direct stored-field
target after an implementation head and its constraints, or after a traversal
name. Elsewhere `via` is an ordinary identifier.

Primitive names are in every scope and are not reserved words. Redeclaring
`UInt8` is a duplicate declaration. A conversion is an ordinary call whose
callee names a primitive.

A trailing `where` clause belongs to a generic declaration head and stands
between that head and its body; on a bodyless function or projection signature
it stands at the end. Its predicates are comma-delimited and a multiline clause
may retain a trailing comma. The `where it in` clause of a newtype is a
refinement instead: its fixed `it` subject is a value, while a trailing
clause's subject is a type.

`qualified` covers every dotted name: a module declaration, a type member or an
enum variant. The parser produces one shape; the head's meaning determines
which it is ([§3](#3-names)). In a type position, a selection follows a
complete written type base. A module base qualifies a declaration; a type base
selects an associated type. `module.Box[T].Item` first names the generic
declaration, applies its arguments, then selects `Item`. Parentheses preserve
the base explicitly, as in `(borrow T).Item`; `borrow T.Item` instead observes
the selected type.

A construct that takes a block takes it directly, so a condition is written
without parentheses.

**[S-Entry]** A program is a list of declarations, exactly one of which is
`main() -> UInt8` or `main() -> Result[UInt8, E]`. Its value is the process's
exit status, and the runtime calls it
([ADR 0024](adr/0024-a-program-is-a-list-of-declarations.md)). A test is never
the entry point, whatever it is named, so a program whose only `main` is a test
declares none. A root module declaring several `main`s is refused once, at the
first: the report reads "a module has one `main`, and `app/` declares 2". A
directory is one module, so two programs kept side by side in one directory
are this mistake, and the report notes it and names one file to build or test
on its own. Every name such a module declares twice, and everything a later
pass would say about it, depends on which of two declarations a name reached,
so the [S-Entry] is the whole report: no [N-Duplicate] and no later diagnostic
is reported for that module. In a module with one `main`, a name declared twice
is an ordinary [N-Duplicate].

A root built to run tests may omit the entry point; the compiler generates the
test binary's entry point, so a module containing only tests can be tested,
including the standard library. Multiple entry points remain invalid. If a
`main` is present it must satisfy the signatures above even though the test
binary emits none of its code.

The second signature lets a failure leave the program. An `Ok` payload becomes
the exit status, exactly as a bare `UInt8` result does. An `Err` is rendered to
standard error, and the process exits non-zero. The success carries `UInt8`;
the failure implements `Display`. [S-Entry] checks the signature's shape; the
type checker checks the payload types and reports a missing failure
implementation as [T-Bound].

The restrictions apply to the whole signature. The success value must be
`UInt8`, the emitted entry point's exit-status representation. The entry point
takes no parameters or type arguments, because the runtime supplies neither. It
is not exported: an executable root has no import route, so `pub fn main` is
refused. That restriction applies only in the root; an imported module's `main`
is an ordinary function and may be exported. Each restriction is checked at its
source location, so a signature that violates two receives both diagnostics.
Entry-point selection requires name resolution: a well-formed file with no
`main` parses but cannot start a program.

The same rule rejects a modifier wherever it has no effect
([ADR 0056](adr/0056-a-modifier-is-refused-where-it-says-nothing.md)).
`opaque` seals a representation, `linear` specifies consumption obligations,
and `copyable` permits copying when the owned parts allow it. They apply only
to a `struct`, an `enum` or a newtype. A function, trait, constant, re-export
or alias declares no representation for them. An `import` accepts no visibility
or modifier; it binds a module within its file. A `use` declaration forwards a
name. `pub` and `internal` apply to the declarations whose names another module
may access. A modifier before `impl` is also refused: an implementation
declares no name for `pub` to export and no type for `linear` or `copyable` to
describe, and `impl` contains only the member declarations listed in the
grammar.

A newtype uses its base's representation and inherits its base's settlement
obligation. `opaque` restricts access to that representation to the declaring
module. Its default policy is affine; an explicit copyable policy must satisfy
[O-Universe], as for a struct or enum ([§4](#4-types)).

Explicit `read` on a function or lambda parameter is redundant and violates
[S-Entry]: omitting the convention already means `read`. This includes trait
signatures, implementation members and parameters with defaults.

A trait declares an associated type with `type Item`; its implementation
settles it with `type Item = UInt8`. A settled type in a trait is refused, so
exactly one place defines it. An **inherent** implementation allows neither
form: an associated type belongs to a trait. A bound appears only on the
declaration (`type Iter: Iterator` requires every implementation's chosen type
to satisfy it); a bound on a settled type is refused. A settled type has no
visibility modifier, and writing one is refused because `pub` would add no
meaning; like a trait signature it is reachable wherever the trait
is.

**[S-Test]** `test fn` declares a function called by the compiler and excluded
from shipped artefacts. A test has **no visibility**: `pub` would export a name
that imports cannot reach. The modifier applies only to a function. A test may
sit at module scope or inside an inherent `impl`, beside the members it tests.
Inside an implementation for a trait it is refused, because a trait
implementation declares only what its trait requires, and inside a template it
is refused, because a template is instantiated for every type that satisfies
it while the compiler writes a test's one call.

A test inside an `impl` is a member of nothing: it is named, resolved and run
exactly as if it were written at module scope. No path through the type reaches
it. Its name shares the module's one namespace with every other test and
top-level name, so two implementations in one module do not each declare a test
of one name ([N-Duplicate]), and the implementation adds nothing to its
qualified name. A test named `main`, inside an `impl` or not, is never the
entry point ([S-Entry]); in the root module beside the program's `main` it is a
second declaration of that name ([N-Duplicate]). A test is not instantiated, so
neither `Self` nor the implementation's type parameters name a type in it;
writing either is refused, and the test names the concrete types it tests
instead: `Boxed[UInt8]` in an annotation, and `Boxed` before a call, whose
arguments settle the instance. Inside a trait implementation or a template,
where the test itself is refused, neither name is reported again.

A test may instead be written `test trap fn`. It succeeds only when its child
process reaches a language trap; returning successfully, returning a failure,
or ending for another reason fails the test. The trap's kind and message are
not matched.

No expression names a test, including an expression inside another test. Only
the compiler may generate a call to it.

A test may omit its return annotation. Its result is then
`Result[(), testing.Failure]`, using the trusted library declaration without
requiring an import or introducing a source binding. Normal unit fallthrough
and bare `return` produce `Ok(())`; explicit return values must satisfy the
result type. Assertions still propagate with `?`, and explicit deferred cleanup
runs on both success and failure. A written return annotation keeps its
ordinary meaning. A function that is not a test and writes no result returns
`()` ([S-UnitResult]).

A test is known outside the compiler by its qualified name: the path of its
module's directory beneath the program root, each directory name followed by
`.`, then the test's own name. A test in the root module is known by its bare
name, and one in `text/str` as `text.str.a_thing_holds`. A directory name that
is an identifier is written as it is. Within a directory name, a `.` is written
`\.` and a `\` is written `\\`, so the one directory `a.b` names its test
`a\.b.holds` and the two directories `a/b` name theirs `a.b.holds`. Every other
byte is written as the directory name holds it, so `my-lib/ledger` names its
test `my-lib.ledger.holds`. The test runner reports each test by this name,
and a test binary runs the test whose name it is given.

A failing test's exit status is fixed and does not encode the failure's
contents; standard error carries the description.

`Result` refers to the prelude's declaration, as it does for `?` and
[T-DiscardFailure].

**[S-Char]** A byte that cannot begin a token is invalid source.

**[S-String]** A string literal must close before the end of its line. This
holds for a raw literal too, and an unclosed raw literal is reported as
unterminated with the closing sequence it needs. A raw literal opens with at
most eight `#`; one opened with more is refused. The lines of a multi-line
literal are consecutive: a blank line or a comment between two of its lines is
refused. A multi-line literal cannot begin inside an interpolation, since its
line would run over the `}` that closes the interpolation.

**[S-Float]** A float literal has digits on both sides of its point and digits
in its exponent. `1.` and `1.5e` are refused where they are written.

A number cannot begin with a point. A point belongs to a number only when a
digit follows it, so `0..9` is three tokens and `1.foo` is an access. The point
also commits the token to being a float: `1e` is a number followed by a name,
while a dangling exponent after a point is an error in the float literal.

**[S-Encoding]** A source file must be valid UTF-8.

**[S-Escape]** An escape in a string literal names one of `n`, `t`, `r`, `0`, a
backslash, a quote, or `u{...}`. A `\u{...}` names a Unicode scalar by number,
so one above `U+10FFFF` or inside the surrogate range is refused. A literal
contains the decoded escapes; its token preserves the source text. `"Ol\u{e1}"`
and `"Olá"` produce the same four bytes.

**[S-Interpolation]** A `{` in a string literal opens an expression, and the `}`
matching it closes one. A doubled brace is one brace in the text: `{{` writes a
literal `{`, and `}}` means one `}`, though a lone `}` outside an interpolation
closes nothing and is an ordinary byte either way. The braces in a `\u{...}`
escape do not open an interpolation. An interpolation requires an expression,
so `"{}"` is invalid, and the expression must fit on one line because the
surrounding string literal ends at a line break.

A **raw literal** is an `r` followed directly by a quote: `r"GET /echo/{name}"`.
Its text is the bytes between its quotes exactly. A backslash begins no escape
and a brace opens no interpolation, so `r"C:\temp"` holds a backslash and
`r"{name}"` holds two braces; [S-Escape] and [S-Interpolation] do not apply.
Hashes between the `r` and the opening quote let the text contain a quote: the
literal closes at the first quote followed by as many hashes as opened it, so
`r#"{"ok":true}"#` holds `{"ok":true}` and `r##"a "# b"##` holds `a "# b`. Up
to eight hashes may open one.

A raw literal is a string literal in every other respect. It has type `Str`, it
is a constant expression, and one naming a single scalar denotes that scalar at
a range end, so the pattern `r"\"..=r"\"` matches the backslash byte. It ends
at a line break as every string literal does, and since it has no escapes it
cannot hold a line break: text of several lines is a multi-line literal. An `r`
followed by anything other than a quote or hashes and a quote is a name: `let r
= 1` binds `r`, `r "x"` is a name and then a literal, and `rr"x"` is the name
`rr` and then a literal.

A **multi-line literal** is a run of lines that each begin with `\\`, after
any indentation:

```linea
let letter =
    \\Dear {name},
    \\your order {order} has shipped.
```

Each line holds the text after its `\\` up to the end of the line, and the
lines are joined with a line break between each two, so `letter` holds two
lines of text and 44 bytes. Nothing on a line is read: a brace opens no
interpolation, a backslash begins no escape, and `"` and `//` are text, so
[S-Escape] and [S-Interpolation] do not apply. The indentation before `\\` is
layout and every byte after it is text, including trailing spaces. A `\r`
directly before a line break belongs to the break.

No line break follows the last line. An empty `\\` line is an empty line of
text, so a literal whose last line is a bare `\\` ends with a line break:

```linea
let rows =
    \\name,total
    \\
```

holds `name,total` and a line break.

Each line is a token of its own. The first line may share its line with the
token before it, as in `let one = \\text`, or start on the line after a token
that cannot end a statement, such as `=`, `(` or `,`. The lines below it belong
to the literal while each is directly below the last; the first line that is
not a `\\` line ends it. A blank line or a comment between two lines is refused
under [S-String]. Whatever follows the literal is on the line after its last,
because the last line runs to its end: a call's `)` or a following argument's
`,` starts the next line, and the literal's last line ends a statement as any
literal ending a line does ([ADR 0041](adr/0041-a-newline-ends-a-statement.md)).

A multi-line literal is a string literal in every other respect. It has type
`Str`, it is a constant expression and it can be a parameter default. A comma
after its last line is text, so a match arm whose body is a multi-line literal
writes the body as a block and puts the comma after the block's `}`. It is not
a pattern: the `=>` after it would be part of its last line.

An **embedded file** is the content of a file the program carries, read when
the program is compiled rather than when it runs:

```linea
let page = embed("templates/page.html")
let icon = embed_bytes("icon.png")
```

`embed(path)` is the file's text, a `Str`, and `embed_bytes(path)` is its bytes,
a `mem.Slice[UInt8]`. Every byte is kept as the file holds it: a byte order
mark, `\r\n` line ends, a final line break and NUL bytes are all part of the
value. The path is relative to the directory of the file that writes it, and
which files it may name is [M-Embed]'s. The program needs nothing beside it
when it runs, and a change to the file is seen the next time the program is
compiled.

**[S-Embed]** The argument of `embed` or `embed_bytes` is one string literal,
quoted or raw, that names the file. The file is read before any name is
resolved, so the path is written where it is used: a name, even of a string
constant, an interpolated or multi-line literal, a second argument and no
argument are refused. Both words are reserved and written with their
parentheses; neither is a callable value.

**[S-Format]** An expression inside an interpolation may be followed by a
colon and a format spec, `[[fill]align][+][0][width][.precision][x|X|?]`,
each part optional and in that order: `"{day:02}"`, `"{count:>4}"`,
`"{price:.2}"`, `"{name:<10}"`, `"{name:*^9?}"`, `"{color:06x}"`. A colon begins a spec only
outside every parenthesis, bracket and brace of the value, so the colon in
`"{f(n: 1)}"` names an argument. Spaces around the spec are not part of it.

- `?` renders the value through `Debug`; without it the value renders through
  `Display`.
- `<`, `>` and `^` place the value at the left, the right or the centre of its
  width, with any odd column of centring after it. Without an alignment,
  numbers sit on the right and every other value on the left. A fill is the one
  character before an alignment, written once for each column of padding;
  without one the fill is a space. `{`, `}`, `\`, a quote and a line break
  cannot be a fill. Spaces and tabs directly after the colon are not part of
  the spec, so a tab cannot be a fill and a written space fill is the default
  one.
- `+` writes a plus sign before a number that is not negative.
- `0` pads a number with zeros between its sign and its digits, so `-5` with
  `:04` is `-005`. It replaces the fill and alignment, so it is refused beside
  an alignment.
- The width, digits not beginning with `0`, is the fewest columns the value
  occupies, counted in Unicode scalars: `"café"` occupies four. A value wider
  than its width is written whole.
- `.precision` is the number of digits after a float's point.
- `x` writes an integer's digits in base 16 with the letters `a` to `f`, and
  `X` with `A` to `F`. A negative integer is written as `-` and the digits of
  its magnitude, so `-255` with `:x` is `-ff` whatever its type, and zero
  padding goes between the two: `-000ff` with `:06x`.

A colon with no spec after it, a part out of order, more than one of `x`, `X`
and `?`, an alignment or `0` without a width, a width or precision above
65535, and `0` beside an alignment are refused. A width and a precision are literal numbers; a width chosen at run
time is written through `std.fmt.Spec` instead.

**[T-Format]** A spec's parts must suit the value's type. A sign and zero
padding lay out integers and floats, a precision lays out a float only,
and `x` and `X` write integers only; fill, alignment and width lay out any
value. A generic value is a number, and an integer, when it has `Integer`
evidence. `"{name:.2}"` on a `Str`, `"{count:.2}"` on an integer and
`"{price:x}"` on a float are refused.

**[T-Interpolation]** The compiler creates a type for each interpolated
literal. Its value contains the surrounding text and the interpolated values.
The type implements `Display` and otherwise behaves like an ordinary struct: it
may be bound, passed and laid out. One literal may be interpolated into
another: `"[{"x={x}"}]"`.

An interpolated value that is Copyable is held as a copy, and an interpolated
place that is not is held by a read borrow. Any other value is moved into the
literal, unless it must be settled. Each must implement the selected format:
`Display` without `?`, or `Debug` with it. A copy carries whatever the value
observes, so a literal holding a `Str` view depends on the string it views. A
`borrow T` value is copied as the borrow itself and renders what it observes:
it implements the format wherever `T` does, a type parameter bounded by the
trait included. Both traits observe values, so a literal renders a place it
cannot copy, including a linear one, and the place's owner still settles it
afterwards. A missing formatting implementation violates [T-Bound].

The literal carries its borrows as a view does: it may be bound, passed and
returned only while the places it borrows outlive it, under [O-Borrow] and
[O-Escapes]. A constant is a place whose storage is static, so a literal that
borrows one depends on nothing. A value computed in the braces, such as a call
`"{score(4)}"`, a nested literal or a string literal, has no other owner and is
held by the literal. A computed value that must be settled cannot be held; it
is borrowed as a temporary of the literal's statement ([O-Temporary]), where
[O-Leak] refuses it unless something takes it.

Two literals that render the same types are one type, except where a value
that cannot be copied is borrowed in one and held in the other: `"hi {name}"`
borrows a variable `name`, while `"hi {make_name()}"` holds the value it
computes. Assigning one to a variable of the other, or choosing between them in
the arms of an `if` or a `match`, is [T-Mismatch]; binding the computed value
with `let` first makes both borrow a variable. Likewise, with
`let observed = borrow name`, `"hi {observed}"` holds a copy of the borrow and
`"hi {name}"` borrows the variable, so they are different types.

Interpolated expressions are evaluated once each, in source order, when the
literal is evaluated. A snapshot, a held value and a temporary are made there;
a borrowed place is observed there and cannot change while the literal borrows
it. Rendering the resulting value twice does not evaluate them again; leaving
it unrendered does not skip their evaluation. The syntax tree preserves the
literal's source form for the formatter.

**[S-Extern]** An `extern` declaration has no body. It names a runtime-provided
symbol.

**[S-Expr]** Where the grammar expects an expression, one must appear.

**[S-Name]** Where the grammar expects a name, an identifier must appear.

**[S-Type]** Where the grammar expects a type, a type name must appear.

**[S-UnitResult]** A callable that returns Unit writes no result type:
`fn add_tip(inout bill: UInt64) { ... }`. Leaving out `-> T` means the result
is `()`, for a function, a method, a trait's signature, an `extern` and a
callable type alike, so `add_tip` is a value of type
`fn(inout bill: UInt64)`. Writing `-> ()`, or `()` in grouping parentheses, is
refused where it is written, with help to remove it; on a top-level `main` the
help also says that an entry point writes `-> UInt8`
([ADR 0223](adr/0223-a-function-returning-nothing-writes-no-result.md)). Only
the unit type written as such is refused: `-> Result[(), E]` and `-> ((), T)`
are results that hold a Unit, and a name standing for `()`, such as an alias, is
not looked through. A lambda that writes no result takes its body's
type, Unit included, so `-> ()` is refused on a lambda too. Where neither a
written result nor its context gives it a type, its first `return` carrying a
value settles the result, as a loop's first `break` does: every later
`return`, a bare one included, and the body's own value are checked against
that type as their expected type, and an open literal in any of them settles
with the rest. A `return` inside another `return`'s value that settles the
result first holds that value to it in the same way, and so does a `break`
inside another `break`'s value for its loop. A `?` fixes only whether the
answer is an `Option` or a `Result`, not what a success carries, so it settles
nothing: it answers to the closure's result, whatever settles it and wherever
that is written, and is refused by [T-TryAnswer] only when nothing settles it.
A closure passed where its result is a type parameter the call infers is
read the same way: its `?`s answer to what its returns and body solve that
parameter to.
One that writes
contracts without a result keeps the arrow, `|x| -> where carries() { ... }`.
A `test fn` that writes no result answers `Result[(), testing.Failure]`
([S-Test]). A projection names a place and always writes its type.

**[S-Equals]** A binding's name is followed by `=`.

**[S-Destructure]** A destructuring binding begins with `let`; `var` is
rejected. It names each part once. For a struct,
`let Type { field, other: binder } = value` may omit the type head:
`let { field, other: binder } = value`. The initializer must then
independently determine its struct type; the pattern does not infer a type from
its field names. Both forms consume the whole value and require every field
exactly once. Shorthand, renamed binders, `_` discards, opaque visibility, and
ownership obligations follow the same rules. An empty struct uses
`let {} = value`. A tuple is taken apart by position with a tuple pattern
`(a, b)` ([S-Tuple]). A part of any of these patterns may itself be a pattern
([S-Match]), so `let Frame { origin: Point { x, y }, scale } = frame` takes the
inner point apart too; the pattern must match every value of its type
([T-Refutable]). There are no partial moves: the `let` takes the whole value.
Taking a tuple apart does not dispose of any component: each binder receives
its component and carries its ownership obligations.

`let read Pattern = place` binds the same newtype, whole-struct and tuple
patterns, nested as a consuming `let`'s may be, without taking the value apart. `read` marks the pattern, as it does
in `match read`; it is not an operator on the initializer. Each binder is a
read-only lend of the part its pattern selects, exactly as a `match read`
binder is, and no value is copied or moved to make it. The initializer must be
a place ([T-Lend]); an enum pattern stays refutable and is not admitted, and
`let read name = value` is rejected because `read` marks a pattern rather than
a name. `var read` is rejected with the other destructuring `var` forms.

```
pub fn address(self: Self) -> Str {
    let read Email(raw) = self   // `raw` is lent from `self`
    copy(raw)                    // a `Str` view still needs `copy`
}
```

The binders follow the rules of any lend: a scalar part produces a snapshot in
a value position, other duplication needs `copy` and Copyable, and nothing can
assign through a binder, pass it to `inout`, or move it ([O-Move]). Ignoring a
part with `_` settles nothing: the owner keeps every obligation it had. A lend
lasts until the last use of its binder or of anything observing through it, and
until then [O-Borrow] protects the selected part from the owner being written,
moved or released. A disjoint part may still change.

**[S-Separator]** Statements require a separator. A newline separates them;
`;` allows them to share a line. A newline ends a statement unless the
preceding token cannot end one, or the next line opens with `.` and a lowercase
name. The tokens that can end one are those an expression can end with: a name,
`reflect`, an integer, float or string literal, a `\\` line, the closing quote
of an interpolated string, `true`, `false`, `)`, `}`, `]`, a postfix `?`, and a
bare `break`, `continue` or `return`. The final expression of a block is an
exception: its position makes it the block's value. A statement ending in `}`
needs no further separator, so another statement may follow on the same line.
An `import` uses the same termination rule. A line beginning with `else`
continues the construct above it ([S-LetElse]).

A line opening with `.` and a lowercase name continues the expression above it
([ADR 0196](adr/0196-a-selection-line-continues-the-line-above.md)). An
operation and a field start with a lowercase letter and no statement begins
with one after a `.` ([N-Case]), so such a line can only select from the value
above, and a chain may put each selection on a line of its own:

```
let total = scores
    .as_slice()
    .map(|sink score| *score)
    .fold(0, |sink sum, sink score| sum + score)
```

A comment or a blank line between the two lines holds no token and changes
nothing. A line opening with `.` and a capitalised name, `.{`, or a name with
no case, such as `._1`, begins a statement: `.Ok(total)` below a statement is a
function's result. `fmt` writes a chain broken at any link one selection per
line, and leaves a chain written on one line on one line.

A line break also ends a declaration's result type, and the path of an
`import`, a `use` or a trait a declaration names, so a line opening with `.`
below one never continues it, whatever the case of the name. A line opening
with `.` and a name after a function's or a signature's result, as in `-> S`
followed by `.Item`, is refused once here, and the declaration continues from
there with no result type, so nothing else is refused for it.

**[S-Continuation]** The compiler emits a note when a newline ends a statement
and the next line begins with `-`, `()` or `.`, each of which can begin a new
statement or continue the preceding expression. The check uses token shape, not
types. The note identifies the token and suggests moving it to the end of the
preceding line if continuation was intended. It is a note, not an error,
because both readings may be valid. An explicit `;` confirms the statement
boundary, and `fmt` preserves it.

- A line beginning with `(` and anything other than `)` is not noted: such a
  line opens the tail of every function returning a tuple, and a call split
  before an argument that is not Unit leaves a value nothing uses, which
  [T-Discard] refuses. A call split before `()` leaves the unit value standing
  alone, which nothing refuses, so that line is noted; a split before a
  parenthesised argument that is Unit but not `()`, such as `(log())`, is
  neither noted nor refused
  ([ADR 0202](adr/0202-a-line-beginning-with-a-parenthesis-is-noted-only-as-an-empty-call.md)).
- A line opening with `.` is noted unless a capitalised name or `{` follows the
  dot, so `.Ok(0)`, `.None` and `.{ x = 1 }` are not noted while `.0`, `._1` and
  a `.` before anything else are
  ([ADR 0190](adr/0190-a-variant-line-is-not-a-continuation.md)). A line
  opening with `.` and a lowercase name continues an expression, so a newline
  ends a statement before one only after a declaration's path, as in `pub use
  mm` followed by `.thing`, and after an expression ending in a block, which
  takes no selection; both are noted, the second with the help to bind the
  value first.
- A brace cannot continue a statement: a named structure literal keeps its
  opening brace on the type head's line, while `{` on the next line opens a
  block.

**[S-LetElse]** A binding's `else` binds one name between two bars, or none,
and a binding takes one `else`. `else ||`, a binder of two names and a second
`else` after the block are each reported once.

A line that begins with `else` continues the construct above it, for an `if`
and for a binding alike, and the nearest construct still able to take the
`else` takes it: after an `if` initializer the first `else` is the `if`'s, and
a further one is the binding's.

```
let found = find(4)
else {                       // continues the binding above
    return 1
}
let chosen = if ready { a }
else { b }                   // the `if`'s `else`
```

**[S-Nesting]** An expression, a pattern, or a written type nests at most
1000 levels deep. The limit makes acceptance independent of optimisation
level, debug settings and sanitiser use, and reports excessive depth instead of
overflowing the stack.

The limit measures syntax-tree height, not parser recursion depth. A chain such
as `a + b + c + …` is parsed in a loop but produces a tree as tall as the
chain, and chains of `.` selections behave the same way. Patterns and written
types share the limit. A pattern is one level below the construct that holds
it, a `match` for an arm's pattern or the statement for a `let`'s, and each
part of a pattern is one below the pattern it is a part of, so the binder `x`
in an arm `Some(Some(x))` stands three levels below the `match`. Depth is
counted from the type's source position: a type nested five levels inside
another construct has five fewer levels available, and terms earlier in a
chain add no depth above a type they do not enclose.

The limit is reported once per file. What stands past it is stepped over, up to
the end of the pattern, or of the expression's enclosing group or block, and
nothing inside it is reported again: a binder written there is bound, with no
known type, so a use of it is not [N-Undefined], and a name used there counts
as used, so it is not [N-Unused]. A control header stops at the brace that
opens its body, so the body is still read.

**[S-Paren]** A parenthesised expression or type, and a tuple, is closed.

**[S-Tuple]** A tuple has at least two components and at most eight, in a
literal `(a, b)`, a type `(A, B)` and a pattern `(a, b)`. `(x)` groups `x` and
is not a tuple; `(x,)` is refused; `()` is the unit value and type, the tuple
of no components. A component of a literal is an expression, of a type a type,
and of a pattern a pattern ([S-Match]). Components are separated by commas, and a
trailing comma is accepted after the second component or later.

**[S-Brace]** A block is closed.

**[S-Params]** A parameter is a name optionally preceded by a convention. A
lambda parameter may instead be a tuple pattern, `|sink (i, x)|`, whose binders
are locals of the lambda. Its type comes from the expected callable at its
position, or from the annotation written after it, and must be a tuple with as
many components as the pattern has binders ([T-Arity], [T-Mismatch]). The
convention decides how the pattern takes the argument apart, as it does for a
`let`: `sink` moves each component into its binder, so a linear component must
be settled there; `read`, the default, lends each component from the caller's
pair, which stays whole; `inout` lends each component writably. A pattern
parameter has no name, so a contract cannot refer to it and a call through the
lambda passes it by position. A declaration parameter is always a name, because
its name is the label a call writes; a pair is taken apart in the body with
`let (a, b) = pair`.

A declaration or structural callable parameter has a type separated by `:`. A
lambda parameter may omit its type only when an expected structural callable
type supplies it position for position. The lambda chooses its own local binder
names; conventions and defaults must match the contextual parameters. Direct
closure calls use those local names; calls through a structural callable or
generic callable requirement use the labels written where the callee was
declared ([T-Mismatch]). An omitted convention means `read` in every parameter
list; it does not inherit another convention from context.

**[S-Lambda]** A lambda opens and closes its parameter list with `|`, with `||`
as the empty list in prefix position, and is followed by one expression or
block body. A capture list may precede the parameter list:
`[threshold] |item: UInt8| item > threshold`. Capture declarations are
comma-separated `name` or `alias = place` entries in brackets; an omitted
capture convention means `read`. Explicit `read` before a capture remains
valid. An explicit invocation convention precedes and requires a capture list,
which may be empty. An omitted invocation convention means `read`, with or
without captures. Captures and parameters occupy the closure body scope;
capture sources are evaluated in the enclosing scope. `sink name` or
`sink alias = expression` initializes an owned capture, and `inout name` or
`inout alias = place` lends a place to the closure. An invocation convention
may be `read`, `inout`, or `sink`; capture conventions are `read`, `inout` or
`sink`.

Each lambda expression declares one source identity and therefore one unique
static closure type. Two identical spellings at different source positions are
different types. Inside a generic declaration that identity is applied to the
enclosing concrete type arguments, so each reachable enclosing instantiation
has its own concrete closure type and generated body. A lambda declares no type
parameters of its own.

**[S-Args]** An argument may name its parameter as `name` `:` `expression`.
Positional arguments form a prefix in declaration order. After the first named
argument, all remaining arguments must also be named. A misplaced positional
argument is diagnosed and retained in the parsed call; the parser does not
guess which parameter it intended.

**[S-Default]** A parameter may follow its type with `=` and an expression,
providing a default when a call omits that argument. `read` and `sink`
parameters allow defaults: a default is a constant that owes nothing
([T-Default]). `inout` requires the caller to supply the place. Defaulted
parameters form a suffix: every parameter after the first default must also have
one. A default on the wrong convention is diagnosed at its own `=`. A required
parameter after a default is diagnosed at the nearest earlier `=`. Both errors
preserve the parsed parameter list.

A default in a structural callable type is part of that type after it is
folded. Presence remains distinct from absence, while two constant expressions
with the same value name the same default.

**[S-Match]** A `match` contains a scrutinee and a brace-enclosed,
comma-separated list of arms. Each arm is a pattern, `=>`, and an expression.
A pattern is a variant name with an optional parenthesised list of patterns, a
type name with a braced list of `field: pattern`, a tuple pattern `(a, b)`
([S-Tuple]), a literal or range, or `_`. The patterns inside one -- in a
variant's or newtype's parentheses, a tuple's components, or after a field's
`:` -- are patterns of the same grammar, so `Some((name, port))`,
`(Some(a), None)`, `Ok(Point { x, y })` and `Err(Read(Limit))` are patterns
([ADR 0224](adr/0224-a-pattern-nests-wherever-a-binder-stands.md)). Inside a
pattern a bare name is read by its case ([N-Case]): a lowercase name or `_`
binds the part it stands at, and a capitalised one is a variant, matched with
its payload unnamed. An inferred struct pattern `{ a, b }` may stand inside
another pattern. A part is a pattern and never an expression: nothing compares
a part against a value but a literal or a range.

```
match load(step) {
    Ok(Some(value)) => value,
    Ok(None) => 0,
    Err(Read(Limit)) => 1,
    Err(Read(Closed)) => 2,
    Err(Parse(_)) => 3,
}
```

A range-pattern bound must be an optionally negated integer literal, a string
literal, or a name: either bare or a path to a declaration's constant
([ADR 0059](adr/0059-one-table-answers-both-questions-about-a-constant-expression.md)).
Other forms violate [S-Range], as do chained ranges and open range ends. Both
`0..=9` and `9` normalise to closed intervals. For integer matches, [T-Cover]
reports uncovered intervals. [T-Unreachable] reports an arm covered by earlier
arms, an empty backwards range, or a `_` after intervals that cover the whole
type. A pattern interprets a range as an interval, so backwards bounds match no
values; after `in`, the same bounds describe a downward walk.

A string literal used as a range end, in an expression or a pattern, converts
to its Unicode scalar number if it contains exactly one scalar. The expected
integer type determines the result type, with the same default as an integer
literal when context supplies none. Thus `"a"..="z"` denotes that letter
range. A literal containing more than one scalar remains `Str` and causes
[T-Mismatch] for the range. This conversion applies only at a range end: a
string literal standing alone in a pattern is `Str`, which over an integer is
[T-Mismatch]. No pattern compares text; over `Str` outside its module a literal
is refused at any depth by [M-Opaque], as the `match` taking one apart is.

`match read` observes the scrutinee without taking it apart: the value is
lent, as with a parameter's `read` convention. `let read` applies the same
lending to one irrefutable pattern over a place ([S-Destructure]).

**[S-Enum]** An enum declares a name and a brace-enclosed, comma-separated
variant list. Each variant is a name optionally followed by a parenthesised,
comma-separated list of payload types. A trailing comma is allowed. A variant
construction supplies its payload, as in `Shape.Circle(3)`, using the same form
as the declaration.

**[S-Struct]** A struct declares a name and a brace-enclosed, comma-separated
field list. Each field is a name, `:`, and a type. A trailing comma is allowed.

A type's braces contain only its representation. A function among its fields
is diagnosed with a reference to `impl`, where behaviour is declared
([§3.8](#38-visibility)). A field or variant takes no visibility or attribute
of its own: the type's reaches its parts. Each such misplaced member is
diagnosed where it is written, and the parts after it are still read.

**[S-Field]** A field requires a name and an explicit type; there is no
initialiser from which to infer one.

**[S-Mutation]** An argument to an `inout` parameter must carry `&`; an
argument to a `read` parameter must not. `&` marks possible mutation and the
associated exclusivity requirement at the call site. It does not take an
address or create a reference; the language has no reference values. `&` is
written in three places: before an argument, before a postfix call whose
receiver is `inout` (below), and at the head of a plain `for`, `for x in &it`,
where it marks the iterator the walk advances ([T-For]).

A postfix call whose receiver is `inout`, `inout self`, marks the receiver by
writing `&` before the call: `&counter.bump()` and `&list.push(x)` pass
`counter` and `list` for mutation exactly as `Counter.bump(&counter)` and
`Vec.push(&list, x)` do. The receiver is the place written before the
operation's name, so `&a.b.push(x)` lends `a.b` and `&items[0].push(x)` lends
`items[0]`; it must be a writable place and is exclusive during the call like
any argument passed `&`, so `&list.push(list.length())` is [N-Aliased]. An
`inout` receiver called without the marker, `list.push(x)`, is refused with the
marked spelling as the fix. A receiver that is `read` or `sink` takes no
marker: `&list.length()` is refused as `&` on a `read` argument is. The marker
binds to the first call after it, so in `&list.first().push(x)` it marks the
receiver `list` of `first`, and `push` takes what `first` returned. An `inout`
receiver that is not a place, such as the result of `fresh()` or of
`list.first()`, cannot be lent; the value is bound to a `var` first
([ADR 0170](adr/0170-a-marked-postfix-call-lends-its-receiver.md)).

Mutable callable invocation is `&callback(arguments)`. This marks the
invocation, not its resulting value as an inout argument: `inspect(&callback())`
passes the result normally. The marker binds to the first invocation after its
callable place, before arithmetic and following `?` suffixes. The callable
place must permit mutation and remain exclusive during the call. Read
invocation may be requested through this mutable interface; sink invocation
cannot. An inout callable cannot be invoked without the marker. A callable held
in a field is invoked through the selection in parentheses,
`&(machine.step)(input)`, since `&machine.step(input)` is a postfix call and
marks the receiver `machine` of an operation `step`.

**[S-Break]** `break` and `continue` appear inside a loop. Both name the
nearest enclosing loop of either kind, so a `break` inside a `while` nested in
a `loop` leaves the `while`. A closure's body is a function of its own: a
`break` or `continue` written in it cannot reach a loop outside the closure,
and its `return` and `?` leave the closure, not the loops around it.

Match arms may contain bare `break`, `continue`, or `return` without a block.
The arm's comma terminates the jump; it does not introduce an operand.

**[S-Chain]** Comparisons are not chained. `a < b < c` is not a program,
because the second comparison would be against the `Bool` the first produced.

**[S-For]** A `for` binds one name, or a tuple pattern of names, to elements of
a sequence: `for x in xs { … }` or `for (i, x) in xs { … }`. `in` separates the
binder from the sequence.

**[S-Range]** `..` and `..=` have the lowest precedence among value-computing
operators and cannot chain. `0..9..18` is invalid; neither `(0..9)..18` nor
`0..(9..18)` has a supported meaning. Both endpoints are required. Open ranges
such as `..b`, `a..`, and bare `..` have no consumer and are diagnosed at their
source location.

Parsing never fails. Where a construct cannot be parsed the tree records an
error node covering that region and parsing resumes at the next statement, so
one malformed construct does not consume the rest of the file
([ADR 0003](adr/0003-infallible-frontend.md)). A region already reported
produces no further diagnostic.

## §3 Names

**[N-Undefined]** A name refers to the nearest enclosing binding of that name
declared before it. A name with no such binding refers to nothing.

**[N-Unused]** A binding must be referred to, and so must a function: both are
declarations. A name beginning with `_` declares the value deliberately unused;
the prefix marks intent only, so such a name may still be referred to
([ADR 0014](adr/0014-unused-declarations-are-errors.md)). `main` is exempt,
because the runtime calls it.

A declaration determines whether a name refers to a local, a parameter, a
constant or a function; the syntax represents these uses uniformly
([ADR 0023](adr/0023-one-symbol-space-and-two-phase-resolution.md)). Whether a
name can be called or used as a value depends on the callable rules below.

A function is visible throughout the program, including before its
declaration, which permits mutual recursion. Parameters and locals are visible
only within the body that declares them.

**[N-Duplicate]** A name may be declared once. A duplicate is diagnosed at the
second declaration; later references retain the first declaration. Constants
and functions accessed through a type share its namespace, so a constant and a
function cannot have the same name. Associated constants have no separate
namespace.

A prelude name is not declared by the module that sees it, so a module's own
top-level declaration or `use` of that name shadows the prelude's in that
module rather than duplicating it ([§3.7](#37-modules)). Two such declarations
in one module are still a duplicate. A primitive type name is not a prelude
name, and redeclaring one remains a duplicate.

Type-parameter names must be unique within a declaration's parameter list,
whether on a function, type, trait or implementation. A value parameter list
names each parameter once too, whether it is a function's, a signature's or a
closure's, and a closure's capture aliases share its list. A pattern binds
each name once, whether it is a tuple pattern, a struct pattern, a variant's
payload or a `for` binder. In each case the first of a spelling keeps the name
and the second is reported where it is written. `_` binds no name, so any of
these lists or patterns, type-parameter lists included, may hold it any number
of times.

**[N-Case]** A declared name starts in the case its kind requires
([ADR 0189](adr/0189-a-names-case-is-part-of-its-kind.md)). A type, a trait,
an associated type, a variant and a type parameter start with an ASCII capital
letter: `struct Point`, `trait Sized`, `type Unit`, `alias Pricing`, `Light`,
`[T]`. Every other name starts with a lowercase ASCII letter: a function, a
projection, a traversal, a field, a parameter, a module constant or a constant
an `impl` declares, the name an `import` binds, and every name a body binds (a
local, a pattern's binder, a loop's binder, an `else` binder, a closure's
parameter and a capture alias).

A leading `_` marks a name deliberately unused ([N-Unused]) and does not count
towards its case, and neither does a digit: the case is that of the name's
first letter, so `_T` and `_2Big` are capitalised names and `_count` and
`_1light` lowercase ones. A name with no letter, such as `_` or `_1`, has no
case and is accepted in every kind. A capitalised name is never a value and a
lowercase one never a type. Because an operation and a field start with a
lowercase letter, a `.` followed by a capitalised name selects neither, which
[S-Continuation] reads.

A name is checked where it is declared, once. A name that restates another is
checked where the original is declared: a trait implementation's members and
settled types spell the trait's, a `use` spells the declaration it names, a
struct pattern's shorthand binder spells the field, and a capture written
without `=` spells the binding it captures. The primitive types are named by
the compiler rather than declared, and are capitalised. So is the one member
the compiler provides: a structural template's component descriptor has `Type`,
which names the component's type and is read only where a type is written.

Every element of an import's path names a module, its directory, and is held to
the same case as the name the import binds: `import Sub as sub` is refused at
`Sub`.

The diagnostic names the kind and suggests the name respelled. A capitalised
spelling joins the words of a snake-case name (`not_found` becomes `NotFound`),
keeping a `_` between two digits (`x86_64` becomes `X86_64`). A lowercase one
separates the words of a capitalised name (`MakeThing` becomes `make_thing`,
`XMLHttpRequest` becomes `xml_http_request`, `IPv4Addr` becomes `ipv4_addr`) or
lowercases one written wholly in capitals (`MAX_SIZE` becomes `max_size`). A
respelling that no program can declare, such as a reserved word or `Self`, is
named but not offered, and so is one that would be declared twice where the name
is (in its module, among its type's members, or in the list of fields, variants
or type parameters it was written in), since accepting it would trade this error
for [N-Duplicate]. A rename refuses a new name in the wrong case for the same
kind, with the same respelling.

**[N-NotCallable]** Only a function or a value whose type carries a callable
signature may be called. A unique closure type carries its lambda's signature;
a structural `fn` value carries its exact signature; a type parameter carrying
a structural callable bound carries that signature until an instantiation
supplies its concrete callable type; and `mem.Closure[S, A]` carries `S`,
whose defaults and conventions its calls follow, with the labels written in `S`
where the closure was declared.

**[N-NotAValue]** A local, a parameter, a constant and a pattern's binder name a
value. So does a function, wherever an expression is written: its name is a
value of a structural `fn` type whose calls are indirect. A test, an `extern`
and a projection are not values: a test is run only by the compiler, an
`extern`'s body is outside the program, and a projection names a place that a
bracket reaches.

A function is a top-level function with a body and an ordinary result. A public
function reached through a module and an `export` referenced within its own
module are values on the same terms. So is a function with a body declared in
an inherent implementation, reached through its qualified path
(`Inventory.list`, `stock.Inventory.list`). A method is a value with its
receiver as the first parameter, carrying the receiver's convention: `inout
self: Inventory` becomes an `inout` first parameter. So is a trait's operation,
reached through its trait (`Priced.cents`), with `Self` among its parameters.
Calling any function directly remains a call to its declaration rather than a
conversion followed by an indirect call.

A function is written over type parameters: its own, a generic inherent
implementation's head parameters, a trait operation's `Self`, and its trait's
parameters. Which instance a value names is settled in one of two ways.

Where one exact structural callable type flows inward, the value converts to it
at once. Its declaration signature must satisfy that contextual interface,
comparing outer parameters by position while allowing their names to differ.
Its result dependencies must fit the interface's `carries` upper bound, as for
a callable bound, so a function carrying fewer parameters than the interface
allows converts; retention contracts and the invocation convention must match
exactly. Matching the declaration's parameter and result types against the
interface selects every type parameter, list by list, and each selected
argument satisfies its bound. A parameter the interface leaves unselected is
[T-Infer]; two different types for one parameter are [T-Mismatch]. Conventions,
defaults, nested callable types and dependency effects retain their checks.

Where none does, the value has its declaration's signature (conventions,
defaults and contracts) and calls through it use the declaration's labels:
`let increment = add_one` holds a `fn(read UInt8) -> UInt8`, called
`increment(value: 1)` as the declaration is. Labels are not part of a type
([T-Mismatch]), so the value fits wherever a `fn` type naming its parameters
differently is written. Each type parameter of the signature is an **open
type**, settled by the value's uses as an open integer is ([T-Literal]): on the
first type it must equal, whether an argument of a call through the value, the
parameter or annotation the value flows into, or another open type it meets,
which it then becomes one with. An open type met by an open integer must be an
integer, and falls back to `Int64` with it when its body finishes. Settling is
equality; a type that later meets a different one is refused under that site's
own rule. A parameter still open when the body finishes is [T-Infer], and the
report names the parameter and the function type to write for it. Each settled
parameter must satisfy its bound, as [T-Bound] requires of a call. An argument
that was itself refused settles nothing, and the open type it met is not
reported again.

A trait operation's `Self` must implement the trait once it is settled. The
value names that implementation's member. Where `Self` settles to a type
parameter, the member is selected when the enclosing function is instantiated,
as a call through the trait's is. A settled reference written in the
operation's signature (`Self.Unit`) is read once `Self` is settled. An
operation the compiler provides, such as `Equatable.equals` at `UInt8`, is a
value like one a program writes, and so is one an array answers through its
slice view: the value views each array argument and calls the slice's
operation, as a direct call does. A member of an implementation of a trait is
reached only through its trait.

A lambda and a function value meet at the function's type: an `if` whose arms
are a name and a lambda gives the lambda the name's type, in either order.

A single-payload enum constructor also names a value in a structural callable
context. `Failure.Parse` selects its result explicitly; `.Parse` selects it from
the contextual callable result. Its parameter consumes the payload with `sink`;
`read`, `inout`, stable-address parameters and defaults are not admitted. Enum
payloads declare no parameter name, so the constructor adopts the contextual
name and named calls use that name. Payload and result context must determine
all enum type arguments and satisfy their bounds; where the payload parameter
and the result give one argument different types, the constructor is
[T-Mismatch]. The enum identity must already be known from the result head;
selection never searches enum declarations by variant name. A callback's known
payload can determine open arguments of that result before the enclosing call
finishes inference.

The constructor transfers its payload's owner dependencies into the selected
variant. Its promised callable contract must cover those dependencies; a
borrow-bearing payload cannot satisfy `carries()`. A contract targeted to the
selected variant is permitted. The resulting value uses the existing structural
callable representation and ordinary consuming-call rules. Nullary and
multi-payload constructor values are not admitted. Direct enum construction
keeps its ordinary rules.

Tests, `extern`s, types, traits and modules are not values and cannot be used
as standalone expressions, whether compiler-provided or user-declared: name
resolution checks the declaration's kind, not its spelling. Such a name has no
value type, so [T-Discard] does not apply to it; a function named alone as a
statement is a value, and dropping it is [T-Discard].

A namespace may still qualify a name: `Colour.Red` selects a variant without
using its enum as a value. The selected declaration must itself be a value when
used in a value position. `Measure.Item` selects an associated type, which is
not a value; `Measure.of` selects a trait operation, which is.

**[N-NotAType]** Only a type may have an `impl`. An invalid target is diagnosed
at the header rather than at every member.

A type argument named in brackets before a call must likewise be a type:
`nothing[count]()`, where `count` is a local, is diagnosed at `count`, and so
is a value that reads as no type, such as `3` in `"7".parse[3]()`. A named
literal's head must name a type. A local, function, trait or module written
there is diagnosed once at the head; it is still a use of that declaration, so
it is not also undefined or unused.

**[N-TypeAlias]** `alias Name = T` declares another name for the type `T`
([ADR 0194](adr/0194-an-alias-names-a-type-that-exists.md)). The alias is not a
new type: wherever a type is written (an annotation, a parameter, a result, a
field, a variant's payload, a type argument, a bound's argument, an array's
element) writing the alias writes `T`, with `T`'s identity and capabilities.
`alias Pricing = fn(cents: UInt64) -> UInt64` makes
`Closure[Pricing, SystemAllocator]` and
`Closure[fn(cents: UInt64) -> UInt64, SystemAllocator]` one type. `type Name = T`
is the declaration that makes a distinct type.

`T` is read in the module that declares the alias, so the names in it are the
ones that module can write. An alias is private, `internal` or `pub` like any
declaration ([M-Vis]); `pub alias` is reached as `module.Name` or brought in by
`use`. Like a re-export, an alias may preserve or narrow the reach of what it
names but not widen it: `pub alias Leak = Secret` over a private `Secret` is
[M-Vis] at `Secret`. It declares no representation, so `opaque`, `export` and
the type attributes are refused ([S-Entry], [M-Export]), and it is capitalised
([N-Case]).

An alias may declare type parameters, `alias Step[T] = fn(value: T) -> T`, each
with the bounds a declaration's parameters take. Writing `Step[UInt8]`
substitutes the arguments for the parameters in `T`, and the arguments must
meet those bounds ([T-Bound]). An alias is written with as many arguments as it
declares parameters, less those with a default ([T-ArgumentDefault]), so `Step`
alone and `Meters[UInt8]` are [T-Bound] as they would be for a structure. Every
parameter must appear in `T` ([N-Unused]), and `phantom` is refused
([T-Phantom]).

The alias is the same type in every other position a type's name is written. A
named literal's head and a pattern's head may be an alias, so
`Spot { x = 1, y = 2 }` builds a `Point` where `alias Spot = Point`. A generic
alias heading a pattern takes apart only the type it writes: `let Fixed { a, b }
= pair` with `alias Fixed[T] = Pair[T, UInt8]` refuses a `Pair[UInt16, UInt16]`
([T-Mismatch]). A call on an alias is the call on its type: `Points(3)`
constructs a `Score` where `alias Points = Score` names a newtype, and
`Cents(x)` converts where `alias Cents = UInt64`. A path through an alias
reaches what its type holds, at the alias's arguments: `Maybe.Some(3)` is an
`Option[UInt8]` where `alias Maybe = Option[UInt8]`, and
`Bytes.new_in(allocator)` opens the `Vec[UInt8, A]` an alias names. A generic
alias at the head of a path takes its parameters from the call: with
`alias SysVec[T] = Vec[T, SystemAllocator]`, `SysVec.new_in(allocator)` is
`Vec[?T, SystemAllocator].new_in(allocator)`, and `?T` settles from the expected
type or an argument as `Vec.new_in`'s does. What the alias writes is fixed, so
a call whose arguments give another type there is [T-Mismatch]; a parameter
nothing settles is [T-Infer]; the settled arguments meet the alias's bounds
([T-Bound]); and a variant through the alias is settled by the type expected. A
path writes no arguments of its own, so `SysVec[UInt8].new_in(allocator)` is
[N-NotAValue], as `Vec[UInt8].new_in(allocator)` is. An alias of a function,
array or borrowed type holds nothing to select ([N-TypeAlias]). An alias of a
function type bounds a type parameter as the function type written out would:
`F: Step + Release` where `alias Step = fn(value: UInt8) -> UInt8`, and
`F: units.Step` names one another module publishes. A bound naming an alias of
any other type is [N-TypeAlias], and so is an alias naming a trait.

An `impl` or `derive` head is the one place an alias is refused
([N-TypeAlias]): an implementation is written against the type's own
declaration, which is what coherence and `opaque` are decided by. The report
offers the type the alias names. The refused implementation adds nothing to any
type, and the refusal is its one report: a call to an operation it declares is
not reported missing as well, and the alias counts as used.

A part written through an alias is held to [T-PolyRec] and [T-InfiniteLayout]
exactly as the type it names written out would be: `v: Deeper[T]` with
`alias Deeper[U] = S[Option[U]]` grows `S`'s argument, reported where the alias
writes `S`, and `v: Again[T]` with `alias Again[U] = S[U]` holds `S` inline.

An alias may not reach itself through `T`, directly, inside an argument, or
through another alias: `alias Chain = Option[Chain]` and a pair of aliases
naming each other are [N-TypeAlias], reported once per cycle. A type that holds
itself is a `struct` or an `enum`.

A diagnostic reports the type an alias names. Where an expected type was written
as an alias, the label at that annotation or result names the alias and the type
it stands for.

**[N-Variant]** A variant is named through its enum: `Colour.Red`, or `.Red`
when context supplies the type. A bare `Red` cannot name a variant. A leading
`.` means that context supplies the type; this holds beyond enums, always
refers to a named type, and creates no unnamed type. A name at a `match` arm's
head names a variant of the subject's enum, so over a subject whose type is not
an enum, or not known to be one, it names nothing and is refused here; the
report suggests `_`, or the pattern that takes the value apart.

A postfix call can access **a type's inherent operations or operations of
traits it satisfies**. For example, `s.length()` calls an operation in
`impl Str { … }`, while `a.of()` calls one declared by a trait. Lookup
determines which kind it is. **A postfix call reaches an operation, never a
field.** Where `Door` has a field `width` and an operation `width`,
`door.width()` calls the operation and `door.width`, a selection that is not
called, reads the field. A field that holds a callable value is called through
the selection in parentheses, `(door.width)()`; parentheses around the receiver
alone, `(door).width()`, leave the postfix form intact. A field therefore never
stands in an operation's way, sealed or not: `ticket.seat()` reaches a public
operation `seat` from any module, whether or not `Ticket` has a field `seat`
that module cannot read
([ADR 0161](adr/0161-a-postfix-call-reaches-an-operation-never-a-field.md)).
The receiver is the operation's first argument and follows its convention; an
`inout` receiver is marked by `&` before the call, `&door.widen()`
([S-Mutation]).

**The type's own operation precedes a trait's.** Where the receiver's type
declares an operation the call could take and a visible trait it satisfies
declares one under the same name, the postfix form calls the type's own; the
trait's is reached written out, as `Shut.close(door)`. Importing a trait or
adding a bound can never change what an existing call runs. The call could take
the type's own operation when it is accessible from the call's module under
[M-Vis], its `impl` applies to the receiver's instantiation, and its first
parameter takes the receiver as the call passes it: from a borrowed door,
`peek(self: borrow Door)` takes the observation, `lock(self: Self)` reads the
door through it, and `open(self: Door)` takes no observation at all. An
operation the call could not take does not stand in a trait's way, and lookup
proceeds as if the type declared none: a private `close` in another module, a
`get` declared in `impl Box[UInt8]` when the receiver is a `Box[Bool]`, a
`close(code: UInt8)` inside `impl Door`, or an `open(self: Door)` called on a
`borrow Door` each leave the call to the trait's. Where no trait answers
either, the call is refused for the reason the type's own operation could not
be taken, not as an operation the type lacks: [M-Vis] for one out of the
module's reach, [T-Arity] for one taking no argument at all, and [T-Mismatch]
at the parameter for one taking something other than the receiver. Only a call
is refused so, and only a call is told of a trait out of scope that declares
the name: a selection that is not a call's callee, `let f = door.close`,
reaches a field or nothing. An operation the type declares is not a field of it
[T-UnknownField], whether or not a call could take it; the report names the
path that reaches the operation where a function is expected, `Door.close`,
qualified by the declaring module where this one does not name the type, and
says the receiver is the first argument where the operation takes one. A
receiver known only through a bound, `[T: Shut]`, declares no operations of its
own, so `item.close()` there calls the trait's
([ADR 0160](adr/0160-a-postfix-call-reaches-the-types-own-operation-first.md)).

**A bound brings its trait's operations into reach.** A trait named by a bound
on a type parameter, including every trait that trait requires, or by a `where`
clause in force at the declaration, is in scope for that parameter whether or
not the module names it: under `G: gauge.Gauge`, `G.zero()`, `level.reading()`
on a `G` value and `G.Unit` reach `Gauge`'s members with no `use gauge.Gauge`.
The bound reaches only the type it bounds, so a concrete type such as
`gauge.Tank` still reaches `Gauge`'s operations only through a `use`. A trait
reached through a bound counts with the traits in scope, so where it and
another trait answering the parameter declare the same name, the name is
[N-Ambiguous], and the report spells it through its module,
`gauge.Gauge.zero(…)`
([ADR 0187](adr/0187-a-bound-brings-its-traits-operations-into-reach.md)).

**A type's name reaches the operations of the traits it implements.** A name
written after a type's name that the type's own namespace does not hold (its
`impl` members and an enum's variants) names the operation of a trait in scope
that the type implements, with `Self` settled to that type: `Limits.default()`
is `Default.default()` at `Self = Limits`, `Money.from(1250)` is
`From.from(1250)` at `Self = Money`, and `UInt16.parse("8080")` is
`Parse.parse("8080")` at `Self = UInt16`. Any operation the trait declares is
reached this way, whatever its first parameter takes, and
`Account.of(account)` passes the account as the first argument. The type's own
operation answers first where this module may name it, so a type that declares
`default` itself reaches its own through `Tank.default()` and the trait's
through `Default.default()`, while a private `close` declared in another module
stands aside for a trait's, as it does for `door.close()`, and is refused under
[M-Vis] only where no trait answers. Where two traits in scope that the type
implements declare the name and the type declares none this module may name,
the name is [N-Ambiguous]. Where no trait the type implements declares it, the
name is [N-Undefined], and the report names a trait in scope that declares it
as the one to implement; where only a trait out of scope would answer, it is
[T-UnknownOperation] with the `use` that brings the trait into scope. A type
parameter reaches what its bounds promise the same way: `T.default()` under
`T: Default` is `Default.default()` at `Self = T`, whether or not the module
names the bound's trait, and a name no bound's trait declares is
[T-UnknownField]. A generic type takes the instantiation the expression is
expected to produce, as `let empty: Option[UInt8] = Option.default()` does.
Without a call, `Crate.default` is a function value, `Default.default` with
`Self` fixed.

Where an argument stands at a trait parameter that no argument deciding its own
type and no expectation settles, and `Self` implements the trait at exactly one
argument list, the parameter takes that implementation's argument, so the
literal in `Money.from(1250)` takes the integer type `Money` converts from.
This holds however the call is written: `x.op(1)`, `Trait.op(x, 1)` or
`Type.op(x, 1)`. Where several implementations answer, including one whose
trait arguments `Self` leaves open, the literal takes its default type, so
adding a second implementation can change which body a literal argument runs,
without a diagnostic. A trait
parameter no argument stands at is settled only by what the call is expected to
produce.

Importing a trait can make such a name ambiguous, as it can a postfix call: a
trait brought into scope that declares the name for the type turns an existing
`Limits.default()` into [N-Ambiguous], and the call is then written through the
trait. An import never changes silently which operation runs, and never displaces the type's own
([ADR 0186](adr/0186-a-type-reaches-the-operations-of-the-traits-it-implements.md)).

**A call may name its function's type arguments in brackets before its
arguments.** `"8080".parse[UInt16]()`, `nothing[Bool]()` and
`Shelf.empty[Str](shelf)` name the type parameters the function declares, in the
order it declares them, where otherwise the call's arguments and the type it is
expected to produce would settle them. The brackets hold type arguments where
the name in front of them reaches a function: a function named alone or through
a path, a trait's operation named through its trait or through a type that
implements it, `Crate.packed[UInt8](7)`, or an operation a postfix call
reaches. Otherwise they index what is in front of them, so `rack.steps[0](5)`
calls the element the field `steps` holds, as `(rack.steps[0])(5)` does.
Because a postfix call reaches an operation and never a field, `x.name[…](…)`
names type arguments exactly where `x.name(…)` would call an operation; where
`name` is neither an operation nor a field of `x`'s type, the call is
[T-UnknownOperation]. Behind a value, only brackets followed on the same line
by the call's `(` can hold type arguments, so `(x.items[0])()` indexes. **A
function named with type arguments and no call is the value of that instance:**
`let make = create[UInt8]` holds `create` with `P` settled to `UInt8`, and
`apply(pair[UInt8, Bool])` passes that instance where a function is expected.
The brackets are read as they are before a call, and settle their parameters
before any use of the value does. Brackets holding only types after anything
that is not a function, `values[UInt8, Bool]`, index nothing and are [T-Index].
A name that reaches nothing is reported once, as [N-Undefined] or the rule that
refused it, and its brackets are read as neither.

Naming them is optional. A call names every type parameter its function
declares or none, and one naming a different number is [T-Bound]. The
parameters of a generic implementation's head and a trait operation's `Self`
are not among them: the receiver or the path the call is written through
settles those. Each named argument must be a type ([N-NotAType]) and must
satisfy its parameter's bounds ([T-Bound], reported at the type written). It
settles its parameter before any argument is read, so an argument of a
different type is [T-Mismatch]: `same[UInt8](true)` names `T` as `UInt8` and
passes a `Bool`
([ADR 0181](adr/0181-a-call-may-name-its-type-arguments.md)).

**[T-UnknownOperation]** A postfix call `x.name(…)` must reach an operation:
one the receiver's type declares and the call could take, or one a visible
trait the type satisfies declares with `Self` first. A trait a bound on the
receiver names is visible for that receiver. A field named `name` does not
answer. Where the type has one the call's module can read, the report says so,
and where that field holds a callable value it spells the call that reaches the
value, `(x.name)(…)`. Where a trait out of scope declares the name, the report
names the trait and the `use` that brings it into scope, and so does a name
written after a type's name, `UInt64.hash(seat)`, that only a trait out of
scope would answer. The `use` names the trait through a module the file imports
that declares it or passes it on, spelled as that import binds it; where no
import does, it names the module enclosing a nested library module, as `std.io`
encloses `std.io.core` and passes its public traits on, and otherwise the
declaring module, together with the `import` that reaches it. Which module that
is depends only on where the trait is declared. Where a trait in scope
declares it only for other receivers, the report names that trait. Where the
type's own implementation declaring the name has a head the receiver does not
match, `c.send(v)` on a `Chan[Recv[UInt64, End]]` where `send` is declared in
`impl[T, N: Protocol] Chan[Send[T, N]]`, the report names the receiver's type
and the head as written. A call on a
sealed type reaches no part of its representation, so it is refused under this
rule and never under [M-Opaque].

A free function is not an operation of any type, so `n.double()` does not call
`fn double(value: UInt8)`. Where a postfix call's name reaches a free function
from the call's module (its own, or a public one of a module the file imports)
the call is refused under this rule, and the report writes the call that runs
the function, `double(n)` or `scores.double(n)`, where the function's first
parameter takes the value and the arguments that settles meet the function's
bounds; otherwise it names the function without a call. A call refused so names
the function and the import, so neither is reported unused, and so does a call
on a value whose type was already refused. A call that reaches an operation of
the same name names neither, and a function or import nothing else uses is
reported unused.

**[N-Shadowed]** A warning. A trait implementation for a type supplies an
operation under a name the type declares itself and a postfix call written in
the implementation's own module could take, so postfix calls on that type reach
the type's own and the trait's is reached only as `Trait.op(x)`. It is reported
once, at the implementation's member, and does not stop the build. An
implementation for every type, `impl[T] Shut for T`, names no type to ask, so
it draws no warning even where a type it covers declares the name. A member
whose body is only a call of the type's own operation, written `Door.close(x)`
or `x.close()` with the member's parameters in order, draws no warning either:
whichever one a postfix call reaches, the same code runs. This is how a type
keeps its own operation, callable without an import, and supplies it to generic
code through a trait.

**[N-Ambiguous]** A postfix call is ambiguous when two visible traits declare
the operation for its receiver type and the type declares no operation of its
own under that name. A name written after a type's name, `Meal.blank()`, is
ambiguous when two visible traits the type implements declare it and the type's
own namespace does not hold it. Either report writes the call through each
trait, `Starter.blank(…)` and `Empty.blank(…)`, and spells a trait the module
reaches only through a bound through its module, `gauge.Gauge.zero(…)`. The
same diagnostic applies to an associated type available through two applicable
trait keys, whether exposed by visible traits on a structural base or by
bounds: either different traits or one trait with different arguments, such as
`[C: Index[UInt64] + Index[FromEnd]]`. The compiler reports ambiguity rather
than choosing a trait. An explicit trait call, such as `Measure.of(a)`,
resolves a call; for an associated-type reference, retain only the intended
bound.

**[N-Aliased]** A place mutated by one argument must not overlap any place
accessed by another argument, whether that access mutates or only reads it.
Mutation includes both passing a place with `&` and assigning to it. Places
overlap when they share a root and one path is a prefix of the other; path
steps are treated as equal whenever they may select the same place. The check
uses only the arguments at each call site, without inference or lifetimes.

Mutation counts anywhere inside an argument. Both `f(g(&p), p)` and `f(&p, p)`
access one place twice, as does `f(p, { p.x = 9  0 })`: an assignment inside a
block still occurs within the argument. A variant's payloads and a structure
literal's values, its base included, are checked as one argument list:
`Counter { hits = next(&counter), ..counter }` mutates the place its base
reads.

An index is a path step, like a field selection. `a` is a prefix of `a[0]`, so
`f(&a[0], a)` accesses overlapping places. Two array indexes overlap unless
both resolve to different elements: `f(&a[0], a[1])` is disjoint, while
`f(&a[i], a[j])` may overlap. An unresolved index is treated as possibly
selecting any element. Indexing from the end uses the same rule: `a[^1]` and
`a[3]` select the same element of a four-element array, so `f(&a[^1], a[3])`
overlaps.

For a projection, `b[i]` refers to the place selected by the implementation's
path. That place may be any part of `b`, including the receiver itself, and an
implementation may ignore the index or map different indexes to one place. Two
indexes into the same container are therefore treated as overlapping even when
both index values are known; `f(&b[0], b[1])` overlaps.

**[N-Immutable]** A binding declared with `var` may be assigned again; one
declared with `let` may not. Mutability is a property of the binding rather
than of its type.

A projected place may be written only if its implementation permits it. An
assignment through `b[i]`, or a lend through `&b[i]`, violates this rule when
the implementation declares `read self`. The diagnostic points to that `self`
convention. §4.2 defines the access limit; this rule diagnoses writes that
exceed it.

A binding shadows an earlier one of the same name. The earlier binding is
unaffected and must still satisfy [N-Unused] on its own.

An assignment names an existing binding and does not introduce one, so it
resolves by [N-Undefined] like any other name: an assignment inside a block
reaches a binding declared outside it, and a shadowing binding is assigned
without touching the one it shadows. Assigning to a binding is not reading it,
so a binding only ever assigned still fails [N-Unused]. Both binding forms
require an initialiser at their declaration.

### §3.7 Modules

A module is a directory. Every `.lin` file directly inside it belongs to that
module and sees every other file's declarations, regardless of order. The
directory determines membership; source files contain no module declaration.

A compilation accepts a file or a directory as its entry. A file entry forms a
single-file module, so unrelated programs stored in one directory do not become
one module with multiple entry points.

```
import util.hash;
import crypto.hash as ch;
```

Dots in imports separate directories. Within the primary root, `util.hash`
names `util/hash` relative to that root, regardless of the importing module.
`std.hash` uses the standard-library root; no primary-root directory may
capture `std`. An import binds the path's last element, or the alias supplied
by `as`. An alias is required to import two paths with the same last element
into one file. The imported name is visible only in that file.

An imported name is shadowed like any other outer binding. In an expression
within the scope of a local, a parameter, a loop or pattern binder, a closure
parameter or capture, or a type parameter of the same name, the name is that
binding: inside `fn parse(text: Str)`, `text.find(":")` searches the
parameter. A `let`'s initializer precedes its scope, so `let text =
text.ParseError.Syntax(0)` reaches the module on the right. An `as` alias for
the same import still reaches the module. A type path, `text.ParseError` or a
struct literal's head such as `shapes.Thing { size = 2 }`, names the module
unless a type parameter of that name is in scope, because a local names a value
and never a type. A trait path, in an `impl` header, a bound or a `where`
clause, always names the module, because a type parameter is never a trait.

**[M-Import]** An import names a root-relative directory holding at least one
`.lin` file. An import path starting with `std` names the `std` dependency, the
library whose manifest gives it the name `std`, wherever it appears. It
therefore cannot name a primary-root directory even where one has that name;
such a directory is part of its program but no import reaches it. When the root
being compiled is itself the library named `std`, the path names that root's own
modules: a package is never its own dependency. An import path whose first
element is the name of a library the importing root depends on (below) names
that library's root module, and its remaining elements a directory beneath the
library's source; a directory of the importing root spelled the same way is not
reached. A directory beneath a root that holds a manifest of its own is another
root, never a module of the enclosing one, whether or not another root has
loaded it, and an import reaching it by a directory path is refused; where it is
a library the importing root depends on, the help names the library to import
it by. Only the importing root's own manifest
decides what a first element names: a library another root depends on leaves
this root's directories of that name importable, and an import that reaches
neither a dependency of this root nor a directory of it, but names a library
another root depends on, is refused with that said.

**Dependencies.** A manifest names the libraries its root depends on, by the
name every import of each starts with and the directory holding its manifest,
relative to the manifest that writes it:

```
{ "dependencies": { "shapes": { "path": "../shapes" }, "sqlite": { "path": "../sqlite", "extern": true } } }
```

Each dependency is its own root ([M-Vis]): its `internal` declarations stay
inside it, and it may name its own dependencies, which its consumer reaches
only by naming them too. A library two manifests name is one root, so a type it
declares is one type wherever it is named; a library is identified by the
directory it sits in as the filesystem resolves it, however a manifest spells
the path to it. A library's `source` names a directory inside the one holding
its manifest. A dependency and its consumer are compiled together from source,
and testing a root runs that root's tests alone.

**[M-Dependency]** An entry under `dependencies` names a library this root may
depend on. It is refused, at the entry in the manifest that writes it, when its
`path` holds no manifest; when that manifest does not say `"kind": "library"`;
when the library's own `"name"` is absent or differs from the entry's name;
when the name is `std`, or is written twice in one manifest; when the name
already names a library in another directory anywhere in the compilation; when
the library reaches itself through dependencies, the cycle named in the help;
when the library's `source` leaves the directory holding its manifest, or
shares modules with another root's source (they are one directory, or one holds
the other without the inner root's manifest between them); or when the library's manifest grants `extern` to any of its modules and the
entry does not consent with `"extern": true`, or the entry consents and the
manifest grants nothing. The program links every root's `extern`
declarations, so the primary root's manifest also names every library in the
graph whose manifest grants `extern`, with `"extern": true`, however deep it
sits; the primary root's entry through which such a library is reached is
refused until it does. A refused entry is left out of the compilation, and an
import naming it reports nothing further.

Root-relative imports may form cycles. Names can refer across a cycle in either
direction, independent of declaration order. An import cycle does not imply
infinite layout; a cycle in value containment does, and [T-InfiniteLayout]
rejects it regardless of the declaring modules. A directory identifies one
module regardless of how many routes reach it.

**The prelude** is the standard library's root. Its public re-exports are in
scope in every module without an explicit import. It publishes two groups of
names. The first is what the language's syntax requires:

| Name | Syntax requiring it |
| --- | --- |
| `Str` | a string literal has this type |
| `Range` | `lo..hi` constructs this type |
| `Option` | `?` propagates this type |
| `Result` | `?` propagates this type, and an entry point may return it |
| `Display` | `{}` uses it for rendering, as does an entry-point failure |
| `Debug` | `?` in a format spec selects diagnostic formatting in interpolation |
| `Sequence` | `for` obtains an iterator through this trait |
| `Iterator` | `for` requests each next item through this trait |
| `Equatable` | `==` calls this trait |
| `Comparable` | `<` calls this trait |
| `Steppable` | `..` uses this trait to step |
| `Index` | `a[i]` accesses this trait's projection |
| `FromEnd` | an index counted from the end has this type |
| `Tuple2` | `(a, b)` constructs this type |
| `Tuple3` | `(a, b, c)` constructs this type |
| `Tuple4` | a tuple of four components constructs this type |
| `Tuple5` | a tuple of five components constructs this type |
| `Tuple6` | a tuple of six components constructs this type |
| `Tuple7` | a tuple of seven components constructs this type |
| `Tuple8` | a tuple of eight components constructs this type |

**The core vocabulary** is the second group. No syntax requires these names;
they are the traits and types most programs write in signatures and bounds:

| Name | Declared in | What it is |
| --- | --- | --- |
| `Release` | `std.release` | a value's one ordinary consuming operation |
| `Equivalent` | `std.cmp` | equality that is reflexive, symmetric and transitive |
| `Ordered` | `std.cmp` | a total order consistent with that equality |
| `From` | `std.convert` | a total conversion defined on its destination |
| `Into` | `std.convert` | the same conversion called on its source |
| `TryFrom` | `std.convert` | a conversion that returns `None` when the value does not fit |
| `TryInto` | `std.convert` | the same conversion called on its source |
| `Default` | `std.default` | the value a type starts from |
| `Allocator` | `std.mem` | the source of owned storage |
| `Vec` | `std.mem` | a growable sequence owning its storage |
| `String` | `std.text` | growable text owning its storage |
| `Writer` | `std.io` | the sink `Display` and `Debug` write to, also re-exported by `std.fmt` |
| `Protocol` | `std.session` | a type naming what one end of a session does next, and its dual |

All other library names require an import of their module. Membership in the
first group follows from the syntax; membership in the second is a decision
about the vocabulary
([ADR 0179](adr/0179-the-prelude-holds-the-core-vocabulary-and-yields-to-a-module.md)).
Collections without a syntax of their own, such as `collections.Map`, and a
library area's own vocabulary, such as `http.Observer`, stay behind their
imports.

A prelude trait is a visible trait in every module that does not shadow its
name, so a postfix call reaches its operations wherever a type implements it,
and so does a name written after the type's name: `Limits.default()` and
`Money.from(1250)` need no import. Where a type declares an operation of the
same name, the type's own is called and [N-Shadowed] warns at the
implementation; where another visible trait also declares the name for the
receiver, the call is [N-Ambiguous] and is written out as `Release.release(x)`.
`Into` and `TryInto` are implemented for every type through their blanket
implementations, so a program trait declaring `into` or `try_into` makes a
postfix call of that name ambiguous on every receiver.

A module's own top-level declaration or `use` of a prelude name shadows the
prelude's binding in that module and is not [N-Duplicate]. The syntax that
requires a prelude name finds the prelude's declaration by identity, not by
name, so shadowing never changes what the syntax means: a string literal is
still the prelude's `Str`, `?` still propagates the prelude's `Option` and
`Result`, interpolation still renders through its `Display` and `Debug`, and
`==`, `<`, `..`, brackets and `for` still call its traits. A module that
shadows one of these names reaches the prelude's declaration through its
module, as in `result.Result[UInt8, Str]` after `import std.result`, and an
entry point may return that spelling.

A derive list names traits as every other name is written, so where a module
declares its own `Release`, `@derive(Release)` names that trait and the
standard library's is written `@derive(release.Release)`. A derived
implementation reaches the prelude's declarations by identity: a module that
declares its own `Result` or `Option` still derives `Debug`, `Display` and the
other standard traits.

**[M-Embed]** An embedded path names a regular file inside the root of the
code that writes it. The path is relative to the directory of the writing
file, and is one or more names separated by `/`. It may begin with a run of
`..`, each naming the directory above, but may not climb above the root: the
directory holding the program's or library's `linea.json`, or, for a file no
program's source holds, the file's own directory. A program whose source sits
in `src` therefore embeds `../templates/page.html` from `src/main.lin`, and the
standard library embeds only files under its own directory. The path is
refused when it is empty, begins with `/`, has an empty part (`a//b`, `a/`),
holds a `.` part, a `..` after another name, a backslash, a NUL byte or a `:`,
or climbs above the root. It names no file when no entry is spelled exactly as
it is, byte for byte, including letter case on a filesystem that ignores case;
when any directory on the way, or the file itself, is a symbolic link; when it
names a directory or anything but a regular file; and when the file holds more
than 16 MiB (16 777 216 bytes), which is refused before the file is read.

Because no link below the root is followed, a path whose spelling stays inside
the root stays inside it on disk. The root's own directory is not inspected, so
a program reached through a link above it is unaffected. A file is read once
per compilation however many expressions name it, and the code emitted for a
program depends on the bytes it embeds and not on where the file sits.

**[M-EmbedText]** A file embedded with `embed` is UTF-8 text, checked as a
source file is ([S-Encoding]), because a `Str`'s bytes are valid UTF-8. A file
of any bytes is embedded with `embed_bytes`.

### §3.8 Visibility

A declaration is private, `internal`, `pub`, or `opaque`. Private is the
default; broader visibility must be explicit.

```
pub fn open() -> UInt8 { 1 }
```

**[M-Vis]** A private name is accessible only in its declaring module. An
`internal` name is also accessible to every module in the same loaded root. A
`pub` or `opaque` name is accessible to every importing root. The primary
program or library, the standard library and each dependency library are
distinct roots; sharing a compilation or filesystem ancestor does not merge
them. Visibility is checked at qualified accesses such as `a.open()`, where an
import binds `a`.

`pub use m.Name;` binds and re-exports an imported module's public declaration.
`internal use m.Name;` exposes it to modules in the same root. Both bind the
original declaration as an alias, preserving its identity and nominal type
regardless of which spelling is used. A re-export cannot rename its target: it
always binds the path's last element.

Visibility is checked at each `use`. An alias may preserve or narrow its
target's visibility, but cannot widen it. Re-exporting a private name or using
`pub use` for an internal name violates [M-Vis]. A missing declaration or an
unimported module violates [M-Import].

Public re-exports are exempt from unused-name checks because they provide
access for unloaded roots. Private and internal aliases are checked.

**[M-Entry]** A library declares no entry point. A root whose manifest names it
a library and which declares `main` is refused where the `main` is written,
`pub fn main` included; so is a dependency whose root module declares one. This differs from [S-Entry], which requires a program
entry point.

A manifest says what its root is: `"kind"` is `"program"` (the default) or
`"library"`; `"name"` names a library, and the name `std` makes the root the
standard library every program depends on, so only a library may take it;
`"extern"` lists the modules granted [M-Extern]'s capability, each spelled as
an import inside the root names it (`"store"`, `"io.core"`), with `"."` for the
root module. A grant of another shape, or one naming a directory of the root
that holds no source, stops the command before anything is checked. The
standard library's manifest is
`{ "kind": "library", "name": "std", "extern": ["fmt", "fs", "io.core", "mem", "net", "scalar", "time"] }`.
`"native"` lists C sources, relative to the manifest, that a build compiles
with the same `cc` at the same level and links into the program, and `"link"`
lists libraries the build links, each a name `cc` takes after `-l`
(`["sqlite3"]`). Either requires an `"extern"` grant, since only a granted
module can call what they build. A library may name both, its sources relative
to its own manifest: a program builds and links the C of every root it loads,
its own first and then each dependency's in the order the dependency graph
numbers them; a source named twice is built once, and libraries keep each
manifest's order, named again wherever another manifest names them. A
dependency granted `extern` is loaded, and its C built, only where its
consumers consent ([M-Dependency]).
Whether a
root is the standard library is read from its manifest and never from its
directory's name or location.

A type's braces contain only its representation: struct fields or enum
variants. Behaviour is declared in `impl` blocks, which may appear anywhere in
the declaring module, with no limit on their number.

**[M-Impl]** An implementation must be declared in a module that owns its type
or trait. An inherent `impl` names only a type and therefore belongs in that
type's declaring module. A trait implementation may be written in either the
type's or the trait's declaring module.

A module may thus implement its own trait for a foreign type, or a foreign
trait for its own type. It may not implement a foreign trait for a foreign
type. A callable type has no declaring module either, so a trait is implemented
for one only in the trait's own module.

Primitives have no declaring module; the standard library owns their type side.
It alone may declare an inherent implementation such as `impl UInt8 { … }`. The
loader identifies the standard library, so a program directory named `std` does
not gain that authority.

Unit is also declared by no module, but grants no type-side owner. A trait may
be implemented for `()` only in the module declaring the trait. An inherent
`impl ()` therefore has no owner and is [M-Impl], including in the standard
library.

Other modules may implement a trait for a primitive only if they declare that
trait: `impl Show for UInt8` belongs in the trait's module, never a third
module. A foreign trait's operations are reached through the trait, or through
the type's name where the trait is in scope and the type's own namespace does
not hold the name.

A declaration attribute applies exactly to the type braces it precedes.
`@opaque` controls representation access; `@linear` and `@copyable` select
ownership policy. These attributes do not affect functions, which are declared
separately; applying a representation modifier where no representation follows
violates [S-Entry].

```
struct Account {
    id: UInt8,
}

impl Account {
    pub fn open(id: UInt8) -> Account { .{ id = id } }
}
```

A type is a namespace. Its `impl` declarations are accessed through its name,
as in `Account.open(7)`, and follow [M-Vis]. Exporting the type and exporting
its members are separate decisions. `impl` has no visibility of its own; each
public member needs its own `pub`. An `impl` may be in a different file from
its type declaration because all files of a module share one namespace.

**There is no receiver.** A member sees the module's declarations and its own
parameters, just as a top-level declaration does. It has no implicit instance.
In the example, `id` inside `open` is the parameter; a bare field name would be
undefined.

A member does not enter module scope, so a type member and a module declaration
may share a name. Two members of one type may not: [N-Duplicate] applies across
all of that type's `impl` blocks.

Primitive integer namespaces expose the compiler-owned properties `min` and
`max`, each with the receiver's integer type. Concrete properties such as
`UInt8.max` are constant expressions and require no standard-library
declaration. A symbolic `T.min` or `T.max` requires Integer evidence and is
evaluated from the instantiated type's range; while `T` is symbolic, these
properties are not constant expressions or parameter defaults. Bool, the
floats and nominal newtypes do not inherit integer range properties. Declaring an
inherent member named `min` or `max` for a built-in integer violates
[N-Duplicate].

Other primitive members are declared by the standard library. Several library
modules may write inherent `impl` blocks for one primitive, and [N-Duplicate]
applies across all of them. An undeclared member violates [N-Undefined].

A trait's namespace contains its declared signatures. Implementation members
enter neither that namespace nor the type's inherent namespace. Accessing a
missing member violates [N-Undefined]. An inherent member cannot substitute for
a trait member, nor can a trait implementation supply an inherent member. A
name after the type's name that its namespace does not hold reaches the
operation of a trait in scope the type implements, as described under the
postfix rules, so an implementation can make such a name reach an operation, or
make it ambiguous where another trait already answered, but never changes what
a name the type declares means.

**A type may be named through its declaring module** in every type position: a
parameter, return type, field, variant payload, binding annotation, array
element, newtype base, type argument or argument supplied to a trait by an
`impl`. `a.T` refers to that module's `T` and is subject to [M-Vis], just like
`a.f`. The head determines the interpretation: a module qualifies the following
name, which must denote a type or receive [N-Undefined]. `use a.T` makes the
same declaration available without qualification.

An implementation's type head must be a bare name, optionally applied to type
arguments, or Unit. This applies after `impl` in an inherent implementation and
after `for` in a trait implementation. `use` brings a foreign type into scope
for that head. Trait references may be qualified in every trait position,
including before `for`, in bounds after `:`, in template and derive targets, in
supertraits and in trailing predicates.

Head lookup checks `Self` first, then an enclosing type parameter, then an
imported module. Thus `T.Item` inside `fn f[T: Carry]` resolves through `T`'s
bound regardless of neighbouring directory names. `Self` is defined by the
language and cannot be supplied by a scope.

A settled reference also uses a dot, but selects a trait member through an
implementation or bound. A path beginning with a module first selects its
declared type; any further selection must use that type's bounds. A
module-declared type has no such bounds; bounds on associated types belong to
trait declarations, which are accessed through the trait's namespace.

A newtype construction is a call naming that newtype. Qualified forms
`a.Score(9)` and `a.Score?(9)` construct the same type as the bare forms made
available by `use`, with the same `opaque` restrictions. Pattern heads cannot
be qualified: the matched value determines the type being destructured.

A module name is visible only as a qualifier, never as a value. Using a bare
module name as a value violates [N-NotAValue].

A `pub` or `opaque` declaration satisfies [N-Unused] because an unloaded root
may access it. Private and internal declarations must satisfy [N-Unused]
through use in the loaded modules, which include all their possible callers.

### §3.9 Opaque types

`opaque` exports a type's name while hiding its representation. Outside the
declaring module, values may be held, passed and returned, but cannot be
constructed from their parts, destructured, or inspected through those parts.

```
@opaque
struct Account { id: UInt8, balance: UInt8 }
```

**[M-Extern]** An `extern` declaration appears only in a module that its root's
manifest lists under `"extern"`; any root, program or library, may grant its
own modules. A dependency's grant takes effect only where every manifest
naming it, and the primary root's manifest, consent with `"extern": true` in
an entry ([M-Dependency]). A module the manifest does not list is refused. An
`extern` is private to its module: `pub` or `internal` on one is refused,
because another module calling C directly would be trusted with C too. The
granted module publishes ordinary functions that call it. The compiler
trusts an `extern` signature without inspecting its implementation, so the
grant bounds that trust to the modules a reviewer was told to read
([ADR 0068](adr/0068-a-declaration-may-name-a-symbol-the-runtime-provides.md),
[ADR 0171](adr/0171-the-standard-library-is-an-ordinary-library.md),
[ADR 0228](adr/0228-a-granted-module-calls-c.md)). A type marked `@unshareable`
is declared under the same grant, and one in a module the manifest does not
list is refused: only a module trusted with C can write raw storage under a
`read`, which is what makes a type unshareable
([ADR 0250](adr/0250-tasks-are-structured-through-linear-sessions.md)).

**[M-Foreign]** Only a module its root's manifest grants `extern` may use
`std.ffi`: import it, call any function or method `std.ffi` declares, or take
one as a value, whatever `std.ffi` value it is handed. A trait's operation
reached through one of `std.ffi`'s implementations, such as `release` on a
`CString`, reads no C memory and is not refused. A module that is not granted may
hold such a value and pass it on, which reads nothing. A granted module also
publishes none of its types, as an earlier and plainer report: no function that
is not private names one in its signature, no `pub use` or alias names one, and
no struct or enum whose representation another module can reach holds one in a
field or payload.
`std.ffi` holds what crosses to C as an address: `Bytes` lends a view's bytes,
`CText` is NUL-terminated text, `CTextList` is C's `char **`, and `CString`
owns text with a NUL after it. A `Bytes`, `CText` or `CTextList` is a copyable
newtype over the address whose dependencies originate at the value, as a
`mem.Slice`'s do, so a contract ties it to what it views: `ffi.bytes(text)`
carries `text`, and an `extern` answering a pointer into a handle declares
`borrows(handle)`. Their operations trust what C supplied, such as a length,
which is why they stay inside the module the grant names
([ADR 0228](adr/0228-a-granted-module-calls-c.md)).

**[M-Export]** An `export` declaration designates exactly one concrete foreign
ABI entry point. Six declaration forms are excluded.

- Only a **function** can provide an entry point; an `export` on a type,
  constant or trait cannot.
- A **generic** has no concrete entry point before instantiation.
- A **program** is entered through the compiler-generated wrapper for `main`
  and provides no foreign interface.
- An **`extern`** imports a trusted signature rather than defining a body to
  publish.
- A **`test`** is called by the compiler and omitted from shipped artefacts.

An export must also be in a library's **root module**, the interface available
to foreign callers; modules below it cannot be named externally. An export
below the root is diagnosed where declared. The published symbol uses the
declaration's name, matching the C header, and omits the prefix applied to
other Linea-defined symbols, so it must not collide with a runtime symbol.

A dependency's `export` is not exported. Only the root being built publishes C
symbols, so an `export` in a library a program depends on gives that program's
artefact no C-visible symbol: the program calls it as an ordinary `pub`
function, and none of these rules is asked of it. Building the library on its
own publishes it.

**[S-Export]** An `export` does not sit in an `impl`. It has a dedicated
diagnostic, as [S-Test] does, so the restriction is not obscured by a generic
message about permitted members. An export names a module entry point; a member
is accessed through its type.

**[M-Opaque]** A sealed representation is accessible only in its declaring
module. Within that module, construction and representation access follow the
ordinary type rules. Linea resolves `.Forged(7)` and `.{ id = 1 }` from the
expected type, without looking up a constructor in scope, so [M-Opaque] checks
every operation that accesses a representation:

- a variant named from context, `.Forged(7)`
- a variant named through its type, `a.Key.Forged(7)`
- a payload-free variant, `.Closed` or `a.Door.Closed`, which builds a value
  by being named, including as a constant or a default
- a structure literal, `.{ id = 1 }`, including one built from a base,
  `.{ id = 1, ..other }`
- a `match`, whatever its arms name
- a field read, `x.balance`
- a field assigned, `x.balance = 1`
- a contract path naming a field or variant, as a source, `carries(x.balance)`,
  a retention destination, `retains(x.balance: y)`, or a result target,
  `carries(.balance: y)`

A contract written in the type's own declaring module may name its sealed
fields, including in a public signature. Such a contract publishes the
dependencies of those fields to callers without giving callers any access to
them, so renaming or restructuring a field that a public contract names changes
that contract. A contract never settles, moves or releases a value: outside its
module, a linear opaque value is settled only by calling that module's
functions.

A `match` checks **the scrutinee's type**, including when its arms name no
variant. Thus `match k { _ => 0 }` is rejected outside the declaring module
even though the catch-all names no part of the opaque value.

**[M-Unused]** An import and a `use` must each be referenced. This diagnostic
is separate from [N-Unused] because the remedy is removal. A leading `_` still
binds the module or the `use` target and does not exempt it. The rule covers
both importing a module and importing one name with `use`. A `pub use` is
exempt because it exposes the declaration to other modules.

A `use` that binds a trait is exempt: a method call can use a trait without
naming it (`a.acquire(n)` requires `Allocator` in scope even if it appears only
in the `use`), and these calls are resolved after name resolution. Unused
aliases of types and functions remain diagnosed. An import or `use` that names
nothing is refused by [M-Import], and is not also reported as unused.

Prelude imports are exempt. The prelude imports every library module so its
implementations are loaded and available for lookup, and a module that only
provides implementations may export no name for the prelude to reference.
Other standard-library modules must reference their imports like any other
module.

An imported module's name is subject to [N-Duplicate] like any other
declaration in the file that wrote it.

## §4 Types

An expression receives an expected type **inward** from an annotation, the
entry point's return type, a conversion or a condition. An expression that
determines its own type supplies that type **outward**.

A parameter's declared type supplies the expected type for its argument. A type
parameter settled by another argument supplies the same context: in
`same(n, 1)`, where `n` is a `UInt8`, the literal has type `UInt8`, just as it
would for a parameter declared `UInt8`.

Arguments that determine their own types settle type parameters; arguments that
need an expected type are then checked against those settled types. Argument
position does not affect this process, so `same(n, 1)` and `same(1, n)` mean
the same thing. If nothing settles a parameter, the dependent arguments use
their defaults, so `same(6, 6)` is a call over `Int64`
([ADR 0092](adr/0092-a-settled-type-parameter-flows-inward.md)).

A condition receives its expected type from the language: [T-Condition]
requires `Bool`. This expectation can settle a call's result type when its
arguments do not determine it.

A postfix call passes its expectation to its receiver through the operation's
result. In `let p: Option[UInt64] = make().unwrap()`, the receiver `make()`
leaves its `T` open, and `unwrap`'s result is what the receiver's `Result`
carries on success, so the annotation settles `T`. The operation is found on
the receiver's type as its arguments left it, its own parameters are bound from
that receiver alone, and its result is matched against what the postfix call is
expected to produce, projected through a `?` or an `else` written around the
call, as `make().map_err(f)?` is. This supplies only what the receiver's own
arguments left open; an operation whose result mentions none of it, such as
`is_ok`, settles nothing, and the receiver is reported as [T-Infer] reports any
call nothing determines.

Branch arms determine each other's types in the same way as arguments. When an
`if` or a `match` has no expected type, an arm that determines its own type
supplies the expectation for completing arms that need one, whichever is
written first. A qualified variant of a generic enum with no payload,
`Option.None`, names its enum but not what the enum holds, so it needs one: in
`match r { Ok(_) => Option.None, Err(code) => Option.Some(code) }` the second
arm settles the first. An arm of type `Never` neither settles a type nor
participates in agreement, so `if c { panic("stop") } else { n }` has the type
of `n` in either arm order. If no completing arm determines a type, the arms
use their defaults together: `if c { 1 } else { 2 }` has type `Int64`. If no
arm completes, the branch has type `Never`. When arms disagree, the diagnostic
identifies the arm that needed an expected type and points to the arm that
supplied it.

**[T-Never]** `Never` converts to every known expected type, and no type
converts to `Never`. This bottom conversion emits neither an operation nor a
value: it says that the expected continuation is unreachable. A `Never`
expression therefore satisfies an annotation, argument, result, branch or
statement position once that position's type is known.

`Never` does not settle an open type parameter. In `choose(panic("stop"))`,
another argument, a result expectation or a declaration fact must determine
`T`; if nothing else settles the parameter, the call is [T-Infer]. `Never`
written as a type argument is a type like any other: the argument
`certain: Result[UInt8, Never]` settles `E` in `certain.is_ok()` as `Never`.
Only an expression whose type is `Never` leaves a parameter open.

Arguments that name their own type settle a call's type parameters first, in
any order. A leading-dot variant, bare or applied to its payload, names no enum,
so like a numeric literal or a contextual struct literal it takes the type the
other arguments settle: `assert_eq(code, .Some(9), message)` and
`same(.Some(9), code)` both type the variant as `code`'s enum.

Every expression whose local continuation is unreachable has type `Never`:

- `return`, after its optional value is checked against the function result;
- `break`, after its optional value is checked against the loop's result;
- `continue`;
- a `loop` with no reachable `break`;
- `panic(message)`;
- a direct or indirect call whose settled result is `Never`;
- a conditional, match or block whose every path fails to reach its
  continuation.

A parameter or local declared `Never` supplies no runtime value; reading it is
itself a `Never` expression with no continuation. Control transfers keep their
destinations: `break` reaches the loop join, and `return` reaches the caller.
Their type `Never` means only that execution cannot continue after the
transfer expression
([ADR 0106](adr/0106-a-non-completing-expression-has-type-never.md)).

A function declared `-> Never` has no normal path to the end of its body. A
normally completing tail or bare fallthrough is [T-Mismatch]. A direct call or a
call through `fn(...) -> Never` ends the caller's current block.

`panic(message)` is the only panic form. `panic` is reserved, cannot be
shadowed, and is neither a declaration nor a callable value. Its single
argument must have the canonical `Str` type published by the prelude; a
different type is [T-Mismatch]. The panic expression has type `Never`. The
message is evaluated exactly once; if evaluation does not complete, the outer
panic is not reached. Once the message is available, panic writes and flushes
standard error, then aborts without unwinding:

```text
linea: panic: <message> at <file>:<line>:<column>
```

The message is written by its recorded byte length, not as a C string or a
format string, so every byte is
preserved, including a zero or newline. The file, line and column identify the
written `panic` expression, so a panic inside a library operation reports that
library expression rather than an outer caller. It cannot be caught and runs no
deferred cleanup. Live Linear values are not leaks on the aborting path; values
consumed while evaluating the message follow the ordinary rules until the trap
is reached.

**[T-Mismatch]** An expression must satisfy its expected type. Integer types
have no implicit conversions, regardless of width or signedness.

A structural callable type is written `fn(parameters) -> Result`, optionally
preceded by `read`, `inout`, or `sink`; omission means `read`. Its identity
includes that invocation convention, the parameter count and, in order, each
parameter's convention, type, stable-address requirement, default presence and
folded default value, followed by the result type and normalized dependency
contracts. A parameter's name is not part of it: `fn(cents: UInt64) -> UInt64`
and `fn(amount: UInt64) -> UInt64` are one type, spelled in a message as
`fn(read UInt64) -> UInt64`, with a contract naming a parameter by its position
(`where carries(#1)`, where `#n` is defined with the contract rules). Every
component of identity is exact. The type has one code-pointer word of
representation and no runtime environment.

A parameter's name is a label a named call uses. A call to a declaration uses
the declaration's names. A call through a parameter, a field or an annotated
local uses the names of the type written there; through a parameter whose type
is a type parameter with one callable bound, the bound's; through a kept
closure `mem.Closure[S, A]`, those written in `S`. A call through a local with
no written type uses the names of what it was bound to (a function, a lambda,
another local, or a copy of one), and a capture takes its source's. A call
through a value nothing declared names for, such as a call's result or a value
joined from two arms, passes its arguments by position; a named argument there
is [T-UnknownParameter].

A message comparing two types prints both by position, as above, so what it
shows differing is what differs. A message describing one value, such as a hover
or a type to write, spells it with the labels a call through that value uses,
and by position where it has none.

Contextual conversion of an eligible named function or noncapturing lambda
checks conventions, types, defaults, stable-address requirements, invocation
and dependency contracts by position. Nested callable types are exact. There is
no variance between different signatures. For a generic declaration, parameter
and result positions both select type arguments. Disagreement is a mismatch; an
argument selected by no position cannot be inferred; each selected argument
must still satisfy [T-Bound]. Defaults are folded before selection or exact
comparison.

A lambda may write `-> ResultType` after its parameter list; its body and
explicit returns are checked against that type. Without a written result or an
expected callable signature, the body determines the result. The lambda keeps
its unique closure type; every parameter needs an annotation when no context
supplies it. Where an exact structural signature flows inward, it supplies
omitted parameter types and its result type is the expectation on the body. A
non-capturing lambda whose completed signature satisfies that interface then
converts to that one structural code-pointer type. A structural callable bound
supplies the same parameter and result context without erasing the lambda's
unique type, so two closures passed for one type parameter are two types, and
the call is [T-Mismatch]: the report says each closure has its own type and
names a type parameter for each, with the same bound. Callable-bound
satisfaction also compares outer parameters by
position, independently of their binder names. Label differences require no
runtime adapter and introduce no parameter or result type variance.

A callback parameter is one declared with a structural callable type or with a
type parameter carrying a callable bound. Both take part in the same call
inference; a structural parameter then converts its argument to the settled
structural type, while a bound keeps the argument's own type. When a callback
parameter has known input types and an undetermined result, its lambda body,
named function signature, or stored callable signature can determine the
remaining result parameters. A lambda's written parameter types settle the
callee's type parameters through the callback parameter's callable type before
the lambda's body is checked, as an argument whose own type is determined
does: with `fn start[P: Protocol, F: sink fn(sink me: Chan[P]) -> UInt64](sink
body: F)`, the call `start(sink [] |sink me: Chan[Worker]| me.id)` settles `P`
as `Worker`. A written type is read as an argument in its place: one that
disagrees with what an earlier argument settled is [T-Call] at the lambda's
parameter, and an argument after the lambda that disagrees with it is
[T-Mismatch] there, as between any two arguments. A type parameter whose one
callable bound fits the callback parameter's settles the callee's parameters
the same way: inside `fn launch[G: sink fn(sink me: Chan[Worker]) ->
UInt64](sink body: G)`, `start(body)` settles `P` as `Worker`. Known result
structure still supplies context to constructor payloads. Callback constraints within one call may supply another
callback's input types, independently of argument order; each body is checked
once, and runtime evaluation order is unchanged. A dependency cycle with no
known input does not infer types from the callback bodies. The completed
signature must still satisfy the callable bound, including its source promises.
A trait operation's callable bound may name `Self` and the types `Self`'s
implementation settles, `F: fn(sink reading: Self.Reading) -> U`; a call reads
the bound at the `Self` it settled, so `tank.reading_as(|sink r| r * 2)` takes
`r`'s type from `Tank`'s implementation.

Within a `Result`-returning function, each propagated `Result` supplies the
enclosing error type to open error types in its operand. A callback result is
open when its argument leaves it for context: a lambda without a written
result, or a leading-dot constructor. A type parameter that is the declared
type of an integer literal argument is open too, and takes the enclosing error
type where that is an integer type: in a function failing with `UInt16`,
`fail(5)?` settles `fail`'s error parameter on `UInt16`. A named function, a
qualified constructor, an annotated lambda, or a value with its own type fixes
the result, so propagating a different error converts through `From` or is
[T-TryAnswer], exactly as when the call is bound first and propagated
afterwards. Nested propagation applies that constraint at each corresponding
carrier depth. An open error type settles on the enclosing error type before
any conversion is considered, so a `From` implementation never makes an open
error ambiguous, and conversion applies only to an error type already known to
differ. The context does not cross an `Option` carrier or enter a lambda whose
own return type supplies its context.

**[T-Literal]** An integer literal takes its expected type. With none supplied,
its type is open, and so is the type of a range whose ends are both open,
arithmetic or negation over open operands, a group of an open expression, and a
`let` or `var` binding whose initializer is open.

An open type settles on the first integer type it must equal: an expected type
flowing into it, including a parameter or an annotation; the other operand of
an arithmetic or comparison operator; an assignment's target; a demand inside a
callback on a parameter whose type is open; the other end of a range; a sibling
array element; the key of the container it indexes, `UInt64` for an array; and
another argument settling the same type parameter. Two open types that meet
become one. Settling is equality: no integer type converts to another.

An open type still open when its body finishes becomes `Int64`. The body is a
function body, a constant's initializer or a parameter default, and a lambda
belongs to the body it is written in. A method call or field selection on the
value itself, a `match` on it, a conversion of it, and a generic argument
nothing else settles each need a type at once, and give it `Int64` there. A
method call on a value whose type only holds an open type, `(0..3).map(f)` on a
`Range` of literals, reads the call's receiver by its known head and leaves the
open type to the call's arguments, as a call of a generic function does:
`(0..3).map(|sink i| Row.of(i))` walks a `Range[UInt64]` where `Row.of` takes a
`UInt64`. A `match` or `match read` on such a value, and a `let ... else` or
struct pattern over one, takes it apart by its known head in the same way:
`match Iterator.next(&pending) { Some(i) => total += i, None => ... }` over a
`Range` of literals binds `i` at the open type, which `total` then settles. A
`match` on the binder itself is a match on an open integer and falls back
there, so `Some(x) => match x { ... }` compares `x` as an `Int64` unless
something settled it first. A trait question about a literal's type is asked of
what the type settled on, whether an integer type or a type parameter. While it
is still open, it implements a trait exactly when every integer type does. The
same holds for a literal a closure captures: a closure capturing `let fee = 499`
is `Release` whether `fee` is still open or has settled on an integer type, and
is not when `fee` settled on a parameter `T: Integer`, which does not promise
`Release`. An implementation query that no implementation answers while an open
type stands in it gives each such open type `Int64` and asks again.

An open type that settled and then meets a different type is refused at the
second meeting under that site's own rule, with a label where it settled or
fell back. The literal's value must lie within the range of the type it finally
has; a value outside it is refused at the literal, labelled where the type was
settled. A negation or an arithmetic result folded over open operands is
checked the same way, as [T-Literal] and [T-Overflow].

When the expected type is a symbolic Integer parameter, the literal must fit
every admitted type: 0 through 127, the intersection of the eight integer
ranges. An explicit conversion supplies a runtime range check instead.

A float literal is typed the same way, among the float types: it takes its
expected type, and with none supplied its type is open, settled where it meets
a float type at the same sites an open integer settles, and `Float64` when
nothing settles it. The same operations that give an open integer `Int64` give
an open float `Float64`. An open float and an open integer never settle as one:
`1 + 1.5` is refused by [T-Operands]. A float literal converted to a float
type settles on that type, written bare, inside parentheses or under any
number of minus signs: `Float32(0.1)`, `Float32((0.1))`, `Float32(-0.1)` and
`Float32(-(-0.1))` each round the literal once, to `Float32`. Any other
operand of a conversion is typed before the conversion applies, so an open
float there falls back to `Float64`: after `let tenth = 0.1`, `tenth` is a
`Float64` and `Float32(tenth)` narrows it, as `Float32(0.1 + 0.2)` narrows a
`Float64` sum.

A float literal is rounded once, to nearest with ties to even, at the type it
finally has. The type must hold it: a literal that rounds to an infinity, or a
nonzero literal that rounds to zero, is refused at the literal, labelled where
its type was settled. Inexact rounding of any other value is admitted. A
literal too large for `Float64` is too large for every float type and is
refused before its type is known. A float literal is not a constant expression
under [T-Const]; arithmetic over float literals runs where it is written.

The `Float64` math methods are library operations and are not constant
expressions; their results, including the special values, are defined with the
standard library ([scalar/float.lin](../std/scalar/float.lin)). `Float32` has
no math methods. Both float types have `to_bits` and `from_bits`, which
reinterpret a float as the unsigned integer of its width and back, keeping
every bit, and `total_less`.

**[T-Convert]** `T(e)` explicitly converts its single argument `e` to the
primitive type named by `T`
([ADR 0018](adr/0018-the-integer-model.md)). A conversion uses call syntax.
Newtypes also use `T(e)` for construction under [T-Newtype]; struct and enum
type names are not callable ([N-NotCallable]).

A symbolic source or target with Integer evidence admits the same explicit
numeric conversions. The conversion is not a constant expression while either
numeric type is symbolic. `T(256)` is valid under `T: Integer` and traps when
evaluated at UInt8, while directly written `UInt8(256)` is rejected at compile
time. Explicit float endpoints remain permitted; this does not make a float a
member of Integer.

A conversion to a float is defined for every value and may round. An integer
outside the exact representable values of the target becomes the nearest
representable value, with round-to-nearest, ties-to-even. `Float64(x)` of a
`Float32` is exact. `Float32(x)` of a `Float64` rounds the same way; a finite
value beyond `Float32`'s range becomes the infinity of its sign, and NaN stays
NaN. A `Float64` value converted to `Float32` has been rounded once already,
so a decimal reaches `Float32` through it by two roundings; a literal written
in the conversion is rounded once.

A conversion from a float truncates toward zero. It traps if the target cannot
hold the truncated value, or if the input is NaN; NaN is diagnosed separately
from an out-of-range number. Float conversion is the only trapping operation
over floats; IEEE 754 arithmetic defines a result for every input.

**[T-Overflow]** An arithmetic operation's result must lie in the range of the
type it produces. Remainder follows the overflow rule for division: `a % b`
overflows whenever the quotient `a / b` is unrepresentable, even if the
remainder would be zero.

**[T-Operands]** Binary operands must have the same type, and arithmetic
operands must be numeric. The left operand determines the type and the right is
checked against it; a disagreement is diagnosed at the differing operand.
Aggregates, enum tags and `Bool` are not numeric. Unary `-e` also requires a
numeric operand.

A symbolic type needs Integer evidence at its declaration, including an
associated type constrained by a `where` predicate; an unconstrained parameter
does not defer that requirement to instantiation. A concrete float retains its
arithmetic rules.

Floats support `+`, `-`, `*` and `/`, but not `%`. Each operation is rounded
to nearest, ties to even, in its operands' type: `Float32` arithmetic is
binary32 arithmetic, with no wider intermediate. `Float32` and `Float64` do
not mix. Every NaN that arithmetic, a conversion between the float types or a
math method produces is the positive quiet NaN, whatever NaN went in, on every
target and at every optimisation level
([ADR 0249](adr/0249-a-float-has-a-total-order-and-a-computed-nan-is-canonical.md)),
and so is every NaN C hands a program: an `extern`'s result, a parameter of a
function C calls, and a value C writes through an `inout` parameter.
Negation flips the sign bit and nothing else, and copies keep every bit, so a
NaN's sign and payload are what the program made them. Integer `/` truncates toward
zero, and `%` is the remainder of that division, `a - (a / b) * b`, so a nonzero
remainder has the sign of the dividend. Floating-point remainder is a different
operation and does not share the operator. Float arithmetic requires no
checks: IEEE 754 defines a result for every input, including a zero divisor;
[T-Overflow] and the division rules apply to integers. There is no implicit
conversion between a float and an integer, in either direction: `1.0 + 1` is
refused by this rule.

An operand disagreement is [T-Operands] when no surrounding context imposed a
type. If a context supplies an expected type, both operands are checked against
it and a failure is [T-Mismatch].

Comparison takes two operands of the same type and produces `Bool`. The traits
declared by `std` determine which operand types are supported. Each of the six
operators is a trait call:

| written | means |
| --- | --- |
| `a == b` | `Equatable.equals(a, b)` |
| `a != b` | `!Equatable.equals(a, b)` |
| `a < b` | `Comparable.less(a, b)` |
| `a > b` | `Comparable.less(b, a)` |
| `a <= b` | `Comparable.less(a, b) \|\| Equatable.equals(a, b)` |
| `a >= b` | `Comparable.less(b, a) \|\| Equatable.equals(a, b)` |

An operand type missing the operator's trait implementation is rejected by
[T-Bound], which names that trait. The four ordering operators require
`Comparable`; its supertrait requirement also guarantees `Equatable`. Neither a
structural callable type nor a generated closure type implements `Equatable`.

`<=` and `>=` combine ordering **or** equality. Under [T-Logical], `||` calls
`equals` exactly when `less` returns false. `Comparable` defines a strict
partial order, so a pair may be ordered in neither direction while
`!less(b, a)` is true; negating the reversed comparison would give a different
result.

A `Comparable` type's inherited equality is symmetric and transitive, disjoint
from `less`, and substitutive for `less` on either side. Reflexivity is not
required: `Equivalent` adds that promise. An unequal pair that compares less in
neither direction is incomparable, and lexicographic comparison does not
consult later components after finding one.

Each float type uses this partial order. NaN is equal to nothing and ordered before
or after nothing: `less` and `equals` return false when either operand is NaN,
including when both operands are the same NaN. Thus `!=`, defined by negating
equality, is the only comparison that returns true for NaN. `Ordered` adds the
stronger requirements of a total order.

`total_less` is IEEE 754's `totalOrder` and is not `Comparable.less`: it orders
bit patterns, so `-0.0` comes before `0.0`, NaNs of one sign order by payload,
and the order runs from the negative NaNs through `-inf`, the negative numbers,
`-0.0`, `0.0`, the positive numbers and `inf` to the positive NaNs. Two values
tie only when their bits are equal.

The compiler provides primitive comparison implementations, which use the same
lookup and bound discharge as written implementations. A primitive belongs to
no module, so a module that implements a trait for one violates [M-Impl] unless
it declares the trait itself. The trait's module may write the head, but a
relationship already supplied by the compiler is [N-Duplicate].

**[T-Impl]** An implementation supplies exactly the members its trait
declares. Omitting a member leaves a trait call without an implementation.
Adding a member makes it unreachable: the trait namespace does not declare it,
and members of a trait implementation do not belong to the type's namespace.

A trait's operation written with a body is **provided**: every type
implementing the trait offers it, reached as any trait operation is, and runs
the trait's one body with `Self` settled to that type. The body is checked once
over the trait's symbolic `Self`, so it may call the trait's operations, itself
included, name the trait's parameters, and read the types an implementation
settles, `Self.Iter`, but nothing a particular implementation holds. A body
provided by a trait with parameters, `Scale[K]`, runs at the arguments of the
implementation it was reached through. An implementation does not supply a
provided operation, and one that does is refused under this rule. A member
refused for being there at all is dropped by the fix, so its body is not checked
for ownership: what it would return or keep is not a mistake of its own.
`Sequence` provides `map` this way:

```linea
pub trait Sequence {
    type Iter: Iterator

    fn iterate(sink self: Self) -> Self.Iter where carries(self)

    fn map[U, F: inout fn(sink item: Self.Iter.Item) -> U](sink self: Self, sink transform: F) -> Map[Self.Iter, U, F] where carries(self, transform) {
        .{ iterator = self.iterate(), transform = transform }
    }
}
```

`impl Index[I] for Wrapper via field` supplies Index's associated element type
and projection by delegation to one direct stored field. It occupies the whole
implementation: no member block or overrides accompany it. Only the standard
Index trait admits this form; delegation of another trait is [T-Impl]. Generic
heads, bounds and qualified trait references retain their ordinary rules. The
wrapper's defining module must declare the implementation under [M-Impl]; the
field's visibility does not change. Handwritten and delegated implementations
participate in the same coherence relation and neither overrides the other.

A trait with no members is satisfied by an empty implementation, such as
`impl Equivalent for Str {}`. A marker trait adds no operations; it promises
properties of the operations named by its bounds and carries those bounds.

Traits declare associated types as well as function signatures. A declaration
such as `type Item` requires an implementation member such as
`type Item = UInt8`. Omitting a declared type leaves it unresolved; defining a
type absent from the trait makes it unreachable through either namespace. An
implementation member must also have the declared kind: a function cannot
satisfy an associated type declaration, and a type cannot satisfy a function
signature. An associated type declaration that requires only a type to exist is
satisfied by any supplied type; function members are checked parameter by
parameter and by return type. A bodyless `type Item` in an implementation
supplies no definition and is a missing member.

A settled reference reads an associated type from the selected implementation.
`Self.Item` means that implementation's definition of `Item`. Inside an
implementation, it uses the enclosing implementation; in a called trait
signature, it uses the implementation selected for `Self`. A trait declaration
has no selected implementation, so its signature's settled references cannot be
checked against a concrete definition there; each call determines them.

A generic implementation defines associated types in its own parameters, which
the complete coherence key supplies. In `impl[T] Give[T] for Holder[T]`, a
definition `type Item = T` becomes `UInt8` for `Holder[UInt8]` and `Bool` for
`Holder[Bool]`, by the same substitution as fields of a generic type.

Inside a trait's braces, its associated type names may stand alone. A signature
written `-> Item` refers to the adjacent `type Item` and means `Self.Item`. A
bare `Item` outside the trait is undefined unless another declaration supplies
it.

A settled reference is a postfix selection from a written type. Its base may be
a name, application, grouped type, array or callable; `Wrapper[T].Item` and
`(Wrapper[T]).Item` select from the same applied type. `Self` selects through
its enclosing trait implementation. A bare type parameter requires a bound
declaring the selected member; it cannot acquire one by searching
implementations. Chained selections use the preceding associated declaration's
bounds while its result remains opaque.

For a known structural base, visible trait declarations can supply the member
through ordinary implementation selection under the enclosing constraints.
Exactly one associated declaration and complete trait key must be determined. A
trait-only parameter that cannot be inferred from that base remains
undetermined; the desired result type does not guess it. No applicable key or
missing bound/member is [T-Impl], and more than one applicable key is
[N-Ambiguous]. Visibility and opaque representations retain their ordinary
rules. Argument lists on associated types are [T-Bound], because associated
types declare no parameters; module-qualified nominal types still take their
ordinary arguments.

The shared written-type nesting bound includes selections, and an incomplete
suffix is recoverable [S-Type]. A name absent from the trait cannot be selected,
regardless of implementation members; an operation name is not a type. `Self`
without an enclosing implementation is [N-Undefined]. Its opaque structural step
remains part of [T-PolyRec]'s measure even when a known implementation could
settle it.

A settled reference through a type parameter is opaque while the generic body is
checked once; each instantiation determines its concrete type. Values may be
bound, moved, passed and returned, but the body may assume no fields, variants
or operations beyond those promised by the associated type's bounds. A bound
that only declares the type's existence promises no operations. Capability
bounds are checked at each associated type definition and therefore apply to
references to that type: `type Iter: Copyable` permits a body to copy and drop
`S.Iter` without knowing its concrete type. Without a capability bound, the
reference is noncopyable and potentially requires settlement, as an unbounded
type parameter does.

The exception is an implementation headed by a bare parameter that the type
parameter's bounds select, `impl[I: Iterator] Sequence for I` for
`I: Iterator`. Coherence admits no other implementation of that trait any
instantiation could reach, so the reference is that implementation's definition
while the body is checked: `I.Iter` is `I`.

Each instantiation settles a reference using its type arguments. Lookup uses
the trait named by the bound, the supplied trait arguments and the concrete head
type: the unique coherence key. The reference then reads that implementation's
associated type definition. Thus `fn measured[T: Measure](v: T) -> T.Item`
called with a `Counter` returns the type defined as `Item` by `Counter`'s
implementation. Fields use the same substitution: in
`struct Holder[W: Measure] { v: W.Item }`, the field of `Holder[Counter]` uses
`Counter`'s definition, and the field of `Holder[Flag]` uses `Flag`'s. These
instantiations are distinct types. A field of a type with no parameters may
name a concrete type's settled reference, `struct Sample { reading:
Celsius.Reading }`, and holds the type that implementation defines.

A settled reference retains the arguments of its declaring trait bound. A type
may implement a parameterized trait at different arguments and define the
associated type differently in each: `fn first[C: Lookup[UInt64]](c: C) -> C.Elem`
selects `Elem` from `Lookup[UInt64]`, not from `Lookup[Range[UInt64]]` for the
same type. Arguments may remain open: `[I, C: Lookup[I]]` carries `I` into
lookup and each instantiation supplies its concrete type.

A parameter without a trait bound supports no settled reference. With several
bounds, the reference uses the one whose trait declares the name:
`fn measured[W: Measure + Show](v: W) -> W.Item` takes `Item` from `Measure` if
`Show` declares no such name. A name absent from all bounds is unresolved. A
name declared by two distinct bound traits is ambiguous and rejected; there is
no qualification syntax to select one, and a parameter bounded by only one of
them avoids the ambiguity. Repeating a trait at identical arguments still gives
one bound, so `[W: Measure + Measure]` permits `W.Item`. Different argument
lists are distinct bounds with independently defined associated types:
`[C: Lookup[UInt64] + Lookup[Bool]]` cannot resolve `C.Elem` through either.
Source order never selects a bound.

An associated type definition cannot use a settled reference: `type Item =
Self.Other` would define one associated type through another in the same
implementation; reading another implementation's is described below. An
implementation defines each associated type exactly once; duplicate definitions are [N-Duplicate].

What a part, a settled type, a delegated element or an alias names never
depends on the order declarations are written in: each is decided once, after
everything it names is decided. A type's parts may not depend on the type's
own capabilities. A capability question asked about a type -- whether it can
be copied or discarded -- whose answer depends on one of its parts, or of the
parts it owns, that names a settled type and is being decided because of
that question, is [T-Bound]: `struct Tray { held: Chooser[Tray].Out }` with
`impl[T: Discardable] Pick for Chooser[T]` asks whether `Tray` can be
discarded in order to decide `Tray`'s part. The part may name the settled
type in any way: written, through an alias, or through a parameter's default,
`held: Holder` with `struct Holder[T = Chooser[Tray].Out]`. Writing the
part's type removes the question. The cycle may close through an
instantiation: `type Item = Ch[W[S]].Out` with `struct W[T: Tr] { v: T.Item }`
asks whether `W[S]`, which holds `S.Item`, can be discarded, and is refused at
the settled type. Each part is refused whose cycle remains once the parts
already refused read as nothing: two parts asking about one holder of both
are two errors, and two types whose parts ask about each other are one. A question the type's declaration answers
is not refused: a type not declared `copyable` is never copied, and one
declared `linear` is never discarded. A recursive type whose parts name no
settled type, such as `struct Node { log: Ledger[Node] }` with
`Ledger[phantom T: Discardable]`, is answered from its written parts under the
rule for recursive types.

**[T-AnswerDepth]** A chain of declared answers passes through at most 1000
links, where a link is a settled reference (`S1.Reading`, `B.Elem`,
`Chooser[S1].Out`) or an alias. A settled reference counts where it is
written and also where a template's is read at an argument: `type Item =
H[S1]` with `struct H[T: Tr] { v: T.Item }` reads `S1.Item`. A reference read
through a parameter's bounds, `T.Item` itself, reads no other answer and is
no link. Parts, the
members and delegations a reference reaches, and capability questions add
none. The count is the most
links any answer rests on, so it is the same in every declaration order. A
chain of 1000 settled references, each implementation settling `Reading` to
the next one's, is accepted, and one of 1001 is refused where the chain
starts; so are delegations, aliases and parts selecting through one another's
capabilities. A plain chain of 1001 aliases is refused as well. As with
[S-Nesting], the limit makes acceptance independent of optimisation level and
stack size, and reports the depth instead of overflowing. Writing a type
directly anywhere along the chain shortens it.

A definition may read another implementation's settled type, `type Dual =
Pong.Dual`, and means what that definition means, whichever implementation is
written first. A definition that reads back to itself through such references,
`Ping.Dual` reading `Pong.Dual` reading `Ping.Dual`, or `type Dual = Echo.Dual`
inside `Echo`'s own implementation, defines no type and is [T-Impl], reported
once per cycle at the definition on it written first, naming each definition
and the type it is written as. The reference may sit inside an argument:
`type D = Option[B.D]` with `type D = Option[A.D]` is the same cycle. A
definition that only reads into such a cycle is that report's consequence. A
cycle that passes through a type's field rather than through definitions,
`type Iter = S[Box]` where `S[T]` has a field of type `T.Iter`, defines `Iter` as
an ordinary type; it is the layout of `S[Box]` that contains itself, and
[T-InfiniteLayout] reports it.

**[T-Dual]** An implementation of `Protocol` (`std.session`) for `X` names
`X.Dual`, what the other end of a session does while one end does `X`, and
`X.Step`, what `X` does next. It must satisfy two equations:

- `X.Dual.Dual` is `X`;
- `X.Dual.Step` is `X.Step.Dual`.

Each side is read through the implementations that answer it, one projection
at a time. A named protocol is compared by the dual its implementation names
and is never unfolded, so the check ends however protocols recur: a `Worker`
whose step is `Offer[Recv[Str, Worker], Send[UInt64, End]]` and a `Boss`
whose step is `Choose[Send[Str, Boss], Recv[UInt64, End]]` name each other as
duals and satisfy both equations. A pair that does not is refused at the
definition that breaks it: `Liar.Dual = Boss` with `Boss.Dual = Other` is
refused at `Liar`'s `Dual`, naming both definitions, and two protocols that
name each other but whose steps disagree, one sending `Str` where the other
receives `UInt64`, are refused once, at the `Step` written first, naming the
first part where the two differ. An implementation that breaks the first
equation is not also reported for the second. A named protocol's dual is
named: `type Dual = Recv[UInt64, End]` for a protocol whose step is
`Send[UInt64, End]` is refused, since the dual of that receive is a send and
not the protocol. A generic implementation is checked over its own
parameters: `impl[N: Protocol] Protocol for Quiet[N]` with `type Dual =
N.Dual` is refused, since its dual's dual is `N` rather than `Quiet[N]`.

**Dual normalisation.** For every `P` bounded by `Protocol`, `P.Dual.Dual` is
`P`, and `P.Dual.Step` is `P.Step.Dual`. [T-Dual] proves both equations at
every implementation, which is what makes them true for whatever settles `P`;
a generic implementation is checked through them, so `impl[N: Protocol]
Protocol for Fwd[N]` with `type Dual = Fwd[N.Dual]` and `type Step = N.Step`
is accepted. A generic function relies on them too, so
`fn same[P: Protocol](sink tag: Tag[P]) -> Tag[P.Dual.Dual]` returns `tag`
unchanged, and a call that settles a parameter `Q` as `P.Dual` reads `Q.Dual`
as `P`. A `Dual` defined through other definitions that never reach a type,
`type Dual = Pong.Dual` beside `type Dual = Ping.Dual`, is the definition
cycle above and [T-Impl].

An implementation supplies the trait's type arguments, as in
`impl Holds[UInt8] for Coins` for `Holds[T]`. A wrong argument count is rejected
before checking members.

An implementation may declare type parameters in the same position and with the
same bounds as a function. A generic nominal head applies a distinct, ordered
subset of those parameters, filling the constructor's full arity.
`impl[T: Display] Display for Option[T]` describes a family, one instantiation
for each admitted `T`, and `impl[A, T] Build[A] for Holder[T]` has receiver
`Holder[T]` while `A` is determined by the requested trait argument. `Self`
denotes that receiver, not the complete implementation parameter vector. A
concrete implementation declares no parameters.

Every trait implementation parameter must be recoverable from injective
structure in the receiver and requested trait arguments together. Nominal
applications, array elements, observation referents and callable signature
structure can determine parameters. An associated projection cannot be inverted
to recover its subject, and bounds alone determine no parameter. An undetermined
implementation parameter is [T-Impl]. The canonical complete key supplies
implementation arguments in binder declaration order to member checking,
dispatch and instantiation.

Unit is a concrete head and can carry trait-only parameters:
`impl[A] Build[A] for ()` determines `A` from Build's argument, while
`impl[T] Trait for ()` leaves `T` undetermined and is [T-Impl]. A parameter
absent from both receiver and trait arguments is refused. Arrays, callables and
parenthesized type patterns cannot be written directly as implementation heads,
though a parameter-headed family can match their types when its constraints are
satisfied.

Receiver arguments remain bare distinct parameters in their relative
declaration order. Partial patterns such as `Pair[T, UInt8]`, repeated
parameters such as `Pair[T, T]`, and reordered parameters such as `Pair[U, T]`
for binders `T`, `U` are refused. Inherent implementations and explicitly
marked defaults retain their own head rules.

A type's own implementation writes each declared parameter exactly once in
its head's arguments, at any depth: as a whole argument, an argument of a
named type, a tuple's component, an array's element, an observation's
referent, or a callable type's parameter or result. Every other position holds
a type naming no declared parameter, and an array's length names none.
`impl[P] Router[(), P]` is admitted, and its members belong to the
instantiations whose first argument is `()`; so is
`impl[T, N: Protocol, H] Chan[Send[T, N], H]`, whose members belong to every
endpoint whose protocol argument is a `Send`. "Once" counts every position the
parameter's name stands in as a type, the base of a selection such as `T.Dual`
included, and not its bounds or the block's `where` clause. A parameter
written a second time is [T-Impl] at the second position; one the head never
writes, or writes only as the base of a selection, cannot be recovered from
the key and is [T-Impl] as for any implementation.

A receiver matches a head by one structural walk: a nominal type matches the
same declaration and then each argument, a tuple, an array of the same length
and an observation match their own form and then their parts, a callable
matches the same invocation and the same convention at each parameter and
then each parameter's type and its result, and a declared parameter matches
whatever stands at its one position and is settled to it. Nothing is unified,
since no parameter has a second position. A receiver the head does not match,
through any observation of it, is not one of its instantiations, and a postfix
call that reaches a member only through such a block is [T-UnknownOperation].
Member names stay unique per constructor ([N-Duplicate]), whatever the heads,
so two inherent implementations of one type never offer two members for one
call
([ADR 0182](adr/0182-a-types-own-implementation-may-fix-its-type-arguments.md),
[ADR 0252](adr/0252-a-types-own-implementation-may-write-a-parameter-inside-an-argument.md)).

An ordinary trait implementation may instead use a declared parameter as its
entire head. `impl[S, D: Build[S]] Adapt[D] for S` recovers `S` from the
receiver and `D` from the trait argument. Every declared parameter must be
recoverable from that complete key, outside associated-type projections; a
missing parameter is [T-Impl]. A parameter head grants no type-side module
owner, so the implementation belongs in the trait's module ([M-Impl]); an
inherent parameter-headed implementation is invalid.

A structural callable type may head an implementation of a trait,
`impl[S] Handle[S] for fn(inout state: S, input: UInt64) -> UInt64`. It has no
declaring module, so the implementation belongs in the trait's module
([M-Impl]); an inherent implementation for a callable type is a parse error. The
head is written exactly as a callable type is, with its own parameter
conventions, result and contract, and the implementation's parameters are
recovered from it as from any other head. Coherence keys a callable head by its
**shape**: the invocation and each parameter's convention, in order. Two
implementations of one trait at one shape and one argument list are
[N-Duplicate], whatever types the signatures write, as two tuple heads of one
arity are, which refuses
`fn(x: UInt64)` beside `fn(x: UInt8)`; implementations at different shapes never
meet, and a callable head names at most 60 parameters ([T-Impl]). A function
value implements the trait where its signature matches the written head exactly,
contract included, binding the head's parameters: a function taking `read` where
the head writes `inout` does not match. A closure never does, because its type
is its own and not a structural signature; passing one where the trait is
required is [T-Bound].

Two implementations of one trait overlap if a substitution over both
declarations' parameters makes both their heads and trait arguments
structurally equal. Overlap between open headers is checked at declaration time
and rejected without ranking either declaration by specificity among ordinary
implementations. An explicitly marked default
occupies a separate fallback tier, described below. For example,
`impl[T] Give[T] for Holder[T]` and `impl[U] Give[Bool] for Holder[U]` agree
when `T = U` and both are `Bool`, so both would implement the trait for
`Holder[Bool]`. Parameters from different declarations remain independent even
when their names match. Open trait predicates do not prove two headers disjoint,
with one exception: a head that is a bare parameter bounded by a trait does not
overlap a constructor-headed implementation when no implementation of that trait
could answer for the constructor, since every implementation of the trait is in
the program. `impl[I: Iterator] Sequence for I` and
`impl[T] Sequence for Slice[T]` are disjoint because nothing implements
`Iterator` for a `Slice`, while an `impl Sequence for Pages` beside
`impl Iterator for Pages` overlaps the first and is refused. Integer is an
optional closed constraint on a parameter head, not a prerequisite for it. The
closed Integer constraint does exclude noninteger receiver constructors; its
domain is fixed by
the language rather than extensible through user implementations.

An overlap between a program's implementation and a standard-library
implementation is reported at the program's. The library implements `Into[U]`
for every `T` where `U: From[T]`, so a direct `Into` implementation overlaps
that bridge; a conversion is implemented through `From`.

Trait arguments may be independent of the head's parameters.
`impl[T, A] Index[UInt64] for Vec[T, A]` and
`impl[T, A] Index[FromEnd] for Vec[T, A]` are both valid: `UInt64` and `FromEnd`
are distinct ground types, so no substitution makes the trait arguments equal.
Ground types, including primitives and names from other modules, cannot change
under substitution; either declaration's parameters can. Settled references are
also open: their definitions vary by implementation, and distinct associated
types may be defined identically. A settled reference is therefore treated as
possibly equal to any type, so a given trait and head may have at most one
implementation whose trait argument is a settled reference, regardless of the
selected name: `impl[T: Pair] Give[T.A] for Holder[T]` and
`impl[T: Pair] Give[T.B] for Holder[T]` overlap because some `T: Pair` may
define `A` and `B` as the same type. This is a deliberate conservative
restriction.

An equation requiring a type to contain itself has no finite solution:
`impl[T] Give[T] for Holder[T]` and `impl[U] Give[Box[U]] for Holder[U]` do not
overlap, because matching their heads gives `T := U` and matching the arguments
would require `U` to equal `Box[U]`. Recursive instantiation of a declaration is
governed by [T-PolyRec]. By the same rule
`impl[T] Give[Pair[T, T]] for Holder[T]` and
`impl[T] Give[Pair[T, Bool]] for Holder[T]` unify at `T = Bool` and are rejected
([ADR 0081](adr/0081-an-implementation-is-generic-over-its-head.md),
[ADR 0093](adr/0093-two-implementations-that-could-answer-once-are-refused.md)).

Method discovery may find a parameter-headed family before every trait argument
is known. So may an implementation for the receiver's own head whose trait
arguments the receiver does not fix: `impl[P] Watch[P] for Tally` makes
`&tally.observe(true)` a call at `Watch[Bool]`, settled by its argument as
`Watch.observe(&tally, true)` is. This exposes a candidate name, not proof that
its bounds hold. The call's arguments and expected result must determine the
full key before implementation selection succeeds; missing target context is
[T-Bound]. Unrelated traits offering the same method remain subject to ordinary
name ambiguity, and discovery does not partially solve user predicates while
some implementation parameters remain unresolved, so an unrelated method can
require trait qualification even when a receiver-only user predicate would
eventually refuse the open candidate
([ADR 0148](adr/0148-parameter-heads-match-complete-trait-keys.md)).

Inside an implementation, `Self` is its head: **an instantiation with the
implementation's parameters still free**. Writing `Self` or `Option[T]` there
gives the same type. A call substitutes the complete implementation key, making
`Self` equal to `Option[Str]` at one call and `Option[UInt8]` at another.

An explicit `default impl[T: Bound] Trait for T { ... }` supplies a fallback for
a trait with no type parameters. It has exactly one implementation parameter,
used as the entire head. It may define ordinary functions and associated types;
it is not an inherent implementation, a template, or a delegated implementation.
Invalid default heads are [T-Impl]. Defaults must be declared in the trait's
module ([M-Impl]), and a second default for that trait is [N-Duplicate].

Ordinary implementations retain precedence by their structural key, before
checking bounds. A matching ordinary implementation whose bounds fail blocks the
default. Ambient implementations, conditional closure Release, declared trait
bounds and transparent observation forwarding keep precedence as well. Only when
those paths supply no implementation and no ordinary key blocks it does lookup
check the default's bounds. Defaults never rank two ordinary implementations or
make ordinary overlap legal.

A bare type parameter or unresolved associated-type projection cannot select a
default. A nominal generic receiver may select one only when its constructor has
no ordinary implementation of that trait. Generic code requiring query behaviour
therefore declares `K: Key` and uses `K.Query`; it cannot assume `K.Query`
equals `K`. For example, `std.hash` declares a default `Key` implementation for
`Hash` types, using the same type and equality for queries, so derived struct
hashes work as `Map` keys without a `Key` block, while `String`'s explicit `Key`
implementation continues to query with `Str`. The compiler recognizes neither
name ([ADR 0139](adr/0139-default-implementations-follow-ordinary-selection.md)).

An implementation function must match its trait signature's parameter count,
parameter conventions and types, and return type. Both sides interpret `Self` as
the implementation's head and substitute the supplied trait arguments. Parameter
names must match the signature, and the implementation member may declare no
defaults of its own: named arguments use the signature's names, and omitted
arguments use its defaults ([T-Default]).

A leading `_` on a member parameter may mark non-use under [N-Unused] without
renaming the signature's parameter. This applies only to the member: a leading
underscore in the bodyless signature is part of the callable name, and the
member cannot drop it. A member named `_` alone is rejected unless the signature
also names that parameter `_`.

A generic trait operation requires a generic implementation member. The member's
k-th type parameter corresponds to the signature's k-th parameter; their
declaration identities need not be identical. Corresponding member type
parameters must carry the same bounds: an added bound would let the body rely on
a requirement that no caller checks, a dropped bound would check the body
against less than the signature promises, and an added `Copyable` bound would
permit copying an argument without a caller ever proving it Copyable ([O-Copy]).
Bound comparison uses declaration identity. Repeated bounds resolving to one
trait represent one requirement, regardless of order or repetition; identical
spellings resolving to different traits represent different requirements.
Capability bounds are compared by the strongest requirement the complete list
demands ([T-Bound]); Copyable includes Discardable.

At most one ordinary implementation may answer a given trait declaration, trait
argument list and head constructor. Repeating the same implementation is
[N-Duplicate]; potential overlap between distinct open headers is checked as
described above. Distinct concrete trait arguments describe distinct
relationships, so `TryFrom[Int64] for UInt8` may coexist with
`TryFrom[UInt8] for UInt8`. Compiler-provided implementations also count when
detecting duplicates.

The head key uses the constructor. A generic implementation describes a family
of its instantiations; its own bounds determine which family members it
supports, but do not distinguish overlapping implementations or choose between
them. For any concrete trait arguments and receiver there is at most one
ordinary implementation; a default is considered only under the separate
fallback rules above. Specialisation among ordinary implementations is
forbidden.

Trait identity is declaration identity. Two modules may each declare `Measure`;
implementing one does not implement the other. Bound checking and call dispatch
use the declaration resolved at the reference's lexical site.

**[T-Template]** `template impl Trait { ... }` declares the sole structural
template for `Trait`. Every trait position accepts `trait_ref`, whose final
name resolves through any preceding imported module path. A template is not
itself an implementation. A template must belong to the trait's module, declare
one parameter per trait parameter, and apply those parameters to the trait
exactly once in declaration order. Parameter names may differ; their bounds must
match the trait declaration under positional substitution. A zero-argument trait
needs no template parameters. Specialized arguments and ordinary trailing
constraints are not admitted. A second template or a declaration outside this
form is rejected here.

An admitted template is either empty for a marker trait or supplies exactly one
function for every function signature the trait declares, matched by name, and
supplies nothing else. Each template function is checked against that signature
with an open symbolic `Self`, including its parameter count and names,
conventions, defaults, parameter types and result. Generic member parameters
match positionally rather than by name: each side has the same arity, and the
bound set on the member's k-th parameter is the signature's bound set after
reading that member parameter as the signature's k-th parameter. A member cannot
add or drop a bound, including a capability bound or a trait bound whose
arguments mention another member parameter. An ordinary trailing `where`
predicate on a template member is not admitted. Its body may refer to its
parameters, locals, `Self`, primitive and ambient names, and declarations that
are members of or re-exported by the trait module with reach at least as broad
as the trait: `module <= root <= public`. A file-local import is not such a
member. A template with another member shape, an unmatched or repeated function
or a narrower free reference is refused once here, whether or not any derive
names it.

A template may write `where reflect.components: Required + Other[Argument]`.
Each bound names a trait. Its explicit arguments may use accessible closed types
and template parameters, including nested applications justified by the
template's bounds. They are checked once in that symbolic scope and substituted
with each derive entry's trait arguments before discharge. `Self`, reflection
descriptors and member-local parameters are not admitted in requirement
arguments; capabilities and structural callable bounds are not traits. Every
trait application and nested type application supplies exactly the parameters
its declaration requires. One source component requirement containing any
invalid bound or argument is refused once here, however many bounds, components
or derives would read it. Name-resolution errors retain their own rule.

A component requirement applies to every component of every structural case:
all struct fields, each enum variant's payloads, or the single newtype base.
Every component must implement each listed trait at its written arguments. An
empty product and an uninhabited enum satisfy the requirement vacuously.
Repeated requirements retain source order and imply only their named traits.

A template may also state one `reflect.target: struct`, `reflect.target: enum`
or `reflect.target: type` requirement. It selects the target declaration kind;
`type` means a newtype. Repeated or malformed shape requirements are
[T-Template]. A target of the wrong kind is [T-Derive] for that entry, before
its generated bodies are checked. The requirement grants no construction
privilege.

The template-only requirement `reflect.supertraits: derived` requires derived
evidence for every direct supertrait. Both the target trait and its direct
supertraits must take no type arguments; a generic direct supertrait is rejected
once here. The predicate checks provenance. It neither requests a new
implementation nor adds a bound to the generated header.

Declaration attributes form a closed set. `@opaque`, `@linear`, `@copyable`,
`@carrier`, `@unshareable`, and `@derive(Traits...)` may be written separately or
as items of one `@(...)` group. Every group precedes the struct, enum, or
newtype it modifies, before ordinary visibility. An empty group, unknown item,
a repeated policy, `carrier` or `unshareable`, `linear` combined with `copyable`,
`unshareable` combined with `copyable`, an attribute before another
declaration, or `carrier` on a newtype violates [S-Entry]. `@unshareable`
marks a type that is not `Shareable` (§5.3); it states no ownership policy and
is declared only where [M-Extern] grants it. It excludes `copyable` because
copies of a value reach what it reaches: a copyable type reaches shared state
through a borrow of an `@unshareable` owner, whose observation every copy
carries, as `mem.Handle` borrows its `mem.Arena`. `@carrier`
marks a struct or an enum; it states no ownership policy and combines with
either. What it means is under the callable source clauses
([ADR 0216](adr/0216-a-carrier-type-supplies-its-signatures-default-contract.md)).
Bare `opaque`, `linear`, and `copyable` declaration prefixes are not accepted.

**[T-Derive]** A derive request is either a standalone bodyless declaration or
one `derive(...)` item attached to a nominal type. It is not an implementation
by itself. A standalone request may declare type parameters with inline bounds
and trailing `where` predicates, and may name one trait or a parenthesised group
of traits. An attached request uses the following type's parameter list and
written constraints, and adds the field requirements described below. Each
trait entry independently names a trait, its ordinary type arguments and its
structural template. A type requests each resolved trait taking no arguments
once across attached and standalone requests; aliases and qualified spellings do
not evade that rule. A trait with arguments may be requested once per argument
list, and two requests naming one implementation are refused as coherent
implementations are.

`@derive(From[S])` on an enum requests the implementation `From[S]` for it that
wraps the source in the one variant whose only field has type `S`
(`std.convert` declares the template with `reflect.wrap`). The entry names the
source, so no variant converts without being named, and each entry names one
conversion: two entries of one source are refused as two implementations of one
key are. A struct or newtype target, a source no variant holds, and a source two
variants hold are [T-Derive] at the entry; a conversion that does more than wrap
is written as an `impl`. The generated implementation is the same as a
handwritten one, so `?` finds it through the function's error type's `From`
([T-TryAnswer]) and `source.into()` through the `Into` bridge.

The derive request and its struct, enum or newtype target belong to the same
module. The trait and its template may belong to another loaded module. A
generic derive head fills the target's arity with distinct derive parameters in
relative declaration order; the derive and target parameter names need not
match. Additional derive parameters may be determined by trait arguments. Every
parameter must be recoverable from each entry's complete trait-and-target key,
independently. Bounds alone and associated projections do not determine a
parameter. Inline bounds and trailing predicates form the ordinary normalized
written constraint environment. A missing template, ineligible target,
malformed head or unsupported trait application is refused here for the
affected trait entry only.

For each admitted trait entry the template produces an independent ordinary
trait implementation in the target's module and copies each template function
into it. A foreign trait is reached through an ordinary generated import; a
same-module entry emits none. An empty marker template produces an ordinary
empty implementation; a function template produces ordinary members reached
through the trait's normal dispatch. One rejected group entry neither admits nor
rejects a sibling. Coherence and member compatibility apply to every generated
header exactly as to one written by hand, so a generated and a handwritten
implementation with overlapping keys conflict in the ordinary tier. Defaults
remain the lower selection tier.

Target substitution maps each target parameter to the derive parameter written
at that target position. Template substitution independently maps each template
parameter to the corresponding trait argument. For example, in
`derive[A, T] Build[A] for Record[T]`, Record's first parameter maps to `T`, not
`A`. Neither mapping uses the entire implementation binder list as target
arguments. A grouped entry may fail recoverability while a sibling succeeds: a
trait-only `A` in `(Release, Build[A]) for Record[T]` is undetermined for
`Release`. Expansion neither drops `A` nor edits the written constraints to
admit that entry.

Before checking generated bodies, the compiler applies those substitutions to
target component types and template requirements. Every component requirement
must then be discharged by the ordinary implementation relation under the
derive's normalized written constraints.

A standalone request states its whole environment: no bound is inferred for it
from fields, requirements or generated calls. An attached request on a generic
type instead makes its implementation conditional on its fields. For each struct
field or variant payload whose written type names one of the type's parameters,
the generated header gains one trailing predicate: that type, bounded by every
trait the template's component requirements name, at the entry's arguments.
`@derive(Equatable) struct Labelled[T] { label: Str, value: T }` therefore
implements `Equatable` for `Labelled[T]` where `T: Equatable`; a field
`tag: Tag[T]` contributes `Tag[T]: Equatable`, which asks nothing of `T` when
`Tag`'s implementation does not. Equal field types contribute one predicate. A
field naming no parameter, such as `label: Str`, and a phantom parameter, which
no field names, contribute none; such fields are checked once, at the derive, as
a standalone request's are. The type's own written bounds still apply at every
use, and a template with no component requirement adds nothing. The predicates
are ordinary implementation predicates: coherence, selection and diagnostics
read them as they read written ones, and a use whose field type lacks the trait
is [T-Bound] at the use, naming the field type that fails. When the type at the
use is sealed from there, the note names the sealed type's own parameter and
argument instead of a field type the reader cannot see. A field whose type is an
instantiation of a declaration that implements the trait for no arguments at
all, such as `items: Vec[T, A]` for `Equatable`, would leave an implementation
that never applies, so the derive is [T-Derive] at that field.

A derived `Release` settles each component, the last component first. Each
component is decided once, at the derive, under the derive's own constraints:
the type's written bounds for an attached request, the request's written
environment for a standalone one. A component whose type implements `Release`
there is released. One whose type is discardable there and not proven to
implement `Release` is discarded: it adds no requirement to the implementation
and is settled by `release.discard`, which runs nothing. Any other component is
released, which for a type naming a parameter is the field requirement above and
for a closed type is [T-Derive] at that field. So
`struct Pool[A: Allocator] { allocator: A, items: Vec[UInt64, A] }` derives
`Release` for every allocator: `A` is copyable because every allocator is, so
the allocator is discarded and the vector is released. A discarded component
whose type has an effectful `Release` at some instantiation is still discarded,
because the choice does not depend on the instantiation; bound the parameter by
`Release`, or write a standalone request, to release it instead. A discardable
component adds no `Release` requirement to an attached request whichever way it
is settled, so whether a component's type implements `Release` is answered
against every derive's final requirements, and the order of declarations never
changes the choice.

A diagnostic about generated code is reported at the derive's trait entry in the
program's source. Where the code was generated for one component, the diagnostic
also points at that field or payload and names it as the source spells it
(`Pair.first`, `Shape.Circle.radius`, `Slot.Held.0` or `Meters.0`), never by a
binding name expansion chose. Two such diagnostics that say the same thing about
the same source are reported once.

When derived supertraits are required, each direct supertrait must have an
ordinary implementation generated by a derive request for the same normalized
head. The dependent derive's written constraints must discharge the
prerequisite's constraints, independently of parameter spelling and source
order. Handwritten implementations do not count as derived evidence, and the
predicate does not create missing prerequisites. Grouped entries remain
independent requests; none implies another.

The first undischarged component requirement for one trait entry is refused
here. Its primary location is that exact trait entry in the derive; secondary
locations identify the field, variant payload or newtype base and the template
bound. For an open component type the diagnostic states that the written derive
environment does not prove the capability. Rows are considered in case order,
component declaration order and then template-bound order. Different group
entries report independently.

An invalid template requirement is reported once under [T-Template] and
suppresses every body generated from that template, including one for an empty
target. An undischarged valid requirement suppresses only the affected trait
entry's generated bodies. Suppression prevents causally downstream type and
ownership diagnostics but does not remove the generated header from coherence or
implementation lookup, suppress sibling entries, or skip unrelated bodies. A
prerequisite derive suppressed by its own failed component requirement remains
poisoned provenance evidence, so its own diagnostic is not followed by a
dependent provenance cascade. Every generated body that passes these checks
receives the ordinary ownership and call rules.

**[T-Reflection]** Structural reflection is available only inside a function
member of `template impl`. `reflect.case` is a pattern consumed by a `match`
arm and expands once for each structural case. Within that arm, a nested match
may use `reflect.same_case` for one named subject and an optional final
`reflect.other_case`; the former selects the enclosing concrete case and the
latter denotes all other cases. An independent `reflect.case` may not appear
while another reflected case is active.

A component loop must iterate over exactly `reflect.components` or
`reflect.components.reversed` inside an active reflected case. Component loops
cannot nest. The binder is one name, never a tuple pattern, and it is a
descriptor, not a runtime value. Its `of` operation takes exactly one argument
naming a subject matched by the active case or same-case arm. Subject identity
follows the resolved binding, not its spelling.

Inside an active case, `reflect.case.name`, `reflect.case.ordinal` and
`reflect.case.components_named` are respectively a `Str`, `UInt64` and `Bool`.
Inside a component loop, `component.name` and `component.ordinal` are a `Str`
and `UInt64`. Struct component names are field names; positional enum and
newtype components use the decimal spelling of their ordinal. Case and
component ordinals follow declaration order. `reflect.ordinal_of(value)` is
available only outside reflected cases and component loops and evaluates its
argument once before selecting that value's case ordinal.

`reflect.wrap(parameter)` constructs the one variant of an enum target whose
only field has the written type of the member's parameter `parameter`, applied
to the value `parameter` holds, as that variant's ordinary constructor does. It
is available outside reflected cases and component loops, in a template
declaring `reflect.target: enum`, and its argument is a parameter of the member.
The derive entry selects the variant: the parameter's written type is read with
the template's parameters standing for the entry's trait arguments, and each
variant of one field is compared with it as coherence compares the written
arguments of two implementations, so the names a type reaches decide and an
alias is the type it names. A variant with no field, several fields, or a
different type is not selected. No variant selected, or two, is [T-Derive] at
the entry; any other use is [T-Reflection].

Bare reflection roots, bare descriptors, unsupported selections, and descriptor
uses in any other position are refused. A `break` or `continue` may not target
a reflected loop; a transfer targeting an ordinary loop nested in its body
remains ordinary.

`reflect.construct(selector, |component| { ...; local }, { ... })` constructs a
target from declaration-ordered component recipes. The selector is
`reflect.product` for a struct or the active `reflect.case` for a struct or enum
variant. Newtypes are excluded, including active newtype cases, so construction
cannot bypass a constrained newtype's ordinary constructor. An invalid selector
or construction shape is [T-Reflection].

The recipe has exactly one unannotated descriptor and a block body. It has no
explicit captures, passing/callable convention, return annotation or contract.
Its descriptor exposes `name`, `ordinal` and written `Type`; `component.Type`
denotes the substituted field or payload type and is valid only in type
positions, without arguments. A construction descriptor has no observed subject
and therefore no `of` operation. A recipe's final expression must name a local
let, var or destructured binding declared directly in that recipe; parentheses
may group the name. Arbitrary expressions, the descriptor, outer bindings and
nested-scope bindings are refused under [T-Reflection].

Expansion places each recipe's top-level statements in one ordinary block,
renaming declarations and references by binding identity, shadows, shorthand
fields and capture sources included. Nested lambda parameter labels and capture
aliases retain their spelling; shorthand captures become explicit aliases when
their source is renamed. Expansion preserves outer bindings and gives each
component distinct locals. The finalization
block runs once after all recipes succeed and before the constructor consumes
each yielded local exactly once. It must fall through with unit under ordinary
[T-Mismatch] checking and cannot refer to recipe locals. Empty products skip the
recipe and still run finalization. Structs use contextual literals; an active
enum case uses its exact ordinary variant constructor and payload order.

A recipe's `?`, `return` or panic leaves the enclosing generated function along
ordinary paths; it is not a runtime callback. Written defers remain active
across later recipes and finalization. Success consumes the completed values
into the result and cancels their defers. Failure runs remaining defers in
reverse order. Expansion inserts no release, defer, default or rollback; missing
cleanup, moved results and dead defers receive ordinary ownership diagnostics.
Nested construction recipes and reflected component loops inside a recipe are
[T-Reflection]; ordinary nested blocks and loops retain their scope rules.

Template expansion erases every reflection operation: reflection roots,
descriptors and reflected control constructs do not reach type checking,
ownership or lowering. The generated body is ordinary source, and
`component.of` produces a place whose position determines whether it is read,
moved or mutated.

A struct has one named case whose components are its fields, an enum has one
case per variant whose components are that variant's payloads, and a newtype has
one named case whose sole positional component is its base. `.reversed`
reverses component order and nothing else. An empty struct retains an ordinary
`Empty {}` pattern, so a consuming match still consumes the zero-component
product as a whole. An uninhabited enum expands to `match value {}`; an ordinary
empty match is admitted only for a scrutinee with no values, `Never` or an
enum declaring no variants, has type `Never`, and ends that ownership path.
An empty match over any other type is [T-Cover].

**[T-Where]** A type predicate in a trailing `where` clause constrains a type
expression that depends on an open type parameter. The parameter may belong to
the declaration carrying the clause or to an enclosing generic scope. A concrete
subject such as `where UInt8: Copyable`, and a type predicate where neither
scope supplies an open parameter, are refused because they constrain no generic
declaration. Ownership contracts in a callable's `where` clause do not require a
generic parameter and are checked by [T-BorrowContract].

A trait's implicit `Self` is open on the same terms as a written parameter. An
implementation's `Self` is open only where its head depends on an open
parameter; a concrete implementation does not turn its head into a generic
constraint subject merely by spelling it `Self`.

Functions, bodyless function and projection signatures, structs, enums, traits
and implementations may carry the clause. Its subject may be a parameter,
another open type expression or an associated projection such as `I.Item` or
`Self.Error`. Its requirements are the existing bound grammar: named traits with
arguments, an exact structural callable type, a capability, or a `+` list of
them. The clause adds no type equality, negative, region or value predicate.

An inline parameter bound is shorthand for a constraint whose subject is that
parameter; both forms contribute to one per-declaration set of subject type
expressions and requirements. All constraints are collected before projected
subjects resolve, so predicate order is irrelevant: `where I.Item: Copyable,
I: Iterator` and its reverse define the same set. Resolving an associated name
requires a declaring bound in that set. No such bound gives the ordinary
unresolved-name error at the projection; two possible bounds give
[N-Ambiguous].

Instantiation substitutes a concrete type for each constraint subject, and
[T-Bound] checks every requirement. When a generic declaration passes an open
parameter or projection to a bounded position, its context must already promise
enough to discharge that bound, without waiting for a concrete instantiation.

Implementation predicates restrict the instantiations supported by the unique
implementation. They cannot distinguish overlapping implementations, rank
candidates or enable specialisation
([ADR 0107](adr/0107-a-trailing-where-predicate-constrains-any-open-type-expression.md)).

**[T-Bound]** A type argument must satisfy its parameter's bounds, and a generic
type must receive its declared number of arguments: all of them, or all but the
trailing parameters that declare a default ([T-ArgumentDefault]), in which case
the diagnostic says the type takes `N to M` arguments. A substituted `where`
subject must satisfy every requirement of its predicate. Applying arguments to a
type that declares none also violates this rule, and so does a call naming a
number of type arguments other than the number of type parameters its function
declares, as `double[UInt8](2)` does where `double` declares none.

Where the unmet requirement is `Discardable` written on a function's own `where`
clause for a subject the clause spells out, such as `Self.Iter.Item`, the help
says that the function may dispose of a value of the type, so it requires the
type to be Discardable, and the fix is to give the value to an operation that
keeps it or to settle it before. A bound written on a type parameter,
`[T: Discardable]`, states what the parameter must be and keeps the general help.

Where the unmet requirement is a trait, whether at a bound, at an operation
reached through `Self`, or at an operator, the help offers only edits the
program can make:

- For a type parameter inside a generic body, which implements only what its
  bounds promise, it offers adding the trait to the parameter's bounds.
- For a closure and `Release`, which a closure implements when every capture it
  owns does, it names the first capture that does not and offers the edit that
  capture's type needs.
- No `impl` head can name a closure's type or an array's type, so for those it
  says so and offers passing another value.
- When a module of the program owns a side of the implementation under
  [M-Impl], it offers implementing the trait, naming the modules that may write
  it when the module reporting the error may not.
- When neither side is the program's, as with `Ordered` and `Float64`, which
  the library declares, it says so and offers a type the program declares that
  wraps the type and implements the trait; [M-Impl] gives the same help where
  such an `impl` is written. For unit, a callable type or an observation, whose
  only implementations are the trait module's, it says that only the library
  may write one.

It offers dropping the bound only where the program wrote the bound, not where
the library or a derive did.

Where an implementation matches the type but one of its own requirements is
unmet, a note names that requirement, following it down to the last one unmet,
and implementing the trait again would overlap that implementation. The help
then names the edit that last requirement needs, under the same rules: a trait
to implement for a type, a bound to add, or `@copyable` to mark on a type the
program declares. A capability the library's type lacks cannot be added, and
neither can an implementation that would overlap one already matching the type,
as when the requirements never end; the help then offers another value.

The closed `Integer` bound admits exactly Int8, Int16, Int32, Int64, UInt8,
UInt16, UInt32 and UInt64. It excludes Bool, the floats, nominal newtypes and
user-defined types. It takes no arguments and cannot be implemented by a user. A
declared trait named Integer shadows the built-in bound and supplies only that
trait's ordinary promises. Inline, trailing and inherited Integer bounds provide
the same evidence. Every member is Copyable and Discardable, so the bound
entails those capabilities without changing the explicit-copy rule for authored
symbolic types. They are also Owned, so a value of an Integer-bounded parameter
carries no dependency (§5.3).

The `Owned` bound admits a type whose values can carry no dependency (§5.3). A
type argument for an Owned parameter must carry nothing, which is decided by the
type's representation, private fields included; a type parameter passed on
meets it only when it is itself bounded Owned. A trait named at arguments meets
its parameters' bounds the same way wherever a bound names it: on a type
parameter, in a `where` clause, in a supertrait list, on an associated type,
and in a trait signature at `Self` or `Self.Item`. The refusal names
a path from the argument to what it carries, such as a field holding a `Str` or
a `borrow`, through parts the program can select: it stops at a type whose
representation is sealed and at a newtype's base. Its help offers only edits
the program can make: adding `Owned` to the bounds of a parameter the path ends
at, or `where I.Item: Owned` for an associated type, and dropping the bound where
the program wrote it. `Owned` written twice on one subject is [T-Bound].
The `Shareable` bound admits a type two tasks may read one value of at once
(§5.3), decided the same way and refused the same way: the refusal names the
path to the part that is not shareable, such as a field holding a
`mem.Handle`, the `@unshareable` type it reaches, or the type parameter
not bounded `Shareable`. `Shareable` is written, promised in a `where` clause
and refused on an enclosing declaration's parameter exactly as `Owned` is.
`Owned` is written on a type parameter, inline or in its declaration's own
`where` clause, or in that clause on an associated type read through one of the
declaration's own parameters: `where I.Item: Owned` under `[I: Iterator]`, or
`where Self.Item: Owned` on a trait signature, whose `Self` is its own. On a
parameter of an enclosing declaration, such as an implementation's `T` written
in a method's `where`, in a trait's bound list or on an associated type's
declaration it is [T-Bound]: the promise would hold in declarations that never
made it. Since every `Integer` is `Owned`, `where I.Item: Integer` under
`[I: Iterator]` promises what `where I.Item: Owned` does, and a type holding an
`I.Item` there carries nothing. For the same reason `Integer` on an associated
type read through an enclosing declaration's parameter, such as an
implementation's `S` in a method's `where S.Item: Integer`, is [T-Bound], and
the help is to write it where `S` is declared.

`Copyable`, `Discardable`, `Linear`, `Integer`, `Owned` and `Shareable` are
decided by the compiler, and an implementation of one, such as
`impl Owned for Label`, is
[T-Bound]. A program that declares a trait of one of those names implements its
own trait.

An implementation head that applies arguments must supply exactly the number its
constructor declares. A head with no arguments on a generic type supplies none
of them, and is refused like any other use of that type without its arguments. A
type's own implementation writes its parameters, `impl[T] Cell[T]`, or fixes
arguments, `impl Cell[UInt8]` or `impl[P] Router[(), P]`.

Bounds are checked wherever a type is written or resolved, including
annotations, signatures, fields and payloads. Errors are reported at the use.
Passing an unbounded parameter to a bounded parameter is rejected at the
declaration that passes it, without waiting for an instantiation.

A trait bound is discharged by an implementation for the argument, or by an
enclosing declaration's parameter carrying the same bound. That parameter's
bound guarantees an implementation for every admitted instantiation, which
permits both type uses such as `Holder[S]` and calls through `S`.

A call through such a parameter takes the trait's arguments from its bound.
Where `H` carries exactly one bound on `Watch`, `H: Watch[P]`, a call
`&watcher.observe(event)` on an `H` is a call at `Watch[P]` before any argument
is read: a variant written without its enum, `.Retried(3)`, takes its type from
the parameter, and an operation whose parameters never mention `P` is still
settled. A parameter bounded on one trait at several argument lists leaves the
call's arguments and result to settle which list it means.

A bound may instead be a structural callable type. Its parameter and result
types must match exactly; result dependencies must fit the promised upper bound,
and retention contracts must match exactly. A `read` callable also satisfies an
`inout fn` requirement; `sink fn` requires a sink callable. This capability
relation does not change structural type identity or insert a function-pointer
adapter. A parameter carrying the required callable promise also discharges the
bound. It is not a trait, enters no implementation lookup, and grants no trait
transitively. A parameter carrying a named trait bound also carries every
callable promise that trait requires, including those required through another
named trait bound.

A generic implementation applies to the instantiations admitted by its bounds.
The complete receiver and trait-argument key binds the matching implementation's
parameters together, then those arguments are checked against its bounds. A
failure means the implementation does not apply and is diagnosed at the use.
Thus `Option[Str]` implements `Display` when `Str` does; `Option[Key]` does not
when `Key` lacks that implementation.

Implementation bounds use the same discharge rules. A capability bound is
satisfied by the argument's copying or settlement permissions; a trait bound is
satisfied by an implementation or an existing bound on that argument. For
example, `fn wrap[T: Show](h: Holder[T])` may pass `Holder[T]` to an operation
requiring `Show` when `Holder`'s implementation requires exactly `T: Show`. A
promise discharges only the bound it states.

Recursive prerequisite lookup requires progress. Re-entering an implementation
already active in the proof must strictly reduce the structural size of its
complete receiver and trait-argument key. Its size is the sum, over the receiver
and each trait argument separately, of distinct reachable type nodes. Traverse
applied arguments, borrow referents, array elements and callable parameter/result
types; symbolic parameters and unresolved projections are leaves. Nominal
storage fields do not contribute. Shared nodes count once per root, so a fixed
trait argument does not hide progress in the receiver. Exact, mutual and growing
cycles do not prove a bound and are [T-Bound], with one exception: an exact
cycle that passes through a derived implementation holds, whichever of its keys
was asked first, and the answer then rests on the requirements outside the
cycle. A derived body recurses only through the fields of the value it is given,
and a value is finite, so assuming the cycle admits exactly the recursive types
whose fields support it: `struct Tree[T] { value: T, children: Vec[Tree[T], A] }`
releases when `T` does, and so does `Vec[Tree[T], A]`. An answer that rests on a
cycle still being decided is not reused for any other question. Shrinking
container or trait-argument requirements may recurse. Failure of an ordinary
implementation's prerequisite does not enable a default.

Head arguments bind positionally. Bound checking examines the type supplied at
each position, not types or bounds nested inside that argument.

Associated type bounds are checked where an implementation defines the type.
`type Iter: Iterator` requires every definition, such as `type Iter = Counter`,
to supply a type implementing `Iterator`. A `Copyable` bound requires the
supplied type to permit copying; `Discardable` requires it to have no settlement
obligation. Each `Self.Iter` then reads the checked definition without
rechecking its bounds. Associated type bounds retain their trait arguments:
`type Elem: Lookup[UInt64]` requires a type implementing `Lookup` at `UInt64`; an
implementation only at other arguments is insufficient. A reference `C.Elem`
through `[C: Holds]` therefore discharges `Lookup[UInt64]`, but no other argument
list. These arguments resolve in the trait declaration's lexical context, where
neither the trait's own parameters nor `Self` is in scope for them.

A trait's own bounds constrain every implementing type and are checked at its
implementation. Trait arguments must match: `trait Fancy: Lookup[UInt64]`
requires `Lookup` at `UInt64`, and an implementation only at other arguments is
insufficient. Repeating the same trait bound behaves as it does for a type
parameter. A trait bound grants the trait's transitive requirements, preserving
the arguments written on each requirement: a parameter bounded by `Fancy`
discharges `Lookup[UInt64]` and no other `Lookup` argument list. Arguments
referring to the requiring trait's parameters are substituted from the bound
that reaches it. Trait bounds may not cycle; a cycle is diagnosed at its
declaration.

Capability requirements are inherited through the same transitive trait bounds.
`trait Replicable: Copyable` requires every implementation of `Replicable` to
permit copying, so a body with `T: Replicable` may explicitly copy lent values
and discard them. A trait requiring only Discardable grants abandonment without
duplication. Bounds with neither requirement grant neither permission.

Repeating an explicit capability bound, or explicitly restating one already
inherited through a trait, is rejected at the declaration. An explicit
Discardable bound is redundant when Copyable is already required. Linear adds no
capability requirement and cannot add information beside Copyable or
Discardable. `Owned` or `Shareable` written twice on one parameter, or beside
`Integer`, which implies both, is rejected the same way. Reaching a capability through two different trait bounds does not
make either trait redundant: each trait also grants its own operations.
Diagnostics identify the bounded name and the redundant requirement, including
an inherited source where applicable.

Call inference first uses arguments that determine their own types, then the
expected result type, before defaulting remaining literals. An expected result
does not override a known argument type. No context is inferred from later
statements.

A bound guarantees that a type implements a trait; a call must also settle the
trait's arguments to select an implementation. If that lookup key still contains
a type parameter in a generic body, selection occurs at each instantiation. A
concrete key with no implementation is diagnosed at the instantiation, where all
key components first become known.

A trait's `Self` is implicitly bounded by that trait. Argument types determine
it through the same structural inference used for explicit type parameters,
including matching generic constructors, arrays, borrows and callable shapes.
Associated projections are not inverted. The resulting type must implement the
trait. The same selection supplies both the bound evidence and the called body.

When no parameter supplies `Self`, the expected result type may determine it.
This makes constructors such as `fn zero() -> Self` callable, with the same
trait-bound requirement. A call is rejected if neither arguments nor expected
result settle `Self`, including a signature that mentions `Self` nowhere in its
parameters or result.

Result expectations infer `Self` and trait arguments by structurally matching
resolved types, including nested constructors. Constructor identities and fixed
components must agree; inference does not search arbitrary subparts for an
implementing type. A success-payload expectation under `?` uses the same matcher
without supplying an error type.

Trait type parameters are also determined by argument positions or, when present
only in the return type, by the result expectation. Lookup uses these settled
arguments: an implementation of `TryFrom[Int64]` does not answer a call
requiring `TryFrom[UInt8]`. A parameter settled by neither source is diagnosed
at the call because no implementation can be selected.

Inside a generic body, `Self` may settle to a type parameter. Its bound provides
enough evidence to check the call without selecting a concrete implementation.
Each instantiation then selects the body for its supplied type.

**[T-PolyRec]** Recurring generic calls must have a finite structural bound on
their type arguments. Calls with constructor-growing arguments are checked
through the declarations and trait suppliers they can reach. The arguments
include the function's parameters and every implementation parameter determined
by the complete receiver/trait key. A call between different receiver
constructors is still part of a recursive family when it can return to the
original declaration. If no complete implementation substitution is known, both
the receiver and trait arguments participate in discovering growth.

Let H be the maximum structural height of the original caller's type arguments.
Every reentry argument must be bounded by `max(H, C)` for some finite closed
constant C. A positive root-dependent increase, an unbounded contribution or a
reachable positive-weight cycle that can affect reentry is rejected. A helper
that eventually calls back at one fixed closed type can therefore be accepted;
repeatedly wrapping that type cannot. This criterion bounds instantiations, not
the number of times a function may execute at run time.

Symbolic trait dispatch uses canonical implementation selection when it proves
one body. Otherwise all possible source suppliers remain in the analysis. A
provided operation has one body and no suppliers, so a call of one reaches that
body as a direct call does, whatever `Self` it is reached at; that `Self` is one
of the body's arguments, so a provided operation reached again at `Self.Up`
grows as `walk[S]` calling `walk[S.Iter]` does. Each implementation parameter's
injective position in its checked key bounds that parameter whenever the
supplier applies. Visible children are selected before subtracting any remaining
constructor depth from an unknown subtree. Height contributions retain their
outer constructor: a known
`Slot` contribution cannot become a `Document` merely because an unrelated
unknown argument reaches the same helper. Unknown heads, unknown nested
structure and associations between separate parameters remain conservative and
may cause refusal where the finite bound cannot be established.

`f[T]` calling `f[Wrap[T]]` grows and is ill-formed; a stationary `f[T]` call is
well-formed. Mutual recursion such as `Left[A]` calling `Right[Wrap[A]]` and
`Right[A]` calling `Left[A]` grows as well. A structural helper may temporarily
introduce a wrapper when the returning arguments remove that structure.

Each selected associated name is an opaque structural step when identifying
growth. Thus `walk[S]` calling `walk[S.Iter]` grows, including projections from
applied bases such as `Wrapper[S].Item`. An unresolved projection contributes
unknown height, and a directly recurring projection remains rejected even when
an implementation would settle it to a smaller type.

Generic type parts retain the structural non-growth rule: each argument on a
recurring part must contain none of the declaration's parameters or be exactly
one of them. `struct S[T] { v: S[Wrap[T]] }` is rejected. Reachability includes
cycles through multiple declarations, not only immediate self-reference.

Argument growth is separate from layout. A declaration that stores nothing from
its parameter may still instantiate itself at unboundedly growing types;
[T-InfiniteLayout] cannot detect that case.

**[S-Bracket]** Brackets delimit array types `[T; N]`, array literals
`[a, b, c]` and indexes `a[i]`. An unclosed bracket, or an array type missing
`;` between its element type and length, is ill-formed. The diagnostic
identifies the expected closing position, and the parser recovers and
continues.

Indexing may follow any expression that produces an indexable value.
`[1, 2, 3][0]` and `make().x` are projections from expressions; neither
requires the base to name a binding.

**[T-ArraySize]** An array's length is part of its type. An explicit length must
be a non-negative numeric constant expression. A binding initialized with an
array literal may instead write `[T; _]` to infer the count from that literal: a
local `let` or `var`, a module constant or an `impl` constant. Grouping
parentheses around the literal are allowed.

The element type supplies context to every literal element. For example,
`let readings: [Float64; _] = [32.0, 104.0]` has type `[Float64; 2]`, and
`let empty: [UInt8; _] = []` has type `[UInt8; 0]`. At module level,
`let weekday_names: [Str; _] = ["Sunday", "Monday"]` has type `[Str; 2]`; a
constant may also omit its annotation entirely ([T-Const]), so
`let seasons = ["spring", "summer"]` has the same shape. The marker is syntax,
not a variable, constant expression, unsized array or generic length parameter.
It is rejected in signatures, fields, parameter defaults and nested generic
arguments. An initializer that is missing or is not an array literal cannot
supply an inferred count, even if its resulting type has a known count.
Diagnostics point to the unresolved marker
([ADR 0198](adr/0198-array-literal-bindings-infer-written-lengths.md)).

Directly nested array annotations may infer more than one dimension. The first
literal row establishes an inner count, and ordinary element checking requires
all rows to have that same concrete array type. Thus
`let grid: [[UInt8; _]; _] = [[1, 2], [3, 4]]` has type `[[UInt8; 2]; 2]`,
while ragged rows are [T-ArrayLength]. An empty outer literal cannot establish
an inferred inner count: write `[[UInt8; 2]; _] = []` instead. The count is
settled before ordinary element checking; elements keep source-order
evaluation, consuming positions, linear obligations and borrowed dependencies.

Array lengths use exactly the constant expressions admitted by
[§4.1](#41-constant-expressions). Both module constants and block-local `let`
bindings qualify when their initialisers are constant expressions.
`let n: UInt8 = 3` followed by `[UInt8; n]` is valid; `[UInt8; n]` with a `var`
or a binding initialized from a parameter is not. Names in explicit array
lengths use ordinary resolution; a name with no declaration is [N-Undefined].

A constant expression must also have a numeric value: `[UInt8; true]` is
rejected. The maximum length is 4294967295; larger values are diagnosed at the
length. The compiler must be able to determine the length's value at its use;
syntactic constant expressions can still lack values, as with cyclic constants
([T-Const]).

**[T-ArrayLength]** An array literal has as many elements as its type says. The
expected type supplies the required count, as it supplies a braced literal's
type: for `let xs: [UInt8; 3] = [1, 2]`, both the two-element literal and
`[1, 2, 3, 4]` are ill-formed.

An array place `values: [T; N]` provides the explicit call
`values.as_slice() -> mem.Slice[T]`. It observes all N initialized elements in
index order without copying, consuming or allocating. The call accepts no
arguments and no mutable invocation marker. An observed array receiver supplies
its referent's storage. The receiver must supply a stable place; an array
literal or a function's temporary array result cannot be used as the backing
owner. A constant array is a stable place whose storage is static, so its view
may be returned from any function. Ordinary [O-Borrow] and [O-Escapes] rules
govern the view and any observations derived from it. An empty array produces an
empty Slice; an array of zero-sized elements retains its full element count and
index bounds
([ADR 0137](adr/0137-arrays-expose-checked-borrowed-slices.md)).

An array `values: [T; N]`, or an observation of one, provides
`values.length() -> UInt64`, which is N. It accepts no arguments and no mutable
invocation marker. The receiver is read and evaluated in order, and need not be
a place: `row().length()` runs `row` and yields its type's count. When the
receiver is a constant expression whose value is an array, the call is a
constant expression ([§4.1](#41-constant-expressions)), so
`let open_days: [Bool; weekday_names.length()]` sizes one table from another
([ADR 0172](adr/0172-an-array-reports-its-length.md)).

**[T-Index]** An array index must be a whole number or a count from its end. A
compile-time index must identify an existing element: `xs[9]` on a `[UInt8; 3]`
is diagnosed at compile time when the index is known; otherwise a runtime check
traps if the index is out of bounds. Brackets before a call holding what only a
type list can be, such as `rack.steps[UInt8, Bool](1)` where `steps` is a field,
index nothing: only a generic function's or method's call takes types.

`a[^k]` selects the k-th place from the end: `a[^1]` is the last element and
`a[^2]` the preceding one. The caret is allowed only in index position. It
constructs `FromEnd`, an ordinary library structure; an explicitly built and
passed `FromEnd` value selects the same place. Its count is an ordinary
`UInt64` expression, so `a[^(i + 1)]` is valid. `^k` selects the index at length
minus `k`; `^0` is past the last element, and a count greater than the length is
before the first. Known invalid counts are [T-Index] at the source site. Unknown
counts are checked against one and the length at runtime, before subtraction, so
an excessive count traps without wrapping.

The language indexes arrays directly. For another head type, brackets select the
place projected by its `Index` implementation. Lookup uses the trait, the index
expression's type and the head type, as bound discharge does. Other expressions
determine their own index types, and an already typed key is never converted. A
missing implementation is [T-Bound], as for a comparison whose operand type lacks
`Comparable`.

An integer literal, including a negated or parenthesized one, takes the head's
integer key when exactly one applies. The candidates are the integer arguments of
the head's own `Index` bounds and of the implementations lookup would select for
it; `FromEnd` and other non-integer keys are not candidates, and an
implementation whose prerequisites fail does not apply. With one key, `week[0]`
and `week[Int64(0)]` select the same place for reads, writes and `inout`
arguments, and the literal must fit that key, or every integer type a symbolic
key admits. With several keys the literal is [T-Infer], even when its value fits
only one of them; write a typed key instead. A head that still names a type
parameter counts every implementation its constructor could match after
substitution, so a generic body refuses the literal a concrete instance would
refuse. With none, a nonnegative literal is a `UInt64`, a negated one keeps its
ordinary type, and the missing implementation is [T-Bound]. A forwarded
traversal chooses its key by the same rule. A type parameter indexes through its
`Index` bound.

The compiler supplies array implementations of `Index[UInt64]` and
`Index[FromEnd]`, covering the array constructor for every element type and
length, so a generic `Index` bound accepts both arrays and written containers.
The language still defines direct array indexing and checks from-end counts
against the length in the array type.

The compiler also supplies array implementations of `Equatable`, `Equivalent`,
`Comparable`, `Ordered`, `Hash` and `Debug` through the array's view,
`mem.Slice[T]`. Each covers the array constructor for every element type and
length, and applies exactly where the view's own implementation of the trait
does. An array's operation is its view's, given a view of every whole-`Self`
argument, so `==` compares the elements in index order, `<` orders by the first
element pair that differs and stops at an incomparable pair, `Hash` covers the
length and each element's hash in order, and `:?` renders `[1, 2, 3]`. A struct
or enum with an array field therefore derives these traits where the element
type implements them. `Release` is not supplied: releasing a view settles none
of its elements, so no array implements `Release`. A derived `Release` discards
an array field whose elements are discardable, as it discards any discardable
component without `Release`. A missing element implementation makes the array's
use [T-Bound].

Compile-time bounds checking applies to the array reached by an implementation's
projection path, using the index written at the call site. If the path reaches a
four-element array, `b[9]` is rejected wherever `xs[9]` on `[UInt8; 4]` would
be, whether the place is read, written or lent. A runtime check inside a
projection's path, or inside a traversal's expression, traps at the use that
reached it: `view[at]` past the end of a `Slice` reports `view[at]`'s line and
column even though `Slice`'s projection is written in the library. The check
follows composed projection paths through any number of container
implementations: if each passes the site's index to the next bracket, the index
is checked against the final array's length. It follows how the path interprets
the index: a site using `^k` with a container that forwards the count selects
length minus `k`, and a plain index passed to an implementation whose path uses
`^i` also selects from the end.

**[T-RangePlace]** A range-indexed place has the array type determined by its
known bounds. It supports only whole-place copy or assignment. Other uses, or
bounds that cannot be determined where the place is formed, are diagnosed with
the failed requirement.

For an array `[T; N]`, `a[lo..hi]` has place type `[T; hi - lo]`, and
`a[lo..=hi]` has place type `[T; hi - lo + 1]`. This uses ordinary bracket syntax
with a range index and the `Index[Range[UInt64]]` capability, which arrays
implement alongside `Index[UInt64]` and `Index[FromEnd]`. Index position
supplies `UInt64` as the range ends' expected type, as for a bare index literal,
so `a[0..2]` and `a[0..k]` use the same trait key.

Ordinary rules for the resulting array type govern the operation. `copy(a[0..2])`
copies a `[T; 2]` and is [O-Copy] if its element is Linear. `a[2..4] = pair`
assigns a `[T; 2]`, consuming `pair`; overwriting live Linear elements is
[O-Leak]. Moving from the range is an unsupported partial move under [O-Move].
A range place has no value form: binding the place, passing it, or reading it as
a value to write elsewhere is rejected here.

Bounds must be known where the place is formed, before any later generic
substitution: `[T; ?]` is not a type. Digits, constants and arithmetic over them
can determine the bounds; a `var` cannot. [T-Index] checks the first and last
elements selected by the range. An exclusive end may equal the array length; an
inclusive end identifies that element itself. Empty and reversed ranges are
rejected for range places. Range places do not reverse their elements.

Bounds are evaluated as indexes: `a[i]` reads `i` and `a[^k]` reads `k`. A range
place uses two known numbers without constructing a range value, so using a
binding as a bound does not consume it. Outside index position, a range is a
value and consumes each end like a structure literal consumes its fields.

**[T-Infer]** An expression whose type cannot be determined is ill-formed. A
generic type without determined arguments is a template, not a concrete type,
and is also covered by this rule. An expected type determines all its arguments.
Without one, a constructor infers only parameters mentioned in the selected
variant's checked payload types. Any remaining parameter is [T-Infer]:
`Option.Some(3)` determines a type, but `Option.None` does not, and
`Result.Ok(3)` leaves the error type unknown.

An argument built by another constructor than the one its parameter's type
writes around a parameter the call leaves open can never settle it, and is
[T-Mismatch] rather than [T-Infer]: `Chan[Recv[UInt64, End]]` passed for
`Chan[Send[T, N]]` is reported against `Chan[Send[UInt64, N]]`, with what the
call settled filled in and the open parameter by its name.

Inference does not use later statements, with two exceptions: an integer
literal's open type ([T-Literal]) and a function value's open type parameters
([N-NotAValue]) are settled by their uses within the body. `let x = Option.None;`
is ill-formed even if a subsequent use could determine its type. An open type
reaches no further than its body, and is reported where it was written.

A leading-`.` variant also requires an expected type. Without that context, name
the enum or annotate the binding. Other expressions determine their type from
operands, and literals have defaults.

A call refused for its callee (a name nothing declares, an operation the
receiver lacks, a free function written as an operation) has no parameter to say
what a callback's inputs are. Its arguments are still checked, and a lambda
among them whose parameter types are unwritten is not reported under this rule:
the refusal of the callee is the report.

**[T-DivideByZero]** A division or remainder must have a nonzero divisor.

**[T-Condition]** A condition must be `Bool`. Integers cannot serve as
conditions, and no other type converts to `Bool`.

**[T-Arms]** The arms of a conditional have the same type, and that is its type.
Arms of type `Never` do not participate in agreement; if every arm has type
`Never`, so does the conditional. A conditional with no `else` has an `else` arm
of type Unit, so it can complete and does not become `Never` merely because its
written arm cannot. `else if` nests a conditional in the `else` arm under the
ordinary arm rule; without a final `else`, the innermost conditional has an
implicit Unit arm, so the entire chain must have type Unit.

**[T-Logical]** `!e`, `a && b` and `a || b` have type `Bool`. Each operand is a
condition and must satisfy [T-Condition]. `a && b` **is** `if a { b } else { false }`,
and `a || b` **is** `if a { true } else { b }`. The right operand is conditional
on the left, and any value consumed by it is consumed on only that path. The
existing conditional rules govern both operators, and a conforming compiler
generates the same code for each operator and its explicit conditional form.

**[T-While]** A completing `while` has type Unit regardless of its body, because
it may run zero times. The body is evaluated for its effect under [T-Discard]. If
evaluating the condition cannot complete, the whole expression has type `Never`
under [T-Never].

**[T-For]** A `for` consumes a value implementing `Sequence` and obtains an
iterator implementing `Iterator`. Its binder, a name or a tuple pattern that
takes the item apart, receives the iterator's `Item` once per element and is
scoped to the body. A tuple pattern requires the item to be a tuple of the
pattern's arity ([T-Arity], [T-Mismatch]), its components may be patterns of
their own ([S-Match]), and it must match every item ([T-Refutable]). A lending
walk's binders each name their own component of the element, so a write to one
component while another is in use touches a different place.
The expression after `in` is in consuming position, so the value cannot be
referenced afterward.

A slice yields `borrow` items, and a tuple pattern cannot take a borrow apart, so
`for (a, b) in pairs.as_slice()` is refused:

```
error[T-Mismatch]: this takes a tuple apart, and the value is a `borrow (UInt8, UInt8)`
 --> pairs.lin:6:9
  |
6 |     for (a, b) in pairs.as_slice() {
  |         ^^^^^^ a tuple pattern takes a tuple apart
```

`for read (a, b) in pairs` lends each pair and binds both components.

A `Vec` is not a sequence, so a plain `for` over one is refused: taking a vector's
elements out is a separate choice. The report names the walks the refused value
does offer (`for read` and, over a writable place, `for inout` where a traversal
reaches it, `for x in v.as_slice()`, and `v.drain()`). A refused walk never runs,
so it takes nothing from its head.

Every iterator is a sequence of itself: the standard library declares
`impl[I: Iterator] Sequence for I`, whose `iterate` returns the iterator, so a
`for` walks an iterator directly. A type that implements `Iterator` has no other
`Sequence` implementation, which coherence refuses, so the bound `I: Iterator`
says what walking `I` means: `I.Iter` is `I`.

The library's pipeline operations (`map`, `filter`, `fold`, `zip` and the rest,
and their `_inout` forms) are provided operations of `Sequence`, so a pipeline
is written as a chain on what it walks. An operation that takes its callback
`sink` consumes it, so a named callback is moved by its first use (a second use
is [O-Move]) and a copyable one is passed as `copy(f)` to be used again.

Arrays use direct traversal instead: the array is recognised before `Sequence`
is consulted and its elements are visited in index order, each bound as the
element type. Arrays do not implement `Sequence`. The loop consumes the array;
each visited place transfers its element to the body, which must consume a
Linear element exactly once. An iterator must be Discardable under
[O-LinearWalk]; array traversal creates no iterator, so that requirement does
not apply. Its unvisited elements at an exit are governed by [O-LinearTail].

`for x in &it` lends the iterator `it` to the walk instead of taking a sequence.
`it` must be a place holding a value that implements `Iterator`; the loop calls
`next` on it through a writable lend for each element, and the binder receives
the iterator's `Item`. A value that is no `Iterator` is [T-For], and a head that
is not a place is [T-Lend]. The loop takes and abandons nothing, so
[O-LinearWalk] does not apply and the body may leave with `break`, `return` or
`?`. The iterator stays with its owner, whose remaining obligations [O-Leak]
checks at every exit, so a linear drain is settled after the loop by `finish`,
`release` or a written `defer`. The lend lasts for the loop: under [O-Lent] the
body may neither read nor write `it` by its name. The `&` has the meaning it has
on an argument: the walk changes `it` by calling `next` at the head of every
iteration, so under [O-Borrow] an observation of `it`, or a closure reading it,
made before the loop cannot be used once the walk begins, inside the loop or
after it, exactly as it could not across `&it.next()`. Inside
`for inout x in xs`, `for y in &x` advances the lent element through that lend,
as `&x.next()` would.

`for read x in xs` and `for inout x in xs` borrow the traversed value. The
expression after `in` is read, not moved, and remains available afterward. The
binder is a **place** within that value. `read` lends the place read-only;
`inout` lends it writably. Uses of the binder follow the same position rules as
parameter uses. Writable traversal requires a mutable binding and an `inout`
capability at every projection, just as assignment through a bracket does.
[T-Lend] defines the type requirements for a lending traversal. The binder has
the place's element type, is rebound once per position, and is scoped to the
body.

A walked value may observe the storage its places sit in rather than own it: a
`mem.Slice[T]` views elements another value owns, and a type whose projection
indexes a slice it holds reaches them the same way. Each binder of such a walk
then depends on what the walked value observes, as `view[i]` depends on
`view`. Writing, growing or releasing that storage while a binder, or a borrow
of one, is still used is [O-Borrow]. A slice's projection declares `read self`,
so `for inout` over a slice is [N-Immutable].

A range takes its endpoint type from an expected `Range[T]` or a known opposite
endpoint. Otherwise numeric literals use their ordinary default. Known endpoints
must agree without numeric coercion, and each literal must fit the selected type.
Endpoints are evaluated from left to right.

The range syntax produces one `Range` value, and consumers interpret its bounds
according to their operation. A traversal uses their ordering to decide a
direction; a pattern treats them as an interval. So a backwards interval matches
nothing, while a backwards traversal walks toward the lower bound:
`for x in 4..0` yields `4, 3, 2, 1`, and `match n { 4..0 => ... }` is the empty
interval [T-Unreachable] answers for. An index position takes neither reading: a
range there names the run of elements a place is formed over, and ends the wrong
way round name no run, so they are refused rather than reversed.

A `for` has type Unit if every exit carries no value. If a reachable `break e`
supplies a value, the loop has type `Option[E]`: exhaustion produces `None`, and
`break e` produces `Some(e)`. Break sites must agree on `E` under the ordinary
loop rule. The body is evaluated for its effect under [T-Discard].

**[T-Tuple]** `(A, B)` is a positional aggregate whose identity is the
prelude's `Tuple2[A, B]`, a `@copyable` struct whose fields are `_0: A` and
`_1: B`, and likewise through `Tuple8`; `(A, B)` is the canonical spelling. Two
tuple types are one type exactly when their components are, in order. A
literal's components take the expected tuple's component types where one is
expected, and otherwise their own. A tuple's copyability, discardability and
settlement are those of its components under [O-Universe]: copyable where every
component is, linear where any is. A component is selected by its field name,
`t._0`, and follows every rule a field follows. A tuple pattern binds each
component by position to a name or `_`, must name exactly as many as the tuple
has ([T-Arity]), and consumes or lends the whole value as a struct pattern does;
a component bound to `_` is not settled by the pattern, so a linear one is
[O-Leak], reported by its component name; in a `match` the pattern is one
irrefutable arm. A tuple implements `Equatable`, `Equivalent`, `Comparable`,
`Ordered`, `Hash`, `Default` and `Release` wherever every component does,
through the standard library's derives, comparing, hashing and defaulting
components in positional order and releasing them last first; and `Debug` and
`Display`, which write `(1, "a")` and `(1, a)`.

A tuple written against a library whose prelude declares no `Tuple` of its arity
names no type, and is refused by [T-Literal] as text is where no `Str` is
declared.

**[T-Arity]** A call may supply no more arguments than the function has
parameters. A variant construction or pattern must supply the count required by
its declaration. Arity is checked before argument types. A variant that carries
values, named without them where a value of its enum is expected
(`let mode: Mode = .Exact` or `Mode.Exact`), is a construction supplying none
and is [T-Arity]; where a callable is expected it is a constructor value
instead. Where nothing is expected, as in `let make = Mode.Exact`, neither
reading is selected and the name is [T-Infer]. Parentheses around a
construction's callee do not change it: `(Mode.Exact)(5)` builds the variant as
`Mode.Exact(5)` does. [T-Arity] diagnoses surplus arguments; an unfilled
parameter is [T-MissingArgument]. A postfix call `x.f(a)` counts only the
arguments written between its parentheses, since its receiver fills `self`
unwritten; a call through the type, `T.f(x, a)`, writes the receiver as its
first argument and counts it.

**[T-UnknownParameter]** A named argument must name a parameter declared by the
callee. Conversions and variant constructions have no parameter signatures and
reject every named argument. A call through a value nothing declared labels for
passes its arguments by position ([T-Mismatch]); a named argument there is
reported once for the call.

**[T-DuplicateParameter]** Each parameter receives at most one supplied
argument. Both repeated names and a name targeting a parameter already filled by
the positional prefix violate this rule.

**[T-MissingArgument]** Every parameter must receive an argument or have a
default. The diagnostic names the unfilled parameter. An omitted defaulted
argument is filled with the declaration's default value.

**[T-Cover]** A `match` must leave no value of its subject untaken: some arm
matches every value, or it ends with `_` for the rest. Coverage looks inside
every pattern, so a pair of options is covered by its four shapes and an arm
`Some(0)` covers only the `Some` that carries zero. A struct, a tuple and a
newtype have one shape, so a pattern taking one apart with a binder or `_` at
every part covers it; an integer's arms cover the values their literals and
ranges name. The diagnostic names the values no arm takes, each written as a
pattern: `(None, Some)`, `Some(10..=255)`, `Wood`. It names at most nine of
them, then says "and more", in declaration order compared column by column.
Where arms leave several variants of one column to `_`, as `(_, One(0))` leaves
`Off` and `Idle`, the values of the later columns are found for those variants
together, so the nine may name `(Idle, Unset)` before every missing value that
goes with `Off`. A variant whose payload the
pattern would leave unnamed is written bare. A variant remains in the exhaustive
set when its payload contains `Never` or an enum declaring no variants;
`Option[Never]` must still account for `Some`. Only those two types have no
values: a struct or tuple holding one is still a product with one shape, so
`match` over `(Nothing, UInt8)` needs an arm such as `(_, n)`, and a `match`
with none is told that no arm takes a value of its type. The arms of a `match`
over a value of either type are checked against it as any arms are, and since
no value ever reaches them the `match` has type `Never`. Text, a type parameter and any
other type no pattern takes apart are covered only by a binder or `_`.

Coverage is decided in one pass over the arms (Maranget's usefulness): it
answers, for each arm, whether some value matches it and no arm before it, and
which values match no arm, by splitting the arms' patterns position by position
along the constructors each position's type has.

**[T-CoverLimit]** Checking a `match`'s coverage builds rows of its arms'
patterns, one cell per pattern position, and a `match` whose check would build
more than 2^20 cells is refused. Deciding whether nested patterns cover a type is
NP-complete, so without a ceiling the cost of checking one `match` could grow
exponentially with the width of its patterns. A `match` refused this way is
split into nested `match`es, each covering one part. The pattern of a `let`,
`let read`, `let ... else`, `for` or lambda parameter is checked the same way
against a wildcard ([T-Refutable]); one pattern costs about its own size, so
only a pattern of about a million parts reaches the limit, and it is taken apart
in more than one step.

**[T-Unreachable]** A match arm that no value can reach is ill-formed: every
value it matches is taken by the arms before it. This includes an already
covered variant, `_` after coverage is complete, an arm after a pattern that
takes the whole subject apart, `Some(Some(x))` after `Some(_)`, and a range
written backwards, which matches nothing. An unreachable arm and a value no arm
takes are separate mistakes, so a `match` with both reports both ([T-Cover]).

**[T-Bind]** Variant payloads are accessible only by matching. A pattern must
name all payload values or none; a partial prefix is rejected as a miscount.
Binders are scoped to the arm, and a pattern declares each name once however
deep it sits ([N-Duplicate]).

**[S-Literal]** A leading `.` uses the expected type: `.Red` selects its variant,
and `.{ x = 1 }` initializes its fields. A named structure literal writes a named
type before its brace (a name, optionally qualified by dots, and its type
arguments): `Point { x = 1 }`, `Cell[T] { value }`, and
`geometry.Point { x = 1 }`. It constructs exactly that nominal type,
independently of the expected type. A contextual literal without an expected type
is [T-Infer]. The named literal's opening brace must be on the same line as its
type head. In an outer control header, the following brace opens the control body
unless the literal is inside a delimited expression.

Within a structure literal, `field` abbreviates `field = field` and may be mixed
with explicit initializers. Its value resolves to the visible binding with that
name and follows the same consumption rules. Initializers evaluate once in source
order; shorthand introduces no binding, default or copy. Dotted field
initializers are not part of the grammar. Structure patterns keep the
`field: binder` spelling.

A structure literal may end with a **base**, `..base`, after its written fields:
`Limits { read_timeout_ms = 500, ..Default.default() }` or
`.{ depth = 2, ..tall }`. The base is an expression of the literal's own type
([T-Mismatch] otherwise), and every field the literal does not write takes its
value from it. A base does not supply the literal's type: a contextual literal
still needs an expected type ([T-Infer]). The base is written last and evaluates
last, after every written initializer, so an initializer may read the value the
base then takes: `Counter { hits = counter.hits + 1, ..counter }`. The base sits
in a consuming position (§5.4): the literal takes it whole, moves each field it
does not write into the new value, and drops each field it does write
([O-Leak]). A base that should stay usable is copied, `..copy(defaults)`. A
literal with a base is refused outside a sealed type's module as any literal of
it is ([M-Opaque]). A trailing comma may follow the base. A literal that writes
no field and names a base, `Pair { ..pair }`, is that base, moved.

**[S-BaseLast]** A structure literal's base comes after every field it writes,
and a literal has at most one base. An item written after the base is reported
once, and the rest of the literal is still read: a field after the base is
matched to its name, and a second base is checked as an expression, so a name in
it that no binding declares is still [N-Undefined].

**[T-UnknownField]** A selected field must exist on the type. `p.x` and
`Colour.Red` share syntax but select different members: a value selects a field,
and a type selects a variant. Resolution distinguishes them by the left-hand name
in the language's single symbol space. A type parameter selects an operation its
bounds' traits declare, so `T.name` that no bound's trait declares is refused
under this rule.

A selection that is not called and names an operation a sealed type declares, or
one a trait in scope declares, reaches no part of its representation, so it is
refused under this rule, as it is for any type, and never under [M-Opaque].

**[T-MissingField]** A literal without a base must initialize every field. There
are no field defaults; a literal that writes only some fields takes the rest from
a base.

**[T-DuplicateField]** A literal must initialize each field exactly once.

**[T-UnusedBase]** A structure literal's base must supply at least one field. A
literal that writes every field would take its base only to drop all of it, so
the base is refused.

**[L-Layout]** A value's parts are laid out in declaration or positional order,
each at the next offset allowed by its alignment. A type's alignment is the
maximum of its parts' alignments, and its size is rounded up to that alignment,
which also aligns successive elements in an array. Five properties hold:

- a part's offset is a multiple of its own alignment
- a type's alignment is the greatest of its parts' alignments
- a type's size is a multiple of its own alignment
- no two parts overlap
- parts appear in declaration order

An enum's tag occupies a full word, followed by its payload. All variants share
that storage, whose size accommodates the largest variant. Layout is not
observable because memory access requires a typed path, so reordering structure
fields cannot change program results.

**[L-Size]** A type is at most 4294967295 bytes (2^32 - 1, just under 4 GiB)
wide; the limit is the largest offset the representation can hold. Larger types
are diagnosed. The limit
applies to every reachable type, including instantiations discovered only inside
generic bodies, so successful checking includes monomorphisation.

**[T-InfiniteLayout]** The graph formed by traversing inline type parts must be
acyclic. A value that contains itself inline has no finite size. An indirection
with a fixed-size representation can break a layout dependency: a pointer, box
or opaque handle need not store the referenced value inline, and library handles
store addresses without storing the addressed values in their inline parts. The
rule therefore rejects inline cycles rather than recursion by name.

Generic declarations are checked with their parameters substituted into their
parts, not only at explicitly named instantiations. A part that contains its own
declaration is invalid for every argument. For example,
`struct Rec[T] { a: T, b: Wrap[Rec[T]] }` is invalid when `Wrap` stores its
argument: each `Rec` would contain another `Rec`. The argument does not grow, so
[T-PolyRec] admits the finite set of instantiations; the layout cycle is what
makes this declaration invalid.

Whether a type stores an argument depends on its transitive parts, not merely on
whether its head mentions the parameter. If intermediate declarations store
nothing at that parameter, `struct S[T] { b: Mid[S[T]] }` can reach `S` without
containing it and can have a finite size, regardless of the number of
intermediate declarations.

A settled reference stores the type selected by its implementation, so a layout
cycle can depend on the instantiation. Given
`struct S[T: Holder] { a: T, b: T.Iter }`, an implementation defining `Iter` as
`S[Box]` makes `S[Box]` contain itself, while other arguments can leave `S` with
a finite size. The error belongs to `S[Box]`, not the generic `S` declaration.
The diagnostic identifies the cycle so the programmer can locate an inline edge
to remove.

**[T-Loop]** A `loop` exits only through `break` and takes the type agreed on by
its reachable break sites. `break e` supplies `e`; `break` supplies Unit. The
first completing break site determines the type, and later sites must match it.
If a break operand cannot complete, that break never reaches the loop join and
contributes no result type. A `loop` with no reachable break site does not
complete and has type `Never`. It is compatible with a known expected type
without producing a value of that type; `let x: UInt8 = loop {}` never creates an
`x`.

**[T-Call]** A call passes an argument per parameter of the normalised target,
and each argument has that parameter's type: the type flows inward, so a literal
argument takes it exactly as it takes an annotation's. A declared call has the
function's declared return type, whatever its body computes. A call through a
closure value has its closure signature's result type. A call through a
structural `fn` value has that signature's result type. A call through a type
parameter with a structural callable bound uses the bound's signature while the
generic body is checked and the concrete target after instantiation. Where that
settled result is `Never`, the call produces no value and has no local
continuation, for a direct and an indirect target alike.

[S-Args] maps arguments to the signature once. Positional arguments fill a prefix
in declaration order, and named arguments fill their named parameters.
Expressions then evaluate in the callee's parameter order, regardless of written
argument order, so reordering named arguments preserves the program even when
they have effects. The callee expression is evaluated once before any argument.

A parameter is immutable within the body, as a `let` is. `read` is the default
convention; writing it on a function or lambda parameter violates [S-Entry].
Structural callable signatures may spell their parameter conventions explicitly.

A function normally returns its body's trailing expression. `return e` returns
`e` early, and `return` returns Unit. The value must satisfy the function's
declared result type, independently of the surrounding expression. A body that
always exits before its end needs no trailing expression. For `-> Never`, every
path must avoid normal return; a completing tail or bare fallthrough is
[T-Mismatch].

**[T-Assign]** An assignment's value must have the assigned binding's type. The
assignment has type Unit, so `f(x = 3)` is not a value-producing comparison.

A compound assignment, `p += e` or any of the four corresponding forms, also
satisfies [T-Operands]: both operands have the same numeric type and the result
is Unit. It is not expanded as `p = p + e`. The left place is evaluated once,
then read, updated arithmetically and written through that same evaluation, so
an effectful index runs once and the written element is the one read. Ordinary
overflow and division checks still apply.

**[T-Discard]** An expression evaluated for its effect must satisfy Unit. A
`Never` expression does through bottom compatibility and never reaches the next
statement. Any completing value computed and not bound is discarded, which
`let _ = e` says deliberately.

**[T-DiscardFailure]** A `Result` may not be bound to `_`. It must be matched,
handed on with `?`, returned, or passed to something that takes it. A `Result`
reports whether the computation succeeded, so this binder cannot discard it
without acknowledging the alternatives. [T-Discard] governs expression
statements, while [T-DiscardFailure] governs binders; a bare call in statement
position is covered by [T-Discard], and an unread name by [N-Unused]. Both
reports offer `?` only where it would be accepted ([T-TryAnswer]): the function
answers with a `Result` whose error the failure is or converts to, or, for a
failure that settles to such a reason, `.settled()?`. Otherwise they offer
`let … else |_| { … }`, which handles the failure where it happens.

Explicit acknowledgement is sufficient. A `match` with only a `_` arm satisfies
this rule by deliberately treating all alternatives alike; intentionally ignoring
a failure is valid, as in the standard library's debug-tier printing, but
`let _` is not the syntax for that choice. The compiler recognizes `Result` by
the prelude's declaration identity, as it does for `?`
([ADR 0070](adr/0070-explicit-failure-is-acknowledged.md)).

**[T-Const]** A constant's initializer must be a constant expression whose value
does not depend on itself. No code runs at a constant declaration. Constant
expression forms are defined syntactically in
[§4.1](#41-constant-expressions).

A constant's type must be discardable. A constant is copied wherever it is read,
and nothing there takes ownership of the copy, so a type that owes settlement (a
`linear` enum, or an enum whose payload propagates such an obligation even when
the selected variant carries nothing) cannot be a constant.

A constant may declare its type or infer it from its initializer. An annotation
provides the expected type; without one, the initializer determines the binding's
type using the ordinary literal defaults. Later uses do not change that type.
This rule is uniform for module and `impl` constants and for every visibility. A
constant cannot carry `opaque`, `linear` or `copyable`. `pub` has its ordinary
reach.

**[T-Default]** A parameter default must be a constant expression
([§4.1](#41-constant-expressions)) of the declared parameter type. It is computed
once at the declaration, using the same table as [T-Const]. No code runs in the
parameter list and no call-site scope is available, so calls and parameters of
the same declaration are invalid default expressions. A default's type must be
discardable, for the reason [T-Const] gives.

A default built from a type's parts, such as `Percent(10)` or `.{ amount = 7 }`,
is built again at every omission, so the type it builds must be Copyable. The
report names that type and, where the program declares it, says to mark it
`@copyable`; a library type that is not copyable is written where it is used
instead. [T-Const] reports a constant built from the parts of a type that is not
copyable the same way.

An omitted argument is filled with the computed default value; writing that
constant argument explicitly produces the same program. Only the value crosses a
module boundary, so a default may name an unexported constant without exposing
its name to callers. Omitting the argument evaluates nothing and adds nothing to
argument evaluation order.

A lambda default is folded at the lambda expression's outer lexical site before
the lambda parameter scope opens. It may therefore name an immutable enclosing
binding whose initialiser is a constant expression, and doing so creates no
capture. In a structural callable signature the folded type and value, and the
fact that a default is present, are part of exact callable identity.

A parameter whose type is a type parameter cannot have a default, including an
Integer-constrained parameter with a uniformly representable literal, unless
that type parameter writes a default of its own ([T-ArgumentDefault]):
`fn serve[S: Release = ()](sink state: S = ())`. The default is then a constant
of the type parameter's default, and a call that settles the type parameter as
another type cannot omit the argument ([T-Mismatch]). Otherwise defaults
require a concrete declared type; a type that mentions a type parameter, such as
`Choice[T]`, is not concrete either, so `.Empty` cannot be its default. The same
holds for `Self` in a trait signature, where it is a parameter bounded by that
trait ([T-Bound]). A trait operation declares defaults only on its signature
([T-Impl]); every call uses that declaration.

**[O-DeferDead]** A deferred expression is ill-formed if it is skipped on every
scope-exit path because its consumed value has already moved. Such a schedule
never runs, just as the copy rejected by [O-CopyDead] has no effect. Deferred
expressions run in reverse scheduling order, so if two consume the same value,
the second consumes it first, and the first schedule never runs.

**[S-Defer]** A `defer` must contain an expression that does not leave the scope.
`return`, `break`, `continue` and `?` cannot transfer control out of a deferred
expression during scope exit. An empty `defer` is also rejected.

Deferred expressions run at every enclosing scope exit, last scheduled first. The
compiler selects their execution sites and verifies that the written schedule
discharges the scope's obligations; it inserts no unwritten disposal. Control
flow never implies disposal: an operation that may dispose of a value itself, as
`Sequence.zip` does with an item when the second sequence ends first, says so by
requiring the value's type to be Discardable in its bounds. A schedule is skipped
on any path where its consumed value has moved away; where paths rejoin they must
agree about that value ([O-Merge]).

**[S-DeferLet]** `defer let x = e` and `defer var x = e` bind one name, and that
name is what the schedule releases. A pattern takes a value apart into several
bindings and a `let read` pattern owns nothing, so neither has one release to
schedule: each is refused where it is written, and the help says to write `let`
and `defer` the release of each part by hand. There is no block form.

**[T-DeferLet]** For a type that implements `Release`, `defer let x = e` is
`let x = e` followed by `defer x.release()`, scheduled at the statement's own
position
([ADR 0208](adr/0208-defer-let-binds-and-schedules-its-release.md)). The
`release` it schedules is `Release.release`, found by the lookup a written
`x.release()` is answered by, so the type of `x` must implement
`std.release.Release`: a derived or a written implementation is accepted, and
whether the type is linear is not asked. A type that does not, because it has no
`release` or only one of its own that is not the trait's, is refused where the
binding is written. A transaction is committed or rolled back, and the compiler
chooses neither, so the report names the type, says it has no single ending, and
points at the explicit form: write `let`, then `defer` the operation that ends it
on every path.

Everything else is what the second statement already is. The release runs at
every exit from the block, in reverse scheduling order, and once per iteration in
a loop body. A move of `x` cancels it on that path, so [O-DeferDead] and
[O-Merge] answer for `defer let` as for the written pair, and [O-DeferDead] says
the binding is moved on every path and that `let` is what the program means. An
initialiser that leaves by `?` or by its `else` block binds nothing and schedules
nothing: the schedule begins once the name is bound. `defer var` releases the
value the place holds at each exit.

**[T-ArgumentDefault]** A struct, an enum, an alias or a function may give a type
parameter a default, `struct Vec[T, A: Allocator = SystemAllocator]`: the argument a written
type may omit. A type written with fewer arguments than the declaration has
parameters takes each missing one from its default, read where the declaration
is, so `Vec[Str]` is `Vec[Str, SystemAllocator]` in every position a type is
written: annotations, fields, signatures, aliases and the head of an inherent
`impl`. It is one type, with one identity, and the two spellings are the same
implementation key wherever the language compares written types
([N-Duplicate]). Arguments are filled only where a type is written with brackets
or a bare name in a type position; a path head such as `Vec.new_in(allocator)`
takes its arguments from the call. A parameter of the implementation that nothing
in the call determines, neither an argument nor the expected type, takes the
default of the type parameter it stands alone for in the implementation's head:
with `struct Router[S = (), P: Allocator = SystemAllocator]` and
`impl[S] Router[S]`, `Router.new()` is a `Router[()]` unless the context names
another state. A parameter the head writes inside a larger type, or whose type
parameter has no default, is left to [T-Infer]. The fallback applies to members
of an inherent implementation; a member of a trait implementation stays
[T-Infer]. A mismatch against a type holding an argument the fallback filled
names the call that left it to the default. The fallback is subject to
[T-DefaultedAllocator].

The rule has four parts, each a refusal at the declaration:

- Defaults trail: a parameter without a default may not follow one that has one,
  so the arguments a written type must give are a prefix of the list. A
  declaration's parameter list that puts the defaulted parameter last (state
  first, allocator last, as `Router[S = (), P: Allocator = SystemAllocator]`
  does) lets the other parameters be written and the allocator omitted.
- Only a struct, an enum, an alias or a function declares one. A trait's, an
  implementation's and a derive's arguments are settled by the head they key
  on, so a default there would fill nothing. A function's type parameter that no
  argument, expected type or callback determines takes its default (an
  unsuffixed literal alone does not determine it), and a parameter typed by it
  may default to a constant of that type ([T-Default]).
- A default is a type that names no parameter of its own list, so it means the
  same type for every argument that is written beside it.
- A default meets its parameter's bounds, checked where a type omits it
  ([T-Bound]).

A trait implementation's head and a derive's head name every parameter of their
type: the head key is the constructor applied to its own parameters, and an
omitted argument is no parameter. `impl[T] Trait for Vec[T]` is [T-Bound], and a
derive head that omits one is refused as an unsupported derive ([T-Derive]). An
inherent implementation's head may omit them, so `impl[T] Vec[T]` declares
members of the system form.

**[T-DefaultedAllocator]** A type written without the argument of a defaulted
allocator parameter, or a call whose allocator parameter only that default would
fix, is refused inside a declaration that declares an allocator parameter of its
own: any type parameter bounded by `Allocator`, on the declaration or on the
implementation or trait it is a member of, whether the bound is written on the
parameter or in a `where` clause, and whether it names `Allocator` or a trait
that requires it. `fn f[A: Allocator](v: Vec[T, A]) -> Vec[T]` would otherwise
return a system vector silently, where the declaration says it is generic over
where memory comes from. The help says to write the parameter, or to write the
default out where the system allocator is meant. A declaration with no allocator
parameter writes the short form freely, unless it is a public signature of a
library.

A library's public signatures state their allocator. In a library root (the
standard library, a dependency, or a primary root whose manifest says
`"kind": "library"`), a type written without the argument of a defaulted
allocator parameter is refused in every position a signature publishes to
another root: a `pub` function's parameters, result, bounds and `where` clause;
a `pub` trait's signatures; the head of an inherent implementation of a public
type that has a `pub` member, and those members' signatures; a type a public
type settles for a trait; a `pub` struct's fields and a `pub` enum's payloads; a
`pub` alias, newtype or constant, a type parameter's default included. A
wrapper's arguments, a tuple's components and a callable type's parameters and
result are written types in the same position. A private alias the signature
names counts as what it writes, and so does the default a signature leaves a
private declaration's type parameter to; the report shows where the alias or
the default leaves the allocator out. The signature writes the
allocator as a parameter, `Vec[Str, A]` with `A: Allocator`, which keeps it
usable with any allocator, or spells out `mem.SystemAllocator`, which makes the
restriction deliberate: `Vec[Str]` and `Vec[Str, mem.SystemAllocator]` are one
type, and the written argument is what tells them apart. A public library
function's type parameter bounded by `Allocator` takes no default, since a
caller leaving the argument out would take the system allocator without
writing it; such a function is a pair, `x` over the system allocator and
`x_in` taking the allocator first, which is what that report's help says. Function bodies, calls, private and
`internal` declarations, an `@opaque` type's representation and the members of
a trait implementation are not signatures another root reads, and keep the
short form. A declaration that is generic over an allocator is held to the
clause above, whose help names its parameter. The report reads "Public library
signature uses the default allocator for `Vec`." with the help "Specify
`mem.SystemAllocator` to make this restriction intentional, or make the
allocator a generic parameter to preserve allocator polymorphism." A type a
trait implementation settles cannot take an allocator parameter, so there the
help offers `mem.SystemAllocator` alone.

**[T-Phantom]** A type parameter absent from every struct field, enum variant and
trait signature must be declared `phantom`. It contributes to type identity
without appearing in the stored representation. An unused-name spelling,
including a leading underscore, does not express this role. Conversely, a
parameter that does occur in those positions cannot be `phantom`. Phantom
parameters carry ordinary bounds, checked on their arguments
([ADR 0099](adr/0099-a-phantom-parameter-carries-its-bound.md)). Functions,
including trait function signatures, cannot declare phantom parameters. A phantom
argument does not contribute to the instantiation's ownership because no stored
part contains it, and it carries none of its argument's dependencies; a type
that should carry them holds a `mem.Carried` field instead (§5.3). An instantiated aggregate derives ownership from its
substituted fields and payloads. A type argument occurring only behind `borrow`
is observed, so its referent contributes no ownership obligation to the
aggregate.

**[T-Extern]** An `extern`'s parameters and result cross the foreign boundary,
and the result may also be Unit. What crosses is an integer of 8, 16, 32 or 64
bits, a `Float64`, or an unrefined newtype whose base crosses, which crosses as
its base:
every bit pattern of these is a value on both sides, so nothing C hands back
is a value Linea does not define. Integer width and signedness define the
integer's representation, and an 8- or 16-bit integer is extended to a full
register by whichever side produces it. A `Float64` is a C `double`; a NaN C
hands over arrives as the positive quiet NaN, as every NaN arithmetic produces
does. A newtype
crosses whatever its ownership policy, because the parameter convention says
what C does with the value: `read` and `inout` lend it for the call, and
`sink` hands it to C, which consumes it. An `inout` parameter crosses as the
address of its slot, which is C's `T *`: C reads the value there and may write
another, as an out-parameter does. The compiler believes these statements as
it believes the rest of the signature, so a linear newtype over `UInt64` is how
a module holds a C object it must release, and a `UInt64` lent `inout` is how
it receives one from a function that writes it through a pointer. An `extern`
whose result can carry a dependency, such as a `std.ffi` view, writes a
contract saying what the result points into, `borrows(handle)` or
`carries()`: no body is read to infer one, and a handle parameter carries none
by default, so a declaration that writes none is refused. A `borrows(p)` contract names
a parameter `p` that is a handle ([T-ExternHandle]) whose type is not
`copyable`, or a `std.ffi` view: an integer, an unsealed newtype or a type of
an untrusted module could be copied or rebuilt to name the memory after `p`'s
place changed, so it is refused. A refined newtype cannot cross,
because C could hand back a value outside its range. `Bool` cannot cross,
because no C ABI fixes which bytes are true. Aggregates cannot cross because
doing so would expose the layout kept private by [L-Layout]. A callable crosses
only as an `extern`'s callback, in the form [T-ExternCallback] checks; nothing
else hands C a code pointer, because the convention a Linea function is called
in is not part of the foreign ABI contract.

An `extern` may instead answer `std.ffi`'s `Errno[R]`, where `R` crosses as a
result does. C's function returns `R`, and the call evaluates to an `Errno`
holding that value and the `errno` the call left set, read with no other
evaluation between the call's return and the read. `Errno` is an opaque
copyable type: its value is `value()`, and its code is reachable only through
`failed_at(failure)`, which is `.Err(code)` when the value equals `failure` and
`.Ok(value)` otherwise, or `failed_when(failed)`, which is `.Err(code)` when
`failed` is true. `Errno` is not itself a type that crosses, so it is never a
parameter and never an exported function's result. The compiler builds each
`Errno` itself, so the library must declare it as `struct Errno[R]` with the
fields `value: R` and `code: Int32`, in that order; a declaration of any other
shape is [T-Extern] at the declaration, and an `extern` answering it is not
checked further.

The private `std.mem` declarations `slot_stride`, `slot_take`, `slot_put`, and
`slot_place` are typed storage primitives, not foreign calls. A recognized
primitive must retain its compiler-defined private signature; violations are
[T-Extern]. Another module's declaration of the same spelling receives no
exemption.

The private `std.scalar` declarations `linea_math_sqrt`, `linea_math_floor`,
`linea_math_ceil`, `linea_math_trunc`, `linea_math_round`, `linea_math_sin`,
`linea_math_cos`, `linea_math_ln`, and `linea_math_exp` have the exact signature
`(value: Float64) -> Float64`; `linea_math_pow` additionally takes
`exponent: Float64`. These checked primitives are compiler-owned rather than
foreign calls. They are private, nongeneric externs with read parameters, no defaults and no
contracts or where predicates. A malformed trusted declaration is [T-Extern],
even when its substituted signature would fit the ordinary integer boundary. A
declaration of one of these symbols anywhere else, even in a root granted
`extern`, is [T-Extern]: the symbols are compiler-owned. An ordinary body with
the same name remains an ordinary function. The runtime symbols are reserved
against exports.

**[T-ExternCallback]** An `extern` may take a callback, a parameter of a plain
`fn` type that C calls during the call through a C function pointer. Its
parameters and result cross the boundary, apart from a leading `inout`
parameter, which is a context: the `extern` takes exactly one `inout` parameter
of the same type, which C receives as a `void *` and hands back on every call.
The callback is declared without a convention, is a plain `fn` rather than an
`inout fn` or `sink fn`, and promises to retain nothing. At a call, its
argument names a function or is a lambda that captures nothing, because C calls
an entry generated for one fixed function; a function value whose target is
known only at run time is refused. The entry takes the callback's parameters in
their C widths and calls the function, and nothing but an `extern` call is
handed one. The compiler believes the declaration: C calls a callback that
takes a context only during the call, on the calling thread, with the context
it was lent. A callback without a context holds nothing but its fixed
function, so C may keep it and call it later, from any thread; the standard
library's `task` hands the runtime the function a task's thread runs this
way.

```linea
struct Tally { total: Int64 }

extern fn squares_visit(count: Int32, visit: fn(inout tally: Tally, square: Int32) -> Int32, inout tally: Tally) -> Int32

fn add_square(inout tally: Tally, square: Int32) -> Int32 {
    tally.total += Int64(square)
    0
}
```

`squares_visit(5, add_square, &tally)` lends `tally` for the call, and every
call C makes to `add_square` receives it.

**[T-ExternHandle]** A handle is a newtype that is not `copyable` and is either
sealed (`@opaque`) in a module its root's manifest grants `extern`, in any root,
or a newtype over a handle. An `extern` parameter whose type is a handle names
an object C holds, whichever root's `extern` takes it. A `copyable` newtype is
never a handle. Written `read`, the parameter promises that C only reads the
object. Only an `extern` may write `read` on a parameter, and only on a handle;
on any other parameter it is redundant
([S-Entry]). A handle parameter taken by a plain lend, without `read`, lets C
change or free the object, so a call lends its argument's place exclusively,
as an `inout` argument is lent, although C receives the handle by value. The
argument must be a place that may change: a mutable binding, an `inout`
parameter, a mutable capture, the binder of a `for inout` walk, or a field of
one. Every observation of the place made before the call, such as a `CText`
read from the object, ends at the call, and a later use of it is [O-Borrow];
another argument of the same call naming the place is [N-Aliased]. A handle
taken `inout` is lent as any `inout` argument is, and one taken `sink` is
moved. The compiler believes a
written `read`, and believes that each handle is the only one naming its
object: an `extern` answering a handle answers a new or handed-over object,
and the module trusted with C never builds a handle from an address another
handle holds. A handle taken `sink` beside a `read` or plain lend of the same
handle moves what the call still lends, which is [O-Move].

**[T-ExternAgreement]** Every `extern` declaration of one symbol names the one
function the runtime provides under that symbol, so each module may declare the
runtime functions it calls: `std.fs` and `std.net` each declare `linea_close`, and
both call the same function. The declarations must agree on every parameter's
type and convention and on the result. Parameter names and defaults belong to each
declaration and need not agree. A declaration whose signature was already refused
is not compared again
([ADR 0156](adr/0156-every-declaration-of-an-extern-symbol-is-one-function.md)).

**[T-ExternRuntime]** The `linea_` symbol namespace is the runtime's. An `extern`
naming a `linea_` symbol must have the signature the runtime declares for that
symbol (the same parameter types, conventions and result, and for a parameter
the runtime calls back through, a function type taking and answering exactly
what the runtime passes and expects) in whatever root
declares it, and a `linea_` symbol the runtime does not declare is refused. The
standard library's declarations are held to the runtime's signatures exactly as
any other root's are. The compiler-owned symbols above are [T-Extern]'s instead,
and the typed storage primitives have no runtime definition and are refused
wherever else they are declared. A declaration agreeing with the runtime's
signature agrees with every other declaration of the symbol, so
[T-ExternAgreement] does not also report a `linea_` symbol
([ADR 0171](adr/0171-the-standard-library-is-an-ordinary-library.md)).

**[T-ThreadStart]** A runtime function that runs Linea code on a thread of its
own, `linea_task_start`, may be named, as a callee or as a value, only inside
`task.Slot.start`. A body handed to such a function keeps running after the
call returns, and `Slot.start` alone answers a handle that carries what the
body captured until `close` joins the thread, so the body's reads and lends
last as long as it runs ([O-Cross]). Anywhere else they would end while the
body still ran, so a module granted `extern` that declares the symbol cannot
start a thread with it, and no library can offer an unjoined or detached task.
The rule reads the symbol a declaration names, so every root's declaration of
it is held to the rule as the standard library's is
([ADR 0250](adr/0250-tasks-are-structured-through-linear-sessions.md)).

**[T-Export]** An `export`'s parameters and result cross the foreign boundary
as an `extern`'s do, and the result may also be Unit. It applies the same
boundary restriction as [T-Extern], using the same predicate; the separate rule
names the export site that violates it.

**[T-Try]** The operand of `?` must be the prelude's `Option` or `Result`,
recognized by declaration identity. A user type with variants named `Ok` and
`Err` is not a `Result` and cannot use `?`.

String literals and interpolations accept postfix chains, including method calls
and indexing. Numeric and Boolean literals take no suffix, so `7?` is a syntax
error before this rule applies.

An expected success-payload type constrains generic call results beneath `?`,
including grouped expressions and the result positions of blocks and branches.
Nested `?` applies successive success projections. This context does not select a
carrier or an error type; independent whole-result context still applies.

**[T-TryAnswer]** The enclosing function must return the same type constructor as
the operand of `?`, and a `Result`'s error must be the function's error type or
convert into it. Success payload types may differ: a function returning
`Option[String]` may use `?` on `Option[UInt8]` because failure returns no
payload. There is no conversion between `Option` and `Result`. Using `?` in a
function returning `UInt8` violates this rule; the report names the result type
that would carry the failure, `Result[UInt8, E]` with the operand's error. Where
the `?` is the whole of a statement, it also offers handling the failure there:
`let count = … else |_| { … }` for the initialiser of `let count` (`var` for a
`var`), and
`let _ = … else |_| { … }` for an expression kept for its effect. `else` stands
nowhere else, so a `?` inside a larger expression is offered only the signature.
A destructuring `let` is offered `let … else` with its own pattern,
`let (a, b) = … else |_| { … }`. A closure that writes no result, and is given
none by a callable type it is passed as, answers with what its body gives, so a
`?` in it is held to that type once the body is checked, and the report offers
the closure's result, `|| -> Result[UInt8, E] { … }`.

A failing `Result` returns its error. An error of the function's own error type
passes through unchanged and needs no implementation. An error of a different
type is converted with the prelude's `From`: where the operand's error type is `A`
and the function's is `B`, `?` returns `.Err(From.from(error))` through the
implementation `From[A] for B`. Only the function's error type is ever the
target, so a conversion is never ambiguous. The implementation may be declared,
or supplied by a bound in scope: inside `fn load[E: From[ParseError]]() -> Result[T, E]`,
a `?` over `Result[T, ParseError]` converts through the bound, and each
instantiation calls its own implementation. Where no implementation or bound
supplies `From[A] for B`, the `?` violates this rule, and the diagnostic names the
missing implementation. The trait is the library's, by declaration identity; a
program's own trait named `From` does not convert. The library supplies no
identity implementation, so `From[A] for A` exists only where one is written.

The error is moved into `from`, so a Linear error is settled by the conversion,
and the converted error is the function's to settle. The conversion runs on the
failing path before the function's scheduled operations, as the operand of a
`return` does. The converted error carries what `From.from`'s signature says its
result carries: the trait declares `where carries(source)`, so the converted error
keeps the dependencies of the error it was built from, as far as its type can hold
any; a payload-free enum keeps none.

The library declares no `From` that drops a value a failure hands back, and `?`
calls only the `From` implementations that are declared, so a `?` gives up an
owned value only through a conversion the program wrote. A refused `push`,
`insert` or `collect` therefore needs `.settled()` before `?`, which releases
the value and converts the reason
([ADR 0218](adr/0218-the-library-gives-up-no-value-at-question-mark.md)).

**[T-LetElse]** `let pattern = e else { … }` unwraps the prelude's `Option` or
`Result`, recognized by declaration identity as for `?`
([ADR 0167](adr/0167-a-binding-handles-its-failure-with-else.md)). On success the
pattern binds what `Some` or `Ok` carries. On failure the block runs:

```
let listener = net.listen(address) else |error| {
    io.eprintln("cannot listen: {error}")
    return 1
}
let first = values.first() else { return 0 }
let port = parse(text) else |_| { 8080 }
```

A failed `Result` carries its error into the block, so `else |error|` names it and
`else |_|` discards it; a `Result`'s `else` without a binder is refused. A failed
`Option` carries nothing, so its `else` takes no binder. An initializer of any
other type is refused. The binder is a name or `_` and never a pattern; its scope
is the block.

The block either does not complete or yields the success type in the value's
place. A block of type `Never` (one that ends in `return`, `break`, `continue`, a
panic or a call that does not return) leaves the binding's scope, and the binding
is never made. A block that completes supplies the value the binding takes. Any
other block type is [T-Mismatch], and the diagnostic names both shapes the block
may take.

The binding's annotation is the expected success type, and it constrains a
generic initializer's result as a success-payload expectation does under `?`. The
pattern is any binding pattern: a name, or a struct, tuple or newtype pattern that
takes the success apart, nested as deep as it needs, such as
`let Entry { name, span: (start, end) } = find(key) else { … }`. It must match
every value of the success type ([T-Refutable]): the `else` runs when the
initializer is `None` or `Err`, and never because a part of the pattern failed. `let read` observes a place, and an `else` construct is not one
([T-Lend]). A constant's initializer runs nothing, so a constant with an `else` is
[T-Const].

The construct is a `match` with two arms written where the binding is, so its
ownership is a consuming `match`'s: the initializer is taken, the error binding
owns the error, and everything the function still holds where the block leaves is
checked by [O-Leak] at that exit as it is at any `return`.

**[T-Refutable]** A pattern in a `let`, `let read`, `let … else`, `for` or
lambda parameter must match every value of its type: there is no arm to take the
values it misses. `let Some(n) = found` misses `None` and is refused, with
`match` or `let n = found else { … }` as the two ways to handle the other case.
A pattern nested inside the head is held to the same rule, so
`let (key, Some(value)) = pair else { … }` is refused too: the `else` of a
binding runs when its `Option` or `Result` initializer fails, never when a part
of the pattern does ([ADR 0224](adr/0224-a-pattern-nests-wherever-a-binder-stands.md)).
The diagnostic names a value the pattern misses, at the part of the pattern
that first leaves it out. A part that matches no value at all, a literal
outside a refinement or a range written backwards, is reported here as well,
as "this pattern matches no value"; in a `match` arm the same part is
[T-Unreachable].

**[T-Refine]** Every violation of a newtype's refinement contract is reported
under this rule. An empty range is rejected at its declaration:
`type EmptyRange = UInt8 where it in 5..=4` admits no value. A construction with a
known out-of-range value is rejected at the construction and reports the value and
range: `error[T-Refine]: 150 is not in 0..=99 for Percent`. Construction also
requires proof that an unknown value is in range. Without that proof it is
rejected, with `Percent?(n)` suggested as the fallible construction.

A refinement requires an integer base; non-integer refinement, such as
`@opaque type Email = Str where ...`, is rejected here. `it` is the sole
refinement value name, matched by identifier text as `Self` is. The `lo` and `hi`
bounds must be integer literals. The lower bound is inclusive. `..` excludes the
upper bound, while `..=` includes it. A range reaching past what the base can
hold, such as `UInt8 where it in 0..=300`, is rejected at its declaration.

A rejected refinement is reported once, at its declaration. Patterns of its type
are judged by the values the range admits within what the base can hold, so
`Level(0..=255)` covers the `UInt8` refinement above ([T-Cover]). Where no such
value is left, because the range is empty or the base is not an integer, a `_`
or a binder at that type, bare or inside the type's name as `Closed(_)`, still
takes any value it holds, so the rest of the pattern is judged as usual. A pattern that names a value of the type is not
judged, and neither are the other arms of its `match` nor its `let`.

### §4.1 Constant expressions

Aggregate data follows [ADR 0140](adr/0140-aggregate-constants-retain-checked-construction-plans.md).

A **constant expression** is:

- an integer literal;
- a truth value, `true` or `false`;
- a string literal without interpolation, raw or not;
- an embedded file, `embed(path)` or `embed_bytes(path)`;
- the unit value `()`;
- a structure literal, fixed-array literal, tuple literal or enum variant
  construction whose stored components are constant expressions and whose
  complete concrete type is Copyable with no owned obligation or runtime
  observation. A tuple literal `(0, 0)` is the structure literal of its
  positional fields ([T-Tuple]), so it qualifies as one does. A variant is
  written qualified (`Mode.Preserve`) or selected from the type expected where
  it stands (`.Preserve`), and carries constant payloads such as
  `Mode.Exact(384)`. A payload-free variant stores nothing, so it qualifies
  whenever its enum owes no settlement, even where a sibling's payload leaves
  the enum affine. A structure literal with a base qualifies when its base is a
  constant expression too: `.{ width = 8, ..small }`, where `small` is a
  constant, supplies `small`'s other fields;
- `min` or `max` selected from a concrete built-in integer type;
- a parenthesised constant expression;
- a negation or conversion of a constant expression;
- a newtype construction `Name(e)` whose operand is a constant expression of the
  base type and whose newtype is Copyable
  ([ADR 0157](adr/0157-a-newtype-built-from-a-constant-is-a-constant-expression.md));
- an arithmetic operation whose operands are both constant expressions;
- a length call `e.length()` whose receiver `e` is a constant expression whose
  value is a fixed array; its value is that array's element count;
- a reference to an immutable binding whose initialiser is a constant
  expression.

Arithmetic, negation and conversion with a symbolic numeric operand or result
type are not constant expressions: their checks execute against the instantiated
type. Parentheses do not change this classification, and such expressions cannot
supply parameter defaults or implementation constants. Range properties selected
from a symbolic Integer parameter are likewise nonconstant.

Only these forms are constant expressions. `!ready`, `ready && ready`, ordinary
function calls and blocks, including an empty `{}`, remain excluded even when the
compiler can evaluate them without running the program
([ADR 0078](adr/0078-a-truth-value-is-a-constant-expression.md),
[ADR 0146](adr/0146-payload-free-variants-are-constant-expressions.md)).

A newtype construction's value is its operand's, typed as the newtype. A refined
newtype's range is checked where the construction is written, as [T-Refine]
checks every construction: `let cap: Percent = Percent(150)` and a default
`by: Percent = Percent(150)` are both refused with
`150 is not in 0..=99 for Percent`, and neither is also reported as non-constant.
The fallible form `Percent?(n)` produces an `Option` and is not a constant
expression. A newtype's constant is not a number: it cannot be an array length or
an arithmetic operand, even where its base is an integer.

Truth values cannot be negated or converted ([T-Operands], [T-Convert]), and have
no arithmetic operations. A `Bool` constant is a literal or a reference to one,
optionally parenthesised. Its value is `true` or `false`, distinct from every
integer value, and a Bool cannot serve as a numeric bound or array length.

A string constant is a string literal, an embedded file read with `embed`, or an
immutable reference to one, optionally parenthesised. Its value denotes static
decoded bytes with the same UTF-8, escape and byte-length rules as a direct
string literal; an embedded file's value is the file's bytes. A byte constant is
an embedded file read with `embed_bytes`, or an immutable reference to one: its
value is the file's bytes, as a `mem.Slice[UInt8]` viewing static storage. An
embed the loader refused is a constant whose value does not exist, so it is
reported once, by [M-Embed] or [M-EmbedText], and not again by [T-Const].
Embedded NUL and empty strings are admitted. String equality, concatenation,
slicing, length calls and interpolation are not constant-expression forms, and
text does not become an integer count, an arithmetic operand or a numeric
conversion operand because it is constant. Function defaults admit these same
string constant forms.

Aggregate literals obey ordinary contextual typing, field completeness,
uniqueness, extent, payload, range and opacity checks. The annotation on a named
constant or parameter supplies context; an alias retains its initializer's type.
A variant construction is data construction, not an ordinary function call.
Qualified and contextual variant spellings denote the same value when their
checked types and payloads agree. Open generic aggregate defaults are refused; a
concrete generic instance may qualify. An empty fixed array owns no elements,
even when its element type is Linear.

A constant variant's value is the variant together with the enum type it has:
`First.Preserve` and `Second.Preserve` are distinct values even where both are
the first variant, and a generic enum's constant has the instantiation its
binding or parameter declares. A contextual variant is selected once, from the
type expected where it stands: a constant's own annotation, or the type of the
parameter it defaults. A later use never retypes it, and a constant without an
annotation cannot take a contextual variant ([T-Infer]). An enum constant is not
a number and cannot be an array length or an arithmetic or conversion operand.

Copyable eligibility does not make an arbitrary observation static. A record
containing literal-backed Str, or the byte slice of an embedded file, can be
constant; the same record containing a
runtime text view or `borrow` expression cannot. Resource owners, allocator calls
and user-defined copy operations cannot appear inside constant values. A
constant's value is laid out from checked data, without executing a constructor,
initializer, copy implementation or cleanup operation, and held in **static
storage** that lasts as long as the program and is never written, replaced or
released ([ADR 0178](adr/0178-a-constant-is-a-static-place.md)). Each read of a
constant by value and each omitted argument yields an independent copy, exactly
as writing the value there would. A constant is also a place ([T-Lend]): a borrow
of it, or of a field or element of it, observes the static storage itself, so it
depends on no owner and may be kept, stored or returned anywhere ([O-Escapes]).

Constants of the same type and value may share one storage; no program can tell,
since an observation's address cannot be compared.

Constant and default identity includes the checked type and structural value.
Record field spelling order does not matter; array and payload order and variant
choice do. Aliases do not change identity. User equality and hash implementations
are not involved. The same rules govern ordinary, lambda and structural callable
defaults, including comparison during implementation coherence.

Module and `impl` constants are immutable bindings. A reference to one is a
constant expression regardless of its spelling: `Limits.high` qualifies just as a
local `let` bound to a literal does
([ADR 0059](adr/0059-one-table-answers-both-questions-about-a-constant-expression.md)).
A `var` does not qualify because it can be reassigned.

Declaration order does not matter ([§2](#2-grammar)). A constant may reference
another declared above or below it, with the same result. A direct or indirect
reference back to the constant being initialised creates a dependency cycle,
which the second half of [T-Const] rejects. A cycle is reported once, at the
reference that closes it, and not separately as a non-constant initialiser for
each member. Dependency chains have no length limit.

[T-Literal], [T-Convert], [T-Overflow] and [T-DivideByZero] are checked at
compile time for constant operands and at runtime otherwise. Constant-expression
validity depends on this definition, not on how much a compiler can prove, and
no later pass may reject a program the definition accepts
([ADR 0020](adr/0020-a-constant-expression-is-defined.md)). An admitted form
remains a constant expression even if evaluation fails: `200 + 200` typed as
`UInt8` produces [T-Overflow], with no additional [T-Const] error.

The minimum of a signed type is a constant expression even though its magnitude
alone is not: `-128` is an `Int8` and `128` is not. A negated literal is one
constant, not a negation applied to another, and parentheses do not change this:
`-(128)` and `(-128)` are both the `Int8` minimum, and `-(129)` reports the value
`-129` as out of range.

### §4.2 Projections

A **projection** is a member that yields a place, declared with `proj` alongside
`fn`. A function body executes when called; a projection body specifies a place
path substituted at each use.

```
pub trait Index[I] {
    type Elem
    proj at(inout self: Self, i: I) -> Elem
}
```

**[T-Projection]** A projection's body must be a place rooted at `self`, reached
through field selection and indexing. A body that computes a value, branches or
calls ordinary functions is rejected. Each index expression may use parameters,
literals, arithmetic over them or other places in scope, but may not call or
branch, because the body is substituted at every use and such code would execute
once per use where the caller did not write it.

An Index implementation written `via field` forms the same place path as
`self.field[i]`. Its target must be a direct stored field of the implementing
type, and that field must support the declared key type. Missing fields,
unsupported backing keys and recursive delegation are [T-Projection], including
a field whose type reads the delegation's own element,
`struct B { values: [B.Elem; 2] }` with `impl Index[UInt64] for B via values`,
directly or through settled types and other delegations. After
generic substitution, the backing indexing operation supplies `Elem` and the
receiver access ceiling. Delegation cannot widen read-only access. The key is
forwarded unchanged, with the same single evaluation, bounds checks, FromEnd
interpretation and owner dependencies as a handwritten projection. It grants no
permission to move an element out of its owner. The private `std.mem.slot_place`
primitive may instead form the projection's tail; it checks the index against the
live element count and retains the receiver's root and projection ceiling.

A projection implements a projection declared by a trait; an implementation
cannot add undeclared projections or specify a mode ceiling above the trait's.
Projections are accessed through brackets and cannot be called. Direct or
indirect recursive expansion, including brackets beneath field selections and
within other index expressions, is rejected with a diagnostic naming the cycle.

The index expression written at the use site executes there exactly once, even if
the expanded path uses its result several times or never uses it.

A container supports indexing from its end through `impl Index[FromEnd]`, with a
projection path subject to the same rules. The array reached by the path
interprets the from-end count using the length in its type, and the projection
forwards the count rather than calling an operation to compute a length. A
container backed by an array can therefore forward `^k` to that array; an
ordinary field-and-index projection without such an array cannot define from-end
indexing.

Only brackets access a projection: `v[i]` names a place, while `v.at(i)` and
`Index.at(v, i)` are rejected calls. Projection paths stay visible to ownership
checking, and a Linear part cannot leave its container through a call.

Other member rules apply unchanged. A missing projection is [T-Impl]; a duplicate
is [N-Duplicate]. Its result type must match the trait's after substituting the
implementation's declared types: with `type Elem = UInt8`, both
`proj at(…) -> UInt8` and `-> Self.Elem` match. A projection receives its generic
arguments from its trait and declares its output type; it cannot declare type
parameters of its own. Projections may appear only in trait implementations: an
inherent `impl` cannot declare one, and a projection cannot implement a trait
function or vice versa.

Projection access has three distinct properties:

- **Evaluation access**: the access needed to locate the place. This is always a
  read, regardless of the mode, since address arithmetic and bounds checks do not
  mutate the container.
- **Place access**: what the use site does with the resulting place. Position
  determines this: a reading position reads, an assignment writes, and a marked
  argument lends `inout`.
- **The ceiling**: the mode on the implementation's `self`, which limits access
  through the resulting place.

| Site | Evaluation | Place access | Requires |
| --- | --- | --- | --- |
| `let x = b[i]` | read | read | ceiling ≥ `read` |
| `b[i] = x` | read | write | ceiling ≥ `inout`, `b` mutable |
| `f(&b[i])` | read | `inout` lend | ceiling ≥ `inout`, `b` mutable |
| `copy(b[i])` | read | read | ceiling ≥ `read` |

The trait sets the maximum ceiling an implementation may offer; an implementation
may choose a lower one. `Index` permits `inout`, while a container that exposes
elements only for reading may declare `read self`. A write exceeding that ceiling
is [N-Immutable], with `read self` identified as the reason the place is not
mutable. Evaluating the path itself needs no mutable receiver.

Every projection in an expanded place path constrains its access: if one
container's path indexes another container, the use site must satisfy both
implementations' ceilings. Places used within an index expression are read only,
regardless of nesting depth. `sink self` exceeds every permitted trait ceiling,
so a projection cannot move an element out; removing an element leaves a hole
that the container must handle through an operation with a body.

### §4.3 Traversals

A **traversal** specifies the order in which a type's places are visited. `trav`
declares one in an `impl` naming only the type:

```
impl Grid {
    trav positions = 0..4
}
```

The bound expression must produce an `Iterator` with an integer `Item`, giving
one bracket index at a time. It is evaluated at each walk over the type, not at
the declaration, so every walk gets its own iterator.

A traversal whose positions depend on the walked value may declare one read
receiver:

```linea
impl Grid {
    trav positions(read self: Self) = UInt64(0)..copy(self.len)
}
```

The receiver is an ordinary parameter scoped to the initializer. Its type is
written `Self`, it has no default, and its convention is `read`; `sink`, `inout`,
and additional parameters are [T-Lend]. The receiver name follows the ordinary
unused-name rule. The initializer is checked by the ordinary ownership rules, so
reading its receiver cannot move a Linear part. A lending walk evaluates its head
once, supplies that value to the initializer, and uses the same value for the
projected places.

A traversal implements no trait and has no visibility modifier. Walks find it
through its type, so `pub` would have no effect and its name is exempt from
unused-declaration checks. Only the type's declaring module may specify a
traversal, under the same [M-Impl] rule as an inherent `impl`. A type may declare
only one traversal.

**[T-Lend]** A traversal must produce an `Iterator` whose `Item` is an integer. A
lending `for` requires both a traversal and a projection indexed by the
traversal's item type: the traversal chooses positions, and the projection maps
each position to a place. The iterator and item requirements are checked at the
traversal declaration, so an invalid traversal produces one diagnostic instead of
one per loop.

A lend needs storage that outlives it, so the operand of `borrow` and the
initializer of `let read` must each be a place: a local, parameter, capture or
binder, a constant, a field, index or dereference reaching one, or an existing
observation's referent. A constant is a place whether it is named bare or reached
through its module or a type, and its storage is static, so a lend of it has no
limit. A temporary, such as a call's result or a field of one, is rejected rather
than given a longer life. `let read Point { x } = *seen` reads the referent of
the observation `seen`; the observation itself is a `borrow Point` and does not
match a `Point` pattern.

`trav positions via field` explicitly chooses ascending positions from a direct
fixed-array field. This form has no receiver, initializer or body. The wrapper
must supply exactly one applicable integer Index key; FromEnd is not an integer
candidate. That key determines the range's integer type. Zero or multiple integer
keys are [T-Lend]; an ordinary typed traversal, such as
`trav positions = UInt64(0)..UInt64(4)`, states the choice explicitly. A non-array
field is also [T-Lend]. The array length must fit as the exclusive upper bound of
that integer range; an unrepresentable bound is diagnosed, never truncated. An
empty array supplies no positions. An integer key determined by a generic receiver
may remain a type parameter; the endpoint must then fit every integer type
admitted by its bounds.

A forwarded traversal still indexes the wrapper through its selected Index
implementation and preserves that projection's access ceiling. It neither
bypasses indexing policy nor supplies consuming Sequence iteration or cleanup.

Arrays need neither declaration: their length is part of the type, their positions
already denote built-in places, and traversal and projection are resolved before
a declared traversal is looked for.

A traversal's iterator is abandoned when a walk ends, just like the iterator
produced by a `Sequence`, so [O-LinearWalk] applies, checked at the traversal
declaration. [O-LinearTail] does not apply to lending walks: a lending walk moves
no elements, and unvisited places retain their values. Both consuming and lending
walks can visit Linear elements: a plain `for` transfers each element's
consumption obligation to its body, while `for read` and `for inout` leave the
obligation with the container's owner.

## §5 Ownership

Copyability and mandatory consumption are separate capabilities. A value is
Copyable when duplication is permitted, Affine when duplication is forbidden but
omission is permitted, and Linear when it must be consumed exactly once.
Discarding a value invokes no operation.

User-defined structs, enums, and nominal newtypes are affine by default.
`copyable` conditionally permits explicit duplication when all owned parts are
Copyable. `linear` imposes mandatory consumption regardless of representation.
Owned Linear parts propagate mandatory consumption through concrete and generic
wrappers. Observed referents do not count as owned parts.

`Copyable` is the built-in duplication bound. `Discardable` admits Copyable and
Affine values. Neither is an implementable trait. An unbounded type parameter may
not be copied or discarded; a checked bound grants the corresponding permission.
The `Linear` bound retains its unrestricted type-argument meaning.

Built-in numbers, Boolean values, unit, observations, and noncapturing callables
are Copyable. Arrays compose their actual elements; an empty array owns none.
`Never` has no values, so its vacuous capabilities create no successor state.
Nominal newtypes are affine unless explicitly declared copyable or linear.

A declaration policy and its instantiated capabilities are different facts.
`@copyable enum Option[T]` remains valid for Linear T: that instantiation is
Linear and cannot be copied. An ordinary struct containing a File is Linear
without requiring a redundant modifier. An explicit linear type may contain only
a UInt64 if it represents a protocol obligation.

`Release` is an optional ordinary trait, independent of those capabilities.
Linear values may require a choice among terminal operations and omit Release.
Discardable values may implement effectful Release. Such an operation runs only
when explicitly called or scheduled by a written defer, never on discard.
Unused-binding and fallible-result acknowledgement rules remain independent.

`Settle`, declared in `std.release` as `trait Settle: Release`, is the library's
operation for a failure that holds an owned value: it consumes the failure, releases the
owned part and returns the reason. Like `Release`, it is never scheduled and runs
only where it is called.

### §5.1 Conventions

| Convention | Consumes | Universe | |
| --- | --- | --- | --- |
| `read` | no | any capability category | a lend; may never be moved from |
| `inout` | no | any capability category | may be moved from, must be refilled |
| `sink` | yes | any capability category | the callee takes ownership |

`read` supports every capability category: `fn tag(k: Key)` is legal for a Linear
`Key` because the parameter cannot be moved from. `sink` transfers a value to a
callee that may perform any terminal operation its interface provides; the
argument's Linear consumption obligation passes to the callee's body. No
convention distinguishes `release` from `commit`, `rollback` or another
consuming operation. Neither `read` nor `sink` uses `&` at the call, because that
marker permits writeback through the argument, which neither convention allows.

### §5.2 Matching

A plain `match` consumes its scrutinee. `match read` does not, and binds each
leaf as a lend.

```
match k { Forged(n) => n }        // consumes `k`
match read k { Forged(n) => n }   // does not; `n` is lent
```

The construct decides how every binder holds its part, at any depth. Under a
plain `match`, `let` or `let ... else` the value is taken whole, and each binder
owns the part its path selects: in `Some((name, value))` each `String` moves to
its own binder, which must settle it. Under `match read`, `let read` or a lending
walk each binder lends exactly that part, so `Some((name, port))` over a lent
option lends `name` from inside the pair inside `Some` with nothing copied; a
scalar binder still reads a snapshot and other duplication still needs `copy`.
There are no partial moves and no per-binder modes. `_` settles nothing at any
depth: a linear part a consuming pattern binds to `_` is [O-Leak], and a variant
whose linear payload a consuming pattern leaves unnamed is [O-Leak] as a `_` arm
is. Each arm tests its pattern outer part first, so a payload is read only once
its variant's tag is tested.

The unit value `()` is not a pattern: the unit type has one value, so matching it
tests nothing. `_` matches it; a bare name in an arm is a variant, not a binding.
A variant's payload binder, as in `Dot(u)`, binds a unit payload.

An arm's body may be an expression or a block, as in an `if`. An empty block
computes nothing and has the value `()`, allowing an arm to do nothing:

```
fn release(sink k: Key) {
    match k { Forged(_) => {} }
}
```

**[O-Capture]** A closure may observe only explicitly declared captures from its
enclosing body. `read name` observes that place; `read alias = place` gives the
observation a different name in the closure body. The source must be a place.
References to other enclosing locals, parameters or capture bindings are
rejected. Module constants and declarations require no capture. Capture sources
evaluate once, left to right, when the closure value is constructed. Parameter
defaults are evaluated outside the closure parameter scope.

A read capture aliases the observed source and does not copy it. Its owner
dependencies survive closure movement and storage; the observed owner must remain
live. The closure body may read a capture but may neither mutate nor move from
it. Scalar value reads produce the ordinary independent snapshots. Nested
closures must declare their own captures. A read invocation may run repeatedly
without consuming the environment.

A sink capture transfers its value into the environment. Read invocation lends
owned fields without consuming them. Inout invocation may mutate owned fields and
must leave them initialized on every completing path. A sink invocation consumes
the closure and must settle or transfer every mandatory owned capture on every
completing path. Constructing or discarding a callback runs no cleanup; partially
constructed environments obey the ordinary transfer obligations. Results cannot
borrow closure-owned storage.

An `inout` capture lends its source place to the closure exclusively
([ADR 0193](adr/0193-a-closure-may-hold-a-place-lent-inout.md)). The source must
be a place that may change, as for `&` ([N-Immutable]); a value that is not a
place is [T-Lend]. The environment stores an observation of the place, and the
capture binding names the place itself, as an `inout` parameter does: the body
may read and write it and must leave it initialized. Only a closure called
`inout` or `sink` may hold one ([O-Capture]), because a closure called for
reading may be reached through several observations at once. The lend lasts until
the last use of the closure or of any value that carries it, such as an adapter
holding the closure; until then the place is reached only through the lend
([O-Borrow]), and afterwards it holds every update the closure made:

```
var inspected = UInt64(0)
let accepted = arrivals.filter(inout [limit, inout inspected] |parcel| {
    inspected += 1
    *parcel <= limit
})
// ... the last use of `accepted` ...
io.println("{inspected} inspected")?
```

Lending a place `inout` ends every earlier observation of it, as a write does. A
value holding the lend cannot leave the function that lends the place
([O-Escapes]). No contract clause may name an `inout` capture
([T-BorrowContract]), and a closure's result never depends on one. `carries`
forwards a lend unchanged, so a value whose contract carries a closure, or an
adapter holding one, holds its lend; `borrows` observes the argument's own place
and never forwards a lend. A value whose type can hold no closure, function value
or type parameter's value cannot write through a lend, so a lend it carries is a
read observation there: a vector of borrowed items collected from a counting
filter leaves the count readable, and refuses only a write, move or new lend of
it until the vector's last use. A closure cannot store in a place lent to it a
value that may observe another place, since no contract can name the `inout`
capture as a retention destination; in generic code that refuses storing a copy
of a `T` value there. An environment holding an `inout` capture is never Copyable
and may be dropped: dropping a lend settles nothing. A Linear place may be lent;
its owner settles it after the lend ends.

Captured sources may be named in explicit `carries` and `borrows` clauses after
`->` and a `where` separator, with an optional result type between them. These
clauses preserve external owner dependencies; `carries` does not authorize
borrowing the capture's own storage. A `retains(destination: source)` clause may
name an owned capture as its destination only under `inout` invocation. New
argument observations stored there remain dependencies of the closure and of its
recovered environment. An undeclared retained dependency is rejected. Stored
observations cannot be used to mutate their referents through a contract
destination.

A lambda without authored clauses may inherit contextual parameter and captured
result sources. Generic callable bounds permit external dependencies carried by
the callable environment in addition to their parameter sources, unless explicit
`where carries()` requires result independence. The normalized generic callee
source carries existing external dependencies; it never borrows callable storage.
Authored result clauses must fit the contextual upper bound; retention
requirements remain exact. Captured effects are never erased to satisfy an
independent-result requirement.

`callback.into_captures()` consumes a concrete closure and returns a record whose
fields are named by its capture aliases. Read and `inout` fields remain
observations (an `inout` field becomes a read observation of its place, since the
closure that could write through it is consumed); owned fields retain their
settlement obligations. Recovery preserves each field's owner dependencies. A
noncapturing closure returns an empty record. Recovery does not invoke the
callback, copy captures, or release resources.

A closure implements `Release` exactly when every owned capture implements it. An
explicit release consumes the closure and releases owned fields in reverse
capture order without invoking the callback. Read captures do not release their
observed owners. An owned observation is still an owned capture and must satisfy
the same Release bound. Empty environments also support explicit release; no
release is scheduled implicitly. A structural function value owns nothing, so it
implements `Release` as well, and releasing it does nothing: a `Vec` of function
values releases as a vector of numbers does.

A capturing closure has a concrete inline environment, and its field ownership
determines its copyability and settlement capability. Copying observations
requires explicit `copy`; no capture or closure construction copies an owner
implicitly. A capturing closure cannot convert to a structural function pointer,
because a code pointer holds no environment. Noncapturing closures may convert to
an exact structural code pointer.

A closure is kept behind one type by `mem.Closure`, whose first argument must be a
`fn` or `inout fn` type and whose callback must be callable as that type; its
rules follow from the contract and capture rules above and are stated with the
standard library ([mem/closure.lin](../std/mem/closure.lin)).

**[O-Universe]** A concrete copyable declaration cannot contain a known
noncopyable owned part. Report the part that prevents copying. Generic copyable
declarations are conditional: a substituted affine or Linear part removes
copyability without invalidating the generic declaration. Ordinary wrappers
inherit mandatory consumption from their owned parts. Declaring linear does not
grant copying, and linear and copyable modifiers cannot be combined.

### §5.3 Copying

```
let snapshot = copy(a);
let n = a.balance;
```

`copy(p)` produces a value **independent of `p`**: no later operation on either
value is observable through the other. Independence begins when `copy(p)` is
evaluated, regardless of when its result is consumed, so `f(copy(p), …)` cannot
receive changes made to `p` before the call begins.

Built-in numeric and Boolean values and copyable payload-free enums take implicit
snapshots in value-consuming positions, including indexed, field, and borrowed
places. The scalar source is not moved and its owner's lifetime is not retained in
the snapshot. Place-demanding operations still select storage. Records, arrays,
views, observations, callable descriptors, and nominal newtypes do not receive
this scalar exception.

**[O-Copy]** Explicit copying requires Copyable permission. Affine and Linear
values cannot be duplicated, including through generic instantiation.

**[O-ScalarCopy]** An explicit copy of a concretely known snapshot type is
rejected; read that scalar directly. Authored types are checked before
specialization: a symbolic `T: Copyable` can be copied even when later
instantiated with a scalar, while a concrete scalar expression in a generic body
is rejected. Generated code follows the same rule.

**[O-LinearWalk]** A `for` with a Linear iterator is rejected. The loop abandons
its iterator when iteration ends and has no written operation to consume it.
[T-For] checks whether the walked value implements `Sequence`; [O-LinearWalk]
checks whether the iterator it produces may be discarded. The report says what
the abandoned iterator owes, read through its type arguments: linear items it has
not handed over, or storage from an allocator. It teaches the lent walk,
`for x in &name`, after which the owner settles the iterator with an operation it
chooses, such as `finish()`; a head that is not a name is bound to one first. A
lending walk also creates and abandons an iterator through its traversal; the
same rule applies, checked at the traversal declaration instead of at each walk.

**[O-Lent]** While a construct lends a place, another operation on an overlapping
place is rejected if either access may write. The lend lasts for the `match read`
arm or the body of a `for read` or `for inout`, where its binder remains
available. A `let read` binder is not enclosed by such a construct; its lend ends
at its last use and [O-Borrow] checks it instead. Multiple `read` lends and other
reads may coexist. A read through a pattern binder of the lend, such as
`let read P { x } = p` inside `for inout p`, is a use of that lend. A lend that
may write requires exclusive access: no separate read, write or lend may overlap
it. Each binder of a pattern lends the part its path selects, at any depth, so
two binders of one pattern lend different places and a write through one leaves
the other's part alone; a binder the body never names lends nothing. Access
through the binder uses the existing lend, so `for inout x in xs { x = x * 2 }`
is allowed.

The overlap relation is the same as [N-Aliased]. That rule compares places passed
to one call; [O-Lent] compares an operation's place with places lent by enclosing
constructs. A `match read` binder names the part selected by its pattern,
allowing writes to disjoint parts: `pair._1 = 7` beside a binder of
`(Some(first), _)` writes a part the binder does not name. A walk's element is a
position not known statically, so the check conservatively treats it as every
position in the container, and any write to those positions overlaps it; a
binder of a walk's tuple pattern names its own component of that element. All
overlap checks occur at compile time, with no generated runtime check.

**[O-LinearTail]** A `for` over an array with Linear elements is rejected if
control can leave before the last position. The walk moves each element as it
visits it. A `break`, `return` or `?` can leave later elements unconsumed;
`return` and `?` leave every enclosing loop. The whole array was already consumed
at the loop head, so no remaining binding can be destructured to consume those
elements. [O-LinearWalk] concerns the iterator abandoned at the end of iteration;
[O-LinearTail] concerns elements abandoned by an early exit. Exhausting the array
satisfies [O-LinearTail]: each element has moved to the body, which is
responsible for settling its obligations. Discardable elements create no such
obligation, so the check depends on the element's settlement capability.

**[O-CopyRead]** `copy` in a reading position is rejected. The position does not
consume a value, so the copy has no effect.

**[O-CopyDead]** `copy` whose source is never read again is rejected. The copy
has no effect; use a move instead.

Both are errors because `copy` is a semantic assertion that the result is an
independently usable value, not a performance hint or a copy the compiler may
implicitly insert. Copied observations still
depend on their backing owners. Rejecting ineffective copies ensures that every
written assertion has an effect on the program's meaning.

### Read-only observations

`borrow T` is a `Copyable`, pointer-sized observation of an existing `T` place.
`borrow place` introduces the observation; it does not consume or copy the
referent. Its source must have storage, including an owned pattern binder or a
selected field. A temporary value cannot supply its own escaping storage.

For `b: borrow T`, `*b` names the observed `T` as a read-only place. One
dereference crosses one observation layer. Field selection follows observation
layers transparently: `b.field` selects the referent's real field, including a
field named `value`; there is no synthetic `value` member. Postfix selection
binds more tightly than dereference: `*b.field` means `*(b.field)`, while
`(*b).field` selects a field after one explicit dereference. Field and index
selections through an observed place remain read-only: they cannot be assigned,
passed `inout`, or moved out of. A `Copyable` non-scalar referent still requires
explicit `copy(...)` to duplicate it. There is no implicit conversion from
`borrow T` to `T`. `copy(b)` duplicates the observation. `copy(*b)` duplicates
the observed value when copying that value is permitted; contained observations
preserve their backing dependencies.

An observation protects its source until the last use of every live value that
contains or forwards it. The protected place cannot be reassigned, moved,
disposed, or relocated during that interval. Separate fixed record fields are
disjoint. Borrowing an element of a container protects the whole container; the
language does not promise disjointness between dynamically selected indices. A
value cannot own storage and contain an observation of that same owned storage.
These rules also apply to arrays, enum payloads, closures, returned values, and
dynamically stored collection elements.

Callable signatures introduce source contracts with `where`, after their result
type. Contracts and generic type predicates share one comma-separated clause:
`-> T where carries(input), T: Copyable`. A lambda with an inferred result may
write `-> where borrows(source) { borrow source }`; an explicit result uses
`-> borrow T where borrows(source) { borrow source }`. Bare source clauses and an
empty `->` annotation are rejected. Contract keywords keep the same meaning for
named functions, structural callable types, and lambdas.

Callable source clauses describe dependencies at a boundary:

| Clause | Effect |
| --- | --- |
| `borrows(source)` | The result observes the source place and preserves its contained dependencies. |
| `carries(source)` | The result preserves dependencies already contained in the source value. It does not observe the source descriptor's storage. |
| `retains(destination: source)` | An `inout` destination can retain dependencies already contained in the source. |
| `retains(destination: borrow source)` | The destination can additionally retain an observation of the source place. |

Source paths name parameters and fixed fields and can dereference observations.
A message that prints a `fn` type's contracts names a parameter as `#n`, its
position counted from 1, because a parameter's name is not part of the type;
a program names the parameter, and a mismatch that prints such a clause says
so. What a callable requirement's result may carry from the callable itself is
implied by the requirement and written by no program, so a message leaves it
out. `carries(reference)` preserves the descriptor's
dependencies; `carries(*reference)` preserves those contained in its referent.
Retention destinations cannot cross readonly observation storage. A clause can
list several sources. `borrows` and `retains` require a source; only `carries()`
admits an empty source list. A result with one eligible source can omit its
result clause; multiple eligible sources require an explicit clause, except that
the one carrier among them settles the choice with the contract of `carries` of
that parameter. `carries()` explicitly promises an independent result and
suppresses source inference. A callable type whose sources would otherwise be
inferred is written with `carries()` in diagnostics, so its text reads back as the
same type. Retention is declared explicitly. A `sink` parameter cannot supply its
own place to an escaping observation. Bodies are checked against these contracts,
including explicit returns, trailing expressions, and writes through `inout`
destinations. Callable types retain source contracts as part of their signature.

A **carrier** is a struct or enum declared `@carrier`: values built from it live as
long as it does. A signature that writes no `where` clause and has exactly one
parameter whose type is a carrier, after alias expansion and for any
instantiation, whatever the parameter's convention, and several eligible sources
for a result that may carry dependencies, means exactly what
`where carries(that parameter)` means. The carrier settles a choice among several
dependency sources; it never overrides a single inferred source, and never a lent
place: where a parameter other than the carrier lends the place the result
observes, the signature stays ambiguous, and where the carrier is the place the
result observes, the contract is `borrows` of the carrier. This is a property of
the signature, so it holds for a bodyless declaration, a trait signature, a
function value and a callable type alike. Any written clause, `carries()`
included, replaces the default. With two or more carrier parameters there is no
default, and an ambiguity that remains is [T-BorrowContract], naming the
carriers. The body is checked against the default as against a written clause, so
a result that comes from another parameter is [O-Escapes], reported with the
carrier that supplied the contract and the clause that would describe the source.
Nothing is inferred from the body.

A member of a trait implementation that writes no clause adopts the contract its
trait signature declares, instead of inferring one
([ADR 0164](adr/0164-a-trait-implementation-adopts-its-traits-contract.md)). The
signature's sources and destinations name the member's parameters in the same
positions, whatever the member calls them, so a generic trait's contract reads
through the implementation's arguments like the rest of the signature. The rule
covers every implementation of the trait: ordinary, `default`, and those a
`template` supplies. The signature's own contract, written or inferred, is the
one adopted; if its inference is ambiguous or a clause it wrote is refused, that
is its only error and the member is not checked against a contract. Nor is a
member that does not match its signature: the mismatch is its error. Otherwise
the member's body is checked against the adopted contract, and a result it does
not cover is [O-Escapes], naming the signature it adopted. A member that writes
its own clause keeps it and may promise less than the signature; it cannot
introduce effects outside the signature's promise ([T-BorrowContract]). A call is
checked against the trait signature in both cases. Inherent methods and free
functions infer as above.

A result clause can target a contained component: `carries(.Ok: allocator)` or
`borrows(.Ok.view: source)`. Targets follow fixed record fields and named enum
variants with exactly one payload. They never cross an observation into external
referent storage. Multiple sources share one target, and clauses can be repeated.
Dependencies assigned to `.Ok` do not contaminate the `.Err` payload.

`carries` and `retains` are upper bounds on possible dependencies, including for
`sink` parameters. An independent result is permitted under a carried-source
bound. The ordinary consuming position transfers or disposes the owned input; a
source clause does not impose a second pool-preservation obligation. A single
generic callback API can therefore accept both an input-consuming conversion and
an identity that forwards borrowed data.

Allocator handles obey these same rules: copying an allocator preserves its owner
dependencies, and a handle that borrows an arena conflicts with moving or
releasing the arena while it is live.

**Owned values.** A type is **Owned** when none of its values can carry a
dependency: nothing reachable through its fields, variant payloads, array
elements, newtype base, closure environment or stored container elements is an
observation, a view, or a value holding one. Built-in scalars, a struct of them,
a linear file owner and `Vec[UInt8]` over the system allocator are Owned; `Str`,
`mem.Slice[T]`, `borrow T`, a closure holding a lent place and
`Vec[UInt8, mem.Handle]`, whose allocator borrows its arena, are not. Being Owned
is independent of copying and settlement. A type parameter carries dependencies
unless it is bounded `Owned` or `Integer` ([T-Bound]), and so does an
associated type read through one unless the declaration bounds it `Owned`;
inside the declaration
that bounds it, a value of that parameter is never an eligible contract source
and adds nothing to a result or to an `inout` destination, so copying an element
of `items: mem.Slice[T]` into a vector needs no `retains` clause when `T` is
Owned. The bound narrows only that parameter: another source the body stores
must still be declared ([O-Escapes]). A dependency never comes from an Owned
type, so substituting any admitted argument keeps a body checked with the
parameter unseeded correct.

**Shareable values.** A type is **Shareable** when two tasks may read one value
of it at once, because no read of it writes. A type is not Shareable when it is
declared `@unshareable`, or when anything reachable through its fields, variant
payloads, array elements, newtype base, closure environment, type arguments or
the referent of an observation is not: an observation lets whoever reads it
read its referent. `mem.Arena` is `@unshareable`, since a handle's `acquire`
takes the handle by `read` and advances the arena's cursor; `mem.Handle`
borrows its arena, so it, `Vec[UInt8, mem.Handle]` and `borrow mem.Arena` are
not Shareable;
`mem.AllocationLog` is `@unshareable` too, since its allocator writes the log
under a `read`. A type
parameter is not Shareable unless it is bounded `Shareable` or `Integer`, and
neither is a function value, which may hold anything. Being Shareable is
independent of being Owned: an arena owns its memory and carries nothing yet
is not Shareable, and `borrow UInt64` is Shareable and not Owned. It is
independent of copying too: a `mem.Handle` is copyable, and every copy borrows
the one arena and reaches its cursor. Being unshareable restricts only observation: an unshareable
value moves, copies and settles as its declaration says.

**Carried dependencies.** `mem.Carried[H]` is a zero-sized field type that
carries every dependency a value of `H` may carry, read observations and
exclusive `inout` lends alike, without holding or owning an `H`
([ADR 0250](adr/0250-tasks-are-structured-through-linear-sessions.md)). A value
holding one, at any depth (a field of a nested structure, an enum payload, a
tuple, a type argument such as `Option[T]`, or a closure capture), may carry
whatever `H` may, and may hold a writer exactly where `H` may, so a lend it
carries stays exclusive where `H` is a closure. `Carried[H]` is Owned exactly
when `H` is. The holder gets the dependencies through its constructor's
contract:

```linea
import std.mem

struct Ticket[F] {
    number: UInt64,
    held: mem.Carried[F],
}

fn issue[F: sink fn()](sink body: F) -> Ticket[F] where carries(body) {
    body()
    .{ number = 1, held = .{} }
}
```

A ticket issued for `sink [inout seen] || { seen += 1 }` keeps `seen` lent
until the ticket's last use, so a read or write of `seen` before then is
[O-Borrow], and the ticket cannot leave the function that lends `seen`
([O-Escapes]). A dependency is held by the parts that can carry it, so reading
the ticket's `number` does not use the lend; passing, matching or settling the
whole ticket does. `Carried[H]` has no fields, so it adds nothing to a layout
and nothing to settle, and it is Copyable and Discardable whatever `H` is: it
owns no `H`, and the holder's own declaration decides whether the holder may be
copied or dropped. Each copy of a copyable holder carries the same facts. A
holder whose `H` keeps running after the holder is gone must be linear, so that
its settlement comes after that `H` has finished.

Dependencies form conservative sets. A collection can retain views from several
independent owners. Removing an element transfers its contained observations
without borrowing the container's own storage; its dependency set may
conservatively include the other owners represented in that collection. Replacing
a fixed field replaces that field's dependency set.

A `read` parameter whose place supplies a returned or retained observation
receives the caller's stable storage address, including for a scalar. A constant
is a place, so the observation it supplies depends on nothing. An argument that is
not a place is evaluated into a temporary whose address the parameter receives,
and the temporary lives until the end of the call's statement ([O-Temporary]). A
parameter used only by `carries` may receive a temporary descriptor: the returned
view observes its backing storage, not the descriptor temporary.

A trait is structurally forwarded through `borrow T` only when every occurrence
of `Self` across its complete surface and supertraits is the entire type of a
`read` parameter. Returning, nesting, consuming, or mutating `Self` prevents
forwarding of the whole trait. Generic inference keeps the type `borrow T`;
selected calls read the observed value and invoke the underlying implementation
without creating an owned value. An observation can also have its own trait
implementation, declared in the trait's module using
`impl[T] Trait for borrow T`. An explicit implementation takes precedence before
forwarding through each observation layer. Associated member types come from that
selected implementation; a generic function cannot assume that an observation and
its referent have equal associated member types. Readonly methods can also adjust
their whole-`Self` read receiver through an observation when other methods
prevent whole-trait forwarding. Dot and qualified calls use the same candidate
rules, including ambiguity and explicit observation implementation precedence.
This does not grant mixed-trait conformance at a generic bound or allow writes or
noncopyable consumption through an observation. The observation's `Release`
implementation discards only the observation and requires no `Release`
implementation for the referent.

`mem.Slice[T]` is a read-only span over initialized contiguous elements. Only
checked storage operations can introduce its backing address, and a copy or a
subspan keeps the original backing dependencies. Its iterator yields `borrow T`
observations that carry the backing owner's dependencies rather than borrowing
the iterator ([mem/slice.lin](../std/mem/slice.lin)).

### §5.4 Positions

Every occurrence of a value occupies either a consuming or a reading position.
Its position determines whether it moves.

**Consuming positions** take the value: the right-hand side of a `let` or plain
assignment, an argument to a `sink` parameter, a `return` operand, a function's
trailing value, a variant payload, a structure field initialiser, a structure
literal's base, and the scrutinee of a plain `match`.

**Reading positions** observe the value: operator operands, conditions, arguments
to `read` or `inout` parameters, the scrutinee of `match read`, the initializer of
`let read`, and the subject of field access. The right-hand side of a compound
assignment is an operator operand, so `a += b` leaves `b` unchanged just as
`a = a + b` does.

Expressions that supply a construct's **value** inherit that construct's
position. These include `if` branches, `match` arms, block trailing expressions
and `break` operands. Thus `record(if c { p.x } else { p.y })` observes the
selected field just as `record(p.x)` would.

A consuming position moves an aggregate regardless of its category. Its source
becomes `moved`, and subsequent reads are errors. A Copyable aggregate may be
duplicated first with `copy`; an Affine or Linear aggregate may not. Scalar
snapshot types produce an independent scalar instead of moving their source. At
scope exit, Discardable bindings may be omitted without running code; a Linear
binding still holding a value is a leak.

A move takes a **whole binding**. Partial moves are forbidden. Reading a part
observes its containing value regardless of the part's type: `a.balance` reads
`a`. Moving a part is [O-Move] because the place is not a whole binding. A scalar
part produces a snapshot in a value position. Use `copy(a.details)` to obtain an
independent Copyable aggregate part.

### §5.5 What is checked

**[O-Move]** The following are rejected: using a moved or uninitialised binding;
moving part of a binding; moving from a `read` parameter; moving from a
`match read` or `let read` binder; and moving a binding that another argument
of the same call lends. Use-after-free and double-free both access a moved
root, so they share this rule and diagnostic code.

A call lends every argument it does not take, and its receiver, for as long as
the callee runs, which is after every argument has been evaluated. A place such
an argument names, or that a branch of it yields, is held from where the
argument is evaluated until the call is made, so taking it in a later argument
is a use after a move whichever way the arguments are written:
`both(v, v)` with the second parameter `sink` would have the callee read `v`
after it took `v`, and is rejected exactly as `both(v, v)` with the first
parameter `sink` is. A take anywhere inside a later argument counts: a nested
call, a `let` in a block, or a structure literal's field; a take on a path that
leaves before the call is made, such as a branch ending in `return`, lends
nothing it takes from. An operator is a call of the operation its trait
declares, so `a == b` lends both operands until the comparison runs, and
`p == same(p)` with `same` taking `p` is rejected the same way. A field lent beside
its whole, `f(s.items, s)`, names the root the move takes. Two lends of one
place share it, and `f(p, copy(p))` lends `p` beside a copy of it. A scalar
snapshot lends nothing. A view or a capture of the place passed beside its
owner is an observation, and the take that ends it is [O-Borrow].

Writing a field uses its containing binding: `p.f = v` reads `p` to locate the
field. The read is invalid if `p` has moved, even on the left-hand side of `=`.
Only whole-binding assignment reinitialises a moved binding; writing one field
cannot restore the rest or permit a second consumption.

An expression typed `Never` has no local successor ownership state. Its operands
are checked in evaluation order, and `return`, `break` and `continue` transfer the
resulting state to their destinations. Panic and other traps have no destination
and run no deferred cleanup. Live Linear values do not leak on a path that
terminates the process.

**[O-Leak]** A Linear value is leaked when its binding remains initialised at
scope exit, a consuming `match` leaves its contents unnamed, a write overwrites
it, or a structure literal writes over a field of its base that holds one.
`let _ = k` is not exempt: `_` marks intentional non-use, not permission to
discard a Linear value. The report names the operations that settle the value,
and where it is left on an early exit and its type implements `Release`, the
schedule that settles it on every path: `defer let` or `defer var` for a
single-name binding, and `defer name.release()` where it is bound otherwise.

A consuming arm can discard a payload with `_` or by naming the variant without
binding its contents: `Has =>` and `_ =>` have the same effect. The match has
already consumed the scrutinee, so an unnamed payload has no owner. The check
uses the value's type regardless of whether the scrutinee was named or temporary.
`let … else |_|` discards a failed `Result`'s error the same way, so a Linear
error bound to that `_` is leaked.

Destructuring a Linear enum whose variants have no payload consumes it fully. A
`_` arm over that enum is therefore allowed: it abbreviates an exhaustive list of
payloadless variants and leaves no contents unconsumed. This exception does not
apply to type parameters, since the generic body is checked once for every
instantiation: `match x { _ => .. }` over `sink x: T` is a leak, just as an
unbounded `T` is treated as Linear in that body.

The overwrite check applies to every written place, whether a whole binding or
one of its parts, and to all writes, including `+=` and the other four compound
assignments. §5.4 classifies where an input value **appears**; [O-Leak] also
checks the destination where it **goes**, because the destination may already
hold a Linear value. A move transfers the consumption obligation with the value
and leaves its source `moved`; an overwrite replaces the old value without
transferring it to another owner, so its obligation cannot be fulfilled.

The destination's own settlement obligation determines whether an overwrite
leaks. Both a whole Linear binding and a Linear part of a binding are protected.
Overwriting a discardable part of a linear value is allowed because that part
needs no disposal. An overwrite in a loop can lose one value per iteration;
[O-Loop] does not cover it because overwriting does not move a binding.
Likewise, moving a `sink` parameter into a local transfers the obligation to
that local, where an overwrite can leak it.

Overwriting an `inout` parameter destroys the caller's value, so the callee is
checked. [O-Reinit] only requires the parameter to be initialised at every exit;
an overwrite may satisfy that requirement while violating [O-Leak]. Both checks
apply: the final state must be initialised, and the previous value must have
been consumed.

A structure literal with a base takes the base whole and drops each field it
writes over. Such a field is checked by its declared type, as an overwritten part
is: `Booking { ticket = fresh, ..booking }` leaks `booking`'s old ticket when
`Ticket` is Linear, and a field whose type is a type parameter is checked as the
parameter's bounds allow, so an unbounded `T` counts as Linear. The leak is
reported at the written field, with the base named beside it. A replaced field
that owes nothing is dropped silently, and fields the literal does not write move
into the new value with their obligations.

Scope exit, an unnamed payload, an overwrite and a replaced field all leave a
Linear value consumed zero times, so they share [O-Leak].

A leak is reported once per value, where the fix is written. A binding still
owned when a path leaves by `return`, `?`, `break` or `continue` is reported at
the first such exit in the source, with the binding named where it was acquired
and every other exit that leaves it owned named beside it. A binding that is
only still owned where its scope ends is reported at the binding, with the end
of the block named. An overwrite is reported at the write, and an unnamed
payload at the arm that drops it. For `let _ = k`, the `_` is labelled as not
settling the value, as the report's primary location or beside the exit that is.
The report names the binding, or for one a derive generated the field or payload
it holds, and the value's type as the function's module writes it, arguments
included.

A help line names up to three operations that a postfix call written in the
function's module runs on the value and that settle it: they take the value by
`sink` and their result owes no settlement. They are listed in the order the
postfix lookup yields them, the type's own and then those of traits in scope,
and an own operation is named only where its block's bounds hold for the value's
type. Where no operation in scope settles the value and a trait out of scope
would, the help names that operation with the `use` that brings the trait in.
Taking the value apart is suggested only where the module may do so and doing so
settles everything it holds.

A postfix call that reaches no operation is refused, and with no operation there
is no saying whether it would have settled its receiver or its arguments. A
binding such a call names is therefore not reported under [O-Leak]; the refused
call is the error.

Consume the existing value, or move it to another owner, before writing a
replacement. A `moved` or uninitialised destination has no value to lose, so
writing it is allowed and can satisfy [O-Reinit]. `k = k` also does not leak: the
consuming right-hand side takes the value before the destination is written.

**[O-Merge]** Paths into a join must agree about the state of a Linear binding,
and of a binding that a `defer` able to run after the join, before the binding is
assigned again as a whole, consumes. Other bindings merge pessimistically
(`init ⊔ moved = moved`), with any later use reported as an error. For a Linear
binding, choosing `moved` would hide a leak on one path, while choosing `init`
would permit double consumption on the other; for a deferred binding the same two
choices skip the schedule where it should run, or run it where the value is gone.
The disagreement is reported at the join, once: a later join that only inherits
it is not reported again. A path that leaves the join's scope keeps an answer of
its own, so a value given away on a path that returns is not a disagreement.

A `defer` whose schedule has already run consumed its value where it ran, as the
same call written there would. A `defer lock(k)` in an `if` body or a `match` arm
gives an affine `k` away on that path, and after the join `k` is moved, exactly
as after a direct `lock(k)`. A binding ends with the block that declares it, so a
join after a block compares nothing about a binding declared inside it.

**[O-Reinit]** An `inout` parameter must be initialised on every path to an exit.
Moving from it is allowed, but each path to a `return` or the body's end must
reinitialise it.

**[O-Uncommitted]** A `return`, `break` or `continue` cannot leave a construct
with a pending transfer of a Linear value. Transfer to a call commits when the
call begins: the source owns the value before then, and the callee owns it
afterwards. Leaving during argument evaluation would produce a reachable state
with an unowned value. Temporaries are checked too: `use2(key(), return 7)`
abandons a `Key` produced by `key` before `use2` can take it. The rule applies to
values regardless of whether the program gives them names.

Argument lists, structure literals, variant payloads and tuple literals can hold pending
transfers because they accept several values before completing. These constructs
can nest; completing an inner construct commits only its own transfers. The same
rule applies to any construct that combines several values in this way.

The lexical position of a jump determines which constructs it leaves. A `break`
exits through its target loop, including intervening loops; a `return` leaves the
whole body. Exiting a loop used as an operand need not abandon the surrounding
construct: `use2(d, loop { break key() })` is allowed by this rule, since the loop
yields and the call begins. Only a construct's own operands remain pending on it.
A `let`, assignment, `match` scrutinee or `return` receives its value at its own
location, completing that transfer there, and a later jump does not cross those
completed transfers. For a block argument, only the tail expression supplies the
surrounding construct's operand. A `break` operand supplies the loop's value at
the loop's position; from the `break` onward, that value is pending on the
construct receiving the loop's result.

Traps are not abrupt completion: they terminate execution instead of transferring
control to another reachable state, so this rule does not apply to them. The
invariant is that every Linear value has exactly one owner in every reachable
state. Abandoning a pending Discardable value creates no consumption obligation
and is allowed.

Evaluation order determines which check fails. `use2(d, return 7)` violates
[O-Uncommitted], while `use2(return 7, d)` does not; the latter still violates
[O-Leak] because `d` remains live when control leaves.

**[O-Loop]** Moving a binding declared outside a loop from within its body is
rejected at the move. A binding declared inside the loop is fresh on every
iteration and may be moved freely. This rule deliberately rejects safe programs,
including a move immediately followed by an unconditional `break`, so that
acceptance depends on a direct source rule rather than control-flow analysis.

**[T-BorrowContract]** Callable source clauses name declared parameters and
existing fields. Retention destinations are `inout`; escaping place observations
come from `read` or `inout` parameter storage, or use `*` to reach the external
referent of an observation carried by any parameter convention. Result targets
and retention destinations cannot cross observation storage. An ambiguous
inferred source requires an explicit `borrows` or `carries` clause; the ambiguity
is the only error reported, and the body is not checked against a contract nobody
declared. The report names each candidate's clause and the one clause listing them
all: `borrows` for a parameter it does not consume whose place the result may
observe, or that may hold storage of its own a view would point into and holds
no view; `carries` for one that holds a view, such as a `Str` or a struct with
one, for a type parameter its bounds make copyable, and for one it consumes. A consumed parameter ends with
the function, so no clause lets anything observe its place past the return, and
[O-Escapes] says so instead of naming one. Where several of the sources are carriers the report says so and
names them. A clause whose source, destination or target is refused is likewise the only
error: the body is not checked against what remains of the clause. A trait
implementation's member cannot promise more than its signature. Bodies must obey
these signature contracts.

**[O-Borrow]** A place observed by a live read-only borrow cannot be mutated,
reassigned, moved, disposed, or relocated before that observation's last use. A
place lent `inout` to a closure cannot be used at all, read included, while a
value holding that lend is live: no read, write, move, `&`, observation or second
`inout` capture may overlap it before the lend's last use. A value holds the lend
when it carries the closure's dependencies, through any `carries` contract and in
a type that can hold the writer, such as an adapter, a closure, or a type with a
`mem.Carried[F]` field for such an `F`; in any other value the lend is a read
observation. A `let read` binder observes the part its
pattern selected in the same way, whatever that part's type, until the binder's
last use. Copies and stored observations preserve the restriction. Disjoint
record fields remain independent; an observation of a container element protects
its container, and the binders of a lending walk's pattern share the walked
element's place, so a change through one ends an observation made through
another. Scope exits and deferred actions participate in the same check.

**[O-Escapes]** A returned or retained observation must depend only on the
sources its callable contract permits. A place lent `inout` to a closure never
leaves the function that lends it: no contract permits returning or retaining a
value that holds the lend. An observation of a constant, or of a part of one,
depends on nothing, because a constant's storage is static. So do a string
literal and an embedded file, whose bytes are static storage too: a function
declaring `carries()` may return `embed("page.html")` or its `as_bytes()`.
A trait implementation's member without a clause is held to the contract it adopts from
its trait signature. An observation of local storage cannot escape that storage's
scope, and copying or embedding the observation does not remove this restriction.
Replacing a statically known array slot removes that slot's previous carried
dependencies, including dependencies inherited from a parameter or callable
result; other slots retain their dependencies. A dynamic index cannot establish
which slot was replaced, except in a one-element array. At control-flow joins, a
previous dependency is removed only where every incoming path replaced it.

Exits include explicit returns, trailing expressions and writes through `inout`
parameters. Deferred owner disposal still occurs before the recipient can use a
returned observation, so returning a view into a local owner is rejected. An
independent owned value may leave its scope through the ordinary move rules.

A report is made once per exit for the observations leaving there, and once per
lend; it is placed where the escaping value took its dependency, following a
block to its tail and a local binding back to the value written into it. It
names the edit each source calls for, spelled as [T-BorrowContract] spells it:
the one clause listing every parameter the value comes from (`where
borrows(first, second)`), the retention clause for a value an `inout` parameter
keeps (`where retains(seen: field)`), or, for a local owner, that it ends when the
function returns. Each further place the value took a dependency is pointed at
as well. The clause named is the whole clause to write, and a function has one:
every report of one function names the same clause, listing every source its
escapes return and every retention its `inout` parameters keep, so writing the
clause any report names answers them all. One the signature wrote keeps its
sources, with a `borrows` written for a consumed parameter, which
[T-BorrowContract] refuses, named `carries`; one written where the signature
wrote none replaces the contract it inferred, so it also lists the sources that
contract covered at any exit: `where borrows(self), carries(other)`.

An observation of a local owner leaving the function is one mistake: the owner
ending, or a `defer` releasing it, before the observation's use outside is that
escape's consequence, and [O-Borrow] does not report it again. Where the local is
an allocator the function opens and what leaves was built in it, the report names
the form that takes the allocator as a parameter, `load_in` with `A: Allocator`
and `allocator: A` first, so the caller's allocator decides how long the result
lives, and the owned copy in the system allocator.

A member of a trait implementation answers to its trait's signature, and a
function received by a written callable type or a callable bound answers to that
type. Where that fixed signature does not permit the clause, the report names
the clause, says it cannot be added there, and offers what the program can
change: returning or keeping what the fixed signature permits, or widening the
trait or callable type where the program wrote it, and this signature with it.

Where the type holding the observation declares `to_owned`, the report also
offers the owned copy, which observes nothing and needs no clause, naming the
type that holds it and the failure copying can report: `Result[String, mem.Oom]`
for a result that was the view, `String` where a part of the result or an
`inout` parameter held it. Where a local owner of that type supplied the view,
it offers the owner itself instead, unless a `defer` releases the owner and runs
at no other exit of the function, where moving it would leave the `defer`
nothing to release. Under a
fixed signature the result type is fixed too, so a returned view is offered no
copy; a stored view still is, which is the fix for a route handler that keeps a
request's text in its state.

**[O-Cross]** A value crosses a task boundary as a capture of the body that
`task.start`, `task.start_in`, `task.prepare` or `task.prepare_in` takes for a
new task. The task runs on another
thread while its creator runs on, so what the body carries is used by both at
once until `close` joins the task. Every observation the body carries must
observe a `Shareable` place: a `read` capture's own observation of its source,
and every observation a captured value holds, a value moved in by a `sink`
capture included, one observation at a time. Two readers of a Shareable place
cannot race, since neither may write it while the handle lives ([O-Borrow]),
and a place that is not Shareable is written by a read. A value carrying an
exclusive lend crosses only as the body's own `inout` capture of the place:
the body is then the one writer, and the handle keeps every other use of the
place out until the join. A lend held by another value the body captures, such
as a closure moved in by `sink`, is refused. A body whose type is a type
parameter or a function value carries captures the function cannot see, so it
does not cross. The report is at the capture, names the place, and names the
part of its type that is not Shareable. An unshareable value itself still
crosses whole: a `sink` capture of a `mem.Arena` moves the arena, and only the
task reads it afterwards. A copyable value reaches shared state only through a
borrow of an `@unshareable` owner, since `@copyable` and `@unshareable` are
exclusive ([S-Entry]): every copy of a `mem.Handle` carries the observation of
its arena, so a copy moved in by `sink`, held in a record or erased into a
`mem.Closure` is refused like the handle itself.

```linea
fn main() -> UInt8 {
    defer let arena = mem.Arena.open(mem.system(), 64)
    let handle = arena.handle()
    let body = sink [read handle] |sink me: Chan[End]| {
        let _bytes = handle.acquire(8)
        me.close()
    }
    task.start(body).unwrap().close()
    0
}
```

The body reads `handle`, whose `acquire` advances the arena's cursor through a
`read`, while `main` could acquire from the arena too, so the capture is
[O-Cross]. A payload crosses under its operation's `Owned` bound instead:
`send` and `recv` take a `T: Owned`, so a session sends `text.String` and not
`Str`. A library value that writes storage another value owns observes that
owner, as the standard library's `ReleaseTag` observes the `ReleaseLog` it
writes, so the bound and this rule see the write
([ADR 0250](adr/0250-tasks-are-structured-through-linear-sessions.md) §5).

A task runs on its own operating-system thread. `start` orders everything
its creator did before it before everything the body does; a `send` returns
once the other end has received the value, and orders everything the sender
did before it before everything the receiver does after the `recv`; `close`
on the handle returns once the body has returned and its thread has been
joined, and orders everything the body did before everything after the
`close`. With [O-Borrow], [O-Cross] and the `Owned` payload bound, every
other location is reached by one task between two of these points, or only
read, so an accepted program has no data race and behaves at every
optimisation level as if its tasks' steps were interleaved one at a time. A
task's stack has guard pages below it, and every generated function probes a
frame larger than a page as it grows, so an overflow on any thread, `main`
included, stops the program with `linea: a stack overflowed`.

**[O-Temporary]** A value that is borrowed where it is written without being a
place, such as `log.field("count", 3)`'s `3`, an argument `base + 2` to a
parameter the result borrows, or an interpolated call whose result must be
settled, is evaluated into a temporary. The temporary lives until the end of the
statement that evaluates it, and a value borrowing it may be used only until
then: it may be passed, rendered and written within the statement, as in
`logger.info("counted", log.field("count", 3))`, but not used by a later statement
or returned. Binding such a value with `let` and using the binding afterwards is
refused; binding the borrowed value first gives it a place that lives as long as
its binding.

A statement here is an expression statement, a `let`, a `defer`'s expression
where it runs, a function's or closure's body, a `while` condition, and a loop
body, which is evaluated once per iteration. A block's trailing value, a
conditional's branches and a `match`'s arms belong to the statement around them,
so `logger.info("done", if ok { log.field("count", 3) } else { log.field("count", 0) })`
is accepted. A `break` or a `continue` ends the statements it leaves. A temporary
is discarded where it ends and runs no cleanup; one that must be settled is
refused by [O-Leak] as any unsettled result is.

A constant is a place, not a temporary: its storage is static, so a value
borrowing it, such as `log.field("service", SERVICE)`, may be kept or returned
anywhere ([ADR 0178](adr/0178-a-constant-is-a-static-place.md)).

## §6 Execution

The entry point's result is the program's value and becomes the process's exit
status ([ADR 0019](adr/0019-entry-point-is-main-returning-u8.md)).

No operation has undefined behaviour. Every operation produces a defined result
or a diagnosed failure, independently of optimisation level
([ADR 0013](adr/0013-no-undefined-behaviour.md)).

A non-constant operation that would exceed its type's range **traps**: execution
stops, the failure and source location are written to standard error, and the
process aborts. Traps cannot be caught and do not unwind. A trap produces no
program result or normal exit status, so abnormal termination distinguishes it
from every status the entry point can return
([ADR 0017](adr/0017-failure-is-a-trap-or-a-value.md)).

No accepted program uses storage after it is freed, disposes of an allocation
twice or at another size, or reaches outside an allocation: the ownership rules
and the checked storage accesses rule each of these out. A runtime built to check
storage, which `linea test` always links, aborts where a program would do one of
them anyway. It writes `linea: ` and what happened to standard error and aborts,
without a source location. Such an abort reports a compiler or runtime defect
rather than a failure of the program, so it names no rule, and a test expecting a
trap is not satisfied by it
([ADR 0197](adr/0197-a-checking-runtime-makes-a-use-of-freed-storage-abort.md)).

Generated programs identify six runtime trap failures by number. These numbers
are part of the runtime interface:

| | reports |
| --- | --- |
| 0 | integer overflow |
| 1 | division by zero |
| 2 | value out of range for its type |
| 6 | index out of bounds |
| 7 | misaligned access |
| 8 | not a number |

`3`, `4` and `5` are reserved for reaching unreachable code, a failed assertion
and a panic, respectively. New kinds are appended; existing kinds are never
renumbered, including around these reserved entries.

## §7 Diagnostics

A diagnostic names the violated rule. For example, `error[T-Mismatch]` refers to
the rule in §4 of this document.

A diagnostic includes a second location whenever one is relevant. A type mismatch
identifies both the expression and the annotation, return type or operand
requiring the type. An impossible conversion identifies where its value was
written. Some diagnostics have no second location: a literal too large for any
representation has only its own location.

Failures outside the language, such as an unreadable file or a missing toolchain,
have no rule name because they violate no language rule.
