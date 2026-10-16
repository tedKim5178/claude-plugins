#!/bin/bash
# impl-chain 프로필 읽기·검사. 규격: impl-chain references/impl-profile-spec.md
#
# Usage:
#   impl-profile.sh get <섹션>.<키>                                    값 출력. 없으면 exit 2
#   impl-profile.sh check [--for analyze-spec|start-work]  게이트. 문제는 stderr, 실패 exit 1
#   impl-profile.sh adapter <이슈.spec_adapter|화면 확인.device_adapter>   실행할 어댑터 절대 경로 출력
#       값 `builtin:gh-spec-issue` / `builtin:android-device` / `builtin:ios-device` / `builtin:ios-real-device` → 이 스크립트와 같은 폴더의 공용 어댑터
#       (예전 값 `.claude/scripts/gh-spec-issue.sh`도 builtin으로 본다) / 그 외 → 레포 루트 기준 경로 (레포 전용 어댑터)
#       `화면 확인.device_adapter`는 키가 없으면 `builtin:android-device`로 본다. 값이 목록(쉼표 구분)이면 adapters를 쓴다 (exit 1)
#   impl-profile.sh apps       `빌드.apps`(화이트라벨 앱)를 한 줄에 하나씩 `{이름}<TAB>{값}`으로 출력. 첫 줄이 기본 앱. 키가 없으면 출력 없이 exit 0
#       값은 빌드 명령의 `{app}` 자리에 들어간다. 항목이 `이름`만이면 값 = 이름
#   impl-profile.sh adapters   `화면 확인.device_adapter`의 기기 어댑터 절대 경로를 우선순위 순서로 한 줄씩 출력
#       예: `builtin:ios-real-device, builtin:ios-device` → 실기기 어댑터, 시뮬레이터 어댑터 (visual-verifier가 앞에서부터 ensure를 시도)
#
# 프로필 경로: $IMPL_PROFILE (impl-setup 검증용) → 없으면 {repo}/.claude/impl-chain/profile.md
# 프로필 안의 상대 경로는 레포 루트 기준이다. 이 스크립트는 레포 밖(플러그인)에 있어도 된다.

set -uo pipefail
ROOT="$(git rev-parse --show-toplevel)"
PROFILE="${IMPL_PROFILE:-$ROOT/.claude/impl-chain/profile.md}"

HERE="$(cd "$(dirname "$0")" && pwd)"

# 공용 어댑터 — builtin:{이름} → $HERE/{이름}.sh. 이슈 어댑터를 쓰면 그 어댑터가 읽는 키도 필수가 된다
BUILTIN_ADAPTERS="gh-spec-issue android-device ios-device ios-real-device"
# 기기 어댑터 키 — 없으면 기본값 (기기 어댑터가 생기기 전에 쓴 프로필이 그대로 돌도록)
DEVICE_ADAPTER_KEY="화면 확인.device_adapter"
DEVICE_ADAPTER_DEFAULT="builtin:android-device"

die() { echo "ERROR: $*" >&2; exit 1; }

# $1 = "섹션.키" (섹션에 공백 가능, 키에는 점 없음) → 값. 없으면 return 2
pget() {
  local sec="${1%.*}" key="${1##*.}"
  [ -f "$PROFILE" ] || return 2
  awk -v sec="## $sec" -v key="- $key:" '
    $0 == sec { inside = 1; next }
    /^## /    { inside = 0 }
    inside && index($0, key) == 1 {
      v = substr($0, length(key) + 1)
      sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
      # 값 전체가 백틱 한 쌍으로 감싸져 있을 때만 벗긴다 (`a` / `b` 같은 값은 그대로)
      if (v ~ /^`[^`]*`$/) v = substr(v, 2, length(v) - 2)
      print v; found = 1; exit
    }
    END { exit found ? 0 : 2 }
  ' "$PROFILE"
}

# $1 = 어댑터 키 → 값 (stdout). 기기 어댑터 키는 없으면 기본값. 키 없음이면 return 2
adapter_value() {
  local v
  if ! v=$(pget "$1") || [ -z "$v" ]; then
    [ "$1" = "$DEVICE_ADAPTER_KEY" ] || return 2
    v=$DEVICE_ADAPTER_DEFAULT
  fi
  echo "$v"
}
# 기기 어댑터 값 → 항목을 한 줄씩 (쉼표로 나누고 앞뒤 공백·백틱 제거, 빈 항목 제외)
device_entries() {
  adapter_value "$DEVICE_ADAPTER_KEY" | tr ',' '\n' | sed 's/^[[:space:]`]*//; s/[[:space:]`]*$//' | grep -v '^$'
}
# $1 = 어댑터 키 → 절대 경로 (stdout). 이름 해석 실패면 return 1, 키 없음이면 return 2
# 두 번째 줄(stderr 아님)로 builtin 이름을 알려주지 않는다 — builtin_name()을 쓴다
resolve_adapter() {
  local v
  v=$(adapter_value "$1") || return 2
  case "$v" in *,*) echo "$1 은 목록이다 ($v) — impl-profile.sh adapters 로 하나씩 받는다" >&2; return 1 ;; esac
  resolve_value "$v"
}
# $1 = 어댑터 값 하나 → 절대 경로. 모르는 builtin이면 return 1
resolve_value() {
  local v=$1 name
  name=$(builtin_name "$v")
  if [ -n "$name" ]; then
    case " $BUILTIN_ADAPTERS " in
      *" $name "*) echo "$HERE/$name.sh" ;;
      *) echo "알 수 없는 builtin 어댑터: $v (지원: $(echo $BUILTIN_ADAPTERS | sed 's/[^ ]*/builtin:&/g'))" >&2; return 1 ;;
    esac
  else
    echo "$ROOT/$v"
  fi
}
# 값 → builtin 이름 (아니면 빈 문자열). 예전 레포 경로 값 .claude/scripts/gh-spec-issue.sh 도 builtin으로 본다
builtin_name() {
  case "$1" in
    builtin:*) echo "${1#builtin:}" ;;
    .claude/scripts/gh-spec-issue.sh) basename "$1" .sh ;;
    *) echo "" ;;
  esac
}

