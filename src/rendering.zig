const std = @import("std");
const c = @import("c");
const ecs = @import("ecs.zig");
const math = @import("math.zig");
const img = @import("img.zig");
const World = @import("ecs.zig").World;
const out_of_memory = ecs.out_of_memory;
const ColorMode = img.ColorMode;
const RenderCommand = struct {
    mesh_id: usize,
    material_id: usize,
    model_matrix: [16]f32
};

pub const Camera = struct {
    position: @Vector(3, f32),

    pub fn init(position: @Vector(3, f32)) Camera {
        return .{
            .position = position
        };
    }

    pub fn getViewMatrix(self: *Camera) math.Matrix4(f32) {
        const translation = math.Matrix4(f32).init(.{
            .{ 1.0, 0.0, 0.0, 0.0 },
            .{ 0.0, 1.0, 0.0, 0.0 },
            .{ 0.0, 0.0, 1.0, 0.0 },
            .{ -self.position[0], -self.position[1], -self.position[2], 1.0 }
        });

        const rotation = math.Matrix4(f32).init(.{
            .{ 0.707106, -0.408248,  0.577350, 0 },
            .{ 0.707106,  0.408248, -0.577350, 0 },
            .{ 0.0,       0.816496,  0.577350, 0 },
            .{ 0.0, 0.0, 0.0, 1.0 }
        });

        return translation.multiply(rotation);
    }
};

