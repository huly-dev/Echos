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
                fn cmp(_: A, _: A) Cmp {
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

pub fn EnumFields(comptime T: type) type {
    const typeinfo = @typeInfo(T).Struct;
    var enum_fields: [typeinfo.fields.len]Type.EnumField = undefined;

    for (typeinfo.fields, 0..) |key, i| {
        enum_fields[i] = Type.EnumField{
            .name = key.name,
            .value = i,
        };
    }

    return @Type(.{
        .Enum = .{
            .tag_type = u8,
            .fields = &enum_fields,
            .decls = typeinfo.decls,
            .is_exhaustive = false,
        },
    });
}

fn indexOf(comptime S: Type.Struct, comptime name: [:0]const u8) comptime_int {
    for (S.fields, 0..) |f, i| {
        if (std.mem.eql(u8, f.name, name))
            return i;
    }
    @compileError("field not found: " ++ name);
}

pub fn Key(comptime T: type, comptime E: type) type {
    // construct tuple with ordered key values
    const typeinfo = @typeInfo(T).Struct;
    const order = @typeInfo(E).Enum;
    var tuple: [order.fields.len]Type.StructField = undefined;

    for (order.fields, 0..) |key, i| {
        tuple[i] = typeinfo.fields[comptime indexOf(typeinfo, key.name)];
        tuple[i].name = comptime &[1:0]u8{'0' + @as(u8, i)};
    }

    const K = @Type(.{
        .Struct = .{
            .layout = typeinfo.layout,
            .fields = &tuple,
            .decls = typeinfo.decls,
            .is_tuple = true,
        },
    });

    return struct {
        pub const Type = T;
        pub const Key = K;
        pub const PK = E;

        fn key(record: *const T) K {
            var result: K = undefined;
            inline for (order.fields, 0..) |f, i| {
                result[i] = @field(record, f.name);
            }
            return result;
        }

        fn compareKey(k: K, record: *const T) Cmp {
            inline for (order.fields, 0..) |field, i| {
                const cmp = comparator(typeinfo.fields[i].type).cmp;
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
    const keyinfo = @typeInfo(K.Key).Struct;
    const valinfo = @typeInfo(V).Struct;
    var tuple: [keyinfo.fields.len + valinfo.fields.len]Type.StructField = undefined;
    var pk: [keyinfo.fields.len]Type.EnumField = undefined;

    for (keyinfo.fields, 0..) |key, i| {
        tuple[i] = key;
        tuple[i].name = comptime &[1:0]u8{'0' + @as(u8, i)};
        pk[i] = Type.EnumField{
            .name = key.name,
            .value = i,
        };
    }

    for (valinfo.fields, keyinfo.fields.len..) |val, i| {
        tuple[i] = val;
        tuple[i].name = comptime &[1:0]u8{'0' + @as(u8, i)};
    }

    const KV = @Type(.{
        .Struct = .{
            .layout = keyinfo.layout,
            .fields = &tuple,
            .decls = keyinfo.decls,
            .is_tuple = true,
        },
    });

    const PK = @Type(.{
        .Enum = .{
            .tag_type = u8,
            .fields = &pk,
            .decls = keyinfo.decls,
            .is_exhaustive = false,
        },
    });

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

        fn lowerBound(self: *Self, key: rel.KeyType) usize {
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

        fn upperBound(self: *Self, key: rel.KeyType) usize {
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

        pub fn seek(self: *Self, key: rel.KeyType) Cursor {
            return Cursor{
                .records = &self.records,
                .pos = self.lowerBound(key),
            };
        }

        pub fn get(self: *Self, key: rel.KeyType) ?*rel.Type {
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
    // const u = Uuid.v4();

    const S = struct { ax: u32, bx: Uuid, cx: u16, dx: i8 };

    const R1 = Key(S, enum { ax, bx });
    const R2 = Key(S, enum { bx, ax });

    const R1Page = Page(R1);

    const testing = std.testing;
    const pages = try testing.allocator.alloc(R1Page, 1);
    defer std.testing.allocator.free(pages);

    const v1 = &S{ .ax = 5, .bx = Uuid.v4(), .cx = 3, .dx = -5 };
    const v2 = &S{ .ax = 8, .bx = Uuid.v4(), .cx = 943, .dx = 2 };
    const v3 = &S{ .ax = 5, .bx = Uuid.v4(), .cx = 111, .dx = 22 };
    const v4 = &S{ .ax = 5, .bx = Uuid.v4(), .cx = 111, .dx = 22 };
    _ = v1;
    _ = v2;
    _ = v3;
    _ = v4;

    // try testing.expectEqualDeep(.{ 5, -7 }, R1.key(v1));
    // try testing.expectEqualDeep(.{ 8, -345 }, R1.key(v2));
    // try testing.expectEqualDeep(.{ 5, -7 }, R1.key(v3));
    // try testing.expectEqualDeep(.{ 5, 7 }, R1.key(v4));

    // const m = struct { Uuid };
    // const y = m{u};
    // std.debug.print("{any}\n", .{y});

    // const R1I = KeyValue(R1, m);
    // // var z = [1]u8{0} ** 16;
    // // z = uuid.v4();
    // const x = R1I.Type{ 5, 5, u }; // [1]u8{0} ** 16 };

    std.debug.print("{any}\n", .{R1});
    std.debug.print("{any}\n", .{R2});

    // std.debug.print("{any}\n", .{R1Page});
    // std.debug.print("{any}\n", .{x});
}
