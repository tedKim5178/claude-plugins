---
name: analyze-spec
description: 마일스톤의 할당된 이슈를 선택하고 기획서를 분석하여 구현 방향을 제시할 때 사용
invocable: true
---

> **플러그인 `impl-chain`** — 이 플러그인의 스킬·에이전트는 `impl-chain:` 접두사로 부른다 (예: Skill `impl-chain:analyze-spec`, 에이전트 `impl-chain:code-researcher`). `${CLAUDE_PLUGIN_ROOT}`는 플러그인 설치 경로(절대 경로)로 치환되어 있다 — 명령에 그대로 쓴다. 레포별 값은 레포 루트 `.claude/impl-chain/`(프로필·어댑터)에 있다.


# Spec Issue Analyzer

마일스톤의 할당된 이슈를 고르고, 기획서(프로필 `이슈.spec_repo`)·댓글·서버 계약·코드를 조사해
**출처가 달린 todo 목록과 구현 방향**을 만든다. 사용자가 승인하면 `.impl-spec/spec-{n}.json`에 기록하고,
`start-work`·`create-pr`은 그 파일만 읽고 이어간다.

**이 스킬의 품질이 곧 구현의 품질이다.** 여기서 요구를 빠뜨리거나 문구를 요약해 버리면,
뒤 단계는 그 잘못된 todo를 정확하게 구현한다.

## 자동 진행 원칙

**묻지 않고 진행:** 이슈·기획서 조회, 리서치 에이전트 스폰, 파일 읽기, 코드 검색.

**사용자 확인 (이것뿐):**
1. 마일스톤·이슈 번호가 없을 때 → AskUserQuestion
1-1. 앱 이슈에 기획 이슈 링크가 2개 이상일 때 → AskUserQuestion (Step 2)
2. proto 의존성이 `missing`일 때 → AskUserQuestion (Step 5)
3. open questions 해소 + 최종 리포트 승인 (Step 7)

## 입력

```
/analyze-spec              # 마일스톤 + 이슈 선택
/analyze-spec 4.11.0       # 이슈만 선택
/analyze-spec 4.11.0 4895  # 바로 분석
/analyze-spec 좌석 등급     # 키워드 검색 → 이슈 선택 (마일스톤은 고른 이슈의 것)
```
첫 인자가 열린 마일스톤 제목도, 숫자도 아니면 **키워드**로 본다 — 마일스톤을 잘못 기억하거나(닫힌 마일스톤 포함) 이슈 제목만 아는 경우.

---

## 실행 단계

### 0-0. 프로필 게이트 (맨 먼저)

`${CLAUDE_PLUGIN_ROOT}/scripts/impl-profile.sh check --for analyze-spec` — exit 0이 아니면 stderr의 문제 목록을 그대로 보여주고 **중단**.
이후 "프로필 `X.Y`"는 `.claude/impl-chain/profile.md`의 값이다.

이슈 어댑터는 값이 아니라 **해석한 경로**로 부른다 (`builtin:` 값은 체인 공용 스크립트):
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/impl-profile.sh adapter 이슈.spec_adapter     # stdout = 실행할 절대 경로
```
이후 이 문서의 `{이슈.spec_adapter}`는 이 출력 경로를 **글자 그대로** 쓴다 (셸 변수는 다음 호출에 남지 않는다).

### 0. base 브랜치 = 지금 서 있는 브랜치

**base는 고르지 않는다. 이 스킬을 실행한 로컬 브랜치가 base다.** 다른 base가 필요하면 사용자가 그 브랜치로 옮겨서 다시 실행한다.
**origin은 보지 않는다** — 조사·작업 브랜치·리뷰 모두 로컬 base 기준이다. origin은 create-pr의 push 직전에만 확인한다(`check-pr-ready.sh`).
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/detect-base.sh    # stdout = base 이름, stderr = 오류
```

| exit | 처리 |
|------|------|
| 0 | `base_branch` = stdout |
| 2 (detached HEAD) | 메시지를 그대로 보여주고 **중단** |

