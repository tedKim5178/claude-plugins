#!/bin/bash
# impl-profile.sh 테스트. 실행: scripts/tests/impl-profile.test.sh
# 임시 레포(fixture 프로필)에서 get/check/adapter 동작을 검사한다 — 이 레포 프로필과 무관.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
P="$SCRIPTS/impl-profile.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
make_repo "$T/repo" && cd "$T/repo"
BASE=.claude/impl-chain/profile.md
FAIL=0
ok()   { echo "  ok   $1"; }
bad()  { echo "  FAIL $1"; FAIL=1; }
expect_exit() { # $1=설명 $2=기대 exit, 나머지=명령
  local d=$1 want=$2; shift 2
  "$@" > "$T/out" 2> "$T/err"; local got=$?
  [ "$got" = "$want" ] && ok "$d" || { bad "$d (exit $got, 기대 $want) $(head -3 "$T/err")"; }
}
variant() { # $1=이름, stdin=sed 스크립트 → 변형 프로필 경로 출력
  sed -f /dev/stdin "$BASE" > "$T/$1.md"; echo "$T/$1.md"
}
secsed() { # $1=이름 $2=섹션 $3=sed 명령(그 섹션 안에만 적용) → 변형 프로필 경로 출력
  sed "/^## $2\$/,/^## /{$3;}" "$BASE" > "$T/$1.md"; echo "$T/$1.md"
}

echo "get"
[ "$($P get 서버\ 계약.mode)" = "proto-repo" ] && ok "섹션 이름에 공백" || bad "섹션 이름에 공백"
[ "$($P get 빌드.compile)" = "./gradlew :{module}:compile{variant}Kotlin" ] && ok "값 그대로" || bad "값 그대로"
[ "$($P get 코드.source_glob)" = "'*.kt'" ] && ok "따옴표 보존" || bad "따옴표 보존"
[ "$($P get 코드.navigation)" = "\`NavGraph.kt\` 등" ] && ok "부분 백틱 보존" || bad "부분 백틱 보존: $($P get 코드.navigation)"
expect_exit "없는 키 exit 2" 2 $P get 빌드.nope
expect_exit "없는 섹션 exit 2" 2 $P get 없음.mode

echo "adapter"
[ "$($P adapter 이슈.spec_adapter)" = "$SCRIPTS/spec-issue.sh" ] && ok "builtin:spec-issue → 공용 어댑터" || bad "spec adapter=$($P adapter 이슈.spec_adapter)"
F=$(variant old-name-adapter <<< 's#^- spec_adapter: .*#- spec_adapter: builtin:gh-spec-issue#')
[ "$(IMPL_PROFILE="$F" $P adapter 이슈.spec_adapter)" = "$SCRIPTS/spec-issue.sh" ] && ok "예전 이름 builtin:gh-spec-issue도 공용 어댑터로" || bad "old name"
IMPL_PROFILE="$F" $P check --for analyze-spec > /dev/null 2>&1 && ok "예전 이름으로도 게이트 통과" || bad "old name check"
F=$(variant legacy-adapter <<< 's#^- spec_adapter: .*#- spec_adapter: .claude/scripts/gh-spec-issue.sh#')
[ "$(IMPL_PROFILE="$F" $P adapter 이슈.spec_adapter)" = "$SCRIPTS/spec-issue.sh" ] && ok "예전 레포 경로 값도 builtin으로" || bad "legacy"
mkdir -p tools && printf '#!/bin/bash\n' > tools/my-adapter.sh && chmod +x tools/my-adapter.sh
F=$(variant repo-adapter <<< 's#^- spec_adapter: .*#- spec_adapter: tools/my-adapter.sh#')
[ "$(IMPL_PROFILE="$F" $P adapter 이슈.spec_adapter)" = "$(pwd -P)/tools/my-adapter.sh" ] && ok "레포 전용 어댑터는 레포 경로" || bad "repo adapter=$(IMPL_PROFILE="$F" $P adapter 이슈.spec_adapter)"
F=$(variant bad-builtin <<< 's#^- spec_adapter: .*#- spec_adapter: builtin:jira#')
expect_exit "모르는 builtin은 exit 1" 1 env IMPL_PROFILE="$F" $P adapter 이슈.spec_adapter

