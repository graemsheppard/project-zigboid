const std = @import("std");
const ecs = @import("ecs.zig");
const math = @import("math.zig");
const GameState = ecs.GameState;
const World = ecs.World;
const Vector3 = math.Vector3;
const PhysicsBodyComponent = ecs.PhysicsBodyComponent;
const TransformComponent = ecs.TransformComponent;
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
                const is_colliding, const correction = checkCollision(
                    .{ .collider = physics_collider, .transform = physics_tranform }, 
                    .{ .collider = collider_collider, .transform = collider_transform });
                if (is_colliding) {
                    physics_tranform.position += correction;
                }             
            }
        }
    }

    const CollisionParams = struct {
        collider: *ColliderComponent,
        transform: *TransformComponent
    };

    fn checkCollision(first: CollisionParams, second: CollisionParams) struct { bool, @Vector(3, f32) } {
        return switch(first.collider.*) {
            .sphere => switch (second.collider.*) {
                .sphere => unreachable,
                .triangle => collisionSphereTriangle(first, second)
            },
            .triangle => switch (second.collider.*) {
                .sphere => collisionSphereTriangle(second, first),
                .triangle => unreachable
            }
        };
    }

    fn collisionSphereTriangle(sphere: CollisionParams, triangle: CollisionParams) struct { bool, @Vector(3, f32) } {
        var triangle_points: [3]@Vector(3, f32) = undefined;
        const sphere_center = sphere.collider.sphere.offset + sphere.transform.position;

        inline for (0..3) |idx| {
            triangle_points[idx] = triangle.collider.triangle.points[idx] + triangle.transform.position;
        }

        const edge_1 = triangle_points[1] - triangle_points[0];
        const edge_2 = triangle_points[2] - triangle_points[0];
        const t_norm = Vector3.normalize(Vector3.cross(edge_1, edge_2));
        const to_sphere = sphere_center - triangle_points[0];
        const plane_dist = Vector3.dot(to_sphere, t_norm);

        if (@abs(plane_dist) > sphere.collider.sphere.radius)
            return .{ false, .{ 0, 0, 0 } };

        const projected_center = sphere_center - @as(@Vector(3, f32), @splat(plane_dist)) * t_norm;
        const nearest_point = nearestPointOnTriangle(projected_center, triangle_points[0], triangle_points[1], triangle_points[2]);
        const diff = sphere_center - nearest_point;
        const dist = Vector3.magnitude(diff);
        const norm = Vector3.normalize(diff);
        const correction = norm * @as(@Vector(3, f32), @splat(sphere.collider.sphere.radius - dist));

        if (dist <= sphere.collider.sphere.radius) {
            return .{ true, correction };
        }

        return .{ false, .{ 0, 0, 0 } };
    }

    /// Returns the nearest point on a triangle abc to point p that lies within its plane
    fn nearestPointOnTriangle(p: @Vector(3, f32), a: @Vector(3, f32), b: @Vector(3, f32), c: @Vector(3, f32)) @Vector(3, f32) {
        // Check if vertex a is closest
        const ap = p - a;
        const ab = b - a;
        const ac = c - a;

        const d1 = Vector3.dot(ap, ab);
        const d2 = Vector3.dot(ap, ac);

        if (d1 <= 0 and d2 <= 0)
            return a;

        // Check if vertex b is closest
        const bp = p - b;

        const d3 = Vector3.dot(ab, bp);
        const d4 = Vector3.dot(ac, bp);

        if (d3 >= 0 and d4 <= d3)
            return b;

        // Check if point is on edge ab
        const vc = d1 * d4 - d3 * d2;
        if (vc <= 0 and d1 >= 0 and d3 <= 0) {
            const v = d1 / (d1 - d3);
            return a + (ab * @as(@Vector(3, f32), @splat(v)));
        }

        // Check if vertex c is closest
        const cp = p - c;
        const d5 = Vector3.dot(ab, cp);
        const d6 = Vector3.dot(ac, cp);
        if (d5 >= 0 and d5 <= d6) 
            return c;

        // Check if point is on edge ac
        const vb = d5 * d2 - d1 * d6;
        if (vb <= 0 and d2 >= 0 and d6 <= 0) {
            const w = d2 / (d2 - d6);
            return a + (ac * @as(@Vector(3, f32), @splat(w)));
        }

        // Check if point is on edge bc
        const va = d3 * d6 - d5 * d4;
        if (va <= 0 and (d4 - d3) >= 0 and (d6 - d5) >= 0) {
            const w = (d4 - d3) / (d4 - d3 + d6 - d5);
            return b + ((c - b) * @as(@Vector(3, f32), @splat(w)));
        }

        return p;
    }

    fn collisionTriangleTriangle(_: CollisionParams, _: CollisionParams) struct { bool, @Vector(3, f32) } {
        return .{ false, .{0,0,0} };
    }

};

const gravity_vect: @Vector(3, f32) = .{ 0.0, 0.0, -1 };
