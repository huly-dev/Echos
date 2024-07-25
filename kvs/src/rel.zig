//

const std = @import("std");
const ulid = @import("./ulid.zig");

const DbValueType = enum(u8) {
    dbulid,
    dbsymbol,
    dbu64,
    dbu32,
    dbu16,
    dbu8,
};

const DbValue = union(DbValueType) {
    dbulid: *const ulid.Ulid,
    dbsymbol: []const u8,
    dbu64: u64,
    dbu32: u32,
    dbu16: u16,
    dbu8: u8,

    fn write(value: DbValue, buf: []u8) usize {
        switch (value) {
            .dbu64, .dbu32, .dbu16, .dbu8 => |v| {
                const T = @TypeOf(v);
                const size = @sizeOf(T);
                std.mem.writeInt(T, buf[0..size], v, .big);
                return size;
            },
            else => unreachable,
        }
    }
};

const DbOperation = enum(u8) {
    insert,
    delete,
};

const EphemeralId = struct { id: u32 };

// const db_types = [_]db_type{ db_type(u64), db_type(u32), db_type(u16), db_type(u8) };

// const PageSize = 4096;

const HashSize = 32;
const Hash = [HashSize]u8;

// const PageHeader = struct { prev_page: Hash };

pub const Db = struct {
    const Tuple = struct {
        e: EphemeralId,
        a: EphemeralId,
        offset: u16,
        v: DbValueType,
        op: DbOperation,
    };

    allocator: std.mem.Allocator,

    sources: std.ArrayListUnmanaged(Hash),
    ulids: std.ArrayListUnmanaged(ulid.Ulid),
    tuples: std.ArrayListUnmanaged(Tuple),
    values: [PageSize]u8,
    last_value: usize,

    fn init(allocator: std.mem.Allocator, sources: []Hash) !*Db {
        const source_list = try std.ArrayListUnmanaged(Hash).initCapacity(allocator, @max(sources.len, 2));
        try source_list.appendSlice(allocator, sources);
        var tx = Db{
            .allocator = allocator,
            .sources = source_list,
            .ulids = try std.ArrayListUnmanaged(ulid.Ulid).initCapacity(allocator, 8),
            .tuples = try std.ArrayListUnmanaged(Tuple).initCapacity(allocator, 16),
            .values = undefined,
            .last_value = 0,
        };
        return &tx;
    }

    fn deinit(self: *Db) void {
        self.tuples.deinit(self.allocator);
        self.ulids.deinit(self.allocator);
        self.sources.deinit(self.allocator);
    }

    fn insert(self: *Db, e: EphemeralId, a: EphemeralId, v: DbValue) !void {
        const offset = self.last_value;
        const value_size = DbValue.write(v, self.values[offset..]);
        self.last_value += value_size;

        const value_type = @as(DbValueType, v);
        const tuple = Tuple{ .e = e, .a = a, .offset = @as(u16, @intCast(offset)), .v = value_type, .op = DbOperation.insert };
        try self.tuples.append(self.allocator, tuple);
    }
};

test "test" {
    const x = DbValue{ .dbu64 = 42 };
    std.debug.print("{any}\n", .{x});

    var buf: [256]u8 = undefined;
    const s = DbValue.write(x, &buf);
    std.debug.print("{any} {d}\n", .{ buf, s });

    const db = try Db.init(std.testing.allocator);
    defer db.deinit();

    try db.insert(EphemeralId{ .id = 1 }, EphemeralId{ .id = 2 }, x);
    std.debug.print("{any}\n", .{tx});
}
