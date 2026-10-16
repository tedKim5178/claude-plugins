#!/bin/bash
# ios-device.sh 테스트 — 가짜 xcrun(simctl)·axe 스텁으로 도구 확인·시뮬레이터 선택·부팅 분기·조작 전달을 확인한다.
# 실행: scripts/tests/ios-device.test.sh  (실제 시뮬레이터를 건드리지 않는다)
set -uo pipefail
source "$(dirname "$0")/lib.sh"
D="$SCRIPTS/ios-device.sh"
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

# 가짜 도구: xcrun은 $T/devices.json을 기기 목록으로 출력하고 부팅·종료·스크린샷 요청을 기록한다. axe는 호출을 기록한다
BIN="$T/bin"; NOAXE="$T/bin-noaxe"; mkdir -p "$BIN" "$NOAXE" "$T/tmp"
cat > "$BIN/xcrun" <<EOF
#!/bin/bash
[ "\$1" = simctl ] || exit 1
shift
case "\$1" in
  help) : ;;
  list) cat "$T/devices.json" ;;
  bootstatus) [ -f "$T/boot-hang" ] && sleep 30; [ -f "$T/boot-fail" ] && exit 1; echo "\$*" >> "$T/booted" ;;
  shutdown) echo "\$*" >> "$T/shutdown" ;;
  io) [ -f "$T/shot-broken" ] || printf 'PNG' > "\$4" ;;
  *) : ;;
esac
EOF
cat > "$BIN/axe" <<EOF
#!/bin/bash
echo "\$*" >> "$T/calls"
case "\$1" in
  describe-ui) [ -f "$T/ui-broken" ] && exit 1; echo '[{"AXLabel":"확인","frame":{"x":10,"y":20,"width":100,"height":44}}]' ;;
esac
EOF
chmod +x "$BIN/xcrun" "$BIN/axe"
cp "$BIN/xcrun" "$NOAXE/xcrun"
# PATH에서 진짜 xcrun·axe를 숨긴다 (/usr/bin의 xcrun보다 스텁이 먼저). /opt/homebrew·/usr/local의 axe는 HOME과 무관하게 잡히므로 axe 없음 테스트는 그 경로에 없을 때만 한다
CLEAN_PATH="/usr/bin:/bin:/usr/sbin:/sbin"
run()   { env -i HOME="$T/home" TMPDIR="$T/tmp" PATH="$BIN:$CLEAN_PATH" IOS_DEVICE_BOOT_TIMEOUT=2 "$@"; }
devices() { # $1 = 15 Pro(26.3) 상태, $2 = 16(18.5) 상태
  cat > "$T/devices.json" <<EOF
{"devices": {
  "com.apple.CoreSimulator.SimRuntime.iOS-18-5": [
    {"udid": "U-185-IPAD", "name": "iPad Air", "state": "Shutdown", "isAvailable": true},
    {"udid": "U-185-16", "name": "iPhone 16", "state": "$2", "isAvailable": true}],
  "com.apple.CoreSimulator.SimRuntime.iOS-26-3": [
    {"udid": "U-263-GONE", "name": "iPhone 17", "state": "Shutdown", "isAvailable": false},
    {"udid": "U-263-15P", "name": "iPhone 15 Pro", "state": "$1", "isAvailable": true}],
  "com.apple.CoreSimulator.SimRuntime.watchOS-11-0": [
    {"udid": "U-WATCH", "name": "iPhone Watch", "state": "Booted", "isAvailable": true}]
}}
EOF
}

echo "check"
expect "도구 있음" 0 run "$D" check
[ "$out" = "$BIN/axe" ] && ok "axe 경로 출력" || bad "out=$out"
if [ -x /opt/homebrew/bin/axe ] || [ -x /usr/local/bin/axe ]; then
  ok "axe 없음 테스트 건너뜀 (이 Mac에 axe가 설치돼 있다)"
else
  expect "axe가 없으면 exit 3" 3 env -i HOME="$T/home" PATH="$NOAXE:$CLEAN_PATH" "$D" check
  grep -q "brew install" "$T/err" && ok "설치 방법 안내" || bad "err=$(cat "$T/err")"
fi
expect "xcrun이 없으면 exit 3" 3 env -i HOME="$T/home" PATH="/nonexistent" /bin/bash "$D" check

echo "ensure — 부팅된 시뮬레이터"
devices Shutdown Booted
expect "부팅된 것이 있으면 그 UDID" 0 run "$D" ensure
[ "$out" = "U-185-16" ] && ok "Booted만 고름 (iOS 런타임만)" || bad "out=$out"
[ ! -f "$T/booted" ] && ok "부팅하지 않음" || bad "부팅함"
grep -qx "KIND virtual" "$T/err" && ok "KIND virtual" || bad "KIND: $(cat "$T/err")"

