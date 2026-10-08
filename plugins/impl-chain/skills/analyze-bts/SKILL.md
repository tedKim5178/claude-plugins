---
name: analyze-bts
description: BTS 이슈를 분석하여 문제점과 수정 방안을 제시
invocable: true
---

> **플러그인 `impl-chain`** — 이 플러그인의 스킬·에이전트는 `impl-chain:` 접두사로 부른다 (예: Skill `impl-chain:analyze-spec`, 에이전트 `impl-chain:code-researcher`). `${CLAUDE_PLUGIN_ROOT}`는 플러그인 설치 경로(절대 경로)로 치환되어 있다 — 명령에 그대로 쓴다. 레포별 값은 레포 루트 `.claude/impl-chain/`(프로필·어댑터)에 있다.


# BTS Issue Analyzer

BTS 이슈의 내용, 댓글, 관련 기획서를 면밀히 분석하여 문제점을 파악하고 수정 방안을 일목요연하게 제시합니다.

## ⚡ SUPERPOWERS 통합

**CRITICAL: BTS 이슈 분석 시 반드시 superpowers 스킬을 사용하세요.**

이슈 유형에 따라 적절한 superpowers 스킬을 먼저 실행:

- **버그/테스트 실패**: `systematic-debugging` 스킬(superpowers) 사용 (REQUIRED)
  - Phase 1: Root Cause Investigation (증거 수집, 재현, 데이터 흐름 추적)
  - Phase 2: Pattern Analysis (작동하는 코드와 비교)
  - Phase 3: Hypothesis and Testing (가설 수립 및 검증)
  - Phase 4: Implementation → **이 스킬에서는 하지 않는다.** 승인 후 `start-work`가 수행 (Step 4 실패 테스트 → Step 5 수정)

- **새 기능 / 리팩토링 성격의 BTS**: 요구 탐색(brainstorming 역할)은 Step 6의 open_questions 확인 루프가,
  계획(writing-plans 역할)은 todo 설계가, TDD는 `start-work`가 맡는다. 분석 중에 별도로 질문을 늘리지 않는다.

**워크플로우 (반드시 이 순서):**
1. BTS 이슈 정보 수집 (아래 단계 0~1) + 리서치 (단계 3: spec-researcher ∥ figma-collector → code-researcher)
2. 이슈 유형 파악 (버그/기능/리팩토링)
3. **버그면 Skill tool로 `systematic-debugging` 즉시 실행** — 건너뛰면 안 됨. Phase 1~3을 완전히 수행 (Phase 4는 start-work)
4. 기능/리팩토링 성격이면 위 설명대로 확인 루프·todo 설계로 진행 (별도 스킬 호출 없음)
5. 결과 정리 및 수정 방안 제시

**❌ 절대 금지**: 버그 이슈를 `systematic-debugging` 호출 없이 바로 분석하는 것

## 작업 흐름

1. **할당된 이슈 목록 조회**: 나에게 할당된 OPEN 상태의 실제 작업 가능한 이슈 목록 조회 (해결책/보류 라벨 제외)
2. **이슈 선택**: 사용자가 분석할 이슈 선택 (또는 직접 이슈 번호 입력)
3. **BTS 이슈 조회**: 선택된 이슈의 상세 정보 및 모든 댓글 조회
4. **리서치**: `spec-researcher`(기획서·댓글) ∥ `figma-collector` → 이어서 `code-researcher`(요구별 코드 매핑·AS-IS·영향 범위)
5. **문제 분석**: 현재 동작과 기대 동작 비교 + 공통 검증 체크리스트
6. **수정 방안 제시**: 구체적인 수정 방법 제안 (브랜치명·검증 커맨드 포함, base는 실행 브랜치)
7. **상태 파일 기록**: 승인 후 `.impl-spec/bts-{bts_number}.json` 기록 → `start-work bts {bts_number}`로 인계

## 입력 파라미터

- `bts_number`: 분석할 BTS 이슈 번호 (선택, 생략 시 할당된 이슈 목록에서 선택)

## 실행 예시

```bash
/analyze-bts          # 할당된 이슈 목록에서 선택
/analyze-bts 7919     # 직접 이슈 번호 지정
```

## 실행 단계

