!linea_static0 = !llvm.struct<packed (i64, i64)>
module {
  llvm.mlir.global external @linea_runtime_abi_1() {addr_space = 0 : i32} : i64
  llvm.mlir.global internal @linea_abi() {addr_space = 0 : i32} : !llvm.ptr {
    %a = llvm.mlir.addressof @linea_runtime_abi_1 : !llvm.ptr
    llvm.return %a : !llvm.ptr
  }
  llvm.mlir.global appending @llvm.used() {addr_space = 0 : i32, section = "llvm.metadata"} : !llvm.array<1 x ptr> {
    %a = llvm.mlir.addressof @linea_abi : !llvm.ptr
    %u = llvm.mlir.undef : !llvm.array<1 x ptr>
    %v = llvm.insertvalue %a, %u[0] : !llvm.array<1 x ptr>
    llvm.return %v : !llvm.array<1 x ptr>
  }
  llvm.mlir.global internal constant @linea_file0("tests/text/a_slice_refuses_to_split_a_character.lin\00") : !llvm.array<52 x i8>
  llvm.mlir.global internal constant @linea_file1("std/text/str.lin\00") : !llvm.array<17 x i8>
  llvm.mlir.global internal constant @linea_file2("std/io/core/output.lin\00") : !llvm.array<23 x i8>
  llvm.mlir.global internal constant @linea_file3("std/mem/slice.lin\00") : !llvm.array<18 x i8>
  llvm.mlir.global internal constant @linea_file4("std/option/option.lin\00") : !llvm.array<22 x i8>
  llvm.mlir.global internal constant @linea_file5("std/io/core/descriptor.lin\00") : !llvm.array<27 x i8>
  llvm.mlir.global internal constant @linea_file6("std/fmt/render.lin\00") : !llvm.array<19 x i8>
  llvm.mlir.global internal constant @linea_file7("std/io/core/error.lin\00") : !llvm.array<22 x i8>
  llvm.mlir.global internal constant @linea_file8("std/io/core/byte_writer.lin\00") : !llvm.array<28 x i8>
  llvm.mlir.global internal constant @linea_file9("std/fmt/decimal.lin\00") : !llvm.array<20 x i8>
  llvm.mlir.global internal constant @linea_file10("std/mem/fd.lin\00") : !llvm.array<15 x i8>
  llvm.mlir.global internal constant @linea_str0("Ol\C3\A1!") : !llvm.array<5 x i8>
  llvm.mlir.global internal constant @linea_str1("error: ") : !llvm.array<7 x i8>
  llvm.mlir.global internal constant @linea_str2("called Option.unwrap on None") : !llvm.array<28 x i8>
  llvm.mlir.global internal constant @linea_str3("\0A") : !llvm.array<1 x i8>
  llvm.mlir.global internal constant @linea_str4("") : !llvm.array<0 x i8>
  llvm.mlir.global internal constant @linea_str5(" failed (") : !llvm.array<9 x i8>
  llvm.mlir.global internal constant @linea_str6(") after ") : !llvm.array<8 x i8>
  llvm.mlir.global internal constant @linea_str7(" bytes") : !llvm.array<6 x i8>
  llvm.mlir.global internal constant @linea_str8("; errno ") : !llvm.array<8 x i8>
  llvm.mlir.global internal constant @linea_str9("Read") : !llvm.array<4 x i8>
  llvm.mlir.global internal constant @linea_str10(" }") : !llvm.array<2 x i8>
  llvm.mlir.global internal constant @linea_str11(")") : !llvm.array<1 x i8>
  llvm.mlir.global internal constant @linea_str12("Write") : !llvm.array<5 x i8>
  llvm.mlir.global internal constant @linea_str13("Flush") : !llvm.array<5 x i8>
  llvm.mlir.global internal constant @linea_str14("Close") : !llvm.array<5 x i8>
  llvm.mlir.global internal constant @linea_str15("Open") : !llvm.array<4 x i8>
  llvm.mlir.global internal constant @linea_str16("Metadata") : !llvm.array<8 x i8>
  llvm.mlir.global internal constant @linea_str17("Permissions") : !llvm.array<11 x i8>
  llvm.mlir.global internal constant @linea_str18("Publish") : !llvm.array<7 x i8>
  llvm.mlir.global internal constant @linea_str19("Remove") : !llvm.array<6 x i8>
  llvm.mlir.global internal constant @linea_str20("Random") : !llvm.array<6 x i8>
  llvm.mlir.global internal constant @linea_str21("Listen") : !llvm.array<6 x i8>
  llvm.mlir.global internal constant @linea_str22("Accept") : !llvm.array<6 x i8>
  llvm.mlir.global internal constant @linea_str23("Connect") : !llvm.array<7 x i8>
  llvm.mlir.global internal constant @linea_str24("Configure") : !llvm.array<9 x i8>
  llvm.mlir.global internal constant @linea_str25("Other") : !llvm.array<5 x i8>
  llvm.mlir.global internal constant @linea_str26("NotFound") : !llvm.array<8 x i8>
  llvm.mlir.global internal constant @linea_str27("PermissionDenied") : !llvm.array<16 x i8>
  llvm.mlir.global internal constant @linea_str28("AlreadyExists") : !llvm.array<13 x i8>
  llvm.mlir.global internal constant @linea_str29("WouldBlock") : !llvm.array<10 x i8>
  llvm.mlir.global internal constant @linea_str30("BrokenPipe") : !llvm.array<10 x i8>
  llvm.mlir.global internal constant @linea_str31("Interrupted") : !llvm.array<11 x i8>
  llvm.mlir.global internal constant @linea_str32("InvalidInput") : !llvm.array<12 x i8>
  llvm.mlir.global internal constant @linea_str33("NotDirectory") : !llvm.array<12 x i8>
  llvm.mlir.global internal constant @linea_str34("IsDirectory") : !llvm.array<11 x i8>
  llvm.mlir.global internal constant @linea_str35("Unsupported") : !llvm.array<11 x i8>
  llvm.mlir.global internal constant @linea_str36("NoSpace") : !llvm.array<7 x i8>
  llvm.mlir.global internal constant @linea_str37("ResourceExhausted") : !llvm.array<17 x i8>
  llvm.mlir.global internal constant @linea_str38("Symlink") : !llvm.array<7 x i8>
  llvm.mlir.global internal constant @linea_str39("InvalidDescriptor") : !llvm.array<17 x i8>
  llvm.mlir.global internal constant @linea_str40("NoProgress") : !llvm.array<10 x i8>
  llvm.mlir.global internal constant @linea_str41("InvalidProgress") : !llvm.array<15 x i8>
  llvm.mlir.global internal constant @linea_str42("TimedOut") : !llvm.array<8 x i8>
  llvm.mlir.global internal constant @linea_str43("ConnectionReset") : !llvm.array<15 x i8>
  llvm.mlir.global internal constant @linea_str44("ConnectionRefused") : !llvm.array<17 x i8>
  llvm.mlir.global internal constant @linea_str45("AddressInUse") : !llvm.array<12 x i8>
  llvm.mlir.global internal constant @linea_str46("-") : !llvm.array<1 x i8>
  llvm.mlir.global internal constant @linea_str47("00010203040506070809101112131415161718192021222324252627282930313233343536373839404142434445464748495051525354555657585960616263646566676869707172737475767778798081828384858687888990919293949596979899") : !llvm.array<200 x i8>
  llvm.mlir.global internal constant @linea_str48("0") : !llvm.array<1 x i8>
  llvm.mlir.global internal constant @linea_static0() {addr_space = 0 : i32, alignment = 8 : i64} : !linea_static0 {
    %s0 = llvm.mlir.undef : !linea_static0
    %a0 = llvm.mlir.addressof @linea_str47 : !llvm.ptr
    %e0 = llvm.ptrtoint %a0 : !llvm.ptr to i64
    %s1 = llvm.insertvalue %e0, %s0[0] : !linea_static0
    %e1 = llvm.mlir.constant(200 : i64) : i64
    %s2 = llvm.insertvalue %e1, %s1[1] : !linea_static0
    llvm.return %s2 : !linea_static0
  }
  func.func private @linea_set_args(i32, !llvm.ptr)
  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_panic(i64, i64, !llvm.ptr, i32, i32) attributes {passthrough = ["noreturn"]}
  func.func private @linea_write_some(i32, i64, i64) -> i64
  func.func private @linea_io_category(i32) -> i8
  func.func private @"lin.;main"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 16 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 16 : i64
    %s3 = llvm.alloca %z3 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z4 = arith.constant 1 : i64
    %s4 = llvm.alloca %z4 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z5 = arith.constant 1 : i64
    %s5 = llvm.alloca %z5 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z6 = arith.constant 16 : i64
    %s6 = llvm.alloca %z6 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z7 = arith.constant 1 : i64
    %s7 = llvm.alloca %z7 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z8 = arith.constant 1 : i64
    %s8 = llvm.alloca %z8 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z9 = arith.constant 16 : i64
    %s9 = llvm.alloca %z9 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z10 = arith.constant 1 : i64
    %s10 = llvm.alloca %z10 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z11 = arith.constant 1 : i64
    %s11 = llvm.alloca %z11 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z12 = arith.constant 16 : i64
    %s12 = llvm.alloca %z12 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z13 = arith.constant 1 : i64
    %s13 = llvm.alloca %z13 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z14 = arith.constant 1 : i64
    %s14 = llvm.alloca %z14 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z15 = arith.constant 16 : i64
    %s15 = llvm.alloca %z15 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z16 = arith.constant 48 : i64
    %s16 = llvm.alloca %z16 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz12 = arith.constant 24 : i64
    %rs12 = llvm.alloca %rz12 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz37 = arith.constant 24 : i64
    %rs37 = llvm.alloca %rz37 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz62 = arith.constant 24 : i64
    %rs62 = llvm.alloca %rz62 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz87 = arith.constant 24 : i64
    %rs87 = llvm.alloca %rz87 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz111 = arith.constant 24 : i64
    %rs111 = llvm.alloca %rz111 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %ba1 = llvm.mlir.addressof @linea_str0 : !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":15:13)
    %v1 = llvm.ptrtoint %ba1 : !llvm.ptr to i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":15:13)
    %v2 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":15:13)
    llvm.store %v1, %s0 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":15:13)
    %v5 = arith.constant 5 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":15:13)
    %v6 = arith.constant 8 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":15:13)
    %v7 = llvm.getelementptr %s0[%v6] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_slice_refuses_to_split_a_character.lin":15:13)
    llvm.store %v5, %v7 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":15:13)
    %v10 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:43)
    %v11 = arith.constant 2 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:46)
    func.call @"lin.std.text;Str.slice"(%rs12, %s0, %v10, %v11) : (!llvm.ptr, !llvm.ptr, i64, i64) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:30)
    %v13 = llvm.load %rs12 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
    %v14 = arith.constant 1 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
    %v15 = arith.cmpi eq, %v13, %v14 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
    cf.cond_br %v15, ^b2, ^b3 loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
  ^b1:
    %v32 = llvm.load %s2 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
    llvm.store %v32, %s1 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:5)
    %v35 = arith.constant 2 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:44)
    %v36 = arith.constant 3 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:47)
    func.call @"lin.std.text;Str.slice"(%rs37, %s0, %v35, %v36) : (!llvm.ptr, !llvm.ptr, i64, i64) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:31)
    %v38 = llvm.load %rs37 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    %v39 = arith.constant 1 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    %v40 = arith.cmpi eq, %v38, %v39 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    cf.cond_br %v40, ^b7, ^b8 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
  ^b2:
    %v17 = arith.constant 8 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
    %v18 = llvm.getelementptr %rs12[%v17] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
    %cl20 = arith.constant 16 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
    "llvm.intr.memcpy"(%s3, %v18, %cl20) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
    %v22 = func.call @"lin.std.text;Str.length"(%s3) : (!llvm.ptr) -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":19:20)
    llvm.store %v22, %s2 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
    cf.br ^b1 loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
  ^b3:
    %v25 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
    %v26 = arith.cmpi eq, %v13, %v25 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
    cf.cond_br %v26, ^b4, ^b5 loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
  ^b4:
    %v28 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":20:17)
    llvm.store %v28, %s2 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
    cf.br ^b1 loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
  ^b5:
    %tk1 = arith.constant 3 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
    %tl1 = arith.constant 18 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
    %tc1 = arith.constant 24 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
    llvm.unreachable loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
  ^b6:
    %v56 = llvm.load %s5 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    llvm.store %v56, %s4 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:5)
    %v59 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:44)
    %v61 = func.call @"lin.std.text;Str.length"(%s0) : (!llvm.ptr) -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:47)
    func.call @"lin.std.text;Str.slice"(%rs62, %s0, %v59, %v61) : (!llvm.ptr, !llvm.ptr, i64, i64) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:31)
    %v63 = llvm.load %rs62 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    %v64 = arith.constant 1 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    %v65 = arith.cmpi eq, %v63, %v64 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    cf.cond_br %v65, ^b12, ^b13 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
  ^b7:
    %v42 = arith.constant 8 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    %v43 = llvm.getelementptr %rs37[%v42] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    %cl45 = arith.constant 16 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    "llvm.intr.memcpy"(%s6, %v43, %cl45) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    %v46 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":25:20)
    llvm.store %v46, %s5 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    cf.br ^b6 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
  ^b8:
    %v49 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    %v50 = arith.cmpi eq, %v38, %v49 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    cf.cond_br %v50, ^b9, ^b10 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
  ^b9:
    %v52 = arith.constant 1 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":26:17)
    llvm.store %v52, %s5 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    cf.br ^b6 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
  ^b10:
    %tk2 = arith.constant 3 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    %tf2 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    %tl2 = arith.constant 24 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    %tc2 = arith.constant 25 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    llvm.unreachable loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
  ^b11:
    %v82 = llvm.load %s8 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    llvm.store %v82, %s7 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:5)
    %v85 = arith.constant 3 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:48)
    %v86 = arith.constant 2 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:51)
    func.call @"lin.std.text;Str.slice"(%rs87, %s0, %v85, %v86) : (!llvm.ptr, !llvm.ptr, i64, i64) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:35)
    %v88 = llvm.load %rs87 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    %v89 = arith.constant 1 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    %v90 = arith.cmpi eq, %v88, %v89 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    cf.cond_br %v90, ^b17, ^b18 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
  ^b12:
    %v67 = arith.constant 8 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    %v68 = llvm.getelementptr %rs62[%v67] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    %cl70 = arith.constant 16 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    "llvm.intr.memcpy"(%s9, %v68, %cl70) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    %v72 = func.call @"lin.std.text;Str.length"(%s9) : (!llvm.ptr) -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":32:20)
    llvm.store %v72, %s8 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    cf.br ^b11 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
  ^b13:
    %v75 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    %v76 = arith.cmpi eq, %v63, %v75 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    cf.cond_br %v76, ^b14, ^b15 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
  ^b14:
    %v78 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":33:17)
    llvm.store %v78, %s8 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    cf.br ^b11 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
  ^b15:
    %tk3 = arith.constant 3 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    %tf3 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    %tl3 = arith.constant 31 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    %tc3 = arith.constant 25 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    func.call @linea_trap(%tk3, %tf3, %tl3, %tc3) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    llvm.unreachable loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
  ^b16:
    %v106 = llvm.load %s11 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    llvm.store %v106, %s10 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:5)
    %v109 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:43)
    %v110 = arith.constant 99 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:46)
    func.call @"lin.std.text;Str.slice"(%rs111, %s0, %v109, %v110) : (!llvm.ptr, !llvm.ptr, i64, i64) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:30)
    %v112 = llvm.load %rs111 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    %v113 = arith.constant 1 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    %v114 = arith.cmpi eq, %v112, %v113 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    cf.cond_br %v114, ^b22, ^b23 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
  ^b17:
    %v92 = arith.constant 8 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    %v93 = llvm.getelementptr %rs87[%v92] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    %cl95 = arith.constant 16 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    "llvm.intr.memcpy"(%s12, %v93, %cl95) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    %v96 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":39:20)
    llvm.store %v96, %s11 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    cf.br ^b16 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
  ^b18:
    %v99 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    %v100 = arith.cmpi eq, %v88, %v99 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    cf.cond_br %v100, ^b19, ^b20 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
  ^b19:
    %v102 = arith.constant 1 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":40:17)
    llvm.store %v102, %s11 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    cf.br ^b16 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
  ^b20:
    %tk4 = arith.constant 3 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    %tf4 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    %tl4 = arith.constant 38 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    %tc4 = arith.constant 29 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    func.call @linea_trap(%tk4, %tf4, %tl4, %tc4) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    llvm.unreachable loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
  ^b21:
    %v130 = llvm.load %s14 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    llvm.store %v130, %s13 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:5)
    %v132 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:12)
    llvm.store %v132, %s16 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:12)
    %v135 = arith.constant 8 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:12)
    %v136 = llvm.getelementptr %s16[%v135] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:12)
    %v137 = llvm.load %s1 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:22)
    %v138 = llvm.load %s4 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:29)
    %v139 = arith.addi %v137, %v138 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:22)
    %k5 = arith.cmpi ult, %v139, %v137 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:27)
    cf.cond_br %k5, ^t5, ^c5 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:27)
  ^t5:
    %tk5 = arith.constant 0 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:27)
    %tf5 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:27)
    %tl5 = arith.constant 48 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:27)
    %tc5 = arith.constant 27 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:27)
    func.call @linea_trap(%tk5, %tf5, %tl5, %tc5) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:27)
    llvm.unreachable loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:27)
  ^c5:
    %p140 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:27)
    %v140 = arith.addi %v139, %p140 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:27)
    %v141 = llvm.load %s7 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:37)
    %v142 = arith.addi %v140, %v141 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:22)
    %k6 = arith.cmpi ult, %v142, %v140 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:35)
    cf.cond_br %k6, ^t6, ^c6 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:35)
  ^t6:
    %tk6 = arith.constant 0 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:35)
    %tf6 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:35)
    %tl6 = arith.constant 48 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:35)
    %tc6 = arith.constant 35 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:35)
    func.call @linea_trap(%tk6, %tf6, %tl6, %tc6) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:35)
    llvm.unreachable loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:35)
  ^c6:
    %p143 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:35)
    %v143 = arith.addi %v142, %p143 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:35)
    %v144 = llvm.load %s10 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:45)
    %v145 = arith.addi %v143, %v144 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:22)
    %k7 = arith.cmpi ult, %v145, %v143 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:43)
    cf.cond_br %k7, ^t7, ^c7 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:43)
  ^t7:
    %tk7 = arith.constant 0 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:43)
    %tf7 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:43)
    %tl7 = arith.constant 48 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:43)
    %tc7 = arith.constant 43 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:43)
    func.call @linea_trap(%tk7, %tf7, %tl7, %tc7) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:43)
    llvm.unreachable loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:43)
  ^c7:
    %p146 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:43)
    %v146 = arith.addi %v145, %p146 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:43)
    %v147 = llvm.load %s13 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:57)
    %v148 = arith.addi %v146, %v147 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:22)
    %k8 = arith.cmpi ult, %v148, %v146 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:55)
    cf.cond_br %k8, ^t8, ^c8 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:55)
  ^t8:
    %tk8 = arith.constant 0 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:55)
    %tf8 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:55)
    %tl8 = arith.constant 48 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:55)
    %tc8 = arith.constant 55 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:55)
    func.call @linea_trap(%tk8, %tf8, %tl8, %tc8) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:55)
    llvm.unreachable loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:55)
  ^c8:
    %p149 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:55)
    %v149 = arith.addi %v148, %p149 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:55)
    %k9m = arith.constant 255 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:16)
    %k9 = arith.cmpi ugt, %v149, %k9m : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:16)
    cf.cond_br %k9, ^t9, ^c9 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:16)
  ^t9:
    %tk9 = arith.constant 2 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:16)
    %tf9 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:16)
    %tl9 = arith.constant 48 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:16)
    %tc9 = arith.constant 16 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:16)
    func.call @linea_trap(%tk9, %tf9, %tl9, %tc9) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:16)
    llvm.unreachable loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:16)
  ^c9:
    %p150 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:16)
    %v150 = arith.addi %v149, %p150 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:16)
    %iw151 = arith.trunci %v150 : i64 to i8 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:12)
    llvm.store %iw151, %v136 : i8, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:12)
    %v152 = llvm.load %s16 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:5)
    %v153 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:5)
    %v154 = arith.cmpi eq, %v152, %v153 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:5)
    cf.cond_br %v154, ^b26, ^b27 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:5)
  ^b22:
    %v116 = arith.constant 8 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    %v117 = llvm.getelementptr %rs111[%v116] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    %cl119 = arith.constant 16 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    "llvm.intr.memcpy"(%s15, %v117, %cl119) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    %v120 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":43:20)
    llvm.store %v120, %s14 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    cf.br ^b21 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
  ^b23:
    %v123 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    %v124 = arith.cmpi eq, %v112, %v123 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    cf.cond_br %v124, ^b24, ^b25 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
  ^b24:
    %v126 = arith.constant 1 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":44:17)
    llvm.store %v126, %s14 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    cf.br ^b21 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
  ^b25:
    %tk10 = arith.constant 3 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    %tf10 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    %tl10 = arith.constant 42 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    %tc10 = arith.constant 24 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    func.call @linea_trap(%tk10, %tf10, %tl10, %tc10) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    llvm.unreachable loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
  ^b26:
    %v156 = arith.constant 8 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:5)
    %v157 = llvm.getelementptr %s16[%v156] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:5)
    %iw158 = llvm.load %v157 : !llvm.ptr -> i8 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:5)
    %v158 = arith.extui %iw158 : i8 to i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:5)
    func.return %v158 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:5)
  ^b27:
    %v160 = arith.constant 8 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:5)
    %v161 = llvm.getelementptr %s16[%v160] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:5)
    %v162 = func.call @"lin.std.io.core;report[std.io.core.IoError]"(%v161) : (!llvm.ptr) -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:5)
    func.return %v162 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:5)
  }
  func.func private @"lin.std.text;Str.slice"(%sret: !llvm.ptr, %a0: !llvm.ptr, %a1: i64, %a2: i64) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 1 : i64
    %s3 = llvm.alloca %z3 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z4 = arith.constant 24 : i64
    %s4 = llvm.alloca %z4 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z5 = arith.constant 1 : i64
    %s5 = llvm.alloca %z5 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z6 = arith.constant 24 : i64
    %s6 = llvm.alloca %z6 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    llvm.store %a1, %s1 : i64, !llvm.ptr
    llvm.store %a2, %s2 : i64, !llvm.ptr
    %rz57 = arith.constant 24 : i64
    %rs57 = llvm.alloca %rz57 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz58 = arith.constant 16 : i64
    %rs58 = llvm.alloca %rz58 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/text/str.lin":L:C)
    %v1 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/text/str.lin":L:C)
    %v2 = arith.cmpi ugt, %v0, %v1 : i64 loc("std/text/str.lin":L:C)
    cf.cond_br %v2, ^b1, ^b2 loc("std/text/str.lin":L:C)
  ^b1:
    %v4 = arith.constant 1 : i1 loc("std/text/str.lin":L:C)
    %sw5 = arith.extui %v4 : i1 to i8 loc("std/text/str.lin":L:C)
    llvm.store %sw5, %s3 : i8, !llvm.ptr loc("std/text/str.lin":L:C)
    cf.br ^b3 loc("std/text/str.lin":L:C)
  ^b2:
    %v7 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/text/str.lin":L:C)
    %v8 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/text/str.lin":L:C)
    %v9 = func.call @"lin.std.text;Str.length"(%v8) : (!llvm.ptr) -> i64 loc("std/text/str.lin":L:C)
    %v10 = arith.cmpi ugt, %v7, %v9 : i64 loc("std/text/str.lin":L:C)
    %sw11 = arith.extui %v10 : i1 to i8 loc("std/text/str.lin":L:C)
    llvm.store %sw11, %s3 : i8, !llvm.ptr loc("std/text/str.lin":L:C)
    cf.br ^b3 loc("std/text/str.lin":L:C)
  ^b3:
    %lw13 = llvm.load %s3 : !llvm.ptr -> i8 loc("std/text/str.lin":L:C)
    %lz13 = arith.constant 0 : i8 loc("std/text/str.lin":L:C)
    %v13 = arith.cmpi ne, %lw13, %lz13 : i8 loc("std/text/str.lin":L:C)
    cf.cond_br %v13, ^b4, ^b5 loc("std/text/str.lin":L:C)
  ^b4:
    %v16 = arith.constant 0 : i64 loc("std/text/str.lin":L:C)
    llvm.store %v16, %s4 : i64, !llvm.ptr loc("std/text/str.lin":L:C)
    cf.br ^b6 loc("std/text/str.lin":L:C)
  ^b5:
    %v20 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/text/str.lin":L:C)
    %v21 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/text/str.lin":L:C)
    %v22 = func.call @"lin.std.text;starts_a_character"(%v20, %v21) : (!llvm.ptr, i64) -> i1 loc("std/text/str.lin":L:C)
    %v23 = arith.constant 0 : i1 loc("std/text/str.lin":L:C)
    %v24 = arith.cmpi eq, %v22, %v23 : i1 loc("std/text/str.lin":L:C)
    cf.cond_br %v24, ^b7, ^b8 loc("std/text/str.lin":L:C)
  ^b6:
    %rl65 = arith.constant 24 : i64 loc("std/text/str.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s4, %rl65) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/text/str.lin":L:C)
    func.return loc("std/text/str.lin":L:C)
  ^b7:
    %v26 = arith.constant 1 : i1 loc("std/text/str.lin":L:C)
    %sw27 = arith.extui %v26 : i1 to i8 loc("std/text/str.lin":L:C)
    llvm.store %sw27, %s5 : i8, !llvm.ptr loc("std/text/str.lin":L:C)
    cf.br ^b9 loc("std/text/str.lin":L:C)
  ^b8:
    %v29 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/text/str.lin":L:C)
    %v30 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/text/str.lin":L:C)
    %v31 = func.call @"lin.std.text;starts_a_character"(%v29, %v30) : (!llvm.ptr, i64) -> i1 loc("std/text/str.lin":L:C)
    %v32 = arith.constant 0 : i1 loc("std/text/str.lin":L:C)
    %v33 = arith.cmpi eq, %v31, %v32 : i1 loc("std/text/str.lin":L:C)
    %sw34 = arith.extui %v33 : i1 to i8 loc("std/text/str.lin":L:C)
    llvm.store %sw34, %s5 : i8, !llvm.ptr loc("std/text/str.lin":L:C)
    cf.br ^b9 loc("std/text/str.lin":L:C)
  ^b9:
    %lw36 = llvm.load %s5 : !llvm.ptr -> i8 loc("std/text/str.lin":L:C)
    %lz36 = arith.constant 0 : i8 loc("std/text/str.lin":L:C)
    %v36 = arith.cmpi ne, %lw36, %lz36 : i8 loc("std/text/str.lin":L:C)
    cf.cond_br %v36, ^b10, ^b11 loc("std/text/str.lin":L:C)
  ^b10:
    %v39 = arith.constant 0 : i64 loc("std/text/str.lin":L:C)
    llvm.store %v39, %s6 : i64, !llvm.ptr loc("std/text/str.lin":L:C)
    cf.br ^b12 loc("std/text/str.lin":L:C)
  ^b11:
    %v43 = arith.constant 1 : i64 loc("std/text/str.lin":L:C)
    llvm.store %v43, %s6 : i64, !llvm.ptr loc("std/text/str.lin":L:C)
    %v45 = arith.constant 8 : i64 loc("std/text/str.lin":L:C)
    %v46 = llvm.getelementptr %s6[%v45] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/text/str.lin":L:C)
    %v47 = arith.constant 0 : i64 loc("std/text/str.lin":L:C)
    %v49 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/text/str.lin":L:C)
    %v50 = arith.constant 0 : i64 loc("std/text/str.lin":L:C)
    %v52 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/text/str.lin":L:C)
    %v53 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/text/str.lin":L:C)
    %v54 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/text/str.lin":L:C)
    %v55 = arith.subi %v53, %v54 : i64 loc("std/text/str.lin":L:C)
    %k1 = arith.cmpi ult, %v53, %v54 : i64 loc("std/text/str.lin":L:C)
    cf.cond_br %k1, ^t1, ^c1 loc("std/text/str.lin":L:C)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("std/text/str.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file1 : !llvm.ptr loc("std/text/str.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/text/str.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/text/str.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/text/str.lin":L:C)
    llvm.unreachable loc("std/text/str.lin":L:C)
  ^c1:
    %p56 = arith.constant 0 : i64 loc("std/text/str.lin":L:C)
    %v56 = arith.addi %v55, %p56 : i64 loc("std/text/str.lin":L:C)
    func.call @"lin.std.mem;Slice[UInt8].subspan"(%rs57, %v49, %v52, %v56) : (!llvm.ptr, !llvm.ptr, i64, i64) -> () loc("std/text/str.lin":L:C)
    func.call @"lin.std.option;Option[std.mem.Slice[UInt8]].unwrap"(%rs58, %rs57) : (!llvm.ptr, !llvm.ptr) -> () loc("std/text/str.lin":L:C)
    %cl59 = arith.constant 16 : i64 loc("std/text/str.lin":L:C)
    "llvm.intr.memcpy"(%v46, %rs58, %cl59) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/text/str.lin":L:C)
    cf.br ^b12 loc("std/text/str.lin":L:C)
  ^b12:
    %cl62 = arith.constant 24 : i64 loc("std/text/str.lin":L:C)
    "llvm.intr.memcpy"(%s4, %s6, %cl62) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/text/str.lin":L:C)
    cf.br ^b6 loc("std/text/str.lin":L:C)
  }
  func.func private @"lin.std.text;Str.length"(%a0: !llvm.ptr) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/text/str.lin":L:C)
    %v1 = arith.constant 0 : i64 loc("std/text/str.lin":L:C)
    %v3 = func.call @"lin.std.mem;Slice[UInt8].length"(%v0) : (!llvm.ptr) -> i64 loc("std/text/str.lin":L:C)
    func.return %v3 : i64 loc("std/text/str.lin":L:C)
  }
  func.func private @"lin.std.io.core;report[std.io.core.IoError]"(%a0: !llvm.ptr) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 16 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %ba1 = llvm.mlir.addressof @linea_str1 : !llvm.ptr loc("std/io/core/output.lin":L:C)
    %v1 = llvm.ptrtoint %ba1 : !llvm.ptr to i64 loc("std/io/core/output.lin":L:C)
    %v2 = arith.constant 0 : i64 loc("std/io/core/output.lin":L:C)
    llvm.store %v1, %s1 : i64, !llvm.ptr loc("std/io/core/output.lin":L:C)
    %v5 = arith.constant 7 : i64 loc("std/io/core/output.lin":L:C)
    %v6 = arith.constant 8 : i64 loc("std/io/core/output.lin":L:C)
    %v7 = llvm.getelementptr %s1[%v6] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/output.lin":L:C)
    llvm.store %v5, %v7 : i64, !llvm.ptr loc("std/io/core/output.lin":L:C)
    %v9 = func.call @"lin.std.io.core;eprint[std.text.Str]"(%s1) : (!llvm.ptr) -> i64 loc("std/io/core/output.lin":L:C)
    %v10 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/io/core/output.lin":L:C)
    %v11 = func.call @"lin.std.io.core;eprintln[std.io.core.IoError]"(%v10) : (!llvm.ptr) -> i64 loc("std/io/core/output.lin":L:C)
    %v12 = arith.constant 1 : i64 loc("std/io/core/output.lin":L:C)
    func.return %v12 : i64 loc("std/io/core/output.lin":L:C)
  }
  func.func private @"lin.std.text;starts_a_character"(%a0: !llvm.ptr, %a1: i64) -> i1 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 1 : i64
    %s3 = llvm.alloca %z3 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z4 = arith.constant 1 : i64
    %s4 = llvm.alloca %z4 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z5 = arith.constant 1 : i64
    %s5 = llvm.alloca %z5 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    llvm.store %a1, %s1 : i64, !llvm.ptr
    %rz13 = arith.constant 16 : i64
    %rs13 = llvm.alloca %rz13 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/text/str.lin":L:C)
    %v1 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/text/str.lin":L:C)
    %v2 = func.call @"lin.std.text;Str.length"(%v1) : (!llvm.ptr) -> i64 loc("std/text/str.lin":L:C)
    %v3 = arith.cmpi uge, %v0, %v2 : i64 loc("std/text/str.lin":L:C)
    cf.cond_br %v3, ^b1, ^b2 loc("std/text/str.lin":L:C)
  ^b1:
    %v5 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/text/str.lin":L:C)
    %v6 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/text/str.lin":L:C)
    %v7 = func.call @"lin.std.text;Str.length"(%v6) : (!llvm.ptr) -> i64 loc("std/text/str.lin":L:C)
    %v8 = arith.cmpi eq, %v5, %v7 : i64 loc("std/text/str.lin":L:C)
    %sw9 = arith.extui %v8 : i1 to i8 loc("std/text/str.lin":L:C)
    llvm.store %sw9, %s2 : i8, !llvm.ptr loc("std/text/str.lin":L:C)
    cf.br ^b3 loc("std/text/str.lin":L:C)
  ^b2:
    %v11 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/text/str.lin":L:C)
    %v12 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/text/str.lin":L:C)
    func.call @"lin.std.text;Str.byte"(%rs13, %v11, %v12) : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/text/str.lin":L:C)
    %v14 = llvm.load %rs13 : !llvm.ptr -> i64 loc("std/text/str.lin":L:C)
    %v15 = arith.constant 1 : i64 loc("std/text/str.lin":L:C)
    %v16 = arith.cmpi eq, %v14, %v15 : i64 loc("std/text/str.lin":L:C)
    cf.cond_br %v16, ^b5, ^b6 loc("std/text/str.lin":L:C)
  ^b3:
    %lw47 = llvm.load %s2 : !llvm.ptr -> i8 loc("std/text/str.lin":L:C)
    %lz47 = arith.constant 0 : i8 loc("std/text/str.lin":L:C)
    %v47 = arith.cmpi ne, %lw47, %lz47 : i8 loc("std/text/str.lin":L:C)
    func.return %v47 : i1 loc("std/text/str.lin":L:C)
  ^b4:
    %lw44 = llvm.load %s3 : !llvm.ptr -> i8 loc("std/text/str.lin":L:C)
    %lz44 = arith.constant 0 : i8 loc("std/text/str.lin":L:C)
    %v44 = arith.cmpi ne, %lw44, %lz44 : i8 loc("std/text/str.lin":L:C)
    %sw45 = arith.extui %v44 : i1 to i8 loc("std/text/str.lin":L:C)
    llvm.store %sw45, %s2 : i8, !llvm.ptr loc("std/text/str.lin":L:C)
    cf.br ^b3 loc("std/text/str.lin":L:C)
  ^b5:
    %v18 = arith.constant 8 : i64 loc("std/text/str.lin":L:C)
    %v19 = llvm.getelementptr %rs13[%v18] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/text/str.lin":L:C)
    %iw20 = llvm.load %v19 : !llvm.ptr -> i8 loc("std/text/str.lin":L:C)
    %v20 = arith.extui %iw20 : i8 to i64 loc("std/text/str.lin":L:C)
    %sw21 = arith.trunci %v20 : i64 to i8 loc("std/text/str.lin":L:C)
    llvm.store %sw21, %s4 : i8, !llvm.ptr loc("std/text/str.lin":L:C)
    %lw22 = llvm.load %s4 : !llvm.ptr -> i8 loc("std/text/str.lin":L:C)
    %v22 = arith.extui %lw22 : i8 to i64 loc("std/text/str.lin":L:C)
    %v23 = arith.constant 128 : i64 loc("std/text/str.lin":L:C)
    %v24 = arith.cmpi ult, %v22, %v23 : i64 loc("std/text/str.lin":L:C)
    cf.cond_br %v24, ^b7, ^b8 loc("std/text/str.lin":L:C)
  ^b6:
    %v37 = arith.constant 0 : i64 loc("std/text/str.lin":L:C)
    %v38 = arith.cmpi eq, %v14, %v37 : i64 loc("std/text/str.lin":L:C)
    cf.cond_br %v38, ^b10, ^b11 loc("std/text/str.lin":L:C)
  ^b7:
    %v26 = arith.constant 1 : i1 loc("std/text/str.lin":L:C)
    %sw27 = arith.extui %v26 : i1 to i8 loc("std/text/str.lin":L:C)
    llvm.store %sw27, %s5 : i8, !llvm.ptr loc("std/text/str.lin":L:C)
    cf.br ^b9 loc("std/text/str.lin":L:C)
  ^b8:
    %lw29 = llvm.load %s4 : !llvm.ptr -> i8 loc("std/text/str.lin":L:C)
    %v29 = arith.extui %lw29 : i8 to i64 loc("std/text/str.lin":L:C)
    %v30 = arith.constant 191 : i64 loc("std/text/str.lin":L:C)
    %v31 = arith.cmpi ugt, %v29, %v30 : i64 loc("std/text/str.lin":L:C)
    %sw32 = arith.extui %v31 : i1 to i8 loc("std/text/str.lin":L:C)
    llvm.store %sw32, %s5 : i8, !llvm.ptr loc("std/text/str.lin":L:C)
    cf.br ^b9 loc("std/text/str.lin":L:C)
  ^b9:
    %lw34 = llvm.load %s5 : !llvm.ptr -> i8 loc("std/text/str.lin":L:C)
    %lz34 = arith.constant 0 : i8 loc("std/text/str.lin":L:C)
    %v34 = arith.cmpi ne, %lw34, %lz34 : i8 loc("std/text/str.lin":L:C)
    %sw35 = arith.extui %v34 : i1 to i8 loc("std/text/str.lin":L:C)
    llvm.store %sw35, %s3 : i8, !llvm.ptr loc("std/text/str.lin":L:C)
    cf.br ^b4 loc("std/text/str.lin":L:C)
  ^b10:
    %v40 = arith.constant 0 : i1 loc("std/text/str.lin":L:C)
    %sw41 = arith.extui %v40 : i1 to i8 loc("std/text/str.lin":L:C)
    llvm.store %sw41, %s3 : i8, !llvm.ptr loc("std/text/str.lin":L:C)
    cf.br ^b4 loc("std/text/str.lin":L:C)
  ^b11:
    %tk1 = arith.constant 3 : i32 loc("std/text/str.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file1 : !llvm.ptr loc("std/text/str.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/text/str.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/text/str.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/text/str.lin":L:C)
    llvm.unreachable loc("std/text/str.lin":L:C)
  }
  func.func private @"lin.std.mem;Slice[UInt8].subspan"(%sret: !llvm.ptr, %a0: !llvm.ptr, %a1: i64, %a2: i64) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 24 : i64
    %s3 = llvm.alloca %z3 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z4 = arith.constant 24 : i64
    %s4 = llvm.alloca %z4 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z5 = arith.constant 16 : i64
    %s5 = llvm.alloca %z5 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    llvm.store %a1, %s1 : i64, !llvm.ptr
    llvm.store %a2, %s2 : i64, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/mem/slice.lin":L:C)
    %v1 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/mem/slice.lin":L:C)
    %v2 = arith.constant 8 : i64 loc("std/mem/slice.lin":L:C)
    %v3 = llvm.getelementptr %v1[%v2] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/mem/slice.lin":L:C)
    %v4 = llvm.load %v3 : !llvm.ptr -> i64 loc("std/mem/slice.lin":L:C)
    %v5 = arith.cmpi ugt, %v0, %v4 : i64 loc("std/mem/slice.lin":L:C)
    cf.cond_br %v5, ^b1, ^b2 loc("std/mem/slice.lin":L:C)
  ^b1:
    %v8 = arith.constant 0 : i64 loc("std/mem/slice.lin":L:C)
    llvm.store %v8, %s3 : i64, !llvm.ptr loc("std/mem/slice.lin":L:C)
    cf.br ^b3 loc("std/mem/slice.lin":L:C)
  ^b2:
    %v12 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/mem/slice.lin":L:C)
    %v13 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/mem/slice.lin":L:C)
    %v14 = arith.constant 8 : i64 loc("std/mem/slice.lin":L:C)
    %v15 = llvm.getelementptr %v13[%v14] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/mem/slice.lin":L:C)
    %v16 = llvm.load %v15 : !llvm.ptr -> i64 loc("std/mem/slice.lin":L:C)
    %v17 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/mem/slice.lin":L:C)
    %v18 = arith.subi %v16, %v17 : i64 loc("std/mem/slice.lin":L:C)
    %k1 = arith.cmpi ult, %v16, %v17 : i64 loc("std/mem/slice.lin":L:C)
    cf.cond_br %k1, ^t1, ^c1 loc("std/mem/slice.lin":L:C)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("std/mem/slice.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file3 : !llvm.ptr loc("std/mem/slice.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/mem/slice.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/mem/slice.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/mem/slice.lin":L:C)
    llvm.unreachable loc("std/mem/slice.lin":L:C)
  ^c1:
    %p19 = arith.constant 0 : i64 loc("std/mem/slice.lin":L:C)
    %v19 = arith.addi %v18, %p19 : i64 loc("std/mem/slice.lin":L:C)
    %v20 = arith.cmpi ugt, %v12, %v19 : i64 loc("std/mem/slice.lin":L:C)
    cf.cond_br %v20, ^b4, ^b5 loc("std/mem/slice.lin":L:C)
  ^b3:
    %rl63 = arith.constant 24 : i64 loc("std/mem/slice.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s3, %rl63) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/mem/slice.lin":L:C)
    func.return loc("std/mem/slice.lin":L:C)
  ^b4:
    %v23 = arith.constant 0 : i64 loc("std/mem/slice.lin":L:C)
    llvm.store %v23, %s4 : i64, !llvm.ptr loc("std/mem/slice.lin":L:C)
    cf.br ^b6 loc("std/mem/slice.lin":L:C)
  ^b5:
    %v27 = arith.constant 1 : i64 loc("std/mem/slice.lin":L:C)
    llvm.store %v27, %s4 : i64, !llvm.ptr loc("std/mem/slice.lin":L:C)
    %v29 = arith.constant 8 : i64 loc("std/mem/slice.lin":L:C)
    %v30 = llvm.getelementptr %s4[%v29] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/mem/slice.lin":L:C)
    %v31 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/mem/slice.lin":L:C)
    %v32 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/mem/slice.lin":L:C)
    %v33 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/mem/slice.lin":L:C)
    %v34 = arith.constant 1 : i64 loc("std/mem/slice.lin":L:C)
    %v35 = arith.constant 0 : i64 loc("std/mem/slice.lin":L:C)
    %v37 = llvm.load %v31 : !llvm.ptr -> i64 loc("std/mem/slice.lin":L:C)
    %v38 = arith.constant 8 : i64 loc("std/mem/slice.lin":L:C)
    %v39 = llvm.getelementptr %v31[%v38] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/mem/slice.lin":L:C)
    %v40 = llvm.load %v39 : !llvm.ptr -> i64 loc("std/mem/slice.lin":L:C)
    %v41 = arith.cmpi ule, %v32, %v40 : i64 loc("std/mem/slice.lin":L:C)
    %k2z = arith.constant true loc("std/mem/slice.lin":L:C)
    %k2 = arith.xori %v41, %k2z : i1 loc("std/mem/slice.lin":L:C)
    cf.cond_br %k2, ^t2, ^c2 loc("std/mem/slice.lin":L:C)
  ^t2:
    %tk2 = arith.constant 6 : i32 loc("std/mem/slice.lin":L:C)
    %tf2 = llvm.mlir.addressof @linea_file3 : !llvm.ptr loc("std/mem/slice.lin":L:C)
    %tl2 = arith.constant L : i32 loc("std/mem/slice.lin":L:C)
    %tc2 = arith.constant C : i32 loc("std/mem/slice.lin":L:C)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("std/mem/slice.lin":L:C)
    llvm.unreachable loc("std/mem/slice.lin":L:C)
  ^c2:
    %v42 = arith.ori %v41, %v41 : i1 loc("std/mem/slice.lin":L:C)
    %v43 = arith.subi %v40, %v32 : i64 loc("std/mem/slice.lin":L:C)
    %v44 = arith.cmpi ule, %v33, %v43 : i64 loc("std/mem/slice.lin":L:C)
    %k3z = arith.constant true loc("std/mem/slice.lin":L:C)
    %k3 = arith.xori %v44, %k3z : i1 loc("std/mem/slice.lin":L:C)
    cf.cond_br %k3, ^t3, ^c3 loc("std/mem/slice.lin":L:C)
  ^t3:
    %tk3 = arith.constant 6 : i32 loc("std/mem/slice.lin":L:C)
    %tf3 = llvm.mlir.addressof @linea_file3 : !llvm.ptr loc("std/mem/slice.lin":L:C)
    %tl3 = arith.constant L : i32 loc("std/mem/slice.lin":L:C)
    %tc3 = arith.constant C : i32 loc("std/mem/slice.lin":L:C)
    func.call @linea_trap(%tk3, %tf3, %tl3, %tc3) : (i32, !llvm.ptr, i32, i32) -> () loc("std/mem/slice.lin":L:C)
    llvm.unreachable loc("std/mem/slice.lin":L:C)
  ^c3:
    %v45 = arith.ori %v44, %v44 : i1 loc("std/mem/slice.lin":L:C)
    %m46 = "llvm.intr.umul.with.overflow"(%v32, %v34) : (i64, i64) -> !llvm.struct<(i64, i1)> loc("std/mem/slice.lin":L:C)
    %v46 = llvm.extractvalue %m46[0] : !llvm.struct<(i64, i1)> loc("std/mem/slice.lin":L:C)
    %k4 = llvm.extractvalue %m46[1] : !llvm.struct<(i64, i1)> loc("std/mem/slice.lin":L:C)
    cf.cond_br %k4, ^t4, ^c4 loc("std/mem/slice.lin":L:C)
  ^t4:
    %tk4 = arith.constant 0 : i32 loc("std/mem/slice.lin":L:C)
    %tf4 = llvm.mlir.addressof @linea_file3 : !llvm.ptr loc("std/mem/slice.lin":L:C)
    %tl4 = arith.constant L : i32 loc("std/mem/slice.lin":L:C)
    %tc4 = arith.constant C : i32 loc("std/mem/slice.lin":L:C)
    func.call @linea_trap(%tk4, %tf4, %tl4, %tc4) : (i32, !llvm.ptr, i32, i32) -> () loc("std/mem/slice.lin":L:C)
    llvm.unreachable loc("std/mem/slice.lin":L:C)
  ^c4:
    %p47 = arith.constant 0 : i64 loc("std/mem/slice.lin":L:C)
    %v47 = arith.addi %v46, %p47 : i64 loc("std/mem/slice.lin":L:C)
    %v48 = arith.addi %v37, %v46 : i64 loc("std/mem/slice.lin":L:C)
    %k5 = arith.cmpi ult, %v48, %v37 : i64 loc("std/mem/slice.lin":L:C)
    cf.cond_br %k5, ^t5, ^c5 loc("std/mem/slice.lin":L:C)
  ^t5:
    %tk5 = arith.constant 0 : i32 loc("std/mem/slice.lin":L:C)
    %tf5 = llvm.mlir.addressof @linea_file3 : !llvm.ptr loc("std/mem/slice.lin":L:C)
    %tl5 = arith.constant L : i32 loc("std/mem/slice.lin":L:C)
    %tc5 = arith.constant C : i32 loc("std/mem/slice.lin":L:C)
    func.call @linea_trap(%tk5, %tf5, %tl5, %tc5) : (i32, !llvm.ptr, i32, i32) -> () loc("std/mem/slice.lin":L:C)
    llvm.unreachable loc("std/mem/slice.lin":L:C)
  ^c5:
    %p49 = arith.constant 0 : i64 loc("std/mem/slice.lin":L:C)
    %v49 = arith.addi %v48, %p49 : i64 loc("std/mem/slice.lin":L:C)
    %v51 = arith.constant 0 : i64 loc("std/mem/slice.lin":L:C)
    llvm.store %v48, %s5 : i64, !llvm.ptr loc("std/mem/slice.lin":L:C)
    %v54 = arith.constant 8 : i64 loc("std/mem/slice.lin":L:C)
    %v55 = llvm.getelementptr %s5[%v54] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/mem/slice.lin":L:C)
    llvm.store %v33, %v55 : i64, !llvm.ptr loc("std/mem/slice.lin":L:C)
    %cl57 = arith.constant 16 : i64 loc("std/mem/slice.lin":L:C)
    "llvm.intr.memcpy"(%v30, %s5, %cl57) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/mem/slice.lin":L:C)
    cf.br ^b6 loc("std/mem/slice.lin":L:C)
  ^b6:
    %cl60 = arith.constant 24 : i64 loc("std/mem/slice.lin":L:C)
    "llvm.intr.memcpy"(%s3, %s4, %cl60) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/mem/slice.lin":L:C)
    cf.br ^b3 loc("std/mem/slice.lin":L:C)
  }
  func.func private @"lin.std.option;Option[std.mem.Slice[UInt8]].unwrap"(%sret: !llvm.ptr, %a0: !llvm.ptr) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 24 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 16 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 16 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 16 : i64
    %s3 = llvm.alloca %z3 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %pl0 = arith.constant 24 : i64
    "llvm.intr.memcpy"(%s0, %a0, %pl0) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> ()
    cf.br ^b0
  ^b0:
    %v1 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/option/option.lin":L:C)
    %v2 = arith.constant 1 : i64 loc("std/option/option.lin":L:C)
    %v3 = arith.cmpi eq, %v1, %v2 : i64 loc("std/option/option.lin":L:C)
    cf.cond_br %v3, ^b2, ^b3 loc("std/option/option.lin":L:C)
  ^b1:
    %rl30 = arith.constant 16 : i64 loc("std/option/option.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s1, %rl30) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/option/option.lin":L:C)
    func.return loc("std/option/option.lin":L:C)
  ^b2:
    %v5 = arith.constant 8 : i64 loc("std/option/option.lin":L:C)
    %v6 = llvm.getelementptr %s0[%v5] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/option/option.lin":L:C)
    %cl8 = arith.constant 16 : i64 loc("std/option/option.lin":L:C)
    "llvm.intr.memcpy"(%s2, %v6, %cl8) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/option/option.lin":L:C)
    %cl11 = arith.constant 16 : i64 loc("std/option/option.lin":L:C)
    "llvm.intr.memcpy"(%s1, %s2, %cl11) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/option/option.lin":L:C)
    cf.br ^b1 loc("std/option/option.lin":L:C)
  ^b3:
    %v13 = arith.constant 0 : i64 loc("std/option/option.lin":L:C)
    %v14 = arith.cmpi eq, %v1, %v13 : i64 loc("std/option/option.lin":L:C)
    cf.cond_br %v14, ^b4, ^b5 loc("std/option/option.lin":L:C)
  ^b4:
    %ba17 = llvm.mlir.addressof @linea_str2 : !llvm.ptr loc("std/option/option.lin":L:C)
    %v17 = llvm.ptrtoint %ba17 : !llvm.ptr to i64 loc("std/option/option.lin":L:C)
    %v18 = arith.constant 0 : i64 loc("std/option/option.lin":L:C)
    llvm.store %v17, %s3 : i64, !llvm.ptr loc("std/option/option.lin":L:C)
    %v21 = arith.constant 28 : i64 loc("std/option/option.lin":L:C)
    %v22 = arith.constant 8 : i64 loc("std/option/option.lin":L:C)
    %v23 = llvm.getelementptr %s3[%v22] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/option/option.lin":L:C)
    llvm.store %v21, %v23 : i64, !llvm.ptr loc("std/option/option.lin":L:C)
    %poa1 = arith.constant 0 : i64 loc("std/option/option.lin":L:C)
    %ppa1 = llvm.getelementptr %s3[%poa1] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/option/option.lin":L:C)
    %pva1 = llvm.load %ppa1 : !llvm.ptr -> i64 loc("std/option/option.lin":L:C)
    %pol1 = arith.constant 8 : i64 loc("std/option/option.lin":L:C)
    %ppl1 = llvm.getelementptr %s3[%pol1] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/option/option.lin":L:C)
    %pvl1 = llvm.load %ppl1 : !llvm.ptr -> i64 loc("std/option/option.lin":L:C)
    %pf1 = llvm.mlir.addressof @linea_file4 : !llvm.ptr loc("std/option/option.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/option/option.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/option/option.lin":L:C)
    func.call @linea_panic(%pva1, %pvl1, %pf1, %tl1, %tc1) : (i64, i64, !llvm.ptr, i32, i32) -> () loc("std/option/option.lin":L:C)
    llvm.unreachable loc("std/option/option.lin":L:C)
  ^b5:
    %tk2 = arith.constant 3 : i32 loc("std/option/option.lin":L:C)
    %tf2 = llvm.mlir.addressof @linea_file4 : !llvm.ptr loc("std/option/option.lin":L:C)
    %tl2 = arith.constant L : i32 loc("std/option/option.lin":L:C)
    %tc2 = arith.constant C : i32 loc("std/option/option.lin":L:C)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("std/option/option.lin":L:C)
    llvm.unreachable loc("std/option/option.lin":L:C)
  }
  func.func private @"lin.std.mem;Slice[UInt8].length"(%a0: !llvm.ptr) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/mem/slice.lin":L:C)
    %v1 = arith.constant 8 : i64 loc("std/mem/slice.lin":L:C)
    %v2 = llvm.getelementptr %v0[%v1] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/mem/slice.lin":L:C)
    %v3 = llvm.load %v2 : !llvm.ptr -> i64 loc("std/mem/slice.lin":L:C)
    func.return %v3 : i64 loc("std/mem/slice.lin":L:C)
  }
  func.func private @"lin.std.io.core;eprint[std.text.Str]"(%a0: !llvm.ptr) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i32 {alignment = 4 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = func.call @"lin.std.io.core;stderr"() : () -> i64 loc("std/io/core/output.lin":L:C)
    %sw1 = arith.trunci %v0 : i64 to i32 loc("std/io/core/output.lin":L:C)
    llvm.store %sw1, %s1 : i32, !llvm.ptr loc("std/io/core/output.lin":L:C)
    %v2 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/io/core/output.lin":L:C)
    %v4 = func.call @"lin.std.io.core;eprint_to[std.text.Str,std.io.core.Descriptor]"(%v2, %s1) : (!llvm.ptr, !llvm.ptr) -> i64 loc("std/io/core/output.lin":L:C)
    func.return %v4 : i64 loc("std/io/core/output.lin":L:C)
  }
  func.func private @"lin.std.io.core;eprintln[std.io.core.IoError]"(%a0: !llvm.ptr) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i32 {alignment = 4 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = func.call @"lin.std.io.core;stderr"() : () -> i64 loc("std/io/core/output.lin":L:C)
    %sw1 = arith.trunci %v0 : i64 to i32 loc("std/io/core/output.lin":L:C)
    llvm.store %sw1, %s1 : i32, !llvm.ptr loc("std/io/core/output.lin":L:C)
    %v2 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/io/core/output.lin":L:C)
    %v4 = func.call @"lin.std.io.core;eprintln_to[std.io.core.IoError,std.io.core.Descriptor]"(%v2, %s1) : (!llvm.ptr, !llvm.ptr) -> i64 loc("std/io/core/output.lin":L:C)
    func.return %v4 : i64 loc("std/io/core/output.lin":L:C)
  }
  func.func private @"lin.std.text;Str.byte"(%sret: !llvm.ptr, %a0: !llvm.ptr, %a1: i64) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 16 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    llvm.store %a1, %s1 : i64, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/text/str.lin":L:C)
    %v1 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/text/str.lin":L:C)
    %v2 = func.call @"lin.std.text;Str.length"(%v1) : (!llvm.ptr) -> i64 loc("std/text/str.lin":L:C)
    %v3 = arith.cmpi uge, %v0, %v2 : i64 loc("std/text/str.lin":L:C)
    cf.cond_br %v3, ^b1, ^b2 loc("std/text/str.lin":L:C)
  ^b1:
    %v6 = arith.constant 0 : i64 loc("std/text/str.lin":L:C)
    llvm.store %v6, %s2 : i64, !llvm.ptr loc("std/text/str.lin":L:C)
    cf.br ^b3 loc("std/text/str.lin":L:C)
  ^b2:
    %v10 = arith.constant 1 : i64 loc("std/text/str.lin":L:C)
    llvm.store %v10, %s2 : i64, !llvm.ptr loc("std/text/str.lin":L:C)
    %v12 = arith.constant 8 : i64 loc("std/text/str.lin":L:C)
    %v13 = llvm.getelementptr %s2[%v12] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/text/str.lin":L:C)
    %v14 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/text/str.lin":L:C)
    %v15 = arith.constant 0 : i64 loc("std/text/str.lin":L:C)
    %v17 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/text/str.lin":L:C)
    %v18 = arith.constant 1 : i64 loc("std/text/str.lin":L:C)
    %v19 = arith.constant 0 : i64 loc("std/text/str.lin":L:C)
    %v21 = llvm.load %v14 : !llvm.ptr -> i64 loc("std/text/str.lin":L:C)
    %v22 = arith.constant 8 : i64 loc("std/text/str.lin":L:C)
    %v23 = llvm.getelementptr %v14[%v22] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/text/str.lin":L:C)
    %v24 = llvm.load %v23 : !llvm.ptr -> i64 loc("std/text/str.lin":L:C)
    %v25 = arith.cmpi ult, %v17, %v24 : i64 loc("std/text/str.lin":L:C)
    %k1z = arith.constant true loc("std/text/str.lin":L:C)
    %k1 = arith.xori %v25, %k1z : i1 loc("std/text/str.lin":L:C)
    cf.cond_br %k1, ^t1, ^c1 loc("std/text/str.lin":L:C)
  ^t1:
    %tk1 = arith.constant 6 : i32 loc("std/text/str.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file1 : !llvm.ptr loc("std/text/str.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/text/str.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/text/str.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/text/str.lin":L:C)
    llvm.unreachable loc("std/text/str.lin":L:C)
  ^c1:
    %v26 = arith.ori %v25, %v25 : i1 loc("std/text/str.lin":L:C)
    %m27 = "llvm.intr.umul.with.overflow"(%v24, %v18) : (i64, i64) -> !llvm.struct<(i64, i1)> loc("std/text/str.lin":L:C)
    %v27 = llvm.extractvalue %m27[0] : !llvm.struct<(i64, i1)> loc("std/text/str.lin":L:C)
    %k2 = llvm.extractvalue %m27[1] : !llvm.struct<(i64, i1)> loc("std/text/str.lin":L:C)
    cf.cond_br %k2, ^t2, ^c2 loc("std/text/str.lin":L:C)
  ^t2:
    %tk2 = arith.constant 0 : i32 loc("std/text/str.lin":L:C)
    %tf2 = llvm.mlir.addressof @linea_file1 : !llvm.ptr loc("std/text/str.lin":L:C)
    %tl2 = arith.constant L : i32 loc("std/text/str.lin":L:C)
    %tc2 = arith.constant C : i32 loc("std/text/str.lin":L:C)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("std/text/str.lin":L:C)
    llvm.unreachable loc("std/text/str.lin":L:C)
  ^c2:
    %p28 = arith.constant 0 : i64 loc("std/text/str.lin":L:C)
    %v28 = arith.addi %v27, %p28 : i64 loc("std/text/str.lin":L:C)
    %m29 = "llvm.intr.umul.with.overflow"(%v17, %v18) : (i64, i64) -> !llvm.struct<(i64, i1)> loc("std/text/str.lin":L:C)
    %v29 = llvm.extractvalue %m29[0] : !llvm.struct<(i64, i1)> loc("std/text/str.lin":L:C)
    %k3 = llvm.extractvalue %m29[1] : !llvm.struct<(i64, i1)> loc("std/text/str.lin":L:C)
    cf.cond_br %k3, ^t3, ^c3 loc("std/text/str.lin":L:C)
  ^t3:
    %tk3 = arith.constant 0 : i32 loc("std/text/str.lin":L:C)
    %tf3 = llvm.mlir.addressof @linea_file1 : !llvm.ptr loc("std/text/str.lin":L:C)
    %tl3 = arith.constant L : i32 loc("std/text/str.lin":L:C)
    %tc3 = arith.constant C : i32 loc("std/text/str.lin":L:C)
    func.call @linea_trap(%tk3, %tf3, %tl3, %tc3) : (i32, !llvm.ptr, i32, i32) -> () loc("std/text/str.lin":L:C)
    llvm.unreachable loc("std/text/str.lin":L:C)
  ^c3:
    %p30 = arith.constant 0 : i64 loc("std/text/str.lin":L:C)
    %v30 = arith.addi %v29, %p30 : i64 loc("std/text/str.lin":L:C)
    %v31 = arith.constant 1 : i64 loc("std/text/str.lin":L:C)
    %v32 = arith.addi %v29, %v31 : i64 loc("std/text/str.lin":L:C)
    %k4 = arith.cmpi ult, %v32, %v29 : i64 loc("std/text/str.lin":L:C)
    cf.cond_br %k4, ^t4, ^c4 loc("std/text/str.lin":L:C)
  ^t4:
    %tk4 = arith.constant 0 : i32 loc("std/text/str.lin":L:C)
    %tf4 = llvm.mlir.addressof @linea_file1 : !llvm.ptr loc("std/text/str.lin":L:C)
    %tl4 = arith.constant L : i32 loc("std/text/str.lin":L:C)
    %tc4 = arith.constant C : i32 loc("std/text/str.lin":L:C)
    func.call @linea_trap(%tk4, %tf4, %tl4, %tc4) : (i32, !llvm.ptr, i32, i32) -> () loc("std/text/str.lin":L:C)
    llvm.unreachable loc("std/text/str.lin":L:C)
  ^c4:
    %p33 = arith.constant 0 : i64 loc("std/text/str.lin":L:C)
    %v33 = arith.addi %v32, %p33 : i64 loc("std/text/str.lin":L:C)
    %v34 = arith.cmpi ule, %v32, %v27 : i64 loc("std/text/str.lin":L:C)
    %k5z = arith.constant true loc("std/text/str.lin":L:C)
    %k5 = arith.xori %v34, %k5z : i1 loc("std/text/str.lin":L:C)
    cf.cond_br %k5, ^t5, ^c5 loc("std/text/str.lin":L:C)
  ^t5:
    %tk5 = arith.constant 6 : i32 loc("std/text/str.lin":L:C)
    %tf5 = llvm.mlir.addressof @linea_file1 : !llvm.ptr loc("std/text/str.lin":L:C)
    %tl5 = arith.constant L : i32 loc("std/text/str.lin":L:C)
    %tc5 = arith.constant C : i32 loc("std/text/str.lin":L:C)
    func.call @linea_trap(%tk5, %tf5, %tl5, %tc5) : (i32, !llvm.ptr, i32, i32) -> () loc("std/text/str.lin":L:C)
    llvm.unreachable loc("std/text/str.lin":L:C)
  ^c5:
    %v35 = arith.ori %v34, %v34 : i1 loc("std/text/str.lin":L:C)
    %v36 = arith.addi %v21, %v29 : i64 loc("std/text/str.lin":L:C)
    %v37 = llvm.inttoptr %v36 : i64 to !llvm.ptr loc("std/text/str.lin":L:C)
    %iw38 = llvm.load %v37 : !llvm.ptr -> i8 loc("std/text/str.lin":L:C)
    %v38 = arith.extui %iw38 : i8 to i64 loc("std/text/str.lin":L:C)
    %iw39 = arith.trunci %v38 : i64 to i8 loc("std/text/str.lin":L:C)
    llvm.store %iw39, %v13 : i8, !llvm.ptr loc("std/text/str.lin":L:C)
    cf.br ^b3 loc("std/text/str.lin":L:C)
  ^b3:
    %rl42 = arith.constant 16 : i64 loc("std/text/str.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s2, %rl42) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/text/str.lin":L:C)
    func.return loc("std/text/str.lin":L:C)
  }
  func.func private @"lin.std.io.core;stderr"() -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 2 : i64 loc("std/io/core/descriptor.lin":L:C)
    %v1 = func.call @"lin.std.io.core;descriptor"(%v0) : (i64) -> i64 loc("std/io/core/descriptor.lin":L:C)
    func.return %v1 : i64 loc("std/io/core/descriptor.lin":L:C)
  }
  func.func private @"lin.std.io.core;eprint_to[std.text.Str,std.io.core.Descriptor]"(%a0: !llvm.ptr, %a1: !llvm.ptr) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    llvm.store %a1, %s1 : !llvm.ptr, !llvm.ptr
    %rz2 = arith.constant 48 : i64
    %rs2 = llvm.alloca %rz2 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/io/core/output.lin":L:C)
    %v1 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/output.lin":L:C)
    func.call @"lin.std.text.Str;std.fmt;Display.fmt[std.io.core.Descriptor]"(%rs2, %v0, %v1) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/output.lin":L:C)
    cf.br ^b2 loc("std/io/core/output.lin":L:C)
  ^b1:
    %v7 = arith.constant 0 : i64 loc("std/io/core/output.lin":L:C)
    func.return %v7 : i64 loc("std/io/core/output.lin":L:C)
  ^b2:
    %v4 = arith.constant 0 : i64 loc("std/io/core/output.lin":L:C)
    cf.br ^b1 loc("std/io/core/output.lin":L:C)
  }
  func.func private @"lin.std.io.core;eprintln_to[std.io.core.IoError,std.io.core.Descriptor]"(%a0: !llvm.ptr, %a1: !llvm.ptr) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    llvm.store %a1, %s1 : !llvm.ptr, !llvm.ptr
    %rz2 = arith.constant 48 : i64
    %rs2 = llvm.alloca %rz2 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/io/core/output.lin":L:C)
    %v1 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/output.lin":L:C)
    func.call @"lin.std.io.core;line[std.io.core.IoError,std.io.core.Descriptor]"(%rs2, %v0, %v1) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/output.lin":L:C)
    cf.br ^b2 loc("std/io/core/output.lin":L:C)
  ^b1:
    %v7 = arith.constant 0 : i64 loc("std/io/core/output.lin":L:C)
    func.return %v7 : i64 loc("std/io/core/output.lin":L:C)
  ^b2:
    %v4 = arith.constant 0 : i64 loc("std/io/core/output.lin":L:C)
    cf.br ^b1 loc("std/io/core/output.lin":L:C)
  }
  func.func private @"lin.std.io.core;descriptor"(%a0: i64) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i32 {alignment = 4 : i64} : (i64) -> !llvm.ptr
    %pw0 = arith.trunci %a0 : i64 to i32
    llvm.store %pw0, %s0 : i32, !llvm.ptr
    cf.br ^b0
  ^b0:
    %lw0 = llvm.load %s0 : !llvm.ptr -> i32 loc("std/io/core/descriptor.lin":L:C)
    %v0 = arith.extsi %lw0 : i32 to i64 loc("std/io/core/descriptor.lin":L:C)
    func.return %v0 : i64 loc("std/io/core/descriptor.lin":L:C)
  }
  func.func private @"lin.std.text.Str;std.fmt;Display.fmt[std.io.core.Descriptor]"(%sret: !llvm.ptr, %a0: !llvm.ptr, %a1: !llvm.ptr) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    llvm.store %a1, %s1 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/fmt/render.lin":L:C)
    %v1 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/fmt/render.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%sret, %v0, %v1) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/fmt/render.lin":L:C)
    func.return loc("std/fmt/render.lin":L:C)
  }
  func.func private @"lin.std.io.core;line[std.io.core.IoError,std.io.core.Descriptor]"(%sret: !llvm.ptr, %a0: !llvm.ptr, %a1: !llvm.ptr) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 48 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 16 : i64
    %s3 = llvm.alloca %z3 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    llvm.store %a1, %s1 : !llvm.ptr, !llvm.ptr
    %rz2 = arith.constant 48 : i64
    %rs2 = llvm.alloca %rz2 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/io/core/output.lin":L:C)
    %v1 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/output.lin":L:C)
    func.call @"lin.std.io.core.IoError;std.fmt;Display.fmt[std.io.core.Descriptor]"(%rs2, %v0, %v1) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/output.lin":L:C)
    %v3 = llvm.load %rs2 : !llvm.ptr -> i64 loc("std/io/core/output.lin":L:C)
    %v4 = arith.constant 0 : i64 loc("std/io/core/output.lin":L:C)
    %v5 = arith.cmpi eq, %v3, %v4 : i64 loc("std/io/core/output.lin":L:C)
    cf.cond_br %v5, ^b1, ^b2 loc("std/io/core/output.lin":L:C)
  ^b1:
    %v16 = arith.constant 8 : i64 loc("std/io/core/output.lin":L:C)
    %v17 = llvm.getelementptr %rs2[%v16] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/output.lin":L:C)
    %v18 = arith.constant 0 : i64 loc("std/io/core/output.lin":L:C)
    %v19 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/output.lin":L:C)
    %ba21 = llvm.mlir.addressof @linea_str3 : !llvm.ptr loc("std/io/core/output.lin":L:C)
    %v21 = llvm.ptrtoint %ba21 : !llvm.ptr to i64 loc("std/io/core/output.lin":L:C)
    %v22 = arith.constant 0 : i64 loc("std/io/core/output.lin":L:C)
    llvm.store %v21, %s3 : i64, !llvm.ptr loc("std/io/core/output.lin":L:C)
    %v25 = arith.constant 1 : i64 loc("std/io/core/output.lin":L:C)
    %v26 = arith.constant 8 : i64 loc("std/io/core/output.lin":L:C)
    %v27 = llvm.getelementptr %s3[%v26] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/output.lin":L:C)
    llvm.store %v25, %v27 : i64, !llvm.ptr loc("std/io/core/output.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%sret, %v19, %s3) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/output.lin":L:C)
    func.return loc("std/io/core/output.lin":L:C)
  ^b2:
    %v7 = arith.constant 8 : i64 loc("std/io/core/output.lin":L:C)
    %v8 = llvm.getelementptr %rs2[%v7] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/output.lin":L:C)
    %v9 = arith.constant 1 : i64 loc("std/io/core/output.lin":L:C)
    llvm.store %v9, %s2 : i64, !llvm.ptr loc("std/io/core/output.lin":L:C)
    %v12 = arith.constant 8 : i64 loc("std/io/core/output.lin":L:C)
    %v13 = llvm.getelementptr %s2[%v12] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/output.lin":L:C)
    %cl14 = arith.constant 40 : i64 loc("std/io/core/output.lin":L:C)
    "llvm.intr.memcpy"(%v13, %v8, %cl14) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/output.lin":L:C)
    %rl15 = arith.constant 48 : i64 loc("std/io/core/output.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s2, %rl15) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/output.lin":L:C)
    func.return loc("std/io/core/output.lin":L:C)
  }
  func.func private @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%sret: !llvm.ptr, %a0: !llvm.ptr, %a1: !llvm.ptr) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 48 : i64
    %s3 = llvm.alloca %z3 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z4 = arith.constant 48 : i64
    %s4 = llvm.alloca %z4 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    llvm.store %a1, %s1 : !llvm.ptr, !llvm.ptr
    %rz2 = arith.constant 16 : i64
    %rs2 = llvm.alloca %rz2 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz3 = arith.constant 72 : i64
    %rs3 = llvm.alloca %rz3 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz10 = arith.constant 40 : i64
    %rs10 = llvm.alloca %rz10 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/io/core/descriptor.lin":L:C)
    %v1 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/descriptor.lin":L:C)
    func.call @"lin.std.text;Str.as_bytes"(%rs2, %v1) : (!llvm.ptr, !llvm.ptr) -> () loc("std/io/core/descriptor.lin":L:C)
    func.call @"lin.std.io.core;write_all[std.io.core.Descriptor]"(%rs3, %v0, %rs2) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/descriptor.lin":L:C)
    %v4 = llvm.load %rs3 : !llvm.ptr -> i64 loc("std/io/core/descriptor.lin":L:C)
    %v5 = arith.constant 0 : i64 loc("std/io/core/descriptor.lin":L:C)
    %v6 = arith.cmpi eq, %v4, %v5 : i64 loc("std/io/core/descriptor.lin":L:C)
    cf.cond_br %v6, ^b1, ^b2 loc("std/io/core/descriptor.lin":L:C)
  ^b1:
    %v18 = arith.constant 8 : i64 loc("std/io/core/descriptor.lin":L:C)
    %v19 = llvm.getelementptr %rs3[%v18] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/descriptor.lin":L:C)
    %v20 = llvm.load %v19 : !llvm.ptr -> i64 loc("std/io/core/descriptor.lin":L:C)
    llvm.store %v20, %s2 : i64, !llvm.ptr loc("std/io/core/descriptor.lin":L:C)
    %v22 = arith.constant 0 : i64 loc("std/io/core/descriptor.lin":L:C)
    llvm.store %v22, %s4 : i64, !llvm.ptr loc("std/io/core/descriptor.lin":L:C)
    %v25 = arith.constant 8 : i64 loc("std/io/core/descriptor.lin":L:C)
    %v26 = llvm.getelementptr %s4[%v25] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/descriptor.lin":L:C)
    %v27 = arith.constant 0 : i64 loc("std/io/core/descriptor.lin":L:C)
    %rl28 = arith.constant 48 : i64 loc("std/io/core/descriptor.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s4, %rl28) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/descriptor.lin":L:C)
    func.return loc("std/io/core/descriptor.lin":L:C)
  ^b2:
    %v8 = arith.constant 8 : i64 loc("std/io/core/descriptor.lin":L:C)
    %v9 = llvm.getelementptr %rs3[%v8] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/descriptor.lin":L:C)
    func.call @"lin.std.io.core.IoError;std.convert;From[std.io.core.WriteFailure[std.io.core.IoError]].from"(%rs10, %v9) : (!llvm.ptr, !llvm.ptr) -> () loc("std/io/core/descriptor.lin":L:C)
    %v11 = arith.constant 1 : i64 loc("std/io/core/descriptor.lin":L:C)
    llvm.store %v11, %s3 : i64, !llvm.ptr loc("std/io/core/descriptor.lin":L:C)
    %v14 = arith.constant 8 : i64 loc("std/io/core/descriptor.lin":L:C)
    %v15 = llvm.getelementptr %s3[%v14] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/descriptor.lin":L:C)
    %cl16 = arith.constant 40 : i64 loc("std/io/core/descriptor.lin":L:C)
    "llvm.intr.memcpy"(%v15, %rs10, %cl16) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/descriptor.lin":L:C)
    %rl17 = arith.constant 48 : i64 loc("std/io/core/descriptor.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s3, %rl17) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/descriptor.lin":L:C)
    func.return loc("std/io/core/descriptor.lin":L:C)
  }
  func.func private @"lin.std.io.core.IoError;std.fmt;Display.fmt[std.io.core.Descriptor]"(%sret: !llvm.ptr, %a0: !llvm.ptr, %a1: !llvm.ptr) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 88 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 48 : i64
    %s3 = llvm.alloca %z3 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z4 = arith.constant 48 : i64
    %s4 = llvm.alloca %z4 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z5 = arith.constant 48 : i64
    %s5 = llvm.alloca %z5 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z6 = arith.constant 48 : i64
    %s6 = llvm.alloca %z6 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z7 = arith.constant 40 : i64
    %s7 = llvm.alloca %z7 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z8 = arith.constant 48 : i64
    %s8 = llvm.alloca %z8 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z9 = arith.constant 48 : i64
    %s9 = llvm.alloca %z9 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    llvm.store %a1, %s1 : !llvm.ptr, !llvm.ptr
    %rz65 = arith.constant 48 : i64
    %rs65 = llvm.alloca %rz65 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz76 = arith.constant 48 : i64
    %rs76 = llvm.alloca %rz76 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz86 = arith.constant 48 : i64
    %rs86 = llvm.alloca %rz86 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz97 = arith.constant 48 : i64
    %rs97 = llvm.alloca %rz97 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz107 = arith.constant 48 : i64
    %rs107 = llvm.alloca %rz107 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz118 = arith.constant 48 : i64
    %rs118 = llvm.alloca %rz118 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz128 = arith.constant 48 : i64
    %rs128 = llvm.alloca %rz128 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz197 = arith.constant 48 : i64
    %rs197 = llvm.alloca %rz197 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz208 = arith.constant 48 : i64
    %rs208 = llvm.alloca %rz208 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz218 = arith.constant 48 : i64
    %rs218 = llvm.alloca %rz218 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v1 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba3 = llvm.mlir.addressof @linea_str4 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v3 = llvm.ptrtoint %ba3 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v4 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v3, %s2 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v7 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v8 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v9 = llvm.getelementptr %s2[%v8] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v7, %v9 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v11 = arith.constant 16 : i64 loc("std/io/core/error.lin":L:C)
    %v12 = llvm.getelementptr %s2[%v11] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v13 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v14 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v16 = llvm.load %v13 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v16, %v12 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v18 = arith.constant 24 : i64 loc("std/io/core/error.lin":L:C)
    %v19 = llvm.getelementptr %s2[%v18] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %ba20 = llvm.mlir.addressof @linea_str5 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v20 = llvm.ptrtoint %ba20 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v21 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v20, %v19 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v24 = arith.constant 9 : i64 loc("std/io/core/error.lin":L:C)
    %v25 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v26 = llvm.getelementptr %v19[%v25] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v24, %v26 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v28 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    %v29 = llvm.getelementptr %s2[%v28] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v30 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v31 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v32 = llvm.getelementptr %v30[%v31] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v33 = llvm.load %v32 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v33, %v29 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v35 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    %v36 = llvm.getelementptr %s2[%v35] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %ba37 = llvm.mlir.addressof @linea_str6 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v37 = llvm.ptrtoint %ba37 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v38 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v37, %v36 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v41 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v42 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v43 = llvm.getelementptr %v36[%v42] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v41, %v43 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v45 = arith.constant 64 : i64 loc("std/io/core/error.lin":L:C)
    %v46 = llvm.getelementptr %s2[%v45] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v47 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v48 = arith.constant 32 : i64 loc("std/io/core/error.lin":L:C)
    %v49 = llvm.getelementptr %v47[%v48] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v50 = llvm.load %v49 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v50, %v46 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v52 = arith.constant 72 : i64 loc("std/io/core/error.lin":L:C)
    %v53 = llvm.getelementptr %s2[%v52] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %ba54 = llvm.mlir.addressof @linea_str7 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v54 = llvm.ptrtoint %ba54 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v55 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v54, %v53 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v58 = arith.constant 6 : i64 loc("std/io/core/error.lin":L:C)
    %v59 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v60 = llvm.getelementptr %v53[%v59] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v58, %v60 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v62 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v63 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.text.Str;std.fmt;Display.fmt[std.io.core.Descriptor]"(%rs65, %s2, %v62) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v66 = llvm.load %rs65 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v67 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v68 = arith.cmpi eq, %v66, %v67 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v68, ^b2, ^b3 loc("std/io/core/error.lin":L:C)
  ^b1:
    %v143 = llvm.load %s3 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v144 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v145 = arith.cmpi eq, %v143, %v144 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v145, ^b16, ^b17 loc("std/io/core/error.lin":L:C)
  ^b2:
    %v73 = arith.constant 16 : i64 loc("std/io/core/error.lin":L:C)
    %v74 = llvm.getelementptr %s2[%v73] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v75 = llvm.load %v74 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.IoOperation;std.fmt;Display.fmt[std.io.core.Descriptor]"(%rs76, %v75, %v62) : (!llvm.ptr, i64, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v77 = llvm.load %rs76 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v78 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v79 = arith.cmpi eq, %v77, %v78 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v79, ^b4, ^b5 loc("std/io/core/error.lin":L:C)
  ^b3:
    %cl71 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%s3, %rs65, %cl71) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b4:
    %v84 = arith.constant 24 : i64 loc("std/io/core/error.lin":L:C)
    %v85 = llvm.getelementptr %s2[%v84] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.text.Str;std.fmt;Display.fmt[std.io.core.Descriptor]"(%rs86, %v85, %v62) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v87 = llvm.load %rs86 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v88 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v89 = arith.cmpi eq, %v87, %v88 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v89, ^b6, ^b7 loc("std/io/core/error.lin":L:C)
  ^b5:
    %cl82 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%s3, %rs76, %cl82) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b6:
    %v94 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    %v95 = llvm.getelementptr %s2[%v94] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v96 = llvm.load %v95 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.IoCategory;std.fmt;Display.fmt[std.io.core.Descriptor]"(%rs97, %v96, %v62) : (!llvm.ptr, i64, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v98 = llvm.load %rs97 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v99 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v100 = arith.cmpi eq, %v98, %v99 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v100, ^b8, ^b9 loc("std/io/core/error.lin":L:C)
  ^b7:
    %cl92 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%s3, %rs86, %cl92) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b8:
    %v105 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    %v106 = llvm.getelementptr %s2[%v105] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.text.Str;std.fmt;Display.fmt[std.io.core.Descriptor]"(%rs107, %v106, %v62) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v108 = llvm.load %rs107 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v109 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v110 = arith.cmpi eq, %v108, %v109 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v110, ^b10, ^b11 loc("std/io/core/error.lin":L:C)
  ^b9:
    %cl103 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%s3, %rs97, %cl103) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b10:
    %v115 = arith.constant 64 : i64 loc("std/io/core/error.lin":L:C)
    %v116 = llvm.getelementptr %s2[%v115] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v117 = llvm.load %v116 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    func.call @"lin.UInt64;std.fmt;Display.fmt[std.io.core.Descriptor]"(%rs118, %v117, %v62) : (!llvm.ptr, i64, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v119 = llvm.load %rs118 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v120 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v121 = arith.cmpi eq, %v119, %v120 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v121, ^b12, ^b13 loc("std/io/core/error.lin":L:C)
  ^b11:
    %cl113 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%s3, %rs107, %cl113) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b12:
    %v126 = arith.constant 72 : i64 loc("std/io/core/error.lin":L:C)
    %v127 = llvm.getelementptr %s2[%v126] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.text.Str;std.fmt;Display.fmt[std.io.core.Descriptor]"(%rs128, %v127, %v62) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v129 = llvm.load %rs128 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v130 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v131 = arith.cmpi eq, %v129, %v130 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v131, ^b14, ^b15 loc("std/io/core/error.lin":L:C)
  ^b13:
    %cl124 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%s3, %rs118, %cl124) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b14:
    %v136 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v136, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %cl140 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%s3, %s4, %cl140) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b15:
    %cl134 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%s3, %rs128, %cl134) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b16:
    %v156 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v157 = llvm.getelementptr %s3[%v156] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v158 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v159 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v160 = arith.constant 16 : i64 loc("std/io/core/error.lin":L:C)
    %v161 = llvm.getelementptr %v159[%v160] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v162 = llvm.load %v161 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v163 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v164 = arith.cmpi eq, %v162, %v163 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v164, ^b19, ^b20 loc("std/io/core/error.lin":L:C)
  ^b17:
    %v147 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v148 = llvm.getelementptr %s3[%v147] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v149 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v149, %s5 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v152 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v153 = llvm.getelementptr %s5[%v152] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl154 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v153, %v148, %cl154) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl155 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s5, %rl155) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b18:
    %rl247 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s6, %rl247) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b19:
    %v166 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v167 = llvm.getelementptr %v161[%v166] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v170 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba172 = llvm.mlir.addressof @linea_str8 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v172 = llvm.ptrtoint %ba172 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v173 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v172, %s7 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v176 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v177 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v178 = llvm.getelementptr %s7[%v177] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v176, %v178 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v180 = arith.constant 16 : i64 loc("std/io/core/error.lin":L:C)
    %v181 = llvm.getelementptr %s7[%v180] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %iw182 = llvm.load %v167 : !llvm.ptr -> i32 loc("std/io/core/error.lin":L:C)
    %v182 = arith.extsi %iw182 : i32 to i64 loc("std/io/core/error.lin":L:C)
    %iw183 = arith.trunci %v182 : i64 to i32 loc("std/io/core/error.lin":L:C)
    llvm.store %iw183, %v181 : i32, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v184 = arith.constant 24 : i64 loc("std/io/core/error.lin":L:C)
    %v185 = llvm.getelementptr %s7[%v184] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %ba186 = llvm.mlir.addressof @linea_str4 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v186 = llvm.ptrtoint %ba186 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v187 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v186, %v185 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v190 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v191 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v192 = llvm.getelementptr %v185[%v191] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v190, %v192 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v194 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v195 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.text.Str;std.fmt;Display.fmt[std.io.core.Descriptor]"(%rs197, %s7, %v194) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v198 = llvm.load %rs197 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v199 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v200 = arith.cmpi eq, %v198, %v199 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v200, ^b22, ^b23 loc("std/io/core/error.lin":L:C)
  ^b20:
    %v235 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v236 = arith.cmpi eq, %v162, %v235 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v236, ^b28, ^b29 loc("std/io/core/error.lin":L:C)
  ^b21:
    %cl233 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%s6, %s8, %cl233) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    cf.br ^b18 loc("std/io/core/error.lin":L:C)
  ^b22:
    %v205 = arith.constant 16 : i64 loc("std/io/core/error.lin":L:C)
    %v206 = llvm.getelementptr %s7[%v205] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %iw207 = llvm.load %v206 : !llvm.ptr -> i32 loc("std/io/core/error.lin":L:C)
    %v207 = arith.extsi %iw207 : i32 to i64 loc("std/io/core/error.lin":L:C)
    func.call @"lin.Int32;std.fmt;Display.fmt[std.io.core.Descriptor]"(%rs208, %v207, %v194) : (!llvm.ptr, i64, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v209 = llvm.load %rs208 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v210 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v211 = arith.cmpi eq, %v209, %v210 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v211, ^b24, ^b25 loc("std/io/core/error.lin":L:C)
  ^b23:
    %cl203 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%s8, %rs197, %cl203) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    cf.br ^b21 loc("std/io/core/error.lin":L:C)
  ^b24:
    %v216 = arith.constant 24 : i64 loc("std/io/core/error.lin":L:C)
    %v217 = llvm.getelementptr %s7[%v216] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.text.Str;std.fmt;Display.fmt[std.io.core.Descriptor]"(%rs218, %v217, %v194) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v219 = llvm.load %rs218 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v220 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v221 = arith.cmpi eq, %v219, %v220 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v221, ^b26, ^b27 loc("std/io/core/error.lin":L:C)
  ^b25:
    %cl214 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%s8, %rs208, %cl214) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    cf.br ^b21 loc("std/io/core/error.lin":L:C)
  ^b26:
    %v226 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v226, %s9 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %cl230 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%s8, %s9, %cl230) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    cf.br ^b21 loc("std/io/core/error.lin":L:C)
  ^b27:
    %cl224 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%s8, %rs218, %cl224) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    cf.br ^b21 loc("std/io/core/error.lin":L:C)
  ^b28:
    %v239 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v239, %s6 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v241 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v242 = llvm.getelementptr %s6[%v241] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v243 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b18 loc("std/io/core/error.lin":L:C)
  ^b29:
    %tk1 = arith.constant 3 : i32 loc("std/io/core/error.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file7 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/io/core/error.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/io/core/error.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/io/core/error.lin":L:C)
    llvm.unreachable loc("std/io/core/error.lin":L:C)
  }
  func.func private @"lin.std.text;Str.as_bytes"(%sret: !llvm.ptr, %a0: !llvm.ptr) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 16 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/text/str.lin":L:C)
    %v1 = arith.constant 0 : i64 loc("std/text/str.lin":L:C)
    %cl4 = arith.constant 16 : i64 loc("std/text/str.lin":L:C)
    "llvm.intr.memcpy"(%s1, %v0, %cl4) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/text/str.lin":L:C)
    %rl6 = arith.constant 16 : i64 loc("std/text/str.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s1, %rl6) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/text/str.lin":L:C)
    func.return loc("std/text/str.lin":L:C)
  }
  func.func private @"lin.std.io.core;write_all[std.io.core.Descriptor]"(%sret: !llvm.ptr, %a0: !llvm.ptr, %a1: !llvm.ptr) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 1 : i64
    %s3 = llvm.alloca %z3 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z4 = arith.constant 16 : i64
    %s4 = llvm.alloca %z4 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z5 = arith.constant 1 : i64
    %s5 = llvm.alloca %z5 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z6 = arith.constant 72 : i64
    %s6 = llvm.alloca %z6 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z7 = arith.constant 72 : i64
    %s7 = llvm.alloca %z7 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z8 = arith.constant 64 : i64
    %s8 = llvm.alloca %z8 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z9 = arith.constant 1 : i64
    %s9 = llvm.alloca %z9 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z10 = arith.constant 48 : i64
    %s10 = llvm.alloca %z10 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z11 = arith.constant 1 : i64
    %s11 = llvm.alloca %z11 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z12 = arith.constant 72 : i64
    %s12 = llvm.alloca %z12 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z13 = arith.constant 72 : i64
    %s13 = llvm.alloca %z13 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z14 = arith.constant 72 : i64
    %s14 = llvm.alloca %z14 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    llvm.store %a1, %s1 : !llvm.ptr, !llvm.ptr
    %rz18 = arith.constant 24 : i64
    %rs18 = llvm.alloca %rz18 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz19 = arith.constant 16 : i64
    %rs19 = llvm.alloca %rz19 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz23 = arith.constant 72 : i64
    %rs23 = llvm.alloca %rz23 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 0 : i64 loc("std/io/core/byte_writer.lin":L:C)
    llvm.store %v0, %s2 : i64, !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    cf.br ^b1 loc("std/io/core/byte_writer.lin":L:C)
  ^b1:
    %v3 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
    %v4 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %v5 = func.call @"lin.std.mem;Slice[UInt8].length"(%v4) : (!llvm.ptr) -> i64 loc("std/io/core/byte_writer.lin":L:C)
    %v6 = arith.cmpi ult, %v3, %v5 : i64 loc("std/io/core/byte_writer.lin":L:C)
    cf.cond_br %v6, ^b2, ^b3 loc("std/io/core/byte_writer.lin":L:C)
  ^b2:
    %v8 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %v9 = func.call @"lin.std.mem;Slice[UInt8].length"(%v8) : (!llvm.ptr) -> i64 loc("std/io/core/byte_writer.lin":L:C)
    %v10 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
    %v11 = arith.subi %v9, %v10 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %k1 = arith.cmpi ult, %v9, %v10 : i64 loc("std/io/core/byte_writer.lin":L:C)
    cf.cond_br %k1, ^t1, ^c1 loc("std/io/core/byte_writer.lin":L:C)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("std/io/core/byte_writer.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file8 : !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/io/core/byte_writer.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/io/core/byte_writer.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/io/core/byte_writer.lin":L:C)
    llvm.unreachable loc("std/io/core/byte_writer.lin":L:C)
  ^c1:
    %p12 = arith.constant 0 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v12 = arith.addi %v11, %p12 : i64 loc("std/io/core/byte_writer.lin":L:C)
    llvm.store %v12, %s3 : i64, !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %v15 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %v16 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
    %v17 = llvm.load %s3 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
    func.call @"lin.std.mem;Slice[UInt8].subspan"(%rs18, %v15, %v16, %v17) : (!llvm.ptr, !llvm.ptr, i64, i64) -> () loc("std/io/core/byte_writer.lin":L:C)
    func.call @"lin.std.option;Option[std.mem.Slice[UInt8]].unwrap"(%rs19, %rs18) : (!llvm.ptr, !llvm.ptr) -> () loc("std/io/core/byte_writer.lin":L:C)
    %cl20 = arith.constant 16 : i64 loc("std/io/core/byte_writer.lin":L:C)
    "llvm.intr.memcpy"(%s4, %rs19, %cl20) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/byte_writer.lin":L:C)
    %v21 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;ByteWriter.write_some"(%rs23, %v21, %s4) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/byte_writer.lin":L:C)
    %v24 = llvm.load %rs23 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
    %v25 = arith.constant 0 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v26 = arith.cmpi eq, %v24, %v25 : i64 loc("std/io/core/byte_writer.lin":L:C)
    cf.cond_br %v26, ^b5, ^b6 loc("std/io/core/byte_writer.lin":L:C)
  ^b3:
    %v163 = arith.constant 0 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v164 = arith.constant 0 : i64 loc("std/io/core/byte_writer.lin":L:C)
    llvm.store %v164, %s14 : i64, !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %v167 = arith.constant 8 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v168 = llvm.getelementptr %s14[%v167] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/byte_writer.lin":L:C)
    %v169 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
    llvm.store %v169, %v168 : i64, !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %rl171 = arith.constant 72 : i64 loc("std/io/core/byte_writer.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s14, %rl171) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/byte_writer.lin":L:C)
    func.return loc("std/io/core/byte_writer.lin":L:C)
  ^b4:
    %v161 = arith.constant 0 : i64 loc("std/io/core/byte_writer.lin":L:C)
    cf.br ^b1 loc("std/io/core/byte_writer.lin":L:C)
  ^b5:
    %v28 = arith.constant 8 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v29 = llvm.getelementptr %rs23[%v28] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/byte_writer.lin":L:C)
    %v30 = llvm.load %v29 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
    llvm.store %v30, %s5 : i64, !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %v32 = llvm.load %s5 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
    %v33 = arith.constant 0 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v34 = arith.cmpi eq, %v32, %v33 : i64 loc("std/io/core/byte_writer.lin":L:C)
    cf.cond_br %v34, ^b7, ^b8 loc("std/io/core/byte_writer.lin":L:C)
  ^b6:
    %v91 = arith.constant 1 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v92 = arith.cmpi eq, %v24, %v91 : i64 loc("std/io/core/byte_writer.lin":L:C)
    cf.cond_br %v92, ^b15, ^b16 loc("std/io/core/byte_writer.lin":L:C)
  ^b7:
    %v36 = arith.constant 1 : i64 loc("std/io/core/byte_writer.lin":L:C)
    llvm.store %v36, %s6 : i64, !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %v39 = arith.constant 8 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v40 = llvm.getelementptr %s6[%v39] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/byte_writer.lin":L:C)
    %v41 = arith.constant 0 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v43 = arith.constant 1 : i64 loc("std/io/core/byte_writer.lin":L:C)
    llvm.store %v43, %v40 : i64, !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %v45 = arith.constant 8 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v46 = llvm.getelementptr %v40[%v45] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/byte_writer.lin":L:C)
    %v47 = arith.constant 0 : i64 loc("std/io/core/byte_writer.lin":L:C)
    llvm.store %v47, %v46 : i64, !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %v49 = arith.constant 56 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v50 = llvm.getelementptr %v40[%v49] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/byte_writer.lin":L:C)
    %v51 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
    llvm.store %v51, %v50 : i64, !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %rl53 = arith.constant 72 : i64 loc("std/io/core/byte_writer.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s6, %rl53) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/byte_writer.lin":L:C)
    func.return loc("std/io/core/byte_writer.lin":L:C)
  ^b8:
    cf.br ^b9 loc("std/io/core/byte_writer.lin":L:C)
  ^b9:
    %v57 = arith.constant 0 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v58 = llvm.load %s5 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
    %v59 = llvm.load %s3 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
    %v60 = arith.cmpi ugt, %v58, %v59 : i64 loc("std/io/core/byte_writer.lin":L:C)
    cf.cond_br %v60, ^b11, ^b12 loc("std/io/core/byte_writer.lin":L:C)
  ^b11:
    %v62 = arith.constant 1 : i64 loc("std/io/core/byte_writer.lin":L:C)
    llvm.store %v62, %s7 : i64, !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %v65 = arith.constant 8 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v66 = llvm.getelementptr %s7[%v65] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/byte_writer.lin":L:C)
    %v67 = arith.constant 0 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v69 = arith.constant 2 : i64 loc("std/io/core/byte_writer.lin":L:C)
    llvm.store %v69, %v66 : i64, !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %v71 = arith.constant 8 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v72 = llvm.getelementptr %v66[%v71] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/byte_writer.lin":L:C)
    %v73 = arith.constant 0 : i64 loc("std/io/core/byte_writer.lin":L:C)
    llvm.store %v73, %v72 : i64, !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %v75 = arith.constant 56 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v76 = llvm.getelementptr %v66[%v75] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/byte_writer.lin":L:C)
    %v77 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
    llvm.store %v77, %v76 : i64, !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %rl79 = arith.constant 72 : i64 loc("std/io/core/byte_writer.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s7, %rl79) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/byte_writer.lin":L:C)
    func.return loc("std/io/core/byte_writer.lin":L:C)
  ^b12:
    cf.br ^b13 loc("std/io/core/byte_writer.lin":L:C)
  ^b13:
    %v83 = arith.constant 0 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v84 = llvm.load %s5 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
    %v85 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
    %v86 = arith.addi %v85, %v84 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %k2 = arith.cmpi ult, %v86, %v85 : i64 loc("std/io/core/byte_writer.lin":L:C)
    cf.cond_br %k2, ^t2, ^c2 loc("std/io/core/byte_writer.lin":L:C)
  ^t2:
    %tk2 = arith.constant 0 : i32 loc("std/io/core/byte_writer.lin":L:C)
    %tf2 = llvm.mlir.addressof @linea_file8 : !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %tl2 = arith.constant L : i32 loc("std/io/core/byte_writer.lin":L:C)
    %tc2 = arith.constant C : i32 loc("std/io/core/byte_writer.lin":L:C)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("std/io/core/byte_writer.lin":L:C)
    llvm.unreachable loc("std/io/core/byte_writer.lin":L:C)
  ^c2:
    %p87 = arith.constant 0 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v87 = arith.addi %v86, %p87 : i64 loc("std/io/core/byte_writer.lin":L:C)
    llvm.store %v87, %s2 : i64, !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %v89 = arith.constant 0 : i64 loc("std/io/core/byte_writer.lin":L:C)
    cf.br ^b4 loc("std/io/core/byte_writer.lin":L:C)
  ^b15:
    %v94 = arith.constant 8 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v95 = llvm.getelementptr %rs23[%v94] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/byte_writer.lin":L:C)
    %cl97 = arith.constant 64 : i64 loc("std/io/core/byte_writer.lin":L:C)
    "llvm.intr.memcpy"(%s8, %v95, %cl97) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/byte_writer.lin":L:C)
    %v99 = arith.constant 0 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v101 = llvm.load %s8 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
    llvm.store %v101, %s9 : i64, !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %v103 = arith.constant 8 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v104 = llvm.getelementptr %s8[%v103] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/byte_writer.lin":L:C)
    %cl106 = arith.constant 48 : i64 loc("std/io/core/byte_writer.lin":L:C)
    "llvm.intr.memcpy"(%s10, %v104, %cl106) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/byte_writer.lin":L:C)
    %v107 = arith.constant 56 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v108 = llvm.getelementptr %s8[%v107] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/byte_writer.lin":L:C)
    %v109 = llvm.load %v108 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
    llvm.store %v109, %s11 : i64, !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %v111 = llvm.load %s11 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
    %v112 = llvm.load %s3 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
    %v113 = arith.cmpi ugt, %v111, %v112 : i64 loc("std/io/core/byte_writer.lin":L:C)
    cf.cond_br %v113, ^b17, ^b18 loc("std/io/core/byte_writer.lin":L:C)
  ^b16:
    %tk3 = arith.constant 3 : i32 loc("std/io/core/byte_writer.lin":L:C)
    %tf3 = llvm.mlir.addressof @linea_file8 : !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %tl3 = arith.constant L : i32 loc("std/io/core/byte_writer.lin":L:C)
    %tc3 = arith.constant C : i32 loc("std/io/core/byte_writer.lin":L:C)
    func.call @linea_trap(%tk3, %tf3, %tl3, %tc3) : (i32, !llvm.ptr, i32, i32) -> () loc("std/io/core/byte_writer.lin":L:C)
    llvm.unreachable loc("std/io/core/byte_writer.lin":L:C)
  ^b17:
    %v115 = arith.constant 1 : i64 loc("std/io/core/byte_writer.lin":L:C)
    llvm.store %v115, %s12 : i64, !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %v118 = arith.constant 8 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v119 = llvm.getelementptr %s12[%v118] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/byte_writer.lin":L:C)
    %v120 = arith.constant 0 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v122 = arith.constant 2 : i64 loc("std/io/core/byte_writer.lin":L:C)
    llvm.store %v122, %v119 : i64, !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %v124 = arith.constant 8 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v125 = llvm.getelementptr %v119[%v124] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/byte_writer.lin":L:C)
    %cl127 = arith.constant 48 : i64 loc("std/io/core/byte_writer.lin":L:C)
    "llvm.intr.memcpy"(%v125, %s10, %cl127) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/byte_writer.lin":L:C)
    %v128 = arith.constant 56 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v129 = llvm.getelementptr %v119[%v128] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/byte_writer.lin":L:C)
    %v130 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
    llvm.store %v130, %v129 : i64, !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %rl132 = arith.constant 72 : i64 loc("std/io/core/byte_writer.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s12, %rl132) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/byte_writer.lin":L:C)
    func.return loc("std/io/core/byte_writer.lin":L:C)
  ^b18:
    cf.br ^b19 loc("std/io/core/byte_writer.lin":L:C)
  ^b19:
    %v136 = arith.constant 0 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v137 = arith.constant 1 : i64 loc("std/io/core/byte_writer.lin":L:C)
    llvm.store %v137, %s13 : i64, !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %v140 = arith.constant 8 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v141 = llvm.getelementptr %s13[%v140] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/byte_writer.lin":L:C)
    %v142 = arith.constant 0 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v144 = llvm.load %s9 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
    llvm.store %v144, %v141 : i64, !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %v146 = arith.constant 8 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v147 = llvm.getelementptr %v141[%v146] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/byte_writer.lin":L:C)
    %cl149 = arith.constant 48 : i64 loc("std/io/core/byte_writer.lin":L:C)
    "llvm.intr.memcpy"(%v147, %s10, %cl149) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/byte_writer.lin":L:C)
    %v150 = arith.constant 56 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v151 = llvm.getelementptr %v141[%v150] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/byte_writer.lin":L:C)
    %v152 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
    %v153 = llvm.load %s11 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
    %v154 = arith.addi %v152, %v153 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %k4 = arith.cmpi ult, %v154, %v152 : i64 loc("std/io/core/byte_writer.lin":L:C)
    cf.cond_br %k4, ^t4, ^c4 loc("std/io/core/byte_writer.lin":L:C)
  ^t4:
    %tk4 = arith.constant 0 : i32 loc("std/io/core/byte_writer.lin":L:C)
    %tf4 = llvm.mlir.addressof @linea_file8 : !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %tl4 = arith.constant L : i32 loc("std/io/core/byte_writer.lin":L:C)
    %tc4 = arith.constant C : i32 loc("std/io/core/byte_writer.lin":L:C)
    func.call @linea_trap(%tk4, %tf4, %tl4, %tc4) : (i32, !llvm.ptr, i32, i32) -> () loc("std/io/core/byte_writer.lin":L:C)
    llvm.unreachable loc("std/io/core/byte_writer.lin":L:C)
  ^c4:
    %p155 = arith.constant 0 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v155 = arith.addi %v154, %p155 : i64 loc("std/io/core/byte_writer.lin":L:C)
    llvm.store %v155, %v151 : i64, !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %rl157 = arith.constant 72 : i64 loc("std/io/core/byte_writer.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s13, %rl157) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/byte_writer.lin":L:C)
    func.return loc("std/io/core/byte_writer.lin":L:C)
  }
  func.func private @"lin.std.io.core.IoError;std.convert;From[std.io.core.WriteFailure[std.io.core.IoError]].from"(%sret: !llvm.ptr, %a0: !llvm.ptr) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 64 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 48 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 1 : i64
    %s3 = llvm.alloca %z3 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z4 = arith.constant 40 : i64
    %s4 = llvm.alloca %z4 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z5 = arith.constant 40 : i64
    %s5 = llvm.alloca %z5 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z6 = arith.constant 40 : i64
    %s6 = llvm.alloca %z6 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %pl0 = arith.constant 64 : i64
    "llvm.intr.memcpy"(%s0, %a0, %pl0) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> ()
    cf.br ^b0
  ^b0:
    %v1 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v3 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v3, %s1 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v5 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v6 = llvm.getelementptr %s0[%v5] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl8 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%s2, %v6, %cl8) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %v9 = arith.constant 56 : i64 loc("std/io/core/error.lin":L:C)
    %v10 = llvm.getelementptr %s0[%v9] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v11 = llvm.load %v10 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v11, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v15 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v16 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v17 = arith.cmpi eq, %v15, %v16 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v17, ^b2, ^b3 loc("std/io/core/error.lin":L:C)
  ^b1:
    %cl50 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%s4, %s5, %cl50) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %v51 = llvm.load %s3 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v53 = arith.constant 32 : i64 loc("std/io/core/error.lin":L:C)
    %v54 = llvm.getelementptr %s4[%v53] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v51, %v54 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v56 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v57 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v58 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v59 = arith.cmpi eq, %v57, %v58 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v59, ^b7, ^b8 loc("std/io/core/error.lin":L:C)
  ^b2:
    %v19 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v20 = llvm.getelementptr %s2[%v19] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl22 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%s6, %v20, %cl22) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %cl25 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%s5, %s6, %cl25) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b3:
    %v27 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v28 = arith.cmpi eq, %v15, %v27 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v28, ^b4, ^b5 loc("std/io/core/error.lin":L:C)
  ^b4:
    %v31 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v33 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v33, %s5 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v35 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v36 = llvm.getelementptr %s5[%v35] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v37 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v37, %v36 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v39 = arith.constant 16 : i64 loc("std/io/core/error.lin":L:C)
    %v40 = llvm.getelementptr %s5[%v39] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v41 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v41, %v40 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v43 = arith.constant 32 : i64 loc("std/io/core/error.lin":L:C)
    %v44 = llvm.getelementptr %s5[%v43] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v45 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v45, %v44 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b5:
    %tk1 = arith.constant 3 : i32 loc("std/io/core/error.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file7 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/io/core/error.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/io/core/error.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/io/core/error.lin":L:C)
    llvm.unreachable loc("std/io/core/error.lin":L:C)
  ^b6:
    %v84 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl86 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s4, %rl86) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b7:
    %v61 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b6 loc("std/io/core/error.lin":L:C)
  ^b8:
    %v63 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v64 = arith.cmpi eq, %v57, %v63 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v64, ^b9, ^b10 loc("std/io/core/error.lin":L:C)
  ^b9:
    %v66 = arith.constant 15 : i64 loc("std/io/core/error.lin":L:C)
    %v68 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v69 = llvm.getelementptr %s4[%v68] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v66, %v69 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v71 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b6 loc("std/io/core/error.lin":L:C)
  ^b10:
    %v73 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v74 = arith.cmpi eq, %v57, %v73 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v74, ^b11, ^b12 loc("std/io/core/error.lin":L:C)
  ^b11:
    %v76 = arith.constant 16 : i64 loc("std/io/core/error.lin":L:C)
    %v78 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v79 = llvm.getelementptr %s4[%v78] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v76, %v79 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v81 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b6 loc("std/io/core/error.lin":L:C)
  ^b12:
    %tk2 = arith.constant 3 : i32 loc("std/io/core/error.lin":L:C)
    %tf2 = llvm.mlir.addressof @linea_file7 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %tl2 = arith.constant L : i32 loc("std/io/core/error.lin":L:C)
    %tc2 = arith.constant C : i32 loc("std/io/core/error.lin":L:C)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("std/io/core/error.lin":L:C)
    llvm.unreachable loc("std/io/core/error.lin":L:C)
  }
  func.func private @"lin.std.io.core.IoOperation;std.fmt;Display.fmt[std.io.core.Descriptor]"(%sret: !llvm.ptr, %a0: i64, %a1: !llvm.ptr) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 16 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 48 : i64
    %s3 = llvm.alloca %z3 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z4 = arith.constant 1 : i64
    %s4 = llvm.alloca %z4 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z5 = arith.constant 16 : i64
    %s5 = llvm.alloca %z5 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z6 = arith.constant 48 : i64
    %s6 = llvm.alloca %z6 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z7 = arith.constant 16 : i64
    %s7 = llvm.alloca %z7 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z8 = arith.constant 48 : i64
    %s8 = llvm.alloca %z8 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z9 = arith.constant 48 : i64
    %s9 = llvm.alloca %z9 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z10 = arith.constant 16 : i64
    %s10 = llvm.alloca %z10 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z11 = arith.constant 48 : i64
    %s11 = llvm.alloca %z11 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z12 = arith.constant 1 : i64
    %s12 = llvm.alloca %z12 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z13 = arith.constant 16 : i64
    %s13 = llvm.alloca %z13 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z14 = arith.constant 48 : i64
    %s14 = llvm.alloca %z14 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z15 = arith.constant 16 : i64
    %s15 = llvm.alloca %z15 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z16 = arith.constant 48 : i64
    %s16 = llvm.alloca %z16 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z17 = arith.constant 48 : i64
    %s17 = llvm.alloca %z17 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z18 = arith.constant 16 : i64
    %s18 = llvm.alloca %z18 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z19 = arith.constant 48 : i64
    %s19 = llvm.alloca %z19 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z20 = arith.constant 1 : i64
    %s20 = llvm.alloca %z20 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z21 = arith.constant 16 : i64
    %s21 = llvm.alloca %z21 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z22 = arith.constant 48 : i64
    %s22 = llvm.alloca %z22 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z23 = arith.constant 16 : i64
    %s23 = llvm.alloca %z23 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z24 = arith.constant 48 : i64
    %s24 = llvm.alloca %z24 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z25 = arith.constant 48 : i64
    %s25 = llvm.alloca %z25 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z26 = arith.constant 16 : i64
    %s26 = llvm.alloca %z26 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z27 = arith.constant 48 : i64
    %s27 = llvm.alloca %z27 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z28 = arith.constant 1 : i64
    %s28 = llvm.alloca %z28 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z29 = arith.constant 16 : i64
    %s29 = llvm.alloca %z29 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z30 = arith.constant 48 : i64
    %s30 = llvm.alloca %z30 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z31 = arith.constant 16 : i64
    %s31 = llvm.alloca %z31 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z32 = arith.constant 48 : i64
    %s32 = llvm.alloca %z32 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z33 = arith.constant 48 : i64
    %s33 = llvm.alloca %z33 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z34 = arith.constant 16 : i64
    %s34 = llvm.alloca %z34 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z35 = arith.constant 48 : i64
    %s35 = llvm.alloca %z35 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z36 = arith.constant 1 : i64
    %s36 = llvm.alloca %z36 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z37 = arith.constant 16 : i64
    %s37 = llvm.alloca %z37 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z38 = arith.constant 48 : i64
    %s38 = llvm.alloca %z38 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z39 = arith.constant 16 : i64
    %s39 = llvm.alloca %z39 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z40 = arith.constant 48 : i64
    %s40 = llvm.alloca %z40 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z41 = arith.constant 48 : i64
    %s41 = llvm.alloca %z41 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z42 = arith.constant 16 : i64
    %s42 = llvm.alloca %z42 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z43 = arith.constant 48 : i64
    %s43 = llvm.alloca %z43 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z44 = arith.constant 1 : i64
    %s44 = llvm.alloca %z44 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z45 = arith.constant 16 : i64
    %s45 = llvm.alloca %z45 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z46 = arith.constant 48 : i64
    %s46 = llvm.alloca %z46 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z47 = arith.constant 16 : i64
    %s47 = llvm.alloca %z47 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z48 = arith.constant 48 : i64
    %s48 = llvm.alloca %z48 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z49 = arith.constant 48 : i64
    %s49 = llvm.alloca %z49 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z50 = arith.constant 16 : i64
    %s50 = llvm.alloca %z50 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z51 = arith.constant 48 : i64
    %s51 = llvm.alloca %z51 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z52 = arith.constant 1 : i64
    %s52 = llvm.alloca %z52 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z53 = arith.constant 16 : i64
    %s53 = llvm.alloca %z53 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z54 = arith.constant 48 : i64
    %s54 = llvm.alloca %z54 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z55 = arith.constant 16 : i64
    %s55 = llvm.alloca %z55 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z56 = arith.constant 48 : i64
    %s56 = llvm.alloca %z56 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z57 = arith.constant 48 : i64
    %s57 = llvm.alloca %z57 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z58 = arith.constant 16 : i64
    %s58 = llvm.alloca %z58 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z59 = arith.constant 48 : i64
    %s59 = llvm.alloca %z59 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z60 = arith.constant 1 : i64
    %s60 = llvm.alloca %z60 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z61 = arith.constant 16 : i64
    %s61 = llvm.alloca %z61 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z62 = arith.constant 48 : i64
    %s62 = llvm.alloca %z62 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z63 = arith.constant 16 : i64
    %s63 = llvm.alloca %z63 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z64 = arith.constant 48 : i64
    %s64 = llvm.alloca %z64 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z65 = arith.constant 48 : i64
    %s65 = llvm.alloca %z65 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z66 = arith.constant 16 : i64
    %s66 = llvm.alloca %z66 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z67 = arith.constant 48 : i64
    %s67 = llvm.alloca %z67 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z68 = arith.constant 1 : i64
    %s68 = llvm.alloca %z68 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z69 = arith.constant 16 : i64
    %s69 = llvm.alloca %z69 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z70 = arith.constant 48 : i64
    %s70 = llvm.alloca %z70 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z71 = arith.constant 16 : i64
    %s71 = llvm.alloca %z71 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z72 = arith.constant 48 : i64
    %s72 = llvm.alloca %z72 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z73 = arith.constant 48 : i64
    %s73 = llvm.alloca %z73 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z74 = arith.constant 16 : i64
    %s74 = llvm.alloca %z74 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z75 = arith.constant 48 : i64
    %s75 = llvm.alloca %z75 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z76 = arith.constant 1 : i64
    %s76 = llvm.alloca %z76 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z77 = arith.constant 16 : i64
    %s77 = llvm.alloca %z77 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z78 = arith.constant 48 : i64
    %s78 = llvm.alloca %z78 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z79 = arith.constant 16 : i64
    %s79 = llvm.alloca %z79 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z80 = arith.constant 48 : i64
    %s80 = llvm.alloca %z80 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z81 = arith.constant 48 : i64
    %s81 = llvm.alloca %z81 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z82 = arith.constant 16 : i64
    %s82 = llvm.alloca %z82 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z83 = arith.constant 48 : i64
    %s83 = llvm.alloca %z83 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z84 = arith.constant 1 : i64
    %s84 = llvm.alloca %z84 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z85 = arith.constant 16 : i64
    %s85 = llvm.alloca %z85 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z86 = arith.constant 48 : i64
    %s86 = llvm.alloca %z86 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z87 = arith.constant 16 : i64
    %s87 = llvm.alloca %z87 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z88 = arith.constant 48 : i64
    %s88 = llvm.alloca %z88 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z89 = arith.constant 48 : i64
    %s89 = llvm.alloca %z89 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z90 = arith.constant 16 : i64
    %s90 = llvm.alloca %z90 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z91 = arith.constant 48 : i64
    %s91 = llvm.alloca %z91 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z92 = arith.constant 1 : i64
    %s92 = llvm.alloca %z92 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z93 = arith.constant 16 : i64
    %s93 = llvm.alloca %z93 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z94 = arith.constant 48 : i64
    %s94 = llvm.alloca %z94 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z95 = arith.constant 16 : i64
    %s95 = llvm.alloca %z95 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z96 = arith.constant 48 : i64
    %s96 = llvm.alloca %z96 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z97 = arith.constant 48 : i64
    %s97 = llvm.alloca %z97 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z98 = arith.constant 16 : i64
    %s98 = llvm.alloca %z98 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z99 = arith.constant 48 : i64
    %s99 = llvm.alloca %z99 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z100 = arith.constant 1 : i64
    %s100 = llvm.alloca %z100 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z101 = arith.constant 16 : i64
    %s101 = llvm.alloca %z101 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z102 = arith.constant 48 : i64
    %s102 = llvm.alloca %z102 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z103 = arith.constant 16 : i64
    %s103 = llvm.alloca %z103 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z104 = arith.constant 48 : i64
    %s104 = llvm.alloca %z104 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z105 = arith.constant 48 : i64
    %s105 = llvm.alloca %z105 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z106 = arith.constant 16 : i64
    %s106 = llvm.alloca %z106 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z107 = arith.constant 48 : i64
    %s107 = llvm.alloca %z107 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z108 = arith.constant 1 : i64
    %s108 = llvm.alloca %z108 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z109 = arith.constant 16 : i64
    %s109 = llvm.alloca %z109 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z110 = arith.constant 48 : i64
    %s110 = llvm.alloca %z110 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z111 = arith.constant 16 : i64
    %s111 = llvm.alloca %z111 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z112 = arith.constant 48 : i64
    %s112 = llvm.alloca %z112 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z113 = arith.constant 48 : i64
    %s113 = llvm.alloca %z113 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : i64, !llvm.ptr
    llvm.store %a1, %s1 : !llvm.ptr, !llvm.ptr
    %rz14 = arith.constant 48 : i64
    %rs14 = llvm.alloca %rz14 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz48 = arith.constant 48 : i64
    %rs48 = llvm.alloca %rz48 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz76 = arith.constant 48 : i64
    %rs76 = llvm.alloca %rz76 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz120 = arith.constant 48 : i64
    %rs120 = llvm.alloca %rz120 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz154 = arith.constant 48 : i64
    %rs154 = llvm.alloca %rz154 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz182 = arith.constant 48 : i64
    %rs182 = llvm.alloca %rz182 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz226 = arith.constant 48 : i64
    %rs226 = llvm.alloca %rz226 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz260 = arith.constant 48 : i64
    %rs260 = llvm.alloca %rz260 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz288 = arith.constant 48 : i64
    %rs288 = llvm.alloca %rz288 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz332 = arith.constant 48 : i64
    %rs332 = llvm.alloca %rz332 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz366 = arith.constant 48 : i64
    %rs366 = llvm.alloca %rz366 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz394 = arith.constant 48 : i64
    %rs394 = llvm.alloca %rz394 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz438 = arith.constant 48 : i64
    %rs438 = llvm.alloca %rz438 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz472 = arith.constant 48 : i64
    %rs472 = llvm.alloca %rz472 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz500 = arith.constant 48 : i64
    %rs500 = llvm.alloca %rz500 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz544 = arith.constant 48 : i64
    %rs544 = llvm.alloca %rz544 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz578 = arith.constant 48 : i64
    %rs578 = llvm.alloca %rz578 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz606 = arith.constant 48 : i64
    %rs606 = llvm.alloca %rz606 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz650 = arith.constant 48 : i64
    %rs650 = llvm.alloca %rz650 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz684 = arith.constant 48 : i64
    %rs684 = llvm.alloca %rz684 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz712 = arith.constant 48 : i64
    %rs712 = llvm.alloca %rz712 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz756 = arith.constant 48 : i64
    %rs756 = llvm.alloca %rz756 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz790 = arith.constant 48 : i64
    %rs790 = llvm.alloca %rz790 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz818 = arith.constant 48 : i64
    %rs818 = llvm.alloca %rz818 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz862 = arith.constant 48 : i64
    %rs862 = llvm.alloca %rz862 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz896 = arith.constant 48 : i64
    %rs896 = llvm.alloca %rz896 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz924 = arith.constant 48 : i64
    %rs924 = llvm.alloca %rz924 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz968 = arith.constant 48 : i64
    %rs968 = llvm.alloca %rz968 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1002 = arith.constant 48 : i64
    %rs1002 = llvm.alloca %rz1002 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1030 = arith.constant 48 : i64
    %rs1030 = llvm.alloca %rz1030 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1074 = arith.constant 48 : i64
    %rs1074 = llvm.alloca %rz1074 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1108 = arith.constant 48 : i64
    %rs1108 = llvm.alloca %rz1108 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1136 = arith.constant 48 : i64
    %rs1136 = llvm.alloca %rz1136 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1180 = arith.constant 48 : i64
    %rs1180 = llvm.alloca %rz1180 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1214 = arith.constant 48 : i64
    %rs1214 = llvm.alloca %rz1214 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1242 = arith.constant 48 : i64
    %rs1242 = llvm.alloca %rz1242 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1286 = arith.constant 48 : i64
    %rs1286 = llvm.alloca %rz1286 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1320 = arith.constant 48 : i64
    %rs1320 = llvm.alloca %rz1320 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1348 = arith.constant 48 : i64
    %rs1348 = llvm.alloca %rz1348 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1392 = arith.constant 48 : i64
    %rs1392 = llvm.alloca %rz1392 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1426 = arith.constant 48 : i64
    %rs1426 = llvm.alloca %rz1426 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1454 = arith.constant 48 : i64
    %rs1454 = llvm.alloca %rz1454 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v2 = arith.cmpi eq, %v0, %v1 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v2, ^b2, ^b3 loc("std/io/core/error.lin":L:C)
  ^b2:
    %v4 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba6 = llvm.mlir.addressof @linea_str9 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v6 = llvm.ptrtoint %ba6 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v7 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v6, %s2 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v10 = arith.constant 4 : i64 loc("std/io/core/error.lin":L:C)
    %v11 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v12 = llvm.getelementptr %s2[%v11] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v10, %v12 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs14, %v4, %s2) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v15 = llvm.load %rs14 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v16 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v17 = arith.cmpi eq, %v15, %v16 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v17, ^b4, ^b5 loc("std/io/core/error.lin":L:C)
  ^b3:
    %v107 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v108 = arith.cmpi eq, %v0, %v107 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v108, ^b17, ^b18 loc("std/io/core/error.lin":L:C)
  ^b4:
    %v28 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v29 = llvm.getelementptr %rs14[%v28] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v30 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v31 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw32 = arith.extui %v31 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw32, %s4 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v33 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw34 = llvm.load %s4 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz34 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v34 = arith.cmpi ne, %lw34, %lz34 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v34, ^b6, ^b7 loc("std/io/core/error.lin":L:C)
  ^b5:
    %v19 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v20 = llvm.getelementptr %rs14[%v19] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v21 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v21, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v24 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v25 = llvm.getelementptr %s3[%v24] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl26 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v25, %v20, %cl26) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl27 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s3, %rl27) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b6:
    %v36 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v36, ^b9, ^b10 loc("std/io/core/error.lin":L:C)
  ^b7:
    cf.br ^b8 loc("std/io/core/error.lin":L:C)
  ^b8:
    %v97 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v98 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v98, %s9 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v101 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v102 = llvm.getelementptr %s9[%v101] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v103 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl104 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s9, %rl104) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b9:
    %v38 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba40 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v40 = llvm.ptrtoint %ba40 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v41 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v40, %s5 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v44 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v45 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v46 = llvm.getelementptr %s5[%v45] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v44, %v46 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs48, %v38, %s5) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v49 = llvm.load %rs48 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v50 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v51 = arith.cmpi eq, %v49, %v50 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v51, ^b12, ^b13 loc("std/io/core/error.lin":L:C)
  ^b10:
    %v66 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba68 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v68 = llvm.ptrtoint %ba68 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v69 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v68, %s7 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v72 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v73 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v74 = llvm.getelementptr %s7[%v73] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v72, %v74 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs76, %v66, %s7) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v77 = llvm.load %rs76 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v78 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v79 = arith.cmpi eq, %v77, %v78 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v79, ^b14, ^b15 loc("std/io/core/error.lin":L:C)
  ^b11:
    %v94 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b8 loc("std/io/core/error.lin":L:C)
  ^b12:
    %v62 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v63 = llvm.getelementptr %rs48[%v62] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v64 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b11 loc("std/io/core/error.lin":L:C)
  ^b13:
    %v53 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v54 = llvm.getelementptr %rs48[%v53] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v55 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v55, %s6 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v58 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v59 = llvm.getelementptr %s6[%v58] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl60 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v59, %v54, %cl60) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl61 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s6, %rl61) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b14:
    %v90 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v91 = llvm.getelementptr %rs76[%v90] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v92 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b11 loc("std/io/core/error.lin":L:C)
  ^b15:
    %v81 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v82 = llvm.getelementptr %rs76[%v81] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v83 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v83, %s8 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v86 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v87 = llvm.getelementptr %s8[%v86] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl88 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v87, %v82, %cl88) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl89 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s8, %rl89) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b17:
    %v110 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba112 = llvm.mlir.addressof @linea_str12 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v112 = llvm.ptrtoint %ba112 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v113 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v112, %s10 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v116 = arith.constant 5 : i64 loc("std/io/core/error.lin":L:C)
    %v117 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v118 = llvm.getelementptr %s10[%v117] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v116, %v118 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs120, %v110, %s10) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v121 = llvm.load %rs120 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v122 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v123 = arith.cmpi eq, %v121, %v122 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v123, ^b19, ^b20 loc("std/io/core/error.lin":L:C)
  ^b18:
    %v213 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v214 = arith.cmpi eq, %v0, %v213 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v214, ^b32, ^b33 loc("std/io/core/error.lin":L:C)
  ^b19:
    %v134 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v135 = llvm.getelementptr %rs120[%v134] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v136 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v137 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw138 = arith.extui %v137 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw138, %s12 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v139 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw140 = llvm.load %s12 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz140 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v140 = arith.cmpi ne, %lw140, %lz140 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v140, ^b21, ^b22 loc("std/io/core/error.lin":L:C)
  ^b20:
    %v125 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v126 = llvm.getelementptr %rs120[%v125] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v127 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v127, %s11 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v130 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v131 = llvm.getelementptr %s11[%v130] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl132 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v131, %v126, %cl132) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl133 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s11, %rl133) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b21:
    %v142 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v142, ^b24, ^b25 loc("std/io/core/error.lin":L:C)
  ^b22:
    cf.br ^b23 loc("std/io/core/error.lin":L:C)
  ^b23:
    %v203 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v204 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v204, %s17 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v207 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v208 = llvm.getelementptr %s17[%v207] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v209 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl210 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s17, %rl210) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b24:
    %v144 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba146 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v146 = llvm.ptrtoint %ba146 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v147 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v146, %s13 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v150 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v151 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v152 = llvm.getelementptr %s13[%v151] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v150, %v152 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs154, %v144, %s13) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v155 = llvm.load %rs154 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v156 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v157 = arith.cmpi eq, %v155, %v156 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v157, ^b27, ^b28 loc("std/io/core/error.lin":L:C)
  ^b25:
    %v172 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba174 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v174 = llvm.ptrtoint %ba174 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v175 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v174, %s15 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v178 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v179 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v180 = llvm.getelementptr %s15[%v179] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v178, %v180 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs182, %v172, %s15) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v183 = llvm.load %rs182 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v184 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v185 = arith.cmpi eq, %v183, %v184 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v185, ^b29, ^b30 loc("std/io/core/error.lin":L:C)
  ^b26:
    %v200 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b23 loc("std/io/core/error.lin":L:C)
  ^b27:
    %v168 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v169 = llvm.getelementptr %rs154[%v168] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v170 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b26 loc("std/io/core/error.lin":L:C)
  ^b28:
    %v159 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v160 = llvm.getelementptr %rs154[%v159] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v161 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v161, %s14 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v164 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v165 = llvm.getelementptr %s14[%v164] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl166 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v165, %v160, %cl166) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl167 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s14, %rl167) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b29:
    %v196 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v197 = llvm.getelementptr %rs182[%v196] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v198 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b26 loc("std/io/core/error.lin":L:C)
  ^b30:
    %v187 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v188 = llvm.getelementptr %rs182[%v187] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v189 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v189, %s16 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v192 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v193 = llvm.getelementptr %s16[%v192] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl194 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v193, %v188, %cl194) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl195 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s16, %rl195) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b32:
    %v216 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba218 = llvm.mlir.addressof @linea_str13 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v218 = llvm.ptrtoint %ba218 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v219 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v218, %s18 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v222 = arith.constant 5 : i64 loc("std/io/core/error.lin":L:C)
    %v223 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v224 = llvm.getelementptr %s18[%v223] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v222, %v224 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs226, %v216, %s18) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v227 = llvm.load %rs226 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v228 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v229 = arith.cmpi eq, %v227, %v228 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v229, ^b34, ^b35 loc("std/io/core/error.lin":L:C)
  ^b33:
    %v319 = arith.constant 3 : i64 loc("std/io/core/error.lin":L:C)
    %v320 = arith.cmpi eq, %v0, %v319 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v320, ^b47, ^b48 loc("std/io/core/error.lin":L:C)
  ^b34:
    %v240 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v241 = llvm.getelementptr %rs226[%v240] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v242 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v243 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw244 = arith.extui %v243 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw244, %s20 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v245 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw246 = llvm.load %s20 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz246 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v246 = arith.cmpi ne, %lw246, %lz246 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v246, ^b36, ^b37 loc("std/io/core/error.lin":L:C)
  ^b35:
    %v231 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v232 = llvm.getelementptr %rs226[%v231] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v233 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v233, %s19 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v236 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v237 = llvm.getelementptr %s19[%v236] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl238 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v237, %v232, %cl238) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl239 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s19, %rl239) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b36:
    %v248 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v248, ^b39, ^b40 loc("std/io/core/error.lin":L:C)
  ^b37:
    cf.br ^b38 loc("std/io/core/error.lin":L:C)
  ^b38:
    %v309 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v310 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v310, %s25 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v313 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v314 = llvm.getelementptr %s25[%v313] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v315 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl316 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s25, %rl316) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b39:
    %v250 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba252 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v252 = llvm.ptrtoint %ba252 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v253 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v252, %s21 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v256 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v257 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v258 = llvm.getelementptr %s21[%v257] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v256, %v258 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs260, %v250, %s21) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v261 = llvm.load %rs260 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v262 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v263 = arith.cmpi eq, %v261, %v262 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v263, ^b42, ^b43 loc("std/io/core/error.lin":L:C)
  ^b40:
    %v278 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba280 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v280 = llvm.ptrtoint %ba280 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v281 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v280, %s23 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v284 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v285 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v286 = llvm.getelementptr %s23[%v285] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v284, %v286 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs288, %v278, %s23) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v289 = llvm.load %rs288 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v290 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v291 = arith.cmpi eq, %v289, %v290 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v291, ^b44, ^b45 loc("std/io/core/error.lin":L:C)
  ^b41:
    %v306 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b38 loc("std/io/core/error.lin":L:C)
  ^b42:
    %v274 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v275 = llvm.getelementptr %rs260[%v274] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v276 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b41 loc("std/io/core/error.lin":L:C)
  ^b43:
    %v265 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v266 = llvm.getelementptr %rs260[%v265] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v267 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v267, %s22 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v270 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v271 = llvm.getelementptr %s22[%v270] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl272 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v271, %v266, %cl272) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl273 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s22, %rl273) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b44:
    %v302 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v303 = llvm.getelementptr %rs288[%v302] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v304 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b41 loc("std/io/core/error.lin":L:C)
  ^b45:
    %v293 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v294 = llvm.getelementptr %rs288[%v293] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v295 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v295, %s24 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v298 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v299 = llvm.getelementptr %s24[%v298] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl300 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v299, %v294, %cl300) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl301 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s24, %rl301) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b47:
    %v322 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba324 = llvm.mlir.addressof @linea_str14 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v324 = llvm.ptrtoint %ba324 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v325 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v324, %s26 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v328 = arith.constant 5 : i64 loc("std/io/core/error.lin":L:C)
    %v329 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v330 = llvm.getelementptr %s26[%v329] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v328, %v330 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs332, %v322, %s26) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v333 = llvm.load %rs332 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v334 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v335 = arith.cmpi eq, %v333, %v334 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v335, ^b49, ^b50 loc("std/io/core/error.lin":L:C)
  ^b48:
    %v425 = arith.constant 4 : i64 loc("std/io/core/error.lin":L:C)
    %v426 = arith.cmpi eq, %v0, %v425 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v426, ^b62, ^b63 loc("std/io/core/error.lin":L:C)
  ^b49:
    %v346 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v347 = llvm.getelementptr %rs332[%v346] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v348 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v349 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw350 = arith.extui %v349 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw350, %s28 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v351 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw352 = llvm.load %s28 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz352 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v352 = arith.cmpi ne, %lw352, %lz352 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v352, ^b51, ^b52 loc("std/io/core/error.lin":L:C)
  ^b50:
    %v337 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v338 = llvm.getelementptr %rs332[%v337] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v339 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v339, %s27 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v342 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v343 = llvm.getelementptr %s27[%v342] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl344 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v343, %v338, %cl344) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl345 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s27, %rl345) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b51:
    %v354 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v354, ^b54, ^b55 loc("std/io/core/error.lin":L:C)
  ^b52:
    cf.br ^b53 loc("std/io/core/error.lin":L:C)
  ^b53:
    %v415 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v416 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v416, %s33 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v419 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v420 = llvm.getelementptr %s33[%v419] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v421 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl422 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s33, %rl422) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b54:
    %v356 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba358 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v358 = llvm.ptrtoint %ba358 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v359 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v358, %s29 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v362 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v363 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v364 = llvm.getelementptr %s29[%v363] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v362, %v364 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs366, %v356, %s29) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v367 = llvm.load %rs366 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v368 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v369 = arith.cmpi eq, %v367, %v368 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v369, ^b57, ^b58 loc("std/io/core/error.lin":L:C)
  ^b55:
    %v384 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba386 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v386 = llvm.ptrtoint %ba386 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v387 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v386, %s31 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v390 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v391 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v392 = llvm.getelementptr %s31[%v391] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v390, %v392 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs394, %v384, %s31) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v395 = llvm.load %rs394 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v396 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v397 = arith.cmpi eq, %v395, %v396 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v397, ^b59, ^b60 loc("std/io/core/error.lin":L:C)
  ^b56:
    %v412 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b53 loc("std/io/core/error.lin":L:C)
  ^b57:
    %v380 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v381 = llvm.getelementptr %rs366[%v380] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v382 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b56 loc("std/io/core/error.lin":L:C)
  ^b58:
    %v371 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v372 = llvm.getelementptr %rs366[%v371] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v373 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v373, %s30 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v376 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v377 = llvm.getelementptr %s30[%v376] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl378 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v377, %v372, %cl378) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl379 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s30, %rl379) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b59:
    %v408 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v409 = llvm.getelementptr %rs394[%v408] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v410 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b56 loc("std/io/core/error.lin":L:C)
  ^b60:
    %v399 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v400 = llvm.getelementptr %rs394[%v399] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v401 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v401, %s32 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v404 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v405 = llvm.getelementptr %s32[%v404] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl406 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v405, %v400, %cl406) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl407 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s32, %rl407) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b62:
    %v428 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba430 = llvm.mlir.addressof @linea_str15 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v430 = llvm.ptrtoint %ba430 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v431 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v430, %s34 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v434 = arith.constant 4 : i64 loc("std/io/core/error.lin":L:C)
    %v435 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v436 = llvm.getelementptr %s34[%v435] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v434, %v436 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs438, %v428, %s34) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v439 = llvm.load %rs438 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v440 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v441 = arith.cmpi eq, %v439, %v440 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v441, ^b64, ^b65 loc("std/io/core/error.lin":L:C)
  ^b63:
    %v531 = arith.constant 5 : i64 loc("std/io/core/error.lin":L:C)
    %v532 = arith.cmpi eq, %v0, %v531 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v532, ^b77, ^b78 loc("std/io/core/error.lin":L:C)
  ^b64:
    %v452 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v453 = llvm.getelementptr %rs438[%v452] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v454 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v455 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw456 = arith.extui %v455 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw456, %s36 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v457 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw458 = llvm.load %s36 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz458 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v458 = arith.cmpi ne, %lw458, %lz458 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v458, ^b66, ^b67 loc("std/io/core/error.lin":L:C)
  ^b65:
    %v443 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v444 = llvm.getelementptr %rs438[%v443] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v445 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v445, %s35 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v448 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v449 = llvm.getelementptr %s35[%v448] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl450 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v449, %v444, %cl450) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl451 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s35, %rl451) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b66:
    %v460 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v460, ^b69, ^b70 loc("std/io/core/error.lin":L:C)
  ^b67:
    cf.br ^b68 loc("std/io/core/error.lin":L:C)
  ^b68:
    %v521 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v522 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v522, %s41 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v525 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v526 = llvm.getelementptr %s41[%v525] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v527 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl528 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s41, %rl528) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b69:
    %v462 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba464 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v464 = llvm.ptrtoint %ba464 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v465 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v464, %s37 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v468 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v469 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v470 = llvm.getelementptr %s37[%v469] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v468, %v470 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs472, %v462, %s37) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v473 = llvm.load %rs472 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v474 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v475 = arith.cmpi eq, %v473, %v474 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v475, ^b72, ^b73 loc("std/io/core/error.lin":L:C)
  ^b70:
    %v490 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba492 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v492 = llvm.ptrtoint %ba492 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v493 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v492, %s39 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v496 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v497 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v498 = llvm.getelementptr %s39[%v497] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v496, %v498 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs500, %v490, %s39) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v501 = llvm.load %rs500 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v502 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v503 = arith.cmpi eq, %v501, %v502 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v503, ^b74, ^b75 loc("std/io/core/error.lin":L:C)
  ^b71:
    %v518 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b68 loc("std/io/core/error.lin":L:C)
  ^b72:
    %v486 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v487 = llvm.getelementptr %rs472[%v486] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v488 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b71 loc("std/io/core/error.lin":L:C)
  ^b73:
    %v477 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v478 = llvm.getelementptr %rs472[%v477] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v479 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v479, %s38 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v482 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v483 = llvm.getelementptr %s38[%v482] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl484 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v483, %v478, %cl484) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl485 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s38, %rl485) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b74:
    %v514 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v515 = llvm.getelementptr %rs500[%v514] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v516 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b71 loc("std/io/core/error.lin":L:C)
  ^b75:
    %v505 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v506 = llvm.getelementptr %rs500[%v505] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v507 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v507, %s40 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v510 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v511 = llvm.getelementptr %s40[%v510] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl512 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v511, %v506, %cl512) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl513 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s40, %rl513) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b77:
    %v534 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba536 = llvm.mlir.addressof @linea_str16 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v536 = llvm.ptrtoint %ba536 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v537 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v536, %s42 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v540 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v541 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v542 = llvm.getelementptr %s42[%v541] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v540, %v542 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs544, %v534, %s42) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v545 = llvm.load %rs544 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v546 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v547 = arith.cmpi eq, %v545, %v546 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v547, ^b79, ^b80 loc("std/io/core/error.lin":L:C)
  ^b78:
    %v637 = arith.constant 6 : i64 loc("std/io/core/error.lin":L:C)
    %v638 = arith.cmpi eq, %v0, %v637 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v638, ^b92, ^b93 loc("std/io/core/error.lin":L:C)
  ^b79:
    %v558 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v559 = llvm.getelementptr %rs544[%v558] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v560 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v561 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw562 = arith.extui %v561 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw562, %s44 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v563 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw564 = llvm.load %s44 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz564 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v564 = arith.cmpi ne, %lw564, %lz564 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v564, ^b81, ^b82 loc("std/io/core/error.lin":L:C)
  ^b80:
    %v549 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v550 = llvm.getelementptr %rs544[%v549] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v551 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v551, %s43 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v554 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v555 = llvm.getelementptr %s43[%v554] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl556 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v555, %v550, %cl556) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl557 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s43, %rl557) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b81:
    %v566 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v566, ^b84, ^b85 loc("std/io/core/error.lin":L:C)
  ^b82:
    cf.br ^b83 loc("std/io/core/error.lin":L:C)
  ^b83:
    %v627 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v628 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v628, %s49 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v631 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v632 = llvm.getelementptr %s49[%v631] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v633 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl634 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s49, %rl634) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b84:
    %v568 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba570 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v570 = llvm.ptrtoint %ba570 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v571 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v570, %s45 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v574 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v575 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v576 = llvm.getelementptr %s45[%v575] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v574, %v576 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs578, %v568, %s45) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v579 = llvm.load %rs578 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v580 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v581 = arith.cmpi eq, %v579, %v580 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v581, ^b87, ^b88 loc("std/io/core/error.lin":L:C)
  ^b85:
    %v596 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba598 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v598 = llvm.ptrtoint %ba598 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v599 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v598, %s47 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v602 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v603 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v604 = llvm.getelementptr %s47[%v603] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v602, %v604 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs606, %v596, %s47) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v607 = llvm.load %rs606 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v608 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v609 = arith.cmpi eq, %v607, %v608 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v609, ^b89, ^b90 loc("std/io/core/error.lin":L:C)
  ^b86:
    %v624 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b83 loc("std/io/core/error.lin":L:C)
  ^b87:
    %v592 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v593 = llvm.getelementptr %rs578[%v592] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v594 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b86 loc("std/io/core/error.lin":L:C)
  ^b88:
    %v583 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v584 = llvm.getelementptr %rs578[%v583] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v585 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v585, %s46 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v588 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v589 = llvm.getelementptr %s46[%v588] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl590 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v589, %v584, %cl590) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl591 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s46, %rl591) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b89:
    %v620 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v621 = llvm.getelementptr %rs606[%v620] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v622 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b86 loc("std/io/core/error.lin":L:C)
  ^b90:
    %v611 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v612 = llvm.getelementptr %rs606[%v611] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v613 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v613, %s48 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v616 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v617 = llvm.getelementptr %s48[%v616] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl618 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v617, %v612, %cl618) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl619 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s48, %rl619) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b92:
    %v640 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba642 = llvm.mlir.addressof @linea_str17 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v642 = llvm.ptrtoint %ba642 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v643 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v642, %s50 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v646 = arith.constant 11 : i64 loc("std/io/core/error.lin":L:C)
    %v647 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v648 = llvm.getelementptr %s50[%v647] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v646, %v648 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs650, %v640, %s50) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v651 = llvm.load %rs650 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v652 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v653 = arith.cmpi eq, %v651, %v652 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v653, ^b94, ^b95 loc("std/io/core/error.lin":L:C)
  ^b93:
    %v743 = arith.constant 7 : i64 loc("std/io/core/error.lin":L:C)
    %v744 = arith.cmpi eq, %v0, %v743 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v744, ^b107, ^b108 loc("std/io/core/error.lin":L:C)
  ^b94:
    %v664 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v665 = llvm.getelementptr %rs650[%v664] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v666 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v667 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw668 = arith.extui %v667 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw668, %s52 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v669 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw670 = llvm.load %s52 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz670 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v670 = arith.cmpi ne, %lw670, %lz670 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v670, ^b96, ^b97 loc("std/io/core/error.lin":L:C)
  ^b95:
    %v655 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v656 = llvm.getelementptr %rs650[%v655] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v657 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v657, %s51 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v660 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v661 = llvm.getelementptr %s51[%v660] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl662 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v661, %v656, %cl662) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl663 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s51, %rl663) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b96:
    %v672 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v672, ^b99, ^b100 loc("std/io/core/error.lin":L:C)
  ^b97:
    cf.br ^b98 loc("std/io/core/error.lin":L:C)
  ^b98:
    %v733 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v734 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v734, %s57 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v737 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v738 = llvm.getelementptr %s57[%v737] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v739 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl740 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s57, %rl740) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b99:
    %v674 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba676 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v676 = llvm.ptrtoint %ba676 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v677 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v676, %s53 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v680 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v681 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v682 = llvm.getelementptr %s53[%v681] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v680, %v682 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs684, %v674, %s53) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v685 = llvm.load %rs684 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v686 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v687 = arith.cmpi eq, %v685, %v686 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v687, ^b102, ^b103 loc("std/io/core/error.lin":L:C)
  ^b100:
    %v702 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba704 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v704 = llvm.ptrtoint %ba704 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v705 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v704, %s55 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v708 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v709 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v710 = llvm.getelementptr %s55[%v709] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v708, %v710 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs712, %v702, %s55) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v713 = llvm.load %rs712 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v714 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v715 = arith.cmpi eq, %v713, %v714 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v715, ^b104, ^b105 loc("std/io/core/error.lin":L:C)
  ^b101:
    %v730 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b98 loc("std/io/core/error.lin":L:C)
  ^b102:
    %v698 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v699 = llvm.getelementptr %rs684[%v698] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v700 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b101 loc("std/io/core/error.lin":L:C)
  ^b103:
    %v689 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v690 = llvm.getelementptr %rs684[%v689] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v691 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v691, %s54 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v694 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v695 = llvm.getelementptr %s54[%v694] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl696 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v695, %v690, %cl696) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl697 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s54, %rl697) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b104:
    %v726 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v727 = llvm.getelementptr %rs712[%v726] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v728 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b101 loc("std/io/core/error.lin":L:C)
  ^b105:
    %v717 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v718 = llvm.getelementptr %rs712[%v717] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v719 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v719, %s56 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v722 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v723 = llvm.getelementptr %s56[%v722] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl724 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v723, %v718, %cl724) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl725 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s56, %rl725) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b107:
    %v746 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba748 = llvm.mlir.addressof @linea_str18 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v748 = llvm.ptrtoint %ba748 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v749 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v748, %s58 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v752 = arith.constant 7 : i64 loc("std/io/core/error.lin":L:C)
    %v753 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v754 = llvm.getelementptr %s58[%v753] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v752, %v754 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs756, %v746, %s58) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v757 = llvm.load %rs756 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v758 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v759 = arith.cmpi eq, %v757, %v758 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v759, ^b109, ^b110 loc("std/io/core/error.lin":L:C)
  ^b108:
    %v849 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v850 = arith.cmpi eq, %v0, %v849 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v850, ^b122, ^b123 loc("std/io/core/error.lin":L:C)
  ^b109:
    %v770 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v771 = llvm.getelementptr %rs756[%v770] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v772 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v773 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw774 = arith.extui %v773 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw774, %s60 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v775 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw776 = llvm.load %s60 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz776 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v776 = arith.cmpi ne, %lw776, %lz776 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v776, ^b111, ^b112 loc("std/io/core/error.lin":L:C)
  ^b110:
    %v761 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v762 = llvm.getelementptr %rs756[%v761] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v763 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v763, %s59 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v766 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v767 = llvm.getelementptr %s59[%v766] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl768 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v767, %v762, %cl768) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl769 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s59, %rl769) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b111:
    %v778 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v778, ^b114, ^b115 loc("std/io/core/error.lin":L:C)
  ^b112:
    cf.br ^b113 loc("std/io/core/error.lin":L:C)
  ^b113:
    %v839 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v840 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v840, %s65 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v843 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v844 = llvm.getelementptr %s65[%v843] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v845 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl846 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s65, %rl846) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b114:
    %v780 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba782 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v782 = llvm.ptrtoint %ba782 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v783 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v782, %s61 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v786 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v787 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v788 = llvm.getelementptr %s61[%v787] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v786, %v788 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs790, %v780, %s61) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v791 = llvm.load %rs790 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v792 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v793 = arith.cmpi eq, %v791, %v792 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v793, ^b117, ^b118 loc("std/io/core/error.lin":L:C)
  ^b115:
    %v808 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba810 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v810 = llvm.ptrtoint %ba810 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v811 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v810, %s63 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v814 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v815 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v816 = llvm.getelementptr %s63[%v815] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v814, %v816 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs818, %v808, %s63) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v819 = llvm.load %rs818 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v820 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v821 = arith.cmpi eq, %v819, %v820 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v821, ^b119, ^b120 loc("std/io/core/error.lin":L:C)
  ^b116:
    %v836 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b113 loc("std/io/core/error.lin":L:C)
  ^b117:
    %v804 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v805 = llvm.getelementptr %rs790[%v804] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v806 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b116 loc("std/io/core/error.lin":L:C)
  ^b118:
    %v795 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v796 = llvm.getelementptr %rs790[%v795] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v797 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v797, %s62 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v800 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v801 = llvm.getelementptr %s62[%v800] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl802 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v801, %v796, %cl802) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl803 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s62, %rl803) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b119:
    %v832 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v833 = llvm.getelementptr %rs818[%v832] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v834 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b116 loc("std/io/core/error.lin":L:C)
  ^b120:
    %v823 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v824 = llvm.getelementptr %rs818[%v823] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v825 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v825, %s64 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v828 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v829 = llvm.getelementptr %s64[%v828] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl830 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v829, %v824, %cl830) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl831 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s64, %rl831) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b122:
    %v852 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba854 = llvm.mlir.addressof @linea_str19 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v854 = llvm.ptrtoint %ba854 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v855 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v854, %s66 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v858 = arith.constant 6 : i64 loc("std/io/core/error.lin":L:C)
    %v859 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v860 = llvm.getelementptr %s66[%v859] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v858, %v860 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs862, %v852, %s66) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v863 = llvm.load %rs862 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v864 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v865 = arith.cmpi eq, %v863, %v864 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v865, ^b124, ^b125 loc("std/io/core/error.lin":L:C)
  ^b123:
    %v955 = arith.constant 9 : i64 loc("std/io/core/error.lin":L:C)
    %v956 = arith.cmpi eq, %v0, %v955 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v956, ^b137, ^b138 loc("std/io/core/error.lin":L:C)
  ^b124:
    %v876 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v877 = llvm.getelementptr %rs862[%v876] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v878 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v879 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw880 = arith.extui %v879 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw880, %s68 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v881 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw882 = llvm.load %s68 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz882 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v882 = arith.cmpi ne, %lw882, %lz882 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v882, ^b126, ^b127 loc("std/io/core/error.lin":L:C)
  ^b125:
    %v867 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v868 = llvm.getelementptr %rs862[%v867] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v869 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v869, %s67 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v872 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v873 = llvm.getelementptr %s67[%v872] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl874 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v873, %v868, %cl874) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl875 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s67, %rl875) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b126:
    %v884 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v884, ^b129, ^b130 loc("std/io/core/error.lin":L:C)
  ^b127:
    cf.br ^b128 loc("std/io/core/error.lin":L:C)
  ^b128:
    %v945 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v946 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v946, %s73 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v949 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v950 = llvm.getelementptr %s73[%v949] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v951 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl952 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s73, %rl952) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b129:
    %v886 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba888 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v888 = llvm.ptrtoint %ba888 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v889 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v888, %s69 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v892 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v893 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v894 = llvm.getelementptr %s69[%v893] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v892, %v894 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs896, %v886, %s69) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v897 = llvm.load %rs896 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v898 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v899 = arith.cmpi eq, %v897, %v898 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v899, ^b132, ^b133 loc("std/io/core/error.lin":L:C)
  ^b130:
    %v914 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba916 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v916 = llvm.ptrtoint %ba916 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v917 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v916, %s71 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v920 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v921 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v922 = llvm.getelementptr %s71[%v921] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v920, %v922 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs924, %v914, %s71) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v925 = llvm.load %rs924 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v926 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v927 = arith.cmpi eq, %v925, %v926 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v927, ^b134, ^b135 loc("std/io/core/error.lin":L:C)
  ^b131:
    %v942 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b128 loc("std/io/core/error.lin":L:C)
  ^b132:
    %v910 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v911 = llvm.getelementptr %rs896[%v910] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v912 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b131 loc("std/io/core/error.lin":L:C)
  ^b133:
    %v901 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v902 = llvm.getelementptr %rs896[%v901] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v903 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v903, %s70 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v906 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v907 = llvm.getelementptr %s70[%v906] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl908 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v907, %v902, %cl908) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl909 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s70, %rl909) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b134:
    %v938 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v939 = llvm.getelementptr %rs924[%v938] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v940 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b131 loc("std/io/core/error.lin":L:C)
  ^b135:
    %v929 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v930 = llvm.getelementptr %rs924[%v929] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v931 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v931, %s72 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v934 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v935 = llvm.getelementptr %s72[%v934] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl936 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v935, %v930, %cl936) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl937 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s72, %rl937) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b137:
    %v958 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba960 = llvm.mlir.addressof @linea_str20 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v960 = llvm.ptrtoint %ba960 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v961 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v960, %s74 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v964 = arith.constant 6 : i64 loc("std/io/core/error.lin":L:C)
    %v965 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v966 = llvm.getelementptr %s74[%v965] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v964, %v966 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs968, %v958, %s74) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v969 = llvm.load %rs968 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v970 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v971 = arith.cmpi eq, %v969, %v970 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v971, ^b139, ^b140 loc("std/io/core/error.lin":L:C)
  ^b138:
    %v1061 = arith.constant 10 : i64 loc("std/io/core/error.lin":L:C)
    %v1062 = arith.cmpi eq, %v0, %v1061 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1062, ^b152, ^b153 loc("std/io/core/error.lin":L:C)
  ^b139:
    %v982 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v983 = llvm.getelementptr %rs968[%v982] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v984 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v985 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw986 = arith.extui %v985 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw986, %s76 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v987 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw988 = llvm.load %s76 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz988 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v988 = arith.cmpi ne, %lw988, %lz988 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v988, ^b141, ^b142 loc("std/io/core/error.lin":L:C)
  ^b140:
    %v973 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v974 = llvm.getelementptr %rs968[%v973] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v975 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v975, %s75 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v978 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v979 = llvm.getelementptr %s75[%v978] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl980 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v979, %v974, %cl980) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl981 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s75, %rl981) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b141:
    %v990 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v990, ^b144, ^b145 loc("std/io/core/error.lin":L:C)
  ^b142:
    cf.br ^b143 loc("std/io/core/error.lin":L:C)
  ^b143:
    %v1051 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1052 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1052, %s81 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1055 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1056 = llvm.getelementptr %s81[%v1055] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1057 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl1058 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s81, %rl1058) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b144:
    %v992 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba994 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v994 = llvm.ptrtoint %ba994 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v995 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v994, %s77 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v998 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v999 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1000 = llvm.getelementptr %s77[%v999] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v998, %v1000 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1002, %v992, %s77) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1003 = llvm.load %rs1002 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1004 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1005 = arith.cmpi eq, %v1003, %v1004 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1005, ^b147, ^b148 loc("std/io/core/error.lin":L:C)
  ^b145:
    %v1020 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1022 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1022 = llvm.ptrtoint %ba1022 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1023 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1022, %s79 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1026 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v1027 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1028 = llvm.getelementptr %s79[%v1027] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1026, %v1028 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1030, %v1020, %s79) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1031 = llvm.load %rs1030 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1032 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1033 = arith.cmpi eq, %v1031, %v1032 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1033, ^b149, ^b150 loc("std/io/core/error.lin":L:C)
  ^b146:
    %v1048 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b143 loc("std/io/core/error.lin":L:C)
  ^b147:
    %v1016 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1017 = llvm.getelementptr %rs1002[%v1016] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1018 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b146 loc("std/io/core/error.lin":L:C)
  ^b148:
    %v1007 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1008 = llvm.getelementptr %rs1002[%v1007] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1009 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1009, %s78 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1012 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1013 = llvm.getelementptr %s78[%v1012] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1014 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1013, %v1008, %cl1014) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1015 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s78, %rl1015) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b149:
    %v1044 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1045 = llvm.getelementptr %rs1030[%v1044] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1046 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b146 loc("std/io/core/error.lin":L:C)
  ^b150:
    %v1035 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1036 = llvm.getelementptr %rs1030[%v1035] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1037 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1037, %s80 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1040 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1041 = llvm.getelementptr %s80[%v1040] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1042 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1041, %v1036, %cl1042) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1043 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s80, %rl1043) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b152:
    %v1064 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1066 = llvm.mlir.addressof @linea_str21 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1066 = llvm.ptrtoint %ba1066 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1067 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1066, %s82 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1070 = arith.constant 6 : i64 loc("std/io/core/error.lin":L:C)
    %v1071 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1072 = llvm.getelementptr %s82[%v1071] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1070, %v1072 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1074, %v1064, %s82) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1075 = llvm.load %rs1074 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1076 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1077 = arith.cmpi eq, %v1075, %v1076 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1077, ^b154, ^b155 loc("std/io/core/error.lin":L:C)
  ^b153:
    %v1167 = arith.constant 11 : i64 loc("std/io/core/error.lin":L:C)
    %v1168 = arith.cmpi eq, %v0, %v1167 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1168, ^b167, ^b168 loc("std/io/core/error.lin":L:C)
  ^b154:
    %v1088 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1089 = llvm.getelementptr %rs1074[%v1088] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1090 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1091 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw1092 = arith.extui %v1091 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw1092, %s84 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1093 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw1094 = llvm.load %s84 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz1094 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v1094 = arith.cmpi ne, %lw1094, %lz1094 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1094, ^b156, ^b157 loc("std/io/core/error.lin":L:C)
  ^b155:
    %v1079 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1080 = llvm.getelementptr %rs1074[%v1079] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1081 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1081, %s83 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1084 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1085 = llvm.getelementptr %s83[%v1084] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1086 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1085, %v1080, %cl1086) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1087 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s83, %rl1087) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b156:
    %v1096 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1096, ^b159, ^b160 loc("std/io/core/error.lin":L:C)
  ^b157:
    cf.br ^b158 loc("std/io/core/error.lin":L:C)
  ^b158:
    %v1157 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1158 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1158, %s89 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1161 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1162 = llvm.getelementptr %s89[%v1161] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1163 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl1164 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s89, %rl1164) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b159:
    %v1098 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1100 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1100 = llvm.ptrtoint %ba1100 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1101 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1100, %s85 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1104 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v1105 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1106 = llvm.getelementptr %s85[%v1105] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1104, %v1106 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1108, %v1098, %s85) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1109 = llvm.load %rs1108 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1110 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1111 = arith.cmpi eq, %v1109, %v1110 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1111, ^b162, ^b163 loc("std/io/core/error.lin":L:C)
  ^b160:
    %v1126 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1128 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1128 = llvm.ptrtoint %ba1128 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1129 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1128, %s87 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1132 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v1133 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1134 = llvm.getelementptr %s87[%v1133] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1132, %v1134 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1136, %v1126, %s87) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1137 = llvm.load %rs1136 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1138 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1139 = arith.cmpi eq, %v1137, %v1138 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1139, ^b164, ^b165 loc("std/io/core/error.lin":L:C)
  ^b161:
    %v1154 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b158 loc("std/io/core/error.lin":L:C)
  ^b162:
    %v1122 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1123 = llvm.getelementptr %rs1108[%v1122] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1124 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b161 loc("std/io/core/error.lin":L:C)
  ^b163:
    %v1113 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1114 = llvm.getelementptr %rs1108[%v1113] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1115 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1115, %s86 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1118 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1119 = llvm.getelementptr %s86[%v1118] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1120 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1119, %v1114, %cl1120) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1121 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s86, %rl1121) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b164:
    %v1150 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1151 = llvm.getelementptr %rs1136[%v1150] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1152 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b161 loc("std/io/core/error.lin":L:C)
  ^b165:
    %v1141 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1142 = llvm.getelementptr %rs1136[%v1141] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1143 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1143, %s88 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1146 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1147 = llvm.getelementptr %s88[%v1146] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1148 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1147, %v1142, %cl1148) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1149 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s88, %rl1149) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b167:
    %v1170 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1172 = llvm.mlir.addressof @linea_str22 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1172 = llvm.ptrtoint %ba1172 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1173 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1172, %s90 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1176 = arith.constant 6 : i64 loc("std/io/core/error.lin":L:C)
    %v1177 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1178 = llvm.getelementptr %s90[%v1177] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1176, %v1178 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1180, %v1170, %s90) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1181 = llvm.load %rs1180 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1182 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1183 = arith.cmpi eq, %v1181, %v1182 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1183, ^b169, ^b170 loc("std/io/core/error.lin":L:C)
  ^b168:
    %v1273 = arith.constant 12 : i64 loc("std/io/core/error.lin":L:C)
    %v1274 = arith.cmpi eq, %v0, %v1273 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1274, ^b182, ^b183 loc("std/io/core/error.lin":L:C)
  ^b169:
    %v1194 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1195 = llvm.getelementptr %rs1180[%v1194] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1196 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1197 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw1198 = arith.extui %v1197 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw1198, %s92 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1199 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw1200 = llvm.load %s92 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz1200 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v1200 = arith.cmpi ne, %lw1200, %lz1200 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1200, ^b171, ^b172 loc("std/io/core/error.lin":L:C)
  ^b170:
    %v1185 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1186 = llvm.getelementptr %rs1180[%v1185] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1187 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1187, %s91 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1190 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1191 = llvm.getelementptr %s91[%v1190] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1192 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1191, %v1186, %cl1192) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1193 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s91, %rl1193) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b171:
    %v1202 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1202, ^b174, ^b175 loc("std/io/core/error.lin":L:C)
  ^b172:
    cf.br ^b173 loc("std/io/core/error.lin":L:C)
  ^b173:
    %v1263 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1264 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1264, %s97 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1267 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1268 = llvm.getelementptr %s97[%v1267] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1269 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl1270 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s97, %rl1270) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b174:
    %v1204 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1206 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1206 = llvm.ptrtoint %ba1206 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1207 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1206, %s93 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1210 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v1211 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1212 = llvm.getelementptr %s93[%v1211] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1210, %v1212 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1214, %v1204, %s93) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1215 = llvm.load %rs1214 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1216 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1217 = arith.cmpi eq, %v1215, %v1216 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1217, ^b177, ^b178 loc("std/io/core/error.lin":L:C)
  ^b175:
    %v1232 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1234 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1234 = llvm.ptrtoint %ba1234 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1235 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1234, %s95 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1238 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v1239 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1240 = llvm.getelementptr %s95[%v1239] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1238, %v1240 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1242, %v1232, %s95) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1243 = llvm.load %rs1242 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1244 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1245 = arith.cmpi eq, %v1243, %v1244 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1245, ^b179, ^b180 loc("std/io/core/error.lin":L:C)
  ^b176:
    %v1260 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b173 loc("std/io/core/error.lin":L:C)
  ^b177:
    %v1228 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1229 = llvm.getelementptr %rs1214[%v1228] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1230 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b176 loc("std/io/core/error.lin":L:C)
  ^b178:
    %v1219 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1220 = llvm.getelementptr %rs1214[%v1219] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1221 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1221, %s94 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1224 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1225 = llvm.getelementptr %s94[%v1224] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1226 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1225, %v1220, %cl1226) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1227 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s94, %rl1227) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b179:
    %v1256 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1257 = llvm.getelementptr %rs1242[%v1256] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1258 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b176 loc("std/io/core/error.lin":L:C)
  ^b180:
    %v1247 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1248 = llvm.getelementptr %rs1242[%v1247] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1249 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1249, %s96 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1252 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1253 = llvm.getelementptr %s96[%v1252] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1254 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1253, %v1248, %cl1254) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1255 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s96, %rl1255) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b182:
    %v1276 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1278 = llvm.mlir.addressof @linea_str23 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1278 = llvm.ptrtoint %ba1278 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1279 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1278, %s98 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1282 = arith.constant 7 : i64 loc("std/io/core/error.lin":L:C)
    %v1283 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1284 = llvm.getelementptr %s98[%v1283] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1282, %v1284 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1286, %v1276, %s98) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1287 = llvm.load %rs1286 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1288 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1289 = arith.cmpi eq, %v1287, %v1288 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1289, ^b184, ^b185 loc("std/io/core/error.lin":L:C)
  ^b183:
    %v1379 = arith.constant 13 : i64 loc("std/io/core/error.lin":L:C)
    %v1380 = arith.cmpi eq, %v0, %v1379 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1380, ^b197, ^b198 loc("std/io/core/error.lin":L:C)
  ^b184:
    %v1300 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1301 = llvm.getelementptr %rs1286[%v1300] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1302 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1303 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw1304 = arith.extui %v1303 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw1304, %s100 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1305 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw1306 = llvm.load %s100 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz1306 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v1306 = arith.cmpi ne, %lw1306, %lz1306 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1306, ^b186, ^b187 loc("std/io/core/error.lin":L:C)
  ^b185:
    %v1291 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1292 = llvm.getelementptr %rs1286[%v1291] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1293 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1293, %s99 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1296 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1297 = llvm.getelementptr %s99[%v1296] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1298 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1297, %v1292, %cl1298) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1299 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s99, %rl1299) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b186:
    %v1308 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1308, ^b189, ^b190 loc("std/io/core/error.lin":L:C)
  ^b187:
    cf.br ^b188 loc("std/io/core/error.lin":L:C)
  ^b188:
    %v1369 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1370 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1370, %s105 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1373 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1374 = llvm.getelementptr %s105[%v1373] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1375 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl1376 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s105, %rl1376) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b189:
    %v1310 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1312 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1312 = llvm.ptrtoint %ba1312 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1313 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1312, %s101 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1316 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v1317 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1318 = llvm.getelementptr %s101[%v1317] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1316, %v1318 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1320, %v1310, %s101) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1321 = llvm.load %rs1320 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1322 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1323 = arith.cmpi eq, %v1321, %v1322 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1323, ^b192, ^b193 loc("std/io/core/error.lin":L:C)
  ^b190:
    %v1338 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1340 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1340 = llvm.ptrtoint %ba1340 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1341 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1340, %s103 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1344 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v1345 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1346 = llvm.getelementptr %s103[%v1345] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1344, %v1346 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1348, %v1338, %s103) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1349 = llvm.load %rs1348 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1350 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1351 = arith.cmpi eq, %v1349, %v1350 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1351, ^b194, ^b195 loc("std/io/core/error.lin":L:C)
  ^b191:
    %v1366 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b188 loc("std/io/core/error.lin":L:C)
  ^b192:
    %v1334 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1335 = llvm.getelementptr %rs1320[%v1334] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1336 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b191 loc("std/io/core/error.lin":L:C)
  ^b193:
    %v1325 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1326 = llvm.getelementptr %rs1320[%v1325] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1327 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1327, %s102 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1330 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1331 = llvm.getelementptr %s102[%v1330] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1332 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1331, %v1326, %cl1332) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1333 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s102, %rl1333) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b194:
    %v1362 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1363 = llvm.getelementptr %rs1348[%v1362] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1364 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b191 loc("std/io/core/error.lin":L:C)
  ^b195:
    %v1353 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1354 = llvm.getelementptr %rs1348[%v1353] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1355 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1355, %s104 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1358 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1359 = llvm.getelementptr %s104[%v1358] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1360 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1359, %v1354, %cl1360) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1361 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s104, %rl1361) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b197:
    %v1382 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1384 = llvm.mlir.addressof @linea_str24 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1384 = llvm.ptrtoint %ba1384 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1385 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1384, %s106 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1388 = arith.constant 9 : i64 loc("std/io/core/error.lin":L:C)
    %v1389 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1390 = llvm.getelementptr %s106[%v1389] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1388, %v1390 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1392, %v1382, %s106) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1393 = llvm.load %rs1392 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1394 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1395 = arith.cmpi eq, %v1393, %v1394 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1395, ^b199, ^b200 loc("std/io/core/error.lin":L:C)
  ^b198:
    %tk1 = arith.constant 3 : i32 loc("std/io/core/error.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file7 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/io/core/error.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/io/core/error.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/io/core/error.lin":L:C)
    llvm.unreachable loc("std/io/core/error.lin":L:C)
  ^b199:
    %v1406 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1407 = llvm.getelementptr %rs1392[%v1406] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1408 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1409 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw1410 = arith.extui %v1409 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw1410, %s108 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1411 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw1412 = llvm.load %s108 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz1412 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v1412 = arith.cmpi ne, %lw1412, %lz1412 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1412, ^b201, ^b202 loc("std/io/core/error.lin":L:C)
  ^b200:
    %v1397 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1398 = llvm.getelementptr %rs1392[%v1397] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1399 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1399, %s107 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1402 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1403 = llvm.getelementptr %s107[%v1402] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1404 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1403, %v1398, %cl1404) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1405 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s107, %rl1405) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b201:
    %v1414 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1414, ^b204, ^b205 loc("std/io/core/error.lin":L:C)
  ^b202:
    cf.br ^b203 loc("std/io/core/error.lin":L:C)
  ^b203:
    %v1475 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1476 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1476, %s113 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1479 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1480 = llvm.getelementptr %s113[%v1479] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1481 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl1482 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s113, %rl1482) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b204:
    %v1416 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1418 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1418 = llvm.ptrtoint %ba1418 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1419 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1418, %s109 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1422 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v1423 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1424 = llvm.getelementptr %s109[%v1423] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1422, %v1424 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1426, %v1416, %s109) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1427 = llvm.load %rs1426 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1428 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1429 = arith.cmpi eq, %v1427, %v1428 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1429, ^b207, ^b208 loc("std/io/core/error.lin":L:C)
  ^b205:
    %v1444 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1446 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1446 = llvm.ptrtoint %ba1446 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1447 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1446, %s111 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1450 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v1451 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1452 = llvm.getelementptr %s111[%v1451] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1450, %v1452 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1454, %v1444, %s111) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1455 = llvm.load %rs1454 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1456 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1457 = arith.cmpi eq, %v1455, %v1456 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1457, ^b209, ^b210 loc("std/io/core/error.lin":L:C)
  ^b206:
    %v1472 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b203 loc("std/io/core/error.lin":L:C)
  ^b207:
    %v1440 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1441 = llvm.getelementptr %rs1426[%v1440] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1442 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b206 loc("std/io/core/error.lin":L:C)
  ^b208:
    %v1431 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1432 = llvm.getelementptr %rs1426[%v1431] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1433 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1433, %s110 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1436 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1437 = llvm.getelementptr %s110[%v1436] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1438 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1437, %v1432, %cl1438) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1439 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s110, %rl1439) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b209:
    %v1468 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1469 = llvm.getelementptr %rs1454[%v1468] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1470 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b206 loc("std/io/core/error.lin":L:C)
  ^b210:
    %v1459 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1460 = llvm.getelementptr %rs1454[%v1459] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1461 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1461, %s112 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1464 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1465 = llvm.getelementptr %s112[%v1464] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1466 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1465, %v1460, %cl1466) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1467 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s112, %rl1467) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  }
  func.func private @"lin.std.io.core.IoCategory;std.fmt;Display.fmt[std.io.core.Descriptor]"(%sret: !llvm.ptr, %a0: i64, %a1: !llvm.ptr) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 16 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 48 : i64
    %s3 = llvm.alloca %z3 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z4 = arith.constant 1 : i64
    %s4 = llvm.alloca %z4 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z5 = arith.constant 16 : i64
    %s5 = llvm.alloca %z5 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z6 = arith.constant 48 : i64
    %s6 = llvm.alloca %z6 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z7 = arith.constant 16 : i64
    %s7 = llvm.alloca %z7 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z8 = arith.constant 48 : i64
    %s8 = llvm.alloca %z8 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z9 = arith.constant 48 : i64
    %s9 = llvm.alloca %z9 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z10 = arith.constant 16 : i64
    %s10 = llvm.alloca %z10 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z11 = arith.constant 48 : i64
    %s11 = llvm.alloca %z11 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z12 = arith.constant 1 : i64
    %s12 = llvm.alloca %z12 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z13 = arith.constant 16 : i64
    %s13 = llvm.alloca %z13 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z14 = arith.constant 48 : i64
    %s14 = llvm.alloca %z14 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z15 = arith.constant 16 : i64
    %s15 = llvm.alloca %z15 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z16 = arith.constant 48 : i64
    %s16 = llvm.alloca %z16 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z17 = arith.constant 48 : i64
    %s17 = llvm.alloca %z17 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z18 = arith.constant 16 : i64
    %s18 = llvm.alloca %z18 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z19 = arith.constant 48 : i64
    %s19 = llvm.alloca %z19 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z20 = arith.constant 1 : i64
    %s20 = llvm.alloca %z20 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z21 = arith.constant 16 : i64
    %s21 = llvm.alloca %z21 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z22 = arith.constant 48 : i64
    %s22 = llvm.alloca %z22 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z23 = arith.constant 16 : i64
    %s23 = llvm.alloca %z23 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z24 = arith.constant 48 : i64
    %s24 = llvm.alloca %z24 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z25 = arith.constant 48 : i64
    %s25 = llvm.alloca %z25 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z26 = arith.constant 16 : i64
    %s26 = llvm.alloca %z26 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z27 = arith.constant 48 : i64
    %s27 = llvm.alloca %z27 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z28 = arith.constant 1 : i64
    %s28 = llvm.alloca %z28 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z29 = arith.constant 16 : i64
    %s29 = llvm.alloca %z29 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z30 = arith.constant 48 : i64
    %s30 = llvm.alloca %z30 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z31 = arith.constant 16 : i64
    %s31 = llvm.alloca %z31 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z32 = arith.constant 48 : i64
    %s32 = llvm.alloca %z32 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z33 = arith.constant 48 : i64
    %s33 = llvm.alloca %z33 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z34 = arith.constant 16 : i64
    %s34 = llvm.alloca %z34 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z35 = arith.constant 48 : i64
    %s35 = llvm.alloca %z35 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z36 = arith.constant 1 : i64
    %s36 = llvm.alloca %z36 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z37 = arith.constant 16 : i64
    %s37 = llvm.alloca %z37 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z38 = arith.constant 48 : i64
    %s38 = llvm.alloca %z38 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z39 = arith.constant 16 : i64
    %s39 = llvm.alloca %z39 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z40 = arith.constant 48 : i64
    %s40 = llvm.alloca %z40 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z41 = arith.constant 48 : i64
    %s41 = llvm.alloca %z41 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z42 = arith.constant 16 : i64
    %s42 = llvm.alloca %z42 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z43 = arith.constant 48 : i64
    %s43 = llvm.alloca %z43 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z44 = arith.constant 1 : i64
    %s44 = llvm.alloca %z44 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z45 = arith.constant 16 : i64
    %s45 = llvm.alloca %z45 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z46 = arith.constant 48 : i64
    %s46 = llvm.alloca %z46 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z47 = arith.constant 16 : i64
    %s47 = llvm.alloca %z47 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z48 = arith.constant 48 : i64
    %s48 = llvm.alloca %z48 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z49 = arith.constant 48 : i64
    %s49 = llvm.alloca %z49 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z50 = arith.constant 16 : i64
    %s50 = llvm.alloca %z50 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z51 = arith.constant 48 : i64
    %s51 = llvm.alloca %z51 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z52 = arith.constant 1 : i64
    %s52 = llvm.alloca %z52 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z53 = arith.constant 16 : i64
    %s53 = llvm.alloca %z53 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z54 = arith.constant 48 : i64
    %s54 = llvm.alloca %z54 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z55 = arith.constant 16 : i64
    %s55 = llvm.alloca %z55 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z56 = arith.constant 48 : i64
    %s56 = llvm.alloca %z56 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z57 = arith.constant 48 : i64
    %s57 = llvm.alloca %z57 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z58 = arith.constant 16 : i64
    %s58 = llvm.alloca %z58 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z59 = arith.constant 48 : i64
    %s59 = llvm.alloca %z59 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z60 = arith.constant 1 : i64
    %s60 = llvm.alloca %z60 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z61 = arith.constant 16 : i64
    %s61 = llvm.alloca %z61 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z62 = arith.constant 48 : i64
    %s62 = llvm.alloca %z62 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z63 = arith.constant 16 : i64
    %s63 = llvm.alloca %z63 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z64 = arith.constant 48 : i64
    %s64 = llvm.alloca %z64 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z65 = arith.constant 48 : i64
    %s65 = llvm.alloca %z65 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z66 = arith.constant 16 : i64
    %s66 = llvm.alloca %z66 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z67 = arith.constant 48 : i64
    %s67 = llvm.alloca %z67 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z68 = arith.constant 1 : i64
    %s68 = llvm.alloca %z68 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z69 = arith.constant 16 : i64
    %s69 = llvm.alloca %z69 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z70 = arith.constant 48 : i64
    %s70 = llvm.alloca %z70 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z71 = arith.constant 16 : i64
    %s71 = llvm.alloca %z71 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z72 = arith.constant 48 : i64
    %s72 = llvm.alloca %z72 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z73 = arith.constant 48 : i64
    %s73 = llvm.alloca %z73 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z74 = arith.constant 16 : i64
    %s74 = llvm.alloca %z74 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z75 = arith.constant 48 : i64
    %s75 = llvm.alloca %z75 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z76 = arith.constant 1 : i64
    %s76 = llvm.alloca %z76 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z77 = arith.constant 16 : i64
    %s77 = llvm.alloca %z77 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z78 = arith.constant 48 : i64
    %s78 = llvm.alloca %z78 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z79 = arith.constant 16 : i64
    %s79 = llvm.alloca %z79 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z80 = arith.constant 48 : i64
    %s80 = llvm.alloca %z80 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z81 = arith.constant 48 : i64
    %s81 = llvm.alloca %z81 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z82 = arith.constant 16 : i64
    %s82 = llvm.alloca %z82 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z83 = arith.constant 48 : i64
    %s83 = llvm.alloca %z83 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z84 = arith.constant 1 : i64
    %s84 = llvm.alloca %z84 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z85 = arith.constant 16 : i64
    %s85 = llvm.alloca %z85 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z86 = arith.constant 48 : i64
    %s86 = llvm.alloca %z86 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z87 = arith.constant 16 : i64
    %s87 = llvm.alloca %z87 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z88 = arith.constant 48 : i64
    %s88 = llvm.alloca %z88 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z89 = arith.constant 48 : i64
    %s89 = llvm.alloca %z89 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z90 = arith.constant 16 : i64
    %s90 = llvm.alloca %z90 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z91 = arith.constant 48 : i64
    %s91 = llvm.alloca %z91 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z92 = arith.constant 1 : i64
    %s92 = llvm.alloca %z92 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z93 = arith.constant 16 : i64
    %s93 = llvm.alloca %z93 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z94 = arith.constant 48 : i64
    %s94 = llvm.alloca %z94 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z95 = arith.constant 16 : i64
    %s95 = llvm.alloca %z95 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z96 = arith.constant 48 : i64
    %s96 = llvm.alloca %z96 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z97 = arith.constant 48 : i64
    %s97 = llvm.alloca %z97 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z98 = arith.constant 16 : i64
    %s98 = llvm.alloca %z98 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z99 = arith.constant 48 : i64
    %s99 = llvm.alloca %z99 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z100 = arith.constant 1 : i64
    %s100 = llvm.alloca %z100 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z101 = arith.constant 16 : i64
    %s101 = llvm.alloca %z101 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z102 = arith.constant 48 : i64
    %s102 = llvm.alloca %z102 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z103 = arith.constant 16 : i64
    %s103 = llvm.alloca %z103 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z104 = arith.constant 48 : i64
    %s104 = llvm.alloca %z104 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z105 = arith.constant 48 : i64
    %s105 = llvm.alloca %z105 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z106 = arith.constant 16 : i64
    %s106 = llvm.alloca %z106 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z107 = arith.constant 48 : i64
    %s107 = llvm.alloca %z107 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z108 = arith.constant 1 : i64
    %s108 = llvm.alloca %z108 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z109 = arith.constant 16 : i64
    %s109 = llvm.alloca %z109 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z110 = arith.constant 48 : i64
    %s110 = llvm.alloca %z110 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z111 = arith.constant 16 : i64
    %s111 = llvm.alloca %z111 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z112 = arith.constant 48 : i64
    %s112 = llvm.alloca %z112 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z113 = arith.constant 48 : i64
    %s113 = llvm.alloca %z113 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z114 = arith.constant 16 : i64
    %s114 = llvm.alloca %z114 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z115 = arith.constant 48 : i64
    %s115 = llvm.alloca %z115 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z116 = arith.constant 1 : i64
    %s116 = llvm.alloca %z116 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z117 = arith.constant 16 : i64
    %s117 = llvm.alloca %z117 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z118 = arith.constant 48 : i64
    %s118 = llvm.alloca %z118 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z119 = arith.constant 16 : i64
    %s119 = llvm.alloca %z119 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z120 = arith.constant 48 : i64
    %s120 = llvm.alloca %z120 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z121 = arith.constant 48 : i64
    %s121 = llvm.alloca %z121 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z122 = arith.constant 16 : i64
    %s122 = llvm.alloca %z122 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z123 = arith.constant 48 : i64
    %s123 = llvm.alloca %z123 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z124 = arith.constant 1 : i64
    %s124 = llvm.alloca %z124 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z125 = arith.constant 16 : i64
    %s125 = llvm.alloca %z125 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z126 = arith.constant 48 : i64
    %s126 = llvm.alloca %z126 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z127 = arith.constant 16 : i64
    %s127 = llvm.alloca %z127 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z128 = arith.constant 48 : i64
    %s128 = llvm.alloca %z128 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z129 = arith.constant 48 : i64
    %s129 = llvm.alloca %z129 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z130 = arith.constant 16 : i64
    %s130 = llvm.alloca %z130 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z131 = arith.constant 48 : i64
    %s131 = llvm.alloca %z131 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z132 = arith.constant 1 : i64
    %s132 = llvm.alloca %z132 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z133 = arith.constant 16 : i64
    %s133 = llvm.alloca %z133 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z134 = arith.constant 48 : i64
    %s134 = llvm.alloca %z134 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z135 = arith.constant 16 : i64
    %s135 = llvm.alloca %z135 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z136 = arith.constant 48 : i64
    %s136 = llvm.alloca %z136 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z137 = arith.constant 48 : i64
    %s137 = llvm.alloca %z137 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z138 = arith.constant 16 : i64
    %s138 = llvm.alloca %z138 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z139 = arith.constant 48 : i64
    %s139 = llvm.alloca %z139 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z140 = arith.constant 1 : i64
    %s140 = llvm.alloca %z140 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z141 = arith.constant 16 : i64
    %s141 = llvm.alloca %z141 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z142 = arith.constant 48 : i64
    %s142 = llvm.alloca %z142 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z143 = arith.constant 16 : i64
    %s143 = llvm.alloca %z143 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z144 = arith.constant 48 : i64
    %s144 = llvm.alloca %z144 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z145 = arith.constant 48 : i64
    %s145 = llvm.alloca %z145 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z146 = arith.constant 16 : i64
    %s146 = llvm.alloca %z146 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z147 = arith.constant 48 : i64
    %s147 = llvm.alloca %z147 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z148 = arith.constant 1 : i64
    %s148 = llvm.alloca %z148 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z149 = arith.constant 16 : i64
    %s149 = llvm.alloca %z149 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z150 = arith.constant 48 : i64
    %s150 = llvm.alloca %z150 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z151 = arith.constant 16 : i64
    %s151 = llvm.alloca %z151 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z152 = arith.constant 48 : i64
    %s152 = llvm.alloca %z152 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z153 = arith.constant 48 : i64
    %s153 = llvm.alloca %z153 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z154 = arith.constant 16 : i64
    %s154 = llvm.alloca %z154 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z155 = arith.constant 48 : i64
    %s155 = llvm.alloca %z155 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z156 = arith.constant 1 : i64
    %s156 = llvm.alloca %z156 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z157 = arith.constant 16 : i64
    %s157 = llvm.alloca %z157 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z158 = arith.constant 48 : i64
    %s158 = llvm.alloca %z158 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z159 = arith.constant 16 : i64
    %s159 = llvm.alloca %z159 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z160 = arith.constant 48 : i64
    %s160 = llvm.alloca %z160 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z161 = arith.constant 48 : i64
    %s161 = llvm.alloca %z161 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z162 = arith.constant 16 : i64
    %s162 = llvm.alloca %z162 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z163 = arith.constant 48 : i64
    %s163 = llvm.alloca %z163 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z164 = arith.constant 1 : i64
    %s164 = llvm.alloca %z164 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z165 = arith.constant 16 : i64
    %s165 = llvm.alloca %z165 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z166 = arith.constant 48 : i64
    %s166 = llvm.alloca %z166 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z167 = arith.constant 16 : i64
    %s167 = llvm.alloca %z167 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z168 = arith.constant 48 : i64
    %s168 = llvm.alloca %z168 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z169 = arith.constant 48 : i64
    %s169 = llvm.alloca %z169 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : i64, !llvm.ptr
    llvm.store %a1, %s1 : !llvm.ptr, !llvm.ptr
    %rz14 = arith.constant 48 : i64
    %rs14 = llvm.alloca %rz14 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz48 = arith.constant 48 : i64
    %rs48 = llvm.alloca %rz48 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz76 = arith.constant 48 : i64
    %rs76 = llvm.alloca %rz76 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz120 = arith.constant 48 : i64
    %rs120 = llvm.alloca %rz120 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz154 = arith.constant 48 : i64
    %rs154 = llvm.alloca %rz154 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz182 = arith.constant 48 : i64
    %rs182 = llvm.alloca %rz182 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz226 = arith.constant 48 : i64
    %rs226 = llvm.alloca %rz226 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz260 = arith.constant 48 : i64
    %rs260 = llvm.alloca %rz260 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz288 = arith.constant 48 : i64
    %rs288 = llvm.alloca %rz288 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz332 = arith.constant 48 : i64
    %rs332 = llvm.alloca %rz332 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz366 = arith.constant 48 : i64
    %rs366 = llvm.alloca %rz366 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz394 = arith.constant 48 : i64
    %rs394 = llvm.alloca %rz394 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz438 = arith.constant 48 : i64
    %rs438 = llvm.alloca %rz438 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz472 = arith.constant 48 : i64
    %rs472 = llvm.alloca %rz472 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz500 = arith.constant 48 : i64
    %rs500 = llvm.alloca %rz500 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz544 = arith.constant 48 : i64
    %rs544 = llvm.alloca %rz544 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz578 = arith.constant 48 : i64
    %rs578 = llvm.alloca %rz578 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz606 = arith.constant 48 : i64
    %rs606 = llvm.alloca %rz606 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz650 = arith.constant 48 : i64
    %rs650 = llvm.alloca %rz650 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz684 = arith.constant 48 : i64
    %rs684 = llvm.alloca %rz684 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz712 = arith.constant 48 : i64
    %rs712 = llvm.alloca %rz712 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz756 = arith.constant 48 : i64
    %rs756 = llvm.alloca %rz756 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz790 = arith.constant 48 : i64
    %rs790 = llvm.alloca %rz790 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz818 = arith.constant 48 : i64
    %rs818 = llvm.alloca %rz818 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz862 = arith.constant 48 : i64
    %rs862 = llvm.alloca %rz862 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz896 = arith.constant 48 : i64
    %rs896 = llvm.alloca %rz896 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz924 = arith.constant 48 : i64
    %rs924 = llvm.alloca %rz924 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz968 = arith.constant 48 : i64
    %rs968 = llvm.alloca %rz968 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1002 = arith.constant 48 : i64
    %rs1002 = llvm.alloca %rz1002 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1030 = arith.constant 48 : i64
    %rs1030 = llvm.alloca %rz1030 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1074 = arith.constant 48 : i64
    %rs1074 = llvm.alloca %rz1074 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1108 = arith.constant 48 : i64
    %rs1108 = llvm.alloca %rz1108 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1136 = arith.constant 48 : i64
    %rs1136 = llvm.alloca %rz1136 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1180 = arith.constant 48 : i64
    %rs1180 = llvm.alloca %rz1180 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1214 = arith.constant 48 : i64
    %rs1214 = llvm.alloca %rz1214 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1242 = arith.constant 48 : i64
    %rs1242 = llvm.alloca %rz1242 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1286 = arith.constant 48 : i64
    %rs1286 = llvm.alloca %rz1286 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1320 = arith.constant 48 : i64
    %rs1320 = llvm.alloca %rz1320 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1348 = arith.constant 48 : i64
    %rs1348 = llvm.alloca %rz1348 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1392 = arith.constant 48 : i64
    %rs1392 = llvm.alloca %rz1392 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1426 = arith.constant 48 : i64
    %rs1426 = llvm.alloca %rz1426 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1454 = arith.constant 48 : i64
    %rs1454 = llvm.alloca %rz1454 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1498 = arith.constant 48 : i64
    %rs1498 = llvm.alloca %rz1498 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1532 = arith.constant 48 : i64
    %rs1532 = llvm.alloca %rz1532 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1560 = arith.constant 48 : i64
    %rs1560 = llvm.alloca %rz1560 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1604 = arith.constant 48 : i64
    %rs1604 = llvm.alloca %rz1604 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1638 = arith.constant 48 : i64
    %rs1638 = llvm.alloca %rz1638 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1666 = arith.constant 48 : i64
    %rs1666 = llvm.alloca %rz1666 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1710 = arith.constant 48 : i64
    %rs1710 = llvm.alloca %rz1710 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1744 = arith.constant 48 : i64
    %rs1744 = llvm.alloca %rz1744 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1772 = arith.constant 48 : i64
    %rs1772 = llvm.alloca %rz1772 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1816 = arith.constant 48 : i64
    %rs1816 = llvm.alloca %rz1816 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1850 = arith.constant 48 : i64
    %rs1850 = llvm.alloca %rz1850 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1878 = arith.constant 48 : i64
    %rs1878 = llvm.alloca %rz1878 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1922 = arith.constant 48 : i64
    %rs1922 = llvm.alloca %rz1922 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1956 = arith.constant 48 : i64
    %rs1956 = llvm.alloca %rz1956 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz1984 = arith.constant 48 : i64
    %rs1984 = llvm.alloca %rz1984 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz2028 = arith.constant 48 : i64
    %rs2028 = llvm.alloca %rz2028 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz2062 = arith.constant 48 : i64
    %rs2062 = llvm.alloca %rz2062 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz2090 = arith.constant 48 : i64
    %rs2090 = llvm.alloca %rz2090 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz2134 = arith.constant 48 : i64
    %rs2134 = llvm.alloca %rz2134 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz2168 = arith.constant 48 : i64
    %rs2168 = llvm.alloca %rz2168 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz2196 = arith.constant 48 : i64
    %rs2196 = llvm.alloca %rz2196 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v2 = arith.cmpi eq, %v0, %v1 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v2, ^b2, ^b3 loc("std/io/core/error.lin":L:C)
  ^b2:
    %v4 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba6 = llvm.mlir.addressof @linea_str25 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v6 = llvm.ptrtoint %ba6 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v7 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v6, %s2 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v10 = arith.constant 5 : i64 loc("std/io/core/error.lin":L:C)
    %v11 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v12 = llvm.getelementptr %s2[%v11] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v10, %v12 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs14, %v4, %s2) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v15 = llvm.load %rs14 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v16 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v17 = arith.cmpi eq, %v15, %v16 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v17, ^b4, ^b5 loc("std/io/core/error.lin":L:C)
  ^b3:
    %v107 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v108 = arith.cmpi eq, %v0, %v107 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v108, ^b17, ^b18 loc("std/io/core/error.lin":L:C)
  ^b4:
    %v28 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v29 = llvm.getelementptr %rs14[%v28] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v30 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v31 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw32 = arith.extui %v31 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw32, %s4 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v33 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw34 = llvm.load %s4 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz34 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v34 = arith.cmpi ne, %lw34, %lz34 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v34, ^b6, ^b7 loc("std/io/core/error.lin":L:C)
  ^b5:
    %v19 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v20 = llvm.getelementptr %rs14[%v19] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v21 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v21, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v24 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v25 = llvm.getelementptr %s3[%v24] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl26 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v25, %v20, %cl26) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl27 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s3, %rl27) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b6:
    %v36 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v36, ^b9, ^b10 loc("std/io/core/error.lin":L:C)
  ^b7:
    cf.br ^b8 loc("std/io/core/error.lin":L:C)
  ^b8:
    %v97 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v98 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v98, %s9 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v101 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v102 = llvm.getelementptr %s9[%v101] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v103 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl104 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s9, %rl104) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b9:
    %v38 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba40 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v40 = llvm.ptrtoint %ba40 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v41 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v40, %s5 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v44 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v45 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v46 = llvm.getelementptr %s5[%v45] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v44, %v46 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs48, %v38, %s5) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v49 = llvm.load %rs48 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v50 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v51 = arith.cmpi eq, %v49, %v50 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v51, ^b12, ^b13 loc("std/io/core/error.lin":L:C)
  ^b10:
    %v66 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba68 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v68 = llvm.ptrtoint %ba68 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v69 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v68, %s7 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v72 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v73 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v74 = llvm.getelementptr %s7[%v73] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v72, %v74 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs76, %v66, %s7) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v77 = llvm.load %rs76 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v78 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v79 = arith.cmpi eq, %v77, %v78 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v79, ^b14, ^b15 loc("std/io/core/error.lin":L:C)
  ^b11:
    %v94 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b8 loc("std/io/core/error.lin":L:C)
  ^b12:
    %v62 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v63 = llvm.getelementptr %rs48[%v62] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v64 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b11 loc("std/io/core/error.lin":L:C)
  ^b13:
    %v53 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v54 = llvm.getelementptr %rs48[%v53] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v55 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v55, %s6 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v58 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v59 = llvm.getelementptr %s6[%v58] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl60 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v59, %v54, %cl60) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl61 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s6, %rl61) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b14:
    %v90 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v91 = llvm.getelementptr %rs76[%v90] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v92 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b11 loc("std/io/core/error.lin":L:C)
  ^b15:
    %v81 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v82 = llvm.getelementptr %rs76[%v81] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v83 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v83, %s8 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v86 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v87 = llvm.getelementptr %s8[%v86] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl88 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v87, %v82, %cl88) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl89 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s8, %rl89) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b17:
    %v110 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba112 = llvm.mlir.addressof @linea_str26 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v112 = llvm.ptrtoint %ba112 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v113 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v112, %s10 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v116 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v117 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v118 = llvm.getelementptr %s10[%v117] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v116, %v118 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs120, %v110, %s10) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v121 = llvm.load %rs120 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v122 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v123 = arith.cmpi eq, %v121, %v122 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v123, ^b19, ^b20 loc("std/io/core/error.lin":L:C)
  ^b18:
    %v213 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v214 = arith.cmpi eq, %v0, %v213 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v214, ^b32, ^b33 loc("std/io/core/error.lin":L:C)
  ^b19:
    %v134 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v135 = llvm.getelementptr %rs120[%v134] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v136 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v137 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw138 = arith.extui %v137 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw138, %s12 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v139 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw140 = llvm.load %s12 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz140 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v140 = arith.cmpi ne, %lw140, %lz140 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v140, ^b21, ^b22 loc("std/io/core/error.lin":L:C)
  ^b20:
    %v125 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v126 = llvm.getelementptr %rs120[%v125] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v127 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v127, %s11 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v130 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v131 = llvm.getelementptr %s11[%v130] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl132 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v131, %v126, %cl132) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl133 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s11, %rl133) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b21:
    %v142 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v142, ^b24, ^b25 loc("std/io/core/error.lin":L:C)
  ^b22:
    cf.br ^b23 loc("std/io/core/error.lin":L:C)
  ^b23:
    %v203 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v204 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v204, %s17 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v207 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v208 = llvm.getelementptr %s17[%v207] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v209 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl210 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s17, %rl210) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b24:
    %v144 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba146 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v146 = llvm.ptrtoint %ba146 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v147 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v146, %s13 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v150 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v151 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v152 = llvm.getelementptr %s13[%v151] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v150, %v152 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs154, %v144, %s13) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v155 = llvm.load %rs154 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v156 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v157 = arith.cmpi eq, %v155, %v156 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v157, ^b27, ^b28 loc("std/io/core/error.lin":L:C)
  ^b25:
    %v172 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba174 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v174 = llvm.ptrtoint %ba174 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v175 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v174, %s15 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v178 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v179 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v180 = llvm.getelementptr %s15[%v179] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v178, %v180 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs182, %v172, %s15) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v183 = llvm.load %rs182 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v184 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v185 = arith.cmpi eq, %v183, %v184 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v185, ^b29, ^b30 loc("std/io/core/error.lin":L:C)
  ^b26:
    %v200 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b23 loc("std/io/core/error.lin":L:C)
  ^b27:
    %v168 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v169 = llvm.getelementptr %rs154[%v168] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v170 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b26 loc("std/io/core/error.lin":L:C)
  ^b28:
    %v159 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v160 = llvm.getelementptr %rs154[%v159] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v161 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v161, %s14 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v164 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v165 = llvm.getelementptr %s14[%v164] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl166 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v165, %v160, %cl166) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl167 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s14, %rl167) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b29:
    %v196 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v197 = llvm.getelementptr %rs182[%v196] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v198 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b26 loc("std/io/core/error.lin":L:C)
  ^b30:
    %v187 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v188 = llvm.getelementptr %rs182[%v187] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v189 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v189, %s16 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v192 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v193 = llvm.getelementptr %s16[%v192] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl194 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v193, %v188, %cl194) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl195 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s16, %rl195) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b32:
    %v216 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba218 = llvm.mlir.addressof @linea_str27 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v218 = llvm.ptrtoint %ba218 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v219 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v218, %s18 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v222 = arith.constant 16 : i64 loc("std/io/core/error.lin":L:C)
    %v223 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v224 = llvm.getelementptr %s18[%v223] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v222, %v224 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs226, %v216, %s18) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v227 = llvm.load %rs226 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v228 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v229 = arith.cmpi eq, %v227, %v228 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v229, ^b34, ^b35 loc("std/io/core/error.lin":L:C)
  ^b33:
    %v319 = arith.constant 3 : i64 loc("std/io/core/error.lin":L:C)
    %v320 = arith.cmpi eq, %v0, %v319 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v320, ^b47, ^b48 loc("std/io/core/error.lin":L:C)
  ^b34:
    %v240 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v241 = llvm.getelementptr %rs226[%v240] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v242 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v243 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw244 = arith.extui %v243 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw244, %s20 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v245 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw246 = llvm.load %s20 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz246 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v246 = arith.cmpi ne, %lw246, %lz246 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v246, ^b36, ^b37 loc("std/io/core/error.lin":L:C)
  ^b35:
    %v231 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v232 = llvm.getelementptr %rs226[%v231] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v233 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v233, %s19 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v236 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v237 = llvm.getelementptr %s19[%v236] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl238 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v237, %v232, %cl238) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl239 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s19, %rl239) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b36:
    %v248 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v248, ^b39, ^b40 loc("std/io/core/error.lin":L:C)
  ^b37:
    cf.br ^b38 loc("std/io/core/error.lin":L:C)
  ^b38:
    %v309 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v310 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v310, %s25 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v313 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v314 = llvm.getelementptr %s25[%v313] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v315 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl316 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s25, %rl316) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b39:
    %v250 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba252 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v252 = llvm.ptrtoint %ba252 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v253 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v252, %s21 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v256 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v257 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v258 = llvm.getelementptr %s21[%v257] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v256, %v258 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs260, %v250, %s21) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v261 = llvm.load %rs260 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v262 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v263 = arith.cmpi eq, %v261, %v262 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v263, ^b42, ^b43 loc("std/io/core/error.lin":L:C)
  ^b40:
    %v278 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba280 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v280 = llvm.ptrtoint %ba280 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v281 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v280, %s23 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v284 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v285 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v286 = llvm.getelementptr %s23[%v285] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v284, %v286 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs288, %v278, %s23) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v289 = llvm.load %rs288 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v290 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v291 = arith.cmpi eq, %v289, %v290 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v291, ^b44, ^b45 loc("std/io/core/error.lin":L:C)
  ^b41:
    %v306 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b38 loc("std/io/core/error.lin":L:C)
  ^b42:
    %v274 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v275 = llvm.getelementptr %rs260[%v274] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v276 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b41 loc("std/io/core/error.lin":L:C)
  ^b43:
    %v265 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v266 = llvm.getelementptr %rs260[%v265] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v267 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v267, %s22 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v270 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v271 = llvm.getelementptr %s22[%v270] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl272 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v271, %v266, %cl272) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl273 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s22, %rl273) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b44:
    %v302 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v303 = llvm.getelementptr %rs288[%v302] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v304 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b41 loc("std/io/core/error.lin":L:C)
  ^b45:
    %v293 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v294 = llvm.getelementptr %rs288[%v293] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v295 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v295, %s24 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v298 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v299 = llvm.getelementptr %s24[%v298] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl300 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v299, %v294, %cl300) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl301 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s24, %rl301) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b47:
    %v322 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba324 = llvm.mlir.addressof @linea_str28 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v324 = llvm.ptrtoint %ba324 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v325 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v324, %s26 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v328 = arith.constant 13 : i64 loc("std/io/core/error.lin":L:C)
    %v329 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v330 = llvm.getelementptr %s26[%v329] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v328, %v330 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs332, %v322, %s26) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v333 = llvm.load %rs332 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v334 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v335 = arith.cmpi eq, %v333, %v334 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v335, ^b49, ^b50 loc("std/io/core/error.lin":L:C)
  ^b48:
    %v425 = arith.constant 4 : i64 loc("std/io/core/error.lin":L:C)
    %v426 = arith.cmpi eq, %v0, %v425 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v426, ^b62, ^b63 loc("std/io/core/error.lin":L:C)
  ^b49:
    %v346 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v347 = llvm.getelementptr %rs332[%v346] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v348 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v349 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw350 = arith.extui %v349 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw350, %s28 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v351 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw352 = llvm.load %s28 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz352 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v352 = arith.cmpi ne, %lw352, %lz352 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v352, ^b51, ^b52 loc("std/io/core/error.lin":L:C)
  ^b50:
    %v337 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v338 = llvm.getelementptr %rs332[%v337] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v339 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v339, %s27 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v342 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v343 = llvm.getelementptr %s27[%v342] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl344 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v343, %v338, %cl344) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl345 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s27, %rl345) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b51:
    %v354 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v354, ^b54, ^b55 loc("std/io/core/error.lin":L:C)
  ^b52:
    cf.br ^b53 loc("std/io/core/error.lin":L:C)
  ^b53:
    %v415 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v416 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v416, %s33 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v419 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v420 = llvm.getelementptr %s33[%v419] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v421 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl422 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s33, %rl422) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b54:
    %v356 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba358 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v358 = llvm.ptrtoint %ba358 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v359 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v358, %s29 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v362 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v363 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v364 = llvm.getelementptr %s29[%v363] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v362, %v364 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs366, %v356, %s29) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v367 = llvm.load %rs366 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v368 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v369 = arith.cmpi eq, %v367, %v368 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v369, ^b57, ^b58 loc("std/io/core/error.lin":L:C)
  ^b55:
    %v384 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba386 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v386 = llvm.ptrtoint %ba386 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v387 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v386, %s31 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v390 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v391 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v392 = llvm.getelementptr %s31[%v391] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v390, %v392 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs394, %v384, %s31) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v395 = llvm.load %rs394 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v396 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v397 = arith.cmpi eq, %v395, %v396 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v397, ^b59, ^b60 loc("std/io/core/error.lin":L:C)
  ^b56:
    %v412 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b53 loc("std/io/core/error.lin":L:C)
  ^b57:
    %v380 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v381 = llvm.getelementptr %rs366[%v380] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v382 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b56 loc("std/io/core/error.lin":L:C)
  ^b58:
    %v371 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v372 = llvm.getelementptr %rs366[%v371] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v373 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v373, %s30 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v376 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v377 = llvm.getelementptr %s30[%v376] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl378 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v377, %v372, %cl378) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl379 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s30, %rl379) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b59:
    %v408 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v409 = llvm.getelementptr %rs394[%v408] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v410 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b56 loc("std/io/core/error.lin":L:C)
  ^b60:
    %v399 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v400 = llvm.getelementptr %rs394[%v399] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v401 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v401, %s32 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v404 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v405 = llvm.getelementptr %s32[%v404] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl406 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v405, %v400, %cl406) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl407 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s32, %rl407) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b62:
    %v428 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba430 = llvm.mlir.addressof @linea_str29 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v430 = llvm.ptrtoint %ba430 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v431 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v430, %s34 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v434 = arith.constant 10 : i64 loc("std/io/core/error.lin":L:C)
    %v435 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v436 = llvm.getelementptr %s34[%v435] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v434, %v436 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs438, %v428, %s34) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v439 = llvm.load %rs438 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v440 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v441 = arith.cmpi eq, %v439, %v440 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v441, ^b64, ^b65 loc("std/io/core/error.lin":L:C)
  ^b63:
    %v531 = arith.constant 5 : i64 loc("std/io/core/error.lin":L:C)
    %v532 = arith.cmpi eq, %v0, %v531 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v532, ^b77, ^b78 loc("std/io/core/error.lin":L:C)
  ^b64:
    %v452 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v453 = llvm.getelementptr %rs438[%v452] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v454 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v455 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw456 = arith.extui %v455 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw456, %s36 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v457 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw458 = llvm.load %s36 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz458 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v458 = arith.cmpi ne, %lw458, %lz458 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v458, ^b66, ^b67 loc("std/io/core/error.lin":L:C)
  ^b65:
    %v443 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v444 = llvm.getelementptr %rs438[%v443] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v445 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v445, %s35 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v448 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v449 = llvm.getelementptr %s35[%v448] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl450 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v449, %v444, %cl450) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl451 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s35, %rl451) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b66:
    %v460 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v460, ^b69, ^b70 loc("std/io/core/error.lin":L:C)
  ^b67:
    cf.br ^b68 loc("std/io/core/error.lin":L:C)
  ^b68:
    %v521 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v522 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v522, %s41 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v525 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v526 = llvm.getelementptr %s41[%v525] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v527 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl528 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s41, %rl528) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b69:
    %v462 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba464 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v464 = llvm.ptrtoint %ba464 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v465 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v464, %s37 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v468 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v469 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v470 = llvm.getelementptr %s37[%v469] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v468, %v470 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs472, %v462, %s37) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v473 = llvm.load %rs472 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v474 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v475 = arith.cmpi eq, %v473, %v474 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v475, ^b72, ^b73 loc("std/io/core/error.lin":L:C)
  ^b70:
    %v490 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba492 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v492 = llvm.ptrtoint %ba492 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v493 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v492, %s39 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v496 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v497 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v498 = llvm.getelementptr %s39[%v497] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v496, %v498 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs500, %v490, %s39) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v501 = llvm.load %rs500 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v502 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v503 = arith.cmpi eq, %v501, %v502 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v503, ^b74, ^b75 loc("std/io/core/error.lin":L:C)
  ^b71:
    %v518 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b68 loc("std/io/core/error.lin":L:C)
  ^b72:
    %v486 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v487 = llvm.getelementptr %rs472[%v486] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v488 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b71 loc("std/io/core/error.lin":L:C)
  ^b73:
    %v477 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v478 = llvm.getelementptr %rs472[%v477] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v479 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v479, %s38 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v482 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v483 = llvm.getelementptr %s38[%v482] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl484 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v483, %v478, %cl484) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl485 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s38, %rl485) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b74:
    %v514 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v515 = llvm.getelementptr %rs500[%v514] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v516 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b71 loc("std/io/core/error.lin":L:C)
  ^b75:
    %v505 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v506 = llvm.getelementptr %rs500[%v505] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v507 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v507, %s40 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v510 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v511 = llvm.getelementptr %s40[%v510] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl512 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v511, %v506, %cl512) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl513 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s40, %rl513) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b77:
    %v534 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba536 = llvm.mlir.addressof @linea_str30 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v536 = llvm.ptrtoint %ba536 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v537 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v536, %s42 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v540 = arith.constant 10 : i64 loc("std/io/core/error.lin":L:C)
    %v541 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v542 = llvm.getelementptr %s42[%v541] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v540, %v542 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs544, %v534, %s42) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v545 = llvm.load %rs544 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v546 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v547 = arith.cmpi eq, %v545, %v546 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v547, ^b79, ^b80 loc("std/io/core/error.lin":L:C)
  ^b78:
    %v637 = arith.constant 6 : i64 loc("std/io/core/error.lin":L:C)
    %v638 = arith.cmpi eq, %v0, %v637 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v638, ^b92, ^b93 loc("std/io/core/error.lin":L:C)
  ^b79:
    %v558 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v559 = llvm.getelementptr %rs544[%v558] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v560 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v561 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw562 = arith.extui %v561 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw562, %s44 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v563 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw564 = llvm.load %s44 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz564 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v564 = arith.cmpi ne, %lw564, %lz564 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v564, ^b81, ^b82 loc("std/io/core/error.lin":L:C)
  ^b80:
    %v549 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v550 = llvm.getelementptr %rs544[%v549] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v551 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v551, %s43 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v554 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v555 = llvm.getelementptr %s43[%v554] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl556 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v555, %v550, %cl556) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl557 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s43, %rl557) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b81:
    %v566 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v566, ^b84, ^b85 loc("std/io/core/error.lin":L:C)
  ^b82:
    cf.br ^b83 loc("std/io/core/error.lin":L:C)
  ^b83:
    %v627 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v628 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v628, %s49 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v631 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v632 = llvm.getelementptr %s49[%v631] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v633 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl634 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s49, %rl634) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b84:
    %v568 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba570 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v570 = llvm.ptrtoint %ba570 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v571 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v570, %s45 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v574 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v575 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v576 = llvm.getelementptr %s45[%v575] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v574, %v576 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs578, %v568, %s45) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v579 = llvm.load %rs578 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v580 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v581 = arith.cmpi eq, %v579, %v580 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v581, ^b87, ^b88 loc("std/io/core/error.lin":L:C)
  ^b85:
    %v596 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba598 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v598 = llvm.ptrtoint %ba598 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v599 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v598, %s47 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v602 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v603 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v604 = llvm.getelementptr %s47[%v603] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v602, %v604 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs606, %v596, %s47) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v607 = llvm.load %rs606 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v608 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v609 = arith.cmpi eq, %v607, %v608 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v609, ^b89, ^b90 loc("std/io/core/error.lin":L:C)
  ^b86:
    %v624 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b83 loc("std/io/core/error.lin":L:C)
  ^b87:
    %v592 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v593 = llvm.getelementptr %rs578[%v592] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v594 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b86 loc("std/io/core/error.lin":L:C)
  ^b88:
    %v583 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v584 = llvm.getelementptr %rs578[%v583] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v585 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v585, %s46 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v588 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v589 = llvm.getelementptr %s46[%v588] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl590 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v589, %v584, %cl590) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl591 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s46, %rl591) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b89:
    %v620 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v621 = llvm.getelementptr %rs606[%v620] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v622 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b86 loc("std/io/core/error.lin":L:C)
  ^b90:
    %v611 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v612 = llvm.getelementptr %rs606[%v611] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v613 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v613, %s48 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v616 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v617 = llvm.getelementptr %s48[%v616] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl618 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v617, %v612, %cl618) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl619 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s48, %rl619) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b92:
    %v640 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba642 = llvm.mlir.addressof @linea_str31 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v642 = llvm.ptrtoint %ba642 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v643 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v642, %s50 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v646 = arith.constant 11 : i64 loc("std/io/core/error.lin":L:C)
    %v647 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v648 = llvm.getelementptr %s50[%v647] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v646, %v648 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs650, %v640, %s50) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v651 = llvm.load %rs650 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v652 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v653 = arith.cmpi eq, %v651, %v652 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v653, ^b94, ^b95 loc("std/io/core/error.lin":L:C)
  ^b93:
    %v743 = arith.constant 7 : i64 loc("std/io/core/error.lin":L:C)
    %v744 = arith.cmpi eq, %v0, %v743 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v744, ^b107, ^b108 loc("std/io/core/error.lin":L:C)
  ^b94:
    %v664 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v665 = llvm.getelementptr %rs650[%v664] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v666 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v667 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw668 = arith.extui %v667 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw668, %s52 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v669 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw670 = llvm.load %s52 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz670 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v670 = arith.cmpi ne, %lw670, %lz670 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v670, ^b96, ^b97 loc("std/io/core/error.lin":L:C)
  ^b95:
    %v655 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v656 = llvm.getelementptr %rs650[%v655] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v657 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v657, %s51 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v660 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v661 = llvm.getelementptr %s51[%v660] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl662 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v661, %v656, %cl662) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl663 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s51, %rl663) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b96:
    %v672 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v672, ^b99, ^b100 loc("std/io/core/error.lin":L:C)
  ^b97:
    cf.br ^b98 loc("std/io/core/error.lin":L:C)
  ^b98:
    %v733 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v734 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v734, %s57 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v737 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v738 = llvm.getelementptr %s57[%v737] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v739 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl740 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s57, %rl740) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b99:
    %v674 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba676 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v676 = llvm.ptrtoint %ba676 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v677 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v676, %s53 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v680 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v681 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v682 = llvm.getelementptr %s53[%v681] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v680, %v682 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs684, %v674, %s53) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v685 = llvm.load %rs684 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v686 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v687 = arith.cmpi eq, %v685, %v686 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v687, ^b102, ^b103 loc("std/io/core/error.lin":L:C)
  ^b100:
    %v702 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba704 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v704 = llvm.ptrtoint %ba704 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v705 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v704, %s55 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v708 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v709 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v710 = llvm.getelementptr %s55[%v709] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v708, %v710 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs712, %v702, %s55) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v713 = llvm.load %rs712 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v714 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v715 = arith.cmpi eq, %v713, %v714 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v715, ^b104, ^b105 loc("std/io/core/error.lin":L:C)
  ^b101:
    %v730 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b98 loc("std/io/core/error.lin":L:C)
  ^b102:
    %v698 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v699 = llvm.getelementptr %rs684[%v698] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v700 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b101 loc("std/io/core/error.lin":L:C)
  ^b103:
    %v689 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v690 = llvm.getelementptr %rs684[%v689] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v691 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v691, %s54 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v694 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v695 = llvm.getelementptr %s54[%v694] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl696 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v695, %v690, %cl696) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl697 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s54, %rl697) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b104:
    %v726 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v727 = llvm.getelementptr %rs712[%v726] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v728 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b101 loc("std/io/core/error.lin":L:C)
  ^b105:
    %v717 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v718 = llvm.getelementptr %rs712[%v717] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v719 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v719, %s56 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v722 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v723 = llvm.getelementptr %s56[%v722] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl724 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v723, %v718, %cl724) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl725 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s56, %rl725) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b107:
    %v746 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba748 = llvm.mlir.addressof @linea_str32 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v748 = llvm.ptrtoint %ba748 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v749 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v748, %s58 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v752 = arith.constant 12 : i64 loc("std/io/core/error.lin":L:C)
    %v753 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v754 = llvm.getelementptr %s58[%v753] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v752, %v754 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs756, %v746, %s58) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v757 = llvm.load %rs756 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v758 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v759 = arith.cmpi eq, %v757, %v758 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v759, ^b109, ^b110 loc("std/io/core/error.lin":L:C)
  ^b108:
    %v849 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v850 = arith.cmpi eq, %v0, %v849 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v850, ^b122, ^b123 loc("std/io/core/error.lin":L:C)
  ^b109:
    %v770 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v771 = llvm.getelementptr %rs756[%v770] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v772 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v773 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw774 = arith.extui %v773 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw774, %s60 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v775 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw776 = llvm.load %s60 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz776 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v776 = arith.cmpi ne, %lw776, %lz776 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v776, ^b111, ^b112 loc("std/io/core/error.lin":L:C)
  ^b110:
    %v761 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v762 = llvm.getelementptr %rs756[%v761] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v763 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v763, %s59 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v766 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v767 = llvm.getelementptr %s59[%v766] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl768 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v767, %v762, %cl768) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl769 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s59, %rl769) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b111:
    %v778 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v778, ^b114, ^b115 loc("std/io/core/error.lin":L:C)
  ^b112:
    cf.br ^b113 loc("std/io/core/error.lin":L:C)
  ^b113:
    %v839 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v840 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v840, %s65 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v843 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v844 = llvm.getelementptr %s65[%v843] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v845 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl846 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s65, %rl846) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b114:
    %v780 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba782 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v782 = llvm.ptrtoint %ba782 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v783 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v782, %s61 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v786 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v787 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v788 = llvm.getelementptr %s61[%v787] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v786, %v788 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs790, %v780, %s61) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v791 = llvm.load %rs790 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v792 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v793 = arith.cmpi eq, %v791, %v792 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v793, ^b117, ^b118 loc("std/io/core/error.lin":L:C)
  ^b115:
    %v808 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba810 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v810 = llvm.ptrtoint %ba810 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v811 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v810, %s63 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v814 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v815 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v816 = llvm.getelementptr %s63[%v815] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v814, %v816 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs818, %v808, %s63) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v819 = llvm.load %rs818 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v820 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v821 = arith.cmpi eq, %v819, %v820 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v821, ^b119, ^b120 loc("std/io/core/error.lin":L:C)
  ^b116:
    %v836 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b113 loc("std/io/core/error.lin":L:C)
  ^b117:
    %v804 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v805 = llvm.getelementptr %rs790[%v804] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v806 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b116 loc("std/io/core/error.lin":L:C)
  ^b118:
    %v795 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v796 = llvm.getelementptr %rs790[%v795] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v797 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v797, %s62 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v800 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v801 = llvm.getelementptr %s62[%v800] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl802 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v801, %v796, %cl802) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl803 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s62, %rl803) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b119:
    %v832 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v833 = llvm.getelementptr %rs818[%v832] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v834 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b116 loc("std/io/core/error.lin":L:C)
  ^b120:
    %v823 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v824 = llvm.getelementptr %rs818[%v823] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v825 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v825, %s64 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v828 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v829 = llvm.getelementptr %s64[%v828] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl830 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v829, %v824, %cl830) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl831 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s64, %rl831) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b122:
    %v852 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba854 = llvm.mlir.addressof @linea_str33 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v854 = llvm.ptrtoint %ba854 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v855 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v854, %s66 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v858 = arith.constant 12 : i64 loc("std/io/core/error.lin":L:C)
    %v859 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v860 = llvm.getelementptr %s66[%v859] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v858, %v860 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs862, %v852, %s66) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v863 = llvm.load %rs862 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v864 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v865 = arith.cmpi eq, %v863, %v864 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v865, ^b124, ^b125 loc("std/io/core/error.lin":L:C)
  ^b123:
    %v955 = arith.constant 9 : i64 loc("std/io/core/error.lin":L:C)
    %v956 = arith.cmpi eq, %v0, %v955 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v956, ^b137, ^b138 loc("std/io/core/error.lin":L:C)
  ^b124:
    %v876 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v877 = llvm.getelementptr %rs862[%v876] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v878 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v879 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw880 = arith.extui %v879 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw880, %s68 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v881 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw882 = llvm.load %s68 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz882 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v882 = arith.cmpi ne, %lw882, %lz882 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v882, ^b126, ^b127 loc("std/io/core/error.lin":L:C)
  ^b125:
    %v867 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v868 = llvm.getelementptr %rs862[%v867] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v869 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v869, %s67 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v872 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v873 = llvm.getelementptr %s67[%v872] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl874 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v873, %v868, %cl874) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl875 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s67, %rl875) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b126:
    %v884 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v884, ^b129, ^b130 loc("std/io/core/error.lin":L:C)
  ^b127:
    cf.br ^b128 loc("std/io/core/error.lin":L:C)
  ^b128:
    %v945 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v946 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v946, %s73 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v949 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v950 = llvm.getelementptr %s73[%v949] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v951 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl952 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s73, %rl952) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b129:
    %v886 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba888 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v888 = llvm.ptrtoint %ba888 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v889 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v888, %s69 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v892 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v893 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v894 = llvm.getelementptr %s69[%v893] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v892, %v894 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs896, %v886, %s69) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v897 = llvm.load %rs896 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v898 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v899 = arith.cmpi eq, %v897, %v898 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v899, ^b132, ^b133 loc("std/io/core/error.lin":L:C)
  ^b130:
    %v914 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba916 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v916 = llvm.ptrtoint %ba916 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v917 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v916, %s71 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v920 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v921 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v922 = llvm.getelementptr %s71[%v921] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v920, %v922 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs924, %v914, %s71) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v925 = llvm.load %rs924 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v926 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v927 = arith.cmpi eq, %v925, %v926 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v927, ^b134, ^b135 loc("std/io/core/error.lin":L:C)
  ^b131:
    %v942 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b128 loc("std/io/core/error.lin":L:C)
  ^b132:
    %v910 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v911 = llvm.getelementptr %rs896[%v910] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v912 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b131 loc("std/io/core/error.lin":L:C)
  ^b133:
    %v901 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v902 = llvm.getelementptr %rs896[%v901] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v903 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v903, %s70 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v906 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v907 = llvm.getelementptr %s70[%v906] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl908 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v907, %v902, %cl908) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl909 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s70, %rl909) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b134:
    %v938 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v939 = llvm.getelementptr %rs924[%v938] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v940 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b131 loc("std/io/core/error.lin":L:C)
  ^b135:
    %v929 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v930 = llvm.getelementptr %rs924[%v929] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v931 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v931, %s72 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v934 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v935 = llvm.getelementptr %s72[%v934] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl936 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v935, %v930, %cl936) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl937 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s72, %rl937) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b137:
    %v958 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba960 = llvm.mlir.addressof @linea_str34 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v960 = llvm.ptrtoint %ba960 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v961 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v960, %s74 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v964 = arith.constant 11 : i64 loc("std/io/core/error.lin":L:C)
    %v965 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v966 = llvm.getelementptr %s74[%v965] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v964, %v966 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs968, %v958, %s74) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v969 = llvm.load %rs968 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v970 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v971 = arith.cmpi eq, %v969, %v970 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v971, ^b139, ^b140 loc("std/io/core/error.lin":L:C)
  ^b138:
    %v1061 = arith.constant 10 : i64 loc("std/io/core/error.lin":L:C)
    %v1062 = arith.cmpi eq, %v0, %v1061 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1062, ^b152, ^b153 loc("std/io/core/error.lin":L:C)
  ^b139:
    %v982 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v983 = llvm.getelementptr %rs968[%v982] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v984 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v985 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw986 = arith.extui %v985 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw986, %s76 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v987 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw988 = llvm.load %s76 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz988 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v988 = arith.cmpi ne, %lw988, %lz988 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v988, ^b141, ^b142 loc("std/io/core/error.lin":L:C)
  ^b140:
    %v973 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v974 = llvm.getelementptr %rs968[%v973] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v975 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v975, %s75 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v978 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v979 = llvm.getelementptr %s75[%v978] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl980 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v979, %v974, %cl980) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl981 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s75, %rl981) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b141:
    %v990 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v990, ^b144, ^b145 loc("std/io/core/error.lin":L:C)
  ^b142:
    cf.br ^b143 loc("std/io/core/error.lin":L:C)
  ^b143:
    %v1051 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1052 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1052, %s81 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1055 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1056 = llvm.getelementptr %s81[%v1055] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1057 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl1058 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s81, %rl1058) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b144:
    %v992 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba994 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v994 = llvm.ptrtoint %ba994 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v995 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v994, %s77 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v998 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v999 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1000 = llvm.getelementptr %s77[%v999] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v998, %v1000 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1002, %v992, %s77) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1003 = llvm.load %rs1002 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1004 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1005 = arith.cmpi eq, %v1003, %v1004 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1005, ^b147, ^b148 loc("std/io/core/error.lin":L:C)
  ^b145:
    %v1020 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1022 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1022 = llvm.ptrtoint %ba1022 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1023 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1022, %s79 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1026 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v1027 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1028 = llvm.getelementptr %s79[%v1027] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1026, %v1028 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1030, %v1020, %s79) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1031 = llvm.load %rs1030 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1032 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1033 = arith.cmpi eq, %v1031, %v1032 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1033, ^b149, ^b150 loc("std/io/core/error.lin":L:C)
  ^b146:
    %v1048 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b143 loc("std/io/core/error.lin":L:C)
  ^b147:
    %v1016 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1017 = llvm.getelementptr %rs1002[%v1016] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1018 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b146 loc("std/io/core/error.lin":L:C)
  ^b148:
    %v1007 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1008 = llvm.getelementptr %rs1002[%v1007] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1009 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1009, %s78 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1012 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1013 = llvm.getelementptr %s78[%v1012] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1014 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1013, %v1008, %cl1014) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1015 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s78, %rl1015) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b149:
    %v1044 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1045 = llvm.getelementptr %rs1030[%v1044] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1046 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b146 loc("std/io/core/error.lin":L:C)
  ^b150:
    %v1035 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1036 = llvm.getelementptr %rs1030[%v1035] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1037 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1037, %s80 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1040 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1041 = llvm.getelementptr %s80[%v1040] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1042 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1041, %v1036, %cl1042) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1043 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s80, %rl1043) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b152:
    %v1064 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1066 = llvm.mlir.addressof @linea_str35 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1066 = llvm.ptrtoint %ba1066 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1067 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1066, %s82 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1070 = arith.constant 11 : i64 loc("std/io/core/error.lin":L:C)
    %v1071 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1072 = llvm.getelementptr %s82[%v1071] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1070, %v1072 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1074, %v1064, %s82) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1075 = llvm.load %rs1074 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1076 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1077 = arith.cmpi eq, %v1075, %v1076 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1077, ^b154, ^b155 loc("std/io/core/error.lin":L:C)
  ^b153:
    %v1167 = arith.constant 11 : i64 loc("std/io/core/error.lin":L:C)
    %v1168 = arith.cmpi eq, %v0, %v1167 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1168, ^b167, ^b168 loc("std/io/core/error.lin":L:C)
  ^b154:
    %v1088 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1089 = llvm.getelementptr %rs1074[%v1088] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1090 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1091 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw1092 = arith.extui %v1091 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw1092, %s84 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1093 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw1094 = llvm.load %s84 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz1094 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v1094 = arith.cmpi ne, %lw1094, %lz1094 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1094, ^b156, ^b157 loc("std/io/core/error.lin":L:C)
  ^b155:
    %v1079 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1080 = llvm.getelementptr %rs1074[%v1079] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1081 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1081, %s83 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1084 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1085 = llvm.getelementptr %s83[%v1084] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1086 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1085, %v1080, %cl1086) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1087 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s83, %rl1087) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b156:
    %v1096 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1096, ^b159, ^b160 loc("std/io/core/error.lin":L:C)
  ^b157:
    cf.br ^b158 loc("std/io/core/error.lin":L:C)
  ^b158:
    %v1157 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1158 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1158, %s89 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1161 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1162 = llvm.getelementptr %s89[%v1161] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1163 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl1164 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s89, %rl1164) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b159:
    %v1098 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1100 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1100 = llvm.ptrtoint %ba1100 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1101 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1100, %s85 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1104 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v1105 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1106 = llvm.getelementptr %s85[%v1105] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1104, %v1106 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1108, %v1098, %s85) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1109 = llvm.load %rs1108 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1110 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1111 = arith.cmpi eq, %v1109, %v1110 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1111, ^b162, ^b163 loc("std/io/core/error.lin":L:C)
  ^b160:
    %v1126 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1128 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1128 = llvm.ptrtoint %ba1128 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1129 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1128, %s87 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1132 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v1133 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1134 = llvm.getelementptr %s87[%v1133] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1132, %v1134 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1136, %v1126, %s87) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1137 = llvm.load %rs1136 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1138 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1139 = arith.cmpi eq, %v1137, %v1138 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1139, ^b164, ^b165 loc("std/io/core/error.lin":L:C)
  ^b161:
    %v1154 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b158 loc("std/io/core/error.lin":L:C)
  ^b162:
    %v1122 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1123 = llvm.getelementptr %rs1108[%v1122] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1124 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b161 loc("std/io/core/error.lin":L:C)
  ^b163:
    %v1113 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1114 = llvm.getelementptr %rs1108[%v1113] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1115 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1115, %s86 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1118 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1119 = llvm.getelementptr %s86[%v1118] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1120 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1119, %v1114, %cl1120) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1121 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s86, %rl1121) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b164:
    %v1150 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1151 = llvm.getelementptr %rs1136[%v1150] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1152 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b161 loc("std/io/core/error.lin":L:C)
  ^b165:
    %v1141 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1142 = llvm.getelementptr %rs1136[%v1141] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1143 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1143, %s88 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1146 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1147 = llvm.getelementptr %s88[%v1146] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1148 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1147, %v1142, %cl1148) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1149 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s88, %rl1149) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b167:
    %v1170 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1172 = llvm.mlir.addressof @linea_str36 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1172 = llvm.ptrtoint %ba1172 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1173 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1172, %s90 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1176 = arith.constant 7 : i64 loc("std/io/core/error.lin":L:C)
    %v1177 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1178 = llvm.getelementptr %s90[%v1177] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1176, %v1178 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1180, %v1170, %s90) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1181 = llvm.load %rs1180 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1182 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1183 = arith.cmpi eq, %v1181, %v1182 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1183, ^b169, ^b170 loc("std/io/core/error.lin":L:C)
  ^b168:
    %v1273 = arith.constant 12 : i64 loc("std/io/core/error.lin":L:C)
    %v1274 = arith.cmpi eq, %v0, %v1273 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1274, ^b182, ^b183 loc("std/io/core/error.lin":L:C)
  ^b169:
    %v1194 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1195 = llvm.getelementptr %rs1180[%v1194] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1196 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1197 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw1198 = arith.extui %v1197 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw1198, %s92 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1199 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw1200 = llvm.load %s92 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz1200 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v1200 = arith.cmpi ne, %lw1200, %lz1200 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1200, ^b171, ^b172 loc("std/io/core/error.lin":L:C)
  ^b170:
    %v1185 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1186 = llvm.getelementptr %rs1180[%v1185] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1187 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1187, %s91 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1190 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1191 = llvm.getelementptr %s91[%v1190] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1192 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1191, %v1186, %cl1192) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1193 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s91, %rl1193) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b171:
    %v1202 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1202, ^b174, ^b175 loc("std/io/core/error.lin":L:C)
  ^b172:
    cf.br ^b173 loc("std/io/core/error.lin":L:C)
  ^b173:
    %v1263 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1264 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1264, %s97 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1267 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1268 = llvm.getelementptr %s97[%v1267] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1269 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl1270 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s97, %rl1270) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b174:
    %v1204 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1206 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1206 = llvm.ptrtoint %ba1206 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1207 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1206, %s93 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1210 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v1211 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1212 = llvm.getelementptr %s93[%v1211] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1210, %v1212 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1214, %v1204, %s93) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1215 = llvm.load %rs1214 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1216 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1217 = arith.cmpi eq, %v1215, %v1216 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1217, ^b177, ^b178 loc("std/io/core/error.lin":L:C)
  ^b175:
    %v1232 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1234 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1234 = llvm.ptrtoint %ba1234 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1235 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1234, %s95 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1238 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v1239 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1240 = llvm.getelementptr %s95[%v1239] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1238, %v1240 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1242, %v1232, %s95) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1243 = llvm.load %rs1242 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1244 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1245 = arith.cmpi eq, %v1243, %v1244 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1245, ^b179, ^b180 loc("std/io/core/error.lin":L:C)
  ^b176:
    %v1260 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b173 loc("std/io/core/error.lin":L:C)
  ^b177:
    %v1228 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1229 = llvm.getelementptr %rs1214[%v1228] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1230 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b176 loc("std/io/core/error.lin":L:C)
  ^b178:
    %v1219 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1220 = llvm.getelementptr %rs1214[%v1219] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1221 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1221, %s94 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1224 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1225 = llvm.getelementptr %s94[%v1224] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1226 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1225, %v1220, %cl1226) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1227 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s94, %rl1227) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b179:
    %v1256 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1257 = llvm.getelementptr %rs1242[%v1256] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1258 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b176 loc("std/io/core/error.lin":L:C)
  ^b180:
    %v1247 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1248 = llvm.getelementptr %rs1242[%v1247] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1249 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1249, %s96 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1252 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1253 = llvm.getelementptr %s96[%v1252] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1254 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1253, %v1248, %cl1254) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1255 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s96, %rl1255) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b182:
    %v1276 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1278 = llvm.mlir.addressof @linea_str37 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1278 = llvm.ptrtoint %ba1278 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1279 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1278, %s98 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1282 = arith.constant 17 : i64 loc("std/io/core/error.lin":L:C)
    %v1283 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1284 = llvm.getelementptr %s98[%v1283] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1282, %v1284 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1286, %v1276, %s98) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1287 = llvm.load %rs1286 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1288 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1289 = arith.cmpi eq, %v1287, %v1288 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1289, ^b184, ^b185 loc("std/io/core/error.lin":L:C)
  ^b183:
    %v1379 = arith.constant 13 : i64 loc("std/io/core/error.lin":L:C)
    %v1380 = arith.cmpi eq, %v0, %v1379 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1380, ^b197, ^b198 loc("std/io/core/error.lin":L:C)
  ^b184:
    %v1300 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1301 = llvm.getelementptr %rs1286[%v1300] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1302 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1303 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw1304 = arith.extui %v1303 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw1304, %s100 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1305 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw1306 = llvm.load %s100 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz1306 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v1306 = arith.cmpi ne, %lw1306, %lz1306 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1306, ^b186, ^b187 loc("std/io/core/error.lin":L:C)
  ^b185:
    %v1291 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1292 = llvm.getelementptr %rs1286[%v1291] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1293 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1293, %s99 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1296 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1297 = llvm.getelementptr %s99[%v1296] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1298 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1297, %v1292, %cl1298) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1299 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s99, %rl1299) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b186:
    %v1308 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1308, ^b189, ^b190 loc("std/io/core/error.lin":L:C)
  ^b187:
    cf.br ^b188 loc("std/io/core/error.lin":L:C)
  ^b188:
    %v1369 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1370 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1370, %s105 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1373 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1374 = llvm.getelementptr %s105[%v1373] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1375 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl1376 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s105, %rl1376) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b189:
    %v1310 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1312 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1312 = llvm.ptrtoint %ba1312 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1313 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1312, %s101 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1316 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v1317 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1318 = llvm.getelementptr %s101[%v1317] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1316, %v1318 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1320, %v1310, %s101) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1321 = llvm.load %rs1320 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1322 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1323 = arith.cmpi eq, %v1321, %v1322 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1323, ^b192, ^b193 loc("std/io/core/error.lin":L:C)
  ^b190:
    %v1338 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1340 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1340 = llvm.ptrtoint %ba1340 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1341 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1340, %s103 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1344 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v1345 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1346 = llvm.getelementptr %s103[%v1345] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1344, %v1346 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1348, %v1338, %s103) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1349 = llvm.load %rs1348 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1350 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1351 = arith.cmpi eq, %v1349, %v1350 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1351, ^b194, ^b195 loc("std/io/core/error.lin":L:C)
  ^b191:
    %v1366 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b188 loc("std/io/core/error.lin":L:C)
  ^b192:
    %v1334 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1335 = llvm.getelementptr %rs1320[%v1334] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1336 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b191 loc("std/io/core/error.lin":L:C)
  ^b193:
    %v1325 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1326 = llvm.getelementptr %rs1320[%v1325] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1327 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1327, %s102 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1330 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1331 = llvm.getelementptr %s102[%v1330] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1332 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1331, %v1326, %cl1332) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1333 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s102, %rl1333) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b194:
    %v1362 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1363 = llvm.getelementptr %rs1348[%v1362] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1364 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b191 loc("std/io/core/error.lin":L:C)
  ^b195:
    %v1353 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1354 = llvm.getelementptr %rs1348[%v1353] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1355 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1355, %s104 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1358 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1359 = llvm.getelementptr %s104[%v1358] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1360 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1359, %v1354, %cl1360) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1361 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s104, %rl1361) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b197:
    %v1382 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1384 = llvm.mlir.addressof @linea_str38 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1384 = llvm.ptrtoint %ba1384 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1385 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1384, %s106 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1388 = arith.constant 7 : i64 loc("std/io/core/error.lin":L:C)
    %v1389 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1390 = llvm.getelementptr %s106[%v1389] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1388, %v1390 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1392, %v1382, %s106) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1393 = llvm.load %rs1392 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1394 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1395 = arith.cmpi eq, %v1393, %v1394 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1395, ^b199, ^b200 loc("std/io/core/error.lin":L:C)
  ^b198:
    %v1485 = arith.constant 14 : i64 loc("std/io/core/error.lin":L:C)
    %v1486 = arith.cmpi eq, %v0, %v1485 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1486, ^b212, ^b213 loc("std/io/core/error.lin":L:C)
  ^b199:
    %v1406 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1407 = llvm.getelementptr %rs1392[%v1406] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1408 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1409 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw1410 = arith.extui %v1409 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw1410, %s108 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1411 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw1412 = llvm.load %s108 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz1412 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v1412 = arith.cmpi ne, %lw1412, %lz1412 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1412, ^b201, ^b202 loc("std/io/core/error.lin":L:C)
  ^b200:
    %v1397 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1398 = llvm.getelementptr %rs1392[%v1397] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1399 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1399, %s107 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1402 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1403 = llvm.getelementptr %s107[%v1402] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1404 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1403, %v1398, %cl1404) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1405 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s107, %rl1405) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b201:
    %v1414 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1414, ^b204, ^b205 loc("std/io/core/error.lin":L:C)
  ^b202:
    cf.br ^b203 loc("std/io/core/error.lin":L:C)
  ^b203:
    %v1475 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1476 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1476, %s113 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1479 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1480 = llvm.getelementptr %s113[%v1479] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1481 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl1482 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s113, %rl1482) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b204:
    %v1416 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1418 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1418 = llvm.ptrtoint %ba1418 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1419 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1418, %s109 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1422 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v1423 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1424 = llvm.getelementptr %s109[%v1423] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1422, %v1424 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1426, %v1416, %s109) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1427 = llvm.load %rs1426 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1428 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1429 = arith.cmpi eq, %v1427, %v1428 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1429, ^b207, ^b208 loc("std/io/core/error.lin":L:C)
  ^b205:
    %v1444 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1446 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1446 = llvm.ptrtoint %ba1446 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1447 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1446, %s111 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1450 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v1451 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1452 = llvm.getelementptr %s111[%v1451] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1450, %v1452 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1454, %v1444, %s111) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1455 = llvm.load %rs1454 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1456 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1457 = arith.cmpi eq, %v1455, %v1456 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1457, ^b209, ^b210 loc("std/io/core/error.lin":L:C)
  ^b206:
    %v1472 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b203 loc("std/io/core/error.lin":L:C)
  ^b207:
    %v1440 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1441 = llvm.getelementptr %rs1426[%v1440] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1442 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b206 loc("std/io/core/error.lin":L:C)
  ^b208:
    %v1431 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1432 = llvm.getelementptr %rs1426[%v1431] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1433 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1433, %s110 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1436 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1437 = llvm.getelementptr %s110[%v1436] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1438 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1437, %v1432, %cl1438) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1439 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s110, %rl1439) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b209:
    %v1468 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1469 = llvm.getelementptr %rs1454[%v1468] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1470 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b206 loc("std/io/core/error.lin":L:C)
  ^b210:
    %v1459 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1460 = llvm.getelementptr %rs1454[%v1459] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1461 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1461, %s112 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1464 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1465 = llvm.getelementptr %s112[%v1464] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1466 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1465, %v1460, %cl1466) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1467 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s112, %rl1467) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b212:
    %v1488 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1490 = llvm.mlir.addressof @linea_str39 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1490 = llvm.ptrtoint %ba1490 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1491 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1490, %s114 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1494 = arith.constant 17 : i64 loc("std/io/core/error.lin":L:C)
    %v1495 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1496 = llvm.getelementptr %s114[%v1495] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1494, %v1496 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1498, %v1488, %s114) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1499 = llvm.load %rs1498 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1500 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1501 = arith.cmpi eq, %v1499, %v1500 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1501, ^b214, ^b215 loc("std/io/core/error.lin":L:C)
  ^b213:
    %v1591 = arith.constant 15 : i64 loc("std/io/core/error.lin":L:C)
    %v1592 = arith.cmpi eq, %v0, %v1591 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1592, ^b227, ^b228 loc("std/io/core/error.lin":L:C)
  ^b214:
    %v1512 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1513 = llvm.getelementptr %rs1498[%v1512] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1514 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1515 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw1516 = arith.extui %v1515 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw1516, %s116 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1517 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw1518 = llvm.load %s116 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz1518 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v1518 = arith.cmpi ne, %lw1518, %lz1518 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1518, ^b216, ^b217 loc("std/io/core/error.lin":L:C)
  ^b215:
    %v1503 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1504 = llvm.getelementptr %rs1498[%v1503] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1505 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1505, %s115 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1508 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1509 = llvm.getelementptr %s115[%v1508] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1510 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1509, %v1504, %cl1510) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1511 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s115, %rl1511) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b216:
    %v1520 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1520, ^b219, ^b220 loc("std/io/core/error.lin":L:C)
  ^b217:
    cf.br ^b218 loc("std/io/core/error.lin":L:C)
  ^b218:
    %v1581 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1582 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1582, %s121 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1585 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1586 = llvm.getelementptr %s121[%v1585] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1587 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl1588 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s121, %rl1588) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b219:
    %v1522 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1524 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1524 = llvm.ptrtoint %ba1524 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1525 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1524, %s117 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1528 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v1529 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1530 = llvm.getelementptr %s117[%v1529] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1528, %v1530 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1532, %v1522, %s117) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1533 = llvm.load %rs1532 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1534 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1535 = arith.cmpi eq, %v1533, %v1534 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1535, ^b222, ^b223 loc("std/io/core/error.lin":L:C)
  ^b220:
    %v1550 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1552 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1552 = llvm.ptrtoint %ba1552 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1553 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1552, %s119 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1556 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v1557 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1558 = llvm.getelementptr %s119[%v1557] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1556, %v1558 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1560, %v1550, %s119) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1561 = llvm.load %rs1560 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1562 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1563 = arith.cmpi eq, %v1561, %v1562 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1563, ^b224, ^b225 loc("std/io/core/error.lin":L:C)
  ^b221:
    %v1578 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b218 loc("std/io/core/error.lin":L:C)
  ^b222:
    %v1546 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1547 = llvm.getelementptr %rs1532[%v1546] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1548 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b221 loc("std/io/core/error.lin":L:C)
  ^b223:
    %v1537 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1538 = llvm.getelementptr %rs1532[%v1537] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1539 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1539, %s118 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1542 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1543 = llvm.getelementptr %s118[%v1542] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1544 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1543, %v1538, %cl1544) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1545 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s118, %rl1545) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b224:
    %v1574 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1575 = llvm.getelementptr %rs1560[%v1574] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1576 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b221 loc("std/io/core/error.lin":L:C)
  ^b225:
    %v1565 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1566 = llvm.getelementptr %rs1560[%v1565] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1567 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1567, %s120 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1570 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1571 = llvm.getelementptr %s120[%v1570] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1572 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1571, %v1566, %cl1572) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1573 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s120, %rl1573) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b227:
    %v1594 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1596 = llvm.mlir.addressof @linea_str40 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1596 = llvm.ptrtoint %ba1596 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1597 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1596, %s122 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1600 = arith.constant 10 : i64 loc("std/io/core/error.lin":L:C)
    %v1601 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1602 = llvm.getelementptr %s122[%v1601] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1600, %v1602 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1604, %v1594, %s122) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1605 = llvm.load %rs1604 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1606 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1607 = arith.cmpi eq, %v1605, %v1606 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1607, ^b229, ^b230 loc("std/io/core/error.lin":L:C)
  ^b228:
    %v1697 = arith.constant 16 : i64 loc("std/io/core/error.lin":L:C)
    %v1698 = arith.cmpi eq, %v0, %v1697 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1698, ^b242, ^b243 loc("std/io/core/error.lin":L:C)
  ^b229:
    %v1618 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1619 = llvm.getelementptr %rs1604[%v1618] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1620 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1621 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw1622 = arith.extui %v1621 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw1622, %s124 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1623 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw1624 = llvm.load %s124 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz1624 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v1624 = arith.cmpi ne, %lw1624, %lz1624 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1624, ^b231, ^b232 loc("std/io/core/error.lin":L:C)
  ^b230:
    %v1609 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1610 = llvm.getelementptr %rs1604[%v1609] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1611 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1611, %s123 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1614 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1615 = llvm.getelementptr %s123[%v1614] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1616 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1615, %v1610, %cl1616) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1617 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s123, %rl1617) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b231:
    %v1626 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1626, ^b234, ^b235 loc("std/io/core/error.lin":L:C)
  ^b232:
    cf.br ^b233 loc("std/io/core/error.lin":L:C)
  ^b233:
    %v1687 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1688 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1688, %s129 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1691 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1692 = llvm.getelementptr %s129[%v1691] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1693 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl1694 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s129, %rl1694) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b234:
    %v1628 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1630 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1630 = llvm.ptrtoint %ba1630 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1631 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1630, %s125 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1634 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v1635 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1636 = llvm.getelementptr %s125[%v1635] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1634, %v1636 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1638, %v1628, %s125) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1639 = llvm.load %rs1638 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1640 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1641 = arith.cmpi eq, %v1639, %v1640 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1641, ^b237, ^b238 loc("std/io/core/error.lin":L:C)
  ^b235:
    %v1656 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1658 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1658 = llvm.ptrtoint %ba1658 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1659 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1658, %s127 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1662 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v1663 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1664 = llvm.getelementptr %s127[%v1663] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1662, %v1664 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1666, %v1656, %s127) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1667 = llvm.load %rs1666 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1668 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1669 = arith.cmpi eq, %v1667, %v1668 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1669, ^b239, ^b240 loc("std/io/core/error.lin":L:C)
  ^b236:
    %v1684 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b233 loc("std/io/core/error.lin":L:C)
  ^b237:
    %v1652 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1653 = llvm.getelementptr %rs1638[%v1652] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1654 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b236 loc("std/io/core/error.lin":L:C)
  ^b238:
    %v1643 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1644 = llvm.getelementptr %rs1638[%v1643] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1645 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1645, %s126 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1648 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1649 = llvm.getelementptr %s126[%v1648] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1650 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1649, %v1644, %cl1650) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1651 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s126, %rl1651) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b239:
    %v1680 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1681 = llvm.getelementptr %rs1666[%v1680] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1682 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b236 loc("std/io/core/error.lin":L:C)
  ^b240:
    %v1671 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1672 = llvm.getelementptr %rs1666[%v1671] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1673 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1673, %s128 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1676 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1677 = llvm.getelementptr %s128[%v1676] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1678 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1677, %v1672, %cl1678) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1679 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s128, %rl1679) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b242:
    %v1700 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1702 = llvm.mlir.addressof @linea_str41 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1702 = llvm.ptrtoint %ba1702 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1703 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1702, %s130 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1706 = arith.constant 15 : i64 loc("std/io/core/error.lin":L:C)
    %v1707 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1708 = llvm.getelementptr %s130[%v1707] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1706, %v1708 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1710, %v1700, %s130) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1711 = llvm.load %rs1710 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1712 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1713 = arith.cmpi eq, %v1711, %v1712 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1713, ^b244, ^b245 loc("std/io/core/error.lin":L:C)
  ^b243:
    %v1803 = arith.constant 17 : i64 loc("std/io/core/error.lin":L:C)
    %v1804 = arith.cmpi eq, %v0, %v1803 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1804, ^b257, ^b258 loc("std/io/core/error.lin":L:C)
  ^b244:
    %v1724 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1725 = llvm.getelementptr %rs1710[%v1724] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1726 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1727 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw1728 = arith.extui %v1727 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw1728, %s132 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1729 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw1730 = llvm.load %s132 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz1730 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v1730 = arith.cmpi ne, %lw1730, %lz1730 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1730, ^b246, ^b247 loc("std/io/core/error.lin":L:C)
  ^b245:
    %v1715 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1716 = llvm.getelementptr %rs1710[%v1715] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1717 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1717, %s131 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1720 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1721 = llvm.getelementptr %s131[%v1720] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1722 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1721, %v1716, %cl1722) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1723 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s131, %rl1723) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b246:
    %v1732 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1732, ^b249, ^b250 loc("std/io/core/error.lin":L:C)
  ^b247:
    cf.br ^b248 loc("std/io/core/error.lin":L:C)
  ^b248:
    %v1793 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1794 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1794, %s137 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1797 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1798 = llvm.getelementptr %s137[%v1797] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1799 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl1800 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s137, %rl1800) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b249:
    %v1734 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1736 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1736 = llvm.ptrtoint %ba1736 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1737 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1736, %s133 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1740 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v1741 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1742 = llvm.getelementptr %s133[%v1741] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1740, %v1742 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1744, %v1734, %s133) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1745 = llvm.load %rs1744 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1746 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1747 = arith.cmpi eq, %v1745, %v1746 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1747, ^b252, ^b253 loc("std/io/core/error.lin":L:C)
  ^b250:
    %v1762 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1764 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1764 = llvm.ptrtoint %ba1764 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1765 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1764, %s135 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1768 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v1769 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1770 = llvm.getelementptr %s135[%v1769] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1768, %v1770 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1772, %v1762, %s135) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1773 = llvm.load %rs1772 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1774 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1775 = arith.cmpi eq, %v1773, %v1774 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1775, ^b254, ^b255 loc("std/io/core/error.lin":L:C)
  ^b251:
    %v1790 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b248 loc("std/io/core/error.lin":L:C)
  ^b252:
    %v1758 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1759 = llvm.getelementptr %rs1744[%v1758] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1760 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b251 loc("std/io/core/error.lin":L:C)
  ^b253:
    %v1749 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1750 = llvm.getelementptr %rs1744[%v1749] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1751 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1751, %s134 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1754 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1755 = llvm.getelementptr %s134[%v1754] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1756 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1755, %v1750, %cl1756) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1757 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s134, %rl1757) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b254:
    %v1786 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1787 = llvm.getelementptr %rs1772[%v1786] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1788 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b251 loc("std/io/core/error.lin":L:C)
  ^b255:
    %v1777 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1778 = llvm.getelementptr %rs1772[%v1777] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1779 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1779, %s136 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1782 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1783 = llvm.getelementptr %s136[%v1782] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1784 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1783, %v1778, %cl1784) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1785 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s136, %rl1785) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b257:
    %v1806 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1808 = llvm.mlir.addressof @linea_str42 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1808 = llvm.ptrtoint %ba1808 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1809 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1808, %s138 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1812 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1813 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1814 = llvm.getelementptr %s138[%v1813] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1812, %v1814 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1816, %v1806, %s138) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1817 = llvm.load %rs1816 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1818 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1819 = arith.cmpi eq, %v1817, %v1818 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1819, ^b259, ^b260 loc("std/io/core/error.lin":L:C)
  ^b258:
    %v1909 = arith.constant 18 : i64 loc("std/io/core/error.lin":L:C)
    %v1910 = arith.cmpi eq, %v0, %v1909 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1910, ^b272, ^b273 loc("std/io/core/error.lin":L:C)
  ^b259:
    %v1830 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1831 = llvm.getelementptr %rs1816[%v1830] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1832 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1833 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw1834 = arith.extui %v1833 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw1834, %s140 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1835 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw1836 = llvm.load %s140 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz1836 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v1836 = arith.cmpi ne, %lw1836, %lz1836 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1836, ^b261, ^b262 loc("std/io/core/error.lin":L:C)
  ^b260:
    %v1821 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1822 = llvm.getelementptr %rs1816[%v1821] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1823 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1823, %s139 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1826 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1827 = llvm.getelementptr %s139[%v1826] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1828 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1827, %v1822, %cl1828) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1829 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s139, %rl1829) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b261:
    %v1838 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1838, ^b264, ^b265 loc("std/io/core/error.lin":L:C)
  ^b262:
    cf.br ^b263 loc("std/io/core/error.lin":L:C)
  ^b263:
    %v1899 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1900 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1900, %s145 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1903 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1904 = llvm.getelementptr %s145[%v1903] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1905 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl1906 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s145, %rl1906) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b264:
    %v1840 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1842 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1842 = llvm.ptrtoint %ba1842 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1843 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1842, %s141 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1846 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v1847 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1848 = llvm.getelementptr %s141[%v1847] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1846, %v1848 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1850, %v1840, %s141) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1851 = llvm.load %rs1850 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1852 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1853 = arith.cmpi eq, %v1851, %v1852 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1853, ^b267, ^b268 loc("std/io/core/error.lin":L:C)
  ^b265:
    %v1868 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1870 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1870 = llvm.ptrtoint %ba1870 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1871 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1870, %s143 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1874 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v1875 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1876 = llvm.getelementptr %s143[%v1875] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1874, %v1876 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1878, %v1868, %s143) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1879 = llvm.load %rs1878 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1880 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1881 = arith.cmpi eq, %v1879, %v1880 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1881, ^b269, ^b270 loc("std/io/core/error.lin":L:C)
  ^b266:
    %v1896 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b263 loc("std/io/core/error.lin":L:C)
  ^b267:
    %v1864 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1865 = llvm.getelementptr %rs1850[%v1864] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1866 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b266 loc("std/io/core/error.lin":L:C)
  ^b268:
    %v1855 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1856 = llvm.getelementptr %rs1850[%v1855] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1857 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1857, %s142 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1860 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1861 = llvm.getelementptr %s142[%v1860] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1862 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1861, %v1856, %cl1862) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1863 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s142, %rl1863) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b269:
    %v1892 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1893 = llvm.getelementptr %rs1878[%v1892] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1894 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b266 loc("std/io/core/error.lin":L:C)
  ^b270:
    %v1883 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1884 = llvm.getelementptr %rs1878[%v1883] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1885 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1885, %s144 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1888 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1889 = llvm.getelementptr %s144[%v1888] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1890 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1889, %v1884, %cl1890) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1891 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s144, %rl1891) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b272:
    %v1912 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1914 = llvm.mlir.addressof @linea_str43 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1914 = llvm.ptrtoint %ba1914 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1915 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1914, %s146 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1918 = arith.constant 15 : i64 loc("std/io/core/error.lin":L:C)
    %v1919 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1920 = llvm.getelementptr %s146[%v1919] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1918, %v1920 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1922, %v1912, %s146) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1923 = llvm.load %rs1922 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1924 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1925 = arith.cmpi eq, %v1923, %v1924 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1925, ^b274, ^b275 loc("std/io/core/error.lin":L:C)
  ^b273:
    %v2015 = arith.constant 19 : i64 loc("std/io/core/error.lin":L:C)
    %v2016 = arith.cmpi eq, %v0, %v2015 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v2016, ^b287, ^b288 loc("std/io/core/error.lin":L:C)
  ^b274:
    %v1936 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1937 = llvm.getelementptr %rs1922[%v1936] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1938 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1939 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw1940 = arith.extui %v1939 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw1940, %s148 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1941 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw1942 = llvm.load %s148 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz1942 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v1942 = arith.cmpi ne, %lw1942, %lz1942 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1942, ^b276, ^b277 loc("std/io/core/error.lin":L:C)
  ^b275:
    %v1927 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1928 = llvm.getelementptr %rs1922[%v1927] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1929 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1929, %s147 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1932 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1933 = llvm.getelementptr %s147[%v1932] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1934 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1933, %v1928, %cl1934) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1935 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s147, %rl1935) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b276:
    %v1944 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1944, ^b279, ^b280 loc("std/io/core/error.lin":L:C)
  ^b277:
    cf.br ^b278 loc("std/io/core/error.lin":L:C)
  ^b278:
    %v2005 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v2006 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v2006, %s153 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v2009 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v2010 = llvm.getelementptr %s153[%v2009] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v2011 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl2012 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s153, %rl2012) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b279:
    %v1946 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1948 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1948 = llvm.ptrtoint %ba1948 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1949 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1948, %s149 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1952 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v1953 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1954 = llvm.getelementptr %s149[%v1953] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1952, %v1954 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1956, %v1946, %s149) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1957 = llvm.load %rs1956 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1958 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1959 = arith.cmpi eq, %v1957, %v1958 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1959, ^b282, ^b283 loc("std/io/core/error.lin":L:C)
  ^b280:
    %v1974 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba1976 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1976 = llvm.ptrtoint %ba1976 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v1977 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1976, %s151 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1980 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v1981 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1982 = llvm.getelementptr %s151[%v1981] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v1980, %v1982 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs1984, %v1974, %s151) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v1985 = llvm.load %rs1984 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v1986 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v1987 = arith.cmpi eq, %v1985, %v1986 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v1987, ^b284, ^b285 loc("std/io/core/error.lin":L:C)
  ^b281:
    %v2002 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b278 loc("std/io/core/error.lin":L:C)
  ^b282:
    %v1970 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1971 = llvm.getelementptr %rs1956[%v1970] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1972 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b281 loc("std/io/core/error.lin":L:C)
  ^b283:
    %v1961 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1962 = llvm.getelementptr %rs1956[%v1961] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1963 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1963, %s150 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1966 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1967 = llvm.getelementptr %s150[%v1966] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1968 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1967, %v1962, %cl1968) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1969 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s150, %rl1969) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b284:
    %v1998 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1999 = llvm.getelementptr %rs1984[%v1998] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v2000 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b281 loc("std/io/core/error.lin":L:C)
  ^b285:
    %v1989 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1990 = llvm.getelementptr %rs1984[%v1989] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v1991 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v1991, %s152 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v1994 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v1995 = llvm.getelementptr %s152[%v1994] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl1996 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v1995, %v1990, %cl1996) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl1997 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s152, %rl1997) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b287:
    %v2018 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba2020 = llvm.mlir.addressof @linea_str44 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v2020 = llvm.ptrtoint %ba2020 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v2021 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v2020, %s154 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v2024 = arith.constant 17 : i64 loc("std/io/core/error.lin":L:C)
    %v2025 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v2026 = llvm.getelementptr %s154[%v2025] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v2024, %v2026 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs2028, %v2018, %s154) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v2029 = llvm.load %rs2028 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v2030 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v2031 = arith.cmpi eq, %v2029, %v2030 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v2031, ^b289, ^b290 loc("std/io/core/error.lin":L:C)
  ^b288:
    %v2121 = arith.constant 20 : i64 loc("std/io/core/error.lin":L:C)
    %v2122 = arith.cmpi eq, %v0, %v2121 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v2122, ^b302, ^b303 loc("std/io/core/error.lin":L:C)
  ^b289:
    %v2042 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v2043 = llvm.getelementptr %rs2028[%v2042] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v2044 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v2045 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw2046 = arith.extui %v2045 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw2046, %s156 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v2047 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw2048 = llvm.load %s156 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz2048 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v2048 = arith.cmpi ne, %lw2048, %lz2048 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v2048, ^b291, ^b292 loc("std/io/core/error.lin":L:C)
  ^b290:
    %v2033 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v2034 = llvm.getelementptr %rs2028[%v2033] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v2035 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v2035, %s155 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v2038 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v2039 = llvm.getelementptr %s155[%v2038] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl2040 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v2039, %v2034, %cl2040) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl2041 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s155, %rl2041) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b291:
    %v2050 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v2050, ^b294, ^b295 loc("std/io/core/error.lin":L:C)
  ^b292:
    cf.br ^b293 loc("std/io/core/error.lin":L:C)
  ^b293:
    %v2111 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v2112 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v2112, %s161 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v2115 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v2116 = llvm.getelementptr %s161[%v2115] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v2117 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl2118 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s161, %rl2118) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b294:
    %v2052 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba2054 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v2054 = llvm.ptrtoint %ba2054 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v2055 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v2054, %s157 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v2058 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v2059 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v2060 = llvm.getelementptr %s157[%v2059] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v2058, %v2060 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs2062, %v2052, %s157) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v2063 = llvm.load %rs2062 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v2064 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v2065 = arith.cmpi eq, %v2063, %v2064 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v2065, ^b297, ^b298 loc("std/io/core/error.lin":L:C)
  ^b295:
    %v2080 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba2082 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v2082 = llvm.ptrtoint %ba2082 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v2083 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v2082, %s159 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v2086 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v2087 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v2088 = llvm.getelementptr %s159[%v2087] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v2086, %v2088 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs2090, %v2080, %s159) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v2091 = llvm.load %rs2090 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v2092 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v2093 = arith.cmpi eq, %v2091, %v2092 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v2093, ^b299, ^b300 loc("std/io/core/error.lin":L:C)
  ^b296:
    %v2108 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b293 loc("std/io/core/error.lin":L:C)
  ^b297:
    %v2076 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v2077 = llvm.getelementptr %rs2062[%v2076] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v2078 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b296 loc("std/io/core/error.lin":L:C)
  ^b298:
    %v2067 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v2068 = llvm.getelementptr %rs2062[%v2067] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v2069 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v2069, %s158 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v2072 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v2073 = llvm.getelementptr %s158[%v2072] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl2074 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v2073, %v2068, %cl2074) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl2075 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s158, %rl2075) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b299:
    %v2104 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v2105 = llvm.getelementptr %rs2090[%v2104] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v2106 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b296 loc("std/io/core/error.lin":L:C)
  ^b300:
    %v2095 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v2096 = llvm.getelementptr %rs2090[%v2095] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v2097 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v2097, %s160 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v2100 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v2101 = llvm.getelementptr %s160[%v2100] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl2102 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v2101, %v2096, %cl2102) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl2103 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s160, %rl2103) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b302:
    %v2124 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba2126 = llvm.mlir.addressof @linea_str45 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v2126 = llvm.ptrtoint %ba2126 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v2127 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v2126, %s162 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v2130 = arith.constant 12 : i64 loc("std/io/core/error.lin":L:C)
    %v2131 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v2132 = llvm.getelementptr %s162[%v2131] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v2130, %v2132 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs2134, %v2124, %s162) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v2135 = llvm.load %rs2134 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v2136 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v2137 = arith.cmpi eq, %v2135, %v2136 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v2137, ^b304, ^b305 loc("std/io/core/error.lin":L:C)
  ^b303:
    %tk1 = arith.constant 3 : i32 loc("std/io/core/error.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file7 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/io/core/error.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/io/core/error.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/io/core/error.lin":L:C)
    llvm.unreachable loc("std/io/core/error.lin":L:C)
  ^b304:
    %v2148 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v2149 = llvm.getelementptr %rs2134[%v2148] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v2150 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v2151 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    %sw2152 = arith.extui %v2151 : i1 to i8 loc("std/io/core/error.lin":L:C)
    llvm.store %sw2152, %s164 : i8, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v2153 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %lw2154 = llvm.load %s164 : !llvm.ptr -> i8 loc("std/io/core/error.lin":L:C)
    %lz2154 = arith.constant 0 : i8 loc("std/io/core/error.lin":L:C)
    %v2154 = arith.cmpi ne, %lw2154, %lz2154 : i8 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v2154, ^b306, ^b307 loc("std/io/core/error.lin":L:C)
  ^b305:
    %v2139 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v2140 = llvm.getelementptr %rs2134[%v2139] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v2141 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v2141, %s163 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v2144 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v2145 = llvm.getelementptr %s163[%v2144] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl2146 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v2145, %v2140, %cl2146) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl2147 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s163, %rl2147) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b306:
    %v2156 = arith.constant 0 : i1 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v2156, ^b309, ^b310 loc("std/io/core/error.lin":L:C)
  ^b307:
    cf.br ^b308 loc("std/io/core/error.lin":L:C)
  ^b308:
    %v2217 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v2218 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v2218, %s169 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v2221 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v2222 = llvm.getelementptr %s169[%v2221] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v2223 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl2224 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s169, %rl2224) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b309:
    %v2158 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba2160 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v2160 = llvm.ptrtoint %ba2160 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v2161 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v2160, %s165 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v2164 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v2165 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v2166 = llvm.getelementptr %s165[%v2165] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v2164, %v2166 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs2168, %v2158, %s165) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v2169 = llvm.load %rs2168 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v2170 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v2171 = arith.cmpi eq, %v2169, %v2170 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v2171, ^b312, ^b313 loc("std/io/core/error.lin":L:C)
  ^b310:
    %v2186 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    %ba2188 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v2188 = llvm.ptrtoint %ba2188 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v2189 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v2188, %s167 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v2192 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v2193 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v2194 = llvm.getelementptr %s167[%v2193] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v2192, %v2194 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs2196, %v2186, %s167) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    %v2197 = llvm.load %rs2196 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v2198 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v2199 = arith.cmpi eq, %v2197, %v2198 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v2199, ^b314, ^b315 loc("std/io/core/error.lin":L:C)
  ^b311:
    %v2214 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b308 loc("std/io/core/error.lin":L:C)
  ^b312:
    %v2182 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v2183 = llvm.getelementptr %rs2168[%v2182] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v2184 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b311 loc("std/io/core/error.lin":L:C)
  ^b313:
    %v2173 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v2174 = llvm.getelementptr %rs2168[%v2173] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v2175 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v2175, %s166 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v2178 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v2179 = llvm.getelementptr %s166[%v2178] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl2180 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v2179, %v2174, %cl2180) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl2181 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s166, %rl2181) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b314:
    %v2210 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v2211 = llvm.getelementptr %rs2196[%v2210] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v2212 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b311 loc("std/io/core/error.lin":L:C)
  ^b315:
    %v2201 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v2202 = llvm.getelementptr %rs2196[%v2201] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v2203 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v2203, %s168 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v2206 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v2207 = llvm.getelementptr %s168[%v2206] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl2208 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%v2207, %v2202, %cl2208) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %rl2209 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s168, %rl2209) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  }
  func.func private @"lin.UInt64;std.fmt;Display.fmt[std.io.core.Descriptor]"(%sret: !llvm.ptr, %a0: i64, %a1: !llvm.ptr) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 48 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : i64, !llvm.ptr
    llvm.store %a1, %s1 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v1 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %k1z = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %k1 = arith.cmpi slt, %v1, %k1z : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k1, ^t1, ^c1 loc("std/fmt/decimal.lin":L:C)
  ^t1:
    %tk1 = arith.constant 2 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file9 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c1:
    %p2 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v2 = arith.addi %v1, %p2 : i64 loc("std/fmt/decimal.lin":L:C)
    %v3 = arith.cmpi ult, %v0, %v2 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %v3, ^b1, ^b2 loc("std/fmt/decimal.lin":L:C)
  ^b1:
    %v6 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %k2z = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %k2 = arith.cmpi slt, %v6, %k2z : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k2, ^t2, ^c2 loc("std/fmt/decimal.lin":L:C)
  ^t2:
    %tk2 = arith.constant 2 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf2 = llvm.mlir.addressof @linea_file9 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl2 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc2 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c2:
    %p7 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v7 = arith.addi %v6, %p7 : i64 loc("std/fmt/decimal.lin":L:C)
    %v8 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    func.call @"lin.std.fmt;format_signed[std.io.core.Descriptor]"(%sret, %v7, %v8) : (!llvm.ptr, i64, !llvm.ptr) -> () loc("std/fmt/decimal.lin":L:C)
    func.return loc("std/fmt/decimal.lin":L:C)
  ^b2:
    %v13 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %p14 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v14 = arith.addi %v13, %p14 : i64 loc("std/fmt/decimal.lin":L:C)
    %v15 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    func.call @"lin.std.fmt;format_unsigned[std.io.core.Descriptor]"(%sret, %v14, %v15) : (!llvm.ptr, i64, !llvm.ptr) -> () loc("std/fmt/decimal.lin":L:C)
    func.return loc("std/fmt/decimal.lin":L:C)
  }
  func.func private @"lin.Int32;std.fmt;Display.fmt[std.io.core.Descriptor]"(%sret: !llvm.ptr, %a0: i64, %a1: !llvm.ptr) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i32 {alignment = 4 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 48 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %pw0 = arith.trunci %a0 : i64 to i32
    llvm.store %pw0, %s0 : i32, !llvm.ptr
    llvm.store %a1, %s1 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %lw0 = llvm.load %s0 : !llvm.ptr -> i32 loc("std/fmt/decimal.lin":L:C)
    %v0 = arith.extsi %lw0 : i32 to i64 loc("std/fmt/decimal.lin":L:C)
    %v1 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %k1m = arith.constant 2147483647 : i64 loc("std/fmt/decimal.lin":L:C)
    %k1 = arith.cmpi sgt, %v1, %k1m : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k1, ^t1, ^c1 loc("std/fmt/decimal.lin":L:C)
  ^t1:
    %tk1 = arith.constant 2 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file9 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c1:
    %k2m = arith.constant -2147483648 : i64 loc("std/fmt/decimal.lin":L:C)
    %k2 = arith.cmpi slt, %v1, %k2m : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k2, ^t2, ^c2 loc("std/fmt/decimal.lin":L:C)
  ^t2:
    %tk2 = arith.constant 2 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf2 = llvm.mlir.addressof @linea_file9 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl2 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc2 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c2:
    %p2 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v2 = arith.addi %v1, %p2 : i64 loc("std/fmt/decimal.lin":L:C)
    %v3 = arith.cmpi slt, %v0, %v2 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %v3, ^b1, ^b2 loc("std/fmt/decimal.lin":L:C)
  ^b1:
    %lw6 = llvm.load %s0 : !llvm.ptr -> i32 loc("std/fmt/decimal.lin":L:C)
    %v6 = arith.extsi %lw6 : i32 to i64 loc("std/fmt/decimal.lin":L:C)
    %p7 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v7 = arith.addi %v6, %p7 : i64 loc("std/fmt/decimal.lin":L:C)
    %v8 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    func.call @"lin.std.fmt;format_signed[std.io.core.Descriptor]"(%sret, %v7, %v8) : (!llvm.ptr, i64, !llvm.ptr) -> () loc("std/fmt/decimal.lin":L:C)
    func.return loc("std/fmt/decimal.lin":L:C)
  ^b2:
    %lw13 = llvm.load %s0 : !llvm.ptr -> i32 loc("std/fmt/decimal.lin":L:C)
    %v13 = arith.extsi %lw13 : i32 to i64 loc("std/fmt/decimal.lin":L:C)
    %k3z = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %k3 = arith.cmpi slt, %v13, %k3z : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k3, ^t3, ^c3 loc("std/fmt/decimal.lin":L:C)
  ^t3:
    %tk3 = arith.constant 2 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf3 = llvm.mlir.addressof @linea_file9 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl3 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc3 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk3, %tf3, %tl3, %tc3) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c3:
    %p14 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v14 = arith.addi %v13, %p14 : i64 loc("std/fmt/decimal.lin":L:C)
    %v15 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    func.call @"lin.std.fmt;format_unsigned[std.io.core.Descriptor]"(%sret, %v14, %v15) : (!llvm.ptr, i64, !llvm.ptr) -> () loc("std/fmt/decimal.lin":L:C)
    func.return loc("std/fmt/decimal.lin":L:C)
  }
  func.func private @"lin.std.io.core.Descriptor;std.io.core;ByteWriter.write_some"(%sret: !llvm.ptr, %a0: !llvm.ptr, %a1: !llvm.ptr) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 72 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 1 : i64
    %s3 = llvm.alloca %z3 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z4 = arith.constant 40 : i64
    %s4 = llvm.alloca %z4 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z5 = arith.constant 72 : i64
    %s5 = llvm.alloca %z5 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z6 = arith.constant 72 : i64
    %s6 = llvm.alloca %z6 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    llvm.store %a1, %s1 : !llvm.ptr, !llvm.ptr
    %rz36 = arith.constant 40 : i64
    %rs36 = llvm.alloca %rz36 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/descriptor.lin":L:C)
    %v1 = func.call @"lin.std.mem;Slice[UInt8].length"(%v0) : (!llvm.ptr) -> i64 loc("std/io/core/descriptor.lin":L:C)
    %v2 = arith.constant 0 : i64 loc("std/io/core/descriptor.lin":L:C)
    %v3 = arith.cmpi eq, %v1, %v2 : i64 loc("std/io/core/descriptor.lin":L:C)
    cf.cond_br %v3, ^b1, ^b2 loc("std/io/core/descriptor.lin":L:C)
  ^b1:
    %v5 = arith.constant 0 : i64 loc("std/io/core/descriptor.lin":L:C)
    llvm.store %v5, %s2 : i64, !llvm.ptr loc("std/io/core/descriptor.lin":L:C)
    %v8 = arith.constant 8 : i64 loc("std/io/core/descriptor.lin":L:C)
    %v9 = llvm.getelementptr %s2[%v8] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/descriptor.lin":L:C)
    %v10 = arith.constant 0 : i64 loc("std/io/core/descriptor.lin":L:C)
    llvm.store %v10, %v9 : i64, !llvm.ptr loc("std/io/core/descriptor.lin":L:C)
    %rl12 = arith.constant 72 : i64 loc("std/io/core/descriptor.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s2, %rl12) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/descriptor.lin":L:C)
    func.return loc("std/io/core/descriptor.lin":L:C)
  ^b2:
    cf.br ^b3 loc("std/io/core/descriptor.lin":L:C)
  ^b3:
    %v16 = arith.constant 0 : i64 loc("std/io/core/descriptor.lin":L:C)
    %v17 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/io/core/descriptor.lin":L:C)
    %v18 = arith.constant 0 : i64 loc("std/io/core/descriptor.lin":L:C)
    %v20 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/descriptor.lin":L:C)
    %iw21 = llvm.load %v17 : !llvm.ptr -> i32 loc("std/io/core/descriptor.lin":L:C)
    %v21 = arith.extsi %iw21 : i32 to i64 loc("std/io/core/descriptor.lin":L:C)
    %v22 = func.call @"lin.std.mem;write_slice_fd"(%v20, %v21) : (!llvm.ptr, i64) -> i64 loc("std/io/core/descriptor.lin":L:C)
    llvm.store %v22, %s3 : i64, !llvm.ptr loc("std/io/core/descriptor.lin":L:C)
    %v24 = llvm.load %s3 : !llvm.ptr -> i64 loc("std/io/core/descriptor.lin":L:C)
    %v25 = arith.constant 0 : i64 loc("std/io/core/descriptor.lin":L:C)
    %v26 = arith.cmpi slt, %v24, %v25 : i64 loc("std/io/core/descriptor.lin":L:C)
    cf.cond_br %v26, ^b5, ^b6 loc("std/io/core/descriptor.lin":L:C)
  ^b5:
    %v29 = arith.constant 1 : i64 loc("std/io/core/descriptor.lin":L:C)
    %v30 = arith.constant 0 : i64 loc("std/io/core/descriptor.lin":L:C)
    %v31 = llvm.load %s3 : !llvm.ptr -> i64 loc("std/io/core/descriptor.lin":L:C)
    %v32 = arith.subi %v30, %v31 : i64 loc("std/io/core/descriptor.lin":L:C)
    %k1a = arith.xori %v30, %v31 : i64 loc("std/io/core/descriptor.lin":L:C)
    %k1b = arith.xori %v30, %v32 : i64 loc("std/io/core/descriptor.lin":L:C)
    %k1c = arith.andi %k1a, %k1b : i64 loc("std/io/core/descriptor.lin":L:C)
    %k1z = arith.constant 0 : i64 loc("std/io/core/descriptor.lin":L:C)
    %k1 = arith.cmpi slt, %k1c, %k1z : i64 loc("std/io/core/descriptor.lin":L:C)
    cf.cond_br %k1, ^t1, ^c1 loc("std/io/core/descriptor.lin":L:C)
  ^t1:
    %tk1 = arith.constant 0 : i32 loc("std/io/core/descriptor.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file5 : !llvm.ptr loc("std/io/core/descriptor.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/io/core/descriptor.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/io/core/descriptor.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/io/core/descriptor.lin":L:C)
    llvm.unreachable loc("std/io/core/descriptor.lin":L:C)
  ^c1:
    %p33 = arith.constant 0 : i64 loc("std/io/core/descriptor.lin":L:C)
    %v33 = arith.addi %v32, %p33 : i64 loc("std/io/core/descriptor.lin":L:C)
    %k2m = arith.constant 2147483647 : i64 loc("std/io/core/descriptor.lin":L:C)
    %k2 = arith.cmpi sgt, %v33, %k2m : i64 loc("std/io/core/descriptor.lin":L:C)
    cf.cond_br %k2, ^t2, ^c2 loc("std/io/core/descriptor.lin":L:C)
  ^t2:
    %tk2 = arith.constant 2 : i32 loc("std/io/core/descriptor.lin":L:C)
    %tf2 = llvm.mlir.addressof @linea_file5 : !llvm.ptr loc("std/io/core/descriptor.lin":L:C)
    %tl2 = arith.constant L : i32 loc("std/io/core/descriptor.lin":L:C)
    %tc2 = arith.constant C : i32 loc("std/io/core/descriptor.lin":L:C)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("std/io/core/descriptor.lin":L:C)
    llvm.unreachable loc("std/io/core/descriptor.lin":L:C)
  ^c2:
    %k3m = arith.constant -2147483648 : i64 loc("std/io/core/descriptor.lin":L:C)
    %k3 = arith.cmpi slt, %v33, %k3m : i64 loc("std/io/core/descriptor.lin":L:C)
    cf.cond_br %k3, ^t3, ^c3 loc("std/io/core/descriptor.lin":L:C)
  ^t3:
    %tk3 = arith.constant 2 : i32 loc("std/io/core/descriptor.lin":L:C)
    %tf3 = llvm.mlir.addressof @linea_file5 : !llvm.ptr loc("std/io/core/descriptor.lin":L:C)
    %tl3 = arith.constant L : i32 loc("std/io/core/descriptor.lin":L:C)
    %tc3 = arith.constant C : i32 loc("std/io/core/descriptor.lin":L:C)
    func.call @linea_trap(%tk3, %tf3, %tl3, %tc3) : (i32, !llvm.ptr, i32, i32) -> () loc("std/io/core/descriptor.lin":L:C)
    llvm.unreachable loc("std/io/core/descriptor.lin":L:C)
  ^c3:
    %p34 = arith.constant 0 : i64 loc("std/io/core/descriptor.lin":L:C)
    %v34 = arith.addi %v33, %p34 : i64 loc("std/io/core/descriptor.lin":L:C)
    %v35 = arith.constant 0 : i64 loc("std/io/core/descriptor.lin":L:C)
    func.call @"lin.std.io.core;IoError.from_os"(%rs36, %v29, %v34, %v35) : (!llvm.ptr, i64, i64, i64) -> () loc("std/io/core/descriptor.lin":L:C)
    %cl37 = arith.constant 40 : i64 loc("std/io/core/descriptor.lin":L:C)
    "llvm.intr.memcpy"(%s4, %rs36, %cl37) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/descriptor.lin":L:C)
    %v38 = arith.constant 1 : i64 loc("std/io/core/descriptor.lin":L:C)
    llvm.store %v38, %s5 : i64, !llvm.ptr loc("std/io/core/descriptor.lin":L:C)
    %v41 = arith.constant 8 : i64 loc("std/io/core/descriptor.lin":L:C)
    %v42 = llvm.getelementptr %s5[%v41] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/descriptor.lin":L:C)
    %v43 = arith.constant 0 : i64 loc("std/io/core/descriptor.lin":L:C)
    %v45 = arith.constant 0 : i64 loc("std/io/core/descriptor.lin":L:C)
    llvm.store %v45, %v42 : i64, !llvm.ptr loc("std/io/core/descriptor.lin":L:C)
    %v47 = arith.constant 8 : i64 loc("std/io/core/descriptor.lin":L:C)
    %v48 = llvm.getelementptr %v42[%v47] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/descriptor.lin":L:C)
    %v49 = arith.constant 1 : i64 loc("std/io/core/descriptor.lin":L:C)
    llvm.store %v49, %v48 : i64, !llvm.ptr loc("std/io/core/descriptor.lin":L:C)
    %v51 = arith.constant 8 : i64 loc("std/io/core/descriptor.lin":L:C)
    %v52 = llvm.getelementptr %v48[%v51] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/descriptor.lin":L:C)
    %cl54 = arith.constant 40 : i64 loc("std/io/core/descriptor.lin":L:C)
    "llvm.intr.memcpy"(%v52, %s4, %cl54) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/descriptor.lin":L:C)
    %v55 = arith.constant 56 : i64 loc("std/io/core/descriptor.lin":L:C)
    %v56 = llvm.getelementptr %v42[%v55] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/descriptor.lin":L:C)
    %v57 = arith.constant 0 : i64 loc("std/io/core/descriptor.lin":L:C)
    llvm.store %v57, %v56 : i64, !llvm.ptr loc("std/io/core/descriptor.lin":L:C)
    %rl59 = arith.constant 72 : i64 loc("std/io/core/descriptor.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s5, %rl59) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/descriptor.lin":L:C)
    func.return loc("std/io/core/descriptor.lin":L:C)
  ^b6:
    %v62 = arith.constant 0 : i64 loc("std/io/core/descriptor.lin":L:C)
    llvm.store %v62, %s6 : i64, !llvm.ptr loc("std/io/core/descriptor.lin":L:C)
    %v65 = arith.constant 8 : i64 loc("std/io/core/descriptor.lin":L:C)
    %v66 = llvm.getelementptr %s6[%v65] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/descriptor.lin":L:C)
    %v67 = llvm.load %s3 : !llvm.ptr -> i64 loc("std/io/core/descriptor.lin":L:C)
    %k4z = arith.constant 0 : i64 loc("std/io/core/descriptor.lin":L:C)
    %k4 = arith.cmpi slt, %v67, %k4z : i64 loc("std/io/core/descriptor.lin":L:C)
    cf.cond_br %k4, ^t4, ^c4 loc("std/io/core/descriptor.lin":L:C)
  ^t4:
    %tk4 = arith.constant 2 : i32 loc("std/io/core/descriptor.lin":L:C)
    %tf4 = llvm.mlir.addressof @linea_file5 : !llvm.ptr loc("std/io/core/descriptor.lin":L:C)
    %tl4 = arith.constant L : i32 loc("std/io/core/descriptor.lin":L:C)
    %tc4 = arith.constant C : i32 loc("std/io/core/descriptor.lin":L:C)
    func.call @linea_trap(%tk4, %tf4, %tl4, %tc4) : (i32, !llvm.ptr, i32, i32) -> () loc("std/io/core/descriptor.lin":L:C)
    llvm.unreachable loc("std/io/core/descriptor.lin":L:C)
  ^c4:
    %p68 = arith.constant 0 : i64 loc("std/io/core/descriptor.lin":L:C)
    %v68 = arith.addi %v67, %p68 : i64 loc("std/io/core/descriptor.lin":L:C)
    llvm.store %v68, %v66 : i64, !llvm.ptr loc("std/io/core/descriptor.lin":L:C)
    %rl70 = arith.constant 72 : i64 loc("std/io/core/descriptor.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s6, %rl70) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/descriptor.lin":L:C)
    func.return loc("std/io/core/descriptor.lin":L:C)
  }
  func.func private @"lin.std.fmt;format_signed[std.io.core.Descriptor]"(%sret: !llvm.ptr, %a0: i64, %a1: !llvm.ptr) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 16 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 48 : i64
    %s3 = llvm.alloca %z3 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z4 = arith.constant 1 : i64
    %s4 = llvm.alloca %z4 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z5 = arith.constant 1 : i64
    %s5 = llvm.alloca %z5 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z6 = arith.constant 1 : i64
    %s6 = llvm.alloca %z6 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z7 = arith.constant 1 : i64
    %s7 = llvm.alloca %z7 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z8 = arith.constant 1 : i64
    %s8 = llvm.alloca %z8 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z9 = arith.constant 1 : i64
    %s9 = llvm.alloca %z9 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z10 = arith.constant 48 : i64
    %s10 = llvm.alloca %z10 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z11 = arith.constant 48 : i64
    %s11 = llvm.alloca %z11 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : i64, !llvm.ptr
    llvm.store %a1, %s1 : !llvm.ptr, !llvm.ptr
    %rz14 = arith.constant 48 : i64
    %rs14 = llvm.alloca %rz14 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz74 = arith.constant 16 : i64
    %rs74 = llvm.alloca %rz74 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz75 = arith.constant 48 : i64
    %rs75 = llvm.alloca %rz75 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v1 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v2 = arith.cmpi slt, %v0, %v1 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %v2, ^b1, ^b2 loc("std/fmt/decimal.lin":L:C)
  ^b1:
    %v4 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %ba6 = llvm.mlir.addressof @linea_str46 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v6 = llvm.ptrtoint %ba6 : !llvm.ptr to i64 loc("std/fmt/decimal.lin":L:C)
    %v7 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v6, %s2 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v10 = arith.constant 1 : i64 loc("std/fmt/decimal.lin":L:C)
    %v11 = arith.constant 8 : i64 loc("std/fmt/decimal.lin":L:C)
    %v12 = llvm.getelementptr %s2[%v11] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v10, %v12 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs14, %v4, %s2) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/fmt/decimal.lin":L:C)
    %v15 = llvm.load %rs14 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v16 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v17 = arith.cmpi eq, %v15, %v16 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %v17, ^b4, ^b5 loc("std/fmt/decimal.lin":L:C)
  ^b2:
    cf.br ^b3 loc("std/fmt/decimal.lin":L:C)
  ^b3:
    %v33 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v34 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v35 = func.call @"lin.std.fmt;scale"(%v34) : (i64) -> i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v35, %s4 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v37 = arith.constant 1 : i1 loc("std/fmt/decimal.lin":L:C)
    %sw38 = arith.extui %v37 : i1 to i8 loc("std/fmt/decimal.lin":L:C)
    llvm.store %sw38, %s5 : i8, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    cf.br ^b6 loc("std/fmt/decimal.lin":L:C)
  ^b4:
    %v28 = arith.constant 8 : i64 loc("std/fmt/decimal.lin":L:C)
    %v29 = llvm.getelementptr %rs14[%v28] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/fmt/decimal.lin":L:C)
    %v30 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.br ^b3 loc("std/fmt/decimal.lin":L:C)
  ^b5:
    %v19 = arith.constant 8 : i64 loc("std/fmt/decimal.lin":L:C)
    %v20 = llvm.getelementptr %rs14[%v19] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/fmt/decimal.lin":L:C)
    %v21 = arith.constant 1 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v21, %s3 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v24 = arith.constant 8 : i64 loc("std/fmt/decimal.lin":L:C)
    %v25 = llvm.getelementptr %s3[%v24] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/fmt/decimal.lin":L:C)
    %cl26 = arith.constant 40 : i64 loc("std/fmt/decimal.lin":L:C)
    "llvm.intr.memcpy"(%v25, %v20, %cl26) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/fmt/decimal.lin":L:C)
    %rl27 = arith.constant 48 : i64 loc("std/fmt/decimal.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s3, %rl27) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/fmt/decimal.lin":L:C)
    func.return loc("std/fmt/decimal.lin":L:C)
  ^b6:
    %v40 = llvm.load %s4 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v41 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v42 = arith.cmpi sgt, %v40, %v41 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %v42, ^b7, ^b8 loc("std/fmt/decimal.lin":L:C)
  ^b7:
    %v44 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v45 = llvm.load %s4 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %k1z = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %k1 = arith.cmpi eq, %v45, %k1z : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k1, ^t1, ^c1 loc("std/fmt/decimal.lin":L:C)
  ^t1:
    %tk1 = arith.constant 1 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file9 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c1:
    %p46 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v46 = arith.addi %v45, %p46 : i64 loc("std/fmt/decimal.lin":L:C)
    %k2ca = arith.constant -9223372036854775808 : i64 loc("std/fmt/decimal.lin":L:C)
    %k2a = arith.cmpi eq, %v44, %k2ca : i64 loc("std/fmt/decimal.lin":L:C)
    %k2cb = arith.constant -1 : i64 loc("std/fmt/decimal.lin":L:C)
    %k2b = arith.cmpi eq, %v46, %k2cb : i64 loc("std/fmt/decimal.lin":L:C)
    %k2 = arith.andi %k2a, %k2b : i1 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k2, ^t2, ^c2 loc("std/fmt/decimal.lin":L:C)
  ^t2:
    %tk2 = arith.constant 0 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf2 = llvm.mlir.addressof @linea_file9 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl2 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc2 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c2:
    %v47 = arith.divsi %v44, %v46 : i64 loc("std/fmt/decimal.lin":L:C)
    %p48 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v48 = arith.addi %v47, %p48 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v48, %s6 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v50 = llvm.load %s6 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v51 = arith.constant 100 : i64 loc("std/fmt/decimal.lin":L:C)
    %k3z = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %k3 = arith.cmpi eq, %v51, %k3z : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k3, ^t3, ^c3 loc("std/fmt/decimal.lin":L:C)
  ^t3:
    %tk3 = arith.constant 1 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf3 = llvm.mlir.addressof @linea_file9 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl3 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc3 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk3, %tf3, %tl3, %tc3) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c3:
    %p52 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v52 = arith.addi %v51, %p52 : i64 loc("std/fmt/decimal.lin":L:C)
    %k4ca = arith.constant -9223372036854775808 : i64 loc("std/fmt/decimal.lin":L:C)
    %k4a = arith.cmpi eq, %v50, %k4ca : i64 loc("std/fmt/decimal.lin":L:C)
    %k4cb = arith.constant -1 : i64 loc("std/fmt/decimal.lin":L:C)
    %k4b = arith.cmpi eq, %v52, %k4cb : i64 loc("std/fmt/decimal.lin":L:C)
    %k4 = arith.andi %k4a, %k4b : i1 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k4, ^t4, ^c4 loc("std/fmt/decimal.lin":L:C)
  ^t4:
    %tk4 = arith.constant 0 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf4 = llvm.mlir.addressof @linea_file9 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl4 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc4 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk4, %tf4, %tl4, %tc4) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c4:
    %v53 = arith.remsi %v50, %v52 : i64 loc("std/fmt/decimal.lin":L:C)
    %p54 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v54 = arith.addi %v53, %p54 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v54, %s7 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v56 = llvm.load %s7 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v57 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v58 = arith.cmpi slt, %v56, %v57 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %v58, ^b9, ^b10 loc("std/fmt/decimal.lin":L:C)
  ^b8:
    %v103 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v104 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v104, %s11 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v107 = arith.constant 8 : i64 loc("std/fmt/decimal.lin":L:C)
    %v108 = llvm.getelementptr %s11[%v107] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/fmt/decimal.lin":L:C)
    %v109 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %rl110 = arith.constant 48 : i64 loc("std/fmt/decimal.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s11, %rl110) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/fmt/decimal.lin":L:C)
    func.return loc("std/fmt/decimal.lin":L:C)
  ^b9:
    %v60 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v61 = llvm.load %s7 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v62 = arith.subi %v60, %v61 : i64 loc("std/fmt/decimal.lin":L:C)
    %k5a = arith.xori %v60, %v61 : i64 loc("std/fmt/decimal.lin":L:C)
    %k5b = arith.xori %v60, %v62 : i64 loc("std/fmt/decimal.lin":L:C)
    %k5c = arith.andi %k5a, %k5b : i64 loc("std/fmt/decimal.lin":L:C)
    %k5z = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %k5 = arith.cmpi slt, %k5c, %k5z : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k5, ^t5, ^c5 loc("std/fmt/decimal.lin":L:C)
  ^t5:
    %tk5 = arith.constant 0 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf5 = llvm.mlir.addressof @linea_file9 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl5 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc5 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk5, %tf5, %tl5, %tc5) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c5:
    %p63 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v63 = arith.addi %v62, %p63 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v63, %s9 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    cf.br ^b11 loc("std/fmt/decimal.lin":L:C)
  ^b10:
    %v66 = llvm.load %s7 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v66, %s9 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    cf.br ^b11 loc("std/fmt/decimal.lin":L:C)
  ^b11:
    %v69 = llvm.load %s9 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v69, %s8 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v71 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v72 = llvm.load %s8 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %lw73 = llvm.load %s5 : !llvm.ptr -> i8 loc("std/fmt/decimal.lin":L:C)
    %lz73 = arith.constant 0 : i8 loc("std/fmt/decimal.lin":L:C)
    %v73 = arith.cmpi ne, %lw73, %lz73 : i8 loc("std/fmt/decimal.lin":L:C)
    func.call @"lin.std.fmt;digits"(%rs74, %v72, %v73) : (!llvm.ptr, i64, i1) -> () loc("std/fmt/decimal.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs75, %v71, %rs74) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/fmt/decimal.lin":L:C)
    %v76 = llvm.load %rs75 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v77 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v78 = arith.cmpi eq, %v76, %v77 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %v78, ^b12, ^b13 loc("std/fmt/decimal.lin":L:C)
  ^b12:
    %v89 = arith.constant 8 : i64 loc("std/fmt/decimal.lin":L:C)
    %v90 = llvm.getelementptr %rs75[%v89] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/fmt/decimal.lin":L:C)
    %v91 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v92 = arith.constant 0 : i1 loc("std/fmt/decimal.lin":L:C)
    %sw93 = arith.extui %v92 : i1 to i8 loc("std/fmt/decimal.lin":L:C)
    llvm.store %sw93, %s5 : i8, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v94 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v95 = llvm.load %s4 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v96 = arith.constant 100 : i64 loc("std/fmt/decimal.lin":L:C)
    %k6z = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %k6 = arith.cmpi eq, %v96, %k6z : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k6, ^t6, ^c6 loc("std/fmt/decimal.lin":L:C)
  ^t6:
    %tk6 = arith.constant 1 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf6 = llvm.mlir.addressof @linea_file9 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl6 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc6 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk6, %tf6, %tl6, %tc6) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c6:
    %p97 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v97 = arith.addi %v96, %p97 : i64 loc("std/fmt/decimal.lin":L:C)
    %k7ca = arith.constant -9223372036854775808 : i64 loc("std/fmt/decimal.lin":L:C)
    %k7a = arith.cmpi eq, %v95, %k7ca : i64 loc("std/fmt/decimal.lin":L:C)
    %k7cb = arith.constant -1 : i64 loc("std/fmt/decimal.lin":L:C)
    %k7b = arith.cmpi eq, %v97, %k7cb : i64 loc("std/fmt/decimal.lin":L:C)
    %k7 = arith.andi %k7a, %k7b : i1 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k7, ^t7, ^c7 loc("std/fmt/decimal.lin":L:C)
  ^t7:
    %tk7 = arith.constant 0 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf7 = llvm.mlir.addressof @linea_file9 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl7 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc7 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk7, %tf7, %tl7, %tc7) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c7:
    %v98 = arith.divsi %v95, %v97 : i64 loc("std/fmt/decimal.lin":L:C)
    %p99 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v99 = arith.addi %v98, %p99 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v99, %s4 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v101 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.br ^b6 loc("std/fmt/decimal.lin":L:C)
  ^b13:
    %v80 = arith.constant 8 : i64 loc("std/fmt/decimal.lin":L:C)
    %v81 = llvm.getelementptr %rs75[%v80] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/fmt/decimal.lin":L:C)
    %v82 = arith.constant 1 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v82, %s10 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v85 = arith.constant 8 : i64 loc("std/fmt/decimal.lin":L:C)
    %v86 = llvm.getelementptr %s10[%v85] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/fmt/decimal.lin":L:C)
    %cl87 = arith.constant 40 : i64 loc("std/fmt/decimal.lin":L:C)
    "llvm.intr.memcpy"(%v86, %v81, %cl87) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/fmt/decimal.lin":L:C)
    %rl88 = arith.constant 48 : i64 loc("std/fmt/decimal.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s10, %rl88) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/fmt/decimal.lin":L:C)
    func.return loc("std/fmt/decimal.lin":L:C)
  }
  func.func private @"lin.std.fmt;format_unsigned[std.io.core.Descriptor]"(%sret: !llvm.ptr, %a0: i64, %a1: !llvm.ptr) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 1 : i64
    %s3 = llvm.alloca %z3 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z4 = arith.constant 1 : i64
    %s4 = llvm.alloca %z4 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z5 = arith.constant 1 : i64
    %s5 = llvm.alloca %z5 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z6 = arith.constant 48 : i64
    %s6 = llvm.alloca %z6 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z7 = arith.constant 48 : i64
    %s7 = llvm.alloca %z7 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : i64, !llvm.ptr
    llvm.store %a1, %s1 : !llvm.ptr, !llvm.ptr
    %rz26 = arith.constant 16 : i64
    %rs26 = llvm.alloca %rz26 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz27 = arith.constant 48 : i64
    %rs27 = llvm.alloca %rz27 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v1 = func.call @"lin.std.fmt;scale_unsigned"(%v0) : (i64) -> i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v1, %s2 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v3 = arith.constant 1 : i1 loc("std/fmt/decimal.lin":L:C)
    %sw4 = arith.extui %v3 : i1 to i8 loc("std/fmt/decimal.lin":L:C)
    llvm.store %sw4, %s3 : i8, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    cf.br ^b1 loc("std/fmt/decimal.lin":L:C)
  ^b1:
    %v6 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v7 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v8 = arith.cmpi ugt, %v6, %v7 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %v8, ^b2, ^b3 loc("std/fmt/decimal.lin":L:C)
  ^b2:
    %v10 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v11 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %k1z = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %k1 = arith.cmpi eq, %v11, %k1z : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k1, ^t1, ^c1 loc("std/fmt/decimal.lin":L:C)
  ^t1:
    %tk1 = arith.constant 1 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file9 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c1:
    %p12 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v12 = arith.addi %v11, %p12 : i64 loc("std/fmt/decimal.lin":L:C)
    %v13 = arith.divui %v10, %v12 : i64 loc("std/fmt/decimal.lin":L:C)
    %p14 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v14 = arith.addi %v13, %p14 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v14, %s4 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v16 = llvm.load %s4 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v17 = arith.constant 100 : i64 loc("std/fmt/decimal.lin":L:C)
    %k2z = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %k2 = arith.cmpi eq, %v17, %k2z : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k2, ^t2, ^c2 loc("std/fmt/decimal.lin":L:C)
  ^t2:
    %tk2 = arith.constant 1 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf2 = llvm.mlir.addressof @linea_file9 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl2 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc2 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c2:
    %p18 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v18 = arith.addi %v17, %p18 : i64 loc("std/fmt/decimal.lin":L:C)
    %v19 = arith.remui %v16, %v18 : i64 loc("std/fmt/decimal.lin":L:C)
    %p20 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v20 = arith.addi %v19, %p20 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v20, %s5 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v22 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v23 = llvm.load %s5 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %k3z = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %k3 = arith.cmpi slt, %v23, %k3z : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k3, ^t3, ^c3 loc("std/fmt/decimal.lin":L:C)
  ^t3:
    %tk3 = arith.constant 2 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf3 = llvm.mlir.addressof @linea_file9 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl3 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc3 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk3, %tf3, %tl3, %tc3) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c3:
    %p24 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v24 = arith.addi %v23, %p24 : i64 loc("std/fmt/decimal.lin":L:C)
    %lw25 = llvm.load %s3 : !llvm.ptr -> i8 loc("std/fmt/decimal.lin":L:C)
    %lz25 = arith.constant 0 : i8 loc("std/fmt/decimal.lin":L:C)
    %v25 = arith.cmpi ne, %lw25, %lz25 : i8 loc("std/fmt/decimal.lin":L:C)
    func.call @"lin.std.fmt;digits"(%rs26, %v24, %v25) : (!llvm.ptr, i64, i1) -> () loc("std/fmt/decimal.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%rs27, %v22, %rs26) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/fmt/decimal.lin":L:C)
    %v28 = llvm.load %rs27 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v29 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v30 = arith.cmpi eq, %v28, %v29 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %v30, ^b4, ^b5 loc("std/fmt/decimal.lin":L:C)
  ^b3:
    %v55 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v56 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v56, %s7 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v59 = arith.constant 8 : i64 loc("std/fmt/decimal.lin":L:C)
    %v60 = llvm.getelementptr %s7[%v59] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/fmt/decimal.lin":L:C)
    %v61 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %rl62 = arith.constant 48 : i64 loc("std/fmt/decimal.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s7, %rl62) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/fmt/decimal.lin":L:C)
    func.return loc("std/fmt/decimal.lin":L:C)
  ^b4:
    %v41 = arith.constant 8 : i64 loc("std/fmt/decimal.lin":L:C)
    %v42 = llvm.getelementptr %rs27[%v41] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/fmt/decimal.lin":L:C)
    %v43 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v44 = arith.constant 0 : i1 loc("std/fmt/decimal.lin":L:C)
    %sw45 = arith.extui %v44 : i1 to i8 loc("std/fmt/decimal.lin":L:C)
    llvm.store %sw45, %s3 : i8, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v46 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v47 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v48 = arith.constant 100 : i64 loc("std/fmt/decimal.lin":L:C)
    %k4z = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %k4 = arith.cmpi eq, %v48, %k4z : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k4, ^t4, ^c4 loc("std/fmt/decimal.lin":L:C)
  ^t4:
    %tk4 = arith.constant 1 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf4 = llvm.mlir.addressof @linea_file9 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl4 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc4 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk4, %tf4, %tl4, %tc4) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c4:
    %p49 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v49 = arith.addi %v48, %p49 : i64 loc("std/fmt/decimal.lin":L:C)
    %v50 = arith.divui %v47, %v49 : i64 loc("std/fmt/decimal.lin":L:C)
    %p51 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v51 = arith.addi %v50, %p51 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v51, %s2 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v53 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.br ^b1 loc("std/fmt/decimal.lin":L:C)
  ^b5:
    %v32 = arith.constant 8 : i64 loc("std/fmt/decimal.lin":L:C)
    %v33 = llvm.getelementptr %rs27[%v32] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/fmt/decimal.lin":L:C)
    %v34 = arith.constant 1 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v34, %s6 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v37 = arith.constant 8 : i64 loc("std/fmt/decimal.lin":L:C)
    %v38 = llvm.getelementptr %s6[%v37] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/fmt/decimal.lin":L:C)
    %cl39 = arith.constant 40 : i64 loc("std/fmt/decimal.lin":L:C)
    "llvm.intr.memcpy"(%v38, %v33, %cl39) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/fmt/decimal.lin":L:C)
    %rl40 = arith.constant 48 : i64 loc("std/fmt/decimal.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s6, %rl40) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/fmt/decimal.lin":L:C)
    func.return loc("std/fmt/decimal.lin":L:C)
  }
  func.func private @"lin.std.mem;write_slice_fd"(%a0: !llvm.ptr, %a1: i64) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i32 {alignment = 4 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : !llvm.ptr, !llvm.ptr
    %pw1 = arith.trunci %a1 : i64 to i32
    llvm.store %pw1, %s1 : i32, !llvm.ptr
    cf.br ^b0
  ^b0:
    %lw0 = llvm.load %s1 : !llvm.ptr -> i32 loc("std/mem/fd.lin":L:C)
    %v0 = arith.extsi %lw0 : i32 to i64 loc("std/mem/fd.lin":L:C)
    %v1 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/mem/fd.lin":L:C)
    %v2 = arith.constant 0 : i64 loc("std/mem/fd.lin":L:C)
    %v4 = llvm.load %v1 : !llvm.ptr -> i64 loc("std/mem/fd.lin":L:C)
    %v5 = llvm.load %s0 : !llvm.ptr -> !llvm.ptr loc("std/mem/fd.lin":L:C)
    %v6 = arith.constant 8 : i64 loc("std/mem/fd.lin":L:C)
    %v7 = llvm.getelementptr %v5[%v6] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/mem/fd.lin":L:C)
    %v8 = llvm.load %v7 : !llvm.ptr -> i64 loc("std/mem/fd.lin":L:C)
    %va9_0 = arith.trunci %v0 : i64 to i32 loc("std/mem/fd.lin":L:C)
    %v9 = func.call @linea_write_some(%va9_0, %v4, %v8) : (i32, i64, i64) -> i64 loc("std/mem/fd.lin":L:C)
    func.return %v9 : i64 loc("std/mem/fd.lin":L:C)
  }
  func.func private @"lin.std.io.core;IoError.from_os"(%sret: !llvm.ptr, %a0: i64, %a1: i64, %a2: i64) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i32 {alignment = 4 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 1 : i64
    %s3 = llvm.alloca %z3 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z4 = arith.constant 1 : i64
    %s4 = llvm.alloca %z4 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z5 = arith.constant 40 : i64
    %s5 = llvm.alloca %z5 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : i64, !llvm.ptr
    %pw1 = arith.trunci %a1 : i64 to i32
    llvm.store %pw1, %s1 : i32, !llvm.ptr
    llvm.store %a2, %s2 : i64, !llvm.ptr
    cf.br ^b0
  ^b0:
    %lw0 = llvm.load %s1 : !llvm.ptr -> i32 loc("std/io/core/error.lin":L:C)
    %v0 = arith.extsi %lw0 : i32 to i64 loc("std/io/core/error.lin":L:C)
    %va1_0 = arith.trunci %v0 : i64 to i32 loc("std/io/core/error.lin":L:C)
    %vr1 = func.call @linea_io_category(%va1_0) : (i32) -> i8 loc("std/io/core/error.lin":L:C)
    %v1 = arith.extui %vr1 : i8 to i64 loc("std/io/core/error.lin":L:C)
    %v2 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v3 = arith.cmpi eq, %v1, %v2 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v3, ^b2, ^b3 loc("std/io/core/error.lin":L:C)
  ^b1:
    %v115 = llvm.load %s4 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v115, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v118 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v120 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v120, %s5 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v122 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v123 = llvm.getelementptr %s5[%v122] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v124 = llvm.load %s3 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v124, %v123 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v126 = arith.constant 16 : i64 loc("std/io/core/error.lin":L:C)
    %v127 = llvm.getelementptr %s5[%v126] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v128 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v128, %v127 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v130 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v131 = llvm.getelementptr %v127[%v130] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %lw132 = llvm.load %s1 : !llvm.ptr -> i32 loc("std/io/core/error.lin":L:C)
    %v132 = arith.extsi %lw132 : i32 to i64 loc("std/io/core/error.lin":L:C)
    %iw133 = arith.trunci %v132 : i64 to i32 loc("std/io/core/error.lin":L:C)
    llvm.store %iw133, %v131 : i32, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v134 = arith.constant 32 : i64 loc("std/io/core/error.lin":L:C)
    %v135 = llvm.getelementptr %s5[%v134] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v136 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v136, %v135 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %rl138 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s5, %rl138) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b2:
    %v5 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v5, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b3:
    %v8 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v9 = arith.cmpi eq, %v1, %v8 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v9, ^b4, ^b5 loc("std/io/core/error.lin":L:C)
  ^b4:
    %v11 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v11, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b5:
    %v14 = arith.constant 3 : i64 loc("std/io/core/error.lin":L:C)
    %v15 = arith.cmpi eq, %v1, %v14 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v15, ^b6, ^b7 loc("std/io/core/error.lin":L:C)
  ^b6:
    %v17 = arith.constant 3 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v17, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b7:
    %v20 = arith.constant 4 : i64 loc("std/io/core/error.lin":L:C)
    %v21 = arith.cmpi eq, %v1, %v20 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v21, ^b8, ^b9 loc("std/io/core/error.lin":L:C)
  ^b8:
    %v23 = arith.constant 4 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v23, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b9:
    %v26 = arith.constant 5 : i64 loc("std/io/core/error.lin":L:C)
    %v27 = arith.cmpi eq, %v1, %v26 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v27, ^b10, ^b11 loc("std/io/core/error.lin":L:C)
  ^b10:
    %v29 = arith.constant 5 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v29, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b11:
    %v32 = arith.constant 6 : i64 loc("std/io/core/error.lin":L:C)
    %v33 = arith.cmpi eq, %v1, %v32 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v33, ^b12, ^b13 loc("std/io/core/error.lin":L:C)
  ^b12:
    %v35 = arith.constant 6 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v35, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b13:
    %v38 = arith.constant 7 : i64 loc("std/io/core/error.lin":L:C)
    %v39 = arith.cmpi eq, %v1, %v38 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v39, ^b14, ^b15 loc("std/io/core/error.lin":L:C)
  ^b14:
    %v41 = arith.constant 7 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v41, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b15:
    %v44 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v45 = arith.cmpi eq, %v1, %v44 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v45, ^b16, ^b17 loc("std/io/core/error.lin":L:C)
  ^b16:
    %v47 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v47, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b17:
    %v50 = arith.constant 9 : i64 loc("std/io/core/error.lin":L:C)
    %v51 = arith.cmpi eq, %v1, %v50 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v51, ^b18, ^b19 loc("std/io/core/error.lin":L:C)
  ^b18:
    %v53 = arith.constant 9 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v53, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b19:
    %v56 = arith.constant 10 : i64 loc("std/io/core/error.lin":L:C)
    %v57 = arith.cmpi eq, %v1, %v56 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v57, ^b20, ^b21 loc("std/io/core/error.lin":L:C)
  ^b20:
    %v59 = arith.constant 10 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v59, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b21:
    %v62 = arith.constant 11 : i64 loc("std/io/core/error.lin":L:C)
    %v63 = arith.cmpi eq, %v1, %v62 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v63, ^b22, ^b23 loc("std/io/core/error.lin":L:C)
  ^b22:
    %v65 = arith.constant 11 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v65, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b23:
    %v68 = arith.constant 12 : i64 loc("std/io/core/error.lin":L:C)
    %v69 = arith.cmpi eq, %v1, %v68 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v69, ^b24, ^b25 loc("std/io/core/error.lin":L:C)
  ^b24:
    %v71 = arith.constant 12 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v71, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b25:
    %v74 = arith.constant 13 : i64 loc("std/io/core/error.lin":L:C)
    %v75 = arith.cmpi eq, %v1, %v74 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v75, ^b26, ^b27 loc("std/io/core/error.lin":L:C)
  ^b26:
    %v77 = arith.constant 13 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v77, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b27:
    %v80 = arith.constant 14 : i64 loc("std/io/core/error.lin":L:C)
    %v81 = arith.cmpi eq, %v1, %v80 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v81, ^b28, ^b29 loc("std/io/core/error.lin":L:C)
  ^b28:
    %v83 = arith.constant 14 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v83, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b29:
    %v86 = arith.constant 15 : i64 loc("std/io/core/error.lin":L:C)
    %v87 = arith.cmpi eq, %v1, %v86 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v87, ^b30, ^b31 loc("std/io/core/error.lin":L:C)
  ^b30:
    %v89 = arith.constant 17 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v89, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b31:
    %v92 = arith.constant 16 : i64 loc("std/io/core/error.lin":L:C)
    %v93 = arith.cmpi eq, %v1, %v92 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v93, ^b32, ^b33 loc("std/io/core/error.lin":L:C)
  ^b32:
    %v95 = arith.constant 18 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v95, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b33:
    %v98 = arith.constant 17 : i64 loc("std/io/core/error.lin":L:C)
    %v99 = arith.cmpi eq, %v1, %v98 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v99, ^b34, ^b35 loc("std/io/core/error.lin":L:C)
  ^b34:
    %v101 = arith.constant 19 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v101, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b35:
    %v104 = arith.constant 18 : i64 loc("std/io/core/error.lin":L:C)
    %v105 = arith.cmpi eq, %v1, %v104 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v105, ^b36, ^b37 loc("std/io/core/error.lin":L:C)
  ^b36:
    %v107 = arith.constant 20 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v107, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b37:
    cf.br ^b38 loc("std/io/core/error.lin":L:C)
  ^b38:
    %v111 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v111, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  }
  func.func private @"lin.std.fmt;scale"(%a0: i64) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : i64, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 1 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v0, %s1 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    cf.br ^b1 loc("std/fmt/decimal.lin":L:C)
  ^b1:
    %v3 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v4 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %k1z = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %k1 = arith.cmpi eq, %v4, %k1z : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k1, ^t1, ^c1 loc("std/fmt/decimal.lin":L:C)
  ^t1:
    %tk1 = arith.constant 1 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file9 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c1:
    %p5 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v5 = arith.addi %v4, %p5 : i64 loc("std/fmt/decimal.lin":L:C)
    %k2ca = arith.constant -9223372036854775808 : i64 loc("std/fmt/decimal.lin":L:C)
    %k2a = arith.cmpi eq, %v3, %k2ca : i64 loc("std/fmt/decimal.lin":L:C)
    %k2cb = arith.constant -1 : i64 loc("std/fmt/decimal.lin":L:C)
    %k2b = arith.cmpi eq, %v5, %k2cb : i64 loc("std/fmt/decimal.lin":L:C)
    %k2 = arith.andi %k2a, %k2b : i1 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k2, ^t2, ^c2 loc("std/fmt/decimal.lin":L:C)
  ^t2:
    %tk2 = arith.constant 0 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf2 = llvm.mlir.addressof @linea_file9 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl2 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc2 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c2:
    %v6 = arith.divsi %v3, %v5 : i64 loc("std/fmt/decimal.lin":L:C)
    %p7 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v7 = arith.addi %v6, %p7 : i64 loc("std/fmt/decimal.lin":L:C)
    %v8 = arith.constant 100 : i64 loc("std/fmt/decimal.lin":L:C)
    %k3z = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %k3 = arith.cmpi eq, %v8, %k3z : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k3, ^t3, ^c3 loc("std/fmt/decimal.lin":L:C)
  ^t3:
    %tk3 = arith.constant 1 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf3 = llvm.mlir.addressof @linea_file9 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl3 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc3 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk3, %tf3, %tl3, %tc3) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c3:
    %p9 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v9 = arith.addi %v8, %p9 : i64 loc("std/fmt/decimal.lin":L:C)
    %k4ca = arith.constant -9223372036854775808 : i64 loc("std/fmt/decimal.lin":L:C)
    %k4a = arith.cmpi eq, %v7, %k4ca : i64 loc("std/fmt/decimal.lin":L:C)
    %k4cb = arith.constant -1 : i64 loc("std/fmt/decimal.lin":L:C)
    %k4b = arith.cmpi eq, %v9, %k4cb : i64 loc("std/fmt/decimal.lin":L:C)
    %k4 = arith.andi %k4a, %k4b : i1 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k4, ^t4, ^c4 loc("std/fmt/decimal.lin":L:C)
  ^t4:
    %tk4 = arith.constant 0 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf4 = llvm.mlir.addressof @linea_file9 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl4 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc4 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk4, %tf4, %tl4, %tc4) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c4:
    %v10 = arith.divsi %v7, %v9 : i64 loc("std/fmt/decimal.lin":L:C)
    %p11 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v11 = arith.addi %v10, %p11 : i64 loc("std/fmt/decimal.lin":L:C)
    %v12 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v13 = arith.cmpi ne, %v11, %v12 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %v13, ^b2, ^b3 loc("std/fmt/decimal.lin":L:C)
  ^b2:
    %v15 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v16 = arith.constant 100 : i64 loc("std/fmt/decimal.lin":L:C)
    %m17 = "llvm.intr.smul.with.overflow"(%v15, %v16) : (i64, i64) -> !llvm.struct<(i64, i1)> loc("std/fmt/decimal.lin":L:C)
    %v17 = llvm.extractvalue %m17[0] : !llvm.struct<(i64, i1)> loc("std/fmt/decimal.lin":L:C)
    %k5 = llvm.extractvalue %m17[1] : !llvm.struct<(i64, i1)> loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k5, ^t5, ^c5 loc("std/fmt/decimal.lin":L:C)
  ^t5:
    %tk5 = arith.constant 0 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf5 = llvm.mlir.addressof @linea_file9 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl5 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc5 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk5, %tf5, %tl5, %tc5) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c5:
    %p18 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v18 = arith.addi %v17, %p18 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v18, %s1 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v20 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.br ^b1 loc("std/fmt/decimal.lin":L:C)
  ^b3:
    %v22 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v23 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    func.return %v23 : i64 loc("std/fmt/decimal.lin":L:C)
  }
  func.func private @"lin.std.fmt;digits"(%sret: !llvm.ptr, %a0: i64, %a1: i1) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 1 : i64
    %s2 = llvm.alloca %z2 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 1 : i64
    %s3 = llvm.alloca %z3 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z4 = arith.constant 1 : i64
    %s4 = llvm.alloca %z4 x i8 {alignment = 1 : i64} : (i64) -> !llvm.ptr
    %z5 = arith.constant 1 : i64
    %s5 = llvm.alloca %z5 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z6 = arith.constant 16 : i64
    %s6 = llvm.alloca %z6 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : i64, !llvm.ptr
    %pw1 = arith.extui %a1 : i1 to i8
    llvm.store %pw1, %s1 : i8, !llvm.ptr
    %rz35 = arith.constant 24 : i64
    %rs35 = llvm.alloca %rz35 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %k1z = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %k1 = arith.cmpi slt, %v0, %k1z : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k1, ^t1, ^c1 loc("std/fmt/decimal.lin":L:C)
  ^t1:
    %tk1 = arith.constant 2 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file9 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c1:
    %p1 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v1 = arith.addi %v0, %p1 : i64 loc("std/fmt/decimal.lin":L:C)
    %v2 = arith.constant 2 : i64 loc("std/fmt/decimal.lin":L:C)
    %m3 = "llvm.intr.umul.with.overflow"(%v1, %v2) : (i64, i64) -> !llvm.struct<(i64, i1)> loc("std/fmt/decimal.lin":L:C)
    %v3 = llvm.extractvalue %m3[0] : !llvm.struct<(i64, i1)> loc("std/fmt/decimal.lin":L:C)
    %k2 = llvm.extractvalue %m3[1] : !llvm.struct<(i64, i1)> loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k2, ^t2, ^c2 loc("std/fmt/decimal.lin":L:C)
  ^t2:
    %tk2 = arith.constant 0 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf2 = llvm.mlir.addressof @linea_file9 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl2 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc2 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c2:
    %p4 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v4 = arith.addi %v3, %p4 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v4, %s2 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %lw6 = llvm.load %s1 : !llvm.ptr -> i8 loc("std/fmt/decimal.lin":L:C)
    %lz6 = arith.constant 0 : i8 loc("std/fmt/decimal.lin":L:C)
    %v6 = arith.cmpi ne, %lw6, %lz6 : i8 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %v6, ^b1, ^b2 loc("std/fmt/decimal.lin":L:C)
  ^b1:
    %v8 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v9 = arith.constant 10 : i64 loc("std/fmt/decimal.lin":L:C)
    %v10 = arith.cmpi slt, %v8, %v9 : i64 loc("std/fmt/decimal.lin":L:C)
    %sw11 = arith.extui %v10 : i1 to i8 loc("std/fmt/decimal.lin":L:C)
    llvm.store %sw11, %s4 : i8, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    cf.br ^b3 loc("std/fmt/decimal.lin":L:C)
  ^b2:
    %v13 = arith.constant 0 : i1 loc("std/fmt/decimal.lin":L:C)
    %sw14 = arith.extui %v13 : i1 to i8 loc("std/fmt/decimal.lin":L:C)
    llvm.store %sw14, %s4 : i8, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    cf.br ^b3 loc("std/fmt/decimal.lin":L:C)
  ^b3:
    %lw16 = llvm.load %s4 : !llvm.ptr -> i8 loc("std/fmt/decimal.lin":L:C)
    %lz16 = arith.constant 0 : i8 loc("std/fmt/decimal.lin":L:C)
    %v16 = arith.cmpi ne, %lw16, %lz16 : i8 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %v16, ^b4, ^b5 loc("std/fmt/decimal.lin":L:C)
  ^b4:
    %v18 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v19 = arith.constant 1 : i64 loc("std/fmt/decimal.lin":L:C)
    %v20 = arith.addi %v18, %v19 : i64 loc("std/fmt/decimal.lin":L:C)
    %k3 = arith.cmpi ult, %v20, %v18 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k3, ^t3, ^c3 loc("std/fmt/decimal.lin":L:C)
  ^t3:
    %tk3 = arith.constant 0 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf3 = llvm.mlir.addressof @linea_file9 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl3 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc3 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk3, %tf3, %tl3, %tc3) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c3:
    %p21 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v21 = arith.addi %v20, %p21 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v21, %s5 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    cf.br ^b6 loc("std/fmt/decimal.lin":L:C)
  ^b5:
    %v24 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v24, %s5 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    cf.br ^b6 loc("std/fmt/decimal.lin":L:C)
  ^b6:
    %v27 = llvm.load %s5 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v27, %s3 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v29 = llvm.mlir.addressof @linea_static0 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v30 = llvm.load %s3 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v31 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v32 = arith.constant 2 : i64 loc("std/fmt/decimal.lin":L:C)
    %v33 = arith.addi %v31, %v32 : i64 loc("std/fmt/decimal.lin":L:C)
    %k4 = arith.cmpi ult, %v33, %v31 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k4, ^t4, ^c4 loc("std/fmt/decimal.lin":L:C)
  ^t4:
    %tk4 = arith.constant 0 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf4 = llvm.mlir.addressof @linea_file9 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl4 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc4 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk4, %tf4, %tl4, %tc4) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c4:
    %p34 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v34 = arith.addi %v33, %p34 : i64 loc("std/fmt/decimal.lin":L:C)
    func.call @"lin.std.text;Str.slice"(%rs35, %v29, %v30, %v34) : (!llvm.ptr, !llvm.ptr, i64, i64) -> () loc("std/fmt/decimal.lin":L:C)
    %ba37 = llvm.mlir.addressof @linea_str48 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v37 = llvm.ptrtoint %ba37 : !llvm.ptr to i64 loc("std/fmt/decimal.lin":L:C)
    %v38 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v37, %s6 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v41 = arith.constant 1 : i64 loc("std/fmt/decimal.lin":L:C)
    %v42 = arith.constant 8 : i64 loc("std/fmt/decimal.lin":L:C)
    %v43 = llvm.getelementptr %s6[%v42] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v41, %v43 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    func.call @"lin.std.option;Option[std.text.Str].unwrap_or"(%sret, %rs35, %s6) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/fmt/decimal.lin":L:C)
    func.return loc("std/fmt/decimal.lin":L:C)
  }
  func.func private @"lin.std.fmt;scale_unsigned"(%a0: i64) -> i64 attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : i64, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v0 = arith.constant 1 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v0, %s1 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    cf.br ^b1 loc("std/fmt/decimal.lin":L:C)
  ^b1:
    %v3 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v4 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %k1z = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %k1 = arith.cmpi eq, %v4, %k1z : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k1, ^t1, ^c1 loc("std/fmt/decimal.lin":L:C)
  ^t1:
    %tk1 = arith.constant 1 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file9 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c1:
    %p5 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v5 = arith.addi %v4, %p5 : i64 loc("std/fmt/decimal.lin":L:C)
    %v6 = arith.divui %v3, %v5 : i64 loc("std/fmt/decimal.lin":L:C)
    %p7 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v7 = arith.addi %v6, %p7 : i64 loc("std/fmt/decimal.lin":L:C)
    %v8 = arith.constant 100 : i64 loc("std/fmt/decimal.lin":L:C)
    %k2z = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %k2 = arith.cmpi eq, %v8, %k2z : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k2, ^t2, ^c2 loc("std/fmt/decimal.lin":L:C)
  ^t2:
    %tk2 = arith.constant 1 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf2 = llvm.mlir.addressof @linea_file9 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl2 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc2 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c2:
    %p9 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v9 = arith.addi %v8, %p9 : i64 loc("std/fmt/decimal.lin":L:C)
    %v10 = arith.divui %v7, %v9 : i64 loc("std/fmt/decimal.lin":L:C)
    %p11 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v11 = arith.addi %v10, %p11 : i64 loc("std/fmt/decimal.lin":L:C)
    %v12 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v13 = arith.cmpi ne, %v11, %v12 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %v13, ^b2, ^b3 loc("std/fmt/decimal.lin":L:C)
  ^b2:
    %v15 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    %v16 = arith.constant 100 : i64 loc("std/fmt/decimal.lin":L:C)
    %m17 = "llvm.intr.umul.with.overflow"(%v15, %v16) : (i64, i64) -> !llvm.struct<(i64, i1)> loc("std/fmt/decimal.lin":L:C)
    %v17 = llvm.extractvalue %m17[0] : !llvm.struct<(i64, i1)> loc("std/fmt/decimal.lin":L:C)
    %k3 = llvm.extractvalue %m17[1] : !llvm.struct<(i64, i1)> loc("std/fmt/decimal.lin":L:C)
    cf.cond_br %k3, ^t3, ^c3 loc("std/fmt/decimal.lin":L:C)
  ^t3:
    %tk3 = arith.constant 0 : i32 loc("std/fmt/decimal.lin":L:C)
    %tf3 = llvm.mlir.addressof @linea_file9 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %tl3 = arith.constant L : i32 loc("std/fmt/decimal.lin":L:C)
    %tc3 = arith.constant C : i32 loc("std/fmt/decimal.lin":L:C)
    func.call @linea_trap(%tk3, %tf3, %tl3, %tc3) : (i32, !llvm.ptr, i32, i32) -> () loc("std/fmt/decimal.lin":L:C)
    llvm.unreachable loc("std/fmt/decimal.lin":L:C)
  ^c3:
    %p18 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v18 = arith.addi %v17, %p18 : i64 loc("std/fmt/decimal.lin":L:C)
    llvm.store %v18, %s1 : i64, !llvm.ptr loc("std/fmt/decimal.lin":L:C)
    %v20 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    cf.br ^b1 loc("std/fmt/decimal.lin":L:C)
  ^b3:
    %v22 = arith.constant 0 : i64 loc("std/fmt/decimal.lin":L:C)
    %v23 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/fmt/decimal.lin":L:C)
    func.return %v23 : i64 loc("std/fmt/decimal.lin":L:C)
  }
  func.func private @"lin.std.option;Option[std.text.Str].unwrap_or"(%sret: !llvm.ptr, %a0: !llvm.ptr, %a1: !llvm.ptr) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 24 : i64
    %s0 = llvm.alloca %z0 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 16 : i64
    %s1 = llvm.alloca %z1 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 16 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 16 : i64
    %s3 = llvm.alloca %z3 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %pl0 = arith.constant 24 : i64
    "llvm.intr.memcpy"(%s0, %a0, %pl0) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> ()
    %pl1 = arith.constant 16 : i64
    "llvm.intr.memcpy"(%s1, %a1, %pl1) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> ()
    cf.br ^b0
  ^b0:
    %v1 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/option/option.lin":L:C)
    %v2 = arith.constant 1 : i64 loc("std/option/option.lin":L:C)
    %v3 = arith.cmpi eq, %v1, %v2 : i64 loc("std/option/option.lin":L:C)
    cf.cond_br %v3, ^b2, ^b3 loc("std/option/option.lin":L:C)
  ^b1:
    %rl22 = arith.constant 16 : i64 loc("std/option/option.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s2, %rl22) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/option/option.lin":L:C)
    func.return loc("std/option/option.lin":L:C)
  ^b2:
    %v5 = arith.constant 8 : i64 loc("std/option/option.lin":L:C)
    %v6 = llvm.getelementptr %s0[%v5] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/option/option.lin":L:C)
    %cl8 = arith.constant 16 : i64 loc("std/option/option.lin":L:C)
    "llvm.intr.memcpy"(%s3, %v6, %cl8) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/option/option.lin":L:C)
    %cl11 = arith.constant 16 : i64 loc("std/option/option.lin":L:C)
    "llvm.intr.memcpy"(%s2, %s3, %cl11) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/option/option.lin":L:C)
    cf.br ^b1 loc("std/option/option.lin":L:C)
  ^b3:
    %v13 = arith.constant 0 : i64 loc("std/option/option.lin":L:C)
    %v14 = arith.cmpi eq, %v1, %v13 : i64 loc("std/option/option.lin":L:C)
    cf.cond_br %v14, ^b4, ^b5 loc("std/option/option.lin":L:C)
  ^b4:
    %cl18 = arith.constant 16 : i64 loc("std/option/option.lin":L:C)
    "llvm.intr.memcpy"(%s2, %s1, %cl18) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/option/option.lin":L:C)
    cf.br ^b1 loc("std/option/option.lin":L:C)
  ^b5:
    %tk1 = arith.constant 3 : i32 loc("std/option/option.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file4 : !llvm.ptr loc("std/option/option.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/option/option.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/option/option.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/option/option.lin":L:C)
    llvm.unreachable loc("std/option/option.lin":L:C)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