echo "check — fixture 레포"
expect_exit "기본 통과" 0 $P check
expect_exit "analyze-spec 통과" 0 $P check --for analyze-spec
expect_exit "analyze-bts는 없는 대상 (삭제됨)" 1 $P check --for analyze-bts
expect_exit "start-work 통과" 0 $P check --for start-work

echo "check — 실패해야 하는 변형"
F=$(variant no-file <<< 's/x/x/'); rm "$F"
expect_exit "프로필 없음" 1 env IMPL_PROFILE="$F" $P check
F=$(variant no-commit <<< '/^- commit_format:/d')
expect_exit "필수 키 누락 (git.commit_format)" 1 env IMPL_PROFILE="$F" $P check
grep -q "git.commit_format" "$T/err" && ok "누락 키 이름을 보고" || bad "누락 키 이름을 보고"
F=$(variant bad-mode <<< 's/^- mode: rule$/- mode: rulez/')
expect_exit "모드 값 범위 밖" 1 env IMPL_PROFILE="$F" $P check
F=$(secsed no-token-map "디자인 토큰" 's#^- map: .*#- map: .claude/impl-chain/adapters/none.md#')
expect_exit "모드가 가리키는 파일 없음 (토큰 대응표)" 1 env IMPL_PROFILE="$F" $P check
F=$(secsed token-script "디자인 토큰" 's/^- mode: map$/- mode: script/')
expect_exit "토큰 script 모드 폐지" 1 env IMPL_PROFILE="$F" $P check
grep -q "폐지" "$T/err" && ok "script 폐지 안내" || bad "script 폐지 안내: $(cat "$T/err")"
F=$(secsed token-no-source "디자인 토큰" '/^- source: /d')
expect_exit "토큰 map인데 source 없음" 1 env IMPL_PROFILE="$F" $P check
F=$(secsed token-bad-source "디자인 토큰" 's#^\(- source: .*\)$#\1 nope/Missing.kt#')
expect_exit "source 파일 하나 없음" 1 env IMPL_PROFILE="$F" $P check
grep -q "nope/Missing.kt" "$T/err" && ok "없는 source 파일 보고" || bad "없는 source 파일 보고"
F=$(variant no-repo <<< '/^- repo: /d')
expect_exit "proto-repo인데 repo 없음" 1 env IMPL_PROFILE="$F" $P check
F=$(variant no-spec-regex <<< '/^- spec_link_regex:/d')
expect_exit "builtin spec 어댑터인데 spec_link_regex 없음 (analyze-spec)" 1 env IMPL_PROFILE="$F" $P check --for analyze-spec
expect_exit "같은 변형이라도 start-work는 통과" 0 env IMPL_PROFILE="$F" $P check --for start-work
F=$(printf '/^- spec_adapter:/a\\\n- bts_adapter: builtin:gh-bts-issue\n' | variant old-bts-keys)   # bash 3.2: $( ) 안 heredoc 금지
grep -q "^- bts_adapter: builtin:gh-bts-issue$" "$F" && ok "변형 프로필에 예전 bts 키" || bad "변형 프로필 생성"
expect_exit "예전 프로필의 bts_adapter 키는 무시하고 통과" 0 env IMPL_PROFILE="$F" $P check --for analyze-spec
expect_exit "builtin:gh-bts-issue는 더 이상 공용 어댑터가 아님" 1 env IMPL_PROFILE="$F" $P adapter 이슈.bts_adapter
F=$(variant missing-repo-adapter <<< 's#^- spec_adapter: .*#- spec_adapter: tools/none.sh#')
expect_exit "레포 어댑터 파일 없음 (analyze-spec)" 1 env IMPL_PROFILE="$F" $P check --for analyze-spec
F=$(variant no-variants <<< '/^- module_variants:/d')
expect_exit "{variant}를 쓰는데 module_variants 없음" 1 env IMPL_PROFILE="$F" $P check
F=$(secsed discover "UI 컴포넌트" 's/^- mode: map$/- mode: discover/; /^- map: /d')
expect_exit "UI 컴포넌트.mode discover 거부" 1 env IMPL_PROFILE="$F" $P check
F=$(variant no-asset-target <<< '/^- asset_target:/d')
expect_exit "asset_export 있는데 asset_target 없음" 1 env IMPL_PROFILE="$F" $P check
F=$(variant no-mock <<< 's/^- mock_skill: .*/- mock_skill: nope-mock/')
expect_exit "adb-mock인데 mock 스킬 없음" 1 env IMPL_PROFILE="$F" $P check
F=$(variant bad-remote <<< 's/^- commit_format: .*/&\n- remote: no such/')
expect_exit "git.remote 값에 공백" 1 env IMPL_PROFILE="$F" $P check

