//
const std = @import("std");
const rel = @import("./rel.zig");
const uuid = @import("./uuid.zig");
const testing = std.testing;
const Cmp = rel.Cmp;

test "test create relation" {
    const S1 = struct { ax: u32, bx: i16, cx: u16, dx: i8 };
    const R1 = rel.Rel(S1, enum { ax, bx });

    const R1Page = rel.LeafPage(R1);

    const pages = try testing.allocator.alloc(R1Page, 1);
    defer testing.allocator.free(pages);

    const v1 = &S1{ .ax = 5, .bx = -7, .cx = 3, .dx = -5 };
    const v2 = &S1{ .ax = 8, .bx = -345, .cx = 943, .dx = 2 };
    const v3 = &S1{ .ax = 5, .bx = -7, .cx = 111, .dx = 22 };
    const v4 = &S1{ .ax = 5, .bx = 7, .cx = 111, .dx = 22 };

    try testing.expectEqualDeep(.{ 5, -7 }, R1.key(v1));
    try testing.expectEqualDeep(.{ 8, -345 }, R1.key(v2));
    try testing.expectEqualDeep(.{ 5, -7 }, R1.key(v3));
    try testing.expectEqualDeep(.{ 5, 7 }, R1.key(v4));

    try testing.expectEqual(Cmp.eq, R1.compareKey(.{ 5, 7 }, v4));
    try testing.expectEqual(Cmp.le, R1.compareKey(.{ 5, 7 }, v2));
    try testing.expectEqual(Cmp.gt, R1.compareKey(.{ 5, 7 }, v1));

    const page = &pages[0];
    page.init(uuid.v4());

    try testing.expectEqual(false, page.upsert(v1));
    try testing.expectEqual(false, page.upsert(v2));
    try testing.expectEqual(false, page.upsert(v4));
    try testing.expectEqual(true, page.upsert(v3));
    try testing.expectEqual(true, page.upsert(v3));
    try testing.expectEqualDeep(v2, page.get(.{ 8, -345 }));
    try testing.expectEqualDeep(v3, page.get(.{ 5, -7 }));
    try testing.expectEqual(null, page.get(.{ 5, 0 }));

    std.debug.print("{any}\n", .{pages[0]});
}

test "test inner page" {
    const S1 = struct { ax: u32, bx: u16, cx: u16, dx: i8 };
    const R1 = rel.Rel(S1, enum { ax, bx });

    const InnerPage = rel.InnerPage(R1.KeyType);

    const pages = try testing.allocator.alloc(InnerPage, 1);
    defer testing.allocator.free(pages);

    const page = &pages[0];
    page.init(uuid.v4());

    _ = page.upsert(&.{ 5, 16, [1]u8{77} ** 16 });

    std.debug.print("{any}\n", .{page.get(.{ 5, 16 })});
}