cmd_adapter() {
  [ $# -eq 1 ] || die "usage: impl-profile.sh adapter <이슈.spec_adapter|화면 확인.device_adapter>"
  [ -f "$PROFILE" ] || die "프로필 없음: $PROFILE"
  local p; p=$(resolve_adapter "$1"); case $? in 0) ;; 2) echo "ERROR: 키 없음: $1" >&2; exit 2 ;; *) exit 1 ;; esac
  [ -x "$p" ] || die "$1 어댑터가 없거나 실행할 수 없음: $p"
  echo "$p"
}

# 빌드.apps → `이름<TAB>값` 줄들 (공백·백틱 정리, 빈 항목 제외)
app_entries() {
  local v; v=$(pget "빌드.apps" 2>/dev/null) || return 0
  tr ',' '\n' <<< "$v" | sed 's/^[[:space:]`]*//; s/[[:space:]`]*$//' | grep -v '^$' \
    | awk '{ i = index($0, "="); if (i) { n = substr($0, 1, i - 1); v = substr($0, i + 1) } else { n = $0; v = $0 }
             gsub(/^[ \t]+|[ \t]+$/, "", n); gsub(/^[ \t]+|[ \t]+$/, "", v); print n "\t" v }'
}

cmd_apps() {
  [ $# -eq 0 ] || die "usage: impl-profile.sh apps"
  [ -f "$PROFILE" ] || die "프로필 없음: $PROFILE"
  app_entries
}

cmd_adapters() {
  [ $# -eq 0 ] || die "usage: impl-profile.sh adapters"
  [ -f "$PROFILE" ] || die "프로필 없음: $PROFILE"
  local e p out=()
  while IFS= read -r e; do
    p=$(resolve_value "$e") || exit 1
    [ -x "$p" ] || die "$DEVICE_ADAPTER_KEY 의 어댑터가 없거나 실행할 수 없음: $e ($p)"
    out+=("$p")
  done < <(device_entries)
  [ ${#out[@]} -gt 0 ] || die "$DEVICE_ADAPTER_KEY 값이 비어 있음"
  printf '%s\n' "${out[@]}"
}

cmd_get() {
  [ $# -eq 1 ] || die "usage: impl-profile.sh get <섹션>.<키>"
  [ -f "$PROFILE" ] || die "프로필 없음: $PROFILE"
  pget "$1" || { echo "ERROR: 키 없음: $1" >&2; exit 2; }
}

cmd_check() {
  local target="${2:-}"
  [ "${1:-}" = "--for" ] || target=""
  if [ ! -f "$PROFILE" ]; then
    echo "impl-chain 프로필이 없습니다: $PROFILE" >&2
    echo "  /impl-setup 을 실행하세요 (형식: impl-chain references/impl-profile-spec.md)." >&2
    exit 1
  fi

  local problems=()
  need()  { local v; v=$(pget "$1") && [ -n "$v" ] || problems+=("필수 키 없음: $1"); }
  oneof() { # $1=키, 나머지=허용 값
    local k=$1 v; shift
    v=$(pget "$k") || { problems+=("필수 키 없음: $k"); return; }
    local a; for a in "$@"; do [ "$v" = "$a" ] && return; done
    problems+=("$k 값 '$v' — 허용: $*")
  }
  needfile() { # $1=키 → 값이 가리키는 파일이 있어야 한다
    local v; v=$(pget "$1") && [ -n "$v" ] || { problems+=("필수 키 없음: $1"); return; }
    [ -e "$ROOT/$v" ] || problems+=("$1 가 가리키는 파일 없음: $v")
  }
  mode() { pget "$1.mode" 2>/dev/null || true; }
  needadapter() { # $1=어댑터 키 → 해석되고 실행 가능해야 한다. builtin이면 그 어댑터 필수 키도
    local v p; v=$(pget "$1") && [ -n "$v" ] || { problems+=("필수 키 없음: $1"); return; }
    p=$(resolve_adapter "$1" 2>&1) || { problems+=("$1: $p"); return; }
    [ -x "$p" ] || { problems+=("$1 가 가리키는 어댑터가 없거나 실행 불가: $v"); return; }
    case "$(builtin_name "$v")" in
      gh-spec-issue) need "이슈.spec_repo"; need "이슈.spec_link_regex" ;;
    esac
  }

  # 상태 파일·이슈 원문이 커밋되지 않도록 — .impl-spec/ 은 반드시 gitignore 대상
  git -C "$ROOT" check-ignore -q .impl-spec/x 2>/dev/null \
    || problems+=(".impl-spec/ 이 gitignore 대상이 아님 — 이슈 원문·상태 파일이 커밋될 수 있다. 레포 .gitignore에 '.impl-spec/' 한 줄을 추가하세요 (/impl-setup이 추가한다)")

  # 공통 필수
  oneof "서버 계약.mode" proto-repo none
  need  "git.standalone_base_candidates"; need "git.branch_format"; need "git.commit_format"
  need  "빌드.compile"; need "빌드.test"
  need  "코드.source_glob"; need "코드.trace_path"; need "코드.layer_order"
  case "$(mode "디자인 토큰")" in
    script|doc) problems+=("디자인 토큰.mode '$(mode "디자인 토큰")'는 폐지됨 — 'mode: map' + map(대응표, 빈 표 가능) + source(시맨틱 토큰 정의 파일)로 바꾸세요 (/impl-setup 갱신 모드)") ;;
    *) oneof "디자인 토큰.mode" map none ;;
  esac
  if [ "$(mode "UI 컴포넌트")" = discover ]; then
    problems+=("UI 컴포넌트.mode 'discover'는 map으로 통합됨 — 'mode: map' + 대응표 파일(빈 표 가능)로 바꾸세요")
  else
    oneof "UI 컴포넌트.mode" map none
  fi
  need  "UI 컴포넌트.figma_client"
  # 에셋 자동 export는 선택. 쓰면 결과를 둘 경로 템플릿도 있어야 한다
  pget "UI 컴포넌트.asset_export" > /dev/null 2>&1 && need "UI 컴포넌트.asset_target"
  oneof "문구.mode" rule hardcode
  oneof "화면 확인.mode" device-mock device adb-mock adb none   # adb-mock·adb = device-mock·device와 같은 뜻 (Android 전용이던 때의 이름)
  # 선택 키: 작업 중 추가한 테스트 코드를 커밋에 남길지 (없으면 discard)
  local tr; tr=$(pget "빌드.test_retention" 2>/dev/null) && { [ "$tr" = discard ] || [ "$tr" = keep ] || problems+=("빌드.test_retention 값 '$tr' — 허용: discard keep"); }
  # 선택 키: push·PR에 쓰는 원격 이름 (없으면 origin)
  local remote; remote=$(pget "git.remote" 2>/dev/null) && { [[ "$remote" =~ ^[A-Za-z0-9._-]+$ ]] || problems+=("git.remote 값 '$remote' — 원격 이름 한 단어여야 함"); }

  # 화이트라벨 앱 — 빌드 명령(또는 module_variants)이 {app}을 쓰면 빌드.apps가 있어야 하고, 항목은 이름이 겹치지 않아야 한다
  local uses_app="" k
  for k in compile test install install_real module_variants; do
    pget "빌드.$k" 2>/dev/null | grep -q '{app}' && uses_app=1
  done
  if pget "빌드.apps" > /dev/null 2>&1; then
    local an ab names=" " n_apps=0
    while IFS=$'\t' read -r an ab; do
      n_apps=$((n_apps + 1))
      [ -n "$an" ] && [ -n "$ab" ] || problems+=("빌드.apps 항목이 비어 있음 ('이름=값' 또는 '이름')")
      [[ "$an" =~ ^[A-Za-z0-9._-]+$ ]] || problems+=("빌드.apps 이름 '$an' — 영문·숫자·._- 만 (폴더·파일 이름에 쓴다)")
      case "$names" in *" $an "*) problems+=("빌드.apps 이름이 두 번: $an") ;; esac
      names="$names$an "
    done < <(app_entries)
    [ "$n_apps" -gt 0 ] || problems+=("빌드.apps 값이 비어 있음")
    [ -n "$uses_app" ] || problems+=("빌드.apps가 있는데 빌드 명령(compile·test·install·install_real·module_variants) 어디에도 {app}이 없음 — 앱을 골라도 빌드가 바뀌지 않는다")
  elif [ -n "$uses_app" ]; then
    problems+=("빌드 명령이 {app}을 쓰는데 빌드.apps가 없음")
  fi

  # 빌드 명령이 {variant}를 쓰면 모듈 → variant 대응이 있어야 한다
  if pget 빌드.compile 2>/dev/null | grep -q '{variant}' || pget 빌드.test 2>/dev/null | grep -q '{variant}'; then
    need "빌드.module_variants"
  fi

  # 모드별 조건부
  [ "$(mode "서버 계약")" = proto-repo ] && need "서버 계약.repo"
  if [ "$(mode "디자인 토큰")" = map ]; then
    needfile "디자인 토큰.map"
    local src f; src=$(pget "디자인 토큰.source") || src=""
    [ -n "$src" ] || problems+=("필수 키 없음: 디자인 토큰.source")
    for f in $src; do [ -e "$ROOT/$f" ] || problems+=("디자인 토큰.source 파일 없음: $f"); done
  fi
  [ "$(mode "UI 컴포넌트")" = map ]      && needfile "UI 컴포넌트.map"
  [ "$(mode "문구")" = rule ]            && needfile "문구.rule"
  case "$(mode "화면 확인")" in
    device|device-mock|adb|adb-mock)
      need "빌드.install"
      # 기기 어댑터 — 키가 없으면 기본값. 목록이면 우선순위 순서. 항목마다 해석되고 실행 가능해야 한다
      local de dp seen=" "
      while IFS= read -r de; do
        case "$seen" in *" $de "*) problems+=("$DEVICE_ADAPTER_KEY 에 같은 어댑터가 두 번: $de"); continue ;; esac
        seen="$seen$de "
        if dp=$(resolve_value "$de" 2>&1); then
          [ -x "$dp" ] || problems+=("$DEVICE_ADAPTER_KEY 가 가리키는 어댑터가 없거나 실행 불가: $de")
        else
          problems+=("$DEVICE_ADAPTER_KEY: $dp")
        fi
      done < <(device_entries)
      [ "$seen" != " " ] || problems+=("$DEVICE_ADAPTER_KEY 값이 비어 있음") ;;
  esac
  if [ "$(mode "화면 확인")" = device-mock ] || [ "$(mode "화면 확인")" = adb-mock ]; then
    # mock 스킬은 레포(.claude/skills) 또는 사용자 스킬 폴더(~/.claude/skills)에 있어야 한다
    local ms; ms=$(pget "화면 확인.mock_skill") && [ -n "$ms" ] \
      && { [ -f "$ROOT/.claude/skills/$ms/SKILL.md" ] || [ -f "$HOME/.claude/skills/$ms/SKILL.md" ] \
           || problems+=("화면 확인.mock_skill 스킬 없음: $ms (.claude/skills/ 또는 ~/.claude/skills/ — mock 없이 기기로만 볼 거면 mode: device)"); } \
      || problems+=("필수 키 없음: 화면 확인.mock_skill")
    # 선택: 실기기일 때만 쓰는 mock 스킬
    local msr; msr=$(pget "화면 확인.mock_skill_real" 2>/dev/null) && [ -n "$msr" ] \
      && { [ -f "$ROOT/.claude/skills/$msr/SKILL.md" ] || [ -f "$HOME/.claude/skills/$msr/SKILL.md" ] \
           || problems+=("화면 확인.mock_skill_real 스킬 없음: $msr (.claude/skills/ 또는 ~/.claude/skills/)"); }
  fi

  # 스킬별
  case "$target" in
    analyze-spec) needadapter "이슈.spec_adapter" ;;
    ""|start-work) ;;
    *) die "알 수 없는 --for 값: $target (analyze-spec | start-work)" ;;
  esac

  if [ ${#problems[@]} -gt 0 ]; then
    echo "impl-chain 프로필 검사 실패 ($PROFILE):" >&2
    printf '  - %s\n' "${problems[@]}" >&2
    exit 1
  fi
  echo "프로필 OK${target:+ ($target)}"
}

case "${1:-}" in
  get)     shift; cmd_get "$@" ;;
  check)   shift; cmd_check "$@" ;;
  adapter) shift; cmd_adapter "$@" ;;
  adapters) shift; cmd_adapters "$@" ;;
  apps)    shift; cmd_apps "$@" ;;
  *)       die "usage: impl-profile.sh get <섹션>.<키> | check [--for analyze-spec|start-work] | adapter <키> | adapters | apps" ;;
esac
