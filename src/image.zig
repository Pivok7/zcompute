const std = @import("std");
const vk = @import("vulkan");
const core = @import("core.zig");
const memory = @import("memory.zig");
const command = @import("command.zig");

const App = core.VulkanApp;

pub fn createImage(
    app: *App,
    width: u32,
    height: u32,
    format: vk.Format,
    tiling: vk.ImageTiling,
    usage: vk.ImageUsageFlags,
) !vk.Image {
    const image_create_info = vk.ImageCreateInfo{
        .image_type = .@"2d",
        .format = format,
        .extent = .{
            .width = width,
            .height = height,
            .depth = 1,
        },
        .mip_levels = 1,
        .array_layers = 1,
        .samples = .{ .@"1_bit" = true },
        .tiling = tiling,
        .usage = usage,
        .initial_layout = .undefined,
        .sharing_mode = .exclusive,
    };

    return try app.gpu.vkd.createImage(
        app.gpu.device,
        &image_create_info,
        null,
    );
}

pub fn createImageView(app: *App, image: vk.Image, format: vk.Format) !vk.ImageView {
    const image_view_create_info = vk.ImageViewCreateInfo{
        .image = image,
        .view_type = .@"2d",
        .format = format,
        .subresource_range = .{
            .aspect_mask = .{ .color_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
        .components = .{
            .r = .identity,
            .g = .identity,
            .b = .identity,
            .a = .identity,
        },
    };

    return app.gpu.vkd.createImageView(
        app.gpu.device,
        &image_view_create_info,
        null
    );
}

pub fn transitionImageLayout(
    app: *const App,
    image: vk.Image,
    old_layout: vk.ImageLayout,
    new_layout: vk.ImageLayout,
) !void {
    const command_buffer = try command.beginSingleTimeCommands(app);

    var barrier1 = vk.ImageMemoryBarrier{
        .old_layout = old_layout,
        .new_layout = new_layout,
        .image = image,
        .subresource_range = .{
            .aspect_mask = .{ .color_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
        .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .src_access_mask = .{},
        .dst_access_mask = .{},
    };

    var src_stage_mask: vk.PipelineStageFlags = .{};
    var dst_stage_mask: vk.PipelineStageFlags = .{};

    if (old_layout == .undefined and new_layout == .transfer_dst_optimal) {
        barrier1.src_access_mask = .{};
        barrier1.dst_access_mask = .{ .transfer_write_bit = true };
        src_stage_mask = .{ .top_of_pipe_bit = true };
        dst_stage_mask = .{ .transfer_bit = true };

    } else if (old_layout == .transfer_dst_optimal and new_layout == .general) {
        barrier1.src_access_mask = .{ .transfer_write_bit = true };
        barrier1.dst_access_mask = .{ .shader_write_bit = true, .shader_read_bit = true };
        src_stage_mask = .{ .transfer_bit = true };
        dst_stage_mask = .{ .compute_shader_bit = true };

    } else {
        std.log.err("Invalid layout transition", .{});
        return error.InvalidLayoutTransition;
    }

    app.gpu.vkd.cmdPipelineBarrier(
        command_buffer,
        src_stage_mask,
        dst_stage_mask,
        .{},
        0,
        null,
        0,
        null,
        1,
        @ptrCast(&barrier1),
    );

    try command.endSingleTimeCommands(app, command_buffer);
}

pub fn copyBufferToImage(
    app: *const App,
    buffer: vk.Buffer,
    image: vk.Image,
    width: u32,
    height: u32,
) !void {
    const command_buffer = try command.beginSingleTimeCommands(app);

    const region = vk.BufferImageCopy{
        .buffer_offset = 0,
        .buffer_row_length = 0,
        .buffer_image_height = 0,
        .image_subresource = .{
            .aspect_mask = .{ .color_bit = true },
            .base_array_layer = 0,
            .mip_level = 0,
            .layer_count = 1,
        },
        .image_offset = .{ .x = 0, .y = 0, .z = 0 },
        .image_extent = .{
            .width = width,
            .height = height,
            .depth = 1,
        },
    };

    app.gpu.vkd.cmdCopyBufferToImage(
        command_buffer,
        buffer,
        image,
        .transfer_dst_optimal,
        1,
        @ptrCast(&region),
    );

    try command.endSingleTimeCommands(app, command_buffer);
}

pub fn copyImageToBuffer(
    app: *const App,
    buffer: vk.Buffer,
    image: vk.Image,
    width: u32,
    height: u32,
) !void {
    const command_buffer = try command.beginSingleTimeCommands(app);

    const region = vk.BufferImageCopy{
        .buffer_offset = 0,
        .buffer_row_length = 0,
        .buffer_image_height = 0,
        .image_subresource = .{
            .aspect_mask = .{ .color_bit = true },
            .base_array_layer = 0,
            .mip_level = 0,
            .layer_count = 1,
        },
        .image_offset = .{ .x = 0, .y = 0, .z = 0 },
        .image_extent = .{
            .width = width,
            .height = height,
            .depth = 1,
        },
    };

    app.gpu.vkd.cmdCopyImageToBuffer(
        command_buffer,
        image,
        .general,
        buffer,
        1,
        @ptrCast(&region),
    );

    try command.endSingleTimeCommands(app, command_buffer);
}
