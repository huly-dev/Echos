//

const std = @import("std");
const ulid = @import("./ulid.zig");

const assert = std.debug.assert;
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Ulid = ulid.Ulid;

// D A T A B A S E  T Y P E S

const DbValueType = enum(u8) {
    dbsymbol,
    dbid,
    dbu64,
    dbu32,
    dbu16,
    dbu8,
    dbvoid,
    dbchar,
};

const EphemeralId = struct { id: usize };

const DbValue = union(DbValueType) {
    dbsymbol: *const Ulid,
    dbid: EphemeralId, // this is ephemeral id pointing to symbol
    dbu64: u64,
    dbu32: u32,
    dbu16: u16,
    dbu8: u8,
    dbvoid: void,
    dbchar: []const u8,
};

// D A T A B A S E  P A G E S

const PageSize = 4096;
const HashSize = 32;
const Hash = [HashSize]u8;

const WorkspaceGenesis = struct {
    workspace: Ulid,
    owner: Ulid,
};

const PageHeader = struct {
    signature: Hash, // 32 bytes
    author: Hash, // 32 bytes
    prev: union { page: Hash, genesis: WorkspaceGenesis }, // 32 bytes, height == 0 -> workspace, height > 0 -> prev
    height: u32, // 4 bytes
    symbols: u32, // 4 bytes
};

const PageType = enum(u8) {
    tuples,
    merge,
};

const Page = struct { header: PageHeader, data: union(PageType) {
    tuples: void,
    merge: void,
} };

// const symbol_db_null = [16]u8{ 1, 144, 237, 89, 186, 123, 15, 113, 198, 10, 84, 52, 8, 223, 230, 126 };
const symbol_db_symbol = Ulid{ .bytes = [16]u8{ 1, 144, 237, 102, 185, 237, 123, 44, 199, 209, 139, 129, 121, 70, 59, 59 } };
const symbol_db_attribute = Ulid{ .bytes = [16]u8{ 1, 144, 237, 92, 235, 182, 248, 226, 248, 193, 64, 30, 228, 94, 52, 132 } };

const db_symbol = EphemeralId{ .id = 1 };

const Tuple = struct {
    e: EphemeralId,
    a: EphemeralId,
    v: DbValue,
};

const Tuples = struct {
    start_id: usize,

    ulid_gen: ulid.Generator,
    ulid_buf: [PageSize / @sizeOf(Ulid)]Ulid,
    ulid_len: usize,

    tuple_buf: [PageSize / @sizeOf(Tuple)]Tuple,
    tuple_len: usize,

    fn init(start_id: usize) Tuples {
        return Tuples{
            .start_id = start_id,
            .ulid_gen = ulid.ulid(),
            .ulid_buf = undefined,
            .ulid_len = 0,
            .tuple_buf = undefined,
            .tuple_len = 0,
        };
    }

    fn insert(self: *Tuples, e: EphemeralId, a: EphemeralId, v: DbValue) void {
        self.tuple_buf[self.tuple_len] = Tuple{ .e = e, .a = a, .v = v };
        self.tuple_len += 1;
    }

    fn addSymbol(self: *Tuples, symbol: Ulid) EphemeralId {
        const len = self.ulid_len;
        self.ulid_buf[len] = symbol;
        self.ulid_len += 1;
        const id = EphemeralId{ .id = len + self.start_id };
        self.insert(id, db_symbol, DbValue{ .dbsymbol = &symbol });
        return id;
    }

    fn nextSymbol(self: *Tuples) DbValue {
        return self.addSymbol(self.ulid_gen.next());
    }
};

fn genesis(workspace: Ulid, owner: Ulid) Page {
    var tuples = Tuples.init(1);
    const id = tuples.addSymbol(symbol_db_symbol);
    assert(id.id == db_symbol.id);
    // const db_attribute = tuples.addSymbol(symbol_db_attribute);

    const page = Page{
        .header = .{
            .signature = undefined,
            .author = undefined,
            .prev = .{ .genesis = .{ .workspace = workspace, .owner = owner } }, //++ workspace.bytes,
            .height = 0,
            .symbols = 0,
        },
        .data = .{ .tuples = undefined },
    };
    return page;
}

const Db = struct {
    allocator: Allocator,

    prev: *const PageHeader,

    fn init(allocator: Allocator, prev: *const PageHeader) Db {
        const db = Db{ .allocator = allocator, .prev = prev };
        return db;
    }
};

test "db" {
    try testing.expectEqual(true, true);
    var gen = ulid.ulid();
    const tx0 = genesis(gen.next(), gen.next());
    std.debug.print("tx: {any}\n", .{tx0});

    const db = Db.init(testing.allocator, &tx0.header);
    std.debug.print("db: {any}\n", .{db});
}
