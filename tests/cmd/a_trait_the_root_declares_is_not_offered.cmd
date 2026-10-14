A trait the root module declares cannot be brought into another module's
scope, because no import names the root module. No `use` is offered for it:
the call is reported as one to an operation the type does not have.

  $ linea test "$LINEA_ROOT"/tests/cmd/fixtures/a_trait_the_root_declares_is_not_offered
  error[T-UnknownOperation]: `Box` has no operation `count`
   --> $LINEA_ROOT/tests/cmd/fixtures/a_trait_the_root_declares_is_not_offered/shapes/shapes.lin:8:8
    |
  8 |     if b.count() == 3 {
    |        ^^^^^^^ no operation of this name is declared for this type
  [1]
