#!/usr/bin/env bash

set -euo pipefail

echo "Building website"

rm -rf out
mkdir out

cp styles.css out

pandoc_args=(
  --from=gfm
  --to=html5
  --template=template.html
  --css=styles.css
  --fail-if-warnings=true
  --lua-filter=pandoc/title-from-h1.lua
  --lua-filter=pandoc/fix-md-links.lua
)

for page in content/*.md; do
  filename=$(basename "${page}" .md)
  html_file="${filename}.html"

  args=("${pandoc_args[@]}") # copy common arguments

  # There is a mixture of normal pages and blog posts. All blog posts start with the publication
  # date (e.g. "20250705_my-great-post.md"). If this is a blog post, pass the date to pandoc.
  if [[ "$filename" =~ ^([0-9]{8})- ]]; then # filename starts with 8 digits then an underscore
    date="${BASH_REMATCH[1]}"
    args+=("--metadata=date:$(date -d "${date}" "+%B %-d, %Y")") # add to args list
  fi

  # Generate the HTML page.
  pandoc "${args[@]}" "${page}" --output "out/${html_file}"

  echo "Built out/${html_file}"
done

# Generate HTML blog list from generated HTML files.
BLOG_LIST=$(
  echo "<ul>"
  # Match blog posts only: "YYYYMMDD-*.html".
  for f in out/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-*.html; do
    filename=$(basename "$f")
    title=$(grep --only-matching --max-count=1 --perl-regexp '(?<=<title>).*?(?=</title>)' "$f" || \
      echo "$filename")

    # Extract the date prefix from the filename. e.g. "20250707"
    date_part="${filename:0:8}"
    date_fmt=$(date -d "$date_part" +%F 2>/dev/null || echo "$date_part")

    # Add list entry in format "YYYY-MM-DD: Title".
    printf '  <li><a href="%s" target="_self">%s: %s</a></li>\n' "$filename" "$date_fmt" "$title"
  # The list of blog posts should be ordered newest to oldest.
  done | sort -r
  echo "</ul>"
)

# Replace the placeholder in out/index.html with the list of blog posts.
awk -v blog_list="$BLOG_LIST" '
  /<!-- BLOG-POSTS -->/ {
    print blog_list
    next
  }
  { print }
' out/index.html > out/tmp.html && mv out/tmp.html out/index.html