- 기획서·댓글·마일스톤에 release/hotfix 단서가 있어도 **base를 바꾸거나 묻지 않는다.** 실행 브랜치와 어긋나 보이면 리포트 base 줄 아래에 `ℹ️ 기획 단서: {원문} — 실행 브랜치와 다름` 한 줄만 적는다.
- 분석 중에 사용자가 base를 바꿔 달라고 하면 바꾸지 않는다: "{브랜치}로 옮겨서 다시 실행해주세요"라고 안내하고 종료한다 (draft는 다음 실행의 Step 0-1이 처리한다).

### 0-1. 이어하기 확인

이슈 번호가 있고 `.impl-spec/spec-{n}.draft.json`이 있으면, 이전 분석이 승인 전에 끊긴 것이다. draft의 `base_branch`를 Step 0 결과와 비교한다.

| 비교 | 처리 |
|------|------|
| 같음 | AskUserQuestion: "이전 분석 초안에서 이어서 (base {base}, decisions {k}개)" / "처음부터 다시". 이어서면 draft와 research 파일을 읽고 Step 7 루프로 바로 간다 (재조사·issue.json 재생성 안 함) |
| 다름 | 초안은 다른 base의 코드로 조사한 것이라 이어갈 수 없다. AskUserQuestion: "{현재 브랜치} 기준으로 처음부터" / "중단 — {draft base}로 옮겨서 다시 실행" |

"처음부터"면 draft를 지우고 Step 0-2로 간다.

### 0-2. 마일스톤
주어지지 않았으면:
```bash
{이슈.spec_adapter} milestones
```
AskUserQuestion으로 선택.

### 0-3. 키워드로 찾기 (입력이 키워드일 때)
```bash
{이슈.spec_adapter} search "{키워드}"     # "#{n} [{milestone}] [{state}] {title}" — 어댑터가 search를 지원하지 않으면 Step 0-2로
```
결과를 AskUserQuestion으로 고르게 하고(0개면 키워드를 다시 받는다), 고른 이슈의 `[milestone]`을 `{milestone}`으로 써서 Step 0-1(이어하기)과 Step 2로 간다.
마일스톤이 없는 이슈면 Step 0-2로 마일스톤을 고르게 한다.

### 1. 이슈 선택 (번호 없을 때)
```bash
{이슈.spec_adapter} list {milestone}
```
목록을 표로 보여주고 **AskUserQuestion**으로 선택 (4개 초과면 대표 3개 + Other). 자유 입력 안내문으로 대체하지 않는다.

### 2. 이슈 데이터 → 파일
원문 JSON을 메인 컨텍스트에 올리지 않는다. 파일로 저장하고 요약만 본다.
```bash
mkdir -p .impl-spec
{이슈.spec_adapter} fetch {milestone} {n} > .impl-spec/spec-{n}.issue.json
jq '{title: .issue.title, spec: .spec.number, spec_title: .spec.title, candidates: .spec_candidates,
     issue_comments: (.issue_comments | length), spec_comments: (.comments | length)}' .impl-spec/spec-{n}.issue.json
```

**기획 이슈 후보** (`candidates`) = 앱 이슈 본문·댓글에 적힌 기획 이슈 링크(어댑터가 찾는 형태 — 공용 어댑터면 프로필 `이슈.spec_link_regex`) 전부 (`{number, title, found_in}`).

| 후보 수 | 처리 |
|--------|------|
| 1개 | 스크립트가 그 기획 이슈를 가져왔다. 그대로 진행 |
| 2개 이상 | 스크립트는 기획서를 **가져오지 않았다** (`spec` 비어 있음). AskUserQuestion으로 "이 작업의 기획서는?"을 묻는다 — 선택지 = `#{번호} {제목} ({본문/댓글})`. 고른 번호로 다시 실행: `{이슈.spec_adapter} fetch {milestone} {n} {spec_number}` |
| 0개 | 기획 이슈 링크 없음 — 앱 이슈 본문만으로 진행할지 AskUserQuestion (기획서 번호 직접 입력 선택지 포함) |

번호순·등장순으로 임의로 고르지 않는다. 엉뚱한 기획서로 분석 전체가 진행된다.

### 3. 리서치 — 2단계

**3-a. 원문 리서치 — 두 에이전트를 한 메시지에서 병렬로**

