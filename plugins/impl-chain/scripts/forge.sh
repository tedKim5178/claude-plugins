#!/bin/bash
# 코드 호스팅 공용 래퍼 — GitHub(gh) / GitLab(glab). 체인의 이슈·PR(MR)·파일 조회는 전부 이것으로 한다 (읽기만).
# 레포마다 플랫폼을 따로 정한다 → 앱은 GitLab, 기획·proto는 GitHub처럼 섞여 있어도 된다.
#
# <repo> 형식: `owner/name` (앱 레포와 같은 호스트) / `host/owner/name` / 레포 URL. GitLab 하위 그룹(`g/sub/proj`)도 된다.
#   첫 마디에 점이 있으면 호스트로 본다 (`github.com/org/repo`, `gitlab.company.com/g/proj`).
#
# 앱 레포 = 원격(프로필 `git.remote`, 없으면 origin)의 URL. 호스트를 URL로 못 쓰는 경우(ssh 별칭 등)는 프로필 `git.host`.
# 플랫폼 판정 (호스트마다): github.com → github / gitlab.com → gitlab / 앱 호스트이고 프로필 `git.platform`이 있으면 그 값
#   → `gh`·`glab` 로그인 호스트 → API 응답(/api/v4 = GitLab, /api/v3 = GitHub Enterprise) → 모르면 exit 1 (git.platform을 적으라고 안내)
#
# Usage (출력은 플랫폼과 무관하게 같은 형식 — GitLab의 iid는 number, MR은 PR로 부른다):
#   forge.sh repo                              앱 레포 `host/path`
#   forge.sh platform [<repo>]                 github | gitlab
#   forge.sh me                                앱 호스트의 내 로그인 이름
#   forge.sh milestones                        열린 마일스톤 제목 (줄 단위). GitLab은 상위 그룹 마일스톤 포함 (16.7+, 그 이전은 프로젝트 것만)
#   forge.sh milestones-all                    닫힌 것 포함 전부
#   forge.sh issues-mine <milestone>           JSON [{number, title}] — 내게 할당된 open 이슈 전부 (PR 제외)
#   forge.sh search <keyword>                  JSON [{number, milestone, state(open|closed), title}] — 최근 갱신순 20개
#   forge.sh issue <repo> <n>                  JSON {number, title, body, labels:[{name}], url}
#   forge.sh comments <repo> <n>               JSON [{author, created_at, body}] — 시간순 전부 (GitLab 시스템 노트 제외)
#   forge.sh pr-diff <repo> <n>                unified diff 원문
#   forge.sh commit-files <repo> <sha>         JSON [{filename, patch}]
#   forge.sh file <repo> <path> [ref]          파일 원문 (ref 없으면 기본 브랜치)
#   forge.sh refs <repo>                       stdin 텍스트에서 그 레포의 링크를 뽑아 `pr {n}` / `commit {sha}` / `file {ref} {path}` 줄로
#   forge.sh issue-ref <url>                   이슈 URL → `{repo} {n}` (repo는 host/path)

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
die() { echo "ERROR: $*" >&2; exit 1; }
pget() { "$HERE/impl-profile.sh" get "$1" 2>/dev/null || true; }
enc() { jq -rn --arg s "$1" '$s|@uri'; }

# 원격 URL → "host path" (https / ssh:// / scp 꼴, .git 제거)
parse_remote() {
  local u=${1%/} h p
  u=${u%.git}
  case "$u" in
    ssh://*) u=${u#ssh://}; u=${u#*@}; h=${u%%/*}; h=${h%%:*}; p=${u#*/} ;;
    *://*)   u=${u#*://}; u=${u#*@}; h=${u%%/*}; p=${u#*/} ;;
    *@*:*)   u=${u#*@}; h=${u%%:*}; p=${u#*:} ;;
    *) return 1 ;;
  esac
  [ -n "$h" ] && [ -n "$p" ] && [ "$h" != "$p" ] || return 1
  echo "$h $p"
}

