//

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

// T Y P E S

const DbValueType = u4;

const DbValueKind = enum(DbValueType) {
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
    dbkeyword: []const u8,
    dbuint: usize,
    dbchar: []const u8,
    dbdatetime: u32,
};

fn Keyword(comptime namespace: [:0]const u8, comptime name: [:0]const u8) DbValue {
    return DbValue{ .dbkeyword = namespace ++ "/" ++ name };
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
};

// G E N E S I S

const kw_db_ident = Keyword("db", "ident");
const kw_db_type = Keyword("db", "type");
const kw_db_cardinality = Keyword("db", "cardinality");

// types
const kw_db_type_keyword = Keyword("db.type", "keyword");
const kw_db_type_ref = Keyword("db.type", "ref");

// cardinality
const kw_db_cardinality_one = Keyword("db.cardinalty", "one");
const kw_db_cardinality_many = Keyword("db.cardinalty", "many");

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
    const kw = Keyword("foo", "bar");
    std.debug.print("{s}\n", .{kw.dbkeyword});
}

test "genesis" {
    var tx = try genesisTx(std.testing.allocator);
    defer tx.deinit();
    std.debug.print("{any}", .{tx});
}
