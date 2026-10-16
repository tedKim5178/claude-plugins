---
name: create-pr
description: start-work 완료 후 작업 브랜치를 push하고 PR을 생성할 때 사용. 스펙 이슈 연결 포함.
invocable: true
---

> **플러그인 `impl-chain`** — 이 플러그인의 스킬·에이전트는 `impl-chain:` 접두사로 부른다 (예: Skill `impl-chain:analyze-spec`, 에이전트 `impl-chain:code-researcher`). `${CLAUDE_PLUGIN_ROOT}`는 플러그인 설치 경로(절대 경로)로 치환되어 있다 — 명령에 그대로 쓴다. 레포별 값은 레포 루트 `.claude/impl-chain/`(프로필·어댑터)에 있다.


# Create PR

## ❌ 절대 금지 — Force Push

**`git push --force` / `-f` / `--force-with-lease`는 어떤 상황에서도 실행하지 않는다.**
push가 rejected·non-fast-forward 등으로 실패하면 보고 후 중단한다. 사용자가 요청해도 거부한다.

---

`start-work`로 커밋한 브랜치를 push하고 이슈와 연결된 PR을 만든다.
**PR 본문은 사람 리뷰어가 "기획서대로 됐는가"를 바로 확인할 수 있게** todo 체크리스트와 검증 증거를 담는다.

## 자동 진행 원칙

**묻지 않고:** 상태 파일 읽기, 브랜치 확인, 제목·본문 작성.
**확인 필요:** push 직전 (되돌리기 어려운 외부 공개 행위) / 상태 파일·이슈를 특정할 수 없을 때.

코드 리뷰는 여기서 하지 않는다 — `start-work` Step 9에서 끝났다.

## 입력

```
/create-pr                    # 상태 파일 선택 규칙대로
/create-pr spec 4895          # 명시
```

---

## 실행 단계

### 0. 상태 파일

`S=${CLAUDE_PLUGIN_ROOT}/scripts/impl-state.sh`. 선택은 `${CLAUDE_PLUGIN_ROOT}/references/impl-state-file.md`의 "상태 파일 선택 규칙"
(`find --stage implemented`). **가장 최근 파일로 고르지 않는다.**

| 상황 | 처리 |
|------|------|
| `stage: implemented` | 진행 |
| `stage: analyzed` | "start-work가 끝나지 않았습니다" 보고 후 중단 |
| `stage: pr_created` | `pr_url` 출력 후 종료 |
| 상태 파일 없음 | Step 0-1 |

```bash
$S check-branch {type} {n}     # 현재 브랜치 == 상태 파일 branch 인지. 다르면 보고 후 중단
```

### 0-1. 폴백 — 상태 파일 없음 (단독 작업)
```bash
B=$(git branch --show-current)          # 프로필 git.branch_format 꼴이어야 한다 (base 브랜치 위에서 실행한 게 아닌지)
git status --porcelain --untracked-files=no   # 비어 있어야 한다 (커밋 안 된 변경이 있으면 보고)
```
base와 이슈 번호는 **AskUserQuestion**으로 받는다 (base 선택지: 프로필 `git.standalone_base_candidates`). 추측하지 않는다.

### 1. 이미 PR이 있는지
```bash
gh repo view --json nameWithOwner --jq .nameWithOwner     # 앱 레포 → 이후 {app_repo}에 이 값을 **글자 그대로** 쓴다 (셸 변수는 다음 호출에 남지 않는다)
gh pr list --repo {app_repo} --head {branch} --state all --json number,url,state
```
있으면 새로 만들지 않고 URL 출력 (체인이면 `pr_url` merge + stage 전이) 후 종료.

### 2. 제목
start-work는 작업 전체를 한 커밋으로 남긴다 — 그 메시지를 쓴다 (이전 방식으로 커밋이 여러 개면 첫 커밋 메시지).
```bash
git log --reverse --format=%s $(git merge-base {base_branch} HEAD)..HEAD | head -1
```

### 3. 본문 작성

상태 파일에서 조립한다 (체인). 단독이면 해당 섹션을 생략한다.

