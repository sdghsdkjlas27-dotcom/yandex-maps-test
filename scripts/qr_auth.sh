#!/usr/bin/env bash
# QR auth experiment: install Yandex Maps, open login, capture QR, keep runner
# alive while the user scans it manually with a phone, detect authentication,
# then research what state can be saved (app data / AVD / snapshot).
set +e

SCAN_WAIT_MIN="${SCAN_WAIT:-15}"

dump_ui() {
  for i in 1 2 3 4 5; do
    adb shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1
    adb pull /sdcard/window.xml . >/dev/null 2>&1
    [ -s window.xml ] && return 0
    sleep 3
  done
  return 1
}

foreground_focus() {
  adb shell dumpsys window 2>/dev/null | grep -i mCurrentFocus | head -1
}

echo "=== install Yandex Maps ==="
adb install -r -g YandexMaps.apk
adb shell pm list packages | grep ru.yandex.yandexmaps || echo "::error::maps not installed"
adb shell pm grant ru.yandex.yandexmaps android.permission.ACCESS_FINE_LOCATION 2>/dev/null
adb shell pm grant ru.yandex.yandexmaps android.permission.ACCESS_COARSE_LOCATION 2>/dev/null

echo "=== launch maps ==="
adb shell monkey -p ru.yandex.yandexmaps 1
sleep 45
adb exec-out screencap -p > 01_maps_started.png

echo "=== find and tap login element ==="
LOGIN_TAPPED=no
for attempt in 1 2 3 4 5; do
  dump_ui || true
  cp window.xml "ui_attempt_${attempt}.xml" 2>/dev/null
  if MODE=login python3 scripts/find_login.py window.xml > login_center.txt 2>> find_login.log; then
    read -r CX CY < login_center.txt
    echo "login element found at ($CX,$CY), attempt $attempt"
    adb shell input tap "$CX" "$CY"
    LOGIN_TAPPED=yes
    break
  fi
  echo "login not found, trying to open menu (attempt $attempt)"
  if MODE=menu python3 scripts/find_login.py window.xml > menu_center.txt 2>> find_login.log; then
    read -r MX MY < menu_center.txt
    adb shell input tap "$MX" "$MY"
    sleep 4
  fi
  sleep 5
done
echo "LOGIN_TAPPED=$LOGIN_TAPPED"

sleep 8
dump_ui || true
cp window.xml ui_after_login_tap.xml 2>/dev/null
adb exec-out screencap -p > login_screen.png

echo "=== look for QR option ==="
QR_TAPPED=no
for attempt in 1 2 3; do
  dump_ui || true
  if python3 scripts/find_qr.py window.xml > qr_center.txt 2>> find_qr.log; then
    read -r QX QY < qr_center.txt
    echo "QR element found at ($QX,$QY), tapping (attempt $attempt)"
    adb shell input tap "$QX" "$QY"
    QR_TAPPED=yes
    sleep 6
    dump_ui || true
    break
  fi
  sleep 4
done
echo "QR_TAPPED=$QR_TAPPED"
cp window.xml qr_window.xml 2>/dev/null
adb exec-out screencap -p > qr_screen.png
ls -la qr_screen.png qr_window.xml login_screen.png

echo "=== publish QR for immediate manual scan ==="
QR_URL="(not pushed)"
if [ -n "${GH_TOKEN:-}" ]; then
  git config user.email "actions@github.com" 2>/dev/null
  git config user.name "actions-bot" 2>/dev/null
  git add -f qr_screen.png login_screen.png qr_window.xml 2>/dev/null
  git commit -q -m "QR screen for manual scan [run ${GITHUB_RUN_ID}]" 2>/dev/null
  if git push -f "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" HEAD:refs/heads/qr-latest 2>/dev/null; then
    QR_URL="https://github.com/${GITHUB_REPOSITORY}/raw/refs/heads/qr-latest/qr_screen.png"
    echo "QR_PUSHED=yes"
  else
    echo "QR_PUSHED=no"
  fi
fi
echo "=============================================================="
echo "SCAN THE QR NOW: $QR_URL"
echo "=============================================================="

echo "=== polling for authentication (max ${SCAN_WAIT_MIN} min) ==="
MAX_WAIT=$(( SCAN_WAIT_MIN * 60 ))
START=$(date +%s)
STATUS=timeout
CONS=0
while :; do
  NOW=$(date +%s); EL=$((NOW - START))
  [ "$EL" -ge "$MAX_WAIT" ] && { echo "auth wait timeout after ${EL}s"; break; }
  sleep 10
  FOCUS=$(foreground_focus)
  dump_ui || true
  RES=$(FOCUS="$FOCUS" python3 scripts/auth_check.py window.xml 2>/dev/null || echo WAITING)
  echo "[poll ${EL}s] $RES"
  if echo "$RES" | grep -q AUTHENTICATED; then
    CONS=$((CONS + 1))
    if [ "$CONS" -ge 2 ]; then
      STATUS=authenticated
      cp window.xml authenticated.xml 2>/dev/null
      break
    fi
  else
    CONS=0
  fi
