const std = @import("std");
const html_dir = @import("options").html_dir;

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const io = init.io;

    var dir = try std.Io.Dir.cwd().openDir(io, html_dir, .{ .iterate = true });
    defer dir.close(io);
    var walker = try dir.walk(allocator);

    var http_links = std.array_list.AlignedManaged([]const u8, null).init(allocator);

    // Go through html_dir one HTML file at a time.
    while (try walker.next(io)) |entry| switch (entry.kind) {
        .file => {
            if (!std.mem.endsWith(u8, entry.basename, ".html")) continue;

            const content = try dir.readFileAlloc(io, entry.path, allocator, .unlimited);

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
                if (std.mem.startsWith(u8, link, "#")) continue; // same-page anchor

                const bad_links = [_][]const u8{
                    "https://youtu", // redirects and probably bot detection
                };
                for (bad_links) |start| if (std.mem.startsWith(u8, link, start)) continue :links;

                const own_link_start = "https://francisco.wiki/";
                if (std.mem.startsWith(u8, link, own_link_start)) {
                    try check_relative_path(io, dir, link[own_link_start.len..]); // check as path
                    continue;
                }

                // If it starts with HTTP, we'll see if we get a 200 back. Otherwise, we assume it's
                // a relative path so we just check the file exists.
                if (std.mem.startsWith(u8, link, "http")) {
                    try http_links.append(try allocator.dupe(u8, link));
                    continue;
                }

                try check_relative_path(io, dir, link);
            }
        },
        .directory => {},
        else => unreachable,
    };

    std.debug.assert(http_links.items.len > 0);

    var client: std.http.Client = .{ .allocator = init.gpa, .io = io };
    defer client.deinit();
    try client.initDefaultProxies(allocator, init.environ_map);

    // Each worker reports its failure (if any) in its own slot so we can list every broken link
    // rather than stopping at the first.
    const failures = try allocator.alloc(?[]const u8, http_links.items.len);
    @memset(failures, null);

    var group: std.Io.Group = .init;
    for (http_links.items, failures) |url, *failure|
        group.async(io, check_link_worker, .{ allocator, &client, url, failure });
    try group.await(io);

    var failed = false;
    for (failures) |failure| if (failure) |message| {
        std.debug.print("{s}\n", .{message});
        failed = true;
    };
    if (failed) return error.LinksNotReachable;
}

fn check_link(client: *std.http.Client, url: []const u8) !std.http.Status {
    const uri = try std.Uri.parse(url);
    var request = try client.request(.HEAD, uri, .{
        .redirect_behavior = .not_allowed,
        .keep_alive = false,
    });
    defer request.deinit();
    try request.sendBodiless();

    const response = try request.receiveHead(&.{});
    return response.head.status;
}

/// Sets `failure` to a message saying why `url` couldn't be reached, if it couldn't.
fn check_link_worker(
    allocator: std.mem.Allocator,
    client: *std.http.Client,
    url: []const u8,
    failure: *?[]const u8,
) void {
    const status = check_link(client, url) catch |e| {
        failure.* = std.fmt.allocPrint(allocator, "'{s}': {s}", .{ url, @errorName(e) }) catch
            @panic("OOM");
        return;
    };
    if (status != .ok) {
        failure.* = std.fmt.allocPrint(allocator, "'{s}': HEAD request returned {d}", .{
            url,
            @backingInt(status),
        }) catch @panic("OOM");
    }
}

fn check_relative_path(io: std.Io, dir: std.Io.Dir, link: []const u8) !void {
    const path = link[0 .. std.mem.indexOfScalar(u8, link, '#') orelse link.len]; // drop fragment
    dir.access(io, path, .{}) catch |e| switch (e) {
        error.FileNotFound => {
            std.debug.print("Relative link '{s}' not in prefix\n", .{path});
            return e;
        },
        else => return e,
    };
}
