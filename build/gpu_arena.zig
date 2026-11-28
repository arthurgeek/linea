const std = @import("std");
const builtin = @import("builtin");

/// Include the actual runtime in a dedicated real-device harness so private
/// backing identities can be compared without a production observability API.
pub fn add(
    b: *std.Build,
    archive: std.Build.LazyPath,
    gpu_flags: []const []const u8,
    shader: std.Build.LazyPath,
) *std.Build.Step {
    const step = b.step("test-gpu-arena", "Verify real GPU arena commitments, reuse and settlement");
    const compile = b.addSystemCommand(&.{"cc"});
    compile.addArgs(gpu_flags);
    if (b.graph.host.result.os.tag == .macos)
        compile.addArg(b.fmt("-mmacosx-version-min={f}", .{b.graph.host.result.os.version_range.semver.min}));
    compile.addArg("-UNDEBUG");
    compile.addFileArg(b.path("runtime/tests/gpu_arena/main.c"));
    for ([_][]const u8{ "runtime/gpu.c", "runtime/gpu.h", "runtime/park.h", "runtime/fiber.h", "runtime/loop.h", "runtime/task.h" }) |path|
        compile.addFileInput(b.path(path));
    // The definitions included above satisfy GPU symbols, so the archive's
    // separate gpu.o is not extracted; the park/fiber implementation is reused.
    compile.addFileArg(archive);
    compile.addArgs(&.{ "-lpthread", "-lm" });
    if (builtin.os.tag == .linux) compile.addArg("-ldl");
    compile.addArg("-o");
    const binary = compile.addOutputFileArg("gpu-arena-hardware");
    const run = std.Build.Step.Run.create(b, "run real GPU arena reuse and settlement");
    run.addFileArg(binary);
    run.addFileArg(shader);
    run.has_side_effects = true;
    step.dependOn(&run.step);
    return step;
}
