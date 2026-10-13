Dump expanded prints the files a program's derives generate. The library's
own generated files come first in the dump and are left out here, so what is
compared is this program's.

  $ linea dump-expanded "$LINEA_ROOT"/tests/cmd/fixtures/dump_expanded_prints_generated_files > out
  $ awk '/^\/\/ === /{own = index($0, "dump_expanded_prints_generated_files/") == 1 + length("// === ")} own' out
  // === dump_expanded_prints_generated_files/linea-derive-0.lin ===
  // origin: derive 2, trait token 10
  import protocol as _linea_trait_0
  
  impl _linea_trait_0.First for Item {
  }
  
  // === dump_expanded_prints_generated_files/linea-derive-1.lin ===
  // origin: derive 2, trait token 14
  import protocol as _linea_trait_1
  
  impl _linea_trait_1.Second for Item {
  }
  
