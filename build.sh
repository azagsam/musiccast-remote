#!/bin/sh
# Builds "build/Yamaha Remote.app" using only the Swift command-line tools.
set -e
cd "$(dirname "$0")"

swift build -c release

APP="build/Yamaha Remote.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/YamahaRemote" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
cp Icon/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"

echo "Built $APP"
