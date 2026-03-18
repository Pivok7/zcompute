const std = @import("std");
const vk = @import("vulkan");

const Self = @This();

data: ?*const anyopaque = null,
binding: u32 = 0,
info: union(enum) {
    buffer: Buffer,
    image_2d: Image2d,
},

pub fn size(self: *const Self) usize {
    return switch (self.info) {
        .buffer => |*buffer| buffer.size(),
        .image_2d => |*image_2d| image_2d.size(),
    };
}

pub fn elem_num(self: *const Self) usize {
    return switch (self.info) {
        .buffer => |*buffer| buffer.elem_num,
        .image_2d => |*image_2d| image_2d.width * image_2d.height,
    };
}

pub fn elem_size(self: *const Self) usize {
    return switch (self.info) {
        .buffer => |*buffer| buffer.elem_size,
        .image_2d => |*image_2d| image_2d.pixelSize(),
    };
}

pub fn dataAsSlice(self: *const Self, T: type) []const T {
    return @as([*]const T, @alignCast(@ptrCast(self.data)))[0..self.size()];
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
    pub fn newEmpty(T: type, len: u32) !Self {
        if (len == 0) return error.LengthTooShort;
        if (@sizeOf(T) == 0) return error.ZeroSizeType;

        return .{
            .data = null,
            .info = .{ .buffer = .{
                .elem_num = len,
                .elem_size = @sizeOf(T),
            } },
        };
    }

    /// Create Buffer with provided slice.
    /// SharedBuffer doesn't own this data so the caller is
    /// responsible for managing the memory.
    pub fn newSlice(T: type, slice: []const T) !Self {
        if (slice.len == 0) return error.EmptySlice;

        const child_type = @typeInfo(@TypeOf(slice)).pointer.child;
        if (@sizeOf(child_type) == 0) return error.ZeroSizeType;

        return .{
            .data = @ptrCast(slice.ptr),
            .info = .{ .buffer = .{
                .elem_num = @intCast(slice.len),
                .elem_size = @sizeOf(child_type),
            } },
        };
    }
};

pub const Image2d = struct {
    pub const Format = enum {
        r32g32b32a32_sfloat,
        //r8g8b8a8_uint,
    };

    width: u32,
    height: u32,
    format: Format,

    pub fn size(self: *const @This()) usize {
        const pixel_size = self.pixelSize();
        return self.width * self.height * pixel_size;
    }

    pub fn pixelSize(self: *const @This()) usize {
        return switch (self.format) {
            .r32g32b32a32_sfloat => @sizeOf(f32) * 4,
            //.r8g8b8a8_uint => @sizeOf(u8) * 4,
        };
    }

    pub fn toVulkanFormat(self: *const @This()) vk.Format {
        return switch (self.format) {
            .r32g32b32a32_sfloat => .r32g32b32a32_sfloat,
            //.r8g8b8a8_uint => .r8g8b8a8_uint,
        };
    }

    /// Create Image2d with undefined data.
    /// It doesn't allocate any memory.
    pub fn newEmpty(width: u32, height: u32, format: Format) !Self {
        if (width == 0) return error.WidthTooShort;
        if (height == 0) return error.HeightTooShort;

        return .{
            .data = null,
            .info = .{ .image_2d = .{
                .width = width,
                .height = height,
                .format = format,
            } },
        };
    }
};
