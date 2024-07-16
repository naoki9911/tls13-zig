const std = @import("std");
const log = @import("log.zig");

/// RFC5746 Seection 4.2.3 3.2. Extension Definition
///
///  struct {
///      opaque renegotiated_connection<0..255>;
///  } RenegotiationInfo;
pub const RenegotiationInfo = struct {
    const Self = @This();

    renegotinated_connection: []u8,
    allocator: std.mem.Allocator,

    /// initialize RenegotiationInfo.
    /// @param allocator allocator to allocate renegotinated_connection.
    /// @param len   length of renegotinated_connection.
    /// @return initialized KeyShareEntry.
    pub fn init(allocator: std.mem.Allocator, len: usize) !Self {
        return Self{
            .renegotinated_connection = try allocator.alloc(u8, len),
            .allocator = allocator,
        };
    }

    /// decode RenegotiationInfo reading from io.Reader.
    /// @param reader    io.Reader to read messages.
    /// @param allocator allocator to initialize RenegotiationInfo.
    /// @return decoded RenegotiationInfo.
    pub fn decode(reader: anytype, allocator: std.mem.Allocator, len: usize) !Self {
        const con = try allocator.alloc(u8, len);
        errdefer allocator.free(con);
        try reader.readNoEof(con);

        return Self{
            .renegotinated_connection = con,
            .allocator = allocator,
        };
    }

    /// encode RenegotiationInfo writing to io.Writer.
    /// @param self   RenegotiationInfo to be encoded.
    /// @param writer io.Writer to write encoded RenegotiationInfo.
    /// @return length of encoded RenegotiationInfo.
    pub fn encode(self: Self, writer: anytype) !usize {
        return try writer.write(self.renegotinated_connection);
    }

    /// get the length of encoded RenegotiationInfo.
    /// @param self the target RenegotiationInfo.
    /// @return length of encoded RenegotiationInfo.
    pub fn length(self: Self) usize {
        return self.renegotinated_connection.len;
    }

    /// deinitialize RenegotiationInfo.
    /// @param self RenegotiationInfo to be deinitialized.
    pub fn deinit(self: Self) void {
        self.allocator.free(self.renegotinated_connection);
    }

    pub fn print(self: Self) void {
        log.debug("Extension: RenegotiationInfo", .{});
        log.debug("- {s}", .{std.fmt.fmtSliceHexLower(self.renegotinated_connection)});
    }
};
