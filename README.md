# claude-plugins

Claude Code 플러그인 마켓플레이스.

| 플러그인 | 설명 |
|---------|------|
| [`impl-chain`](plugins/impl-chain) | GitHub 기획 이슈에서 **분석 → 구현 → PR**까지 이어지는 작업 체인. GitHub + Android(Kotlin) 프로젝트용 |

## 설치

Claude Code 터미널에서:

```
/plugin marketplace add tedKim5178/claude-plugins
/plugin install impl-chain@tedkim
```

레포에 들어오면 자동으로 설치를 안내하게 하려면, 그 레포의 `.claude/settings.json`에:

```json
{
  "extraKnownMarketplaces": {
    "tedkim": { "source": { "source": "github", "repo": "tedKim5178/claude-plugins" } }
  },
  "enabledPlugins": { "impl-chain@tedkim": true }
}
```

업데이트: `/plugin marketplace update tedkim`

---

# impl-chain

기획 이슈 하나를 받아 **요구 분석 → 승인 → 브랜치·구현·테스트·리뷰·커밋 → PR**까지 진행한다.
단계마다 결과를 상태 파일(`.impl-spec/{type}-{n}.json`)로 넘겨서, 세션이 끊겨도 이어서 할 수 있다.

```
impl-spec ─┬─ analyze-spec  기획서·댓글·Figma·코드 리서치 → todo + 결정 → (사용자 승인)
           ├─ start-work    브랜치 → 테스트 먼저 → 구현 → 컴파일·테스트 → 화면 확인(스크린샷 비교 리포트) → 리뷰 2종 → 테스트 정리 → 커밋 1개
           └─ create-pr     PR 본문 조립 → (사용자 승인) → push + PR
impl-setup                  레포 프로필 생성 (레포마다 처음 한 번)
```

## 전제

