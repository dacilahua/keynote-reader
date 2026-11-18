#!/bin/bash
set -euo pipefail
SOURCE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$SOURCE")"
RELEASE="$(dirname "$ROOT")/release"
VERSION="1.1.1"
"$SOURCE/build.sh"
"$SOURCE/test.sh"
mkdir -p "$RELEASE"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/reader-release.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ditto "$ROOT/Keynote Reader.app" "$STAGE/Keynote Reader.app"
cp "$ROOT/安装说明.txt" "$ROOT/使用说明.md" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
codesign --verify --deep --strict "$STAGE/Keynote Reader.app"
# Optional disk image: use --dmg on a host with DiskManagement access.
if [[ "${1:-}" == "--dmg" ]]; then
 hdiutil create -volname "Keynote Reader $VERSION" -srcfolder "$STAGE" -format UDZO -ov "$RELEASE/KeynoteReader-$VERSION.dmg"
fi
# ZIP alternative has the same installable app and instructions.
ditto -c -k --sequesterRsrc "$STAGE" "$RELEASE/KeynoteReader-$VERSION-macOS.zip"
SOURCE_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/reader-source.XXXXXX")"
trap 'rm -rf "$STAGE" "$SOURCE_STAGE"' EXIT
mkdir -p "$SOURCE_STAGE/KeynoteReader-Source"
ditto "$SOURCE" "$SOURCE_STAGE/KeynoteReader-Source/Source"
cp "$ROOT/安装说明.txt" "$ROOT/使用说明.md" "$SOURCE_STAGE/KeynoteReader-Source/"
ditto -c -k --sequesterRsrc --keepParent "$SOURCE_STAGE/KeynoteReader-Source" "$RELEASE/KeynoteReader-$VERSION-source.zip"
(cd "$RELEASE" && shasum -a 256 "KeynoteReader-$VERSION-macOS.zip" "KeynoteReader-$VERSION-source.zip" > SHA256SUMS.txt)
echo "Release: $RELEASE"
