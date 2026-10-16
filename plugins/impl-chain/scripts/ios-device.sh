#!/bin/bash
# 기기 어댑터 (iOS 시뮬레이터) — visual-verifier가 쓰는 기기 확보·조작·정리. 프로필 `화면 확인.device_adapter: builtin:ios-device`.
# 계약: impl-chain references/impl-profile-spec.md "기기 어댑터".
#
# 도구: Xcode(`xcrun simctl` — 부팅·스크린샷) + AXe(`axe` — 화면 요소 읽기·터치. simctl에는 이 기능이 없다)
#       AXe 설치: brew install cameroncooke/axe/axe
# 시뮬레이터 전용이다 — 실기기는 다루지 않는다.
#
# Usage:
#   ios-device.sh check                → 도구(simctl·axe)를 쓸 수 있으면 axe 경로 출력
#       axe 찾는 순서: PATH → /opt/homebrew/bin → /usr/local/bin
#   ios-device.sh ensure [name|udid]   → 쓸 시뮬레이터 UDID 출력 (부팅돼 있는 것 중 첫 번째)
#       없으면 부팅한다(창 없이): 인자 → 프로필 `화면 확인.simulator` → 최신 iOS 런타임의 첫 iPhone.
#       부팅했으면 stderr에 `BOOTED {udid}` — 호출자는 끝날 때 cleanup으로 정리한다. stderr에 `KIND virtual` 한 줄 (항상 시뮬레이터).
#       부팅 대기 시간: $IOS_DEVICE_BOOT_TIMEOUT초 (기본 180)
#   ios-device.sh cleanup <udid>       → ensure가 부팅한 시뮬레이터 종료 (원래 켜져 있던 것은 건드리지 않는다)
#   ios-device.sh ui <udid>                              → 화면 요소 트리(AXe JSON — 라벨·frame) 출력. 좌표 단위는 포인트
#   ios-device.sh tap <udid> <x> <y>                     → 탭 (포인트 — `ui`의 frame과 같은 좌표계. 스크린샷 픽셀이 아니다)
#   ios-device.sh swipe <udid> <x1> <y1> <x2> <y2> [ms]  → 스와이프·스크롤 (기본 300ms)
#   ios-device.sh key <udid> home                        → 홈 버튼. back은 iOS에 없다 (exit 1 — 화면의 뒤로 버튼을 tap한다)
#   ios-device.sh screenshot <udid> <out.png>            → 스크린샷 저장
#
# 종료 코드: 0 성공 / 3 도구 없음 / 4 쓸 시뮬레이터 없음 / 5 부팅 시간 초과 / 1 사용법 오류·조작 실패

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

find_axe() {
  if command -v axe > /dev/null 2>&1; then command -v axe; return 0; fi
  local d
  for d in /opt/homebrew/bin /usr/local/bin; do
    [ -x "$d/axe" ] && { echo "$d/axe"; return 0; }
  done
  return 1
}

command -v xcrun > /dev/null 2>&1 && xcrun simctl help > /dev/null 2>&1 \
  || { echo "xcrun simctl을 쓸 수 없습니다 — Xcode를 설치하고 xcode-select로 선택해주세요" >&2; exit 3; }
AXE="$(find_axe)" \
  || { echo "axe를 찾지 못했습니다 — 화면 요소 읽기·터치에 필요합니다: brew install cameroncooke/axe/axe" >&2; exit 3; }

# ensure가 부팅한 시뮬레이터 표시 — cleanup은 이 표시가 있는 것만 종료한다
MARK_DIR="${TMPDIR:-/tmp}/impl-chain-ios-device"
mark() { echo "$MARK_DIR/$1.booted"; }

# simctl 기기 목록(JSON)에서 고른다. $1 = booted | pick, $2 = 이름 또는 UDID (pick일 때, 비면 기본 선택)
# stdout = UDID (없으면 빈 출력)
select_device() {
  xcrun simctl list devices available -j 2> /dev/null | python3 -c '
import json, re, sys
mode, want = sys.argv[1], sys.argv[2]
try:
    data = json.load(sys.stdin).get("devices", {})
except Exception:
    sys.exit(0)
rows = []
for runtime, devs in data.items():
    m = re.search(r"SimRuntime\.iOS-(\d+)(?:-(\d+))?", runtime)
    if not m:
        continue
    ver = (int(m.group(1)), int(m.group(2) or 0))
    for i, d in enumerate(devs):
        if d.get("isAvailable", True):
            rows.append((ver, i, d))
if mode == "booted":
    hit = [r for r in rows if r[2].get("state") == "Booted"]
elif want:
    hit = [r for r in rows if want in (r[2].get("name"), r[2].get("udid"))]
else:
    hit = [r for r in rows if r[2].get("name", "").startswith("iPhone")]
# 런타임이 높은 것 먼저, 같은 런타임 안에서는 목록 순서
hit.sort(key=lambda r: (-r[0][0], -r[0][1], r[1]))
if hit:
    print(hit[0][2]["udid"])
' "$1" "${2:-}"
}

