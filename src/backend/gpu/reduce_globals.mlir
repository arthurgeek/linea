// Shared runtime ABI: A/input=0, C/output=1, B/right=2; 16-byte push range.
  spirv.GlobalVariable @input bind(0, 0) : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
  spirv.GlobalVariable @output bind(0, 1) : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
  spirv.GlobalVariable @right bind(0, 2) : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
  spirv.GlobalVariable @count : !spirv.ptr<!spirv.struct<(i32 [0], i32 [4])>, PushConstant>
  spirv.GlobalVariable @global built_in("LocalInvocationId") : !spirv.ptr<vector<3xi32>, Input>
  spirv.GlobalVariable @element_global built_in("GlobalInvocationId") : !spirv.ptr<vector<3xi32>, Input>
  spirv.GlobalVariable @partial : !spirv.ptr<!spirv.array<64 x i32>, Workgroup>
  spirv.GlobalVariable @present : !spirv.ptr<!spirv.array<64 x i32>, Workgroup>
