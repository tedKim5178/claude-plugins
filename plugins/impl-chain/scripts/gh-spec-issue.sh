#!/bin/bash
# GitHub 스펙 이슈 데이터 수집 — 공용 spec 어댑터 (GitHub + gh)
# 계약: impl-chain references/impl-profile-spec.md "spec 어댑터" (프로필 `이슈.spec_adapter`)
# 프로필에서 읽는 값: 이슈.spec_repo, 이슈.spec_link_regex. 앱 레포는 `gh repo view`.
#
# Usage:
#   fetch-spec-issue.sh milestones                         → 열린 마일스톤 제목 (줄 단위)
#   fetch-spec-issue.sh list <milestone>                   → "#{n} {title}" (내게 할당된 open 이슈, 전부 — 페이지 끝까지)
#   fetch-spec-issue.sh search <keyword>                   → "#{n} [{milestone}] [{state}] {title}" (앱 레포 이슈 키워드 검색, 최근 갱신순 20개)
#   fetch-spec-issue.sh fetch <milestone> <n> [spec_n]     → JSON {issue, issue_comments, spec, comments, spec_candidates}
#     spec_n: 기획 이슈를 지정 (후보가 여럿일 때 사용자가 고른 것)
#
#   spec_candidates: 앱 이슈 본문·댓글에서 spec_link_regex로 찾은 기획 이슈 전부 [{number, title, found_in}]
#   기획 이슈 지정 없이 후보가 2개 이상이면 spec/comments는 비워 둔다 — 호출자가 사용자에게 물어서 다시 호출한다.

set -euo pipefail

CMD=${1:?usage: fetch-spec-issue.sh milestones | list <milestone> | search <keyword> | fetch <milestone> <n> [spec_n]}
MILESTONE=${2:-}
ISSUE=${3:-}
SPEC_OVERRIDE=${4:-}
HERE="$(cd "$(dirname "$0")" && pwd)"
PROFILE_GET() { "$HERE/impl-profile.sh" get "$1"; }
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner) || { echo "ERROR: 앱 레포를 알 수 없습니다 (gh repo view)" >&2; exit 1; }
SPEC_REPO=$(PROFILE_GET 이슈.spec_repo) || exit 1
SPEC_LINK_REGEX=$(PROFILE_GET 이슈.spec_link_regex) || exit 1

case "$CMD" in
  milestones)
    gh api "repos/$REPO/milestones?state=open&per_page=100" --jq '.[].title'
    exit 0 ;;
  search)
    KW=${2:?search 에는 키워드가 필요합니다}
    gh api -X GET search/issues -f q="repo:$REPO is:issue $KW" -f sort=updated -f per_page=20 \
      --jq '.items[] | "#\(.number) [\(.milestone.title // "마일스톤 없음")] [\(.state)] \(.title)"'
    exit 0 ;;
  list|fetch) ;;
  *) echo "ERROR: 알 수 없는 명령 '$CMD' (milestones | list | search | fetch)" >&2; exit 1 ;;
esac
[ -n "$MILESTONE" ] || { echo "ERROR: $CMD 에는 milestone이 필요합니다" >&2; exit 1; }
if [ "$CMD" = "fetch" ] && [ -z "$ISSUE" ]; then
  echo "ERROR: fetch 에는 이슈 번호가 필요합니다" >&2; exit 1
fi

# NOTE: 아래 gh 호출에는 전부 `|| true`를 붙인다.
# set -e 아래에서 VAR=$(failing-cmd) 는 스크립트를 즉시 종료시키므로,
# `|| true` 없이는 바로 아래의 친절한 에러 메시지에 도달하지 못한다.

MY_LOGIN=$(gh api user --jq '.login' 2>/dev/null || true)
if [ -z "$MY_LOGIN" ]; then
  echo "ERROR: gh 로그인이 필요합니다 (gh auth login)" >&2
  exit 1
fi

# 마일스톤 번호 조회 (state=all: 이미 닫힌 마일스톤도 조회 대상)
MILESTONE_NUM=$(gh api "repos/$REPO/milestones?state=all&per_page=100" \
  --jq ".[] | select(.title == \"$MILESTONE\") | .number" 2>/dev/null || true)
if [ -z "$MILESTONE_NUM" ]; then
  echo "ERROR: 마일스톤 '$MILESTONE'을 찾을 수 없습니다." >&2
  echo "사용 가능한 마일스톤:" >&2
  gh api "repos/$REPO/milestones?state=all&per_page=100" --jq '.[].title' >&2 2>/dev/null || true
  exit 1
fi

