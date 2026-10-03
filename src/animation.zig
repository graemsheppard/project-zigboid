const std = @import("std");
const ecs = @import("ecs.zig");

const AnimationComponent = ecs.AnimationComponent;
const MeshComponent = ecs.MeshComponent;

pub const AnimationSystem = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) AnimationSystem {
        return .{
            .allocator = allocator
        };
    }

    pub fn update(self: *AnimationSystem, world: *ecs.World, game_state: *ecs.GameState, animation_store: *ecs.AnimationStore) void {
        const animated_entities = world.queryEntitiesByComponents(self.allocator, .{ AnimationComponent, MeshComponent });
        defer self.allocator.free(animated_entities);
        const animation_components = world.getComponentsForEntities(self.allocator, AnimationComponent, animated_entities);
        defer self.allocator.free(animation_components);
        for (animation_components) |maybe_animation_component| {
            var animation_component = maybe_animation_component orelse continue;
            const animation = animation_store.get(animation_component.animation_id);
            animation_component.elapsed = @rem((animation_component.elapsed + game_state.dt), animation.duration);
            animation_component.current_frame = blk: {
                var frame: usize = 0;
                for (animation.keyframes, 0..) |kf, frame_idx| {
                    if (kf >= animation_component.elapsed)
                        break :blk frame_idx;
                    frame = frame_idx;
                } 
                break :blk 0;
            };
        }
    }
};
