const std = @import("std");
const assert = std.debug.assert;

fn connectSocket(allocator: std.mem.Allocator) !std.posix.socket_t {
    const wayland_display = std.posix.getenv("WAYLAND_DISPLAY") orelse return error.WaylandDisplayMissing;
    const xdg_runtime = std.posix.getenv("XDG_RUNTIME_DIR") orelse return error.XDGRuntimeMissing;

    const socket_path = try std.fs.path.join(allocator, &[_][]const u8{ xdg_runtime, wayland_display });
    defer allocator.free(socket_path);

    var path: [108]u8 = undefined;
    assert(socket_path.len <= 108);
    @memcpy(path[0..socket_path.len], socket_path);
    path[socket_path.len] = 0;

    const socket = try std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0);
    const addr = std.posix.sockaddr.un{ .path = path };

    try std.posix.connect(socket, @ptrCast(&addr), @sizeOf(@TypeOf(addr)));
    return socket;
}

pub fn conn(allocator: std.mem.Allocator) !void {
    _ = try connectSocket(allocator);
}
