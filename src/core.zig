const std = @import("std");
const vk = @import("vulkan");
const loader = @import("loader.zig");
const instance = @import("instance.zig");
const device = @import("device.zig");
const memory = @import("memory.zig");
const pipeline = @import("pipeline.zig");
const command = @import("command.zig");
const SharedMemory = @import("SharedMemory.zig");
const Shader = @import("Shader.zig");

const Allocator = std.mem.Allocator;

pub const validation_layers = [_][*:0]const u8{
    "VK_LAYER_KHRONOS_validation",
};

pub const device_extensions = [_][*:0]const u8{
};

pub const VkAssert = struct {
    pub fn basic(result: vk.Result) !void {
        switch (result) {
            .success => return,
            else => return error.Unknown,
        }
    }

    pub fn withMessage(result: vk.Result, message: []const u8) !void {
        switch (result) {
            .success => return,
            else => {
                std.log.err("{s} {s}", .{ @tagName(result), message });
                return error.Unknown;
            },
        }
    }
};

pub const VulkanGPU = struct {
    pub const Options = struct {
        const Features = struct {
            float64: bool = false,
        };

        const VulkanApiVersion = struct {
            major: u7 = 1,
            minor: u10 = 1,
            patch: u12 = 0,
        };

        debug_mode: bool = false,
        enable_validation_layers: bool = false,
        features: Features = .{},
        vulkan_api_version: VulkanApiVersion = .{},
    };

    const Self = @This();

    allocator: Allocator,
    options: Options = .{},

    vulkan_lib: std.DynLib = undefined,

    vkb: vk.BaseWrapper = undefined,
    vki: vk.InstanceWrapper = undefined,
    vkd: vk.DeviceWrapper = undefined,

    instance: vk.Instance = .null_handle,

    physical_device: vk.PhysicalDevice = .null_handle,
    device: vk.Device = .null_handle,

    compute_queue: vk.Queue = .null_handle,
    compute_queue_index: u32 = undefined,

    pub fn init(
        allocator: Allocator,
        options: Options,
    ) !Self {
        var dev = VulkanGPU{
            .allocator = allocator,
            .options = options,
        };

        dev.vulkan_lib = try loader.loadVulkan();
        const vkGetInstanceProcAddr = try loader.loadVkGetInstanceProcAddr(&dev.vulkan_lib);
        dev.log(.debug, "Loaded Vulkan library", .{});

        dev.vkb = vk.BaseWrapper.load(vkGetInstanceProcAddr);

        dev.instance = try instance.createInstance(&dev);
        dev.log(.info, "Created Vulkan instance", .{});

        dev.vki = vk.InstanceWrapper.load(
            dev.instance,
            dev.vkb.dispatch.vkGetInstanceProcAddr.?
        );

        dev.physical_device = try device.pickPhysicalDevice(&dev);
        dev.log(
            .info,
            "Device: {s}",
            .{dev.vki.getPhysicalDeviceProperties(dev.physical_device).device_name}
        );

        dev.device = try device.createLogicalDevice(&dev);
        dev.log(.debug, "Created logical device", .{});

        dev.vkd = vk.DeviceWrapper.load(
            dev.device,
            dev.vki.dispatch.vkGetDeviceProcAddr.?
        );

        dev.compute_queue_index = try device.getComputeQueueIndex(&dev);
        dev.compute_queue = try device.getComputeQueue(&dev);

        return dev;
    }

    pub fn deinit(dev: *Self) void {
        dev.vkd.destroyDevice(dev.device, null);
        dev.vki.destroyInstance(dev.instance, null);
        dev.log(.info, "Destroyed Vulkan instance", .{});

        dev.vulkan_lib.close();
        dev.log(.debug, "Unloaded Vulkan library", .{});
    }

    pub fn log(
        dev: *const Self,
        level: std.log.Level,
        comptime format: []const u8,
        args: anytype
    ) void {
        switch (level) {
            .debug => if (dev.options.debug_mode) {
                std.log.debug("(gpu) " ++ format, args);
            },
            .info => if (dev.options.debug_mode) {
                std.log.info("(gpu) " ++ format, args);
            },
            .warn => std.log.warn("(gpu) " ++ format, args),
            .err => std.log.err("(gpu) " ++ format, args),
        }
    }
};

