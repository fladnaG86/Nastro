#!/bin/bash
# Builds Nastro.app in ./dist. Usage: ./build.sh [--install]
# Signs with the "Nastro Dev" certificate if present (see scripts/make-dev-cert.sh), else ad-hoc.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Nastro"
APP="dist/Nastro.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Nastro"
mkdir -p "$APP/Contents/Resources"
cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Nastro</string>
    <key>CFBundleIdentifier</key><string>it.nastro.app</string>
    <key>CFBundleExecutable</key><string>Nastro</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Nastro records your voice during calls. / Nastro registra la tua voce durante le call.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Nastro transcribes your recordings on this Mac. / Nastro trascrive le tue registrazioni su questo Mac.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Nastro records your screen and system audio during calls. / Nastro registra lo schermo e l'audio di sistema durante le call.</string>
</dict>
</plist>
PLIST

if security find-identity -p codesigning 2>/dev/null | grep -q "Nastro Dev"; then
    codesign --force --sign "Nastro Dev" "$APP"
    echo "Signed with Nastro Dev"
else
    codesign --force --sign - "$APP"
    echo "WARNING: 'Nastro Dev' certificate not found, signed ad-hoc."
    echo "         The Screen Recording permission must be granted again after every build."
    echo "         Run scripts/make-dev-cert.sh once to fix this."
fi
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Nastro 2>/dev/null || true
    rm -rf "/Applications/Nastro.app"
    cp -R "$APP" "/Applications/Nastro.app"
    echo "Installed /Applications/Nastro.app"
fi
