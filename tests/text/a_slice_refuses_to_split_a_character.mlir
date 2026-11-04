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
  llvm.mlir.global internal constant @linea_str10("Write") : !llvm.array<5 x i8>
  llvm.mlir.global internal constant @linea_str11("Flush") : !llvm.array<5 x i8>
  llvm.mlir.global internal constant @linea_str12("Close") : !llvm.array<5 x i8>
  llvm.mlir.global internal constant @linea_str13("Open") : !llvm.array<4 x i8>
  llvm.mlir.global internal constant @linea_str14("Metadata") : !llvm.array<8 x i8>
  llvm.mlir.global internal constant @linea_str15("Permissions") : !llvm.array<11 x i8>
  llvm.mlir.global internal constant @linea_str16("Publish") : !llvm.array<7 x i8>
  llvm.mlir.global internal constant @linea_str17("Remove") : !llvm.array<6 x i8>
  llvm.mlir.global internal constant @linea_str18("Random") : !llvm.array<6 x i8>
  llvm.mlir.global internal constant @linea_str19("Listen") : !llvm.array<6 x i8>
  llvm.mlir.global internal constant @linea_str20("Accept") : !llvm.array<6 x i8>
  llvm.mlir.global internal constant @linea_str21("Connect") : !llvm.array<7 x i8>
  llvm.mlir.global internal constant @linea_str22("Configure") : !llvm.array<9 x i8>
  llvm.mlir.global internal constant @linea_str23("Other") : !llvm.array<5 x i8>
  llvm.mlir.global internal constant @linea_str24("NotFound") : !llvm.array<8 x i8>
  llvm.mlir.global internal constant @linea_str25("PermissionDenied") : !llvm.array<16 x i8>
  llvm.mlir.global internal constant @linea_str26("AlreadyExists") : !llvm.array<13 x i8>
  llvm.mlir.global internal constant @linea_str27("WouldBlock") : !llvm.array<10 x i8>
  llvm.mlir.global internal constant @linea_str28("BrokenPipe") : !llvm.array<10 x i8>
  llvm.mlir.global internal constant @linea_str29("Interrupted") : !llvm.array<11 x i8>
  llvm.mlir.global internal constant @linea_str30("InvalidInput") : !llvm.array<12 x i8>
  llvm.mlir.global internal constant @linea_str31("NotDirectory") : !llvm.array<12 x i8>
  llvm.mlir.global internal constant @linea_str32("IsDirectory") : !llvm.array<11 x i8>
  llvm.mlir.global internal constant @linea_str33("Unsupported") : !llvm.array<11 x i8>
  llvm.mlir.global internal constant @linea_str34("NoSpace") : !llvm.array<7 x i8>
  llvm.mlir.global internal constant @linea_str35("ResourceExhausted") : !llvm.array<17 x i8>
  llvm.mlir.global internal constant @linea_str36("Symlink") : !llvm.array<7 x i8>
  llvm.mlir.global internal constant @linea_str37("InvalidDescriptor") : !llvm.array<17 x i8>
  llvm.mlir.global internal constant @linea_str38("NoProgress") : !llvm.array<10 x i8>
  llvm.mlir.global internal constant @linea_str39("InvalidProgress") : !llvm.array<15 x i8>
  llvm.mlir.global internal constant @linea_str40("TimedOut") : !llvm.array<8 x i8>
  llvm.mlir.global internal constant @linea_str41("ConnectionReset") : !llvm.array<15 x i8>
  llvm.mlir.global internal constant @linea_str42("ConnectionRefused") : !llvm.array<17 x i8>
  llvm.mlir.global internal constant @linea_str43("AddressInUse") : !llvm.array<12 x i8>
  llvm.mlir.global internal constant @linea_str44("-") : !llvm.array<1 x i8>
  llvm.mlir.global internal constant @linea_str45("00010203040506070809101112131415161718192021222324252627282930313233343536373839404142434445464748495051525354555657585960616263646566676869707172737475767778798081828384858687888990919293949596979899") : !llvm.array<200 x i8>
  llvm.mlir.global internal constant @linea_str46("0") : !llvm.array<1 x i8>
  llvm.mlir.global internal constant @linea_static0() {addr_space = 0 : i32, alignment = 8 : i64} : !linea_static0 {
    %s0 = llvm.mlir.undef : !linea_static0
    %a0 = llvm.mlir.addressof @linea_str45 : !llvm.ptr
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
  func.func private @linea_io_category(i32) -> (i8 {llvm.zeroext})
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
    %rz38 = arith.constant 24 : i64
    %rs38 = llvm.alloca %rz38 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz64 = arith.constant 24 : i64
    %rs64 = llvm.alloca %rz64 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz90 = arith.constant 24 : i64
    %rs90 = llvm.alloca %rz90 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %rz115 = arith.constant 24 : i64
    %rs115 = llvm.alloca %rz115 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
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
    cf.cond_br %v15, ^b3, ^b2 loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
  ^b1:
    %v33 = llvm.load %s2 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
    llvm.store %v33, %s1 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:5)
    %v36 = arith.constant 2 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:44)
    %v37 = arith.constant 3 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:47)
    func.call @"lin.std.text;Str.slice"(%rs38, %s0, %v36, %v37) : (!llvm.ptr, !llvm.ptr, i64, i64) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:31)
    %v39 = llvm.load %rs38 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    %v40 = arith.constant 1 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    %v41 = arith.cmpi eq, %v39, %v40 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    cf.cond_br %v41, ^b8, ^b7 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
  ^b2:
    %v25 = llvm.load %rs12 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
    %v26 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
    %v27 = arith.cmpi eq, %v25, %v26 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
    cf.cond_br %v27, ^b5, ^b4 loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
  ^b3:
    %v17 = arith.constant 8 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
    %v18 = llvm.getelementptr %rs12[%v17] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
    %cl20 = arith.constant 16 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
    "llvm.intr.memcpy"(%s3, %v18, %cl20) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
    %v22 = func.call @"lin.std.text;Str.length"(%s3) : (!llvm.ptr) -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":19:20)
    llvm.store %v22, %s2 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
    cf.br ^b1 loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
  ^b4:
    %tk1 = arith.constant 3 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
    %tf1 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
    %tl1 = arith.constant 18 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
    %tc1 = arith.constant 24 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
    llvm.unreachable loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
  ^b5:
    %v29 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":20:17)
    llvm.store %v29, %s2 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
    cf.br ^b1 loc("tests/text/a_slice_refuses_to_split_a_character.lin":18:24)
  ^b6:
    %v58 = llvm.load %s5 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    llvm.store %v58, %s4 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:5)
    %v61 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:44)
    %v63 = func.call @"lin.std.text;Str.length"(%s0) : (!llvm.ptr) -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:47)
    func.call @"lin.std.text;Str.slice"(%rs64, %s0, %v61, %v63) : (!llvm.ptr, !llvm.ptr, i64, i64) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:31)
    %v65 = llvm.load %rs64 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    %v66 = arith.constant 1 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    %v67 = arith.cmpi eq, %v65, %v66 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    cf.cond_br %v67, ^b13, ^b12 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
  ^b7:
    %v50 = llvm.load %rs38 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    %v51 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    %v52 = arith.cmpi eq, %v50, %v51 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    cf.cond_br %v52, ^b10, ^b9 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
  ^b8:
    %v43 = arith.constant 8 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    %v44 = llvm.getelementptr %rs38[%v43] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    %cl46 = arith.constant 16 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    "llvm.intr.memcpy"(%s6, %v44, %cl46) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    %v47 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":25:20)
    llvm.store %v47, %s5 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    cf.br ^b6 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
  ^b9:
    %tk2 = arith.constant 3 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    %tf2 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    %tl2 = arith.constant 24 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    %tc2 = arith.constant 25 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    llvm.unreachable loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
  ^b10:
    %v54 = arith.constant 1 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":26:17)
    llvm.store %v54, %s5 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
    cf.br ^b6 loc("tests/text/a_slice_refuses_to_split_a_character.lin":24:25)
  ^b11:
    %v85 = llvm.load %s8 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    llvm.store %v85, %s7 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:5)
    %v88 = arith.constant 3 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:48)
    %v89 = arith.constant 2 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:51)
    func.call @"lin.std.text;Str.slice"(%rs90, %s0, %v88, %v89) : (!llvm.ptr, !llvm.ptr, i64, i64) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:35)
    %v91 = llvm.load %rs90 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    %v92 = arith.constant 1 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    %v93 = arith.cmpi eq, %v91, %v92 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    cf.cond_br %v93, ^b18, ^b17 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
  ^b12:
    %v77 = llvm.load %rs64 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    %v78 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    %v79 = arith.cmpi eq, %v77, %v78 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    cf.cond_br %v79, ^b15, ^b14 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
  ^b13:
    %v69 = arith.constant 8 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    %v70 = llvm.getelementptr %rs64[%v69] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    %cl72 = arith.constant 16 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    "llvm.intr.memcpy"(%s9, %v70, %cl72) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    %v74 = func.call @"lin.std.text;Str.length"(%s9) : (!llvm.ptr) -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":32:20)
    llvm.store %v74, %s8 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    cf.br ^b11 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
  ^b14:
    %tk3 = arith.constant 3 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    %tf3 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    %tl3 = arith.constant 31 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    %tc3 = arith.constant 25 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    func.call @linea_trap(%tk3, %tf3, %tl3, %tc3) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    llvm.unreachable loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
  ^b15:
    %v81 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":33:17)
    llvm.store %v81, %s8 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
    cf.br ^b11 loc("tests/text/a_slice_refuses_to_split_a_character.lin":31:25)
  ^b16:
    %v110 = llvm.load %s11 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    llvm.store %v110, %s10 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:5)
    %v113 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:43)
    %v114 = arith.constant 99 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:46)
    func.call @"lin.std.text;Str.slice"(%rs115, %s0, %v113, %v114) : (!llvm.ptr, !llvm.ptr, i64, i64) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:30)
    %v116 = llvm.load %rs115 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    %v117 = arith.constant 1 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    %v118 = arith.cmpi eq, %v116, %v117 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    cf.cond_br %v118, ^b23, ^b22 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
  ^b17:
    %v102 = llvm.load %rs90 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    %v103 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    %v104 = arith.cmpi eq, %v102, %v103 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    cf.cond_br %v104, ^b20, ^b19 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
  ^b18:
    %v95 = arith.constant 8 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    %v96 = llvm.getelementptr %rs90[%v95] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    %cl98 = arith.constant 16 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    "llvm.intr.memcpy"(%s12, %v96, %cl98) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    %v99 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":39:20)
    llvm.store %v99, %s11 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    cf.br ^b16 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
  ^b19:
    %tk4 = arith.constant 3 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    %tf4 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    %tl4 = arith.constant 38 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    %tc4 = arith.constant 29 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    func.call @linea_trap(%tk4, %tf4, %tl4, %tc4) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    llvm.unreachable loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
  ^b20:
    %v106 = arith.constant 1 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":40:17)
    llvm.store %v106, %s11 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
    cf.br ^b16 loc("tests/text/a_slice_refuses_to_split_a_character.lin":38:29)
  ^b21:
    %v135 = llvm.load %s14 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    llvm.store %v135, %s13 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:5)
    %v137 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:12)
    llvm.store %v137, %s16 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:12)
    %v140 = arith.constant 8 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:12)
    %v141 = llvm.getelementptr %s16[%v140] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:12)
    %v142 = llvm.load %s1 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:22)
    %v143 = llvm.load %s4 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:29)
    %v144 = arith.addi %v142, %v143 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:22)
    %k5 = arith.cmpi ult, %v144, %v142 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:27)
    cf.cond_br %k5, ^t5, ^c5 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:27)
  ^t5:
    %tk5 = arith.constant 0 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:27)
    %tf5 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:27)
    %tl5 = arith.constant 48 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:27)
    %tc5 = arith.constant 27 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:27)
    func.call @linea_trap(%tk5, %tf5, %tl5, %tc5) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:27)
    llvm.unreachable loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:27)
  ^c5:
    %p145 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:27)
    %v145 = arith.addi %v144, %p145 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:27)
    %v146 = llvm.load %s7 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:37)
    %v147 = arith.addi %v145, %v146 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:22)
    %k6 = arith.cmpi ult, %v147, %v145 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:35)
    cf.cond_br %k6, ^t6, ^c6 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:35)
  ^t6:
    %tk6 = arith.constant 0 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:35)
    %tf6 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:35)
    %tl6 = arith.constant 48 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:35)
    %tc6 = arith.constant 35 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:35)
    func.call @linea_trap(%tk6, %tf6, %tl6, %tc6) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:35)
    llvm.unreachable loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:35)
  ^c6:
    %p148 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:35)
    %v148 = arith.addi %v147, %p148 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:35)
    %v149 = llvm.load %s10 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:45)
    %v150 = arith.addi %v148, %v149 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:22)
    %k7 = arith.cmpi ult, %v150, %v148 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:43)
    cf.cond_br %k7, ^t7, ^c7 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:43)
  ^t7:
    %tk7 = arith.constant 0 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:43)
    %tf7 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:43)
    %tl7 = arith.constant 48 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:43)
    %tc7 = arith.constant 43 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:43)
    func.call @linea_trap(%tk7, %tf7, %tl7, %tc7) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:43)
    llvm.unreachable loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:43)
  ^c7:
    %p151 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:43)
    %v151 = arith.addi %v150, %p151 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:43)
    %v152 = llvm.load %s13 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:57)
    %v153 = arith.addi %v151, %v152 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:22)
    %k8 = arith.cmpi ult, %v153, %v151 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:55)
    cf.cond_br %k8, ^t8, ^c8 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:55)
  ^t8:
    %tk8 = arith.constant 0 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:55)
    %tf8 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:55)
    %tl8 = arith.constant 48 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:55)
    %tc8 = arith.constant 55 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:55)
    func.call @linea_trap(%tk8, %tf8, %tl8, %tc8) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:55)
    llvm.unreachable loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:55)
  ^c8:
    %p154 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:55)
    %v154 = arith.addi %v153, %p154 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:55)
    %k9m = arith.constant 255 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:16)
    %k9 = arith.cmpi ugt, %v154, %k9m : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:16)
    cf.cond_br %k9, ^t9, ^c9 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:16)
  ^t9:
    %tk9 = arith.constant 2 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:16)
    %tf9 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:16)
    %tl9 = arith.constant 48 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:16)
    %tc9 = arith.constant 16 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:16)
    func.call @linea_trap(%tk9, %tf9, %tl9, %tc9) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:16)
    llvm.unreachable loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:16)
  ^c9:
    %p155 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:16)
    %v155 = arith.addi %v154, %p155 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:16)
    %iw156 = arith.trunci %v155 : i64 to i8 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:12)
    llvm.store %iw156, %v141 : i8, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:12)
    %v157 = llvm.load %s16 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:5)
    %v158 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:5)
    %v159 = arith.cmpi eq, %v157, %v158 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:5)
    cf.cond_br %v159, ^b26, ^b27 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:5)
  ^b22:
    %v127 = llvm.load %rs115 : !llvm.ptr -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    %v128 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    %v129 = arith.cmpi eq, %v127, %v128 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    cf.cond_br %v129, ^b25, ^b24 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
  ^b23:
    %v120 = arith.constant 8 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    %v121 = llvm.getelementptr %rs115[%v120] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    %cl123 = arith.constant 16 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    "llvm.intr.memcpy"(%s15, %v121, %cl123) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    %v124 = arith.constant 0 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":43:20)
    llvm.store %v124, %s14 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    cf.br ^b21 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
  ^b24:
    %tk10 = arith.constant 3 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    %tf10 = llvm.mlir.addressof @linea_file0 : !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    %tl10 = arith.constant 42 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    %tc10 = arith.constant 24 : i32 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    func.call @linea_trap(%tk10, %tf10, %tl10, %tc10) : (i32, !llvm.ptr, i32, i32) -> () loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    llvm.unreachable loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
  ^b25:
    %v131 = arith.constant 1 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":44:17)
    llvm.store %v131, %s14 : i64, !llvm.ptr loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
    cf.br ^b21 loc("tests/text/a_slice_refuses_to_split_a_character.lin":42:24)
  ^b26:
    %v161 = arith.constant 8 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:5)
    %v162 = llvm.getelementptr %s16[%v161] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:5)
    %iw163 = llvm.load %v162 : !llvm.ptr -> i8 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:5)
    %v163 = arith.extui %iw163 : i8 to i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:5)
    func.return %v163 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:5)
  ^b27:
    %v165 = arith.constant 8 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:5)
    %v166 = llvm.getelementptr %s16[%v165] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:5)
    %v167 = func.call @"lin.std.io.core;report[std.io.core.IoError]"(%v166) : (!llvm.ptr) -> i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:5)
    func.return %v167 : i64 loc("tests/text/a_slice_refuses_to_split_a_character.lin":48:5)
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
    cf.cond_br %v16, ^b6, ^b5 loc("std/text/str.lin":L:C)
  ^b3:
    %lw48 = llvm.load %s2 : !llvm.ptr -> i8 loc("std/text/str.lin":L:C)
    %lz48 = arith.constant 0 : i8 loc("std/text/str.lin":L:C)
    %v48 = arith.cmpi ne, %lw48, %lz48 : i8 loc("std/text/str.lin":L:C)
    func.return %v48 : i1 loc("std/text/str.lin":L:C)
  ^b4:
    %lw45 = llvm.load %s3 : !llvm.ptr -> i8 loc("std/text/str.lin":L:C)
    %lz45 = arith.constant 0 : i8 loc("std/text/str.lin":L:C)
    %v45 = arith.cmpi ne, %lw45, %lz45 : i8 loc("std/text/str.lin":L:C)
    %sw46 = arith.extui %v45 : i1 to i8 loc("std/text/str.lin":L:C)
    llvm.store %sw46, %s2 : i8, !llvm.ptr loc("std/text/str.lin":L:C)
    cf.br ^b3 loc("std/text/str.lin":L:C)
  ^b5:
    %v37 = llvm.load %rs13 : !llvm.ptr -> i64 loc("std/text/str.lin":L:C)
    %v38 = arith.constant 0 : i64 loc("std/text/str.lin":L:C)
    %v39 = arith.cmpi eq, %v37, %v38 : i64 loc("std/text/str.lin":L:C)
    cf.cond_br %v39, ^b11, ^b10 loc("std/text/str.lin":L:C)
  ^b6:
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
    %tk1 = arith.constant 3 : i32 loc("std/text/str.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file1 : !llvm.ptr loc("std/text/str.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/text/str.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/text/str.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/text/str.lin":L:C)
    llvm.unreachable loc("std/text/str.lin":L:C)
  ^b11:
    %v41 = arith.constant 0 : i1 loc("std/text/str.lin":L:C)
    %sw42 = arith.extui %v41 : i1 to i8 loc("std/text/str.lin":L:C)
    llvm.store %sw42, %s3 : i8, !llvm.ptr loc("std/text/str.lin":L:C)
    cf.br ^b4 loc("std/text/str.lin":L:C)
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
    cf.cond_br %v3, ^b3, ^b2 loc("std/option/option.lin":L:C)
  ^b1:
    %rl31 = arith.constant 16 : i64 loc("std/option/option.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s1, %rl31) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/option/option.lin":L:C)
    func.return loc("std/option/option.lin":L:C)
  ^b2:
    %v13 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/option/option.lin":L:C)
    %v14 = arith.constant 0 : i64 loc("std/option/option.lin":L:C)
    %v15 = arith.cmpi eq, %v13, %v14 : i64 loc("std/option/option.lin":L:C)
    cf.cond_br %v15, ^b5, ^b4 loc("std/option/option.lin":L:C)
  ^b3:
    %v5 = arith.constant 8 : i64 loc("std/option/option.lin":L:C)
    %v6 = llvm.getelementptr %s0[%v5] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/option/option.lin":L:C)
    %cl8 = arith.constant 16 : i64 loc("std/option/option.lin":L:C)
    "llvm.intr.memcpy"(%s2, %v6, %cl8) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/option/option.lin":L:C)
    %cl11 = arith.constant 16 : i64 loc("std/option/option.lin":L:C)
    "llvm.intr.memcpy"(%s1, %s2, %cl11) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/option/option.lin":L:C)
    cf.br ^b1 loc("std/option/option.lin":L:C)
  ^b4:
    %tk1 = arith.constant 3 : i32 loc("std/option/option.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file4 : !llvm.ptr loc("std/option/option.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/option/option.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/option/option.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/option/option.lin":L:C)
    llvm.unreachable loc("std/option/option.lin":L:C)
  ^b5:
    %ba18 = llvm.mlir.addressof @linea_str2 : !llvm.ptr loc("std/option/option.lin":L:C)
    %v18 = llvm.ptrtoint %ba18 : !llvm.ptr to i64 loc("std/option/option.lin":L:C)
    %v19 = arith.constant 0 : i64 loc("std/option/option.lin":L:C)
    llvm.store %v18, %s3 : i64, !llvm.ptr loc("std/option/option.lin":L:C)
    %v22 = arith.constant 28 : i64 loc("std/option/option.lin":L:C)
    %v23 = arith.constant 8 : i64 loc("std/option/option.lin":L:C)
    %v24 = llvm.getelementptr %s3[%v23] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/option/option.lin":L:C)
    llvm.store %v22, %v24 : i64, !llvm.ptr loc("std/option/option.lin":L:C)
    %poa2 = arith.constant 0 : i64 loc("std/option/option.lin":L:C)
    %ppa2 = llvm.getelementptr %s3[%poa2] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/option/option.lin":L:C)
    %pva2 = llvm.load %ppa2 : !llvm.ptr -> i64 loc("std/option/option.lin":L:C)
    %pol2 = arith.constant 8 : i64 loc("std/option/option.lin":L:C)
    %ppl2 = llvm.getelementptr %s3[%pol2] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/option/option.lin":L:C)
    %pvl2 = llvm.load %ppl2 : !llvm.ptr -> i64 loc("std/option/option.lin":L:C)
    %pf2 = llvm.mlir.addressof @linea_file4 : !llvm.ptr loc("std/option/option.lin":L:C)
    %tl2 = arith.constant L : i32 loc("std/option/option.lin":L:C)
    %tc2 = arith.constant C : i32 loc("std/option/option.lin":L:C)
    func.call @linea_panic(%pva2, %pvl2, %pf2, %tl2, %tc2) : (i64, i64, !llvm.ptr, i32, i32) -> () loc("std/option/option.lin":L:C)
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
    %v3 = arith.constant 0 : i64 loc("std/io/core/output.lin":L:C)
    cf.br ^b1 loc("std/io/core/output.lin":L:C)
  ^b1:
    %v6 = arith.constant 0 : i64 loc("std/io/core/output.lin":L:C)
    func.return %v6 : i64 loc("std/io/core/output.lin":L:C)
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
    %v3 = arith.constant 0 : i64 loc("std/io/core/output.lin":L:C)
    cf.br ^b1 loc("std/io/core/output.lin":L:C)
  ^b1:
    %v6 = arith.constant 0 : i64 loc("std/io/core/output.lin":L:C)
    func.return %v6 : i64 loc("std/io/core/output.lin":L:C)
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
    cf.cond_br %v164, ^b20, ^b19 loc("std/io/core/error.lin":L:C)
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
    %rl248 = arith.constant 48 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s6, %rl248) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b19:
    %v235 = llvm.load %v161 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v236 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v237 = arith.cmpi eq, %v235, %v236 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v237, ^b29, ^b28 loc("std/io/core/error.lin":L:C)
  ^b20:
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
    %tk1 = arith.constant 3 : i32 loc("std/io/core/error.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file7 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/io/core/error.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/io/core/error.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/io/core/error.lin":L:C)
    llvm.unreachable loc("std/io/core/error.lin":L:C)
  ^b29:
    %v240 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v240, %s6 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v242 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v243 = llvm.getelementptr %s6[%v242] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v244 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b18 loc("std/io/core/error.lin":L:C)
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
    %z8 = arith.constant 1 : i64
    %s8 = llvm.alloca %z8 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z9 = arith.constant 48 : i64
    %s9 = llvm.alloca %z9 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z10 = arith.constant 1 : i64
    %s10 = llvm.alloca %z10 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z11 = arith.constant 72 : i64
    %s11 = llvm.alloca %z11 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z12 = arith.constant 72 : i64
    %s12 = llvm.alloca %z12 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z13 = arith.constant 72 : i64
    %s13 = llvm.alloca %z13 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
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
    cf.cond_br %v26, ^b6, ^b5 loc("std/io/core/byte_writer.lin":L:C)
  ^b3:
    %v163 = arith.constant 0 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v164 = arith.constant 0 : i64 loc("std/io/core/byte_writer.lin":L:C)
    llvm.store %v164, %s13 : i64, !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %v167 = arith.constant 8 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v168 = llvm.getelementptr %s13[%v167] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/byte_writer.lin":L:C)
    %v169 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
    llvm.store %v169, %v168 : i64, !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %rl171 = arith.constant 72 : i64 loc("std/io/core/byte_writer.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s13, %rl171) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/byte_writer.lin":L:C)
    func.return loc("std/io/core/byte_writer.lin":L:C)
  ^b4:
    %v161 = arith.constant 0 : i64 loc("std/io/core/byte_writer.lin":L:C)
    cf.br ^b1 loc("std/io/core/byte_writer.lin":L:C)
  ^b5:
    %v91 = llvm.load %rs23 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
    %v92 = arith.constant 1 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v93 = arith.cmpi eq, %v91, %v92 : i64 loc("std/io/core/byte_writer.lin":L:C)
    cf.cond_br %v93, ^b16, ^b15 loc("std/io/core/byte_writer.lin":L:C)
  ^b6:
    %v28 = arith.constant 8 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v29 = llvm.getelementptr %rs23[%v28] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/byte_writer.lin":L:C)
    %v30 = llvm.load %v29 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
    llvm.store %v30, %s5 : i64, !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %v32 = llvm.load %s5 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
    %v33 = arith.constant 0 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v34 = arith.cmpi eq, %v32, %v33 : i64 loc("std/io/core/byte_writer.lin":L:C)
    cf.cond_br %v34, ^b7, ^b8 loc("std/io/core/byte_writer.lin":L:C)
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
    %tk3 = arith.constant 3 : i32 loc("std/io/core/byte_writer.lin":L:C)
    %tf3 = llvm.mlir.addressof @linea_file8 : !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %tl3 = arith.constant L : i32 loc("std/io/core/byte_writer.lin":L:C)
    %tc3 = arith.constant C : i32 loc("std/io/core/byte_writer.lin":L:C)
    func.call @linea_trap(%tk3, %tf3, %tl3, %tc3) : (i32, !llvm.ptr, i32, i32) -> () loc("std/io/core/byte_writer.lin":L:C)
    llvm.unreachable loc("std/io/core/byte_writer.lin":L:C)
  ^b16:
    %v95 = arith.constant 8 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v96 = llvm.getelementptr %rs23[%v95] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/byte_writer.lin":L:C)
    %v97 = arith.constant 8 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v98 = llvm.getelementptr %rs23[%v97] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/byte_writer.lin":L:C)
    %v99 = arith.constant 0 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v101 = llvm.load %v98 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
    llvm.store %v101, %s8 : i64, !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %v103 = arith.constant 8 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v104 = llvm.getelementptr %v98[%v103] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/byte_writer.lin":L:C)
    %cl106 = arith.constant 48 : i64 loc("std/io/core/byte_writer.lin":L:C)
    "llvm.intr.memcpy"(%s9, %v104, %cl106) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/byte_writer.lin":L:C)
    %v107 = arith.constant 56 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v108 = llvm.getelementptr %v98[%v107] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/byte_writer.lin":L:C)
    %v109 = llvm.load %v108 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
    llvm.store %v109, %s10 : i64, !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %v111 = llvm.load %s10 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
    %v112 = llvm.load %s3 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
    %v113 = arith.cmpi ugt, %v111, %v112 : i64 loc("std/io/core/byte_writer.lin":L:C)
    cf.cond_br %v113, ^b17, ^b18 loc("std/io/core/byte_writer.lin":L:C)
  ^b17:
    %v115 = arith.constant 1 : i64 loc("std/io/core/byte_writer.lin":L:C)
    llvm.store %v115, %s11 : i64, !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %v118 = arith.constant 8 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v119 = llvm.getelementptr %s11[%v118] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/byte_writer.lin":L:C)
    %v120 = arith.constant 0 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v122 = arith.constant 2 : i64 loc("std/io/core/byte_writer.lin":L:C)
    llvm.store %v122, %v119 : i64, !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %v124 = arith.constant 8 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v125 = llvm.getelementptr %v119[%v124] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/byte_writer.lin":L:C)
    %cl127 = arith.constant 48 : i64 loc("std/io/core/byte_writer.lin":L:C)
    "llvm.intr.memcpy"(%v125, %s9, %cl127) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/byte_writer.lin":L:C)
    %v128 = arith.constant 56 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v129 = llvm.getelementptr %v119[%v128] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/byte_writer.lin":L:C)
    %v130 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
    llvm.store %v130, %v129 : i64, !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %rl132 = arith.constant 72 : i64 loc("std/io/core/byte_writer.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s11, %rl132) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/byte_writer.lin":L:C)
    func.return loc("std/io/core/byte_writer.lin":L:C)
  ^b18:
    cf.br ^b19 loc("std/io/core/byte_writer.lin":L:C)
  ^b19:
    %v136 = arith.constant 0 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v137 = arith.constant 1 : i64 loc("std/io/core/byte_writer.lin":L:C)
    llvm.store %v137, %s12 : i64, !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %v140 = arith.constant 8 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v141 = llvm.getelementptr %s12[%v140] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/byte_writer.lin":L:C)
    %v142 = arith.constant 0 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v144 = llvm.load %s8 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
    llvm.store %v144, %v141 : i64, !llvm.ptr loc("std/io/core/byte_writer.lin":L:C)
    %v146 = arith.constant 8 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v147 = llvm.getelementptr %v141[%v146] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/byte_writer.lin":L:C)
    %cl149 = arith.constant 48 : i64 loc("std/io/core/byte_writer.lin":L:C)
    "llvm.intr.memcpy"(%v147, %s9, %cl149) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/byte_writer.lin":L:C)
    %v150 = arith.constant 56 : i64 loc("std/io/core/byte_writer.lin":L:C)
    %v151 = llvm.getelementptr %v141[%v150] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/byte_writer.lin":L:C)
    %v152 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
    %v153 = llvm.load %s10 : !llvm.ptr -> i64 loc("std/io/core/byte_writer.lin":L:C)
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
    "llvm.intr.memcpy"(%sret, %s12, %rl157) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/byte_writer.lin":L:C)
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
    cf.cond_br %v17, ^b3, ^b2 loc("std/io/core/error.lin":L:C)
  ^b1:
    %cl51 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%s4, %s5, %cl51) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %v52 = llvm.load %s3 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v54 = arith.constant 32 : i64 loc("std/io/core/error.lin":L:C)
    %v55 = llvm.getelementptr %s4[%v54] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v52, %v55 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v57 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v58 = llvm.load %s1 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v59 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v60 = arith.cmpi eq, %v58, %v59 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v60, ^b8, ^b7 loc("std/io/core/error.lin":L:C)
  ^b2:
    %v27 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v28 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v29 = arith.cmpi eq, %v27, %v28 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v29, ^b5, ^b4 loc("std/io/core/error.lin":L:C)
  ^b3:
    %v19 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v20 = llvm.getelementptr %s2[%v19] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %cl22 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%s6, %v20, %cl22) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %cl25 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%s5, %s6, %cl25) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b4:
    %tk1 = arith.constant 3 : i32 loc("std/io/core/error.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file7 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/io/core/error.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/io/core/error.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/io/core/error.lin":L:C)
    llvm.unreachable loc("std/io/core/error.lin":L:C)
  ^b5:
    %v32 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v34 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v34, %s5 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v36 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v37 = llvm.getelementptr %s5[%v36] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v38 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v38, %v37 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v40 = arith.constant 16 : i64 loc("std/io/core/error.lin":L:C)
    %v41 = llvm.getelementptr %s5[%v40] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v42 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v42, %v41 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v44 = arith.constant 32 : i64 loc("std/io/core/error.lin":L:C)
    %v45 = llvm.getelementptr %s5[%v44] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v46 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v46, %v45 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b6:
    %v85 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %rl87 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s4, %rl87) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b7:
    %v64 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v65 = arith.cmpi eq, %v58, %v64 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v65, ^b10, ^b9 loc("std/io/core/error.lin":L:C)
  ^b8:
    %v62 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b6 loc("std/io/core/error.lin":L:C)
  ^b9:
    %v74 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v75 = arith.cmpi eq, %v58, %v74 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v75, ^b12, ^b11 loc("std/io/core/error.lin":L:C)
  ^b10:
    %v67 = arith.constant 15 : i64 loc("std/io/core/error.lin":L:C)
    %v69 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v70 = llvm.getelementptr %s4[%v69] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v67, %v70 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v72 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b6 loc("std/io/core/error.lin":L:C)
  ^b11:
    %tk2 = arith.constant 3 : i32 loc("std/io/core/error.lin":L:C)
    %tf2 = llvm.mlir.addressof @linea_file7 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %tl2 = arith.constant L : i32 loc("std/io/core/error.lin":L:C)
    %tc2 = arith.constant C : i32 loc("std/io/core/error.lin":L:C)
    func.call @linea_trap(%tk2, %tf2, %tl2, %tc2) : (i32, !llvm.ptr, i32, i32) -> () loc("std/io/core/error.lin":L:C)
    llvm.unreachable loc("std/io/core/error.lin":L:C)
  ^b12:
    %v77 = arith.constant 16 : i64 loc("std/io/core/error.lin":L:C)
    %v79 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v80 = llvm.getelementptr %s4[%v79] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v77, %v80 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v82 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    cf.br ^b6 loc("std/io/core/error.lin":L:C)
  }
  func.func private @"lin.std.io.core.IoOperation;std.fmt;Display.fmt[std.io.core.Descriptor]"(%sret: !llvm.ptr, %a0: i64, %a1: !llvm.ptr) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 16 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 16 : i64
    %s3 = llvm.alloca %z3 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : i64, !llvm.ptr
    llvm.store %a1, %s1 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v1 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v2 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v3 = arith.cmpi eq, %v1, %v2 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v3, ^b3, ^b2 loc("std/io/core/error.lin":L:C)
  ^b1:
    %cl200 = arith.constant 16 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%s2, %s3, %cl200) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %v201 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%sret, %v201, %s2) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b2:
    %v16 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v17 = arith.cmpi eq, %v1, %v16 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v17, ^b5, ^b4 loc("std/io/core/error.lin":L:C)
  ^b3:
    %v6 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba7 = llvm.mlir.addressof @linea_str9 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v7 = llvm.ptrtoint %ba7 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v8 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v7, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v11 = arith.constant 4 : i64 loc("std/io/core/error.lin":L:C)
    %v12 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v13 = llvm.getelementptr %s3[%v12] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v11, %v13 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b4:
    %v30 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v31 = arith.cmpi eq, %v1, %v30 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v31, ^b7, ^b6 loc("std/io/core/error.lin":L:C)
  ^b5:
    %v20 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba21 = llvm.mlir.addressof @linea_str10 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v21 = llvm.ptrtoint %ba21 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v22 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v21, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v25 = arith.constant 5 : i64 loc("std/io/core/error.lin":L:C)
    %v26 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v27 = llvm.getelementptr %s3[%v26] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v25, %v27 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b6:
    %v44 = arith.constant 3 : i64 loc("std/io/core/error.lin":L:C)
    %v45 = arith.cmpi eq, %v1, %v44 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v45, ^b9, ^b8 loc("std/io/core/error.lin":L:C)
  ^b7:
    %v34 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba35 = llvm.mlir.addressof @linea_str11 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v35 = llvm.ptrtoint %ba35 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v36 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v35, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v39 = arith.constant 5 : i64 loc("std/io/core/error.lin":L:C)
    %v40 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v41 = llvm.getelementptr %s3[%v40] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v39, %v41 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b8:
    %v58 = arith.constant 4 : i64 loc("std/io/core/error.lin":L:C)
    %v59 = arith.cmpi eq, %v1, %v58 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v59, ^b11, ^b10 loc("std/io/core/error.lin":L:C)
  ^b9:
    %v48 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba49 = llvm.mlir.addressof @linea_str12 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v49 = llvm.ptrtoint %ba49 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v50 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v49, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v53 = arith.constant 5 : i64 loc("std/io/core/error.lin":L:C)
    %v54 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v55 = llvm.getelementptr %s3[%v54] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v53, %v55 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b10:
    %v72 = arith.constant 5 : i64 loc("std/io/core/error.lin":L:C)
    %v73 = arith.cmpi eq, %v1, %v72 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v73, ^b13, ^b12 loc("std/io/core/error.lin":L:C)
  ^b11:
    %v62 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba63 = llvm.mlir.addressof @linea_str13 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v63 = llvm.ptrtoint %ba63 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v64 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v63, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v67 = arith.constant 4 : i64 loc("std/io/core/error.lin":L:C)
    %v68 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v69 = llvm.getelementptr %s3[%v68] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v67, %v69 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b12:
    %v86 = arith.constant 6 : i64 loc("std/io/core/error.lin":L:C)
    %v87 = arith.cmpi eq, %v1, %v86 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v87, ^b15, ^b14 loc("std/io/core/error.lin":L:C)
  ^b13:
    %v76 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba77 = llvm.mlir.addressof @linea_str14 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v77 = llvm.ptrtoint %ba77 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v78 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v77, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v81 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v82 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v83 = llvm.getelementptr %s3[%v82] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v81, %v83 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b14:
    %v100 = arith.constant 7 : i64 loc("std/io/core/error.lin":L:C)
    %v101 = arith.cmpi eq, %v1, %v100 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v101, ^b17, ^b16 loc("std/io/core/error.lin":L:C)
  ^b15:
    %v90 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba91 = llvm.mlir.addressof @linea_str15 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v91 = llvm.ptrtoint %ba91 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v92 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v91, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v95 = arith.constant 11 : i64 loc("std/io/core/error.lin":L:C)
    %v96 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v97 = llvm.getelementptr %s3[%v96] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v95, %v97 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b16:
    %v114 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v115 = arith.cmpi eq, %v1, %v114 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v115, ^b19, ^b18 loc("std/io/core/error.lin":L:C)
  ^b17:
    %v104 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba105 = llvm.mlir.addressof @linea_str16 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v105 = llvm.ptrtoint %ba105 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v106 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v105, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v109 = arith.constant 7 : i64 loc("std/io/core/error.lin":L:C)
    %v110 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v111 = llvm.getelementptr %s3[%v110] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v109, %v111 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b18:
    %v128 = arith.constant 9 : i64 loc("std/io/core/error.lin":L:C)
    %v129 = arith.cmpi eq, %v1, %v128 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v129, ^b21, ^b20 loc("std/io/core/error.lin":L:C)
  ^b19:
    %v118 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba119 = llvm.mlir.addressof @linea_str17 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v119 = llvm.ptrtoint %ba119 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v120 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v119, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v123 = arith.constant 6 : i64 loc("std/io/core/error.lin":L:C)
    %v124 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v125 = llvm.getelementptr %s3[%v124] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v123, %v125 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b20:
    %v142 = arith.constant 10 : i64 loc("std/io/core/error.lin":L:C)
    %v143 = arith.cmpi eq, %v1, %v142 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v143, ^b23, ^b22 loc("std/io/core/error.lin":L:C)
  ^b21:
    %v132 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba133 = llvm.mlir.addressof @linea_str18 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v133 = llvm.ptrtoint %ba133 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v134 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v133, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v137 = arith.constant 6 : i64 loc("std/io/core/error.lin":L:C)
    %v138 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v139 = llvm.getelementptr %s3[%v138] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v137, %v139 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b22:
    %v156 = arith.constant 11 : i64 loc("std/io/core/error.lin":L:C)
    %v157 = arith.cmpi eq, %v1, %v156 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v157, ^b25, ^b24 loc("std/io/core/error.lin":L:C)
  ^b23:
    %v146 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba147 = llvm.mlir.addressof @linea_str19 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v147 = llvm.ptrtoint %ba147 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v148 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v147, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v151 = arith.constant 6 : i64 loc("std/io/core/error.lin":L:C)
    %v152 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v153 = llvm.getelementptr %s3[%v152] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v151, %v153 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b24:
    %v170 = arith.constant 12 : i64 loc("std/io/core/error.lin":L:C)
    %v171 = arith.cmpi eq, %v1, %v170 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v171, ^b27, ^b26 loc("std/io/core/error.lin":L:C)
  ^b25:
    %v160 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba161 = llvm.mlir.addressof @linea_str20 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v161 = llvm.ptrtoint %ba161 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v162 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v161, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v165 = arith.constant 6 : i64 loc("std/io/core/error.lin":L:C)
    %v166 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v167 = llvm.getelementptr %s3[%v166] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v165, %v167 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b26:
    %v184 = arith.constant 13 : i64 loc("std/io/core/error.lin":L:C)
    %v185 = arith.cmpi eq, %v1, %v184 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v185, ^b29, ^b28 loc("std/io/core/error.lin":L:C)
  ^b27:
    %v174 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba175 = llvm.mlir.addressof @linea_str21 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v175 = llvm.ptrtoint %ba175 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v176 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v175, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v179 = arith.constant 7 : i64 loc("std/io/core/error.lin":L:C)
    %v180 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v181 = llvm.getelementptr %s3[%v180] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v179, %v181 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b28:
    %tk1 = arith.constant 3 : i32 loc("std/io/core/error.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file7 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/io/core/error.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/io/core/error.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/io/core/error.lin":L:C)
    llvm.unreachable loc("std/io/core/error.lin":L:C)
  ^b29:
    %v188 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba189 = llvm.mlir.addressof @linea_str22 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v189 = llvm.ptrtoint %ba189 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v190 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v189, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v193 = arith.constant 9 : i64 loc("std/io/core/error.lin":L:C)
    %v194 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v195 = llvm.getelementptr %s3[%v194] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v193, %v195 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  }
  func.func private @"lin.std.io.core.IoCategory;std.fmt;Display.fmt[std.io.core.Descriptor]"(%sret: !llvm.ptr, %a0: i64, %a1: !llvm.ptr) attributes {llvm.linkage = #llvm.linkage<internal>} {
    %z0 = arith.constant 1 : i64
    %s0 = llvm.alloca %z0 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z1 = arith.constant 1 : i64
    %s1 = llvm.alloca %z1 x !llvm.ptr {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z2 = arith.constant 16 : i64
    %s2 = llvm.alloca %z2 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %z3 = arith.constant 16 : i64
    %s3 = llvm.alloca %z3 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    llvm.store %a0, %s0 : i64, !llvm.ptr
    llvm.store %a1, %s1 : !llvm.ptr, !llvm.ptr
    cf.br ^b0
  ^b0:
    %v1 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    %v2 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v3 = arith.cmpi eq, %v1, %v2 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v3, ^b3, ^b2 loc("std/io/core/error.lin":L:C)
  ^b1:
    %cl298 = arith.constant 16 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%s2, %s3, %cl298) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    %v299 = llvm.load %s1 : !llvm.ptr -> !llvm.ptr loc("std/io/core/error.lin":L:C)
    func.call @"lin.std.io.core.Descriptor;std.io.core;Writer.write_str"(%sret, %v299, %s2) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b2:
    %v16 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    %v17 = arith.cmpi eq, %v1, %v16 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v17, ^b5, ^b4 loc("std/io/core/error.lin":L:C)
  ^b3:
    %v6 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba7 = llvm.mlir.addressof @linea_str23 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v7 = llvm.ptrtoint %ba7 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v8 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v7, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v11 = arith.constant 5 : i64 loc("std/io/core/error.lin":L:C)
    %v12 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v13 = llvm.getelementptr %s3[%v12] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v11, %v13 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b4:
    %v30 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v31 = arith.cmpi eq, %v1, %v30 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v31, ^b7, ^b6 loc("std/io/core/error.lin":L:C)
  ^b5:
    %v20 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba21 = llvm.mlir.addressof @linea_str24 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v21 = llvm.ptrtoint %ba21 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v22 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v21, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v25 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v26 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v27 = llvm.getelementptr %s3[%v26] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v25, %v27 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b6:
    %v44 = arith.constant 3 : i64 loc("std/io/core/error.lin":L:C)
    %v45 = arith.cmpi eq, %v1, %v44 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v45, ^b9, ^b8 loc("std/io/core/error.lin":L:C)
  ^b7:
    %v34 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba35 = llvm.mlir.addressof @linea_str25 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v35 = llvm.ptrtoint %ba35 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v36 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v35, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v39 = arith.constant 16 : i64 loc("std/io/core/error.lin":L:C)
    %v40 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v41 = llvm.getelementptr %s3[%v40] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v39, %v41 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b8:
    %v58 = arith.constant 4 : i64 loc("std/io/core/error.lin":L:C)
    %v59 = arith.cmpi eq, %v1, %v58 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v59, ^b11, ^b10 loc("std/io/core/error.lin":L:C)
  ^b9:
    %v48 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba49 = llvm.mlir.addressof @linea_str26 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v49 = llvm.ptrtoint %ba49 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v50 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v49, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v53 = arith.constant 13 : i64 loc("std/io/core/error.lin":L:C)
    %v54 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v55 = llvm.getelementptr %s3[%v54] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v53, %v55 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b10:
    %v72 = arith.constant 5 : i64 loc("std/io/core/error.lin":L:C)
    %v73 = arith.cmpi eq, %v1, %v72 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v73, ^b13, ^b12 loc("std/io/core/error.lin":L:C)
  ^b11:
    %v62 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba63 = llvm.mlir.addressof @linea_str27 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v63 = llvm.ptrtoint %ba63 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v64 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v63, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v67 = arith.constant 10 : i64 loc("std/io/core/error.lin":L:C)
    %v68 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v69 = llvm.getelementptr %s3[%v68] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v67, %v69 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b12:
    %v86 = arith.constant 6 : i64 loc("std/io/core/error.lin":L:C)
    %v87 = arith.cmpi eq, %v1, %v86 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v87, ^b15, ^b14 loc("std/io/core/error.lin":L:C)
  ^b13:
    %v76 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba77 = llvm.mlir.addressof @linea_str28 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v77 = llvm.ptrtoint %ba77 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v78 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v77, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v81 = arith.constant 10 : i64 loc("std/io/core/error.lin":L:C)
    %v82 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v83 = llvm.getelementptr %s3[%v82] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v81, %v83 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b14:
    %v100 = arith.constant 7 : i64 loc("std/io/core/error.lin":L:C)
    %v101 = arith.cmpi eq, %v1, %v100 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v101, ^b17, ^b16 loc("std/io/core/error.lin":L:C)
  ^b15:
    %v90 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba91 = llvm.mlir.addressof @linea_str29 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v91 = llvm.ptrtoint %ba91 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v92 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v91, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v95 = arith.constant 11 : i64 loc("std/io/core/error.lin":L:C)
    %v96 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v97 = llvm.getelementptr %s3[%v96] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v95, %v97 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b16:
    %v114 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v115 = arith.cmpi eq, %v1, %v114 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v115, ^b19, ^b18 loc("std/io/core/error.lin":L:C)
  ^b17:
    %v104 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba105 = llvm.mlir.addressof @linea_str30 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v105 = llvm.ptrtoint %ba105 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v106 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v105, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v109 = arith.constant 12 : i64 loc("std/io/core/error.lin":L:C)
    %v110 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v111 = llvm.getelementptr %s3[%v110] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v109, %v111 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b18:
    %v128 = arith.constant 9 : i64 loc("std/io/core/error.lin":L:C)
    %v129 = arith.cmpi eq, %v1, %v128 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v129, ^b21, ^b20 loc("std/io/core/error.lin":L:C)
  ^b19:
    %v118 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba119 = llvm.mlir.addressof @linea_str31 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v119 = llvm.ptrtoint %ba119 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v120 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v119, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v123 = arith.constant 12 : i64 loc("std/io/core/error.lin":L:C)
    %v124 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v125 = llvm.getelementptr %s3[%v124] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v123, %v125 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b20:
    %v142 = arith.constant 10 : i64 loc("std/io/core/error.lin":L:C)
    %v143 = arith.cmpi eq, %v1, %v142 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v143, ^b23, ^b22 loc("std/io/core/error.lin":L:C)
  ^b21:
    %v132 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba133 = llvm.mlir.addressof @linea_str32 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v133 = llvm.ptrtoint %ba133 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v134 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v133, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v137 = arith.constant 11 : i64 loc("std/io/core/error.lin":L:C)
    %v138 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v139 = llvm.getelementptr %s3[%v138] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v137, %v139 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b22:
    %v156 = arith.constant 11 : i64 loc("std/io/core/error.lin":L:C)
    %v157 = arith.cmpi eq, %v1, %v156 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v157, ^b25, ^b24 loc("std/io/core/error.lin":L:C)
  ^b23:
    %v146 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba147 = llvm.mlir.addressof @linea_str33 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v147 = llvm.ptrtoint %ba147 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v148 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v147, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v151 = arith.constant 11 : i64 loc("std/io/core/error.lin":L:C)
    %v152 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v153 = llvm.getelementptr %s3[%v152] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v151, %v153 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b24:
    %v170 = arith.constant 12 : i64 loc("std/io/core/error.lin":L:C)
    %v171 = arith.cmpi eq, %v1, %v170 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v171, ^b27, ^b26 loc("std/io/core/error.lin":L:C)
  ^b25:
    %v160 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba161 = llvm.mlir.addressof @linea_str34 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v161 = llvm.ptrtoint %ba161 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v162 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v161, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v165 = arith.constant 7 : i64 loc("std/io/core/error.lin":L:C)
    %v166 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v167 = llvm.getelementptr %s3[%v166] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v165, %v167 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b26:
    %v184 = arith.constant 13 : i64 loc("std/io/core/error.lin":L:C)
    %v185 = arith.cmpi eq, %v1, %v184 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v185, ^b29, ^b28 loc("std/io/core/error.lin":L:C)
  ^b27:
    %v174 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba175 = llvm.mlir.addressof @linea_str35 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v175 = llvm.ptrtoint %ba175 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v176 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v175, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v179 = arith.constant 17 : i64 loc("std/io/core/error.lin":L:C)
    %v180 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v181 = llvm.getelementptr %s3[%v180] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v179, %v181 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b28:
    %v198 = arith.constant 14 : i64 loc("std/io/core/error.lin":L:C)
    %v199 = arith.cmpi eq, %v1, %v198 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v199, ^b31, ^b30 loc("std/io/core/error.lin":L:C)
  ^b29:
    %v188 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba189 = llvm.mlir.addressof @linea_str36 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v189 = llvm.ptrtoint %ba189 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v190 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v189, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v193 = arith.constant 7 : i64 loc("std/io/core/error.lin":L:C)
    %v194 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v195 = llvm.getelementptr %s3[%v194] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v193, %v195 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b30:
    %v212 = arith.constant 15 : i64 loc("std/io/core/error.lin":L:C)
    %v213 = arith.cmpi eq, %v1, %v212 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v213, ^b33, ^b32 loc("std/io/core/error.lin":L:C)
  ^b31:
    %v202 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba203 = llvm.mlir.addressof @linea_str37 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v203 = llvm.ptrtoint %ba203 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v204 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v203, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v207 = arith.constant 17 : i64 loc("std/io/core/error.lin":L:C)
    %v208 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v209 = llvm.getelementptr %s3[%v208] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v207, %v209 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b32:
    %v226 = arith.constant 16 : i64 loc("std/io/core/error.lin":L:C)
    %v227 = arith.cmpi eq, %v1, %v226 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v227, ^b35, ^b34 loc("std/io/core/error.lin":L:C)
  ^b33:
    %v216 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba217 = llvm.mlir.addressof @linea_str38 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v217 = llvm.ptrtoint %ba217 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v218 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v217, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v221 = arith.constant 10 : i64 loc("std/io/core/error.lin":L:C)
    %v222 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v223 = llvm.getelementptr %s3[%v222] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v221, %v223 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b34:
    %v240 = arith.constant 17 : i64 loc("std/io/core/error.lin":L:C)
    %v241 = arith.cmpi eq, %v1, %v240 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v241, ^b37, ^b36 loc("std/io/core/error.lin":L:C)
  ^b35:
    %v230 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba231 = llvm.mlir.addressof @linea_str39 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v231 = llvm.ptrtoint %ba231 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v232 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v231, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v235 = arith.constant 15 : i64 loc("std/io/core/error.lin":L:C)
    %v236 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v237 = llvm.getelementptr %s3[%v236] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v235, %v237 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b36:
    %v254 = arith.constant 18 : i64 loc("std/io/core/error.lin":L:C)
    %v255 = arith.cmpi eq, %v1, %v254 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v255, ^b39, ^b38 loc("std/io/core/error.lin":L:C)
  ^b37:
    %v244 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba245 = llvm.mlir.addressof @linea_str40 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v245 = llvm.ptrtoint %ba245 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v246 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v245, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v249 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v250 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v251 = llvm.getelementptr %s3[%v250] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v249, %v251 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b38:
    %v268 = arith.constant 19 : i64 loc("std/io/core/error.lin":L:C)
    %v269 = arith.cmpi eq, %v1, %v268 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v269, ^b41, ^b40 loc("std/io/core/error.lin":L:C)
  ^b39:
    %v258 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba259 = llvm.mlir.addressof @linea_str41 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v259 = llvm.ptrtoint %ba259 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v260 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v259, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v263 = arith.constant 15 : i64 loc("std/io/core/error.lin":L:C)
    %v264 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v265 = llvm.getelementptr %s3[%v264] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v263, %v265 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b40:
    %v282 = arith.constant 20 : i64 loc("std/io/core/error.lin":L:C)
    %v283 = arith.cmpi eq, %v1, %v282 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v283, ^b43, ^b42 loc("std/io/core/error.lin":L:C)
  ^b41:
    %v272 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba273 = llvm.mlir.addressof @linea_str42 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v273 = llvm.ptrtoint %ba273 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v274 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v273, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v277 = arith.constant 17 : i64 loc("std/io/core/error.lin":L:C)
    %v278 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v279 = llvm.getelementptr %s3[%v278] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v277, %v279 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b42:
    %tk1 = arith.constant 3 : i32 loc("std/io/core/error.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file7 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/io/core/error.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/io/core/error.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/io/core/error.lin":L:C)
    llvm.unreachable loc("std/io/core/error.lin":L:C)
  ^b43:
    %v286 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %ba287 = llvm.mlir.addressof @linea_str43 : !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v287 = llvm.ptrtoint %ba287 : !llvm.ptr to i64 loc("std/io/core/error.lin":L:C)
    %v288 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v287, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v291 = arith.constant 12 : i64 loc("std/io/core/error.lin":L:C)
    %v292 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v293 = llvm.getelementptr %s3[%v292] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    llvm.store %v291, %v293 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
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
    %ba6 = llvm.mlir.addressof @linea_str44 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
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
    cf.cond_br %v3, ^b3, ^b2 loc("std/io/core/error.lin":L:C)
  ^b1:
    %v114 = llvm.load %s4 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v114, %s3 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v117 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    %v119 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v119, %s5 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v121 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v122 = llvm.getelementptr %s5[%v121] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v123 = llvm.load %s3 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v123, %v122 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v125 = arith.constant 16 : i64 loc("std/io/core/error.lin":L:C)
    %v126 = llvm.getelementptr %s5[%v125] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v127 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v127, %v126 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v129 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v130 = llvm.getelementptr %v126[%v129] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %lw131 = llvm.load %s1 : !llvm.ptr -> i32 loc("std/io/core/error.lin":L:C)
    %v131 = arith.extsi %lw131 : i32 to i64 loc("std/io/core/error.lin":L:C)
    %iw132 = arith.trunci %v131 : i64 to i32 loc("std/io/core/error.lin":L:C)
    llvm.store %iw132, %v130 : i32, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %v133 = arith.constant 32 : i64 loc("std/io/core/error.lin":L:C)
    %v134 = llvm.getelementptr %s5[%v133] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/io/core/error.lin":L:C)
    %v135 = llvm.load %s2 : !llvm.ptr -> i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v135, %v134 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    %rl137 = arith.constant 40 : i64 loc("std/io/core/error.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s5, %rl137) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/io/core/error.lin":L:C)
    func.return loc("std/io/core/error.lin":L:C)
  ^b2:
    %v8 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    %v9 = arith.cmpi eq, %v1, %v8 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v9, ^b5, ^b4 loc("std/io/core/error.lin":L:C)
  ^b3:
    %v5 = arith.constant 1 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v5, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b4:
    %v14 = arith.constant 3 : i64 loc("std/io/core/error.lin":L:C)
    %v15 = arith.cmpi eq, %v1, %v14 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v15, ^b7, ^b6 loc("std/io/core/error.lin":L:C)
  ^b5:
    %v11 = arith.constant 2 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v11, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b6:
    %v20 = arith.constant 4 : i64 loc("std/io/core/error.lin":L:C)
    %v21 = arith.cmpi eq, %v1, %v20 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v21, ^b9, ^b8 loc("std/io/core/error.lin":L:C)
  ^b7:
    %v17 = arith.constant 3 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v17, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b8:
    %v26 = arith.constant 5 : i64 loc("std/io/core/error.lin":L:C)
    %v27 = arith.cmpi eq, %v1, %v26 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v27, ^b11, ^b10 loc("std/io/core/error.lin":L:C)
  ^b9:
    %v23 = arith.constant 4 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v23, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b10:
    %v32 = arith.constant 6 : i64 loc("std/io/core/error.lin":L:C)
    %v33 = arith.cmpi eq, %v1, %v32 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v33, ^b13, ^b12 loc("std/io/core/error.lin":L:C)
  ^b11:
    %v29 = arith.constant 5 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v29, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b12:
    %v38 = arith.constant 7 : i64 loc("std/io/core/error.lin":L:C)
    %v39 = arith.cmpi eq, %v1, %v38 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v39, ^b15, ^b14 loc("std/io/core/error.lin":L:C)
  ^b13:
    %v35 = arith.constant 6 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v35, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b14:
    %v44 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    %v45 = arith.cmpi eq, %v1, %v44 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v45, ^b17, ^b16 loc("std/io/core/error.lin":L:C)
  ^b15:
    %v41 = arith.constant 7 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v41, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b16:
    %v50 = arith.constant 9 : i64 loc("std/io/core/error.lin":L:C)
    %v51 = arith.cmpi eq, %v1, %v50 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v51, ^b19, ^b18 loc("std/io/core/error.lin":L:C)
  ^b17:
    %v47 = arith.constant 8 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v47, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b18:
    %v56 = arith.constant 10 : i64 loc("std/io/core/error.lin":L:C)
    %v57 = arith.cmpi eq, %v1, %v56 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v57, ^b21, ^b20 loc("std/io/core/error.lin":L:C)
  ^b19:
    %v53 = arith.constant 9 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v53, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b20:
    %v62 = arith.constant 11 : i64 loc("std/io/core/error.lin":L:C)
    %v63 = arith.cmpi eq, %v1, %v62 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v63, ^b23, ^b22 loc("std/io/core/error.lin":L:C)
  ^b21:
    %v59 = arith.constant 10 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v59, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b22:
    %v68 = arith.constant 12 : i64 loc("std/io/core/error.lin":L:C)
    %v69 = arith.cmpi eq, %v1, %v68 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v69, ^b25, ^b24 loc("std/io/core/error.lin":L:C)
  ^b23:
    %v65 = arith.constant 11 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v65, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b24:
    %v74 = arith.constant 13 : i64 loc("std/io/core/error.lin":L:C)
    %v75 = arith.cmpi eq, %v1, %v74 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v75, ^b27, ^b26 loc("std/io/core/error.lin":L:C)
  ^b25:
    %v71 = arith.constant 12 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v71, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b26:
    %v80 = arith.constant 14 : i64 loc("std/io/core/error.lin":L:C)
    %v81 = arith.cmpi eq, %v1, %v80 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v81, ^b29, ^b28 loc("std/io/core/error.lin":L:C)
  ^b27:
    %v77 = arith.constant 13 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v77, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b28:
    %v86 = arith.constant 15 : i64 loc("std/io/core/error.lin":L:C)
    %v87 = arith.cmpi eq, %v1, %v86 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v87, ^b31, ^b30 loc("std/io/core/error.lin":L:C)
  ^b29:
    %v83 = arith.constant 14 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v83, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b30:
    %v92 = arith.constant 16 : i64 loc("std/io/core/error.lin":L:C)
    %v93 = arith.cmpi eq, %v1, %v92 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v93, ^b33, ^b32 loc("std/io/core/error.lin":L:C)
  ^b31:
    %v89 = arith.constant 17 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v89, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b32:
    %v98 = arith.constant 17 : i64 loc("std/io/core/error.lin":L:C)
    %v99 = arith.cmpi eq, %v1, %v98 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v99, ^b35, ^b34 loc("std/io/core/error.lin":L:C)
  ^b33:
    %v95 = arith.constant 18 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v95, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b34:
    %v104 = arith.constant 18 : i64 loc("std/io/core/error.lin":L:C)
    %v105 = arith.cmpi eq, %v1, %v104 : i64 loc("std/io/core/error.lin":L:C)
    cf.cond_br %v105, ^b37, ^b36 loc("std/io/core/error.lin":L:C)
  ^b35:
    %v101 = arith.constant 19 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v101, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b36:
    %v110 = arith.constant 0 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v110, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
    cf.br ^b1 loc("std/io/core/error.lin":L:C)
  ^b37:
    %v107 = arith.constant 20 : i64 loc("std/io/core/error.lin":L:C)
    llvm.store %v107, %s4 : i64, !llvm.ptr loc("std/io/core/error.lin":L:C)
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
    %ba37 = llvm.mlir.addressof @linea_str46 : !llvm.ptr loc("std/fmt/decimal.lin":L:C)
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
    cf.cond_br %v3, ^b3, ^b2 loc("std/option/option.lin":L:C)
  ^b1:
    %rl23 = arith.constant 16 : i64 loc("std/option/option.lin":L:C)
    "llvm.intr.memcpy"(%sret, %s2, %rl23) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/option/option.lin":L:C)
    func.return loc("std/option/option.lin":L:C)
  ^b2:
    %v13 = llvm.load %s0 : !llvm.ptr -> i64 loc("std/option/option.lin":L:C)
    %v14 = arith.constant 0 : i64 loc("std/option/option.lin":L:C)
    %v15 = arith.cmpi eq, %v13, %v14 : i64 loc("std/option/option.lin":L:C)
    cf.cond_br %v15, ^b5, ^b4 loc("std/option/option.lin":L:C)
  ^b3:
    %v5 = arith.constant 8 : i64 loc("std/option/option.lin":L:C)
    %v6 = llvm.getelementptr %s0[%v5] : (!llvm.ptr, i64) -> !llvm.ptr, i8 loc("std/option/option.lin":L:C)
    %cl8 = arith.constant 16 : i64 loc("std/option/option.lin":L:C)
    "llvm.intr.memcpy"(%s3, %v6, %cl8) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/option/option.lin":L:C)
    %cl11 = arith.constant 16 : i64 loc("std/option/option.lin":L:C)
    "llvm.intr.memcpy"(%s2, %s3, %cl11) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/option/option.lin":L:C)
    cf.br ^b1 loc("std/option/option.lin":L:C)
  ^b4:
    %tk1 = arith.constant 3 : i32 loc("std/option/option.lin":L:C)
    %tf1 = llvm.mlir.addressof @linea_file4 : !llvm.ptr loc("std/option/option.lin":L:C)
    %tl1 = arith.constant L : i32 loc("std/option/option.lin":L:C)
    %tc1 = arith.constant C : i32 loc("std/option/option.lin":L:C)
    func.call @linea_trap(%tk1, %tf1, %tl1, %tc1) : (i32, !llvm.ptr, i32, i32) -> () loc("std/option/option.lin":L:C)
    llvm.unreachable loc("std/option/option.lin":L:C)
  ^b5:
    %cl19 = arith.constant 16 : i64 loc("std/option/option.lin":L:C)
    "llvm.intr.memcpy"(%s2, %s1, %cl19) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> () loc("std/option/option.lin":L:C)
    cf.br ^b1 loc("std/option/option.lin":L:C)
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    func.call @linea_set_args(%argc, %argv) : (i32, !llvm.ptr) -> ()
    %status = func.call @"lin.;main"() : () -> i64
    %status32 = arith.trunci %status : i64 to i32
    func.return %status32 : i32
  }
}
