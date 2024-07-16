const std = @import("std");
const utils = @import("utils.zig");
const ArrayList = std.ArrayList;
const expect = std.testing.expect;

/// RFC9000 Section 16. Variable-Length Integer Encoding
///
/// 2MSB	Length	Usable Bits	Range
/// 00	1	6	0-63
/// 01	2	14	0-16383
/// 10	4	30	0-1073741823
/// 11	8	62	0-4611686018427387903
pub const VLI = struct {
    value: u64,
    length: u8,

    const Self = @This();

    pub fn decodeFromReader(reader: anytype) !Self {
        const fb = try reader.readInt(u8, .big);
        const type_bits: u2 = @intCast((fb >> 6) & 0x3);
        switch (type_bits) {
            0 => {
                return .{
                    .value = @intCast(fb & 0x3F),
                    .length = 1,
                };
            },
            1 => {
                var tmp_buf = [1]u8{0} ** 2;
                _ = try reader.read(tmp_buf[1..2]);
                tmp_buf[0] = fb & 0x3F;
                return .{
                    .value = @intCast(std.mem.readInt(u16, &tmp_buf, .big)),
                    .length = 2,
                };
            },
            2 => {
                var tmp_buf = [1]u8{0} ** 4;
                _ = try reader.read(tmp_buf[1..4]);
                tmp_buf[0] = fb & 0x3F;
                return .{
                    .value = @intCast(std.mem.readInt(u32, &tmp_buf, .big)),
                    .length = 4,
                };
            },
            3 => {
                var tmp_buf = [1]u8{0} ** 8;
                _ = try reader.read(tmp_buf[1..8]);
                tmp_buf[0] = fb & 0x3F;
                return .{
                    .value = @intCast(std.mem.readInt(u64, &tmp_buf, .big)),
                    .length = 8,
                };
            },
        }
    }

    pub fn encodeToWriter(self: Self, writer: anytype) !usize {
        switch (self.length) {
            1 => {
                const type_byte: u8 = @intCast(self.value & 0x3F);
                try writer.writeByte(type_byte);
                return 1;
            },
            2 => {
                var tmp_buf = [1]u8{0} ** 2;
                std.mem.writeInt(u16, &tmp_buf, @intCast(self.value), .big);
                tmp_buf[0] = (tmp_buf[0] & 0x3F) | (1 << 6);
                return try writer.write(&tmp_buf);
            },
            4 => {
                var tmp_buf = [1]u8{0} ** 4;
                std.mem.writeInt(u32, &tmp_buf, @intCast(self.value), .big);
                tmp_buf[0] = (tmp_buf[0] & 0x3F) | (2 << 6);
                return try writer.write(&tmp_buf);
            },
            8 => {
                var tmp_buf = [1]u8{0} ** 8;
                std.mem.writeInt(u64, &tmp_buf, @intCast(self.value), .big);
                tmp_buf[0] = (tmp_buf[0] & 0x3F) | (3 << 6);
                return try writer.write(&tmp_buf);
            },
            else => @panic("invalid length"),
        }
    }
};

test "VLI encode and decode" {
    var buf = [_]u8{0} ** 8;
    var stream = std.io.fixedBufferStream(&buf);

    var vli = VLI{
        .value = 0xFF,
        .length = 1,
    };
    var write_len = try vli.encodeToWriter(stream.writer());
    try expect(write_len == 1);
    stream.reset();
    var vli_dec = try VLI.decodeFromReader(stream.reader());
    try expect(vli_dec.length == 1);
    try expect(vli_dec.value == 0x3F);

    stream.reset();
    vli = VLI{
        .value = 42,
        .length = 2,
    };
    write_len = try vli.encodeToWriter(stream.writer());
    try expect(write_len == 2);
    stream.reset();
    vli_dec = try VLI.decodeFromReader(stream.reader());
    try expect(vli_dec.length == 2);
    try expect(vli_dec.value == 42);

    stream.reset();
    vli = VLI{
        .value = 42,
        .length = 4,
    };
    write_len = try vli.encodeToWriter(stream.writer());
    try expect(write_len == 4);
    stream.reset();
    vli_dec = try VLI.decodeFromReader(stream.reader());
    try expect(vli_dec.length == 4);
    try expect(vli_dec.value == 42);

    stream.reset();
    vli = VLI{
        .value = 42,
        .length = 8,
    };
    write_len = try vli.encodeToWriter(stream.writer());
    try expect(write_len == 8);
    stream.reset();
    vli_dec = try VLI.decodeFromReader(stream.reader());
    try expect(vli_dec.length == 8);
    try expect(vli_dec.value == 42);
}

