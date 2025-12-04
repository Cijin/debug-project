const std = @import("std");
const mem = std.mem;
const time = std.time;
const math = std.math;
const assert = std.debug.assert;

const common = @import("common.zig");

const BlueOffset = 0x0000ff;
const RedOffset = 0xff0000;
const GreenOffset = 0x00ff00;
const FontColor = 0x00ff0000;
const BackgroundColor = 0x00000000;

const Bg = BackgroundColor;
const Bg_r = (Bg >> 16) & 0xff;
const Bg_g = (Bg >> 8) & 0xff;
const Bg_b = Bg & 0xff;
const Fg_r: u32 = (FontColor >> 16) & 0xff;
const Fg_g: u32 = (FontColor >> 8) & 0xff;
const Fg_b: u32 = FontColor & 0xff;

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

fn render_font(allocator: mem.Allocator, game_memory: *common.GameMemory, buffer: *common.OffScreenBuffer) void {
    var text_buffer: std.ArrayListUnmanaged(u8) = .empty;
    defer text_buffer.deinit(allocator);

    const example = "antialiasing";
    // Todo: how does scale translate to font pixel height
    const scale = game_memory.ttf.scaleForPixelHeight(25);
    var it = std.unicode.Utf8View.initComptime(example).iterator();

    // Todo: improve this
    const padding_y: i16 = 400;
    const padding_x: usize = 100;
    var start: usize = 0;
    while (it.nextCodepoint()) |codepoint| {
        if (game_memory.ttf.codepointGlyphIndex(codepoint)) |glyph| {
            text_buffer.clearRetainingCapacity();
            const dims = game_memory.ttf.glyphBitmap(
                allocator,
                &text_buffer,
                glyph,
                scale,
                scale,
            ) catch |err| {
                std.debug.print("Failed to get font dimensions: {any}\n", .{err});
                return;
            };

            const pixels = text_buffer.items;
            for (0..dims.height) |j| {
                for (0..dims.width, start..) |i, buff_i| {
                    const alpha = pixels[j * dims.width + i];

                    const inv_alpha = 255 - alpha;
                    const r = (Fg_r * alpha + Bg_r * inv_alpha) / 255;
                    const g = (Fg_g * alpha + Bg_g * inv_alpha) / 255;
                    const b = (Fg_b * alpha + Bg_b * inv_alpha) / 255;

                    buffer.memory[j + @as(usize, @intCast(padding_y + dims.off_y))][padding_x + buff_i] =
                        0xff000000 | (r << 16) | (g << 8) | b;
                }
            }
            start += dims.width;
        }
    }
}

fn renderer_bg(_: *common.GameState, buffer: *common.OffScreenBuffer) void {
    for (0..buffer.window_height) |i| {
        for (0..buffer.window_width) |j| {
            buffer.memory[i][j] = BackgroundColor;
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
    renderer_bg(game_memory.game_state, buffer);

    render_font(allocator, game_memory, buffer);
}