```markdown
## 🔖 관련 이슈
* {issue_url}
* 기획서: {spec_url}   (없으면 줄 생략)

## 📝 구현 사항
* {implementation_direction 1~3줄}

## ✅ 구현 항목
- [x] T1 {desc} — {verify} ✅
- [x] T2 {desc} — visual ✅
- [ ] T4 {desc} — ⚠️ 수동 확인 필요: {사유}
- ~~T5 {desc}~~ — 범위 외 ({decision})

## 🧪 검증
* 확인한 앱: {apps — 있을 때만 줄}
* 테스트: {verification.tests}
* 화면: {verification.visual} {mock으로 만든 화면이면 그 사실을 한 구절로}
* 리뷰: 스펙 {review.spec} / 품질 {review.quality}

## 🤔 결정 사항
* {decisions — question → answer (by). 없으면 섹션 생략}

## 📌 추가 코멘트
* {verification.notes, 남은 ⚠️. 없으면 비움}
```

체크리스트는 todo의 `status` + `note`로 만든다 (파싱 없이):
- `done` + note가 `unit:` 또는 `visual: pass` → `[x]` (note에 `(통과 확인 후 삭제)`가 있으면 그대로 싣는다 — 테스트 코드는 PR에 없고 로컬에서 통과를 확인했다는 뜻)
- `done` + note가 `visual: skipped` / `manual:` → `[ ]` + "⚠️ 수동 확인 필요: {note}"
- `deferred` → 취소선 + note

### 3-1. PR 가능 여부 (원격 확인 — 체인에서 원격을 보는 유일한 지점)
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/check-pr-ready.sh {base_branch} {proto_dependency.status — 체인이면 상태 파일 값, 단독이면 생략}
```

| exit | 처리 |
|------|------|
| 0 | 진행. stdout = push·PR에 쓸 **원격 이름**(프로필 `git.remote`, 없으면 origin) → 이후 `{remote}`. stderr에 `WARN:`(로컬 base가 원격보다 앞섬)이 있으면 Step 4 확인 문구에 ⚠️로 그대로 싣는다 |
| 3 | base가 원격에 없음 → 메시지를 보여주고 **중단** (push·PR 안 함). "base를 먼저 push하거나, origin에 있는 브랜치에서 다시 분석해주세요" |
| 4 | 원격 조회 실패 (네트워크·`git.remote` 이름) → 보고 후 중단 |
| 5 | 임시 proto 반영 브랜치(`temp-local`) → **중단**. 로컬 테스트 전용이라 PR을 만들지 않는다 |

### 4. 사용자 확인 (필수)
```
{⚠️ 화면 확인을 하지 않았습니다 — {사유}   ← verification.visual이 skipped일 때만, 맨 위에}
브랜치: {branch} → base: {base_branch}
커밋: {commits 개수}개 — {제목}
이슈: {issue_url}
확인한 앱: {apps — 있을 때. 컴파일·테스트·화면 확인을 앱마다 함}
화면 확인: {verification.visual} — 리포트: {verification.visual_report — 앱별 객체면 앱마다 한 줄}   ← visual todo가 있을 때
(본문 미리보기)

push하고 PR을 생성할까요?
```
- `verification.visual_report`가 있으면 **경로를 링크로** 보여준다 — 사용자가 push 전에 스크린샷을 직접 보는 지점이다. 리포트를 본 뒤 고칠 것이 나오면 승인 전에 반영한다.
- 사용자가 리포트를 공유용 페이지로 원하면 `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/visual-report.py --fragment {state_file} {output_dir}`로 껍데기 없는 본문을 만들어 게시한다 (스크린샷에 계정·위치 등 개인 정보가 찍혀 있을 수 있다 — 요청받았을 때만, 비공개로).
- 리포트의 스크린샷은 로컬 파일이라 PR 본문에 넣지 않는다. 본문 "🧪 검증"에는 판정 요약만, "📌 추가 코멘트"에는 확인하지 못한 것(`verification.notes`)을 싣는다.

승인 → Step 5. 수정 요청 → 반영 후 재확인.

### 5. Push
```bash
git push -u {remote} {branch}     # {remote} = Step 3-1 stdout
```
실패 시 에러 보고 후 중단. **force push 금지.**

### 6. PR 생성
```bash
gh pr create --repo {app_repo} \
  --base {base_branch} --head {branch} --title "{제목}" --body-file {본문 파일}
```
본문은 scratch 파일에 써서 `--body-file`로 넘긴다 (heredoc 인용 문제 방지).

### 7. 상태 파일 갱신 (체인)
```bash
echo '{"pr_url":"{url}"}' | $S merge {type} {n}
$S stage {type} {n} pr_created
```

### 8. 완료 보고
```
PR #{번호}: {제목}
URL: {url}
```

---

## 주의사항

- push는 상태 파일의 `branch`와 현재 브랜치가 같을 때만.
- base는 상태 파일 값. 여기서 새로 정하지 않는다.
