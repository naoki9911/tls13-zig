const std = @import("std");
const SupportedGroups = @import("groups.zig").SupportedGroups;
const SupportedVersions = @import("versions.zig").SupportedVersions;
const SignatureAlgorithms = @import("signatures.zig").SignatureAlgorithms;
const KeyShare = @import("key_share.zig").KeyShare;
const HandshakeType = @import("msg.zig").HandshakeType;

pub const ExtensionType = enum(u16) {
    server_name = 0,
    supported_groups = 10,
    signature_algorithms = 13,
    record_size_limit = 28,
    supported_versions = 43,
    key_share = 51,
};

pub const Extension = union(ExtensionType) {
    server_name: ServerName,
    supported_groups: SupportedGroups,
    signature_algorithms: SignatureAlgorithms,
    record_size_limit: RecordSizeLimit,
    supported_versions: SupportedVersions,
    key_share: KeyShare,

    const Self = @This();

    pub fn decode(reader: anytype, allocator: std.mem.Allocator, ht: HandshakeType, hello_retry: bool) !Self {
        const t = @intToEnum(ExtensionType, try reader.readIntBig(u16));
        switch (t) {
            ExtensionType.server_name => return Self { .server_name = try ServerName.decode(reader) },
            ExtensionType.supported_groups => return Self{ .supported_groups = try SupportedGroups.decode(reader, allocator) },
            ExtensionType.signature_algorithms => return Self{ .signature_algorithms = try SignatureAlgorithms.decode(reader, allocator) },
            ExtensionType.record_size_limit => return Self{ .record_size_limit = try RecordSizeLimit.decode(reader) },
            ExtensionType.supported_versions => return Self{ .supported_versions = try SupportedVersions.decode(reader, ht) },
            ExtensionType.key_share => return Self{ .key_share = try KeyShare.decode(reader, allocator, ht, hello_retry) },
        }
    }

    pub fn print(self: Self) void {
        switch (self) {
            ExtensionType.server_name => |e| e.print(),
            ExtensionType.supported_groups => |e| e.print(),
            ExtensionType.signature_algorithms => |e| e.print(),
            ExtensionType.record_size_limit => |e| e.print(),
            ExtensionType.supported_versions => |e| e.print(),
            ExtensionType.key_share => |e| e.print(),

        }
    }

    pub fn length(self: Self) usize {
        switch (self) {
            ExtensionType.server_name => |e| return e.length(),
            ExtensionType.supported_groups => |e| return e.length(),
            ExtensionType.signature_algorithms => |e| return e.length(),
            ExtensionType.record_size_limit => |e| return e.length(),
            ExtensionType.supported_versions => |e| return e.length(),
            ExtensionType.key_share => |e| return e.length(),
        }
    }

    pub fn deinit(self: Self) void {
        switch (self) {
            ExtensionType.supported_groups => |e| e.deinit(),
            ExtensionType.signature_algorithms => |e| e.deinit(),
            ExtensionType.key_share => |e| e.deinit(),
            else => {},
        }
    }
};

//RFC8449 Record Size Limit Extension for TLS
pub const RecordSizeLimit = struct {
    record_size_limit:u16 = undefined,

    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    pub fn decode(reader: anytype) !Self {
        var res = Self.init();

        // type is already read.
        _ = try reader.readIntBig(u16);
        res.record_size_limit = try reader.readIntBig(u16);

        return res;
    }

    pub fn length(self: Self) usize {
        _ = self;
        var len: usize = 0;
        len += @sizeOf(u16); // type
        len += @sizeOf(u16); // length
        len += @sizeOf(u16); // size limit
        return len;
    }

    pub fn print(self: Self) void {
        _ = self;
    }
};

//RFC6066 Transport Layer Security (TLS) Extensions: Extension Definitions
pub const ServerName = struct {
    len:u16 = undefined,

    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    pub fn decode(reader: anytype) !Self {
        var res = Self.init();
        res.len = try reader.readIntBig(u16);

        var i:u16 = 0;
        while (i < res.len) : (i += 1) {
            _ = try reader.readIntBig(u8);
        }

        return res;
    }

    pub fn length(self: Self) usize {
        var len: usize = 0;
        len += @sizeOf(u16); // type
        len += @sizeOf(u16); // length
        len += self.len;
        return len;
    }

    pub fn print(self: Self) void {
        _ = self;
    }
};

const io = std.io;
const expect = std.testing.expect;

test "Extension RecordSizeLimit decode" {
    const recv_data = [_]u8{0x00, 0x1c, 0x00, 0x02, 0x40, 0x01};
    var readStream = io.fixedBufferStream(&recv_data);

    const res = try Extension.decode(readStream.reader(), std.testing.allocator, .server_hello, false);
    try expect(res == .record_size_limit);

    const rsl = res.record_size_limit;
    try expect(rsl.record_size_limit == 16385);
}

test "Extension ServerName decode" {
    const recv_data = [_]u8{0x00, 0x00, 0x00, 0x00};
    var readStream = io.fixedBufferStream(&recv_data);

    const res = try Extension.decode(readStream.reader(), std.testing.allocator, .server_hello, false);
    try expect(res == .server_name);
}