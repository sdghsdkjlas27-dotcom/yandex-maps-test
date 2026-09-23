#!/usr/bin/env bash
# Full scenario: launch Yandex Maps, set GPS, search for QUERY, extract results.
# Runs on the emulator runner host; ADB is already connected by the action.
set +e

QUERY="${QUERY:-АЗС}"
LAT="${LAT:-55.079}"
LON="${LON:-38.778}"

dump_ui() {
  for i in 1 2 3 4; do
    adb shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1
    adb pull /sdcard/window.xml . >/dev/null 2>&1
    if [ -s window.xml ]; then return 0; fi
    sleep 3
  done
  return 1
}

echo "### params: query=$QUERY lat=$LAT lon=$LON"

echo "=== adb devices ==="
adb devices

echo "=== enable location, set GPS before app start ==="
adb shell settings put secure location_mode 3 2>/dev/null
adb emu geo fix "$LON" "$LAT"
sleep 3

echo "=== install ADBKeyboard (for Cyrillic input) ==="
adb install -r ADBKeyboard.apk
adb shell ime enable com.android.adbkeyboard/.AdbIME

echo "=== launch ru.yandex.yandexmaps ==="
adb shell monkey -p ru.yandex.yandexmaps 1
echo "=== waiting 45s for app to load ==="
sleep 45

echo "=== diagnostics: packages / activities ==="
adb shell pm list packages | grep yandex || true
adb shell dumpsys activity activities | grep -i yandex || true

adb exec-out screencap -p > 01_maps_started.png
dump_ui && cp window.xml ui_map.xml || true

echo "=== set GPS again while app is running + verify ==="
adb emu geo fix "$LON" "$LAT"
sleep 10
adb shell dumpsys location > dumpsys_location.txt 2>&1
LAT_HITS=$(grep -c "$LAT" dumpsys_location.txt)
LON_HITS=$(grep -c "$LON" dumpsys_location.txt)
echo "location verification: lat hits=$LAT_HITS lon hits=$LON_HITS"
if [ "${LAT_HITS:-0}" -gt 0 ] && [ "${LON_HITS:-0}" -gt 0 ]; then
  GPS_VERIFIED=true
else
  GPS_VERIFIED=false
fi
echo "GPS_VERIFIED=$GPS_VERIFIED"
adb exec-out screencap -p > 02_location_set.png

echo "=== step A/B: find and tap search field ==="
SEARCH_METHOD=uiautomator
if dump_ui && python3 scripts/find_search.py window.xml > center.txt 2> find_search.log; then
  cat find_search.log 2>/dev/null || true
  read -r CX CY < center.txt
  echo "tapping search field at ($CX,$CY)"
  adb shell input tap "$CX" "$CY"
  sleep 4
else
  echo "search field not found via uiautomator, will use deep link fallback"
  SEARCH_METHOD=deeplink
fi
adb exec-out screencap -p > 03_search_opened.png

echo "=== step C/D: type query and submit ==="
if [ "$SEARCH_METHOD" = "uiautomator" ]; then
  adb shell ime set com.android.adbkeyboard/.AdbIME
  sleep 1
  B64=$(printf '%s' "$QUERY" | base64 -w0)
  adb shell am broadcast -a ADB_INPUT_B64 --es msg "$B64"
  sleep 3
  dump_ui || true
  if grep -q "$QUERY" window.xml 2>/dev/null; then
    echo "query text confirmed in UI"
    adb shell input keyevent 66
  else
    echo "query NOT visible after typing, falling back to deep link"
    SEARCH_METHOD=deeplink
  fi
fi

if [ "$SEARCH_METHOD" = "deeplink" ]; then
  ENC=$(QUERY="$QUERY" python3 -c "import urllib.parse,os;print(urllib.parse.quote(os.environ['QUERY']))")
  adb shell am start -a android.intent.action.VIEW -d "yandexmaps://maps.yandex.ru/?text=$ENC"
fi

echo "=== step E: waiting for results ==="
sleep 15
dump_ui || true
adb exec-out screencap -p > 04_search_results.png

echo "=== step F: extract results ==="
SEARCH_METHOD="$SEARCH_METHOD" GPS_VERIFIED="$GPS_VERIFIED" \
  python3 scripts/extract.py window.xml result.json
cat result.json || true

echo "=== final artifacts ==="
cp 04_search_results.png screenshot.png
adb logcat -d > logcat.txt
ls -la screenshot.png result.json window.xml logcat.txt
exit 0
