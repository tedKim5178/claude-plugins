---
name: impl-setup
description: Use when a repo has no impl-chain profile (.claude/impl-chain/profile.md) and the impl-spec chain needs to run there, when impl-profile.sh check fails, or when the repo's build, design tokens, string resources or issue setup changed and the profile must be refreshed
invocable: true
---

> **플러그인 `impl-chain`** — 이 플러그인의 스킬·에이전트는 `impl-chain:` 접두사로 부른다 (예: Skill `impl-chain:analyze-spec`, 에이전트 `impl-chain:code-researcher`). `${CLAUDE_PLUGIN_ROOT}`는 플러그인 설치 경로(절대 경로)로 치환되어 있다 — 명령에 그대로 쓴다. 레포별 값은 레포 루트 `.claude/impl-chain/`(프로필·어댑터)에 있다.


# Impl Setup

레포를 분석해 impl-chain 프로필(`.claude/impl-chain/profile.md`)과 레포 전용 어댑터를 만든다.
형식·키·모드·어댑터 계약: `${CLAUDE_PLUGIN_ROOT}/references/impl-profile-spec.md`. 완료 조건: `impl-profile.sh check` 통과.

**한 번 만들고 커밋해 두는 파일이다.** 체인은 실행마다 레포를 분석하지 않고 이 파일만 믿는다 — 그래서 여기서 추측하면 매 실행이 그 추측을 따른다.

## 입력

```
/impl-setup                 # .claude/impl-chain/ 에 생성 (있으면 갱신 모드)
/impl-setup --out <dir>     # 다른 경로에 생성 (검증용 — 기존 프로필과 비교할 때)
```
`--out`이면 이후 `impl-profile.sh` 호출에 `IMPL_PROFILE=<dir>/profile.md`를 붙인다.

## 사용자 확인 (이것뿐)

1. 갱신 모드에서 바뀌는 키 (Step 0)
2. repo-profiler의 질문 + `confidence: low` 키 (Step 3)
3. 최종 쓰기 직전 요약 승인 (Step 5)

## 실행 단계

### 0-0. 전제 확인 (GitHub + Android 레포 기준)

```bash
for t in git gh jq python3; do command -v $t > /dev/null || echo "없음: $t"; done
gh auth status 2>&1 | head -5                      # 로그인·scope (read:project는 BTS 상태 필터를 쓸 때만)
${CLAUDE_PLUGIN_ROOT}/scripts/android-device.sh adb               # 화면 확인용 adb (없으면 화면 확인.mode 후보에서 adb·adb-mock 제외)
git remote -v                                       # 원격이 둘 이상이면 Step 3에서 PR용 원격(git.remote)을 묻는다
git check-ignore -q .impl-spec/x && echo ".impl-spec ignored" || echo ".impl-spec NOT ignored"
```
필수 도구(git·gh·jq·python3)가 없거나 gh가 로그인 안 돼 있으면 설치·로그인 방법을 안내하고 **중단**. adb가 없으면 진행하되 보고에 남긴다.

### 0. 기존 프로필

`{out}/profile.md`가 있으면 **갱신 모드**: 현재 값을 읽고, Step 1에 `skip` 없이 전부 조사시킨 뒤
Step 3에서 **현재 값과 다른 키만** "현재 → 제안 (근거)"로 묻는다. 승인 없이 덮어쓰지 않는다. 사람이 손으로 바꾼 값일 수 있다.

### 1. 레포 분석 — `repo-profiler` 에이전트

| 파라미터 | 값 |
|---------|-----|
| `repo_root` | 레포 루트 |
| `spec_file` | `${CLAUDE_PLUGIN_ROOT}/references/impl-profile-spec.md` |
| `output_file` | `.impl-spec/setup/profile-proposal.md` |

메인은 코드 탐색을 직접 하지 않는다 — 제안서 요약으로 판단한다.

### 2. 제안서 검토 — 받아들이기 전에 메인이 확인

