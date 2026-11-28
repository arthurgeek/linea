// Instrument only the test reducer, leaving the production reduction wrapper
// unchanged. Counter word 1 is separate from the numerical result in word 0.
spirv.func @linea_count_add(%left: i32, %right: i32) -> i32 "None" {
  %zero = spirv.Constant 0 : i32
  %one = spirv.Constant 1 : i32
  %out = spirv.mlir.addressof @output : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>
  %counter = spirv.AccessChain %out[%zero, %one] : !spirv.ptr<!spirv.struct<(!spirv.rtarray<i32, stride=4> [0])>, StorageBuffer>, i32, i32 -> !spirv.ptr<i32, StorageBuffer>
  %previous = spirv.AtomicIAdd <Device> <None> %counter, %one : !spirv.ptr<i32, StorageBuffer>
  %answer = spirv.FunctionCall @linea_f32_add(%left, %right) : (i32, i32) -> i32
  spirv.ReturnValue %answer : i32
}
