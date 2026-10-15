An embedded path names files and directories themselves. A symbolic link to
the file, or a link standing for a directory on the path, is refused, so no
path inside a program can reach a file outside it. A program reached through a
link above its own directory is not affected.

  $ mkdir -p real/app/pages outside
  $ printf '{}\n' > real/app/linea.json
  $ printf 'outside' > outside/secret.txt
  $ printf 'beside' > real/app/pages/page.txt
  $ ln -s ../../outside/secret.txt real/app/linked.txt
  $ ln -s pages real/app/aliased
  $ printf 'fn main() -> UInt8 {\n    UInt8(embed("linked.txt").length())\n}\n' > real/app/main.lin
  $ linea check real/app
  error[M-Embed]: "linked.txt" goes through a symbolic link
   --> real/app/main.lin:2:17
    |
  2 |     UInt8(embed("linked.txt").length())
    |                 ^^^^^^^^^^^^ `linked.txt` is a link, and an embedded path names files and directories themselves
  [1]
  $ printf 'fn main() -> UInt8 {\n    UInt8(embed("aliased/page.txt").length())\n}\n' > real/app/main.lin
  $ linea check real/app
  error[M-Embed]: "aliased/page.txt" goes through a symbolic link
   --> real/app/main.lin:2:17
    |
  2 |     UInt8(embed("aliased/page.txt").length())
    |                 ^^^^^^^^^^^^^^^^^^ `aliased` is a link, and an embedded path names files and directories themselves
  [1]
  $ printf 'fn main() -> UInt8 {\n    UInt8(embed("pages/page.txt").length())\n}\n' > real/app/main.lin
  $ ln -s real through
  $ linea run through/app
  [6]