- **확인 방법이 "실행"이 아닌데 `high`인 키** → `medium`으로 내리고 Step 3 질문 후보로.
- **빌드**: `{variant}`를 쓰면 `module_variants`가 모든 모듈 유형을 덮는지. 안 쓰면 "모듈 유형별로 태스크 이름이 같다"는 근거가 있는지.
- **토큰 시드**: 시드 행의 근거가 Figma 이름 연결(주석·명명 규칙)이고 커버리지가 적혀 있는지. 이름 유사도뿐이면 시드를 버리고 빈 표로.
  `source`가 시맨틱 층 파일인지 — 팔레트 파일이 섞여 있으면 빼라고 되돌린다.
- **정책 키**(문구 `rule` 내용, 브랜치·커밋 형식, BTS 필터, 토큰 필수 여부)가 관찰만으로 확정돼 있으면 질문으로 돌린다.

### 3. 질문

AskUserQuestion으로 묻는다 (한 번에 최대 4개, 후보를 선택지로, 관찰 근거를 description에).
반드시 묻는 것 (근거가 아무리 강해도):
- **문구 정책**: 새 문구를 어디에 어떤 키로 넣는지 (`hardcode`로 둘지 포함). 관찰된 임시 파일 관례가 있으면 첫 선택지로.
- **브랜치·커밋 형식**: 이력의 관례가 둘 이상이면 분포를 보여주고.
- **BTS 필터**: 제외 라벨·프로젝트 상태 (gh `read:project` scope가 없으면 상태 필터를 쓰면 목록 조회가 실패한다는 점을 함께).
- **기획서 위치**: 링크 레포 후보가 둘 이상이거나, 기획서가 앱 이슈 자체에 있는 경우.
- **새 에셋 위치** (`asset_target`): drawable·asset 폴더가 둘 이상 모듈에 있으면 어느 모듈에 둘지 (분포를 보여주고)
- **화면 확인** (`화면 확인.mode`): `adb-mock`(서버 응답 mock 스킬이 있을 때 — 레포·`~/.claude/skills/`에서 찾은 후보를 보여주고) / `adb`(기기로만, 서버 상태가 필요한 케이스는 수동) / `none`. adb가 없으면 `none`만.
- **테스트 코드 보존** (`빌드.test_retention`): `discard`(기본 — 작업 중 추가한 테스트를 통과 확인 뒤 지우고 커밋하지 않음) / `keep`(테스트도 커밋). 레포에 기존 테스트가 많고 CI가 돌리면 `keep`을 첫 선택지로.
- **PR 원격** (`git.remote`): `git remote`가 둘 이상일 때만 (포크 구조면 PR을 올릴 쪽). 하나면 묻지 않고 키를 생략한다 (기본 origin).

"알아서 해"면 고른 값과 근거를 보고에 남긴다.

### 4. 레포 전용 어댑터

| 모드 | 만드는 것 | 검증 |
|------|----------|------|
| 토큰 `map` | `{out}/adapters/figma-token-map.md` — 시드 행(연결 근거가 있을 때) 또는 헤더만 있는 빈 표 (`\| Figma 변수 \| 토큰 \| 값 \| 근거 \|` + 구분선 — `apply-ui-decisions.py`가 이 헤더로 표를 찾는다). 시드가 많으면 일회성 생성 스크립트로 만들되 스크립트는 레포에 남기지 않는다 | ① 시드 행의 토큰 이름이 `source` 파일에 존재 (`git grep`) ② 시드 5개 샘플의 값 칸이 소스에서 해석한 값과 같은지 ③ 사용자가 Figma URL을 주면 `get_variable_defs` 값과 시드 값 칸을 대조 ④ `source` 파일 존재 |
| 컴포넌트 `map` | `{out}/adapters/figma-component-map.md` — 근거 있는 행만, 없으면 헤더만 있는 빈 표 (`\| Figma 컴포넌트 (data-name) \| 프로젝트 \| 비고 \| 근거 \|` + 구분선 — `apply-ui-decisions.py`가 이 헤더로 표를 찾는다) | 표의 프로젝트 컴포넌트가 코드에 존재 |
| 에셋 `asset_export` | 프로필 키만 (파일 없음) | 샘플 SVG 1개(`<svg … viewBox="0 0 24 24"><path d="M3 3h18v18H3z"/></svg>`)를 명령으로 변환해 결과가 프로젝트 형식인지 (Android: `<vector` 로 시작하는 xml) + `asset_lookup`을 레포에 있는 아이콘 이름 1개로 실행해 결과가 나오는지 |
| 문구 `rule` | `{out}/adapters/string-resources.md` — 규칙·금지·확인 세 절 (계약) | "확인" 절 명령을 실제로 한 번 실행해 오류 없이 도는지 |

