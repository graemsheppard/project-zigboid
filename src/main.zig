const std = @import("std");
const Io = std.Io;
const c = @import("c");
const math = @import("math.zig");
const rendering = @import("rendering.zig");
const ecs = @import("ecs.zig");
const World = ecs.World;
const Renderer = rendering.Renderer;
const TransformComponent = ecs.TransformComponent;
const SpriteComponent = ecs.SpriteComponent;
const Vector3 = math.Vector3;
const Color = ecs.Color;

const frame_rate: i64 = 30;
const frame_duration_ns: i64 = 1_000_000_000 / frame_rate;

pub fn main(init: std.process.Init) !void {
    const arena_allocator = init.arena.allocator();

    // Initialize stores
    var material_store = ecs.MaterialStore.init(arena_allocator);
    var mesh_store = ecs.MeshStore.init(arena_allocator);

    var world = World.init(init.gpa);
    defer world.deinit();

    // Initialize systems
    var renderer = Renderer.init(init.gpa);
    defer renderer.deinit();

    const floor_vao, const floor_vbo, const floor_ebo, const index_count = renderer.createFloorBuffer();
    const floor_mesh_id = mesh_store.registerMesh(floor_vao, floor_vbo, floor_ebo, index_count);

    const transform = TransformComponent {
        .position = Vector3(f32).zero(),
        .rotation = Vector3(f32).zero(),
        .scale = Vector3(f32).one()
    };

    const floor_mesh = ecs.MeshComponent {
        .material_id = 0,
        .mesh_id = floor_mesh_id
    };

    const mat1 = math.Matrix4(u32).init(.{ 
        .{ 1, 2, 3, 4 },
        .{ 1, 2, 3, 4 },
        .{ 1, 2, 3, 4 },
        .{ 1, 2, 3, 4 } 
    });

    const mat2 = math.Matrix4(u32).init(.{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 2 }
    });

    std.log.debug("{any}", .{ math.Matrix4(u32).multiply(mat1, mat2) });

    std.log.debug("{any}", .{ math.Matrix4(u32).multiply(mat1, mat2).toArray() });

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
        }

        renderer.update(&world);

        renderer.draw(&material_store, &mesh_store);

        // Cap the frame rate
        const elapsed = frame_start.untilNow(init.io, .awake).toNanoseconds();
        if (elapsed < frame_duration_ns) {
            const surplus = frame_duration_ns - elapsed;
            try std.Io.sleep(init.io, .{ .nanoseconds = surplus }, .awake);
        }

    }

    std.log.info("Program exited without error", .{});
}

