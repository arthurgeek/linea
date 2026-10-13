Dump mir names declared types.

  $ linea dump-mir "$LINEA_ROOT"/tests/cmd/fixtures/declared_types_in_mir.lin > out
  $ cat out
  function ;main
  local $0 Coins value storage=bytes
  local $1 Notes value storage=bytes
  @0:
    %0 = addr_of Coins managed-address $0
    %1 = constant UInt64 value computation=i64 0
    %2 = field_addr UInt8 managed-address %0, %1
    %3 = constant UInt8 value computation=i64 3
    store_indirect UInt8 %2, %3
    %5 = addr_of Notes managed-address $1
    %6 = constant UInt64 value computation=i64 0
    %7 = field_addr UInt8 managed-address %5, %6
    %8 = constant UInt8 value computation=i64 2
    store_indirect UInt8 %7, %8
    %10 = constant UInt64 value computation=i64 1
    %11 = field_addr UInt8 managed-address %5, %10
    %12 = constant UInt8 value computation=i64 5
    store_indirect UInt8 %11, %12
    %14 = addr_of Coins managed-address $0
    %15 = addr_of Notes managed-address $1
    %16 = call UInt8 value computation=i64 @f1(%14, %15)
    ret %16
  function ;total
  local $0 Coins managed-address
  local $1 Notes managed-address
  @0:
    %0 = load Coins managed-address $0
    %1 = constant UInt64 value computation=i64 0
    %2 = field_addr UInt8 managed-address %0, %1
    %3 = load_indirect UInt8 value computation=i64 %2
    %4 = load Notes managed-address $1
    %5 = constant UInt64 value computation=i64 0
    %6 = field_addr UInt8 managed-address %4, %5
    %7 = load_indirect UInt8 value computation=i64 %6
    %8 = load Notes managed-address $1
    %9 = constant UInt64 value computation=i64 1
    %10 = field_addr UInt8 managed-address %8, %9
    %11 = load_indirect UInt8 value computation=i64 %10
    %12 = mul UInt8 value computation=i64 %7, %11
    %13 = check UInt8 value computation=i64 %12 (overflow)
    %14 = add UInt8 value computation=i64 %3, %13
    %15 = check UInt8 value computation=i64 %14 (overflow)
    ret %15
