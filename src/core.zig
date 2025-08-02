const std = @import("std");
const vk = @import("vulkan");
const vk_ctx = @import("vk_context.zig");
const glfw = @import("zglfw");
const instance = @import("instance.zig");
const device = @import("device.zig");
const memory = @import("memory.zig");
const shader = @import("shader.zig");
const pipeline = @import("pipeline.zig");
const command = @import("command.zig");

const Allocator = std.mem.Allocator;
const BaseDispatch = vk_ctx.BaseDispatch;
const InstanceDispatch = vk_ctx.InstanceDispatch;
const DeviceDispatch = vk_ctx.DeviceDispatch;

pub const VulkanAppOptions = struct {
    debug_mode: bool = false,
    enable_validation_layers: bool = false,
};

pub const SharedMemory = struct {
    const Self = @This();

    data: ?*const anyopaque = null,
    elem_num: u32,
    elem_size: usize,

    pub fn size(self: *const Self) usize {
        return self.elem_num * self.elem_size;
    }

    pub fn newEmpty(len: u32, T: type) !Self {
        if (len == 0) return error.LengthTooShort;
        if (@sizeOf(T) == 0) return error.ZeroSizeType;

        return .{
            .elem_num = len,
            .elem_size = @sizeOf(T),
        };
    }

    pub fn newSlice(slice: anytype) !Self {
        if (slice.len == 0) return error.NotSlice;

        const child_type = @typeInfo(@TypeOf(slice)).pointer.child;
        if (@sizeOf(child_type) == 0) return error.ZeroSizeType;

        return .{
            .data = slice.ptr,
            .elem_num = slice.len,
            .elem_size = @sizeOf(child_type),
        };
    }
};

pub const Dispatch = struct {
    x: usize,
    y: usize,
    z: usize,
};

