#!/bin/bash
# merge-ui-results.py 테스트. 실행: scripts/tests/merge-ui-results.test.sh
set -uo pipefail
source "$(dirname "$0")/lib.sh"
M="$SCRIPTS/merge-ui-results.py"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
FAIL=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; FAIL=1; }
# $1=설명 $2=jq 식 (true여야 통과)
check() { if jq -e "$2" "$T/draft.json" > /dev/null 2>&1; then ok "$1"; else bad "$1 — $(jq -c "$2" "$T/draft.json" 2>&1 | head -c 200)"; fi; }

cat > "$T/draft.json" <<'EOF'
{
  "todo_items": [
    {"id": "T1", "figma_screens": ["S1"]},
    {"id": "T2", "figma_screens": ["S2"]},
    {"id": "T3", "figma_screens": ["S3"]},
    {"id": "T9", "figma_screens": []}
  ],
  "decisions": [{"key": "proto", "question": "p", "answer": "a", "by": "user", "todo_ids": []}],
  "open_questions": [{"key": "nav:back", "question": "뒤로가기?", "candidates": ["a"], "todo_ids": ["T1"]}],
  "ui_specs": []
}
EOF
AP() { echo "[{\"kind\":\"map_row\",\"op\":\"add\",\"data_name\":\"$1\",\"component\":\"$2\",\"evidence\":\"e\"}]"; }
cat > "$T/g1.json" <<EOF
{"group": "G1", "screens": ["S1"], "file": "ui/S1.md",
 "auto": [{"key": "component:A", "question": "A?", "answer": "CompA", "evidence": "e1", "apply": $(AP A CompA)}],
 "questions": [{"key": "component:Q", "question": "Q?", "candidates": ["x", "y"], "evidence": "eq1", "recommended_reason": "r1",
                "apply_by_answer": {"x": $(AP Q x), "y": $(AP Q y1)}}]}
EOF
cat > "$T/g2.json" <<EOF
{"group": "G2", "screens": ["S2"], "file": "ui/S2.md",
 "auto": [{"key": "component:A", "question": "A?", "answer": "CompA", "evidence": "e2", "apply": $(AP A CompA)},
          {"key": "token:B", "question": "B?", "answer": "Tok1", "evidence": "e", "apply": []}],
 "questions": [{"key": "component:Q", "question": "Q?", "candidates": ["y", "z"], "evidence": "eq2",
                "apply_by_answer": {"y": $(AP Q y2), "z": $(AP Q z)}}]}
EOF
cat > "$T/g3.json" <<EOF
{"group": "G3", "screens": ["S3"], "file": "ui/S3.md",
 "auto": [{"key": "token:B", "question": "B?", "answer": "Tok2", "evidence": "e", "apply": []}],
 "questions": []}
EOF

echo "병합"
python3 "$M" "$T/draft.json" "$T/g1.json" "$T/g2.json" "$T/g3.json" > "$T/out" 2>&1 || bad "실행 실패: $(cat "$T/out")"
check "ui_specs 3개" '.ui_specs | length == 3'
check "ui_specs 항목 형식" '.ui_specs[0] == {"group":"G1","screens":["S1"],"file":"ui/S1.md"}'
check "기존 decision 유지" '[.decisions[] | select(.key == "proto")] | length == 1'
check "같은 답 auto는 하나로 + todo 합집합" '[.decisions[] | select(.key == "component:A")] | length == 1 and .[0].todo_ids == ["T1","T2"] and .[0].by == "claude"'
check "auto에 ui_spec·evidence·apply" '.decisions[] | select(.key == "component:A") | .ui_spec == "ui/S1.md" and .evidence != null and (.apply | length) == 1'
check "답이 다른 auto는 decisions에서 빠짐" '[.decisions[] | select(.key == "token:B")] | length == 0'
check "답이 다른 auto는 질문으로" '[.open_questions[] | select(.key == "token:B")] | length == 1 and .[0].candidates == ["Tok1","Tok2"] and .[0].todo_ids == ["T2","T3"]'
check "같은 key 질문은 하나로" '[.open_questions[] | select(.key == "component:Q")] | length == 1'
check "후보 합집합 순서 유지" '.open_questions[] | select(.key == "component:Q") | .candidates == ["x","y","z"]'
check "apply_by_answer 병합 (같은 후보는 이어붙임)" '.open_questions[] | select(.key == "component:Q") | (.apply_by_answer.y | length) == 2 and (.apply_by_answer.x | length) == 1'
check "todo_ids 합집합" '.open_questions[] | select(.key == "component:Q") | .todo_ids == ["T1","T2"]'
check "recommended = 첫 후보" '.open_questions[] | select(.key == "component:Q") | .recommended == "x" and .recommended_reason == "r1"'
check "다른 그룹 파일은 ui_spec_also" '.open_questions[] | select(.key == "component:Q") | .ui_spec == "ui/S1.md" and .ui_spec_also == ["ui/S2.md"]'
check "기존 질문 유지" '[.open_questions[] | select(.key == "nav:back")] | length == 1'
grep -q "MERGED" "$T/out" && ok "요약 출력" || bad "요약 없음: $(cat "$T/out")"

echo "재실행 (같은 그룹 다시 병합)"
cp "$T/draft.json" "$T/before.json"
python3 "$M" "$T/draft.json" "$T/g1.json" "$T/g2.json" "$T/g3.json" > /dev/null 2>&1
if diff <(jq -S . "$T/before.json") <(jq -S . "$T/draft.json") > /dev/null; then ok "재실행해도 결과 같음"; else bad "재실행 결과 달라짐"; fi

echo "그룹 하나 재실행 — 그 그룹 결과만 교체"
cat > "$T/g1b.json" <<EOF
{"group": "G1", "screens": ["S1"], "file": "ui/S1.md",
 "auto": [{"key": "component:C", "question": "C?", "answer": "CompC", "evidence": "e", "apply": []}], "questions": []}
EOF
python3 "$M" "$T/draft.json" "$T/g1b.json" > /dev/null 2>&1
check "G1의 새 auto 추가" '[.decisions[] | select(.key == "component:C")] | length == 1'
check "G1이 기여한 todo는 A에서 빠짐" '.decisions[] | select(.key == "component:A") | .todo_ids == ["T2"] and .ui_spec == "ui/S2.md"'
check "G1이 기여한 후보 x는 Q에서 빠짐" '.open_questions[] | select(.key == "component:Q") | .candidates == ["y","z"] and .todo_ids == ["T2"] and .ui_spec == "ui/S2.md"'
check "ui_specs 여전히 3개" '.ui_specs | length == 3'

echo "형식 오류"
echo '{"group":"G","screens":["S1"]}' > "$T/bad.json"
python3 "$M" "$T/draft.json" "$T/bad.json" > /dev/null 2>&1 && bad "file 없는 결과를 받아들임" || ok "file 없는 결과는 exit 1"

echo
[ "$FAIL" = 0 ] && echo "ALL PASS" || { echo "FAILED"; exit 1; }
