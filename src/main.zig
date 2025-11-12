const std = @import("std");
// https://codeberg.org/andrewrk/TrueType
const TrueType = @import("TrueType");
const builtin = @import("builtin");
const common = @import("common.zig");
const handmade = @import("handmade.zig");
const dyn_lib = std.DynLib;
const thread = std.Thread;
const fs = std.fs;
const mem = std.mem;
const time = std.time;
const math = std.math;
const assert = std.debug.assert;
const c = @cImport({
    // https://tronche.com/gui/x/xlib/
    @cInclude("X11/Xlib.h");
    @cInclude("X11/keysym.h");
    // https://www.x.org/archive/X11R7.6/doc/man/man3/Xrandr.3.xhtml
    @cInclude("X11/extensions/Xrandr.h");
});

const FontPath = "font/font.ttf";
const KiB = 1024;
const MB = KiB * 1024;
const GB = MB * 1024;
const BitmapPad = 32;

pub fn main() !u8 {
    var X11RefreshRate: u32 = 60;
    var X11MsPerFrame = 1000 / X11RefreshRate;
    var run_playback: bool = false;
    var is_recording: bool = false;

    var GlobalOffScreenBuffer: common.OffScreenBuffer = undefined;

    // Todo: this could be done better?
    // total_mem = [ game_state audio_buffer screen_buffer]
    // allocate(total_mem)
    // game_state = total_mem[0..@sizeOf(game_state)]
    // game_state.audio -> total_mem[@sizeOf(game_state)..@sizeOf(audio_buffer)]
    // audio_buffer = total_mem[0..@sizeOf(audio_buffer)]
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    // Todo: move to load font method
    // Todo: replace max_size with file size
    const font = try fs.cwd().readFileAlloc(arena.allocator(), FontPath, 1024 * 1024);
    const ttf = try TrueType.load(font);

    // Todo: combine with linux state
    const game_memory = arena.allocator().create(common.GameMemory) catch unreachable;
    game_memory.* = common.GameMemory{
        .is_initialized = false,
        .game_state = arena.allocator().create(common.GameState) catch unreachable,
        .ttf = &ttf,
    };

    var GlobalLinuxState = arena.allocator().create(common.LinuxState) catch unreachable;
    GlobalLinuxState.* = common.LinuxState{
        .filename = "playback/game_state.hmh",
        .recording_file = null,
        .playback_file = null,
        .game_input = arena.allocator().create(common.Input) catch unreachable,
        .game_state = game_memory.game_state,
    };
    GlobalLinuxState.game_input.* = common.Input{
        .mouse_x = -1,
        .mouse_y = -1,
        .mouse_z = 0,
        .mouse_buttons = [3]bool{ false, false, false },
        .key = 0,
        .key_released = 0,
        .time = 0,
    };
    GlobalLinuxState.init() catch |err| {
        std.debug.print("Failed to init LinuxState: {any}\n", .{err});
        return 1;
    };
    defer GlobalLinuxState.deinit();

    GlobalOffScreenBuffer.window_width = common.InitialWindowWidth;
    GlobalOffScreenBuffer.window_height = common.InitialWindowHeight;
    GlobalOffScreenBuffer.pitch = 0;

    // On a POSIX-conformant system, if the display_name is NULL, it defaults to the value of the DISPLAY environment variable.
    const display = c.XOpenDisplay(null) orelse {
        std.debug.print("failed to open display", .{});

        return 1;
    };
    defer _ = c.XCloseDisplay(display);

    const screen = c.XDefaultScreen(display);

    const window_parent = c.XRootWindow(display, screen);
    const window = c.XCreateSimpleWindow(
        display,
        window_parent,
        0,
        0,
        @intCast(GlobalOffScreenBuffer.window_width),
        @intCast(GlobalOffScreenBuffer.window_height),
        0,
        c.XBlackPixel(display, screen),
        c.XBlackPixel(display, screen),
    );

    const XRRScreenConf = c.XRRGetScreenInfo(display, window);
    const XRRCurrentRate = c.XRRConfigCurrentRate(XRRScreenConf);
    if (XRRCurrentRate > 0) {
        X11RefreshRate = @intCast(XRRCurrentRate);
        X11MsPerFrame = 1000 / X11RefreshRate;
    }

    // Todo: use a specific font, not sure where the current font is loaded from
    // Todo: handle errors
    const x11_font = c.XLoadFont(display, "*");
    defer _ = c.XUnloadFont(display, x11_font);

    const gc = c.XCreateGC(display, window, 0, @ptrCast(@constCast(&c.XGCValues{ .font = x11_font })));

    var delete_atom: c.Atom = undefined;
    delete_atom = c.XInternAtom(display, "WM_DELETE_WINDOW", 0);
    const protocol_status = c.XSetWMProtocols(display, window, &delete_atom, 1);
    if (protocol_status == 0) {
        std.debug.print("failed to set wm_delete protocol", .{});
        return 1;
    }

    _ = c.XStoreName(display, window, "Handmade");

    // events don't get triggered without masks
    _ = c.XSelectInput(
        display,
        window,
        c.KeyPressMask | c.KeyReleaseMask | c.StructureNotifyMask | c.PointerMotionMask | c.ButtonPressMask | c.ButtonReleaseMask,
    );

    _ = c.XMapWindow(display, window);

    // window will not show up without sync
    _ = c.XSync(display, 0);

    var quit = false;
    var event: c.XEvent = undefined;
    var start_time = time.milliTimestamp();
    var fps: i64 = 0;
    var time_per_frame: i64 = 0;
    var end_time: i64 = 0;
    while (!quit) {
        while (c.XPending(display) > 0) {
            _ = c.XNextEvent(display, &event);
            switch (event.type) {
                c.KeyPress => {
                    const keysym = c.XLookupKeysym(&event.xkey, 0);
                    GlobalLinuxState.game_input.key = @intCast(keysym);
                    if (keysym == c.XK_Escape) {
                        quit = true;
                        break;
                    } else if (keysym == 'l') {
                        if (!is_recording) {
                            is_recording = true;
                            run_playback = false;
                            std.debug.print("Recording input...\n", .{});
                        } else {
                            is_recording = false;
                            std.debug.print("Recording stoped...\n", .{});
                        }
                    } else if (keysym == 'p') {
                        is_recording = false;

                        run_playback = true;
                        std.debug.print("Playback recording...\n", .{});
                    } else if (keysym == 's') {
                        run_playback = false;

                        std.debug.print("Playback paused...\n", .{});
                    }

                    if (is_recording) {
                        write_linux_state(GlobalLinuxState);
                    }
                },
                c.KeyRelease => {
                    const keysym = c.XLookupKeysym(&event.xkey, 0);
                    GlobalLinuxState.game_input.key_released = @intCast(keysym);
                    // Todo: what if two keys pressed
                    GlobalLinuxState.game_input.key = 0;
                    GlobalLinuxState.game_input.time = @intCast(event.xkey.time);
                },
                c.ButtonRelease => {
                    const btn_pressed = event.xbutton.button;
                    if (btn_pressed <= 3) {
                        GlobalLinuxState.game_input.mouse_buttons[btn_pressed - 1] = false;
                    }
                },
                c.ButtonPress => {
                    const btn_pressed = event.xbutton.button;
                    if (btn_pressed <= 3) {
                        GlobalLinuxState.game_input.mouse_buttons[btn_pressed - 1] = true;
                    }

                    if (btn_pressed == 4) {
                        GlobalLinuxState.game_input.mouse_z += 1;
                    }

                    if (btn_pressed == 5) {
                        GlobalLinuxState.game_input.mouse_z -= 1;
                    }
                },
                c.MotionNotify => {
                    GlobalLinuxState.game_input.mouse_x = @intCast(event.xmotion.x);
                    GlobalLinuxState.game_input.mouse_y = @intCast(event.xmotion.y);
                },
                // Todo: handle window destroyed or prematurely closed
                // so that it can be restarted if it was unintended
                c.ClientMessage => {
                    if (event.xclient.data.l[0] == delete_atom) {
                        std.debug.print("Closing window.\n", .{});
                        quit = true;
                        break;
                    }
                },
                c.ConfigureNotify => {
                    // Todo: currently window width and height is fixed, can be "streched" once
                    // prototyping is done
                },
                else => continue,
            }
        }

        handmade.GameUpdateAndRenderer(arena.allocator(), game_memory, GlobalLinuxState.game_input, &GlobalOffScreenBuffer);

        // Todo: RDTSC() to get cycles/frame
        end_time = time.milliTimestamp();
        time_per_frame = end_time - start_time;
        while (time_per_frame < X11MsPerFrame) {
            const sleep_time: u64 = @intCast(@divTrunc((X11MsPerFrame - time_per_frame), 1000));
            thread.sleep(sleep_time);

            end_time = time.milliTimestamp();
            time_per_frame = end_time - start_time;
        }

        render_game(
            &GlobalOffScreenBuffer,
            display,
            window,
            gc,
        );

        end_time = time.milliTimestamp();
        time_per_frame = end_time - start_time;

        assert(time_per_frame != 0);
        fps = @divTrunc(1000, time_per_frame);

        //std.debug.print("MsPerFrame: {d}\t FPS: {d}\t TargetFPS: {d}\n", .{
        //    time_per_frame,
        //    fps,
        //    X11RefreshRate,
        //});
        start_time = end_time;
    }

    return 0;
}

