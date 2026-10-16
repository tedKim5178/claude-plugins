#!/bin/bash
# 기기 어댑터 (iOS 실기기) — visual-verifier가 쓰는 기기 확보·조작·정리. 프로필 `화면 확인.device_adapter: builtin:ios-real-device`.
# 계약: impl-chain references/impl-profile-spec.md "기기 어댑터". 시뮬레이터는 ios-device.sh(builtin:ios-device).
#
# 실기기에는 화면 읽기·터치·스크린샷을 해 주는 Apple CLI가 없다. 기기에서 도는 WebDriverAgent(WDA — XCUITest 러너,
# https://github.com/appium/WebDriverAgent)의 HTTP API를 USB 포트 포워드(iproxy)로 부른다.
#
# 도구: libimobiledevice(`idevice_id`, `iproxy` — brew install libimobiledevice), `curl`, `python3`
# 전제: 기기가 USB로 연결·신뢰돼 있고 개발자 모드가 켜져 있다. WDA는 본인 개발 팀으로 서명해 기기에 올릴 수 있어야 한다.
#
# 프로필 키 (`화면 확인` 섹션 — 전부 선택):
#   device_udid  쓸 기기 UDID (없으면 USB로 연결된 첫 기기)
#   wda_port     WDA로 포워드할 Mac 쪽 포트 (기본 8100 — 기기 쪽은 항상 8100)
#   wda_start    WDA가 안 떠 있을 때 띄우는 명령. `{udid}`가 기기 UDID로 바뀐다. 끝나지 않는 명령이어야 한다. 예:
#                xcodebuild -project ~/WebDriverAgent/WebDriverAgent.xcodeproj -scheme WebDriverAgentRunner -destination id={udid} -allowProvisioningUpdates test
#                없으면 WDA를 직접 띄워 둔 상태에서만 동작한다.
#
# Usage:
#   ios-real-device.sh check                → 도구가 있으면 iproxy 경로 출력 (기기·WDA 상태는 보지 않는다)
#   ios-real-device.sh ensure [udid]        → 쓸 기기 UDID 출력. 포트 포워드를 열고 WDA가 응답할 때까지 기다린다 (필요하면 wda_start 실행).
#       이 어댑터가 포워드나 WDA를 띄웠으면 stderr에 `BOOTED {udid}` — 호출자는 끝날 때 cleanup으로 정리한다. stderr에 `KIND real` 한 줄.
#       WDA 대기 시간: $IOS_WDA_START_TIMEOUT초 (기본 180)
#   ios-real-device.sh cleanup <udid>       → ensure가 띄운 포트 포워드·WDA 프로세스 종료 (기기와 원래 떠 있던 WDA는 건드리지 않는다)
#   ios-real-device.sh ui <udid>                              → 화면 요소 트리(WDA JSON — label·rect) 출력. 좌표 단위는 포인트
#   ios-real-device.sh tap <udid> <x> <y>                     → 탭 (포인트 — `ui`의 rect와 같은 좌표계. 스크린샷 픽셀이 아니다)
#   ios-real-device.sh swipe <udid> <x1> <y1> <x2> <y2> [ms]  → 누른 채 끌기 (ms = 끌기 전 누르는 시간, 기본 300ms)
#   ios-real-device.sh key <udid> home                        → 홈 화면. back은 iOS에 없다 (exit 1 — 화면의 뒤로 버튼을 tap한다)
#   ios-real-device.sh screenshot <udid> <out.png>            → 스크린샷 저장
#
# 종료 코드: 0 성공 / 3 도구 없음 / 4 기기 없음·WDA를 띄울 수단 없음 / 5 WDA 대기 시간 초과 / 1 사용법 오류·조작 실패

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

for t in idevice_id iproxy; do
  command -v "$t" > /dev/null 2>&1 \
    || { echo "$t 를 찾지 못했습니다 — 실기기 연결에 필요합니다: brew install libimobiledevice" >&2; exit 3; }
done
for t in curl python3; do
  command -v "$t" > /dev/null 2>&1 || { echo "$t 를 찾지 못했습니다" >&2; exit 3; }
done

profile() { "$HERE/impl-profile.sh" get "화면 확인.$1" 2> /dev/null || true; }
PORT="$(profile wda_port)"; PORT="${PORT:-8100}"
BASE="http://127.0.0.1:$PORT"

