#!/usr/bin/env python3
"""사용자가 일을 시킨 뒤 새로 생긴 화면 확인 리포트(report.html)만, 턴이 끝날 때 브라우저로 연다.

Usage (플러그인 훅이 부른다 — hooks/hooks.json):
  open-reports.py mark   UserPromptSubmit 훅: 지금을 이 세션의 기준 시각으로 적는다
  open-reports.py open   Stop 훅: 기준 시각 이후에 쓰인 {레포}/.impl-spec/**/report.html을 연다

- 훅 입력(stdin JSON)의 session_id·cwd를 쓴다. 레포 루트는 cwd에서 git으로 찾고, 실패하면 cwd.
- 한 번 연 리포트(경로+수정 시각)는 다시 열지 않는다 — 백그라운드 알림으로 턴이 여러 번 끝나도 한 번만.
  리포트를 다시 만들면(수정 시각이 바뀌면) 다시 연다.
- 기준 시각이 없으면(플러그인을 세션 중간에 켬) 아무것도 안 연다 — 예전 리포트가 쏟아지지 않게.
- 연 리포트는 systemMessage로 알린다.

환경 변수:
  IMPL_CHAIN_OPEN_REPORTS=0   끈다
  IMPL_CHAIN_OPEN_CMD         여는 명령 (기본: macOS `open`, 그 밖 `xdg-open`) — 테스트용
  IMPL_CHAIN_STATE_DIR        기준 시각·연 목록을 두는 곳 (기본: $TMPDIR/impl-chain-reports)

훅이 세션을 막으면 안 되므로 어떤 경우에도 종료 코드 0.
"""
import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import time


def state_paths(session_id):
    d = os.environ.get("IMPL_CHAIN_STATE_DIR") or os.path.join(tempfile.gettempdir(), "impl-chain-reports")
    os.makedirs(d, exist_ok=True)
    safe = "".join(c for c in session_id if c.isalnum() or c in "-_") or "default"
    return os.path.join(d, safe + ".since"), os.path.join(d, safe + ".opened")


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
    cmd = os.environ.get("IMPL_CHAIN_OPEN_CMD")
    if cmd:
        return shlex.split(cmd)
    name = "open" if sys.platform == "darwin" else "xdg-open"
    return [name] if shutil.which(name) else None


def new_reports(root, since, opened):
    base = os.path.join(root, ".impl-spec")
    found = []
    for d, _, files in os.walk(base):
        if "report.html" not in files:
            continue
        p = os.path.join(d, "report.html")
        m = os.path.getmtime(p)
        key = f"{p}\t{m}"
        if m >= since and key not in opened:
            found.append((m, p, key))
    return sorted(found)


def main():
    if os.environ.get("IMPL_CHAIN_OPEN_REPORTS") == "0" or len(sys.argv) != 2:
        return
    try:
        hook = json.load(sys.stdin)
    except Exception:
        hook = {}
    since_f, opened_f = state_paths(str(hook.get("session_id") or ""))

    if sys.argv[1] == "mark":
        with open(since_f, "w") as f:
            f.write(str(time.time()))
        return
    if sys.argv[1] != "open" or not os.path.exists(since_f):
        return

    with open(since_f) as f:
        since = float(f.read().strip() or 0)
    opened = set()
    if os.path.exists(opened_f):
        with open(opened_f) as f:
            opened = set(f.read().splitlines())

    root = repo_root(hook.get("cwd") or os.getcwd())
    reports = new_reports(root, since, opened)
    cmd = opener()
    if not reports or not cmd:
        return

    shown = []
    for _, p, key in reports:
        try:
            # 기다린다 — 훅이 끝나면 남은 자식 프로세스가 죽을 수 있다. open/xdg-open은 바로 돌아온다.
            subprocess.run(cmd + [p], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
        except Exception:
            continue
        shown.append(os.path.relpath(p, root))
        with open(opened_f, "a") as f:
            f.write(key + "\n")
    if shown:
        print(json.dumps({"systemMessage": "화면 확인 리포트를 열었습니다: " + ", ".join(shown)}, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
