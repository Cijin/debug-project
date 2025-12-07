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
    // https://ssp.impulsetrain.com/porterduff.html (understaning 'IN')
    // https://www.x.org/releases/current/doc/libXrender/libXrender.txt
    // https://www.x.org/releases/current/doc/renderproto/renderproto.txt
    @cInclude("X11/extensions/Xrender.h");
});

const FontPath = "font/font.ttf";
const KiB = 1024;
const MB = KiB * 1024;
const GB = MB * 1024;
const BitmapPad = 32;
const PixmapDepth = 32;

const X11 = struct {
    display: *c.Display,
    screen: c_int,
    refresh_rate: u32,
    mpf: u32,
    pixmap: c.Pixmap,
    pixmap_gc: c.GC,
    dst_picture: c.Picture,
    src_picture: c.Picture,
};

pub fn main() !u8 {
    var x11 = X11{
        .display = undefined,
        .screen = undefined,
        .refresh_rate = 60,
        .mpf = 1000 / 60,
        .pixmap = undefined,
        .pixmap_gc = undefined,
        .dst_picture = undefined,
        .src_picture = undefined,
    };
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
        .fps = 0,
        .time_per_frame = 0,
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
    x11.display = c.XOpenDisplay(null) orelse {
        std.debug.print("failed to open display", .{});

        return 1;
    };
    defer _ = c.XCloseDisplay(x11.display);

    x11.screen = c.XDefaultScreen(x11.display);
    const root_window = c.XRootWindow(x11.display, x11.screen);
    const window = c.XCreateSimpleWindow(
        x11.display,
        root_window,
        0,
        0,
        @intCast(GlobalOffScreenBuffer.window_width),
        @intCast(GlobalOffScreenBuffer.window_height),
        0,
        c.XBlackPixel(x11.display, x11.screen),
        c.XBlackPixel(x11.display, x11.screen),
    );

    const XRRScreenConf = c.XRRGetScreenInfo(x11.display, window);
    const XRRCurrentRate = c.XRRConfigCurrentRate(XRRScreenConf);
    if (XRRCurrentRate > 0) {
        x11.refresh_rate = @intCast(XRRCurrentRate);
        x11.mpf = 1000 / x11.refresh_rate;
    }

    var delete_atom: c.Atom = undefined;
    delete_atom = c.XInternAtom(x11.display, "WM_DELETE_WINDOW", 0);
    const protocol_status = c.XSetWMProtocols(x11.display, window, &delete_atom, 1);
    if (protocol_status == 0) {
        std.debug.print("failed to set wm_delete protocol", .{});
        return 1;
    }

    _ = c.XStoreName(x11.display, window, "Handmade");

    // events don't get triggered without masks
    _ = c.XSelectInput(
        x11.display,
        window,
        c.KeyPressMask | c.KeyReleaseMask | c.StructureNotifyMask | c.PointerMotionMask | c.ButtonPressMask | c.ButtonReleaseMask,
    );

    _ = c.XMapWindow(x11.display, window);

    // Todo: remove this at some point
    // only done so I don't have to move it out of the way of the logs
    _ = c.XMoveWindow(x11.display, window, 1400, 300);

    // window will not show up without sync
    _ = c.XSync(x11.display, 0);

    x11.pixmap = c.XCreatePixmap(x11.display, window, @intCast(GlobalOffScreenBuffer.window_width), @intCast(GlobalOffScreenBuffer.window_height), @intCast(PixmapDepth));
    defer _ = c.XFreePixmap(x11.display, x11.pixmap);

    x11.pixmap_gc = c.XCreateGC(x11.display, x11.pixmap, 0, null);

    const src_format = c.XRenderFindStandardFormat(x11.display, c.PictStandardARGB32);
    x11.src_picture = c.XRenderCreatePicture(x11.display, x11.pixmap, src_format, 0, null);

    var wa: c.XWindowAttributes = undefined;
    _ = c.XGetWindowAttributes(x11.display, window, &wa);
    const dst_format = c.XRenderFindVisualFormat(x11.display, wa.visual);
    x11.dst_picture = c.XRenderCreatePicture(x11.display, window, dst_format, 0, null);

    var quit = false;
    var event: c.XEvent = undefined;
    var start_time = time.milliTimestamp();
    var fps: i64 = 0;
    var time_per_frame: i64 = 0;
    var end_time: i64 = 0;
    while (!quit) {
        while (c.XPending(x11.display) > 0) {
            _ = c.XNextEvent(x11.display, &event);
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
                    // Todo: resize window buffer
                },
                else => continue,
            }
        }

        game_memory.fps = fps;
        game_memory.time_per_frame = time_per_frame;
        handmade.GameUpdateAndRenderer(arena.allocator(), game_memory, GlobalLinuxState.game_input, &GlobalOffScreenBuffer);

        end_time = time.milliTimestamp();
        time_per_frame = end_time - start_time;
        while (time_per_frame < x11.mpf) {
            const sleep_time: u64 = @intCast(@divTrunc((x11.mpf - time_per_frame), 1000));
            thread.sleep(sleep_time);

            end_time = time.milliTimestamp();
            time_per_frame = end_time - start_time;
        }

        render(&GlobalOffScreenBuffer, x11);

        end_time = time.milliTimestamp();
        time_per_frame = end_time - start_time;

        assert(time_per_frame != 0);

        fps = @divTrunc(1000, time_per_frame);
        start_time = end_time;
    }

    return 0;
}

fn render(screen_buffer: *common.OffScreenBuffer, x11: X11) void {
    // Note: xrender operations are server side (x11)
    // Operations on the image are done once they are sent to the x11 server
    //
    // Steps as I understand them so far:
    // Write the bitmap onto a pixmap (client side) using putimage
    // Create a picture from this pixmap
    // Create a second picture on the window
    // Composite the two pictures above
    const image = c.XCreateImage(
        x11.display,
        null,
        @intCast(PixmapDepth),
        c.ZPixmap,
        0,
        @ptrCast(&screen_buffer.memory),
        @intCast(screen_buffer.window_width),
        @intCast(screen_buffer.window_height),
        BitmapPad,
        @intCast(@sizeOf(u32) * screen_buffer.window_width),
    );
    _ = c.XPutImage(x11.display, x11.pixmap, x11.pixmap_gc, image, 0, 0, 0, 0, @intCast(screen_buffer.window_width), @intCast(screen_buffer.window_height));

    c.XRenderComposite(
        x11.display,
        c.PictOpOver,
        x11.src_picture,
        0,
        x11.dst_picture,
        0,
        0,
        0,
        0,
        0,
        0,
        @intCast(screen_buffer.window_width),
        @intCast(screen_buffer.window_height),
    );
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
