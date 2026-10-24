The standard library may give a primitive its methods in more than one
inherent `impl`, as it may for a type it declares. An inherent block
implements no trait, so a second one for the same primitive is not a second
implementation of anything, and its methods are reached through the
primitive's name.

  $ cp -R "$LINEA_ROOT"/std split
  $ printf '\nimpl Float64 {\n    // Return twice the value.\n    pub fn doubled(self: Self) -> Float64 {\n        self * 2.0\n    }\n}\n\ntest fn doubled_multiplies_by_two() {\n    testing.assert_eq(Float64.doubled(1.5), 3.0, "doubling changed the value")?\n    .Ok(())\n}\n' >> split/scalar/float.lin
  $ linea check split; echo "split $?"
  split 0

A primitive's method name is still declared once, across every inherent
block of every library module, so a second `floor` for Float64 is refused
whether it sits beside the first or in another module.

  $ cp -R "$LINEA_ROOT"/std beside
  $ printf '\nimpl Float64 {\n    // Return the value unchanged.\n    pub fn floor(self: Self) -> Float64 {\n        self\n    }\n}\n' >> beside/scalar/float.lin
  $ linea check beside > beside.out 2>&1; echo "beside $?"
  beside 1
  $ grep -A4 'N-Duplicate' beside.out
  error[N-Duplicate]: `floor` is already declared in this type
     --> beside/scalar/float.lin:328:12
      |
  328 |     pub fn floor(self: Self) -> Float64 {
      |            ^^^^^ a name is declared once
  $ cp -R "$LINEA_ROOT"/std across
  $ printf '\nimpl Float64 {\n    // Return the value unchanged.\n    pub fn floor(self: Self) -> Float64 {\n        self\n    }\n}\n' >> across/text/parse_float.lin
  $ linea check across > across.out 2>&1; echo "across $?"
  across 1
  $ grep -A4 'N-Duplicate' across.out
  error[N-Duplicate]: `floor` is already declared in this type
     --> across/text/parse_float.lin:157:12
      |
  157 |     pub fn floor(self: Self) -> Float64 {
      |            ^^^^^ a name is declared once

The rule is the same for every primitive: two library modules may not both
give UInt8 a `halved`.

  $ cp -R "$LINEA_ROOT"/std integer
  $ printf '\nimpl UInt8 {\n    // Return half the value, rounded down.\n    pub fn halved(self: Self) -> UInt8 {\n        self / 2\n    }\n}\n' >> integer/scalar/float.lin
  $ printf '\nimpl UInt8 {\n    // Return half the value, rounded down.\n    pub fn halved(self: Self) -> UInt8 {\n        self / 2\n    }\n}\n' >> integer/text/parse_float.lin
  $ linea check integer > integer.out 2>&1; echo "integer $?"
  integer 1
  $ grep -A4 'N-Duplicate' integer.out
  error[N-Duplicate]: `halved` is already declared in this type
     --> integer/text/parse_float.lin:157:12
      |
  157 |     pub fn halved(self: Self) -> UInt8 {
      |            ^^^^^^ a name is declared once