done
echo "AUTH_STATUS=$STATUS"

PROFILE=no
if [ "$STATUS" = "authenticated" ]; then
  adb exec-out screencap -p > authenticated.png
  if grep -qE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' authenticated.xml 2>/dev/null; then
    PROFILE=email
  elif grep -qiE 'профиль|profile' authenticated.xml 2>/dev/null; then
    PROFILE=yes
  fi
fi
echo "PROFILE=$PROFILE"

QUERY=""; LAT=""; LON=""
STATUS="$STATUS" PROFILE="$PROFILE" SCAN_WAIT="$SCAN_WAIT_MIN" QR_TAPPED="$QR_TAPPED" \
  python3 - <<'EOF'
import json, os, time
status = os.environ.get("STATUS", "timeout")
res = {
    "authenticated": status == "authenticated",
    "profile_detected": os.environ.get("PROFILE", "no") != "no",
    "profile_kind": os.environ.get("PROFILE", "no"),
    "status": status,
    "qr_tapped": os.environ.get("QR_TAPPED") == "yes",
    "package": "ru.yandex.yandexmaps",
    "scan_wait_minutes": int(os.environ.get("SCAN_WAIT", "15")),
    "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
}
json.dump(res, open("auth-result.json", "w", encoding="utf-8"), indent=2)
print(json.dumps(res))
EOF

echo "=== keep android running 30s to flush state ==="
sleep 30

echo "=== state research: adb root ==="
ROOT=no
adb root >/dev/null 2>&1
sleep 4
adb wait-for-device >/dev/null 2>&1
ROOT_ID=$(adb shell id 2>/dev/null | head -1)
echo "root id: $ROOT_ID" | tee root_check.txt
if echo "$ROOT_ID" | grep -q "uid=0"; then
  ROOT=yes
  echo "=== pulling app data ==="
  rm -rf appdata_pull
  timeout 120 adb pull /data/data/ru.yandex.yandexmaps appdata_pull > appdata_pull.log 2>&1
  if [ -d appdata_pull ] && [ -n "$(ls -A appdata_pull 2>/dev/null)" ]; then
    APPDATA=yes
    tar -czf app-data-yandexmaps.tar.gz appdata_pull 2>/dev/null
    du -sh app-data-yandexmaps.tar.gz
  else
    APPDATA=no
  fi
else
  APPDATA=no
fi

echo "=== state research: AVD location and size ==="
AVD_NAME=$(adb emu avd name 2>/dev/null | head -1 | tr -d '\r')
echo "AVD name: $AVD_NAME"
AVD_DIR="$HOME/.android/avd/${AVD_NAME}.avd"
if [ ! -d "$AVD_DIR" ]; then
  AVD_DIR=$(find "$HOME" -maxdepth 5 -type d -name "${AVD_NAME}.avd" 2>/dev/null | head -1)
fi
echo "AVD dir: $AVD_DIR"
AVD_SIZE_BYTES=0
if [ -d "$AVD_DIR" ]; then
  du -sh "$AVD_DIR" | tee avd_size.txt
  AVD_SIZE_BYTES=$(du -sb "$AVD_DIR" | cut -f1)
  echo "AVD bytes: $AVD_SIZE_BYTES"
fi

echo "=== state research: snapshot ==="
SNAP=no
timeout 420 adb emu avd snapshot save authenticated > snapshot_save.txt 2>&1
cat snapshot_save.txt
adb emu avd snapshot list > snapshot_list.txt 2>&1
cat snapshot_list.txt
grep -qi "OK" snapshot_save.txt && SNAP=yes

echo "=== archive full AVD state ==="
FULLAVD=no
if [ -d "$AVD_DIR" ] && [ "$AVD_SIZE_BYTES" -gt 0 ] && [ "$AVD_SIZE_BYTES" -lt 4500000000 ]; then
  echo "archiving AVD ($AVD_SIZE_BYTES bytes)..."
  tar -cf - -C "$(dirname "$AVD_DIR")" "$(basename "$AVD_DIR")" 2>/dev/null | gzip -1 > android-state.tar.gz
  du -sh android-state.tar.gz
  [ -s android-state.tar.gz ] && FULLAVD=yes
else
  echo "AVD too large or missing, skipping full archive"
fi

cat > state-info.txt <<EOF
AVD path: $AVD_DIR
AVD size: $AVD_SIZE_BYTES bytes
snapshot support: $SNAP (save output in snapshot_save.txt)
adb root support: $ROOT
app_data_available: $APPDATA
full_avd_available: $FULLAVD
package: ru.yandex.yandexmaps
auth status: $STATUS
EOF
cat state-info.txt

adb logcat -d > logcat.txt
echo "=== final files ==="
ls -la qr_screen.png qr_window.xml login_screen.png auth-result.json logcat.txt state-info.txt 2>/dev/null
ls -la authenticated.png authenticated.xml app-data-yandexmaps.tar.gz android-state.tar.gz 2>/dev/null
exit 0
