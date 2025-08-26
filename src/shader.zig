const std = @import("std");
const vk = @import("vulkan");
const core = @import("core.zig");

const VulkanApp = core.VulkanApp;

pub fn createShaderModuleFromFilePath(app: *const VulkanApp, file_path: []const u8) !vk.ShaderModule {
    const file_data = try std.fs.cwd().readFileAlloc(app.allocator, file_path, std.math.maxInt(usize));
    defer app.allocator.free(file_data);

    return try createShaderModule(app, file_data);
}

pub fn createShaderModule(app: *const VulkanApp, code: []const u8) !vk.ShaderModule {
    const create_info = vk.ShaderModuleCreateInfo{
        .code_size = code.len,
        .p_code = @ptrCast(@alignCast(code.ptr)),
    };

    return try app.vkd.createShaderModule(app.device, &create_info, null);
}
