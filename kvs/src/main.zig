const std = @import("std");
const rel = @import("rel.zig");
const uuid = @import("uuid.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.testing.expect(gpa.deinit() == .ok) catch @panic("memory leak");
    const allocator = gpa.allocator();

    var prng = std.Random.DefaultPrng.init(0);
    const random = prng.random();

    //

    const S1 = struct { ax: u32, bx: i16, cx: i16, dx: i8 };
    const R1 = rel.Rel(S1, enum { ax, bx });

    const R1Page = rel.LeafPage(R1);

    const pages = try allocator.alloc(R1Page, 1);
    defer allocator.free(pages);

    const page = &pages[0];
    page.init(uuid.v4());

    //

    const n = 1000000;
    var timer = try std.time.Timer.start();
    for (0..n) |_| {
        const record = &S1{
            .ax = random.uintLessThan(u32, 16),
            .bx = random.intRangeAtMost(i16, -8, 8),
            .cx = random.int(i16),
            .dx = random.int(i8),
        };
        _ = page.upsert(record);
    }
    const elapsed_ns = timer.read();
    const elapsed_s = @as(f64, @floatFromInt(elapsed_ns)) / std.time.ns_per_s;
    try stdout.print("inserted {d} records in {d:.6} seconds\n", .{ n, elapsed_s });
}