APP_HOST="" APP_PATH=""
load_app() {
  [ -n "$APP_HOST" ] && return 0
  local remote url hp
  remote=$(pget git.remote); remote=${remote:-origin}
  url=$(git remote get-url "$remote" 2>/dev/null) || die "원격 '$remote' 이 없습니다 (프로필 git.remote 확인)"
  hp=$(parse_remote "$url") || die "원격 URL을 해석할 수 없습니다: $url"
  APP_HOST=${hp%% *}; APP_PATH=${hp#* }
  local h; h=$(pget git.host); [ -z "$h" ] || APP_HOST=$h
}

# <repo> → 전역 HOST, RPATH
set_repo() {
  local r=${1:?repo가 필요합니다} first hp
  case "$r" in
    *://*|*@*:*) hp=$(parse_remote "$r") || die "레포 URL을 해석할 수 없습니다: $r"; HOST=${hp%% *}; RPATH=${hp#* }; return ;;
  esac
  r=${r%/}; r=${r%.git}
  first=${r%%/*}
  case "$r" in */*) ;; *) die "레포 형식이 아닙니다 (owner/name): $1" ;; esac
  case "$first" in
    *.*) HOST=$first; RPATH=${r#*/}
         case "$RPATH" in */*) ;; *) die "레포 형식이 아닙니다 (host/owner/name): $1" ;; esac ;;
    *)   load_app; HOST=$APP_HOST; RPATH=$r ;;
  esac
}
set_app() { load_app; HOST=$APP_HOST; RPATH=$APP_PATH; }

# 호스트 → github | gitlab (같은 호스트를 여러 번 판정하지 않도록 캐시)
CACHE_DIR="${TMPDIR:-/tmp}/impl-chain-forge"
platform_of() {
  local h=$1 p="" code
  case "$h" in
    github.com|*.github.com) echo github; return ;;
    gitlab.com) echo gitlab; return ;;
  esac
  load_app 2>/dev/null || true
  if [ "$h" = "$APP_HOST" ]; then
    p=$(pget git.platform)
    case "$p" in github|gitlab) echo "$p"; return ;; "") ;; *) die "프로필 git.platform 값 '$p' — github | gitlab" ;; esac
  fi
  if [ -f "$CACHE_DIR/$h" ]; then cat "$CACHE_DIR/$h"; return; fi
  if command -v glab > /dev/null && glab auth status --hostname "$h" > /dev/null 2>&1; then p=gitlab
  elif command -v gh > /dev/null && gh auth status --hostname "$h" > /dev/null 2>&1; then p=github
  else
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "https://$h/api/v4/version" 2>/dev/null || true)
    case "$code" in 200|401|403) p=gitlab ;; esac
    if [ -z "$p" ]; then
      code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "https://$h/api/v3/meta" 2>/dev/null || true)
      [ "$code" = 200 ] && p=github
    fi
  fi
  [ -n "$p" ] || die "$h 가 GitHub인지 GitLab인지 알 수 없습니다 — 프로필 git 섹션에 'platform: github' 또는 'platform: gitlab'을 적어주세요"
  mkdir -p "$CACHE_DIR" 2>/dev/null && echo "$p" > "$CACHE_DIR/$h" 2>/dev/null || true
  echo "$p"
}

PLAT=""
use() { # set_repo/set_app 뒤에 → PLAT + CLI 확인
  PLAT=$(platform_of "$HOST")
  case "$PLAT" in
    github) command -v gh > /dev/null || die "gh가 필요합니다 ($HOST — brew install gh, gh auth login --hostname $HOST)" ;;
    gitlab) command -v glab > /dev/null || die "glab이 필요합니다 ($HOST — brew install glab, glab auth login --hostname $HOST)" ;;
  esac
}
GH()   { gh api --hostname "$HOST" "$@"; }
GL()   { glab api --hostname "$HOST" "$@"; }
PROJ() { echo "projects/$(enc "$RPATH")"; }
# 페이지마다 나온 배열을 하나로
SLURP() { jq -s 'map(if type == "array" then . else [.] end) | add // []'; }

cmd=${1:-}; [ $# -gt 0 ] && shift
case "$cmd" in
  repo)
    set_app; echo "$HOST/$RPATH" ;;

  platform)
    if [ $# -gt 0 ]; then set_repo "$1"; else set_app; fi
    platform_of "$HOST" ;;

  me)
    set_app; use
    case $PLAT in github) GH user | jq -r .login ;; gitlab) GL user | jq -r .username ;; esac ;;

  milestones|milestones-all)
    set_app; use
    if [ "$cmd" = milestones ]; then ghs=open gls="&state=active"; else ghs=all gls=""; fi
    case $PLAT in
      github) GH --paginate "repos/$RPATH/milestones?state=$ghs&per_page=100" | SLURP | jq -r '.[].title' ;;
      gitlab) GL --paginate "$(PROJ)/milestones?include_ancestors=true&per_page=100$gls" | SLURP | jq -r '.[].title' | awk '!seen[$0]++' ;;
    esac ;;

  issues-mine)
    ms=${1:?issues-mine 에는 milestone이 필요합니다}
    set_app; use
    me=$("$0" me) || die "로그인이 필요합니다 ($PLAT $HOST)"
    case $PLAT in
      github)
        num=$(GH --paginate "repos/$RPATH/milestones?state=all&per_page=100" | SLURP \
          | jq -r --arg t "$ms" '.[] | select(.title == $t) | .number' | head -1)
        [ -n "$num" ] || die "마일스톤 '$ms' 을 찾을 수 없습니다"
        GH --paginate "repos/$RPATH/issues?milestone=$num&state=open&assignee=$(enc "$me")&per_page=100" | SLURP \
          | jq -c --arg me "$me" '[.[] | select(has("pull_request") | not)
                                       | select(.assignees | map(.login) | any(. == $me))
                                       | {number, title}]' ;;
      gitlab)
        GL --paginate "$(PROJ)/issues?milestone=$(enc "$ms")&state=opened&assignee_username=$(enc "$me")&per_page=100" | SLURP \
          | jq -c '[.[] | {number: .iid, title}]' ;;
    esac ;;

  search)
    kw=${1:?search 에는 키워드가 필요합니다}
    set_app; use
    case $PLAT in
      github)
        GH -X GET search/issues -f q="repo:$RPATH is:issue $kw" -f sort=updated -f per_page=20 \
          | jq -c '[.items[] | {number, milestone: .milestone.title, state, title}]' ;;
      gitlab)
        GL "$(PROJ)/issues?search=$(enc "$kw")&order_by=updated_at&sort=desc&per_page=20" \
          | jq -c '[.[] | {number: .iid, milestone: .milestone.title,
                          state: (if .state == "opened" then "open" else .state end), title}]' ;;
    esac ;;

  issue)
    set_repo "${1:-}"; n=${2:?issue 에는 번호가 필요합니다}; use
    case $PLAT in
      github) GH "repos/$RPATH/issues/$n" \
                | jq -c '{number, title, body: (.body // ""), labels: [.labels[] | {name}], url: .html_url}' ;;
      gitlab) GL "$(PROJ)/issues/$n" \
                | jq -c '{number: .iid, title, body: (.description // ""), labels: [.labels[] | {name: .}], url: .web_url}' ;;
    esac ;;

  comments)
    set_repo "${1:-}"; n=${2:?comments 에는 번호가 필요합니다}; use
    case $PLAT in
      github) GH --paginate "repos/$RPATH/issues/$n/comments?per_page=100" | SLURP \
                | jq -c '[.[] | {author: .user.login, created_at, body}]' ;;
      gitlab) GL --paginate "$(PROJ)/issues/$n/notes?sort=asc&order_by=created_at&per_page=100" | SLURP \
                | jq -c '[.[] | select(.system | not) | {author: .author.username, created_at, body}]' ;;
    esac ;;

  pr-diff)
    set_repo "${1:-}"; n=${2:?pr-diff 에는 번호가 필요합니다}; use
    case $PLAT in
      github) gh pr diff "$n" --repo "$HOST/$RPATH" ;;
      gitlab)
        fmt='.[] | "diff --git a/\(.old_path) b/\(.new_path)\n--- a/\(.old_path)\n+++ b/\(.new_path)\n\(.diff)"'
        if out=$(GL --paginate "$(PROJ)/merge_requests/$n/diffs?per_page=100" 2>/dev/null); then
          SLURP <<< "$out" | jq -r "$fmt"
        else   # GitLab 15.7 이전: /diffs 없음
          GL "$(PROJ)/merge_requests/$n/changes" | jq -r ".changes | $fmt"
        fi ;;
    esac ;;

  commit-files)
    set_repo "${1:-}"; sha=${2:?commit-files 에는 sha가 필요합니다}; use
    case $PLAT in
      github) GH "repos/$RPATH/commits/$sha" | jq -c '[.files[] | {filename, patch}]' ;;
      gitlab) GL --paginate "$(PROJ)/repository/commits/$sha/diff?per_page=100" | SLURP \
                | jq -c '[.[] | {filename: .new_path, patch: .diff}]' ;;
    esac ;;

  file)
    set_repo "${1:-}"; path=${2:?file 에는 경로가 필요합니다}; ref=${3:-}; use
    case $PLAT in
      github) GH -H "Accept: application/vnd.github.raw" "repos/$RPATH/contents/$path${ref:+?ref=$(enc "$ref")}" ;;
      gitlab)
        [ -n "$ref" ] || ref=$(GL "$(PROJ)" | jq -r .default_branch)
        GL "$(PROJ)/repository/files/$(enc "$path")/raw?ref=$(enc "$ref")" ;;
    esac ;;

  refs)
    set_repo "${1:-}"; use
    PLAT=$PLAT HOST=$HOST RPATH=$RPATH python3 -c '
import os, re, sys
host, path = re.escape(os.environ["HOST"]), re.escape(os.environ["RPATH"])
sep = r"/-/" if os.environ["PLAT"] == "gitlab" else r"/"
pr = "merge_requests" if os.environ["PLAT"] == "gitlab" else "pull"
rx = re.compile(host + "/" + path + sep + r"(?:(" + pr + r")/(\d+)|(commit)/([0-9a-f]{7,40})|(blob)/([^\s)\]\"#?]+))")
seen = set()
for m in rx.finditer(sys.stdin.read()):
    if m.group(1):   line = "pr " + m.group(2)
    elif m.group(3): line = "commit " + m.group(4)
    else:
        ref, _, p = m.group(6).partition("/")
        if not p: continue
        line = "file " + ref + " " + p
    if line not in seen:
        seen.add(line); print(line)
' ;;

  issue-ref)
    u=${1:?issue-ref 에는 URL이 필요합니다}
    u=${u#*://}; u=${u%%[?#]*}
    if [[ "$u" =~ ^(.+)/-/(issues|work_items)/([0-9]+)$ ]] || [[ "$u" =~ ^(.+)/(issues)/([0-9]+)$ ]]; then
      echo "${BASH_REMATCH[1]} ${BASH_REMATCH[3]}"
    else
      die "이슈 URL이 아닙니다: $1"
    fi ;;

  *) die "usage: forge.sh repo | platform [repo] | me | milestones | milestones-all | issues-mine <ms> | search <kw> | issue <repo> <n> | comments <repo> <n> | pr-diff <repo> <n> | commit-files <repo> <sha> | file <repo> <path> [ref] | refs <repo> | issue-ref <url>" ;;
esac
