#!/bin/bash
# 기기 어댑터 계약 검사 — 어댑터를 실제 기기로 한 바퀴 돌려 계약(impl-profile-spec.md "기기 어댑터")대로 동작하는지 본다.
# impl-setup이 프로필에 기기 어댑터를 적기 전에 돌린다 (공용 어댑터든 레포에 새로 만든 어댑터든). 사람이 직접 돌려도 된다.
#
# Usage:
#   device-adapter-check.sh [--out <dir>] [<어댑터 경로>]
#       어댑터 경로가 없으면 프로필 `화면 확인.device_adapter`의 첫 어댑터 (키가 없으면 builtin:android-device).
#       목록(우선순위)이면 어댑터마다 경로를 주고 따로 돌린다.
#       --out: ui 출력·스크린샷을 남길 폴더 (없으면 임시 폴더 — 경로를 출력한다)
#
# 하는 일 (순서대로 — 기기를 실제로 조작한다):
#   check → ensure(+ KIND 줄) → ui → screenshot → tap(1,1) → swipe(1,1→1,3) → 인자 부족 거부 → key home(선택) → cleanup
#   tap·swipe는 화면 구석의 무해한 좌표로 "명령이 전달되는지"만 본다 — 화면이 바뀌는지는 보지 않는다.
#   `ui` 출력에 텍스트와 좌표가 실제로 들어 있는지는 형식이 자유라 기계로 판정하지 않는다 — 남긴 파일을 호출자가 읽고 확인한다.
#
# 출력: 줄마다 `PASS|FAIL|SKIP {단계} — {설명}`, 마지막 줄 `RESULT ok|contract-fail|env-unavailable`
# 종료 코드: 0 계약 통과 / 1 계약 위반 (어댑터를 고쳐야 한다) / 2 환경 미충족 — 도구·기기가 없어 검사하지 못함 (어댑터 잘못이 아닐 수 있다) / 64 사용법 오류

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

OUT=""; ADAPTER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="${2:?--out <dir>}"; shift 2 ;;
    -*) echo "usage: device-adapter-check.sh [--out <dir>] [<어댑터 경로>]" >&2; exit 64 ;;
    *) ADAPTER="$1"; shift ;;
  esac
done
if [ -z "$ADAPTER" ]; then
  ADAPTER="$("$HERE/impl-profile.sh" adapters | head -1)"
  [ -n "$ADAPTER" ] || exit 64
fi
[ -x "$ADAPTER" ] || { echo "어댑터가 없거나 실행할 수 없음: $ADAPTER" >&2; exit 64; }
[ -n "$OUT" ] || OUT="$(mktemp -d "${TMPDIR:-/tmp}/device-adapter-check.XXXXXX")"
mkdir -p "$OUT"

FAILED=0
pass() { echo "PASS $1 — $2"; }
fail() { echo "FAIL $1 — $2"; FAILED=1; }
skip() { echo "SKIP $1 — $2"; }
first_line() { head -1 "$1" 2> /dev/null; }
finish() { # $1 = RESULT 값, $2 = 종료 코드
  echo "산출물: $OUT"
  echo "RESULT $1"
  exit "$2"
}

echo "어댑터: $ADAPTER"

# 1. check — 도구
"$ADAPTER" check > "$OUT/check.out" 2> "$OUT/check.err"; rc=$?
if [ "$rc" = 0 ]; then
  [ -s "$OUT/check.out" ] && pass check "도구 있음: $(first_line "$OUT/check.out")" || fail check "exit 0인데 stdout이 비어 있음 (도구 경로 한 줄을 내야 한다)"
elif [ "$rc" = 3 ]; then
  skip check "도구 없음: $(first_line "$OUT/check.err")"
  finish env-unavailable 2
else
  fail check "exit $rc (도구가 없으면 3이어야 한다): $(first_line "$OUT/check.err")"
  finish contract-fail 1
fi

