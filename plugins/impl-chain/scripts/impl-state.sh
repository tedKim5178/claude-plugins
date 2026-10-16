#!/bin/bash
# impl-spec 체인 상태 파일 조작 도구. 규격: impl-chain references/impl-state-file.md
#
# 상태 파일은 이 스크립트로만 읽고 쓴다. md 안에서 jq를 손으로 짜지 않는다.
#
# Usage:
#   impl-state.sh path  <type> <number>             파일 경로 출력
#   impl-state.sh find  [--stage <stage>]           상태 파일 목록 (TSV: key stage branch updated_at title)
#   impl-state.sh init  <type> <number>  < json     analyzed 상태로 새로 기록 (필수 필드 검증)
#   impl-state.sh get   <type> <number> [jq-filter] 값 조회 (기본: 전체)
#   impl-state.sh merge <type> <number>  < json     객체를 깊은 병합 (stage 불가, 배열은 통째로 교체됨)
#   impl-state.sh todo  <type> <number> <id> <done|deferred|pending> [note]   todo 항목 하나의 상태 갱신
#   impl-state.sh add-commit <type> <number> [sha]  commits 배열에 추가 (기본: HEAD)
#   impl-state.sh stage <type> <number> <stage>     단계 전이 (조건 검증)
#   impl-state.sh check-branch <type> <number>      현재 브랜치가 상태 파일의 branch와 같은지
#
# type: spec   (파일 이름 spec-4895.json — 이슈 종류를 키에 남겨 둔다)
# 종료 코드: 0 성공, 1 사용법/검증 실패, 2 파일 없음, 3 단계 전이 불가

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
DIR="$ROOT/.impl-spec"

die() { echo "ERROR: $1" >&2; exit "${2:-1}"; }

key_of() {
  [ "$1" = spec ] || die "type은 spec: '$1'"
  [[ "$2" =~ ^[0-9]+$ ]] || die "number는 숫자: '$2'"
  echo "$1-$2"
}

file_of() { local k; k=$(key_of "$1" "$2") || exit 1; echo "$DIR/$k.json"; }   # 잘못된 type·number면 exit 1 (빈 키 경로로 진행하지 않는다)

require_file() {
  local f; f="$(file_of "$1" "$2")" || exit 1   # $( ) 안에서는 set -e가 안 걸린다
  [ -f "$f" ] || die "상태 파일 없음: $f" 2
  echo "$f"
}

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

write_atomic() { # $1=file, stdin=json
  local tmp="$1.tmp"
  cat > "$tmp"
  jq -e . "$tmp" > /dev/null || { rm -f "$tmp"; die "잘못된 JSON — 기록하지 않음"; }
  mv "$tmp" "$1"
}

