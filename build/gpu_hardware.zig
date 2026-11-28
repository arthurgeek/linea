const std = @import("std");

pub const Steps = struct {
    hardware: *std.Build.Step,
    shaders: *std.Build.Step,
};

const Shader = struct {
    bytes: std.Build.LazyPath,
    validation: *std.Build.Step,
};

const helpers = @embedFile("../src/backend/gpu/float32.mlir");
const pair_template = @embedFile("../runtime/tests/gpu_float32/pair.mlir");

fn pairSource(b: *std.Build, operation: []const u8, comparison: bool) []const u8 {
    const call = if (comparison)
        b.fmt(
            \\      %predicate = spirv.FunctionCall @linea_f32_{s}(%left, %right) : (i32, i32) -> i1
            \\      %result = spirv.Select %predicate, %one, %zero : i1, i32
        , .{operation})
    else
        b.fmt("      %result = spirv.FunctionCall @linea_f32_{s}(%left, %right) : (i32, i32) -> i32", .{operation});
    return pairKernel(b, call);
}

fn pairKernel(b: *std.Build, call: []const u8) []const u8 {
    const with_helpers = std.mem.replaceOwned(u8, b.allocator, pair_template, "@HELPERS@", helpers) catch @panic("OOM");
    return std.mem.replaceOwned(u8, b.allocator, with_helpers, "@OPERATION@", call) catch @panic("OOM");
}

fn numericalSource(b: *std.Build, reduction: ?[]const u8, extra: []const u8) []const u8 {
    const globals = if (reduction != null)
        @embedFile("../src/backend/gpu/reduce_globals.mlir")
    else
        @embedFile("../src/backend/gpu/matmul_globals.mlir");
    const wrapper = if (reduction) |root|
        std.mem.replaceOwned(u8, b.allocator, @embedFile("../src/backend/gpu/reduce.mlir") ++ @embedFile("../src/backend/gpu/binary_map.mlir"), "ROOT", root) catch @panic("OOM")
    else
        @embedFile("../src/backend/gpu/matmul.mlir");
    return b.fmt("spirv.module Logical GLSL450 requires #spirv.vce<v1.3, [Shader], []> {{\n{s}\n{s}\n{s}\n{s}\n}}\n", .{ globals, helpers, extra, wrapper });
}

fn shader(b: *std.Build, checker: *std.Build.Step.Compile, name: []const u8, text: []const u8, barriers: usize) Shader {
    const source = b.addWriteFiles().add(b.fmt("{s}.mlir", .{name}), text);
    const opt = b.addSystemCommand(&.{ "mlir-opt", "--no-implicit-module", "--pass-pipeline=spirv.module(symbol-dce)" });
    opt.addFileArg(source);
    opt.addArg("-o");
    const checked = opt.addOutputFileArg(b.fmt("{s}.checked.mlir", .{name}));
    const translate = b.addSystemCommand(&.{ "mlir-translate", "--no-implicit-module", "--serialize-spirv" });
    translate.addFileArg(checked);
    translate.addArg("-o");
    const bytes = translate.addOutputFileArg(b.fmt("{s}.spv", .{name}));
    const validate = b.addSystemCommand(&.{ "spirv-val", "--target-env", "vulkan1.1" });
    validate.addFileArg(bytes);
    const disassemble = b.addSystemCommand(&.{"spirv-dis"});
    disassemble.addFileArg(bytes);
    disassemble.addArg("-o");
    const assembly = disassemble.addOutputFileArg(b.fmt("{s}.spvasm", .{name}));
    const inspect = b.addRunArtifact(checker);
    inspect.addFileArg(assembly);
    inspect.addArg(b.fmt("{d}", .{barriers}));
    inspect.step.dependOn(&validate.step);
    return .{ .bytes = bytes, .validation = &inspect.step };
}

fn harness(
    b: *std.Build,
    archive: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    sanitize: ?[]const u8,
    name: []const u8,
    source: []const u8,
    headers: []const []const u8,
) *std.Build.Step.Run {
    const compile = b.addSystemCommand(&.{
        "cc",             "-std=c99",          "-pedantic",       "-Wall", "-Wextra", "-Werror", "-UNDEBUG", "-O2",
        "-fno-fast-math", "-ffp-contract=off", "-frounding-math",
    });
    if (sanitize) |selected| compile.addArgs(&.{
        b.fmt("-fsanitize={s}", .{selected}), "-fsanitize=undefined", "-fno-sanitize-recover=all", "-g",
    });
    if (target.result.os.tag == .macos)
        compile.addArg(b.fmt("-mmacosx-version-min={f}", .{target.result.os.version_range.semver.min}));
    compile.addFileArg(b.path(source));
    for (headers) |header| compile.addFileInput(b.path(header));
    compile.addFileArg(archive);
    if (target.result.os.tag == .linux) compile.addArgs(&.{ "-lpthread", "-ldl", "-lm" });
    compile.addArg("-o");
    const executable = compile.addOutputFileArg(name);
    const run = std.Build.Step.Run.create(b, b.fmt("run {s}", .{name}));
    run.addFileArg(executable);
    run.has_side_effects = true;
    return run;
}

