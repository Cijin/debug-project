const std = @import("std");
const TrueType = @import("TrueType");
const fs = std.fs;
const mem = std.mem;

pub const GameMemory = struct {
    is_initialized: bool,
    fps: i64,
    time_per_frame: i64,
    game_state: *GameState,
    ttf: *const TrueType,

    pub fn init(self: *GameMemory) void {
        self.game_state.height_offset = 0;
        self.game_state.width_offset = 0;

        self.game_state.player_x = 200;
        self.game_state.player_y = 200;

        self.is_initialized = true;
    }
};

pub const GameState = struct {
    target_fps: f32,
    height_offset: u32,
    width_offset: u32,
    player_x: u32,
    player_y: u32,
};

pub const Input = struct {
    mouse_x: i32,
    mouse_y: i32,
    mouse_z: i32,
    mouse_buttons: [3]bool,
    key: u32,
    key_released: u32,
    time: u32,
};

pub const LinuxState = struct {
    filename: []const u8,
    recording_file: ?fs.File,
    playback_file: ?fs.File,

    game_input: *Input,
    game_state: *GameState,

    pub fn init(self: *LinuxState) !void {
        self.recording_file = fs.cwd().openFile(self.filename, .{ .mode = .write_only }) catch |err| {
            if (err == fs.File.OpenError.FileNotFound) {
                self.recording_file = try fs.cwd().createFile(self.filename, .{});
                self.playback_file = try fs.cwd().openFile(self.filename, .{ .mode = .read_only });
                return;
            } else {
                return err;
            }
        };

        self.playback_file = try fs.cwd().openFile(self.filename, .{ .mode = .read_only });
    }

    pub fn deinit(self: *LinuxState) void {
        self.recording_file.?.close();
        self.playback_file.?.close();
    }
};

pub const InitialWindowWidth = 960;
pub const InitialWindowHeight = 480;
pub const OffScreenBuffer = struct {
    window_width: u32,
    window_height: u32,
    // Todo: this will not work on resize
    memory: [InitialWindowHeight][InitialWindowWidth]u32,
    pitch: usize,

    pub fn get_memory_size(self: *OffScreenBuffer) usize {
        return self.window_width * self.window_height;
    }
};

const ThreadContext = struct {
    // identifier for the current thread
    handle: u32,
};
