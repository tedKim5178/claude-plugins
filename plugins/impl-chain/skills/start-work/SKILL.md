---
name: start-work
description: 버그 수정 또는 기능 구현을 시작할 때 사용. 브랜치 생성부터 코드 수정, 컴파일, 테스트, 리뷰, 커밋(한 개)까지 수행
invocable: true
---

> **플러그인 `impl-chain`** — 이 플러그인의 스킬·에이전트는 `impl-chain:` 접두사로 부른다 (예: Skill `impl-chain:analyze-spec`, 에이전트 `impl-chain:code-researcher`). `${CLAUDE_PLUGIN_ROOT}`는 플러그인 설치 경로(절대 경로)로 치환되어 있다 — 명령에 그대로 쓴다. 레포별 값은 레포 루트 `.claude/impl-chain/`(프로필·어댑터)에 있다.


# Start Work

메인 워크스페이스에서 작업 브랜치를 만들고
**테스트 작성 → 구현 → 컴파일 → 테스트 → (화면 확인) → 리뷰 → 테스트 정리 → 커밋**까지 수행한다.

**커밋은 작업 전체에 하나다.** 규모(small/large)와 무관하게 리뷰가 끝난 뒤 Step 10에서 한 번만 커밋한다 — task별·리뷰 반영분 커밋으로 나누지 않는다.

## 호출 경로 2가지

| 경로 | 상태 파일 | 동작 차이 |
|------|----------|----------|
| **체인** (`impl-spec`/`analyze-spec` → 여기) | `.impl-spec/{type}-{n}.json`, `stage: analyzed` | base·브랜치·todo·검증 커맨드를 파일에서 읽는다. Step 0은 **미리보기만** (묻지 않음) |
| **단독** (`/start-work {브랜치명}`, 예: `fix/xxx`) | 없음 | Step 0 승인 게이트 + Step 1 base 선택 |

**상태 파일 선택** — `${CLAUDE_PLUGIN_ROOT}/references/impl-state-file.md`의 "상태 파일 선택 규칙"을 따른다.
**"가장 최근 파일"로 고르지 않는다.** `/start-work fix/xxx`처럼 브랜치 인자(`/`를 포함한 이름)가 주어졌으면
사용자는 단독 작업을 원한 것이다 — 남아 있는 analyzed 파일로 체인 경로에 빠지지 않는다.

체인 경로에서 쓰는 도구: `S=${CLAUDE_PLUGIN_ROOT}/scripts/impl-state.sh`, 키는 `{type} {n}` (예: `spec 4895`).

## 자동 진행 원칙

코드 수정 이후는 묻지 않고 진행한다. 멈추는 경우는 이것뿐:
- 커밋 안 된 변경 때문에 브랜치를 못 바꿀 때 (Step 2)
- 근거 없는 동작을 결정해야 할 때 (Step 0-1)
- 같은 단계 3회 실패, 리뷰 2차 FAIL

## 출력 원칙

| 시점 | 출력 |
|------|------|
| Step 0 | 수정 파일 + 변경 내용 요약 (단독이면 + "진행할까요?") |
| 구현 후 | 무엇을 왜 바꿨는지 한두 줄 |
| 완료 | Step 12 보고 |

git·빌드 명령과 로그 원문, "컴파일 중입니다" 같은 중간 알림은 출력하지 않는다.

---

## 실행 단계

### 0-0. 프로필 게이트 (체인·단독 모두 — 분석 뒤에 프로필이 바뀌거나 지워졌을 수 있다)

`${CLAUDE_PLUGIN_ROOT}/scripts/impl-profile.sh check --for start-work` — exit 0이 아니면 stderr의 문제 목록을 그대로 보여주고 **중단**.
이후 "프로필 `X.Y`"는 `.claude/impl-chain/profile.md`의 값이다 (체인 경로도 같다).

### 0. 수정 방향 미리보기

체인: `$S get {type} {n}`으로 todo_items·files_to_modify·implementation_direction·decisions를 읽는다.
수정 대상 파일을 Read해 **기존 스타일을 파악하고** 맞춘다. 어디를 바꿀지는 code 리서치 1번 매핑표를 따른다.

