#!/bin/bash
set -euo pipefail
MODE="${1:-run}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="CodexUsage"
APP_BUNDLE="$PROJECT_ROOT/dist/Codex Usage.app"
TASK_BUILD_ROOT="${CODEX_USAGE_BUILD_ROOT:-$PROJECT_ROOT/.build/local}"
TASK_CONFIGURATION="${CODEX_USAGE_CONFIGURATION:-debug}"
cd "$PROJECT_ROOT"
if [[ "$MODE" != "--build-only" ]]; then
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi
mkdir -p "$TASK_BUILD_ROOT/module-cache"
export CLANG_MODULE_CACHE_PATH="$TASK_BUILD_ROOT/module-cache"
swift build --configuration "$TASK_CONFIGURATION" --scratch-path "$TASK_BUILD_ROOT/swift" --disable-sandbox
BUILD_BIN="$(swift build --configuration "$TASK_CONFIGURATION" --scratch-path "$TASK_BUILD_ROOT/swift" --show-bin-path --disable-sandbox)/$APP_NAME"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_BIN" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
"$PROJECT_ROOT/script/generate_icon.sh" "$TASK_BUILD_ROOT/icons"
cp "$TASK_BUILD_ROOT/icons/CodexUsage.icns" "$APP_BUNDLE/Contents/Resources/CodexUsage.icns"
cp "$PROJECT_ROOT/Assets/CodexStatusIcon.png" "$APP_BUNDLE/Contents/Resources/CodexStatusIcon.png"
cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CodexUsage</string>
<key>CFBundleIdentifier</key><string>local.codexusage.menubar</string>
<key>CFBundleName</key><string>Codex Usage</string>
<key>CFBundleDisplayName</key><string>Codex 用量</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>CodexUsage.icns</string>
<key>CFBundleShortVersionString</key><string>1.5.0</string>
<key>CFBundleVersion</key><string>8</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# File Provider can add FinderInfo just after a bundle is updated in Documents.
# Retry this specific generated-bundle cleanup; never remove quarantine metadata.
SIGNED=0
for attempt in 1 2 3; do
    /usr/bin/xattr -d com.apple.FinderInfo "$APP_BUNDLE" 2>/dev/null || true
    if /usr/bin/codesign --force --sign - "$APP_BUNDLE" && /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"; then
        SIGNED=1
        break
    fi
    sleep 0.3
done
[[ "$SIGNED" == 1 ]] || exit 1
case "$MODE" in
    --build-only) ;;
    run) /usr/bin/open -n "$APP_BUNDLE" ;;
    --verify) /usr/bin/open -n "$APP_BUNDLE"; sleep 1; pgrep -x "$APP_NAME" >/dev/null ;;
    --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
    --logs) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'process == "CodexUsage"' ;;
    --telemetry) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'subsystem == "local.codexusage.menubar"' ;;
    *) printf 'Usage: %s [run|--build-only|--verify|--debug|--logs|--telemetry]\n' "$0" >&2; exit 2 ;;
esac
