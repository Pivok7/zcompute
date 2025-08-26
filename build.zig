const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addModule("zcompute", .{
        .root_source_file = b.path("src/zcompute.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // Libraries
    const vulkan_zig_dep = b.dependency("vulkan", .{
        .registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml"),
        .target = target,
        .optimize = optimize,
    });
    lib.addImport("vulkan", vulkan_zig_dep.module("vulkan-zig"));
}
