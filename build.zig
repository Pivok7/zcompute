const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addModule("zcompute", .{
        .root_source_file = b.path("src/zcompute.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Libraries
    const vulkan_zig_deb = b.dependency("vulkan", .{
        .registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml"),
    }).module("vulkan-zig");
    lib.addImport("vulkan", vulkan_zig_deb);

    const zglfw_dep = b.dependency("zglfw", .{
        .target = target,
        .optimize = optimize,
    });
    lib.addImport("zglfw", zglfw_dep.module("root"));

    if (target.result.os.tag != .emscripten) {
        lib.linkLibrary(zglfw_dep.artifact("glfw"));
    }
}
