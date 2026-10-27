#!/bin/bash
# detect-base.sh / setup-branch.sh 테스트. 실행: scripts/tests/branch.test.sh
# 임시 git 레포에서 돌린다. 이 레포 자체는 건드리지 않는다.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
FAIL=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; FAIL=1; }
# $1=설명 $2=기대 exit $3..=명령 — stdout은 $out, stderr는 $T/err
expect() {
  local d=$1 want=$2; shift 2
  out=$("$@" 2>"$T/err"); local got=$?
  if [ "$got" = "$want" ]; then ok "$d"; else bad "$d (exit $got, want $want): $(head -2 "$T/err")"; fi
}

git init -q -b main "$T/repo" && cd "$T/repo"
git config user.email t@t && git config user.name t
git commit -q --allow-empty -m init
git switch -q -c feat/local-only
git commit -q --allow-empty -m local

echo "detect-base"
expect "origin 없는 로컬 브랜치도 base" 0 "$SCRIPTS/detect-base.sh"
[ "$out" = "feat/local-only" ] && ok "stdout = 현재 브랜치" || bad "stdout=$out"
git switch -q --detach HEAD
expect "detached HEAD는 exit 2" 2 "$SCRIPTS/detect-base.sh"

echo "setup-branch"
git switch -q main
expect "로컬 base에서 작업 브랜치 생성" 0 "$SCRIPTS/setup-branch.sh" feat/local-only feat/1-work
[ "$(git branch --show-current)" = feat/1-work ] && ok "작업 브랜치로 전환" || bad "현재=$(git branch --show-current)"
[ "$(git rev-parse HEAD)" = "$(git rev-parse feat/local-only)" ] && ok "로컬 base tip에서 분기" || bad "분기점 다름"
expect "이미 그 브랜치면 재개 exit 0" 0 "$SCRIPTS/setup-branch.sh" feat/local-only feat/1-work
git switch -q main
expect "같은 이름 브랜치 있으면 exit 3" 3 "$SCRIPTS/setup-branch.sh" feat/local-only feat/1-work
expect "없는 base면 exit 4" 4 "$SCRIPTS/setup-branch.sh" no-such-base feat/2-work
echo x > f && git add f
expect "커밋 안 된 변경 있으면 exit 2" 2 "$SCRIPTS/setup-branch.sh" feat/local-only feat/3-work
git reset -q --hard

echo
[ "$FAIL" = 0 ] && echo "ALL PASS" || { echo "FAILED"; exit 1; }
