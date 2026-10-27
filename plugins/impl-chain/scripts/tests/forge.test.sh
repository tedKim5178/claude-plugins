#!/bin/bash
# forge.sh·spec-issue.sh 테스트. 실행: scripts/tests/forge.test.sh
# 가짜 gh·glab(PATH 앞)이 엔드포인트별 응답 파일을 돌려준다 — 네트워크·로그인 없이 돈다.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
FG="$SCRIPTS/forge.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
FAIL=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; FAIL=1; }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 — 기대 [$3], 실제 [$2]"; }

export FAKE_DIR="$T/fake" FAKE_LOG="$T/fake/log" TMPDIR="$T/tmp"
mkdir -p "$FAKE_DIR/resp" "$T/bin" "$TMPDIR"
key() { printf '%s' "${1%%\?*}" | sed 's#[/%]#_#g'; }
resp() { printf '%s' "$3" > "$FAKE_DIR/resp/$1_$(key "$2")"; }   # $1=gh|glab $2=엔드포인트 $3=응답

# 가짜 CLI — `{cli} api [옵션] <엔드포인트>` → resp 파일, gh pr <sub> → resp/gh_pr_<sub>. 인자는 FAKE_LOG에
for cli in gh glab; do
  cat > "$T/bin/$cli" <<EOF
#!/bin/bash
CLI=$cli
EOF
  cat >> "$T/bin/$cli" <<'EOF'
echo "$CLI $*" >> "$FAKE_LOG"
case "$1" in
  auth) [ "$CLI" = gh ] && exit "${FAKE_GH_AUTH:-1}" || exit "${FAKE_GLAB_AUTH:-1}" ;;
  pr)   f="$FAKE_DIR/resp/gh_pr_$2"; [ -f "$f" ] && cat "$f" && exit 0; exit 1 ;;
  api)  shift ;;
  *)    exit 9 ;;
esac
ep=""
while [ $# -gt 0 ]; do
  case "$1" in
    --input) cp "$2" "$FAKE_DIR/last-input.json"; shift 2 ;;
    --hostname|-X|-H|-f|-F|--jq) shift 2 ;;
    --paginate) shift ;;
    *) ep=$1; shift ;;
  esac
done
f="$FAKE_DIR/resp/${CLI}_$(printf '%s' "${ep%%\?*}" | sed 's#[/%]#_#g')"
[ -f "$f" ] && cat "$f" || { echo "404 $ep" >&2; exit 1; }
EOF
  chmod +x "$T/bin/$cli"
done
export PATH="$T/bin:$PATH"

make_repo "$T/repo" && cd "$T/repo"
PROF=.claude/impl-chain/profile.md
remote() { git remote remove origin 2>/dev/null; git remote add origin "$1"; rm -rf "$TMPDIR/impl-chain-forge"; }
setkey() { # $1=섹션 $2=키 $3=값 — 섹션 맨 끝에 추가 (있으면 바꿈)
  python3 - "$PROF" "$1" "$2" "$3" <<'PY'
import sys
p, sec, k, v = sys.argv[1:]
lines = open(p).read().split("\n"); out = []; inside = False; done = False
for l in lines:
    if l.startswith("## "):
        if inside and not done: out.append(f"- {k}: {v}"); done = True
        inside = (l == "## " + sec)
    if inside and l.startswith(f"- {k}:"): l = f"- {k}: {v}"; done = True
    out.append(l)
if inside and not done: out.append(f"- {k}: {v}")
open(p, "w").write("\n".join(out))
PY
}

echo "repo·platform 판정"
remote https://github.com/acme/app.git
eq "https GitHub" "$("$FG" repo) $("$FG" platform)" "github.com/acme/app github"
remote git@gitlab.com:mobile/sub/app.git
eq "scp 꼴 GitLab 하위 그룹" "$("$FG" repo) $("$FG" platform)" "gitlab.com/mobile/sub/app gitlab"
remote ssh://git@git.corp.io:2222/mobile/app.git
setkey git platform gitlab
eq "ssh:// 포트 + 프로필 git.platform" "$("$FG" repo) $("$FG" platform)" "git.corp.io/mobile/app gitlab"
eq "다른 호스트는 그 호스트로 판정" "$("$FG" platform github.com/acme/planning)" "github"
eq "호스트 없는 레포 = 앱 호스트" "$("$FG" platform plan/spec)" "gitlab"
setkey git platform ""
FAKE_GLAB_AUTH=0 "$FG" platform > "$T/out" 2>&1; eq "glab 로그인 호스트면 gitlab" "$(cat "$T/out")" "gitlab"
remote git@unknown.invalid:a/b.git
"$FG" platform > /dev/null 2> "$T/err"; rc=$?
[ $rc = 1 ] && grep -q "git.platform\|platform:" "$T/err" && ok "모르는 호스트는 exit 1 + git.platform 안내" || bad "모르는 호스트 (exit $rc): $(cat "$T/err")"
remote git@github-work:acme/app.git
setkey git host github.com
eq "ssh 별칭은 git.host로" "$("$FG" repo)" "github.com/acme/app"
setkey git host ""
sed -i '' '/^- host: $/d; /^- platform: $/d' "$PROF"