// Todo: this won't work for higher fps
fn write_audio(server: ?*c.struct_pa_simple, sound_buffer: *common.SoundBuffer) void {
    var error_code: c_int = 0;
    const result = c.pa_simple_write(
        server,
        @ptrCast(sound_buffer.buffer),
        sound_buffer.buffer.len * @sizeOf(i16),
        &error_code,
    );
    if (result < 0) {
        std.debug.print("Audio write error: {s}\n", .{c.pa_strerror(error_code)});
        return;
    }
}

fn render_game(
    screen_buffer: *common.OffScreenBuffer,
    display: ?*c.Display,
    window: c.Window,
    gc: c.GC,
) void {
    var wa: c.XWindowAttributes = undefined;
    _ = c.XGetWindowAttributes(display, window, &wa);

    const image = c.XCreateImage(
        display,
        wa.visual,
        @intCast(wa.depth),
        c.ZPixmap,
        0,
        @ptrCast(&screen_buffer.memory),
        @intCast(screen_buffer.window_width),
        @intCast(screen_buffer.window_height),
        BitmapPad,
        @intCast(@sizeOf(u32) * screen_buffer.window_width),
    );

    _ = c.XPutImage(display, window, gc, image, 0, 0, 0, 0, @intCast(screen_buffer.window_width), @intCast(screen_buffer.window_height));
    const example = "Testing";
    // Todo: use XDrawText instead
    _ = c.XDrawString(display, window, gc, 20, 20, example, example.len);
}

// Todo: read entire file at once
fn read_linux_state(linux_state: *common.LinuxState) !void {
    const current_pos = try linux_state.playback_file.?.getPos();
    const stat = try linux_state.playback_file.?.stat();

    if (current_pos == stat.size) {
        try linux_state.playback_file.?.seekTo(0);
    }

    var buffer: [@sizeOf(common.GameState) + @sizeOf(common.Input)]u8 = undefined;
    _ = linux_state.playback_file.?.read(&buffer) catch |err| {
        std.debug.print("Failed to read input: {any}\n", .{err});
    };

    linux_state.game_state.* = mem.bytesToValue(common.GameState, buffer[0..@sizeOf(common.GameState)]);
    linux_state.game_input.* = mem.bytesToValue(common.Input, buffer[@sizeOf(common.GameState)..]);
}

// Todo: write larger chunks of inputs at once instead of one at a time
fn write_linux_state(linux_state: *common.LinuxState) void {
    const buffer = mem.asBytes(linux_state.game_state) ++ mem.asBytes(linux_state.game_input);
    _ = linux_state.recording_file.?.write(buffer) catch |err| {
        std.debug.print("Failed to write input: {any}\n", .{err});
    };
}