pub const VulkanApp = struct {
    const Self = @This();

    allocator: Allocator,
    debug_mode: bool,
    enable_validation_layers: bool,

    vkb: BaseDispatch = undefined,
    vki: InstanceDispatch = undefined,
    vkd: DeviceDispatch = undefined,

    instance: vk.Instance = .null_handle,
    instance_extensions: [][*:0]const u8 = undefined,

    physical_device: vk.PhysicalDevice = .null_handle,
    device: vk.Device = .null_handle,

    compute_queue: vk.Queue = .null_handle,
    compute_queue_index: u32 = undefined,

    shared_memories: []const SharedMemory,
    dispatch: Dispatch,

    device_memories: std.ArrayList(vk.DeviceMemory) = undefined,
    device_buffers: std.ArrayList(vk.Buffer) = undefined,

    shader_module: vk.ShaderModule = .null_handle,

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
        options: VulkanAppOptions,
        shader_path: []const u8,
        data: []const SharedMemory,
        dispatch: Dispatch,
    ) !Self {
        std.fs.cwd().access(shader_path, .{}) catch |e| switch (e) {
            error.FileNotFound => {
                std.log.err("File: {s} not found\n", .{shader_path});
                return error.FileNotFound;
            },
            else => return e,
        };

        var app = VulkanApp{
            .allocator = allocator,
            .debug_mode = options.debug_mode,
            .enable_validation_layers = options.enable_validation_layers,
            .shared_memories = data,
            .dispatch = dispatch,
        };

        try glfw.init();
        app.log(.debug, "Initialized GLFW", .{});

        app.vkb = try BaseDispatch.load(vk_ctx.glfwGetInstanceProcAddress);

        app.instance_extensions = try instance.getRequiredExtensions(&app);
        app.instance = try instance.createInstance(&app);
        app.log(.info, "Created Vulkan instance", .{});

        app.vki = try InstanceDispatch.load(app.instance, app.vkb.dispatch.vkGetInstanceProcAddr);

        app.physical_device = try device.pickPhysicalDevice(&app);
        app.log(.info, "Device: {s}", .{app.vki.getPhysicalDeviceProperties(app.physical_device).device_name});

        app.device = try device.createLogicalDevice(&app);
        app.log(.debug, "Created logical device", .{});

        app.vkd = try DeviceDispatch.load(app.device, app.vki.dispatch.vkGetDeviceProcAddr);

        app.compute_queue = try device.getComputeQueue(&app);
        app.compute_queue_index = try device.getComputeQueueIndex(&app);

        app.device_memories = std.ArrayList(vk.DeviceMemory).init(app.allocator);
        app.device_buffers = std.ArrayList(vk.Buffer).init(app.allocator);

        try memory.createBuffer(&app);
        app.log(.debug, "Created memory buffer", .{});

        app.shader_module = try shader.createShaderModuleFromFilePath(&app, shader_path);
        app.log(.debug, "Loaded shader module", .{});

        app.descriptor_set_layout = try pipeline.createDescriptorSetLayout(&app);
        app.descriptor_pool = try pipeline.createDescriptorPool(&app);
        app.pipeline_layout = try pipeline.createPipelineLayout(&app);
        app.pipeline_cache = try pipeline.createPipelineCache(&app);
        app.compute_pipeline = try pipeline.CreatePipeline(&app);
        app.descriptor_set = try pipeline.createDescriptorSet(&app);
        app.log(.debug, "Created compute pipeline", .{});

        app.command_pool = try command.createCommandPool(&app);
        app.command_buffer = try command.createCommandBuffer(&app);
        app.log(.debug, "Created command pool", .{});

        return app;
    }

    pub fn deinit(app: *Self) void {
        app.vkd.destroyCommandPool(app.device, app.command_pool, null);
        app.vkd.destroyPipeline(app.device, app.compute_pipeline, null);

        app.vkd.destroyPipelineCache(app.device, app.pipeline_cache, null);
        app.vkd.destroyPipelineLayout(app.device, app.pipeline_layout, null);
        app.vkd.destroyDescriptorPool(app.device, app.descriptor_pool, null);
        app.vkd.destroyDescriptorSetLayout(app.device, app.descriptor_set_layout, null);

        app.vkd.destroyShaderModule(app.device, app.shader_module, null);

        for (app.device_memories.items) |*mem| {
            app.vkd.freeMemory(app.device, mem.*, null);
        }

        for (app.device_buffers.items) |*buf| {
            app.vkd.destroyBuffer(app.device, buf.*, null);
        }

        app.vkd.destroyDevice(app.device, null);
        app.vki.destroyInstance(app.instance, null);
        app.log(.info, "Destroyed Vulkan instance", .{});

        glfw.terminate();
        app.log(.debug, "Terminated GLFW", .{});

        app.allocator.free(app.instance_extensions);
        app.device_memories.deinit();
        app.device_buffers.deinit();
    }

    pub fn run(app: *const Self) !void {
        try command.submitWork(app);
    }
    
    pub fn getData(app: *const Self, buf: anytype, index: usize, T: type) !void {
        const dev_mem = app.device_memories.items[index];
        const shdr_mem = app.shared_memories[index];

        const buffer_slice = @as([*]T, @ptrCast(@alignCast(
            try app.vkd.mapMemory(app.device, dev_mem, 0, shdr_mem.size(), .{})
        )))[0..shdr_mem.elem_num];

        @memcpy(buf, buffer_slice);

        app.vkd.unmapMemory(app.device, dev_mem);
    }

    pub fn getDataAlloc(app: *const Self, allocator: Allocator, index: usize, T: type) ![]T {
        const buf = try allocator.alloc(T, app.shared_memories[index].elem_num);

        try app.getData(buf, index, T);

        return buf;
    }

    pub fn log(app: *const Self, level: std.log.Level, comptime format: []const u8, args: anytype) void {
        if (app.debug_mode) {
            switch (level) {
                .debug => std.log.debug(format, args),
                .info => std.log.info(format, args),
                .warn => std.log.info(format, args),
                .err => std.log.err(format, args),
            }
        }
    }
};
