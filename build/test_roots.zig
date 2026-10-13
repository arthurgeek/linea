//! Optimization selection and the roots owned by each named test suite.

const std = @import("std");

pub fn optimizeMode(release: std.Build.ReleaseMode, preferred: ?bool) std.builtin.OptimizeMode {
    return switch (release) {
        .safe => .ReleaseSafe,
        .fast => .ReleaseFast,
        .small => .ReleaseSmall,
        .off, .any => if (preferred orelse (release != .off)) .ReleaseFast else .Debug,
    };
}

pub const Suite = enum { full, corpus, support, unit, conformance, fuzz };
pub const Root = enum { joined, fuzz };

pub const Options = struct {
    optimize: std.builtin.OptimizeMode,
    suite: Suite = .full,
    filtered: bool,
};

pub const Selection = struct {
    selected: ?Root,
    source: bool,
    corpus: bool,
    examples: bool,
    /// The guide gate checks pasted output, so it runs once with the ordinary
    /// runtime and never in `conformance`, which the sanitizer lanes run.
    guide: bool,
    editor: bool,
};

pub fn select(options: Options) Selection {
    // Both split suites project the full graph, including its filter policy.
    const suite: Suite = switch (options.suite) {
        .corpus, .support => .full,
        else => options.suite,
    };
    const broad = suite == .full and !options.filtered;
    var selected: Selection = .{
        .selected = switch (suite) {
            .full, .unit => .joined,
            .conformance => null,
            .fuzz => .fuzz,
            .corpus, .support => unreachable,
        },
        .source = suite == .full or suite == .unit,
        .corpus = broad or suite == .conformance,
        .examples = broad or suite == .conformance,
        .guide = broad,
        .editor = broad,
    };
    if (options.suite == .corpus) return .{
        .selected = null,
        .source = false,
        .corpus = selected.corpus,
        .examples = false,
        .guide = false,
        .editor = false,
    };
    if (options.suite == .support) selected.corpus = false;
    return selected;
}

/// The steps of a test run that each hold gigabytes: three compiles of the
/// compiler and the runs that compile programs in process or start compilers
/// of their own.
pub const Heavy = enum {
    compile_compiler,
    compile_runner,
    corpus,
    properties,
    examples,
    guide,
    compile_unit_tests,
    unit_tests,
};

pub const HeavyOrder = struct {
    steps: [@typeInfo(Heavy).@"enum".fields.len]Heavy = undefined,
    len: usize = 0,

    pub fn slice(self: *const HeavyOrder) []const Heavy {
        return self.steps[0..self.len];
    }

    fn add(self: *HeavyOrder, heavy: Heavy) void {
        self.steps[self.len] = heavy;
        self.len += 1;
    }
};

/// The heavy steps a selection runs, in the order a run that may hold only
/// one of them at a time runs them. Only what the selection already includes
/// is listed, so ordering them adds nothing to the run. The unit tests come
/// first: they fail most often, and a failure stops every step after it.
///
/// `properties` says whether the suite runs the focused properties, which no
/// selection field records; `guide` whether the guide is left in `test`.
pub fn heavyOrder(selection: Selection, options: struct { properties: bool, guide: bool }) HeavyOrder {
    var order: HeavyOrder = .{};
    const guide = selection.guide and options.guide;
    if (selection.selected == .joined) {
        order.add(.compile_unit_tests);
        order.add(.unit_tests);
    }
    if (selection.corpus or guide) order.add(.compile_compiler);
    if (selection.corpus or selection.examples) order.add(.compile_runner);
    if (selection.corpus) order.add(.corpus);
    if (selection.corpus and options.properties) order.add(.properties);
    if (selection.examples) order.add(.examples);
    if (guide) order.add(.guide);
    return order;
}

/// What `zig build conformance` walks: the whole corpus, with its coverage
/// floors and the examples beside it, or the one directory, case or transcript
/// named after `--`, run as a corpus of its own and held to nothing it does not
/// contain.
pub const Walk = union(enum) {
    whole,
    narrowed: []const u8,
};

pub fn walkOf(args: ?[]const []const u8) error{SeveralDirectories}!Walk {
    const given = args orelse return .whole;
    return switch (given.len) {
        0 => .whole,
        1 => .{ .narrowed = given[0] },
        else => error.SeveralDirectories,
    };
}
