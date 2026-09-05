#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$PROJECT_ROOT/script/build_and_run.sh" --build-only
/usr/bin/ditto -c -k --keepParent --norsrc "$PROJECT_ROOT/dist/Codex Usage.app" "$PROJECT_ROOT/dist/Codex-Usage-macOS-arm64.zip"
cd "$PROJECT_ROOT/dist"
shasum -a 256 Codex-Usage-macOS-arm64.zip > SHA256SUMS.txt
