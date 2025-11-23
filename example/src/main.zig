const std = @import("std");
const zcomp = @import("zcompute");
const SharedMemory = zcomp.SharedMemory;

pub fn main() !void {
    var dba = std.heap.DebugAllocator(.{}){};
    defer _ = dba.deinit();
    const allocator = dba.allocator();

    // Fist initialize the GPU
    var gpu = try zcomp.GPU.init(
        allocator,
        .{
            .enable_validation_layers = false,
            .debug_mode = false,
            .features = .{ .float64 = true },
        },
    );
    defer gpu.deinit();

    // Create memory that will be shared between CPU and GPU
    const data = &[_]SharedMemory{
        try SharedMemory.newSlice(&[_]u32{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 }),
        try SharedMemory.newSlice(&[_]f32{ 0, 0.9, 2, 3.3, 4, 5, 6, 7.5, 8, 9 }),
        try SharedMemory.newSlice(&[_]f64{ 2.0, 4.0, 5.0, 7.7, 8.0, 10.0, 16.0, 32.0, 64.0, 100.0 }),
        try SharedMemory.newEmpty(i32, 10),
    };
    const dispatch = zcomp.Dispatch{ .x = 10, .y = 1, .z = 1 };

    // Create an application
    var app = try zcomp.App.init(
        allocator,
        &gpu,
        "src/shader.spv",
        data,
        dispatch,
        .{ .debug_mode = false },
    );
    defer app.deinit();

    // Run the application
    for (0..1) |_| {
        try app.run();
    }

    // Collect output
    std.debug.print("Output:\n", .{});

    const one = try app.getDataAlloc(allocator, 0, u32);
    defer allocator.free(one);

    const two = try app.getDataAlloc(allocator, 1, f32);
    defer allocator.free(two);

    const three = try app.getDataAlloc(allocator, 2, f64);
    defer allocator.free(three);

    const four = try app.getDataAlloc(allocator, 3, i32);
    defer allocator.free(four);

    std.debug.print("{any}\n", .{one});
    std.debug.print("{any}\n", .{two});
    std.debug.print("{any}\n", .{three});
    std.debug.print("{any}\n", .{four});
}
