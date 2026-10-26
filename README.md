# <https://francisco.wiki>

The site is built using the [Zig](https://ziglang.org) build system and [Pandoc](https://pandoc.org)
(based on [this Tigerbeetle blog post][tigerbeetle-ssg]) and hosted with
[GitHub Pages](https://docs.github.com/en/pages). The content lives in
[`src/content`](/src/content). The CSS and generated HTML are validated with
[`vnu`](https://validator.github.io/validator/). The writing is checked with
[Vale](https://vale.sh), using British English spelling. All dependencies are managed by the Zig
build system.

Generate and validate the website with `zig build test`.

[tigerbeetle-ssg]:
  https://tigerbeetle.com/blog/2025-02-27-why-we-designed-tigerbeetles-docs-from-scratch/
