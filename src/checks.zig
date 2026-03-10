const std = @import("std");
const html_dir = @import("config").html_dir;

test "validate_html" {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const allocator = debug_allocator.allocator();

    try std.testing.expect(html_dir.len > 0);

    var child = std.process.Child.init(&.{
        "vnu",
        "--Werror",
        "--filterpattern",
        ".*Trailing slash.*",
        "--skip-non-html",
        html_dir,
    }, allocator);

    try std.testing.expectEqual(std.process.Child.Term{ .Exited = 0 }, try child.spawnAndWait());
}

test "validate_css" {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const allocator = debug_allocator.allocator();

    try std.testing.expect(html_dir.len > 0);

    var child = std.process.Child.init(&.{
        "vnu",
        "--Werror",
        "--skip-non-css",
        html_dir,
    }, allocator);

    try std.testing.expectEqual(std.process.Child.Term{ .Exited = 0 }, try child.spawnAndWait());
}
