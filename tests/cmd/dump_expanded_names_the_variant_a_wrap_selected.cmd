Dump expanded prints a derive's generated file as checking settled it: the
`reflect.wrap` of the `From` template names the variant whose payload is the
type `Celsius.Reading` settles to, `Hot`.

  $ linea dump-expanded "$LINEA_ROOT"/tests/cmd/fixtures/dump_expanded_names_the_variant_a_wrap_selected > out
  $ awk '/^\/\/ === /{own = index($0, "dump_expanded_names_the_variant_a_wrap_selected/") == 1 + length("// === ")} own' out
  // === dump_expanded_names_the_variant_a_wrap_selected/linea-derive-0.lin ===
  // origin: derive 6, trait token 31
  import std.convert as _linea_trait_0
  
  impl _linea_trait_0.From[Celsius.Reading] for Temp {
  fn from(sink source: Celsius.Reading) -> Self {
          Temp.Hot(source)
      }
  }
  