### 0-0. 프로필 게이트 (맨 먼저)

`${CLAUDE_PLUGIN_ROOT}/scripts/impl-profile.sh check --for analyze-bts` — exit 0이 아니면 stderr의 문제 목록을 그대로 보여주고 **중단**.
이후 "프로필 `X.Y`"는 `.claude/impl-chain/profile.md`의 값이다.

이슈 어댑터는 값이 아니라 **해석한 경로**로 부른다 (`builtin:` 값은 체인 공용 스크립트):
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/impl-profile.sh adapter 이슈.bts_adapter     # stdout = 실행할 절대 경로
```
이후 이 문서의 `{이슈.bts_adapter}`는 이 출력 경로를 **글자 그대로** 쓴다 (셸 변수는 다음 호출에 남지 않는다).

### 0. 할당된 이슈 목록 조회 (이슈 번호가 주어지지 않은 경우)

```bash
{이슈.bts_adapter} list
```

- 작업 가능한 내 이슈만 최근 업데이트순으로 나온다 (어떤 라벨·상태를 거르는지는 어댑터에 정의돼 있다).
- 어댑터가 실패하면(권한 부족 등) 에러 메시지를 그대로 보여주고, 이슈 번호를 직접 입력받는다.

**이슈 선택 방법:**
- AskUserQuestion 도구를 사용하여 선택지 형태로 제시
- 각 이슈를 다음 형식으로 변환:
  - **label**: `#{number} {간략한 제목}` (예: "#6502 노티피케이션 시간 변동 안됨")
  - **description**: `상태: {projectItems[0].status.name — 어댑터 출력에 없으면 state}. {전체 제목} ({updatedAt 날짜})`
- 사용자가 선택한 label에서 정규식으로 이슈 번호 추출 (`#(\d+)` 패턴)
- 추출한 번호로 분석 진행

### 0-1. base 브랜치 = 지금 서 있는 브랜치 (이슈 조회보다 먼저)

**base는 고르지 않는다. 이 스킬을 실행한 브랜치가 base다.** 규칙은 analyze-spec Step 0·0-1과 같다:
- `${CLAUDE_PLUGIN_ROOT}/scripts/detect-base.sh` → exit 0이면 stdout이 `base_branch` (로컬 브랜치 — origin은 보지 않는다), exit 2(detached HEAD)면 메시지를 보여주고 **중단**.
- 이슈가 특정 release·hotfix 대상이라고 해도 base를 바꾸거나 묻지 않는다 — 어긋나 보이면 리포트 "작업 설정"에 `ℹ️ 이슈 단서: {원문} — 실행 브랜치와 다름` 한 줄.
- 사용자가 base 변경을 요청하면 "{브랜치}로 옮겨서 다시 실행해주세요"로 안내하고 종료.
- `.impl-spec/bts-{n}.draft.json`이 있으면 draft의 `base_branch`와 비교한다. 같으면 "초안에서 이어서 (base {base}) / 처음부터", 다르면 "{현재 브랜치} 기준으로 처음부터 / 중단 — {draft base}로 옮겨서 다시 실행"을 AskUserQuestion으로 묻는다. "처음부터"면 draft를 지우고 Step 1로 간다.

### 1. BTS 이슈 + 댓글 조회

```bash
mkdir -p .impl-spec
{이슈.bts_adapter} fetch {bts_number} > .impl-spec/bts-{bts_number}.issue.json
jq '{number: .issue.number, title: .issue.title, state: .issue.state, labels: [.issue.labels[]?.name], body: .issue.body}' .impl-spec/bts-{bts_number}.issue.json
jq -r '.comments[] | "\(.created_at[:10]) \(.author): \(.body[:200])"' .impl-spec/bts-{bts_number}.issue.json
```

- 이슈 제목, 본문, 상태, 라벨 — 재현 단계, 기대 동작, 실제 동작 파악
- 모든 댓글 — 추가 정보, 재현 조건, 해결 힌트, 담당자 코멘트

### 3. 리서치 — 2단계 (3-a 병렬 → 3-b)

**링크 추출, 기획서 조회, 코드 탐색을 메인 컨텍스트에서 직접 하지 않는다.**
원문을 메인에 쌓으면 이후 `start-work`의 코드 수정 단계에서 쓸 컨텍스트가 남지 않는다.

