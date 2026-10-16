# impl-chain 프로필 규격

체인(`impl-spec` / `analyze-spec` → `start-work` → `create-pr`, 에이전트 8개, `scripts/`의 상태 스크립트)은
**레포 고유 값을 갖지 않는다.** 레포마다 다른 것은 전부 여기 둔다:

```
.claude/impl-chain/
├── profile.md      이 문서 형식의 값
└── adapters/       프로필이 가리키는 레포 전용 스크립트·문서 (아래 계약을 지킨다)
```

**다른 레포로 옮기기:** 체인(스킬·에이전트·`scripts/`·`references/`)은 공통 자산이다 — 플러그인으로 설치하거나 그대로 복사하고,
레포에서는 `/impl-setup`으로 `impl-chain/`만 만든다 (또는 이 형식대로 직접 작성). 스크립트는 레포 경로를 가정하지 않고 자기 위치 기준으로 서로를 찾는다.
GitHub 이슈를 쓰면 이슈 어댑터는 공용 스크립트를 그대로 쓰고(`builtin:` 값), 레포마다 만드는 어댑터는 대응표(토큰·컴포넌트, 빈 표로 시작 가능)와 문구 규칙 정도다.

**레포 요구 사항:** `.gitignore`에 `.impl-spec/` (상태 파일·이슈 원문·리서치가 여기 쌓인다 — 커밋되면 안 된다). `/impl-setup`이 추가하고, 프로필 게이트가 검사한다.

## 전제

