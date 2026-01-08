const std = @import("std");
const vk = @import("vulkan");
const core = @import("core.zig");

const App = core.VulkanApp;

const Self = @This();

pub const Dispatch = struct {
    x: usize,
    y: usize,
    z: usize,
};

module: vk.ShaderModule,
dispatch: Dispatch,

pub fn init(
    app: *const App,
    file_path: []const u8,
    dispatch: Dispatch,
) !Self {
    return .{
        .module = try createShaderModuleFromFilePath(app, file_path),
        .dispatch = dispatch,
    };
}

pub fn deinit(
    shader: *Self,
    app: *const App,
) void {
    app.gpu.vkd.destroyShaderModule(app.gpu.device, shader.module, null);
}

fn createShaderModuleFromFilePath(
    app: *const App,
    file_path: []const u8
) !vk.ShaderModule {
    var file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    var buf: [4096]u8 = undefined;
    var file_reader = file.reader(&buf);
    const reader = &file_reader.interface;

    const file_data = try reader.allocRemaining(app.allocator, .unlimited);
    defer app.allocator.free(file_data);

    return try createShaderModule(app, file_data);
}

fn createShaderModule(app: *const App, code: []const u8) !vk.ShaderModule {
    const create_info = vk.ShaderModuleCreateInfo{
        .code_size = code.len,
        .p_code = @ptrCast(@alignCast(code.ptr)),
    };

    return try app.gpu.vkd.createShaderModule(
        app.gpu.device,
        &create_info,
        null
    );
}