# 2. ensure — 기기 확보
ID="$("$ADAPTER" ensure 2> "$OUT/device.err")"; rc=$?
BOOTED=0; grep -q "^BOOTED " "$OUT/device.err" 2> /dev/null && BOOTED=1
case "$rc" in
  0)
    if [ -n "$ID" ] && [ "$(printf '%s\n' "$ID" | wc -l | tr -d ' ')" = 1 ]; then
      pass ensure "기기 id: $ID$([ "$BOOTED" = 1 ] && echo " (이 검사가 띄움 — 끝나면 cleanup)")"
    else
      fail ensure "exit 0인데 stdout이 기기 id 한 줄이 아님: '$ID'"
      finish contract-fail 1
    fi
    if [ "$BOOTED" = 1 ] && ! grep -qx "BOOTED $ID" "$OUT/device.err"; then
      fail ensure "stderr의 BOOTED 줄이 'BOOTED $ID' 꼴이 아님: $(grep "^BOOTED " "$OUT/device.err" | head -1)"
    fi
    # KIND — 선택. 있으면 real|virtual 이어야 한다 (visual-verifier가 실기기용 설치·mock 키를 고를 때 쓴다)
    KIND="$(grep "^KIND " "$OUT/device.err" | head -1)"
    case "$KIND" in
      "KIND real"|"KIND virtual") pass kind "${KIND#KIND }" ;;
      "") skip kind "KIND 줄 없음 (선택 — 없으면 실기기 전용 키 빌드.install_real·화면 확인.mock_skill_real을 쓸 수 없다)" ;;
      *) fail kind "stderr의 KIND 줄은 'KIND real' 또는 'KIND virtual'이어야 함: $KIND" ;;
    esac ;;
  3|4|5)
    skip ensure "기기를 확보하지 못함 (exit $rc): $(first_line "$OUT/device.err")"
    [ -s "$OUT/device.err" ] || fail ensure "exit $rc인데 stderr에 사유가 없음"
    [ "$FAILED" = 1 ] && finish contract-fail 1
    finish env-unavailable 2 ;;
  *)
    fail ensure "exit $rc (실패는 3·4·5 중 하나여야 한다): $(first_line "$OUT/device.err")"
    finish contract-fail 1 ;;
esac

# 3. ui — 화면 요소 트리
if "$ADAPTER" ui "$ID" > "$OUT/ui.out" 2> "$OUT/ui.err"; then
  if [ -s "$OUT/ui.out" ] && grep -q '[0-9]' "$OUT/ui.out"; then
    pass ui "$(wc -c < "$OUT/ui.out" | tr -d ' ')바이트 → $OUT/ui.out (텍스트·좌표가 들어 있는지 읽어서 확인할 것)"
  else
    fail ui "exit 0인데 출력이 비었거나 좌표로 볼 숫자가 없음"
  fi
else
  fail ui "exit $? : $(first_line "$OUT/ui.err")"
fi

# 4. screenshot — PNG
SHOT="$OUT/screen.png"; rm -f "$SHOT"
if "$ADAPTER" screenshot "$ID" "$SHOT" > /dev/null 2> "$OUT/shot.err"; then
  if [ "$(head -c 4 "$SHOT" 2> /dev/null | od -An -tx1 | tr -d ' \n')" = "89504e47" ]; then
    pass screenshot "PNG $(wc -c < "$SHOT" | tr -d ' ')바이트 → $SHOT"
  else
    fail screenshot "exit 0인데 PNG 파일이 아님: $SHOT"
  fi
else
  fail screenshot "exit $? : $(first_line "$OUT/shot.err")"
fi

# 5. tap·swipe — 명령 전달 (화면 구석, 무해한 좌표)
if "$ADAPTER" tap "$ID" 1 1 > /dev/null 2> "$OUT/tap.err"; then pass tap "(1,1) 전달됨"; else fail tap "exit $? : $(first_line "$OUT/tap.err")"; fi
if "$ADAPTER" swipe "$ID" 1 1 1 3 > /dev/null 2> "$OUT/swipe.err"; then pass swipe "(1,1)→(1,3) 전달됨"; else fail swipe "exit $? : $(first_line "$OUT/swipe.err")"; fi

# 6. 잘못된 호출은 거부해야 한다 (조용히 성공하면 호출자가 실패를 모른다)
if "$ADAPTER" tap "$ID" > /dev/null 2>&1; then fail 인자검사 "좌표 없는 tap이 exit 0"; else pass 인자검사 "좌표 없는 tap 거부"; fi
if "$ADAPTER" __no_such_command__ > /dev/null 2>&1; then fail 인자검사 "모르는 명령이 exit 0"; else pass 인자검사 "모르는 명령 거부"; fi

# 7. key home — 선택
if "$ADAPTER" key "$ID" home > /dev/null 2> "$OUT/key.err"; then pass key "home 지원"; else skip key "home 미지원 (선택 기능): $(first_line "$OUT/key.err")"; fi

# 8. cleanup — 띄운 것만 정리 (띄운 게 없어도 exit 0이어야 한다)
if "$ADAPTER" cleanup "$ID" > /dev/null 2> "$OUT/cleanup.err"; then
  pass cleanup "$([ "$BOOTED" = 1 ] && echo "이 검사가 띄운 기기 정리" || echo "원래 있던 기기 — 정리할 것 없음")"
else
  fail cleanup "exit $? : $(first_line "$OUT/cleanup.err")"
fi

[ "$FAILED" = 0 ] && finish ok 0
finish contract-fail 1
