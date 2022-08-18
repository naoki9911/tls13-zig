const std = @import("std");
const io = std.io;
const log = std.log;
const assert = std.debug.assert;
const msg = @import("msg.zig");
const ArrayList = std.ArrayList;
const NamedGroup = msg.NamedGroup;
const HandshakeType = msg.HandshakeType;

pub const KeyShare = struct {
    entries: ArrayList(KeyShareEntry) = undefined, // for ClientHello
    selected: NamedGroup = undefined, // for HelloRetryRequest

    ht: HandshakeType = undefined,
    is_hello_retry_request: bool = false,
    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, ht: HandshakeType, hello_retry: bool) Self {
        return .{
            .entries = ArrayList(KeyShareEntry).init(allocator),
            .ht = ht,
            .is_hello_retry_request = hello_retry,
        };
    }

    pub fn decode(reader: anytype, allocator: std.mem.Allocator, ht: HandshakeType, hello_retry: bool) !Self {
        var res = Self.init(allocator, ht, hello_retry);

        // type is already read
        const len = try reader.readIntBig(u16);
        switch (res.ht) {
            HandshakeType.client_hello => {
                const ks_len = try reader.readIntBig(u16);
                assert(len == ks_len + 2);
                var i: usize = 0;
                while (i < ks_len) {
                    var kse = try KeyShareEntry.decode(reader);
                    try res.entries.append(kse);
                    i += kse.length();
                }
                assert(i == ks_len);
            },
            HandshakeType.server_hello => {
                if (res.is_hello_retry_request) {
                    res.selected = @intToEnum(NamedGroup, try reader.readIntBig(u16));
                } else {
                    try res.entries.append(try KeyShareEntry.decode(reader));
                }
            },
            else => unreachable,
        }

        return res;
    }

    pub fn length(self: Self) usize {
        var len: usize = 0;
        len += @sizeOf(u16); // type
        len += @sizeOf(u16); // length
        switch (self.ht) {
            HandshakeType.client_hello => {
                len += @sizeOf(u16); // entries length
                for (self.entries.items) |entry| {
                    len += entry.length();
                }
            },
            HandshakeType.server_hello => {
                if (self.is_hello_retry_request) {
                    len += @sizeOf(u16);
                } else {
                    len += self.entries.items[0].length();
                }
            },
            else => unreachable,
        }
        return len;
    }

    pub fn deinit(self: Self) void {
        self.entries.deinit();
    }

    pub fn print(self: Self) void {
        log.debug("Extension: KeyShare({s})", .{@tagName(self.ht)});
        if (self.is_hello_retry_request) {
            log.debug("- SelectedGroup = {s}(0x{x:0>4})", .{ @tagName(self.selected), @enumToInt(self.selected) });
        } else {
            for (self.entries.items) |e| {
                e.print();
            }
        }
    }
};

pub const KeyShareEntry = union(NamedGroup) {
    x25519: EntryX25519,
    x448: KeyShareEntryDummy,
    secp256r1: EntrySecp256r1,
    secp521r1: KeyShareEntryDummy,
    secp384r1: KeyShareEntryDummy,
    ffdhe2048: KeyShareEntryDummy,
    ffdhe3072: KeyShareEntryDummy,
    ffdhe4096: KeyShareEntryDummy,
    ffdhe6144: KeyShareEntryDummy,
    ffdhe8192: KeyShareEntryDummy,

    const Self = @This();

    pub fn decode(reader: anytype) !Self {
        const t = @intToEnum(NamedGroup, try reader.readIntBig(u16));
        switch (t) {
            NamedGroup.x25519 => return Self{ .x25519 = try EntryX25519.decode(reader) },
            NamedGroup.secp256r1 => return Self{ .secp256r1 = try EntrySecp256r1.decode(reader) },
            else => unreachable,
        }
    }

    pub fn length(self: Self) usize {
        switch (self) {
            NamedGroup.x25519 => |e| return e.length(),
            NamedGroup.secp256r1 => |e| return e.length(),
            else => unreachable,
        }
    }

    pub fn print(self: Self) void {
        switch (self) {
            NamedGroup.x25519 => |e| e.print(),
            NamedGroup.secp256r1 => |e| e.print(),
            else => unreachable,
        }
    }
};

pub const EntryX25519 = struct {
    key_exchange: [32]u8 = [_]u8{0} ** 32,

    const Self = @This();

    pub fn decode(reader: anytype) !Self {
        var res: Self = .{};

        // type is alread read.
        const len = try reader.readIntBig(u16);
        assert(len == res.key_exchange.len);

        const read_len = try reader.readAll(&res.key_exchange);
        assert(read_len == len);

        return res;
    }

    pub fn length(self: Self) usize {
        var len: usize = 0;
        len += @sizeOf(u16); // group
        len += @sizeOf(u16); // key_exchange length
        len += self.key_exchange.len;
        return len;
    }

    pub fn print(self: Self) void {
        log.debug("- KeyShare X25519", .{});
        log.debug("  - key = {}", .{std.fmt.fmtSliceHexLower(&self.key_exchange)});
    }
};

