const std = @import("std");
const builtin = @import("builtin");
const zcomp = @import("zcomp.zig");
const SharedMemory = zcomp.SharedMemory;

pub const debug_mode = switch (builtin.mode) {
    .Debug => true,
    else => false,
};

pub fn main() !void {
    var dba = std.heap.DebugAllocator(.{}){};
    defer _ = dba.deinit();
    const allocator = dba.allocator();

    const data = &[_]SharedMemory{
        try SharedMemory.newSlice(&[_]u32{0, 1, 2, 3, 4, 5, 6, 7, 8, 9}),
        try SharedMemory.newSlice(&[_]u32{0, 1, 2, 3, 4, 5, 6, 7, 8, 9}),
    };
    const dispatch = zcomp.Dispatch{ .x = 10, .y = 1, .z = 1 };

    var app = try zcomp.App.init(
        allocator,
        .{
            .debug_mode = true,
            .enable_validation_layers = debug_mode,
        },
        "src/shaders/square.spv",
        data,
        dispatch,
    );
    defer app.deinit();

    try app.run();

    std.debug.print("---------->\n", .{});

    const one = try app.getDataAlloc(allocator, 0, u32);
    defer allocator.free(one);

    const two = try app.getDataAlloc(allocator, 1, u32);
    defer allocator.free(two);

    std.debug.print("{d}\n", .{one});
    std.debug.print("{d}\n", .{two});

    std.debug.print("---------->\n", .{});
}
