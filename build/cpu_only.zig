//! Focused CPU-only execution and canonical unavailable-provider checks.
const std = @import("std");

pub fn add(b: *std.Build, compiler: std.Build.LazyPath, ordinary: std.Build.LazyPath, checked: std.Build.LazyPath, target: std.Build.ResolvedTarget, sanitizer: ?[]const u8, without_gpu: [2][]*std.Build.Step.Compile, rustls: std.Build.LazyPath, runtime_flags: []const []const u8) *std.Build.Step {
    const step = b.allocator.create(std.Build.Step) catch @panic("OOM");
    step.* = .init(.{ .id = .custom, .name = "CPU-only runtime and compiler execution", .owner = b });
    const fake_module = b.createModule(.{ .target = target, .optimize = .ReleaseSmall, .link_libc = true });
    fake_module.addCSourceFile(.{ .file = b.path("runtime/tests/cpu_only/fake_gpu.c"), .flags = runtime_flags });
    const fake_gpu = b.addObject(.{ .name = "gpu", .root_module = fake_module });
    for ([_]std.Build.LazyPath{ ordinary, checked }, 0..) |runtime, variant| {
        // Same runtime objects, but acquisition positively succeeds without a
        // Vulkan SDK/loader. A compiler-disabled call must never reach it.
        const fake_runtime = b.addSystemCommand(&.{ b.graph.zig_exe, "ar", "qcsDL" });
        const fake_archive = fake_runtime.addOutputFileArg(b.fmt("liblinea_rt_fake_gpu{d}.a", .{variant}));
        for (without_gpu[variant]) |object| fake_runtime.addArtifactArg(object);
        fake_runtime.addArtifactArg(fake_gpu);
        fake_runtime.addFileArg(rustls);
        step.dependOn(&b.addInstallFile(fake_archive, b.fmt("test-fixtures/liblinea_rt_fake_gpu{d}.a", .{variant})).step);
        const fake_link = b.addSystemCommand(&.{ "cc", "-std=c99", "-Wall", "-Wextra", "-Werror", "-UNDEBUG" });
        if (sanitizer) |selected| fake_link.addArgs(&.{ b.fmt("-fsanitize={s}", .{selected}), "-fsanitize=undefined", "-fno-sanitize-recover=all", "-g" });
        if (target.result.os.tag == .macos)
            fake_link.addArg(b.fmt("-mmacosx-version-min={f}", .{target.result.os.version_range.semver.min}));
        fake_link.addFileArg(b.path("runtime/tests/cpu_only/fake_provider.c"));
        fake_link.addFileArg(fake_archive);
        if (target.result.os.tag == .linux) fake_link.addArgs(&.{ "-lpthread", "-ldl", "-lm" });
        fake_link.addArg("-o");
        const fake_executable = fake_link.addOutputFileArg(b.fmt("positive-gpu-provider-{d}", .{variant}));
        const positive = std.Build.Step.Run.create(b, "prove fake provider acquisition succeeds");
        positive.addFileArg(fake_executable);
        positive.expectExitCode(0);
        positive.expectStdOutEqual("fake GPU acquisition entered\n");
        step.dependOn(&positive.step);
        const mixed = b.addSystemCommand(&.{"env"});
        mixed.addPrefixedFileArg("LINEA_RUNTIME=", fake_archive);
        mixed.addFileArg(compiler);
        mixed.addArg("run");
        mixed.addFileArg(b.path("runtime/tests/cpu_only/capability_unavailable.lin"));
        mixed.has_side_effects = true;
        mixed.expectExitCode(0);
        mixed.expectStdOutEqual("");
        mixed.step.dependOn(&positive.step);
        step.dependOn(&mixed.step);
        const link = b.addSystemCommand(&.{ "cc", "-std=c99", "-Wall", "-Wextra", "-Werror", "-UNDEBUG" });
        if (sanitizer) |selected| link.addArgs(&.{ b.fmt("-fsanitize={s}", .{selected}), "-fsanitize=undefined", "-fno-sanitize-recover=all", "-g" });
        if (target.result.os.tag == .macos)
            link.addArg(b.fmt("-mmacosx-version-min={f}", .{target.result.os.version_range.semver.min}));
        link.addFileArg(b.path("runtime/tests/cpu_only/provider.c"));
        link.addFileInput(b.path("runtime/gpu.h"));
        link.addFileArg(runtime);
        if (target.result.os.tag == .linux) link.addArgs(&.{ "-lpthread", "-ldl", "-lm" });
        link.addArg("-o");
        const executable = link.addOutputFileArg(b.fmt("cpu-only-provider-{d}", .{variant}));
        const native = std.Build.Step.Run.create(b, "check unavailable GPU ABI");
        native.addFileArg(executable);
        native.expectExitCode(0);
        step.dependOn(&native.step);
        for ([_][]const u8{ "runtime/tests/cpu_only/public_gpu.lin", "tests/tensor/sequential.lin", "tests/tensor/shapes.lin", "tests/fibers_public/execution.lin", "tests/fibers_public/simulation_children.lin" }) |path| {
            const run = b.addSystemCommand(&.{"env"});
            run.addPrefixedFileArg("LINEA_RUNTIME=", runtime);
            run.addFileArg(compiler);
            run.addArg("run");
            run.addFileArg(b.path(path));
            run.has_side_effects = true;
            run.expectExitCode(0);
            step.dependOn(&run.step);
        }
    }
    return step;
}
