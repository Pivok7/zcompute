const std = @import("std");
const vk = @import("vulkan");
const glfw = @import("zglfw");
const core = @import("core.zig");

const VulkanApp = core.VulkanApp;

pub fn getRequiredExtensions(app: *VulkanApp) !void {
    var glfw_extensions: [][*:0]const u8 = undefined;
    glfw_extensions = try glfw.getRequiredInstanceExtensions();

    var extensions = std.ArrayList([*:0]const u8).init(app.allocator);
    try extensions.appendSlice(glfw_extensions);
    try extensions.append(vk.extensions.ext_debug_utils.name);

    app.instance_extensions = extensions;
}
