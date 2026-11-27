//! Build device images separately from pure emission, retaining failing inputs
//! and transferring validated image ownership to the host emitter's caller.
const std = @import("std");
const backend = @import("../backend/gpu.zig");
const mir = @import("../mir/mir.zig");
const Sink = @import("../diagnostics/sink.zig").Sink;
const toolchain = @import("toolchain.zig");

pub const Result = union(enum) {
    images: []backend.Image,
    failure: toolchain.Failure,
    defect: void,
};

const Intermediates = struct {
    source: []const u8,
    checked: []const u8,
    image: []const u8,

    fn init(gpa: std.mem.Allocator, prefix: []const u8, function: mir.FunctionId) !Intermediates {
        const source = try std.fmt.allocPrint(gpa, "{s}.gpu-{d}.mlir", .{ prefix, function.index() });
        errdefer gpa.free(source);
        const checked = try std.fmt.allocPrint(gpa, "{s}.gpu-{d}.checked.mlir", .{ prefix, function.index() });
        errdefer gpa.free(checked);
        const image = try std.fmt.allocPrint(gpa, "{s}.gpu-{d}.spv", .{ prefix, function.index() });
        return .{ .source = source, .checked = checked, .image = image };
    }

    fn deinit(self: Intermediates, gpa: std.mem.Allocator) void {
        gpa.free(self.source);
        gpa.free(self.checked);
        gpa.free(self.image);
    }

    fn remove(self: Intermediates, io: std.Io) void {
        for ([_][]const u8{ self.source, self.checked, self.image }) |path|
            std.Io.Dir.cwd().deleteFile(io, path) catch {};
    }
};

/// Frees the image bytes and their containing array. A tool failure instead
/// transfers its output buffer to the caller, just as toolchain.build does.
pub fn deinitImages(gpa: std.mem.Allocator, images: []backend.Image) void {
    for (images) |image| gpa.free(image.bytes);
    gpa.free(images);
}

/// Removes the inputs belonging to these images after the complete host
/// artifact succeeds. Callers retaining inputs during preparation can defer
/// this until host lowering and linking have succeeded as well.
pub fn removeInputs(
    gpa: std.mem.Allocator,
    io: std.Io,
    prefix: []const u8,
    images: []const backend.Image,
) void {
    for (images) |image| {
        const path = Intermediates.init(gpa, prefix, image.function) catch continue;
        defer path.deinit(gpa);
        path.remove(io);
    }
}

/// MIR verification and candidate admission belong to the backend. The driver
/// only writes the returned sources and invokes the shared toolchain. With no
/// admitted candidates this returns an empty owned slice and starts no tool.
pub fn prepare(
    gpa: std.mem.Allocator,
    io: std.Io,
    module: *const mir.Module,
    sink: *Sink,
    prefix: []const u8,
    keep: bool,
) !Result {
    if (!@import("build_options").gpu) return .{ .images = try gpa.alloc(backend.Image, 0) };
    const sources = (try backend.emitAll(gpa, module, sink)) orelse return .defect;
    defer {
        for (sources) |source| gpa.free(source.mlir);
        gpa.free(sources);
    }

    const images = try gpa.alloc(backend.Image, sources.len);
    var image_count: usize = 0;
    var succeeded = false;
    defer if (!succeeded) {
        for (images[0..image_count]) |image| gpa.free(image.bytes);
        gpa.free(images);
    };

    const paths = try gpa.alloc(Intermediates, sources.len);
    defer gpa.free(paths);
    var path_count: usize = 0;
    defer for (paths[0..path_count]) |path| {
        // Retain every source and image from an unsuccessful preparation,
        // including kernels built before the one that failed.
        if (succeeded and !keep) path.remove(io);
        path.deinit(gpa);
    };

    for (sources, 0..) |source, i| {
        paths[i] = try Intermediates.init(gpa, prefix, source.function);
        path_count += 1;
        const path = paths[i];
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path.source, .data = source.mlir });
        const failure = switch (source.format) {
            .spirv => try toolchain.gpuImage(gpa, io, path.source, path.checked, path.image),
            .staging => try toolchain.gpuStructuredImage(gpa, io, path.source, path.checked, path.image),
        };
        if (failure) |refusal| return .{ .failure = refusal };
        const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path.image, gpa, .unlimited);
        images[i] = .{ .function = source.function, .bytes = bytes, .kind = source.kind };
        image_count += 1;
    }
    succeeded = true;
    return .{ .images = images };
}
