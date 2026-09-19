const std = @import("std");
const Vector3 = @import("math.zig").Vector3;

const initial_capacity = 64;
pub const out_of_memory = "Program ran out of memory!";

pub const ComponentType = enum(usize) {
    transform = 0,
    sprite = 1
};

const type_count = @typeInfo(ComponentType).@"enum".fields.len;

/// A container for all entities and components
pub const World = struct {
    next_entity_id: u32,
    allocator: std.mem.Allocator,
    transform_list: std.ArrayList(?TransformComponent),
    sprite_list: std.ArrayList(?SpriteComponent),
    mesh_list: std.ArrayList(?MeshComponent),


    pub fn init(allocator: std.mem.Allocator) World {

        return .{
            .next_entity_id = 1,
            .allocator = allocator,
            .transform_list = std.ArrayList(?TransformComponent).initCapacity(allocator, initial_capacity) catch @panic(out_of_memory),
            .sprite_list = std.ArrayList(?SpriteComponent).initCapacity(allocator, initial_capacity) catch @panic(out_of_memory),
            .mesh_list = std.ArrayList(?MeshComponent).initCapacity(allocator, initial_capacity) catch @panic(out_of_memory)
        };
    }

    pub fn deinit(self: *World) void {
        self.transform_list.deinit(self.allocator);
        self.sprite_list.deinit(self.allocator);
        self.mesh_list.deinit(self.allocator);
    }

    /// Given a component type T returns a pointer to its appropriate component array
    pub fn getComponentArray(self: *World, comptime T: type) *std.ArrayList(?T) {
        if (T == SpriteComponent) return &self.sprite_list;
        if (T == TransformComponent) return &self.transform_list;
        if (T == MeshComponent) return &self.mesh_list;
        @compileError("Not a supported component type: " ++ @typeName(T));
    } 

    /// Spawns an entity, returning its id and allocating space for the components
    pub fn spawnEntity(self: *World) u32 {
        const entity_id = self.next_entity_id;
        self.next_entity_id += 1;

        // Ensure array lists are large enough to support the id
        self.transform_list.append(self.allocator, null) catch @panic(out_of_memory);
        self.sprite_list.append(self.allocator, null) catch @panic(out_of_memory);
        self.mesh_list.append(self.allocator, null) catch @panic(out_of_memory);

        return entity_id;
    }

    /// Add a component to the entity
    pub fn addComponent(self: *World, entity_id: u32, component: anytype) void {
        const T = @TypeOf(component);
        var comp_list = self.getComponentArray(T);
        comp_list.insert(self.allocator, entity_id - 1, component) catch @panic(out_of_memory);
    }

    /// Removes a component from the entity
    pub fn removeComponent(self: *World, entity_id: u32, T: type) void {
        var comp_list = self.getComponentArray(T);
        comp_list.items[entity_id - 1] = null;
    }

    /// Returns the ids of entities that have all of the provided components. Caller owns the memory.
    pub fn queryEntitiesByComponents(self: *World, allocator: std.mem.Allocator, args: anytype) []usize {
        var list = std.ArrayList(usize).initCapacity(allocator, 16) catch @panic(out_of_memory);
        for (0..self.next_entity_id) |idx| {
            var exists = true;
            inline for (args) |T| {
                const comp_list = self.getComponentArray(T);
                if (comp_list.items[idx] == null) {
                    exists = false;
                    break;
                }
            }

            if (exists) {
                list.append(allocator, idx + 1) catch @panic(out_of_memory);
            }
        }
        return list.toOwnedSlice(allocator) catch @panic(out_of_memory);
    }

    /// Returns the components for the requested entities. Component must exist. Caller owns the memory
    pub fn getComponentsForEntities(self: *World, allocator: std.mem.Allocator, comptime T: type, entity_ids: []const usize) []?T {
        const result = allocator.alloc(?T, entity_ids.len) catch @panic(out_of_memory);
        const comp_list = self.getComponentArray(T);
        for (entity_ids, 0..) |entity_id, idx| {
            result[idx] = comp_list.items[entity_id - 1];
        }
        return result;
    }

    /// Returns the component for the entity by type
    pub fn getComponent(self: *World, comptime T: type, entity_id: usize) ?*T {
        const comp_list = self.getComponentArray(T);
        const maybe_comp = &comp_list.items[entity_id - 1];
        return if (maybe_comp.*) |*comp| comp else null;
    }
};

