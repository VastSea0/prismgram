#!/bin/zsh
# Builds a release binary and assembles a locally runnable, ad-hoc signed Prismgram.app (and Instagram.app symlink for convenience).
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release

if [ ! -f "Assets/AppIcon.icns" ]; then
    mkdir -p Assets /tmp/AppIcon.iconset
    swift scripts/generate-icon.swift /tmp/AppIcon.iconset/icon_512x512@2x.png
    for s in 16 32 128 256 512; do
        sips -z $s $s /tmp/AppIcon.iconset/icon_512x512@2x.png --out /tmp/AppIcon.iconset/icon_${s}x${s}.png >/dev/null
        d=$((s*2))
        if [ $s -lt 512 ]; then
            sips -z $d $d /tmp/AppIcon.iconset/icon_512x512@2x.png --out /tmp/AppIcon.iconset/icon_${s}x${s}@2x.png >/dev/null
        fi
    done
    iconutil -c icns /tmp/AppIcon.iconset -o Assets/AppIcon.icns
    rm -rf /tmp/AppIcon.iconset
fi

for APP in "Prismgram.app" "Instagram.app"; do
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cp .build/release/InstagramMac "$APP/Contents/MacOS/InstagramMac"
    cp Info.plist "$APP/Contents/Info.plist"
    cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
    codesign --force --deep --sign - --entitlements InstagramMac.entitlements "$APP"
done

echo "Built Prismgram.app"