echo "check — gitignore"
mv .gitignore gi.bak
expect_exit ".impl-spec/가 gitignore 대상이 아니면 실패" 1 $P check
grep -q ".impl-spec/" "$T/err" && grep -q ".gitignore" "$T/err" && ok "추가 방법 안내" || bad "안내 없음: $(cat "$T/err")"
mv gi.bak .gitignore

echo "check — 통과해야 하는 변형"
F=$(variant all-none <<< 's/^- mode: proto-repo$/- mode: none/; /^- repo: /d; /^- source: /d; s/^- mode: map$/- mode: none/; /^- map: /d; s/^- mode: rule$/- mode: hardcode/; /^- rule: /d; s/^- mode: adb-mock$/- mode: none/; /^- mock_skill: /d; /^- install: /d')
expect_exit "모드 전부 none/hardcode + 조건부 키 없음" 0 env IMPL_PROFILE="$F" $P check
F=$(variant no-asset <<< '/^- asset_export:/d; /^- asset_target:/d')
expect_exit "asset 키 둘 다 없음 (선택 키)" 0 env IMPL_PROFILE="$F" $P check
F=$(variant adb-only <<< 's/^- mode: adb-mock$/- mode: adb/; /^- mock_skill: /d')
expect_exit "화면 확인 adb (mock 없이)" 0 env IMPL_PROFILE="$F" $P check
F=$(variant device-mock <<< 's/^- mode: adb-mock$/- mode: device-mock/')
expect_exit "화면 확인 device-mock (adb-mock과 같은 뜻)" 0 env IMPL_PROFILE="$F" $P check
F=$(variant device-only <<< 's/^- mode: adb-mock$/- mode: device/; /^- mock_skill: /d')
expect_exit "화면 확인 device (mock 없이)" 0 env IMPL_PROFILE="$F" $P check
F=$(variant device-mock-no-skill <<< 's/^- mode: adb-mock$/- mode: device-mock/; /^- mock_skill: /d')
expect_exit "device-mock도 mock_skill 필수" 1 env IMPL_PROFILE="$F" $P check