```
이렇게 수정하려고 합니다:
T1 → `SeatItem.kt`: ...
T2 → (문구 리소스 파일): 새 문구 키 추가 ...
```

- 단독: "진행할까요?"를 붙이고 승인 전에는 손대지 않는다.
- 체인: 이미 승인된 내용이다. **다시 묻지 않고** 바로 Step 1.

### 0-1. 근거 없는 동작은 추측하지 않는다 (언제든)

구현 중 todo `acceptance`·`decisions` 어디에도 없는 세부 동작(이동 경로, 플래그 값, 분기 조건, 문구)을
정해야 하면 **그 자리에서 멈추고** AskUserQuestion으로 후보와 근거(또는 근거 없음)를 제시한다.
체인이면 답을 `decisions`에 추가한다 (배열은 통째 교체이므로 기존 배열 + 새 항목을 merge). 단독이면 완료 보고에 결정 사항으로 남긴다:
```bash
$S get {type} {n} '.decisions + [{"question":"...","answer":"...","by":"user"}] | {decisions: .}' | $S merge {type} {n}
```
"그럴듯한 기존 화면"을 연결하고 완료로 보고하면 사용자는 실기기에서야 잘못을 발견한다.

- 물을 때도 후보마다 근거(비슷한 기존 화면의 처리 `파일:라인`)를 달고 추천을 첫 선택지로 둔다. 같은 task에서 질문이 여러 개 나오면 한 번에 모아 묻는다.
- 체인이면 decision에 `"source": "start-work"`를 단다 — 예외 케이스(에러 분류·빈 응답·백스택·1회성 상태 등)가 여기서 나왔다면 analyze의 code 리서치 2-1이 놓친 것이다. 완료 보고에 개수를 적어 체크리스트 개선 근거로 남긴다.

### 1. base 브랜치 · 확인할 앱
- 체인: `$S get {type} {n} .base_branch`. **묻지 않는다.**
- 단독: AskUserQuestion — 선택지 = 프로필 `git.standalone_base_candidates` + 현재 브랜치 + Other

**확인할 앱** (프로필 `빌드.apps`가 있을 때 — 화이트라벨): 이후 `{apps}`.
- 체인: `$S get {type} {n} '.apps // empty'`. 없으면(`빌드.apps`가 생긴 뒤 분석 전의 상태 파일) 기본 앱 하나. **묻지 않는다.**
- 단독: `${CLAUDE_PLUGIN_ROOT}/scripts/impl-profile.sh apps`의 앱이 2개 이상이면 analyze-spec Step 1-1과 같은 질문을 base 질문과 함께 묻는다 (기본 앱만이 첫 선택지).
- 앱마다 `{app}` = `impl-profile.sh apps`에서 그 이름의 **값**이다 (이름이 아니다 — 예: 이름 `gmaas` → 값 `Gmaas`).

### 2. 작업 브랜치 (메인 워크스페이스)

```bash
PREV=$(git branch --show-current)
${CLAUDE_PLUGIN_ROOT}/scripts/setup-branch.sh {base_branch} {branch}
```

| exit | 처리 |
|------|------|
| 0 | 체인이면 `echo "{\"previous_branch\":\"$PREV\"}" \| $S merge {type} {n}` 후 진행 (재개로 이미 브랜치 위면 생략) |
| 2 | 커밋 안 된 변경 목록을 보여주고 중단. "커밋하거나 stash한 뒤 다시 실행해주세요." **직접 stash·commit·checkout 하지 않는다** |
| 3 | 같은 이름 브랜치가 이미 있음 → AskUserQuestion: 그 브랜치로 이어서 작업(`git switch {branch}`, 변경이 없을 때만) / 중단 |
| 4 | 로컬 base 브랜치 없음 (이름 오류·삭제됨) → 보고 후 중단 |
| 1 | 기타 git 오류 → 메시지 그대로 보고 후 중단 |

이후 모든 작업은 이 브랜치에서 한다. 체인이면 커밋 전에 `$S check-branch {type} {n}`.

### 2-1. UI 결정 반영 (체인 — `decisions[].apply`가 있을 때)

analyze에서 승인된 컴포넌트·토큰 대응표 행과 에셋을 **이 브랜치 위에서** 반영한다 (analyze는 base 브랜치 위라 레포 파일을 쓰지 않았다).
```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/apply-ui-decisions.py {type} {n}
```

