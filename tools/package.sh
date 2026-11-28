#!/usr/bin/env bash
# Builds the release archive: EnemyTracker-<version>.zip with one top-level
# EnemyTracker/ folder holding only what the game loads (the .toc, the files
# it lists, Media/, LICENSE). Tests, tools and docs stay out.
# Also writes the changelog of this version to dist/CHANGELOG-<version>.md.
#
# Usage (from the repository root): tools/package.sh   (needs zip)
set -euo pipefail

NAME=EnemyTracker
TOC="$NAME.toc"
version=$(sed -n 's/^## Version: *//p' "$TOC" | tr -d '\r')
[ -n "$version" ] || { echo "no version in $TOC" >&2; exit 1; }

rm -rf dist
mkdir -p "dist/$NAME/Media"
cp "$TOC" LICENSE "dist/$NAME/"
# Every file the .toc loads (non-comment, non-empty lines).
grep -v '^\s*#' "$TOC" | tr -d '\r' | sed '/^\s*$/d' | while read -r f; do
    [ -f "$f" ] || { echo "listed in $TOC but missing: $f" >&2; exit 1; }
    cp "$f" "dist/$NAME/"
done
cp Media/*.tga "dist/$NAME/Media/"

# This version's section of CHANGELOG.md (up to the next "## ").
awk -v v="## $version" '$0 == v { on = 1; next } on && /^## / { exit } on' CHANGELOG.md > "dist/CHANGELOG-$version.md"
[ -s "dist/CHANGELOG-$version.md" ] || { echo "CHANGELOG.md has no section for $version" >&2; exit 1; }

(cd dist && zip -qr "$NAME-$version.zip" "$NAME")
echo "dist/$NAME-$version.zip"
