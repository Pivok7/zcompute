const std = @import("std");
const vk = @import("vulkan");
const core = @import("core.zig");

const App = core.VulkanApp;
const VkAssert = core.VkAssert;

pub fn createCommandPool(app: *const App) !vk.CommandPool {
    const create_info = vk.CommandPoolCreateInfo{
        .queue_family_index = app.gpu.compute_queue_index,
    };

    return try app.gpu.vkd.createCommandPool(app.gpu.device, @ptrCast(&create_info), null);
}

pub fn createCommandBuffer(app: *const App) !vk.CommandBuffer {
    const allocate_info = vk.CommandBufferAllocateInfo{
        .command_pool = app.command_pool,
        .level = .primary,
        .command_buffer_count = 1,
    };

    const command_buffers = try app.allocator.alloc(vk.CommandBuffer, 1);
    defer app.allocator.free(command_buffers);

    try app.gpu.vkd.allocateCommandBuffers(app.gpu.device, @ptrCast(&allocate_info), @ptrCast(command_buffers.ptr));

    const command_buffer = command_buffers[0];

    const begin_info = vk.CommandBufferBeginInfo{};

    try app.gpu.vkd.beginCommandBuffer(command_buffer, &begin_info);
    app.gpu.vkd.cmdBindPipeline(command_buffer, .compute, app.compute_pipeline);
    app.gpu.vkd.cmdBindDescriptorSets(command_buffer, .compute, app.pipeline_layout, 0, 1, @ptrCast(&app.descriptor_set), 0, null);
    app.gpu.vkd.cmdDispatch(command_buffer, @intCast(app.dispatch.x), @intCast(app.dispatch.y), @intCast(app.dispatch.z));
    try app.gpu.vkd.endCommandBuffer(command_buffer);

    return command_buffer;
}

pub fn submitWork(app: *const App) !void {
    const queue = app.gpu.vkd.getDeviceQueue(app.gpu.device, app.gpu.compute_queue_index, 0);

    const fence_create_info = vk.FenceCreateInfo{};
    const fence = try app.gpu.vkd.createFence(app.gpu.device, @ptrCast(&fence_create_info), null);

    const submit_info = vk.SubmitInfo{
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast(&app.command_buffer),
    };

    try app.gpu.vkd.queueSubmit(queue, 1, @ptrCast(&submit_info), fence);
    const result = try app.gpu.vkd.waitForFences(
        app.gpu.device,
        1,
        @ptrCast(&fence),
        vk.TRUE,
        std.math.maxInt(u64),
    );

    try VkAssert.withMessage(result, "Waiting for fence failed");

    app.gpu.vkd.destroyFence(app.gpu.device, fence, null);
}
