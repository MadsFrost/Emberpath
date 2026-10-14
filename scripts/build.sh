#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:-$(git describe --tags --always --dirty)}"
out=".release"
rm -rf "$out"
mkdir -p "$out/Emberpath"

# Ship exactly what the TOC loads, nothing else.
for f in $(grep -E '\.(lua|xml)$' Emberpath.toc | tr -d '\r' | tr '\\' '/'); do
	mkdir -p "$out/Emberpath/$(dirname "$f")"
	cp "$f" "$out/Emberpath/$f"
done
sed "s/@project-version@/$version/" Emberpath.toc > "$out/Emberpath/Emberpath.toc"

(cd "$out" && zip -qr "Emberpath-$version.zip" Emberpath)
echo "$out/Emberpath-$version.zip"
