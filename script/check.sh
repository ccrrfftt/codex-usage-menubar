#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_ROOT="${CODEX_USAGE_BUILD_ROOT:-$PROJECT_ROOT/.build/local}/checks"
mkdir -p "$CHECK_ROOT/module-cache"
xcrun swiftc -module-cache-path "$CHECK_ROOT/module-cache" \
  "$PROJECT_ROOT/Sources/CodexUsage/Models/QuotaSnapshot.swift" \
  "$PROJECT_ROOT/Sources/CodexUsage/Models/EnergyPolicy.swift" \
  "$PROJECT_ROOT/Tests/QuotaChecks.swift" -o "$CHECK_ROOT/quota-checks"
"$CHECK_ROOT/quota-checks"
xcrun swiftc -module-cache-path "$CHECK_ROOT/module-cache" \
  "$PROJECT_ROOT/Tests/FakeCodex.swift" -o "$CHECK_ROOT/fake-codex"
xcrun swiftc -swift-version 6 -module-cache-path "$CHECK_ROOT/module-cache" \
  "$PROJECT_ROOT"/Sources/CodexUsage/Models/*.swift \
  "$PROJECT_ROOT/Sources/CodexUsage/Services/CodexConnection.swift" \
  "$PROJECT_ROOT/Sources/CodexUsage/Services/SystemActivityMonitor.swift" \
  "$PROJECT_ROOT/Sources/CodexUsage/Stores/UsageStore.swift" \
  "$PROJECT_ROOT/Tests/RuntimeChecks.swift" -o "$CHECK_ROOT/runtime-checks"
"$CHECK_ROOT/runtime-checks" "$CHECK_ROOT/fake-codex"
