#!/bin/bash
# 분석을 실행한 브랜치(메인 워크스페이스의 현재 로컬 브랜치)를 base로 확정한다.
# base를 고르거나 묻지 않는다 — 사용자가 서 있는 브랜치가 곧 base다.
# origin은 보지 않는다: 작업 브랜치는 로컬 base에서 따고(setup-branch.sh),
# 체인은 origin을 보지 않는다 — push·PR은 체인 밖(사용자)에서 한다.
#
# Usage: detect-base.sh
#   stdout: base 브랜치 이름 (exit 0일 때만)
#   stderr: 오류 메시지
#
# 종료 코드:
#   0  확정
#   2  detached HEAD → 브랜치 위에서 다시 실행하라고 안내하고 중단

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

BASE="$(git branch --show-current)"
if [ -z "$BASE" ]; then
  echo "detached HEAD — base로 쓸 브랜치가 없습니다. base로 삼을 브랜치로 전환한 뒤 다시 실행해주세요." >&2
  exit 2
fi

echo "$BASE"
