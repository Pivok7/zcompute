const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "main",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const zcompute_dep = b.dependency("zcompute", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zcompute", zcompute_dep.module("zcompute"));

    b.installArtifact(exe);

    // Shader compilation
    const compile_comp_shader = b.addSystemCommand(&.{
        "slangc",
        "src/shader.slang",
        "-target", "spirv",
        "-o", "src/shader.spv",
    });

    exe.step.dependOn(&compile_comp_shader.step);
    if (optimize == .Debug) try buildLog("compiled \"shader.slang\"\n", .{});

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);
}

fn buildLog(comptime string: []const u8, args: anytype) !void {
    std.debug.print("build: " ++ string, args);
}
