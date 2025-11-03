const std = @import("std");
const common = @import("common.zig");
const math = std.math;
const assert = std.debug.assert;

const BlueOffset = 0x0000ff;
const RedOffset = 0xff0000;
const GreenOffset = 0x00ff00;

fn handle_keypress_event(game_state: *common.GameState, input: *common.Input) void {
    switch (input.key) {
        'w' => {
            game_state.height_offset -= 1;
        },
        'a' => {
            game_state.width_offset -= 1;
        },
        's' => {
            game_state.height_offset += 1;
        },
        'd' => {
            game_state.width_offset += 1;
        },
        else => {},
    }
}

fn renderer(game_state: *common.GameState, buffer: *common.OffScreenBuffer) void {
    for (0..buffer.window_width) |i| {
        for (0..buffer.window_height) |j| {
            const blue = j + game_state.width_offset;
            const green = i + game_state.height_offset;

            buffer.memory[i][j] = @intCast(blue & green);
        }
    }
}

export fn GameUpdateAndRenderer(
    game_memory: *common.GameMemory,
    input: *common.Input,
    buffer: *common.OffScreenBuffer,
) void {
    if (!game_memory.is_initialized) {
        game_memory.init();
    }

    handle_keypress_event(game_memory.game_state, input);
    renderer(game_memory.game_state, buffer);
}
