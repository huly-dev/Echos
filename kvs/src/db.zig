//

const std = @import("std");
const ulid = @import("./ulid.zig");

const assert = std.debug.assert;
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Ulid = ulid.Ulid;

// D A T A B A S E  T Y P E S

const DbValueType = u4;

const DbValueKind = enum(DbValueType) {
    dbid,
    dbuuid,
    dbkeyword,
    dbuint,
    dbchar,
    dbdatetime,
};

const EphemeralId = struct { id: usize }; // u32
const Uuid = [16]u8;

const DbValue = union(DbValueKind) {
    dbid: EphemeralId, // this is ephemeral id pointing to symbol
    dbuuid: *const Uuid,
    dbkeyword: []const u8,
    dbuint: usize,
    dbchar: []const u8,
    dbdatetime: u32,
};

// D A T A B A S E  P A G E S

const PageSize = 4096;
const Hash256 = [32]u8;

// const WorkspaceGenesis = struct {
//     workspace: Ulid,
//     owner: Ulid,
// };

// const PageHeader = struct {
//     signature: Hash256,
//     account: EphemeralId, // in person database
//     prev: Id,
//     height: usize,
//     symbols: usize,
// };

// const PageType = enum(u8) {
//     tuples,
//     merge,
// };

// const Page = struct { header: PageHeader, data: union(PageType) {
//     tuples: void,
//     merge: void,
// } };

const symbol_db_symbol = Ulid{ .bytes = [16]u8{ 1, 144, 237, 102, 185, 237, 123, 44, 199, 209, 139, 129, 121, 70, 59, 59 } };
const symbol_db_type = Ulid{ .bytes = [16]u8{ 1, 144, 237, 89, 186, 123, 15, 113, 198, 10, 84, 52, 8, 223, 230, 126 } };
const symbol_db_type_symbol = Ulid{ .bytes = [16]u8{ 1, 144, 237, 150, 50, 202, 221, 224, 43, 81, 143, 241, 2, 125, 74, 248 } };
const symbol_db_type_ref = Ulid{ .bytes = [16]u8{ 1, 144, 237, 131, 190, 90, 7, 157, 125, 11, 197, 175, 52, 221, 119, 243 } };
const symbol_db_cardinalty = Ulid{ .bytes = [16]u8{ 1, 144, 237, 92, 235, 182, 248, 226, 248, 193, 64, 30, 228, 94, 52, 132 } };
const symbol_db_cardinalty_one = Ulid{ .bytes = [16]u8{ 1, 144, 237, 145, 253, 187, 153, 161, 204, 248, 168, 50, 171, 189, 46, 222 } };
const symbol_db_cardinalty_many = Ulid{ .bytes = [16]u8{ 1, 144, 237, 145, 253, 187, 153, 161, 204, 248, 168, 50, 171, 189, 46, 223 } };

const db_symbol = EphemeralId{ .id = 1 };

// T U P L E S

const PValueState = enum(u2) {
    normal,
    deleted,
    entity,
    embedded,
};

const PValue16 = packed struct {
    state: PValueState,
    value: packed union {
        normal: packed struct { value_type: u4, payload: u10 },
        deleted: void,
        entity: u14,
    },
};

const PValue24 = packed struct {
    state: PValueState,
    value: packed union {
        normal: packed struct { value_type: u4, payload: u18 },
        deleted: void,
        entity: u22,
    },
};

const PValue32 = packed struct {
    state: PValueState,
    value: packed union {
        normal: packed struct { value_type: u4, payload: u26 },
        deleted: void,
        entity: u30,
    },
};

const PValueType = enum { pv16, pv24, pv32 };

const Tuple = struct {
    e: EphemeralId,
    a: EphemeralId,
    v: DbValue,
};

const Writer = struct {
    var tuples: []PValue32 = undefined;

    fn init(buf: [*]u8) Writer {
        return Writer{ .tuples = @ptrCast(buf) };
    }

    fn write(self: *Writer, tuple: Tuple) usize {
        const t = PValue32{
            .state = PValueState.normal,
            .value = PValue32Value.normal{
                .value_type = 0,
                .payload = 0,
            },
        };
    }
};

fn valueWriter(max_symbol: usize, max_offset: usize) Writer {
    var buf: [PageSize]u8 = undefined;
    return Writer.init(buf[0..]);
}

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

    const db_type = tuples.addSymbol(symbol_db_type);
    const db_type_symbol = tuples.addSymbol(symbol_db_type_symbol);
    const db_type_ref = tuples.addSymbol(symbol_db_type_ref);

    const db_cardinality = tuples.addSymbol(symbol_db_cardinalty);
    const db_cardinality_one = tuples.addSymbol(symbol_db_cardinalty_one);
    const db_cardinality_many = tuples.addSymbol(symbol_db_cardinalty_many);
    _ = db_cardinality_many;

    tuples.insert(db_symbol, db_type, DbValue{ .dbid = db_type_symbol });
    tuples.insert(db_symbol, db_cardinality, DbValue{ .dbid = db_cardinality_one });

    tuples.insert(db_type, db_type, DbValue{ .dbid = db_type_ref });
    tuples.insert(db_type, db_cardinality, DbValue{ .dbid = db_cardinality_one });

    tuples.insert(db_cardinality, db_type, DbValue{ .dbid = db_type_ref });
    tuples.insert(db_cardinality, db_cardinality, DbValue{ .dbid = db_cardinality_one });

    std.debug.print("tuples: {any}\n", .{tuples});

    const page = Page{
        .header = .{
            .signature = undefined,
            .author = undefined,
            .prev = .{ .genesis = .{ .workspace = workspace, .owner = owner } },
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