| exit | 처리 |
|------|------|
| 0 | exit 0·3 모두 출력의 `CHANGED {path}`마다 `git add -N {path}`. 0이면 그 후 진행 |
| 3 | 먼저 `CHANGED {path}`마다 `git add -N {path}`. 그다음 `CONFLICT` 줄(다른 브랜치가 대응표·파일을 먼저 바꿈)을 보여주고 AskUserQuestion: 현재 대응표·파일을 따름(그 decision의 answer·apply를 고쳐 merge) / 결정대로 직접 수정 / 중단. 처리 후 다시 실행 |
| 1·2 | 메시지 그대로 보고 후 중단 |

재개 시 다시 실행해도 된다 — 반영된 항목은 `SKIP`.
재실행에서 SKIP된 에셋이 아직 추적되지 않았으면(`git ls-files --error-unmatch {target}` 실패) `git add -N`. 반영분은 Step 10의 커밋에 포함한다.

### 3. 작업 분할 (size 기준)

- **small** (단독 경로는 항상 small): Step 4~7을 메인이 직접 수행.
- **large**: todo를 의존 순서(프로필 `코드.layer_order`)로 1~3개씩 묶어 task로 만들고 기록:
  ```bash
  echo '{"tasks":[{"id":"K1","todo_ids":["T1","T2"],"files":["..."]}]}' | $S merge {type} {n}
  ```
  task마다 **순서대로** `general-purpose` 서브에이전트를 스폰한다 (같은 작업 트리이므로 병렬 금지).
  전달: 상태 파일 경로, 담당 todo id, research 파일 경로, Step 4~7 절차(이 문서의 해당 부분), compile/test task.
  서브에이전트는 커밋하지 않는다. 돌아오면 메인이 `git diff --stat`으로 범위를 확인하고,
  compile·test를 직접 다시 돌려 통과를 확인한 뒤 `tasks` 배열에서 해당 task에 `"done": true`를 넣어 merge한다.
  **task 단위로 커밋하지 않는다** — 변경은 작업 트리에 쌓아 두고(신규 파일은 `git add -N`), 모든 task가 끝난 뒤
  Step 8~9(화면 확인·리뷰)를 전체 diff에 대해 한 번 수행하고 Step 10에서 한 번에 커밋한다.
  **재개 시 `done`인 task는 건너뛴다** (작업 트리에 그 task의 변경이 남아 있는지 `git status`로 확인하고, 없으면 `done`을 지우고 다시 한다).

### 3-1. UI 스펙 (체인 + `figma.status=ok` + visual todo가 있을 때 — 생략 불가)

- **`ui_specs`가 있으면** (analyze Step 4-1에서 만들어져 승인됨): 다시 만들지 않는다. `$S get {type} {n} '.ui_specs'`의 `file`들이 구현 기준이다. 묻지 않는다.
- **없으면** (`ui_specs`가 없는 이전 schema 2 상태 파일): 폴백 — visual todo의 `figma_screens`를 화면 그룹 단위로 묶어 `figma-ui-spec`을 스폰한다
  (그룹이 여러 개면 한 메시지에서 병렬). 전달: `todo_file`(상태 파일 경로), `figma_dir`, `screen_ids`, `issue_key: {type}-{n}`, `spec_research_file`(상태 파일 `research_files` 중 `.research.spec.md`).
  에이전트가 쓴 result.json을 병합한다: `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/merge-ui-results.py $($S path {type} {n}) {RESULT 경로들}` (상태 파일에 `ui_specs`·decisions·open_questions가 들어간다).
  생긴 `open_questions`는 Step 0-1처럼 묻고 decisions로 옮긴 뒤(답의 `apply_by_answer` → `apply`) `open_questions`를 비워 merge한다.
  apply가 생겼으면 Step 2-1을 다시 실행한다.
- 이후 **Step 5의 UI 구현은 ui-spec을 기준으로 한다.** 트리·표에 없는 값(색상·크기·아이콘)을 임의로 쓰지 않는다.
  색상·타이포는 표의 토큰 그대로, 케이스 간 차이표의 모든 행을 조건 분기로 구현한다.

