const std = @import("std");
const testing = std.testing;

/// A module's route as its root's own manifest spells it: `route` is how an
/// import in the program reaches the module, which for a library's module
/// starts with the library's name, `root_name`, and the library's manifest
/// writes what follows. The root module is the empty route; a program's root
/// has no name.
pub fn withinRoot(route: []const u8, root_name: []const u8) []const u8 {
    if (root_name.len == 0) return route;
    if (std.mem.eql(u8, route, root_name)) return "";
    if (route.len > root_name.len and std.mem.startsWith(u8, route, root_name) and route[root_name.len] == '.')
        return route[root_name.len + 1 ..];
    return route;
}

test withinRoot {
    try testing.expectEqualStrings("inner", withinRoot("c.inner", "c"));
    try testing.expectEqualStrings("", withinRoot("c", "c"));
    try testing.expectEqualStrings("io.core", withinRoot("std.io.core", "std"));
    try testing.expectEqualStrings("store", withinRoot("store", ""));
    // A name the route only begins with is not the root's.
    try testing.expectEqualStrings("cart.inner", withinRoot("cart.inner", "c"));
}