| 단계 | 에이전트 | 전달 파라미터 |
|------|---------|--------------|
| 3-a | `spec-researcher` | `issue_json_file: .impl-spec/bts-{n}.issue.json`, `issue_type: bts`, `output_file: .impl-spec/bts-{n}.research.spec.md` |
| 3-a | `figma-collector` | `issue_json_file: .impl-spec/bts-{n}.issue.json`, `output_dir: .impl-spec/bts-{n}.figma/` — 링크가 없으면 `status: none`으로 바로 끝난다 |
| 3-b (3-a 후) | `code-researcher` | `spec_research_file: .impl-spec/bts-{n}.research.spec.md`, `figma_index_file`(있으면), `output_file: .impl-spec/bts-{n}.research.code.md`, `base_ref: {base_branch}` (Step 0-1 — 로컬 브랜치), 조사 초점: 재현 조건에서 코드가 타는 경로 |

Figma가 BLOCKED면 사유와 해결 방법을 보여주고 멈춘다 (analyze-spec Step 3과 같다).
화면 버그 todo(`verify: visual`)에는 collector의 화면 id를 `figma_screens`로 단다.

BTS는 보통 서버 작업이 없으므로 proto는 링크가 실제로 발견될 때만 조사된다. 프로필 `서버 계약.mode`가 `none`이면 조사하지 않는다.
`proto_dependency`: `none`이거나 서버 작업이 없으면 `{required:false, status:"n/a"}`, 그 외에는 analyze-spec Step 5 게이트 규칙과 같다.
비공개 문서(Notion/Confluence/Google Docs)는 내용을 가져올 수 없어 링크만 보고된다.

두 리서치의 "근거 없음" / "코드로 판단할 수 없는 것" / code 리서치 2-1 "예외 케이스" 항목은 **open_questions**가 된다(예외 케이스는 추천안 포함). 임의로 메꾸지 않는다.
todo의 `verify`는 code 리서치 4번 "모듈별 테스트 인프라" 표를 따른다 — unit 불가 모듈의 로직은 `manual` + 사유 (analyze-spec Step 4와 같다).

### 4. 문제 분석

**현재 상황 정리**:
- 재현 조건
- 현재 동작
- 기대 동작
- 발생 환경 (OS 버전, 디바이스 등)

**원인 추정**:
- 코드 로직 분석
- 조건문 확인
- 상태 관리 확인
- API 응답 처리 확인

**todo 설계** — 규격: `${CLAUDE_PLUGIN_ROOT}/references/impl-state-file.md`
- 기대 동작 하나 = todo 하나. `acceptance`는 "재현 조건 X에서 Y가 된다"처럼 **재현 조건 + 기대 동작**으로 쓴다.
- `source`: BTS 본문 / 댓글(작성자·날짜) / 기획서.
- `verify`: 로직 버그는 `unit`(재현 조건을 테스트로 고정), 화면 버그는 `visual`, 둘 다 불가하면 `manual` + 사유.
- `size`: todo 6개 이상이거나 3개 이상 모듈에 걸치면 `large`, 아니면 `small` (BTS는 대부분 small).

**공통 검증 체크리스트 (수정 방안 제시 전 필수)**

→ `${CLAUDE_PLUGIN_ROOT}/references/impl-verification-checklist.md`의 **분석 단계** 세 관점을 수행한다.
특히 **AS-IS 보존**은 버그 수정에서 가장 자주 사고가 나는 지점이다 —
code 리서치 1번 매핑표의 "같이 흔들리는 곳" 열을 기준으로, 고치려는 분기를 공유하는 다른 상태·서비스 타입·화면을 전부 열거한다.

### 4-1. UI 결정 (`figma.status=ok`이고 visual todo가 있을 때 — 생략 불가)

