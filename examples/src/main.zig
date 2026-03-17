const std = @import("std");
const zcomp = @import("zcompute");
const SharedMemory = zcomp.SharedMemory;

pub fn editFunc(data: []u8, shrd_mem: *const SharedMemory) void {
    // Add 5 to last element
    const buffer_slice = @as([]u32, @ptrCast(@alignCast(data)));
    buffer_slice[shrd_mem.elem_num() - 1] += 5;
}

pub fn main() !void {
    var dba = std.heap.DebugAllocator(.{}){};
    defer _ = dba.deinit();
    const allocator = dba.allocator();

    // First initialize the GPU
    var gpu = try zcomp.GPU.init(
        allocator,
        .{
            .enable_validation_layers = true,
            .debug_mode = false,
            .features = .{ .float64 = true },
            .vulkan_api_version = .{
                .major = 1,
                .minor = 4,
                .patch = 0,
            },
        },
    );
    defer gpu.deinit();

    // Create memory that will get sent from CPU to GPU
    const sm0 = try SharedMemory.Buffer.newSlice(
        u32, &.{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 }
    );
    const sm1 = try SharedMemory.Buffer.newSlice(
        f32, &.{ 0, 0.9, 2, 3.3, 4, 5, 6, 7.5, 8, 9 },
    );
    const sm2 = try SharedMemory.Buffer.newSlice(
        f64, &.{ 2.0, 4.0, 5.0, 7.7, 8.0, 10.0, 16.0, 32.0, 64.0, 100.0 },
    );
    const sm3 = try SharedMemory.Image2d.newEmpty(10, 1, .r32g32b32a32_sfloat);

    // Create an application
    var app = try zcomp.App.init(
        allocator,
        &gpu,
        .{ .debug_mode = true },
    );
    defer app.deinit();

    // Bind previously created memory
    try app.bindMemory(&sm0, 0);
    try app.bindMemory(&sm1, 1);
    try app.bindMemory(&sm2, 2);
    try app.bindMemory(&sm3, 3);

    // Load shader
    try app.loadShader(
        "src/shader.spv",
        .{ .x = 10, .y = 1, .z = 1 },
    );

    // Build the compute pipeline
    try app.submit();

    // Example of editing the memory
    // Editing takes place in a function called editFunc
    try app.editData(0, editFunc);

    // Run the application
    // Can be called many times
    try app.run();

    // Collect the output
    const one = try app.getDataAlloc(allocator, 0, u32);
    defer allocator.free(one);

    const two = try app.getDataAlloc(allocator, 1, f32);
    defer allocator.free(two);

    const three = try app.getDataAlloc(allocator, 2, f64);
    defer allocator.free(three);

    std.debug.print("Output:\n", .{});
    std.debug.print("{any}\n", .{one});
    std.debug.print("{any}\n", .{two});
    std.debug.print("{any}\n", .{three});
}
