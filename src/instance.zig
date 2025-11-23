const std = @import("std");
const vk = @import("vulkan");
const c = @import("c.zig");
const core = @import("core.zig");

const GPU = core.VulkanGPU;
const vkAssesrt = core.VkAssert;
const validation_layers = core.validation_layers;

pub fn getRequiredExtensions(gpu: *const GPU) ![][*:0]const u8 {
    var extensions = std.ArrayList([*:0]const u8){};
    try extensions.append(gpu.allocator, vk.extensions.ext_debug_utils.name);

    return try extensions.toOwnedSlice(gpu.allocator);
}

pub fn createInstance(gpu: *const GPU) !vk.Instance {
    if (gpu.options.enable_validation_layers) {
        try checkValidationLayerSupport(gpu);
    }

    const app_info = vk.ApplicationInfo{
        .p_application_name = "Vulkan",
        .application_version = @bitCast(vk.makeApiVersion(0, 1, 0, 0)),
        .p_engine_name = "No Engine",
        .engine_version = @bitCast(vk.makeApiVersion(0, 1, 0, 0)),
        .api_version = @bitCast(vk.makeApiVersion(0, 1, 3, 0)),
    };

    const create_info = vk.InstanceCreateInfo{
        .flags = .{},
        .p_application_info = &app_info,
        .enabled_layer_count = if (gpu.options.enable_validation_layers) @intCast(validation_layers.len) else 0,
        .pp_enabled_layer_names = if (gpu.options.enable_validation_layers) @ptrCast(&validation_layers) else null,
        .enabled_extension_count = @intCast(gpu.instance_extensions.len),
        .pp_enabled_extension_names = gpu.instance_extensions.ptr,
    };

    return try gpu.vkb.createInstance(&create_info, null);
}

fn checkValidationLayerSupport(gpu: *const GPU) !void {
    var layer_count: u32 = 0;
    var result = try gpu.vkb.enumerateInstanceLayerProperties(&layer_count, null);
    try vkAssesrt.withMessage(result, "Failed to enumerate instance layer properties.");

    const available_layers = try gpu.allocator.alloc(vk.LayerProperties, layer_count);
    defer gpu.allocator.free(available_layers);

    result = try gpu.vkb.enumerateInstanceLayerProperties(&layer_count, @ptrCast(available_layers));
    try vkAssesrt.withMessage(result, "Failed to enumerate instance layer properties.");

    // Print validation layers if debug mode is on
    if (gpu.options.debug_mode and validation_layers.len > 0) {
        std.debug.print("Active validation layers ({d}): \n", .{validation_layers.len});
        for (validation_layers) |val_layer| {
            for (available_layers) |ava_layer| {
                if (c.cStringEql(val_layer, &ava_layer.layer_name)) {
                    std.debug.print("\t [X] {s}\n", .{ava_layer.layer_name});
                } else {
                    std.debug.print("\t [ ] {s}\n", .{ava_layer.layer_name});
                }
            }
        }
    }

    for (validation_layers) |val_layer| {
        var found_layer: bool = false;

        for (available_layers) |ava_layer| {
            if (c.cStringEql(val_layer, &ava_layer.layer_name)) {
                found_layer = true;
                break;
            }
        }

        if (!found_layer) {
            std.log.err("Validation layer \"{s}\" not found", .{val_layer});
            return error.ValidationLayerNotAvailable;
        }
    }
}
