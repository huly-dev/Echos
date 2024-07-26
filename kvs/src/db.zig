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
};

const DbValue = union(DbValueType) {
    dbsymbol: *const Ulid,
    dbid: usize, // this is ephemeral id pointing to symbol
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

const TxType = enum(u8) {
    tuples,
    merge,
};

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
    tx_type: TxType, // 1 byte
};

const TxPage = struct {
    header: PageHeader,
};

const Db = struct {
    allocator: Allocator,

    prev: *const PageHeader,

    fn init(allocator: Allocator, prev: *const PageHeader) *Db {
        const db = Db{ .allocator = allocator, .prev = prev };
        return &db;
    }
};

fn genesis(workspace: Ulid, owner: Ulid) !*const TxPage {
    var buf: [PageSize]u8 align(4) = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const header = PageHeader{
        .signature = undefined,
        .author = undefined,
        .prev = .{ .genesis = .{ .workspace = workspace, .owner = owner } }, //++ workspace.bytes,
        .height = 0,
        .symbols = 0,
        .tx_type = TxType.tuples,
    };
    const ptr: [*]const u8 = @ptrCast(&header);
    _ = try stream.write(ptr[0..@sizeOf(PageHeader)]);
    return @ptrCast(&buf);
}

test "db" {
    try testing.expectEqual(true, true);
    var gen = ulid.ulid();
    const tx = genesis(gen.next(), gen.next());
    std.debug.print("tx: {any}\n", .{tx});
}
