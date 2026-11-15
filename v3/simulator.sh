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
for screen in settings import import-file import-keyboard sources home; do
  xcrun simctl terminate "$UDID" dev.webox.app.ios || true
  xcrun simctl launch "$UDID" dev.webox.app.ios --"$screen"
  sleep 4
  xcrun simctl io "$UDID" screenshot "evidence/$screen.png"
done
xcrun simctl terminate "$UDID" dev.webox.app.ios || true
mkdir -p /tmp/webox-fixtures
printf '{"value":"probe"}' > /tmp/webox-fixtures/probe.json
printf '{"value":"a"}' > /tmp/webox-fixtures/a.json
printf '{"value":"b"}' > /tmp/webox-fixtures/b.json
python3 -m http.server 8877 --directory /tmp/webox-fixtures > evidence/http.log 2>&1 &
xcrun simctl launch "$UDID" dev.webox.app.ios --self-test
sleep 18
DATA=$(xcrun simctl get_app_container "$UDID" dev.webox.app.ios data)
cp "$DATA/Documents/selftest.json" evidence/selftest.json
python3 - <<'PY'
import json
r=json.load(open('evidence/selftest.json'))
for k in ['loadList','search','loadResource']:
 assert isinstance(r.get(k),list) and len(r[k])>0,(k,r)
assert r['scalarJSON'] != 'nil',r
assert r.get('fileImportAdded') == 1,r
assert r.get('importedList'),r
assert r.get('libraryReloadCount') == 3,r
assert r.get('networkProbe',[{}])[0].get('status') == 200,r
assert len(r.get('concurrentProbe',[])) == 2,r
assert all(x['status'] == 200 for x in r['concurrentProbe']),r
assert r.get('capabilityMetadataImportAdded') == 1,r
assert r.get('capabilityMetadataImportErrors') == [],r
assert any('fixture-specific-error' in x for x in r.get('invalidScriptErrors',[])),r
assert r.get('pickerCallbackSaved') == True,r
assert r.get('keyboardFocus') == True,r
assert r.get('keyboardDismissed') == True,r
print('PASS: demo calls, scalar JSON, file import, persistence, HTTP, concurrent requests, metadata validation, picker callback')
PY
