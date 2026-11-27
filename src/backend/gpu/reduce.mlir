// One 64-lane workgroup folds each strided lane from its first input.
// No synthetic identity enters the tree. Six shared-memory stages combine
// left with right; all invocations reach each Workgroup memory barrier.
  spirv.func @linea_reduce() "None" {
    %acc = spirv.Variable : !spirv.ptr<i32, Function>
    %position = spirv.Variable : !spirv.ptr<i32, Function>
    %z = spirv.Constant 0 : i32
    %one = spirv.Constant 1 : i32
    %width = spirv.Constant 64 : i32
    %gid = spirv.mlir.addressof @global : !spirv.ptr<vector<3xi32>, Input>
    %ids = spirv.Load "Input" %gid : vector<3xi32>
    %lane = spirv.CompositeExtract %ids[0 : i32] : vector<3xi32>
    %pc = spirv.mlir.addressof @count : !spirv.ptr<!spirv.struct<(i32 [0], i32 [4])>, PushConstant>
    %np = spirv.AccessChain %pc[%z] : !spirv.ptr<!spirv.struct<(i32 [0], i32 [4])>, PushConstant>, i32 -> !spirv.ptr<i32, PushConstant>
    %n = spirv.Load "PushConstant" %np : i32
    %initialp = spirv.AccessChain %pc[%one] : !spirv.ptr<!spirv.struct<(i32 [0], i32 [4])>, PushConstant>, i32 -> !spirv.ptr<i32, PushConstant>
    %initial = spirv.Load "PushConstant" %initialp : i32
    %in = spirv.mlir.addressof @input : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
    %out = spirv.mlir.addressof @output : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
    spirv.Store "Function" %acc, %z : i32
    %exists = spirv.ULessThan %lane, %n : i32
    spirv.mlir.selection {
      spirv.BranchConditional %exists, ^first, ^done
    ^first:
    %firstp = spirv.AccessChain %in[%z, %lane] : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>, i32, i32 -> !spirv.ptr<i32, StorageBuffer>
    %first = spirv.Load "StorageBuffer" %firstp : i32
      spirv.Store "Function" %acc, %first : i32
      spirv.Branch ^done
    ^done:
      spirv.mlir.merge
    }
    %start = spirv.IAdd %lane, %width : i32
    spirv.Store "Function" %position, %start : i32
    spirv.mlir.loop {
      spirv.Branch ^header
    ^header:
      %at = spirv.Load "Function" %position : i32
      %inside = spirv.ULessThan %at, %n : i32
      spirv.BranchConditional %inside, ^body, ^done
    ^body:
    %nextp = spirv.AccessChain %in[%z, %at] : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>, i32, i32 -> !spirv.ptr<i32, StorageBuffer>
      %next = spirv.Load "StorageBuffer" %nextp : i32
      %old = spirv.Load "Function" %acc : i32
      %folded = spirv.FunctionCall @ROOT(%old, %next) : (i32, i32) -> i32
      spirv.Store "Function" %acc, %folded : i32
      spirv.Branch ^continue
    ^continue:
      %after = spirv.IAdd %at, %width : i32
      spirv.Store "Function" %position, %after : i32
      spirv.Branch ^header
    ^done:
      spirv.mlir.merge
    }
    %shared = spirv.mlir.addressof @partial : !spirv.ptr<!spirv.array<64 x i32>, Workgroup>
    %flags = spirv.mlir.addressof @present : !spirv.ptr<!spirv.array<64 x i32>, Workgroup>
    %mine = spirv.AccessChain %shared[%lane] : !spirv.ptr<!spirv.array<64 x i32>, Workgroup>, i32 -> !spirv.ptr<i32, Workgroup>
    %mineflag = spirv.AccessChain %flags[%lane] : !spirv.ptr<!spirv.array<64 x i32>, Workgroup>, i32 -> !spirv.ptr<i32, Workgroup>
    %value = spirv.Load "Function" %acc : i32
    %flag = spirv.Select %exists, %one, %z : i1, i32
    spirv.Store "Workgroup" %mine, %value : i32
    spirv.Store "Workgroup" %mineflag, %flag : i32
    spirv.ControlBarrier <Workgroup>, <Workgroup>, <AcquireRelease|WorkgroupMemory>
    // Width 32: previous writes are visible before either operand is read.
    %w32 = spirv.Constant 32 : i32
    %active32 = spirv.ULessThan %lane, %w32 : i32
    spirv.mlir.selection {
      spirv.BranchConditional %active32, ^combine, ^done
    ^combine:
      %other32 = spirv.IAdd %lane, %w32 : i32
      %rp32 = spirv.AccessChain %shared[%other32] : !spirv.ptr<!spirv.array<64 x i32>, Workgroup>, i32 -> !spirv.ptr<i32, Workgroup>
      %rfp32 = spirv.AccessChain %flags[%other32] : !spirv.ptr<!spirv.array<64 x i32>, Workgroup>, i32 -> !spirv.ptr<i32, Workgroup>
      %rv32 = spirv.Load "Workgroup" %rp32 : i32
      %rf32 = spirv.Load "Workgroup" %rfp32 : i32
      %lv32 = spirv.Load "Workgroup" %mine : i32
      %lf32 = spirv.Load "Workgroup" %mineflag : i32
      %hasleft32 = spirv.INotEqual %lf32, %z : i32
      %hasright32 = spirv.INotEqual %rf32, %z : i32
      %fallback32 = spirv.Select %hasleft32, %lv32, %rv32 : i1, i32
      spirv.Store "Function" %acc, %fallback32 : i32
      %both32 = spirv.LogicalAnd %hasleft32, %hasright32 : i1
      spirv.mlir.selection {
        spirv.BranchConditional %both32, ^join, ^done
      ^join:
        %joined32 = spirv.FunctionCall @ROOT(%lv32, %rv32) : (i32, i32) -> i32
        spirv.Store "Function" %acc, %joined32 : i32
        spirv.Branch ^done
      ^done:
        spirv.mlir.merge
      }
      %combined32 = spirv.Load "Function" %acc : i32
      %combinedflag32 = spirv.BitwiseOr %lf32, %rf32 : i32
      spirv.Store "Workgroup" %mine, %combined32 : i32
      spirv.Store "Workgroup" %mineflag, %combinedflag32 : i32
      spirv.Branch ^done
    ^done:
      spirv.mlir.merge
    }
    spirv.ControlBarrier <Workgroup>, <Workgroup>, <AcquireRelease|WorkgroupMemory>
    // Width 16: previous writes are visible before either operand is read.
    %w16 = spirv.Constant 16 : i32
    %active16 = spirv.ULessThan %lane, %w16 : i32
    spirv.mlir.selection {
      spirv.BranchConditional %active16, ^combine, ^done
    ^combine:
      %other16 = spirv.IAdd %lane, %w16 : i32
      %rp16 = spirv.AccessChain %shared[%other16] : !spirv.ptr<!spirv.array<64 x i32>, Workgroup>, i32 -> !spirv.ptr<i32, Workgroup>
      %rfp16 = spirv.AccessChain %flags[%other16] : !spirv.ptr<!spirv.array<64 x i32>, Workgroup>, i32 -> !spirv.ptr<i32, Workgroup>
      %rv16 = spirv.Load "Workgroup" %rp16 : i32
      %rf16 = spirv.Load "Workgroup" %rfp16 : i32
      %lv16 = spirv.Load "Workgroup" %mine : i32
      %lf16 = spirv.Load "Workgroup" %mineflag : i32
      %hasleft16 = spirv.INotEqual %lf16, %z : i32
      %hasright16 = spirv.INotEqual %rf16, %z : i32
      %fallback16 = spirv.Select %hasleft16, %lv16, %rv16 : i1, i32
      spirv.Store "Function" %acc, %fallback16 : i32
      %both16 = spirv.LogicalAnd %hasleft16, %hasright16 : i1
      spirv.mlir.selection {
        spirv.BranchConditional %both16, ^join, ^done
      ^join:
        %joined16 = spirv.FunctionCall @ROOT(%lv16, %rv16) : (i32, i32) -> i32
        spirv.Store "Function" %acc, %joined16 : i32
        spirv.Branch ^done
      ^done:
        spirv.mlir.merge
      }
      %combined16 = spirv.Load "Function" %acc : i32
      %combinedflag16 = spirv.BitwiseOr %lf16, %rf16 : i32
      spirv.Store "Workgroup" %mine, %combined16 : i32
      spirv.Store "Workgroup" %mineflag, %combinedflag16 : i32
      spirv.Branch ^done
    ^done:
      spirv.mlir.merge
    }
    spirv.ControlBarrier <Workgroup>, <Workgroup>, <AcquireRelease|WorkgroupMemory>
    // Width 8: previous writes are visible before either operand is read.
    %w8 = spirv.Constant 8 : i32
    %active8 = spirv.ULessThan %lane, %w8 : i32
    spirv.mlir.selection {
      spirv.BranchConditional %active8, ^combine, ^done
    ^combine:
      %other8 = spirv.IAdd %lane, %w8 : i32
      %rp8 = spirv.AccessChain %shared[%other8] : !spirv.ptr<!spirv.array<64 x i32>, Workgroup>, i32 -> !spirv.ptr<i32, Workgroup>
      %rfp8 = spirv.AccessChain %flags[%other8] : !spirv.ptr<!spirv.array<64 x i32>, Workgroup>, i32 -> !spirv.ptr<i32, Workgroup>
      %rv8 = spirv.Load "Workgroup" %rp8 : i32
      %rf8 = spirv.Load "Workgroup" %rfp8 : i32
      %lv8 = spirv.Load "Workgroup" %mine : i32
      %lf8 = spirv.Load "Workgroup" %mineflag : i32
      %hasleft8 = spirv.INotEqual %lf8, %z : i32
      %hasright8 = spirv.INotEqual %rf8, %z : i32
      %fallback8 = spirv.Select %hasleft8, %lv8, %rv8 : i1, i32
      spirv.Store "Function" %acc, %fallback8 : i32
      %both8 = spirv.LogicalAnd %hasleft8, %hasright8 : i1
      spirv.mlir.selection {
        spirv.BranchConditional %both8, ^join, ^done
      ^join:
        %joined8 = spirv.FunctionCall @ROOT(%lv8, %rv8) : (i32, i32) -> i32
        spirv.Store "Function" %acc, %joined8 : i32
        spirv.Branch ^done
      ^done:
        spirv.mlir.merge
      }
      %combined8 = spirv.Load "Function" %acc : i32
      %combinedflag8 = spirv.BitwiseOr %lf8, %rf8 : i32
      spirv.Store "Workgroup" %mine, %combined8 : i32
      spirv.Store "Workgroup" %mineflag, %combinedflag8 : i32
      spirv.Branch ^done
    ^done:
      spirv.mlir.merge
    }
    spirv.ControlBarrier <Workgroup>, <Workgroup>, <AcquireRelease|WorkgroupMemory>
    // Width 4: previous writes are visible before either operand is read.
    %w4 = spirv.Constant 4 : i32
    %active4 = spirv.ULessThan %lane, %w4 : i32
    spirv.mlir.selection {
      spirv.BranchConditional %active4, ^combine, ^done
    ^combine:
      %other4 = spirv.IAdd %lane, %w4 : i32
      %rp4 = spirv.AccessChain %shared[%other4] : !spirv.ptr<!spirv.array<64 x i32>, Workgroup>, i32 -> !spirv.ptr<i32, Workgroup>
      %rfp4 = spirv.AccessChain %flags[%other4] : !spirv.ptr<!spirv.array<64 x i32>, Workgroup>, i32 -> !spirv.ptr<i32, Workgroup>
      %rv4 = spirv.Load "Workgroup" %rp4 : i32
      %rf4 = spirv.Load "Workgroup" %rfp4 : i32
      %lv4 = spirv.Load "Workgroup" %mine : i32
      %lf4 = spirv.Load "Workgroup" %mineflag : i32
      %hasleft4 = spirv.INotEqual %lf4, %z : i32
      %hasright4 = spirv.INotEqual %rf4, %z : i32
      %fallback4 = spirv.Select %hasleft4, %lv4, %rv4 : i1, i32
      spirv.Store "Function" %acc, %fallback4 : i32
      %both4 = spirv.LogicalAnd %hasleft4, %hasright4 : i1
      spirv.mlir.selection {
        spirv.BranchConditional %both4, ^join, ^done
      ^join:
        %joined4 = spirv.FunctionCall @ROOT(%lv4, %rv4) : (i32, i32) -> i32
        spirv.Store "Function" %acc, %joined4 : i32
        spirv.Branch ^done
      ^done:
        spirv.mlir.merge
      }
      %combined4 = spirv.Load "Function" %acc : i32
      %combinedflag4 = spirv.BitwiseOr %lf4, %rf4 : i32
      spirv.Store "Workgroup" %mine, %combined4 : i32
      spirv.Store "Workgroup" %mineflag, %combinedflag4 : i32
      spirv.Branch ^done
    ^done:
      spirv.mlir.merge
    }
    spirv.ControlBarrier <Workgroup>, <Workgroup>, <AcquireRelease|WorkgroupMemory>
    // Width 2: previous writes are visible before either operand is read.
    %w2 = spirv.Constant 2 : i32
    %active2 = spirv.ULessThan %lane, %w2 : i32
    spirv.mlir.selection {
      spirv.BranchConditional %active2, ^combine, ^done
    ^combine:
      %other2 = spirv.IAdd %lane, %w2 : i32
      %rp2 = spirv.AccessChain %shared[%other2] : !spirv.ptr<!spirv.array<64 x i32>, Workgroup>, i32 -> !spirv.ptr<i32, Workgroup>
      %rfp2 = spirv.AccessChain %flags[%other2] : !spirv.ptr<!spirv.array<64 x i32>, Workgroup>, i32 -> !spirv.ptr<i32, Workgroup>
      %rv2 = spirv.Load "Workgroup" %rp2 : i32
      %rf2 = spirv.Load "Workgroup" %rfp2 : i32
      %lv2 = spirv.Load "Workgroup" %mine : i32
      %lf2 = spirv.Load "Workgroup" %mineflag : i32
      %hasleft2 = spirv.INotEqual %lf2, %z : i32
      %hasright2 = spirv.INotEqual %rf2, %z : i32
      %fallback2 = spirv.Select %hasleft2, %lv2, %rv2 : i1, i32
      spirv.Store "Function" %acc, %fallback2 : i32
      %both2 = spirv.LogicalAnd %hasleft2, %hasright2 : i1
      spirv.mlir.selection {
        spirv.BranchConditional %both2, ^join, ^done
      ^join:
        %joined2 = spirv.FunctionCall @ROOT(%lv2, %rv2) : (i32, i32) -> i32
        spirv.Store "Function" %acc, %joined2 : i32
        spirv.Branch ^done
      ^done:
        spirv.mlir.merge
      }
      %combined2 = spirv.Load "Function" %acc : i32
      %combinedflag2 = spirv.BitwiseOr %lf2, %rf2 : i32
      spirv.Store "Workgroup" %mine, %combined2 : i32
      spirv.Store "Workgroup" %mineflag, %combinedflag2 : i32
      spirv.Branch ^done
    ^done:
      spirv.mlir.merge
    }
    spirv.ControlBarrier <Workgroup>, <Workgroup>, <AcquireRelease|WorkgroupMemory>
    // Width 1: previous writes are visible before either operand is read.
    %w1 = spirv.Constant 1 : i32
    %active1 = spirv.ULessThan %lane, %w1 : i32
    spirv.mlir.selection {
      spirv.BranchConditional %active1, ^combine, ^done
    ^combine:
      %other1 = spirv.IAdd %lane, %w1 : i32
      %rp1 = spirv.AccessChain %shared[%other1] : !spirv.ptr<!spirv.array<64 x i32>, Workgroup>, i32 -> !spirv.ptr<i32, Workgroup>
      %rfp1 = spirv.AccessChain %flags[%other1] : !spirv.ptr<!spirv.array<64 x i32>, Workgroup>, i32 -> !spirv.ptr<i32, Workgroup>
      %rv1 = spirv.Load "Workgroup" %rp1 : i32
      %rf1 = spirv.Load "Workgroup" %rfp1 : i32
      %lv1 = spirv.Load "Workgroup" %mine : i32
      %lf1 = spirv.Load "Workgroup" %mineflag : i32
      %hasleft1 = spirv.INotEqual %lf1, %z : i32
      %hasright1 = spirv.INotEqual %rf1, %z : i32
      %fallback1 = spirv.Select %hasleft1, %lv1, %rv1 : i1, i32
      spirv.Store "Function" %acc, %fallback1 : i32
      %both1 = spirv.LogicalAnd %hasleft1, %hasright1 : i1
      spirv.mlir.selection {
        spirv.BranchConditional %both1, ^join, ^done
      ^join:
        %joined1 = spirv.FunctionCall @ROOT(%lv1, %rv1) : (i32, i32) -> i32
        spirv.Store "Function" %acc, %joined1 : i32
        spirv.Branch ^done
      ^done:
        spirv.mlir.merge
      }
      %combined1 = spirv.Load "Function" %acc : i32
      %combinedflag1 = spirv.BitwiseOr %lf1, %rf1 : i32
      spirv.Store "Workgroup" %mine, %combined1 : i32
      spirv.Store "Workgroup" %mineflag, %combinedflag1 : i32
      spirv.Branch ^done
    ^done:
      spirv.mlir.merge
    }
    spirv.ControlBarrier <Workgroup>, <Workgroup>, <AcquireRelease|WorkgroupMemory>
    %isfirst = spirv.IEqual %lane, %z : i32
    spirv.mlir.selection {
      spirv.BranchConditional %isfirst, ^finish, ^done
    ^finish:
      %tree = spirv.Load "Workgroup" %mine : i32
      %nonempty = spirv.INotEqual %n, %z : i32
      spirv.Store "Function" %acc, %initial : i32
      spirv.mlir.selection {
        spirv.BranchConditional %nonempty, ^apply, ^done
      ^apply:
        %withinitial = spirv.FunctionCall @ROOT(%initial, %tree) : (i32, i32) -> i32
        spirv.Store "Function" %acc, %withinitial : i32
        spirv.Branch ^done
      ^done:
        spirv.mlir.merge
      }
      %answer = spirv.Load "Function" %acc : i32
    %result = spirv.AccessChain %out[%z, %z] : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>, i32, i32 -> !spirv.ptr<i32, StorageBuffer>
      spirv.Store "StorageBuffer" %result, %answer : i32
      spirv.Branch ^done
    ^done:
      spirv.mlir.merge
    }
    spirv.Return
  }
  spirv.EntryPoint "GLCompute" @linea_reduce, @global
  spirv.ExecutionMode @linea_reduce "LocalSize", 64, 1, 1
