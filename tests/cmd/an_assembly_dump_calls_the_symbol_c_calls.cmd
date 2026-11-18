`dump-asm` prints the assembly `build` would ship, so a C function C calls
under another symbol is called by that symbol, as the build calls it. C
calls `twice_of` through an `__asm__` label naming `twice_impl`.

  $ linea dump-asm "$LINEA_ROOT"/tests/ffi/a_c_function_under_an_asm_label_is_called_by_it > label.s
  $ grep -o 'twice_[a-z]*' label.s | sort -u
  twice_impl

A declaration C's prototype refuses is refused before any assembly is
printed, as it is before anything is built.

  $ linea dump-asm "$LINEA_ROOT"/tests/ffi/a_c_ifunc_of_another_type_is_refused
  error[T-ExternPrototype]: C declares `long long twice_of(long long)`, and this declaration calls it as `int32_t twice_of(int32_t)`
   --> $LINEA_ROOT/tests/ffi/a_c_ifunc_of_another_type_is_refused/twice/twice.lin:1:27
    |
  1 | extern fn twice_of(value: Int32) -> Int32
    |                           ^^^^^ C takes `long long` here
    |
    = note: `twice_of` is declared by `twice/twice.c`
    = help: declare `value` as `Int64`, or a newtype over it, the Linea type of C's `long long`
  [1]