pub const EntrySecp256r1 = struct {
    const Secp256r1 = std.crypto.sign.ecdsa.EcdsaP256Sha256;

    key_exchange: [Secp256r1.PublicKey.uncompressed_sec1_encoded_length]u8 = undefined,

    const Self = @This();

    pub fn decode(reader: anytype) !Self {
        var res: Self = .{};

        // type is alread read.
        const len = try reader.readIntBig(u16);
        assert(len == res.key_exchange.len);

        const read_len = try reader.readAll(&res.key_exchange);
        assert(read_len == len);

        return res;
    }

    pub fn length(self: Self) usize {
        var len: usize = 0;
        len += @sizeOf(u16); // group
        len += @sizeOf(u16); // key_exchange length
        len += self.key_exchange.len;
        return len;
    }

    pub fn print(self: Self) void {
        log.debug("- KeyShare Secp256r1", .{});
        log.debug("  - key = {}", .{std.fmt.fmtSliceHexLower(&self.key_exchange)});
    }
};

const KeyShareEntryDummy = struct {};

const expect = std.testing.expect;

test "EntryX25519 decode" {
    const recv_data = [_]u8{ 0x00, 0x26, 0x00, 0x24, 0x00, 0x1d, 0x00, 0x20, 0x49, 0x6c, 0xc8, 0x42, 0x40, 0x7f, 0x7e, 0x62, 0xad, 0x5c, 0xd3, 0x92, 0x97, 0xf7, 0x7f, 0xfc, 0x6c, 0x72, 0x83, 0xba, 0xcb, 0x89, 0x4b, 0x58, 0x20, 0x16, 0x24, 0xae, 0x27, 0xbe, 0x87, 0x2f };
    var readStream = io.fixedBufferStream(&recv_data);

    const res = try KeyShare.decode(readStream.reader(), std.testing.allocator, .client_hello, false);
    defer res.deinit();
    try expect(res.entries.items.len == 1);
    try expect(res.entries.items[0] == .x25519);
    const x25519 = res.entries.items[0].x25519;

    const key_exchg_ans = [_]u8{ 0x49, 0x6c, 0xc8, 0x42, 0x40, 0x7f, 0x7e, 0x62, 0xad, 0x5c, 0xd3, 0x92, 0x97, 0xf7, 0x7f, 0xfc, 0x6c, 0x72, 0x83, 0xba, 0xcb, 0x89, 0x4b, 0x58, 0x20, 0x16, 0x24, 0xae, 0x27, 0xbe, 0x87, 0x2f };
    try expect(x25519.key_exchange.len == key_exchg_ans.len);

    var i: usize = 0;
    while (i < key_exchg_ans.len) : (i += 1) {
        try expect(x25519.key_exchange[i] == key_exchg_ans[i]);
    }
}

test "EntrySecp256r1 decode" {
    const recv_data = [_]u8{ 0x00, 0x17, 0x00, 0x41, 0x04, 0xf9, 0x38, 0x90, 0xa1, 0x01, 0x82, 0xe6, 0xe4, 0xd9, 0x85, 0x60, 0x3a, 0x43, 0x35, 0xfa, 0x77, 0x68, 0x3f, 0x87, 0x69, 0x37, 0xd5, 0xde, 0xda, 0x19, 0x35, 0x1a, 0x7b, 0xbe, 0x21, 0x93, 0x0e, 0x21, 0xf2, 0xe5, 0xf4, 0x18, 0xa3, 0x9d, 0xc1, 0xfb, 0x2f, 0xab, 0xdd, 0x0a, 0xdb, 0x45, 0x9d, 0x79, 0x7f, 0xb9, 0x59, 0x14, 0xb6, 0xe5, 0xda, 0x62, 0xf9, 0xdd, 0x93, 0x20, 0xe7, 0x86, 0xf8 };
    var readStream = io.fixedBufferStream(&recv_data);

    const res = try KeyShareEntry.decode(readStream.reader());
    try expect(res == .secp256r1);
    const x25519 = res.secp256r1;

    const key_exchg_ans = [_]u8{ 0x04, 0xf9, 0x38, 0x90, 0xa1, 0x01, 0x82, 0xe6, 0xe4, 0xd9, 0x85, 0x60, 0x3a, 0x43, 0x35, 0xfa, 0x77, 0x68, 0x3f, 0x87, 0x69, 0x37, 0xd5, 0xde, 0xda, 0x19, 0x35, 0x1a, 0x7b, 0xbe, 0x21, 0x93, 0x0e, 0x21, 0xf2, 0xe5, 0xf4, 0x18, 0xa3, 0x9d, 0xc1, 0xfb, 0x2f, 0xab, 0xdd, 0x0a, 0xdb, 0x45, 0x9d, 0x79, 0x7f, 0xb9, 0x59, 0x14, 0xb6, 0xe5, 0xda, 0x62, 0xf9, 0xdd, 0x93, 0x20, 0xe7, 0x86, 0xf8 };
    try expect(x25519.key_exchange.len == key_exchg_ans.len);

    var i: usize = 0;
    while (i < key_exchg_ans.len) : (i += 1) {
        try expect(x25519.key_exchange[i] == key_exchg_ans[i]);
    }
}
