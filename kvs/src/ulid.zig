//

const std = @import("std");
const Order = std.math.Order;

pub const Ulid = struct {
    bytes: [16]u8,

    pub fn eql(self: *const Ulid, other: *const Ulid) bool {
        return std.mem.eql(u8, &self.bytes, &other.bytes);
    }

    pub fn order(self: *const Ulid, other: *const Ulid) Order {
        return std.mem.order(u8, &self.bytes, &other.bytes);
    }

    pub fn write(self: *const Ulid, buf: []u8) usize {
        @memcpy(buf[0..16], &self.bytes);
        return 16;
    }
};

pub const Generator = struct {
    timestamp: u48,
    randomness: [10]u8,

    pub fn next(self: *Generator) Ulid {
        var bytes: [16]u8 = undefined;
        const ts = @as(u48, @intCast(std.time.milliTimestamp()));
        if (ts == self.timestamp) {
            var i: usize = 9;
            while (i >= 0) : (i -= 1) {
                const val = self.randomness[i];
                if (val < 255) {
                    self.randomness[i] = val + 1;
                    break;
                }
                self.randomness[i] = 0;
            }
        } else self.timestamp = ts;
        std.mem.writeInt(u48, bytes[0..6], ts, .big);
        bytes[6..].* = self.randomness;
        return Ulid{
            .bytes = bytes,
        };
    }
};

pub fn ulid() Generator {
    var bytes: [10]u8 = undefined;
    std.crypto.random.bytes(&bytes);
    return Generator{
        .timestamp = 0,
        .randomness = bytes,
    };
}

test "create ulid" {
    var gen = ulid();
    const x = &gen.next();
    const y = &gen.next();
    try std.testing.expectEqual(true, x.eql(x));
    try std.testing.expectEqual(false, x.eql(y));
    try std.testing.expectEqual(.lt, x.order(y));
}