# ensure가 띄운 프로세스(pid 한 줄씩)와 WDA 세션 id — cleanup은 여기 적힌 것만 정리한다
STATE_DIR="${TMPDIR:-/tmp}/impl-chain-ios-real-device"
pids_file()    { echo "$STATE_DIR/$1.pids"; }
session_file() { echo "$STATE_DIR/$1.session"; }

# $1=메서드 $2=경로 $3=제한 시간(초) [$4=JSON 본문] → 응답 본문 (stdout). 연결 실패면 return 1
wda() {
  if [ $# -ge 4 ]; then
    curl -s --max-time "$3" -X "$1" "$BASE$2" -H 'Content-Type: application/json' -d "$4"
  else
    curl -s --max-time "$3" -X "$1" "$BASE$2"
  fi
}
# stdin = WDA 응답 JSON. $1 = 파이썬 식(d = 응답). 식의 값이 참이면 exit 0 (문자열이면 출력도 한다)
jq_py() {
  python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    v = eval(sys.argv[1])
except Exception:
    sys.exit(1)
if isinstance(v, str):
    print(v)
sys.exit(0 if v else 1)
' "$1"
}
status_ready() { wda GET /status 5 | jq_py '(d.get("value") or {}).get("ready") is True' > /dev/null 2>&1; }
# 응답에 WDA 오류가 없으면 exit 0
no_error() { jq_py 'not (isinstance(d.get("value"), dict) and "error" in d["value"])' > /dev/null 2>&1; }

new_session() { # $1=udid → 세션 id (stdout), 파일에도 적는다
  local sid
  sid="$(wda POST /session 30 '{"capabilities":{"alwaysMatch":{}}}' | jq_py '(d.get("value") or {}).get("sessionId") or d.get("sessionId") or ""')" \
    && [ -n "$sid" ] || return 1
  mkdir -p "$STATE_DIR" && echo "$sid" > "$(session_file "$1")"
  echo "$sid"
}
# 세션이 필요한 POST. 저장된 세션이 죽었으면 새로 만들어 한 번 더 한다. $1=udid $2=경로(/wda/…) $3=본문
session_post() {
  local sid res
  sid="$(cat "$(session_file "$1")" 2> /dev/null || true)"
  if [ -n "$sid" ]; then
    res="$(wda POST "/session/$sid$2" 30 "$3")" && no_error <<< "$res" && return 0
  fi
  sid="$(new_session "$1")" || { echo "WDA 세션을 만들지 못했습니다 ($BASE)" >&2; return 1; }
  res="$(wda POST "/session/$sid$2" 30 "$3")" && no_error <<< "$res"
}

case "${1:-}" in
  check)
    command -v iproxy
    ;;

  ensure)
    WANT="${2:-}"; [ -n "$WANT" ] || WANT="$(profile device_udid)"
    ATTACHED="$(idevice_id -l 2> /dev/null)"
    if [ -n "$WANT" ]; then
      grep -qx -- "$WANT" <<< "$ATTACHED" || { echo "기기 $WANT 가 USB로 연결돼 있지 않습니다 (idevice_id -l)" >&2; exit 4; }
      UDID="$WANT"
    else
      UDID="$(head -1 <<< "$ATTACHED")"
    fi
    [ -n "$UDID" ] || { echo "USB로 연결된 iOS 기기가 없습니다 — 케이블 연결과 '이 컴퓨터 신뢰'를 확인해주세요" >&2; exit 4; }

    if status_ready; then echo "KIND real" >&2; echo "$UDID"; exit 0; fi   # 포워드와 WDA가 이미 떠 있다 — 그대로 쓴다

    mkdir -p "$STATE_DIR" && : > "$(pids_file "$UDID")"
    nohup iproxy -u "$UDID" "$PORT:8100" > /dev/null 2>&1 &
    echo $! >> "$(pids_file "$UDID")"
    sleep 1
    if ! status_ready; then
      START="$(profile wda_start)"
      if [ -z "$START" ]; then
        echo "기기에서 WebDriverAgent가 응답하지 않습니다 ($BASE/status) — WDA를 띄워 두거나 프로필 화면 확인.wda_start에 띄우는 명령을 적어주세요" >&2
        "$0" cleanup "$UDID"
        exit 4
      fi
      nohup /bin/bash -c "${START//\{udid\}/$UDID}" > "$STATE_DIR/$UDID.wda.log" 2>&1 &
      echo $! >> "$(pids_file "$UDID")"
      TIMEOUT="${IOS_WDA_START_TIMEOUT:-180}"
      READY=0
      for _ in $(seq 1 "$TIMEOUT"); do
        if status_ready; then READY=1; break; fi
        sleep 1
      done
      if [ "$READY" = 0 ]; then
        echo "WebDriverAgent 대기 시간 초과 (${TIMEOUT}초) — 로그: $STATE_DIR/$UDID.wda.log" >&2
        "$0" cleanup "$UDID"
        exit 5
      fi
    fi
    echo "BOOTED $UDID" >&2
    echo "KIND real" >&2
    echo "$UDID"
    ;;

  cleanup)
    UDID="${2:?usage: ios-real-device.sh cleanup <udid>}"
    if [ -f "$(pids_file "$UDID")" ]; then
      while read -r pid; do
        [ -n "$pid" ] || continue
        pkill -P "$pid" > /dev/null 2>&1 || true    # wda_start가 띄운 xcodebuild 등
        kill "$pid" > /dev/null 2>&1 || true
      done < "$(pids_file "$UDID")"
      rm -f "$(pids_file "$UDID")" "$(session_file "$UDID")"
    else
      echo "이 어댑터가 띄운 포트 포워드·WDA가 없습니다 ($UDID) — 아무것도 종료하지 않습니다" >&2
    fi
    ;;

  ui)
    UDID="${2:?usage: ios-real-device.sh ui <udid>}"
    wda GET "/source?format=json" 60 | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
