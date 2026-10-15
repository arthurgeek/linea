An embedded file is read each time the program is compiled, so an edit to it
is what the next run prints, and an edit that makes it invalid text is
reported.

  $ mkdir app
  $ printf 'import std.io\n\nfn main() -> Result[UInt8, io.IoError] {\n    io.println(embed("motd.txt"))?\n    .Ok(0)\n}\n' > app/main.lin
  $ printf 'first message' > app/motd.txt
  $ linea run app
  first message
  $ printf 'second message' > app/motd.txt
  $ linea run app
  second message
  $ printf 'bad \377 byte' > app/motd.txt
  $ linea check app
  error[M-EmbedText]: "motd.txt" is not UTF-8 text
   --> app/main.lin:4:22
    |
  4 |     io.println(embed("motd.txt"))?
    |                      ^^^^^^^^^^ byte 4 is 0xFF, which begins no UTF-8 character
    |
    = help: the first byte that is not UTF-8 is at line 1, column 5 of the file
    = help: `embed_bytes("motd.txt")` embeds a file of any bytes as a `mem.Slice[UInt8]`
  [1]
