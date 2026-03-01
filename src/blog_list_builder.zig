//! This is a build system utility driven by the build step that generates the blog posts table of
//! contents and injects it into the final "index.html".
//!
//! Arguments:
//!
//!   --index      The path to the "index.html" generated from "index.md". This argument is passed
//!                once.
//!   --output     The path to save the resulting "index.html" containing the blog post list. This
//!                argument is passed once.
//!   --blog-post  A path to a blog post (HTML) generated from Markdown. This argument is passed for
//!                every blog post.

const std = @import("std");

const Post = struct {
    link_path: []const u8,
    title: []const u8,
    date: []const u8,
};

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    // Since we're using an arena we won't bother deferring deallocations.
    var arena = std.heap.ArenaAllocator.init(debug_allocator.allocator());
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var args = try std.process.argsWithAllocator(arena_allocator);

    var index_in_path: ?[]const u8 = null;
    var index_out_path: ?[]const u8 = null;
    var feed_out_path: ?[]const u8 = null;

    _ = args.next(); // skip the first argument (the executable)

    var posts = std.array_list.Managed(Post).init(arena_allocator);

    while (args.next()) |arg| {
        const index_in_path_arg_prefix = "--index-in=";
        if (std.mem.startsWith(u8, arg, index_in_path_arg_prefix)) {
            std.debug.assert(index_in_path == null); // there can only be one
            index_in_path = arg[index_in_path_arg_prefix.len..];
            continue;
        }

        const index_out_path_arg_prefix = "--index-out=";
        if (std.mem.startsWith(u8, arg, index_out_path_arg_prefix)) {
            std.debug.assert(index_out_path == null); // there can only be one
            index_out_path = arg[index_out_path_arg_prefix.len..];
            continue;
        }

        const feed_out_path_arg_prefix = "--feed=";
        if (std.mem.startsWith(u8, arg, feed_out_path_arg_prefix)) {
            std.debug.assert(feed_out_path == null); // there can only be one
            feed_out_path = arg[feed_out_path_arg_prefix.len..];
            continue;
        }

        const blog_post_arg_prefix = "--blog-post=";
        if (std.mem.startsWith(u8, arg, blog_post_arg_prefix)) {
            // e.g. "--blog-post=20250705-i-like-coffee.html:{zig-cache-path}/stdout"
            const arg_value = arg[blog_post_arg_prefix.len..]; // strips --blog-post=
            const colon_index = std.mem.indexOfScalar(u8, arg_value, ':').?;
            const link_path = arg_value[0..colon_index]; // 20250705-i-like-coffee.html
            const cache_path = arg_value[colon_index + 1 ..]; // {zig-cache-path}/stdout

            const file = try std.fs.cwd().openFile(cache_path, .{});
            defer file.close();
            const file_stat = try file.stat();
            const content = try file.readToEndAlloc(arena_allocator, file_stat.size);

            // Find the blog post title (between <title> and </title>).
            const title_prefix = "<title>";
            const title_suffix = "</title>";
            const title_start = std.mem.indexOf(u8, content, title_prefix).? + title_prefix.len;
            const title_end = std.mem.indexOf(u8, content, title_suffix).?;
            const title = content[title_start..title_end];

            // Find the blog post publication date (between <p class="date"> and </p>).
            const date_prefix = "<p class=\"date\">";
            const date_suffix = "</p>";
            const date_start = std.mem.indexOf(u8, content, date_prefix).? + date_prefix.len;
            const date_end = std.mem.indexOf(u8, content[date_start..], date_suffix).? + date_start;
            const date = content[date_start..date_end];

            try posts.append(.{
                .link_path = try arena_allocator.dupe(u8, link_path),
                .title = try arena_allocator.dupe(u8, title),
                .date = try arena_allocator.dupe(u8, date),
            });
            continue;
        }

        std.debug.panic("Unknown argument: {s}\n", .{arg});
    }

    std.mem.sort(Post, posts.items, {}, reverse_chronological);

    // Read the input "index.html" file.
    const index_in = try std.fs.cwd().readFileAlloc(arena_allocator, index_in_path.?, 1024 * 1024);
    const placeholder = "<!-- BLOG-POSTS -->";
    const placeholder_index = std.mem.indexOf(u8, index_in, placeholder).?;

    const index_out = try std.fs.cwd().createFile(index_out_path.?, .{ .truncate = true });
    defer index_out.close();
    // Write the output "index.html" file: split the input content around the placeholder comment,
    // injecting the blog post list in between.
    try index_out.writeAll(index_in[0..placeholder_index]);
    try index_out.writeAll("<ul>\n"); // list start
    for (posts.items) |post| try index_out.writeAll(try std.fmt.allocPrint(
        arena_allocator,
        "<li><a href=\"{s}\" target=\"_self\">{s}: {s}</a></li>",
        .{ post.link_path, post.date, post.title },
    ));
    try index_out.writeAll("</ul>\n"); // list end
    try index_out.writeAll(index_in[placeholder_index + placeholder.len ..]);

    var feed_out = try std.fs.cwd().createFile(feed_out_path.?, .{ .truncate = true });
    defer feed_out.close();
    try feed_out.writeAll(
        \\<?xml version="1.0" encoding="utf-8"?>
        \\<feed xmlns="http://www.w3.org/2005/Atom">
        \\  <title>Francisco's Blog</title>
        \\  <author>
        \\    <name>Francisco Nevitt Gonçalves</name>
        \\  </author>
        \\  <link href="https://francisco.wiki/"/>
        \\  <link href="https://francisco.wiki/atom.xml" rel="self" type="application/rss+xml"/>
        \\  <id>https://francisco.wiki/</id>
    );
    // Use most recent post's publication date for feed's last-updated.
    try feed_out.writeAll(try std.fmt.allocPrint(
        arena_allocator,
        "  <updated>{s}T00:00:00Z</updated>\n",
        .{posts.items[0].date},
    ));
    for (posts.items) |p| {
        try feed_out.writeAll(try std.fmt.allocPrint(
            arena_allocator,
            \\  <entry>
            \\    <title>{s}</title>
            \\    <link href="https://francisco.wiki/{s}"/>
            \\    <id>https://francisco.wiki/{s}</id>
            \\    <updated>{s}T00:00:00Z</updated>
            \\  </entry>
        ,
            .{ p.title, p.link_path, p.link_path, p.date },
        ));
    }
    try feed_out.writeAll("</feed>\n");
}

// To sort reverse-chronologically we can sort reverse-alphabetically because the blog list entries
// start the same until the part with the date (e.g. "<li><a href="20250705..."). Character values
// increase alphabetically. I.e. 'a' < 'b'.
fn reverse_chronological(_: void, lhs: Post, rhs: Post) bool {
    return std.mem.order(u8, lhs.date, rhs.date) == .gt;
}
