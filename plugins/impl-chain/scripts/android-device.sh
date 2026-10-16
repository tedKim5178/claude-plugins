#!/bin/bash
# 기기 어댑터 (Android) — visual-verifier가 쓰는 기기 확보·조작·정리. 프로필 `화면 확인.device_adapter`의 기본값 `builtin:android-device`.
# 계약: impl-chain references/impl-profile-spec.md "기기 어댑터". 다른 플랫폼은 같은 호출·출력의 스크립트를 레포에 두고 그 경로를 적는다.
#
# Usage:
#   android-device.sh check            → 기기 도구(adb)를 쓸 수 있으면 그 경로 출력 (`adb`도 같은 동작 — mock 스킬이 adb를 직접 부를 때 쓴다)
#       찾는 순서: PATH → $ANDROID_HOME → $ANDROID_SDK_ROOT → ~/Library/Android/sdk → ~/Android/Sdk
#   android-device.sh ensure [avd]     → 쓸 기기 serial 출력. 연결된 기기(state=device) 중 **실기기를 먼저**, 없으면 켜져 있는 에뮬레이터
#       둘 다 없으면 AVD를 헤드리스로 부팅한다: 인자 → 프로필 `화면 확인.avd` → `emulator -list-avds` 첫 번째.
#       부팅했으면 stderr에 `BOOTED {serial}` — 호출자는 끝날 때 cleanup으로 정리한다.
#       stderr에 `KIND real|virtual` 한 줄 — 고른 기기가 실기기인지 에뮬레이터인지
#       부팅 대기 시간: $ANDROID_DEVICE_BOOT_TIMEOUT초 (기본 180)
#   android-device.sh cleanup <serial> → ensure가 부팅한 에뮬레이터 종료 (emulator-* 만 — 실기기는 건드리지 않는다)
#   android-device.sh ui <serial>                      → 화면 요소 트리(uiautomator XML — text·bounds) 출력
#   android-device.sh tap <serial> <x> <y>             → 탭
#   android-device.sh swipe <serial> <x1> <y1> <x2> <y2> [ms]  → 스와이프·스크롤 (기본 300ms)
#   android-device.sh key <serial> back|home           → 시스템 키
#   android-device.sh screenshot <serial> <out.png>    → 스크린샷 저장
#
# 종료 코드: 0 성공 / 3 adb(SDK) 없음 / 4 연결 기기도 쓸 AVD도 없음 / 5 부팅 시간 초과 / 1 사용법 오류·조작 실패

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

# 에뮬레이터인지 — serial이 emulator-* 이거나 커널이 qemu (Genymotion 등 다른 이름의 가상 기기 포함)
is_virtual() {
  case "$1" in emulator-*) return 0 ;; esac
  [ "$("$ADB" -s "$1" shell getprop ro.kernel.qemu 2>/dev/null | tr -d '\r')" = 1 ]
}
# 연결된 기기 중 실기기를 먼저, 없으면 첫 가상 기기
first_device() {
  local s virt=""
  for s in $("$ADB" devices | awk 'NR>1 && $2=="device" {print $1}'); do
    if is_virtual "$s"; then [ -n "$virt" ] || virt=$s; else echo "$s"; return; fi
  done
  [ -z "$virt" ] || echo "$virt"
}
kind_of() { if is_virtual "$1"; then echo virtual; else echo real; fi; }

case "${1:-}" in
  check|adb)
    echo "$ADB"
    ;;

  ui)
    SERIAL="${2:?usage: android-device.sh ui <serial>}"
    "$ADB" -s "$SERIAL" shell uiautomator dump /sdcard/impl-chain-ui.xml > /dev/null 2>&1 \
      || { echo "화면 요소 트리를 읽지 못했습니다 (uiautomator dump 실패)" >&2; exit 1; }
    "$ADB" -s "$SERIAL" exec-out cat /sdcard/impl-chain-ui.xml
    ;;

  tap)
    [ $# -eq 4 ] || { echo "usage: android-device.sh tap <serial> <x> <y>" >&2; exit 1; }
    "$ADB" -s "$2" shell input tap "$3" "$4"
    ;;

  swipe)
    [ $# -ge 6 ] || { echo "usage: android-device.sh swipe <serial> <x1> <y1> <x2> <y2> [ms]" >&2; exit 1; }
    "$ADB" -s "$2" shell input swipe "$3" "$4" "$5" "$6" "${7:-300}"
    ;;

  key)
    [ $# -eq 3 ] || { echo "usage: android-device.sh key <serial> back|home" >&2; exit 1; }
    case "$3" in
      back) "$ADB" -s "$2" shell input keyevent KEYCODE_BACK ;;
      home) "$ADB" -s "$2" shell input keyevent KEYCODE_HOME ;;
      *) echo "지원하지 않는 키: $3 (back | home)" >&2; exit 1 ;;
    esac
    ;;

  screenshot)
    [ $# -eq 3 ] || { echo "usage: android-device.sh screenshot <serial> <out.png>" >&2; exit 1; }
    "$ADB" -s "$2" exec-out screencap -p > "$3" && [ -s "$3" ] \
      || { echo "스크린샷을 저장하지 못했습니다: $3" >&2; exit 1; }
    ;;

  ensure)
    SERIAL="$(first_device)"
    if [ -n "$SERIAL" ]; then echo "KIND $(kind_of "$SERIAL")" >&2; echo "$SERIAL"; exit 0; fi

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
        echo "KIND virtual" >&2
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
    echo "usage: android-device.sh check | ensure [avd] | cleanup <serial> | ui <serial> | tap <serial> <x> <y> | swipe <serial> <x1> <y1> <x2> <y2> [ms] | key <serial> back|home | screenshot <serial> <out.png>" >&2
    exit 1
    ;;
esac
