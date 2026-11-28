// Strict binary32 arithmetic over raw bits (ADRs 0226 and 0249).
// Only Shader integer32 operations are required; no device floating point is used.
// Every shift count is bounded to 0..31. All arithmetic below wraps modulo 2^32.
// All helpers have private symbol visibility, so image preparation removes those
// unreachable from its entry point. Each operation rounds once, nearest/ties-even.
//
// A finite value is sign * significand * 2^(biased_exponent - 150).
// Subnormals start at biased_exponent = 1 without the implicit bit. Multiplication
// and division normalize their significands to bit 23 and adjust that exponent.
// pack receives the exponent of bit 26 and three guard/round/sticky bits below
// the retained 24. It normalizes before subnormal shifting, then rounds exactly
// once; a rounded subnormal may become the smallest normal. Signed exponent
// arithmetic remains within [-256, 512], far from i32 overflow.
//
// Operations evaluate finite-path integer expressions for every input, then
// select IEEE special results. Thus those expressions must remain defined even
// for zeros, infinities and NaNs. Division uses no integer division instruction.
// All functions intentionally have fixed work, with no data-dependent loops.

// Shift right with a sticky low bit; distance may exceed the word width.
spirv.func @linea_f32_jam(%x: i32, %distance: i32) -> i32 "None" attributes {sym_visibility = "private"} {
  %v0 = spirv.Constant 31 : i32
  %v1 = spirv.BitwiseAnd %distance, %v0 : i32
  %v2 = spirv.ShiftRightLogical %x, %v1 : i32, i32
  %v3 = spirv.Constant 1 : i32
  %v4 = spirv.ShiftLeftLogical %v3, %v1 : i32, i32
  %v5 = spirv.ISub %v4, %v3 : i32
  %v6 = spirv.BitwiseAnd %x, %v5 : i32
  %v7 = spirv.Constant 0 : i32
  %v8 = spirv.INotEqual %v6, %v7 : i32
  %v9 = spirv.Select %v8, %v3, %v7 : i1, i32
  %v10 = spirv.BitwiseOr %v2, %v9 : i32
  %v11 = spirv.UGreaterThan %distance, %v0 : i32
  %v12 = spirv.INotEqual %x, %v7 : i32
  %v13 = spirv.Select %v12, %v3, %v7 : i1, i32
  %v14 = spirv.Select %v11, %v13, %v10 : i1, i32
  spirv.ReturnValue %v14 : i32
}

// Count leading zeros, with clz(0) = 32. Five bounded binary-search steps.
spirv.func @linea_f32_clz(%x: i32) -> i32 "None" attributes {sym_visibility = "private"} {
  %v0 = spirv.Constant 0 : i32
  %v1 = spirv.Constant 65536 : i32
  %v2 = spirv.ULessThan %x, %v1 : i32
  %v3 = spirv.Constant 16 : i32
  %v4 = spirv.Select %v2, %v3, %v0 : i1, i32
  %v5 = spirv.IAdd %v0, %v4 : i32
  %v6 = spirv.ShiftLeftLogical %x, %v3 : i32, i32
  %v7 = spirv.Select %v2, %v6, %x : i1, i32
  %v8 = spirv.Constant 16777216 : i32
  %v9 = spirv.ULessThan %v7, %v8 : i32
  %v10 = spirv.Constant 8 : i32
  %v11 = spirv.Select %v9, %v10, %v0 : i1, i32
  %v12 = spirv.IAdd %v5, %v11 : i32
  %v13 = spirv.ShiftLeftLogical %v7, %v10 : i32, i32
  %v14 = spirv.Select %v9, %v13, %v7 : i1, i32
  %v15 = spirv.Constant 268435456 : i32
  %v16 = spirv.ULessThan %v14, %v15 : i32
  %v17 = spirv.Constant 4 : i32
  %v18 = spirv.Select %v16, %v17, %v0 : i1, i32
  %v19 = spirv.IAdd %v12, %v18 : i32
  %v20 = spirv.ShiftLeftLogical %v14, %v17 : i32, i32
  %v21 = spirv.Select %v16, %v20, %v14 : i1, i32
  %v22 = spirv.Constant 1073741824 : i32
  %v23 = spirv.ULessThan %v21, %v22 : i32
  %v24 = spirv.Constant 2 : i32
  %v25 = spirv.Select %v23, %v24, %v0 : i1, i32
  %v26 = spirv.IAdd %v19, %v25 : i32
  %v27 = spirv.ShiftLeftLogical %v21, %v24 : i32, i32
  %v28 = spirv.Select %v23, %v27, %v21 : i1, i32
  %v29 = spirv.Constant -2147483648 : i32
  %v30 = spirv.ULessThan %v28, %v29 : i32
  %v31 = spirv.Constant 1 : i32
  %v32 = spirv.Select %v30, %v31, %v0 : i1, i32
  %v33 = spirv.IAdd %v26, %v32 : i32
  %v34 = spirv.ShiftLeftLogical %v28, %v31 : i32, i32
  %v35 = spirv.Select %v30, %v34, %v28 : i1, i32
  %v36 = spirv.IEqual %v35, %v0 : i32
  %v37 = spirv.Select %v36, %v31, %v0 : i1, i32
  %v38 = spirv.IAdd %v33, %v37 : i32
  spirv.ReturnValue %v38 : i32
}