- 이슈·PR은 **GitHub + `gh` CLI**를 쓴다 (create-pr, 리뷰어의 원문 조회). 이슈 트래커가 다르면 spec 어댑터가 계약 형식으로 변환하고, create-pr은 수정이 필요하다.
- 도구: `git`, `gh`(로그인), `jq`, `python3`, `bash`(3.2+ — macOS 기본 셸 가능). 화면 확인(`device`·`device-mock`)은 기기 어댑터가 쓰는 도구 — `builtin:android-device`면 Android SDK(adb, emulator), `builtin:ios-device`면 Xcode(`xcrun simctl`) + [AXe](https://github.com/cameroncooke/AXe)(`brew install cameroncooke/axe/axe`), `builtin:ios-real-device`면 libimobiledevice(`brew install libimobiledevice`) + 기기에서 도는 [WebDriverAgent](https://github.com/appium/WebDriverAgent).
- 공용 기기 어댑터는 Android(`builtin:android-device` — 기본값), iOS 시뮬레이터(`builtin:ios-device`), iOS 실기기(`builtin:ios-real-device`)가 있다. 그 외 플랫폼은 레포 전용 기기 어댑터를 `화면 확인.device_adapter`에 적는다. 에셋 export 예시는 Android 기준이다 (`asset_export`의 vector drawable) — 다른 플랫폼은 자기 명령을 적는다.

## 형식

`## {섹션}` 아래 `- {키}: {값}` 한 줄씩. 체인 문서는 **"프로필 `섹션.키`"** 로 가리킨다 (예: 프로필 `빌드.compile`).
값 안의 `{module}`, `{variant}`, `{app}`, `{name}`, `{n}`, `{slug}`는 쓰는 쪽이 실행 시 채운다. `{variant}`는 `빌드.module_variants`에서 그 모듈에 해당하는 값이다. `{app}`은 사용자가 고른 화이트라벨 앱의 값(`빌드.apps`)이다 — `module_variants` 값 안에 있어도 된다 (예: `app, presenter → {app}QaDebug`).

## 프로필 게이트 (체인 시작 시 — analyze-spec Step 0-0, 단독 start-work Step 0-0)

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/impl-profile.sh check --for {analyze-spec | start-work}
```
exit 0이면 통과. 아니면 stderr의 문제 목록을 그대로 보여주고 **중단** (프로필이 없으면 `/impl-setup` 안내가 나온다).
스크립트가 검사하는 것: 아래 표의 필수 키·조건부 필수 키, 모드 값 범위, 모드가 가리키는 파일·mock 스킬 존재, 스킬별 이슈 어댑터(해석·실행 가능)와 그 키, `.impl-spec/` gitignore.

이슈 어댑터는 경로가 아니라 **해석해서** 부른다: `$(${CLAUDE_PLUGIN_ROOT}/scripts/impl-profile.sh adapter 이슈.spec_adapter) list 4.14.0`
(`builtin:gh-spec-issue` → 체인 `scripts/`의 공용 어댑터, 그 외 값 → 레포 루트 기준 경로).

값 읽기도 같은 스크립트로 한다: `${CLAUDE_PLUGIN_ROOT}/scripts/impl-profile.sh get 빌드.compile` (없으면 exit 2).

선택 키(필수 열이 빈 키)가 없으면 그 키를 쓰는 조사·확인만 생략한다 (예: `navigation`·`variants` 없음 → 그 항목 조사 생략, `asset_lookup` 없음 → 아이콘 칸에 `프로젝트 존재 미확인`만 적고 질문하지 않음, `asset_export` 없음 → 없는 에셋은 자동 export하지 않고 질문, `string_table_hint` 없음 → 기획서·댓글 원문 문구를 그대로 씀).

**필수 키가 빠진 것을 `none`이나 그럴듯한 값으로 간주하지 않는다.** (토큰이 있는 레포가 원시 값으로 구현되는 사고를 막는다.)

## 키

| 섹션 | 키 | 필수 | 의미 |
|------|-----|------|------|
| 이슈 | `spec_adapter` | analyze-spec 사용 시 | spec 어댑터. GitHub이면 `builtin:gh-spec-issue` (체인 공용), 아니면 레포 전용 어댑터의 레포 루트 기준 경로 |
| | `spec_repo` | 공용 spec 어댑터면 | 기획서 이슈가 있는 레포 (`owner/name`) — 기획서 본문 파일 링크 조회에도 쓴다 |
| | `spec_link_regex` | 공용 spec 어댑터면 | 앱 이슈 본문·댓글에서 기획 이슈 번호를 뽑는 정규식(python `re`, 그룹 1 = 번호). 예: `planning/issues/([0-9]+)` |
| | `string_table_hint` | | 기획자가 문구 키 표를 올리는 방식 (예: 댓글의 `키 \| ko` 표) |
| 서버 계약 | `mode` | ✅ | `proto-repo` \| `none` |
| | `repo` | mode=proto-repo | 서버 계약(proto) 레포 `owner/name` |
| git | `standalone_base_candidates` | ✅ | 상태 파일 없는 단독 start-work/create-pr에서 base 선택지 |
| | `branch_format` | ✅ | 브랜치명 형식. `{접두사}/{이름}` 꼴이어야 한다 (`impl-state.sh`는 이 꼴만 검사) |
| | `commit_format` | ✅ | 커밋 메시지 형식 |
| | `remote` | | push·PR에 쓰는 원격 이름. 없으면 `origin` (포크 구조로 `upstream` 등을 쓰는 레포) |
| 빌드 | `compile` | ✅ | 컴파일 명령 템플릿 (`{module}`) |
| | `test` | ✅ | 유닛 테스트 명령 템플릿. 테스트 인프라가 없으면 `none` |
| | `install` | 화면 확인.mode가 none이 아니면 | 기기 설치 명령. `{id}`가 있으면 visual-verifier가 기기 어댑터 `ensure`가 고른 기기 id로 채운다 |
| | `install_real` | | 고른 기기가 **실기기**(`KIND real`)일 때만 `install` 대신 쓰는 설치 명령 (`{id}` 같음). iOS처럼 실기기·시뮬레이터 빌드가 다를 때. 없으면 `install` |
| | `apps` | 빌드 명령에 `{app}`이 있으면 | 화이트라벨 앱 목록 — 같은 코드로 빌드하는 앱(Android product flavor, iOS 앱 타깃·스킴). 쉼표 구분 `이름=값` (값 = `{app}` 자리에 들어갈 문자열, `이름`만 쓰면 값 = 이름). **첫 항목이 기본 앱**. 이름은 영문·숫자·`._-`. 예: `shucle=Shucle, gmaas=Gmaas, sejong=Sejong` (Android `install{app}DevDebug`) / `shucle=Shucle_DEV-dev, gmaas=gMaaS_DEV-dev` (iOS `-scheme {app}`). analyze-spec이 이번 작업의 앱을 묻고, start-work가 고른 앱마다 컴파일·테스트·화면 확인을 한다 |
| | `module_variants` | compile/test에 `{variant}`가 있으면 | 모듈(그룹) → variant 대응. 모듈마다 빌드 변형이 다른 레포용 |
| | `test_source_hint` | | 모듈의 테스트 소스 위치 (테스트가 있는지 판단용) |
| | `test_retention` | | `discard`(기본 — 키가 없을 때도) \| `keep`. `discard`: start-work가 이번 작업에서 추가한 테스트 코드를 통과 확인·리뷰 뒤에 지우고 커밋에 넣지 않는다 (start-work Step 9-1). `keep`: 테스트도 커밋한다 |
| 코드 | `source_glob` | ✅ | 코드 검색 glob. 여러 개면 공백으로 구분하고 각각 따옴표로 (예: `'*.kt'`, `'*.ts' '*.tsx'`) — `git grep … -- {source_glob}`에 그대로 붙인다 |
| | `trace_path` | ✅ | 화면 요구를 따라갈 레이어 순서 |
| | `navigation` | | 라우트/네비게이션 정의 위치 |
| | `variants` | | 같은 코드를 공유하는 앱·서비스 변형 (영향 범위에 분기별로 넣는다) |
| | `layer_order` | ✅ | large 작업의 task 의존 순서 |
| 디자인 토큰 | `mode` | ✅ | `map` \| `none` (`script`·`doc`은 `map`으로 통합 — 게이트가 거부) |
| | `map` | mode=map | Figma 변수 ↔ 프로젝트 토큰 대응표 |
| | `source` | mode=map | 시맨틱 토큰 정의 파일 (공백 구분, 레포 루트 기준). 대응표에 없는 변수의 값 일치 탐색 대상. 팔레트 파일은 넣지 않는다 (값을 따라갈 때만 읽는다) |
| UI 컴포넌트 | `mode` | ✅ | `map` \| `none` (`discover`는 `map`으로 통합 — 게이트가 거부) |
| | `map` | mode=map | Figma 컴포넌트 ↔ 프로젝트 컴포넌트 대응표 |
| | `figma_client` | ✅ | `get_design_context`의 `clientFrameworks`, `clientLanguages` |
| | `asset_lookup` | | 아이콘·이미지가 프로젝트에 있는지 찾는 명령 (`{name}`) |
| | `asset_export` | | Figma에서 받은 SVG를 프로젝트 형식으로 바꾸는 명령 (`{svg}`, `{out}`). 없으면 없는 에셋은 질문 |
| | `asset_target` | asset_export가 있으면 | 변환 결과를 둘 레포 상대 경로 템플릿 (`{name}`) |
| 문구 | `mode` | ✅ | `rule` \| `hardcode` |
| | `rule` | mode=rule | 문구 규칙 문서 (어디에, 어떤 키로, 리뷰 시 무엇을 검사하는지) |
| 화면 확인 | `mode` | ✅ | `device-mock`(기기 + 서버 응답 mock 스킬) \| `device`(기기만 — 서버 상태가 필요한 케이스는 수동 확인) \| `none`. `adb-mock`·`adb`는 `device-mock`·`device`와 같은 뜻으로 받는다 |
| | `device_adapter` | | 기기 어댑터 — 기기 확보·화면 읽기·탭·스크린샷을 하는 스크립트. **쉼표로 여러 개 적으면 우선순위 목록**이다 — visual-verifier가 앞에서부터 기기를 확보해 보고 처음 성공한 것을 쓴다 (예: `builtin:ios-real-device, builtin:ios-device` = 실기기가 연결돼 있으면 실기기, 아니면 시뮬레이터). `builtin:android-device`(체인 공용 — adb·에뮬레이터) / `builtin:ios-device`(체인 공용 — iOS 시뮬레이터, simctl + AXe) / `builtin:ios-real-device`(체인 공용 — USB로 연결한 iOS 실기기, WebDriverAgent) 또는 레포 전용 어댑터의 레포 루트 기준 경로. **없으면 `builtin:android-device`** |
| | `mock_skill` | mode=device-mock | 서버 응답 mock 스킬 이름 — 레포 `.claude/skills/` 또는 `~/.claude/skills/`에 있어야 한다 |
| | `mock_skill_real` | | 고른 기기가 실기기(`KIND real`)일 때만 `mock_skill` 대신 쓰는 mock 스킬 (mock을 넣는 통로가 실기기·가상 기기에서 다를 때). 없으면 `mock_skill` |
| | `avd` | | (`builtin:android-device` 전용) 연결 기기가 없을 때 헤드리스로 부팅할 AVD 이름 (없으면 `emulator -list-avds` 첫 번째). 레포 전용 기기 어댑터는 자기 키를 정해 `impl-profile.sh get`으로 읽는다 |
| | `simulator` | | (`builtin:ios-device` 전용) 부팅된 시뮬레이터가 없을 때 부팅할 시뮬레이터 이름 또는 UDID (없으면 최신 iOS 런타임의 첫 iPhone) |
| | `device_udid` | | (`builtin:ios-real-device` 전용) 쓸 기기 UDID (없으면 USB로 연결된 첫 기기) |
| | `wda_port` | | (`builtin:ios-real-device` 전용) WebDriverAgent로 포워드할 Mac 쪽 포트 (기본 8100) |
| | `wda_start` | | (`builtin:ios-real-device` 전용) WebDriverAgent가 안 떠 있을 때 띄우는 명령 — `{udid}`가 기기 UDID로 바뀐다. 예: `xcodebuild -project {WDA 경로}/WebDriverAgent.xcodeproj -scheme WebDriverAgentRunner -destination id={udid} -allowProvisioningUpdates test`. 없으면 WDA를 직접 띄워 둔 상태에서만 동작한다 |

## 모드별 동작

| 항목 | 모드 | figma-ui-spec 표 (analyze Step 4-1) | 구현 (start-work) | 리뷰 |
|------|------|-----------------|------------------|------|
| 디자인 토큰 | `map` | 대응표 → 없으면 `source`에서 값 완전 일치 탐색 → 판정 규칙(1개면 자동, 0개·2개 이상·해석 불확실은 질문). 확정분은 start-work Step 2-1이 대응표에 누적 | 토큰 | 토큰 일치 |
| | `none` | 원시 값 (hex·sp·weight) | 값 그대로 | 값 일치 |
| UI 컴포넌트 | `map` | 대응표 → 없으면 코드베이스 탐색 → 판정 규칙(후보 0개·확실한 1개는 자동, 그 외 질문). 확정분은 start-work Step 2-1이 대응표에 누적 | 그 컴포넌트 | 일치 |
| | `none` | 플랫폼 기본 요소로 구조 | 기본 요소 | 구조·값 일치 |
| 문구 | `rule` | 규칙 문서대로 키 | 규칙 문서대로 | impl-reviewer: 규칙 문서의 "확인" / spec-conformance: 값 일치 |
| | `hardcode` | 원문 문구 | 문자열 그대로 | 값 일치만 |
| 화면 확인 | `device-mock` | — | — | start-work Step 8 visual-verifier 실행 (mock으로 케이스별 서버 응답) |
| | `device` | — | — | visual-verifier 실행, mock 없이 도달 가능한 케이스만 확인 — 나머지는 MANUAL |
| | `none` | — | — | visual-verifier 생략, visual todo는 PR에 "수동 확인 필요" |
| 서버 계약 | `proto-repo` | — | — | spec-researcher proto 조사, analyze-spec Step 5 게이트 |
| | `none` | — | — | proto 조사 생략, `proto_dependency = {required:false, status:"n/a"}` |

모드와 무관하게: **문구 값은 원문과 글자 단위로 일치**, **추측 금지** (모드가 `none`이어도 값은 Figma·기획서에서 그대로 옮긴다).

## 어댑터 계약

어댑터는 무엇으로 짜도 되지만 **입출력은 이대로** 지킨다. 체인 문서는 이 출력만 믿는다.

### spec 어댑터 (`이슈.spec_adapter`)

| 호출 | 출력 |
|------|------|
| `{spec_adapter} milestones` | 열린 마일스톤 제목, 줄 단위 |
| `{spec_adapter} list <milestone>` | `#{n} {title}`, 줄 단위 (내게 할당된 open 이슈 — **전부**, 페이지 상한으로 자르지 않는다) |
| `{spec_adapter} search <keyword>` (선택) | `#{n} [{milestone}] [{state}] {title}`, 줄 단위 (앱 이슈 키워드 검색). 없으면 analyze-spec이 키워드 입력을 마일스톤 선택으로 대신한다 |
| `{spec_adapter} fetch <milestone> <n> [spec_n]` | JSON 아래 |

```json
{
  "issue":          {"number": 0, "title": "", "body": "", "labels": [], "url": ""},
  "issue_comments": [{"author": "", "created_at": "", "body": ""}],
  "spec":           {"number": 0, "title": "", "body": "", "url": ""},
  "comments":       [{"author": "", "created_at": "", "body": ""}],
  "spec_candidates":[{"number": 0, "title": "", "found_in": "본문|댓글|본문,댓글"}]
}
```
- 기획 이슈 후보가 0개이거나 2개 이상이고 `spec_n`이 없으면 `spec`은 `{}`, `comments`는 `[]` (호출자가 사용자에게 묻고 `spec_n`으로 다시 호출).
- 기획서가 앱 이슈 자체에 있는 레포라면 `spec`에 앱 이슈를 그대로 넣고 `spec_candidates`는 `[]`로 둔다.
- 댓글은 페이지네이션해서 전부.

### 기기 어댑터 (`화면 확인.device_adapter`)

visual-verifier는 기기를 이 어댑터로만 다룬다. 경로는 `impl-profile.sh adapters`로 우선순위 순서대로 얻는다 (키가 없으면 `builtin:android-device` 하나).
목록이면 앞에서부터 `ensure`를 시도해 exit 3·4(도구·기기 없음)·5(시간 초과)면 다음 어댑터로 넘어가고, 처음 성공한 어댑터 하나만 쓴다.
`{id}`는 `ensure`가 준 기기 식별자다 (Android serial, iOS 시뮬레이터 UDID 등 — 어댑터가 정한다).

| 호출 | 동작·출력 | 필수 |
|------|-----------|------|
| `{device_adapter} check` | 기기 도구를 쓸 수 있으면 exit 0 (stdout: 도구 경로 한 줄), 없으면 exit 3. impl-setup이 모드 후보를 정할 때 쓴다 | ✅ |
| `{device_adapter} ensure` | stdout = 쓸 기기 `{id}`. 연결된 기기가 없으면 에뮬레이터·시뮬레이터를 부팅하고 stderr에 `BOOTED {id}` 한 줄. 실기기·가상 기기를 다 다루는 어댑터는 **실기기를 먼저** 고른다. exit 3 도구 없음 / 4 기기 없음 / 5 부팅 시간 초과 (stderr 첫 줄 = 사유) | ✅ |
| (`ensure`의 stderr) `KIND real\|virtual` | 고른 기기가 실기기인지 에뮬레이터·시뮬레이터인지 한 줄. visual-verifier가 `빌드.install_real`·`화면 확인.mock_skill_real`을 쓸지 정한다 — 없으면 둘 다 쓰지 않는다. 공용 어댑터는 모두 낸다 | |
| `{device_adapter} cleanup {id}` | `ensure`가 부팅한 기기를 종료. 원래 연결돼 있던 기기는 건드리지 않는다 | ✅ |
| `{device_adapter} ui {id}` | stdout = 화면 요소 트리. 요소마다 **보이는 텍스트와 화면 좌표**가 있어야 한다 (형식은 자유 — XML·JSON 등). 못 읽으면 exit 1 | ✅ |
| `{device_adapter} tap {id} {x} {y}` | 그 좌표를 탭. **좌표계는 `ui` 출력과 같다** — 스크린샷 픽셀과는 배율이 다를 수 있다 (iOS는 포인트, 스크린샷은 2~3배 픽셀) | ✅ |
| `{device_adapter} swipe {id} {x1} {y1} {x2} {y2} [ms]` | 스와이프·스크롤 | ✅ |
| `{device_adapter} screenshot {id} {out.png}` | 현재 화면을 PNG로 저장. 실패하면 exit 1 | ✅ |
| `{device_adapter} key {id} back\|home` | 시스템 키. 플랫폼에 없으면 exit 1 (호출자가 화면의 버튼을 tap한다) | |

- 앱 설치는 어댑터가 아니라 프로필 `빌드.install`(실기기면 `빌드.install_real`이 있을 때 그것)이 한다 — `{id}`로 `ensure`가 고른 기기에 설치되도록 맞춘다.
  (iOS 예: 시뮬레이터 `install` = 시뮬레이터용 빌드 후 `xcrun simctl install {id} {앱.app}` / 실기기 `install_real` = 기기용 빌드 후 `xcrun devicectl device install app --device {id} {앱.app}`. Android는 실기기·에뮬레이터 모두 `adb -s {id} install` 하나면 된다.)
- `builtin:ios-device`는 **시뮬레이터 전용**, `builtin:ios-real-device`는 **USB 실기기 전용**이다. 둘 다 `key back`은 없다 — 화면의 뒤로 버튼을 tap한다.
- `builtin:ios-real-device`는 기기를 부팅하지 않는다. `ensure`는 포트 포워드(iproxy)를 열고 WebDriverAgent가 응답할 때까지 기다리며(필요하면 `wda_start` 실행), 자기가 띄운 것이 있으면 `BOOTED`를 낸다 — `cleanup`은 그 포워드·WDA 프로세스만 끝낸다.
  WebDriverAgent는 본인 개발 팀으로 서명해 기기에 올릴 수 있어야 한다 (Xcode에서 WebDriverAgentRunner 타깃의 Team·Bundle Identifier 설정 — 한 번).
- 기기 선택에 설정이 필요하면(부팅할 기기 이름 등) 어댑터가 `화면 확인` 섹션에 자기 키를 정해 읽는다.
- mock 스킬은 어댑터와 별개다 (`화면 확인.mock_skill`) — 같은 플랫폼·같은 대상(에뮬레이터/실기기)의 것끼리 짝을 맞춘다. 어댑터 목록이 실기기·가상 기기를 다 쓰는데 mock을 넣는 통로가 다르면 실기기용을 `mock_skill_real`에 적는다.
- iOS에서 실기기를 먼저 쓰고 싶으면 `builtin:ios-real-device, builtin:ios-device`로 적는다. 레포에 어댑터를 새로 만들 필요는 없다 — Mac에 도구(실기기: libimobiledevice + WebDriverAgent 서명, 시뮬레이터: Xcode + AXe)만 있으면 된다. 실기기 쪽이 준비 안 됐으면 자동으로 시뮬레이터로 넘어간다.
- **어댑터는 검사를 통과한 것만 프로필에 적는다** (목록이면 어댑터마다): `device-adapter-check.sh [--out <dir>] [<어댑터 경로>]`가 실제 기기로 위 호출을 한 바퀴 돌린다 (exit 0 계약 통과 / 1 계약 위반 / 2 도구·기기가 없어 검사 못 함). `/impl-setup` Step 4-1이 공용 어댑터를 고르거나 레포 전용 어댑터를 `.claude/impl-chain/adapters/`에 만든 뒤 이 검사를 돌린다. 어댑터를 손으로 고쳤을 때도 돌린다.

### 문서형 어댑터 (`UI 컴포넌트.map`, `디자인 토큰.map`, `문구.rule`)

- `map`: 표 `| Figma 컴포넌트 (data-name) | 프로젝트 | 비고 | 근거 |` (행이 없는 빈 표도 유효). 표에 없으면 figma-ui-spec 판정 규칙으로 자동 결정 또는 질문하고,
  확정분은 start-work Step 2-1이 `apply-ui-decisions.py`로 행을 추가한다. 기본 요소로 구현하기로 한 것도 `없음 — 기본 요소` 행으로 남기고, 비고의 `사용 이슈:`에 이슈가 쌓인다(3개 이상이면 공용화 후보).
- 토큰 `map`: 표 `| Figma 변수 | 토큰 | 값 | 근거 |` (행이 없는 빈 표도 유효 — 코드에 Figma 이름 연결이 없는 레포의 시작점). 이름 비교는 대소문자 무시.
  값 칸: 색 = 라이트 테마 hex(대문자, 알파가 FF가 아니면 8자리), 타이포 = `크기/굵기/행간`. 숫자 변수(`padding/`·`gap/`·`radius/`·`spacing/`·`font-size/`)는 넣지 않는다.
  표에 없으면 figma-ui-spec 판정 규칙으로 자동 결정 또는 질문하고, 확정분은 start-work Step 2-1이 `apply-ui-decisions.py`(`token_row`)로 행을 추가한다.
  토큰 없이 원시 값으로 구현하기로 한 것도 `없음 — 원시 값` 행으로 남긴다 (같은 질문 반복 방지).
- `rule`: 반드시 세 절을 둔다 — **규칙**(새 문구를 어디에 어떤 키로), **금지**, **확인**(리뷰어가 실행할 명령과 위반 등급).
