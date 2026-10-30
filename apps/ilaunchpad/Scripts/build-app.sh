#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
BUILD_DIR="$PROJECT_DIR/.build"
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/iLaunchPad.app"
ICON_WORK="$BUILD_DIR/AppIcon.iconset"

cd "$PROJECT_DIR"
swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

if [[ -d "$APP_DIR" ]]; then
    rm -rf "$APP_DIR"
fi
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$ICON_WORK"
cp "$BIN_DIR/iLaunchPad" "$APP_DIR/Contents/MacOS/iLaunchPad"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

ICON_MASTER="$BUILD_DIR/AppIcon-1024.png"
swift "$PROJECT_DIR/Tools/prepare_app_icons.swift" "$PROJECT_DIR/Resources/AppIconSources" "$PROJECT_DIR/Resources/AppIcons"
cp "$PROJECT_DIR/Resources/AppIcons/ocean.png" "$ICON_MASTER"
cp -R "$PROJECT_DIR/Resources/AppIcons" "$APP_DIR/Contents/Resources/AppIcons"
for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" "512 512x512" "1024 512x512@2x"; do
    set -- ${=spec}
    sips -z "$1" "$1" "$ICON_MASTER" --out "$ICON_WORK/icon_$2.png" >/dev/null
done
iconutil -c icns "$ICON_WORK" -o "$APP_DIR/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
