---
name: impl-spec
description: Use when starting a spec feature implementation end-to-end from a milestone issue — from spec analysis through implementation to an opened PR, or when resuming such a run that stopped midway
invocable: true
---

> **플러그인 `impl-chain`** — 이 플러그인의 스킬·에이전트는 `impl-chain:` 접두사로 부른다 (예: Skill `impl-chain:analyze-spec`, 에이전트 `impl-chain:code-researcher`). `${CLAUDE_PLUGIN_ROOT}`는 플러그인 설치 경로(절대 경로)로 치환되어 있다 — 명령에 그대로 쓴다. 레포별 값은 레포 루트 `.claude/impl-chain/`(프로필·어댑터)에 있다.


# Impl Spec (오케스트레이터)

스펙 기능 구현 전체를 하나로 묶는다: **analyze-spec → start-work → create-pr**

## 핸드오프 규칙

각 단계는 `.impl-spec/spec-{n}.json` 상태 파일로만 컨텍스트를 주고받는다.
규격·도구·선택 규칙: `${CLAUDE_PLUGIN_ROOT}/references/impl-state-file.md` (도구: `${CLAUDE_PLUGIN_ROOT}/scripts/impl-state.sh`)

- 이 오케스트레이터는 **리포트 본문을 파싱하지 않는다.** 컴팩션되면 사라지고, 문구가 바뀌면 조용히 틀린다.
- 하위 스킬에는 **항상 `spec {n}`을 명시해서** 넘긴다. 하위 스킬이 "가장 최근 파일"을 고르게 두지 않는다.
- 리서치 원본은 `.impl-spec/spec-{n}.research.*.md`에 있어서, 세션이 끊겨도 리뷰어가 원문을 대조할 수 있다.

```
analyze-spec  ─ init ─>  spec-{n}.json (analyzed)   + research.spec.md / research.code.md
start-work    ─ stage ─>                (implemented) — 스크립트가 테스트·리뷰·todo 완료를 검사. 커밋은 하나, 작업용 테스트 코드는 커밋 전 삭제(프로필 `빌드.test_retention`)
create-pr     ─ stage ─>                (pr_created)
impl-spec     ─ clean ─>  .impl-spec/spec-{n}.* 삭제
```

## 사용자 승인

| # | 시점 | 승인 대상 |
|---|------|----------|
| 1 | analyze-spec Step 7 | 리포트 + todo(acceptance) + 브랜치명 + 검증 계획(화면 확인 케이스 표 포함). **open questions가 전부 해소돼야** 상태 파일이 써진다 |
| 2 | create-pr Step 4 | push / PR 생성 — 화면 확인 리포트(조건별 스크린샷 비교)를 여기서 보여준다 |

승인 외에 멈추는 경우:
- detached HEAD에서 실행 (analyze-spec Step 0) — base는 로컬 브랜치면 되고 origin에 없어도 된다
- PR 불가 — base가 origin에 없음 / 임시 proto 반영 브랜치 (create-pr `check-pr-ready.sh`)
- proto 의존성 `missing` (analyze-spec Step 5)
- 커밋 안 된 변경 때문에 브랜치 전환 불가 (start-work Step 2)
- 구현 중 근거 없는 동작 발견 (start-work Step 0-1)
- 3회 실패 / 리뷰 2차 FAIL

## 입력

```
/impl-spec                    # 마일스톤 + 이슈 선택
/impl-spec 4.11.0             # 이슈만 선택
/impl-spec 4.11.0 4895        # 바로 분석
/impl-spec 좌석 등급           # 키워드로 이슈 검색 (analyze-spec Step 0-3)
```

---

## 실행 단계

### 0. 재개 확인

이슈 번호가 주어졌으면 `${CLAUDE_PLUGIN_ROOT}/scripts/impl-state.sh get spec {n} .stage` (exit 2 = 없음).
번호가 없으면 `impl-state.sh find`로 진행 중인 spec 파일을 보여주고 **AskUserQuestion**:
"#{n} 이어서 (stage)" 선택지들 + "새 이슈 시작".

| stage | 다음 |
|-------|------|
| 없음 | Step 1 |
| `analyzed` | Step 2 |
| `implemented` | Step 3 |
| `pr_created` | `pr_url` 출력 후 종료 |

### 1. analyze-spec

Skill tool로 `analyze-spec` 호출 (`{milestone} {n}`).

`spec-{n}.json`이 `stage: analyzed`로 존재한다는 것 자체가 승인의 증거다 (`init`은 승인 직후에만 실행되고,
미해결 질문이 있으면 스크립트가 거부한다). **다시 승인을 묻지 않는다.**
**상태 파일이 생기지 않았으면 다음 단계로 가지 않는다** (proto 보류 선택 등으로 종료된 경우 포함).

### 2. start-work

Skill tool로 `start-work` 호출. 컨텍스트를 나열하지 않고 키만 넘긴다:
```
상태 파일: spec {n} (stage: analyzed) — 체인 경로.
base·브랜치·todo·검증 커맨드는 impl-state.sh로 읽을 것. Step 0은 미리보기만.
```
끝나면 `impl-state.sh get spec {n} .stage`가 `implemented`인지 확인한다. 아니면 start-work가 멈춘 이유를 그대로 보고하고 종료.

