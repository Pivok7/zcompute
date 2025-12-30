pub const SharedBuffer = struct {
    const Self = @This();

    data: ?*const anyopaque = null,
    elem_num: u32,
    elem_size: usize,
    binding: u32,

    pub fn size(self: *const Self) usize {
        return self.elem_num * self.elem_size;
    }

    /// Create shared buffer with undefined data.
    /// It doesn't allocate any memory.
    /// The length is purerly informational.
    pub fn newEmpty(T: type, len: u32, binding: u32) !Self {
        if (len == 0) return error.LengthTooShort;
        if (@sizeOf(T) == 0) return error.ZeroSizeType;

        return .{
            .elem_num = len,
            .elem_size = @sizeOf(T),
            .binding = binding,
        };
    }

    /// Create shared buffer with provided slice.
    /// SharedBuffer doesn't own this data so the caller is
    /// responsible for managing the memory.
    pub fn newSlice(slice: anytype, binding: u32) !Self {
        if (slice.len == 0) return error.NotSlice;

        const child_type = @typeInfo(@TypeOf(slice)).pointer.child;
        if (@sizeOf(child_type) == 0) return error.ZeroSizeType;

        return .{
            .data = slice.ptr,
            .elem_num = @intCast(slice.len),
            .elem_size = @sizeOf(child_type),
            .binding = binding,
        };
    }
};
