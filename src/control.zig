const ecs = @import("ecs.zig");
const World = ecs.World;
const InputComponent = ecs.InputComponent;
const TransformComponent = ecs.TransformComponent;
const GameState = ecs.GameState;
const c = @import("c");

pub const ControlSystem = struct {

    pub fn update(_: *ControlSystem, world: *World, game_state: *GameState) void {
        const transform = world.getComponent(TransformComponent, game_state.player_id) orelse return;
        
        if (c.glfwGetKey(game_state.window, c.GLFW_KEY_W) == 1) {
            transform.position.y += 0.01;
        }
    }
};