analyze-spec Step 4-1과 같다. 파라미터의 `spec-{n}`을 `bts-{n}`으로 바꿔 쓴다
(`todo_file: .impl-spec/bts-{n}.draft.json`, `figma_dir: .impl-spec/bts-{n}.figma/`, `issue_key: bts-{n}`, `spec_research_file: .impl-spec/bts-{n}.research.spec.md`).
스폰 전에 draft를 쓴다 (Step 6 컴팩션 대비 규칙).
질문은 open_questions로 합류하고(Step 6 확인 루프에서 묻는다), Step 5 리포트에는
`${CLAUDE_PLUGIN_ROOT}/skills/analyze-spec/references/report-template.md`의 "🧩 UI 결정" 섹션을 그대로 넣는다.
결과 병합은 `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/merge-ui-results.py .impl-spec/bts-{n}.draft.json {RESULT 경로들}` — 메인이 JSON을 옮겨 적지 않는다.
확인 루프에서 visual todo나 그 화면이 바뀌면 바뀐 그룹만 다시 실행하고 그 result.json을 스크립트에 다시 넣는다 (그 그룹 기여분만 교체). 질문의 답은 Step 6 확인 루프에서 받는다.

### 5. 수정 방안 제시

**Step 6(브랜치명 결정)을 먼저 수행한 뒤** 이 리포트를 출력한다 — 리포트의 "작업 설정"에 그 값이 들어간다.
open_questions가 남아 있으면 리포트 전에 Step 6의 확인 루프 규칙대로 먼저 묻는다.

다음 형식으로 일목요연하게 정리:

```markdown
## 📋 이슈 요약

**BTS #[번호]**: [제목]
- **상태**: [OPEN/IN_PROGRESS/등]
- **라벨**: [라벨들]
- **할당**: [담당자]

## 🔍 문제점

### 현재 동작
[실제로 어떻게 동작하는지]

### 기대 동작
[어떻게 동작해야 하는지]

### 재현 조건
1. [단계 1]
2. [단계 2]
3. [단계 3]

## 🎯 원인 분석

### 관련 코드 위치
- `[파일경로]:[라인번호]` - [설명]
- `[파일경로]:[라인번호]` - [설명]

### 문제 원인
[왜 이런 문제가 발생하는지 상세 설명]

## 💡 수정 방안

### 수정 대상 파일
1. **[파일명]**
   - [수정할 내용]
   - [예상 코드 변경]

2. **[파일명]**
   - [수정할 내용]

### 수정 방향
[어떤 식으로 수정해야 하는지 구체적으로]

### 고려사항
- [주의해야 할 점]
- [영향 받을 수 있는 다른 부분]
- [테스트 시나리오]

## 📌 구현 항목

| id | 내용 | 완료 조건 (재현 조건 → 기대 동작) | 검증 | 출처 |
|----|------|------------------------------|------|------|

## ✅ 계획 검증

[${CLAUDE_PLUGIN_ROOT}/references/impl-verification-checklist.md 의 "분석 단계 — 리포트 출력 형식" 그대로]

## ✅ 결정 사항 / ❓ 결정 필요

[decisions 표 / open_questions — 남아 있으면 승인 불가]

## 🌳 작업 설정

- **규모**: small / large ({사유})
- **base 브랜치**: [base_branch] (실행 브랜치 — 바꾸려면 그 브랜치에서 다시 실행)
- **제안 브랜치명**: `[프로필 git.branch_format의 bts 형식]`
- **컴파일**: `[compile_task — 실행할 전체 명령]`
- **테스트**: `[test_task]` (없으면 "없음 — 신규 테스트 작성 대상: ...")

## 📚 참고 자료

- 기획서: [링크]
- 관련 PR: [링크]
- 유사 이슈: [링크]

---
수정할 내용 있으면 말씀해주세요.
위 **작업 설정**까지 이대로 괜찮으면 "진행해줘"라고 알려주시면 바로 수정에 들어갑니다.
```

### 6. 브랜치명 결정

base는 Step 0-1에서 이미 확정됐다 — 여기서 다시 판단하지 않는다. `start-work`와 `create-pr`은 상태 파일에서 읽기만 한다.

브랜치명을 제안한다: 프로필 `git.branch_format`의 bts 형식.

**컴팩션 대비**: todo를 처음 설계한 시점부터, 답을 받거나 todo가 바뀔 때마다 초안 전체를
`.impl-spec/bts-{n}.draft.json`에 덮어써 둔다. 대화가 요약되면 여기서 decisions·todo를 다시 읽는다.
draft에는 `base_branch`도 넣는다. 시작할 때 draft가 이미 있으면 Step 0-1의 규칙대로 묻는다.

