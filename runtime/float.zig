const std = @import("std");
const decimal_provider = @import("decimal_provider");

const parse_token_limit = 65536;
const ParseStatus = enum(u64) { ok, syntax, out_of_range, token_limit };

// Input is a certified byte extent from std.mem. Outputs contain no observations.
export fn linea_float64_parse(address: u64, length: u64, bits: *u64, offset: *u64) callconv(.c) u64 {
    return parseDecimal(f64, address, length, bits, offset);
}

// The same as `linea_float64_parse`, rounding once to the nearest binary32
// value. `bits` receives the binary64 encoding of that value, which holds it
// exactly, so both widths cross the foreign interface as one kind of word.
export fn linea_float32_parse(address: u64, length: u64, bits: *u64, offset: *u64) callconv(.c) u64 {
    return parseDecimal(f32, address, length, bits, offset);
}

// One scanner owns the decimal grammar and its syntax offsets for both
// widths; only the provider's rounding target differs.
fn parseDecimal(comptime T: type, address: u64, length: u64, bits: *u64, offset: *u64) u64 {
    bits.* = 0;
    offset.* = 0;
    if (length > parse_token_limit) {
        offset.* = parse_token_limit;
        return @intFromEnum(ParseStatus.token_limit);
    }
    if (length == 0 or address == 0 or address > std.math.maxInt(usize)) return @intFromEnum(ParseStatus.syntax);
    const pointer: [*]const u8 = @ptrFromInt(@as(usize, @intCast(address)));
    const input = pointer[0..@intCast(length)];
    var at: usize = 0;
    const negative = input[0] == '-';
    if (negative or input[0] == '+') at += 1;
    const magnitude_start = at;
    var nonzero = false;
    if (!decimalDigits(input, &at, &nonzero)) return parseSyntax(at, offset);
    if (at < input.len and input[at] == '.') {
        at += 1;
        if (!decimalDigits(input, &at, &nonzero)) return parseSyntax(at, offset);
    }
    if (at < input.len and (input[at] == 'e' or input[at] == 'E')) {
        at += 1;
        if (at < input.len and (input[at] == '+' or input[at] == '-')) at += 1;
        var exponent_nonzero = false;
        if (!decimalDigits(input, &at, &exponent_nonzero)) return parseSyntax(at, offset);
    }
    if (at != input.len) return parseSyntax(at, offset);

    // The integer-only provider rounds using 768 digits and a discarded-tail
    // flag. Its biased significand/exponent already are the IEEE fields.
    const Bits = @Int(.unsigned, @bitSizeOf(T));
    const fraction_bits = std.math.floatFractionalBits(T);
    const converted = decimal_provider.convertSlow(T, input[magnitude_start..]);
    const magnitude: Bits = @intCast(converted.f | (@as(u64, @intCast(converted.e)) << fraction_bits));
    const infinity: Bits = @bitCast(std.math.inf(T));
    if (magnitude == infinity or (magnitude == 0 and nonzero)) return @intFromEnum(ParseStatus.out_of_range);
    const value: T = @bitCast(magnitude | (if (negative) @as(Bits, 1) << (@bitSizeOf(T) - 1) else 0));
    bits.* = @bitCast(@as(f64, value));
    return @intFromEnum(ParseStatus.ok);
}

fn decimalDigits(input: []const u8, at: *usize, nonzero: *bool) bool {
    const start = at.*;
    while (at.* < input.len and input[at.*] >= '0' and input[at.*] <= '9') : (at.* += 1) {
        nonzero.* = nonzero.* or input[at.*] != '0';
    }
    return at.* != start;
}

fn parseSyntax(at: usize, offset: *u64) u64 {
    offset.* = at;
    return @intFromEnum(ParseStatus.syntax);
}

export fn linea_float64_debug(bits: u64, first: *u64, second: *u64, third: *u64, fourth: *u64) callconv(.c) u64 {
    return debugWords(@as(f64, @bitCast(bits)), first, second, third, fourth);
}

