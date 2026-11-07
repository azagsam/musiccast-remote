#!/bin/sh
# Builds "build/Remote for MusicCast.app" using only the Swift command-line tools.
# The binary is universal: it runs on both Apple silicon and Intel Macs.
set -e
cd "$(dirname "$0")"

BINARIES=""
for ARCH in arm64 x86_64; do
    TRIPLE="$ARCH-apple-macosx13.0"
    swift build -c release --triple "$TRIPLE"
    BINARIES="$BINARIES $(swift build -c release --triple "$TRIPLE" --show-bin-path)/MusicCastRemote"
done

APP="build/Remote for MusicCast.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# shellcheck disable=SC2086
lipo -create $BINARIES -output "$APP/Contents/MacOS/MusicCastRemote"
cp Info.plist "$APP/Contents/"
cp Icon/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"

echo "Built $APP"
