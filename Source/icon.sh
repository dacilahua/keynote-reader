#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
ICONSET="$(mktemp -d "${TMPDIR:-/tmp}/reader-icon.XXXXXX")/AppIcon.iconset"
mkdir -p "$ICONSET"
trap 'rm -rf "$(dirname "$ICONSET")"' EXIT
for SIZE in 16 32 128 256 512; do
 sips -z "$SIZE" "$SIZE" Assets/AppIcon.png --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
 DOUBLE=$((SIZE * 2))
 sips -z "$DOUBLE" "$DOUBLE" Assets/AppIcon.png --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
python3 - "$ICONSET" Assets/AppIcon.icns <<'PYICON'
import pathlib, struct, sys
source = pathlib.Path(sys.argv[1])
chunks = []
for tag, name in [(b'icp4','icon_16x16.png'),(b'icp5','icon_32x32.png'),(b'ic07','icon_128x128.png'),(b'ic08','icon_256x256.png'),(b'ic09','icon_512x512.png'),(b'ic10','icon_512x512@2x.png'),(b'ic11','icon_16x16@2x.png'),(b'ic12','icon_32x32@2x.png'),(b'ic13','icon_128x128@2x.png'),(b'ic14','icon_256x256@2x.png')]:
    data = (source/name).read_bytes()
    chunks.append(tag + struct.pack('>I',len(data)+8) + data)
body = b''.join(chunks)
pathlib.Path(sys.argv[2]).write_bytes(b'icns'+struct.pack('>I',len(body)+8)+body)
PYICON
