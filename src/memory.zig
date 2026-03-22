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
    properties: vk.MemoryPropertyFlags,
) ?u32 {
    const mem_props = app.gpu.vki.getPhysicalDeviceMemoryProperties(
        app.gpu.physical_device,
    );

    for (0..mem_props.memory_type_count) |i| {
        if ((mem_type_bits & (@as(u32, 1) << @intCast(i)) != 0) and
            (mem_props.memory_types[i].property_flags.contains(properties)))
        {
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
        properties,
    ) orelse {
        std.log.err("Failed to find suitable memory type for buffer", .{});
        return error.NoSuitableMemoryType;
    };

    const memory_allocate_info = vk.MemoryAllocateInfo{
        .allocation_size = mem_requirements.size,
        .memory_type_index = suitable_memory_type,
    };

    return try app.gpu.vkd.allocateMemory(app.gpu.device, &memory_allocate_info, null);
}

pub fn mapMemory(
    app: *const App,
    device_memory: vk.DeviceMemory,
    offset: vk.DeviceSize,
    size: vk.DeviceSize,
) ![]u8 {
    const buffer_opaque = try app.gpu.vkd.mapMemory(
        app.gpu.device,
        device_memory,
        offset,
        size,
        .{},
    ) orelse {
        return error.MemoryMapFailed;
    };

    return @as([*]u8, @ptrCast(buffer_opaque))[0..size];
}

pub fn createBuffers(app: *App) !void {
    if (app.sm_buffers.items.len == 0) {
        app.log(.debug, "No buffers found, skipping...", .{});
        return;
    }

    for (app.sm_buffers.items) |sm_buf| {
        const buffer = try createBuffer(
            app,
            sm_buf.size(),
            .{ .storage_buffer_bit = true },
        );
        try app.buffers.append(app.allocator, buffer);
    }

    const mem_requirements = app.gpu.vkd.getBufferMemoryRequirements(app.gpu.device,
        // We can grab the first one as all of them
        // have the same create info
        app.buffers.items[0]);

    var total_buffers_size: usize = 0;
    for (app.sm_buffers.items) |sm_buf| {
        try app.buffers_offsets.append(app.allocator, total_buffers_size);
        var next_offset = std.mem.alignForward(
            usize,
            sm_buf.size(),
            mem_requirements.alignment,
        );
        next_offset = @max(next_offset, mem_requirements.size);
        total_buffers_size += next_offset;
    }

    app.buffers_memory = try createDeviceMemory(
        app,
        .{
            .size = total_buffers_size,
            .alignment = mem_requirements.alignment,
            .memory_type_bits = mem_requirements.memory_type_bits,
        },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
    );

    const mapped_memory = try mapMemory(
        app,
        app.buffers_memory,
        0,
        total_buffers_size,
    );

    for (
        app.sm_buffers.items,
        app.buffers.items,
        app.buffers_offsets.items,
    ) |sm_buf, buf, offset| {
        if (sm_buf.data != null) {
            const data = sm_buf.dataAsSlice(u8);
            @memcpy(mapped_memory[offset..(offset + data.len)], data);
        }

        try app.gpu.vkd.bindBufferMemory(app.gpu.device, buf, app.buffers_memory, offset);

        app.log(
            .debug,
            "Uploaded buffer [{}] (size: {d}) to GPU",
            .{ sm_buf.binding, sm_buf.size() },
        );
    }

    app.mapped_memory_buffers = mapped_memory;
}

pub fn createImages(app: *App) !void {
    if (app.sm_images_2d.items.len == 0) {
        app.log(.debug, "No images found, skipping...", .{});
        return;
    }

    for (app.sm_images_2d.items) |sm_img| {
        const img = sm_img;
        const img_info = img.info.image_2d;
        const image = try vkimg.createImage(
            app,
            img_info.width,
            img_info.height,
            img_info.format.toVulkan(),
            .optimal,
            .{ .transfer_dst_bit = true, .transfer_src_bit = true, .storage_bit = true },
        );

        try app.images.append(app.allocator, image);
    }

    // TODO: It's probably a good idea to split images into their own groups
    // as different formats may have defferent requirements
    // but for now it works ok I guess?
    const img_mem_requirements = app.gpu.vkd.getImageMemoryRequirements(
        app.gpu.device,
        app.images.items[0],
    );

    var total_buffers_device_size: usize = 0;
    for (app.sm_images_2d.items, app.images.items) |sm_img, image| {
        const mem_req = app.gpu.vkd.getImageMemoryRequirements(
            app.gpu.device,
            image,
        );

        try app.images_buffers_offsets_device.append(
            app.allocator,
            total_buffers_device_size,
        );
        var next_offset = std.mem.alignForward(usize, sm_img.size(), mem_req.alignment);
        next_offset = @max(next_offset, mem_req.size);
        total_buffers_device_size += next_offset;
    }

    app.images_memory_device = try createDeviceMemory(
        app,
        .{
            .size = total_buffers_device_size,
            .alignment = img_mem_requirements.alignment,
            .memory_type_bits = img_mem_requirements.memory_type_bits,
        },
        .{ .device_local_bit = true },
    );

    for (app.images.items, app.images_buffers_offsets_device.items) |image, offset| {
        try app.gpu.vkd.bindImageMemory(
            app.gpu.device,
            image,
            app.images_memory_device,
            offset,
        );
    }

    for (app.sm_images_2d.items) |sm_img| {
        const staging_buffer = try createBuffer(app, sm_img.size(), .{
            .transfer_src_bit = true,
            .transfer_dst_bit = true,
        });
        try app.images_buffers.append(app.allocator, staging_buffer);
    }

    const buf_mem_requirements = app.gpu.vkd.getBufferMemoryRequirements(
        app.gpu.device,
        app.images_buffers.items[0],
    );

    var total_buffers_host_size: usize = 0;
    for (app.sm_images_2d.items) |sm_img| {
        try app.images_buffers_offsets_host.append(
            app.allocator,
            total_buffers_host_size,
        );
        total_buffers_host_size += std.mem.alignForward(
            usize,
            sm_img.size(),
            buf_mem_requirements.alignment,
        );
    }
    total_buffers_host_size = @max(buf_mem_requirements.size, total_buffers_host_size);

    app.images_memory_host = try createDeviceMemory(
        app,
        .{
            .size = total_buffers_device_size,
            .alignment = buf_mem_requirements.alignment,
            .memory_type_bits = buf_mem_requirements.memory_type_bits,
        },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
    );

    for (
        app.images_buffers.items,
        app.images_buffers_offsets_host.items,
    ) |img_buf, offset| {
        try app.gpu.vkd.bindBufferMemory(
            app.gpu.device,
            img_buf,
            app.images_memory_host,
            offset,
        );
    }

    const mapped_memory = try mapMemory(
        app,
        app.images_memory_host,
        0,
        total_buffers_host_size,
    );

    for (
        app.sm_images_2d.items,
        app.images.items,
        app.images_buffers.items,
        app.images_buffers_offsets_host.items,
    ) |sm_img, image, img_buf, offset| {
        const img_info = sm_img.info.image_2d;

        if (sm_img.data != null) {
            const data = sm_img.dataAsSlice(u8);
            @memcpy(mapped_memory[offset..(offset + data.len)], data);
        }

        try vkimg.transitionImageLayout(
            app,
            image,
            .undefined,
            .transfer_dst_optimal,
        );

        try vkimg.copyBufferToImage(
            app,
            img_buf,
            image,
            .transfer_dst_optimal,
            img_info.width,
            img_info.height,
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
            img_info.format.toVulkan(),
        );
        try app.images_views.append(app.allocator, image_view);
    }

    app.mapped_memory_images = mapped_memory;
}

pub fn readImage(app: *const App, img_index: usize) !void {
    const img = app.sm_images_2d.items[img_index];
    const img_info = img.info.image_2d;

    try vkimg.copyImageToBuffer(
        app,
        app.images_buffers.items[img_index],
        app.images.items[img_index],
        .general,
        img_info.width,
        img_info.height,
    );
}

pub fn writeImage(app: *const App, img_index: usize) !void {
    const img = app.sm_images_2d.items[img_index];
    const img_info = img.info.image_2d;

    try vkimg.copyBufferToImage(
        app,
        app.images_buffers.items[img_index],
        app.images.items[img_index],
        .general,
        img_info.width,
        img_info.height,
    );
}
