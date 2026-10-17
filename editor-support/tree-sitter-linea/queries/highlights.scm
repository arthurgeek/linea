; Linea syntax highlighting. Keep in lockstep with grammar.js: a renamed node
; silently produces no highlight rather than an error.
;
; Reserved words are captured by role rather than by spelling. In a language
; where a convention keyword changes what a call does to its argument, `inout`
; reading like `if` costs a reader the one marker saying a value can change
; under them.

; -- Declarations ----------------------------------------------------------
"fn"     @keyword.function
"enum"   @keyword.storage.type
"struct" @keyword.storage.type
"template" @keyword.storage.type
"default" @keyword.storage.type
"derive" @keyword.storage.type
"impl"   @keyword.storage.type
"trait"  @keyword.storage.type
; A member of a trait and of its implementations, and an ordinary name
; everywhere else: the word is not reserved, so this reaches only the rule
; that spells it.
"type"   @keyword.storage.type
; Another name for a type at the top of a file. Contextual the way `type` is.
"alias"  @keyword.storage.type
; A member that yields a place. Contextual the way `type` is, and coloured as
; a declaration keyword rather than as `fn` is: what it introduces is not
; something a reader calls.
"proj"   @keyword.storage.type
; A member naming the positions a lending walk runs through. Contextual the way
; `proj` is, and coloured as the same kind of declaration keyword.
"trav"   @keyword.storage.type
"via"    @keyword.storage.modifier
"extern" @keyword.storage.modifier
; Opens a refinement or declaration constraint clause. Reserved, unlike `type`
; above -- a clause may sit on its own line, and a word a statement could begin
; would leave the continuation ambiguous.
"where"  @keyword.control
(reflection_root) @keyword.control
"in"     @keyword.operator
; The clause's own spelling of the value it is about, and the only one the
; compiler accepts. Not reserved: the grammar spells it inside the clause and
; nowhere else, so the word stays an ordinary name everywhere a program wants
; one.
"it"     @keyword.control
"for"    @keyword.storage.type
"import" @keyword.control.import
"use" @keyword.control.import
"as"     @keyword.operator

; -- Bindings and modifiers ------------------------------------------------
"let"    @keyword.storage
"var"    @keyword.storage
"pub"    @keyword.storage.modifier
"internal" @keyword.storage.modifier
"export" @keyword.storage.modifier
"opaque" @keyword.storage.modifier
"linear" @keyword.storage.modifier
"copyable" @keyword.storage.modifier
"carrier" @keyword.storage.modifier
"test" @keyword.storage.modifier
"trap" @keyword.storage.modifier
"phantom" @keyword.storage.modifier

; -- Parameter conventions -------------------------------------------------
"read"   @keyword.storage.modifier
"inout"  @keyword.storage.modifier
"sink"   @keyword.storage.modifier

; -- Control flow ----------------------------------------------------------
"if"       @keyword.control.conditional
"else"     @keyword.control.conditional
"match"    @keyword.control.conditional
"while"    @keyword.control.repeat
"loop"     @keyword.control.repeat

; The `for` of a walk, which the bare pattern above paints as the `for` of an
; `impl T for U`. Written as a pattern over the node rather than over the word
; because one word spells two things, and the later pattern is the one that
; wins where both match.
(for_expression "for" @keyword.control.repeat)
"break"    @keyword.control.return
"defer" @keyword.control
(continue_expression) @keyword.control.return
"return"   @keyword.control.return
"panic"    @keyword.control.return

; -- Duplication is explicit, so it reads as an operation ------------------
"copy" @keyword.operator

; -- Types and literals ----------------------------------------------------
(self_type) @type.builtin
(array_type length: "_" @constant.builtin)
["true" "false"] @constant.builtin.boolean

(type_identifier)  @type
(integer_literal)  @constant.numeric.integer
(float_literal)    @constant.numeric.float
(string_literal)   @string
(escape_sequence) @string.escape
(escaped_open_brace) @string.escape
(line_comment)     @comment

; A primitive is an ordinary name to the parser, so it arrives as a
; `type_identifier` like every written type and only its spelling tells it
; apart. Matched rather than given a node of its own: a node would be a second
; definition of what a primitive is, and the compiler already has the first.
;
; After the general rule above, because the last pattern capturing a node is
; the one that colours it. Written before it, the narrower pattern matched and
; was then overwritten by the rule it was meant to refine, so every primitive
; read as an ordinary name.
((type_identifier) @type.builtin
 (#match? @type.builtin "^(Int8|Int16|Int32|Int64|UInt8|UInt16|UInt32|UInt64|Bool|Float32|Float64|Never)$"))

; -- Names -----------------------------------------------------------------
; The general rule first, for the reason the primitives sit after theirs: what
; a name is used for is what colours it, and the rules below say what that is.
(identifier) @variable
(function_declaration name: (identifier) @function)
(provided_operation name: (identifier) @function)
(call_expression callee: (identifier) @function)
(instantiation_expression function: (identifier) @function)
(call_expression callee: (index_expression
  head: (identifier) @function
  index: [(identifier) (index_expression)] @_type
  (#match? @_type "^[A-Z]")))
; A bracket holding one name before a call is an index to the grammar, and
; only the compiler knows whether the name before it reaches a function whose
; type arguments the bracket holds. A capitalised name there is coloured as a
; type, because the compiler holds every type name to a capital first letter
; and every value name to a lowercase one; `steps[at](5)` stays a variable.
(call_expression callee: (index_expression
  index: (identifier) @type
  (#match? @type "^[A-Z]")))
(call_expression callee: (index_expression
  index: (index_expression head: (identifier) @type)
  (#match? @type "^[A-Z]")))
((call_expression callee: (index_expression index: (identifier) @type.builtin))
 (#match? @type.builtin "^(Int8|Int16|Int32|Int64|UInt8|UInt16|UInt32|UInt64|Bool|Float32|Float64|Never)$"))
(parameter name: (identifier) @variable.parameter)
(named_argument name: (identifier) @variable.parameter)
(field_expression field: (identifier) @variable.other.member)
(template_requirement target: (identifier) @variable.other.member)
(template_requirement components: (identifier) @variable.other.member)
(impl_block delegate: (identifier) @variable.other.member)
(traversal_declaration delegate: (identifier) @variable.other.member)
(field name: (identifier) @variable.other.member)
(field_initialiser name: (identifier) @variable.other.member)
(field_pattern name: (identifier) @variable.other.member)
(variant name: (type_identifier) @constructor)
(variant_reference (type_identifier) @constructor)
(variant_pattern (type_identifier) @constructor)

; -- Operators and punctuation ---------------------------------------------
["+" "-" "*" "/" "==" "!=" "<" "<=" ">" ">=" "=" "&" "!" "&&" "||" "|" ".." "..=" "^"] @operator
(format_selector ":" @operator)
(format_spec) @operator
(interpolation ["{" "}"] @punctuation.bracket)
["->" "=>"] @punctuation.delimiter
["(" ")" "{" "}"] @punctuation.bracket
; `()`, the one value of the unit type, is a built-in constant as `true` is.
; After the bracket rule, because the last pattern capturing a token colours it.
(unit_expression ["(" ")"] @constant.builtin)
["," ";" ":" "." "@"] @punctuation.delimiter

"borrow" @keyword.operator
"borrows" @keyword.storage.modifier
"carries" @keyword.storage.modifier
"retains" @keyword.storage.modifier