// `bits` is the binary64 encoding of a binary32 value, which narrowing
// recovers exactly; the text is the shortest that reads back as that binary32.
export fn linea_float32_debug(bits: u64, first: *u64, second: *u64, third: *u64, fourth: *u64) callconv(.c) u64 {
    return debugWords(@as(f32, @floatCast(@as(f64, @bitCast(bits)))), first, second, third, fourth);
}

fn debugWords(value: anytype, first: *u64, second: *u64, third: *u64, fourth: *u64) u64 {
    var buffer: [std.fmt.float.bufferSize(.decimal, f64)]u8 = undefined;
    const text = render(value, &buffer);
    // The notation bounds keep every result within four words. Pack by
    // numeric shifts so the caller reads the same bytes on either endianness.
    std.debug.assert(text.len <= 32);
    var words = [_]u64{0} ** 4;
    for (text, 0..) |byte, index| words[index / 8] |= @as(u64, byte) << @as(u6, @intCast(index % 8 * 8));
    first.* = words[0];
    second.* = words[1];
    third.* = words[2];
    fourth.* = words[3];
    return text.len;
}

// Answer the shortest decimal that reads back as a finite value's magnitude,
// as a significand and a power of ten: 0.125 is 125 and -3. These are the
// digits `linea_float64_debug` prints, so a fixed precision rounds what
// Display shows.
export fn linea_float64_shortest(bits: u64, exponent: *i64) callconv(.c) u64 {
    const decimal = std.fmt.float.binaryToDecimal(u64, bits, 52, 11, false, &std.fmt.float.Backend64_TablesFull);
    exponent.* = decimal.exponent;
    return decimal.mantissa;
}

// The same for a binary32 value passed as its exact binary64 encoding: these
// are the digits `linea_float32_debug` prints.
export fn linea_float32_shortest(bits: u64, exponent: *i64) callconv(.c) u64 {
    const narrow: u32 = @bitCast(@as(f32, @floatCast(@as(f64, @bitCast(bits)))));
    const decimal = std.fmt.float.binaryToDecimal(u64, narrow, 23, 8, false, &std.fmt.float.Backend64_TablesFull);
    exponent.* = decimal.exponent;
    return decimal.mantissa;
}

test "binary32 shortest digits are a significand and a power of ten" {
    const Case = struct { value: f32, significand: u64, exponent: i64 };
    const cases = [_]Case{
        .{ .value = 0.1, .significand = 1, .exponent = -1 },
        .{ .value = 1.0 / 3.0, .significand = 33333334, .exponent = -8 },
        .{ .value = 16777216.0, .significand = 16777216, .exponent = 0 },
        .{ .value = std.math.floatTrueMin(f32), .significand = 1, .exponent = -45 },
        .{ .value = std.math.floatMax(f32), .significand = 34028235, .exponent = 31 },
    };
    for (cases) |case| {
        var exponent: i64 = 0;
        try std.testing.expectEqual(case.significand, linea_float32_shortest(@bitCast(@as(f64, case.value)), &exponent));
        try std.testing.expectEqual(case.exponent, exponent);
    }
}

test "float shortest digits are a significand and a power of ten" {
    const Case = struct { value: f64, significand: u64, exponent: i64 };
    // The value is held at run time, so the sum rounds in binary64 rather
    // than exactly.
    var tenth: f64 = 0.1;
    _ = &tenth;
    const cases = [_]Case{
        .{ .value = 0.125, .significand = 125, .exponent = -3 },
        .{ .value = -2.5, .significand = 25, .exponent = -1 },
        .{ .value = 1.005, .significand = 1005, .exponent = -3 },
        .{ .value = 1e22, .significand = 1, .exponent = 22 },
        .{ .value = tenth + 0.2, .significand = 30000000000000004, .exponent = -17 },
        .{ .value = 5e-324, .significand = 5, .exponent = -324 },
        .{ .value = std.math.floatMax(f64), .significand = 17976931348623157, .exponent = 292 },
    };
    for (cases) |case| {
        var exponent: i64 = 0;
        try std.testing.expectEqual(case.significand, linea_float64_shortest(@bitCast(case.value), &exponent));
        try std.testing.expectEqual(case.exponent, exponent);
    }
}

