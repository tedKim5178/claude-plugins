#!/bin/bash
# 메인 워크스페이스에서 작업 브랜치를 로컬 base 브랜치의 현재 tip에서 만든다 (origin은 보지 않는다).
#
# Usage: setup-branch.sh <base_branch> <branch>
#
# 종료 코드:
#   0  준비 완료 (새로 만들었거나, 이미 그 브랜치에 있음)
#   2  커밋 안 된 변경(tracked)이 있음 → 사용자에게 알리고 중단. 자동 stash/commit 하지 않는다.
#   3  같은 이름의 로컬 브랜치가 이미 있는데 현재 브랜치가 아님 → 사용자에게 확인
#   4  로컬 base 브랜치가 없음 (base 이름 오류)
#   1  기타 오류 (git switch 실패 등) → 보고 후 중단

set -euo pipefail

BASE="${1:?usage: setup-branch.sh <base_branch> <branch>}"
BRANCH="${2:?usage: setup-branch.sh <base_branch> <branch>}"
cd "$(git rev-parse --show-toplevel)"

CURRENT="$(git branch --show-current)"

# 재개: 이미 작업 브랜치 위에 있으면 그대로 쓴다.
if [ "$CURRENT" = "$BRANCH" ]; then
  echo "이미 $BRANCH 위에 있음 (재개)"
  exit 0
fi

# 브랜치를 바꾸면 커밋 안 된 변경이 따라오거나 충돌한다. 절대 자동으로 치우지 않는다.
DIRTY="$(git status --porcelain --untracked-files=no)"
if [ -n "$DIRTY" ]; then
  echo "커밋 안 된 변경이 있어 브랜치를 바꿀 수 없습니다 (현재: $CURRENT):" >&2
  echo "$DIRTY" >&2
  exit 2
fi

if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  echo "로컬 브랜치 $BRANCH 가 이미 있습니다 (현재: $CURRENT). 이어서 쓸지 사용자 확인 필요." >&2
  exit 3
fi

git show-ref --verify --quiet "refs/heads/$BASE" || { echo "로컬 base 브랜치 $BASE 가 없습니다 — base 이름 확인" >&2; exit 4; }
git switch --quiet -c "$BRANCH" "$BASE" || { echo "git switch 실패" >&2; exit 1; }
echo "$CURRENT → $BRANCH (from $BASE @ $(git rev-parse --short HEAD))"
