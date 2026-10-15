A file embeds at most 16 MiB. One byte more is refused with the file's size,
before it is read; exactly the limit is accepted.

  $ mkdir app
  $ printf 'fn main() -> UInt8 {\n    UInt8(embed_bytes("big.bin").length() %% 251)\n}\n' > app/main.lin
  $ head -c 16777217 /dev/zero > app/big.bin
  $ linea check app
  error[M-Embed]: "big.bin" holds 16777217 bytes, and a file embeds at most 16777216
   --> app/main.lin:2:23
    |
  2 |     UInt8(embed_bytes("big.bin").length() % 251)
    |                       ^^^^^^^^^ a file embeds at most 16 MiB
  [1]
  $ head -c 16777216 /dev/zero > app/big.bin
  $ linea check app
