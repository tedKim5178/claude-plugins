#!/bin/bash
# apply-ui-decisions.py 테스트. 실행: scripts/tests/apply-ui-decisions.test.sh
# 임시 레포(fixture 프로필)에서 대응표·상태 파일을 .impl-spec/ 안에 만들고, 프로필은 IMPL_PROFILE로 그 대응표를 가리키게 한다.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
A="$SCRIPTS/apply-ui-decisions.py"
N=990002
D=.impl-spec/t$N
STATE=.impl-spec/spec-$N.json
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
make_repo "$T/repo" && cd "$T/repo"
FAIL=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; FAIL=1; }

mkdir -p "$D"
cat > "$D/map.md" <<'EOF'
# test map

| Figma 컴포넌트 (data-name) | 프로젝트 | 비고 | 근거 |
|---|---|---|---|
| `top_navigation` | `AppTopBar` | 뒤로가기 | A.kt:1 |
| `os/ios/statusbar*`, `bottom_bar` | 구현 대상 아님 | 시스템 UI | — |

## 표에 없을 때 찾는 법
EOF
cat > "$D/tokens.md" <<'EOF'
# test tokens

| Figma 변수 | 토큰 | 값 | 근거 |
|---|---|---|---|
| `text/body` | `Semantic.Text.Body` | #5E5F66 | S.kt:1 |

## 메모
EOF
sed -e "/^## UI 컴포넌트\$/,/^## /s#^- map: .*#- map: $D/map.md#" \
    -e "/^## 디자인 토큰\$/,/^## /s#^- map: .*#- map: $D/tokens.md#" \
    .claude/impl-chain/profile.md > "$T/profile.md"
export IMPL_PROFILE="$T/profile.md"

state() { # $1 = apply 배열 JSON
  jq -n --argjson a "$1" '{stage:"analyzed", decisions:[{question:"q", answer:"a", by:"user", apply:$a}]}' > "$STATE"
}
run() { # $1=설명 $2=기대 exit $3=(선택) stdout에 있어야 할 문구
  python3 $A spec $N > "$T/out" 2> "$T/err"; local got=$?
  if [ "$got" != "$2" ]; then bad "$1 (exit $got, 기대 $2) $(cat "$T/out" "$T/err" | head -5)"; return; fi
  if [ -n "${3:-}" ] && ! grep -q -- "$3" "$T/out"; then bad "$1 — 출력에 '$3' 없음: $(head -5 "$T/out")"; return; fi
  ok "$1"
}

echo "map_row add"
state '[{"kind":"map_row","op":"add","data_name":"Button_CTA_Bottom","component":"CommonButton(XLarge)","note":"n","evidence":"B.kt:2"}]'
run "새 행 추가" 0 "ADDED map_row Button_CTA_Bottom"
grep -qx '| `Button_CTA_Bottom` | CommonButton(XLarge) | n | B.kt:2 |' "$D/map.md" && ok "행 형식" || bad "행 형식: $(grep Button_CTA "$D/map.md")"
[ "$(grep -n 'Button_CTA_Bottom' "$D/map.md" | cut -d: -f1)" = 7 ] && ok "표 끝(빈 줄 앞)에 삽입" || bad "표 끝(빈 줄 앞)에 삽입: $(cat -n "$D/map.md")"
grep -q "CHANGED $D/map.md" "$T/out" && ok "CHANGED 출력" || bad "CHANGED 출력: $(cat "$T/out")"
run "다시 실행하면 SKIP" 0 "SKIP map_row Button_CTA_Bottom"
[ "$(grep -c 'Button_CTA_Bottom' "$D/map.md")" = 1 ] && ok "중복 추가 없음" || bad "중복 추가 없음"
state '[{"kind":"map_row","op":"add","data_name":"Button_CTA_Bottom","component":"CtaButton","evidence":"C.kt:3"}]'
run "같은 data-name 다른 컴포넌트 → CONFLICT" 3 "CONFLICT map_row Button_CTA_Bottom"
state '[{"kind":"map_row","op":"add","data_name":"os/ios/statusbar_dark","component":"구현 대상 아님","evidence":"—"}]'
run "glob 행과 일치 → SKIP" 0 "SKIP map_row os/ios/statusbar_dark"

