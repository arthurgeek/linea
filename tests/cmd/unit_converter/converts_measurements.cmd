The unit converter, built once and run on each kind of measurement.

  $ linea build "$LINEA_ROOT"/examples/unit_converter.lin -o units

Each kind converts through its base unit and prints two decimals.

  $ ./units length 5 km mi
  5.0 km = 3.11 mi
  $ ./units weight 2.5 lb kg
  2.5 lb = 1.13 kg
  $ ./units temperature 100 C F
  100.0 C = 212.00 F
  $ ./units units
  length: mm cm m km in ft mi
  weight: g kg oz lb
  temperature: C F K

`--help` writes the help of the command it follows to standard output and
exits with 0.

  $ ./units --help
  usage: unit_converter <command>
  
  Convert a measurement from one unit to another
  
  commands:
    length <value> <from> <to>         convert mm, cm, m, km, in, ft or mi
    weight <value> <from> <to>         convert g, kg, oz or lb
    temperature <value> <from> <to>    convert C, F or K
    units                              list the units of each kind
  $ ./units temperature --help
  usage: unit_converter temperature <value> <from> <to>
  
  convert C, F or K

A value the parse refuses is reported with the help of its command, and the
program exits with 64.

  $ ./units length five m ft
  error: invalid value 'five' for argument 'value'
  usage: unit_converter length <value> <from> <to>
  
  convert mm, cm, m, km, in, ft or mi
  [64]
  $ ./units length 5 km
  error: missing required argument 'to'
  usage: unit_converter length <value> <from> <to>
  
  convert mm, cm, m, km, in, ft or mi
  [64]

A value the parse accepts but the conversion cannot use is reported the same
way. `--` lets a negative number through as the value.

  $ ./units length -- -2 m ft
  error: a length cannot be negative
  usage: unit_converter length <value> <from> <to>
  
  convert mm, cm, m, km, in, ft or mi
  [64]
  $ ./units temperature -- -300 C K
  error: no temperature is below absolute zero
  usage: unit_converter temperature <value> <from> <to>
  
  convert C, F or K
  [64]
  $ ./units weight 3 kg ft
  error: weight units are g, kg, oz and lb
  usage: unit_converter weight <value> <from> <to>
  
  convert g, kg, oz or lb
  [64]
