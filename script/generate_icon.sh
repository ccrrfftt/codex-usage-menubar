#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON_ROOT="${1:-$PROJECT_ROOT/.build/icons}"
ICON_SET="$ICON_ROOT/CodexUsage.iconset"
mkdir -p "$ICON_SET"
for size in 16 32 128 256 512; do
    /usr/bin/sips -z "$size" "$size" "$PROJECT_ROOT/Assets/AppIcon.png" --out "$ICON_SET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    /usr/bin/sips -z "$double" "$double" "$PROJECT_ROOT/Assets/AppIcon.png" --out "$ICON_SET/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$ICON_SET" -o "$ICON_ROOT/CodexUsage.icns"
