//

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const Order = std.math.Order;

// T Y P E S

const DbValueKind = enum(u4) {
    dbid,
    dbuuid,
    dbkeyword,
    dbuint,
    dbchar,
    dbdatetime,
};

const Id = struct { usize }; // u32
const Uuid = struct { [16]u8 };

const DbValue = union(DbValueKind) {
    dbid: Id, // this is ephemeral id pointing to symbol
    dbuuid: *const Uuid,
    dbkeyword: [:0]const u8,
    dbuint: usize,
    dbchar: []const u8,
    dbdatetime: u32,
};

fn write(writer: anytype, v: DbValue) !void {
    switch (v) {
        .dbuuid => |uuid| try writer.writeAll(&uuid[0]),
        .dbkeyword, .dbchar => |keyword| try writer.print("{s}", .{keyword}),
        .dbid => |id| try writer.writeInt(u32, @as(u32, @intCast(id[0])), .little),
        .dbuint => |uint| try writer.writeInt(u32, @as(u32, @intCast(uint)), .little),
        .dbdatetime => |dt| try writer.writeInt(u32, dt, .little),
    }
}

fn compareBytes(kind: DbValueKind, a: []const u8, b: []const u8) Order {
    switch (kind) {
        .dbuuid => return std.mem.order(u8, a[0..16], b[0..16]),
        .dbkeyword, .dbchar => return std.mem.orderZ(u8, @ptrCast(a), @ptrCast(b)),
        .dbid, .dbuint, .dbdatetime => {
            const av = std.mem.bytesToValue(u32, a);
            const bv = std.mem.bytesToValue(u32, b);
            if (av < bv) return Order.lt;
            if (av > bv) return Order.gt;
            return Order.eq;
        },
    }
}

fn Keyword(keyword: [:0]const u8) DbValue {
    return DbValue{ .dbkeyword = keyword };
}

// T U P L E S

const Tuple = struct {
    e: Id,
    a: Id,
    v: DbValue,
};

const MaxTuples = 1024;

const db_ident_id = DbValue{ .dbid = Id{1} };

const Tx = struct {
    next_id: usize,
    tuples: std.ArrayList(Tuple),

    fn init(allocator: Allocator, next_id: Id) Tx {
        return Tx{
            .next_id = next_id[0],
            .tuples = std.ArrayList(Tuple).init(allocator),
        };
    }

    fn deinit(self: *Tx) void {
        self.tuples.deinit();
    }

    fn insert(self: *Tx, e: DbValue, a: DbValue, v: DbValue) !void {
        assert(@as(DbValueKind, e) == DbValueKind.dbid);
        assert(@as(DbValueKind, a) == DbValueKind.dbid);
        try self.tuples.append(Tuple{ .e = e.dbid, .a = a.dbid, .v = v });
    }

    fn nextId(self: *Tx) DbValue {
        const id = DbValue{ .dbid = Id{self.next_id} };
        self.next_id += 1;
        return id;
    }

    fn ident(self: *Tx, keyword: DbValue) !DbValue {
        assert(@as(DbValueKind, keyword) == DbValueKind.dbkeyword);
        const id = DbValue{ .dbid = Id{self.next_id} };
        try self.insert(id, db_ident_id, keyword);
        self.next_id += 1;
        return id;
    }

    fn getTuples(self: *Tx) []Tuple {
        return self.tuples.items;
    }
};

// P E R S I S T E N C E

fn UnsignedInt(comptime bits: u16) type {
    return @Type(.{
        .Int = .{
            .signedness = .unsigned,
            .bits = bits,
        },
    });
}

const TupleOrder = enum {
    eav,
    aev,
    ave,
    vae,
};

const OffsetBits = @bitSizeOf(u16) - @bitSizeOf(DbValueKind);
const Offset = UnsignedInt(OffsetBits);

const PTuple = packed struct {
    e: u32,
    a: u16,
    v: u16,
};

fn compareEAV(values: []const u8, a: PTuple, b: PTuple) Order {
    if (a.e < b.e) return Order.lt;
    if (a.e > b.e) return Order.gt;
    if (a.a < b.a) return Order.lt;
    if (a.a > b.a) return Order.gt;
    const at = a.v >> OffsetBits;
    const bt = b.v >> OffsetBits;
    if (at < bt) return Order.lt;
    if (at > bt) return Order.gt;
    const t: DbValueKind = @enumFromInt(at);
    return compareBytes(t, values[a.v..], values[b.v..]);
}

