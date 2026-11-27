  spirv.func @linea_uniform() "None" {
    %z = spirv.Constant 0 : i32
    %gid = spirv.mlir.addressof @element_global : !spirv.ptr<vector<3xi32>, Input>
    %ids = spirv.Load "Input" %gid : vector<3xi32>
    %i = spirv.CompositeExtract %ids[0 : i32] : vector<3xi32>
    %pc = spirv.mlir.addressof @count : !spirv.ptr<!spirv.struct<(i32 [0], i32 [4])>, PushConstant>
    %np = spirv.AccessChain %pc[%z] : !spirv.ptr<!spirv.struct<(i32 [0], i32 [4])>, PushConstant>, i32 -> !spirv.ptr<i32, PushConstant>
    %n = spirv.Load "PushConstant" %np : i32
    %inside = spirv.ULessThan %i, %n : i32
    spirv.mlir.selection {
      spirv.BranchConditional %inside, ^body, ^done
    ^body:
      %in = spirv.mlir.addressof @input : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
      %out = spirv.mlir.addressof @output : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
      %from = spirv.AccessChain %in[%z, %i] : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>, i32, i32 -> !spirv.ptr<i32, StorageBuffer>
      %to = spirv.AccessChain %out[%z, %i] : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>, i32, i32 -> !spirv.ptr<i32, StorageBuffer>
      %value = spirv.Load "StorageBuffer" %from : i32
      %one = spirv.Constant 1 : i32
      %argumentp = spirv.AccessChain %pc[%one] : !spirv.ptr<!spirv.struct<(i32 [0], i32 [4])>, PushConstant>, i32 -> !spirv.ptr<i32, PushConstant>
      %argument = spirv.Load "PushConstant" %argumentp : i32
      %mapped = spirv.FunctionCall @ROOT(%value, %argument) : (i32, i32) -> i32
      spirv.Store "StorageBuffer" %to, %mapped : i32
      spirv.Branch ^done
    ^done:
      spirv.mlir.merge
    }
    spirv.Return
  }
  spirv.EntryPoint "GLCompute" @linea_uniform, @element_global
  spirv.ExecutionMode @linea_uniform "LocalSize", 64, 1, 1
  spirv.func @linea_zip() "None" {
    %z = spirv.Constant 0 : i32
    %gid = spirv.mlir.addressof @element_global : !spirv.ptr<vector<3xi32>, Input>
    %ids = spirv.Load "Input" %gid : vector<3xi32>
    %i = spirv.CompositeExtract %ids[0 : i32] : vector<3xi32>
    %pc = spirv.mlir.addressof @count : !spirv.ptr<!spirv.struct<(i32 [0], i32 [4])>, PushConstant>
    %np = spirv.AccessChain %pc[%z] : !spirv.ptr<!spirv.struct<(i32 [0], i32 [4])>, PushConstant>, i32 -> !spirv.ptr<i32, PushConstant>
    %n = spirv.Load "PushConstant" %np : i32
    %inside = spirv.ULessThan %i, %n : i32
    spirv.mlir.selection {
      spirv.BranchConditional %inside, ^body, ^done
    ^body:
      %in = spirv.mlir.addressof @input : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
      %out = spirv.mlir.addressof @output : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
      %from = spirv.AccessChain %in[%z, %i] : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>, i32, i32 -> !spirv.ptr<i32, StorageBuffer>
      %to = spirv.AccessChain %out[%z, %i] : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>, i32, i32 -> !spirv.ptr<i32, StorageBuffer>
      %value = spirv.Load "StorageBuffer" %from : i32
      %right = spirv.mlir.addressof @right : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
      %argumentp = spirv.AccessChain %right[%z, %i] : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>, i32, i32 -> !spirv.ptr<i32, StorageBuffer>
      %argument = spirv.Load "StorageBuffer" %argumentp : i32
      %mapped = spirv.FunctionCall @ROOT(%value, %argument) : (i32, i32) -> i32
      spirv.Store "StorageBuffer" %to, %mapped : i32
      spirv.Branch ^done
    ^done:
      spirv.mlir.merge
    }
    spirv.Return
  }
  spirv.EntryPoint "GLCompute" @linea_zip, @element_global
  spirv.ExecutionMode @linea_zip "LocalSize", 64, 1, 1
