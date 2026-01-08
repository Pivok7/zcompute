const std = @import("std");

const Self = @This();

data: ?*const anyopaque = null,
binding: u32,
info: union(enum) {
    buffer: Buffer,
    image_2d: void,
},

pub fn size(self: *const Self) usize {
    return switch (self.info) {
        .buffer => |buffer| buffer.size(),
        .image_2d => unreachable,
    };
}

pub fn elem_num(self: *const Self) usize {
    return switch (self.info) {
        .buffer => |buffer| buffer.elem_num,
        .image_2d => unreachable,
    };
}

pub fn elem_size(self: *const Self) usize {
    return switch (self.info) {
        .buffer => |buffer| buffer.elem_size,
        .image_2d => unreachable,
    };
}

pub const Buffer = struct {
    elem_size: usize,
    elem_num: u32,

    pub fn size(self: *const @This()) usize {
        return self.elem_num * self.elem_size;
    }

    /// Create buffer with undefined data.
    /// It doesn't allocate any memory.
    /// The length is purerly informational.
    pub fn newEmpty(T: type, len: u32, binding: u32) !Self {
        if (len == 0) return error.LengthTooShort;
        if (@sizeOf(T) == 0) return error.ZeroSizeType;

        return .{
            .data = null,
            .binding = binding,
            .info = .{ .buffer = .{
                .elem_num = len,
                .elem_size = @sizeOf(T),
            } },
        };
    }

    /// Create buffer with provided slice.
    /// SharedBuffer doesn't own this data so the caller is
    /// responsible for managing the memory.
    pub fn newSlice(slice: anytype, binding: u32) !Self {
        if (slice.len == 0) return error.NotSlice;

        const child_type = @typeInfo(@TypeOf(slice)).pointer.child;
        if (@sizeOf(child_type) == 0) return error.ZeroSizeType;

        return .{
            .data = @ptrCast(slice.ptr),
            .binding = binding,
            .info = .{ .buffer = .{
                .elem_num = @intCast(slice.len),
                .elem_size = @sizeOf(child_type),
            } },
        };
    }
};
