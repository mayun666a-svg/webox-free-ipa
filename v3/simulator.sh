#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p evidence
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
ARCH=$(uname -m)
mkdir -p Sim/WeBox.app
cp -R Payload/WeBox.app/. Sim/WeBox.app/
rm -rf Sim/WeBox.app/_CodeSignature
xcrun --sdk iphonesimulator swiftc -target "$ARCH-apple-ios17.0-simulator" -sdk "$SDK" -swift-version 5 -Onone *.swift -o Sim/WeBox.app/WeBox
codesign --force --sign - Sim/WeBox.app
xcrun simctl list devices available -j > evidence/devices.json
UDID=$(python3 -c "import json;d=json.load(open('evidence/devices.json'));print(next(x['udid'] for v in d['devices'].values() for x in v if 'iPhone' in x['name']))")
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time 18:43 --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 91
xcrun simctl install "$UDID" Sim/WeBox.app
for screen in settings import sources; do
  xcrun simctl terminate "$UDID" dev.webox.app.ios || true
  xcrun simctl launch "$UDID" dev.webox.app.ios --"$screen"
  sleep 4
  xcrun simctl io "$UDID" screenshot "evidence/$screen.png"
done
xcrun simctl terminate "$UDID" dev.webox.app.ios || true
xcrun simctl launch "$UDID" dev.webox.app.ios --self-test
sleep 10
DATA=$(xcrun simctl get_app_container "$UDID" dev.webox.app.ios data)
cp "$DATA/Documents/selftest.json" evidence/selftest.json
python3 - <<'PY'
import json
r=json.load(open('evidence/selftest.json'))
for k in ['loadList','search','loadResource']:
 assert isinstance(r.get(k),list) and len(r[k])>0,(k,r)
assert r['scalarJSON'] != 'nil',r
print('Runtime demo calls and scalar JSON passed')
PY
