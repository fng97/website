//! This is a build system utility driven by the build step that converts recipe ZON files to
//! Markdown. The Markdown is then converted to HTML by Pandoc like the rest of the website content.
//!
//! It has two modes. To generate a recipe page (arguments in order):
//!
//!   <recipe>   The path to the recipe ZON file.
//!   <output>   The path to save the generated Markdown.
//!
//! To generate the recipe index (arguments in order):
//!
//!   --index    Selects this mode.
//!   <output>   The path to save the generated Markdown.
//!   <recipe>   The path to a recipe ZON file. This argument is passed for every recipe. The page
//!              each entry links to is named after the file (e.g. "dal.zon" -> "dal.html").

const std = @import("std");

const Recipe = struct {
    name: []const u8,
    source: []const u8, // URL of the original recipe
    servings: u32,
    prep_time: u32, // minutes
    cook_time: u32, // minutes
    ingredients: []const struct {
        ingredient: []const u8,
        amount: ?struct {
            quantity: f64,
            unit: enum { count, tin, tsp, tbsp, g, mL, L } = .count,
        } = null, // null for ingredients that aren't measured, e.g. salt to taste
        note: []const u8 = "",
    },
    /// Each instruction is a numbered step. A blank line within a step starts a new paragraph.
    instructions: []const []const u8,

    fn fromZon(arena: std.mem.Allocator, io: std.Io, recipe_path: []const u8) !Recipe {
        const source = try std.Io.Dir.cwd().readFileAllocOptions(
            io,
            recipe_path,
            arena,
            .unlimited,
            .of(u8),
            0,
        );

        var diagnostics: std.zon.parse.Diagnostics = undefined;
        return std.zon.parse.fromSlice(Recipe, .{
            .gpa = arena,
            .arena = arena,
            .source = source,
            .diagnostics = &diagnostics,
        }) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.ParseZon => {
                diagnostics.log(recipe_path);
                std.process.exit(1);
            },
        };
    }
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const cwd = std.Io.Dir.cwd();

    var args = init.minimal.args.iterate();
    _ = args.next(); // skip the first argument (the executable)
    const first = args.next() orelse std.debug.panic("Missing arguments\n", .{});

    if (std.mem.eql(u8, first, "--index")) {
        const output_path = args.next() orelse std.debug.panic("Missing output path\n", .{});

        const Entry = struct {
            stem: []const u8, // e.g. "dal" for "dal.zon"
            recipe: Recipe,
        };
        var entries: std.ArrayList(Entry) = .empty;
        while (args.next()) |recipe_path| {
            const basename = std.fs.path.basename(recipe_path);
            try entries.append(arena, .{
                .stem = basename[0 .. basename.len - ".zon".len],
                .recipe = try .fromZon(arena, io, recipe_path),
            });
        }
        std.mem.sort(Entry, entries.items, {}, struct {
            fn lessThan(_: void, lhs: Entry, rhs: Entry) bool {
                return std.ascii.lessThanIgnoreCase(lhs.recipe.name, rhs.recipe.name);
            }
        }.lessThan);

        const output = try cwd.createFile(io, output_path, .{ .truncate = true });
        defer output.close(io);
        var buffer: [16 * 1024]u8 = undefined;
        var file_writer = output.writer(io, &buffer);
        const w: *std.Io.Writer = &file_writer.interface;

        try w.writeAll("# Recipes\n\n");
        for (entries.items) |entry| try w.print("- [{s}]({s}.md) ({d} min, serves {d})\n", .{
            entry.recipe.name,
            entry.stem,
            entry.recipe.prep_time + entry.recipe.cook_time,
            entry.recipe.servings,
        });
        try w.flush();
        return;
    }

    const recipe_path = first;
    const output_path = args.next() orelse std.debug.panic("Missing output path\n", .{});
    if (args.next()) |arg| std.debug.panic("Unknown argument: {s}\n", .{arg});
    const recipe: Recipe = try .fromZon(arena, io, recipe_path);

    const output = try cwd.createFile(io, output_path, .{ .truncate = true });
    defer output.close(io);
    var buffer: [16 * 1024]u8 = undefined;
    var file_writer = output.writer(io, &buffer);
    const w: *std.Io.Writer = &file_writer.interface;

    try w.writeAll("[All recipes](index.md)\n\n");
    try w.print("# {s}\n\n", .{recipe.name});
    try w.print("Serves {d}. Prep {d} min. Cook {d} min. Total {d} min.\n\n", .{
        recipe.servings,
        recipe.prep_time,
        recipe.cook_time,
        recipe.prep_time + recipe.cook_time,
    });
    try w.print("Original recipe: <{s}>\n\n", .{recipe.source});

    // Each ingredient is a checkbox so that it can be ticked off while cooking. The label makes the
    // whole line clickable, and the span lets the CSS strike through just the text (not the space
    // after the checkbox) once ticked. The ticks aren't saved: they reset when the page is
    // reloaded. The list is wrapped in a Pandoc fenced div ("::: ingredients" to ":::"), which
    // becomes <div class="ingredients"> so that the CSS only applies to this list.
    try w.writeAll("## Ingredients\n\n::: ingredients\n\n");
    for (recipe.ingredients) |ingredient| {
        try w.writeAll("- <label><input type=\"checkbox\"> <span>");
        if (ingredient.amount) |amount| switch (amount.unit) {
            .count => try w.print("{d} ", .{amount.quantity}), // e.g. "3 carrots"
            .tin => try w.print("{d} tin{s} ", .{
                amount.quantity,
                if (amount.quantity > 1) "s" else "",
            }),
            else => |unit| try w.print("{d} {t} ", .{ amount.quantity, unit }),
        };
        try w.writeAll(ingredient.ingredient);
        if (ingredient.note.len > 0) try w.print(", *{s}*", .{ingredient.note});
        try w.writeAll("</span></label>\n");
    }
    try w.writeAll("\n:::\n\n");

    try w.writeAll("## Instructions\n\n");
    for (recipe.instructions, 1..) |instruction, number| {
        // Lines after the first are indented so that any paragraphs after a blank line stay in
        // the list item.
        var lines = std.mem.splitScalar(u8, instruction, '\n');
        try w.print("{d}. {s}\n", .{ number, lines.first() });
        while (lines.next()) |line| try w.print("    {s}\n", .{line});
        try w.writeByte('\n');
    }

    try w.flush();
}