### 3. create-pr

Skill tool로 `create-pr` 호출: `spec {n}`

끝나면 `impl-state.sh get spec {n} .stage`가 `pr_created`인지 확인한다. 아니면(push 거절·PR 불가 등) Step 4로 가지 않는다 — 재개에 상태 파일이 필요하다.

### 4. 작업 파일 정리

완료 출력에 쓸 값(`issue_title`·`branch`·`base_branch`·`previous_branch`·todo 집계·`verification`·`apps`·`pr_url`)을 **먼저 읽어 둔 뒤** 지운다. 묻지 않는다.
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/impl-state.sh clean spec {n}
```
이 이슈의 `.impl-spec/spec-{n}.*`(상태 파일·이슈 원문·리서치·브리프·Figma·화면 확인 스크린샷)를 지우고, 다른 이슈 파일이 없으면 `.impl-spec/`를 통째로 지운다.
`pr_created`가 아니면 스크립트가 거부한다(exit 3) — 그때는 지우지 않고 그대로 보고한다.

---

## 완료 출력

```
✅ impl-spec 완료
이슈 #{n}: {issue_title}
브랜치: {branch} → {base_branch}   (메인 워크스페이스가 이 브랜치로 전환됨. 이전: {previous_branch})
구현 항목: ✅ {done 수} / ⚠️ 수동 확인 {manual·visual skipped 수} / ➖ 범위 외 {deferred 수}
검증: 테스트 {tests} / 화면 {visual} / 리뷰 스펙 {spec}·품질 {quality}
확인한 앱: {apps — 없으면 줄 생략}
화면 확인: {verification.visual}   (리포트·스크린샷은 Step 4에서 지워졌다 — create-pr 확인 화면에서 이미 봤다)
PR: {pr_url}
작업 파일: .impl-spec/spec-{n}.* 삭제됨

⚠️ 남은 확인 사항: {verification.notes + 수동 확인 todo. 없으면 생략}
```

## 체인 공통 규칙 (모든 체인 스킬에 적용 — 레포 지침에 같은 내용이 없어도)

**커밋 허락.** analyze-spec의 리포트 승인(상태 파일 `stage: analyzed`가 생긴 것)이 **그 상태 파일 `branch`에 대한 커밋 허락**이다.
start-work는 다시 묻지 않고 절차대로(컴파일·테스트·리뷰 통과 후, 규모와 무관하게 **한 번**) 커밋한다. 단독 start-work는 Step 0 미리보기 "진행" 승인이 그 작업 브랜치의 커밋 허락이다.
- **push는 별도다** — create-pr Step 4에서 따로 승인받는다.
- 레포 지침(CLAUDE.md 등)이 커밋마다 따로 묻게 하면 그 지침을 따른다 (더 엄격한 쪽).
- start-work가 끝난 뒤의 후속 수정(PR 리뷰 반영 등)은 체인 밖이다 — 커밋 전에 묻는다.

**다른 작업 방식 스킬과의 관계.** 체인은 계획·리뷰·검증 단계를 스스로 갖고 있다. 체인 안에서는 범용 작업 스킬(예: superpowers의 brainstorming·writing-plans·executing-plans·requesting-code-review·verification·worktree·finishing-branch)을 **추가로 부르지 않는다** —
analyze-spec의 리서치+확인 루프가 요구 탐색·계획을, 상태 파일이 계획서를, start-work Step 9 리뷰어가 코드 리뷰를, `impl-state.sh stage`가 완료 검증을 대신한다.
체인 문서가 직접 부르라고 적은 곳만 쓴다: start-work Step 4~5 TDD(RED→GREEN), Step 6·7 실패 시 체계적 디버깅.
**워크트리를 만들지 않는다** — 체인은 메인 워크스페이스에서 브랜치를 바꾼다(setup-branch.sh).

## 주의사항

- **base = 분석(analyze-spec)을 시작한 로컬 브랜치.** 고르거나 묻지 않는다. 작업 브랜치는 그 로컬 tip에서 딴다 (origin 미사용). 다른 base가 필요하면 그 브랜치로 옮겨 다시 실행한다.
  상태 파일이 생긴 뒤(stage analyzed 이후) 재개하면 지금 브랜치와 상관없이 상태 파일의 `base_branch`를 쓴다.
- 작업은 **메인 워크스페이스**에서 브랜치를 바꿔 진행한다 (워크트리를 만들지 않는다). 시작 전 커밋 안 된 변경이 있으면 start-work가 멈춘다.
- 리뷰어 피드백 반영·머지·브랜치 정리는 이 스킬 범위 밖이다. `.impl-spec/` 작업 파일은 PR이 만들어지면 Step 4에서 자동으로 지운다 (중간에 멈춘 실행은 재개용으로 남는다).
- 하위 스킬의 내부 규칙(force push 금지 등)은 그대로 적용된다.