이슈 어댑터는 GitHub이면 공용 — 만들지 않고 프로필에 `spec_adapter: builtin:gh-spec-issue`, `bts_adapter: builtin:gh-bts-issue`로 적는다 (경로를 적지 않는다 — 체인이 플러그인이면 경로가 레포 밖이다).
GitHub이 아니면 계약에 맞춘 어댑터를 `{out}/adapters/`에 만들고 `list`·`fetch`를 실제 이슈 1건으로 실행해 확인한다.

### 5. 쓰기 + 검증

1. 최종 값 요약(키 · 값 · 근거 · 사용자 결정 여부)과 **`.gitignore`에 `.impl-spec/` 추가 여부**(Step 0-0에서 NOT ignored였으면)를 보여주고 승인받는다.
   승인되면 `.gitignore`에 `.impl-spec/` 한 줄을 추가한다 — 상태 파일·이슈 원문·리서치가 커밋되는 것을 막는다 (프로필 게이트가 검사한다).
2. `{out}/profile.md` 작성. 맨 위 두 줄: 레포 이름 / `형식: ${CLAUDE_PLUGIN_ROOT}/references/impl-profile-spec.md`. 확인한 날짜가 의미 있는 값(빌드 variant 등)은 값 끝에 `(… 확인, YYYY-MM-DD)`.
3. 검증 — 하나라도 실패하면 고치고 다시. 3회 실패하면 보고 후 중단:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/impl-profile.sh check --for analyze-spec    # spec 어댑터를 쓰는 레포
   ${CLAUDE_PLUGIN_ROOT}/scripts/impl-profile.sh check --for analyze-bts     # bts 어댑터를 쓰는 레포
   ${CLAUDE_PLUGIN_ROOT}/scripts/impl-profile.sh check --for start-work
   A=$(${CLAUDE_PLUGIN_ROOT}/scripts/impl-profile.sh adapter 이슈.spec_adapter) && $A milestones && $A list {최근 마일스톤}   # 출력 형식이 계약대로인지
   B=$(${CLAUDE_PLUGIN_ROOT}/scripts/impl-profile.sh adapter 이슈.bts_adapter) && $B list | jq length                        # bts를 쓰면 (read:project 오류면 bts_project_status를 빼거나 gh auth refresh -s read:project)
   ```
   - 빌드: 모듈 유형마다 compile·test 명령의 태스크가 **존재**하는지 — 실제 빌드 없이 확인 (Gradle: `-m` dry-run, Xcode: `-list`·`-showBuildSettings`).

### 6. 보고

```
✅ impl-chain 프로필 생성 → {out}/profile.md
모드: 토큰 {mode} / 컴포넌트 {mode} / 문구 {mode} / 화면 확인 {mode} / 서버 계약 {mode}
어댑터: {만든 파일 목록}
사용자 결정: {질문과 답}
⚠️ 확인 필요: {confidence medium 이하로 남은 키, 환경 이슈(PATH·gh scope)}
```
커밋하지 않는다 (CLAUDE.md 규칙 — 사용자가 요청할 때만).

## 주의

- 이 스킬은 체인 문서(`skills/`, `agents/`, `scripts/`, `references/`)를 고치지 않는다. 레포 고유 값은 전부 `{out}/` 아래로.
- `.impl-spec/setup/`은 작업 파일이다 (`.impl-spec/`은 gitignore 대상 — Step 5에서 추가).
