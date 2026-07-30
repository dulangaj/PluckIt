#!/bin/bash
# Regenerate PluckIt/Assets.xcassets/AppIcon.appiconset from a single source image.
#
# Usage: scripts/update-app-icon.sh path/to/image.png

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <path-to-image>" >&2
  exit 1
fi

SOURCE="$1"

if [ ! -f "$SOURCE" ]; then
  echo "error: file not found: $SOURCE" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ICONSET_DIR="$SCRIPT_DIR/../PluckIt/Assets.xcassets/AppIcon.appiconset"

if [ ! -d "$ICONSET_DIR" ]; then
  echo "error: iconset not found: $ICONSET_DIR" >&2
  exit 1
fi

WIDTH=$(sips -g pixelWidth "$SOURCE" | awk '/pixelWidth/{print $2}')
HEIGHT=$(sips -g pixelHeight "$SOURCE" | awk '/pixelHeight/{print $2}')
MIN_SIDE=$(( WIDTH < HEIGHT ? WIDTH : HEIGHT ))

if [ "$MIN_SIDE" -lt 1024 ]; then
  echo "error: source image is ${WIDTH}x${HEIGHT}, need at least 1024x1024" >&2
  exit 1
fi

pairs=(
  "x16.png:16"
  "x32 1.png:32"
  "x32.png:32"
  "x64.png:64"
  "x3.png:128"
  "x2 1.png:256"
  "x2.png:256"
  "x 1.png:512"
  "x.png:512"
  "PluckIt.png:1024"
)

for p in "${pairs[@]}"; do
  filename="${p%:*}"
  size="${p##*:}"
  sips -z "$size" "$size" "$SOURCE" --out "$ICONSET_DIR/$filename" >/dev/null
  echo "wrote $filename (${size}x${size})"
done

echo "done"