// Normalize a significand with three rounding bits, then round and encode.
// sign is 0 or 0x80000000, exp is signed biased, extended < 2^28.
// First remove one carry bit, then normalize any cancellation. clz(0) is
// explicitly excluded from the variable shift. jam masks even unused shifts.
// A tail greater than 100b rounds up; exactly 100b rounds toward an even LSB.
spirv.func @linea_f32_pack(%sign: i32, %exp: i32, %extended: i32) -> i32 "None" attributes {sym_visibility = "private"} {
  %v0 = spirv.Constant 134217727 : i32
  %v1 = spirv.UGreaterThan %extended, %v0 : i32
  %v2 = spirv.Constant 1 : i32
  %v3 = spirv.FunctionCall @linea_f32_jam(%extended, %v2) : (i32, i32) -> i32
  %v4 = spirv.Select %v1, %v3, %extended : i1, i32
  %v5 = spirv.Constant 0 : i32
  %v6 = spirv.Select %v1, %v2, %v5 : i1, i32
  %v7 = spirv.IAdd %exp, %v6 : i32
  %v8 = spirv.FunctionCall @linea_f32_clz(%v4) : (i32) -> i32
  %v9 = spirv.INotEqual %v4, %v5 : i32
  %v10 = spirv.Constant 5 : i32
  %v11 = spirv.ISub %v8, %v10 : i32
  %v12 = spirv.Select %v9, %v11, %v5 : i1, i32
  %v13 = spirv.ShiftLeftLogical %v4, %v12 : i32, i32
  %v14 = spirv.ISub %v7, %v12 : i32
  %v15 = spirv.SLessThan %v14, %v2 : i32
  %v16 = spirv.ISub %v2, %v14 : i32
  %v17 = spirv.FunctionCall @linea_f32_jam(%v13, %v16) : (i32, i32) -> i32
  %v18 = spirv.Select %v15, %v17, %v13 : i1, i32
  %v19 = spirv.Select %v15, %v2, %v14 : i1, i32
  %v20 = spirv.Constant 3 : i32
  %v21 = spirv.ShiftRightLogical %v18, %v20 : i32, i32
  %v22 = spirv.Constant 7 : i32
  %v23 = spirv.BitwiseAnd %v18, %v22 : i32
  %v24 = spirv.Constant 4 : i32
  %v25 = spirv.UGreaterThan %v23, %v24 : i32
  %v26 = spirv.IEqual %v23, %v24 : i32
  %v27 = spirv.BitwiseAnd %v21, %v2 : i32
  %v28 = spirv.INotEqual %v27, %v5 : i32
  %v29 = spirv.LogicalAnd %v26, %v28 : i1
  %v30 = spirv.LogicalOr %v25, %v29 : i1
  %v31 = spirv.Select %v30, %v2, %v5 : i1, i32
  %v32 = spirv.IAdd %v21, %v31 : i32
  %v33 = spirv.Constant 16777215 : i32
  %v34 = spirv.UGreaterThan %v32, %v33 : i32
  %v35 = spirv.ShiftRightLogical %v32, %v2 : i32, i32
  %v36 = spirv.Select %v34, %v35, %v32 : i1, i32
  %v37 = spirv.Select %v34, %v2, %v5 : i1, i32
  %v38 = spirv.IAdd %v19, %v37 : i32
  %v39 = spirv.Constant 8388608 : i32
  %v40 = spirv.ULessThan %v36, %v39 : i32
  %v41 = spirv.Select %v40, %v5, %v38 : i1, i32
  %v42 = spirv.Constant 23 : i32
  %v43 = spirv.ShiftLeftLogical %v41, %v42 : i32, i32
  %v44 = spirv.Constant 8388607 : i32
  %v45 = spirv.BitwiseAnd %v36, %v44 : i32
  %v46 = spirv.BitwiseOr %v43, %v45 : i32
  %v47 = spirv.Constant 255 : i32
  %v48 = spirv.SLessThan %v41, %v47 : i32
  %v49 = spirv.Constant 2139095040 : i32
  %v50 = spirv.Select %v48, %v46, %v49 : i1, i32
  %v51 = spirv.BitwiseOr %sign, %v50 : i32
  spirv.ReturnValue %v51 : i32
}

// Magnitude-order operands, align with sticky precision, add/subtract, and round once.
spirv.func @linea_f32_add(%a: i32, %b: i32) -> i32 "None" attributes {sym_visibility = "private"} {
  %v0 = spirv.Constant 2147483647 : i32
  %v1 = spirv.BitwiseAnd %a, %v0 : i32
  %v2 = spirv.Constant 23 : i32
  %v3 = spirv.ShiftRightLogical %v1, %v2 : i32, i32
  %v4 = spirv.Constant 8388607 : i32
  %v5 = spirv.BitwiseAnd %v1, %v4 : i32
  %v6 = spirv.Constant 0 : i32
  %v7 = spirv.INotEqual %v3, %v6 : i32
  %v8 = spirv.Constant 8388608 : i32
  %v9 = spirv.Select %v7, %v8, %v6 : i1, i32
  %v10 = spirv.BitwiseOr %v5, %v9 : i32
  %v11 = spirv.IEqual %v3, %v6 : i32
  %v12 = spirv.Constant 1 : i32
  %v13 = spirv.Select %v11, %v12, %v3 : i1, i32
  %v14 = spirv.BitwiseAnd %b, %v0 : i32
  %v15 = spirv.ShiftRightLogical %v14, %v2 : i32, i32
  %v16 = spirv.BitwiseAnd %v14, %v4 : i32
  %v17 = spirv.INotEqual %v15, %v6 : i32
  %v18 = spirv.Select %v17, %v8, %v6 : i1, i32
  %v19 = spirv.BitwiseOr %v16, %v18 : i32
  %v20 = spirv.IEqual %v15, %v6 : i32
  %v21 = spirv.Select %v20, %v12, %v15 : i1, i32
  %v22 = spirv.ULessThan %v1, %v14 : i32
  %v23 = spirv.Select %v22, %b, %a : i1, i32
  %v24 = spirv.Select %v22, %a, %b : i1, i32
  %v25 = spirv.Select %v22, %v21, %v13 : i1, i32
  %v26 = spirv.Select %v22, %v13, %v21 : i1, i32
  %v27 = spirv.Select %v22, %v19, %v10 : i1, i32
  %v28 = spirv.Constant 3 : i32
  %v29 = spirv.ShiftLeftLogical %v27, %v28 : i32, i32
  %v30 = spirv.Select %v22, %v10, %v19 : i1, i32
  %v31 = spirv.ShiftLeftLogical %v30, %v28 : i32, i32
  %v32 = spirv.ISub %v25, %v26 : i32
  %v33 = spirv.FunctionCall @linea_f32_jam(%v31, %v32) : (i32, i32) -> i32
  %v34 = spirv.BitwiseXor %v23, %v24 : i32
  %v35 = spirv.Constant -2147483648 : i32
  %v36 = spirv.BitwiseAnd %v34, %v35 : i32
  %v37 = spirv.INotEqual %v36, %v6 : i32
  %v38 = spirv.ISub %v29, %v33 : i32
  %v39 = spirv.IAdd %v29, %v33 : i32
  %v40 = spirv.Select %v37, %v38, %v39 : i1, i32
  %v41 = spirv.BitwiseAnd %v23, %v35 : i32
  %v42 = spirv.IEqual %v40, %v6 : i32
  %v43 = spirv.LogicalAnd %v37, %v42 : i1
  %v44 = spirv.Select %v43, %v6, %v41 : i1, i32
  %v45 = spirv.FunctionCall @linea_f32_pack(%v44, %v25, %v40) : (i32, i32, i32) -> i32
  %v46 = spirv.Constant 2139095040 : i32
  %v47 = spirv.IEqual %v1, %v46 : i32
  %v48 = spirv.IEqual %v14, %v46 : i32
  %v49 = spirv.LogicalOr %v47, %v48 : i1
  %v50 = spirv.Select %v49, %v23, %v45 : i1, i32
  %v51 = spirv.UGreaterThan %v1, %v46 : i32
  %v52 = spirv.UGreaterThan %v14, %v46 : i32
  %v53 = spirv.LogicalOr %v51, %v52 : i1
  %v54 = spirv.IEqual %v1, %v46 : i32
  %v55 = spirv.IEqual %v14, %v46 : i32
  %v56 = spirv.LogicalAnd %v54, %v55 : i1
  %v57 = spirv.LogicalAnd %v56, %v37 : i1
  %v58 = spirv.LogicalOr %v53, %v57 : i1
  %v59 = spirv.Constant 2143289344 : i32
  %v60 = spirv.Select %v58, %v59, %v50 : i1, i32
  spirv.ReturnValue %v60 : i32
}