# list: 목록 출력 후 종료
# select(has("pull_request") | not): GitHub issues API는 PR도 함께 내려주므로 제외한다.
if [ "$CMD" = "list" ]; then
  gh api --paginate "repos/$REPO/issues?milestone=$MILESTONE_NUM&state=open&per_page=100" \
    --jq "[.[]
           | select(has(\"pull_request\") | not)
           | select(.assignees | map(.login) | any(. == \"$MY_LOGIN\"))]
          | .[] | \"#\(.number) \(.title)\"" 2>/dev/null || true
  exit 0
fi

# 앱 이슈 조회
APP_ISSUE=$(gh issue view "$ISSUE" --repo "$REPO" \
  --json number,title,body,labels,url 2>/dev/null || true)
if [ -z "$APP_ISSUE" ]; then
  echo "ERROR: 이슈 #$ISSUE를 찾을 수 없습니다." >&2
  exit 1
fi

# 앱 이슈 댓글 (기획서 링크가 본문이 아니라 댓글에만 있는 경우가 많다)
# --paginate 필수: 기본 페이지 크기(30)를 넘는 댓글이 잘린다 (실제로 겪은 버그 — 최종 문구 키 표 누락)
APP_COMMENTS=$( { gh api --paginate "repos/$REPO/issues/$ISSUE/comments?per_page=100" \
  --jq '.[] | {author: .user.login, created_at: .created_at, body: .body}' 2>/dev/null || true; } | jq -s '.')
[ -n "$APP_COMMENTS" ] || APP_COMMENTS="[]"

# 기획서 이슈 번호 후보 추출 — 앱 이슈 본문·댓글에서 spec_link_regex(그룹 1 = 번호)에 걸리는 것 전부.
# 번호순으로 아무거나 고르지 않는다: 후보가 2개 이상이면 기획서를 가져오지 않고 후보 목록만 돌려준다.
#
# NOTE: grep이 "일치 없음"으로 1을 반환하면 pipefail 때문에 파이프라인 전체가 실패한다.
# `|| true`를 파이프라인 안쪽에 넣어야 한다. 바깥에 `|| echo "[]"`를 붙이면
# jq가 이미 출력한 "[]"와 합쳐져 "[]\n[]" 라는 깨진 JSON이 만들어진다. (실제로 겪은 버그)
# 정규식은 python re 문법 (그룹 1 = 번호). perl 없이 돈다.
find_numbers() { { RE="$SPEC_LINK_REGEX" python3 -c 'import os, re, sys
for m in re.finditer(os.environ["RE"], sys.stdin.read()): print(m.group(1))' || true; } | sort -un; }
IN_BODY=$(jq -r '.body // ""' <<< "$APP_ISSUE" | find_numbers)
IN_COMMENTS=$(jq -r '[.[].body] | join("\n")' <<< "$APP_COMMENTS" | find_numbers)

SPEC_CANDIDATES="[]"
for num in $(printf '%s\n%s\n' "$IN_BODY" "$IN_COMMENTS" | sed '/^$/d' | sort -un); do
  where=""
  grep -qx "$num" <<< "$IN_BODY" && where="본문"
  grep -qx "$num" <<< "$IN_COMMENTS" && where="${where:+$where,}댓글"
  title=$(gh issue view "$num" --repo "$SPEC_REPO" --json title --jq .title 2>/dev/null || echo "(조회 실패)")
  SPEC_CANDIDATES=$(jq -c --argjson n "$num" --arg t "$title" --arg w "$where" \
    '. + [{number: $n, title: $t, found_in: $w}]' <<< "$SPEC_CANDIDATES")
done

if [ -n "$SPEC_OVERRIDE" ]; then
  SPEC_NUMBER="$SPEC_OVERRIDE"
elif [ "$(jq length <<< "$SPEC_CANDIDATES")" -eq 1 ]; then
  SPEC_NUMBER=$(jq -r '.[0].number' <<< "$SPEC_CANDIDATES")
else
  SPEC_NUMBER=""   # 0개: 기획서 없음 / 2개 이상: 호출자가 사용자에게 묻는다
fi

SPEC_BODY="{}"
SPEC_COMMENTS="[]"

if [ -n "$SPEC_NUMBER" ]; then
  SPEC_BODY=$(gh issue view "$SPEC_NUMBER" --repo "$SPEC_REPO" \
    --json number,title,body,url 2>/dev/null || echo "{}")
  [ -n "$SPEC_BODY" ] || SPEC_BODY="{}"

  SPEC_COMMENTS=$( { gh api --paginate "repos/$SPEC_REPO/issues/$SPEC_NUMBER/comments?per_page=100" \
    --jq '.[] | {author: .user.login, created_at: .created_at, body: .body}' 2>/dev/null || true; } | jq -s '.')
  [ -n "$SPEC_COMMENTS" ] || SPEC_COMMENTS="[]"
fi

# 단일 JSON으로 출력
jq -n \
  --argjson issue "$APP_ISSUE" \
  --argjson issue_comments "$APP_COMMENTS" \
  --argjson spec "$SPEC_BODY" \
  --argjson comments "$SPEC_COMMENTS" \
  --argjson spec_candidates "$SPEC_CANDIDATES" \
  '{issue: $issue, issue_comments: $issue_comments, spec: $spec, comments: $comments, spec_candidates: $spec_candidates}'
