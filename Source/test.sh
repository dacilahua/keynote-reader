#!/bin/bash
set -euo pipefail
SOURCE="$(cd "$(dirname "$0")" && pwd)"
APP="$SOURCE/../Keynote Reader.app/Contents/MacOS/KeynoteReader"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/reader-test.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
cd "$TEST_DIR"
mkdir work
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/keynote-reader-clang-cache"
xcrun swift "$SOURCE/edge-fixture.swift"
"$APP" --compose work/edge.pdf work/edge.json work/edge-a4.pdf --a4
"$APP" --compose work/edge.pdf work/edge.json work/edge-compact.pdf
xcrun swift "$SOURCE/check-edge.swift"
if [[ -f "$SOURCE/../跳过页测试-阅读版.pdf" ]]; then
  xcrun swift "$SOURCE/verify.swift" "$SOURCE/../跳过页测试-阅读版.pdf"
fi
xcrun swift "$SOURCE/compression-fixture.swift"
"$APP" --compose work/compression-input.pdf work/compression-notes.json work/compression-original.pdf --original
"$APP" --compose work/compression-input.pdf work/compression-notes.json work/compression-screen.pdf
"$APP" --compose work/compression-input.pdf work/compression-notes.json work/compression-small.pdf --small
xcrun swift "$SOURCE/check-compression.swift"
