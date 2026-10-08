#!/bin/bash
# visual-verifier용 Android 기기 확보·정리.
#
# Usage:
#   android-device.sh adb              → adb 경로 출력
#       찾는 순서: PATH → $ANDROID_HOME → $ANDROID_SDK_ROOT → ~/Library/Android/sdk → ~/Android/Sdk
#   android-device.sh ensure [avd]     → 쓸 기기 serial 출력 (연결된 기기 중 state=device인 첫 번째)
#       없으면 AVD를 헤드리스로 부팅한다: 인자 → 프로필 `화면 확인.avd` → `emulator -list-avds` 첫 번째.
#       부팅했으면 stderr에 `BOOTED {serial}` — 호출자는 끝날 때 cleanup으로 정리한다.
#       부팅 대기 시간: $ANDROID_DEVICE_BOOT_TIMEOUT초 (기본 180)
#   android-device.sh cleanup <serial> → ensure가 부팅한 에뮬레이터 종료 (emulator-* 만 — 실기기는 건드리지 않는다)
#
# 종료 코드: 0 성공 / 3 adb(SDK) 없음 / 4 연결 기기도 쓸 AVD도 없음 / 5 부팅 시간 초과 / 1 사용법 오류

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

find_adb() {
  if command -v adb > /dev/null 2>&1; then command -v adb; return 0; fi
  local d
  for d in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
    [ -n "$d" ] && [ -x "$d/platform-tools/adb" ] && { echo "$d/platform-tools/adb"; return 0; }
  done
  return 1
}

ADB="$(find_adb)" || { echo "adb를 찾지 못했습니다 — Android SDK 경로(ANDROID_HOME)를 확인해주세요" >&2; exit 3; }
SDK="$(cd "$(dirname "$ADB")/.." && pwd)"
EMULATOR="$SDK/emulator/emulator"

first_device() { "$ADB" devices | awk 'NR>1 && $2=="device" {print $1; exit}'; }

case "${1:-}" in
  adb)
    echo "$ADB"
    ;;

  ensure)
    SERIAL="$(first_device)"
    if [ -n "$SERIAL" ]; then echo "$SERIAL"; exit 0; fi

    [ -x "$EMULATOR" ] || { echo "연결된 기기가 없고 emulator도 없습니다 ($EMULATOR)" >&2; exit 4; }
    AVDS="$("$EMULATOR" -list-avds 2>/dev/null)"
    AVD="${2:-}"
    if [ -z "$AVD" ]; then
      AVD="$("$HERE/impl-profile.sh" get "화면 확인.avd" 2>/dev/null || true)"
    fi
    if [ -n "$AVD" ]; then
      grep -qx -- "$AVD" <<< "$AVDS" || { echo "AVD $AVD 가 없습니다 (있는 AVD: $(echo $AVDS))" >&2; exit 4; }
    else
      AVD="$(head -1 <<< "$AVDS")"
    fi
    [ -n "$AVD" ] || { echo "연결된 기기도, 부팅할 AVD도 없습니다" >&2; exit 4; }

    nohup "$EMULATOR" -avd "$AVD" -no-window -no-audio -no-boot-anim -no-snapshot-save > /dev/null 2>&1 &
    TIMEOUT="${ANDROID_DEVICE_BOOT_TIMEOUT:-180}"
    for _ in $(seq 1 "$TIMEOUT"); do
      SERIAL="$("$ADB" devices | awk 'NR>1 && $1 ~ /^emulator-/ && $2=="device" {print $1; exit}')"
      if [ -n "$SERIAL" ] && [ "$("$ADB" -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; then
        echo "BOOTED $SERIAL" >&2
        echo "$SERIAL"
        exit 0
      fi
      sleep 1
    done
    echo "AVD $AVD 부팅 시간 초과 (${TIMEOUT}초)" >&2
    exit 5
    ;;

  cleanup)
    SERIAL="${2:?usage: android-device.sh cleanup <serial>}"
    case "$SERIAL" in
      emulator-*) "$ADB" -s "$SERIAL" emu kill > /dev/null 2>&1 || true ;;
      *) echo "에뮬레이터가 아닌 기기($SERIAL)는 종료하지 않습니다" >&2 ;;
    esac
    ;;

  *)
    echo "usage: android-device.sh adb | ensure [avd] | cleanup <serial>" >&2
    exit 1
    ;;
esac
