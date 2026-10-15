#!/bin/bash
# session-profile.py 테스트 — 가짜 세션 기록으로 요약 출력을 확인한다.
# 실행: scripts/tests/session-profile.test.sh  (임시 디렉토리만 쓴다)
set -uo pipefail
source "$(dirname "$0")/lib.sh"
P="$SCRIPTS/session-profile.py"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
FAIL=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; FAIL=1; }
has() { grep -qF -- "$2" "$1" && ok "$3" || bad "$3 — '$2' 없음"; }
hasnt() { grep -qF -- "$2" "$1" && bad "$3 — '$2' 있음" || ok "$3"; }

S="$T/sess"; mkdir -p "$S/subagents"
cat > "$S.jsonl" <<'J'
{"type":"assistant","timestamp":"2026-10-01T00:00:00Z","message":{"id":"m1","model":"claude-sonnet-5-0","usage":{"input_tokens":10,"cache_read_input_tokens":50000,"output_tokens":5},"content":[{"type":"tool_use","id":"a1","name":"Agent","input":{}}]}}
{"type":"user","timestamp":"2026-10-01T00:10:00Z","message":{"content":[{"type":"tool_result","tool_use_id":"a1","content":"done"}]}}
{"type":"assistant","timestamp":"2026-10-01T00:10:30Z","message":{"id":"m2","model":"claude-sonnet-5-0","usage":{"input_tokens":10,"cache_read_input_tokens":60000,"output_tokens":7},"content":[{"type":"text","text":"끝"}]}}
J
cat > "$S/subagents/agent-x.jsonl" <<'J'
{"type":"assistant","timestamp":"2026-10-01T00:00:10Z","message":{"id":"s1","model":"claude-sonnet-5-0","usage":{"input_tokens":5,"cache_creation_input_tokens":180000,"output_tokens":3},"content":[{"type":"tool_use","id":"f1","name":"mcp__plugin_figma_figma__get_design_context","input":{"nodeId":"1:2"}}]}}
{"type":"user","timestamp":"2026-10-01T00:02:10Z","message":{"content":[{"type":"tool_result","tool_use_id":"f1","content":[{"type":"text","text":"SECRET_CODE_BODY"},{"type":"image","source":{"data":"AAAA"}}]}]}}
{"type":"system","timestamp":"2026-10-01T00:02:20Z","subtype":"api_error"}
{"type":"system","timestamp":"2026-10-01T00:02:30Z","subtype":"compact_boundary"}
{"type":"assistant","timestamp":"2026-10-01T00:03:10Z","message":{"id":"s2","model":"claude-sonnet-5-0","usage":{"output_tokens":9},"content":[{"type":"tool_use","id":"b1","name":"Bash","input":{"command":"x"}}]}}
{"type":"user","timestamp":"2026-10-01T00:03:20Z","message":{"content":[{"type":"tool_result","tool_use_id":"b1","is_error":true,"content":"boom"}]}}
J
echo '{"agentType":"figma-ui-spec","description":"UI spec G1"}' > "$S/subagents/agent-x.meta.json"

echo "요약"
python3 "$P" "$S" > "$T/out" 2> "$T/err"; [ $? = 0 ] && ok "exit 0" || bad "exit $(cat "$T/err")"
has "$T/out" "== 메인 — claude-sonnet-5-0" "메인 블록·모델"
has "$T/out" "figma-ui-spec (UI spec G1)" "서브에이전트 이름은 meta.json에서"
has "$T/out" "figma:get_design_context" "Figma 도구 이름 축약"
has "$T/out" "2.0m" "도구 걸린 시간"
has "$T/out" "이미지 1장" "이미지 따로 집계"
has "$T/out" "컨텍스트 최대 180005 tok" "컨텍스트 최대"
has "$T/out" "API 오류 1" "API 오류 수"
has "$T/out" "압축 1" "압축 횟수"
has "$T/out" "도구 실패 1" "실패한 도구 호출"
has "$T/out" "모델 생성 1.0m" "모델 생성 시간"
hasnt "$T/out" "SECRET_CODE_BODY" "응답 내용은 출력하지 않음"
python3 "$P" "$S.jsonl" > "$T/out2" 2>&1 && cmp -s "$T/out" "$T/out2" && ok ".jsonl 경로로도 같은 결과" || bad ".jsonl 경로"

echo "거부"
python3 "$P" "$T/none" > /dev/null 2>&1; [ $? = 1 ] && ok "없는 세션 → exit 1" || bad "없는 세션"
python3 "$P" "$S" --top x > /dev/null 2>&1; [ $? = 1 ] && ok "--top 숫자 아님 → exit 1" || bad "--top"

echo
[ "$FAIL" = 0 ] && echo "ALL PASS" || { echo "FAILED"; exit 1; }
