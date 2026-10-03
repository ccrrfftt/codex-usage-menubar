#!/bin/bash
set -euo pipefail
MODE="${1:---build-only}"
case "$MODE" in
    --build-only|--launch) ;;
    *) printf 'Usage: %s [--build-only|--launch]\n' "$0" >&2; exit 2 ;;
esac
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QA_BUILD_ROOT="${CODEX_USAGE_BUILD_ROOT:-/private/tmp/codex-usage-acceptance}"
QA_STAGE="$QA_BUILD_ROOT/ui-fixture"
QA_APP_BUNDLE="$QA_STAGE/Codex Usage QA.app"
QA_EXECUTABLE="$QA_APP_BUNDLE/Contents/MacOS/CodexUsageQA"
QA_ARCH="$(uname -m)"
mkdir -p "$QA_BUILD_ROOT/module-cache" "$QA_APP_BUNDLE/Contents/MacOS"
xcrun swiftc -swift-version 6 -parse-as-library -target "$QA_ARCH-apple-macosx14.0" \
    -module-name CodexUsageQA -module-cache-path "$QA_BUILD_ROOT/module-cache" \
    -file-prefix-map "$PROJECT_ROOT=." -debug-prefix-map "$PROJECT_ROOT=." \
    -file-prefix-map "$QA_BUILD_ROOT=.build" -debug-prefix-map "$QA_BUILD_ROOT=.build" \
    -file-compilation-dir . \
    "$PROJECT_ROOT"/Sources/CodexUsage/Models/*.swift \
    "$PROJECT_ROOT"/Sources/CodexUsage/Services/*.swift \
    "$PROJECT_ROOT"/Sources/CodexUsage/Stores/*.swift \
    "$PROJECT_ROOT"/Sources/CodexUsage/Views/*.swift \
    "$PROJECT_ROOT/script/ui_fixture.swift" -o "$QA_EXECUTABLE"
/usr/bin/strip -S "$QA_EXECUTABLE"
/usr/bin/strings "$QA_EXECUTABLE" > "$QA_BUILD_ROOT/qa-binary-strings.txt"
if /usr/bin/grep -Eq '/Users/|/home/' "$QA_BUILD_ROOT/qa-binary-strings.txt"; then
    printf 'QA build privacy check failed: a personal path remains in the binary.\n' >&2
    exit 1
fi
cat > "$QA_APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CodexUsageQA</string>
<key>CFBundleIdentifier</key><string>local.codexusage.acceptance</string>
<key>CFBundleName</key><string>CodexUsageQA</string>
<key>CFBundleDisplayName</key><string>Codex Usage QA</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
/usr/bin/plutil -lint "$QA_APP_BUNDLE/Contents/Info.plist"
/usr/bin/xattr -d com.apple.FinderInfo "$QA_APP_BUNDLE" 2>/dev/null || true
/usr/bin/codesign --force --sign - "$QA_APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict "$QA_APP_BUNDLE"
printf 'Built synthetic QA app: %s\n' "$QA_APP_BUNDLE"
if [[ "$MODE" == "--launch" ]]; then
    /usr/bin/open "$QA_APP_BUNDLE"
else
    printf 'Not launched. Computer-tool interaction remains unverified.\n'
fi