pub const VulkanApp = struct {
    pub const Options = struct {
        debug_mode: bool = false,
    };

    const Self = @This();

    allocator: Allocator,
    options: Options = .{},

    gpu: *const VulkanGPU = undefined,

    shared_memories: std.ArrayList(SharedMemory) = .empty,
    shrd_mem_buffers: std.ArrayList(*const SharedMemory) = .empty,
    shrd_mem_images: std.ArrayList(*const SharedMemory) = .empty,

    buffers: std.ArrayList(vk.Buffer) = .empty,
    buffers_offsets: std.ArrayList(usize) = .empty,
    buffers_memory: vk.DeviceMemory = .null_handle,

    images: std.ArrayList(vk.Image) = .empty,
    images_memory: vk.DeviceMemory = .null_handle,
    images_views: std.ArrayList(vk.ImageView) = .empty,

    shader: ?Shader = null,

    descriptor_set_layout: vk.DescriptorSetLayout = .null_handle,
    descriptor_set: vk.DescriptorSet = .null_handle,
    descriptor_pool: vk.DescriptorPool = .null_handle,
    pipeline_layout: vk.PipelineLayout = .null_handle,
    pipeline_cache: vk.PipelineCache = .null_handle,

    compute_pipeline: vk.Pipeline = .null_handle,
    command_pool: vk.CommandPool = .null_handle,
    command_buffer: vk.CommandBuffer = .null_handle,

    pub fn init(
        allocator: Allocator,
        gpu: *const VulkanGPU,
        options: Options,
    ) !Self {
        return .{
            .allocator = allocator,
            .gpu = gpu,
            .options = options,
        };
    }

    pub fn bindMemory(
        app: *Self,
        shared_memory: *const SharedMemory,
        binding: u32,
    ) !void {
        var shared_memory_copy = shared_memory.*;
        shared_memory_copy.binding = binding;

        try app.shared_memories.append(
            app.allocator,
            shared_memory_copy,
        );
    }

    pub fn loadShader(
        app: *Self,
        shader_path: []const u8,
        dispatch: Shader.Dispatch,
    ) !void {
        if (app.shader) |_| {
            app.log(.err, "Only one shader per app is possible for now", .{});
            return error.MultipleShadersUnsupported;
        }

        app.shader = Shader.init(app, shader_path, dispatch) catch |e| {
            app.log(.err, "Failed to load shader: {s}", .{shader_path});
            return e;
        };
    }

    pub fn submit(
        app: *Self,
    ) !void {
        if (app.shared_memories.items.len == 0) {
            app.log(.err, "Cannot run with no SharedMemory bound", .{});
            return error.NoSharedMemoryBound;
        }

        if (app.shader == null) {
            app.log(.err, "Cannot create pipeline without shader", .{});
            return error.NoShaderLoaded;
        }

        var binding_set = std.AutoHashMap(u32, void).init(
            app.allocator
        );
        defer binding_set.deinit();

        for (app.shared_memories.items) |*shrd_mem| {
            const res = try binding_set.fetchPut(shrd_mem.binding, {});
            if (res) |e| {
                app.log(.err, "Found duplicate binding: {d}", .{e.key});
                return error.DuplicateBinding;
            }
        }

        for (app.shared_memories.items) |*shrd_mem| {
            switch (shrd_mem.info) {
                .buffer => try app.shrd_mem_buffers.append(app.allocator, shrd_mem),
                .image_2d => try app.shrd_mem_images.append(app.allocator, shrd_mem),
            }
        }

        app.command_pool = try command.createCommandPool(app);

        try memory.createBuffers(app);
        try memory.createImages(app);

        app.descriptor_set_layout = try pipeline.createDescriptorSetLayout(app);
        app.descriptor_pool = try pipeline.createDescriptorPool(app);
        app.pipeline_layout = try pipeline.createPipelineLayout(app);
        app.pipeline_cache = try pipeline.createPipelineCache(app);
        app.compute_pipeline = try pipeline.createPipeline(app);
        app.descriptor_set = try pipeline.createDescriptorSets(app);
        app.log(.info, "Created compute pipeline", .{});

        app.command_buffer = try command.createCommandBuffer(app);
        app.log(.debug, "Created command pool", .{});
    }

    pub fn run(app: *const Self) !void {
        try memory.dbgReadImage(app);
        app.log(.info, "Submitting work...", .{});
        try command.submitWork(app);
        app.log(.info, "Work finished", .{});
        try memory.dbgReadImage(app);
    }

    pub fn deinit(app: *Self) void {
        app.gpu.vkd.destroyCommandPool(app.gpu.device, app.command_pool, null);
        app.gpu.vkd.destroyPipeline(app.gpu.device, app.compute_pipeline, null);

        app.gpu.vkd.destroyPipelineCache(app.gpu.device, app.pipeline_cache, null);
        app.gpu.vkd.destroyPipelineLayout(app.gpu.device, app.pipeline_layout, null);
        app.gpu.vkd.destroyDescriptorPool(app.gpu.device, app.descriptor_pool, null);
        app.gpu.vkd.destroyDescriptorSetLayout(app.gpu.device, app.descriptor_set_layout, null);

        if (app.shader) |*shader| {
            shader.deinit(app);
        }

        for (app.images.items) |img| {
            app.gpu.vkd.destroyImage(app.gpu.device, img, null);
        }

        for (app.images_views.items) |img_view| {
            app.gpu.vkd.destroyImageView(app.gpu.device, img_view, null);
        }

        app.gpu.vkd.freeMemory(app.gpu.device, app.images_memory, null);

        app.gpu.vkd.freeMemory(app.gpu.device, app.buffers_memory, null);

        for (app.buffers.items) |buf| {
            app.gpu.vkd.destroyBuffer(app.gpu.device, buf, null);
        }

        app.images.deinit(app.allocator);
        app.images_views.deinit(app.allocator);
        app.buffers_offsets.deinit(app.allocator);
        app.buffers.deinit(app.allocator);
        app.shrd_mem_buffers.deinit(app.allocator);
        app.shrd_mem_images.deinit(app.allocator);
        app.shared_memories.deinit(app.allocator);
    }

    /// This function takes another function as a parameter
    /// which should implement code for editing the buffer.
    /// It's parameters are:
    /// -> u8[] - buffer
    /// -> usize - element size
    pub fn editData(
        app: *const Self,
        binding: u32,
        func: *const fn(data: []u8, shrd_mem: *const SharedMemory) void
    ) !void {
        const index = try app.getBindingIndex(binding);

        const shrd_mem = app.shared_memories.items[index];

        const mapped_memory = try memory.mapMemory(
            app,
            app.buffers_memory,
            app.buffers_offsets.items[index],
            shrd_mem.size(),
        );

        func(mapped_memory, &shrd_mem);

        app.gpu.vkd.unmapMemory(app.gpu.device, app.buffers_memory);
    }

    pub fn getData(
        app: *const Self,
        buf: anytype,
        binding: u32,
    ) !void {
        const index = try app.getBindingIndex(binding);

        const shrd_mem = app.shared_memories.items[index];

        const mapped_memory = try memory.mapMemory(
            app,
            app.buffers_memory,
            app.buffers_offsets.items[index],
            shrd_mem.size(),
        );

        @memcpy(buf, @as(@TypeOf(buf), @ptrCast(@alignCast(mapped_memory))));

        app.gpu.vkd.unmapMemory(app.gpu.device, app.buffers_memory);
    }

    pub fn getDataAlloc(
        app: *const Self,
        allocator: Allocator,
        binding: u32,
        T: type
    ) ![]T {
        const index = try app.getBindingIndex(binding);

        const buf = try allocator.alloc(
            T,
            app.shared_memories.items[index].elem_num()
        );

        try app.getData(buf, binding);

        return buf;
    }

    // TODO: probably good idea to use hash map here
    fn getBindingIndex(app: *const Self, binding: u32) !u32 {
        return app.getBindingIndexOrNull(binding) orelse {
            app.log(.err, "Memory with binding {d} not found", .{binding});
            return error.BindingNotFound;
        };
    }

    fn getBindingIndexOrNull(app: *const Self, binding: u32) ?u32 {
        var index_or_null: ?u32 = null;
        for (app.shared_memories.items, 0..) |*shrd_mem, i| {
            if (shrd_mem.binding == binding) {
                index_or_null = @intCast(i);
                break;
            }
        }

        return index_or_null;
    }

    pub fn log(
        app: *const Self,
        level: std.log.Level,
        comptime format: []const u8,
        args: anytype
    ) void {
        switch (level) {
            .debug => if (app.options.debug_mode) {
                std.log.debug("(app) " ++ format, args);
            },
            .info => if (app.options.debug_mode) {
                std.log.info("(app) " ++ format, args);
            },
            .warn => std.log.warn("(app) " ++ format, args),
            .err => std.log.err("(app) " ++ format, args),
        }
    }
};
