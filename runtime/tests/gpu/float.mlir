spirv.module Logical GLSL450 requires #spirv.vce<v1.3, [Shader@CAPABILITIES@], [@EXTENSIONS@]> {
  spirv.GlobalVariable @input bind(0, 0) : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
  spirv.GlobalVariable @output bind(0, 1) : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
  spirv.GlobalVariable @right bind(0, 2) : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
  spirv.GlobalVariable @count : !spirv.ptr<!spirv.struct<(i32 [0])>, PushConstant>
  spirv.GlobalVariable @global built_in("GlobalInvocationId") : !spirv.ptr<vector<3xi32>, Input>
  spirv.func @identity() "None" {
    %z = spirv.Constant 0 : i32
    %one = spirv.Constant 1 : i32
    %gid = spirv.mlir.addressof @global : !spirv.ptr<vector<3xi32>, Input>
    %ids = spirv.Load "Input" %gid : vector<3xi32>
    %i = spirv.CompositeExtract %ids[0 : i32] : vector<3xi32>
    %pc = spirv.mlir.addressof @count : !spirv.ptr<!spirv.struct<(i32 [0])>, PushConstant>
    %np = spirv.AccessChain %pc[%z] : !spirv.ptr<!spirv.struct<(i32 [0])>, PushConstant>, i32 -> !spirv.ptr<i32, PushConstant>
    %n = spirv.Load "PushConstant" %np : i32
    %inside = spirv.ULessThan %i, %n : i32
    spirv.mlir.selection {
      spirv.BranchConditional %inside, ^body, ^done
    ^body:
      %at = spirv.IAdd %i, %one : i32
      %in = spirv.mlir.addressof @input : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
      %out = spirv.mlir.addressof @output : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
      %from = spirv.AccessChain %in[%z, %at] : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>, i32, i32 -> !spirv.ptr<i32, StorageBuffer>
      %to = spirv.AccessChain %out[%z, %at] : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>, i32, i32 -> !spirv.ptr<i32, StorageBuffer>
      %value = spirv.Load "StorageBuffer" %from : i32
      %lhs = spirv.Bitcast %value : i32 to f32
      %result = spirv.Bitcast %lhs : f32 to i32
      spirv.Store "StorageBuffer" %to, %result : i32
      spirv.Branch ^done
    ^done:
      spirv.mlir.merge
    }
    spirv.Return
  }
  spirv.func @negate() "None" {
    %z = spirv.Constant 0 : i32
    %one = spirv.Constant 1 : i32
    %gid = spirv.mlir.addressof @global : !spirv.ptr<vector<3xi32>, Input>
    %ids = spirv.Load "Input" %gid : vector<3xi32>
    %i = spirv.CompositeExtract %ids[0 : i32] : vector<3xi32>
    %pc = spirv.mlir.addressof @count : !spirv.ptr<!spirv.struct<(i32 [0])>, PushConstant>
    %np = spirv.AccessChain %pc[%z] : !spirv.ptr<!spirv.struct<(i32 [0])>, PushConstant>, i32 -> !spirv.ptr<i32, PushConstant>
    %n = spirv.Load "PushConstant" %np : i32
    %inside = spirv.ULessThan %i, %n : i32
    spirv.mlir.selection {
      spirv.BranchConditional %inside, ^body, ^done
    ^body:
      %at = spirv.IAdd %i, %one : i32
      %in = spirv.mlir.addressof @input : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
      %out = spirv.mlir.addressof @output : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
      %from = spirv.AccessChain %in[%z, %at] : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>, i32, i32 -> !spirv.ptr<i32, StorageBuffer>
      %to = spirv.AccessChain %out[%z, %at] : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>, i32, i32 -> !spirv.ptr<i32, StorageBuffer>
      %value = spirv.Load "StorageBuffer" %from : i32
      %lhs = spirv.Bitcast %value : i32 to f32
      %raw = spirv.FNegate %lhs : f32
      %result = spirv.Bitcast %raw : f32 to i32
      spirv.Store "StorageBuffer" %to, %result : i32
      spirv.Branch ^done
    ^done:
      spirv.mlir.merge
    }
    spirv.Return
  }
  spirv.func @add() "None" {
    %z = spirv.Constant 0 : i32
    %one = spirv.Constant 1 : i32
    %gid = spirv.mlir.addressof @global : !spirv.ptr<vector<3xi32>, Input>
    %ids = spirv.Load "Input" %gid : vector<3xi32>
    %i = spirv.CompositeExtract %ids[0 : i32] : vector<3xi32>
    %pc = spirv.mlir.addressof @count : !spirv.ptr<!spirv.struct<(i32 [0])>, PushConstant>
    %np = spirv.AccessChain %pc[%z] : !spirv.ptr<!spirv.struct<(i32 [0])>, PushConstant>, i32 -> !spirv.ptr<i32, PushConstant>
    %n = spirv.Load "PushConstant" %np : i32
    %inside = spirv.ULessThan %i, %n : i32
    spirv.mlir.selection {
      spirv.BranchConditional %inside, ^body, ^done
    ^body:
      %at = spirv.IAdd %i, %one : i32
      %in = spirv.mlir.addressof @input : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
      %out = spirv.mlir.addressof @output : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
      %from = spirv.AccessChain %in[%z, %at] : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>, i32, i32 -> !spirv.ptr<i32, StorageBuffer>
      %to = spirv.AccessChain %out[%z, %at] : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>, i32, i32 -> !spirv.ptr<i32, StorageBuffer>
      %value = spirv.Load "StorageBuffer" %from : i32
      %lhs = spirv.Bitcast %value : i32 to f32
      %rhs_base = spirv.mlir.addressof @right : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
      %rhs_at = spirv.AccessChain %rhs_base[%z, %at] : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>, i32, i32 -> !spirv.ptr<i32, StorageBuffer>
      %rhs_bits = spirv.Load "StorageBuffer" %rhs_at : i32
      %rhs = spirv.Bitcast %rhs_bits : i32 to f32
      %raw = spirv.FAdd %lhs, %rhs : f32
      %is_nan = spirv.IsNan %raw : f32
      %nan_bits = spirv.Constant 2143289344 : i32
      %nan = spirv.Bitcast %nan_bits : i32 to f32
      %canonical = spirv.Select %is_nan, %nan, %raw : i1, f32
      %result = spirv.Bitcast %canonical : f32 to i32
      spirv.Store "StorageBuffer" %to, %result : i32
      spirv.Branch ^done
    ^done:
      spirv.mlir.merge
    }
    spirv.Return
  }
  spirv.func @subtract() "None" {
    %z = spirv.Constant 0 : i32
    %one = spirv.Constant 1 : i32
    %gid = spirv.mlir.addressof @global : !spirv.ptr<vector<3xi32>, Input>
    %ids = spirv.Load "Input" %gid : vector<3xi32>
    %i = spirv.CompositeExtract %ids[0 : i32] : vector<3xi32>
    %pc = spirv.mlir.addressof @count : !spirv.ptr<!spirv.struct<(i32 [0])>, PushConstant>
    %np = spirv.AccessChain %pc[%z] : !spirv.ptr<!spirv.struct<(i32 [0])>, PushConstant>, i32 -> !spirv.ptr<i32, PushConstant>
    %n = spirv.Load "PushConstant" %np : i32
    %inside = spirv.ULessThan %i, %n : i32
    spirv.mlir.selection {
      spirv.BranchConditional %inside, ^body, ^done
    ^body:
      %at = spirv.IAdd %i, %one : i32
      %in = spirv.mlir.addressof @input : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
      %out = spirv.mlir.addressof @output : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
      %from = spirv.AccessChain %in[%z, %at] : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>, i32, i32 -> !spirv.ptr<i32, StorageBuffer>
      %to = spirv.AccessChain %out[%z, %at] : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>, i32, i32 -> !spirv.ptr<i32, StorageBuffer>
      %value = spirv.Load "StorageBuffer" %from : i32
      %lhs = spirv.Bitcast %value : i32 to f32
      %rhs_base = spirv.mlir.addressof @right : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
      %rhs_at = spirv.AccessChain %rhs_base[%z, %at] : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>, i32, i32 -> !spirv.ptr<i32, StorageBuffer>
      %rhs_bits = spirv.Load "StorageBuffer" %rhs_at : i32
      %rhs = spirv.Bitcast %rhs_bits : i32 to f32
      %raw = spirv.FSub %lhs, %rhs : f32
      %is_nan = spirv.IsNan %raw : f32
      %nan_bits = spirv.Constant 2143289344 : i32
      %nan = spirv.Bitcast %nan_bits : i32 to f32
      %canonical = spirv.Select %is_nan, %nan, %raw : i1, f32
      %result = spirv.Bitcast %canonical : f32 to i32
      spirv.Store "StorageBuffer" %to, %result : i32
      spirv.Branch ^done
    ^done:
      spirv.mlir.merge
    }
    spirv.Return
  }
  spirv.func @multiply() "None" {
    %z = spirv.Constant 0 : i32
    %one = spirv.Constant 1 : i32
    %gid = spirv.mlir.addressof @global : !spirv.ptr<vector<3xi32>, Input>
    %ids = spirv.Load "Input" %gid : vector<3xi32>
    %i = spirv.CompositeExtract %ids[0 : i32] : vector<3xi32>
    %pc = spirv.mlir.addressof @count : !spirv.ptr<!spirv.struct<(i32 [0])>, PushConstant>
    %np = spirv.AccessChain %pc[%z] : !spirv.ptr<!spirv.struct<(i32 [0])>, PushConstant>, i32 -> !spirv.ptr<i32, PushConstant>
    %n = spirv.Load "PushConstant" %np : i32
    %inside = spirv.ULessThan %i, %n : i32
    spirv.mlir.selection {
      spirv.BranchConditional %inside, ^body, ^done
    ^body:
      %at = spirv.IAdd %i, %one : i32
      %in = spirv.mlir.addressof @input : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
      %out = spirv.mlir.addressof @output : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
      %from = spirv.AccessChain %in[%z, %at] : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>, i32, i32 -> !spirv.ptr<i32, StorageBuffer>
      %to = spirv.AccessChain %out[%z, %at] : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>, i32, i32 -> !spirv.ptr<i32, StorageBuffer>
      %value = spirv.Load "StorageBuffer" %from : i32
      %lhs = spirv.Bitcast %value : i32 to f32
      %rhs_base = spirv.mlir.addressof @right : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
      %rhs_at = spirv.AccessChain %rhs_base[%z, %at] : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>, i32, i32 -> !spirv.ptr<i32, StorageBuffer>
      %rhs_bits = spirv.Load "StorageBuffer" %rhs_at : i32
      %rhs = spirv.Bitcast %rhs_bits : i32 to f32
      %raw = spirv.FMul %lhs, %rhs : f32
      %is_nan = spirv.IsNan %raw : f32
      %nan_bits = spirv.Constant 2143289344 : i32
      %nan = spirv.Bitcast %nan_bits : i32 to f32
      %canonical = spirv.Select %is_nan, %nan, %raw : i1, f32
      %result = spirv.Bitcast %canonical : f32 to i32
      spirv.Store "StorageBuffer" %to, %result : i32
      spirv.Branch ^done
    ^done:
      spirv.mlir.merge
    }
    spirv.Return
  }
  spirv.func @divide() "None" {
    %z = spirv.Constant 0 : i32
    %one = spirv.Constant 1 : i32
    %gid = spirv.mlir.addressof @global : !spirv.ptr<vector<3xi32>, Input>
    %ids = spirv.Load "Input" %gid : vector<3xi32>
    %i = spirv.CompositeExtract %ids[0 : i32] : vector<3xi32>
    %pc = spirv.mlir.addressof @count : !spirv.ptr<!spirv.struct<(i32 [0])>, PushConstant>
    %np = spirv.AccessChain %pc[%z] : !spirv.ptr<!spirv.struct<(i32 [0])>, PushConstant>, i32 -> !spirv.ptr<i32, PushConstant>
    %n = spirv.Load "PushConstant" %np : i32
    %inside = spirv.ULessThan %i, %n : i32
    spirv.mlir.selection {
      spirv.BranchConditional %inside, ^body, ^done
    ^body:
      %at = spirv.IAdd %i, %one : i32
      %in = spirv.mlir.addressof @input : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
      %out = spirv.mlir.addressof @output : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
      %from = spirv.AccessChain %in[%z, %at] : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>, i32, i32 -> !spirv.ptr<i32, StorageBuffer>
      %to = spirv.AccessChain %out[%z, %at] : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>, i32, i32 -> !spirv.ptr<i32, StorageBuffer>
      %value = spirv.Load "StorageBuffer" %from : i32
      %lhs = spirv.Bitcast %value : i32 to f32
      %rhs_base = spirv.mlir.addressof @right : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
      %rhs_at = spirv.AccessChain %rhs_base[%z, %at] : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>, i32, i32 -> !spirv.ptr<i32, StorageBuffer>
      %rhs_bits = spirv.Load "StorageBuffer" %rhs_at : i32
      %rhs = spirv.Bitcast %rhs_bits : i32 to f32
      %raw = spirv.FDiv %lhs, %rhs : f32
      %is_nan = spirv.IsNan %raw : f32
      %nan_bits = spirv.Constant 2143289344 : i32
      %nan = spirv.Bitcast %nan_bits : i32 to f32
      %canonical = spirv.Select %is_nan, %nan, %raw : i1, f32
      %result = spirv.Bitcast %canonical : f32 to i32
      spirv.Store "StorageBuffer" %to, %result : i32
      spirv.Branch ^done
    ^done:
      spirv.mlir.merge
    }
    spirv.Return
  }
  spirv.EntryPoint "GLCompute" @identity, @global
  spirv.ExecutionMode @identity "LocalSize", 64, 1, 1
  spirv.EntryPoint "GLCompute" @negate, @global
  spirv.ExecutionMode @negate "LocalSize", 64, 1, 1
  spirv.EntryPoint "GLCompute" @add, @global
  spirv.ExecutionMode @add "LocalSize", 64, 1, 1
  spirv.EntryPoint "GLCompute" @subtract, @global
  spirv.ExecutionMode @subtract "LocalSize", 64, 1, 1
  spirv.EntryPoint "GLCompute" @multiply, @global
  spirv.ExecutionMode @multiply "LocalSize", 64, 1, 1
  spirv.EntryPoint "GLCompute" @divide, @global
  spirv.ExecutionMode @divide "LocalSize", 64, 1, 1
@MODES@
}
