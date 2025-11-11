const std = @import("std");
const common = @import("common.zig");
const mem = std.mem;
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

fn render_text(allocator: mem.Allocator, game_memory: *common.GameMemory, buffer: *common.OffScreenBuffer) void {
    var text_buffer: std.ArrayListUnmanaged(u8) = .empty;
    defer text_buffer.deinit(allocator);

    const example = "testing";
    // Todo: Remove black background in font and change font color
    // Todo: how does scale translate to font pixel height
    const scale = game_memory.ttf.scaleForPixelHeight(200);
    var it = std.unicode.Utf8View.initComptime(example).iterator();

    const padding_y: i16 = 400;
    const padding_x: usize = 100;
    var start: usize = 0;
    while (it.nextCodepoint()) |codepoint| {
        if (game_memory.ttf.codepointGlyphIndex(codepoint)) |glyph| {
            text_buffer.clearRetainingCapacity();
            const dims = game_memory.ttf.glyphBitmap(allocator, &text_buffer, glyph, scale, scale) catch |err| {
                std.debug.print("Failed to get font dimensions: {any}\n", .{err});
                return;
            };

            const pixels = text_buffer.items;
            for (0..dims.height) |j| {
                for (0..dims.width, start..) |i, buff_i| {
                    buffer.memory[j + @as(usize, @intCast(padding_y + dims.off_y))][padding_x + buff_i] = pixels[j * dims.width + i];
                }
            }

            start += dims.width;
        }
    }
}

fn renderer(_: *common.GameState, buffer: *common.OffScreenBuffer) void {
    for (0..buffer.window_height) |i| {
        for (0..buffer.window_width) |j| {
            //const blue = j + game_state.width_offset;
            //const green = i + game_state.height_offset;

            buffer.memory[i][j] = 0xffffffff;
        }
    }
}

pub fn GameUpdateAndRenderer(
    allocator: mem.Allocator,
    game_memory: *common.GameMemory,
    input: *common.Input,
    buffer: *common.OffScreenBuffer,
) void {
    if (!game_memory.is_initialized) {
        game_memory.init();
    }

    handle_keypress_event(game_memory.game_state, input);
    renderer(game_memory.game_state, buffer);
    render_text(allocator, game_memory, buffer);
}
