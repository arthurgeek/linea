Dump mir omits a signature.

  $ linea dump-mir "$LINEA_ROOT"/tests/cmd/fixtures/a_signature_is_not_a_function.lin > out
  $ cat out
  function ;main
  local $0 Account value storage=bytes
  @0:
    %0 = addr_of Account managed-address $0
    %1 = constant UInt64 value computation=i64 0
    %2 = field_addr UInt8 managed-address %0, %1
    %3 = constant UInt8 value computation=i64 7
    store_indirect UInt8 %2, %3
    %5 = call UInt8 value computation=i64 @f1(%0)
    ret %5
  function ;total
  local $0 Account managed-address
  @0:
    %0 = load Account managed-address $0
    %1 = call UInt8 value computation=i64 @f2(%0)
    ret %1
  function Account;;Measure.of
  local $0 Account managed-address
  @0:
    %0 = load Account managed-address $0
    %1 = constant UInt64 value computation=i64 0
    %2 = field_addr UInt8 managed-address %0, %1
    %3 = load_indirect UInt8 value computation=i64 %2
    ret %3
