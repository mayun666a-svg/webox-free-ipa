#!/usr/bin/env bash
# 在 macOS + Xcode runner 上把 WeBox Swift 宿主编成 arm64 iOS Mach-O，打包成可自签 .ipa
# 无 Apple 证书 → 用 ad-hoc 签名（codesign -s -），用户拿 Sideloadly/AltStore/爱思/TrollStore 重签装机
set -euo pipefail
cd "$(dirname "$0")"

echo "=== toolchain ==="
xcodebuild -version
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
echo "SDK=$SDK"

APP=WeBox.app
rm -rf "$APP" Payload WeBox.ipa
mkdir -p "$APP/runtime" "$APP/modules"
cp runtime/*.js "$APP/runtime/"
cp modules/*.js "$APP/modules/"
cp Info.plist "$APP/Info.plist"

echo "=== compile arm64 Mach-O ==="
# -swift-version 5 规避 Swift 6 对 JSContext 非 Sendable 的严格并发报错
xcrun --sdk iphoneos swiftc \
  -target arm64-apple-ios17.0 \
  -sdk "$SDK" \
  -swift-version 5 -O \
  -F "$SDK/System/Library/Frameworks" \
  WeBoxHost.swift main.swift \
  -o "$APP/WeBox"

file "$APP/WeBox"
echo "=== Mach-O check ==="
otool -hv "$APP/WeBox" | head -5 || true

echo "=== ad-hoc codesign (non-fatal; 用户端工具会重签) ==="
# ent.plist 只有 get-task-allow；Sideloadly/AltStore/TrollStore 装机时替换成自己的证书 + entitlements
cat > ent.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>get-task-allow</key><true/>
</dict></plist>
PLIST
codesign -f -s - --entitlements ent.plist "$APP" 2>&1 \
  || codesign -f -s - "$APP" 2>&1 \
  || echo "[warn] ad-hoc 签名跳过（用户端重签即可，不阻断产出）"
codesign -dv "$APP" 2>&1 | head -8 || true
rm -f ent.plist

echo "=== zip -> ipa ==="
mkdir -p Payload
mv "$APP" Payload/
zip -qry WeBox.ipa Payload
ls -la WeBox.ipa
unzip -l WeBox.ipa | head -20
echo "=== DONE ==="
