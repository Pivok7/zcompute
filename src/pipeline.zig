const std = @import("std");
const vk = @import("vulkan");
const vk_ctx = @import("vk_context.zig");
const core = @import("core.zig");

const VkAssert = vk_ctx.VkAssert;
const VulkanApp = core.VulkanApp;

pub fn createDescriptorSetLayout(app: *const VulkanApp) !vk.DescriptorSetLayout {
    var layout_bindings = std.ArrayList(vk.DescriptorSetLayoutBinding).init(app.allocator);
    defer layout_bindings.deinit();

    for (0..app.shared_memories.len) |i| {
        try layout_bindings.append(.{
            .binding = @intCast(i),
            .descriptor_type = .storage_buffer,
            .descriptor_count = 1,
            .stage_flags = .{ .compute_bit = true },
        });
    }

    const create_info = vk.DescriptorSetLayoutCreateInfo{
        .binding_count = @intCast(layout_bindings.items.len),
        .p_bindings = @ptrCast(layout_bindings.items.ptr),
    };

    return try app.vkd.createDescriptorSetLayout(
        app.device,
        &create_info,
        null
    );
}

pub fn createPipelineLayout(app: *const VulkanApp) !vk.PipelineLayout {
    const create_info = vk.PipelineLayoutCreateInfo{
        .set_layout_count = 1,
        .p_set_layouts = @ptrCast(&app.descriptor_set_layout),
    };
    
    return app.vkd.createPipelineLayout(app.device, &create_info, null);
}

pub fn createPipelineCache(app: *const VulkanApp) !vk.PipelineCache {
    const create_info = vk.PipelineCacheCreateInfo{};
    
    return app.vkd.createPipelineCache(app.device, &create_info, null);
}

pub fn CreatePipeline(app: *const VulkanApp) !vk.Pipeline {
    const shared_create_info = vk.PipelineShaderStageCreateInfo{
        .stage = .{ .compute_bit = true },
        .module = app.shader_module,
        .p_name = "main",
    };

    const pipeline_create_info = vk.ComputePipelineCreateInfo{
        .stage = shared_create_info,
        .layout = app.pipeline_layout,
        .base_pipeline_index = 0,
    };

    var pipeline: vk.Pipeline = .null_handle;

    const result = try app.vkd.createComputePipelines(
        app.device,
        app.pipeline_cache,
        1,
        @ptrCast(&pipeline_create_info),
        null,
        @ptrCast(&pipeline),
    );

    try VkAssert.withMessage(result, "Compute pipeline creation failed");

    return pipeline;
}

pub fn createDescriptorPool(app: *const VulkanApp) !vk.DescriptorPool {
    const pool_sizes = [_]vk.DescriptorPoolSize{
        .{
            .type = .storage_buffer,
            .descriptor_count = @intCast(app.shared_memories.len),
        }
    };

    const create_info = vk.DescriptorPoolCreateInfo{
        .pool_size_count = pool_sizes.len,
        .p_pool_sizes = &pool_sizes,
        .max_sets = @intCast(app.shared_memories.len),
    };

    return app.vkd.createDescriptorPool(app.device, &create_info, null);
}

pub fn createDescriptorSet(app: *const VulkanApp) !vk.DescriptorSet {
    const allocate_info = vk.DescriptorSetAllocateInfo{
        .descriptor_pool = app.descriptor_pool,
        .descriptor_set_count = 1,
        .p_set_layouts = @ptrCast(&app.descriptor_set_layout),
    };

    const descriptor_sets = try app.allocator.alloc(vk.DescriptorSet, 1);
    defer app.allocator.free(descriptor_sets);

    try app.vkd.allocateDescriptorSets(
        app.device,
        &allocate_info,
        @ptrCast(descriptor_sets.ptr)
    );

    const descriptor_set = descriptor_sets[0];

    var buffer_infos = std.ArrayList(vk.DescriptorBufferInfo).init(app.allocator);
    defer buffer_infos.deinit();

    for (app.device_buffers.items, app.shared_memories) |buffer, memory| {
        try buffer_infos.append(.{
            .buffer = buffer,
            .offset = 0,
            .range = memory.size(),
        });
    }

    var write_descriptor_sets = std.ArrayList(vk.WriteDescriptorSet).init(app.allocator);
    defer write_descriptor_sets.deinit();

    for (buffer_infos.items, 0..) |*buffer_info, i| {
        try write_descriptor_sets.append(.{
            .dst_set = descriptor_set,
            .dst_binding = @intCast(i),
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = .storage_buffer,
            .p_image_info = undefined,
            .p_buffer_info = @ptrCast(buffer_info),
            .p_texel_buffer_view = undefined,
        });
    }

    app.vkd.updateDescriptorSets(
        app.device,
        @intCast(write_descriptor_sets.items.len),
        @ptrCast(write_descriptor_sets.items.ptr),
        0,
        null
    );

    return descriptor_set;
}
