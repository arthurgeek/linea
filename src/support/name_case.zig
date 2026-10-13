const std = @import("std");
const testing = std.testing;

/// The case a name starts with.
pub const Case = enum {
    capital,
    lower,

    /// How a diagnostic says what a name of this case starts with.
    pub fn describe(self: Case) []const u8 {
        return switch (self) {
            .capital => "a capital letter",
            .lower => "a lowercase letter",
        };
    }
};

/// What a declared name names, as far as its case is concerned: one answer
/// that resolution checks [N-Case] against and a rename checks a new name
/// against.
pub const Kind = enum {
    declared_type,
    trait,
    associated_type,
    variant,
    type_parameter,
    function,
    projection,
    traversal,
    field,
    parameter,
    constant,
    module,
    capture,
    binding,

    /// The case a name of this kind starts with. A name standing for a type,
    /// or for a way to build a value of one, is capitalised; a name standing
    /// for a value, an operation or a module is lowercase.
    pub fn case(self: Kind) Case {
        return switch (self) {
            .declared_type, .trait, .associated_type, .variant, .type_parameter => .capital,
            .function, .projection, .traversal, .field, .parameter, .constant, .module, .capture, .binding => .lower,
        };
    }

    /// How a diagnostic names every name of this kind at once.
    pub fn plural(self: Kind) []const u8 {
        return switch (self) {
            .declared_type => "types",
            .trait => "traits",
            .associated_type => "associated types",
            .variant => "variants",
            .type_parameter => "type parameters",
            .function => "functions",
            .projection => "projections",
            .traversal => "traversals",
            .field => "fields",
            .parameter => "parameters",
            .constant => "constants",
            .module => "modules",
            .capture => "captures",
            .binding => "bindings",
        };
    }
};

/// The case of a name's first letter, or null where it has none. A leading
/// `_` marks a name deliberately unused and says nothing about its case, and
/// neither does a digit, so `_T` is capitalised and `_1light` lowercase; `_`
/// and `_1` have no case.
pub fn of(name: []const u8) ?Case {
    for (name) |c| {
        if (std.ascii.isUpper(c)) return .capital;
        if (std.ascii.isLower(c)) return .lower;
    }
    return null;
}

test "a name's case is its first letter's" {
    try testing.expectEqual(@as(?Case, .capital), of("Shade"));
    try testing.expectEqual(@as(?Case, .lower), of("shade"));
    try testing.expectEqual(@as(?Case, .capital), of("_T"));
    try testing.expectEqual(@as(?Case, .lower), of("__count"));
    try testing.expectEqual(@as(?Case, .lower), of("_1light"));
    try testing.expectEqual(@as(?Case, .capital), of("_2Big"));
    try testing.expectEqual(@as(?Case, null), of("_"));
    try testing.expectEqual(@as(?Case, null), of("_1"));
}

/// `name` respelled to start in `case`, keeping its leading underscores.
///
/// A capitalised spelling joins the words of a snake-case name, so
/// `not_found` becomes `NotFound`; a `_` between two digits is kept, since
/// dropping it would join two numbers into one (`x86_64` becomes `X86_64`).
/// A lowercase spelling separates the words of a capitalised one: `MakeThing`
/// becomes `make_thing`, a run of capitals is one word (`XMLHttpRequest`
/// becomes `xml_http_request`), and a single capital before lowercase letters
/// belongs to the word that follows it (`IPv4Addr` becomes `ipv4_addr`). A
/// name with no lowercase letter at all, such as `MAX_SIZE`, is lowercased
/// whole.
pub fn recased(gpa: std.mem.Allocator, name: []const u8, case: Case) std.mem.Allocator.Error![]u8 {
    const body_start = name.len - std.mem.trimStart(u8, name, "_").len;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, name[0..body_start]);
    const body = name[body_start..];
    switch (case) {
        .capital => {
            var start_word = true;
            var capitalised = false;
            for (body, 0..) |c, i| {
                if (c == '_') {
                    const between_digits = i > 0 and std.ascii.isDigit(body[i - 1]) and
                        i + 1 < body.len and std.ascii.isDigit(body[i + 1]);
                    if (between_digits) try out.append(gpa, '_');
                    start_word = true;
                    continue;
                }
                const first_letter = std.ascii.isAlphabetic(c) and (start_word or !capitalised);
                try out.append(gpa, if (first_letter) std.ascii.toUpper(c) else c);
                if (std.ascii.isAlphabetic(c)) {
                    start_word = false;
                    capitalised = true;
                }
            }
        },
        .lower => {
            const has_lower = for (body) |c| {
                if (std.ascii.isLower(c)) break true;
            } else false;
            var seen_letter = false;
            for (body, 0..) |c, i| {
                if (has_lower and seen_letter and std.ascii.isUpper(c)) {
                    const before = body[i - 1];
                    const after_is_lower = i + 1 < body.len and std.ascii.isLower(body[i + 1]);
                    // A capital ending a run of two or more before lowercase
                    // letters begins the next word: `XMLHttp`. One capital
                    // before a lowercase letter does not: `IPv4`.
                    const run_of_two = i >= 2 and std.ascii.isUpper(body[i - 2]);
                    const starts_word = std.ascii.isLower(before) or std.ascii.isDigit(before) or
                        (std.ascii.isUpper(before) and after_is_lower and run_of_two);
                    if (starts_word) try out.append(gpa, '_');
                }
                try out.append(gpa, std.ascii.toLower(c));
                if (std.ascii.isAlphabetic(c)) seen_letter = true;
            }
        },
    }
    return out.toOwnedSlice(gpa);
}

test "a name is respelled in the case its kind requires" {
    const cases = [_]struct { name: []const u8, case: Case, expected: []const u8 }{
        .{ .name = "light", .case = .capital, .expected = "Light" },
        .{ .name = "not_found", .case = .capital, .expected = "NotFound" },
        .{ .name = "_spare", .case = .capital, .expected = "_Spare" },
        .{ .name = "t", .case = .capital, .expected = "T" },
        .{ .name = "Bump", .case = .lower, .expected = "bump" },
        .{ .name = "MakeThing", .case = .lower, .expected = "make_thing" },
        .{ .name = "HTTPServer", .case = .lower, .expected = "http_server" },
        .{ .name = "Utf8Error", .case = .lower, .expected = "utf8_error" },
        .{ .name = "MAX_SIZE", .case = .lower, .expected = "max_size" },
        .{ .name = "N", .case = .lower, .expected = "n" },
        .{ .name = "_Ignored", .case = .lower, .expected = "_ignored" },
        .{ .name = "x86_64", .case = .capital, .expected = "X86_64" },
        .{ .name = "http2_server", .case = .capital, .expected = "Http2Server" },
        .{ .name = "_1light", .case = .capital, .expected = "_1Light" },
        .{ .name = "IPv4Addr", .case = .lower, .expected = "ipv4_addr" },
        .{ .name = "XMLHttpRequest", .case = .lower, .expected = "xml_http_request" },
        .{ .name = "_2Big", .case = .lower, .expected = "_2big" },
    };
    for (cases) |c| {
        const got = try recased(testing.allocator, c.name, c.case);
        defer testing.allocator.free(got);
        try testing.expectEqualStrings(c.expected, got);
    }
}