| 에이전트 | 전달 파라미터 |
|---------|--------------|
| `spec-researcher` | `issue_json_file: .impl-spec/spec-{n}.issue.json`, `output_file: .impl-spec/spec-{n}.research.spec.md` |
| `figma-collector` | `issue_json_file: .impl-spec/spec-{n}.issue.json`, `output_dir: .impl-spec/spec-{n}.figma/` |

**Figma가 BLOCKED면 여기서 멈춘다.** collector가 준 사유와 해결 방법(플러그인 켜기 / `/mcp` 로그인 / 파일 권한 요청)을
그대로 보여주고 "해결 후 다시 실행해주세요"로 끝낸다. Figma 없이 분석을 계속하지 않는다 — 사람마다 구현 품질이 달라진다.

**3-b. 코드 매핑 — 3-a가 끝난 뒤**

| 에이전트 | 전달 파라미터 |
|---------|--------------|
| `code-researcher` | `spec_research_file: .impl-spec/spec-{n}.research.spec.md`, `figma_index_file: .impl-spec/spec-{n}.figma/index.md`(status ok일 때), `output_file: .impl-spec/spec-{n}.research.code.md`, `base_ref: {base_branch}` (Step 0 — 로컬 브랜치) |

code 리서치 맨 위에 "이미 구현 흔적" 경고가 있으면 open question으로 올린다 (중복 구현 / 이어서 작업 / 다른 브랜치에서 다시 실행).

code-researcher는 요구 목록과 화면 목록을 받아 **요구마다 코드 위치·AS-IS·바꿀 지점·영향 범위**를 매핑하고,
**코드를 봐야만 답이 나오는 질문**(조건 판별 수단 부재, 기존 흐름 재사용 여부 등), **예외 케이스**(에러 분류별 처리·빈 응답·백스택·1회성 상태 등 — 원문에 없으면 추천안을 붙인 질문), proto 필드 존재 여부, **모듈별 테스트 인프라**를 돌려준다.
기획서를 두 번 해석하지 않도록 3-a 결과를 입력으로 받는다 — 그래서 병렬로 돌리지 않는다.

### 4. todo 설계

spec 리서치의 **요구 목록(R1..Rn)** 을 기준으로 `todo_items`를 만든다. 규격: `${CLAUDE_PLUGIN_ROOT}/references/impl-state-file.md`

- 모든 R은 어떤 todo에 대응되거나, 범위 외로 **사용자가 결정**해야 한다. 조용히 버리지 않는다.
- `acceptance`에는 R의 **값·문구·조건·트리거를 원문 그대로** 옮긴다. "적절한 문구로" 같은 요약 금지.
- `source`에 R의 출처를 그대로 단다.
- `verify`: 로직(매핑·조건·상태)은 `unit`, 화면 문구·배치는 `visual`, 둘 다 불가하면 `manual` + 사유.
  로직이 놓일 모듈이 code 리서치 4번 "모듈별 테스트 인프라" 표에서 unit 불가(❌)면 `unit`으로 잡지 않는다 — 테스트 가능한 모듈로 로직을 둘 수 있으면 그렇게 `files_to_modify`에 적고, 아니면 `manual` + "{모듈} 테스트 인프라 없음".
- `figma_screens`: 화면을 만드는 todo는 collector의 화면 id를 단다 (`figma.status=ok`면 visual todo 필수).
  같은 그룹의 케이스 화면(예: 결과 2개 이상/1개/없음)은 하나의 todo가 모두 가리켜도 된다.
- 문구가 있는 todo의 acceptance에는 spec 리서치 **2-1 문구 키**의 키와 값을 쓴다 (Figma 텍스트가 아니라). 문구 키 표가 없으면 기획서·댓글 원문 문구를 글자 그대로.
  새 문구 처리는 프로필 `문구.mode`를 따른다 — `rule`이면 규칙 문서(`문구.rule`)대로, `hardcode`면 원문 그대로.
  규칙 문서가 키를 만들어 쓰라고 하면 "표에 키 없음"은 open question이 아니다. 문구 **값**이 없을 때만 open question.
- `size`: todo 6개 이상이거나 3개 이상 모듈/레이어에 걸치면 `large`, 아니면 `small`.

그다음 `${CLAUDE_PLUGIN_ROOT}/references/impl-verification-checklist.md`의 **분석 단계** 세 관점을 수행한다.

