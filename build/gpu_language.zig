const std = @import("std");

const programs = [_][]const u8{
    "runtime/tests/gpu_runtime/numerical_map.lin",
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

fn command(b: *std.Build, compiler: std.Build.LazyPath, runtime: std.Build.LazyPath, verb: []const u8, path: []const u8) *std.Build.Step.Run {
    const run = b.addSystemCommand(&.{"env"});
    run.addPrefixedFileArg("LINEA_RUNTIME=", runtime);
    run.addFileArg(compiler);
    run.addArg(verb);
    run.addFileArg(b.path(path));
    run.has_side_effects = true;
    return run;
}
