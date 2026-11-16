const std = @import("std");

const ExpandedProgram = @import("../syntax/expanded_program.zig").ExpandedProgram;
const Resolution = @import("resolve.zig").Resolution;
const types = @import("types.zig");
const Typing = types.Typing;

/// The text of every generated file as checking settled it, in the order
/// `ExpandedProgram.generatedSource` numbers them: each rendered wrap's
/// placeholder `.wrap` is replaced by `Target.Variant`, the variant the
/// checker selected for it. This is the text `dump-expanded` prints and
/// derive materialization reloads as ordinary source. A placeholder the
/// checker selected no variant for is left as rendered; checking refused
/// that program.
///
/// **Bound:** each generated file's text is copied once, and each wrap is
/// visited once, in the order the files hold them.
pub fn settledGeneratedTexts(
    gpa: std.mem.Allocator,
    expanded: *const ExpandedProgram,
    res: *const Resolution,
    typing: *const Typing,
) std.mem.Allocator.Error![][]u8 {
    const count = expanded.generatedSourceCount();
    const texts = try gpa.alloc([]u8, count);
    var filled: usize = 0;
    errdefer {
        for (texts[0..filled]) |text| gpa.free(text);
        gpa.free(texts);
    }
    const ast = &expanded.ast;
    const source_parts = expanded.source.ast.parts.len;
    var site_at: usize = 0;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    for (0..count) |index| {
        const part = ast.parts[source_parts + index];
        const text = expanded.generatedSource(@intCast(index)).text;
        out.clearRetainingCapacity();
        var copied: usize = 0;
        // Wraps are ordered by placeholder, and a file's expressions follow
        // the files before it, so this file's wraps come next.
        while (site_at < expanded.wrap_sites.len) : (site_at += 1) {
            const site = expanded.wrap_sites[site_at];
            if (ast.fileOfExpr(site.callee) != part.file) break;
            const ordinal = types.variantOrdinalOf(&res.variant_ordinals, &typing.variant_uses, site.callee) orelse continue;
            const target = expanded.generatedImplementation(site.implementation).target;
            const span = ast.exprSpan(site.callee);
            try out.appendSlice(gpa, text[copied..span.start]);
            try out.appendSlice(gpa, ast.tokenText(ast.declName(target)));
            try out.append(gpa, '.');
            try out.appendSlice(gpa, ast.tokenText(ast.declVariants(target)[ordinal].name));
            copied = span.end;
        }
        try out.appendSlice(gpa, text[copied..]);
        texts[index] = try gpa.dupe(u8, out.items);
        filled += 1;
    }
    return texts;
}

/// Frees what `settledGeneratedTexts` returned.
pub fn freeTexts(gpa: std.mem.Allocator, texts: [][]u8) void {
    for (texts) |text| gpa.free(text);
    gpa.free(texts);
}
