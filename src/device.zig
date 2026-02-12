const std = @import("std");
const vk = @import("vulkan");
const core = @import("core.zig");

const GPU = core.VulkanGPU;
const VkAssert = core.VkAssert;
const validation_layers = core.validation_layers;
const device_extensions = core.device_extensions;

const QueueFamilyIndices = struct {
    compute_bit: ?u32 = null,
    graphics_bit: ?i32 = null,

    fn isOptimal(self: @This()) bool {
        return (
            self.compute_bit != null and
            self.graphics_bit == null
        );
    }

    fn isCapable(self: @This()) bool {
        return (self.compute_bit != null);
    }
};

pub fn pickPhysicalDevice(gpu: *const GPU) !vk.PhysicalDevice {
    var device_count: u32 = 0;
    var result = try gpu.vki.enumeratePhysicalDevices(gpu.instance, &device_count, null);
    try VkAssert.withMessage(result, "Failed to find a GPU with Vulkan support.");

    const available_devices = try gpu.allocator.alloc(vk.PhysicalDevice, device_count);
    defer gpu.allocator.free(available_devices);

    result = try gpu.vki.enumeratePhysicalDevices(gpu.instance, &device_count, available_devices.ptr);
    try VkAssert.withMessage(result, "Failed to find a GPU with Vulkan support.");

    for (available_devices) |device| {
        if (try isDeviceSuitable(gpu, device)) {
            return device;
        }
    }

    std.log.err("Failed to find a suitable GPU!", .{});
    return error.SuitableGPUNotFound;
}

fn isDeviceSuitable(gpu: *const GPU, device: vk.PhysicalDevice) !bool {
    const indices: QueueFamilyIndices = try findQueueFamilies(gpu, device);

    if (indices.isOptimal()) {
        gpu.log(.debug, "Selected compute family", .{});
        return true;
    } else if (indices.isCapable()) {
        gpu.log(.debug, "Selected compute + graphics family", .{});
        gpu.log(.warn, "Suboptimal queue family. Running compute + graphics family. Pure compute family is optimal", .{});
        return true;
    }

    return false;
}

fn findQueueFamilies(gpu: *const GPU, device: vk.PhysicalDevice) !QueueFamilyIndices {
    var indices: QueueFamilyIndices = .{};

    var queue_family_count: u32 = 0;
    gpu.vki.getPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, null);

    const available_queue_families = try gpu.allocator.alloc(vk.QueueFamilyProperties, queue_family_count);
    defer gpu.allocator.free(available_queue_families);

    gpu.vki.getPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, available_queue_families.ptr);

    // First try to find optimal queue family
    for (available_queue_families, 0..) |queue_family, i| {
        indices = .{};

        if (queue_family.queue_flags.compute_bit) {
            indices.compute_bit = @intCast(i);
        }
        if (queue_family.queue_flags.graphics_bit) {
            indices.graphics_bit = @intCast(i);
        }

        if (indices.isOptimal()) return indices;
    }

    // Fallback to compute + graphics
    for (available_queue_families, 0..) |queue_family, i| {
        indices = .{};
        if (queue_family.queue_flags.compute_bit) {
            indices.compute_bit = @intCast(i);
        }
        if (queue_family.queue_flags.graphics_bit) {
            indices.graphics_bit = @intCast(i);
        }

        if (indices.isCapable()) {
            return indices;
        }
    }

    return indices;
}

pub fn createLogicalDevice(gpu: *const GPU) !vk.Device {
    const indices: QueueFamilyIndices = try findQueueFamilies(gpu, gpu.physical_device);

    var unique_queue_families = std.ArrayList(u32){};
    defer unique_queue_families.deinit(gpu.allocator);

    const all_queue_families = &[_]u32{ indices.compute_bit.? };

    for (all_queue_families) |queue_family| {
        for (unique_queue_families.items) |item| {
            if (item == queue_family) {
                continue;
            }
        }
        try unique_queue_families.append(gpu.allocator, queue_family);
    }

    var queue_create_infos = try gpu.allocator.alloc(vk.DeviceQueueCreateInfo, unique_queue_families.items.len);
    defer gpu.allocator.free(queue_create_infos);

    const queue_priority: f32 = 1.0;
    for (unique_queue_families.items, 0..) |queue_family, i| {
        queue_create_infos[i] = vk.DeviceQueueCreateInfo{
            .queue_family_index = queue_family,
            .queue_count = 1,
            .p_queue_priorities = @ptrCast(&queue_priority),
        };
    }

    var feature_chain: ?*anyopaque = null;

    var feature_AMD = vk.PhysicalDeviceCoherentMemoryFeaturesAMD{
        .device_coherent_memory = vk.TRUE,
    };

    if (supportsCoherentMemoryAMD(gpu)) {
        appendFeatureChain(&feature_chain, @ptrCast(&feature_AMD));
        gpu.log(.debug, "Enabled device coherent memory for AMD", .{});
    }

    var device_features = vk.PhysicalDeviceFeatures{
        .shader_float_64 = if (gpu.options.features.float64) vk.TRUE else vk.FALSE,
    };

    var create_info = vk.DeviceCreateInfo{
        .p_next = feature_chain,
        .p_enabled_features = &device_features,
        .p_queue_create_infos = queue_create_infos.ptr,
        .queue_create_info_count = 1,
        .enabled_extension_count = device_extensions.len,
        .pp_enabled_extension_names = @ptrCast(&device_extensions),
        .enabled_layer_count = if (gpu.options.enable_validation_layers) @intCast(validation_layers.len) else 0,
        .pp_enabled_layer_names = if (gpu.options.enable_validation_layers) @ptrCast(&validation_layers) else null,
    };

    return try gpu.vki.createDevice(gpu.physical_device, &create_info, null);
}

pub fn getComputeQueue(gpu: *const GPU) !vk.Queue {
    const indices: QueueFamilyIndices = try findQueueFamilies(gpu, gpu.physical_device);
    return gpu.vkd.getDeviceQueue(gpu.device, indices.compute_bit.?, 0);
}

pub fn getComputeQueueIndex(gpu: *const GPU) !u32 {
    const indices: QueueFamilyIndices = try findQueueFamilies(gpu, gpu.physical_device);
    return indices.compute_bit.?;
}

fn appendFeatureChain(chain: *?*anyopaque, feature: *anyopaque) void {
    if (chain.*) |cha| {
        var current_link: *vk.PhysicalDeviceFeatures2 = @alignCast(@ptrCast(cha));
        while (current_link.p_next) |link| {
            current_link = @alignCast(@ptrCast(link));
        }
        current_link.p_next = feature;
    } else {
        chain.* = feature;
    }
}

fn supportsCoherentMemoryAMD(gpu: *const GPU) bool {
    var features = vk.PhysicalDeviceCoherentMemoryFeaturesAMD{};

    var features2 = vk.PhysicalDeviceFeatures2{
        .p_next = @ptrCast(&features),
        .features = .{},
    };

    gpu.vki.getPhysicalDeviceFeatures2(gpu.physical_device, &features2);

    if (features.device_coherent_memory == vk.TRUE) return true
    else return false;
}
