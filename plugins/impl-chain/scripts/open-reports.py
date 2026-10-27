#!/usr/bin/env python3
"""화면 확인 리포트(report.html)를 브라우저로 연다 — 리포트 여는 일은 전부 이 스크립트 하나로 한다.

Usage:
  open-reports.py now <report.html>...   start-work Step 8: 기록한 리포트를 지금 연다
  open-reports.py mark                   UserPromptSubmit 훅: 지금을 이 세션의 기준 시각으로 적는다
  open-reports.py open                   Stop 훅: 기준 시각 이후에 쓰였고 아직 안 연 {레포}/.impl-spec/**/report.html을 연다
                                         (체인 밖에서 생긴 리포트 — visual-verifier만 다시 돌린 경우 등)

연 목록은 셋이 함께 쓴다 — 리포트(경로+수정 시각)마다 한 번만 연다. start-work가 바로 연 리포트를 턴 끝 훅이 다시 열지 않고,
백그라운드 알림으로 턴이 여러 번 끝나도 한 번만. 리포트를 다시 만들면(수정 시각이 바뀌면) 다시 연다.

now:
  stdout: 리포트마다 `OPENED {경로}` 또는 `PATH {경로}` (열지 못함·이미 연 것 아님 — 사용자에게 경로를 보여줄 것)
          이미 연 리포트도 `now`는 다시 연다 (명시적으로 부른 것이므로)
  종료 코드: 0 성공(열지 못한 경우 포함) / 1 사용법 오류·리포트 파일 없음
mark·open (훅): 입력(stdin JSON)의 session_id·cwd를 쓴다. 레포 루트는 cwd에서 git으로 찾고, 실패하면 cwd.
  기준 시각이 없으면(플러그인을 세션 중간에 켬) 아무것도 안 연다 — 예전 리포트가 쏟아지지 않게.
  연 리포트는 systemMessage로 알린다. 훅이 세션을 막으면 안 되므로 어떤 경우에도 종료 코드 0.

열 수단: macOS `open`, Linux `xdg-open`(DISPLAY·WAYLAND_DISPLAY가 있을 때). 없으면 열지 않는다.
환경 변수:
  IMPL_CHAIN_OPEN_REPORTS=0   열지 않는다 (now는 PATH만 출력, 훅은 아무것도 안 함)
  IMPL_CHAIN_OPEN_CMD         여는 명령 (기본: 위 열 수단) — 테스트용
  IMPL_CHAIN_STATE_DIR        기준 시각·연 목록을 두는 곳 (기본: $TMPDIR/impl-chain-reports)
"""
import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import time


def state_dir():
    d = os.environ.get("IMPL_CHAIN_STATE_DIR") or os.path.join(tempfile.gettempdir(), "impl-chain-reports")
    os.makedirs(d, exist_ok=True)
    return d


def since_path(session_id):
    safe = "".join(c for c in session_id if c.isalnum() or c in "-_") or "default"
    return os.path.join(state_dir(), safe + ".since")


def opened_path():
    return os.path.join(state_dir(), "opened")


def read_opened():
    p = opened_path()
    if not os.path.exists(p):
        return set()
    with open(p) as f:
        return set(f.read().splitlines())


def key_of(p):
    return f"{os.path.realpath(p)}\t{os.path.getmtime(p)}"


def remember(p):
    with open(opened_path(), "a") as f:
        f.write(key_of(p) + "\n")


def repo_root(cwd):
    try:
        out = subprocess.run(["git", "-C", cwd, "rev-parse", "--show-toplevel"],
                             capture_output=True, text=True, timeout=5)
        if out.returncode == 0 and out.stdout.strip():
            return out.stdout.strip()
    except Exception:
        pass
    return cwd


def opener():
    if os.environ.get("IMPL_CHAIN_OPEN_REPORTS") == "0":
        return None
    cmd = os.environ.get("IMPL_CHAIN_OPEN_CMD")
    if cmd:
        return shlex.split(cmd)
    if sys.platform == "darwin":
        return ["open"] if shutil.which("open") else None
    if shutil.which("xdg-open") and (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
        return ["xdg-open"]
    return None


def launch(cmd, p):
    # 기다린다 — 훅이 끝나면 남은 자식 프로세스가 죽을 수 있다. open/xdg-open은 바로 돌아온다.
    r = subprocess.run(cmd + [p], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
    return r.returncode == 0


def cmd_now(paths):
    if not paths:
        print("usage: open-reports.py now <report.html>...", file=sys.stderr)
        return 1
    rc = 0
    cmd = opener()
    for p in paths:
        if not os.path.isfile(p):
            print(f"ERROR: 리포트 없음: {p}", file=sys.stderr)
            rc = 1
            continue
        ok = False
        if cmd:
            try:
                ok = launch(cmd, p)
            except Exception:
                ok = False
        if ok:
            remember(p)
            print(f"OPENED {p}")
        else:
            print(f"PATH {p}")
    return rc


def new_reports(root, since, opened):
    found = []
    for d, _, files in os.walk(os.path.join(root, ".impl-spec")):
        if "report.html" not in files:
            continue
        p = os.path.join(d, "report.html")
        m = os.path.getmtime(p)
        if m >= since and key_of(p) not in opened:
            found.append((m, p))
    return sorted(found)


def cmd_hook(mode):
    if os.environ.get("IMPL_CHAIN_OPEN_REPORTS") == "0":
        return
    try:
        hook = json.load(sys.stdin)
    except Exception:
        hook = {}
    since_f = since_path(str(hook.get("session_id") or ""))

    if mode == "mark":
        with open(since_f, "w") as f:
            f.write(str(time.time()))
        return
    if not os.path.exists(since_f):
        return
    with open(since_f) as f:
        since = float(f.read().strip() or 0)

    root = repo_root(hook.get("cwd") or os.getcwd())
    reports = new_reports(root, since, read_opened())
    cmd = opener()
    if not reports or not cmd:
        return
    shown = []
    for _, p in reports:
        try:
            if not launch(cmd, p):
                continue
        except Exception:
            continue
        remember(p)
        shown.append(os.path.relpath(p, root))
    if shown:
        print(json.dumps({"systemMessage": "화면 확인 리포트를 열었습니다: " + ", ".join(shown)}, ensure_ascii=False))


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "now":
        sys.exit(cmd_now(sys.argv[2:]))
    if mode in ("mark", "open") and len(sys.argv) == 2:
        try:
            cmd_hook(mode)
        except Exception:
            pass
    sys.exit(0)
