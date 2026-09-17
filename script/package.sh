#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CODEX_USAGE_CONFIGURATION=release "$PROJECT_ROOT/script/build_and_run.sh" --build-only
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_ROOT/dist/Codex Usage.app/Contents/Info.plist")
ARCH=$(uname -m)
ARCHIVE="Codex-Usage-${VERSION}-macOS-${ARCH}.zip"
/usr/bin/ditto -c -k --keepParent --norsrc "$PROJECT_ROOT/dist/Codex Usage.app" "$PROJECT_ROOT/dist/$ARCHIVE"
cd "$PROJECT_ROOT/dist"
shasum -a 256 "$ARCHIVE" > SHA256SUMS.txt
