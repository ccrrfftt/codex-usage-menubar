#!/bin/bash
set -euo pipefail
MODE="${1:---build-only}"
case "$MODE" in
    --build-only|--launch|--self-test) ;;
    *) printf 'Usage: %s [--build-only|--launch|--self-test]\n' "$0" >&2; exit 2 ;;
esac
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QA_BUILD_ROOT="${CODEX_USAGE_BUILD_ROOT:-/private/tmp/codex-usage-acceptance}"
QA_STAGE="$QA_BUILD_ROOT/ui-fixture"
QA_APP_BUNDLE="$QA_STAGE/Codex Usage QA.app"
QA_EXECUTABLE="$QA_APP_BUNDLE/Contents/MacOS/CodexUsageQA"
QA_FIXTURE_SOURCE="$QA_BUILD_ROOT/ui_fixture.swift"
QA_ARCH="$(uname -m)"
mkdir -p "$QA_BUILD_ROOT/module-cache" "$QA_APP_BUNDLE/Contents/MacOS"
if [[ "$MODE" == "--self-test" ]]; then
    # Terminate only this fixture bundle before replacing its executable.
    xcrun swift -module-cache-path "$QA_BUILD_ROOT/module-cache" -e '
import AppKit
let applications = ["local.codexusage.acceptance", "local.codexusage.acceptance.app"].flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
for application in applications { application.terminate() }
let deadline = Date().addingTimeInterval(3)
while applications.contains(where: { !$0.isTerminated }) && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
if applications.contains(where: { !$0.isTerminated }) { exit(1) }
'
fi
cp "$PROJECT_ROOT/script/ui_fixture.swift" "$QA_FIXTURE_SOURCE"
xcrun swiftc -swift-version 6 -parse-as-library -target "$QA_ARCH-apple-macosx14.0" \
    -module-name CodexUsageQA -module-cache-path "$QA_BUILD_ROOT/module-cache" \
    -file-prefix-map "$PROJECT_ROOT=." -debug-prefix-map "$PROJECT_ROOT=." \
    -file-prefix-map "$QA_BUILD_ROOT=.build" -debug-prefix-map "$QA_BUILD_ROOT=.build" \
    -file-compilation-dir . \
    "$PROJECT_ROOT"/Sources/CodexUsage/Models/*.swift \
    "$PROJECT_ROOT"/Sources/CodexUsage/Services/*.swift \
    "$PROJECT_ROOT"/Sources/CodexUsage/Stores/*.swift \
    "$PROJECT_ROOT"/Sources/CodexUsage/Views/*.swift \
    "$QA_FIXTURE_SOURCE" -o "$QA_EXECUTABLE"
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
<key>CFBundleIdentifier</key><string>local.codexusage.acceptance.app</string>
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
if [[ "$MODE" == "--self-test" ]]; then
    QA_RESULT_ROOT="$QA_STAGE/self-test-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$QA_RESULT_ROOT"
    /usr/bin/open -n -W --stdout "$QA_RESULT_ROOT/stdout.log" --stderr "$QA_RESULT_ROOT/stderr.log" "$QA_APP_BUNDLE" --args --self-test "$QA_RESULT_ROOT"
    python3 - "$QA_RESULT_ROOT/result.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
counts = {status: sum(item['status'] == status for item in data['checks']) for status in ['pass', 'fail', 'limitation']}
print('Native self-test:', counts)
print('Evidence:', path.parent)
if counts['fail']:
    sys.exit(1)
PY
elif [[ "$MODE" == "--launch" ]]; then
    /usr/bin/open "$QA_APP_BUNDLE"
else
    printf 'Not launched. Native interaction remains unverified.\n'
fi
