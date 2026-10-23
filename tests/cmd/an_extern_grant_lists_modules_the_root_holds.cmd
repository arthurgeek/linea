A manifest grants `extern` to a list of the root's modules. A grant of any
other shape is refused by name, and so is one naming a module the root does not
hold.

  $ mkdir -p yes_or_no typo && echo 'fn main() -> UInt8 { 0 }' > yes_or_no/main.lin && cp yes_or_no/main.lin typo/main.lin
  $ echo '{ "extern": true }' > yes_or_no/linea.json
  $ linea check yes_or_no
  error: cannot read 'yes_or_no'
    the linea.json grants `extern` to something other than a list of modules, such as ["store"] or ["."] for the root module
  [74]
  $ echo '{ "extern": ["sotre"] }' > typo/linea.json
  $ linea check typo
  error: cannot read 'typo'
    the linea.json grants `extern` to a module the root does not hold: each entry names a directory of source, as an import inside the root names it
  [74]
