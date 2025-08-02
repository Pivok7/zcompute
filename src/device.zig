const std = @import("std");
const vk = @import("vulkan");
const vk_ctx = @import("vk_context.zig");
const misc = @import("misc.zig");
const core = @import("core.zig");

const VulkanApp = core.VulkanApp;
const VkAssert = vk_ctx.VkAssert;

const QueueFamilyIndices = struct {
    compute_family: ?u32 = null,

    fn isComplete(self: @This()) bool {
        return (self.compute_family != null);
    }
};

pub fn pickPhysicalDevice(app: *const core.VulkanApp) !vk.PhysicalDevice {
    var device_count: u32 = 0;
    var result = try app.vki.enumeratePhysicalDevices(app.instance, &device_count, null);
    try VkAssert.withMessage(result, "Failed to find a GPU with Vulkan support.");

    const available_devices = try app.allocator.alloc(vk.PhysicalDevice, device_count);
    defer app.allocator.free(available_devices);

    result = try app.vki.enumeratePhysicalDevices(app.instance, &device_count, available_devices.ptr);
    try VkAssert.withMessage(result, "Failed to find a GPU with Vulkan support.");

    for (available_devices) |device| {
        if (try isDeviceSuitable(app, device)) {
            return device;
        }
    }

    std.log.err("Failed to find a suitable GPU!", .{});
    return error.SuitableGPUNotFound;
}

fn isDeviceSuitable(app: *const VulkanApp, device: vk.PhysicalDevice) !bool {
    const indices: QueueFamilyIndices = try findQueueFamilies(app, device);

    return indices.isComplete();
}

fn findQueueFamilies(app: *const VulkanApp, device: vk.PhysicalDevice) !QueueFamilyIndices {
    var indices: QueueFamilyIndices = .{};

    var queue_family_count: u32 = 0;
    app.vki.getPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, null);

    const available_queue_families = try app.allocator.alloc(vk.QueueFamilyProperties, queue_family_count);
    defer app.allocator.free(available_queue_families);

    app.vki.getPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, available_queue_families.ptr);

    for (available_queue_families, 0..) |queue_family, i| {
        if (queue_family.queue_flags.compute_bit) {
            indices.compute_family = @intCast(i);
        }

        if (indices.isComplete()) break;
    }

    return indices;
}

pub fn createLogicalDevice(app: *const VulkanApp) !vk.Device {
    const indices: QueueFamilyIndices = try findQueueFamilies(app, app.physical_device);

    var unique_queue_families = std.ArrayList(u32).init(app.allocator);
    defer unique_queue_families.deinit();

    const all_queue_families = &[_]u32{ indices.compute_family.? };

    for (all_queue_families) |queue_family| {
        for (unique_queue_families.items) |item| {
            if (item == queue_family) {
                continue;
            }
        }
        try unique_queue_families.append(queue_family);
    }

    var queue_create_infos = try app.allocator.alloc(vk.DeviceQueueCreateInfo, unique_queue_families.items.len);
    defer app.allocator.free(queue_create_infos);

    const queue_priority: f32 = 1.0;
    for (unique_queue_families.items, 0..) |queue_family, i| {
        queue_create_infos[i] = vk.DeviceQueueCreateInfo{
            .queue_family_index = queue_family,
            .queue_count = 1,
            .p_queue_priorities = @ptrCast(&queue_priority),
        };
    }

    const features_AMD = vk.PhysicalDeviceCoherentMemoryFeaturesAMD{
        .device_coherent_memory = vk.TRUE,
    };

    const supports_coherent_memory_AMD = supportsCoherentMemoryAMD(app);

    var create_info = vk.DeviceCreateInfo{
        .p_next = if (supports_coherent_memory_AMD) @ptrCast(&features_AMD) else null,
        .p_queue_create_infos = queue_create_infos.ptr,
        .queue_create_info_count = 1,
        .enabled_extension_count = misc.device_extensions.len,
        .pp_enabled_extension_names = @ptrCast(&misc.device_extensions),
        .enabled_layer_count = if (app.enable_validation_layers) @intCast(misc.validation_layers.len) else 0,
        .pp_enabled_layer_names = if (app.enable_validation_layers) @ptrCast(&misc.validation_layers) else null,
    };

    if (supports_coherent_memory_AMD) {
        app.log(.debug, "Enabled device coherent memory for AMD", .{});
    }

    return try app.vki.createDevice(app.physical_device, &create_info, null);
}

pub fn getComputeQueue(app: *const VulkanApp) !vk.Queue {
    const indices: QueueFamilyIndices = try findQueueFamilies(app, app.physical_device);
    return app.vkd.getDeviceQueue(app.device, indices.compute_family.?, 0);
}

pub fn getComputeQueueIndex(app: *const VulkanApp) !u32 {
    const indices: QueueFamilyIndices = try findQueueFamilies(app, app.physical_device);
    return indices.compute_family.?;
}

fn supportsCoherentMemoryAMD(app: *const VulkanApp) bool {
    var features = vk.PhysicalDeviceCoherentMemoryFeaturesAMD{};

    var features2 = vk.PhysicalDeviceFeatures2{
        .p_next = @ptrCast(&features),
        .features = .{},
    };

    app.vki.getPhysicalDeviceFeatures2(app.physical_device, &features2);

    if (features.device_coherent_memory == vk.TRUE) return true
    else return false;
}
