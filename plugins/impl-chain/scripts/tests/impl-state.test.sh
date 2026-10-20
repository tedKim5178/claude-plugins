#!/bin/bash
# impl-state.sh init 검증 테스트. 실행: scripts/tests/impl-state.test.sh
# 임시 레포(fixture 프로필)의 .impl-spec/ 안에 spec-990001 픽스처를 만든다 — 이 레포와 무관.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
S="$SCRIPTS/impl-state.sh"
N=990001
D=.impl-spec/t$N
STATE=.impl-spec/spec-$N.json
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
make_repo "$T/repo" && cd "$T/repo"
FAIL=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; FAIL=1; }

mkdir -p "$D/figma/ui-spec" "$D/figma/assets"
touch "$D/research.md" "$D/figma/ui-spec/S1-S2.md" "$D/figma/ui-spec/sp ace.md" "$D/figma/assets/ico_a.xml"

cat > "$T/base.json" <<EOF
{
  "issue_title": "t", "issue_url": "https://example/issues/$N", "spec_url": null, "milestone": null,
  "base_branch": "develop", "branch": "feat/$N-test", "size": "small",
  "research_files": ["$D/research.md"],
  "todo_items": [
    {"id": "T1", "desc": "화면", "source": "본문", "acceptance": "a", "verify": "visual", "figma_screens": ["S1", "S2"], "status": "pending", "note": null},
    {"id": "T2", "desc": "로직", "source": "본문", "acceptance": "b", "verify": "unit", "figma_screens": [], "status": "pending", "note": null}
  ],
  "decisions": [
    {"question": "q1", "answer": "a1", "by": "user", "todo_ids": ["T1"],
     "apply": [{"kind": "map_row", "op": "add", "data_name": "Button_CTA_Bottom", "component": "CommonButton(XLarge)", "evidence": "B.kt:1"}]},
    {"question": "q2", "answer": "a2", "by": "claude", "todo_ids": ["T1"],
     "apply": [{"kind": "asset", "figma_name": "ico/ico_a", "source": "$D/figma/assets/ico_a.xml", "target": "app/src/main/res/drawable/ico_a.xml"},
               {"kind": "map_row", "op": "append_issue", "data_name": "list_info", "issue": "spec-$N"},
               {"kind": "token_row", "op": "add", "figma_name": "text/body", "token": "Semantic.Text.Body", "value": "#5E5F66", "evidence": "spec-$N 값 일치"}]}
  ],
  "open_questions": [],
  "figma": {"status": "ok", "dir": "$D/figma/", "screens": [
    {"id": "S1", "node_id": "1:1", "group": "g", "case": "c1"},
    {"id": "S2", "node_id": "1:2", "group": "g", "case": "c2"}]},
  "ui_specs": [{"group": "g", "screens": ["S1", "S2"], "file": "$D/figma/ui-spec/S1-S2.md"}],
  "visual_cases": [
    {"id": "V1", "todo_id": "T1", "scenario": "목록 화면", "condition": "PREMIUM", "kind": "target", "expect": "뱃지 있음"},
    {"id": "V2", "todo_id": "T1", "scenario": "목록 화면", "condition": "STANDARD", "kind": "regression", "expect": "뱃지 없음"}],
  "proto_dependency": {"required": false, "status": "n/a"},
  "files_to_modify": [], "implementation_direction": "x", "compile_task": null, "test_task": null,
  "tasks": [], "previous_branch": null
}
EOF

# $1=설명 $2=기대 exit $3=base.json에 적용할 jq 필터 $4=(선택) stderr에 있어야 할 문구
expect_init() {
  local d=$1 want=$2 filter=$3 msg=${4:-}
  rm -f "$STATE"
  jq "$filter" "$T/base.json" | $S init spec $N > "$T/out" 2> "$T/err"; local got=$?
  if [ "$got" != "$want" ]; then bad "$d (exit $got, 기대 $want) $(head -3 "$T/err")"; return; fi
  if [ -n "$msg" ] && ! grep -q -- "$msg" "$T/err"; then bad "$d — stderr에 '$msg' 없음: $(head -3 "$T/err")"; return; fi
  ok "$d"
}