### 4. 테스트 먼저 (RED)

체인: `verify: unit` todo마다 / 단독: 수정할 로직이 유닛 테스트 가능하면 재현 조건 하나를 —
**구현 전에** acceptance(기대 동작)를 단언하는 테스트를 쓴다.
- 테스트 이름에 todo id를 넣는다: `` `T1 PREMIUM 등급이면 프리미엄 뱃지를 노출한다`() ``
- code 리서치 4번의 "참고 테스트" 스타일을 따른다.
- 실행해서 **기대한 이유로 실패하는지** 확인한다 (새 심볼이 없어서 나는 컴파일 에러, 또는 단언 실패).
  이미 통과하면 테스트가 acceptance를 단언하지 않는 것이다 — 고친다.
- 모듈에 테스트 인프라가 없으면 todo를 `manual`로 취급하고 사유를 `verification.notes`에 남긴다.
- 프로필 `빌드.test_retention`이 `discard`(기본)면 여기서 쓰는 테스트는 **검증용 임시 코드**다 — Step 9-1에서 지우므로,
  새 테스트는 가능하면 **새 파일**에 쓴다 (기존 테스트 파일에 케이스를 끼워 넣으면 정리할 때 가려내야 한다).

`test-driven-development` 스킬(superpowers)의 RED-GREEN 원칙을 따른다.

### 5. 구현 (GREEN)
- 테스트를 통과시키는 방향으로 구현한다. todo·decisions에 없는 동작은 추가하지 않는다.
- UI는 ui-spec의 **레이아웃 트리로 골격**(영역·Row/Column/Box·반복·`[조건]` 노드)을 먼저 만들고, **요소 표로 값**(컴포넌트·토큰·dp·문구 키·아이콘)을 채운다.
  다 옮긴 뒤 트리 노드와 요소 표 행(id)마다 구현 위치를 대조해 빠진 것이 없는지 확인한다.
- **배치는 ui-spec의 `배치` 칸(의도)대로만 — Figma 숫자를 눈대중으로 옮기지 않는다.**
  `center`면 정렬(`Alignment.Center`·`Arrangement.Center`·`centerHorizontally` 등)로, `padding {n}`이면 그 padding으로, `gap`·`fill`·`weight`도 그대로.
  가운데 있는 요소를 `padding(start = 156.dp)`·`offset`처럼 **좌표에서 계산한 숫자로 가운데 "처럼" 보이게 만들지 않는다**. 거꾸로 여백으로 정해진 요소를 center로 바꾸지도 않는다.
  - 배치가 `미확정 → layout:…`이면 decisions의 같은 key 답을 따른다. 답이 없으면 Step 0-1처럼 멈추고 묻는다.
  - ui-spec에 배치가 없거나, ui-spec 숫자를 쓰려는데 **가운데인지 여백인지 조금이라도 애매하면** 추측하지 않고 Step 0-1처럼 AskUserQuestion으로 묻는다 — 후보는 `center` / `padding {n}`(또는 위 요소 기준 gap)로, 근거는 Figma 값(x·y·폭·부모 폭)과 비슷한 기존 화면의 처리 `파일:라인`, 그리고 넓은·좁은 기기에서 각 후보가 어떻게 보이는지.
  - 코드에 쓰는 크기·간격 숫자는 전부 ui-spec 요소 표(또는 decisions)에 있는 값이어야 한다. 표에 없는 숫자가 필요하면 그것도 묻는다.
- **문구는 프로필 `문구.mode`를 따른다** (체인·단독 공통).
  `rule`: 규칙 문서(`문구.rule`)대로만 — 거기서 금지한 하드코딩·파일 수정을 하지 않는다. `hardcode`: 원문을 글자 그대로 문자열로.
- 다른 브랜치·stash의 비슷한 작업은 참고하지 않는다.
- **신규 파일은 전부(리소스·이미지 포함) `git add -N {파일}`** — 리뷰어의 diff에 보이게 한다.

