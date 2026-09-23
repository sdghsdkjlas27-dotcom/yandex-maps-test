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

echo "=== open menu (drawer) via UIAutomator ==="
dump_ui || true
if MODE=menu python3 scripts/find_login.py window.xml > menu_center.txt 2>> find_menu.log; then
  read -r MX MY < menu_center.txt
  echo "menu button at ($MX,$MY), tapping"
  adb shell input tap "$MX" "$MY"
  sleep 3
else
  echo "::warning::menu button not found in dump"
fi
dump_ui || true
cp window.xml ui_drawer.xml 2>/dev/null
adb exec-out screencap -p > drawer.png

echo "=== find and tap login element (adaptive, verified) ==="
# screen size for fraction-based fallback inside the custom drawer
WM_SIZE=$(adb shell wm size 2>/dev/null | grep -oP '\d+x\d+' | tail -1)
SW=${WM_SIZE%x*}; SH=${WM_SIZE#*x}
echo "screen: ${SW}x${SH}"
MAIN_FOCUS=$(foreground_focus)
echo "main focus: $MAIN_FOCUS"

dump_text_sig() {
  python3 - "$1" <<'EOF'
import sys, re
try:
    t = open(sys.argv[1], encoding="utf-8", errors="replace").read()
except OSError:
    t = ""
texts = sorted(re.findall(r'(?:text|content-desc)="([^"]{2,})"', t))
print("|".join(texts)[:4000])
EOF
}

login_screen_shown() {
  FOCUS=$(foreground_focus)
  dump_ui || true
  if python3 scripts/is_auth_screen.py window.xml "$FOCUS" > auth_screen_check.txt 2>&1; then
    return 0
  fi
  return 1
}

LOGIN_TAPPED=no
# attempt 1: direct login element in current dump
if MODE=login python3 scripts/find_login.py window.xml > login_center.txt 2>> find_login.log; then
  read -r CX CY < login_center.txt
  echo "login element visible at ($CX,$CY), tapping"
  adb shell input tap "$CX" "$CY"
  LOGIN_TAPPED=uiautomator
  sleep 5
  login_screen_shown && LOGIN_SCREEN=yes || LOGIN_SCREEN=no
  echo "after tap: auth screen=$LOGIN_SCREEN"
fi

# fallback: candidate points inside the custom-drawn drawer, verified per tap
if [ "${LOGIN_SCREEN:-no}" != "yes" ] && [ "$LOGIN_TAPPED" != "uiautomator-confirmed" ]; then
  echo "=== drawer contents invisible to uiautomator, trying verified coordinate candidates ==="
  rm -f .auth_screen_seen
  for FRAC in "0.42 0.16" "0.30 0.14" "0.50 0.20" "0.35 0.21" "0.45 0.25" "0.30 0.28"; do
    FX=${FRAC% *}; FY=${FRAC#* }
    PX=$(python3 -c "print(int($SW*$FX))")
    PY=$(python3 -c "print(int($SH*$FY))")
    echo "--- candidate ($FX,$FY) -> px ($PX,$PY) ---"
    # make sure the drawer is open: toggle menu if its button is visible
    if dump_ui && MODE=menu python3 scripts/find_login.py window.xml > menu_center.txt 2>> find_menu.log; then
      read -r MX MY < menu_center.txt
      adb shell input tap "$MX" "$MY"
      sleep 3
    fi
    adb shell input tap "$PX" "$PY"
    sleep 4
    if login_screen_shown; then
      echo "auth screen appeared after candidate ($FX,$FY)"
      LOGIN_TAPPED="coords($FX,$FY)"
      break
    fi
    adb exec-out screencap -p > "drawer_try_${FX}_${FY}.png"
  done
fi
echo "LOGIN_TAPPED=$LOGIN_TAPPED"

sleep 3
dump_ui || true
cp window.xml ui_after_login_tap.xml 2>/dev/null
adb exec-out screencap -p > login_screen.png

echo "=== look for QR option ==="
QR_TAPPED=no
if [ -f .auth_screen_seen ]; then
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
else
  echo "::warning::auth screen never appeared, skipping QR search"
fi
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
if [ ! -f .auth_screen_seen ]; then
  echo "::warning::auth screen was never shown, skipping auth polling (status=login_failed)"
  STATUS=login_failed
fi
if [ "$STATUS" != "login_failed" ]; then
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
fi
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
seen = os.path.exists(".auth_screen_seen")
res = {
    "authenticated": status == "authenticated",
    "auth_screen_shown": seen,
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
# use actual disk usage (qcow2 files are sparse; apparent size is misleading)
AVD_DISK_MB=0
if [ -d "$AVD_DIR" ]; then
  AVD_DISK_MB=$(du -sm "$AVD_DIR" | cut -f1)
  echo "AVD disk usage: ${AVD_DISK_MB} MB"
fi
FULLAVD=no
if [ -d "$AVD_DIR" ] && [ "$AVD_DISK_MB" -gt 0 ] && [ "$AVD_DISK_MB" -lt 3500 ]; then
  echo "archiving AVD (${AVD_DISK_MB} MB on disk, sparse-aware)..."
  tar -S -cf - -C "$(dirname "$AVD_DIR")" "$(basename "$AVD_DIR")" 2>/dev/null | gzip -1 > android-state.tar.gz
  du -sh android-state.tar.gz
  [ -s android-state.tar.gz ] && FULLAVD=yes
else
  echo "AVD too large or missing, skipping full archive"
fi

cat > state-info.txt <<EOF
AVD path: $AVD_DIR
AVD size (apparent): $AVD_SIZE_BYTES bytes
AVD size (disk): ${AVD_DISK_MB} MB
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