echo "기기 어댑터"
[ "$($P adapter "화면 확인.device_adapter")" = "$SCRIPTS/android-device.sh" ] && ok "키 없으면 builtin:android-device" || bad "기본 기기 어댑터: $($P adapter "화면 확인.device_adapter" 2>&1)"
F=$(variant dev-builtin <<< 's/^- mock_skill: .*/&\n- device_adapter: builtin:android-device/')
[ "$(env IMPL_PROFILE="$F" $P adapter "화면 확인.device_adapter")" = "$SCRIPTS/android-device.sh" ] && ok "builtin:android-device 해석" || bad "builtin:android-device 해석"
expect_exit "builtin 기기 어댑터 check 통과" 0 env IMPL_PROFILE="$F" $P check
F=$(variant dev-ios <<< 's/^- mock_skill: .*/&\n- device_adapter: builtin:ios-device/')
[ "$(env IMPL_PROFILE="$F" $P adapter "화면 확인.device_adapter")" = "$SCRIPTS/ios-device.sh" ] && ok "builtin:ios-device 해석" || bad "builtin:ios-device 해석"
expect_exit "builtin:ios-device check 통과" 0 env IMPL_PROFILE="$F" $P check
F=$(variant dev-ios-real <<< 's/^- mock_skill: .*/&\n- device_adapter: builtin:ios-real-device/')
[ "$(env IMPL_PROFILE="$F" $P adapter "화면 확인.device_adapter")" = "$SCRIPTS/ios-real-device.sh" ] && ok "builtin:ios-real-device 해석" || bad "builtin:ios-real-device 해석"
printf '#!/bin/bash\necho custom\n' > .claude/impl-chain/adapters/ios-device.sh && chmod +x .claude/impl-chain/adapters/ios-device.sh
F=$(variant dev-custom <<< 's/^- mock_skill: .*/&\n- device_adapter: .claude\/impl-chain\/adapters\/ios-device.sh/')
[ "$(env IMPL_PROFILE="$F" $P adapter "화면 확인.device_adapter")" = "$(pwd -P)/.claude/impl-chain/adapters/ios-device.sh" ] && ok "레포 전용 기기 어댑터 경로" || bad "레포 전용 기기 어댑터 경로: $(env IMPL_PROFILE="$F" $P adapter "화면 확인.device_adapter" 2>&1) vs $(pwd -P)"
expect_exit "레포 전용 기기 어댑터 check 통과" 0 env IMPL_PROFILE="$F" $P check
F=$(variant dev-missing <<< 's/^- mock_skill: .*/&\n- device_adapter: .claude\/impl-chain\/adapters\/nope.sh/')
expect_exit "기기 어댑터 파일 없으면 실패" 1 env IMPL_PROFILE="$F" $P check
grep -q "device_adapter" "$T/err" && ok "기기 어댑터 오류 보고" || bad "기기 어댑터 오류 보고: $(cat "$T/err")"
F=$(variant dev-bad-builtin <<< 's/^- mock_skill: .*/&\n- device_adapter: builtin:nope/')
expect_exit "알 수 없는 builtin 기기 어댑터 실패" 1 env IMPL_PROFILE="$F" $P check
F=$(variant dev-missing-none <<< 's/^- mode: adb-mock$/- mode: none/; s/^- mock_skill: .*/- device_adapter: .claude\/impl-chain\/adapters\/nope.sh/; /^- install: /d')
expect_exit "mode none이면 기기 어댑터를 검사하지 않음" 0 env IMPL_PROFILE="$F" $P check

echo "기기 어댑터 — 우선순위 목록"
[ "$($P adapters)" = "$SCRIPTS/android-device.sh" ] && ok "adapters — 키 없으면 기본 하나" || bad "adapters 기본: $($P adapters 2>&1)"
F=$(variant dev-list <<< 's/^- mock_skill: .*/&\n- device_adapter: builtin:ios-real-device, `builtin:ios-device`/')
[ "$(env IMPL_PROFILE="$F" $P adapters | tr '\n' ' ')" = "$SCRIPTS/ios-real-device.sh $SCRIPTS/ios-device.sh " ] && ok "목록 순서대로 (공백·백틱 정리)" || bad "adapters 목록: $(env IMPL_PROFILE="$F" $P adapters 2>&1)"
expect_exit "목록 check 통과" 0 env IMPL_PROFILE="$F" $P check
expect_exit "목록인데 adapter(단수)는 exit 1" 1 env IMPL_PROFILE="$F" $P adapter "화면 확인.device_adapter"
grep -q "adapters" "$T/err" && ok "adapters 안내" || bad "안내 없음: $(cat "$T/err")"
F=$(variant dev-list-bad <<< 's/^- mock_skill: .*/&\n- device_adapter: builtin:ios-real-device, builtin:nope/')
expect_exit "목록에 모르는 builtin" 1 env IMPL_PROFILE="$F" $P check
grep -q "builtin:nope" "$T/err" && ok "틀린 항목 보고" || bad "보고: $(cat "$T/err")"
expect_exit "adapters도 실패" 1 env IMPL_PROFILE="$F" $P adapters
F=$(variant dev-list-dup <<< 's/^- mock_skill: .*/&\n- device_adapter: builtin:ios-device, builtin:ios-device/')
expect_exit "같은 어댑터 두 번" 1 env IMPL_PROFILE="$F" $P check
F=$(variant dev-list-empty <<< 's/^- mock_skill: .*/&\n- device_adapter: ,/')
expect_exit "빈 목록" 1 env IMPL_PROFILE="$F" $P check

echo "실기기 전용 키"
F=$(variant real-keys <<< 's/^- mock_skill: .*/&\n- mock_skill_real: fake-mock/')
expect_exit "mock_skill_real 있는 스킬이면 통과" 0 env IMPL_PROFILE="$F" $P check
F=$(variant real-keys-bad <<< 's/^- mock_skill: .*/&\n- mock_skill_real: no-such-mock/')
expect_exit "mock_skill_real 스킬 없으면 실패" 1 env IMPL_PROFILE="$F" $P check
grep -q "mock_skill_real" "$T/err" && ok "mock_skill_real 보고" || bad "보고: $(cat "$T/err")"

