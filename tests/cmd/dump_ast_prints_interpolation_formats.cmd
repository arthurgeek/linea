Dump ast prints interpolation formats.

  $ linea dump-ast "$LINEA_ROOT"/tests/cmd/fixtures/dump_ast_prints_interpolation_formats/main.lin > out
  $ cat out
  program decls=1
    decl function "main" tokens 0..29
      returns UInt8
      expr %10 block tokens 6..29
        stmt %0 let_decl tokens 7..13 "value" : UInt8
          expr %0 int_literal tokens 12..13 "7"
        stmt %1 let_decl tokens 13..27 "_text"
          expr %8 interp tokens 16..27
            expr %1 str_literal tokens 16..17 ""display={"
            format display
            expr %2 name_ref tokens 17..18 "value"
            expr %3 str_literal tokens 18..19 "} debug={"
            format debug
            expr %4 name_ref tokens 19..20 "value"
            expr %5 str_literal tokens 22..23 "} laid out={"
            format debug *>+6?
            expr %6 name_ref tokens 23..24 "value"
            expr %7 str_literal tokens 26..27 "}""
        expr %9 int_literal tokens 27..28 "0"
