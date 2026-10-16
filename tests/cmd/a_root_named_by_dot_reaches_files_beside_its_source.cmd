An embedded path is bounded by the directory holding the program's
`linea.json` however the program is named on the command line: as `.` from
inside it, as `./site` from beside it, or by its entry file.

  $ mkdir -p site/src site/templates
  $ printf '{"source": "src"}\n' > site/linea.json
  $ printf 'a page kept beside the source' > site/templates/page.txt
  $ printf 'import std.io\n\nfn main() -> Result[UInt8, io.IoError] {\n    io.println(embed("../templates/page.txt"))?\n    .Ok(0)\n}\n' > site/src/main.lin
  $ linea run ./site
  a page kept beside the source
  $ cd site
  $ linea run .
  a page kept beside the source
  $ linea run ./
  a page kept beside the source
  $ linea run src/main.lin
  a page kept beside the source
  $ printf 'fn main() -> UInt8 {\n    UInt8(embed("../../page.txt").length())\n}\n' > src/main.lin
  $ linea check .
  error[M-Embed]: "../../page.txt" climbs above the program's root
   --> src/main.lin:2:17
    |
  2 |     UInt8(embed("../../page.txt").length())
    |                 ^^^^^^^^^^^^^^^^ an embedded file is inside the directory holding the program's `linea.json`
  [1]