### 6. 컴파일
```bash
{compile_task} 2>&1 | tail -30
```
**앱이 있으면(`{apps}`) 앱마다** 명령의 `{app}`을 그 앱의 값으로 채워 실행한다. 채운 명령이 앱끼리 같으면(공통 라이브러리 모듈 등 `{app}`이 없는 명령) 한 번만 돈다. **고른 앱 전부 통과해야 통과다** — 한 앱의 실패를 "다른 앱은 됨"으로 넘기지 않는다.
`compile_task`는 실행할 전체 명령이다. 이전 형식 상태 파일처럼 빌드 도구 없이 태스크 이름만 있으면(예: `:app:compileDebugKotlin`) 프로필 `빌드.compile`의 형태로 전체 명령을 만들어 merge한 뒤 실행한다 (`test_task`도 같다). null이면 프로필 `빌드.compile`의 `{module}`·`{variant}`를 변경 모듈 기준으로 채워 정한다 (체인이면 merge해 둔다).
실패 시 추측으로 고치지 않는다 — `systematic-debugging` 스킬(superpowers) Phase 1~4. 3회 실패하면 보고 후 중단.

### 7. 테스트
```bash
{test_task} 2>&1 | tail -30
```
Step 6처럼 **앱마다** `{app}`을 채워 실행하고(같은 명령은 한 번), 전부 통과해야 한다. `verification.tests`에 앱별 명령을 적는다 (`pass — shucle: {명령} / gmaas: {명령} (T1,T3)`).
`test_task`가 null이면: Step 4에서 테스트를 썼다면 프로필 `빌드.test`의 `{module}`·`{variant}`를 그 모듈 기준으로 채워 실행하고,
새 테스트가 없어도 **변경 모듈에 기존 테스트 소스가 있으면 그 모듈 테스트를 돌린다** (AS-IS 보호).
실행할 테스트가 하나도 없거나 프로필 `빌드.test`가 `none`일 때만 `verification.tests`에 `none — {사유}`를 기록한다 (빈 명령·`null`을 실행하지 않는다).

Step 4의 테스트가 전부 통과해야 한다. 기존 테스트가 깨지면 AS-IS 훼손 신호다 — 원인부터 찾는다.
3회 실패하면 보고 후 중단. **"컴파일만 통과했으니 됐다"로 넘어가지 않는다.**

### 8. 화면 확인 (visual todo가 있을 때)
프로필 `화면 확인.mode`가 `none`이면 스폰하지 않고 `verification.visual = "skipped — 화면 확인 수단 없음 (프로필)"`, visual todo의 note는 `visual: skipped — 프로필 none`.
그 외에는 `visual-verifier` 에이전트를 **반드시** 스폰한다: `state_file`, `output_dir: .impl-spec/{type}-{n}.visual/`.
- **앱이 있으면 앱마다 한 번씩, 순서대로** 스폰한다 (같은 기기를 쓰므로 병렬 금지): `app: {이름}`, `output_dir: .impl-spec/{type}-{n}.visual/{이름}/`. 계획 케이스(`visual_cases`) 전부를 앱마다 확인한다.
  기록은 앱별 객체로: `echo '{"verification":{"visual_report":{"shucle":".impl-spec/{type}-{n}.visual/shucle/report.html","gmaas":"…"}}}' | $S merge {type} {n}`.
  todo의 `visual: pass`는 **고른 앱 전부**에서 대상 케이스가 PASS일 때만이다. 한 앱이라도 FAIL·NOT_RUN·MANUAL이면 그 앱 이름과 사유를 note에 적는다.
- **기기가 있는지 메인이 직접 판단하지 않는다** (`adb devices` 같은 플랫폼 명령을 쳐 보고 "기기 없음"으로 건너뛰지 않는다). 기기 도구는 PATH에 없을 수 있고, 기기가 없으면 에이전트가 기기 어댑터(프로필 `화면 확인.device_adapter`)로 에뮬레이터·시뮬레이터를 부팅한다 — `SKIPPED`는 에이전트가 돌려줄 때만 기록한다.
- 에이전트는 상태 파일 `visual_cases`(analyze에서 승인된 확인 계획)를 실행하고 `{output_dir}/report.html`(조건별 스크린샷 비교)을 만든다.
  돌아오면 메인이 **스크린샷을 직접 열어**(대상 케이스 전부 + 회귀 케이스 하나 이상 Read) 에이전트의 판정과 맞는지 본 뒤 기록한다:
  `echo '{"verification":{"visual_report":".impl-spec/{type}-{n}.visual/report.html"}}' | $S merge {type} {n}`
