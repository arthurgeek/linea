/// Execution requirements supplied by the owner of a native interface.
pub const Policy = struct {
    blocking: bool = false,
    thread_affine: bool = false,
};