pub const TransformComponent = struct {
    position: Vector3(f32),
    rotation: Vector3(f32),
    scale: Vector3(f32)
};

pub const SpriteComponent = struct {
    texture_id: u32,
    color: Color
};

pub const MeshComponent = struct {
    material_id: usize,
    mesh_id: usize
};

pub const Material = struct {
    // should also have the shader id
    texture_id: ?usize,
    color: Color
};

pub const Texture = struct {
    texture_id: u32
};

pub const Mesh = struct {
    vao: u32,
    vbo: u32,
    ebo: u32,
    index_count: i32
};

/// Store meshes for fast lookup
pub const MeshStore = struct {
    meshes: std.ArrayList(Mesh),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MeshStore {
        const meshes = std.ArrayList(Mesh).initCapacity(allocator, 16) catch @panic(out_of_memory);
        return .{
            .allocator = allocator,
            .meshes = meshes 
        };
    }

    pub fn deinit(self: *MeshStore) void {
        self.meshes.deinit(self.allocator);
    }

    /// Add a mesh to the store and return its id.
    pub fn registerMesh(self: *MeshStore, vao: u32, vbo: u32, ebo: u32, index_count: i32) usize {
        self.meshes.append(self.allocator, .{ .vao = vao, .vbo = vbo, .ebo = ebo, .index_count = index_count }) catch @panic(out_of_memory);
        return self.meshes.items.len - 1;
    }

    pub fn get(self: *MeshStore, mesh_id: usize) Mesh {
        return self.meshes.items[mesh_id];
    }
};


/// Store materials for fast lookup
pub const MaterialStore = struct {
    materials: std.ArrayList(Material),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MaterialStore {
        const materials = std.ArrayList(Material).initCapacity(allocator, 16) catch @panic(out_of_memory);
        return .{
            .allocator = allocator,
            .materials = materials
        };
    }

    pub fn deinit(self: *MaterialStore) void {
        self.materials.deinit(self.allocator);
    }

    /// Add a material to the store and return its id.
    pub fn registerMaterial(self: *MaterialStore, material: Material) usize {
        self.materials.append(self.allocator, material) catch @panic(out_of_memory);
        return self.materials.items.len - 1;
    }

    pub fn get(self: *MaterialStore, material_id: usize) Material {
        return self.materials.items[material_id];
    }
};

/// Store textures for fast lookup. Note the lookup id is not currently the same as the GL texture id.
pub const TextureStore = struct {
    textures: std.ArrayList(Texture),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TextureStore {
        const textures = std.ArrayList(Texture).initCapacity(allocator, 16) catch @panic(out_of_memory);
        return .{
            .allocator = allocator,
            .textures = textures 
        };
    }

    pub fn deinit(self: *TextureStore) void {
        self.textures.deinit(self.allocator);
    }

    /// Add a texture to the store and return its id.
    pub fn registerTexture(self: *TextureStore, texture: Texture) usize {
        self.textures.append(self.allocator, texture) catch @panic(out_of_memory);
        return self.textures.items.len - 1;
    }

    pub fn get(self: *TextureStore, texture_id: usize) Texture {
        return self.textures.items[texture_id];
    }
};

pub const Color = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,

    pub fn white() Color {
        return .{
            .r = 1.0,
            .g = 1.0,
            .b = 1.0,
            .a = 1.0
        };
    }
};
