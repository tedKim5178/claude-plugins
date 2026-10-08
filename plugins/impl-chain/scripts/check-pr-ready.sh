#!/bin/bash
# create-pr Step 4 직전: PR을 만들 수 있는 상태인지 확인한다. 체인에서 원격을 보는 유일한 지점.
# 원격 이름은 프로필 `git.remote` (없으면 origin).
#
# Usage: check-pr-ready.sh <base_branch> [proto_status]
#   proto_status: 상태 파일 proto_dependency.status (temp-local이면 PR 금지)
#   stdout: push·PR에 쓸 원격 이름 (exit 0일 때만)
#
# 종료 코드:
#   0  가능. 로컬 base가 원격보다 앞서면 stderr에 WARN 한 줄 (그 커밋들이 PR diff에 함께 보인다)
#   3  base가 원격에 없음 → base를 먼저 push하라고 안내하고 중단
#   4  원격 조회·fetch 실패 (네트워크·원격 이름)
#   5  임시 proto 반영 브랜치 (proto_dependency.status == temp-local) → PR 금지

set -euo pipefail
BASE="${1:?usage: check-pr-ready.sh <base_branch> [proto_status]}"
PROTO="${2:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$(git rev-parse --show-toplevel)"
REMOTE="$("$HERE/impl-profile.sh" get git.remote 2>/dev/null || true)"
REMOTE="${REMOTE:-origin}"

if [ "$PROTO" = "temp-local" ]; then
  echo "proto를 서버 원문에서 임시로 옮겨 온 브랜치입니다 (로컬 테스트 전용) — PR을 만들 수 없습니다." >&2
  exit 5
fi

if ! git ls-remote --exit-code --heads "$REMOTE" "$BASE" > /dev/null 2>&1; then
  if git ls-remote "$REMOTE" > /dev/null 2>&1; then
    echo "base $BASE 가 원격 $REMOTE 에 없습니다 — PR base가 될 수 없습니다. base를 먼저 push해주세요." >&2
    exit 3
  fi
  echo "원격 $REMOTE 조회 실패 — 네트워크 또는 원격 이름(프로필 git.remote) 확인" >&2
  exit 4
fi

git fetch --quiet "$REMOTE" "$BASE" || { echo "$REMOTE/$BASE fetch 실패" >&2; exit 4; }
AHEAD="$(git rev-list --count "$REMOTE/$BASE..$BASE")"
if [ "$AHEAD" -gt 0 ]; then
  echo "WARN: 로컬 $BASE 가 $REMOTE 보다 커밋 ${AHEAD}개 앞섬 — 이 커밋들이 PR diff에 함께 보인다 (base를 먼저 push 권장)" >&2
fi
echo "$REMOTE"