fn render(value: anytype, buffer: []u8) []const u8 {
    if (std.math.isNan(value)) return "NaN";
    if (std.math.isInf(value)) return if (value < 0) "-inf" else "inf";
    const magnitude = @abs(value);
    const mode: std.fmt.float.Mode = if (magnitude == 0 or (magnitude >= 1e-6 and magnitude < 1e16)) .decimal else .scientific;
    const text = std.fmt.float.render(buffer, value, .{ .mode = mode }) catch unreachable;
    if (mode == .decimal and std.mem.indexOfScalar(u8, text, '.') == null) {
        @memcpy(buffer[text.len..][0..2], ".0");
        return buffer[0 .. text.len + 2];
    }
    return text;
}

fn expectText(expected: []const u8, bits: u64) !void {
    var words = [_]u64{std.math.maxInt(u64)} ** 4;
    const length = linea_float64_debug(bits, &words[0], &words[1], &words[2], &words[3]);
    try std.testing.expect(length <= 32);
    var bytes: [32]u8 = undefined;
    for (&bytes, 0..) |*byte, index| byte.* = @truncate(words[index / 8] >> @as(u6, @intCast(index % 8 * 8)));
    try std.testing.expectEqualStrings(expected, bytes[0..@intCast(length)]);
    for (bytes[@intCast(length)..]) |byte| try std.testing.expectEqual(@as(u8, 0), byte);
}

test "float debug spelling and numeric byte packing" {
    const Case = struct { value: f64, text: []const u8 };
    const cases = [_]Case{
        .{ .value = 0.0, .text = "0.0" },
        .{ .value = -0.0, .text = "-0.0" },
        .{ .value = 1.0, .text = "1.0" },
        .{ .value = -2.5, .text = "-2.5" },
        .{ .value = 0.1, .text = "0.1" },
        .{ .value = 1e-6, .text = "0.000001" },
        .{ .value = 1e-7, .text = "1e-7" },
        .{ .value = 1e15, .text = "1000000000000000.0" },
        .{ .value = 1e16, .text = "1e16" },
        .{ .value = -1.2345678901234567e-6, .text = "-0.0000012345678901234567" },
        .{ .value = std.math.floatMin(f64), .text = "2.2250738585072014e-308" },
        .{ .value = std.math.floatMax(f64), .text = "1.7976931348623157e308" },
        .{ .value = std.math.inf(f64), .text = "inf" },
        .{ .value = -std.math.inf(f64), .text = "-inf" },
    };
    for (cases) |case| try expectText(case.text, @bitCast(case.value));
    try expectText("5e-324", 1);
    try expectText("-5e-324", 0x8000000000000001);
    try expectText("NaN", 0x7ff8000000000000);
    try expectText("NaN", 0xfff0000000000001);
}

test "float debug finite values round trip without losing bits" {
    var bits: u64 = 0;
    for (0..8192) |_| {
        bits +%= 0x9e3779b97f4a7c15;
        const value: f64 = @bitCast(bits);
        if (!std.math.isFinite(value)) continue;
        var words: [4]u64 = undefined;
        const length = linea_float64_debug(bits, &words[0], &words[1], &words[2], &words[3]);
        try std.testing.expect(length <= 32);
        var bytes: [32]u8 = undefined;
        for (&bytes, 0..) |*byte, index| byte.* = @truncate(words[index / 8] >> @as(u6, @intCast(index % 8 * 8)));
        try expectParsedBits(bytes[0..@intCast(length)], bits);
    }
}

fn expectText32(expected: []const u8, value: f32) !void {
    var words = [_]u64{std.math.maxInt(u64)} ** 4;
    const length = linea_float32_debug(@bitCast(@as(f64, value)), &words[0], &words[1], &words[2], &words[3]);
    try std.testing.expect(length <= 32);
    var bytes: [32]u8 = undefined;
    for (&bytes, 0..) |*byte, index| byte.* = @truncate(words[index / 8] >> @as(u6, @intCast(index % 8 * 8)));
    try std.testing.expectEqualStrings(expected, bytes[0..@intCast(length)]);
}

