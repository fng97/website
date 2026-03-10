# `francisco.wiki`

The site is built using the [Zig](https://ziglang.org) build system and [Pandoc](https://pandoc.org)
(based on [this Tigerbeetle blog post][tigerbeetle-ssg]) and hosted with
[GitHub Pages](https://docs.github.com/en/pages). The content lives in
[`src/content`](/src/content). The CSS and generated HTML are validated with
[`vnu`](https://validator.github.io/validator/).

All dependencies are managed by the Zig build system. Build and validate with:

```plaintext
$ ./zig/download.ps1 && ./zig/zig build test --summary all

Downloading Zig 0.15.2 release build...
Extracting zig-aarch64-macos-0.15.2.tar.xz...
Downloading completed (/Users/fng/src/website/zig/zig)! Enjoy!

Build Summary: 11/11 steps succeeded
test success
├─ vnu: validate HTML success 545ms MaxRSS:338M
│  └─ install success
│     └─ install generated/ success
│        └─ WriteFile styles.css success
│           ├─ run exe blog_list_builder (index.html) success 1ms MaxRSS:1M
│           │  ├─ compile exe blog_list_builder ReleaseSafe native success 3s MaxRSS:286M
│           │  ├─ pandoc: index.md success 45ms MaxRSS:102M
│           │  └─ pandoc: 20250909-hello-world.md success 46ms MaxRSS:101M
│           ├─ run exe blog_list_builder (index.html) (+3 more reused dependencies)
│           ├─ pandoc: 20250909-hello-world.md (reused)
│           └─ pandoc: links.md success 45ms MaxRSS:102M
└─ vnu: validate CSS success 629ms MaxRSS:334M
   └─ install (+1 more reused dependencies)
```

[tigerbeetle-ssg]:
  https://tigerbeetle.com/blog/2025-02-27-why-we-designed-tigerbeetles-docs-from-scratch/
