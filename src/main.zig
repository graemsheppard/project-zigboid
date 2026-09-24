const std = @import("std");
const Io = std.Io;
const c = @import("c");
const math = @import("math.zig");
const img = @import("img.zig");
const rendering = @import("rendering.zig");
const ecs = @import("ecs.zig");
const control = @import("control.zig");
const World = ecs.World;
const Renderer = rendering.Renderer;
const Camera = rendering.Camera;
const TransformComponent = ecs.TransformComponent;
const SpriteComponent = ecs.SpriteComponent;
const Vector3 = math.Vector3;
const Color = ecs.Color;
const ControlSystem = control.ControlSystem;
const GameState = ecs.GameState;

const frame_rate: i64 = 30;
const frame_duration_ns: i64 = 1_000_000_000 / frame_rate;

pub fn main(init: std.process.Init) !void {
    const arena_allocator = init.arena.allocator();
    var game_state = GameState {
        .window = undefined,
        .player_id = undefined
    };

    var png = img.PNG.parse(init.gpa, init.io, "snail_plte.png") catch {
        std.process.exit(1);
    };

    // Initialize stores
    var material_store = ecs.MaterialStore.init(arena_allocator);
    var mesh_store = ecs.MeshStore.init(arena_allocator);
    var texture_store = ecs.TextureStore.init(arena_allocator);

    var world = World.init(init.gpa);
    defer world.deinit();

    // Initialize systems
    var camera = Camera.init(.{ 0, 0, 0 });
    var renderer = Renderer.init(init.gpa, &camera, &game_state);
    var control_system = ControlSystem {};
    defer renderer.deinit();

    const snail_id = texture_store.registerTexture(.{
        .texture_id = renderer.createTexture(.{
            .color_mode = png.color_mode,
            .width = png.ihdr.width,
            .height = png.ihdr.height,
            .data = png.raw_image
        })
    });
    png.deinit();

    const mat_id = material_store.registerMaterial(.{
        .color = .white(),
        .texture_id = snail_id
    });

    const player_id = world.spawnEntity();
    game_state.player_id = player_id;
    world.addComponent(player_id, TransformComponent {
        .position = Vector3(f32).zero(),
        .rotation = Vector3(f32).zero(),
        .scale = Vector3(f32).one()
    });

    const floor_vao, const floor_vbo, const floor_ebo, const index_count = renderer.createFloorBuffer();
    const floor_mesh_id = mesh_store.registerMesh(floor_vao, floor_vbo, floor_ebo, index_count);

    const transform = TransformComponent {
        .position = Vector3(f32).zero(),
        .rotation = Vector3(f32).zero(),
        .scale = Vector3(f32).one()
    };

    const floor_mesh = ecs.MeshComponent {
        .material_id = mat_id,
        .mesh_id = floor_mesh_id
    };

    const floor_1 = world.spawnEntity();
    world.addComponent(floor_1, transform);
    world.addComponent(floor_1, floor_mesh);

    const floor_2 = world.spawnEntity();
    world.addComponent(floor_2, TransformComponent { .position = .{ .x = -1.0, .y = 0.0, .z = 0.0 }, .rotation = Vector3(f32).zero(), .scale = Vector3(f32).one() });
    world.addComponent(floor_2, floor_mesh);

    const floor_3 = world.spawnEntity();
    world.addComponent(floor_3, TransformComponent { .position = .{ .x = -1.0, .y = -1.0, .z = 0.0 }, .rotation = Vector3(f32).zero(), .scale = Vector3(f32).one() });
    world.addComponent(floor_3, floor_mesh);

    // The main game loop
    while (!renderer.shouldClose()) {
        const frame_start = std.Io.Clock.awake.now(init.io);
        
        const maybe_floor_3_transform = world.getComponent(TransformComponent, floor_3);
        if (maybe_floor_3_transform) |floor_3_transform| {
            floor_3_transform.position.x += 0.01;
            floor_3_transform.position.y += 0.01;
        }

        // Testing only
        const player_pos = world.getComponent(TransformComponent, player_id) orelse @panic("aa");
        camera.position = .{ player_pos.position.x, player_pos.position.y, player_pos.position.z };

        control_system.update(&world, &game_state);
        renderer.update(&world);

        renderer.draw(&material_store, &mesh_store, &texture_store);

        // Cap the frame rate
        const elapsed = frame_start.untilNow(init.io, .awake).toNanoseconds();
        if (elapsed < frame_duration_ns) {
            const surplus = frame_duration_ns - elapsed;
            try std.Io.sleep(init.io, .{ .nanoseconds = surplus }, .awake);
        }

    }

    std.log.info("Program exited without error", .{});
}

