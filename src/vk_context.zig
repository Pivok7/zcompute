const std = @import("std");
const vk = @import("vulkan");
const glfw = @import("zglfw");

pub const VkAssert = struct {
    pub fn basic(result: vk.Result) !void {
        switch (result) {
            .success => return,
            else => return error.Unknown,
        }
    }

    pub fn withMessage(result: vk.Result, message: []const u8) !void {
        switch (result) {
            .success => return,
            else => {
                std.log.err("{s} {s}", .{ @tagName(result), message });
                return error.Unknown;
            },
        }
    }
};

/// To construct base, instance and device wrappers for vulkan-zig, you need to pass a list of 'apis' to it.
const apis: []const vk.ApiInfo = &.{
    .{
        .base_commands = .{
            .createInstance = true,
            .enumerateInstanceLayerProperties = true,
            .getInstanceProcAddr = true,
        },
        .instance_commands = .{
            .destroyInstance = true,
            .enumeratePhysicalDevices = true,
            .getPhysicalDeviceProperties = true,
            .getPhysicalDeviceQueueFamilyProperties = true,
            .createDevice = true,
            .getDeviceProcAddr = true,
            .getPhysicalDeviceMemoryProperties = true,
        },
        .device_commands = .{
            .destroyDevice = true,
            .getDeviceQueue = true,
            .createBuffer = true,
            .destroyBuffer = true,
            .getBufferMemoryRequirements = true,
            .allocateMemory = true,
            .freeMemory = true,
            .mapMemory = true,
            .unmapMemory = true,
            .bindBufferMemory = true,
            .createShaderModule = true,
            .destroyShaderModule = true,
            .createDescriptorSetLayout = true,
            .destroyDescriptorSetLayout = true,
            .createPipelineLayout = true,
            .destroyPipelineLayout = true,
            .createPipelineCache = true,
            .destroyPipelineCache = true,
            .createComputePipelines = true,
            .destroyPipeline = true,
            .createDescriptorPool = true,
            .destroyDescriptorPool = true,
            .allocateDescriptorSets = true,
            .updateDescriptorSets = true,
            .createCommandPool = true,
            .destroyCommandPool = true,
            .allocateCommandBuffers = true,
            .beginCommandBuffer = true,
            .cmdBindPipeline = true,
            .cmdBindDescriptorSets = true,
            .cmdDispatch = true,
            .endCommandBuffer = true,
            .createFence = true,
            .queueSubmit = true,
            .waitForFences = true,
            .destroyFence = true,
        },
    },
};

/// Next, pass the `apis` to the wrappers to create dispatch tables.
pub const BaseDispatch = vk.BaseWrapper(apis);
pub const InstanceDispatch = vk.InstanceWrapper(apis);
pub const DeviceDispatch = vk.DeviceWrapper(apis);

pub extern fn glfwGetInstanceProcAddress(instance: vk.Instance, procname: [*:0]const u8) vk.PfnVoidFunction;
