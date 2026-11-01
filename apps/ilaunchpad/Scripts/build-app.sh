#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
BUILD_DIR="$PROJECT_DIR/.build"
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/iLaunchPad.app"
RUNTIME_ICON_WORK="$BUILD_DIR/AppIcons.runtime"

cd "$PROJECT_DIR"
swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

if [[ -d "$APP_DIR" ]]; then
    rm -rf "$APP_DIR"
fi
rm -rf "$RUNTIME_ICON_WORK"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/iLaunchPad" "$APP_DIR/Contents/MacOS/iLaunchPad"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

swift "$PROJECT_DIR/Tools/prepare_app_icons.swift" "$PROJECT_DIR/Resources/AppIconSources" "$PROJECT_DIR/Resources/AppIcons"
mkdir -p "$RUNTIME_ICON_WORK"
for icon in "$PROJECT_DIR"/Resources/AppIcons/*.png; do
    sips -z 512 512 "$icon" --out "$RUNTIME_ICON_WORK/${icon:t}" >/dev/null
done
cp -R "$RUNTIME_ICON_WORK" "$APP_DIR/Contents/Resources/AppIcons"
ACTOOL="$(xcrun --find actool 2>/dev/null || true)"
if [[ -z "$ACTOOL" && -x /Applications/Xcode.app/Contents/Developer/usr/bin/actool ]]; then
    ACTOOL=/Applications/Xcode.app/Contents/Developer/usr/bin/actool
fi
if [[ -z "$ACTOOL" ]]; then
    echo "error: actool is required to build the native macOS app icon" >&2
    exit 1
fi
"$ACTOOL" "$PROJECT_DIR/Resources/AppIcon.icon" \
    --compile "$APP_DIR/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 26.0 \
    --product-type com.apple.product-type.application \
    --app-icon AppIcon \
    --output-partial-info-plist "$BUILD_DIR/AppIcon-Info.plist" \
    >/dev/null

codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