// Subtraction changes the second sign before the same exact addition algorithm.
spirv.func @linea_f32_sub(%a: i32, %b: i32) -> i32 "None" attributes {sym_visibility = "private"} {
  %v0 = spirv.Constant -2147483648 : i32
  %v1 = spirv.BitwiseXor %b, %v0 : i32
  %v2 = spirv.FunctionCall @linea_f32_add(%a, %v1) : (i32, i32) -> i32
  spirv.ReturnValue %v2 : i32
}

// Multiply normalized 24-bit significands as four 12-bit products, retaining
// all 48 bits. The two cross products plus carry fit 25 bits. Base-2^12
// carry propagation builds high/low 24-bit halves without integer64 support.
// Shift the exact product by 20, folding discarded bits into sticky. pack
// removes a possible carry before deciding whether a subnormal shift is needed.
spirv.func @linea_f32_mul(%a: i32, %b: i32) -> i32 "None" attributes {sym_visibility = "private"} {
  %v0 = spirv.Constant 2147483647 : i32
  %v1 = spirv.BitwiseAnd %a, %v0 : i32
  %v2 = spirv.Constant 23 : i32
  %v3 = spirv.ShiftRightLogical %v1, %v2 : i32, i32
  %v4 = spirv.Constant 8388607 : i32
  %v5 = spirv.BitwiseAnd %v1, %v4 : i32
  %v6 = spirv.Constant 0 : i32
  %v7 = spirv.INotEqual %v3, %v6 : i32
  %v8 = spirv.Constant 8388608 : i32
  %v9 = spirv.Select %v7, %v8, %v6 : i1, i32
  %v10 = spirv.BitwiseOr %v5, %v9 : i32
  %v11 = spirv.IEqual %v3, %v6 : i32
  %v12 = spirv.Constant 1 : i32
  %v13 = spirv.Select %v11, %v12, %v3 : i1, i32
  %v14 = spirv.BitwiseAnd %b, %v0 : i32
  %v15 = spirv.ShiftRightLogical %v14, %v2 : i32, i32
  %v16 = spirv.BitwiseAnd %v14, %v4 : i32
  %v17 = spirv.INotEqual %v15, %v6 : i32
  %v18 = spirv.Select %v17, %v8, %v6 : i1, i32
  %v19 = spirv.BitwiseOr %v16, %v18 : i32
  %v20 = spirv.IEqual %v15, %v6 : i32
  %v21 = spirv.Select %v20, %v12, %v15 : i1, i32
  %v22 = spirv.INotEqual %v10, %v6 : i32
  %v23 = spirv.FunctionCall @linea_f32_clz(%v10) : (i32) -> i32
  %v24 = spirv.Constant 8 : i32
  %v25 = spirv.ISub %v23, %v24 : i32
  %v26 = spirv.Select %v22, %v25, %v6 : i1, i32
  %v27 = spirv.ShiftLeftLogical %v10, %v26 : i32, i32
  %v28 = spirv.ISub %v13, %v26 : i32
  %v29 = spirv.INotEqual %v19, %v6 : i32
  %v30 = spirv.FunctionCall @linea_f32_clz(%v19) : (i32) -> i32
  %v31 = spirv.ISub %v30, %v24 : i32
  %v32 = spirv.Select %v29, %v31, %v6 : i1, i32
  %v33 = spirv.ShiftLeftLogical %v19, %v32 : i32, i32
  %v34 = spirv.ISub %v21, %v32 : i32
  %v35 = spirv.BitwiseXor %a, %b : i32
  %v36 = spirv.Constant -2147483648 : i32
  %v37 = spirv.BitwiseAnd %v35, %v36 : i32
  %v38 = spirv.Constant 4095 : i32
  %v39 = spirv.BitwiseAnd %v27, %v38 : i32
  %v40 = spirv.Constant 12 : i32
  %v41 = spirv.ShiftRightLogical %v27, %v40 : i32, i32
  %v42 = spirv.BitwiseAnd %v33, %v38 : i32
  %v43 = spirv.ShiftRightLogical %v33, %v40 : i32, i32
  %v44 = spirv.IMul %v39, %v42 : i32
  %v45 = spirv.IMul %v41, %v42 : i32
  %v46 = spirv.IMul %v39, %v43 : i32
  %v47 = spirv.IAdd %v45, %v46 : i32
  %v48 = spirv.IMul %v41, %v43 : i32
  %v49 = spirv.ShiftRightLogical %v44, %v40 : i32, i32
  %v50 = spirv.IAdd %v47, %v49 : i32
  %v51 = spirv.ShiftRightLogical %v50, %v40 : i32, i32
  %v52 = spirv.IAdd %v48, %v51 : i32
  %v53 = spirv.BitwiseAnd %v44, %v38 : i32
  %v54 = spirv.BitwiseAnd %v50, %v38 : i32
  %v55 = spirv.ShiftLeftLogical %v54, %v40 : i32, i32
  %v56 = spirv.BitwiseOr %v53, %v55 : i32
  %v57 = spirv.Constant 4 : i32
  %v58 = spirv.ShiftLeftLogical %v52, %v57 : i32, i32
  %v59 = spirv.Constant 20 : i32
  %v60 = spirv.ShiftRightLogical %v56, %v59 : i32, i32
  %v61 = spirv.BitwiseOr %v58, %v60 : i32
  %v62 = spirv.Constant 1048575 : i32
  %v63 = spirv.BitwiseAnd %v56, %v62 : i32
  %v64 = spirv.INotEqual %v63, %v6 : i32
  %v65 = spirv.Select %v64, %v12, %v6 : i1, i32
  %v66 = spirv.BitwiseOr %v61, %v65 : i32
  %v67 = spirv.IAdd %v28, %v34 : i32
  %v68 = spirv.Constant 127 : i32
  %v69 = spirv.ISub %v67, %v68 : i32
  %v70 = spirv.FunctionCall @linea_f32_pack(%v37, %v69, %v66) : (i32, i32, i32) -> i32
  %v71 = spirv.IEqual %v1, %v6 : i32
  %v72 = spirv.IEqual %v14, %v6 : i32
  %v73 = spirv.LogicalOr %v71, %v72 : i1
  %v74 = spirv.Constant 2139095040 : i32
  %v75 = spirv.IEqual %v1, %v74 : i32
  %v76 = spirv.IEqual %v14, %v74 : i32
  %v77 = spirv.LogicalOr %v75, %v76 : i1
  %v78 = spirv.Select %v73, %v37, %v70 : i1, i32
  %v79 = spirv.BitwiseOr %v37, %v74 : i32
  %v80 = spirv.Select %v77, %v79, %v78 : i1, i32
  %v81 = spirv.UGreaterThan %v1, %v74 : i32
  %v82 = spirv.UGreaterThan %v14, %v74 : i32
  %v83 = spirv.LogicalOr %v81, %v82 : i1
  %v84 = spirv.LogicalAnd %v73, %v77 : i1
  %v85 = spirv.LogicalOr %v83, %v84 : i1
  %v86 = spirv.Constant 2143289344 : i32
  %v87 = spirv.Select %v85, %v86, %v80 : i1, i32
  spirv.ReturnValue %v87 : i32
}

