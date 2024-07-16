const std = @import("std");

pub const ALPN = struct {
    buf: []u8,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, len: usize) !Self {
        return .{
            .buf = try allocator.alloc(u8, len),
            .allocator = allocator,
        };
    }

    pub fn decode(reader: anytype, len: usize, allocator: std.mem.Allocator) !Self {
        const buf = try allocator.alloc(u8, len);
        errdefer allocator.free(buf);

        _ = try reader.read(buf);
        return Self{
            .buf = buf,
            .allocator = allocator,
        };
    }

    pub fn encode(self: Self, writer: anytype) !usize {
        return try writer.write(self.buf);
    }

    pub fn deinit(self: Self) void {
        self.allocator.free(self.buf);
    }

    pub fn length(self: Self) usize {
        return self.buf.len;
    }
};
