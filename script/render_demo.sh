#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEMO_ROOT="${CODEX_USAGE_BUILD_ROOT:-$PROJECT_ROOT/.build/local}/demo"
OUTPUT_ROOT="${CODEX_USAGE_DEMO_OUTPUT_ROOT:-$PROJECT_ROOT/Assets}"
mkdir -p "$DEMO_ROOT/module-cache" "$OUTPUT_ROOT"
xcrun swiftc -swift-version 6 -parse-as-library -module-cache-path "$DEMO_ROOT/module-cache" \
  "$PROJECT_ROOT"/Sources/CodexUsage/Models/*.swift \
  "$PROJECT_ROOT/Sources/CodexUsage/Services/StatusItemRing.swift" \
  "$PROJECT_ROOT/Sources/CodexUsage/Services/StatusItemLabel.swift" \
  "$PROJECT_ROOT/Sources/CodexUsage/Views/QuotaSummaryView.swift" \
  "$PROJECT_ROOT/Sources/CodexUsage/Views/ResetCardsView.swift" \
  "$PROJECT_ROOT/Sources/CodexUsage/Views/UsageAccountingView.swift" \
  "$PROJECT_ROOT/script/render_demo.swift" -o "$DEMO_ROOT/render-demo"
TZ=UTC "$DEMO_ROOT/render-demo" "$OUTPUT_ROOT"
