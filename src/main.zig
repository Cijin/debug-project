const std = @import("std");
const builtin = @import("builtin");
const dyn_lib = std.DynLib;
const thread = std.Thread;
const fs = std.fs;
const mem = std.mem;
const time = std.time;
const math = std.math;
const assert = std.debug.assert;
const wayland = @import("wayland.zig");

// https://codeberg.org/andrewrk/TrueType
const TrueType = @import("TrueType");

// https://wayland-book.com/
// https://gaultier.github.io/blog/wayland_from_scratch.html
// https://wayland.app/protocols/
// Check if wayland: $XDG_SESSION_TYPE
// Socket: $WAYLAND_DISPLAY
// Path: $XDG_RUNTIME_DIR

const FontPath = "font/font.ttf";
const KiB = 1024;
const MB = KiB * 1024;
const GB = MB * 1024;
const PixmapDepth = 32;

const InitialWindowWidth = 960;
const InitialWindowHeight = 480;

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    try wayland.conn(allocator);

    //var run_playback: bool = false;
    //var is_recording: bool = false;

    // Todo: move to load font method
    // Todo: replace max_size with file size
    //const font = try fs.cwd().readFileAlloc(arena.allocator(), FontPath, 1024 * 1024);
    //const ttf = try TrueType.load(font);

    //const quit = false;
    //var start_time = time.milliTimestamp();
    //var fps: i64 = 0;
    //var time_per_frame: i64 = 0;
    //var end_time: i64 = 0;
    //while (!quit) {
    //    end_time = time.milliTimestamp();
    //    time_per_frame = end_time - start_time;
    //    while (time_per_frame < wayland.mpf) {
    //        const sleep_time: u64 = @intCast(@divTrunc((wayland.mpf - time_per_frame), 1000));
    //        thread.sleep(sleep_time);

    //        end_time = time.milliTimestamp();
    //        time_per_frame = end_time - start_time;
    //    }

    //    end_time = time.milliTimestamp();
    //    time_per_frame = end_time - start_time;

    //    assert(time_per_frame != 0);

    //    fps = @divTrunc(1000, time_per_frame);
    //    start_time = end_time;
    //}

    return 0;
}

fn getMemory(h: u32, w: u32, allocator: mem.Allocator) ![][]u32 {
    var memory = try allocator.alloc([]u32, h);
    for (0..h) |i| {
        memory[i] = try allocator.alloc(u32, w);
    }

    return memory;
}
