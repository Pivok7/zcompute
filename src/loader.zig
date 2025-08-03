const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");

pub fn loadVulkan() !std.DynLib {
    const vulkan_lib_name = switch (builtin.os.tag) {
        .windows => "vulkan-1.dll",
        .linux => "libvulkan.so.1",
        .macos => "libvulkan.1.dylib",
        else => @panic("Unsupported OS"),
    };

    return std.DynLib.open(vulkan_lib_name) catch |err| {
        std.log.err("Failed to load Vulkan library '{s}': {s}", .{
            vulkan_lib_name,
            @errorName(err),
        });
        return err;
    };
}

pub fn loadVkGetInstanceProcAddr(lib: *std.DynLib) !vk.PfnGetInstanceProcAddr {
    return lib.lookup(
        vk.PfnGetInstanceProcAddr,
        "vkGetInstanceProcAddr",
    ) orelse {
        std.log.err("Failed to load {s}", .{"vkGetInstanceProcAddr"});
        return error.SymbolNotFound;
    };
}
