const std = @import("std");
const crypto = std.crypto;

pub const Uuid = struct {
    bytes: [16]u8,

    pub fn v4() Uuid {
        var uuid: [16]u8 = undefined;
        crypto.random.bytes(&uuid);
        uuid[6] = (uuid[6] & 0x0f) | 0x40; // version 4
        uuid[8] = (uuid[8] & 0x3f) | 0x80; // variant 1
        return Uuid{ .bytes = uuid };
    }
};