pub const Renderer = struct {
    allocator: std.mem.Allocator,
    camera: *Camera,
    window: *c.struct_GLFWwindow,
    render_queue: std.ArrayList(RenderCommand),
    program_id: u32,
    model_matrix_loc: i32,
    view_matrix_loc: i32,
    proj_matrix_loc: i32,
    has_texture_loc: i32,
    texture_loc: i32,
    color_loc: i32,

    pub fn init(allocator: std.mem.Allocator, camera: *Camera) Renderer {
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

        // Shader variables will belong to material in the future
        const model_matrix_loc = c.glGetUniformLocation(program_id, "u_ModelMatrix");
        const view_matrix_loc = c.glGetUniformLocation(program_id, "u_ViewMatrix");
        const proj_matrix_loc = c.glGetUniformLocation(program_id, "u_ProjMatrix");
        const has_texture_loc = c.glGetUniformLocation(program_id, "u_HasTexture");
        const texture_loc = c.glGetUniformLocation(program_id, "u_Texture");
        const color_loc = c.glGetUniformLocation(program_id, "u_Color");

        // TODO: error handling
        std.log.info("Shader compilation complete.", .{});

        const render_queue = std.ArrayList(RenderCommand).initCapacity(allocator, 64) catch @panic(out_of_memory);

        return .{
            .allocator = allocator,
            .camera = camera,
            .window = window,
            .render_queue = render_queue,
            .program_id = program_id,
            .model_matrix_loc = model_matrix_loc,
            .view_matrix_loc = view_matrix_loc,
            .proj_matrix_loc = proj_matrix_loc,
            .has_texture_loc = has_texture_loc,
            .texture_loc = texture_loc,
            .color_loc = color_loc
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

    pub fn draw(self: *Renderer, material_store: *ecs.MaterialStore, mesh_store: *ecs.MeshStore, texture_store: *ecs.TextureStore) void {
        c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);
        c.glUseProgram(self.program_id);
        var view_matrix = self.camera.getViewMatrix();

        const width: i32 = 16;
        const height: i32 = 9;
        //c.glfwGetWindowSize(self.window, &width, &height);

        var proj_matrix = [16]f32 {
            2.0 / @as(f32, @floatFromInt(width)), 0.0, 0.0, 0.0,
            0.0, 2.0 / @as(f32, @floatFromInt(height)), 0.0, 0.0,
            0.0, 0.0, 1.0, 0.0,
            0.0, 0.0, 0.0, 1.0
        };

        for (self.render_queue.items) |cmd| {
            const mesh = mesh_store.get(cmd.mesh_id);
            const material = material_store.get(cmd.material_id);
            const maybe_texture = if (material.texture_id) |texture_id| texture_store.get(texture_id) else null;

            // Assign uniforms
            c.glUniform1i(self.has_texture_loc, if (material.texture_id != null) 1 else 0);
            c.glUniform4fv(self.color_loc, 1, &[_]f32{ material.color.r, material.color.g, material.color.b, material.color.a });
            c.glUniformMatrix4fv(self.model_matrix_loc, 1, c.GL_FALSE, &cmd.model_matrix);
            c.glUniformMatrix4fv(self.view_matrix_loc, 1, c.GL_FALSE, &view_matrix.toArray() );
            c.glUniformMatrix4fv(self.proj_matrix_loc, 1, c.GL_FALSE, &proj_matrix );

            if (maybe_texture) |texture| {
                c.glActiveTexture(c.GL_TEXTURE0);
                c.glBindTexture(c.GL_TEXTURE_2D, texture.texture_id);
                c.glUniform1i(self.texture_loc, 0);
            }

            c.glBindVertexArray(mesh.vao);
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
            .mesh_id = mesh.mesh_id,
            .material_id = mesh.material_id
        }) catch @panic(out_of_memory);
    }

    pub fn createFloorBuffer(_: *Renderer) struct { u32, u32, u32, i32 } {
        var vao: u32 = 0;
        var vbo: u32 = 0;
        var ebo: u32 = 0;

        const vertex_array = [_]f32 {
            0.0, 0.0, 0.0,   0.0, 0.0,
            1.0, 0.0, 0.0,   1.0, 0.0,
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

    /// Registers a texture_id for the data. No longer need the raw image after this is called. Returns the GL texture id
    pub fn createTexture(_: *Renderer, texture: TextureData) u32 {
        var texture_id: u32 = 0;
        c.glGenTextures(1, &texture_id);
        c.glBindTexture(c.GL_TEXTURE_2D, texture_id);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_REPEAT);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_REPEAT);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);

        const format = if (texture.color_mode == ColorMode.RGB) c.GL_RGB else c.GL_RGBA;
        c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, 1);
        c.glTexImage2D(
            c.GL_TEXTURE_2D,
            0,
            @intCast(format),
            @intCast(texture.width),
            @intCast(texture.height),
            0,
            @intCast(format),
            c.GL_UNSIGNED_BYTE,
            texture.data.ptr
        );

        c.glBindTexture(c.GL_TEXTURE_2D, 0);

        return texture_id;
    }
};

pub const TextureData = struct {
    data: []u8,
    width: usize,
    height: usize,
    color_mode: ColorMode
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
\\  uniform mat4 u_ViewMatrix;
\\  uniform mat4 u_ProjMatrix;
\\  layout (location = 0) in vec3 position;
\\  layout (location = 1) in vec2 uv;
\\  out vec2 TexCoord;
\\  void main() {
\\      vec4 screenPos = u_ProjMatrix * u_ViewMatrix * u_ModelMatrix * vec4(position, 1.0);
\\      gl_Position = vec4(screenPos.xy, 0.0, 1.0);
\\      TexCoord = uv;
\\  }
;

const ft_shader =
\\  #version 330 core
\\  layout (location = 0) out vec4 color;
\\  uniform sampler2D u_Texture;
\\  uniform int u_HasTexture;
\\  uniform vec4 u_Color;
\\  in vec2 TexCoord;
\\  void main() {
\\      vec4 finalColor = u_Color;
\\      if (u_HasTexture == 1) {
\\          finalColor *= texture(u_Texture, TexCoord);
\\      }
\\      color = finalColor;
\\  }
;

const mat4_identity = [_]f32 {
    1.0, 0.0, 0.0, 0.0,
    0.0, 1.0, 0.0, 0.0,
    0.0, 0.0, 1.0, 0.0,
    0.0, 0.0, 0.0, 1.0
};
