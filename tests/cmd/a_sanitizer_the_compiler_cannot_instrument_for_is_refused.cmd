A build instruments its generated code for the sanitizer `LINEA_SANITIZE`
names, so a name the compiler has no instrumentation for is refused before
anything is built, rather than linked with the program left unwatched.

  $ echo 'fn main() -> UInt8 { 0 }' > main.lin
  $ LINEA_SANITIZE=memory linea run main.lin; echo "exit $?"
  error: LINEA_SANITIZE=memory names a sanitizer the compiler cannot instrument for; use address or thread
  exit 64
