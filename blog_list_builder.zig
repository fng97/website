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

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = try std.process.argsWithAllocator(allocator);

    var index_path: ?[]const u8 = null;
    var output_path: ?[]const u8 = null;

    _ = args.next(); // skip the first argument (the executable)

    var blog_post_list_entries = std.ArrayList([]const u8).init(allocator);

    while (args.next()) |arg| {
        const index_prefix = "--index=";
        if (std.mem.startsWith(u8, arg, index_prefix)) {
            std.debug.assert(index_path == null); // there can only be one
            index_path = arg[index_prefix.len..];
            continue;
        }

        const output_prefix = "--output=";
        if (std.mem.startsWith(u8, arg, output_prefix)) {
            std.debug.assert(output_path == null); // there can only be one
            output_path = arg[output_prefix.len..];
            continue;
        }

        const blog_post_prefix = "--blog-post=";
        if (std.mem.startsWith(u8, arg, blog_post_prefix)) {
            // e.g. "--blog-post=20250705-i-like-coffee.html:{zig-cache-path}/stdout"
            const arg_value = arg[blog_post_prefix.len..]; // strips --blog-post=
            const colon_index = std.mem.indexOfScalar(u8, arg_value, ':').?;
            const link_path = arg_value[0..colon_index]; // 20250705-i-like-coffee.html
            const cache_path = arg_value[colon_index + 1 ..]; // {zig-cache-path}/stdout

            const file = try std.fs.cwd().openFile(cache_path, .{});
            defer file.close();
            const file_stat = try file.stat();
            const content = try file.readToEndAlloc(allocator, file_stat.size);
            defer allocator.free(content);

            // Parse the blog post title (between <title> and </title>).
            const title_prefix = "<title>";
            const title_suffix = "</title>";
            const title_start = std.mem.indexOf(u8, content, title_prefix).? + title_prefix.len;
            const title_end = std.mem.indexOf(u8, content, title_suffix).?;
            const title = content[title_start..title_end];

            // Parse the blog post publication date (between <p class="date"> and </p>).
            const date_prefix = "<p class=\"date\">";
            const date_suffix = "</p>";
            const date_start = std.mem.indexOf(u8, content, date_prefix).? + date_prefix.len;
            const date_end = std.mem.indexOf(u8, content[date_start..], date_suffix).? + date_start;
            const date = content[date_start..date_end];

            const list_entry = try std.fmt.allocPrint(
                allocator,
                "<li><a href=\"{s}\" target=\"_self\">{s}: {s}</a></li>",
                .{ link_path, date, title },
            );
            try blog_post_list_entries.append(list_entry);

            continue;
        }

        std.debug.panic("Unknown argument: {s}\n", .{arg});
    }

    // To sort reverse-chronologically we can sort reverse-alphabetically because the blog list
    // entries start the same until the part with the date (e.g. "<li><a href="20250705...").
    std.mem.sort([]const u8, blog_post_list_entries.items, {}, reverse_alphabetical);

    // Read the input "index.html" file.
    const index_in = try std.fs.cwd().readFileAlloc(allocator, index_path.?, 1024 * 1024);
    defer allocator.free(index_in);
    const placeholder = "<!-- BLOG-POSTS -->";
    const placeholder_index = std.mem.indexOf(u8, index_in, placeholder).?;

    const index_out = try std.fs.cwd().createFile(output_path.?, .{ .truncate = true });
    defer index_out.close();
    const index_out_writer = index_out.writer();

    // Write the output "index.html" file: split the input content around the placeholder comment,
    // injecting the blog post list in between.
    try index_out_writer.writeAll(index_in[0..placeholder_index]);
    try index_out_writer.writeAll("<ul>\n"); // list start
    for (blog_post_list_entries.items) |line| try index_out_writer.print("  {s}\n", .{line});
    try index_out_writer.writeAll("</ul>\n"); // list end
    try index_out_writer.writeAll(index_in[placeholder_index + placeholder.len ..]);
}

// Character values increase alphabetically. I.e. 'a' > 'b'.
fn reverse_alphabetical(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .gt;
}
