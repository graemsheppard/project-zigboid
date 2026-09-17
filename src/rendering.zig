const std = @import("std");
const c = @import("c");
const ecs = @import("ecs.zig");
const World = @import("ecs.zig").World;
const out_of_memory = ecs.out_of_memory;
const RenderCommand = struct {
    mesh_id: usize,
    model_matrix: [16]f32
};

pub const Renderer = struct {
    allocator: std.mem.Allocator,
    window: *c.struct_GLFWwindow,
    render_queue: std.ArrayList(RenderCommand),
    program_id: u32,
    model_matrix_id: i32,


    pub fn init(allocator: std.mem.Allocator) Renderer {
        // Init window
        if (c.glfwInit() == 0) {
            std.log.err("Failed to intialize GLFW. Exiting...", .{});
            std.process.exit(1);
        }

        std.log.info("GLFW Initialized", .{});

        // Window parameters
        c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 3);
        c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 3);
        c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);
        c.glfwWindowHint(c.GLFW_OPENGL_FORWARD_COMPAT, c.GLFW_TRUE);
        c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_TRUE);

        const window = c.glfwCreateWindow(1240, 720, "Project Zigboid", null, null) orelse {
            std.log.err("Failed to create window. Exiting...", .{});
            std.process.exit(1);
        };

        c.glfwMakeContextCurrent(window);
        if (c.gladLoadGLLoader(@ptrCast(&c.glfwGetProcAddress)) == 0) {
            std.log.err("Failed to load GLAD. Exiting...", .{});
            std.process.exit(1);
        }

        std.log.info("GLAD Initialized", .{});

        c.glClearColor(0, 0, 0.6, 0);


        std.log.info("Loading shaders...", .{});
        const vt_compile_result = createShader(allocator, c.GL_VERTEX_SHADER, vt_shader);
        const vt_shader_id = vt_compile_result.shader_id;
        defer c.glDeleteShader(vt_shader_id);

        if (vt_compile_result.err) |err| {
            std.log.err("{s}", .{err});
            std.process.exit(1);
        }

        const ft_compile_result = createShader(allocator, c.GL_FRAGMENT_SHADER, ft_shader);
        const ft_shader_id = ft_compile_result.shader_id;
        defer c.glDeleteShader(ft_shader_id);

        if (ft_compile_result.err) |err| {
            std.log.err("{s}", .{err});
            std.process.exit(1);
        }

        const program_id = c.glCreateProgram();
        c.glAttachShader(program_id, vt_shader_id);
        c.glAttachShader(program_id, ft_shader_id);
        c.glLinkProgram(program_id);
        c.glValidateProgram(program_id);

        const model_matrix_id = c.glGetUniformLocation(program_id, "u_ModelMatrix");

        // TODO: error handling
        std.log.info("Shader compilation complete.", .{});

        const render_queue = std.ArrayList(RenderCommand).initCapacity(allocator, 64) catch @panic(out_of_memory);

        return .{
            .allocator = allocator,
            .window = window,
            .render_queue = render_queue,
            .program_id = program_id,
            .model_matrix_id = model_matrix_id
        };
    }

    pub fn deinit(self: *Renderer) void {
        c.glfwDestroyWindow(self.window);
        c.glfwTerminate();
        self.render_queue.deinit(self.allocator);
    }

    /// Wrapper for glfwWindowShouldClose
    pub fn shouldClose(self: *Renderer) bool {
        return c.glfwWindowShouldClose(self.window) != 0;
    }

    pub fn draw(self: *Renderer, _: *ecs.MaterialStore, mesh_store: *ecs.MeshStore) void {
        c.glClear(c.GL_COLOR_BUFFER_BIT);
        c.glUseProgram(self.program_id);
        for (self.render_queue.items) |cmd| {
            const mesh = mesh_store.get(cmd.mesh_id);
            c.glBindVertexArray(mesh.vao);
            c.glUniformMatrix4fv(self.model_matrix_id, 1, c.GL_FALSE, &cmd.model_matrix);
            c.glDrawElements(c.GL_TRIANGLES, mesh.index_count, c.GL_UNSIGNED_INT, null);
        }

        c.glfwSwapBuffers(self.window);
        c.glfwPollEvents();

        self.render_queue.clearRetainingCapacity();
    }

    /// Submits the drawable entities to the render queue
    pub fn update(self: *Renderer, world: *World) void {
        const entities_to_submit = world.queryEntitiesByComponents(self.allocator, .{ ecs.MeshComponent, ecs.TransformComponent });

        const transforms = world.getComponentsForEntities(self.allocator, ecs.TransformComponent, entities_to_submit);
        defer self.allocator.free(transforms);

        const meshes = world.getComponentsForEntities(self.allocator, ecs.MeshComponent, entities_to_submit);
        defer self.allocator.free(meshes);

        self.allocator.free(entities_to_submit);

        for (meshes, 0..) |maybe_mesh, idx| {
            const mesh = maybe_mesh orelse continue;
            const transform = transforms[idx] orelse continue;
            self.submit(transform, mesh);
        }

    }

    /// Calculates the model matrix
    pub fn submit(self: *Renderer, transform: ecs.TransformComponent, mesh: ecs.MeshComponent) void {
        const model_matrix = [_]f32 {
            transform.scale.x, 0.0, 0.0, 0.0,
            0.0, transform.scale.y, 0.0, 0.0,
            0.0, 0.0, transform.scale.z, 0.0,
            transform.position.x, transform.position.y, transform.position.z, 1.0
        };
        self.render_queue.append(self.allocator, .{
            .model_matrix = model_matrix,
            .mesh_id = mesh.mesh_id
        }) catch @panic(out_of_memory);
    }

    pub fn createFloorBuffer(_: *Renderer) struct { u32, u32, u32, i32 } {
        var vao: u32 = 0;
        var vbo: u32 = 0;
        var ebo: u32 = 0;

        const vertex_array = [_]f32 {
            0.0, 0.0, 0.0,   0.0, 0.0,
            1.0, 0.0, 0.0,   0.0, 1.0,
            1.0, 1.0, 0.0,   1.0, 1.0,
            0.0, 1.0, 0.0,   0.0, 1.0
        };

        const index_array = [_]u32 {
            0, 1, 2,
            2, 3, 0
        };

        // Initialization step
        c.glGenVertexArrays(1, &vao);
        c.glGenBuffers(1, &vbo);
        c.glGenBuffers(1, &ebo);

        // Binding step
        c.glBindVertexArray(vao);

        // Upload data to the vbo
        c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo);
        c.glBufferData(c.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(vertex_array)), &vertex_array, c.GL_STATIC_DRAW);

        // Upload data to the ebo
        c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, ebo);
        c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, @sizeOf(@TypeOf(index_array)), &index_array, c.GL_STATIC_DRAW);

        // Bind inputs
        c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, 5 * @sizeOf(f32), null);
        c.glEnableVertexAttribArray(0);

        c.glVertexAttribPointer(1, 2, c.GL_FLOAT, c.GL_FALSE, 5 * @sizeOf(f32), @ptrFromInt(3 * @sizeOf(f32)));
        c.glEnableVertexAttribArray(1);

        c.glBindVertexArray(0);

        return .{
            vao,
            vbo,
            ebo,
            index_array.len
        };
    }
};

