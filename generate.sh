#!/usr/bin/env bash

echo "Building website"

rm -rf out
mkdir out

cp styles.css out

for page in content/*.html; do
  filename=$(basename "${page}")
  cat partial/header.html "${page}" partial/footer.html > "out/${filename}"
  echo "Generated out/${filename}"
done

open out/index.html
