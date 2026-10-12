# impl-spec 상태 파일 규격

`analyze-spec`/`analyze-bts` → `start-work` → `create-pr` 체인이 컨텍스트를 주고받는 **단일 진실 공급원**.

리포트 본문을 파싱하거나 "대화 맥락에서 추론"하지 않는다. 각 단계는 이 파일만 읽고 쓴다.

## 도구 — 손으로 jq를 짜지 않는다

```bash
S=${CLAUDE_PLUGIN_ROOT}/scripts/impl-state.sh
$S path  spec 4895                 # 경로
$S find  --stage analyzed          # 목록 (TSV: key stage branch updated_at title)
$S init  spec 4895 < state.json    # analyzed로 신규 기록 — 필수 필드·todo 형식·open_questions=0 검증
$S get   spec 4895 '.base_branch'  # 조회
$S merge spec 4895 <<< '{"verification":{"compile":"pass"}}'   # 깊은 병합 (배열은 통째 교체)
$S todo  spec 4895 T1 done         # todo 하나 상태 갱신
$S add-commit spec 4895            # HEAD를 commits에 추가
$S stage spec 4895 implemented     # 전이 — 조건 미달이면 거부(exit 3)
$S check-branch spec 4895          # 현재 브랜치 == .branch 확인
```

`.impl-spec/` 안의 `*.issue.json`, `*.draft.json`은 상태 파일이 아니다 (`find`가 무시한다).

스크립트가 검증에 실패하면 **값을 추측으로 채워 넣어 통과시키지 않는다.** 빠진 정보를 조사하거나 사용자에게 묻는다.

## 경로와 키

```
.impl-spec/{type}-{number}.json             상태 파일      (type = spec | bts)
.impl-spec/{type}-{number}.research.*.md    리서치 원본 요약 (researcher 에이전트가 기록)
.impl-spec/{type}-{number}.visual/          visual-verifier 스크린샷
.impl-spec/{type}-{number}.figma/           figma-collector(index.md, screens/) + figma-ui-spec(ui-spec/, vars/, context/, assets/)
```

- BTS #4895와 안드로이드 #4895는 다른 레포라 **type으로 분리**한다.
- `.gitignore` 대상. 커밋하지 않는다.

## 상태 파일 선택 규칙 (모든 단계 공통)

**"가장 최근 파일"로 고르지 않는다.** (`ls -t | head -1` 금지)

0. 호출 인자가 **브랜치명**(`/`를 포함한 이름 — 예: `fix/xxx`, `feature/xxx`)이면 사용자는 단독 작업을 원한 것이다 → 상태 파일 없이 진행. 목록도 묻지 않는다.
1. 호출 인자나 오케스트레이터가 `{type} {number}`를 명시했으면 그것.
2. 이번 대화에서 직접 `init`한 파일이면 그것.
3. 그 외에는 `find --stage {기대 단계}` 결과를 보여주고 **AskUserQuestion**으로 고르게 한다
   (선택지에 "상태 파일 없이 진행"을 포함). 0개면 단독 경로.

## 스키마 (schema 3)

```json
{
  "schema": 3,
  "issue_type": "spec",
  "issue_number": 4895,
  "issue_title": "좌석 등급 뱃지",
  "issue_url": "https://github.com/{org}/{app-repo}/issues/4895",
  "spec_url": "https://github.com/{org}/{spec-repo}/issues/1234",
  "milestone": "4.11.0",
  "base_branch": "develop",
  "branch": "feat/4895-seat-grade-badge",
  "size": "small",
  "research_files": [".impl-spec/spec-4895.research.spec.md", ".impl-spec/spec-4895.research.code.md"],
  "todo_items": [
    {
      "id": "T1",
      "desc": "PREMIUM 좌석에 등급 뱃지 표시",
      "source": "기획서 댓글 #3 (2026-09-20)",
      "acceptance": "grade == PREMIUM 일 때만 '프리미엄' 뱃지. 그 외 등급은 뱃지 없음. 좌석 목록 진입 시 1회 렌더",
      "verify": "unit",
      "figma_screens": [],
      "status": "pending",
      "note": null
    }
  ],
  "decisions": [
    { "question": "뱃지 탭 시 이동 화면?", "answer": "탭 동작 없음", "by": "user", "todo_ids": ["T1"] },
    { "question": "badge_grade 대응 컴포넌트", "answer": "없음 — 화면 안 기본 요소로 구현 (후보 0개)", "by": "claude", "todo_ids": ["T1"],
      "apply": [{ "kind": "map_row", "op": "add", "data_name": "badge_grade", "component": "없음 — 기본 요소",
                  "note": "사용 이슈: spec-4895", "evidence": "spec-4895" }] }
  ],
  "open_questions": [],
  "figma": {
    "status": "ok",
    "dir": ".impl-spec/spec-4895.figma/",
    "design_url": "https://www.figma.com/design/…?node-id=14661-141259",
    "screens": [{ "id": "S4", "node_id": "14661:139923", "group": "계정 현황", "case": "계정 2개 이상" }]
  },
  "ui_specs": [{ "group": "계정 현황", "screens": ["S4"], "file": ".impl-spec/spec-4895.figma/ui-spec/S4.md" }],
  "proto_dependency": { "required": true, "status": "available", "note": "SeatInfo.grade 이미 의존성에 있음" },
  "files_to_modify": [
    { "path": "app/src/.../SeatItem.kt", "action": "수정" }
  ],
  "implementation_direction": "한 문단 요약",
  "compile_task": "./gradlew :app:compileDebugKotlin",
  "test_task": "./gradlew :app:testDebugUnitTest",
  "tasks": [],
  "previous_branch": "feat/ai-skills",
  "stage": "analyzed",
  "commits": [],
  "verification": {},
  "pr_url": null,
  "updated_at": "2026-09-30T05:00:00Z"
}
```

