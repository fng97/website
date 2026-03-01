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

fn check_link(_: std.mem.Allocator, client: *std.http.Client, url: []const u8) !void {
    const uri = try std.Uri.parse(url);
    var request = try client.request(.HEAD, uri, .{
        .redirect_behavior = .not_allowed,
        .keep_alive = false,
    });
    defer request.deinit();
    try request.sendBodiless();

    const response = try request.receiveHead(&.{});
    const status = response.head.status;

    if (status != std.http.Status.ok) {
        std.debug.print("HEAD request to '{s}' returned {d}\n", .{ url, status });
        return error.LinkNotOk;
    }
}

fn check_link_worker(
    wait_group: *std.Thread.WaitGroup,
    allocator: std.mem.Allocator,
    client: *std.http.Client,
    url: []const u8,
) void {
    defer wait_group.finish();
    check_link(allocator, client, url) catch |e|
        std.debug.panic("Error: {s}. Failed to reach: '{s}'\n", .{ @errorName(e), url });
}

fn check_relative_path(dir: std.fs.Dir, path: []const u8) !void {
    dir.access(path, .{}) catch |e| switch (e) {
        error.FileNotFound => {
            std.debug.print("Relative link '{s}' not in prefix\n", .{path});
            return e;
        },
        else => return e,
    };
}

test "check_links" {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const allocator = debug_allocator.allocator();

    try std.testing.expect(html_dir.len > 0);
    var dir = try std.fs.cwd().openDir(html_dir, .{ .iterate = true });
    defer dir.close();
    var walker = try dir.walk(allocator);

    var http_links = std.array_list.AlignedManaged([]const u8, null).init(allocator);

    // Go through html_dir one HTML file at a time.
    while (try walker.next()) |entry| switch (entry.kind) {
        .file => {
            if (!std.mem.endsWith(u8, entry.basename, ".html")) continue;

            const file = try dir.openFile(entry.path, .{});
            defer file.close();
            const stat = try file.stat();
            var content = try file.readToEndAlloc(allocator, stat.size);

            // Go through HTML file one link at a time.
            const link_prefix = "href=\""; // from href="
            const link_suffix = "\""; // to "
            var pos: usize = 0;
            links: while (std.mem.indexOfPos(u8, content, pos, link_prefix)) |prefix_start| {
                const start_pos = prefix_start + link_prefix.len;
                const end_pos = std.mem.indexOfPos(u8, content, start_pos, link_suffix).?;
                pos = end_pos + link_suffix.len;
                const link = content[start_pos..end_pos];

                std.debug.assert(link.len > 0);

                if (std.mem.startsWith(u8, link, "mailto:")) continue;

                const bad_links = [_][]const u8{
                    "https://youtu", // redirects and probably bot detection
                };
                for (bad_links) |start| if (std.mem.startsWith(u8, link, start)) continue :links;

                const own_link_start = "https://francisco.wiki/";
                if (std.mem.startsWith(u8, link, own_link_start)) {
                    try check_relative_path(dir, link[own_link_start.len..]); // check as path
                    continue;
                }

                // If it starts with HTTP, we'll see if we get a 200 back. Otherwise, we assume it's
                // a relative path so we just check the file exists.
                if (std.mem.startsWith(u8, link, "http")) {
                    try http_links.append(try allocator.dupe(u8, link));
                    continue;
                }

                try check_relative_path(dir, link);
            }
        },
        .directory => {},
        else => unreachable,
    };

    std.debug.assert(http_links.items.len > 0);

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var thread_pool: std.Thread.Pool = undefined;
    try thread_pool.init(.{
        .allocator = allocator,
        .n_jobs = @min(http_links.items.len, 50), // limit concurrent connections
    });
    defer thread_pool.deinit();
    var wait_group = std.Thread.WaitGroup{};
    for (http_links.items) |url| {
        wait_group.start();
        try thread_pool.spawn(check_link_worker, .{ &wait_group, allocator, &client, url });
    }
    thread_pool.waitAndWork(&wait_group);
}
