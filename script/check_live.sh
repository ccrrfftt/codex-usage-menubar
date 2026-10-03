#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_ROOT="${CODEX_USAGE_BUILD_ROOT:-$PROJECT_ROOT/.build/local}/live-check"
mkdir -p "$CHECK_ROOT/module-cache"
xcrun swiftc -swift-version 6 -module-cache-path "$CHECK_ROOT/module-cache" \
  "$PROJECT_ROOT"/Sources/CodexUsage/Models/*.swift \
  "$PROJECT_ROOT/Sources/CodexUsage/Services/CodexConnection.swift" \
  "$PROJECT_ROOT/Sources/CodexUsage/Services/UsageAccountingReader.swift" \
  "$PROJECT_ROOT/script/check_live.swift" -o "$CHECK_ROOT/live-check"
"$CHECK_ROOT/live-check"