echo "init — 통과"
expect_init "기본 픽스처" 0 '.'
[ "$(jq -r .schema "$STATE")" = 3 ] && ok "schema 3으로 기록" || bad "schema 3으로 기록: $(jq -r .schema "$STATE")"
expect_init "figma none이면 ui_specs 불필요" 0 '.figma = {status:"none"} | del(.ui_specs) | .todo_items[0].figma_screens = []'
expect_init "visual todo 없으면 ui_specs 불필요" 0 '.todo_items |= map(.verify = "unit") | del(.ui_specs)'
expect_init "공백 포함 ui_specs 경로" 0 ".ui_specs[0].file = \"$D/figma/ui-spec/sp ace.md\""
expect_init "apply 없는 decision" 0 '.decisions = [{question:"q", answer:"a", by:"user"}]'
expect_init "map_row replace" 0 '.decisions[0].apply[0] += {op:"replace", expect:"CtaButton 또는 CommonButton"}'
expect_init "token_row replace" 0 '.decisions[1].apply[2] += {op:"replace", expect:"Semantic.Text.Caption"}'
expect_init "merge-ui-results 산출 필드 (ui_results·ui_spec_also·source)" 0 ".ui_results = [{file:\"$D/figma/ui-spec/S1-S2.md\", result_path:\"$D/figma/ui-spec/S1-S2.result.json\"}] | .decisions[0] += {key:\"component:x\", ui_spec:\"$D/figma/ui-spec/S1-S2.md\", ui_spec_also:[], source:\"start-work\"}"
expect_init "visual todo 없으면 visual_cases 불필요" 0 '.todo_items |= map(.verify = "unit") | del(.ui_specs) | del(.visual_cases)'
expect_init "manual todo에 단 visual_cases" 0 '.todo_items[1].verify = "manual" | .visual_cases += [{id:"V3", todo_id:"T2", scenario:"s", condition:"c", kind:"target", expect:"e"}]'
expect_init "apps 선택 (화이트라벨)" 0 '.apps = ["shucle","gmaas"]'
expect_init "apps null은 선택 없음" 0 '.apps = null'
expect_init "proto temp-local" 0 '.proto_dependency = {required:true, status:"temp-local", note:"example-proto#1 원문 임시 반영"}'

echo "init — 실패"
expect_init "apps 빈 배열" 1 '.apps = []' "apps"
expect_init "apps 중복" 1 '.apps = ["a","a"]' "두 번"
expect_init "apps 이름 형식" 1 '.apps = ["세종"]' "apps"
$S path bts 1 > /dev/null 2> "$T/err"; [ $? = 1 ] && grep -q "type은 spec" "$T/err" && ok "type bts는 거부 (BTS 지원 삭제)" || bad "type bts 거부: $(cat "$T/err")"
$S get bts 1 > /dev/null 2>&1; [ $? = 1 ] && ok "get도 잘못된 type이면 exit 1 (파일 없음 2가 아님)" || bad "get bts exit"
expect_init "visual 화면이 ui_specs에 없음" 1 '.ui_specs[0].screens = ["S1"]' "S2"
expect_init "ui_specs 없음" 1 'del(.ui_specs)' "ui_specs"
expect_init "ui_specs 파일 없음" 1 ".ui_specs[0].file = \"$D/figma/ui-spec/none.md\"" "none.md"
expect_init "apply kind 오류" 1 '.decisions[0].apply[0].kind = "file"' "map_row|token_row|asset"
expect_init "token_row op 오류" 1 '.decisions[1].apply[2].op = "append_issue"' "add|replace"
expect_init "token_row value 없음" 1 'del(.decisions[1].apply[2].value)' "figma_name/token/value/evidence"
expect_init "token_row replace에 expect 없음" 1 '.decisions[1].apply[2].op = "replace"' "expect"
expect_init "token_row 값에 파이프" 1 '.decisions[1].apply[2].token = "a | b"' "파이프"
expect_init "token_row figma_name에 백틱" 1 '.decisions[1].apply[2].figma_name = "a`b"' "백틱"
expect_init "map_row op 오류" 1 '.decisions[0].apply[0].op = "zap"' "add|append_issue|replace"
expect_init "replace에 expect 없음" 1 '.decisions[0].apply[0].op = "replace"' "expect"
expect_init "replace expect에 파이프" 1 '.decisions[0].apply[0] += {op:"replace", expect:"a | b"}' "파이프"
expect_init "ui_specs 화면이 figma.screens에 없음" 1 '.ui_specs[0].screens += ["S9"]' "ui_specs 화면 S9가 figma.screens에 없음"
expect_init "map_row add에 component 없음" 1 'del(.decisions[0].apply[0].component)' "component/evidence"
expect_init "append_issue에 issue 없음" 1 'del(.decisions[1].apply[1].issue)' "issue"
expect_init "map_row note에 파이프" 1 '.decisions[0].apply[0].note = "a | b"' "파이프"
expect_init "map_row data_name에 백틱" 1 '.decisions[0].apply[0].data_name = "a`b"' "백틱"
expect_init "asset source가 .impl-spec 밖" 1 '.decisions[1].apply[0].source = "tmp/ico_a.xml"' ".impl-spec/"
expect_init "asset source 파일 없음" 1 ".decisions[1].apply[0].source = \"$D/figma/assets/none.xml\"" "none.xml"
expect_init "asset target이 레포 밖" 1 '.decisions[1].apply[0].target = "../x/ico_a.xml"' "레포 상대 경로"
expect_init "ui_specs 항목에 file 없음" 1 'del(.ui_specs[0].file)' "file 없음"
expect_init "asset source가 .. 로 탈출" 1 '.decisions[1].apply[0].source = ".impl-spec/../CLAUDE.md"' ".impl-spec/"
expect_init "apply가 배열 아님" 1 '.decisions[0].apply = "x"' "배열"
expect_init "apply 항목이 객체 아님" 1 '.decisions[0].apply = ["x"]' "객체"
expect_init "타입 오류는 exit 1" 1 '.decisions[1].apply[0].target = 5' "입력 형식 오류"
expect_init "visual todo인데 visual_cases 없음" 1 'del(.visual_cases)' "visual todo T1에 target 케이스 없음"
expect_init "visual todo에 회귀 케이스만 있음" 1 '.visual_cases |= map(.kind = "regression")' "visual todo T1에 target 케이스 없음"
expect_init "visual_cases todo_id가 todo에 없음" 1 '.visual_cases[1].todo_id = "T9"' "T9"
expect_init "visual_cases kind 오류" 1 '.visual_cases[1].kind = "extra"' "target|regression"
expect_init "visual_cases 필드 누락" 1 'del(.visual_cases[1].expect)' "id/todo_id/scenario/condition/expect"
expect_init "visual_cases id 중복" 1 '.visual_cases[1].id = "V1"' "id 중복: V1"
expect_init "visual_cases가 배열 아님" 1 '.visual_cases = "x"' "visual_cases는 배열"
expect_init "기존 규칙 유지 — open_questions 남음" 1 '.open_questions = ["q"]' "open_questions"

