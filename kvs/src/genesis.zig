//

const std = @import("std");
const tuples = @import("./tuple.zig");

const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Tx = tuples.Tx;
const Id = tuples.Id;
const Keyword = tuples.Keyword;

// attributes
const kw_db_ident = Keyword("db", "ident");
const kw_db_type = Keyword("db", "type");
const kw_db_cardinality = Keyword("db", "cardinality");

// types
const kw_db_type_keyword = Keyword("db.type", "keyword");
const kw_db_type_ref = Keyword("db.type", "ref");

// cardinality
const kw_db_cardinality_one = Keyword("db.cardinalty", "one");
const kw_db_cardinality_many = Keyword("db.cardinalty", "many");

fn genesisTx(allocator: Allocator) Tx {
    var tx = Tx.init(allocator, tuples.db_ident_id);

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
    const tx = genesisTx(std.testing.allocator);
    std.debug.print("{any}", .{tx});
}
