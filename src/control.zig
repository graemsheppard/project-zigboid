const ecs = @import("ecs.zig");
const std = @import("std");
const World = ecs.World;
const InputComponent = ecs.InputComponent;
const TransformComponent = ecs.TransformComponent;
const GameState = ecs.GameState;
const c = @import("c");

pub const ControlSystem = struct {
    const half_root_2 = 1.0 / @sqrt(2);
    pub fn update(_: *ControlSystem, world: *World, game_state: *GameState) void {
        const input = world.getComponent(InputComponent, game_state.player_id) orelse return;
        const transform  = world.getComponent(TransformComponent, game_state.player_id) orelse return;

        var dir: @Vector(3, f32) = .{ 0.0, 0.0, 0.0 };
        
        if (c.glfwGetKey(game_state.window, c.GLFW_KEY_W) == 1) {
            dir += .{ -1.0, 1.0, 0.0 };
        }

        if (c.glfwGetKey(game_state.window, c.GLFW_KEY_S) == 1) {
            dir += .{ 1.0, -1.0, 0.0 };
        }

        if (c.glfwGetKey(game_state.window, c.GLFW_KEY_D) == 1) {
            dir += .{ 1.0, 1.0, 0.0 };
        }

        if (c.glfwGetKey(game_state.window, c.GLFW_KEY_A) == 1) {
            dir += .{ -1.0, -1.0, 0.0 };
        }

        if (@reduce(.Add, @abs(dir)) == 0)  return;

        const dir_mag: f32 = @sqrt(@reduce(.Add, dir * dir));
        input.direction = dir / @as(@Vector(3, f32), @splat(dir_mag)) * @as(@Vector(3, f32), @splat(0.5 * game_state.dt));
        transform.position.x += input.direction[0];
        transform.position.y += input.direction[1];
        transform.position.z += input.direction[2];
    }
};
