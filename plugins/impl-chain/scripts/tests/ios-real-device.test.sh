#!/bin/bash
# ios-real-device.sh 테스트 — 가짜 idevice_id·iproxy·curl(WDA) 스텁으로 기기 선택·포워드·WDA 기동 분기·조작 전달을 확인한다.
# 실행: scripts/tests/ios-real-device.test.sh  (실제 기기를 건드리지 않는다)
set -uo pipefail
source "$(dirname "$0")/lib.sh"
D="$SCRIPTS/ios-real-device.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
make_repo "$T/repo" && cd "$T/repo"
BASE_PROFILE=.claude/impl-chain/profile.md
FAIL=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; FAIL=1; }
expect() {
  local d=$1 want=$2; shift 2
  out=$("$@" 2>"$T/err"); local got=$?
  if [ "$got" = "$want" ]; then ok "$d"; else bad "$d (exit $got, want $want): $(head -2 "$T/err")"; fi
}

# 가짜 도구.
#   idevice_id -l  → $T/attached 내용
#   iproxy         → 호출 기록. $T/wda-on-device가 있으면(기기에 WDA가 이미 떠 있음) 포워드가 열리자마자 WDA가 응답한다
#   curl           → WDA. $T/wda-ready가 있을 때만 응답한다. 호출을 "METHOD URL BODY"로 기록한다
BIN="$T/bin"; mkdir -p "$BIN" "$T/tmp"
cat > "$BIN/idevice_id" <<EOF
#!/bin/bash
cat "$T/attached" 2>/dev/null
EOF
cat > "$BIN/iproxy" <<EOF
#!/bin/bash
echo "\$*" >> "$T/iproxy"
[ -f "$T/wda-on-device" ] && touch "$T/wda-ready"
exit 0
EOF
cat > "$BIN/curl" <<EOF
#!/bin/bash
M=GET; URL=; BODY=
while [ \$# -gt 0 ]; do
  case "\$1" in
    -X) M=\$2; shift ;;
    -d) BODY=\$2; shift ;;
    --max-time|-H) shift ;;
    http*) URL=\$1 ;;
  esac
  shift
done
[ -f "$T/wda-ready" ] || exit 7
echo "\$M \$URL \$BODY" >> "$T/calls"
case "\$M \$URL" in
  "GET "*/status) echo '{"value":{"ready":true}}' ;;
  "POST "*/session) n=\$(cat "$T/sid" 2>/dev/null || echo 0); n=\$((n+1)); echo \$n > "$T/sid"; echo "{\"value\":{\"sessionId\":\"S\$n\"}}" ;;
  "POST "*/session/DEAD/*) echo '{"value":{"error":"invalid session id"}}' ;;
  "POST "*/wda/tap|"POST "*/wda/dragfromtoforduration|"POST "*/wda/homescreen) [ -f "$T/op-broken" ] && echo '{"value":{"error":"unknown error"}}' || echo '{"value":null}' ;;
  "GET "*/source*) [ -f "$T/ui-broken" ] && echo '{"value":{"error":"x"}}' || echo '{"value":{"type":"Application","children":[{"type":"Button","label":"확인","rect":{"x":10,"y":20,"width":100,"height":44}}]}}' ;;
  "GET "*/screenshot) [ -f "$T/shot-broken" ] && echo '{"value":{"error":"x"}}' || echo '{"value":"UE5H"}' ;;
esac
EOF
chmod +x "$BIN/idevice_id" "$BIN/iproxy" "$BIN/curl"
CLEAN_PATH="/usr/bin:/bin:/usr/sbin:/sbin"
PROFILE="$T/profile.md"; cp "$BASE_PROFILE" "$PROFILE"
run() { env -i HOME="$T/home" TMPDIR="$T/tmp" PATH="$BIN:$CLEAN_PATH" IMPL_PROFILE="$PROFILE" IOS_WDA_START_TIMEOUT=3 "$@"; }
reset() { rm -f "$T/wda-ready" "$T/wda-on-device" "$T/iproxy" "$T/calls" "$T/sid" "$T/started"; rm -rf "$T/tmp/impl-chain-ios-real-device"; cp "$BASE_PROFILE" "$PROFILE"; }
set_key() { printf -- '- %s: %s\n' "$1" "$2" >> "$PROFILE"; }   # fixture의 마지막 섹션이 `화면 확인`이다