echo "GitLab 조회 정규화"
remote git@gitlab.com:mobile/app.git
P='projects/mobile%2Fapp'
resp glab user '{"username":"me"}'
resp glab "$P/issues/7" '{"iid":7,"id":9001,"title":"좌석 뱃지","description":null,"labels":["spec","ios"],"web_url":"https://gitlab.com/mobile/app/-/issues/7"}'
eq "issue: iid→number, description→body, labels" "$("$FG" issue mobile/app 7)" \
  '{"number":7,"title":"좌석 뱃지","body":"","labels":[{"name":"spec"},{"name":"ios"}],"url":"https://gitlab.com/mobile/app/-/issues/7"}'
resp glab "$P/issues/7/notes" '[{"system":false,"author":{"username":"pm"},"created_at":"2026-01-01","body":"첫 댓글"},{"system":true,"author":{"username":"bot"},"created_at":"2026-01-02","body":"added label"}][{"system":false,"author":{"username":"dev"},"created_at":"2026-01-03","body":"둘째 페이지"}]'
eq "comments: 시스템 노트 제외 + 페이지 합치기" "$("$FG" comments mobile/app 7 | jq -c 'map(.author)')" '["pm","dev"]'
resp glab "$P/milestones" '[{"title":"4.11.0"},{"title":"4.12.0"},{"title":"4.11.0"}]'
eq "milestones: 그룹·프로젝트 중복 제거" "$("$FG" milestones | tr '\n' ' ')" "4.11.0 4.12.0 "
grep -q "include_ancestors=true.*state=active" "$FAKE_LOG" && ok "milestones: 상위 그룹 포함 + 열린 것만" || bad "milestones 쿼리: $(grep milestones "$FAKE_LOG" | tail -1)"
resp glab "$P/issues" '[{"iid":7,"title":"좌석 뱃지"},{"iid":8,"title":"할인"}]'
eq "issues-mine" "$("$FG" issues-mine 4.11.0)" '[{"number":7,"title":"좌석 뱃지"},{"number":8,"title":"할인"}]'
grep -q "milestone=4.11.0&state=opened&assignee_username=me" "$FAKE_LOG" && ok "issues-mine: 마일스톤 제목·내 담당·open" || bad "issues-mine 쿼리: $(grep '/issues?' "$FAKE_LOG" | tail -1)"
resp glab "$P/merge_requests/12/diffs" '[{"old_path":"a.proto","new_path":"a.proto","diff":"@@ -1 +1 @@\n-x\n+y\n"}]'
"$FG" pr-diff mobile/app 12 > "$T/out"
grep -q '^diff --git a/a.proto b/a.proto' "$T/out" && grep -q '^+y' "$T/out" && ok "pr-diff: unified diff" || bad "pr-diff: $(cat "$T/out")"
rm "$FAKE_DIR/resp/glab_$(key "$P/merge_requests/12/diffs")"
resp glab "$P/merge_requests/12/changes" '{"changes":[{"old_path":"b.proto","new_path":"b.proto","diff":"+z\n"}]}'
"$FG" pr-diff mobile/app 12 2>/dev/null | grep -q 'b/b.proto' && ok "pr-diff: 구버전 /changes 폴백" || bad "pr-diff 폴백"
resp glab "$P/repository/commits/abc1234/diff" '[{"new_path":"c.proto","diff":"+c"}]'
eq "commit-files" "$("$FG" commit-files mobile/app abc1234)" '[{"filename":"c.proto","patch":"+c"}]'
resp glab "$P" '{"default_branch":"develop"}'
resp glab "$P/repository/files/docs%2Fspec.md/raw" '# 스펙'
eq "file: 기본 브랜치" "$("$FG" file mobile/app docs/spec.md)" "# 스펙"
grep -q 'raw?ref=develop' "$FAKE_LOG" && ok "file: ref = default_branch" || bad "file ref"

echo "링크·URL"
TXT='proto https://gitlab.com/mobile/app/-/merge_requests/31 and gitlab.com/mobile/app/-/commit/0123abcd
blob https://gitlab.com/mobile/app/-/blob/main/proto/seat.proto#L10 other gitlab.com/mobile/other/-/merge_requests/9
dup https://gitlab.com/mobile/app/-/merge_requests/31/diffs'
eq "refs: GitLab MR·커밋·파일, 다른 레포 제외, 중복 제거" "$(printf '%s' "$TXT" | "$FG" refs mobile/app | tr '\n' '|')" \
  "pr 31|commit 0123abcd|file main proto/seat.proto|"
