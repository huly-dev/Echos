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

test "test create relation" {
    const S = struct { ax: u32, bx: i16, cx: u16, dx: i8 };

    const R1 = Key(S, enum { ax, bx });
    const R2 = Key(S, enum { bx, ax });

    // const X = R1.Tuple ++ .{Uuid};

    std.debug.print("{any}\n", .{R1});
    std.debug.print("{any}\n", .{R2});
}
