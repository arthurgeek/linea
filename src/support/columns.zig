const std = @import("std");

/// Copies each column once into storage sized to the existing rows. The caller
/// owns the result; later appends use the list's ordinary growth policy.
pub fn cloneExact(comptime T: type, gpa: std.mem.Allocator, source: std.MultiArrayList(T).Slice) std.mem.Allocator.Error!std.MultiArrayList(T) {
    var out: std.MultiArrayList(T) = .empty;
    if (source.len == 0) return out;
    try out.setCapacity(gpa, source.len);
    out.len = source.len;
    const target = out.slice();
    inline for (std.meta.fields(T)) |field| {
        if (@sizeOf(field.type) != 0) {
            const column = @field(std.MultiArrayList(T).Field, field.name);
            @memcpy(target.items(column), source.items(column));
        }
    }
    return out;
}
