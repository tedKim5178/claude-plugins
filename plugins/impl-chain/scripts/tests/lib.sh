#!/bin/bash
# 체인 스크립트 테스트 공용 — 이 레포와 무관한 임시 git 레포를 만든다 (플러그인으로 옮겨도 그대로 돈다).
#
#   source "$(dirname "$0")/lib.sh"
#   make_repo "$T/repo"     # fixture 프로필 + 프로필이 가리키는 파일 + .gitignore(.impl-spec/) + 첫 커밋, cd 하지 않음
#
# SCRIPTS = 테스트 대상 스크립트 디렉토리 (tests/의 상위)
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="$SCRIPTS/tests/fixtures"

make_repo() {
  local R=$1
  mkdir -p "$R" && git -C "$R" init -q -b main
  git -C "$R" config user.email t@t && git -C "$R" config user.name t
  mkdir -p "$R/.claude/impl-chain/adapters" "$R/app/src/main/java/example" "$R/.claude/skills/fake-mock"
  cp "$FIXTURES/profile.md" "$R/.claude/impl-chain/profile.md"
  cat > "$R/.claude/impl-chain/adapters/figma-component-map.md" <<'EOF'
| Figma 컴포넌트 (data-name) | 프로젝트 | 비고 | 근거 |
|---|---|---|---|
EOF
  cat > "$R/.claude/impl-chain/adapters/figma-token-map.md" <<'EOF'
| Figma 변수 | 토큰 | 값 | 근거 |
|---|---|---|---|
EOF
  echo "# 문구 규칙" > "$R/.claude/impl-chain/adapters/string-resources.md"
  echo "object Tokens" > "$R/app/src/main/java/example/Tokens.kt"
  echo "# fake mock" > "$R/.claude/skills/fake-mock/SKILL.md"
  echo ".impl-spec/" > "$R/.gitignore"
  git -C "$R" add -A && git -C "$R" commit -q -m init
}
