#!/bin/bash
# visual-report.py 테스트 — 상태 파일의 visual_cases + results.json → report.html.
# 실행: scripts/tests/visual-report.test.sh  (임시 디렉토리만 쓴다)
set -uo pipefail
source "$(dirname "$0")/lib.sh"
R="$SCRIPTS/visual-report.py"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
FAIL=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; FAIL=1; }
has() { grep -qF -- "$2" "$1" && ok "$3" || bad "$3 — '$2' 없음"; }
hasnt() { grep -qF -- "$2" "$1" && bad "$3 — '$2' 있음" || ok "$3"; }

OUT="$T/out"; mkdir -p "$OUT"
printf 'png' > "$OUT/V1.png"; printf 'png' > "$OUT/V2.png"; printf 'png' > "$OUT/X1.png"

cat > "$T/state.json" <<'JSON'
{
  "issue_type": "spec", "issue_number": 4895, "issue_title": "좌석 <등급> 뱃지",
  "todo_items": [
    {"id": "T1", "desc": "PREMIUM 뱃지", "verify": "visual"},
    {"id": "T2", "desc": "도착 시 시트", "verify": "manual"}
  ],
  "visual_cases": [
    {"id": "V1", "todo_id": "T1", "scenario": "좌석 목록", "condition": "PREMIUM", "kind": "target", "expect": "'프리미엄' 뱃지"},
    {"id": "V2", "todo_id": "T1", "scenario": "좌석 목록", "condition": "STANDARD", "kind": "regression", "expect": "뱃지 없음"},
    {"id": "V3", "todo_id": "T2", "scenario": "차량 도착", "condition": "PREMIUM", "kind": "target", "expect": "시트 안 뜸"},
    {"id": "V4", "todo_id": "T2", "scenario": "차량 도착", "condition": "STANDARD", "kind": "regression", "expect": "시트 뜸"}
  ]
}
JSON

cat > "$T/results.json" <<'JSON'
{
  "device": "R5CT (연결 기기)", "build": "./gradlew :app:installDebug", "commit": "abc1234",
  "entry": "홈 → 예약 → 좌석. mock은 grade만 바꿈",
  "mock_files": ["seat.v1.SeatService__ListSeats.json"],
  "device_fallback": ["ios-real-device: USB로 연결된 iOS 기기가 없습니다"],
  "results": [
    {"case_id": "V1", "verdict": "PASS", "evidence": "text=\"프리미엄\"", "screenshot": "V1.png"},
    {"case_id": "V2", "verdict": "FAIL", "evidence": "기대 \"뱃지 없음\", 실제 <프리미엄>", "screenshot": "V2.png"},
    {"case_id": "V3", "verdict": "MANUAL", "evidence": "진입 경로: 홈 → 온고잉 카드"}
  ],
  "extra_cases": [
    {"id": "X1", "todo_id": "T1", "scenario": "좌석 목록", "condition": "등급 없음", "kind": "regression",
     "expect": "뱃지 없음", "verdict": "PASS", "evidence": "뱃지 없음", "screenshot": "X1.png"}
  ],
  "not_verified": ["실서버 응답"],
  "observations": ["날짜 형식이 Figma와 다름"]
}
JSON

cp "$T/results.json" "$OUT/results.json"
run() { python3 "$R" "$@" > "$T/stdout" 2> "$T/stderr"; }
expect() { local d=$1 want=$2; shift 2; run "$@"; local got=$?
  if [ "$got" = "$want" ]; then ok "$d"; else bad "$d (exit $got, want $want): $(head -2 "$T/stderr")"; fi; }

echo "리포트 생성"
expect "정상 입력" 0 "$T/state.json" "$OUT"
H="$OUT/report.html"
[ -f "$H" ] && ok "report.html 생성" || bad "report.html 없음"
has "$T/stdout" "REPORT $H" "stdout에 경로"
has "$T/stdout" "PASS 2 / FAIL 1 / MANUAL 1 / NOT_RUN 1" "stdout에 판정 수"
has "$H" "<!doctype html>" "완결된 문서"
has "$H" "좌석 &lt;등급&gt; 뱃지" "제목 escape"
has "$H" "실제 &lt;프리미엄&gt;" "근거 escape"
has "$H" 'src="V1.png"' "스크린샷은 상대 경로"
has "$H" "좌석 목록" "시나리오 묶음"
has "$H" "PREMIUM" "조건 표시"
has "$H" "확인 안 함" "결과 없는 계획 케이스(V4)는 '확인 안 함'"
has "$H" "계획에 없던 케이스" "extra 케이스 표시"
has "$H" "실서버 응답" "확인하지 못한 것"
has "$H" "seat.v1.SeatService__ListSeats.json" "mock 파일"
has "$H" "건너뛴 기기 어댑터 — ios-real-device" "건너뛴 기기 어댑터"
has "$H" "날짜 형식이 Figma와 다름" "관찰"
# 대상(target)이 회귀보다 먼저
[ "$(grep -n 'data-case="V1"' "$H" | cut -d: -f1)" -lt "$(grep -n 'data-case="V2"' "$H" | cut -d: -f1)" ] && ok "target이 regression보다 앞" || bad "순서"

