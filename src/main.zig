const std = @import("std");
const builtin = @import("builtin");
const dyn_lib = std.DynLib;
const thread = std.Thread;
const fs = std.fs;
const mem = std.mem;
const time = std.time;
const math = std.math;
const assert = std.debug.assert;

// https://codeberg.org/andrewrk/TrueType
const TrueType = @import("TrueType");

const c = @cImport({
    // https://wayland.freedesktop.org/docs/html/apa.html
    // https://wayland.freedesktop.org/
    // Todo:
    // * libwayland: xml (wayland) -> C
    // * Find installed version of wayland
    // * Generate XML??
    @cInclude("wayland-client.h");
});

const FontPath = "font/font.ttf";
const KiB = 1024;
const MB = KiB * 1024;
const GB = MB * 1024;
const PixmapDepth = 32;

const InitialWindowWidth = 960;
const InitialWindowHeight = 480;

const Wayland = struct {
    refresh_rate: u32,
    mpf: u32,
};

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    //var run_playback: bool = false;
    //var is_recording: bool = false;

    // Todo: move to load font method
    // Todo: replace max_size with file size
    //const font = try fs.cwd().readFileAlloc(arena.allocator(), FontPath, 1024 * 1024);
    //const ttf = try TrueType.load(font);

    const display = c.wl_display_connect(null);
    defer c.wl_display_disconnect(display);

    std.debug.print("{any}\n", .{display});

    const registry = c.wl_display_get_registry(display);
    // Todo:
    // Get compositor
    // Get surface
    // https://github.com/vvavrychuk/hello_wayland/blob/master/helpers.c#L176

    std.debug.print("{any}\n", .{registry});

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

fn get_memory(h: u32, w: u32, allocator: mem.Allocator) ![][]u32 {
    var memory = try allocator.alloc([]u32, h);
    for (0..h) |i| {
        memory[i] = try allocator.alloc(u32, w);
    }

    return memory;
}
