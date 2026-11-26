const std = @import("std");

const Shader = struct { bytes: std.Build.LazyPath, validation: *std.Build.Step };

fn shader(b: *std.Build, name: []const u8, input: std.Build.LazyPath) Shader {
    const opt = b.addSystemCommand(&.{ "mlir-opt", "--no-implicit-module" });
    opt.addFileArg(input);
    opt.addArg("-o");
    const checked = opt.addOutputFileArg(b.fmt("{s}.checked.mlir", .{name}));
    const translate = b.addSystemCommand(&.{ "mlir-translate", "--no-implicit-module", "--serialize-spirv" });
    translate.addFileArg(checked);
    translate.addArg("-o");
    const bytes = translate.addOutputFileArg(b.fmt("{s}.spv", .{name}));
    const validate = b.addSystemCommand(&.{ "spirv-val", "--target-env", "vulkan1.1" });
    validate.addFileArg(bytes);
    return .{ .bytes = bytes, .validation = &validate.step };
}

fn floatShader(b: *std.Build, mask: u3) Shader {
    const names = [_][]const u8{ "identity", "negate", "add", "subtract", "multiply", "divide" };
    const controls = [_][]const u8{ "DenormPreserve", "SignedZeroInfNanPreserve", "RoundingModeRTE" };
    var capabilities: []const u8 = "";
    var modes: []const u8 = "";
    for (controls, 0..) |control, bit| {
        if (mask & (@as(u3, 1) << @intCast(bit)) == 0) continue;
        capabilities = b.fmt("{s}, {s}", .{ capabilities, control });
        for (names) |name|
            modes = b.fmt("{s}  spirv.ExecutionMode @{s} \"{s}\", 32\n", .{ modes, name, control });
    }
    var text: []const u8 = @embedFile("../runtime/tests/gpu/float.mlir");
    text = std.mem.replaceOwned(u8, b.allocator, text, "@CAPABILITIES@", capabilities) catch @panic("OOM");
    text = std.mem.replaceOwned(u8, b.allocator, text, "@EXTENSIONS@", if (mask == 0) "" else "SPV_KHR_float_controls") catch @panic("OOM");
    text = std.mem.replaceOwned(u8, b.allocator, text, "@MODES@", modes) catch @panic("OOM");
    const name = b.fmt("float-{d}", .{mask});
    const source = b.addWriteFiles().add(b.fmt("{s}.mlir", .{name}), text);
    return shader(b, name, source);
}