test "binary32 debug prints the shortest text that reads back as binary32" {
    const Case = struct { value: f32, text: []const u8 };
    const cases = [_]Case{
        .{ .value = 0.0, .text = "0.0" },
        .{ .value = -0.0, .text = "-0.0" },
        .{ .value = 0.1, .text = "0.1" },
        .{ .value = 1.0 / 3.0, .text = "0.33333334" },
        .{ .value = 16777216.0, .text = "16777216.0" },
        .{ .value = 1e-6, .text = "0.000001" },
        .{ .value = 1e-7, .text = "1e-7" },
        .{ .value = 1e16, .text = "1e16" },
        .{ .value = std.math.floatTrueMin(f32), .text = "1e-45" },
        .{ .value = std.math.floatMin(f32), .text = "1.1754944e-38" },
        .{ .value = std.math.floatMax(f32), .text = "3.4028235e38" },
        .{ .value = std.math.inf(f32), .text = "inf" },
        .{ .value = -std.math.inf(f32), .text = "-inf" },
        .{ .value = std.math.nan(f32), .text = "NaN" },
    };
    for (cases) |case| try expectText32(case.text, case.value);
}

fn expectParsed32(input: []const u8, expected: u32) !void {
    var bits: u64 = std.math.maxInt(u64);
    var offset: u64 = std.math.maxInt(u64);
    try std.testing.expectEqual(@as(u64, 0), linea_float32_parse(@intFromPtr(input.ptr), input.len, &bits, &offset));
    try std.testing.expectEqual(expected, @as(u32, @bitCast(@as(f32, @floatCast(@as(f64, @bitCast(bits)))))));
    try std.testing.expectEqual(@as(u64, 0), offset);
}

fn expectOutOfRange32(input: []const u8) !void {
    var bits: u64 = 999;
    var offset: u64 = 999;
    try std.testing.expectEqual(@as(u64, 2), linea_float32_parse(@intFromPtr(input.ptr), input.len, &bits, &offset));
    try std.testing.expectEqual(@as(u64, 0), bits);
}

test "binary32 parsing rounds once to the nearest even binary32 value" {
    // Just above the halfway point 1 + 2^-24: rounding through binary64 would
    // land on the halfway point and then on the even 1.0.
    try expectParsed32("1.0000000596046447753906250000000001", 0x3f800001);
    try expectParsed32("1.000000059604644775390625", 0x3f800000);
    try expectParsed32("16777217", 0x4b800000);
    try expectParsed32("16777219", 0x4b800002);
    try expectParsed32("0.1", 0x3dcccccd);
    try expectParsed32("-0", 0x80000000);
    try expectParsed32("340282356779733661637539395458142568447", 0x7f7fffff);
    try expectParsed32("7.0064923216240862e-46", 0x00000001);
    try expectParsed32("1.1754942e-38", 0x007fffff);
    try expectParsed32("1.1754944e-38", 0x00800000);
    try expectParsed32("1.000000059604644775390625" ++ ("0" ** 900) ++ "1", 0x3f800001);
    try expectOutOfRange32("340282356779733661637539395458142568448");
    try expectOutOfRange32("7.0064923216240853e-46");
    try expectOutOfRange32("1e39");
    try expectOutOfRange32("-1e-50");
}

test "binary32 parsing shares the decimal grammar and its offsets" {
    var bits: u64 = 999;
    var offset: u64 = 999;
    try std.testing.expectEqual(@as(u64, 1), linea_float32_parse(@intFromPtr("1.".ptr), 2, &bits, &offset));
    try std.testing.expectEqual(@as(u64, 2), offset);
    try std.testing.expectEqual(@as(u64, 3), linea_float32_parse(0, parse_token_limit + 1, &bits, &offset));
}

test "binary32 parsing ignores ambient rounding modes" {
    const fenv = @cImport(@cInclude("fenv.h"));
    const original = fenv.fegetround();
    defer _ = fenv.fesetround(original);
    for ([_]c_int{ fenv.FE_TONEAREST, fenv.FE_DOWNWARD, fenv.FE_UPWARD, fenv.FE_TOWARDZERO }) |mode| {
        try std.testing.expectEqual(@as(c_int, 0), fenv.fesetround(mode));
        try expectParsed32("0.1", 0x3dcccccd);
        try expectParsed32("1.0000000596046447753906250000000001", 0x3f800001);
        try expectParsed32("16777217", 0x4b800000);
        try std.testing.expectEqual(mode, fenv.fegetround());
    }
}