echo "fragment"
expect "--fragment" 0 --fragment "$T/state.json" "$OUT"
hasnt "$H" "<!doctype html>" "문서 껍데기 없음"
has "$H" "<title>" "title은 유지"

echo "거부"
jq '.results[0].screenshot = "none.png"' "$T/results.json" > "$OUT/results.json"
cp "$T/results.json" "$T/keep.json"
expect "PASS인데 스크린샷 파일 없음" 1 "$T/state.json" "$OUT" --results "$OUT/results.json"
has "$T/stderr" "none.png" "없는 파일 이름"
jq 'del(.results[0].screenshot)' "$T/keep.json" > "$OUT/results.json"
expect "PASS인데 스크린샷 없음" 1 "$T/state.json" "$OUT" --results "$OUT/results.json"
has "$T/stderr" "V1" "증거 없는 PASS의 case id"
jq '.results[0].case_id = "V9"' "$T/keep.json" > "$OUT/results.json"
expect "계획에 없는 case_id" 1 "$T/state.json" "$OUT" --results "$OUT/results.json"
has "$T/stderr" "V9" "모르는 case id"
jq '.results[0].verdict = "OK"' "$T/keep.json" > "$OUT/results.json"
expect "verdict 오류" 1 "$T/state.json" "$OUT" --results "$OUT/results.json"
jq '.results[0].screenshot = "../x.png"' "$T/keep.json" > "$OUT/results.json"
expect "스크린샷이 출력 디렉토리 밖" 1 "$T/state.json" "$OUT" --results "$OUT/results.json"
rm -f "$OUT/results.json"
expect "results.json 없음" 1 "$T/state.json" "$OUT"

echo "기본 위치"
cp "$T/keep.json" "$OUT/results.json"
expect "{output_dir}/results.json을 기본으로 읽음" 0 "$T/state.json" "$OUT"

echo "레이아웃"
jq '.ui_specs = [{"file": "x.md"}]' "$T/state.json" > "$T/state-ui.json"
expect "ui_specs 있는데 target PASS에 layout 없음" 1 "$T/state-ui.json" "$OUT" --results "$T/keep.json"
has "$T/stderr" "V1" "layout 없는 PASS의 case id"
jq '.results[0].layout = [{"element": "E2 타이틀", "expect": "start padding 20", "actual": "21.8", "ok": true},
                          {"element": "E12 icon", "expect": "centerH", "actual": "중심 차이 18", "ok": false}]' "$T/keep.json" > "$T/lay.json"
expect "layout ok:false인데 PASS" 1 "$T/state-ui.json" "$OUT" --results "$T/lay.json"
has "$T/stderr" "E12 icon" "불일치 요소 이름"
jq '.results[0].verdict = "FAIL"' "$T/lay.json" > "$T/lay-fail.json"
expect "layout 불일치 → FAIL은 허용" 0 "$T/state-ui.json" "$OUT" --results "$T/lay-fail.json"
has "$H" "레이아웃 1/2" "레이아웃 집계 표시"
has "$H" "중심 차이 18" "실제 측정값 표시"
jq '.results[0].layout = [{"element": "E2", "expect": "start padding 20", "ok": "yes"}]' "$T/keep.json" > "$T/lay-bad.json"
expect "layout ok가 bool 아님" 1 "$T/state-ui.json" "$OUT" --results "$T/lay-bad.json"
jq '.results[0].layout_na = "기존 화면 — ui-spec 없음"' "$T/keep.json" > "$T/lay-na.json"
expect "layout_na 사유가 있으면 PASS 허용" 0 "$T/state-ui.json" "$OUT" --results "$T/lay-na.json"
has "$H" "레이아웃 측정 안 함" "layout_na 표시"
jq '.extra_cases[0].kind = "target"' "$T/keep.json" > "$T/lay-x.json"
jq '.results[0].layout_na = "n/a"' "$T/lay-x.json" > "$T/lay-x2.json"
expect "extra target PASS에도 layout 필요" 1 "$T/state-ui.json" "$OUT" --results "$T/lay-x2.json"
has "$T/stderr" "X1" "extra case id"

echo
[ "$FAIL" = 0 ] && echo "ALL PASS" || { echo "FAILED"; exit 1; }
