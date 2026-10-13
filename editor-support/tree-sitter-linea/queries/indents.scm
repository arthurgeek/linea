; Linea indentation. Without this Helix indents by its own guess and `linea fmt`
; corrects it on save, which reads as the two tools fighting each other.
;
; Node names must match those emitted by grammar.js.

[
  (block)
  (field_list)
  (variant_list)
  (parameter_list)
  (argument_list)
  (match_expression)
  (struct_literal)
  (struct_pattern)
  (impl_block)
  (template_impl_block)
  (derive_traits)
  (attribute_group)
] @indent

["}" ")"] @outdent
