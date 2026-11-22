#!/usr/bin/env bash
# Creates (once) and boots a "low-end" Android emulator: 2 cores, 1.5 GB RAM,
# 720x1600 @ 280 dpi, Android 11 (API 30), arm64 google_apis image.
#
#   ./lowend_avd.sh            # create if missing, boot with the host GPU
#   ./lowend_avd.sh --kill     # shut it down
#
# READ BEFORE TRUSTING ITS NUMBERS (measured 2026-11-22, Apple Silicon):
# - The CPU is NOT slow: emulator cores run at host speed, so UI-thread
#   (build) times matched a flagship phone. Fewer cores and less RAM only
#   expose memory pressure and parallelism issues.
# - `-gpu swiftshader_indirect` (software GPU) is FAR slower than any real
#   phone (raster median 200 ms, menu 112 s to load): unusable for numbers.
# - Pinning qemu to efficiency cores (`taskpolicy -b`) froze the emulator
#   (adb offline). `cpulimit` is untested.
# => Use it for "does it run / does it degrade gracefully / memory", not
#    for frame budgets. Real budgets come from a real phone and the
#    flagship rule in SKILL.md (UI thread ~3-4x slower on budget phones).
set -euo pipefail

NAME=LowEnd_API30
IMAGE="system-images;android-30;google_apis;arm64-v8a"
SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
EMU=$SDK/emulator/emulator
AVDMANAGER=$(ls -d "$SDK"/cmdline-tools/*/bin 2>/dev/null | head -1)/avdmanager
CONFIG=$HOME/.android/avd/$NAME.avd/config.ini

if [[ "${1:-}" == "--kill" ]]; then
  for s in $(adb devices | awk '/^emulator-/{print $1}'); do
    [[ "$(adb -s "$s" emu avd name 2>/dev/null | head -1 | tr -d '\r')" == "$NAME" ]] && adb -s "$s" emu kill
  done
  exit 0
fi

if [[ ! -f "$CONFIG" ]]; then
  [[ -x "$AVDMANAGER" ]] || { echo "avdmanager not found under $SDK/cmdline-tools"; exit 1; }
  if [[ ! -d "$SDK/system-images/android-30/google_apis/arm64-v8a" ]]; then
    echo "missing image: $SDK/cmdline-tools/latest/bin/sdkmanager \"$IMAGE\""; exit 1
  fi
  echo no | "$AVDMANAGER" create avd -n "$NAME" -k "$IMAGE" -d pixel_3a --force >/dev/null
  for kv in hw.cpu.ncore=2 hw.ramSize=1536 vm.heapSize=192 hw.lcd.width=720 hw.lcd.height=1600 \
            hw.lcd.density=280 hw.gpu.enabled=yes hw.gpu.mode=host disk.dataPartition.size=6G hw.keyboard=yes; do
    k=${kv%%=*}
    grep -v "^$k=" "$CONFIG" > "$CONFIG.t" && mv "$CONFIG.t" "$CONFIG"
    echo "$kv" >> "$CONFIG"
  done
  echo "created $NAME"
fi

before=$(adb devices | awk '/^emulator-/{print $1}' | sort)
nohup "$EMU" -avd "$NAME" -gpu host -no-snapshot -no-audio -no-boot-anim -read-only \
  > "${TMPDIR:-/tmp}/$NAME.log" 2>&1 &
serial=""
for _ in $(seq 1 60); do
  sleep 3
  serial=$(comm -13 <(echo "$before") <(adb devices | awk '/^emulator-/{print $1}' | sort) | head -1)
  [[ -n "$serial" ]] || continue
  [[ "$(timeout 5 adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]] && break
done
[[ -n "$serial" ]] || { echo "emulator did not come up; log: ${TMPDIR:-/tmp}/$NAME.log"; exit 1; }
echo "booted $NAME as $serial"
