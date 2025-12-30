const std = @import("std");

fn connectSocket(allocator: std.mem.Allocator) !std.posix.socket_t {
    const wayland_display = std.posix.getenv("WAYLAND_DISPLAY") orelse return error.WaylandDisplayMissing;
    const xdg_runtime = std.posix.getenv("XDG_RUNTIME_DIR") orelse return error.XDGRuntimeMissing;

    const socket_path = try std.fs.path.joinZ(allocator, &.{ xdg_runtime, wayland_display });
    defer allocator.free(socket_path);

    var addr = std.posix.sockaddr.un{ .path = undefined };
    if (socket_path.len >= addr.path.len) {
        std.log.err("Path len: {d} | Socket path len: {d}\n", .{ addr.path.len, socket_path.len });
        return error.PathTooLong;
    }

    var path = [_]u8{0} ** addr.path.len;
    @memcpy(path[0..socket_path.len], socket_path);
    addr.path = path;

    const socket = try std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0);
    try std.posix.connect(socket, @ptrCast(&addr), @sizeOf(@TypeOf(addr)));
    return socket;
}

const Header = packed struct {
    object_id: u32,
    // Note: opcode is the index of the request within the interface in the protocol xml
    op: u16,
    // Note: size includes size of header and message
    message_size: u16,
};

const Request = packed struct {
    header: Header,
    new_id: u32,
};

const Event = struct {
    header: Header,
    data: []u8,
};

const Response = struct {
    buf: []u8,

    fn next(self: *Response) ?Event {
        const header_size = @sizeOf(Header);
        if (self.buf.len < header_size) {
            return null;
        }

        const header = std.mem.bytesToValue(Header, self.buf);

        if (self.buf.len < header.message_size) {
            return null;
        }
        const data = self.buf[header_size..header.message_size];
        self.consume(header.message_size);

        return Event{
            .header = header,
            .data = data,
        };
    }

    fn consume(self: *Response, bytes: usize) void {
        self.buf = self.buf[bytes..];
    }
};

pub fn conn(allocator: std.mem.Allocator) !void {
    const socket = try connectSocket(allocator);

    const h = Header{ .object_id = 1, .op = 1, .message_size = @sizeOf(Request) };
    var m = Request{ .header = h, .new_id = 2 };

    const msg: []const u8 = std.mem.asBytes(&m);
    const sent_len = try std.posix.send(socket, msg, 0);

    std.debug.assert(msg.len == sent_len);

    var buf: [1024]u8 = undefined;
    const read_bytes = try std.posix.read(socket, &buf);

    var res: Response = .{ .buf = buf[0..read_bytes] };
    while (res.next()) |e| {
        std.debug.print("ObjectId:{d}, Op:{d}, Len:{d}, Data:{any}\n", .{ e.header.object_id, e.header.op, e.header.message_size, e.data });
    }
}