echo "화이트라벨 앱"
[ -z "$($P apps)" ] && ok "apps — 키 없으면 출력 없음" || bad "apps 기본: $($P apps)"
F=$(variant apps <<< 's/^- install: .*/- install: .\/gradlew :app:install{app}DevDebug\n- apps: shucle=Shucle, `gmaas=Gmaas`, sejong/')
[ "$(env IMPL_PROFILE="$F" $P apps | tr '\t\n' ':|')" = "shucle:Shucle|gmaas:Gmaas|sejong:sejong|" ] && ok "이름·값 순서대로 (값 없으면 이름)" || bad "apps: $(env IMPL_PROFILE="$F" $P apps)"
expect_exit "{app}을 쓰고 apps가 있으면 통과" 0 env IMPL_PROFILE="$F" $P check
F=$(variant apps-missing <<< 's/^- install: .*/- install: .\/gradlew :app:install{app}DevDebug/')
expect_exit "{app}을 쓰는데 apps 없음" 1 env IMPL_PROFILE="$F" $P check
grep -q "빌드.apps가 없음" "$T/err" && ok "apps 없음 보고" || bad "보고: $(cat "$T/err")"
F=$(variant apps-unused <<< 's/^- install: .*/&\n- apps: a, b/')
expect_exit "apps가 있는데 {app}을 안 씀" 1 env IMPL_PROFILE="$F" $P check
F=$(variant apps-dup <<< 's/^- install: .*/- install: x {app}\n- apps: a=A, a=B/')
expect_exit "앱 이름 중복" 1 env IMPL_PROFILE="$F" $P check
F=$(variant apps-badname <<< 's/^- install: .*/- install: x {app}\n- apps: 세종=Sejong/')
expect_exit "앱 이름에 한글·공백" 1 env IMPL_PROFILE="$F" $P check

echo "check — 그 외 변형"
F=$(variant adb-no-install <<< 's/^- mode: adb-mock$/- mode: adb/; /^- mock_skill: /d; /^- install: /d')
expect_exit "adb 모드도 install 필수" 1 env IMPL_PROFILE="$F" $P check
mkdir -p "$T/home/.claude/skills/user-mock" && echo x > "$T/home/.claude/skills/user-mock/SKILL.md"
F=$(variant user-mock <<< 's/^- mock_skill: .*/- mock_skill: user-mock/')
expect_exit "mock 스킬이 사용자 스킬 폴더에 있어도 통과" 0 env HOME="$T/home" IMPL_PROFILE="$F" $P check
F=$(variant retention-keep <<< 's/^- test_source_hint: .*/- test_retention: keep/')
expect_exit "빌드.test_retention 선택 키 (keep)" 0 env IMPL_PROFILE="$F" $P check
F=$(variant retention-bad <<< 's/^- test_source_hint: .*/- test_retention: sometimes/')
expect_exit "빌드.test_retention 값 범위 밖" 1 env IMPL_PROFILE="$F" $P check
grep -q "test_retention" "$T/err" && ok "test_retention 값 오류 보고" || bad "test_retention 값 오류 보고: $(cat "$T/err")"
F=$(variant remote <<< 's/^- commit_format: .*/&\n- remote: upstream/')
expect_exit "git.remote 선택 키" 0 env IMPL_PROFILE="$F" $P check
F=$(printf '/^- commit_format:/a\\\n- platform: gitlab\n' | variant platform-ok)   # bash 3.2: $( ) 안 heredoc 금지
expect_exit "git.platform gitlab" 0 env IMPL_PROFILE="$F" $P check
F=$(printf '/^- commit_format:/a\\\n- platform: bitbucket\n' | variant platform-bad)
expect_exit "git.platform 값 범위 밖" 1 env IMPL_PROFILE="$F" $P check
grep -q "git.platform" "$T/err" && ok "git.platform 값 오류 보고" || bad "git.platform 값 오류 보고: $(cat "$T/err")"

[ $FAIL = 0 ] && echo "ALL PASS" || { echo "FAILED"; exit 1; }
