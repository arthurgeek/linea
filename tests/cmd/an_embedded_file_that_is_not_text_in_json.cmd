In the JSON form a diagnostic's advice is under `help` and a fact about the
problem under `notes`, as the human form prints them `= help:` and `= note:`.

  $ mkdir app
  $ printf 'fn main() -> UInt8 {\n    UInt8(embed("motd.txt").length())\n}\n' > app/main.lin
  $ printf 'bad \377 byte' > app/motd.txt
  $ linea check --error-format=json app
  {"severity":"error","code":"M-EmbedText","message":"\"motd.txt\" is not UTF-8 text","file":"app/main.lin","labels":[{"file":"app/main.lin","line":2,"column":17,"start":37,"end":47,"style":"primary","message":"byte 4 is 0xFF, which begins no UTF-8 character"}],"help":["`embed_bytes(\"motd.txt\")` embeds a file of any bytes as a `mem.Slice[UInt8]`"],"notes":["that byte is at line 1, column 5 of the file"]}
  [1]