# analyzed 단계에 들어가기 위한 필수 조건. 여기서 빠진 값은 뒤 단계에서 추론으로 메워진다.
validate_analyzed() { # stdin=json → 문제 목록 출력
  jq -r '
    def need(k): if (has(k) | not) or .[k] == null or .[k] == "" then "필수 필드 누락: \(k)" else empty end;
    need("issue_type"), need("issue_number"), need("issue_title"), need("issue_url"),
    need("base_branch"), need("branch"), need("implementation_direction"), need("research_files"),
    (if has("compile_task") | not then "필드 누락: compile_task (모르면 null)" else empty end),
    (if has("test_task") | not then "필드 누락: test_task (없으면 null)" else empty end),
    (if (.files_to_modify | type) != "array" then "files_to_modify는 배열이어야 함" else empty end),
    (if (.todo_items | type) != "array" or (.todo_items | length) == 0 then "todo_items가 비어 있음"
     else (.todo_items[] | select((.id // "") == "" or (.desc // "") == "" or (.source // "") == ""
                                  or (.acceptance // "") == "" or ((.verify // "") | IN("unit","visual","manual") | not))
           | "todo_items 항목 불완전 (id/desc/source/acceptance/verify=unit|visual|manual): \(.id // .desc // "?")")
     end),
    (if (.open_questions // [] | length) > 0
     then "미해결 open_questions \(.open_questions | length)개 — 전부 decisions로 해소한 뒤 기록" else empty end),
    (if (.size // "") | IN("small","large") | not then "size는 small 또는 large" else empty end),
    # 화이트라벨 앱 선택 (프로필 빌드.apps가 있을 때만) — 이름 배열, 비어 있지 않고 겹치지 않음
    (if has("apps") and .apps != null then
       (if (.apps | type) != "array" or (.apps | length) == 0 then "apps는 앱 이름 배열 (1개 이상)"
        elif ([.apps[] | select(type != "string" or test("^[A-Za-z0-9._-]+$") | not)] | length) > 0 then "apps 항목은 프로필 빌드.apps의 이름: \(.apps)"
        elif (.apps | length) != (.apps | unique | length) then "apps에 같은 앱이 두 번: \(.apps)"
        else empty end)
     else empty end),
    # 형식(접두사·slug 규칙)은 프로필 git.branch_format이 정한다. 여기서는 "{접두사}/{이름}" 꼴인지만 본다 — 레포 고유 규칙을 넣지 않는다.
    (if (.branch // "") | test("^[A-Za-z0-9._-]+/[A-Za-z0-9._/-]+$") | not then "branch 형식 오류 ({접두사}/{이름} 꼴이어야 함): \(.branch)" else empty end),
    (if (.figma.status // "") | IN("ok","none") | not
     then "figma.status는 ok 또는 none (BLOCKED면 분석을 멈추고 사용자가 해결해야 함): \(.figma.status // "없음")" else empty end),
    (if .figma.status == "ok" then
       ([.figma.screens[]?.id] as $ids
        | (if ($ids | length) == 0 then "figma.status=ok인데 figma.screens가 비어 있음" else empty end),
          (.todo_items[] | select(.verify == "visual")
           | if ((.figma_screens // []) | length) == 0 then "visual todo \(.id)에 figma_screens 없음"
             else (.figma_screens[] as $s | select(($ids | index($s)) == null) | "todo \(.id)의 figma_screens \($s)가 figma.screens에 없음") end))
     else empty end),
    # analyze Step 4-1: visual todo의 화면은 전부 어떤 ui-spec이 덮어야 한다
    (if .figma.status == "ok" and any(.todo_items[]; .verify == "visual") then
       ([.ui_specs[]?.screens[]?] as $covered
        | if (.ui_specs // [] | length) == 0 then "visual todo가 있는데 ui_specs 없음 — analyze Step 4-1(figma-ui-spec) 필요"
          else (.todo_items[] | select(.verify == "visual") | .id as $id | (.figma_screens // [])[] as $s
                | select(($covered | index($s)) == null) | "visual todo \($id)의 화면 \($s)가 ui_specs에 없음") end)
     else empty end),
    (if .figma.status == "ok" then
       ([.figma.screens[]?.id] as $ids | .ui_specs[]?.screens[]? as $s | select(($ids | index($s)) == null) | "ui_specs 화면 \($s)가 figma.screens에 없음")
     else empty end),
    # analyze Step 4-2: 화면 확인 케이스 — visual-verifier가 케이스를 즉석에서 정하지 않도록 승인 전에 확정한다
    (if has("visual_cases") and (.visual_cases | type) != "array" then "visual_cases는 배열이어야 함"
     else
       ([.todo_items[]?.id] as $tids
        | (.visual_cases // []) as $vc
        | ($vc[] | select(type != "object" or (.id // "") == "" or (.todo_id // "") == "" or (.scenario // "") == ""
                          or (.condition // "") == "" or (.expect // "") == "")
           | "visual_cases 항목 불완전 (id/todo_id/scenario/condition/expect): \(if type == "object" then (.id // "?") else "?" end)"),
          ($vc[] | select(type == "object") | select((.kind // "") | IN("target","regression") | not)
           | "visual_cases kind는 target|regression: \(.id // "?")"),
          ($vc[] | select(type == "object" and (.todo_id // "") != "") | select(.todo_id as $t | ($tids | index($t)) == null)
           | "visual_cases \(.id // "?")의 todo_id \(.todo_id)가 todo_items에 없음"),
          ($vc | map(select(type == "object") | .id // empty) | group_by(.) | .[] | select(length > 1) | "visual_cases id 중복: \(.[0])"),
          (.todo_items[]? | select(.verify == "visual") | .id as $id
           | select(any($vc[]; type == "object" and .todo_id == $id and .kind == "target") | not)
           | "visual todo \($id)에 target 케이스 없음 — analyze Step 4-2(visual_cases) 필요"))
     end),
    # start-work Step 2-1이 반영할 항목 — 형식이 틀리면 반영 스크립트가 중간에 멈춘다
    (.ui_specs[]? | select((.file // "") == "") | "ui_specs 항목에 file 없음: \(.screens // [] | join(","))"),
    (.decisions[]? | select(type == "object" and has("apply") and .apply != null and (.apply | type) != "array") | "decision apply는 배열이어야 함: \(.question // "?")"),
    (.decisions[]? | select(type == "object") | (.apply // []) | select(type == "array") | .[] | select(type != "object") | "apply 항목은 객체여야 함"),
    (.decisions[]? | select(type == "object") | (.apply // []) | select(type == "array") | .[] | select(type == "object") |
      if .kind == "map_row" then
        (if (.op // "") | IN("add","append_issue","replace") | not then "apply map_row op는 add|append_issue|replace: \(.data_name // "?")" else empty end),
        (if (.data_name // "") == "" then "apply map_row data_name 없음" else empty end),
        (if .op == "add" and ((.component // "") == "" or (.evidence // "") == "") then "apply map_row add에 component/evidence 없음: \(.data_name // "?")" else empty end),
        (if .op == "replace" and ((.component // "") == "" or (.evidence // "") == "" or (.expect // "") == "") then "apply map_row replace에 component/evidence/expect 없음: \(.data_name // "?")" else empty end),
        (if ([.data_name, .component, .note, .evidence, .expect] | map(. // "" | tostring | contains("|")) | any) or ((.data_name // "") | tostring | contains("`")) then "apply map_row 값에 파이프 문자 또는 data_name에 백틱 사용 불가: \(.data_name // "?")" else empty end),
        (if .op == "append_issue" and (.issue // "") == "" then "apply map_row append_issue에 issue 없음: \(.data_name // "?")" else empty end)
      elif .kind == "token_row" then
        (if (.op // "") | IN("add","replace") | not then "apply token_row op는 add|replace: \(.figma_name // "?")" else empty end),
        (if (.figma_name // "") == "" or (.token // "") == "" or (.value // "") == "" or (.evidence // "") == "" then "apply token_row 필드 누락 (figma_name/token/value/evidence): \(.figma_name // "?")" else empty end),
        (if .op == "replace" and (.expect // "") == "" then "apply token_row replace에 expect 없음: \(.figma_name // "?")" else empty end),
        (if ([.figma_name, .token, .value, .evidence, .expect] | map(. // "" | tostring | contains("|")) | any) or ((.figma_name // "") | tostring | contains("`")) then "apply token_row 값에 파이프 문자 또는 figma_name에 백틱 사용 불가: \(.figma_name // "?")" else empty end)
      elif .kind == "asset" then
        (if (.figma_name // "") == "" or (.source // "") == "" or (.target // "") == "" then "apply asset 필드 누락 (figma_name/source/target): \(.figma_name // .target // "?")" else empty end),
        (if (.source // "") != "" and ((.source | startswith(".impl-spec/") | not) or (.source | test("(^|/)\\.\\.(/|$)"))) then "apply asset source는 .impl-spec/ 안이어야 함: \(.source // "")" else empty end),
        (if (.target // "") | test("^/|(^|/)\\.\\.(/|$)") then "apply asset target은 레포 상대 경로여야 함: \(.target)" else empty end)
      else "apply kind는 map_row|token_row|asset: \(.kind // "없음")" end)
  '
}

cmd="${1:-}"; shift || true
case "$cmd" in
  path)
    [ $# -eq 2 ] || die "usage: path <type> <number>"
    file_of "$1" "$2"
    ;;

  find)
    want=""
    if [ "${1:-}" = "--stage" ]; then want="${2:?--stage 값 필요}"; fi
    [ -d "$DIR" ] || exit 0
    for f in "$DIR"/*.json; do
      [ -e "$f" ] || continue
      [[ "$(basename "$f")" =~ ^spec-[0-9]+\.json$ ]] || continue   # issue.json, draft.json 제외
      jq -r --arg k "$(basename "$f" .json)" --arg want "$want" '
        select($want == "" or .stage == $want)
        | [$k, .stage, .branch, .updated_at, .issue_title] | @tsv' "$f"
    done | sort -t$'\t' -k4 -r
    ;;

  init)
    [ $# -eq 2 ] || die "usage: init <type> <number> < json"
    f="$(file_of "$1" "$2")"
    if [ -f "$f" ]; then
      cur="$(jq -r .stage "$f")"
      [ "$cur" = "analyzed" ] || die "이미 $cur 단계인 상태 파일이 있음: $f — 재분석하려면 사용자 확인 후 파일을 직접 옮길 것" 3
      jq -e '(.commits // []) | length == 0' "$f" > /dev/null \
        || die "구현 커밋이 기록된 상태 파일을 덮어쓸 수 없음: $f — 사용자 확인 필요" 3
    fi
    input="$(cat)"
    jq -e 'type == "object"' <<< "$input" > /dev/null 2>&1 || die "입력이 JSON 객체가 아님"
    input="$(jq --arg t "$1" --argjson n "$2" '. + {issue_type:$t, issue_number:$n}' <<< "$input")"
    problems="$(validate_analyzed <<< "$input")" \
      || die "입력 형식 오류 — 필드 타입이 규격과 다름 (위 jq 오류 참고). 규격: impl-chain references/impl-state-file.md"
    while IFS= read -r p; do [ -n "$p" ] || continue
      [ -f "$ROOT/$p" ] || problems="$problems"$'\n'"research 파일 없음: $p"
    done < <(jq -r '.research_files // [] | .[]' <<< "$input")
    while IFS= read -r p; do [ -n "$p" ] || continue
      [ -f "$ROOT/$p" ] || problems="$problems"$'\n'"ui_specs 파일 없음: $p"
    done < <(jq -r '.ui_specs // [] | .[].file // empty' <<< "$input")
    while IFS= read -r p; do [ -n "$p" ] || continue
      [ -f "$ROOT/$p" ] || problems="$problems"$'\n'"apply asset source 파일 없음 (시험 변환 결과): $p"
    done < <(jq -r '[.decisions[]? | select(type == "object") | (.apply // []) | select(type == "array") | .[] | select(type == "object" and .kind == "asset") | .source // empty | select(type == "string")] | .[]' <<< "$input" 2>/dev/null)
    problems="$(sed '/^$/d' <<< "$problems")"
    [ -z "$problems" ] || die $'검증 실패 — 기록하지 않음:\n'"$problems"
    mkdir -p "$DIR"
    jq --arg now "$(now)" '. + {schema:3, stage:"analyzed", commits:[], verification:{}, pr_url:null, updated_at:$now}' \
      <<< "$input" | write_atomic "$f"
    echo "$f"
    ;;

  get)
    [ $# -ge 2 ] || die "usage: get <type> <number> [jq-filter]"
    f="$(require_file "$1" "$2")"
    jq -r "${3:-.}" "$f"
    ;;

  merge)
    [ $# -eq 2 ] || die "usage: merge <type> <number> < json"
    f="$(require_file "$1" "$2")"
    patch="$(cat)"
    jq -e 'type == "object"' <<< "$patch" > /dev/null 2>&1 || die "입력이 JSON 객체가 아님"
    jq -e 'has("stage") | not' <<< "$patch" > /dev/null || die "stage는 merge로 바꿀 수 없음 — stage 명령 사용"
    jq --argjson p "$patch" --arg now "$(now)" '. * $p | .updated_at = $now' "$f" | write_atomic "$f"
    ;;

  todo)
    [ $# -ge 4 ] || die "usage: todo <type> <number> <id> <done|deferred|pending> [note]"
    f="$(require_file "$1" "$2")"
    case "$4" in done|deferred|pending) ;; *) die "status는 done|deferred|pending" ;; esac
    jq -e --arg id "$3" 'any(.todo_items[]; .id == $id)' "$f" > /dev/null || die "todo id 없음: $3"
    jq --arg id "$3" --arg st "$4" --arg note "${5:-}" --arg now "$(now)" '
      .todo_items |= map(if .id == $id then .status = $st | (if $note != "" then .note = $note else . end) else . end)
      | .updated_at = $now' "$f" | write_atomic "$f"
    ;;

  add-commit)
    [ $# -ge 2 ] || die "usage: add-commit <type> <number> [sha]"
    f="$(require_file "$1" "$2")"
    sha="$(git -C "$ROOT" rev-parse --short "${3:-HEAD}")"
    jq --arg c "$sha" --arg now "$(now)" '.commits = ((.commits // []) + [$c] | unique) | .updated_at = $now' "$f" | write_atomic "$f"
    echo "$sha"
    ;;

  stage)
    [ $# -eq 3 ] || die "usage: stage <type> <number> <analyzed|implemented|pr_created>"
    f="$(require_file "$1" "$2")"
    cur="$(jq -r .stage "$f")"; next="$3"
    case "$cur>$next" in
      "analyzed>implemented")
        miss="$(jq -r '
          (if (.commits | length) == 0 then "commits 비어 있음" else empty end),
          (if .verification.compile != "pass" then "verification.compile != pass" else empty end),
          (if (.verification.tests // "") | test("^(pass|none)") | not then "verification.tests는 pass… 또는 none — 사유 여야 함" else empty end),
          (if (.verification.review.quality // "") != "PASS" then "verification.review.quality != PASS" else empty end),
          (if (.verification.review.spec // "") != "PASS" then "verification.review.spec != PASS" else empty end),
          (.todo_items[] | .id as $id | select((.status // "") | IN("done","deferred") | not) | "todo \($id) status 미완료")
        ' "$f")"
        [ -z "$miss" ] || die $'implemented로 전이 불가:\n'"$miss" 3
        ;;
      "implemented>pr_created")
        jq -e '(.pr_url // "") != ""' "$f" > /dev/null || die "pr_url 없음 — 먼저 merge로 기록" 3
        ;;
      *) die "허용되지 않는 전이: $cur → $next" 3 ;;
    esac
    jq --arg s "$next" --arg now "$(now)" '.stage = $s | .updated_at = $now' "$f" | write_atomic "$f"
    echo "$cur → $next"
    ;;

  check-branch)
    [ $# -eq 2 ] || die "usage: check-branch <type> <number>"
    f="$(require_file "$1" "$2")"
    want="$(jq -r .branch "$f")"; have="$(git -C "$ROOT" branch --show-current)"
    [ "$want" = "$have" ] || die "현재 브랜치($have) ≠ 상태 파일 branch($want)" 3
    echo "$have"
    ;;

  *)
    sed -n '2,18p' "$0" >&2
    exit 1
    ;;
esac
