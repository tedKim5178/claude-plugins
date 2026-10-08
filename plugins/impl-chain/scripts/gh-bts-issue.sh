#!/bin/bash
# BTS 이슈 데이터 수집 — 공용 bts 어댑터 (GitHub + gh)
# 계약: impl-chain references/impl-profile-spec.md "bts 어댑터" (프로필 `이슈.bts_adapter`)
# 프로필에서 읽는 값: 이슈.bts_repo, 이슈.bts_exclude_labels(선택), 이슈.bts_project_status(선택)
#
# Usage:
#   fetch-bts-issue.sh list        → JSON 배열 [{number,title,state,labels,updatedAt,projectItems}] (작업 가능한 내 이슈, 최근순)
#   fetch-bts-issue.sh fetch <n>   → JSON {issue, comments}  (issue.url 포함)
#
# list 필터 (프로필 값, 쉼표 구분 — 없으면 그 필터를 쓰지 않는다):
#   - bts_exclude_labels: 이 라벨이 하나라도 붙은 이슈 제외
#   - bts_project_status: 프로젝트 상태가 이 중 하나인 이슈만. projectItems 조회에 gh 토큰의 read:project 권한 필요
#     (`gh auth refresh -s read:project`)

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO=$("$HERE/impl-profile.sh" get 이슈.bts_repo) || exit 1
# 쉼표 구분 → JSON 배열 (키가 없으면 빈 배열)
csv_json() { "$HERE/impl-profile.sh" get "$1" 2>/dev/null | jq -Rc 'split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(. != ""))' || echo '[]'; }
EXCLUDE=$(csv_json 이슈.bts_exclude_labels); [ -n "$EXCLUDE" ] || EXCLUDE='[]'
STATUS=$(csv_json 이슈.bts_project_status);  [ -n "$STATUS" ] || STATUS='[]'
CMD=${1:?usage: fetch-bts-issue.sh list | fetch <n>}

case "$CMD" in
  list)
    FIELDS=number,title,state,labels,updatedAt
    [ "$STATUS" != '[]' ] && FIELDS="$FIELDS,projectItems"
    # gh 실패를 삼키지 않는다 — 목록이 "조용히 비어" 보이면 작업할 이슈가 없다고 오해한다
    ERRF=$(mktemp); trap 'rm -f "$ERRF"' EXIT
    if ! RAW=$(gh issue list --repo "$REPO" --assignee @me --state open --json "$FIELDS" --limit 1000 2> "$ERRF"); then
      echo "ERROR: BTS 이슈 목록 조회 실패 ($REPO): $(head -c 300 "$ERRF")" >&2
      case "$(cat "$ERRF")" in *read:project*|*scope*)
        echo "  프로젝트 상태 필터(이슈.bts_project_status)에는 gh 토큰의 read:project 권한이 필요합니다: gh auth refresh -s read:project" >&2 ;;
      esac
      exit 1
    fi
    jq --argjson ex "$EXCLUDE" --argjson st "$STATUS" '[.[]
          | ((.labels // []) | map(.name)) as $labels
          | ((.projectItems // []) | map(.status.name // "")) as $statuses
          | select(($labels | any(. as $l | $ex | index($l) != null)) | not)
          | select(($st | length) == 0 or ($statuses | any(. as $s | $st | index($s) != null)))
        ] | sort_by(.updatedAt) | reverse' <<< "$RAW"
    ;;
  fetch)
    N=${2:?fetch 에는 이슈 번호가 필요합니다}
    ISSUE=$(gh issue view "$N" --repo "$REPO" --json number,title,body,state,labels,assignees,url,createdAt,updatedAt)
    # --paginate 필수: 기본 페이지 크기(30)를 넘는 댓글이 잘린다
    COMMENTS=$(gh api --paginate "repos/$REPO/issues/$N/comments?per_page=100" \
      --jq '.[] | {author: .user.login, created_at: .created_at, body: .body}' | jq -s '.')
    jq -n --argjson i "$ISSUE" --argjson c "$COMMENTS" '{issue: $i, comments: $c}'
    ;;
  *)
    echo "ERROR: 알 수 없는 명령 '$CMD' (list | fetch)" >&2; exit 1 ;;
esac
