; Linea textobjects, powering `mif`/`maf` and friends in Helix, where
; textobjects are core editing rather than a plugin.

(function_declaration body: (block) @function.inside) @function.around
(provided_operation body: (block) @function.inside) @function.around
(lambda_expression body: (_) @function.inside) @function.around

(enum_declaration)   @class.around
(struct_declaration) @class.around
(impl_block)         @class.around
(template_impl_block) @class.around

(parameter) @parameter.inside @parameter.around
(derive_trait) @parameter.inside @parameter.around
(template_requirement) @parameter.inside @parameter.around

(line_comment) @comment.inside @comment.around