echo "ensure — 부팅된 것 없음"
devices Shutdown Shutdown
expect "기본 선택으로 부팅" 0 run "$D" ensure
[ "$out" = "U-263-15P" ] && ok "최신 런타임의 사용 가능한 iPhone" || bad "out=$out"
grep -q "BOOTED U-263-15P" "$T/err" && ok "stderr에 BOOTED" || bad "BOOTED 없음: $(cat "$T/err")"
grep -qx "KIND virtual" "$T/err" && ok "부팅한 것도 KIND virtual" || bad "KIND: $(cat "$T/err")"
grep -q "bootstatus U-263-15P -b" "$T/booted" && ok "bootstatus -b 호출" || bad "booted=$(cat "$T/booted" 2>/dev/null)"
rm -f "$T/booted"
expect "이름으로 지정" 0 run "$D" ensure "iPhone 16"
[ "$out" = "U-185-16" ] && ok "지정 시뮬레이터 부팅" || bad "out=$out"
expect "UDID로 지정" 0 run "$D" ensure U-185-IPAD
[ "$out" = "U-185-IPAD" ] && ok "UDID 일치" || bad "out=$out"
expect "없는 이름은 exit 4" 4 run "$D" ensure "iPhone 99"
expect "사용 불가(isAvailable=false)는 고르지 않음" 4 run "$D" ensure "iPhone 17"
touch "$T/boot-fail"
expect "부팅 실패는 exit 4" 4 run "$D" ensure
rm "$T/boot-fail"; touch "$T/boot-hang"
expect "부팅 시간 초과는 exit 5" 5 run "$D" ensure
rm "$T/boot-hang"
echo '{"devices": {}}' > "$T/devices.json"
expect "시뮬레이터가 하나도 없으면 exit 4" 4 run "$D" ensure

echo "cleanup"
rm -f "$T/shutdown"
expect "ensure가 부팅한 시뮬레이터 종료" 0 run "$D" cleanup U-263-15P
grep -q "shutdown U-263-15P" "$T/shutdown" && ok "shutdown 호출" || bad "종료 안 함"
expect "다시 부르면 종료하지 않음 (표시 삭제됨)" 0 run "$D" cleanup U-263-15P
[ "$(grep -c U-263-15P "$T/shutdown")" = 1 ] && ok "한 번만 종료" || bad "shutdown=$(cat "$T/shutdown")"
expect "부팅하지 않은 시뮬레이터는 종료하지 않음" 0 run "$D" cleanup U-OTHER
grep -q U-OTHER "$T/shutdown" && bad "원래 켜져 있던 것을 종료함" || ok "원래 켜져 있던 것 보호"

echo "기기 조작"
: > "$T/calls"
expect "ui — 요소 트리 출력" 0 run "$D" ui U1
grep -q '"AXLabel":"확인"' <<< "$out" && ok "라벨 포함" || bad "out=$out"
touch "$T/ui-broken"
expect "ui — 실패면 exit 1" 1 run "$D" ui U1
rm "$T/ui-broken"
expect "tap" 0 run "$D" tap U1 10 20
grep -qx -- "tap -x 10 -y 20 --udid U1" "$T/calls" && ok "그 시뮬레이터에 tap 전달" || bad "calls=$(cat "$T/calls")"
expect "tap — 인자 부족" 1 run "$D" tap U1 10
expect "swipe" 0 run "$D" swipe U1 1 2 3 4
grep -q -- "swipe --start-x 1 --start-y 2 --end-x 3 --end-y 4 --duration 0.300 --udid U1" "$T/calls" && ok "기본 300ms → 0.300초" || bad "calls=$(cat "$T/calls")"
expect "swipe — ms 지정" 0 run "$D" swipe U1 1 2 3 4 1500
grep -q -- "--duration 1.500 --udid U1" "$T/calls" && ok "1500ms → 1.500초" || bad "calls=$(cat "$T/calls")"
expect "key home" 0 run "$D" key U1 home
grep -qx -- "button home --udid U1" "$T/calls" && ok "home 버튼 전달" || bad "calls=$(cat "$T/calls")"
expect "key back — iOS에 없음" 1 run "$D" key U1 back
expect "screenshot" 0 run "$D" screenshot U1 "$T/shot.png"
[ -s "$T/shot.png" ] && ok "파일 저장" || bad "스크린샷 없음"
touch "$T/shot-broken"
expect "screenshot — 실패면 exit 1" 1 run "$D" screenshot U1 "$T/shot2.png"

echo
[ "$FAIL" = 0 ] && echo "ALL PASS" || { echo "FAILED"; exit 1; }
