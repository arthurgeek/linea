spirv.module Logical GLSL450 requires #spirv.vce<v1.3, [Shader], []> {
  spirv.GlobalVariable @input bind(0, 0) : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
  spirv.GlobalVariable @output bind(0, 1) : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
  spirv.GlobalVariable @count : !spirv.ptr<!spirv.struct<(i32 [0])>, PushConstant>
  spirv.GlobalVariable @global built_in("GlobalInvocationId") : !spirv.ptr<vector<3xi32>, Input>
  spirv.func @copy() "None" {
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
      spirv.Store "StorageBuffer" %to, %value : i32
      spirv.Branch ^done
    ^done:
      spirv.mlir.merge
    }
    spirv.Return
  }
  spirv.EntryPoint "GLCompute" @copy, @global
  spirv.ExecutionMode @copy "LocalSize", 64, 1, 1
}
