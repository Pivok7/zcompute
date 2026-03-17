const std = @import("std");
const vk = @import("vulkan");
const core = @import("core.zig");
const vkimg = @import("image.zig");

const App = core.VulkanApp;

fn createBuffer(app: *const App, size: usize, usage: vk.BufferUsageFlags) !vk.Buffer {
    const buffer_create_info = vk.BufferCreateInfo{
        .size = size,
        .usage = usage,
        .sharing_mode = .exclusive,
        .queue_family_index_count = 1,
        .p_queue_family_indices = @ptrCast(&app.gpu.compute_queue_index),
    };

    return try app.gpu.vkd.createBuffer(app.gpu.device, &buffer_create_info, null);
}

fn findMemoryType(
    app: *const App,
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

pub fn createDeviceMemory(
    app: *const App,
    mem_requirements: vk.MemoryRequirements,
    properties: vk.MemoryPropertyFlags,
) !vk.DeviceMemory {
    const suitable_memory_type = findMemoryType(
        app,
        mem_requirements.memory_type_bits,
        properties
    ) orelse {
        std.log.err("Failed to find suitable memory type for buffer", .{});
        return error.NoSuitableMemoryType;
    };

    const memory_allocate_info = vk.MemoryAllocateInfo{
        .allocation_size = mem_requirements.size,
        .memory_type_index = suitable_memory_type,
    };

    return try app.gpu.vkd.allocateMemory(
        app.gpu.device,
        &memory_allocate_info,
        null
    );
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
    if (app.shrd_mem_buffers.items.len == 0) {
        app.log(.debug, "No buffers found, skipping...", .{});
        return;
    }

    for (app.shrd_mem_buffers.items) |shrm_mem| {
        const buffer = try createBuffer(app, shrm_mem.size(), .{ .storage_buffer_bit = true });
        try app.buffers.append(app.allocator, buffer);
    }

    const mem_requirements = app.gpu.vkd.getBufferMemoryRequirements(
        app.gpu.device,
        // We can grab the first one as all of them
        // have the same create info
        app.buffers.items[0]
    );
    const mem_alignment = mem_requirements.alignment;

    var total_buffers_size: usize = 0;
    for (app.shrd_mem_buffers.items) |shrd_mem| {
        try app.buffers_offsets.append(app.allocator, total_buffers_size);
        total_buffers_size += std.mem.alignForward(usize, shrd_mem.size(), mem_alignment);
    }

    app.buffers_memory = try createDeviceMemory(
        app,
        .{
            .size = total_buffers_size,
            .alignment = mem_alignment,
            .memory_type_bits = mem_requirements.memory_type_bits
        },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
    );

    for (app.shrd_mem_buffers.items, app.buffers.items, app.buffers_offsets.items)
        |shrd_mem, buf, offset| {
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

        app.log(
            .debug,
            "Uploaded buffer [{}] (size: {d}) to GPU",
            .{ shrd_mem.binding, shrd_mem.size() }
        );
    }
}


pub fn createImages(app: *App) !void {
    if (app.shrd_mem_images.items.len == 0) {
        app.log(.debug, "No images found, skipping...", .{});
        return;
    }

    var image: vk.Image = .null_handle;
    var image_memory: vk.DeviceMemory = .null_handle;

    const img = app.shrd_mem_images.items[0];
    const img_info = img.info.image_2d;
    try vkimg.createImage(
        app,
        img_info.width,
        img_info.height,
        .r32g32b32a32_sfloat,
        .optimal,
        .{ .transfer_dst_bit = true, .transfer_src_bit = true, .storage_bit = true },
        .{ .device_local_bit = true },
        &image,
        &image_memory,
    );


    const staging_buffer = try createBuffer(app, img.size(), .{
        .transfer_src_bit = true,
        .transfer_dst_bit = true,
    });
    const mem_requirements = app.gpu.vkd.getBufferMemoryRequirements(
        app.gpu.device,
        staging_buffer
    );
    const staging_buffer_memory = try createDeviceMemory(
        app,
        mem_requirements,
        .{ .host_visible_bit = true, .host_coherent_bit = true },
    );

    defer {
        app.gpu.vkd.destroyBuffer(app.gpu.device, staging_buffer, null);
        app.gpu.vkd.freeMemory(app.gpu.device, staging_buffer_memory, null);
    }

    {
        const mapped_memory = try mapMemory(
            app,
            staging_buffer_memory,
            0,
            img.size(),
        );
        @memset(mapped_memory, 100);
        app.gpu.vkd.unmapMemory(app.gpu.device, staging_buffer_memory);
    }

    try app.gpu.vkd.bindBufferMemory(
        app.gpu.device,
        staging_buffer,
        staging_buffer_memory,
        0
    );

    try app.images.append(app.allocator, image);
    app.images_memory = image_memory;

    try vkimg.transitionImageLayout(
        app,
        image,
        .undefined,
        .transfer_dst_optimal,
    );

    try vkimg.copyBufferToImage(
        app,
        staging_buffer,
        image,
        img_info.width,
        img_info.height
    );

    try vkimg.transitionImageLayout(
        app,
        image,
        .transfer_dst_optimal,
        .general,
    );

    const image_view = try vkimg.createImageView(
        app,
        image,
        .r32g32b32a32_sfloat
    );
    try app.images_views.append(app.allocator, image_view);

    try vkimg.copyImageToBuffer(
        app,
        staging_buffer,
        image,
        img_info.width,
        img_info.height
    );

    {
        const mapped_memory2 = try mapMemory(
            app,
            staging_buffer_memory,
            0,
            img.size(),
        );
        std.debug.print("{any}\n", .{mapped_memory2});
    }
}

pub fn dbgReadImage(app: *const App) !void {
    const img = app.shrd_mem_images.items[0];
    const img_info = img.info.image_2d;

    const staging_buffer = try createBuffer(app, img.size(), .{
        .transfer_src_bit = true,
        .transfer_dst_bit = true,
    });
    const mem_requirements = app.gpu.vkd.getBufferMemoryRequirements(
        app.gpu.device,
        staging_buffer
    );
    const staging_buffer_memory = try createDeviceMemory(
        app,
        mem_requirements,
        .{ .host_visible_bit = true, .host_coherent_bit = true },
    );

    defer {
        app.gpu.vkd.destroyBuffer(app.gpu.device, staging_buffer, null);
        app.gpu.vkd.freeMemory(app.gpu.device, staging_buffer_memory, null);
    }

    try app.gpu.vkd.bindBufferMemory(
        app.gpu.device,
        staging_buffer,
        staging_buffer_memory,
        0
    );

    try vkimg.copyImageToBuffer(
        app,
        staging_buffer,
        app.images.items[0],
        img_info.width,
        img_info.height
    );

    {
        const mapped_memory2 = try mapMemory(
            app,
            staging_buffer_memory,
            0,
            img.size(),
        );
        std.debug.print("{any}\n", .{mapped_memory2});
    }
}