// Restoring long division produces 27 quotient bits and a sticky remainder,
// with 26 fixed steps after the leading 1. Normalize the ratio to [1, 2).
// Each remainder is less than the 24-bit divisor; doubling fits 25 bits.
// The low quotient bit OR the remaining remainder is the sticky bit.
// A zero divisor also follows these bounded integer steps, then selects the
// IEEE infinity/NaN result below. There is no approximate floating fallback.
spirv.func @linea_f32_div(%a: i32, %b: i32) -> i32 "None" attributes {sym_visibility = "private"} {
  %v0 = spirv.Constant 2147483647 : i32
  %v1 = spirv.BitwiseAnd %a, %v0 : i32
  %v2 = spirv.Constant 23 : i32
  %v3 = spirv.ShiftRightLogical %v1, %v2 : i32, i32
  %v4 = spirv.Constant 8388607 : i32
  %v5 = spirv.BitwiseAnd %v1, %v4 : i32
  %v6 = spirv.Constant 0 : i32
  %v7 = spirv.INotEqual %v3, %v6 : i32
  %v8 = spirv.Constant 8388608 : i32
  %v9 = spirv.Select %v7, %v8, %v6 : i1, i32
  %v10 = spirv.BitwiseOr %v5, %v9 : i32
  %v11 = spirv.IEqual %v3, %v6 : i32
  %v12 = spirv.Constant 1 : i32
  %v13 = spirv.Select %v11, %v12, %v3 : i1, i32
  %v14 = spirv.BitwiseAnd %b, %v0 : i32
  %v15 = spirv.ShiftRightLogical %v14, %v2 : i32, i32
  %v16 = spirv.BitwiseAnd %v14, %v4 : i32
  %v17 = spirv.INotEqual %v15, %v6 : i32
  %v18 = spirv.Select %v17, %v8, %v6 : i1, i32
  %v19 = spirv.BitwiseOr %v16, %v18 : i32
  %v20 = spirv.IEqual %v15, %v6 : i32
  %v21 = spirv.Select %v20, %v12, %v15 : i1, i32
  %v22 = spirv.INotEqual %v10, %v6 : i32
  %v23 = spirv.FunctionCall @linea_f32_clz(%v10) : (i32) -> i32
  %v24 = spirv.Constant 8 : i32
  %v25 = spirv.ISub %v23, %v24 : i32
  %v26 = spirv.Select %v22, %v25, %v6 : i1, i32
  %v27 = spirv.ShiftLeftLogical %v10, %v26 : i32, i32
  %v28 = spirv.ISub %v13, %v26 : i32
  %v29 = spirv.INotEqual %v19, %v6 : i32
  %v30 = spirv.FunctionCall @linea_f32_clz(%v19) : (i32) -> i32
  %v31 = spirv.ISub %v30, %v24 : i32
  %v32 = spirv.Select %v29, %v31, %v6 : i1, i32
  %v33 = spirv.ShiftLeftLogical %v19, %v32 : i32, i32
  %v34 = spirv.ISub %v21, %v32 : i32
  %v35 = spirv.BitwiseXor %a, %b : i32
  %v36 = spirv.Constant -2147483648 : i32
  %v37 = spirv.BitwiseAnd %v35, %v36 : i32
  %v38 = spirv.ULessThan %v27, %v33 : i32
  %v39 = spirv.ShiftLeftLogical %v27, %v12 : i32, i32
  %v40 = spirv.Select %v38, %v39, %v27 : i1, i32
  %v41 = spirv.ISub %v28, %v34 : i32
  %v42 = spirv.Constant 127 : i32
  %v43 = spirv.IAdd %v41, %v42 : i32
  %v44 = spirv.Select %v38, %v12, %v6 : i1, i32
  %v45 = spirv.ISub %v43, %v44 : i32
  %v46 = spirv.ISub %v40, %v33 : i32
  %v47 = spirv.ShiftLeftLogical %v46, %v12 : i32, i32
  %v48 = spirv.ISub %v33, %v12 : i32
  %v49 = spirv.UGreaterThan %v47, %v48 : i32
  %v50 = spirv.ShiftLeftLogical %v12, %v12 : i32, i32
  %v51 = spirv.Select %v49, %v12, %v6 : i1, i32
  %v52 = spirv.BitwiseOr %v50, %v51 : i32
  %v53 = spirv.ISub %v47, %v33 : i32
  %v54 = spirv.Select %v49, %v53, %v47 : i1, i32
  %v55 = spirv.ShiftLeftLogical %v54, %v12 : i32, i32
  %v56 = spirv.ISub %v33, %v12 : i32
  %v57 = spirv.UGreaterThan %v55, %v56 : i32
  %v58 = spirv.ShiftLeftLogical %v52, %v12 : i32, i32
  %v59 = spirv.Select %v57, %v12, %v6 : i1, i32
  %v60 = spirv.BitwiseOr %v58, %v59 : i32
  %v61 = spirv.ISub %v55, %v33 : i32
  %v62 = spirv.Select %v57, %v61, %v55 : i1, i32
  %v63 = spirv.ShiftLeftLogical %v62, %v12 : i32, i32
  %v64 = spirv.ISub %v33, %v12 : i32
  %v65 = spirv.UGreaterThan %v63, %v64 : i32
  %v66 = spirv.ShiftLeftLogical %v60, %v12 : i32, i32
  %v67 = spirv.Select %v65, %v12, %v6 : i1, i32
  %v68 = spirv.BitwiseOr %v66, %v67 : i32
  %v69 = spirv.ISub %v63, %v33 : i32
  %v70 = spirv.Select %v65, %v69, %v63 : i1, i32
  %v71 = spirv.ShiftLeftLogical %v70, %v12 : i32, i32
  %v72 = spirv.ISub %v33, %v12 : i32
  %v73 = spirv.UGreaterThan %v71, %v72 : i32
  %v74 = spirv.ShiftLeftLogical %v68, %v12 : i32, i32
  %v75 = spirv.Select %v73, %v12, %v6 : i1, i32
  %v76 = spirv.BitwiseOr %v74, %v75 : i32
  %v77 = spirv.ISub %v71, %v33 : i32
  %v78 = spirv.Select %v73, %v77, %v71 : i1, i32
  %v79 = spirv.ShiftLeftLogical %v78, %v12 : i32, i32
  %v80 = spirv.ISub %v33, %v12 : i32
  %v81 = spirv.UGreaterThan %v79, %v80 : i32
  %v82 = spirv.ShiftLeftLogical %v76, %v12 : i32, i32
  %v83 = spirv.Select %v81, %v12, %v6 : i1, i32
  %v84 = spirv.BitwiseOr %v82, %v83 : i32
  %v85 = spirv.ISub %v79, %v33 : i32
  %v86 = spirv.Select %v81, %v85, %v79 : i1, i32
  %v87 = spirv.ShiftLeftLogical %v86, %v12 : i32, i32
  %v88 = spirv.ISub %v33, %v12 : i32
  %v89 = spirv.UGreaterThan %v87, %v88 : i32
  %v90 = spirv.ShiftLeftLogical %v84, %v12 : i32, i32
  %v91 = spirv.Select %v89, %v12, %v6 : i1, i32
  %v92 = spirv.BitwiseOr %v90, %v91 : i32
  %v93 = spirv.ISub %v87, %v33 : i32
  %v94 = spirv.Select %v89, %v93, %v87 : i1, i32
  %v95 = spirv.ShiftLeftLogical %v94, %v12 : i32, i32
  %v96 = spirv.ISub %v33, %v12 : i32
  %v97 = spirv.UGreaterThan %v95, %v96 : i32
  %v98 = spirv.ShiftLeftLogical %v92, %v12 : i32, i32
  %v99 = spirv.Select %v97, %v12, %v6 : i1, i32
  %v100 = spirv.BitwiseOr %v98, %v99 : i32
  %v101 = spirv.ISub %v95, %v33 : i32
  %v102 = spirv.Select %v97, %v101, %v95 : i1, i32
  %v103 = spirv.ShiftLeftLogical %v102, %v12 : i32, i32
  %v104 = spirv.ISub %v33, %v12 : i32
  %v105 = spirv.UGreaterThan %v103, %v104 : i32
  %v106 = spirv.ShiftLeftLogical %v100, %v12 : i32, i32
  %v107 = spirv.Select %v105, %v12, %v6 : i1, i32
  %v108 = spirv.BitwiseOr %v106, %v107 : i32
  %v109 = spirv.ISub %v103, %v33 : i32
  %v110 = spirv.Select %v105, %v109, %v103 : i1, i32
  %v111 = spirv.ShiftLeftLogical %v110, %v12 : i32, i32
  %v112 = spirv.ISub %v33, %v12 : i32
  %v113 = spirv.UGreaterThan %v111, %v112 : i32
  %v114 = spirv.ShiftLeftLogical %v108, %v12 : i32, i32
  %v115 = spirv.Select %v113, %v12, %v6 : i1, i32
  %v116 = spirv.BitwiseOr %v114, %v115 : i32
  %v117 = spirv.ISub %v111, %v33 : i32
  %v118 = spirv.Select %v113, %v117, %v111 : i1, i32
  %v119 = spirv.ShiftLeftLogical %v118, %v12 : i32, i32
  %v120 = spirv.ISub %v33, %v12 : i32
  %v121 = spirv.UGreaterThan %v119, %v120 : i32
  %v122 = spirv.ShiftLeftLogical %v116, %v12 : i32, i32
  %v123 = spirv.Select %v121, %v12, %v6 : i1, i32
  %v124 = spirv.BitwiseOr %v122, %v123 : i32
  %v125 = spirv.ISub %v119, %v33 : i32
  %v126 = spirv.Select %v121, %v125, %v119 : i1, i32
  %v127 = spirv.ShiftLeftLogical %v126, %v12 : i32, i32
  %v128 = spirv.ISub %v33, %v12 : i32
  %v129 = spirv.UGreaterThan %v127, %v128 : i32
  %v130 = spirv.ShiftLeftLogical %v124, %v12 : i32, i32
  %v131 = spirv.Select %v129, %v12, %v6 : i1, i32
  %v132 = spirv.BitwiseOr %v130, %v131 : i32
  %v133 = spirv.ISub %v127, %v33 : i32
  %v134 = spirv.Select %v129, %v133, %v127 : i1, i32
  %v135 = spirv.ShiftLeftLogical %v134, %v12 : i32, i32
  %v136 = spirv.ISub %v33, %v12 : i32
  %v137 = spirv.UGreaterThan %v135, %v136 : i32
  %v138 = spirv.ShiftLeftLogical %v132, %v12 : i32, i32
  %v139 = spirv.Select %v137, %v12, %v6 : i1, i32
  %v140 = spirv.BitwiseOr %v138, %v139 : i32
  %v141 = spirv.ISub %v135, %v33 : i32
  %v142 = spirv.Select %v137, %v141, %v135 : i1, i32
  %v143 = spirv.ShiftLeftLogical %v142, %v12 : i32, i32
  %v144 = spirv.ISub %v33, %v12 : i32
  %v145 = spirv.UGreaterThan %v143, %v144 : i32
  %v146 = spirv.ShiftLeftLogical %v140, %v12 : i32, i32
  %v147 = spirv.Select %v145, %v12, %v6 : i1, i32
  %v148 = spirv.BitwiseOr %v146, %v147 : i32
  %v149 = spirv.ISub %v143, %v33 : i32
  %v150 = spirv.Select %v145, %v149, %v143 : i1, i32
  %v151 = spirv.ShiftLeftLogical %v150, %v12 : i32, i32
  %v152 = spirv.ISub %v33, %v12 : i32
  %v153 = spirv.UGreaterThan %v151, %v152 : i32
  %v154 = spirv.ShiftLeftLogical %v148, %v12 : i32, i32
  %v155 = spirv.Select %v153, %v12, %v6 : i1, i32
  %v156 = spirv.BitwiseOr %v154, %v155 : i32
  %v157 = spirv.ISub %v151, %v33 : i32
  %v158 = spirv.Select %v153, %v157, %v151 : i1, i32
  %v159 = spirv.ShiftLeftLogical %v158, %v12 : i32, i32
  %v160 = spirv.ISub %v33, %v12 : i32
  %v161 = spirv.UGreaterThan %v159, %v160 : i32
  %v162 = spirv.ShiftLeftLogical %v156, %v12 : i32, i32
  %v163 = spirv.Select %v161, %v12, %v6 : i1, i32
  %v164 = spirv.BitwiseOr %v162, %v163 : i32
  %v165 = spirv.ISub %v159, %v33 : i32
  %v166 = spirv.Select %v161, %v165, %v159 : i1, i32
  %v167 = spirv.ShiftLeftLogical %v166, %v12 : i32, i32
  %v168 = spirv.ISub %v33, %v12 : i32
  %v169 = spirv.UGreaterThan %v167, %v168 : i32
  %v170 = spirv.ShiftLeftLogical %v164, %v12 : i32, i32
  %v171 = spirv.Select %v169, %v12, %v6 : i1, i32
  %v172 = spirv.BitwiseOr %v170, %v171 : i32
  %v173 = spirv.ISub %v167, %v33 : i32
  %v174 = spirv.Select %v169, %v173, %v167 : i1, i32
  %v175 = spirv.ShiftLeftLogical %v174, %v12 : i32, i32
  %v176 = spirv.ISub %v33, %v12 : i32
  %v177 = spirv.UGreaterThan %v175, %v176 : i32
  %v178 = spirv.ShiftLeftLogical %v172, %v12 : i32, i32
  %v179 = spirv.Select %v177, %v12, %v6 : i1, i32
  %v180 = spirv.BitwiseOr %v178, %v179 : i32
  %v181 = spirv.ISub %v175, %v33 : i32
  %v182 = spirv.Select %v177, %v181, %v175 : i1, i32
  %v183 = spirv.ShiftLeftLogical %v182, %v12 : i32, i32
  %v184 = spirv.ISub %v33, %v12 : i32
  %v185 = spirv.UGreaterThan %v183, %v184 : i32
  %v186 = spirv.ShiftLeftLogical %v180, %v12 : i32, i32
  %v187 = spirv.Select %v185, %v12, %v6 : i1, i32
  %v188 = spirv.BitwiseOr %v186, %v187 : i32
  %v189 = spirv.ISub %v183, %v33 : i32
  %v190 = spirv.Select %v185, %v189, %v183 : i1, i32
  %v191 = spirv.ShiftLeftLogical %v190, %v12 : i32, i32
  %v192 = spirv.ISub %v33, %v12 : i32
  %v193 = spirv.UGreaterThan %v191, %v192 : i32
  %v194 = spirv.ShiftLeftLogical %v188, %v12 : i32, i32
  %v195 = spirv.Select %v193, %v12, %v6 : i1, i32
  %v196 = spirv.BitwiseOr %v194, %v195 : i32
  %v197 = spirv.ISub %v191, %v33 : i32
  %v198 = spirv.Select %v193, %v197, %v191 : i1, i32
  %v199 = spirv.ShiftLeftLogical %v198, %v12 : i32, i32
  %v200 = spirv.ISub %v33, %v12 : i32
  %v201 = spirv.UGreaterThan %v199, %v200 : i32
  %v202 = spirv.ShiftLeftLogical %v196, %v12 : i32, i32
  %v203 = spirv.Select %v201, %v12, %v6 : i1, i32
  %v204 = spirv.BitwiseOr %v202, %v203 : i32
  %v205 = spirv.ISub %v199, %v33 : i32
  %v206 = spirv.Select %v201, %v205, %v199 : i1, i32
  %v207 = spirv.ShiftLeftLogical %v206, %v12 : i32, i32
  %v208 = spirv.ISub %v33, %v12 : i32
  %v209 = spirv.UGreaterThan %v207, %v208 : i32
  %v210 = spirv.ShiftLeftLogical %v204, %v12 : i32, i32
  %v211 = spirv.Select %v209, %v12, %v6 : i1, i32
  %v212 = spirv.BitwiseOr %v210, %v211 : i32
  %v213 = spirv.ISub %v207, %v33 : i32
  %v214 = spirv.Select %v209, %v213, %v207 : i1, i32
  %v215 = spirv.ShiftLeftLogical %v214, %v12 : i32, i32
  %v216 = spirv.ISub %v33, %v12 : i32
  %v217 = spirv.UGreaterThan %v215, %v216 : i32
  %v218 = spirv.ShiftLeftLogical %v212, %v12 : i32, i32
  %v219 = spirv.Select %v217, %v12, %v6 : i1, i32
  %v220 = spirv.BitwiseOr %v218, %v219 : i32
  %v221 = spirv.ISub %v215, %v33 : i32
  %v222 = spirv.Select %v217, %v221, %v215 : i1, i32
  %v223 = spirv.ShiftLeftLogical %v222, %v12 : i32, i32
  %v224 = spirv.ISub %v33, %v12 : i32
  %v225 = spirv.UGreaterThan %v223, %v224 : i32
  %v226 = spirv.ShiftLeftLogical %v220, %v12 : i32, i32
  %v227 = spirv.Select %v225, %v12, %v6 : i1, i32
  %v228 = spirv.BitwiseOr %v226, %v227 : i32
  %v229 = spirv.ISub %v223, %v33 : i32
  %v230 = spirv.Select %v225, %v229, %v223 : i1, i32
  %v231 = spirv.ShiftLeftLogical %v230, %v12 : i32, i32
  %v232 = spirv.ISub %v33, %v12 : i32
  %v233 = spirv.UGreaterThan %v231, %v232 : i32
  %v234 = spirv.ShiftLeftLogical %v228, %v12 : i32, i32
  %v235 = spirv.Select %v233, %v12, %v6 : i1, i32
  %v236 = spirv.BitwiseOr %v234, %v235 : i32
  %v237 = spirv.ISub %v231, %v33 : i32
  %v238 = spirv.Select %v233, %v237, %v231 : i1, i32
  %v239 = spirv.ShiftLeftLogical %v238, %v12 : i32, i32
  %v240 = spirv.ISub %v33, %v12 : i32
  %v241 = spirv.UGreaterThan %v239, %v240 : i32
  %v242 = spirv.ShiftLeftLogical %v236, %v12 : i32, i32
  %v243 = spirv.Select %v241, %v12, %v6 : i1, i32
  %v244 = spirv.BitwiseOr %v242, %v243 : i32
  %v245 = spirv.ISub %v239, %v33 : i32
  %v246 = spirv.Select %v241, %v245, %v239 : i1, i32
  %v247 = spirv.ShiftLeftLogical %v246, %v12 : i32, i32
  %v248 = spirv.ISub %v33, %v12 : i32
  %v249 = spirv.UGreaterThan %v247, %v248 : i32
  %v250 = spirv.ShiftLeftLogical %v244, %v12 : i32, i32
  %v251 = spirv.Select %v249, %v12, %v6 : i1, i32
  %v252 = spirv.BitwiseOr %v250, %v251 : i32
  %v253 = spirv.ISub %v247, %v33 : i32
  %v254 = spirv.Select %v249, %v253, %v247 : i1, i32
  %v255 = spirv.INotEqual %v254, %v6 : i32
  %v256 = spirv.Select %v255, %v12, %v6 : i1, i32
  %v257 = spirv.BitwiseOr %v252, %v256 : i32
  %v258 = spirv.FunctionCall @linea_f32_pack(%v37, %v45, %v257) : (i32, i32, i32) -> i32
  %v259 = spirv.Constant 2139095040 : i32
  %v260 = spirv.BitwiseOr %v37, %v259 : i32
  %v261 = spirv.IEqual %v1, %v6 : i32
  %v262 = spirv.IEqual %v14, %v259 : i32
  %v263 = spirv.LogicalOr %v261, %v262 : i1
  %v264 = spirv.Select %v263, %v37, %v258 : i1, i32
  %v265 = spirv.IEqual %v14, %v6 : i32
  %v266 = spirv.IEqual %v1, %v259 : i32
  %v267 = spirv.LogicalOr %v265, %v266 : i1
  %v268 = spirv.Select %v267, %v260, %v264 : i1, i32
  %v269 = spirv.UGreaterThan %v1, %v259 : i32
  %v270 = spirv.UGreaterThan %v14, %v259 : i32
  %v271 = spirv.LogicalOr %v269, %v270 : i1
  %v272 = spirv.IEqual %v1, %v6 : i32
  %v273 = spirv.IEqual %v14, %v6 : i32
  %v274 = spirv.LogicalAnd %v272, %v273 : i1
  %v275 = spirv.IEqual %v1, %v259 : i32
  %v276 = spirv.IEqual %v14, %v259 : i32
  %v277 = spirv.LogicalAnd %v275, %v276 : i1
  %v278 = spirv.LogicalOr %v274, %v277 : i1
  %v279 = spirv.LogicalOr %v271, %v278 : i1
  %v280 = spirv.Constant 2143289344 : i32
  %v281 = spirv.Select %v279, %v280, %v268 : i1, i32
  spirv.ReturnValue %v281 : i32
}

