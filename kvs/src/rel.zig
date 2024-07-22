//
const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const uuid = @import("./uuid.zig");
const Uuid = uuid.Uuid;

const StructField = std.builtin.Type.StructField;

pub const Cmp = enum { eq, gt, le };

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

    return struct {
        const Type = T;
        const KeyType = K;
        const PrimaryKey = PK;

        fn key(record: *const Type) KeyType {
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

        fn compareKey(k: KeyType, record: *const Type) Cmp {
            inline for (keyinfo.fields, 0..) |field, i| {
                if (k[i] < @field(record, field.name)) return Cmp.le;
                if (k[i] > @field(record, field.name)) return Cmp.gt;
            }
            return Cmp.eq;
        }
    };
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

        fn binarySearch(self: *Self, key: rel.KeyType) isize {
            var low: isize = 0;
            var high: isize = @as(isize, @intCast(self.header.len)) - 1;
            while (low <= high) {
                const mid = @divTrunc(low + high, 2);
                const cmp = rel.compareKey(key, &self.records[@intCast(mid)]);
                if (cmp == Cmp.gt) low = mid + 1 else if (cmp == Cmp.le) high = mid - 1 else return mid;
            }
            return -low - 1;
        }

        pub fn seek(self: *Self, key: rel.KeyType) Cursor {
            const ip = self.binarySearch(key);
            const cursor = Cursor{
                .records = &self.records,
                .pos = if (ip < 0) @intCast(-ip - 1) else @intCast(ip),
            };
            return cursor;
        }

        pub fn insert(self: *Self, kv: *const rel.Type) bool {
            const pos = self.binarySearch(rel.key(kv));
            if (pos >= 0) {
                return false;
            } else {
                const ip: usize = @intCast(-pos - 1);
                const len = self.header.len;
                for (self.records[ip + 1 .. len + 1], self.records[ip..len]) |*to, *from| {
                    to.* = from.*;
                }
                self.records[len] = kv.*;
                self.header.len += 1;
                return true;
            }
        }
    };
}
