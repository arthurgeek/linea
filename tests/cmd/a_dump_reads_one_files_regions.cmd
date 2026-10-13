A dump reads one files regions.

  $ linea dump-mono "$LINEA_ROOT"/tests/fmt/hatch_in_a_variant_payload.lin > out
  $ cat out
  enum Pair {
      Both(
          // linea fmt: off
          UInt8,
          // linea fmt: on
          UInt8,
      ),
      Neither,
  }
  
  fn ;main() -> UInt8 {
      let p: Pair = .Neither
      match p {
          Both(x, y) => x + y,
          Neither => 4,
      }
  }
