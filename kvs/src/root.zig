//
const std = @import("std");
const rel = @import("./rel.zig");
const uuid = @import("./uuid.zig");
const testing = std.testing;

test "test create relation" {
    const S1 = struct { dx: i8, ax: u32, bx: i16, cx: u16 };
    const R1 = rel.Rel(S1, enum { ax, bx });

    const R1Page = rel.Page(R1);

    const pages = try testing.allocator.alloc(R1Page, 1);
    defer testing.allocator.free(pages);

    const page = &pages[0];
    page.init(uuid.v4());

    const v1 = &S1{ .ax = 5, .bx = -7, .cx = 3, .dx = -5 };
    const v2 = &S1{ .ax = 8, .bx = -345, .cx = 943, .dx = 2 };
    const v3 = &S1{ .ax = 5, .bx = -7, .cx = 111, .dx = 22 };

    try testing.expectEqual(false, page.upsert(v1));
    try testing.expectEqual(false, page.upsert(v2));
    try testing.expectEqual(true, page.upsert(v3));
    try testing.expectEqualDeep(v2, page.get(.{ 8, -345 }));

    // std.debug.print("{any}\n", .{pages[0]});
}