/// RFC9000 18.2. Transport Parameter Definitions
pub const TransportParameterType = enum(u8) {
    original_destination_connection_id = 0x00,
    max_idle_timeout = 0x01,
    stateless_reset_token = 0x02,
    max_udp_payload_size = 0x03,
    initial_max_data = 0x4,
    initial_max_stream_data_bidi_local = 0x5,
    initial_max_stream_data_bidi_remote = 0x6,
    initial_max_stream_data_uni = 0x07,
    initial_max_streams_bidi = 0x8,
    initial_max_streams_uni = 0x09,
    ack_delay_exponent = 0x0a,
    max_ack_delay = 0x0b,
    disable_active_migration = 0x0c,
    preferred_address = 0x0d,
    active_connection_id_limit = 0x0e,
    initial_source_connection_id = 0x0f,
    retry_source_connection_id = 0x10,
    grease = 0xff,
};

pub const TransportParameters = struct {
    params: ArrayList(TransportParameter),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .params = ArrayList(TransportParameter).init(allocator),
        };
    }

    pub fn deinit(self: Self) void {
        for (self.params.items) |p| {
            p.deinit();
        }
        self.params.deinit();
    }

    pub fn decode(reader: anytype, len: usize, allocator: std.mem.Allocator) !Self {
        var params = ArrayList(TransportParameter).init(allocator);
        var i: usize = 0;
        while (i < len) {
            const p = try TransportParameter.decode(reader, allocator);
            i += p.length();
            try params.append(p);
        }

        return .{
            .params = params,
        };
    }

    pub fn encode(self: Self, writer: anytype) !usize {
        var len: usize = 0;
        for (self.params.items) |p| {
            len += try p.encode(writer);
        }

        return len;
    }

    pub fn length(self: Self) usize {
        var len: usize = 0;
        for (self.params.items) |p| {
            len += p.length();
        }

        return len;
    }
};

/// RFC9000 18. Transport Parameter Encoding
pub const TransportParameter = struct {
    id: TransportParameterType,
    id_vli: VLI,
    len: VLI,
    value: []u8,
    allocator: std.mem.Allocator,

    pub const Error = error{
        UnexpectedType,
    };

    const Self = @This();
    pub fn init(id: TransportParameterType, len: usize, allocator: std.mem.Allocator) !Self {
        return .{
            .id = id,
            .id_vli = .{ .length = 1, .value = @intFromEnum(id) },
            .len = .{ .length = 1, .value = len },
            .value = try allocator.alloc(u8, len),
            .allocator = allocator,
        };
    }
    pub fn deinit(self: Self) void {
        self.allocator.free(self.value);
    }

    pub fn decode(reader: anytype, allocator: std.mem.Allocator) !Self {
        const id_vli = try VLI.decodeFromReader(reader);
        const length_vli = try VLI.decodeFromReader(reader);
        const value = try allocator.alloc(u8, length_vli.value);
        errdefer allocator.free(value);
        _ = try reader.read(value);

        // Handle GREASE
        var id = TransportParameterType.grease;
        if (id_vli.value < 0xFF) {
            id = utils.intToEnum(TransportParameterType, @intCast(id_vli.value)) catch TransportParameterType.grease;
        }

        return Self{
            .id = id,
            .id_vli = id_vli,
            .len = length_vli,
            .value = value,
            .allocator = allocator,
        };
    }

    pub fn encode(self: Self, writer: anytype) !usize {
        var len: usize = 0;
        const id_vli = VLI{
            .value = @intFromEnum(self.id),
            .length = 1,
        };
        len += try id_vli.encodeToWriter(writer);
        len += try self.len.encodeToWriter(writer);
        len += try writer.write(self.value);

        return len;
    }

    pub fn length(self: Self) usize {
        return self.id_vli.length + self.len.length + self.value.len;
    }
};

test "decode TransportParameters" {
    const len = 0x32;
    // zig fmt: off
    const exts = [_]u8{
        0x04, 0x08, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0x05, 0x04, 0x80, 0x00, 0xFF, 0xFF, 0x07, 0x04, 0x80, 0x00,
        0xFF, 0xFF, 0x08, 0x01, 0x10, 0x01, 0x04, 0x80, 0x00, 0x75,
        0x30, 0x09, 0x01, 0x10, 0x0F, 0x08, 0x83, 0x94, 0xC8, 0xF0,
        0x3E, 0x51, 0x57, 0x08, 0x06, 0x04, 0x80, 0x00, 0xFF, 0xFF
    };
    // zig fmt: on

    var stream = std.io.fixedBufferStream(&exts);
    var params = try TransportParameters.decode(stream.reader(), len, std.testing.allocator);
    defer params.deinit();

    var buf = [_]u8{0} ** exts.len;
    var streamEncode = std.io.fixedBufferStream(&buf);
    const encode_len = try params.encode(streamEncode.writer());
    try expect(encode_len == exts.len);
    try expect(std.mem.eql(u8, &exts, &buf));
}

test "encode TransportParameters" {}
