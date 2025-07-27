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

    // The output folder for the website content. The contents of this folder get copied to the
    // installation directory.
    const website = b.addWriteFiles();
    _ = website.addCopyFile(b.path("styles.css"), "styles.css"); // copy in the style file

    // This step generates the list of blog post links and injects it into the final "index.html".
    // It takes an input "index.html" path (--index=...), an output "index.html" path
    // (--output=...), and all of the blog post paths (multiple --blog-post=... arguments).
    const blog_list_builder = b.addExecutable(.{
        .name = "blog_list_builder",
        .root_source_file = b.path("blog_list_builder.zig"),
        .target = b.graph.host,
    });
    const build_blog_list_step = b.addRunArtifact(blog_list_builder);
    const output_index = build_blog_list_step.addPrefixedOutputFileArg("--output=", "index.html");

    _ = website.addCopyFile(output_index, "index.html"); // copy in the final "index.html"

    // NOTE: This only works for tracked files. Expect an error if a committed md file is deleted.
    var lines = std.mem.tokenizeScalar(u8, b.run(&.{ "git", "ls-files", "content/*.md" }), '\n');

    // This iterates over all of the Markdown files to add them to the build tree. A Pandoc step
    // (generates HTML from the Markdown file) is created for each file. The index and blog post
    // Markdown files also get passed as arguments to build_blog_list_step (single step). The
    // generated HTML from all but the index file are copied directly to the output folder.
    while (lines.next()) |file_path| { // e.g. "content/index.md"
        // Map "content/*.md" paths to "*.html" (e.g. "content/index.md" to "index.html").
        const html_path = b.fmt("{s}.html", .{file_path[8 .. file_path.len - 3]});

        // Blog posts start with the publication date and have the format "YYYYMMDD-*.md": eight
        // digits followed by a "-".
        const is_blog_post = html_path.len >= 9 and html_path[8] == '-' and all_numeric: {
            for (html_path[0..8]) |c| if (!std.ascii.isDigit(c)) break :all_numeric false;
            break :all_numeric true;
        };

        const pandoc_step = std.Build.Step.Run.create(b, "run pandoc");
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
            const year = html_path[0..4]; // YYYY
            const month = html_path[4..6]; // MM
            const day = html_path[6..8]; // DD
            pandoc_step.addArg(b.fmt("--metadata=date:{s}-{s}-{s}", .{ year, month, day }));
        }
        pandoc_step.addFileArg(b.path(file_path));
        const generated_html = pandoc_step.captureStdOut();

        if (std.mem.eql(u8, file_path, "content/index.md")) {
            build_blog_list_step.addPrefixedFileArg("--index=", generated_html);
            // This will be the input "index.html" to the "build_blog_list_step" so we don't save it
            // to the website folder below like we do for all the other generated html files.
            // "build_blog_list_step" is responsible for saving this file to website folder once it
            // has injected the blog post list.
            continue;
        }

        // Pass all generated blog posts to the blog post list generation step so it can assemble
        // the blog post list.
        if (is_blog_post) build_blog_list_step.addPrefixedFileArg(
            b.fmt("--blog-post={s}:", .{html_path}),
            generated_html,
        ); // e.g. "--blog-post=20250705-i-like-coffee.html:{zig-cache-path}/stdout"

        _ = website.addCopyFile(generated_html, html_path); // copy in generated HTML file
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
