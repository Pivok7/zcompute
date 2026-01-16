# zcompute

Simple Vulkan library for running compute shaders on the GPU

## Using

You will need:

* Zig compiler (0.15.2)

* Vulkan SDK

* slangc (Slang shader compiler) <br>

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

For examples check out the 'examples' folder

## Third party libraries used in this project

* vulkan-zig: https://github.com/Snektron/vulkan-zig.git <br>
Licensed under the MIT License.