echo "check"
expect "도구 있음" 0 run "$D" check
[ "$out" = "$BIN/iproxy" ] && ok "iproxy 경로 출력" || bad "out=$out"
mkdir -p "$T/bin-noiproxy" && cp "$BIN/idevice_id" "$T/bin-noiproxy/"
if command -v iproxy > /dev/null 2>&1 && case "$(command -v iproxy)" in /usr/bin/*|/bin/*) true ;; *) false ;; esac; then
  ok "iproxy 없음 테스트 건너뜀"
else
  expect "iproxy가 없으면 exit 3" 3 env -i HOME="$T/home" PATH="$T/bin-noiproxy:$CLEAN_PATH" "$D" check
  grep -q "brew install libimobiledevice" "$T/err" && ok "설치 방법 안내" || bad "err=$(cat "$T/err")"
fi

echo "ensure — 기기 선택"
reset; : > "$T/attached"
expect "연결된 기기가 없으면 exit 4" 4 run "$D" ensure
printf 'UDID-A\nUDID-B\n' > "$T/attached"
expect "프로필·인자에 없는 UDID는 exit 4" 4 run "$D" ensure UDID-Z

echo "ensure — 이미 떠 있음"
reset; touch "$T/wda-ready"
expect "포워드·WDA가 이미 응답하면 그대로" 0 run "$D" ensure
[ "$out" = "UDID-A" ] && ok "첫 USB 기기" || bad "out=$out"
[ ! -f "$T/iproxy" ] && ok "포워드를 새로 열지 않음" || bad "iproxy 실행함"
grep -q BOOTED "$T/err" && bad "BOOTED를 냄" || ok "BOOTED 없음 (정리할 것 없음)"
grep -qx "KIND real" "$T/err" && ok "KIND real" || bad "KIND: $(cat "$T/err")"

echo "ensure — 포워드만 열면 됨 (WDA는 기기에 떠 있음)"
reset; touch "$T/wda-on-device"
expect "포워드를 열고 통과" 0 run "$D" ensure UDID-B
[ "$out" = "UDID-B" ] && ok "인자로 지정한 기기" || bad "out=$out"
grep -qx -- "-u UDID-B 8100:8100" "$T/iproxy" && ok "그 기기로 8100 포워드" || bad "iproxy=$(cat "$T/iproxy" 2>/dev/null)"
grep -q "BOOTED UDID-B" "$T/err" && ok "stderr에 BOOTED" || bad "BOOTED 없음: $(cat "$T/err")"
grep -qx "KIND real" "$T/err" && ok "포워드를 연 경우도 KIND real" || bad "KIND: $(cat "$T/err")"

echo "ensure — WDA를 띄워야 함"
reset
expect "wda_start가 없으면 exit 4" 4 run "$D" ensure
grep -q "wda_start" "$T/err" && ok "프로필 키 안내" || bad "err=$(cat "$T/err")"
reset; set_key wda_start "echo {udid} > $T/started; touch $T/wda-ready; sleep 30"; set_key wda_port 8200; set_key device_udid UDID-B
expect "wda_start로 띄우고 통과" 0 run "$D" ensure
[ "$out" = "UDID-B" ] && ok "프로필 device_udid" || bad "out=$out"
[ "$(cat "$T/started" 2>/dev/null)" = "UDID-B" ] && ok "{udid} 치환" || bad "started=$(cat "$T/started" 2>/dev/null)"
grep -qx -- "-u UDID-B 8200:8100" "$T/iproxy" && ok "프로필 wda_port" || bad "iproxy=$(cat "$T/iproxy")"
grep -q "127.0.0.1:8200/status" "$T/calls" && ok "그 포트로 상태 확인" || bad "calls=$(cat "$T/calls")"
PIDS="$T/tmp/impl-chain-ios-real-device/UDID-B.pids"
[ "$(wc -l < "$PIDS" | tr -d ' ')" = 2 ] && ok "포워드·WDA pid 기록" || bad "pids=$(cat "$PIDS" 2>/dev/null)"
WDA_PID="$(tail -1 "$PIDS")"
expect "cleanup" 0 run "$D" cleanup UDID-B
sleep 1
kill -0 "$WDA_PID" 2>/dev/null && bad "WDA 프로세스가 남음" || ok "띄운 WDA 프로세스 종료"
[ ! -f "$PIDS" ] && ok "기록 삭제" || bad "pids 남음"
expect "띄운 것이 없으면 아무것도 종료하지 않음" 0 run "$D" cleanup UDID-B
grep -q "아무것도 종료하지 않습니다" "$T/err" && ok "안내" || bad "err=$(cat "$T/err")"
reset; set_key wda_start "sleep 30"
expect "WDA가 끝내 응답하지 않으면 exit 5" 5 run "$D" ensure
[ ! -f "$T/tmp/impl-chain-ios-real-device/UDID-A.pids" ] && ok "시간 초과 시 띄운 것 정리" || bad "pids 남음"

echo "기기 조작"
reset; touch "$T/wda-ready"
expect "ui — 요소 트리 출력" 0 run "$D" ui U1
grep -q '"label": "확인"' <<< "$out" && ok "라벨 포함 (한글 그대로)" || bad "out=$out"
touch "$T/ui-broken"; expect "ui — WDA 오류면 exit 1" 1 run "$D" ui U1; rm "$T/ui-broken"
expect "tap" 0 run "$D" tap U1 10 20
grep -q 'POST http://127.0.0.1:8100/session/S1/wda/tap {"x":10,"y":20}' "$T/calls" && ok "세션을 만들고 tap 전달" || bad "calls=$(cat "$T/calls")"
expect "tap 한 번 더" 0 run "$D" tap U1 30 40
[ "$(grep -c "POST http://127.0.0.1:8100/session " "$T/calls")" = 1 ] && ok "세션 재사용" || bad "세션을 다시 만듦"
echo DEAD > "$T/tmp/impl-chain-ios-real-device/U1.session"
expect "죽은 세션이면 새로 만들어 재시도" 0 run "$D" tap U1 50 60
grep -q 'session/S2/wda/tap {"x":50,"y":60}' "$T/calls" && ok "새 세션으로 전달" || bad "calls=$(cat "$T/calls")"
expect "tap — 인자 부족" 1 run "$D" tap U1 10
expect "swipe" 0 run "$D" swipe U1 1 2 3 4
grep -q 'wda/dragfromtoforduration {"fromX":1,"fromY":2,"toX":3,"toY":4,"duration":0.300}' "$T/calls" && ok "기본 300ms → 0.300초" || bad "calls=$(cat "$T/calls")"
touch "$T/op-broken"; expect "조작 — WDA 오류면 exit 1" 1 run "$D" swipe U1 1 2 3 4
expect "key home — WDA 오류면 exit 1" 1 run "$D" key U1 home; rm "$T/op-broken"
expect "key home" 0 run "$D" key U1 home
grep -q "POST http://127.0.0.1:8100/wda/homescreen" "$T/calls" && ok "홈 화면 전달" || bad "calls=$(cat "$T/calls")"
expect "key back — iOS에 없음" 1 run "$D" key U1 back
expect "screenshot" 0 run "$D" screenshot U1 "$T/shot.png"
[ "$(cat "$T/shot.png" 2>/dev/null)" = "PNG" ] && ok "base64를 풀어 저장" || bad "스크린샷 내용: $(cat "$T/shot.png" 2>/dev/null)"
touch "$T/shot-broken"; expect "screenshot — WDA 오류면 exit 1" 1 run "$D" screenshot U1 "$T/shot2.png"
rm "$T/wda-ready"
expect "WDA 연결이 끊기면 tap exit 1" 1 run "$D" tap U1 1 2

echo
[ "$FAIL" = 0 ] && echo "ALL PASS" || { echo "FAILED"; exit 1; }
