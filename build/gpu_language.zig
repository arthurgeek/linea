const std = @import("std");

const programs = [_][]const u8{
    "runtime/tests/gpu_runtime/numerical_map.lin",
    "runtime/tests/gpu_runtime/numerical_values.lin",
    "runtime/tests/gpu_runtime/numerical_reduce.lin",
    "runtime/tests/gpu_runtime/numerical_matmul.lin",
    "runtime/tests/gpu_runtime/numerical_control_flow.lin",
    "runtime/tests/gpu_runtime/numerical_pipeline.lin",
    "runtime/tests/gpu_runtime/numerical_failures.lin",
    "runtime/tests/gpu_runtime/numerical_tasks.lin",
    "runtime/tests/gpu_runtime/numerical_shared.lin",
    "runtime/tests/gpu_runtime/numerical_uniform.lin",
    "runtime/tests/gpu_runtime/numerical_identity.lin",
    "examples/gpu_readings.lin",
    "examples/gpu_matrix.lin",
    "examples/numerical_gpu.lin",
    "examples/tensor_pipeline.lin",
};

/// Execute through the actual driver, with mandatory hardware discovery.
pub fn add(b: *std.Build, compiler: std.Build.LazyPath, runtime: std.Build.LazyPath) *std.Build.Step {
    const step = b.step("test-gpu-language", "Execute Linea tensor programs on a real GPU");
    for (programs) |path| {
        const variants: usize = if (std.mem.endsWith(u8, path, "numerical_pipeline.lin")) 2 else 1;
        for (0..variants) |variant| {
            const run = command(b, compiler, runtime, "run", path);
            if (variant != 0) run.addArgs(&.{ "--", "another-argument" });
            step.dependOn(&run.step);
        }
    }
    // Example mains may intentionally succeed without a device. Qualification
    // separately requires specific authored GPU tests to pass, not merely a
    // successful process or an empty filter with no skipped tests.
    const library_tests = hardwareTests(b, compiler, runtime, "std", "gpu.", &.{
        "gpu.completed map preserves GPU subnormals and refuses unsupported ordinary bodies",
        "gpu.matrix dimensions follow nested array lengths",
        "gpu.opening a device reports unavailable capability or owns a device",
        "gpu.upload preserves raw bits and checks zero dimensions before overflow",
    });
    step.dependOn(&library_tests.step);
    for ([_][]const u8{ "examples/gpu_readings.lin", "examples/gpu_matrix.lin", "examples/numerical_gpu.lin" }) |path| {
        const expected: []const []const u8 = if (std.mem.eql(u8, path, "examples/numerical_gpu.lin"))
            &.{ "GPU computation returns the expected values", "GPU empty fixed matrix products preserve every component bit" }
        else
            &.{"GPU computation returns the expected values"};
        const run = hardwareTests(b, compiler, runtime, path, "GPU", expected);
        step.dependOn(&run.step);
    }
    const benchmark = hardwareTests(b, compiler, runtime, "examples/benchmark_cpu_gpu", "GPU", &.{"GPU map matches every reference result bit"});
    step.dependOn(&benchmark.step);
    const pipeline = hardwareTests(b, compiler, runtime, "examples/tensor_pipeline.lin", "GPU", &.{"GPU pipeline matches the complete host algorithm"});
    step.dependOn(&pipeline.step);
    return step;
}

/// Build the same programs, including admitted device functions and embedded
/// images, without opening a device. The standard library's own tests cover
/// this driver path in the ordinary suite as well.
pub fn addCompile(b: *std.Build, compiler: std.Build.LazyPath, runtime: std.Build.LazyPath) *std.Build.Step {
    const step = b.step("test-gpu-compile", "Compile and embed Linea GPU programs without hardware");
    for (programs) |path| {
        const run = command(b, compiler, runtime, "build", path);
        run.addArg("-o");
        _ = run.addOutputFileArg(std.fs.path.stem(path));
        step.dependOn(&run.step);
    }
    return step;
}

fn hardwareTests(b: *std.Build, compiler: std.Build.LazyPath, runtime: std.Build.LazyPath, path: []const u8, filter: []const u8, expected: []const []const u8) *std.Build.Step.Run {
    if (expected.len == 0) @panic("GPU qualification requires named test outcomes");
    const run = command(b, compiler, runtime, "test", path);
    run.addArgs(&.{ "--deny-skips", "--filter", filter });
    run.expectExitCode(0);
    for (expected) |name| run.expectStdOutMatch(b.fmt("ok    {s}\n", .{name}));
    return run;
}

fn command(b: *std.Build, compiler: std.Build.LazyPath, runtime: std.Build.LazyPath, verb: []const u8, path: []const u8) *std.Build.Step.Run {
    const run = b.addSystemCommand(&.{"env"});
    run.addPrefixedFileArg("LINEA_RUNTIME=", runtime);
    run.addFileArg(compiler);
    run.addArg(verb);
    run.addFileArg(b.path(path));
    run.has_side_effects = true;
    return run;
}