- **GitHub** 이슈·PR + `gh` CLI 로그인
- 화면 확인은 **실기기가 연결돼 있으면 실기기, 없으면 에뮬레이터·시뮬레이터**로 한다. **Android**(adb·에뮬레이터)가 기본이다. **iOS**는 프로필에 기기 어댑터를 적는다 — 추천 `device_adapter: builtin:ios-real-device, builtin:ios-device`(우선순위 목록, 레포에 어댑터를 만들 필요 없음) / 시뮬레이터만 `device_adapter: builtin:ios-device`(Xcode + [AXe](https://github.com/cameroncooke/AXe): `brew install cameroncooke/axe/axe`) / USB 실기기만 `device_adapter: builtin:ios-real-device`(libimobiledevice + 기기에서 도는 [WebDriverAgent](https://github.com/appium/WebDriverAgent)). 그 외 플랫폼은 레포 전용 기기 어댑터를 적거나 화면 확인 없이 `none`으로 쓴다
- 도구: `git`, `gh`, `jq`, `python3`, `bash` 3.2+
- Figma 연동: [Figma 공식 플러그인](https://www.figma.com/developers/mcp) (MCP) 로그인
- (선택) 서버 계약을 proto 레포로 관리하면 proto 의존성 확인

## 시작하기

1. 플러그인 설치 (위)
2. 작업할 레포에서 `/impl-chain:impl-setup` — 레포를 분석해 `.claude/impl-chain/profile.md`(빌드 명령, 브랜치 형식, 디자인 토큰·컴포넌트 대응표, 문구 규칙 등)를 만들고 `.gitignore`에 `.impl-spec/`를 추가한다. 만든 프로필은 커밋해 둔다.
3. 기획 이슈로 실행:
   ```
   /impl-chain:impl-spec                 # 마일스톤 → 이슈 선택
   /impl-chain:impl-spec 4.11.0 1234     # 바로 분석
   /impl-chain:impl-spec 좌석 등급        # 키워드로 이슈 검색
   ```

## 동작 방식 요약

- **base = 실행한 로컬 브랜치.** 작업 브랜치는 그 로컬 tip에서 따고, 원격은 PR 직전에만 확인한다 (`git.remote`, 기본 origin).
- **승인은 두 번:** 분석 리포트(= 그 작업 브랜치의 커밋 허락), push·PR.
- **커밋은 작업 전체에 하나.** 규모가 커서 task로 나눠 구현해도 리뷰가 끝난 뒤 한 번만 커밋한다.
- **작업 중 쓴 테스트 코드는 커밋하지 않는다** (기본). 테스트를 먼저 쓰고 통과·리뷰까지 확인한 뒤 지운다. 남기려면 프로필 `빌드.test_retention: keep`.
- 기획서에 답이 없는 동작(에러 처리, 빈 상태, 뒤로가기, 정렬 동순위 등)은 **추천안을 붙인 질문**으로 분석 단계에서 모아 묻는다. 많으면 일괄 수락 가능.
- Figma 화면은 레이아웃 트리·요소 표·케이스 차이로 변환되고, 컴포넌트·토큰·아이콘 결정은 대응표에 누적된다.
- **Figma 좌표를 눈대중 숫자로 옮기지 않는다.** 요소마다 배치 의도(가운데 / 여백 / 간격 / 채움)를 Figma 근거(auto-layout·제약)와 함께 적고, 가운데인지 여백인지 애매하면 사용자에게 묻는다. 화면 확인은 요소 유무뿐 아니라 그 배치를 기기에서 재서 맞아야 통과한다.
- **화이트라벨 앱은 고른 것만, 고른 것은 전부 확인한다.** 프로필에 `빌드.apps`가 있으면 분석 시작 때 이번 작업의 앱을 고른다(기본 앱만 / 전부 / 직접 선택). 여러 개를 고르면 컴파일·테스트·화면 확인을 앱마다 하고, 하나라도 실패하면 통과가 아니다.
- **화면 확인은 계획부터 승인받는다.** 분석 단계에서 "어떤 화면을 어떤 조건으로 볼지"(대상·회귀 케이스 표)를 확정하고, 구현 뒤 기기에서 그대로 찍어 조건별로 나란히 놓은 리포트(`.impl-spec/{type}-{n}.visual/report.html`)를 만든다. 계획에 있는데 못 본 케이스는 "확인 안 함"으로 남고, push 승인 화면에서 리포트를 보여준다.
- 리뷰는 두 에이전트가 병렬로: 원문 대비 요구 충족, 코드 품질(기존 동작 보존·크래시·데드 코드).
- **예외 케이스는 todo에 줄로 남는다.** 분석에서 정한 예외·불변식(1회 호출, 중복 콜백, 백스택, 호출 경로의 전역 에러 처리)은 관련 todo 모두의 완료 조건에 `예외:` 줄로 들어가고, 리뷰어가 줄마다 코드 위치를 대조한다. 질문은 줄이지 않되 high(틀리면 동작이 달라짐 — 하나씩)와 low(구현 방식만 갈림 — 기본값 목록)로 나눠 묻는다.

## 레포마다 다른 것 — 프로필

`.claude/impl-chain/profile.md` (형식: [`references/impl-profile-spec.md`](plugins/impl-chain/references/impl-profile-spec.md))

| 섹션 | 예 |
|------|----|
| 이슈 | `spec_adapter: builtin:gh-spec-issue`, 기획서 레포, 기획 링크 정규식 |
| 빌드 | compile/test 명령 템플릿, 모듈별 variant |
| 디자인 토큰 / UI 컴포넌트 | Figma ↔ 코드 대응표, 아이콘 export 명령 |
| 문구 | 새 문구를 어디에 어떤 키로 넣는지 규칙 |
| 화면 확인 | `device-mock`(mock 스킬로 서버 응답 조작) / `device` / `none`, 기기 어댑터(Android 기본 / iOS 시뮬레이터 / iOS 실기기 / 레포 전용 — `/impl-setup`이 상황에 맞게 고르거나 만들고 실제 기기로 검사한다) |
| git | 브랜치·커밋 형식, PR 원격 |

## 개발

```bash
for t in plugins/impl-chain/scripts/tests/*.test.sh; do bash "$t"; done   # 스크립트 테스트 (임시 git 레포에서 실행)
claude --plugin-dir plugins/impl-chain                                   # 설치 없이 로컬로 써 보기
claude plugin validate .                                                 # 매니페스트 검증
```
