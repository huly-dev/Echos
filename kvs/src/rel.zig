//
const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Type = std.builtin.Type;

const uuid = @import("./uuid.zig");
const Uuid = uuid.Uuid;

pub const Cmp = enum { eq, gt, le };

fn comparator(comptime A: type) type {
    switch (@typeInfo(A)) {
        .Struct => {
            return struct {
                fn cmp(a: A, b: A) Cmp {
                    inline for (std.meta.fields(A)) |field| {
                        const compare = comparator(field.type).cmp;
                        const result = compare(@field(a, field.name), @field(b, field.name));
                        if (result != Cmp.eq) return result;
                    }
                    return Cmp.eq;
                }
            };
        },
        .Array => {
            return struct {
                fn cmp(a: A, b: A) Cmp {
                    for (a, 0..) |elem, i| {
                        if (elem < b[i]) return Cmp.le;
                        if (elem > b[i]) return Cmp.gt;
                    }
                    return Cmp.eq;
                }
            };
        },
        else => {
            return struct {
                fn cmp(a: A, b: A) Cmp {
                    if (a < b) return Cmp.le;
                    if (a > b) return Cmp.gt;
                    return Cmp.eq;
                }
            };
        },
    }
}

// fn Comparators(comptime fields: []Type.StructField) []type {
//     comptime {
//         var comparators: [fields.len]type = undefined;
//         for (fields, 0..) |field, i| {
//             comparators[i] = comparator(field.type);
//         }
//         return comparators;
//     }
// }

fn CreateUniqueTuple(comptime N: comptime_int, comptime types: [N]type) type {
    var tuple_fields: [types.len]Type.StructField = undefined;
    inline for (types, 0..) |T, i| {
        @setEvalBranchQuota(10_000);
        var num_buf: [128]u8 = undefined;
        tuple_fields[i] = .{
            .name = std.fmt.bufPrintZ(&num_buf, "{d}", .{i}) catch unreachable,
            .type = T,
            .default_value = null,
            .is_comptime = false,
            .alignment = if (@sizeOf(T) > 0) @alignOf(T) else 0,
        };
    }

    return @Type(.{
        .Struct = .{
            .is_tuple = true,
            .layout = .auto,
            .decls = &.{},
            .fields = &tuple_fields,
        },
    });
}

// pub fn EnumFields(comptime T: type) type {
//     const fields = std.meta.fields(T);
//     var enum_fields: [fields.len]Type.EnumField = undefined;

//     for (fields, 0..) |key, i| {
//         enum_fields[i] = Type.EnumField{
//             .name = key.name,
//             .value = i,
//         };
//     }

//     return @Type(.{
//         .Enum = .{
//             .tag_type = u8,
//             .fields = &enum_fields,
//             .decls = &.{},
//             .is_exhaustive = false,
//         },
//     });
// }

fn indexOf(comptime T: type, comptime name: [:0]const u8) comptime_int {
    return for (std.meta.fields(T), 0..) |f, i| {
        if (std.mem.eql(u8, f.name, name)) break i;
    } else -1;
}

pub fn Key(comptime T: type, comptime E: type) type {
    // construct tuple with ordered key values
    const type_fields = std.meta.fields(T);
    const order_fields = std.meta.fields(E);
    // var tuple: [order_fields.len]Type.StructField = undefined;
    var key_types: [order_fields.len]type = undefined;

    for (order_fields, 0..) |key, i| {
        // var num_buf: [128]u8 = undefined;
        key_types[i] = type_fields[indexOf(T, key.name)].type;
        // tuple[i] = type_fields[comptime indexOf(T, key.name)];
        // tuple[i].name = std.fmt.bufPrintZ(&num_buf, "{d}", .{i}) catch unreachable;
    }

    const K = CreateUniqueTuple(key_types.len, key_types);

    // const K = @Type(.{
    //     .Struct = .{
    //         .layout = .auto,
    //         .fields = &tuple,
    //         .decls = &.{},
    //         .is_tuple = true,
    //     },
    // });

    return struct {
        pub const Type = T;
        pub const Key = K;

        pub fn key(record: *const T) K {
            var result: K = undefined;
            inline for (order_fields, 0..) |f, i| {
                result[i] = @field(record, f.name);
            }
            return result;
        }

        pub fn compareKey(k: K, record: *const T) Cmp {
            inline for (order_fields, 0..) |field, i| {
                const cmp = comparator(type_fields[i].type).cmp;
                const result = cmp(k[i], @field(record, field.name));
                if (result != Cmp.eq) return result;
            }
            return Cmp.eq;
        }
    };
}

// K: Key, V: Value (tuple) -> tuple
pub fn KeyValue(comptime K: type, comptime V: type) type {
    // construct tuple with ordered key values
    const key_fields = std.meta.fields(K);
    const val_fields = std.meta.fields(V);

    var tuple: [key_fields.len + val_fields.len]Type.StructField = undefined;
    var key_types: [key_fields.len]type = undefined;

    for (key_fields, 0..) |key, i| {
        tuple[i] = key;
        key_types[i] = key.type;
    }

    for (val_fields, key_fields.len..) |val, i| {
        var num_buf: [128]u8 = undefined;
        tuple[i] = val;
        tuple[i].name = std.fmt.bufPrintZ(&num_buf, "{d}", .{i}) catch unreachable;
    }

    const KV = @Type(.{
        .Struct = .{
            .is_tuple = true,
            .layout = .auto,
            .fields = &tuple,
            .decls = &.{},
        },
    });

    const PK = CreateUniqueTuple(key_fields.len, key_types);

    // const PK = @Type(.{
    //     .Enum = .{
    //         .tag_type = u8,
    //         .fields = &pk,
    //         .decls = keyinfo.decls,
    //         .is_exhaustive = false,
    //     },
    // });

    return Key(KV, PK);
}

