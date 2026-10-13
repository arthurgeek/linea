const std = @import("std");
const decimal_provider = @import("decimal_provider");

const parse_token_limit = 65536;
const ParseStatus = enum(u64) { ok, syntax, out_of_range, token_limit };

// Input is a certified byte extent from std.mem. Outputs contain no observations.
export fn linea_float64_parse(address: u64, length: u64, bits: *u64, offset: *u64) callconv(.c) u64 {
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
    const converted = decimal_provider.convertSlow(f64, input[magnitude_start..]);
    const magnitude = converted.f | (@as(u64, @intCast(converted.e)) << 52);
    const infinity = @as(u64, 0x7ff0000000000000);
    if (magnitude == infinity or (magnitude == 0 and nonzero)) return @intFromEnum(ParseStatus.out_of_range);
    bits.* = magnitude | (if (negative) @as(u64, 1) << 63 else 0);
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
    var buffer: [std.fmt.float.bufferSize(.decimal, f64)]u8 = undefined;
    const text = render(@as(f64, @bitCast(bits)), &buffer);
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