fn lessThanEAV(values: []const u8, a: PTuple, b: PTuple) bool {
    return compareEAV(values, a, b) == Order.lt;
}

const Tuples = struct {
    tuples: []const PTuple,
    values: []const u8,

    fn init(allocator: Allocator, tuples: []Tuple) !Tuples {
        var ptuples = try std.ArrayList(PTuple).initCapacity(allocator, tuples.len);
        var values = std.ArrayList(u8).init(allocator);
        const writer = values.writer();
        for (tuples) |tuple| {
            const e: u32 = @intCast(tuple.e[0]);
            const a: u16 = @intCast(tuple.a[0]);
            const t: usize = @intFromEnum(tuple.v);
            const v: u16 = @intCast((t << OffsetBits) + values.items.len);
            try write(writer, tuple.v);
            try ptuples.append(PTuple{ .e = e, .a = a, .v = v });
        }
        std.mem.sort(PTuple, ptuples.items, values.items, lessThanEAV);
        return Tuples{
            .tuples = @constCast(try ptuples.toOwnedSlice()),
            .values = @constCast(try values.toOwnedSlice()),
        };
    }

    fn deinit(self: Tuples, allocator: Allocator) void {
        allocator.free(self.tuples);
        allocator.free(self.values);
    }
};

// G E N E S I S

const kw_db_ident = Keyword("db/ident");
const kw_db_type = Keyword("db/type");
const kw_db_cardinality = Keyword("db/cardinality");

// types
const kw_db_type_keyword = Keyword("db.type/keyword");
const kw_db_type_ref = Keyword("db.type/ref");

// cardinality
const kw_db_cardinality_one = Keyword("db.cardinalty/one");
const kw_db_cardinality_many = Keyword("db.cardinalty/many");

fn genesisTx(allocator: Allocator) !Tx {
    var tx = Tx.init(allocator, db_ident_id.dbid);

    // attributes
    const db_ident = try tx.ident(kw_db_ident);
    const db_type = try tx.ident(kw_db_type);
    const db_cardinality = try tx.ident(kw_db_cardinality);

    // types
    const db_type_keyword = try tx.ident(kw_db_type_keyword);
    const db_type_ref = try tx.ident(kw_db_type_ref);

    // cardinality
    const db_cardinality_one = try tx.ident(kw_db_cardinality_one);
    const db_cardinality_many = try tx.ident(kw_db_cardinality_one);
    _ = db_cardinality_many;

    // db/ident
    try tx.insert(db_ident, db_type, db_type_keyword);
    try tx.insert(db_ident, db_cardinality, db_cardinality_one);

    // db/type
    try tx.insert(db_type, db_type, db_type_ref);
    try tx.insert(db_type, db_cardinality, db_cardinality_one);

    // db/cardinality
    try tx.insert(db_cardinality, db_type, db_type_ref);
    try tx.insert(db_cardinality, db_cardinality, db_cardinality_one);

    return tx;
}

test "test" {
    var tx = Tx.init(std.testing.allocator, Id{1});
    defer tx.deinit();
    const id = tx.nextId();
    try tx.insert(id, id, DbValue{ .dbuint = 42 });
    std.debug.print("{any}\n", .{tx});
    const kw = Keyword("foo/bar");
    std.debug.print("{s}\n", .{kw.dbkeyword});
}

test "genesis" {
    var tx = try genesisTx(std.testing.allocator);
    defer tx.deinit();
    std.debug.print("{any}\n", .{tx});

    const tuples = tx.getTuples();
    const pt = try Tuples.init(std.testing.allocator, tuples);
    defer pt.deinit(std.testing.allocator);
    std.debug.print("{any}\n", .{pt});
    std.debug.print("{d}\n", .{@sizeOf(PTuple)});

    var out = std.ArrayList(u8).init(std.testing.allocator);
    const writer = out.writer();
    for (pt.tuples) |tuple| try writer.writeStructEndian(tuple, .little);
    try writer.writeAll(pt.values);
    const data = try out.toOwnedSlice();

    std.debug.print("{d}\n", .{data.len});
    std.debug.print("{x}\n", .{data});
    std.testing.allocator.free(data);
}
