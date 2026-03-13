const std = @import("std");
const vk = @import("vulkan");
const core = @import("core.zig");

const App = core.VulkanApp;

fn createBuffer(app: *App, size: usize) !vk.Buffer {
    const buffer_create_info = vk.BufferCreateInfo{
        .size = size,
        .usage = .{ .storage_buffer_bit = true },
        .sharing_mode = .exclusive,
        .queue_family_index_count = 1,
        .p_queue_family_indices = @ptrCast(&app.gpu.compute_queue_index),
    };

    return try app.gpu.vkd.createBuffer(app.gpu.device, &buffer_create_info, null);
}

fn findMemoryType(
    app: *App,
    mem_type_bits: u32,
    properties: vk.MemoryPropertyFlags
) ?u32 {
    const mem_props = app.gpu.vki.getPhysicalDeviceMemoryProperties(app.gpu.physical_device);

    for (0..mem_props.memory_type_count) |i| {
        if (
            (mem_type_bits & (@as(u32, 1) << @intCast(i)) != 0) and
            (mem_props.memory_types[i].property_flags.contains(properties))
        ) {
            return @intCast(i);
        }
    }

    return null;
}

pub fn mapMemory(
    app: *const App,
    device_memory: vk.DeviceMemory,
    offset: vk.DeviceSize,
    size: vk.DeviceSize
) ![]u8 {
    const buffer_opaque = try app.gpu.vkd.mapMemory(
        app.gpu.device,
        device_memory,
        offset,
        size,
        .{},
    ) orelse {
        return error.MemoryMapFail;
    };

    return @as([*]u8, @ptrCast(buffer_opaque))[0..size];
}

pub fn createBuffers(app: *App) !void {
    for (app.shared_memories.items) |memory| {
        const buffer = try createBuffer(app, memory.size());
        try app.buffers.append(app.allocator, buffer);
    }

    const mem_requirements = app.gpu.vkd.getBufferMemoryRequirements(
        app.gpu.device,
        // We can grab the first one as all of them
        // have the same create info
        app.buffers.items[0]
    );
    const mem_alignment = mem_requirements.alignment;

    const mem_type_index = findMemoryType(
        app,
        mem_requirements.memory_type_bits,
        .{ .host_visible_bit = true, .host_coherent_bit = true },
    ) orelse {
        std.log.err("No suitable memory type index", .{});
        return error.NoSuitableMemoryTypeIndex;
    };

    var alloc_infos: std.ArrayList(vk.MemoryAllocateInfo) = .empty;
    defer alloc_infos.deinit(app.allocator);

    var total_buffers_size: usize = 0;
    for (app.shared_memories.items) |*shrd_mem| {
        try app.buffers_offsets.append(app.allocator, total_buffers_size);
        total_buffers_size += std.mem.alignForward(usize, shrd_mem.size(), mem_alignment);
    }

    const alloc_info = vk.MemoryAllocateInfo{
        .allocation_size = total_buffers_size,
        .memory_type_index = mem_type_index,
    };

    app.buffers_memory = try app.gpu.vkd.allocateMemory(
        app.gpu.device,
        &alloc_info,
        null
    );

    for (app.shared_memories.items, app.buffers.items, app.buffers_offsets.items)
        |*shrd_mem, buf, offset| {
        if (shrd_mem.data) |data| {
            const data_slice = @as([*]const u8, @ptrCast(data))[0..shrd_mem.size()];

            const mapped_memory = try mapMemory(
                app,
                app.buffers_memory,
                offset,
                shrd_mem.size()
            );
            @memcpy(mapped_memory, data_slice);
            app.gpu.vkd.unmapMemory(app.gpu.device, app.buffers_memory);
        }

        try app.gpu.vkd.bindBufferMemory(
            app.gpu.device,
            buf,
            app.buffers_memory,
            offset
        );

        app.log(.debug, "Uploaded data (size: {d}) to GPU", .{shrd_mem.size()});
    }
}
