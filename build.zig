const std = @import("std");

pub fn build(b: *std.Build) !void {
    const host = b.graph.host.result;
    const pandoc_exe = dependency: {
        // We return null here if the dependency hasn't been fetched. The build system will attempt
        // to fetch it and run this (the configure stage) again.
        const dependency = if (host.os.tag == .linux and host.cpu.arch == .x86_64)
            b.lazyDependency("pandoc_linux_amd64", .{}) orelse return
        else if (host.os.tag == .macos and host.cpu.arch == .aarch64)
            b.lazyDependency("pandoc_macos_arm64", .{}) orelse return
        else
            return error.PandocDependencyNotFoundForHost;
        break :dependency dependency.path("bin/pandoc");
    };

    const website = b.addWriteFiles(); // output folder for website content
    _ = website.addCopyFile(b.path("styles.css"), "styles.css"); // copy in the style file

    // This step generates the list of blog post links and injects it into the final "index.html".
    // It takes an input "index.html" path (--index), an output "index.html" path (--output), and
    // all of the blog post paths (multiple --blog-post arguments).
    const blog_list_builder = b.addExecutable(.{
        .name = "blog_list_builder",
        .root_source_file = b.path("blog_list_builder.zig"),
        .target = b.graph.host,
    });
    const build_blog_list_step = b.addRunArtifact(blog_list_builder);
    const updated_index = build_blog_list_step.addPrefixedOutputFileArg("--output=", "index.html");

    _ = website.addCopyFile(updated_index, "index.html"); // copy in the final "index.html"

    // Process website content. Non-Markdown files are copied directly to the output. HTML is
    // generated from Markdown files using Pandoc.
    var dir = try std.fs.cwd().openDir("content", .{ .iterate = true });
    defer dir.close();
    var walker = try dir.walk(b.allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;

        const filepath = b.path(b.pathJoin(&.{ "content", entry.path }));
        const filename = entry.basename;

        // Copy in non-Markdown files (assets).
        if (!std.mem.endsWith(u8, entry.basename, ".md")) {
            _ = website.addCopyFile(filepath, entry.path); // preserve file structure
            continue;
        }

        // Blog posts start with the publication date and have the format "YYYYMMDD-*.md": eight
        // digits followed by a "-".
        const is_blog_post = filename.len >= 9 and filename[8] == '-' and starts_with_8_digits: {
            for (filename[0..8]) |c| if (!std.ascii.isDigit(c)) break :starts_with_8_digits false;
            break :starts_with_8_digits true;
        };

        // Create a Pandoc step for each Markdown file to generate HTML from the Markdown.
        const pandoc_step = std.Build.Step.Run.create(b, b.fmt("pandoc: {s}", .{filename}));
        pandoc_step.addFileArg(pandoc_exe);
        pandoc_step.addArgs(&.{
            "--from=markdown",
            "--to=html5",
            "--fail-if-warnings=true",
        });
        pandoc_step.addPrefixedFileArg("--template=", b.path("template.html"));
        pandoc_step.addPrefixedFileArg("--css=", b.path("styles.css"));
        pandoc_step.addPrefixedFileArg("--lua-filter=", b.path("pandoc/title-from-h1.lua"));
        pandoc_step.addPrefixedFileArg("--lua-filter=", b.path("pandoc/fix-md-links.lua"));
        if (is_blog_post) { // pass the publication date as metadata to Pandoc
            const year = filename[0..4]; // YYYY
            const month = filename[4..6]; // MM
            const day = filename[6..8]; // DD
            pandoc_step.addArg(b.fmt("--metadata=date:{s}-{s}-{s}", .{ year, month, day }));
        }
        pandoc_step.addFileArg(filepath);
        const generated_html_path = pandoc_step.captureStdOut();

        // Map "*.md" -> "*.html" (e.g. "index.md" -> "index.html").
        const html_filename = b.fmt("{s}.html", .{filename[0 .. filename.len - ".md".len]});

        if (std.mem.eql(u8, filename, "index.md")) {
            // Don't copy in "index.html". This step will save the final "index.html".
            build_blog_list_step.addPrefixedFileArg("--index=", generated_html_path);
            continue;
        }

        if (is_blog_post) build_blog_list_step.addPrefixedFileArg(
            b.fmt("--blog-post={s}:", .{html_filename}), // need the filename for the hyperlink
            generated_html_path,
        ); // e.g. "--blog-post=20250705-i-like-coffee.html:{zig-cache-path}/stdout"

        _ = website.addCopyFile(generated_html_path, html_filename); // copy in generated HTML
    }

    b.installDirectory(.{
        .source_dir = website.getDirectory(),
        .install_dir = .prefix,
        .install_subdir = ".",
    });

    // This step is used to "hot-reload" the web page as I'm working on it. I hook this up to a nvim
    // autocmd that runs on save.
    const reload_step = b.step("reload", "Open (or reload) the given page in the default browser.");
    const open_cmd = b.addSystemCommand(&.{ "open", "--background" });
    if (b.args) |a| open_cmd.addArgs(a) else open_cmd.step.dependOn(
        &b.addFail("'open' requires at least one argument").step,
    );
    if (host.os.tag != .macos) open_cmd.step.dependOn(&b.addFail("'open' is macOS-only").step);
    open_cmd.step.dependOn(b.getInstallStep());
    reload_step.dependOn(&open_cmd.step);
}