// Renders a binary32 pattern, parses the text back, and holds the result to
// the same pattern; and the text has at most nine significant digits.
fn expectRoundTrip32(pattern: u32) !void {
    const value: f32 = @bitCast(pattern);
    if (!std.math.isFinite(value)) return;
    var words: [4]u64 = undefined;
    const length = linea_float32_debug(@bitCast(@as(f64, value)), &words[0], &words[1], &words[2], &words[3]);
    var bytes: [32]u8 = undefined;
    for (&bytes, 0..) |*byte, index| byte.* = @truncate(words[index / 8] >> @as(u6, @intCast(index % 8 * 8)));
    const text = bytes[0..@intCast(length)];
    try expectParsed32(text, pattern);
    var exponent: i64 = 0;
    const significand = linea_float32_shortest(@bitCast(@as(f64, value)), &exponent);
    try std.testing.expect(significand < 1_000_000_000);
}

test "binary32 display round trips through parsing" {
    var pattern: u32 = 0;
    while (true) {
        try expectRoundTrip32(pattern);
        pattern, const overflow = @addWithOverflow(pattern, 65537);
        if (overflow != 0) break;
    }
    for (0..254) |exponent| try expectRoundTrip32(@as(u32, @intCast(exponent + 1)) << 23);
    for ([_]u32{ 1, 0x007fffff, 0x00800000, 0x7f7fffff, 0x3f800001, 0x4b800000 }) |edge| {
        try expectRoundTrip32(edge);
        try expectRoundTrip32(edge | 0x80000000);
    }
}

test "float debug rendering preserves the source precision" {
    var buffer: [std.fmt.float.bufferSize(.decimal, f32)]u8 = undefined;
    try std.testing.expectEqualStrings("0.1", render(@as(f32, 0.1), &buffer));
}

fn expectParsedBits(input: []const u8, expected: u64) !void {
    var bits: u64 = std.math.maxInt(u64);
    var offset: u64 = std.math.maxInt(u64);
    try std.testing.expectEqual(@as(u64, 0), linea_float64_parse(@intFromPtr(input.ptr), input.len, &bits, &offset));
    try std.testing.expectEqual(expected, bits);
    try std.testing.expectEqual(@as(u64, 0), offset);
}

test "float checked parsing uses nearest even known binary64 values" {
    const cases = [_]struct { text: []const u8, bits: u64 }{
        .{ .text = "0", .bits = 0 },
        .{ .text = "-0", .bits = 0x8000000000000000 },
        .{ .text = "+000.125", .bits = 0x3fc0000000000000 },
        .{ .text = "0.1", .bits = 0x3fb999999999999a },
        .{ .text = "9007199254740993", .bits = 0x4340000000000000 },
        .{ .text = "9007199254740995", .bits = 0x4340000000000002 },
        .{ .text = "1.00000000000000011102230246251565404236316680908203125", .bits = 0x3ff0000000000000 },
        .{ .text = "1.00000000000000011102230246251565404236316680908203126", .bits = 0x3ff0000000000001 },
        .{ .text = "1.00000000000000033306690738754696212708950042724609375", .bits = 0x3ff0000000000002 },
        .{ .text = "2.2250738585072014e-308", .bits = 0x0010000000000000 },
        .{ .text = "2.225073858507201e-308", .bits = 0x000fffffffffffff },
        .{ .text = "5e-324", .bits = 1 },
        .{ .text = "-5e-324", .bits = 0x8000000000000001 },
        .{ .text = "2.4703282292062328e-324", .bits = 1 },
        .{ .text = "1.7976931348623157e308", .bits = 0x7fefffffffffffff },
        .{ .text = "1.7976931348623158e308", .bits = 0x7fefffffffffffff },
        .{ .text = "-0e999999999999999999999", .bits = 0x8000000000000000 },
    };
    for (cases) |case| try expectParsedBits(case.text, case.bits);
}