pub fn add(b: *std.Build) *std.Build.Step {
    const logic = b.step("test-gpu-probe", "Check GPU qualification policies without a GPU");
    const compile_logic = b.addSystemCommand(&.{ "cc", "-std=c17", "-Wall", "-Wextra", "-Werror", "-UNDEBUG", "-fno-fast-math", "-ffp-contract=off", "-frounding-math" });
    compile_logic.addFileArg(b.path("runtime/tests/gpu/logic_test.c"));
    compile_logic.addFileArg(b.path("runtime/tests/gpu/logic.c"));
    compile_logic.addFileArg(b.path("runtime/tests/gpu/float_reference_test.c"));
    if (@import("builtin").os.tag == .linux) compile_logic.addArg("-lm");
    for ([_][]const u8{ "probe.h", "float_cases.h" }) |file|
        compile_logic.addFileInput(b.path(b.fmt("runtime/tests/gpu/{s}", .{file})));
    compile_logic.addArg("-o");
    const logic_binary = compile_logic.addOutputFileArg("gpu-probe-logic");
    const run_logic = std.Build.Step.Run.create(b, "run GPU policy tests");
    run_logic.addFileArg(logic_binary);
    logic.dependOn(&run_logic.step);

    const hardware = b.step("gpu-probe", "Qualify the real Apple GPU through Vulkan/SPIR-V");
    const host_tests = b.step("test-gpu-host", "Check GPU host dispatch failures without a GPU");
    const headers = b.graph.environ_map.get("LINEA_VULKAN_HEADERS");
    const loader = b.graph.environ_map.get("LINEA_VULKAN_LOADER");
    if (headers == null or loader == null) {
        hardware.dependOn(&b.addFail("gpu-probe requires nix develop .#gpu").step);
        host_tests.dependOn(&b.addFail("test-gpu-host requires the headers from nix develop .#gpu").step);
        return logic;
    }
    const compile = b.addSystemCommand(&.{ "cc", "-std=c17", "-Wall", "-Wextra", "-Werror", "-O1", "-g" });
    compile.addArgs(&.{ "-isystem", b.pathJoin(&.{ headers.?, "include" }) });
    for ([_][]const u8{ "main.c", "device.c", "logic.c", "dispatch.c", "float.c" }) |file|
        compile.addFileArg(b.path(b.fmt("runtime/tests/gpu/{s}", .{file})));
    for ([_][]const u8{ "probe.h", "device.h", "float_cases.h" }) |file|
        compile.addFileInput(b.path(b.fmt("runtime/tests/gpu/{s}", .{file})));
    const lib = b.pathJoin(&.{ loader.?, "lib" });
    compile.addArgs(&.{ b.fmt("-L{s}", .{lib}), b.fmt("-Wl,-rpath,{s}", .{lib}), "-lvulkan", "-o" });
    const binary = compile.addOutputFileArg("gpu-probe");
    const run = std.Build.Step.Run.create(b, "run Apple GPU qualification");
    run.addFileArg(binary);
    const copy = shader(b, "copy", b.path("runtime/tests/gpu/copy.mlir"));
    run.addFileArg(copy.bytes);
    run.step.dependOn(copy.validation);
    const faults = b.addSystemCommand(&.{ "cc", "-std=c17", "-Wall", "-Wextra", "-Werror", "-UNDEBUG" });
    faults.addArgs(&.{ "-isystem", b.pathJoin(&.{ headers.?, "include" }) });
    for ([_][]const u8{ "dispatch_fault_test.c", "dispatch.c", "logic.c" }) |file|
        faults.addFileArg(b.path(b.fmt("runtime/tests/gpu/{s}", .{file})));
    for ([_][]const u8{ "probe.h", "device.h" }) |file|
        faults.addFileInput(b.path(b.fmt("runtime/tests/gpu/{s}", .{file})));
    faults.addArg("-o");
    const fault_binary = faults.addOutputFileArg("gpu-host-fault-tests");
    const run_faults = std.Build.Step.Run.create(b, "check GPU host failures");
    run_faults.addFileArg(fault_binary);
    run_faults.addFileArg(copy.bytes);
    run_faults.step.dependOn(copy.validation);
    host_tests.dependOn(&run_faults.step);
    const device_faults = b.addSystemCommand(&.{ "cc", "-std=c17", "-Wall", "-Wextra", "-Werror", "-UNDEBUG" });
    device_faults.addArgs(&.{ "-isystem", b.pathJoin(&.{ headers.?, "include" }) });
    for ([_][]const u8{ "device_fault_test.c", "device.c", "logic.c" }) |file|
        device_faults.addFileArg(b.path(b.fmt("runtime/tests/gpu/{s}", .{file})));
    for ([_][]const u8{ "probe.h", "device.h" }) |file|
        device_faults.addFileInput(b.path(b.fmt("runtime/tests/gpu/{s}", .{file})));
    device_faults.addArg("-o");
    const device_binary = device_faults.addOutputFileArg("gpu-device-fault-tests");
    const run_device = std.Build.Step.Run.create(b, "check GPU discovery failures");
    run_device.addFileArg(device_binary);
    host_tests.dependOn(&run_device.step);
    for (0..8) |mask| {
        const floats = floatShader(b, @intCast(mask));
        run.addFileArg(floats.bytes);
        run.step.dependOn(floats.validation);
    }
    hardware.dependOn(&run.step);
    return logic;
}
