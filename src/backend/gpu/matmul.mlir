// One invocation computes one row-major output, visiting k in ascending
// order. Each product and addition rounds separately through strict helpers.
  spirv.func @linea_matmul() "None" {
    %acc = spirv.Variable : !spirv.ptr<i32, Function>
    %position = spirv.Variable : !spirv.ptr<i32, Function>
    %z = spirv.Constant 0 : i32
    %one = spirv.Constant 1 : i32
    %two = spirv.Constant 2 : i32
    %three = spirv.Constant 3 : i32
    %gid = spirv.mlir.addressof @global : !spirv.ptr<vector<3xi32>, Input>
    %ids = spirv.Load "Input" %gid : vector<3xi32>
    %i = spirv.CompositeExtract %ids[0 : i32] : vector<3xi32>
    %pc = spirv.mlir.addressof @count : !spirv.ptr<!spirv.struct<(i32 [0], i32 [4], i32 [8], i32 [12])>, PushConstant>
    %np = spirv.AccessChain %pc[%z] : !spirv.ptr<!spirv.struct<(i32 [0], i32 [4], i32 [8], i32 [12])>, PushConstant>, i32 -> !spirv.ptr<i32, PushConstant>
    %n = spirv.Load "PushConstant" %np : i32
    %innerp = spirv.AccessChain %pc[%two] : !spirv.ptr<!spirv.struct<(i32 [0], i32 [4], i32 [8], i32 [12])>, PushConstant>, i32 -> !spirv.ptr<i32, PushConstant>
    %inner = spirv.Load "PushConstant" %innerp : i32
    %columnsp = spirv.AccessChain %pc[%three] : !spirv.ptr<!spirv.struct<(i32 [0], i32 [4], i32 [8], i32 [12])>, PushConstant>, i32 -> !spirv.ptr<i32, PushConstant>
    %columns = spirv.Load "PushConstant" %columnsp : i32
    %inside = spirv.ULessThan %i, %n : i32
    spirv.mlir.selection {
      spirv.BranchConditional %inside, ^calculate, ^done
    ^calculate:
      %row = spirv.UDiv %i, %columns : i32
      %column = spirv.UMod %i, %columns : i32
      %base = spirv.IMul %row, %inner : i32
      %in = spirv.mlir.addressof @input : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
      %right = spirv.mlir.addressof @right : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
      %out = spirv.mlir.addressof @output : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
      spirv.Store "Function" %acc, %z : i32
      spirv.Store "Function" %position, %z : i32
      spirv.mlir.loop {
        spirv.Branch ^header
      ^header:
        %k = spirv.Load "Function" %position : i32
        %more = spirv.ULessThan %k, %inner : i32
        spirv.BranchConditional %more, ^body, ^done
      ^body:
        %ai = spirv.IAdd %base, %k : i32
        %bbase = spirv.IMul %k, %columns : i32
        %bi = spirv.IAdd %bbase, %column : i32
    %ap = spirv.AccessChain %in[%z, %ai] : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>, i32, i32 -> !spirv.ptr<i32, StorageBuffer>
    %bp = spirv.AccessChain %right[%z, %bi] : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>, i32, i32 -> !spirv.ptr<i32, StorageBuffer>
        %a = spirv.Load "StorageBuffer" %ap : i32
        %b = spirv.Load "StorageBuffer" %bp : i32
        %product = spirv.FunctionCall @linea_f32_mul(%a, %b) : (i32, i32) -> i32
        %old = spirv.Load "Function" %acc : i32
        %sum = spirv.FunctionCall @linea_f32_add(%old, %product) : (i32, i32) -> i32
        spirv.Store "Function" %acc, %sum : i32
        spirv.Branch ^continue
      ^continue:
        %next = spirv.IAdd %k, %one : i32
        spirv.Store "Function" %position, %next : i32
        spirv.Branch ^header
      ^done:
        spirv.mlir.merge
      }
      %answer = spirv.Load "Function" %acc : i32
    %cp = spirv.AccessChain %out[%z, %i] : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>, i32, i32 -> !spirv.ptr<i32, StorageBuffer>
      spirv.Store "StorageBuffer" %cp, %answer : i32
      spirv.Branch ^done
    ^done:
      spirv.mlir.merge
    }
    spirv.Return
  }
  spirv.EntryPoint "GLCompute" @linea_matmul, @global
  spirv.ExecutionMode @linea_matmul "LocalSize", 64, 1, 1
