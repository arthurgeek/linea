//! Tracy's C client, declared directly.
//!
//! Five functions are the whole of what the runner needs -- open, annotate and
//! close a zone, and name a thread -- so a binding for them is more to keep
//! true than the declarations themselves. It was also the thing that broke: a
//! binding pins the client's version, and a client whose protocol does not match the
//! profiler refuses the connection. Declaring the interface here means the
//! version is whatever `build.zig` compiles, which is chosen to match the
//! profiler that is installed.
//!
//! Every function is a no-op unless `-Dtracy`, and the calls vanish rather than
//! being guarded at each site.

const std = @import("std");
const enabled = @import("build_options").tracy;

/// What Tracy is told about a zone's position in the source. Laid out to match
/// `___tracy_source_location_data`, and it must stay that way: the client reads
/// it by offset.
const SourceLocation = extern struct {
    name: ?[*:0]const u8,
    function: [*:0]const u8,
    file: [*:0]const u8,
    line: u32,
    color: u32,
};

const Context = extern struct { id: u32, active: c_int };

extern fn ___tracy_emit_zone_begin(srcloc: *const SourceLocation, active: c_int) Context;
extern fn ___tracy_emit_zone_end(ctx: Context) void;
extern fn ___tracy_emit_zone_text(ctx: Context, text: [*]const u8, len: usize) void;
extern fn ___tracy_emit_zone_value(ctx: Context, value: u64) void;
extern fn ___tracy_set_thread_name(name: [*:0]const u8) void;

pub const Zone = struct {
    ctx: if (enabled) Context else void,

    pub inline fn end(self: Zone) void {
        if (!enabled) return;
        ___tracy_emit_zone_end(self.ctx);
    }

    pub inline fn setText(self: Zone, text: []const u8) void {
        if (!enabled) return;
        ___tracy_emit_zone_text(self.ctx, text.ptr, text.len);
    }

    pub inline fn setValue(self: Zone, value: u64) void {
        if (!enabled) return;
        ___tracy_emit_zone_value(self.ctx, value);
    }
};

/// Opens a zone that lasts until `end`. The location is comptime, so the
/// literal Tracy reads lives in the binary rather than being built per call.
pub inline fn beginZone(comptime src: std.builtin.SourceLocation, comptime name: [:0]const u8) Zone {
    if (!enabled) return .{ .ctx = {} };
    const loc = struct {
        const data: SourceLocation = .{
            .name = name.ptr,
            .function = src.fn_name ++ "",
            .file = src.file ++ "",
            .line = src.line,
            .color = 0,
        };
    };
    return .{ .ctx = ___tracy_emit_zone_begin(&loc.data, 1) };
}

pub inline fn setThreadName(comptime name: [:0]const u8) void {
    if (!enabled) return;
    ___tracy_set_thread_name(name.ptr);
}
