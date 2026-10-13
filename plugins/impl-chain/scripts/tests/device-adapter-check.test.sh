#!/bin/bash
# device-adapter-check.sh 테스트 — 가짜 어댑터(정상·계약 위반·환경 미충족)로 판정과 종료 코드를 확인한다.
# 실행: scripts/tests/device-adapter-check.test.sh  (실제 기기를 건드리지 않는다)
set -uo pipefail
source "$(dirname "$0")/lib.sh"
C="$SCRIPTS/device-adapter-check.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
FAIL=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; FAIL=1; }
expect() {
  local d=$1 want=$2; shift 2
  "$@" > "$T/out" 2> "$T/err"; local got=$?
  if [ "$got" = "$want" ]; then ok "$d"; else bad "$d (exit $got, want $want): $(tail -3 "$T/out") $(head -2 "$T/err")"; fi
}
has() { grep -q -- "$1" "$T/out" && ok "$2" || bad "$2: $(cat "$T/out")"; }

# 가짜 어댑터 — 환경 변수 BREAK로 고장 낼 곳을 고른다. 호출은 $T/calls에 기록
A="$T/adapter.sh"
cat > "$A" <<EOF
#!/bin/bash
echo "\$*" >> "$T/calls"
B="\${BREAK:-}"
case "\${1:-}" in
  check)  [ "\$B" = no-tool ] && { echo "도구 없음" >&2; exit 3; }; [ "\$B" = check-1 ] && exit 1; [ "\$B" = check-empty ] || echo /fake/tool ;;
  ensure) [ "\$B" = no-device ] && { echo "기기 없음" >&2; exit 4; }
          [ "\$B" = no-device-silent ] && exit 4
          [ "\$B" = ensure-1 ] && { echo "뭔가 실패" >&2; exit 1; }
          [ "\$B" = ensure-empty ] && exit 0
          [ "\$B" = booted ] && echo "BOOTED DEV1" >&2
          [ "\$B" = booted-wrong ] && echo "BOOTED OTHER" >&2
          echo DEV1 ;;
  ui)     [ "\$B" = ui-fail ] && { echo "못 읽음" >&2; exit 1; }; [ "\$B" = ui-empty ] || echo '<node text="확인" bounds="[0,0][10,10]"/>' ;;
  screenshot) [ "\$B" = shot-fail ] && exit 1; if [ "\$B" = shot-notpng ]; then echo hello > "\$3"; else printf '\\x89PNG\\r\\n' > "\$3"; fi ;;
  tap)    [ \$# -eq 4 ] || { [ "\$B" = lenient ] && exit 0; exit 1; }; [ "\$B" = tap-fail ] && exit 1; : ;;
  swipe)  [ "\$B" = swipe-fail ] && exit 1; : ;;
  key)    [ "\$B" = no-key ] && { echo "home 없음" >&2; exit 1; }; : ;;
  cleanup) [ "\$B" = cleanup-fail ] && exit 1; : ;;
  *) [ "\$B" = lenient ] && exit 0; exit 1 ;;
esac
EOF
chmod +x "$A"
run() { rm -f "$T/calls"; BREAK="${1:-}" "$C" --out "$T/o" "$A"; }

echo "정상 어댑터"
expect "계약 통과 exit 0" 0 run
has "RESULT ok" "RESULT ok"
has "PASS ensure — 기기 id: DEV1" "기기 id 보고"
has "PASS screenshot" "PNG 확인"
[ "$(grep -c '^FAIL' "$T/out")" = 0 ] && ok "FAIL 없음" || bad "FAIL 있음"
grep -qx "tap DEV1 1 1" "$T/calls" && ok "무해한 좌표로 tap" || bad "calls=$(cat "$T/calls")"
grep -qx "cleanup DEV1" "$T/calls" && ok "cleanup 호출" || bad "cleanup 안 함"
[ -s "$T/o/ui.out" ] && [ -s "$T/o/screen.png" ] && ok "산출물 남김" || bad "산출물 없음"
expect "이 검사가 띄운 기기" 0 run booted
has "이 검사가 띄움" "BOOTED 인식"
expect "key home 미지원은 통과 (선택 기능)" 0 run no-key
has "SKIP key" "SKIP key"

echo "환경 미충족 — exit 2"
expect "도구 없음" 2 run no-tool
has "RESULT env-unavailable" "RESULT env-unavailable"
grep -q "^ensure" "$T/calls" && bad "도구가 없는데 ensure를 부름" || ok "도구 없으면 거기서 멈춤"
expect "기기 없음" 2 run no-device
has "SKIP ensure — 기기를 확보하지 못함 (exit 4): 기기 없음" "사유 전달"

echo "계약 위반 — exit 1"
expect "check가 3이 아닌 실패" 1 run check-1
expect "check stdout 없음" 1 run check-empty
expect "ensure 실패 코드가 3·4·5가 아님" 1 run ensure-1
expect "ensure가 id를 안 냄" 1 run ensure-empty
expect "ensure 실패에 사유 없음" 1 run no-device-silent
expect "BOOTED 줄의 id가 다름" 1 run booted-wrong
expect "ui 실패" 1 run ui-fail
has "RESULT contract-fail" "RESULT contract-fail"
grep -qx "cleanup DEV1" "$T/calls" && ok "실패해도 cleanup까지 감" || bad "cleanup 안 함"
expect "ui 빈 출력" 1 run ui-empty
expect "screenshot 실패" 1 run shot-fail
expect "screenshot이 PNG가 아님" 1 run shot-notpng
expect "tap 실패" 1 run tap-fail
expect "swipe 실패" 1 run swipe-fail
expect "cleanup 실패" 1 run cleanup-fail
expect "잘못된 호출을 받아줌" 1 run lenient
has "FAIL 인자검사 — 좌표 없는 tap이 exit 0" "인자 검사 보고"

echo "사용법"
expect "없는 어댑터 경로" 64 "$C" "$T/nope.sh"
expect "모르는 옵션" 64 "$C" --nope

echo "프로필에서 어댑터 찾기"
make_repo "$T/repo"
mkdir -p "$T/repo/.claude/impl-chain/adapters" && cp "$A" "$T/repo/.claude/impl-chain/adapters/dev.sh"
printf -- '- device_adapter: .claude/impl-chain/adapters/dev.sh\n' >> "$T/repo/.claude/impl-chain/profile.md"
( cd "$T/repo" && "$C" --out "$T/o2" ) > "$T/out" 2> "$T/err"; rc=$?
[ "$rc" = 0 ] && ok "인자 없으면 프로필의 device_adapter" || bad "exit $rc: $(cat "$T/out" "$T/err")"
has "adapters/dev.sh" "그 어댑터를 검사"

echo
[ "$FAIL" = 0 ] && echo "ALL PASS" || { echo "FAILED"; exit 1; }
