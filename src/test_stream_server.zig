const std = @import("std");
const log = @import("log.zig");
const server = @import("server.zig");

pub fn main() !void {
    try do(std.heap.page_allocator);
}

fn do(allocator: std.mem.Allocator) !void {
    log.info("started.", .{});

    // key and certificates need to be der-formatted.
    // if you want to use RSAPrivateKey, please change '.ec' to '.rsa'.
    // The procedure to generate test certificate is described in test/gen_cert.sh
    var tls_server = try server.TLSServerTCP.init("./test/key.pem", "./test/cert.der", null, "localhost", allocator);
    defer tls_server.deinit();

    // Enable KEYLOG output.
    tls_server.print_keys = true;

    try tls_server.listen(8443);

    var buf: [32768]u8 = undefined;
    while (true) {
        var con = try tls_server.accept();
        defer {
            con.close();
            log.info("connection closed", .{});
            con.deinit();
        }

        con.handshake() catch |err| {
            switch (err) {
                error.EndOfStream => continue,
                else => return err,
            }
        };

        while (true) {
            const msg_len = con.tlsReader().readInt(u64, .big) catch |err| {
                switch (err) {
                    error.ConnectionResetByPeer => return,
                    error.EndOfStream => return,
                    else => return err,
                }
            };
            try con.tlsWriter().writeInt(u64, msg_len, .big);

            var cur_idx: u64 = 0;
            while (cur_idx < msg_len) {
                var end_idx = cur_idx + buf.len;
                if (end_idx > msg_len) {
                    end_idx = msg_len;
                }
                try con.tlsReader().readNoEof(buf[0 .. end_idx - cur_idx]);

                try con.tlsWriter().writeAll(buf[0 .. end_idx - cur_idx]);
                cur_idx = end_idx;
            }
        }

        return;
    }

    return;
}

test "stream" {
    try do(std.testing.allocator);
}
