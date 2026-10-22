#!/bin/zsh
# Builds a release binary and assembles a locally runnable, ad-hoc signed Instagram.app.
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release

APP="Instagram.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/InstagramMac "$APP/Contents/MacOS/InstagramMac"
cp Info.plist "$APP/Contents/Info.plist"

codesign --force --deep --sign - --entitlements InstagramMac.entitlements "$APP"
echo "Built $APP"