# clean — pr_created에서만, 이 이슈 파일만, 남은 이슈가 없으면 디렉토리째
rm -f "$STATE"
$S init spec $N < "$T/base.json" > /dev/null 2>&1 || bad "clean 준비: init 실패"
mkdir -p .impl-spec/spec-$N.figma/screens .impl-spec/spec-$N.visual
touch .impl-spec/spec-$N.issue.json .impl-spec/spec-$N.research.spec.md .impl-spec/spec-$N.brief.md .impl-spec/spec-$N.figma/screens/a.png
$S clean spec $N > /dev/null 2>&1; [ $? = 3 ] && [ -f "$STATE" ] && ok "clean: analyzed면 거부하고 남김" || bad "clean: analyzed인데 지움"

jq '.stage = "pr_created" | .pr_url = "https://example/pull/1"' "$STATE" > "$T/s" && cp "$T/s" "$STATE"
echo '{}' > .impl-spec/spec-990002.json; echo '{}' > .impl-spec/spec-${N}0.json
$S clean spec $N > "$T/out" 2> "$T/err" || bad "clean 실패: $(cat "$T/err")"
[ -z "$(ls -d .impl-spec/spec-$N.* 2>/dev/null)" ] && ok "clean: 이 이슈 파일 전부 삭제" || bad "clean: 남음 $(ls -d .impl-spec/spec-$N.*)"
[ -f .impl-spec/spec-990002.json ] && [ -f .impl-spec/spec-${N}0.json ] && ok "clean: 다른 이슈(접두사 같은 번호 포함)는 남김" || bad "clean: 다른 이슈까지 지움"

rm .impl-spec/spec-990002.json .impl-spec/spec-${N}0.json
$S init spec $N < "$T/base.json" > /dev/null 2>&1 || bad "clean 준비: 재init 실패"
jq '.stage = "pr_created" | .pr_url = "https://example/pull/1"' "$STATE" > "$T/s" && cp "$T/s" "$STATE"
$S clean spec $N > /dev/null 2>&1 && [ ! -e .impl-spec ] && ok "clean: 남은 이슈 없으면 .impl-spec/ 삭제" || bad "clean: .impl-spec/ 남음"

[ $FAIL = 0 ] && echo "ALL PASS" || { echo "FAILED"; exit 1; }
