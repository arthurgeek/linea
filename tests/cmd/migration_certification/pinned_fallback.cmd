Optional migration metadata does not prevent ordinary pinned execution.
An object without a selected runtime remains unproven even when another
program later links a runtime with metadata.

  $ printf 'fn main() -> UInt8 { 0 }\n' > main.lin
  $ cp "$LINEA_RUNTIME" old.a
  $ LINEA_RUNTIME=old.a linea build main.lin --keep -o old
  $ ./old
  $ test -s old.mlir && ! grep -E 'linea_migration_|linea_fiber_certify_entry|linea_foreign_enter_unknown' old.mlir
  $ printf '{' > old.a.migration.json
  $ LINEA_RUNTIME=old.a linea build main.lin --keep -o malformed
  $ ./malformed
  $ printf '{"approved":true}' > old.a.migration.json
  $ LINEA_RUNTIME=old.a linea build main.lin --keep -o forged
  $ ./forged
  $ cmp old.mlir forged.mlir
  $ rm old.a.migration.json
  $ mkdir shelf && printf 'export fn seven() -> UInt8 { 7 }\n' > shelf/shelf.lin
  $ printf '{"kind":"library","name":"shelf"}' > shelf/linea.json
  $ LINEA_RUNTIME=missing-runtime.a linea build shelf --keep -o shelf.o
  $ test -s shelf.o && ! grep -E 'linea_migration_|linea_fiber_certify_entry|linea_foreign_enter_unknown' shelf.o.mlir
  $ LINEA_RUNTIME=old.a linea check "$LINEA_ROOT"/tests/text/an_extern_takes_only_scalars.lin
  error[M-Extern]: an `extern` is declared only in a module its root's manifest grants, and linea.json does not list "."
    --> $LINEA_ROOT/tests/text/an_extern_takes_only_scalars.lin:11:11
     |
  11 | extern fn width_of(p: Pair) -> UInt64
     |           ^^^^^^^^ list this module under "extern" in linea.json to trust it with C, or call a module that is granted
  error[T-Extern]: `Pair` may not cross the foreign boundary: only an integer, a `Float64` or a newtype over one has a C representation the language fixes
    --> $LINEA_ROOT/tests/text/an_extern_takes_only_scalars.lin:11:20
     |
  11 | extern fn width_of(p: Pair) -> UInt64
     |                    ^ pass what it is made of, as integers or `Float64`
  [1]