v = d.get("value")
if not isinstance(v, dict) or "error" in v:
    sys.exit(1)
json.dump(v, sys.stdout, ensure_ascii=False)
print()
' || { echo "화면 요소 트리를 읽지 못했습니다 (WDA /source — $BASE)" >&2; exit 1; }
    ;;

  tap)
    [ $# -eq 4 ] || { echo "usage: ios-real-device.sh tap <udid> <x> <y>" >&2; exit 1; }
    session_post "$2" /wda/tap "{\"x\":$3,\"y\":$4}" || { echo "tap 실패" >&2; exit 1; }
    ;;

  swipe)
    [ $# -ge 6 ] || { echo "usage: ios-real-device.sh swipe <udid> <x1> <y1> <x2> <y2> [ms]" >&2; exit 1; }
    SECS="$(awk -v ms="${7:-300}" 'BEGIN { printf "%.3f", ms / 1000 }')"   # WDA는 초 단위
    session_post "$2" /wda/dragfromtoforduration "{\"fromX\":$3,\"fromY\":$4,\"toX\":$5,\"toY\":$6,\"duration\":$SECS}" \
      || { echo "swipe 실패" >&2; exit 1; }
    ;;

  key)
    [ $# -eq 3 ] || { echo "usage: ios-real-device.sh key <udid> home" >&2; exit 1; }
    case "$3" in
      home) wda POST /wda/homescreen 30 | no_error || { echo "home 실패" >&2; exit 1; } ;;
      back) echo "iOS에는 back 키가 없습니다 — 화면의 뒤로 버튼을 tap하세요" >&2; exit 1 ;;
      *) echo "지원하지 않는 키: $3 (home)" >&2; exit 1 ;;
    esac
    ;;

  screenshot)
    [ $# -eq 3 ] || { echo "usage: ios-real-device.sh screenshot <udid> <out.png>" >&2; exit 1; }
    wda GET /screenshot 60 | python3 -c '
import base64, json, sys
try:
    v = json.load(sys.stdin).get("value")
    data = base64.b64decode(v) if isinstance(v, str) else b""
except Exception:
    data = b""
if not data:
    sys.exit(1)
open(sys.argv[1], "wb").write(data)
' "$3" || { echo "스크린샷을 저장하지 못했습니다: $3 (WDA /screenshot — $BASE)" >&2; exit 1; }
    ;;

  *)
    echo "usage: ios-real-device.sh check | ensure [udid] | cleanup <udid> | ui <udid> | tap <udid> <x> <y> | swipe <udid> <x1> <y1> <x2> <y2> [ms] | key <udid> home | screenshot <udid> <out.png>" >&2
    exit 1
    ;;
esac
