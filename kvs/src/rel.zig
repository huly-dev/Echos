//
const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const uuid = @import("./uuid.zig");
const Uuid = uuid.Uuid;

const StructField = std.builtin.Type.StructField;
const EnumField = std.builtin.Type.EnumField;

pub const Cmp = enum { eq, gt, le };

fn makeComparator(comptime A: type) type {
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

fn makeRelation(comptime T: type, K: type, PK: type) type {
    const keyinfo = @typeInfo(PK).Enum;
    const typeinfo = @typeInfo(K).Struct;
    return struct {
        pub const Type = T;
        pub const KeyType = K;
        const PrimaryKey = PK;

        pub fn key(record: *const Type) KeyType {
            var result: KeyType = undefined;
            inline for (keyinfo.fields, 0..) |field, i| {
                result[i] = @field(record, field.name);
            }
            return result;
        }

        // fn compare(a: KeyType, b: KeyType) Cmp {
        //     inline for (0..keys) |i| {
        //         if (a[i] < b[i]) return Cmp.le;
        //         if (a[i] > b[i]) return Cmp.gt;
        //     }
        //     return Cmp.eq;
        // }

        pub fn compareKey(k: KeyType, record: *const Type) Cmp {
            inline for (keyinfo.fields, 0..) |field, i| {
                const cmp = makeComparator(typeinfo.fields[i].type);
                const result = cmp.cmp(k[i], @field(record, field.name));
                if (result != Cmp.eq) return result;
                // if (k[i] < @field(record, field.name)) return Cmp.le;
                // if (k[i] > @field(record, field.name)) return Cmp.gt;
            }
            return Cmp.eq;
        }
    };
}

pub fn Rel(comptime T: type, PK: type) type {
    const keyinfo = @typeInfo(PK).Enum;
    const typeinfo = @typeInfo(T).Struct;

    const keys = keyinfo.fields.len;
    var key_fields: [keys]StructField = undefined;

    for (keyinfo.fields, 0..) |key, i| {
        const field = comptime for (typeinfo.fields, 0..) |field, j| {
            if (std.mem.eql(u8, field.name, key.name))
                break j;
        } else -1;
        if (field == -1)
            @compileError("field not found in struct");
        key_fields[i] = typeinfo.fields[field];
        const name = &[1:0]u8{'0' + @as(u8, i)};
        key_fields[i].name = name;
    }

    const K = @Type(.{
        .Struct = .{
            .layout = typeinfo.layout,
            .fields = &key_fields,
            .decls = typeinfo.decls,
            .is_tuple = true,
        },
    });
    return makeRelation(T, K, PK);
}

fn Comparator(comptime left: type, comptime right: type) type {
    const LK = @typeInfo(left.PrimaryKey).Enum;
    const RK = @typeInfo(right.PrimaryKey).Enum;
    return struct {
        fn compare(a: *const left.Type, b: *const right.Type) Cmp {
            inline for (LK.fields, RK.fields) |l, r| {
                if (@field(a, l.name) < @field(b, r.name)) return Cmp.le;
                if (@field(a, l.name) > @field(b, r.name)) return Cmp.gt;
            }
            return Cmp.eq;
        }
    };
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

        fn binarySearch(self: *Self, key: rel.KeyType) isize {
            const ip = self.lowerBound(key);
            if (ip < self.header.len) {
                const record = &self.records[ip];
                if (rel.compareKey(key, record) == Cmp.eq) {
                    return @intCast(ip);
                }
            }
            return ~@as(isize, @intCast(ip));
        }

        pub fn seek(self: *Self, key: rel.KeyType) Cursor {
            return Cursor{
                .records = &self.records,
                .pos = self.lowerBound(key),
            };
        }

        pub fn get(self: *Self, key: rel.KeyType) ?*rel.Type {
            const ip = self.binarySearch(key);
            if (ip >= 0) {
                return &self.records[@intCast(ip)];
            }
            return null;
        }

        pub fn upsert(self: *Self, kv: *const rel.Type) bool {
            const pos = self.binarySearch(rel.key(kv));
            if (pos >= 0) {
                self.records[@intCast(pos)] = kv.*;
                return true;
            } else {
                const ip: usize = @intCast(~pos);
                var copy = self.header.len;
                while (copy > ip) : (copy -= 1) self.records[copy] = self.records[copy - 1];
                self.records[ip] = kv.*;
                self.header.len += 1;
                return false;
            }
        }
    };
}

pub fn InnerRel(comptime K: type) type {
    const keyinfo = @typeInfo(K).Struct;

    const keys = keyinfo.fields.len;
    var key_fields: [keys + 1]StructField = undefined;
    var enum_fields: [keys]EnumField = undefined;

    for (keyinfo.fields, 0..) |key, i| {
        key_fields[i] = key;
        // @compileLog(key);
        enum_fields[i] = EnumField{
            .name = key.name,
            .value = i,
        };
    }
    const name = &[1:0]u8{'0' + @as(u8, keys)};
    key_fields[keys] = StructField{ .name = name, .type = Uuid, .default_value = null, .is_comptime = false, .alignment = 1 };

    const S = @Type(.{
        .Struct = .{
            .layout = keyinfo.layout,
            .fields = &key_fields,
            .decls = keyinfo.decls,
            .is_tuple = true,
        },
    });

    const PK = @Type(.{
        .Enum = .{
            .tag_type = u8,
            .fields = &enum_fields,
            .decls = keyinfo.decls,
            .is_exhaustive = false,
        },
    });

    return makeRelation(S, K, PK);
}