echo "map_row append_issue"
state '[{"kind":"map_row","op":"append_issue","data_name":"top_navigation","issue":"spec-1234"}]'
run "이슈 덧붙임" 0 "UPDATED map_row top_navigation"
grep -qx '| `top_navigation` | `AppTopBar` | 뒤로가기; 사용 이슈: spec-1234 | A.kt:1 |' "$D/map.md" && ok "비고 형식" || bad "비고 형식: $(grep top_navigation "$D/map.md")"
run "같은 이슈 다시 → SKIP" 0 "SKIP map_row top_navigation"
state '[{"kind":"map_row","op":"append_issue","data_name":"top_navigation","issue":"spec-77"}]'
run "두 번째 이슈" 0 "UPDATED"
grep -q '사용 이슈: spec-1234, spec-77 |' "$D/map.md" && ok "이슈 누적" || bad "이슈 누적: $(grep top_navigation "$D/map.md")"
state '[{"kind":"map_row","op":"append_issue","data_name":"no_such","issue":"spec-77"}]'
run "행 없음 → CONFLICT" 3 "CONFLICT map_row no_such"

echo "asset"
printf '<vector/>\n' > "$D/ico_a.xml"
state "[{\"kind\":\"asset\",\"figma_name\":\"ico/ico_a\",\"source\":\"$D/ico_a.xml\",\"target\":\"$D/out/drawable/ico_a.xml\"}]"
run "복사" 0 "COPIED asset $D/out/drawable/ico_a.xml"
cmp -s "$D/ico_a.xml" "$D/out/drawable/ico_a.xml" && ok "내용 같음" || bad "내용 같음"
grep -q "CHANGED $D/out/drawable/ico_a.xml" "$T/out" && ok "asset CHANGED 출력" || bad "asset CHANGED 출력"
run "다시 실행하면 SKIP" 0 "SKIP asset"
printf '<vector other/>\n' > "$D/out/drawable/ico_a.xml"
run "다른 내용 파일 있음 → CONFLICT" 3 "CONFLICT asset"

echo "사전 검증·표 보호"
cp "$D/map.md" "$T/map.before"
printf '<vector/>\n' > "$D/ico_b.xml"
state "[{\"kind\":\"map_row\",\"op\":\"add\",\"data_name\":\"Pre_Check\",\"component\":\"X\",\"evidence\":\"E:1\"},{\"kind\":\"asset\",\"figma_name\":\"n\",\"source\":\"$D/none.xml\",\"target\":\"$D/out/n.xml\"}]"
run "source 없는 asset → 사전 검증 exit 1" 1
cmp -s "$D/map.md" "$T/map.before" && ok "대응표 변경 없음" || bad "대응표 변경 없음"
! grep -q ADDED "$T/out" && ok "ADDED 출력 없음" || bad "ADDED 출력 없음"
state '[{"kind":"map_row","op":"add","data_name":"Pipe_X","component":"A | B","evidence":"E:1"}]'
run "component에 파이프 → exit 1" 1
state '[{"kind":"map_row","op":"add","data_name":"Tick`X","component":"A","evidence":"E:1"}]'
run "data_name에 백틱 → exit 1" 1
state '[{"kind":"map_row","op":"add","data_name":"No_Comp","evidence":"E:1"}]'
run "add에 component 없음 → exit 1" 1
state '[{"kind":"map_row","op":"zap","data_name":"X"}]'
run "op 오류 → exit 1" 1
cmp -s "$D/map.md" "$T/map.before" && ok "거부 후에도 대응표 그대로" || bad "거부 후에도 대응표 그대로"

echo "append_issue 비고 처리"
printf '| `Empty_Note` | `Comp` | — | F.kt:1 |\n| `Ref_Note` | `Comp2` | spec-7 참고 | G.kt:1 |\n' > "$T/rows"
sed -i.bak "/^| \`os\/ios/r $T/rows" "$D/map.md"
state '[{"kind":"map_row","op":"append_issue","data_name":"Empty_Note","issue":"spec-9"}]'
run "비고 — → 사용 이슈만" 0 "UPDATED map_row Empty_Note"
grep -qx '| `Empty_Note` | `Comp` | 사용 이슈: spec-9 | F.kt:1 |' "$D/map.md" && ok "— 비고 처리" || bad "— 비고 처리: $(grep Empty_Note "$D/map.md")"
state '[{"kind":"map_row","op":"append_issue","data_name":"Ref_Note","issue":"spec-7"}]'
run "비고에 이슈명만 있고 마커 없음 → UPDATED" 0 "UPDATED map_row Ref_Note"
grep -qx '| `Ref_Note` | `Comp2` | spec-7 참고; 사용 이슈: spec-7 | G.kt:1 |' "$D/map.md" && ok "마커 이후만 검사" || bad "마커 이후만 검사: $(grep Ref_Note "$D/map.md")"