// Comparisons classify NaNs through integer bits. No input is canonicalised:
// comparisons produce only a Boolean and do not change either operand.
spirv.func @linea_f32_unordered(%a: i32, %b: i32) -> i1 "None" attributes {sym_visibility = "private"} {
  %magnitude = spirv.Constant 2147483647 : i32
  %infinity = spirv.Constant 2139095040 : i32
  %am = spirv.BitwiseAnd %a, %magnitude : i32
  %bm = spirv.BitwiseAnd %b, %magnitude : i32
  %an = spirv.UGreaterThan %am, %infinity : i32
  %bn = spirv.UGreaterThan %bm, %infinity : i32
  %unordered = spirv.LogicalOr %an, %bn : i1
  spirv.ReturnValue %unordered : i1
}

// Signed zero compares equal; every NaN, including itself, compares unequal.
spirv.func @linea_f32_eq(%a: i32, %b: i32) -> i1 "None" attributes {sym_visibility = "private"} {
  %zero = spirv.Constant 0 : i32
  %magnitude = spirv.Constant 2147483647 : i32
  %either = spirv.BitwiseOr %a, %b : i32
  %magnitudes = spirv.BitwiseAnd %either, %magnitude : i32
  %bothzero = spirv.IEqual %magnitudes, %zero : i32
  %samebits = spirv.IEqual %a, %b : i32
  %same = spirv.LogicalOr %bothzero, %samebits : i1
  %unordered = spirv.FunctionCall @linea_f32_unordered(%a, %b) : (i32, i32) -> i1
  %ordered = spirv.LogicalNot %unordered : i1
  %answer = spirv.LogicalAnd %ordered, %same : i1
  spirv.ReturnValue %answer : i1
}

