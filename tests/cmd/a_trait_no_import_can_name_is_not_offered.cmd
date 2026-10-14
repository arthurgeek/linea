A trait declared in a directory whose name is not an identifier cannot be
brought into scope, because no import can name its module. No `import` and
`use` are offered for it: the call is reported as one to an operation the type
does not have, as it is where that module is not loaded at all.

  $ linea test "$LINEA_ROOT"/tests/cmd/fixtures/a_trait_no_import_can_name_is_not_offered
  error[T-UnknownOperation]: `shapes.Box` has no operation `count`
    --> $LINEA_ROOT/tests/cmd/fixtures/a_trait_no_import_can_name_is_not_offered/main.lin:11:8
     |
  11 |     if b.count() == 3 {
     |        ^^^^^^^ no operation of this name is declared for this type
  [1]