echo "map_row replace"
printf '| `Button` (XS, 라운드), `Btn_Small` | CtaButton 또는 CommonButton | 노트 | H.kt:1 |\n' > "$T/rows2"
sed -i.bak "/^| \`os\/ios/r $T/rows2" "$D/map.md"
state '[{"kind":"map_row","op":"replace","data_name":"Btn_Small","component":"CommonButton(XS)","evidence":"I.kt:2","expect":"CtaButton 또는 CommonButton"}]'
run "expect 일치 → 행 교체" 0 "REPLACED map_row Btn_Small"
grep -qx '| `Button` (XS, 라운드), `Btn_Small` | CommonButton(XS) | 노트 | I.kt:2 |' "$D/map.md" && ok "첫 칸·비고 유지, 나머지 교체" || bad "첫 칸·비고 유지: $(grep Btn_Small "$D/map.md")"
grep -q "CHANGED $D/map.md" "$T/out" && ok "replace CHANGED 출력" || bad "replace CHANGED 출력: $(cat "$T/out")"
run "다시 실행하면 SKIP" 0 "SKIP map_row Btn_Small"
[ "$(grep -c 'Btn_Small' "$D/map.md")" = 1 ] && ok "행 하나 유지" || bad "행 하나 유지"
state '[{"kind":"map_row","op":"replace","data_name":"Button_CTA_Bottom","component":"CtaButton","note":"m","evidence":"C.kt:3","expect":"CommonButton(XLarge)"}]'
run "note 지정 교체" 0 "REPLACED map_row Button_CTA_Bottom"
grep -qx '| `Button_CTA_Bottom` | CtaButton | m | C.kt:3 |' "$D/map.md" && ok "replace 행 형식" || bad "replace 행 형식: $(grep Button_CTA "$D/map.md")"
cp "$D/map.md" "$T/map.before2"
state '[{"kind":"map_row","op":"replace","data_name":"Button_CTA_Bottom","component":"X","evidence":"E:1","expect":"CommonButton(XLarge)"}]'
run "expect 불일치 → CONFLICT" 3 "대응표가 그사이 바뀜"
cmp -s "$D/map.md" "$T/map.before2" && ok "CONFLICT 시 대응표 그대로" || bad "CONFLICT 시 대응표 그대로"
state '[{"kind":"map_row","op":"replace","data_name":"no_such","component":"X","evidence":"E:1","expect":"Y"}]'
run "replace 행 없음 → CONFLICT" 3 "CONFLICT map_row no_such"
state '[{"kind":"map_row","op":"replace","data_name":"Btn_Small","component":"X","evidence":"E:1"}]'
run "replace에 expect 없음 → exit 1" 1
state '[{"kind":"map_row","op":"replace","data_name":"Btn_Small","component":"X","evidence":"E:1","expect":"A | B"}]'
run "expect에 파이프 → exit 1" 1

echo "asset 검증 보강"
state "[{\"kind\":\"asset\",\"figma_name\":\"ico/ico_a\",\"source\":\"$D/ico_a.xml\",\"target\":\"../x.xml\"}]"
run "asset target에 .. → exit 1" 1
state "[{\"kind\":\"asset\",\"figma_name\":\"ico/ico_a\",\"source\":\"$D/ico_a.xml\",\"target\":\"/tmp/x.xml\"}]"
run "asset target 절대 경로 → exit 1" 1
state "[{\"kind\":\"asset\",\"source\":\"$D/ico_a.xml\",\"target\":\"$D/out/drawable/ico_z.xml\"}]"
run "asset figma_name 없음 → exit 1" 1
state '[{"kind":"map_row","op":"add","data_name":5,"component":"A","evidence":"E:1"}]'
run "data_name이 문자열 아님 → exit 1" 1

