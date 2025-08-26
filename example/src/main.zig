const std = @import("std");
const zcomp = @import("zcompute");
const SharedMemory = zcomp.SharedMemory;

pub fn main() !void {
    var dba = std.heap.DebugAllocator(.{}){};
    defer _ = dba.deinit();
    const allocator = dba.allocator();

    const data = &[_]SharedMemory{
        try SharedMemory.newSlice(&[_]u32{0, 1, 2, 3, 4, 5, 6, 7, 8, 9}),
        try SharedMemory.newSlice(&[_]f32{0, 1.1, 2, 3, 4, 5, 6, 7.7, 8, 9}),
        try SharedMemory.newEmpty(i32, 10),
    };
    const dispatch = zcomp.Dispatch{ .x = 10, .y = 1, .z = 1 };

    var app = try zcomp.App.init(
        allocator,
        .{},
        "src/shader.spv",
        data,
        dispatch,
    );
    defer app.deinit();

    try app.run();

    std.debug.print("Output:\n", .{});

    const one = try app.getDataAlloc(allocator, 0, u32);
    defer allocator.free(one);

    const two = try app.getDataAlloc(allocator, 1, f32);
    defer allocator.free(two);

    const three = try app.getDataAlloc(allocator, 2, i32);
    defer allocator.free(three);

    std.debug.print("{any}\n", .{one});
    std.debug.print("{any}\n", .{two});
    std.debug.print("{any}\n", .{three});
}
