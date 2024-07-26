//

const std = @import("std");
const ulid = @import("./ulid.zig");

const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Ulid = ulid.Ulid;

const DbValueType = enum(u8) {
    dbulid,
    dbsymbol,
    dbu64,
    dbu32,
    dbu16,
    dbu8,
    dbvoid,
};

const DbValue = union(DbValueType) {
    dbulid: *const ulid.Ulid,
    dbsymbol: []const u8,
    dbu64: u64,
    dbu32: u32,
    dbu16: u16,
    dbu8: u8,
    dbvoid: void,

    fn write(value: DbValue, buf: []u8) usize {
        switch (value) {
            .dbu64, .dbu32, .dbu16, .dbu8 => |v| {
                const T = @TypeOf(v);
                const size = @sizeOf(T);
                std.mem.writeInt(T, buf[0..size], v, .little);
                return size;
            },
            .dbulid => |v| return v.write(buf),
            .dbsymbol => |v| {
                assert(v.len < 256);
                buf[0] = @as(u8, @intCast(v.len));
                @memcpy(buf[1 .. v.len + 1], v);
                return v.len + 1;
            },
            .dbvoid => return 0,
        }
    }
};

const DbOperation = enum(u8) {
    insert,
    delete,
};

const EphemeralId = struct { id: u32 };

// const db_types = [_]db_type{ db_type(u64), db_type(u32), db_type(u16), db_type(u8) };

const PageSize = 4096;

const HashSize = 32;
const Hash = [HashSize]u8;

const NonceSize = 12;
const Nonce = [NonceSize]u8;

const Encryption = enum(u8) {
    none,
    aes_gcm,
    chacha20_poly1305,
};

const TxType = enum(u8) {
    tuples,
    merge,
};

const PageHeader = struct {
    signature: Hash, // 32 bytes
    author: Hash, // 32 bytes
    workspace: union { prev: Hash, workspace: Ulid }, // 32 bytes
    height: u32, // 4 bytes
    tx_type: TxType, // 1 byte
};

const TxData = struct {
    tuples: u16, // 2 bytes
    symbols: u32, // symbols in the workspace
    ephemerals: u8, // 1 byte, new symbols in this transaction
    encryption: Encryption, // 1 byte
};

const Tuple = struct {
    e: EphemeralId,
    a: EphemeralId,
    offset: u16,
    v: DbValueType,
    op: DbOperation,
};

const TxPage = struct {
    header: PageHeader,
    tx: TxData,
    data: [PageSize - @sizeOf(PageHeader) - @sizeOf(TxData)]u8,

    fn sources(self: *TxPage) []const Hash {
        const sources_ptr: [*]Hash = @ptrCast(&self.data);
        return sources_ptr[0..self.header.lengths.sources];
    }

    fn tuples(self: *TxPage) []const Tuple {
        const offset = self.header.lengths.sources * @sizeOf(Hash);
        const tuples_ptr: [*]Tuple = @ptrCast(&self.data[offset]);
        return tuples_ptr[0..self.header.lengths.tuples];
    }

    fn values(self: *TxPage) []const u8 {
        const offset = self.header.lengths.sources * @sizeOf(Hash) + self.header.lengths.tuples * @sizeOf(Tuple);
        return &self.data[offset..];
    }
};

pub const Db = struct {
    allocator: std.mem.Allocator,

    merges: std.ArrayListUnmanaged(Hash),
    ulids: std.ArrayListUnmanaged(ulid.Ulid),
    tuples: std.ArrayListUnmanaged(Tuple),
    values: [PageSize]u8,
    last_value: usize,

    fn init(allocator: std.mem.Allocator, sources: []const Hash) !*Db {
        var source_list = try std.ArrayListUnmanaged(Hash).initCapacity(allocator, @max(sources.len, 2));
        try source_list.appendSlice(allocator, sources);
        var db = Db{
            .allocator = allocator,
            .sources = source_list,
            .ulids = try std.ArrayListUnmanaged(Ulid).initCapacity(allocator, 8),
            .tuples = try std.ArrayListUnmanaged(Tuple).initCapacity(allocator, 16),
            .values = undefined,
            .last_value = 0,
        };
        return &db;
    }

    fn commit(self: *Db) !void {
        // count tx page size
        const size = @sizeOf(PageHeader) + @sizeOf(TxData) +
            self.sources.items.len * @sizeOf(Hash) + self.tuples.items.len * @sizeOf(Tuple) + self.last_value;

        const sources = self.sources.items;
        const ulids = self.ulids.items;
        const tuples = self.tuples.items;
        const values = self.values[0..self.last_value];

        const page = TxPage{
            .header = PageHeader{
                .signature = [0]Hash{},
                .author = sources[0],
                .previous = sources[1],
                .height = 0,
            },
            .tx = TxData{
                .nonce = [0]Nonce{},
                .encryption = Encryption.none,
                .merges = 0,
                .tuples = @intCast(u16, tuples.len),
            },
        };

        const sources_ptr: [*]Hash = @ptrCast(&page.data);
        @memcpy(sources_ptr[0..sources.len], sources);

        const tuples_ptr: [*]Tuple = @ptrCast(&page.data[sources.len * @sizeOf(Hash)]);
        @memcpy(tuples_ptr[0..tuples.len], tuples);

        const values_ptr: [*]u8 = @ptrCast(&page.data[sources.len * @sizeOf(Hash) + tuples.len * @sizeOf(Tuple)]);
        @memcpy(values_ptr[0..values.len], values);

        // const page_size = @sizeOf(TxPage);
        // const page_ptr: [*]u8 = @ptrCast(&page);
        // const page_hash = std.crypto.sha256.hash(page_ptr[0..page_size]);

        // const page_hash = std.crypto.sha256.hash(&page);
        // std.debug.print("{any}\n", .{page_hash});
    }

    fn reject(self: *Db) void {
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

fn genesis(allocator: Allocator) !Db {
    const db = try Db.init(
        allocator,
    );

    return db;
}

test "test" {
    const x = DbValue{ .dbu64 = 42 };
    std.debug.print("{any}\n", .{x});

    var buf: [256]u8 = undefined;
    const s = DbValue.write(x, &buf);
    std.debug.print("{any} {d}\n", .{ buf, s });

    const db = try Db.init(std.testing.allocator, &[0]Hash{});
    defer db.deinit();

    try db.insert(EphemeralId{ .id = 1 }, EphemeralId{ .id = 2 }, x);
    std.debug.print("{any}\n", .{db});
}
