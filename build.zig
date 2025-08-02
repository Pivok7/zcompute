const std = @import("std");

fn buildLog(comptime string: []const u8, args: anytype) !void {
    std.debug.print("build: " ++ string, args);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zcomp",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = .optimize != .Debug,
    });
    
    // Libraries
    const vulkan = b.dependency("vulkan_zig", .{
        .registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml"),
    }).module("vulkan-zig");
    exe.root_module.addImport("vulkan", vulkan);

    const zglfw_dep = b.dependency("zglfw", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zglfw", zglfw_dep.module("root"));

    if (target.result.os.tag != .emscripten) {
        exe.linkLibrary(zglfw_dep.artifact("glfw"));
    }

    // Hide console on Windows when launching exe
    if (target.result.os.tag == .windows and optimize != .Debug) {
        exe.subsystem = .Windows;
    }

    b.installArtifact(exe);

    // Shader compilation
    const compile_comp_shader = b.addSystemCommand(&.{
        "glslc",
        "src/shaders/square.comp",
        "-o",
        "src/shaders/square.spv",
    });

    exe.step.dependOn(&compile_comp_shader.step);
    if (optimize == .Debug) try buildLog("Compiled compute shader\n", .{});

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);
}