**확인 루프**: open_questions가 남아 있으면 리포트 전에 묻고 답을 `decisions`로 옮긴다 — 묻는 방식(질문마다 추천안 필수, 4개 이하는 하나씩,
5개 이상은 추천 표 + "전부 추천안대로 / 일부만 바꿈 / 하나씩" 일괄 결정)은 analyze-spec Step 7과 같다. 사용자가 명확히 승인("진행해줘")하고 open_questions가 0개일 때만 Step 7.
base 변경 요청이면 Step 0-1의 안내대로 종료한다 (여기서 base를 바꾸지 않는다). 정정이 오면 해당 부분만 재조사(필요하면 researcher 재스폰)하고 리포트를 다시 낸다.
Step 5 리포트에 **base 브랜치(표시) / 제안 브랜치명 / 검증 커맨드(컴파일·테스트)** 를 함께 싣는다 —
사용자는 이 리포트 승인 한 번으로 전부 확정한다.

### 7. 상태 파일 기록 (사용자 승인 직후 — 생략 불가)

규격: `${CLAUDE_PLUGIN_ROOT}/references/impl-state-file.md`

draft를 최종 내용으로 갱신한 뒤 (규격 필드: issue_title, issue_url(issue.json의 `.issue.url`),
spec_url(없으면 null), milestone: null, base_branch, branch, size, research_files, todo_items,
decisions(+apply), open_questions: [], figma, ui_specs(Step 4-1 — visual todo 없거나 Figma 없으면 생략), proto_dependency, files_to_modify, implementation_direction, compile_task, test_task — 프로필 `빌드.*`의 `{module}`·`{variant}`(프로필 `빌드.module_variants`)를 채운 전체 명령):
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/impl-state.sh init bts {n} < .impl-spec/bts-{n}.draft.json && rm .impl-spec/bts-{n}.draft.json
```

검증 실패 시 빠진 값을 조사하거나 사용자에게 묻는다. 그럴듯한 값으로 채워 통과시키지 않는다.
이후 `start-work`에는 **`bts {n}`을 명시해서** 넘긴다 — base·브랜치명을 다시 묻지 않는다.

**사용자가 수정 방안을 승인하기 전에는 쓰지 않는다.**

## 자동화 원칙

**자동으로 처리 (사용자 확인 없이 즉시 실행)**:
- 할당된 이슈 목록 조회
- BTS 이슈 조회
- 댓글 조회
- 링크 추출
- 파일 읽기 (Read tool)
- 코드 검색 (Grep, Glob tool)
- bash/python 스크립트 실행
- 기획서 내용 조회
- 분석 결과 출력

**CRITICAL: 분석 진행 중 절대 사용자에게 묻지 않는다**:
- "이 파일을 읽어도 될까요?" ❌
- "스크립트를 실행할까요?" ❌
- "계속 진행할까요?" ❌
- "이 방법으로 진행해도 될까요?" ❌
- 그냥 바로 실행합니다. 모든 중간 단계는 자동으로 진행합니다.

**사용자 확인 필요 (유일한 예외)**:
- open_questions 해소, 최종 수정 방안 승인
- 이슈 번호가 주어지지 않은 경우 AskUserQuestion 도구를 사용하여 이슈 목록을 선택지로 제시
  - 각 선택지의 label은 "#번호 간략한 제목" 형식
  - 각 선택지의 description은 "상태: [프로젝트 상태]. [전체 제목] (업데이트 날짜)" 형식
  - 사용자가 선택한 이슈 번호를 파싱하여 분석 진행

## 주의사항

- 기획서는 `spec-researcher`, 코드 탐색은 `code-researcher`에 맡긴다. 원문을 메인에 쌓지 않는다.
- 비공개 문서 링크는 내용을 가져올 수 없으므로 링크만 제공
- 추측이 아닌 실제 코드 기반 분석
- 불확실한 부분은 "근거 없음"으로 명확히 표시 — 임의로 메꾸지 않는다
- 사용자가 수정 방안을 승인하기 전에는 상태 파일을 쓰지 않는다