TXT='https://github.com/acme/proto/pull/88/files github.com/acme/proto/blob/v1.2/a/b.proto github.com/acme/proto/commit/deadbeef'
eq "refs: GitHub (다른 호스트·플랫폼)" "$(printf '%s' "$TXT" | "$FG" refs github.com/acme/proto | tr '\n' '|')" \
  "pr 88|file v1.2 a/b.proto|commit deadbeef|"
eq "issue-ref: GitLab" "$("$FG" issue-ref https://git.corp.io/g/sub/proj/-/issues/42)" "git.corp.io/g/sub/proj 42"
eq "issue-ref: GitHub" "$("$FG" issue-ref https://github.com/acme/app/issues/5)" "github.com/acme/app 5"
eq "issue-ref: GitLab work item" "$("$FG" issue-ref https://gitlab.com/g/p/-/work_items/3)" "gitlab.com/g/p 3"

echo "GitHub 조회 정규화 (섞인 레포 — 앱 GitLab, 기획 GitHub)"
resp gh repos/acme/planning/issues/55 '{"number":55,"title":"기획","body":"본문","labels":[{"name":"plan","color":"fff"}],"html_url":"https://github.com/acme/planning/issues/55"}'
: > "$FAKE_LOG"
eq "issue (GitHub)" "$("$FG" issue github.com/acme/planning 55)" \
  '{"number":55,"title":"기획","body":"본문","labels":[{"name":"plan"}],"url":"https://github.com/acme/planning/issues/55"}'
grep -q "^gh api --hostname github.com repos/acme/planning/issues/55" "$FAKE_LOG" && ok "GitHub 레포는 gh로" || bad "호출: $(cat "$FAKE_LOG")"
resp gh repos/acme/planning/issues/55/comments '[{"user":{"login":"pm"},"created_at":"t1","body":"c1"}][{"user":{"login":"pm2"},"created_at":"t2","body":"c2"}]'
eq "comments (GitHub, 페이지 합치기)" "$("$FG" comments github.com/acme/planning 55 | jq -c 'map(.author)')" '["pm","pm2"]'

echo "GitHub 앱 레포"
remote https://github.com/acme/app.git
resp gh user '{"login":"me"}'
resp gh repos/acme/app/milestones '[{"title":"4.11.0","number":3}]'
resp gh repos/acme/app/issues '[{"number":7,"title":"이슈","assignees":[{"login":"me"}]},{"number":9,"title":"PR","pull_request":{},"assignees":[{"login":"me"}]},{"number":10,"title":"남의 것","assignees":[{"login":"you"}]}]'
eq "issues-mine (GitHub): PR·남의 이슈 제외" "$("$FG" issues-mine 4.11.0)" '[{"number":7,"title":"이슈"}]'
grep -q "issues?milestone=3&state=open" "$FAKE_LOG" && ok "issues-mine: 마일스톤 제목 → 번호" || bad "issues-mine 쿼리"
remote git@gitlab.com:mobile/app.git

echo "spec-issue.sh — GitLab 앱 + GitHub 기획"
setkey 이슈 spec_repo github.com/acme/planning
setkey 이슈 spec_link_regex 'acme/planning/issues/([0-9]+)'
resp glab "$P/issues/7" '{"iid":7,"title":"좌석 뱃지","description":"기획: https://github.com/acme/planning/issues/55","labels":[],"web_url":"w"}'
"$SCRIPTS/spec-issue.sh" fetch 4.11.0 7 > "$T/fetch.json" 2> "$T/err"; rc=$?
eq "fetch exit" "$rc" "0"
eq "fetch: 기획서 = GitHub 55, 댓글 2개, 후보 1개" "$(jq -c '[.spec.number, (.comments | length), .spec_candidates[0].found_in, .issue.number, (.issue_comments | length)]' "$T/fetch.json")" \
  '[55,2,"본문",7,2]'
eq "list" "$("$SCRIPTS/spec-issue.sh" list 4.11.0 | tr '\n' '|')" "#7 좌석 뱃지|#8 할인|"
"$SCRIPTS/spec-issue.sh" list 9.9.9 > /dev/null 2> "$T/err"; rc=$?
[ $rc = 1 ] && grep -q "찾을 수 없습니다" "$T/err" && ok "없는 마일스톤은 exit 1" || bad "없는 마일스톤 (exit $rc)"
resp glab "$P/issues" '[{"iid":7,"title":"좌석 뱃지","state":"opened","milestone":{"title":"4.11.0"}},{"iid":3,"title":"옛것","state":"closed","milestone":null}]'
eq "search" "$("$SCRIPTS/spec-issue.sh" search 좌석 | tr '\n' '|')" "#7 [4.11.0] [open] 좌석 뱃지|#3 [마일스톤 없음] [closed] 옛것|"

[ $FAIL = 0 ] && echo "ALL PASS" || { echo "FAILED"; exit 1; }