const PageSize = 4096;

const Header = struct {
    len: u32,
    record_size: u32,
    reserved: u64,
    underlying: Uuid,
};

pub fn Page(rel: type) type {
    const RecordSize = @sizeOf([1]rel.Type);
    const RecordsArea = PageSize - @sizeOf(Header);
    const Records = RecordsArea / RecordSize;
    const Alignment = RecordsArea % RecordSize;

    return struct {
        header: Header,
        records: [Records]rel.Type,
        alignment: [Alignment]u8,

        const Self = @This();

        const Cursor = struct {
            records: *[Records]rel.Type,
            pos: usize,

            fn next(self: Cursor) ?*rel.Type {
                if (self.pos < self.records.len) {
                    const result = &self.records[self.pos];
                    self.pos += 1;
                    return result;
                }
                return null;
            }
        };

        pub fn init(self: *Self, underlying: Uuid) void {
            self.header.len = 0;
            self.header.record_size = RecordSize;
            self.header.reserved = 0;
            self.header.underlying = underlying;
        }

        fn deinit(self: *Self, allocator: Allocator) void {
            allocator.free(self);
        }

        fn lowerBound(self: *Self, key: rel.Key) usize {
            var low: usize = 0;
            var high: usize = self.header.len;
            while (low < high) {
                const mid = (low + high) >> 1;
                const record = &self.records[mid];
                if (rel.compareKey(key, record) == Cmp.gt)
                    low = mid + 1
                else
                    high = mid;
            }
            return low;
        }

        fn upperBound(self: *Self, key: rel.Key) usize {
            var low: usize = 0;
            var high: usize = self.header.len;
            while (low < high) {
                const mid = (low + high) >> 1;
                const record = &self.records[mid];
                if (rel.compareKey(key, record) == Cmp.le)
                    high = mid
                else
                    low = mid + 1;
            }
            return low;
        }

        pub fn seek(self: *Self, key: rel.Key) Cursor {
            return Cursor{
                .records = &self.records,
                .pos = self.lowerBound(key),
            };
        }

        pub fn get(self: *Self, key: rel.Key) ?*rel.Type {
            const pos = self.lowerBound(key);
            if (pos < self.header.len) {
                const record = &self.records[pos];
                if (rel.compareKey(key, record) == Cmp.eq)
                    return record;
            }
            return null;
        }

        pub fn upsert(self: *Self, kv: *const rel.Type) bool {
            const key = rel.key(kv);
            const pos = self.lowerBound(key);
            if (pos < self.header.len) {
                const record = &self.records[pos];
                if (rel.compareKey(key, record) == Cmp.eq) {
                    self.records[@intCast(pos)] = kv.*;
                    return true;
                }
            }
            var copy = self.header.len;
            while (copy > pos) : (copy -= 1) self.records[copy] = self.records[copy - 1];
            self.records[pos] = kv.*;
            self.header.len += 1;
            return false;
        }
    };
}

test "test create relation" {
    const testing = std.testing;

    const u = Uuid.v4();
    const v = Uuid.v4();

    const S = struct { ax: u32, bx: Uuid, cx: u16, dx: i8 };

    const R = Key(S, enum { ax, bx });
    const K = struct { u32, Uuid };

    const v1 = &S{ .ax = 5, .bx = u, .cx = 3, .dx = -5 };
    const v2 = &S{ .ax = 8, .bx = v, .cx = 943, .dx = 2 };
    const v3 = &S{ .ax = 5, .bx = v, .cx = 111, .dx = 22 };
    const v4 = &S{ .ax = 3, .bx = u, .cx = 111, .dx = 22 };

    const k1 = K{ 5, u };
    const k2 = K{ 8, v };
    const k3 = K{ 5, v };
    const k4 = K{ 3, u };

    try testing.expectEqualDeep(k1, R.key(v1));
    try testing.expectEqualDeep(k2, R.key(v2));
    try testing.expectEqualDeep(k3, R.key(v3));
    try testing.expectEqualDeep(k4, R.key(v4));

    try testing.expectEqual(Cmp.eq, R.compareKey(k1, v1));
    try testing.expectEqual(Cmp.le, R.compareKey(k1, v2));
    try testing.expect(Cmp.eq != R.compareKey(k1, v3));
    try testing.expectEqual(Cmp.gt, R.compareKey(k1, v4));

    const RPage = Page(R);
    const pages = try testing.allocator.alloc(RPage, 1);
    defer std.testing.allocator.free(pages);

    const IR = KeyValue(R.Key, struct { Uuid });

    const r = IR.Type{ 5, u, v };

    std.debug.print("KK: {any}\n", .{r});
}