### 필드별 작성 주체

| 필드 | 쓰는 단계 | 비고 |
|------|----------|------|
| `issue_*`, `spec_url`, `milestone` | analyze-* | BTS면 `spec_url`/`milestone`은 `null` 가능 |
| `base_branch`, `branch` | analyze-* | `base_branch` = analyze-*를 **실행한 로컬 브랜치** (`${CLAUDE_PLUGIN_ROOT}/scripts/detect-base.sh`, 고르거나 묻지 않음, origin에 없어도 됨 — 작업 브랜치는 그 로컬 tip에서 따고 리뷰는 `git merge-base {base_branch} HEAD` 기준. origin은 create-pr `check-pr-ready.sh`에서만 확인 — 체인 규칙. 상태 파일 없는 단독 start-work/create-pr은 각자 묻는다). `branch`는 analyze-*가 제안. 이후 단계는 읽기만 |
| `research_files` | analyze-* | researcher 에이전트가 쓴 파일. reviewer가 원본 대조에 쓴다 |
| `todo_items` | analyze-* (생성), start-work (`status`) | 아래 todo 규칙 |
| `decisions` / `open_questions` | analyze-* | `init` 시점에 `open_questions`는 **반드시 빈 배열**. decision이 특정 todo에 영향을 주면 `todo_ids`. 선택: `evidence`(근거 — figma-ui-spec auto는 필수), `key`(figma-ui-spec 판정 키), `ui_spec`(나온 그룹의 ui-spec 파일 — 그룹 재실행 시 이 값으로 지운다) |
| `figma` | analyze-* | `figma-collector` 결과. `status`: `ok`(화면 확정) / `none`(링크 없음). **BLOCKED로는 기록할 수 없다** — 분석을 멈추고 사용자가 해결 |
| `ui_specs` | analyze-* Step 4-1 | `[{group, screens, file}]` — figma-ui-spec 결과. `figma.status=ok`이고 visual todo가 있으면 visual todo의 모든 화면을 덮어야 한다 (init 검사). start-work·리뷰어·visual-verifier가 ui-spec을 여기서 찾는다 |
| `decisions[].apply` | analyze-* (생성), start-work Step 2-1 (반영) | 레포에 반영할 UI 결정 (컴포넌트·토큰 대응표 행, 에셋). 아래 apply 형식 |
| `proto_dependency` | analyze-* | 서버 작업 없으면 `{ "required": false, "status": "n/a" }`. `status`: `n/a` / `available` / `missing`(보류·부분 진행) / `temp-local`(서버 proto PR 원문에서 필요한 부분만 임시 반영 — 로컬 테스트 전용, start-work는 T0에 한해 `.proto` 수정 허용, create-pr은 PR 거부) |
| `size` | analyze-* | `small` / `large` — start-work의 task 분할 여부 |
| `compile_task`, `test_task` | analyze-* | 프로필 `빌드.compile`/`빌드.test`의 `{module}`·`{variant}`(프로필 `빌드.module_variants`)를 채운 **실행할 전체 명령**. 모르면 `null` → start-work가 채움 |
| `tasks` | start-work (large만) | `[{id, todo_ids, files, done}]` — task의 compile·test 통과 확인 직후 `done: true` (task별 커밋 없음 — 커밋은 전체에 하나). 재개 시 done인 task는 건너뛴다 |
| `commits`, `verification` | start-work | 아래 verification 형식 |
| `previous_branch` | start-work | 브랜치 전환 전 메인 워크스페이스 브랜치 (돌아갈 곳 안내용) |
| `pr_url` | create-pr | |
| `stage` | `stage` 명령으로만 | |

### todo_items 규칙

| 키 | 의미 |
|----|------|
| `id` | `T1`, `T2`… 테스트 이름·커밋·리뷰·PR 체크리스트가 모두 이 id로 연결된다 |
| `source` | 근거 위치 (기획서 본문/댓글 번호+날짜/proto). **근거 없는 todo는 만들 수 없다** — 사용자 결정이면 `decisions` 참조 |
| `acceptance` | 관찰 가능한 완료 조건. **값·문구·조건·트리거(언제 실행되는가)** 를 원문 그대로 |
| `verify` | `unit`(유닛 테스트로 검증) / `visual`(화면 확인) / `manual`(둘 다 불가 — 사유를 acceptance에) |
| `figma_screens` | 이 todo가 구현하는 화면 id (`figma.screens[].id`). `figma.status=ok`면 **visual todo는 필수** — 스크립트가 검사 |
| `status` | `pending` → `done` / `deferred`(사용자가 범위 외로 결정한 경우만) |
| `note` | 검증 증거 한 줄 — `impl-state.sh todo … <status> "<note>"`로 기록. 형식: `unit: SeatItemTest#T1` (테스트를 커밋 전에 지웠으면 `unit: SeatItemTest#T1 (통과 확인 후 삭제)`) / `visual: pass` / `visual: skipped — 기기 없음` / `manual: {사유}` / `범위 외: {decision 질문}`. create-pr이 체크리스트를 이 값으로 만든다 |

