#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_ROOT="${CODEX_USAGE_BUILD_ROOT:-$PROJECT_ROOT/.build/local}/checks"
mkdir -p "$CHECK_ROOT/module-cache"
xcrun swiftc -module-cache-path "$CHECK_ROOT/module-cache" \
  "$PROJECT_ROOT"/Sources/CodexUsage/Models/*.swift \
  "$PROJECT_ROOT/Tests/QuotaChecks.swift" -o "$CHECK_ROOT/quota-checks"
for suite in Pricing AccountingCalendar AccountingSummary RecordedReset; do
  xcrun swiftc -swift-version 6 -module-cache-path "$CHECK_ROOT/module-cache" \
    "$PROJECT_ROOT"/Sources/CodexUsage/Models/*.swift \
    "$PROJECT_ROOT/Tests/${suite}Checks.swift" -o "$CHECK_ROOT/${suite}-checks"
  "$CHECK_ROOT/${suite}-checks"
done
"$CHECK_ROOT/quota-checks"
xcrun swiftc -swift-version 6 -module-cache-path "$CHECK_ROOT/module-cache" \
  "$PROJECT_ROOT/Sources/CodexUsage/Models/QuotaRingState.swift" \
  "$PROJECT_ROOT/Sources/CodexUsage/Services/StatusItemRing.swift" \
  "$PROJECT_ROOT/Tests/StatusRingChecks.swift" -o "$CHECK_ROOT/status-ring-checks"
"$CHECK_ROOT/status-ring-checks"
xcrun swiftc -module-cache-path "$CHECK_ROOT/module-cache" \
  "$PROJECT_ROOT/Tests/FakeCodex.swift" -o "$CHECK_ROOT/fake-codex"
xcrun swiftc -swift-version 6 -module-cache-path "$CHECK_ROOT/module-cache" \
  "$PROJECT_ROOT"/Sources/CodexUsage/Models/*.swift \
  "$PROJECT_ROOT/Sources/CodexUsage/Services/CodexConnection.swift" \
  "$PROJECT_ROOT/Sources/CodexUsage/Services/UsageAccountingReader.swift" \
  "$PROJECT_ROOT/Sources/CodexUsage/Services/ScopedThreadIndex.swift" \
  "$PROJECT_ROOT/Sources/CodexUsage/Services/SystemActivityMonitor.swift" \
  "$PROJECT_ROOT/Sources/CodexUsage/Services/RefreshScheduler.swift" \
  "$PROJECT_ROOT/Sources/CodexUsage/Stores/UsageStore.swift" \
  "$PROJECT_ROOT/Tests/RuntimeChecks.swift" -o "$CHECK_ROOT/runtime-checks"
"$CHECK_ROOT/runtime-checks" "$CHECK_ROOT/fake-codex"

xcrun swiftc -swift-version 6 -module-cache-path "$CHECK_ROOT/module-cache" \
  "$PROJECT_ROOT"/Sources/CodexUsage/Models/*.swift \
  "$PROJECT_ROOT/Sources/CodexUsage/Services/UsageAccountingReader.swift" \
  "$PROJECT_ROOT/Sources/CodexUsage/Services/ScopedThreadIndex.swift" \
  "$PROJECT_ROOT/Tests/AccountingChecks.swift" -o "$CHECK_ROOT/accounting-checks"
"$CHECK_ROOT/accounting-checks"
xcrun swiftc -swift-version 6 -module-cache-path "$CHECK_ROOT/module-cache" \
  "$PROJECT_ROOT/Tests/FakeAccountingCodex.swift" -o "$CHECK_ROOT/fake-accounting-codex"
xcrun swiftc -swift-version 6 -module-cache-path "$CHECK_ROOT/module-cache" \
  "$PROJECT_ROOT"/Sources/CodexUsage/Models/*.swift \
  "$PROJECT_ROOT/Sources/CodexUsage/Services/CodexConnection.swift" \
  "$PROJECT_ROOT/Sources/CodexUsage/Services/UsageAccountingReader.swift" \
  "$PROJECT_ROOT/Sources/CodexUsage/Services/ScopedThreadIndex.swift" \
  "$PROJECT_ROOT/Tests/AccountingConnectionChecks.swift" -o "$CHECK_ROOT/accounting-connection-checks"
"$CHECK_ROOT/accounting-connection-checks" "$CHECK_ROOT/fake-accounting-codex"

xcrun swiftc -swift-version 6 -module-cache-path "$CHECK_ROOT/module-cache" \
  "$PROJECT_ROOT"/Sources/CodexUsage/Models/*.swift \
  "$PROJECT_ROOT/Sources/CodexUsage/Services/CodexConnection.swift" \
  "$PROJECT_ROOT/Sources/CodexUsage/Services/UsageAccountingReader.swift" \
  "$PROJECT_ROOT/Sources/CodexUsage/Services/ScopedThreadIndex.swift" \
  "$PROJECT_ROOT/Sources/CodexUsage/Services/SystemActivityMonitor.swift" \
  "$PROJECT_ROOT/Sources/CodexUsage/Services/RefreshScheduler.swift" \
  "$PROJECT_ROOT/Sources/CodexUsage/Stores/UsageStore.swift" \
  "$PROJECT_ROOT/Tests/AccountingStoreChecks.swift" -o "$CHECK_ROOT/accounting-store-checks"
"$CHECK_ROOT/accounting-store-checks"

xcrun swiftc -swift-version 6 -module-cache-path "$CHECK_ROOT/module-cache" \
  "$PROJECT_ROOT"/Sources/CodexUsage/Models/*.swift \
  "$PROJECT_ROOT/Sources/CodexUsage/Services/ScopedThreadIndex.swift" \
  "$PROJECT_ROOT/Tests/ScopedThreadIndexChecks.swift" -o "$CHECK_ROOT/scoped-index-checks"
"$CHECK_ROOT/scoped-index-checks"
