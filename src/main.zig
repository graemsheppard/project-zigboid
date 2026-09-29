const std = @import("std");
const Io = std.Io;
const c = @import("c");
const math = @import("math.zig");
const img = @import("img.zig");
const rendering = @import("rendering.zig");
const ecs = @import("ecs.zig");
const control = @import("control.zig");
const physics = @import("physics.zig");
const World = ecs.World;
const Camera = rendering.Camera;
const TransformComponent = ecs.TransformComponent;
const InputComponent = ecs.InputComponent;
const SpriteComponent = ecs.SpriteComponent;
const MeshComponent = ecs.MeshComponent;
const PhysicsBodyComponent = ecs.PhysicsBodyComponent;
const GameState = ecs.GameState;
const Vector3 = math.Vector3;

const frame_rate: i64 = 30;
const frame_duration_ns: i64 = 1_000_000_000 / frame_rate;

pub fn main(init: std.process.Init) !void {
    const arena_allocator = init.arena.allocator();
    var game_state = GameState {
        .window = undefined,
        .player_id = undefined,
        .dt = @as(f32, @floatFromInt(frame_duration_ns)) / 1_000_000_000
    };

    var png = img.PNG.parse(init.gpa, init.io, "dirt.png") catch {
        std.process.exit(1);
    };

    var wall = img.PNG.parse(init.gpa, init.io, "wood_wall.png") catch {
        std.process.exit(1);
    };

    // Initialize stores
    var material_store = ecs.MaterialStore.init(arena_allocator);
    var mesh_store = ecs.MeshStore.init(arena_allocator);
    var texture_store = ecs.TextureStore.init(arena_allocator);

    var world = World.init(init.gpa);
    defer world.deinit();

    // Initialize systems
    var renderer = rendering.Renderer.init(init.gpa, &game_state);
    defer renderer.deinit();
    var control_system = control.ControlSystem {};
    var physics_system = physics.PhysicsSystem.init(init.gpa);
    var collision_system = physics.CollisionSystem.init(init.gpa);

    const snail_texture_id = texture_store.registerTexture(.{
        .texture_id = renderer.createTexture(.{
            .color_mode = wall.color_mode,
            .width = wall.ihdr.width,
            .height = wall.ihdr.height,
            .data = wall.raw_image
        })
    });
    wall.deinit();

    const dirt_texture_id = texture_store.registerTexture(.{
        .texture_id = renderer.createTexture(.{
            .color_mode = png.color_mode,
            .width = png.ihdr.width,
            .height = png.ihdr.height,
            .data = png.raw_image
        })
    });
    png.deinit();

    const snail_mat_id = material_store.registerMaterial(.{
        .color = math.vector4_one,
        .texture_id = snail_texture_id 
    });

    const dirt_mat_id = material_store.registerMaterial(.{
        .color = math.vector4_one,
        .texture_id = dirt_texture_id 
    });

    const floor_vao, const floor_vbo, const floor_ebo, const index_count = renderer.createFloorBuffer();
    const floor_mesh_id = mesh_store.registerMesh(floor_vao, floor_vbo, floor_ebo, index_count);

    const wall_vao, const wall_vbo, const wall_ebo, const wall_index_count = renderer.createWallBuffer();
    const wall_mesh_id = mesh_store.registerMesh(wall_vao, wall_vbo, wall_ebo, wall_index_count);

    const floor_mesh = MeshComponent {
        .material_id = dirt_mat_id,
        .mesh_id = floor_mesh_id
    };

    const wall_mesh = MeshComponent {
        .material_id = snail_mat_id,
        .mesh_id = wall_mesh_id
    };

    const player_id = world.spawnEntity();
    game_state.player_id = player_id;
    world.addComponent(player_id, InputComponent { .direction = .{ 0.0, 0.0, 0.0 }});
    world.addComponent(player_id, wall_mesh);
    world.addComponent(player_id, PhysicsBodyComponent {
        .acceleration = math.vector3_zero,
        .velocity = math.vector3_zero,
        .mass = 80
    });

    world.addComponent(player_id, ecs.ColliderComponent {
        .sphere = .{
            .radius = 1,
            .offset = .{ 1, 0, 1 }
        }
    });

    world.addComponent(player_id, TransformComponent {
        .position = .{ 0.0, 0.0, 0.0 },
        .rotation = math.vector3_zero,
        .scale = math.vector3_one
    });

    // Create some floors
    for (0..4) |y_idx| {
        const y_pos: f32 = @floatFromInt(@as(i32, @intCast(y_idx)) - 2);
        for (0..4) |x_idx| {
            const x_pos: f32 = @floatFromInt(@as(i32, @intCast(x_idx)) - 2);
            const floor_id = world.spawnEntity();
            if (x_idx == 0 and y_idx == 0) {
                world.addComponent(floor_id, ecs.ColliderComponent {
                    .triangle = .{
                        .points =  .{ .{ -4, -4, 0 }, .{ 4, -4, 0 }, .{ 0, 4, 0 } }
                    }
                });
            }
            world.addComponent(floor_id, TransformComponent { .position = .{ x_pos, y_pos, 0.0 }, .rotation = math.vector3_zero, .scale = math.vector3_one });
            world.addComponent(floor_id, floor_mesh);
        }
    }

    // Create some walls
    for (0..4) |idx| {
        const x_pos: f32 = @floatFromInt(@as(i32, @intCast(idx)) - 2);
        const wall_id = world.spawnEntity();
        world.addComponent(wall_id, TransformComponent { .position = .{ x_pos, 2.0, 0.0}, .rotation = math.vector3_zero, .scale = math.vector3_one });
        world.addComponent(wall_id, wall_mesh);
    }


    // The main game loop
    while (!renderer.shouldClose()) {
        const frame_start = std.Io.Clock.awake.now(init.io);
        
        physics_system.update(&world, &game_state);
        collision_system.update(&world, &game_state);
        control_system.update(&world, &game_state);
        renderer.update(&world, &game_state);

        renderer.draw(&material_store, &mesh_store, &texture_store);

        // Cap the frame rate
        const elapsed = frame_start.untilNow(init.io, .awake).toNanoseconds();
        if (elapsed < frame_duration_ns) {
            const surplus = frame_duration_ns - elapsed;
            try std.Io.sleep(init.io, .{ .nanoseconds = surplus }, .awake);
            game_state.dt = @as(f32, @floatFromInt(frame_duration_ns)) / 1_000_000_000;
        } else {
            game_state.dt = @as(f32, @floatFromInt(elapsed)) / 1_000_000_000;
        }
    }

    std.log.info("Program exited without error", .{});
}