test "float checked parsing rejects range loss and observes explicit extent" {
    for ([_][]const u8{ "1e309", "-1e999999", "1e-324", "-1e-999999", "2.4703282292062327e-324" }) |input| {
        var bits: u64 = 999;
        var offset: u64 = 999;
        try std.testing.expectEqual(@as(u64, 2), linea_float64_parse(@intFromPtr(input.ptr), input.len, &bits, &offset));
        try std.testing.expectEqual(@as(u64, 0), bits);
    }
    const input = "1.25junk";
    try expectParsedBits(input[0..4], 0x3ff4000000000000);
    var bits: u64 = 999;
    var offset: u64 = 999;
    try std.testing.expectEqual(@as(u64, 1), linea_float64_parse(@intFromPtr(input.ptr), input.len, &bits, &offset));
    try std.testing.expectEqual(@as(u64, 4), offset);
    try std.testing.expectEqual(@as(u64, 0), bits);
}

test "float checked parsing retains discarded digits beyond provider storage" {
    const half = "1.00000000000000011102230246251565404236316680908203125";
    try expectParsedBits(half ++ ("0" ** 900), 0x3ff0000000000000);
    try expectParsedBits(half ++ ("0" ** 900) ++ "1", 0x3ff0000000000001);
    try expectParsedBits("-" ++ half ++ ("0" ** 900) ++ "1", 0xbff0000000000001);
    try expectParsedBits("0." ++ ("0" ** 900) ++ "1e901", 0x3ff0000000000000);
}

test "float checked parsing bounds input before dereference and reports syntax" {
    const invalid = [_]struct { text: []const u8, offset: u64 }{
        .{ .text = "", .offset = 0 },
        .{ .text = "+", .offset = 1 },
        .{ .text = ".1", .offset = 0 },
        .{ .text = "1.", .offset = 2 },
        .{ .text = "1e", .offset = 2 },
        .{ .text = "1e+", .offset = 3 },
        .{ .text = " 1", .offset = 0 },
        .{ .text = "1 ", .offset = 1 },
        .{ .text = "1_0", .offset = 1 },
        .{ .text = "0x1p0", .offset = 1 },
        .{ .text = "nan", .offset = 0 },
        .{ .text = "inf", .offset = 0 },
        .{ .text = "12\x003", .offset = 2 },
    };
    for (invalid) |case| {
        var bits: u64 = 999;
        var offset: u64 = 999;
        try std.testing.expectEqual(@as(u64, 1), linea_float64_parse(@intFromPtr(case.text.ptr), case.text.len, &bits, &offset));
        try std.testing.expectEqual(case.offset, offset);
        try std.testing.expectEqual(@as(u64, 0), bits);
    }
    var bits: u64 = 999;
    var offset: u64 = 999;
    try std.testing.expectEqual(@as(u64, 3), linea_float64_parse(0, parse_token_limit + 1, &bits, &offset));
    try std.testing.expectEqual(@as(u64, parse_token_limit), offset);
    try std.testing.expectEqual(@as(u64, 0), bits);
    const longest = "0" ** parse_token_limit;
    try expectParsedBits(longest, 0);
}

test "float checked parsing ignores and preserves ambient rounding modes" {
    const fenv = @cImport(@cInclude("fenv.h"));
    const original = fenv.fegetround();
    defer _ = fenv.fesetround(original);
    for ([_]c_int{ fenv.FE_TONEAREST, fenv.FE_DOWNWARD, fenv.FE_UPWARD, fenv.FE_TOWARDZERO }) |mode| {
        try std.testing.expectEqual(@as(c_int, 0), fenv.fesetround(mode));
        try expectParsedBits("0.1", 0x3fb999999999999a);
        try expectParsedBits("9007199254740993", 0x4340000000000000);
        try expectParsedBits("1.00000000000000033306690738754696212708950042724609375", 0x3ff0000000000002);
        try expectParsedBits("5e-324", 1);
        try expectParsedBits("-0", 0x8000000000000000);
        try std.testing.expectEqual(mode, fenv.fegetround());
    }
}