**이 시점에 첫 초안을 `.impl-spec/spec-{n}.draft.json`에 쓴다** (base_branch·todo·open_questions·decisions 포함). 이후 컴팩션 대비 기준점.

**open_questions**로 모을 것 (하나라도 빠뜨리지 않는다):
- spec 리서치 5번 "근거 없음" 전부
- code 리서치 2번 "코드로만 답할 수 있는 질문" 전부
- code 리서치 2-1번 "예외 케이스" 전부 (추천안 그대로 `recommended`로) — 여기서 묻지 않으면 start-work에서 하나씩 멈춘다
- code 리서치 1번에서 코드 위치를 못 찾은 요구
- todo에 대응되지 않은 R
- 트리거가 원문에 없는 todo
- figma-collector의 `open_questions`와 "충돌"의 미결정 항목 (A안/B안, board ↔ design 불일치, 최종 디자인 링크 없음 등)
- 어느 todo에도 연결되지 않은 Figma 화면 (범위 외인지 누락인지)
- Step 4-1 figma-ui-spec의 `questions` 전부 (키로 그룹 간 중복 제거)

### 4-1. UI 결정 (`figma.status=ok`이고 visual todo가 있을 때 — 생략 불가)

UI의 컴포넌트·값·골격·에셋을 **승인 전에** 확정한다. start-work는 여기서 정한 것을 실행만 한다.

visual todo들의 `figma_screens`를 collector `index.md` 화면 표의 **그룹** 열로 묶고, 그룹마다 `figma-ui-spec`을 **한 메시지에서 병렬로** 스폰한다:

| 파라미터 | 값 |
|---------|-----|
| `todo_file` | `.impl-spec/spec-{n}.draft.json` (Step 4에서 쓴 초안) |
| `figma_dir` | `.impl-spec/spec-{n}.figma/` |
| `screen_ids` | 그 그룹의 화면 id (예: `S4,S5,S6,S7`) |
| `issue_key` | `spec-{n}` |
| `spec_research_file` | `.impl-spec/spec-{n}.research.spec.md` |

에이전트가 `BLOCKED: …`를 반환하면 Step 3의 Figma BLOCKED와 같이 사유·해결 방법을 보여주고 멈춘다.

에이전트는 결과를 `{figma_dir}/ui-spec/{name}.result.json`에 쓰고 `RESULT {경로} — …` 한 줄만 반환한다. **메인은 JSON을 옮겨 적지 않는다** (옮겨 적다 후보를 빠뜨린 적이 있다):
```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/merge-ui-results.py .impl-spec/spec-{n}.draft.json {RESULT 경로들}
```
스크립트가 하는 일: `ui_specs` 등록, `auto` → `decisions`(by claude, 그 화면을 가리키는 todo_ids), `questions` → `open_questions`(`recommended` = 첫 후보),
**같은 key는 그룹 간에 하나로** 합치고(후보·apply 합집합, 다른 그룹 파일은 `ui_spec_also`), 그룹 간 자동 결정이 다르면 질문으로 올린다.
몇 번을 다시 돌려도 결과가 같고, 같은 그룹을 다시 넣으면 그 그룹의 이전 기여분만 교체된다.

- Step 7에서 답을 받으면 `decisions`로 옮기면서(`key`·`ui_spec`·`ui_spec_also` 유지) 그 답의 `apply_by_answer[답]`을 `apply`로 붙인다. "알아서 해"면 `recommended` + `by:"claude (사용자 위임)"`.
- `shared_candidates`는 result.json에서 읽어 리포트 "🧩 UI 결정"에만 싣는다 (질문 아님).

**레포 파일(대응표·drawable)은 여기서 쓰지 않는다** — 아직 base 브랜치 위다. start-work Step 2-1이 작업 브랜치에서 `apply`를 반영한다.
에셋 시험 변환 결과는 `.impl-spec/spec-{n}.figma/assets/`에만 있다.

### 4-2. 화면 확인 케이스 (visual todo가 있을 때 — 생략 불가)

화면에서 **무엇을 어떤 조건으로 볼지**를 승인 전에 표로 확정한다. start-work의 visual-verifier는 이 표를 그대로 실행하고,
표에 있는데 못 본 케이스는 리포트에 "확인 안 함"으로 남는다 — 즉석에서 고른 케이스만 PASS로 보고되는 일을 막는다.

