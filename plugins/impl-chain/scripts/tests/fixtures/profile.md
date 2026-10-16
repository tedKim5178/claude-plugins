# impl-chain 프로필 — 테스트 fixture (GitHub + Android 일반 레포)

## 이슈
- spec_adapter: builtin:gh-spec-issue
- spec_repo: example-org/planning
- spec_link_regex: planning/issues/([0-9]+)

## 서버 계약
- mode: proto-repo
- repo: example-org/proto

## git
- standalone_base_candidates: `main`
- branch_format: `feat/{n}-{slug}`
- commit_format: `{type}({scope}) : {요약}`

## 빌드
- compile: ./gradlew :{module}:compile{variant}Kotlin
- test: ./gradlew :{module}:test{variant}UnitTest
- module_variants: app = DevDebug / 그 외 = Debug
- install: ./gradlew :app:installDevDebug
- test_source_hint: {module}/src/test/

## 코드
- source_glob: '*.kt'
- trace_path: Screen → ViewModel → Repository
- navigation: `NavGraph.kt` 등
- variants: flavor dev·prod
- layer_order: 모델 → ViewModel → UI

## 디자인 토큰
- mode: map
- map: .claude/impl-chain/adapters/figma-token-map.md
- source: app/src/main/java/example/Tokens.kt

## UI 컴포넌트
- mode: map
- map: .claude/impl-chain/adapters/figma-component-map.md
- figma_client: clientFrameworks=jetpack-compose, clientLanguages=kotlin
- asset_lookup: `find app -path '*res/drawable*' -iname '*{name}*'`
- asset_export: npx -y -p svg2vectordrawable@2.9.1 s2v -i {svg} -o {out}
- asset_target: app/src/main/res/drawable/{name}.xml

## 문구
- mode: rule
- rule: .claude/impl-chain/adapters/string-resources.md

## 화면 확인
- mode: adb-mock
- mock_skill: fake-mock
