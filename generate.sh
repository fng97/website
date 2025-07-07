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
