// Binary-operation wrapper shared by arithmetic and comparison hardware tests.
// Production helpers are inserted once; results are raw bits or Boolean 0/1.
spirv.module Logical GLSL450 requires #spirv.vce<v1.3, [Shader], []> {
@HELPERS@
  spirv.GlobalVariable @input bind(0, 0) : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
  spirv.GlobalVariable @output bind(0, 1) : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
  spirv.GlobalVariable @count : !spirv.ptr<!spirv.struct<(i32 [0])>, PushConstant>
  spirv.GlobalVariable @global built_in("GlobalInvocationId") : !spirv.ptr<vector<3xi32>, Input>
  spirv.func @linea_map() "None" {
    %zero = spirv.Constant 0 : i32
    %one = spirv.Constant 1 : i32
    %two = spirv.Constant 2 : i32
    %gid = spirv.mlir.addressof @global : !spirv.ptr<vector<3xi32>, Input>
    %ids = spirv.Load "Input" %gid : vector<3xi32>
    %i = spirv.CompositeExtract %ids[0 : i32] : vector<3xi32>
    %pc = spirv.mlir.addressof @count : !spirv.ptr<!spirv.struct<(i32 [0])>, PushConstant>
    %np = spirv.AccessChain %pc[%zero] : !spirv.ptr<!spirv.struct<(i32 [0])>, PushConstant>, i32 -> !spirv.ptr<i32, PushConstant>
    %n = spirv.Load "PushConstant" %np : i32
    %inside = spirv.ULessThan %i, %n : i32
    spirv.mlir.selection {
      spirv.BranchConditional %inside, ^body, ^done
    ^body:
      %at = spirv.IMul %i, %two : i32
      %next = spirv.IAdd %at, %one : i32
      %in = spirv.mlir.addressof @input : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
      %out = spirv.mlir.addressof @output : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
      %lp = spirv.AccessChain %in[%zero, %at] : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>, i32, i32 -> !spirv.ptr<i32, StorageBuffer>
      %rp = spirv.AccessChain %in[%zero, %next] : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>, i32, i32 -> !spirv.ptr<i32, StorageBuffer>
      %to = spirv.AccessChain %out[%zero, %i] : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>, i32, i32 -> !spirv.ptr<i32, StorageBuffer>
      %left = spirv.Load "StorageBuffer" %lp : i32
      %right = spirv.Load "StorageBuffer" %rp : i32
@OPERATION@
      spirv.Store "StorageBuffer" %to, %result : i32
      spirv.Branch ^done
    ^done:
      spirv.mlir.merge
    }
    spirv.Return
  }
  spirv.EntryPoint "GLCompute" @linea_map, @global
  spirv.ExecutionMode @linea_map "LocalSize", 64, 1, 1
}
