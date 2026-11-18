const std = @import("std");
extern fn object_task_entry() u8;

test "a separately compiled Linea object stays pinned with a migration-capable runtime" {
    const ir = @embedFile("object_ir");
    try std.testing.expect(std.mem.indexOf(u8, ir, "@linea_task_start(") != null);
    try std.testing.expect(std.mem.indexOf(u8, ir, "linea_task_start_migratable") == null);
    try std.testing.expectEqual(@as(u8, 0), object_task_entry());
}
