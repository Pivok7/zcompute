const std = @import("std");
const vk = @import("vulkan");
const core = @import("core.zig");

const VulkanApp = core.VulkanApp;

pub fn createShaderModuleFromFilePath(app: *VulkanApp, file_path: []const u8) !vk.ShaderModule {
    var file = try std.fs.cwd().openFile(file_path, .{});

    const file_data = file.reader().readAllAlloc(app.allocator, std.math.maxInt(usize)) catch |err| {
        file.close();
        return err;
    };
    defer app.allocator.free(file_data);
    file.close();

    return try createShaderModule(app, file_data);
}

pub fn createShaderModule(app: *VulkanApp, code: []const u8) !vk.ShaderModule {
    const create_info = vk.ShaderModuleCreateInfo{
        .code_size = code.len,
        .p_code = @ptrCast(@alignCast(code.ptr)),
    };

    return try app.vkd.createShaderModule(app.device, &create_info, null);
}