- `SKIPPED`면 사유를 기록하고 진행 — visual todo는 PR에 "수동 확인 필요"로 남고, create-pr이 push 확인 화면 맨 위에 경고로 띄운다.
- `NOT_RUN`(계획에 있었으나 못 본 케이스)·`MANUAL`은 `verification.notes`에 케이스 id와 사유를 그대로 옮긴다. 대상(`target`) 케이스가 NOT_RUN·MANUAL인 todo의 note는 `visual: pass`가 아니라 `visual: skipped — {사유}`다.
- FAIL 케이스는 Step 9 전에 고치고 Step 6부터 다시 (고친 뒤 에이전트를 다시 스폰해 리포트를 새로 만든다).

### 9. 리뷰 — 두 에이전트를 **한 메시지에서 병렬로**

| 에이전트 | 전달 | 경로 |
|---------|------|------|
| `spec-conformance-reviewer` | `state_file`, `visual_result`(Step 8 결과 요약, 없으면 생략) | 체인만 |
| `impl-reviewer` | `base_branch`, `research_code_file`(체인만: `.impl-spec/{type}-{n}.research.code.md`) | 항상 |

| 결과 | 처리 |
|------|------|
| 둘 다 PASS, Important 없음 | Step 10 |
| PASS + Important | Important 수정 → Step 6·7 재실행 → Step 10 (재리뷰 없음) |
| FAIL (Critical) | Critical + Important 수정 → Step 6·7 → **FAIL 낸 리뷰어만** 재실행 (1회) |
| 2차 FAIL | 리뷰 결과를 그대로 보여주고 중단 |
| `[ERROR] …` (입력 누락, `git add -N` 누락 등) | 원인을 고치고 같은 리뷰어를 다시 스폰 (FAIL 횟수에 세지 않음) |

리뷰어가 "todo 해석 오류"를 지적하면 코드만 고치지 말고, todo acceptance도 원문대로 고쳐 merge한다
(해석이 애매하면 Step 0-1처럼 사용자에게 묻는다). 단독 경로에서는 impl-reviewer 결과만으로 판정한다.

### 9-1. 테스트 정리 (리뷰 통과 후, 커밋 직전)

프로필 `빌드.test_retention` (`${CLAUDE_PLUGIN_ROOT}/scripts/impl-profile.sh get 빌드.test_retention`, 없으면 `discard`):

| 값 | 처리 |
|----|------|
| `discard` (기본) | **이번 작업에서 추가한 테스트 코드를 커밋에 넣지 않는다.** 아래 절차로 지운다 |
| `keep` | 지우지 않는다 — 테스트도 Step 10의 커밋에 포함한다 |

`discard` 절차 — Step 7의 테스트가 통과하고 Step 9 리뷰가 끝난 **뒤에만** 한다 (리뷰어는 테스트가 acceptance를 단언하는지 본다):
1. 지우기 전에 증거를 남긴다: todo별로 통과한 테스트 이름(`{클래스}#{케이스}`)과 실행한 명령을 적어 둔다 → Step 11의 note·`verification.tests`.
2. 이번 작업에서 **새로 만든 테스트 파일**을 삭제한다 (`git diff --name-only --diff-filter=A $(git merge-base {base_branch} HEAD)` 중 테스트 소스 — 프로필 `빌드.test_source_hint` 아래). 비게 된 디렉토리도 지운다.
3. **기존 테스트 파일에 추가한 케이스·헬퍼**는 그 부분만 되돌린다. 추가만 했으면 `git checkout -- {파일}`.
4. 테스트만을 위해 추가한 것(테스트 전용 의존성·fixture·fake, 프로덕션 코드의 테스트용 훅)도 함께 되돌린다.
5. **지우지 않는 것:** 프로덕션 동작이 바뀌어서 **기존 테스트의 기대값을 고친 수정** — 되돌리면 기존 테스트가 깨진다. 이것은 커밋에 포함한다.
6. `git status --short`로 테스트 소스에 이번 작업의 추가분이 남지 않았는지 확인한다. 프로덕션 코드를 건드렸으면(4번) Step 6을 다시 돌린다.