case "${1:-}" in
  check)
    echo "$AXE"
    ;;

  ensure)
    UDID="$(select_device booted)"
    if [ -n "$UDID" ]; then echo "KIND virtual" >&2; echo "$UDID"; exit 0; fi

    WANT="${2:-}"
    if [ -z "$WANT" ]; then
      WANT="$("$HERE/impl-profile.sh" get "화면 확인.simulator" 2>/dev/null || true)"
    fi
    UDID="$(select_device pick "$WANT")"
    if [ -z "$UDID" ]; then
      if [ -n "$WANT" ]; then echo "시뮬레이터 $WANT 가 없습니다 (xcrun simctl list devices available)" >&2
      else echo "부팅된 시뮬레이터도, 부팅할 iPhone 시뮬레이터도 없습니다" >&2; fi
      exit 4
    fi

    # bootstatus -b = 꺼져 있으면 부팅하고 부팅이 끝날 때까지 기다린다 (Simulator 앱 창은 띄우지 않는다)
    TIMEOUT="${IOS_DEVICE_BOOT_TIMEOUT:-180}"
    xcrun simctl bootstatus "$UDID" -b > /dev/null 2>&1 &
    BOOT_PID=$!
    for _ in $(seq 1 "$TIMEOUT"); do
      kill -0 "$BOOT_PID" 2> /dev/null || break
      sleep 1
    done
    if kill -0 "$BOOT_PID" 2> /dev/null; then
      kill "$BOOT_PID" 2> /dev/null
      xcrun simctl shutdown "$UDID" > /dev/null 2>&1 || true
      echo "시뮬레이터 $UDID 부팅 시간 초과 (${TIMEOUT}초)" >&2
      exit 5
    fi
    wait "$BOOT_PID" || { echo "시뮬레이터 $UDID 를 부팅하지 못했습니다" >&2; exit 4; }
    mkdir -p "$MARK_DIR" && : > "$(mark "$UDID")"
    echo "BOOTED $UDID" >&2
    echo "KIND virtual" >&2
    echo "$UDID"
    ;;

  cleanup)
    UDID="${2:?usage: ios-device.sh cleanup <udid>}"
    if [ -f "$(mark "$UDID")" ]; then
      xcrun simctl shutdown "$UDID" > /dev/null 2>&1 || true
      rm -f "$(mark "$UDID")"
    else
      echo "이 어댑터가 부팅하지 않은 시뮬레이터($UDID)는 종료하지 않습니다" >&2
    fi
    ;;

  ui)
    UDID="${2:?usage: ios-device.sh ui <udid>}"
    "$AXE" describe-ui --udid "$UDID" \
      || { echo "화면 요소 트리를 읽지 못했습니다 (axe describe-ui 실패)" >&2; exit 1; }
    ;;

  tap)
    [ $# -eq 4 ] || { echo "usage: ios-device.sh tap <udid> <x> <y>" >&2; exit 1; }
    "$AXE" tap -x "$3" -y "$4" --udid "$2" > /dev/null || { echo "tap 실패" >&2; exit 1; }
    ;;

  swipe)
    [ $# -ge 6 ] || { echo "usage: ios-device.sh swipe <udid> <x1> <y1> <x2> <y2> [ms]" >&2; exit 1; }
    SECS="$(awk -v ms="${7:-300}" 'BEGIN { printf "%.3f", ms / 1000 }')"   # axe는 초 단위
    "$AXE" swipe --start-x "$3" --start-y "$4" --end-x "$5" --end-y "$6" --duration "$SECS" --udid "$2" > /dev/null \
      || { echo "swipe 실패" >&2; exit 1; }
    ;;

  key)
    [ $# -eq 3 ] || { echo "usage: ios-device.sh key <udid> home" >&2; exit 1; }
    case "$3" in
      home) "$AXE" button home --udid "$2" > /dev/null || { echo "home 버튼 실패" >&2; exit 1; } ;;
      back) echo "iOS에는 back 키가 없습니다 — 화면의 뒤로 버튼을 tap하세요" >&2; exit 1 ;;
      *) echo "지원하지 않는 키: $3 (home)" >&2; exit 1 ;;
    esac
    ;;

  screenshot)
    [ $# -eq 3 ] || { echo "usage: ios-device.sh screenshot <udid> <out.png>" >&2; exit 1; }
    xcrun simctl io "$2" screenshot "$3" > /dev/null 2>&1 && [ -s "$3" ] \
      || { echo "스크린샷을 저장하지 못했습니다: $3" >&2; exit 1; }
    ;;

  *)
    echo "usage: ios-device.sh check | ensure [name|udid] | cleanup <udid> | ui <udid> | tap <udid> <x> <y> | swipe <udid> <x1> <y1> <x2> <y2> [ms] | key <udid> home | screenshot <udid> <out.png>" >&2
    exit 1
    ;;
esac