/// Creates and compiles a shader of s_type given a string
fn createShader(allocator: std.mem.Allocator, s_type: u32, shader: []const u8) struct { err: ?[]const u8, shader_id: u32 } {
    const shader_id: u32 = c.glCreateShader(s_type);
    c.glShaderSource(shader_id, 1, @ptrCast(&shader), null);
    c.glCompileShader(shader_id);

    // Check for compilation error
    var compile_result: i32 = 0;
    var message: ?[]const u8 = null;

    c.glGetShaderiv(shader_id, c.GL_COMPILE_STATUS, &compile_result);

    if (compile_result == c.GL_FALSE) {
        var length: i32 = 0;
        c.glGetShaderiv(shader_id, c.GL_INFO_LOG_LENGTH, &length);
        if (allocator.alloc(u8, @intCast(@abs(length)))) |raw_message| {
            c.glGetShaderInfoLog(shader_id, @intCast(@abs(length)), &length, raw_message.ptr);
            message = raw_message;
        } else |_| {
            message = "Error too long to display.";
        }
    }

    return .{ .err = message, .shader_id = shader_id };
}

const vt_shader =
\\  #version 330 core
\\  uniform ivec2 u_WindowSize;
\\  uniform mat4 u_ModelMatrix;
\\  layout (location = 0) in vec3 position;
\\  layout (location = 1) in vec2 uv;
\\  void main() {
\\      vec2 cameraPos = vec2(0, 0);
\\      vec2 cameraDim = vec2(16, 9);
\\
\\      mat4 isoView = mat4(
\\          vec4( 0.707106, -0.408248,  0.577350, 0),
\\          vec4( 0.707106,  0.408248, -0.577350, 0),
\\          vec4( 0.0,       0.816496,  0.577350, 0),
\\          vec4( 0.0, 0.0, 0.0, 1.0)
\\      );
\\      
\\      vec4 screenPos = isoView * u_ModelMatrix * vec4(position, 1.0);
\\      gl_Position = vec4(screenPos.xy, 0.0, 1.0);
\\  }
;

const ft_shader =
\\  #version 330 core
\\  layout (location = 0) out vec4 color;
\\  void main() {
\\      color = vec4(1.0, 1.0, 1.0, 1.0);
\\  }
;

const mat4_identity = [_]f32 {
    1.0, 0.0, 0.0, 0.0,
    0.0, 1.0, 0.0, 0.0,
    0.0, 0.0, 1.0, 0.0,
    0.0, 0.0, 0.0, 1.0
};