echo "token_row"
state '[{"kind":"token_row","op":"add","figma_name":"text/attention","token":"Semantic.Text.Attention","value":"#476DCC","evidence":"spec-1 값 일치 (S.kt:9)"}]'
run "새 행 추가" 0 "ADDED token_row text/attention"
grep -qx '| `text/attention` | `Semantic.Text.Attention` | #476DCC | spec-1 값 일치 (S.kt:9) |' "$D/tokens.md" && ok "토큰 행 형식" || bad "토큰 행 형식: $(grep attention "$D/tokens.md")"
[ "$(grep -n 'text/attention' "$D/tokens.md" | cut -d: -f1)" = 6 ] && ok "표 끝에 삽입" || bad "표 끝에 삽입: $(cat -n "$D/tokens.md")"
grep -q "CHANGED $D/tokens.md" "$T/out" && ok "토큰 CHANGED 출력" || bad "토큰 CHANGED 출력: $(cat "$T/out")"
run "다시 실행하면 SKIP" 0 "SKIP token_row text/attention"
state '[{"kind":"token_row","op":"add","figma_name":"TEXT/Body","token":"Semantic.Text.Body","value":"#5E5F66","evidence":"x"}]'
run "대소문자 무시 일치 → SKIP" 0 "SKIP token_row TEXT/Body"
state '[{"kind":"token_row","op":"add","figma_name":"text/body","token":"Semantic.Text.Caption","value":"#5E5F66","evidence":"x"}]'
run "다른 토큰 → CONFLICT" 3 "CONFLICT token_row text/body"
state '[{"kind":"token_row","op":"add","figma_name":"text/foo","token":"없음 — 원시 값","value":"#123456","evidence":"사용자 결정 (spec-1)"}]'
run "원시 값 행" 0 "ADDED token_row text/foo"
grep -qx '| `text/foo` | 없음 — 원시 값 | #123456 | 사용자 결정 (spec-1) |' "$D/tokens.md" && ok "원시 값 행은 백틱 없음" || bad "원시 값 행: $(grep text/foo "$D/tokens.md")"
state '[{"kind":"token_row","op":"replace","figma_name":"text/body","token":"Semantic.Text.Secondary","value":"#2E2E33","evidence":"사용자 결정 (spec-2)","expect":"Semantic.Text.Body"}]'
run "replace 교체" 0 "REPLACED token_row text/body"
grep -qx '| `text/body` | `Semantic.Text.Secondary` | #2E2E33 | 사용자 결정 (spec-2) |' "$D/tokens.md" && ok "replace 행 형식" || bad "replace 행 형식: $(grep text/body "$D/tokens.md")"
run "replace 재실행 SKIP" 0 "SKIP token_row text/body"
state '[{"kind":"token_row","op":"replace","figma_name":"text/body","token":"X","value":"#000000","evidence":"e","expect":"Semantic.Text.Body"}]'
run "replace expect 불일치 → CONFLICT" 3 "CONFLICT token_row text/body"
state '[{"kind":"token_row","op":"replace","figma_name":"no/such","token":"X","value":"#000000","evidence":"e","expect":"Y"}]'
run "replace 행 없음 → CONFLICT" 3 "CONFLICT token_row no/such"
cp "$D/tokens.md" "$T/tokens.before"
state '[{"kind":"token_row","op":"add","figma_name":"a/b","token":"A | B","value":"#000000","evidence":"e"}]'
run "토큰에 파이프 → exit 1" 1
state '[{"kind":"token_row","op":"add","figma_name":"a`b","token":"A","value":"#000000","evidence":"e"}]'
run "figma_name에 백틱 → exit 1" 1
state '[{"kind":"token_row","op":"add","figma_name":"a/b","token":"A","evidence":"e"}]'
run "value 없음 → exit 1" 1
state '[{"kind":"token_row","op":"replace","figma_name":"a/b","token":"A","value":"#0","evidence":"e"}]'
run "replace expect 없음 → exit 1" 1
state '[{"kind":"token_row","op":"append_issue","figma_name":"a/b"}]'
run "token_row op 오류 → exit 1" 1
cmp -s "$D/tokens.md" "$T/tokens.before" && ok "거부 후 토큰 대응표 그대로" || bad "거부 후 토큰 대응표 그대로"
state '[{"kind":"map_row","op":"add","data_name":"Mix_Comp","component":"C","evidence":"E:1"},{"kind":"token_row","op":"add","figma_name":"mix/color","token":"Semantic.Mix","value":"#111111","evidence":"e"}]'
run "map_row + token_row 섞임" 0 "ADDED token_row mix/color"
grep -q "ADDED map_row Mix_Comp" "$T/out" && ok "map_row도 반영" || bad "map_row도 반영: $(cat "$T/out")"

echo "헤더 공백 허용"
sed -i.bak 's/^| Figma 컴포넌트/|  Figma 컴포넌트/' "$D/map.md" && rm -f "$D/map.md.bak"
state '[{"kind":"map_row","op":"add","data_name":"Spaced_Header","component":"C","evidence":"E:1"}]'
run "헤더 앞 공백이 있어도 표를 찾음" 0 "ADDED map_row Spaced_Header"

echo "기타"
state '[]'
run "apply 없음" 0 "apply 없음"
rm -f "$STATE"
run "상태 파일 없음" 2

[ $FAIL = 0 ] && echo "ALL PASS" || { echo "FAILED"; exit 1; }