### apply 형식 (`decisions[].apply[]`)

analyze는 base 브랜치 위라 레포 파일을 쓰지 않는다. 반영은 start-work Step 2-1의 `${CLAUDE_PLUGIN_ROOT}/scripts/apply-ui-decisions.py`가 한다.

| kind | 필드 | 반영 |
|------|------|------|
| `map_row` + `op: add` | `data_name`, `component`(기본 요소면 `없음 — 기본 요소`), `evidence`, `note`(선택) | 대응표에 행 추가. 같은 data-name이 같은 component면 SKIP, 다르면 CONFLICT. 값에 `|`·data_name에 백틱 불가 (init·스크립트가 거부) |
| `map_row` + `op: replace` | `data_name`, `component`, `evidence`, `expect`(현재 행의 프로젝트 칸 값), `note`(선택 — 없으면 기존 비고 유지) | 현재 프로젝트 칸이 expect면 행 교체(첫 칸 유지), 이미 component면 SKIP, 그 외(행 없음 포함) CONFLICT. 값 제한은 add와 같음(expect 포함) |
| `map_row` + `op: append_issue` | `data_name`, `issue` (`{type}-{n}`) | 그 행 비고의 `사용 이슈:`에 덧붙임. 행이 없으면 CONFLICT |
| `token_row` + `op: add` | `figma_name`, `token`(원시 값이면 `없음 — 원시 값`), `value`(색 = 대문자 hex / 타이포 = `크기/굵기/행간`), `evidence` | 토큰 대응표(프로필 `디자인 토큰.map`)에 행 추가. 이름은 대소문자 무시로 비교 — 같은 token이면 SKIP, 다르면 CONFLICT. 값에 `|`·figma_name에 백틱 불가 |
| `token_row` + `op: replace` | 위 필드 + `expect`(현재 행의 토큰 칸 값) | 현재 토큰 칸이 expect면 토큰·값·근거 교체(첫 칸 유지), 이미 token이면 SKIP, 그 외(행 없음 포함) CONFLICT |
| `asset` | `figma_name`, `source`(`.impl-spec/` 안 — 시험 변환 결과, 존재해야 함), `target`(프로필 `asset_target`의 `{name}`을 채운 레포 상대 경로 — 절대 경로·`..` 불가) | source → target 복사. 같은 내용이면 SKIP, 다르면 CONFLICT |

스크립트는 모든 항목을 먼저 검증하고(형식 오류면 아무것도 쓰지 않고 exit 1) 반영한다. 다시 실행해도 반영된 항목은 SKIP.

### verification 형식 (start-work가 기록)

```json
{
  "compile": "pass",
  "tests": "pass — ./gradlew :app:testDebugUnitTest (T1, T3)",
  "review": { "spec": "PASS", "quality": "PASS" },
  "visual": "pass — T2 (스크린샷 3장)" ,
  "notes": ["T4 manual: 실기기 결제 필요"]
}
```

- `tests`는 `pass …` 또는 `none — {사유}` (test_task가 null이거나 테스트 인프라가 없을 때). 스크립트가 이 형식을 검사한다.
  프로필 `빌드.test_retention`이 `discard`면 테스트 코드는 커밋에 없다 — `pass — {명령} (T1,T3) · 테스트 코드는 통과 확인 후 삭제`.
- `commits`는 보통 1개다 (start-work는 작업 전체를 한 번에 커밋한다).
- `visual`은 선택. 기기가 없으면 `"skipped — 연결된 기기 없음"`.
- todo `status: done`은 "구현됨"이다. 검증 증거는 `verify` + `verification`이 따로 보여준다 (visual skipped면 PR에서 `[ ]`).

### stage 전이

| 전이 | 스크립트가 검사하는 조건 |
|------|------------------------|
| (없음) → `analyzed` | `init`: 필수 필드, todo 형식, `open_questions` 0개, research 파일 존재, 브랜치명 형식, `figma.status` ok/none, visual todo ↔ figma 화면 연결, visual todo 화면 ↔ `ui_specs` 커버, `ui_specs` 파일·asset source 존재, `apply` 형식 |
| `analyzed` → `implemented` | commits ≥1, compile pass, tests 기록, review spec·quality PASS, 모든 todo `done`/`deferred` |
| `implemented` → `pr_created` | `pr_url` 존재 |

그 외 전이(건너뛰기, 되돌리기)는 거부된다. 되돌려야 하면 사용자에게 알리고 사용자가 파일을 직접 정리한다.
