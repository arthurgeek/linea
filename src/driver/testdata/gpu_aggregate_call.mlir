module {
  gpu.module @device attributes {sym_visibility = "private", spirv.target_env = #spirv.target_env<#spirv.vce<v1.3, [Shader], []>, #spirv.resource_limits<>>} {
    func.func @copy_pair(%input: memref<2xi32, #spirv.storage_class<Function>>, %output: memref<2xi32, #spirv.storage_class<Function>>) {
      %zero = arith.constant 0 : index
      %one = arith.constant 1 : index
      %two = arith.constant 2 : index
      scf.for %i = %zero to %two step %one {
        %value = memref.load %input[%i] : memref<2xi32, #spirv.storage_class<Function>>
        memref.store %value, %output[%i] : memref<2xi32, #spirv.storage_class<Function>>
      }
      return
    }
    spirv.func @linea_map() "None" {
      %zero = arith.constant 0 : index
      %one = arith.constant 1 : index
      %value = arith.constant 17 : i32
      %input = memref.alloca() : memref<2xi32, #spirv.storage_class<Function>>
      %output = memref.alloca() : memref<2xi32, #spirv.storage_class<Function>>
      memref.store %value, %input[%zero] : memref<2xi32, #spirv.storage_class<Function>>
      memref.store %value, %input[%one] : memref<2xi32, #spirv.storage_class<Function>>
      func.call @copy_pair(%input, %output) : (memref<2xi32, #spirv.storage_class<Function>>, memref<2xi32, #spirv.storage_class<Function>>) -> ()
      spirv.Return
    }
    spirv.EntryPoint "GLCompute" @linea_map
    spirv.ExecutionMode @linea_map "LocalSize", 64, 1, 1
  }
}
