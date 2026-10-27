// Linea's grammar for tree-sitter. Permissive on purpose: this is not a second
// implementation of the parser and must not become one. Its job is a tree good
// enough to colour and to navigate, over source that is broken most of the time
// it is read -- so where the real parser diagnoses, this accepts.
//
// The two survive broken source in opposite ways. The compiler's parser
// recovers: it knows what is wrong, says so, and resynchronises. This one
// accepts: it has no diagnostics and no downstream pass with an opinion, and
// being approximately right about a construct beats being unable to say
// anything about the rest of a file because line 12 is half-typed.
//
// Node names here are what queries/*.scm capture. Renaming one silently
// produces no highlight rather than an error, so a rename is a change to both.

// The most `#` that may open a raw literal: the language bounds the count, so
// one expression per count recognises every raw literal the compiler accepts.
const max_raw_hashes = 8;

module.exports = grammar({
  name: 'linea',

  extras: $ => [/\s/, $.line_comment],

  word: $ => $.identifier,

  // `_type` is `_result_type` or `()`, substituted where it is written so
  // that a written type and a written result reduce through one rule.
  inline: $ => [$._type],

  conflicts: $ => [
    [$.capture_list, $.array_literal],
    [$._expression, $.capture],
    [$.literal_type, $._expression],
    [$._result_type, $._type_only],
    [$.type_arguments, $._type_only],
    [$.call_type_arguments, $.call_generic_arguments],
    [$.call_type_arguments, $._call_type],
    [$._expression, $.call_only_generic_type, $.call_generic_type, $.literal_type],
    [$._result_type, $._call_type],
    [$._result_type, $._expression],
    [$._result_type, $._expression, $.literal_type],
    [$.callable_type],
    [$.contract_clause],
    [$.call_expression, $.instantiation_expression],
    // `f[()]` holds a type argument or an index, as the compiler reads it both
    // ways until resolution says what `f` names.
    [$.unit_type, $.unit_expression],
  ],

  rules: {
    // `newtype_declaration` sits here rather than in `_declaration`: that
    // rule is shared with an `impl`'s body, where `type Item = UInt8` is
    // `associated_type` and the two would name one sequence two ways.
    // Position is what tells them apart in the language itself -- a
    // module-level declaration and a member never share a rule the real
    // parser reads either -- so the grammars agree by construction rather
    // than by a precedence one of them wins.
    source_file: $ => repeat(choice($._declaration, $.newtype_declaration, $.alias_declaration)),

    line_comment: _ => token(seq('//', /.*/)),

    _declaration: $ => choice(
      $.function_declaration,
      $.extern_declaration,
      $.enum_declaration,
      $.struct_declaration,
      $.impl_block,
      $.template_impl_block,
      $.derive_declaration,
      $.import_declaration,
      $.use_declaration,
      $.trait_declaration,
      $.constant_declaration,
    ),

    visibility: _ => choice('pub', 'internal'),

    // Attributes precede ordinary visibility and attach only to nominal types.
    attribute: $ => seq('@', choice($._attribute_item, $.attribute_group)),

    attribute_group: $ => seq('(', commaSep1($._attribute_item), ')'),

    _attribute_item: $ => choice($.policy_attribute, $.derive_attribute),

    policy_attribute: _ => choice('opaque', 'linear', 'copyable', 'carrier', 'unshareable'),

    derive_attribute: $ => seq('derive', $.derive_traits),

    // `[T, E: Copyable + Weigh]`. A bound travels with the parameter it is
    // written on, so the list is the whole of what a declaration says about
    // the types it is generic over.
    type_parameters: $ => seq('[', commaSep1($.type_parameter), ']'),

    // `phantom` declares a parameter read for identity alone. A struct, an
    // enum, an alias or a function may end the list with defaults:
    // `A: Allocator = SystemAllocator` is the argument a written type or a
    // call may omit.
    type_parameter: $ => seq(
      optional('phantom'),
      field('name', alias($.identifier, $.type_identifier)),
      optional(seq(':', sep1($.bound, '+'))),
      optional(seq('=', field('default', $._type))),
    ),

    // A bound names a trait and what it applies: `Index[UInt64]` bounds by
    // the trait applied to that argument, on the terms a written type's own
    // arguments already nest by.
    bound: $ => choice(
      $.trait_reference,
      $.callable_type,
    ),

    trait_reference: $ => seq(
      repeat(seq(field('module', $.identifier), '.')),
      field('name', alias($.identifier, $.type_identifier)),
      optional($.type_arguments),
    ),

    // `[UInt8, Cell[T]]`. An argument is itself a written type, so this nests.
    type_arguments: $ => seq('[', commaSep1($._type), ']'),

    // An `extern` declares an operation without a source body, so
    // it is a header ended by a line break the way a trait's signature is.
    extern_declaration: $ => seq(
      optional($.visibility),
      'extern',
      'fn',
      field('name', $.identifier),
      optional($.type_parameters),
      $.parameter_list,
      optional(seq('->', field('return_type', $._result_type))),
      optional($.where_clause),
    ),

    function_declaration: $ => seq(
      optional($.visibility),
      optional('export'),
      choice(
        seq(
          'test', optional('trap'), 'fn',
          field('name', $.identifier),
          optional($.type_parameters),
          $.parameter_list,
          optional(seq('->', field('return_type', $._result_type))),
        ),
        seq(
          'fn',
          field('name', $.identifier),
          optional($.type_parameters),
          $.parameter_list,
          optional(seq('->', field('return_type', $._result_type))),
        ),
      ),
      optional($.where_clause),
      field('body', $.block),
    ),

    // Constants infer from their initializer when the type is omitted.
    constant_declaration: $ => seq(
      ...modifiers($),
      'let',
      field('name', $.identifier),
      optional(seq(':', field('type', $._type))),
      '=',
      field('value', $._expression),
      // The compiler reads a constant's initializer as a binding's, `else` and
      // all, and refuses the `else` because a constant runs nothing.
      optional($.let_else),
      // Optional for the reason it is on an import: the line break is the
      // separator, and this grammar has none to see between tokens.
      optional(';'),
    ),

    parameter_list: $ => seq('(', commaSep($.parameter), ')'),

    parameter: $ => seq(
      optional($.convention),
      field('name', $.identifier),
      ':',
      field('type', $._type),
      optional(seq('=', field('default', $._expression))),
    ),

    convention: _ => choice('read', 'inout', 'sink'),

    enum_declaration: $ => seq(
      repeat($.attribute),
      ...modifiers($),
      'enum',
      field('name', alias($.identifier, $.type_identifier)),
      optional($.type_parameters),
      optional($.where_clause),
      $.variant_list,
    ),

    variant_list: $ => seq('{', commaSep($.variant), '}'),

    variant: $ => seq(
      field('name', alias($.identifier, $.type_identifier)),
      optional(seq('(', commaSep($._type), ')')),
    ),

    struct_declaration: $ => seq(
      repeat($.attribute),
      ...modifiers($),
      'struct',
      field('name', alias($.identifier, $.type_identifier)),
      optional($.type_parameters),
      optional($.where_clause),
      $.field_list,
    ),

    field_list: $ => seq('{', commaSep($.field), '}'),

    field: $ => seq(
      optional($.visibility),
      field('name', $.identifier),
      ':',
      field('type', $._type),
    ),

    // `type Name = Base`, and `type Name = Base where it in lo..=hi`. A
    // distinct nominal type over one base, with the attributes and visibility
    // a struct or an enum takes -- and `type` is not a
    // reserved word here either: a name follows it at the top of a file
    // exactly where a member cannot begin, so the two readings never meet.
    newtype_declaration: $ => seq(
      repeat($.attribute),
      ...modifiers($),
      'type',
      field('name', alias($.identifier, $.type_identifier)),
      '=',
      field('base', $._type),
      optional($.refinement_clause),
    ),

    // `alias Name = Type`, and `alias Name[T] = Type`. Another name for a
    // type that exists. The compiler reads the attributes and modifiers a
    // declaration may carry and refuses those an alias cannot take, so the
    // grammar reads them too. `alias` is contextual the way `type` is: a name
    // follows it only here.
    alias_declaration: $ => seq(
      repeat($.attribute),
      ...modifiers($),
      'alias',
      field('name', alias($.identifier, $.type_identifier)),
      optional(field('type_parameters', $.type_parameters)),
      '=',
      field('type', $._type),
      optional(';'),
    ),

    // `where it in lo..=hi`. `it` is the refinement's own spelling of its
    // value and the only one there is, so it is written here as itself:
    // admitting any identifier derives `where n in 0..=9`, which the compiler
    // refuses. It stays an ordinary word elsewhere, because `word` maps every
    // keyword through the identifier token.
    refinement_clause: $ => seq(
      'where',
      'it',
      'in',
      field('lo', $._refinement_bound),
      choice('..', '..='),
      field('hi', $._refinement_bound),
    ),

    // A bound is a literal with the sign written on it. A signed base's range
    // is mostly negative, so `-40..=40` is the ordinary way to write one.
    _refinement_bound: $ => seq(optional('-'), $.integer_literal),

    // A source implementation may name a declared constructor, Unit, a tuple,
    // a borrow or, after `for`, a callable type. Arrays have no source-owned
    // coherence head.
    impl_block: $ => seq(
      optional('default'),
      'impl',
      // An implementation may be generic over its head, which is what lets one
      // stand for a family: the parameters come before the head that applies
      // them.
      optional($.type_parameters),
      // `impl Trait for Type` names two; `impl Type` names one.
      optional(seq(
        field('trait', $.trait_reference),
        'for',
      )),
      choice(
        seq(
          field('type', alias($.identifier, $.type_identifier)),
          optional($.type_arguments),
        ),
        field('type', $.unit_type),
        field('type', $.tuple_type),
        field('type', $.borrow_type),
        field('type', $.callable_type),
      ),
      optional($.where_clause),
      choice(
        seq('via', field('delegate', $.identifier), optional(';')),
        seq(
          '{',
          repeat(choice($._declaration, $.associated_type, $.projection_declaration, $.traversal_declaration)),
          '}',
        ),
      ),
    ),

    template_impl_block: $ => seq(
      'template',
      'impl',
      optional($.type_parameters),
      field('trait', $.trait_reference),
      optional($.template_requirements),
      '{',
      repeat($.function_declaration),
      '}',
    ),

    template_requirements: $ => seq(
      'where',
      sep1($.template_requirement, ','),
      optional(','),
    ),

    template_requirement: $ => seq(
      $.reflection_root,
      '.',
      choice(
        seq(
          field('target', alias('target', $.identifier)),
          ':',
          field('shape', choice('struct', 'enum', 'type')),
        ),
        seq(
          field('components', alias('components', $.identifier)),
          ':',
          sep1($.bound, '+'),
        ),
        seq(
          field('supertraits', alias('supertraits', $.identifier)),
          ':',
          field('evidence', alias('derived', $.identifier)),
        ),
      ),
    ),

    derive_declaration: $ => seq(
      'derive',
      optional($.type_parameters),
      choice($.derive_trait, $.derive_traits),
      'for',
      // The target is a declared constructor or a tuple, whose declaration
      // the prelude supplies.
      choice(
        seq(
          field('type', alias($.identifier, $.type_identifier)),
          optional($.type_arguments),
        ),
        field('type', $.tuple_type),
      ),
      optional($.where_clause),
    ),

    derive_trait: $ => seq(
      field('trait', $.trait_reference),
    ),

    // The list can be empty. `@derive()` requests nothing, which the compiler
    // reports as a derive rule rather than a syntax one.
    derive_traits: $ => seq(
      '(',
      optional(seq(sep1($.derive_trait, ','), optional(','))),
      ')',
    ),

    import_declaration: $ => seq(
      ...modifiers($),
      'import',
      field('path', sep1($.identifier, '.')),
      optional(seq('as', field('alias', $.identifier))),
      // Optional for the same reason it is on a statement: the line break is
      // the separator, and this grammar has none to see between tokens.
      optional(';'),
    ),

    // A trait declares signatures and types, and no representation. A
    // signature is a function header with no body, ended by a line break like
    // every other declaration; one written with its body is an operation the
    // trait provides to every type implementing it.
    trait_declaration: $ => seq(
      ...modifiers($),
      'trait',
      field('name', alias($.identifier, $.type_identifier)),
      // A trait may be generic on its own account, which is what lets one
      // relate two types rather than one.
      optional($.type_parameters),
      // What the trait asks of every type implementing it, spelled the way a
      // type parameter's bound is: one form wherever a bound is written.
      optional(seq(':', sep1($.bound, '+'))),
      optional($.where_clause),
      '{',
      repeat(choice($.signature, $.provided_operation, $.projection_signature, $.associated_type)),
      '}',
    ),

    // `proj at(inout self: Self, i: I) -> Elem`, which a trait declares and an
    // implementation supplies with a body. Two rules for the two sides, as
    // `signature` and `function_declaration` are two: the body is what tells
    // them apart, and a single optional one would make the trait's side and
    // the implementation's one sequence read two ways.
    //
    // `proj` is not a reserved word -- the position is what tells a member
    // from a binding -- so it is a literal here and nowhere in the parity
    // gates, which read the lexer's table.
    projection_signature: $ => seq(
      'proj',
      field('name', $.identifier),
      optional($.type_parameters),
      $.parameter_list,
      '->',
      field('return_type', $._type),
      optional($.where_clause),
      optional(';'),
    ),

    projection_declaration: $ => seq(
      ...modifiers($),
      'proj',
      field('name', $.identifier),
      optional($.type_parameters),
      $.parameter_list,
      optional(seq('->', field('return_type', $._type))),
      optional($.where_clause),
      field('body', $.block),
    ),

    // `trav positions = 0..4`, the positions a lending walk runs through. A
    // member of the type's own implementation and nothing a trait declares, so
    // there is one rule and no signature side.
    //
    // `trav` is not a reserved word -- the position is what tells a member
    // from a binding -- so it is a literal here and nowhere in the parity
    // gates, which read the lexer's table.
    traversal_declaration: $ => seq(
      'trav',
      field('name', $.identifier),
      choice(
        seq('via', field('delegate', $.identifier)),
        seq(optional($.parameter_list), '=', field('value', $._expression)),
      ),
      optional(';'),
    ),

    // `type Item` in a trait, and `type Item = UInt8` in an implementation of
    // it. One rule for both sides: what an implementation settles it to is
    // what the trait's side leaves out.
    //
    // `type` is not a reserved word -- the position is what tells a member
    // from a binding -- so it is a literal here and nowhere in the parity
    // gates, which read the lexer's table.
    associated_type: $ => seq(
      // Accepted, and diagnosed by the compiler: a declared type carries no
      // visibility of its own, and a grammar that could not derive the line
      // an editor is being asked to colour would colour nothing on it.
      optional($.visibility),
      'type',
      field('name', alias($.identifier, $.type_identifier)),
      optional(seq(':', sep1($.bound, '+'))),
      optional(seq('=', field('settled', $._type))),
      optional(';'),
    ),

    // A signature is generic on its own account where it says so: the trait's
    // parameters are the trait's, and these belong to the operation.
    signature: $ => seq(
      'fn',
      field('name', $.identifier),
      optional($.type_parameters),
      $.parameter_list,
      optional(seq('->', field('return_type', $._result_type))),
      optional($.where_clause),
      optional(';'),
    ),

    // An operation a trait provides: a signature written with its body, which
    // every type implementing the trait runs.
    provided_operation: $ => seq(
      'fn',
      field('name', $.identifier),
      optional($.type_parameters),
      $.parameter_list,
      optional(seq('->', field('return_type', $._result_type))),
      optional($.where_clause),
      field('body', $.block),
    ),

    where_clause: $ => prec.right(seq('where', commaSep(choice($.where_predicate, $.source_contract)))),

    contract_clause: $ => seq('where', commaSep1($.source_contract)),

    where_predicate: $ => seq(
      field('subject', $._type),
      ':',
      sep1($.bound, '+'),
    ),

    // A re-export names a module and a declaration in it, so its path is not
    // a directory the way an import's is.
    use_declaration: $ => seq(
      ...modifiers($),
      'use',
      field('path', sep1($.identifier, '.')),
      // Optional for the reason it is on an import: the line break is the
      // separator, and this grammar has none to see between tokens.
      optional(';'),
    ),

    _type: $ => choice($._result_type, $.unit_type),

    // The type written after a function's, a signature's, a callable type's or
    // a lambda's `->`: any type except `()` written whole. An operation
    // returning nothing leaves the arrow out, and [S-UnitResult] refuses
    // `-> ()`, so it derives nothing here. `()` inside a result (`Result[(),
    // E]`, `((), ())`) is an ordinary argument or element. A projection's
    // result is never omitted and keeps `_type`.
    _result_type: $ => choice($.grouped_type, $.tuple_type, $.borrow_type, $.settled_ref_type, $.self_type, $.generic_type, $.array_type, $.callable_type, alias($.identifier, $.type_identifier)),

    // A selection follows its complete type base, including type arguments.
    // Right-associative so a qualified name takes the type arguments that
    // follow it: `mem.Slice[UInt64]` after a lambda's `->` in an argument
    // list is one type, where reducing early read `[UInt64]` as a capture list.
    settled_ref_type: $ => prec.right(1, seq(
      field('base', $._type),
      '.',
      field('member', alias($.identifier, $.type_identifier)),
      optional($.type_arguments),
    )),

    // A distinguished type name rather than an ordinary one: it stands for the
    // type an implementation names, so a reader who sees it styled as a
    // declared type has been told the wrong thing. Listed before the
    // identifier alias, which would otherwise swallow it.
    //
    // It takes arguments for the same reason any other name of a generic type
    // does. `Self` alone where the implemented type declares parameters is
    // refused by [T-Bound], whose message is `give it the arguments it
    // declares` -- so a grammar accepting only the bare word cannot parse what
    // the compiler tells the programmer to write.
    self_type: $ => prec.right(seq('Self', optional($.type_arguments))),

    generic_type: $ => prec(1, seq(field('name', alias($.identifier, $.type_identifier)), $.type_arguments)),
    // `()`, the unit type, written wherever a type is.
    unit_type: _ => seq('(', ')'),
    // `()`, the unit value, spelled as its type is.
    unit_expression: _ => seq('(', ')'),

    // Concrete counts are expressions; `_` requests a local literal's count.
    array_type: $ => seq('[', field('element', $._type), ';', field('length', choice('_', $._expression)), ']'),

    grouped_type: $ => seq('(', $._type, ')'),

    // A comma makes parentheses a tuple: `(A, B)`. `(A,)` is accepted and
    // left to the compiler to refuse, as is a count above eight.
    tuple_type: $ => seq('(', $._type, ',', optional(commaSep1($._type)), ')'),

    borrow_type: $ => seq('borrow', field('referent', $._type)),

    source_contract: $ => choice(
      seq('borrows', '(', optional(seq($.result_path, ':')), commaSep1($.source_path), ')'),
      seq('carries', '(', choice(seq($.result_path, ':', commaSep1($.source_path)), commaSep($.source_path)), ')'),
      seq('retains', '(', $.source_path, ':', commaSep1(seq(optional('borrow'), $.source_path)), ')'),
    ),

    result_path: $ => seq('.', $.source_path),

    source_path: $ => seq(
      repeat('*'),
      choice($.identifier, seq('(', $.source_path, ')')),
      repeat(seq('.', $.identifier)),
    ),

    callable_type: $ => prec.dynamic(1, seq(
      optional(field('invocation', choice('read', 'inout', 'sink'))),
      'fn',
      $.parameter_list,
      optional(seq('->', field('return_type', $._result_type))),
      optional($.contract_clause),
    )),

    // A block's value is its last expression, which needs no rule of its own:
    // it is a statement in the list like any other, and nothing highlighted
    // here depends on telling the two apart.
    block: $ => seq('{', repeat($._statement), '}'),

    _statement: $ => choice(
      $.let_statement,
      $.defer_let_statement,
      $.defer_statement,
      $.block_statement,
      $.expression_statement,
    ),

    // Higher than a call: `while c { } (6)` is a loop and then a parenthesised
    // expression, not a call on the loop. Reading it the other way makes two
    // constructs one operation, which parses and then reports a type error
    // several lines from what caused it.
    block_statement: $ => prec(13, choice(
      $.if_expression,
      $.while_expression,
      $.for_expression,
      $.loop_expression,
      $.match_expression,
      $.block,
    )),

    // Only `let` takes a value apart. Both keywords name a binding; a
    // destructure names each part once, so there is nothing for `var` to add,
    // and the parser refuses it -- a grammar accepting it would derive a
    // program the compiler does not.
    //
    // A newtype's pattern is the same shape a variant's payload pattern is --
    // `N(n)` -- reused here rather than declared twice, so `let N(n) = e` and
    // `match v { N(n) => .. }` cannot read the shape two ways.
    //
    // `read` belongs to the pattern: `let read N(n) = place` lends the parts
    // of a place instead of taking a value apart, so it is admitted before a
    // pattern and nowhere else -- never after `var`, and never before a name.
    let_statement: $ => seq(
      choice(
        seq(choice('let', 'var'), field('name', $.identifier)),
        seq('let', optional('read'), field('name', choice($.struct_pattern, alias($._inferred_struct_pattern, $.struct_pattern)))),
        seq('let', optional('read'), field('name', $.variant_pattern)),
        seq('let', optional('read'), field('name', $.tuple_pattern)),
      ),
      $._binding_rest,
    ),

    // What follows a binding's name: an optional type, the initializer, and
    // the `else` that handles its failure. One rule for `let` and `defer let`,
    // so the two cannot read an initializer differently.
    _binding_rest: $ => seq(
      optional(seq(':', field('type', $._type))),
      '=',
      field('value', $._expression),
      optional($.let_else),
      optional(';'),
    ),

    // `defer let x = e` binds `x` and schedules its release for the end of the
    // scope. It binds one name: a pattern has several values and a `read`
    // pattern owns none, so a grammar accepting either would derive a program
    // the compiler refuses.
    defer_let_statement: $ => seq(
      'defer',
      choice('let', 'var'),
      field('name', $.identifier),
      $._binding_rest,
    ),

    // `else |error| { … }` after a binding's initializer: the block runs when
    // the `Option` or `Result` failed, binding what a failed `Result` carries.
    // The binder is a name or `_`, never a pattern. An `if` initializer takes
    // the first `else` itself, as the compiler reads it.
    let_else: $ => seq(
      'else',
      optional(seq('|', field('binder', choice($.identifier, $.wildcard_pattern)), '|')),
      field('body', $.block),
    ),

    // A newline ends a statement, so the separator is optional and carries no
    // token here: whitespace is already what this grammar ignores between
    // tokens, which is the one thing it cannot be made to see.
    expression_statement: $ => seq($._expression, optional(';')),

    // `defer e` schedules `e` at every exit from the enclosing scope. A
    // statement, so it sits beside the others rather than among expressions.
    defer_statement: $ => seq('defer', $._expression, optional(';')),

    _expression: $ => choice(
      $.range_expression,
      $.binary_expression,
      $.unary_expression,
      $.from_end_expression,
      $.assignment_expression,
      $.construction_expression,
      $.call_expression,
      $.instantiation_expression,
      $.index_expression,
      $.field_expression,
      $.copy_expression,
      $.borrow_expression,
      $.panic_expression,
      $.embed_expression,
      $.try_expression,
      $.marked_expression,
      $.lambda_expression,
      $.if_expression,
      $.while_expression,
      $.for_expression,
      $.loop_expression,
      $.match_expression,
      $.break_expression,
      $.continue_expression,
      $.return_expression,
      $.struct_literal,
      $.array_literal,
      $.variant_reference,
      $.reflection_root,
      $.unit_expression,
      $.parenthesised_expression,
      $.tuple_expression,
      $.block,
      // A type names a place too -- `Account.remaining(a)` reaches a member,
      // and `Key.Forged(id)` builds a variant where the type is written out --
      // and both are this one token.
      $.identifier,
      $.float_literal,
      $.integer_literal,
      $.string_literal,
      $.boolean_literal,
    ),

    // Comparison is looser than arithmetic. In the language it is also
    // non-associative -- a chain is a syntax error rather than a comparison
    // against a Bool -- but that is a rule the compiler enforces and this
    // grammar does not: accepting a chain colours it, and rejecting one would
    // leave the rest of the line uncoloured while it was being typed.
    binary_expression: $ => choice(
      prec.left(7, seq($._expression, choice('*', '/', '%'), $._expression)),
      prec.left(6, seq($._expression, choice('+', '-'), $._expression)),
      prec.left(5, seq($._expression, choice('==', '!=', '<', '<=', '>', '>='), $._expression)),
      // `||` binds loosest and `&&` next, so a comparison groups before either.
      prec.left(4, seq($._expression, '&&', $._expression)),
      prec.left(3, seq($._expression, '||', $._expression)),
    ),

    // `..` and `..=` bind looser than every operator that computes a value --
    // looser than `||`, so `a..b || c` is `a..(b || c)` -- and non-associative
    // in the compiler, though this grammar accepts a chain for the same
    // reason `binary_expression` accepts a comparison chain: rejecting one
    // would leave the rest of the line uncoloured while it was being typed.
    //
    // Both ends are optional for the same reason: `..b`, `a..` and bare `..`
    // are refused by the compiler rather than by this grammar, which has no
    // diagnostics of its own to refuse them with.
    range_expression: $ => prec.left(2, seq(
      optional($._expression), choice('..', '..='), optional($._expression),
    )),

    unary_expression: $ => prec(8, seq(choice('-', '!', '*'), $._expression)),

    // `^k`, which counts back from the end. The parser reads it anywhere an
    // index is being read -- which is anywhere inside the brackets, however
    // deeply, and nowhere outside them. That is a fact about position and not
    // about shape, and a grammar with no context cannot state it: an
    // expression here is admitted everywhere an expression is admitted, so a
    // caret written outside a bracket is highlighted rather than marked.
    // Where the two disagree the parser is the definition, and it refuses it.
    from_end_expression: $ => prec(8, seq('^', $._expression)),

    assignment_expression: $ => prec.right(1, seq(
      $._expression,
      choice('=', '+=', '-=', '*=', '/=', '%='),
      $._expression,
    )),

    // `pair[UInt8, Bool](1, true)` names the callee's type arguments in
    // brackets before its arguments. Brackets holding one expression-shaped
    // item, `parse[UInt16]()` as much as `steps[at](5)`, are an index to this
    // grammar: which of the two they are depends on what the name before them
    // reaches, which only the compiler knows. The highlight queries colour a
    // capitalised index before a call as a type. Brackets whose contents
    // cannot be one expression are type arguments.
    call_expression: $ => choice(
      prec(9, seq(field('callee', $._expression), $.argument_list)),
      prec(9, seq(field('callee', $._expression), field('type_arguments', alias($.call_type_arguments, $.type_arguments)), $.argument_list)),
      prec(10, seq(field('invocation', '&'), field('callee', $._expression), $.argument_list)),
      prec(10, seq(field('invocation', '&'), field('callee', $._expression), field('type_arguments', alias($.call_type_arguments, $.type_arguments)), $.argument_list)),
    ),

    // `pair[UInt8, Bool]` with no call after it is the function's instance as
    // a value. As before a call, only contents no index can have are read as
    // type arguments; `create[UInt8]` stays an index to this grammar.
    instantiation_expression: $ => prec(9, seq(field('function', $._expression), field('type_arguments', alias($.call_type_arguments, $.type_arguments)))),

    // Contents no index can have: two or more types, a type followed by a
    // comma, or one type that is no expression. A generic type here carries
    // no precedence of its own: `a[b[1]]` reads `b[` as an index as readily
    // as a type's arguments, and a precedence would settle that before the
    // `1` shows which it is.
    call_type_arguments: $ => seq('[', choice(
      seq($._call_type, repeat1(seq(',', $._call_type)), optional(',')),
      seq($._call_type, ','),
      $._type_only,
    ), ']'),
    _call_type: $ => choice(alias($.call_generic_type, $.generic_type), alias($.identifier, $.type_identifier), $._type_only),
    _type_only: $ => choice($.array_type, $.callable_type, $.unit_type, alias($.call_only_generic_type, $.generic_type)),
    call_only_generic_type: $ => seq(field('name', alias($.identifier, $.type_identifier)), alias($.call_type_arguments, $.type_arguments)),
    call_generic_type: $ => seq(field('name', alias($.identifier, $.type_identifier)), alias($.call_generic_arguments, $.type_arguments)),
    call_generic_arguments: $ => seq('[', commaSep1($._call_type), ']'),

    // `Name?(e)`, a newtype's construction declining. One node, because the
    // parser reads it as one form and not as a `?` applied to something that
    // is then called: a call's head is always a name, so there is nothing for
    // the two readings to disagree about. Above both a call and a `?`, or the
    // name would be taken by whichever reached it first.
    construction_expression: $ => prec(12, seq(
      field('type', alias($.identifier, $.type_identifier)),
      '?',
      $.argument_list,
    )),

    index_expression: $ => prec(10, seq(field('head', $._expression), '[', field('index', $._expression), ']')),

    // `f(a, b: 2)`. An argument may restate the parameter it fills, so each
    // element is a bare expression or a name followed by one.
    //
    // The `(` sits on the callee's line. A newline ends a statement after a
    // callee, so a line opening with `(` starts a parenthesised expression or
    // a tuple -- `(lo, hi)` as a function's tail -- and not a call on the line
    // above. Whitespace is otherwise invisible here, so the spaces a call may
    // put before its `(` are part of the immediate token.
    argument_list: $ => seq(alias(token.immediate(prec(1, /[ \t]*\(/)), '('), commaSep($._argument), ')'),

    _argument: $ => choice($._expression, $.named_argument),

    named_argument: $ => seq(field('name', $.identifier), ':', field('value', $._expression)),

    // A line opening with `.` and a lowercase name continues the expression
    // above, as the compiler reads it, so a chain may put each selection on
    // a line of its own. Whitespace is ignored here, which already reads it.
    field_expression: $ => prec(11, seq(
      $._expression,
      '.',
      field('field', $.identifier),
    )),
    reflection_root: _ => 'reflect',
    borrow_expression: $ => prec.right(9, seq('borrow', $._expression)),

    copy_expression: $ => prec(10, seq('copy', '(', $._expression, ')')),
    panic_expression: $ => prec(10, seq('panic', '(', field('message', $._expression), ')')),
    // A file's text or bytes, read when the program is compiled. The path is
    // one string literal, which the compiler holds to a quoted or raw one.
    embed_expression: $ => prec(10, seq(choice('embed', 'embed_bytes'), '(', field('path', $.string_literal), ')')),

    // Postfix, at a field selection's precedence: `f()?.n` selects from what
    // `?` yielded, and `a?.b?` chains, which is what the parser's own suffix
    // loop does by holding all three in one place.
    try_expression: $ => choice(
      // Stated directly so `answer?` does not first have to reduce `answer`
      // to an expression while the declining-construction rule is trying to
      // shift the same question mark. The token after it then distinguishes
      // this from `Name?(value)` without recovery.
      prec(11, seq($.identifier, '?')),
      prec(11, seq($._expression, '?')),
    ),

    // `&x` at a call site, marking an argument the callee writes back through.
    // Not address-of: there are no references in the language to take.
    marked_expression: $ => prec(8, seq('&', $._expression)),

    lambda_expression: $ => {
      const body = [
        choice(
          '||',
          seq('|', commaSep(alias($._lambda_parameter, $.parameter)), '|'),
        ),
        optional(seq('->', choice(
          seq(field('return_type', $._result_type), optional($.contract_clause)),
          $.contract_clause,
        ))),
        field('body', $._expression),
      ];
      return choice(
        prec.right(seq(
          field('invocation', choice('read', 'inout', 'sink')),
          field('captures', $.capture_list),
          ...body,
        )),
        // `match read` consumes its observation marker before the lambda.
        prec.right(1, seq(optional(field('captures', $.capture_list)), ...body)),
      );
    },

    capture_list: $ => prec.dynamic(1, seq('[', commaSep($.capture), ']')),

    capture: $ => seq(
      optional(field('mode', choice('read', 'inout', 'sink'))),
      field('name', $.identifier),
      optional(seq('=', field('source', $._expression))),
    ),

    // The same editor concept as a declared parameter. The compiler permits a
    // lambda's type to be omitted, and this permissive grammar also keeps a
    // missing name in the tree while the source is being edited.
    _lambda_parameter: $ => seq(
      optional(choice('read', 'inout', 'sink')),
      choice(
        seq(field('name', $.identifier), optional(seq(':', field('type', $._type)))),
        seq(field('pattern', $.tuple_pattern), optional(seq(':', field('type', $._type)))),
        seq(':', field('type', $._type)),
      ),
      optional(seq('=', field('default', $._expression))),
    ),

    if_expression: $ => prec.right(seq(
      'if', field('condition', $._expression), field('consequence', $.block),
      optional(seq('else', field('alternative', choice($.block, $.if_expression)))),
    )),

    while_expression: $ => seq('while', field('condition', $._expression), $.block),

    // The binder is a name, or a tuple pattern taking each item apart:
    // `for (a, b) in pairs`.
    //
    // `read` and `inout` before it are the lending forms: the walk observes the
    // places rather than taking them. The words are the ones a parameter uses,
    // and are reserved, so they are literals here as `match read`'s is.
    //
    // `for x in &it` lends an iterator to the walk. Its head is an ordinary
    // `marked_expression`, so the sequence field needs no form of its own.
    for_expression: $ => seq(
      'for',
      optional(choice('read', 'inout')),
      field('binder', choice($.identifier, $.tuple_pattern)),
      'in',
      field('sequence', $._expression),
      $.block,
    ),
    loop_expression: $ => seq('loop', $.block),

    match_expression: $ => seq(
      'match',
      optional('read'),
      field('value', $._expression),
      '{',
      commaSep($.match_arm),
      '}',
    ),

    match_arm: $ => seq(
      field('pattern', $._pattern),
      '=>',
      field('body', $._expression),
    ),

    _pattern: $ => choice(
      $.wildcard_pattern,
      $.struct_pattern,
      $.variant_pattern,
      $.range_pattern,
      $.integer_literal,
      $.string_literal,
      $.reflection_case_pattern,
      $.tuple_pattern,
      alias($.identifier, $.type_identifier),
    ),

    reflection_case_pattern: $ => seq(
      $.reflection_root,
      '.',
      choice('case', 'same_case', 'other_case'),
    ),

    // A literal, or a range built from two: the bound a range pattern shares
    // with a range expression, checked rather than restricted here -- an
    // integer literal, a string literal, or a name reaching a constant
    //. Both ends optional for the reason `range_expression`'s
    // are: the compiler refuses what this grammar has no diagnostics of its
    // own to refuse.
    range_pattern: $ => prec.left(2, seq(
      optional($._pattern_bound), choice('..', '..='), optional($._pattern_bound),
    )),

    _pattern_bound: $ => choice(
      $.integer_literal,
      seq('-', $.integer_literal),
      $.string_literal,
      $.dotted_name,
    ),

    // A name, or a path to a declaration's constant -- the same
    // two shapes an array's length folds through. Spelled without reusing
    // `_expression`, so a bound and whatever else an identifier could start
    // never compete for the same token.
    dotted_name: $ => seq($.identifier, repeat(seq('.', $.identifier))),

    wildcard_pattern: _ => '_',

    // A pattern where a binder may stand: inside a variant's payload, a
    // tuple's component, or after a struct field's `:`. A bare name binds or
    // names a variant by its case, which the compiler reads and this grammar
    // leaves to it.
    _part_pattern: $ => choice(
      $.identifier,
      $.wildcard_pattern,
      $.struct_pattern,
      alias($._inferred_struct_pattern, $.struct_pattern),
      $.variant_pattern,
      $.range_pattern,
      $.integer_literal,
      $.string_literal,
      $.tuple_pattern,
    ),

    // `(a, b)` takes each component apart by position, after `let`, in a
    // walk's binder, in a match arm and as a lambda parameter, and each
    // component is a pattern.
    // `(a,)` is accepted and left to the compiler to refuse.
    tuple_pattern: $ => seq(
      '(',
      $._part_pattern,
      ',',
      optional(commaSep1($._part_pattern)),
      ')',
    ),

    variant_pattern: $ => prec(1, seq(
      alias($.identifier, $.type_identifier),
      '(',
      commaSep($._part_pattern),
      ')',
    )),

    struct_pattern: $ => prec(1, seq(
      alias($.identifier, $.type_identifier),
      $._inferred_struct_pattern,
    )),

    _inferred_struct_pattern: $ => seq(
      '{',
      commaSep($.field_pattern),
      '}',
    ),

    // `{ f }` binds a field to its own name, which is what a reader writing one
    // out would have written.
    field_pattern: $ => seq(
      field('name', $.identifier),
      optional(seq(':', $._part_pattern)),
    ),

    // `break` carries a value: a loop's value is what its breaks agree on.
    break_expression: $ => prec.right(seq('break', optional($._expression))),
    continue_expression: $ => 'continue',
    return_expression: $ => prec.right(seq('return', optional($._expression))),

    // A named head starts with a nominal path; nested arguments use the full
    // type grammar. Keeping that entry separate lets `self.value` finish as a
    // field expression when no construction brace follows.
    literal_type: $ => seq(
      alias($.identifier, $.type_identifier),
      repeat(seq('.', alias($.identifier, $.type_identifier))),
      optional($.type_arguments),
    ),

    // The contextual form keeps the leading dot and receives its type inward.
    // `.{` is one token so that a statement can begin with one: a newline has
    // already ended the line above, and a separate leading dot would be read
    // as continuing it. Written apart, `. {` still parses where no expression
    // precedes it.
    struct_literal: $ => choice(
      seq(token(seq('.', '{')), optional($._literal_items), '}'),
      seq('.', '{', optional($._literal_items), '}'),
      prec.dynamic(1, seq(field('type', $.literal_type), '{', optional($._literal_items), '}')),
    ),

    // The fields a literal writes, then optionally `..base`, which supplies
    // every field not written and comes last.
    _literal_items: $ => choice(
      seq(
        sep1($.field_initialiser, ','),
        optional(seq(',', optional(seq($.struct_base, optional(','))))),
      ),
      seq($.struct_base, optional(',')),
    ),
    struct_base: $ => seq('..', field('value', $._expression)),

    array_literal: $ => seq('[', commaSep($._expression), ']'),
    field_initialiser: $ => seq(field('name', $.identifier), optional(seq('=', $._expression))),

    // `.Red` -- a variant reached where its type is already known.
    variant_reference: $ => seq('.', alias($.identifier, $.type_identifier)),

    parenthesised_expression: $ => seq('(', $._expression, ')'),

    // A comma makes parentheses a tuple: `(a, b)`. `(a,)` is accepted and left
    // to the compiler to refuse, as is a count above eight.
    tuple_expression: $ => seq('(', $._expression, ',', optional(commaSep1($._expression)), ')'),

    // A type is Capitalised and a value is not, which is what lets the two be
    // told apart without resolving anything.
    // One class for every name a program writes. Which of them is a type is
    // decided by where it sits, not by how it is spelled: the compiler has
    // never held a type name to a shape, so a grammar that did underlined
    // `struct m1 { .. }` -- source the compiler accepts.
    identifier: _ => /[a-zA-Z_][a-zA-Z0-9_]*/,

    integer_literal: _ => /[0-9]+/,
    // A point joins only with digits on both sides, and an exponent only with
    // digits after it -- the same one-byte lookahead the compiler's lexer
    // applies, so `0..9` stays a range and `1.foo` an access here too.
    float_literal: _ => /[0-9]+\.[0-9]+([eE][+-]?[0-9]+)?|[0-9]+[eE][+-]?[0-9]+/,
    // The compiler reads a quoted literal, a raw one and a multi-line one as
    // one string literal each, so each is this one node. Consecutive lines
    // are taken greedily, since a line after a line always continues the
    // literal.
    string_literal: $ => choice($._quoted_string, $._raw_string, prec.right(repeat1($._string_line))),
    // Text, embedded expressions and their format selectors remain distinct
    // nodes. The doubled opening brace wins lexically over interpolation, just
    // as the compiler's scanner consumes both bytes as text.
    _quoted_string: $ => seq(
      '"',
      repeat(choice(
        $.escape_sequence,
        $.escaped_open_brace,
        $.interpolation,
        // Above a comment, so `"//"` is text: a comment is a longer match
        // from the same byte, and length would otherwise decide.
        token.immediate(prec(1, /[^"\\{\n]+/)),
        $.literal_close_brace,
      )),
      token.immediate('"'),
    ),
    interpolation: $ => seq(
      token.immediate('{'),
      field('value', $._expression),
      optional(field('format', $.format_selector)),
      token(prec(1, '}')),
    ),
    // The text after the colon, up to the closing brace, is one token: its
    // characters are the parts of a format spec, `[[fill]align][+][0][width]
    // [.precision][x|X|?]`, rather than operators, as the compiler's lexer
    // reads it.
    format_selector: $ => seq(':', $.format_spec),
    // Spaces before the closing brace are not part of the spec.
    format_spec: _ => /[^\s}"]([^}"\n]*[^\s}"])?/,
    escaped_open_brace: _ => token.immediate(prec(1, '{{')),
    literal_close_brace: _ => token.immediate(prec(-1, '}')),
    // Consume Unicode braces as part of the escape, never as interpolation.
    escape_sequence: _ => token.immediate(choice(/\\u\{[0-9a-fA-F]+\}/, /\\[^\n]/)),
    // `r"…"` or `r#"…"#`: no escapes, no interpolation, and it ends at the
    // first `"` followed by as many `#` as opened it. Matching a count is not
    // regular, so each count up to `max_raw_hashes` is its own expression;
    // one token either way, like the compiler's.
    _raw_string: _ => token(choice(...Array.from({ length: max_raw_hashes + 1 }, (_, n) => rawString(n)))),
    // A multi-line literal's line is `\\` followed by everything else on the
    // line, which has no escapes and no interpolation. The compiler joins only
    // lines directly below one another; this grammar sees no line breaks, so
    // it also joins lines a blank line or a comment separates, which the
    // compiler refuses.
    _string_line: _ => token(seq('\\\\', /[^\n]*/)),
    boolean_literal: _ => choice('true', 'false'),
  },
});

// A raw literal opened by `r`, `n` hashes and a quote. Its text is any line of
// bytes in which a quote is followed by fewer than `n` hashes and then a byte
// that is neither a hash nor a quote; the literal closes at a quote followed
// by exactly `n` hashes. A run of quotes before the close is text.
function rawString(n) {
  if (n === 0) return /r"[^"\n]*"/;
  const fewer = `"#{0,${n - 1}}`;
  const text = `(?:[^"\\n]|(?:${fewer})+[^#"\\n])*`;
  return new RegExp(`r#{${n}}"${text}(?:${fewer})*"#{${n}}`);
}

// Ordinary declaration prefixes stay permissive for incomplete editor input.
// Closed type attributes have their own position before this prefix.
function modifiers($) {
  return [optional($.visibility), optional('export'), optional(seq('test', optional('trap')))];
}

function commaSep(rule) {
  return optional(seq(rule, repeat(seq(',', rule)), optional(',')));
}

function commaSep1(rule) {
  return seq(rule, repeat(seq(',', rule)), optional(','));
}

function sep1(rule, separator) {
  return seq(rule, repeat(seq(separator, rule)));
}
