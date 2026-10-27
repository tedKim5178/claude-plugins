#!/bin/bash
# open-reports.py 테스트 — now(start-work가 바로 엶)와 훅(프롬프트 이후 새로 쓰인 report.html만)이 연 목록을 함께 써서 한 번씩 연다.
# 실행: scripts/tests/open-reports.test.sh  (임시 디렉토리만 쓴다)
set -uo pipefail
source "$(dirname "$0")/lib.sh"
O="$SCRIPTS/open-reports.py"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
FAIL=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; FAIL=1; }

R="$T/repo"; mkdir -p "$R/.impl-spec/spec-1.visual/shucle" "$R/.impl-spec/spec-2.visual" "$R/sub"
git -C "$R" init -q -b main
LOG="$T/opened.log"
printf '#!/bin/bash\necho "$1" >> "%s"\n' "$LOG" > "$T/fake-open"; chmod +x "$T/fake-open"
export IMPL_CHAIN_OPEN_CMD="$T/fake-open" IMPL_CHAIN_STATE_DIR="$T/state"
IN='{"session_id":"s1","cwd":"'"$R/sub"'"}'
run() { echo "$IN" | python3 "$O" "$1"; }
opened() { sleep 0.3; [ -f "$LOG" ] && wc -l < "$LOG" | tr -d ' ' || echo 0; }

# 예전 리포트 (프롬프트 전)
echo old > "$R/.impl-spec/spec-2.visual/report.html"
touch -t 202001010000 "$R/.impl-spec/spec-2.visual/report.html"

out=$(run open)
[ -z "$out" ] && [ "$(opened)" = 0 ] && ok "기준 시각 없으면 안 엶" || bad "기준 시각 없이 열었음"

run mark
out=$(run open)
[ "$(opened)" = 0 ] && ok "프롬프트 전 리포트는 안 엶" || bad "예전 리포트를 열었음"

echo new > "$R/.impl-spec/spec-1.visual/shucle/report.html"
out=$(run open)
[ "$(opened)" = 1 ] && grep -q "spec-1.visual/shucle/report.html" "$LOG" && ok "새 리포트 엶 (하위 폴더 cwd에서도)" || bad "새 리포트 안 엶"
echo "$out" | grep -q "systemMessage" && ok "systemMessage로 알림" || bad "알림 없음 — $out"

out=$(run open)
[ "$(opened)" = 1 ] && [ -z "$out" ] && ok "한 번 연 건 다시 안 엶" || bad "중복으로 열었음"

touch -t 203001010000 "$R/.impl-spec/spec-1.visual/shucle/report.html"
run open >/dev/null
[ "$(opened)" = 2 ] && ok "다시 만든 리포트는 다시 엶" || bad "갱신된 리포트 안 엶"

IMPL_CHAIN_OPEN_REPORTS=0 run mark; echo x > "$R/.impl-spec/spec-2.visual/report.html"
IMPL_CHAIN_OPEN_REPORTS=0 run open >/dev/null
[ "$(opened)" = 2 ] && ok "IMPL_CHAIN_OPEN_REPORTS=0 이면 안 엶" || bad "꺼도 열었음"

echo 'not json' | python3 "$O" open; [ $? = 0 ] && ok "잘못된 입력에도 종료 코드 0" || bad "종료 코드 0 아님"

echo "now (start-work Step 8)"
run open > /dev/null; : > "$LOG"   # 앞에서 꺼 둔 동안 바뀐 리포트(spec-2)를 먼저 비운다
echo v3 > "$R/.impl-spec/spec-1.visual/shucle/report.html"
out=$(python3 "$O" now "$R/.impl-spec/spec-1.visual/shucle/report.html"); rc=$?
[ $rc = 0 ] && [ "$out" = "OPENED $R/.impl-spec/spec-1.visual/shucle/report.html" ] && [ "$(opened)" = 1 ] && ok "now: 바로 열고 OPENED" || bad "now (exit $rc): $out"
run open >/dev/null
[ "$(opened)" = 1 ] && ok "now로 연 리포트는 턴 끝 훅이 다시 안 엶" || bad "훅이 중복으로 열었음"
python3 "$O" now "$R/.impl-spec/spec-1.visual/shucle/report.html" >/dev/null
[ "$(opened)" = 2 ] && ok "now는 이미 연 것도 다시 엶 (명시 호출)" || bad "now 재호출"
out=$(IMPL_CHAIN_OPEN_REPORTS=0 python3 "$O" now "$R/.impl-spec/spec-1.visual/shucle/report.html")
[ "$out" = "PATH $R/.impl-spec/spec-1.visual/shucle/report.html" ] && [ "$(opened)" = 2 ] && ok "now: 끄면 PATH만" || bad "now 끔: $out"
out=$(IMPL_CHAIN_OPEN_CMD=false python3 "$O" now "$R/.impl-spec/spec-1.visual/shucle/report.html")
[ "${out%% *}" = PATH ] && ok "now: 열기 실패면 PATH" || bad "now 열기 실패: $out"
python3 "$O" now "$T/none.html" > /dev/null 2> "$T/err"; rc=$?
[ $rc = 1 ] && grep -q "리포트 없음" "$T/err" && ok "now: 리포트 없으면 exit 1" || bad "now 없는 리포트 (exit $rc)"
python3 "$O" now > /dev/null 2>&1; [ $? = 1 ] && ok "now: 인자 없으면 exit 1" || bad "now 인자 없음 허용"

[ $FAIL = 0 ] && echo "ALL PASS" || { echo "FAILED"; exit 1; }