`visual_cases` (규격: `${CLAUDE_PLUGIN_ROOT}/references/impl-state-file.md`) — 한 행 = 화면 한 장:

| 키 | 내용 |
|----|------|
| `scenario` | 화면·상태 (예: "탑승 대기 중 상단 카드"). **같은 scenario끼리 리포트에서 나란히 놓인다** — 조건만 다른 케이스는 글자까지 같은 scenario를 쓴다 |
| `condition` | 그 화면을 가르는 조건 (예: "AV-D2D", "일반 D2D") |
| `kind` | `target`(이번에 바뀌는 조건) / `regression`(바뀌면 안 되는 조건) |
| `expect` | 화면에서 보여야 하는 것 — acceptance의 문구·요소 그대로 |

만드는 법:
- visual todo마다 acceptance의 **조건 × 상태**를 펼친다. 상태가 여럿이면(예: 탑승대기·탑승중) 상태마다 scenario를 만든다. `target`이 하나도 없는 visual todo는 상태 파일이 거부한다.
- **회귀 케이스는 계획 검증의 "영향 범위(AS-IS 보존 대상)" 표에서 뽑는다** — 같은 컴포저블·분기를 지나는 다른 타입·상태마다 `regression` 한 행. 기본값·미지정 값도 한 행.
- `verify: manual` todo라도 화면으로 볼 수 있으면 케이스를 단다 (예: 상태 전환 시 시트가 뜨는지) — 화면 확인이 되면 수동 확인이 줄어든다.
- 화면에 들어가는 길이 막혀 있거나(랜딩 분기 없음 등) mock으로 못 만드는 조건은 케이스로 넣되, 그 사실을 open question으로 올린다 (우회 진입 허용 / 범위에서 제외).

확인 루프(Step 7)에서 todo·acceptance가 바뀌면 케이스도 같이 고친다. 리포트 "검증 계획"에 표 전체를 싣는다.

### 5. proto 의존성 게이트

프로필 `서버 계약.mode`가 `none`이면 `proto_dependency = {required:false, status:"n/a"}`로 두고 이 단계를 건너뛴다.
그 외에는 code 리서치 3번 결과로 `proto_dependency`를 정한다.

| 상태 | 처리 |
|------|------|
| 서버 작업 없음 | `{required:false, status:"n/a"}` |
| `available` | 진행 |
| `missing` / `unknown` | **AskUserQuestion**: ① 서버 proto 반영까지 보류 (여기서 종료, 상태 파일 안 씀) ② proto 의존성 버전 올리기를 todo에 포함 (proto PR이 머지된 경우만) ③ proto 없이 가능한 todo만 진행 (나머지는 `decisions`에 범위 외로) ④ **임시 반영 — 로컬 테스트 전용**: 서버 proto PR(머지 여부 무관) 원문에서 이 기능에 필요한 RPC·메시지·필드만 그대로 옮기는 todo T0 (`proto_dependency.status = "temp-local"`, acceptance에 PR 링크·커밋 sha·옮길 정의 목록). start-work는 T0에 한해 `.proto` 수정을 허용하고, **create-pr은 PR을 만들지 않는다** |

`missing`인데 묻지 않고 진행하지 않는다 — start-work가 없는 필드로 컴파일 실패를 반복하게 된다.

### 6. 브랜치명

프로필 `git.branch_format`의 spec 형식 (예: `feat/{n}-{slug}` → `feat/4895-seat-grade-badge`).
base는 Step 0에서 이미 확정됐다 — 여기서 다시 판단하지 않는다.

### 7. 리포트 + 확인 루프

`${CLAUDE_PLUGIN_ROOT}/skills/analyze-spec/references/report-template.md` 형식으로 출력한다.
복잡한 구현이면 "구현 접근"에 A/B 비교와 트레이드오프를 쓴다.

