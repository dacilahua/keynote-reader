#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="../Keynote Reader.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/keynote-reader-clang-cache"
for ARCH in arm64 x86_64; do
  xcrun swiftc main.swift -O -target "$ARCH-apple-macosx13.0" -o "$APP/Contents/MacOS/KeynoteReader-$ARCH" -framework AppKit -framework PDFKit -framework CoreText
 done
lipo -create "$APP/Contents/MacOS/KeynoteReader-arm64" "$APP/Contents/MacOS/KeynoteReader-x86_64" -output "$APP/Contents/MacOS/KeynoteReader"
rm "$APP/Contents/MacOS/KeynoteReader-arm64" "$APP/Contents/MacOS/KeynoteReader-x86_64"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp fixture.applescript "$APP/Contents/Resources/fixture.applescript"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
echo "Built: $APP"
