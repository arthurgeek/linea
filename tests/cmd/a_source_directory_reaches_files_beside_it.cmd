A path is relative to the file that writes it and may climb with `..` as far
as the directory holding the program's `linea.json`, so a program whose source
sits in `src` embeds a template kept beside `src`. A path climbing further is
refused.

  $ mkdir -p site/src site/templates
  $ printf '{"source": "src"}\n' > site/linea.json
  $ printf 'a page kept beside the source' > site/templates/page.txt
  $ printf 'import std.io\n\nfn main() -> Result[UInt8, io.IoError] {\n    io.println(embed("../templates/page.txt"))?\n    .Ok(0)\n}\n' > site/src/main.lin
  $ linea run site
  a page kept beside the source
  $ printf 'fn main() -> UInt8 {\n    UInt8(embed("../../page.txt").length())\n}\n' > site/src/main.lin
  $ linea check site
  error[M-Embed]: "../../page.txt" climbs above the program's root
   --> site/src/main.lin:2:17
    |
  2 |     UInt8(embed("../../page.txt").length())
    |                 ^^^^^^^^^^^^^^^^ an embedded file is inside the directory holding the program's `linea.json`
  [1]