```
루프:
  1. open_questions가 남아 있으면 → 묻는다. 모든 질문에 `recommended`(첫 후보)와 추천 이유가 있어야 한다 — 없으면 먼저 채운다.
     - 4개 이하: AskUserQuestion으로 하나씩 (후보를 선택지로, 추천을 첫 선택지 + "(Recommended)", 근거 없음을 명시)
     - 5개 이상: 번호·질문·추천(이유) 표를 출력한 뒤 AskUserQuestion 1번 —
       "전부 추천안대로" / "일부만 바꿈 (Other에 `번호=답` 나열)" / "하나씩 묻기"(→ 4개씩 나눠 묻기)
       일괄 수락분은 `by:"user (추천안 일괄 수락)"`, 바꾼 것은 `by:"user"`.
     - 다른 질문의 답으로 정해지는 질문(예: 같은 컴포넌트를 쓰면 배경 토큰도 따라감)은 표에 `→ #{번호}를 따름`으로 묶어 하나로 보여준다.
     답을 decisions[{key, question, answer, by, todo_ids}]로 옮기고 open_questions에서 뺀다.
     답 때문에 todo가 바뀌면 todo를 갱신한다.
  2. 리포트를 출력하고 "수정할 내용 있으면 말씀해주세요. 없으면 '진행해줘'" 로 턴을 끝낸다.
  3. 응답:
     - 명확한 승인("진행해줘", "ㄱㄱ", "네 시작해") + open_questions 0개 → Step 8
     - 승인했지만 open_questions가 남음 → 1번으로 (상태 파일은 이 조건에서 거부된다)
     - base 변경 요청 → Step 0의 안내대로 종료 (여기서 base를 바꾸지 않는다)
     - 정정/추가 정보 → 해당 부분만 재조사 (필요하면 해당 researcher를 조사 초점을 좁혀 재스폰) → 1번부터
       visual todo나 그 figma_screens가 바뀌었으면 Step 4-1을 **바뀐 그룹만** 다시 실행한다.
       다시 돌린 그룹의 result.json을 `merge-ui-results.py`에 다시 넣으면 그 그룹 기여분만 교체된다. 그룹이 통째로 빠졌으면 draft `ui_results`에서 그 항목을 지운 뒤 남은 result.json 하나로 스크립트를 다시 실행한다 (등록된 결과 전부로 다시 만든다).
```

**컴팩션 대비**: 루프를 돌 때마다(질문에 답을 받거나 todo가 바뀔 때마다) 현재 초안 전체를
`.impl-spec/spec-{n}.draft.json`에 덮어써 둔다. 대화가 요약되면 이 파일에서 decisions·todo를 다시 읽는다.
(draft는 상태 파일이 아니다 — `find`에 잡히지 않고, start-work로 넘어가지 않는다.)

사용자가 "그건 알아서 해"라고 하면 네가 고른 답과 근거를 `decisions`에 `by:"claude (사용자 위임)"`로 적고 리포트에 보여준다.

### 8. 상태 파일 기록 (승인 직후 — 생략 불가)

draft를 최종 내용으로 갱신한 뒤 (규격 필드: issue_*, spec_url, milestone, base_branch, branch, size,
research_files, todo_items, decisions(+apply), open_questions: [], figma, ui_specs(Step 4-1 — visual todo 없거나 Figma 없으면 생략), visual_cases(Step 4-2 — visual todo 없으면 생략), proto_dependency, files_to_modify,
implementation_direction, compile_task, test_task — 프로필 `빌드.compile`/`빌드.test`의 `{module}`·`{variant}`(프로필 `빌드.module_variants`)를 채운 **실행할 전체 명령**):
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/impl-state.sh init spec {n} < .impl-spec/spec-{n}.draft.json && rm .impl-spec/spec-{n}.draft.json
```

스크립트가 검증 실패를 내면 **빠진 값을 조사하거나 사용자에게 묻는다.** 그럴듯한 값으로 채워 통과시키지 않는다.
성공하면 한 줄: `상태 파일 기록 완료 → .impl-spec/spec-{n}.json`

---

## 주의사항

- 기획서·proto·코드 원문은 researcher가 읽는다. 메인은 리서치 파일 요약으로 판단한다.
- proto 링크는 이슈/기획서/댓글에 명시된 것만. `.proto` 파일은 절대 수정하지 않는다.
- 댓글이 본문보다 최신일 수 있다 — researcher가 표시한 최신 댓글을 todo에 반영한다.
- 승인 전에는 상태 파일을 쓰지 않는다. 상태 파일이 생기는 순간 `impl-spec`이 다음 단계로 넘어간다.
