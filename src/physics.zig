const std = @import("std");
const ecs = @import("ecs.zig");
const math = @import("math.zig");
const GameState = ecs.GameState;
const World = ecs.World;
const PhysicsBodyComponent = ecs.PhysicsBodyComponent;
const TransformComponent = ecs.TransformComponent;
const RectangleColliderComponent = ecs.RectangleColliderComponent;
const Allocator = std.mem.Allocator;
const ColliderComponent = ecs.ColliderComponent;

/// For updating entity acceleration, velocity, in that order per frame. Collisions should be handled after to reconcile intersections
pub const PhysicsSystem = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) PhysicsSystem {
        return .{
            .allocator = allocator
        };
    }

    pub fn deinit(_: *PhysicsSystem) void {
    }

    pub fn update(self: *PhysicsSystem, world: *World, game_state: *GameState) void {
        const physics_entities = world.queryEntitiesByComponents(self.allocator, .{ PhysicsBodyComponent, TransformComponent });
        defer self.allocator.free(physics_entities);
        const physics_components = world.getComponentsForEntities(self.allocator, PhysicsBodyComponent, physics_entities);
        defer self.allocator.free(physics_components);
        const transform_components = world.getComponentsForEntities(self.allocator, TransformComponent, physics_entities);
        defer self.allocator.free(transform_components);

        for (physics_components, 0..) |maybe_physics_component, idx| {
            var physics_component = maybe_physics_component orelse continue;
            var transform_component = transform_components[idx] orelse continue;

            const dt_vect: @Vector(3, f32) = @splat(game_state.dt);
            
            physics_component.velocity = physics_component.velocity + (physics_component.acceleration + gravity_vect) * dt_vect;
            transform_component.position = transform_component.position + physics_component.velocity * dt_vect; 
            physics_component.acceleration = math.vector3_zero;
        }

    }
};

pub const CollisionSystem = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) CollisionSystem {
        return .{
            .allocator = allocator
        };
    }

    pub fn deinit(_: *CollisionSystem) void {

    }

    pub fn update(self: *CollisionSystem, world: *World, _: *GameState) void {
        const collider_entities = world.queryEntitiesByComponents(self.allocator, .{ TransformComponent, ColliderComponent });
        defer self.allocator.free(collider_entities);
        const physics_entities = world.queryKnownEntitiesByComponents(self.allocator, collider_entities, .{ PhysicsBodyComponent });
        defer self.allocator.free(physics_entities);

        for (physics_entities) |physics_entity| {
            const physics_tranform = world.getComponent(TransformComponent, physics_entity) orelse continue;
            const physics_collider = world.getComponent(ColliderComponent, physics_entity) orelse continue;

            for (collider_entities) |collider_entity| {
                if (collider_entity == physics_entity) continue;
                const collider_transform = world.getComponent(TransformComponent, collider_entity) orelse continue;
                const collider_collider = world.getComponent(ColliderComponent, collider_entity) orelse continue;
                const is_colliding = checkCollision(
                    .{ .collider = physics_collider, .transform = physics_tranform }, 
                    .{ .collider = collider_collider, .transform = collider_transform });
                if (is_colliding) {
                    std.log.debug("Collision: {} and {}", .{ physics_entity, collider_entity });
                }             
            }
        }
    }

    const CollisionParams = struct {
        collider: *ColliderComponent,
        transform: *TransformComponent
    };

    fn checkCollision(first: CollisionParams, second: CollisionParams) bool {
        return switch(first.collider.*) {
            .rectangle => switch (second.collider.*) {
                .rectangle => collisionRectRect(first, second),
                .capsule => unreachable
            },
            .capsule => switch (second.collider.*) {
                .rectangle => unreachable,
                .capsule => unreachable
            }
        };
    }

    fn collisionRectRect(a: CollisionParams, b: CollisionParams) bool {
        const big = std.math.floatMax(f32);
        const small = std.math.floatMin(f32);

        var a_min: @Vector(3, f32) = .{ big, big, big };
        var a_max: @Vector(3, f32) = .{ small, small, small };

        var b_min: @Vector(3, f32) = .{ big, big, big };
        var b_max: @Vector(3, f32) = .{ small, small, small };

        var a_points: [4]@Vector(3, f32) = undefined;
        inline for (a.collider.rectangle.points, 0..) |point, idx| {
            a_points[idx] = point + a.transform.position;
            inline for (0..3) |axis| {
                if (a_points[idx][axis] < a_min[axis]) a_min[axis] = a_points[idx][axis];
                if (a_points[idx][axis] > a_max[axis]) a_max[axis] = a_points[idx][axis];
            }
        }

        var b_points: [4]@Vector(3, f32) = undefined;
        inline for (b.collider.rectangle.points, 0..) |point, idx| {
            b_points[idx] = point + b.transform.position;
            inline for (0..3) |axis| {
                if (b_points[idx][axis] < b_min[axis]) b_min[axis] = b_points[idx][axis];
                if (b_points[idx][axis] > b_max[axis]) b_max[axis] = b_points[idx][axis];
            }
        }

        const overlap: @Vector(3, f32) = .{ 
            @min(a_max[0], b_max[0]) - @max(a_min[0], b_min[0]),
            @min(a_max[1], b_max[1]) - @max(a_min[1], b_min[1]),
            @min(a_max[2], b_max[2]) - @max(a_min[2], b_min[2]),
        };

        return overlap[0] > 0 and overlap[1] > 0 and overlap[2] > 0;
    }

    fn collisionRectCapsule(_: CollisionParams, _: CollisionParams) bool {
        return true;
    }
};

const gravity_vect: @Vector(3, f32) = .{ 0.0, 0.0, -9.81 };
