const std = @import("std");
const vk = @import("vulkan");
const core = @import("core.zig");

const VulkanApp = core.VulkanApp;

const Mems = struct {
    elem_num: u32,
    elem_size: usize,

    pub fn size(self: *const @This()) usize {
        return self.elem_num * self.elem_size;
    }
};

pub fn createBuffer(app: *VulkanApp) !void {
    for (app.shared_memories) |memory| {
        const buffer_create_info = vk.BufferCreateInfo{
            .size = memory.size(),
            .usage = .{ .storage_buffer_bit = true },
            .sharing_mode = .exclusive,
            .queue_family_index_count = 1,
            .p_queue_family_indices = @ptrCast(&app.compute_queue_index),
        };

        const buffer = try app.vkd.createBuffer(app.device, &buffer_create_info, null);
        try app.device_buffers.append(app.allocator, buffer);
    }

    var mem_requirements = std.ArrayList(vk.MemoryRequirements){};
    defer mem_requirements.deinit(app.allocator);

    for (app.device_buffers.items) |buffer| {
        try mem_requirements.append(
            app.allocator,
            app.vkd.getBufferMemoryRequirements(app.device, buffer)
        );
    }

    const mem_properties = app.vki.getPhysicalDeviceMemoryProperties(app.physical_device);

    var mem_type_index: u32 = std.math.maxInt(u32);
    var mem_heap_size: u64 = std.math.maxInt(u64);

    for (0..mem_properties.memory_type_count) |i| {
        const mem_type = mem_properties.memory_types[i];

        if (mem_type.property_flags.contains(.{
            .host_visible_bit = true,
            .host_coherent_bit = true,
        })) {
            mem_heap_size = mem_properties.memory_heaps[mem_type.heap_index].size;
            mem_type_index = @intCast(i);
        }
    }

    app.log(.debug, "Memory type index: {d}", .{mem_type_index});
    const mem_heap_size_MB = mem_heap_size / 1024 / 1024;

    if (mem_heap_size_MB < 4096) {
        app.log(.info, "Memory heap size: {d}MB", .{mem_heap_size_MB});
    } else {
        const mem_heap_size_GB = mem_heap_size_MB / 1024;
        app.log(.info, "Memory heap size: {d}GB", .{mem_heap_size_GB});
    }

    var alloc_infos = std.ArrayList(vk.MemoryAllocateInfo){};
    defer alloc_infos.deinit(app.allocator);

    for (mem_requirements.items) |mem_req| {
        try alloc_infos.append(app.allocator, .{
            .allocation_size = mem_req.size,
            .memory_type_index = mem_type_index,
        });
    }

    for (alloc_infos.items) |alloc_info| {
        const buffer_memory = try app.vkd.allocateMemory(app.device, &alloc_info, null);
        try app.device_memories.append(app.allocator, buffer_memory);
    }

    for (app.device_memories.items, app.shared_memories, 0..) |dev_mem, shdr_mem, i| {
        if (shdr_mem.data) |data| {
            const buffer_slice = @as([*]u8, @ptrCast(
                try app.vkd.mapMemory(app.device, dev_mem, 0, shdr_mem.size(), .{})
            ))[0..shdr_mem.size()];

            const data_slice = @as([*]const u8, @ptrCast(data))[0..shdr_mem.size()];

            @memcpy(buffer_slice, data_slice);

            app.vkd.unmapMemory(app.device, dev_mem);
        }
        app.log(.debug, "Uploaded data ({d}) to GPU", .{i});
    }

    for (app.device_buffers.items, app.device_memories.items) |dev_buf, dev_mem| {
        try app.vkd.bindBufferMemory(app.device, dev_buf, dev_mem, 0);
    }
}
