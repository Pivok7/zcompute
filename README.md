# zcompute

Simple Vulkan library for running compute shaders on the GPU

## Using

You will need:

* Zig compiler (latest stable version)

* Vulkan SDK

* glslc or other shader compiler <br>

Fetch:
```bash
zig fetch --save git+https://github.com/Pivok7/zcompute
```

Inside build.zig:
```zig
const zcompute_dep = b.dependency("zcompute", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zcompute", zcompute_dep.module("zcompute"));
```

Example usage:
```zig
const data = &[_]zcompute.SharedMemory{
    try zcompute.SharedMemory.newSlice(&[_]u32{0, 1, 2, 3, 4}),
};
const dispatch = zcompute.Dispatch{ .x = 5, .y = 1, .z = 1 };

var app = try zcompute.App.init(
    allocator,
    .{},
    "src/shader.spv",
    data,
    dispatch,
);
defer app.deinit();

try app.run();

// Zero means the first buffer
const one = try app.getDataAlloc(allocator, 0, u32);
defer allocator.free(one);

std.debug.print("{d}\n", .{one});
```

Shader (glsl):
```glsl
#version 430
layout(local_size_x = 1, local_size_y = 1) in;

layout(std430, binding = 0) buffer lay0 {
    uint buf[];
};

void main() {
    const uint id = gl_GlobalInvocationID.x;

    buf[id] = buf[id] * buf[id];
}
```

For complete program check out the 'example' folder

## Third party libraries used in this project

* vulkan-zig: https://github.com/Snektron/vulkan-zig.git <br>
Licensed under the MIT License.


* zglfw: https://github.com/zig-gamedev/zglfw.git <br>
Licensed under the MIT License.
