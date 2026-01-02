const std = @import("std");

// Resources:
// https://wayland-book.com/
// https://gaultier.github.io/blog/wayland_from_scratch.html
// https://wayland.app/protocols/
//
// Protocol
// vi /usr/share/wayland/wayland.xml

const ObjectId = enum(u32) {
    Invalid,
    Display,
    Registry,
    Callback,
    Compositor,
};

const Header = packed struct {
    id: ObjectId,
    // Note: opcode is the index of the request within the interface in the protocol xml
    op: u16,
    // Note: size includes size of header and message
    message_size: u16,
};

const Id = struct {
    id: u32 = 2,

    fn newId(self: *Id) u32 {
        defer self.id += 1;
        return self.id;
    }
};

const EventIt = struct {
    buf: []u8,

    const Output = struct {
        header: Header,
        data: []u8,
    };

    fn next(self: *EventIt) ?Output {
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

        return .{
            .header = header,
            .data = data,
        };
    }

    fn consume(self: *EventIt, consume_len: usize) void {
        if (self.buf.len == consume_len) {
            self.buf = &.{};
            return;
        }

        self.buf = self.buf[consume_len..];
    }
};

const ErrorEvent = struct {
    buf: []u8,

    const Args = struct {
        object_id: u32,
        code: u32,
        message: []const u8,
    };

    fn parseEvent(self: *ErrorEvent) !Args {
        if (self.buf.len < @sizeOf(Args)) {
            return error.InvalidErrorEventArgs;
        }

        const object_id = std.mem.bytesToValue(u32, self.buf[0..@sizeOf(u32)]);
        self.consume(@sizeOf(u32));
        const code = std.mem.bytesToValue(u32, self.buf[0..@sizeOf(u32)]);
        self.consume(@sizeOf(u32));

        const msg_len = std.mem.bytesToValue(u32, self.buf[0..@sizeOf(u32)]);
        self.consume(@sizeOf(u32));

        const msg = self.buf[0..msg_len];
        self.consume(msg_len);

        return Args{
            .object_id = object_id,
            .code = code,
            .message = msg,
        };
    }

    fn consume(self: *ErrorEvent, consume_len: usize) void {
        if (self.buf.len == consume_len) {
            self.buf = &.{};
            return;
        }

        self.buf = self.buf[consume_len..];
    }
};

fn handleDisplayEvent(output: EventIt.Output) !void {
    switch (output.header.op) {
        0 => {
            var error_event = ErrorEvent{ .buf = output.data };
            const error_object = try error_event.parseEvent();
            std.log.err("display error: {s}\n", .{error_object.message});
            return;
        },
        else => std.log.warn("todo\n", .{}),
    }
}

const RegistryEvent = struct {
    buf: []u8,

    const Bind = struct {
        name: u32,
        id: u32,
    };

    const Global = struct {
        name: u32,
        interface: []const u8,
        version: u32,
    };

    fn parseBindEvent(self: *RegistryEvent) !Bind {
        if (self.buf.len < @sizeOf(Bind)) {
            return error.InvalidErrorEventArgs;
        }

        const name = std.mem.bytesToValue(u32, self.buf[0..@sizeOf(u32)]);
        self.consume(@sizeOf(u32));

        const id = std.mem.bytesToValue(u32, self.buf[0..@sizeOf(u32)]);
        self.consume(@sizeOf(u32));

        return Bind{
            .name = name,
            .id = id,
        };
    }

    fn intSize(T: type, bytes: T) T {
        return ((bytes + @sizeOf(T) - 1) & ~@as(T, (@sizeOf(T) - 1)));
    }

    fn parseGlobalEvent(self: *RegistryEvent) ?Global {
        if (self.buf.len < @sizeOf(Global)) {
            return null;
        }

        const name = std.mem.bytesToValue(u32, self.buf[0..@sizeOf(u32)]);
        self.consume(@sizeOf(u32));

        const interface_len = std.mem.bytesToValue(u32, self.buf[0..@sizeOf(u32)]);
        self.consume(@sizeOf(u32));

        const interface = self.buf[0..interface_len];
        self.consume(intSize(u32, interface_len));

        const version = std.mem.bytesToValue(u32, self.buf[0..@sizeOf(u32)]);
        self.consume(@sizeOf(u32));

        return Global{
            .name = name,
            .interface = interface,
            .version = version,
        };
    }

    fn consume(self: *RegistryEvent, consume_len: usize) void {
        if (self.buf.len == consume_len) {
            self.buf = &.{};
            return;
        }

        self.buf = self.buf[consume_len..];
    }
};

fn handleRegistryEvent(output: EventIt.Output) !void {
    switch (output.header.op) {
        0 => {
            var registry = RegistryEvent{ .buf = output.data };
            const global = registry.parseGlobalEvent();
            if (global) |g| {
                std.log.info("Name:{d}, Interface:{s}, Version:{d}", .{ g.name, g.interface, g.version });
            }
            return;
        },
        1 => {
            var registry = RegistryEvent{ .buf = output.data };
            _ = registry.parseGlobalEvent();
            return;
        },
        else => std.log.warn("todo\n", .{}),
    }
}

fn getRegistry(socket: std.posix.socket_t, buf: []u8, new_id: u32) !usize {
    const Request = packed struct {
        header: Header,
        new_id: u32,
    };

    const h = Header{ .id = ObjectId.Display, .op = 1, .message_size = @sizeOf(Request) };
    var m = Request{ .header = h, .new_id = new_id };

    const msg: []const u8 = std.mem.asBytes(&m);
    const sent_len = try std.posix.send(socket, msg, 0);
    std.debug.assert(msg.len == sent_len);

    return std.posix.read(socket, buf);
}

fn createSurface(socket: std.posix.socket_t, buf: []u8, new_id: u32) !usize {
    const Request = packed struct {
        header: Header,
        new_id: u32,
    };

    // Todo: Find XDG protocol file
    const h = Header{ .id = ObjectId.Compositor, .op = 0, .message_size = @sizeOf(Request) };
    var m = Request{ .header = h, .new_id = new_id };

    const msg: []const u8 = std.mem.asBytes(&m);
    const sent_len = try std.posix.send(socket, msg, 0);
    std.debug.assert(msg.len == sent_len);

    return std.posix.read(socket, buf);
}

fn getXDGSurface(socket: std.posix.socket_t, buf: []u8, new_id: u32) !usize {
    const Request = packed struct {
        header: Header,
        new_id: u32,
    };

    const h = Header{ .id = ObjectId.Compositor, .op = 0, .message_size = @sizeOf(Request) };
    var m = Request{ .header = h, .new_id = new_id };

    const msg: []const u8 = std.mem.asBytes(&m);
    const sent_len = try std.posix.send(socket, msg, 0);
    std.debug.assert(msg.len == sent_len);

    return std.posix.read(socket, buf);
}

pub fn conn(allocator: std.mem.Allocator) !void {
    const socket = try connectSocket(allocator);

    var buf: [4096]u8 = undefined;
    var id = Id{};
    var event_bytes = try getRegistry(socket, &buf, id.newId());

    var event_it: EventIt = .{ .buf = buf[0..event_bytes] };
    while (event_it.next()) |o| {
        switch (o.header.id) {
            .Display => try handleDisplayEvent(o),
            .Registry => try handleRegistryEvent(o),
            else => std.log.err("invalid object id: {d}\n", .{o.header.id}),
        }
    }

    const surface_id = id.newId();
    event_bytes = try createSurface(socket, &buf, surface_id);
}

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
