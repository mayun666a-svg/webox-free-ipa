#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
mkdir -p Payload/WeBox.app/runtime Payload/WeBox.app/modules Payload/WeBox.app/assets
cp ../runtime/*.js Payload/WeBox.app/runtime/
cp ../modules/*.js Payload/WeBox.app/modules/
cp assets/*.png Payload/WeBox.app/assets/
cp ../Info.plist Payload/WeBox.app/Info.plist
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 85' Payload/WeBox.app/Info.plist
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName WeBox' Payload/WeBox.app/Info.plist
xcrun --sdk iphoneos swiftc -target arm64-apple-ios17.0 -sdk "$SDK" -swift-version 5 -O *.swift -o Payload/WeBox.app/WeBox
codesign --force --sign - Payload/WeBox.app
zip -qry WeBox-v3.ipa Payload