`verification.tests`는 실제로 통과한 기록이므로 `pass — {명령} (T1,T3) · 테스트 코드는 통과 확인 후 삭제`로 남긴다.

### 10. 커밋 (한 번)

커밋 허락 규칙은 impl-spec "체인 공통 규칙"을 따른다 (analyze 승인 = 이 브랜치 커밋 허락, push는 별도).
```bash
git log --oneline -10      # 스타일 파악
git add {수정·신규 파일들}   # -A / . 금지 — 관련 없는 파일이 섞인다
git commit -m "{프로필 git.commit_format}"
```
- **커밋은 하나다** — small·large 모두. task별 커밋, "리뷰 반영" 커밋을 따로 만들지 않는다 (리뷰 수정분은 커밋 전에 이미 작업 트리에 반영돼 있다).
  메시지는 작업 전체를 요약한다 (본문에 todo별 변경을 항목으로 적어도 된다).
- 커밋한 뒤에 고칠 것이 나왔고 **아직 push 전**이면 새 커밋을 쌓지 말고 `git commit --amend`로 같은 커밋에 넣는다 (체인이면 상태 파일 `commits`를 새 sha 하나로 교체해 merge). 이미 push된 커밋은 amend하지 않는다 — 그때는 새 커밋.
- `discard`면 커밋에 이번 작업의 테스트 코드가 없어야 한다 — `git show --stat HEAD`로 확인한다.
- 체인: 커밋 후 `$S add-commit {type} {n}`

### 11. 상태 파일 갱신 (체인 — 생략 불가)
```bash
$S todo {type} {n} T1 done "unit: SeatItemTest#T1"   # todo마다 증거를 note로 (규격의 note 형식). 테스트를 지웠으면(Step 9-1) "unit: SeatItemTest#T1 (통과 확인 후 삭제)"
$S todo {type} {n} T5 deferred "범위 외: {decision 질문}"   # 사용자가 범위 외로 정한 것만
$S merge {type} {n} <<'EOF'
{"verification": {"compile":"pass", "tests":"pass — {task} (T1,T3)",
  "review":{"spec":"PASS","quality":"PASS"}, "visual":"{결과 또는 skipped — 사유}",
  "visual_report":"{Step 8의 report.html 경로 — 없으면 키 생략}", "notes":[...]}}
EOF
$S stage {type} {n} implemented
```
`stage`가 거부하면 빠진 항목을 **실제로 채운다** (값만 바꿔 통과시키지 않는다).

### 12. 완료 보고
- 브랜치 / base / 이전 브랜치 (`previous_branch` — "메인 워크스페이스가 {branch}로 전환됨")
- todo별 결과 (T1 ✅ unit / T2 ✅ visual / T4 ⚠️ manual — 사유)
- 테스트·리뷰·화면 결과 — 화면 확인을 했으면 **리포트 경로(`verification.visual_report`)와 확인하지 못한 것**을 함께 (사용자가 열어 볼 수 있게)
- 확인한 앱 (`{apps}` — 있을 때): 앱마다 컴파일·테스트·화면 결과와 리포트 경로
- 커밋 해시 + 메시지

---

## 주의사항

- 브랜치 전환 전 **커밋 안 된 변경이 있으면 멈춘다.** stash·reset·checkout으로 치우지 않는다.
- base는 체인에서는 상태 파일, 단독에서는 사용자 선택. 여기서 새로 결정하지 않는다.
- 컴파일 + 테스트 + 리뷰 통과 후에만, **한 번** 커밋한다 (large도 task별로 나누지 않는다).
- 프로필 `빌드.test_retention`이 `discard`(기본)면 이번 작업에서 추가한 테스트 코드는 통과 확인·리뷰 뒤 지우고 커밋에 넣지 않는다 (Step 9-1).
- `$S` (impl-state.sh) 호출은 **체인 경로에서만** 한다. 단독 경로에는 상태 파일이 없다.
- `.proto` 파일은 수정하지 않는다. **예외**: `proto_dependency.status`가 `temp-local`이면 T0에 한해 acceptance에 적힌 서버 PR 원문 정의를 글자 그대로 옮긴다 (로컬 테스트 전용 — create-pr이 PR을 거부한다).
