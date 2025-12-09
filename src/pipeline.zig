const std = @import("std");
const vk = @import("vulkan");
const core = @import("core.zig");

const App = core.VulkanApp;
const VkAssert = core.VkAssert;

pub fn createDescriptorSetLayout(app: *const App) !vk.DescriptorSetLayout {
    var layout_bindings = std.ArrayList(vk.DescriptorSetLayoutBinding){};
    defer layout_bindings.deinit(app.allocator);

    for (0..app.shared_memories.len) |i| {
        try layout_bindings.append(app.allocator, .{
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

    return try app.gpu.vkd.createDescriptorSetLayout(
        app.gpu.device,
        &create_info,
        null
    );
}

pub fn createPipelineLayout(app: *const App) !vk.PipelineLayout {
    const create_info = vk.PipelineLayoutCreateInfo{
        .set_layout_count = 1,
        .p_set_layouts = @ptrCast(&app.descriptor_set_layout),
    };

    return app.gpu.vkd.createPipelineLayout(app.gpu.device, &create_info, null);
}

pub fn createPipelineCache(app: *const App) !vk.PipelineCache {
    const create_info = vk.PipelineCacheCreateInfo{};

    return app.gpu.vkd.createPipelineCache(app.gpu.device, &create_info, null);
}

pub fn CreatePipeline(app: *const App) !vk.Pipeline {
    const shader_create_info = vk.PipelineShaderStageCreateInfo{
        .stage = .{ .compute_bit = true },
        .module = app.shader_module,
        .p_name = "main",
    };

    const pipeline_create_info = vk.ComputePipelineCreateInfo{
        .stage = shader_create_info,
        .layout = app.pipeline_layout,
        .base_pipeline_index = 0,
    };

    var pipeline: vk.Pipeline = .null_handle;

    const result = try app.gpu.vkd.createComputePipelines(
        app.gpu.device,
        app.pipeline_cache,
        1,
        @ptrCast(&pipeline_create_info),
        null,
        @ptrCast(&pipeline),
    );

    try VkAssert.withMessage(result, "Compute pipeline creation failed");

    return pipeline;
}

pub fn createDescriptorPool(app: *const App) !vk.DescriptorPool {
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

    return app.gpu.vkd.createDescriptorPool(app.gpu.device, &create_info, null);
}

pub fn createDescriptorSet(app: *const App) !vk.DescriptorSet {
    const allocate_info = vk.DescriptorSetAllocateInfo{
        .descriptor_pool = app.descriptor_pool,
        .descriptor_set_count = 1,
        .p_set_layouts = @ptrCast(&app.descriptor_set_layout),
    };

    const descriptor_sets = try app.allocator.alloc(vk.DescriptorSet, 1);
    defer app.allocator.free(descriptor_sets);

    try app.gpu.vkd.allocateDescriptorSets(
        app.gpu.device,
        &allocate_info,
        @ptrCast(descriptor_sets.ptr)
    );

    const descriptor_set = descriptor_sets[0];

    var buffer_infos = std.ArrayList(vk.DescriptorBufferInfo){};
    defer buffer_infos.deinit(app.allocator);

    for (app.device_buffers.items, app.shared_memories) |buffer, memory| {
        try buffer_infos.append(app.allocator, .{
            .buffer = buffer,
            .offset = 0,
            .range = memory.size(),
        });
    }

    var write_descriptor_sets = std.ArrayList(vk.WriteDescriptorSet){};
    defer write_descriptor_sets.deinit(app.allocator);

    for (buffer_infos.items, 0..) |*buffer_info, i| {
        try write_descriptor_sets.append(app.allocator, .{
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

    app.gpu.vkd.updateDescriptorSets(
        app.gpu.device,
        @intCast(write_descriptor_sets.items.len),
        @ptrCast(write_descriptor_sets.items.ptr),
        0,
        null
    );

    return descriptor_set;
}
