//! Shared MLIR byte-string escaping for host and device symbols and constants.
const std = @import("std");

pub fn writeString(w: *std.Io.Writer, bytes: []const u8) std.Io.Writer.Error!void {
    for (bytes) |b| {
        if (b == '"' or b == '\\' or b < 0x20 or b > 0x7e) {
            try w.print("\\{X:0>2}", .{b});
        } else {
            try w.writeByte(b);
        }
    }
}