spirv.func @linea_f32_ne(%a: i32, %b: i32) -> i1 "None" attributes {sym_visibility = "private"} {
  %equal = spirv.FunctionCall @linea_f32_eq(%a, %b) : (i32, i32) -> i1
  %answer = spirv.LogicalNot %equal : i1
  spirv.ReturnValue %answer : i1
}

// Unsigned monotone keys complement all bits for negative values and flip
// only the sign bit for nonnegative values. Exclude NaNs and the two-zero
// case explicitly; finite values and infinities then follow the same order.
spirv.func @linea_f32_lt(%a: i32, %b: i32) -> i1 "None" attributes {sym_visibility = "private"} {
  %zero = spirv.Constant 0 : i32
  %ones = spirv.Constant -1 : i32
  %sign = spirv.Constant -2147483648 : i32
  %magnitude = spirv.Constant 2147483647 : i32
  %anegative = spirv.SLessThan %a, %zero : i32
  %bnegative = spirv.SLessThan %b, %zero : i32
  %anegkey = spirv.BitwiseXor %a, %ones : i32
  %bnegkey = spirv.BitwiseXor %b, %ones : i32
  %aposkey = spirv.BitwiseXor %a, %sign : i32
  %bposkey = spirv.BitwiseXor %b, %sign : i32
  %ak = spirv.Select %anegative, %anegkey, %aposkey : i1, i32
  %bk = spirv.Select %bnegative, %bnegkey, %bposkey : i1, i32
  %less = spirv.ULessThan %ak, %bk : i32
  %either = spirv.BitwiseOr %a, %b : i32
  %magnitudes = spirv.BitwiseAnd %either, %magnitude : i32
  %bothzero = spirv.IEqual %magnitudes, %zero : i32
  %unordered = spirv.FunctionCall @linea_f32_unordered(%a, %b) : (i32, i32) -> i1
  %excluded = spirv.LogicalOr %unordered, %bothzero : i1
  %ordered = spirv.LogicalNot %excluded : i1
  %answer = spirv.LogicalAnd %ordered, %less : i1
  spirv.ReturnValue %answer : i1
}

spirv.func @linea_f32_le(%a: i32, %b: i32) -> i1 "None" attributes {sym_visibility = "private"} {
  %less = spirv.FunctionCall @linea_f32_lt(%a, %b) : (i32, i32) -> i1
  %equal = spirv.FunctionCall @linea_f32_eq(%a, %b) : (i32, i32) -> i1
  %answer = spirv.LogicalOr %less, %equal : i1
  spirv.ReturnValue %answer : i1
}

spirv.func @linea_f32_gt(%a: i32, %b: i32) -> i1 "None" attributes {sym_visibility = "private"} {
  %answer = spirv.FunctionCall @linea_f32_lt(%b, %a) : (i32, i32) -> i1
  spirv.ReturnValue %answer : i1
}

spirv.func @linea_f32_ge(%a: i32, %b: i32) -> i1 "None" attributes {sym_visibility = "private"} {
  %answer = spirv.FunctionCall @linea_f32_le(%b, %a) : (i32, i32) -> i1
  spirv.ReturnValue %answer : i1
}
