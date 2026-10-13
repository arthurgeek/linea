/// The checked scalar math boundary shared by typing, MIR and code emission.
pub const Operation = enum {
    sqrt,
    floor,
    ceil,
    trunc,
    round,
    pow,
    sin,
    cos,
    ln,
    exp,

    pub const count = @typeInfo(Operation).@"enum".fields.len;

    pub fn arity(self: Operation) u8 {
        return if (self == .pow) 2 else 1;
    }

    pub fn symbol(self: Operation) []const u8 {
        return switch (self) {
            inline else => |operation| "linea_math_" ++ @tagName(operation),
        };
    }
};
