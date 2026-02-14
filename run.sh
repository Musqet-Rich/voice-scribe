#!/bin/bash
# Build and run VoiceScribe as a proper .app bundle
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "Building..."
swift build -c release 2>&1

APP_DIR=".build/VoiceScribe.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"

# Create .app bundle structure
rm -rf "$APP_DIR"
mkdir -p "$MACOS"
cp .build/release/VoiceScribe "$MACOS/VoiceScribe"
cp Info.plist "$CONTENTS/Info.plist"

if [ -f VoiceScribe.entitlements ]; then
    codesign --force --sign - --entitlements VoiceScribe.entitlements "$MACOS/VoiceScribe" 2>/dev/null || true
fi

echo "Launching VoiceScribe.app..."
open "$APP_DIR"