/// Hardware regressions use the exact runtime archive supplied by their build,
/// and retain every generated/validated shader as a build-owned LazyPath.
pub fn add(
    b: *std.Build,
    archive: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    sanitize: ?[]const u8,
) Steps {
    const all = b.step("test-gpu-kernels", "Run production numerical GPU kernel hardware regressions");
    const float32 = b.step("test-gpu-float32", "Check strict Float32 arithmetic and comparisons on hardware");
    const numerical = b.step("test-gpu-numerical", "Check fixed-tree reduction and strict matrix multiplication on hardware");
    const shaders = b.step("test-gpu-shaders", "Validate production numerical SPIR-V and integer32-only contracts without hardware");
    all.dependOn(float32);
    all.dependOn(numerical);
    const checker = b.addExecutable(.{
        .name = "gpu-spirv-check",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/gpu_spirv_check.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
        }),
    });
    const checker_tests = b.addTest(.{ .root_module = checker.root_module });
    const run_checker_tests = b.addRunArtifact(checker_tests);
    shaders.dependOn(&run_checker_tests.step);
    // A transfer-only kernel needs none of the arithmetic library. Half uses
    // multiply and its transitive strict helpers, but no add/divide/comparisons.
    const identity = shader(b, checker, "identity", pairKernel(b, "      %result = spirv.BitwiseOr %left, %zero : i32"), 0);
    shaders.dependOn(identity.validation);
    const half = shader(b, checker, "half", pairKernel(b,
        \\      %half = spirv.Constant 1056964608 : i32
        \\      %result = spirv.FunctionCall @linea_f32_mul(%left, %half) : (i32, i32) -> i32
    ), 0);
    shaders.dependOn(half.validation);
    const headers: []const []const u8 = &.{ "runtime/gpu.h", "runtime/tests/gpu_float32/float_cases.h" };
    const arithmetic = harness(b, archive, target, sanitize, "gpu-float32-arithmetic", "runtime/tests/gpu_float32/main.c", headers);
    for ([_][]const u8{ "add", "sub", "mul", "div" }) |operation| {
        const image = shader(b, checker, b.fmt("float32-{s}", .{operation}), pairSource(b, operation, false), 0);
        arithmetic.addFileArg(image.bytes);
        arithmetic.step.dependOn(image.validation);
        shaders.dependOn(image.validation);
    }
    float32.dependOn(&arithmetic.step);
    const comparisons = harness(b, archive, target, sanitize, "gpu-float32-comparisons", "runtime/tests/gpu_float32/compare.c", headers);
    for ([_][]const u8{ "eq", "ne", "lt", "le", "gt", "ge" }) |operation| {
        const image = shader(b, checker, b.fmt("float32-{s}", .{operation}), pairSource(b, operation, true), 0);
        comparisons.addFileArg(image.bytes);
        comparisons.step.dependOn(image.validation);
        shaders.dependOn(image.validation);
    }
    float32.dependOn(&comparisons.step);
    const matrices = harness(b, archive, target, sanitize, "gpu-numerical", "runtime/tests/gpu_numerical/main.c", &.{"runtime/gpu.h"});
    for ([_][]const u8{ "linea_f32_add", "linea_f32_sub" }) |operation| {
        const image = shader(b, checker, b.fmt("reduce-{s}", .{operation}), numericalSource(b, operation, ""), 7);
        matrices.addFileArg(image.bytes);
        matrices.step.dependOn(image.validation);
        shaders.dependOn(image.validation);
    }
    const matmul = shader(b, checker, "matmul", numericalSource(b, null, ""), 0);
    matrices.addFileArg(matmul.bytes);
    matrices.step.dependOn(matmul.validation);
    shaders.dependOn(matmul.validation);
    const counted = shader(b, checker, "reduce-count-calls", numericalSource(b, "linea_count_add", @embedFile("../runtime/tests/gpu_numerical/count_calls.mlir")), 7);
    matrices.addFileArg(counted.bytes);
    matrices.step.dependOn(counted.validation);
    shaders.dependOn(counted.validation);
    numerical.dependOn(&matrices.step);
    return .{ .hardware = all, .shaders = shaders };
}
