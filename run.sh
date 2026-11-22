#!/bin/bash
# Build VoiceScribe, install it to ~/Applications/Voice Scribe.app and launch it
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "Building..."
swift build -c release

APP_DIR="$HOME/Applications/Voice Scribe.app"
CONTENTS="$APP_DIR/Contents"

pkill -x VoiceScribe 2>/dev/null || true

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp .build/release/VoiceScribe "$CONTENTS/MacOS/VoiceScribe"
cp Info.plist "$CONTENTS/Info.plist"

# SwiftPM resource bundles (FluidAudio) must sit next to the executable
for bundle in .build/release/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$CONTENTS/Resources/"
done

if [ -d "VoiceScribe.iconset" ]; then
    iconutil -c icns -o "$CONTENTS/Resources/AppIcon.icns" VoiceScribe.iconset 2>/dev/null || true
fi

# Sign with a stable local identity if present, so macOS keeps the Accessibility
# permission across rebuilds. Falls back to ad-hoc (permission must be re-granted each build).
IDENTITY="Voice Scribe Local Signing"
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    codesign --force --deep --sign "$IDENTITY" --entitlements VoiceScribe.entitlements "$APP_DIR"
else
    echo "warning: '$IDENTITY' not found or not trusted; using ad-hoc signing"
    codesign --force --deep --sign - --entitlements VoiceScribe.entitlements "$APP_DIR"
fi

echo "Launching $APP_DIR"
open "$APP_DIR"
