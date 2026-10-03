const std = @import("std");
const Window = @import("c").struct_GLFWwindow;

const initial_capacity = 64;
pub const out_of_memory = "Program ran out of memory!";

/// For storing persistent and frequently accessed entities and state that are shared between systems
pub const GameState = struct {
    window: *Window,
    player_id: usize,
    dt: f32
};

/// A container for all entities and components
pub const World = struct {
    next_entity_id: u32,
    allocator: std.mem.Allocator,
    transform_list: std.ArrayList(?TransformComponent),
    sprite_list: std.ArrayList(?SpriteComponent),
    mesh_list: std.ArrayList(?MeshComponent),
    input_list: std.ArrayList(?InputComponent),
    physics_body_list: std.ArrayList(?PhysicsBodyComponent),
    collider_list: std.ArrayList(?ColliderComponent),
    animation_list: std.ArrayList(?AnimationComponent),

    pub fn init(allocator: std.mem.Allocator) World {
        return .{
            .next_entity_id = 1,
            .allocator = allocator,
            .transform_list = std.ArrayList(?TransformComponent).initCapacity(allocator, initial_capacity) catch @panic(out_of_memory),
            .sprite_list = std.ArrayList(?SpriteComponent).initCapacity(allocator, initial_capacity) catch @panic(out_of_memory),
            .mesh_list = std.ArrayList(?MeshComponent).initCapacity(allocator, initial_capacity) catch @panic(out_of_memory),
            .input_list = std.ArrayList(?InputComponent).initCapacity(allocator, initial_capacity) catch @panic(out_of_memory),
            .physics_body_list = std.ArrayList(?PhysicsBodyComponent).initCapacity(allocator, initial_capacity) catch @panic(out_of_memory),
            .collider_list = std.ArrayList(?ColliderComponent).initCapacity(allocator, initial_capacity) catch @panic(out_of_memory),
            .animation_list = std.ArrayList(?AnimationComponent).initCapacity(allocator, initial_capacity) catch @panic(out_of_memory)
        };
    }

    pub fn deinit(self: *World) void {
        self.transform_list.deinit(self.allocator);
        self.sprite_list.deinit(self.allocator);
        self.mesh_list.deinit(self.allocator);
        self.input_list.deinit(self.allocator);
        self.physics_body_list.deinit(self.allocator);
        self.collider_list.deinit(self.allocator);
        self.animation_list.deinit(self.allocator);
    }

    /// Given a component type T returns a pointer to its appropriate component array
    pub fn getComponentArray(self: *World, comptime T: type) *std.ArrayList(?T) {
        if (T == SpriteComponent) return &self.sprite_list;
        if (T == TransformComponent) return &self.transform_list;
        if (T == MeshComponent) return &self.mesh_list;
        if (T == InputComponent) return &self.input_list;
        if (T == PhysicsBodyComponent) return &self.physics_body_list;
        if (T == ColliderComponent) return &self.collider_list;
        if (T == AnimationComponent) return &self.animation_list;
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
        self.input_list.append(self.allocator, null) catch @panic(out_of_memory);
        self.physics_body_list.append(self.allocator, null) catch @panic(out_of_memory);
        self.collider_list.append(self.allocator, null) catch @panic(out_of_memory);
        self.animation_list.append(self.allocator, null) catch @panic(out_of_memory);

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

    /// Same as queryEntitiesByComponents but takes a list of entity ids to further refine
    pub fn queryKnownEntitiesByComponents(self: *World, allocator: std.mem.Allocator, known_ids: []usize, args: anytype) []usize {
        var list = std.ArrayList(usize).initCapacity(allocator, 16) catch @panic(out_of_memory);
        for (known_ids) |entity_id| {
            var exists = true;
            inline for (args) |T| {
                const comp_list = self.getComponentArray(T);
                if (comp_list.items[entity_id - 1] == null) {
                    exists = false;
                    break;
                }
            }

            if (exists) {
                list.append(allocator, entity_id) catch @panic(out_of_memory);
            }
        }
        return list.toOwnedSlice(allocator) catch @panic(out_of_memory);
    }


    /// Returns the components for the requested entities. Component must exist. Caller owns the memory
    pub fn getComponentsForEntities(self: *World, allocator: std.mem.Allocator, comptime T: type, entity_ids: []const usize) []?*T {
        const result = allocator.alloc(?*T, entity_ids.len) catch @panic(out_of_memory);
        const comp_list = self.getComponentArray(T);
        for (entity_ids, 0..) |entity_id, idx| {
            const maybe_comp = &comp_list.items[entity_id - 1];
            result[idx] = if (maybe_comp.*) |*comp| comp else null;
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

pub const transform_default = TransformComponent {
    .position = .{ 0.0, 0.0, 0.0 },
    .rotation = .{ 0.0, 0.0, 0.0 },
    .scale = .{ 1.0, 1.0, 1.0 }
};

pub const SphereColliderComponent = struct {
    offset: @Vector(3, f32),
    radius: f32
};

pub const TriangleColliderComponent = struct {
    points: [3]@Vector(3, f32)
};

pub const ColliderType = enum {
    sphere,
    triangle
};

pub const ColliderComponent = union(ColliderType) {
    const Self = @This();
    sphere: SphereColliderComponent,
    triangle: TriangleColliderComponent
};

pub const PhysicsBodyComponent = struct {
    acceleration: @Vector(3, f32),
    velocity: @Vector(3, f32),
    mass: f32
};

pub const TransformComponent = struct {
    position: @Vector(3, f32),
    rotation: @Vector(3, f32),
    scale: @Vector(3, f32)
};

pub const SpriteComponent = struct {
    texture_id: u32,
    color: @Vector(4, f32)
};

pub const MeshComponent = struct {
    material_id: usize,
    mesh_id: usize
};

pub const InputComponent = struct {
    direction: @Vector(3, f32)
};

pub const AnimationComponent = struct {
    elapsed: f32,
    animation_id: usize,
    current_frame: usize
};

pub const Material = struct {
    // should also have the shader id
    texture_id: ?u32,
    color: @Vector(4, f32)
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

pub const Animation = struct {
    continuous: bool,
    duration: f32,
    keyframes: []const f32,
    textures: []const u32 
};

/// Store animations for fast lookup
pub const AnimationStore = struct {
    animations: std.ArrayList(Animation),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) AnimationStore {
        const animations = std.ArrayList(Animation).initCapacity(allocator, 16) catch @panic(out_of_memory);
        return .{
            .allocator = allocator,
            .animations = animations 
        };
    }

    pub fn deinit(self: *AnimationStore) void {
        self.animations.deinit(self.allocator);
    }

    /// Add an animation to the store and return its id.
    pub fn registerAnimation(self: *AnimationStore, animation: Animation) usize {
        self.animations.append(self.allocator, animation) catch @panic(out_of_memory);
        return self.animations.items.len - 1;
    }

    pub fn get(self: *AnimationStore, animation_id: usize) Animation {
        return self.animations.items[animation_id];
    }
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

