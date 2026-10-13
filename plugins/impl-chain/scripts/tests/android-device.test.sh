#!/bin/bash
# android-device.sh 테스트 — 가짜 SDK(adb/emulator 스텁)로 경로 해석·기기 선택·부팅 분기를 확인한다.
# 실행: scripts/tests/android-device.test.sh  (실제 기기·에뮬레이터를 건드리지 않는다)
set -uo pipefail
source "$(dirname "$0")/lib.sh"
D="$SCRIPTS/android-device.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
FAIL=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; FAIL=1; }
expect() {
  local d=$1 want=$2; shift 2
  out=$("$@" 2>"$T/err"); local got=$?
  if [ "$got" = "$want" ]; then ok "$d"; else bad "$d (exit $got, want $want): $(head -2 "$T/err")"; fi
}

# 가짜 SDK: adb는 $T/state 파일 내용을 devices 목록으로 출력, emulator는 부팅 요청을 기록하고 기기를 '등록'한다
SDK="$T/sdk"; mkdir -p "$SDK/platform-tools" "$SDK/emulator"
cat > "$SDK/platform-tools/adb" <<EOF
#!/bin/bash
S="$T/state"
case "\$*" in
  devices) echo "List of devices attached"; cat "\$S" 2>/dev/null ;;
  *"getprop sys.boot_completed"*) echo 1 ;;
  *"emu kill"*) echo "\$*" >> "$T/killed"; : > "\$S" ;;
  *"uiautomator dump"*) [ -f "$T/ui-broken" ] && exit 1; echo "\$*" >> "$T/calls" ;;
  *"exec-out cat"*) echo '<hierarchy><node text="확인" bounds="[0,0][10,10]"/></hierarchy>' ;;
  *"exec-out screencap"*) [ -f "$T/shot-broken" ] || printf 'PNG' ;;
  *) echo "\$*" >> "$T/calls" ;;
esac
EOF
cat > "$SDK/emulator/emulator" <<EOF
#!/bin/bash
case "\$1" in
  -list-avds) cat "$T/avds" 2>/dev/null ;;
  *) echo "\$*" >> "$T/booted"; printf 'emulator-5554\tdevice\n' > "$T/state" ;;
esac
EOF
chmod +x "$SDK/platform-tools/adb" "$SDK/emulator/emulator"
# PATH에서 진짜 adb를 숨긴다
CLEAN_PATH="/usr/bin:/bin:/usr/sbin:/sbin"
run() { env -i HOME="$T/home" PATH="$CLEAN_PATH" ANDROID_HOME="$SDK" ANDROID_DEVICE_BOOT_TIMEOUT=5 "$@"; }

echo "adb 경로"
expect "ANDROID_HOME에서 adb 찾음" 0 run "$D" adb
[ "$out" = "$SDK/platform-tools/adb" ] && ok "경로 출력" || bad "out=$out"
expect "SDK가 없으면 exit 3" 3 env -i HOME="$T/home" PATH="$CLEAN_PATH" "$D" adb
expect "check — 도구 있음" 0 run "$D" check
[ "$out" = "$SDK/platform-tools/adb" ] && ok "check도 경로 출력" || bad "out=$out"
expect "check — SDK가 없으면 exit 3" 3 env -i HOME="$T/home" PATH="$CLEAN_PATH" "$D" check

echo "ensure — 연결된 기기"
printf 'R5CT\tdevice\nX\toffline\n' > "$T/state"
expect "연결 기기가 있으면 그 serial" 0 run "$D" ensure
[ "$out" = "R5CT" ] && ok "device 상태만 고름" || bad "out=$out"
[ ! -f "$T/booted" ] && ok "부팅하지 않음" || bad "부팅함"

echo "ensure — 기기 없음"
: > "$T/state"; : > "$T/avds"
expect "기기·AVD 둘 다 없으면 exit 4" 4 run "$D" ensure
printf 'Pixel_A\nPixel_B\n' > "$T/avds"
expect "AVD가 있으면 부팅" 0 run "$D" ensure
[ "$out" = "emulator-5554" ] && ok "부팅한 serial 출력" || bad "out=$out"
grep -q "BOOTED emulator-5554" "$T/err" && ok "stderr에 BOOTED" || bad "BOOTED 없음: $(cat "$T/err")"
grep -q -- "-avd Pixel_A" "$T/booted" && ok "첫 AVD를 부팅" || bad "booted=$(cat "$T/booted")"
grep -q -- "-no-window" "$T/booted" && ok "헤드리스" || bad "헤드리스 아님"
: > "$T/state"; rm -f "$T/booted"
expect "인자로 AVD 지정" 0 run "$D" ensure Pixel_B
grep -q -- "-avd Pixel_B" "$T/booted" && ok "지정 AVD 부팅" || bad "booted=$(cat "$T/booted")"
: > "$T/state"
expect "없는 AVD 지정은 exit 4" 4 run "$D" ensure Nope

echo "cleanup"
expect "부팅한 에뮬레이터 종료" 0 run "$D" cleanup emulator-5554
grep -q "emu kill" "$T/killed" && ok "emu kill 호출" || bad "kill 안 함"
expect "에뮬레이터가 아닌 serial은 종료하지 않음" 0 run "$D" cleanup R5CT
[ "$(grep -c R5CT "$T/killed")" = 0 ] && ok "실기기 보호" || bad "실기기 kill"

echo "기기 조작"
expect "ui — 요소 트리 출력" 0 run "$D" ui R5CT
grep -q 'text="확인"' <<< "$out" && ok "텍스트 포함" || bad "out=$out"
touch "$T/ui-broken"
expect "ui — dump 실패면 exit 1" 1 run "$D" ui R5CT
rm "$T/ui-broken"
expect "tap" 0 run "$D" tap R5CT 10 20
grep -q -- "-s R5CT shell input tap 10 20" "$T/calls" && ok "그 기기에 tap 전달" || bad "calls=$(cat "$T/calls")"
expect "tap — 인자 부족" 1 run "$D" tap R5CT 10
expect "swipe" 0 run "$D" swipe R5CT 1 2 3 4
grep -q -- "-s R5CT shell input swipe 1 2 3 4 300" "$T/calls" && ok "기본 300ms" || bad "calls=$(cat "$T/calls")"
expect "key back" 0 run "$D" key R5CT back
grep -q -- "keyevent KEYCODE_BACK" "$T/calls" && ok "BACK 전달" || bad "calls=$(cat "$T/calls")"
expect "key — 모르는 키" 1 run "$D" key R5CT menu
expect "screenshot" 0 run "$D" screenshot R5CT "$T/shot.png"
[ -s "$T/shot.png" ] && ok "파일 저장" || bad "스크린샷 없음"
touch "$T/shot-broken"
expect "screenshot — 빈 결과면 exit 1" 1 run "$D" screenshot R5CT "$T/shot2.png"

echo
[ "$FAIL" = 0 ] && echo "ALL PASS" || { echo "FAILED"; exit 1; }
