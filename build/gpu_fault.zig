const std = @import("std");
const builtin = @import("builtin");

/// No device or Vulkan loader is needed: only headers and the actual runtime
/// archive. The C harness includes gpu.c and substitutes its loader boundary.
/// Call with the build's native runtime flags and attach this step to test.
pub fn add(
    b: *std.Build,
    archive: std.Build.LazyPath,
    headers: []const u8,
    runtime_flags: []const []const u8,
) *std.Build.Step {
    const step = b.step("test-gpu-runtime", "Check production GPU failures, lifetimes and single-carrier progress without hardware");
    const compile = b.addSystemCommand(&.{"cc"});
    compile.addArgs(runtime_flags);
    if (b.graph.host.result.os.tag == .macos)
        compile.addArg(b.fmt("-mmacosx-version-min={f}", .{b.graph.host.result.os.version_range.semver.min}));
    compile.addArgs(&.{ "-UNDEBUG", "-isystem", b.pathJoin(&.{ headers, "include" }) });
    compile.addFileArg(b.path("runtime/tests/gpu_fault/main.c"));
    for ([_][]const u8{
        "runtime/tests/gpu_fault/vulkan.inc",
        "runtime/gpu.c",
        "runtime/gpu.h",
        "runtime/park.h",
        "runtime/fiber.h",
        "runtime/loop.h",
        "runtime/task.h",
    }) |path| compile.addFileInput(b.path(path));
    compile.addFileArg(archive);
    compile.addArgs(&.{ "-lpthread", "-lm" });
    if (builtin.os.tag == .linux) compile.addArg("-ldl");
    compile.addArg("-o");
    const binary = compile.addOutputFileArg("gpu-runtime-faults");
    const run = std.Build.Step.Run.create(b, "run production GPU failure and carrier tests");
    run.addFileArg(binary);
    step.dependOn(&run.step);
    return step;
}
