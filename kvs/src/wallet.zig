const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.io.Writer;

const Blake3 = std.crypto.hash.Blake3;
const argon2 = std.crypto.pwhash.argon2;

const Wallet = struct {
    master_key: [32]u8 = undefined,
};

fn Mnemonic(comptime N: comptime_int) type {
    if (N != 12 and N != 15 and N != 18 and N != 21 and N != 24)
        @compileError("Invalid mnemonic length. Only 12, 15, 18, 21, or 24 allowed.");

    return struct {
        mnemonic: [N]u11 = undefined,

        const Self = @This();

        fn init() Self {
            var mnemonic = Self{ .mnemonic = undefined };
            mnemonic.generate();
            return mnemonic;
        }

        fn generate(self: *Self) void {
            var entropy_checksum: [N * 8 + 1]u8 align(2) = undefined;
            const entropy = entropy_checksum[0 .. N * 8];
            std.crypto.random.bytes(entropy);

            var hash: [32]u8 = undefined;
            var blake = Blake3.init(.{});
            blake.update(entropy);
            blake.final(&hash);

            entropy_checksum[N * 8] = hash[0];
            const ptr: [*]u11 = @ptrCast(&entropy_checksum);
            @memcpy(self.mnemonic[0..N], ptr[0..N]);
        }

        fn passphrase(self: Self, allocator: Allocator) ![]u8 {
            var buf = std.ArrayList(u8).init(allocator);

            var writer = buf.writer();
            for (self.mnemonic[0 .. N - 1]) |word| {
                try writer.print("{d} ", .{word});
            }
            try writer.print("{d}", .{self.mnemonic[N - 1]});
            return try buf.toOwnedSlice();
        }

        fn derive_key(self: Self, allocator: Allocator) ![32]u8 {
            const password = try self.passphrase(allocator);
            defer allocator.free(password);
            var derived_key: [32]u8 = undefined;
            try argon2.kdf(
                allocator,
                &derived_key,
                password,
                "mnemonic",
                argon2.Params.sensitive_2i,
                argon2.Mode.argon2i,
            );
            return derived_key;
        }
    };
}

test "test mnemonic" {
    const mnemonic = Mnemonic(15).init();
    std.debug.print("wallet: {any}\n", .{mnemonic});

    const passphrase = try mnemonic.passphrase(std.testing.allocator);
    defer std.testing.allocator.free(passphrase);
    std.debug.print("passphrase: {s}\n", .{passphrase});

    const derived_key = try mnemonic.derive_key(std.testing.allocator);
    std.debug.print("derived key: {x}\n", .{derived_key});
}
