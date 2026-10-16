#!/usr/bin/env python3
"""analyze에서 확정된 UI 결정(decisions[].apply)을 작업 브랜치에 반영한다.

규격: impl-chain references/impl-state-file.md "apply 형식". start-work Step 2-1이 브랜치 생성 직후 실행한다.

Usage: apply-ui-decisions.py spec <number>

- map_row add          : 대응표(프로필 `UI 컴포넌트.map`)에 행 추가.
                         같은 data-name 행이 같은 component면 SKIP, 다르면 CONFLICT
- map_row append_issue : 그 data-name 행의 비고에 `사용 이슈: …`로 이슈를 덧붙임. 이미 있으면 SKIP, 행이 없으면 CONFLICT
- map_row replace      : 그 행의 프로젝트 칸이 expect면 프로젝트·비고·근거 칸을 교체(첫 칸 유지, note 없으면 비고 유지).
                         이미 component면 SKIP, 행이 없거나 그 외 값이면 CONFLICT
- token_row add        : 토큰 대응표(프로필 `디자인 토큰.map`)에 행 추가. 이름 비교는 대소문자 무시.
                         같은 figma_name 행이 같은 token이면 SKIP, 다르면 CONFLICT
- token_row replace    : 그 행의 토큰 칸이 expect면 토큰·값·근거 칸을 교체(첫 칸 유지). 이미 token이면 SKIP, 그 외 CONFLICT
- asset                : source → target 복사. 같은 내용이면 SKIP, 다른 파일이 있으면 CONFLICT

출력: 항목마다 ADDED / UPDATED / REPLACED / COPIED / SKIP / CONFLICT 한 줄, 바뀐 파일마다 `CHANGED <path>` (호출자가 git add -N)
종료: 0 성공 / 1 사용법·형식 오류 / 2 상태 파일 없음 / 3 CONFLICT 있음 (나머지 항목은 반영됨 — 다시 실행해도 안전)
"""
import filecmp
import fnmatch
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
MAP_HEADER = "| Figma 컴포넌트"
TOKEN_HEADER = "| Figma 변수"


def die(msg, code=1):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(code)


def repo_path(p):
    q = Path(p)
    return q if q.is_absolute() else ROOT / q


def rel(p):
    try:
        return str(p.relative_to(ROOT))
    except ValueError:
        return str(p)


def cells(line):
    return [c.strip() for c in line.strip().strip("|").split("|")]


def row_matches(line, data_name):
    """첫 칸의 `이름`들 중 하나가 data-name과 같거나, `*` 패턴이 일치하면 그 행이다."""
    names = re.findall(r"`([^`]+)`", cells(line)[0])
    return any(n == data_name or ("*" in n and fnmatch.fnmatchcase(data_name, n)) for n in names)


def bare(s):
    return str(s or "").strip().strip("`").strip()


def token_row_matches(line, name):
    """첫 칸의 `이름`들 중 하나가 figma_name과 대소문자 무시로 같으면 그 행이다."""
    names = re.findall(r"`([^`]+)`", cells(line)[0])
    return any(n.lower() == name.lower() for n in names)


def token_cell(token):
    return token if token.startswith("없음") else f"`{token}`"


HERE = Path(__file__).resolve().parent   # impl-profile.sh는 이 스크립트와 같은 폴더 (레포 안이든 플러그인이든)


def profile_file(key, kind):
    r = subprocess.run([str(HERE / "impl-profile.sh"), "get", key], capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():
        die(f"프로필 `{key}`이 없음 — {kind}를 반영할 대응표가 없다")
    return repo_path(r.stdout.strip())


def table_rows(lines, header):
    """대응표 행 범위 [start, end). 헤더·구분선 다음부터 '|'로 시작하는 줄이 끝날 때까지."""
    # 헤더 칸 앞뒤 공백은 무시한다 (`|  Figma 컴포넌트 …`도 같은 표)
    want = cells(header)[0]
    head = next((i for i, l in enumerate(lines) if l.lstrip().startswith("|") and cells(l)[0].startswith(want)), None)
    if head is None:
        die(f"대응표 형식 오류: '{header} …' 헤더가 없음")
    end = head + 2
    while end < len(lines) and lines[end].startswith("|"):
        end += 1
    return head + 2, end


def validate(entries):
    """아무것도 쓰기 전에 모든 항목을 검증한다. 실패하면 die(exit 1) — 파일은 하나도 바뀌지 않는다."""
    for a in entries:
        kind = a.get("kind")
        if kind == "map_row":
            op, dn = a.get("op"), a.get("data_name")
            if op not in ("add", "append_issue", "replace"):
                die(f"map_row op 오류: {op} ({dn})")
            need = {"add": ["data_name", "component", "evidence"],
                    "replace": ["data_name", "component", "evidence", "expect"],
                    "append_issue": ["data_name", "issue"]}[op]
            missing = [k for k in need if not a.get(k)]
            if missing:
                die(f"map_row {op}에 필수 값 없음 {missing}: {dn}")
            if not isinstance(dn, str):
                die(f"map_row data_name은 문자열이어야 함: {dn!r}")
            if any("|" in str(a.get(k) or "") for k in ("data_name", "component", "note", "evidence", "expect")) or "`" in dn:
                die(f"map_row 값에 '|' 또는 data_name에 '`' 사용 불가: {dn}")
        elif kind == "token_row":
            op, fn = a.get("op"), a.get("figma_name")
            if op not in ("add", "replace"):
                die(f"token_row op 오류: {op} ({fn})")
            need = ["figma_name", "token", "value", "evidence"] + (["expect"] if op == "replace" else [])
            missing = [k for k in need if not a.get(k)]
            if missing:
                die(f"token_row {op}에 필수 값 없음 {missing}: {fn}")
            if not isinstance(fn, str):
                die(f"token_row figma_name은 문자열이어야 함: {fn!r}")
            if any("|" in str(a.get(k) or "") for k in ("figma_name", "token", "value", "evidence", "expect")) or "`" in fn:
                die(f"token_row 값에 '|' 또는 figma_name에 '`' 사용 불가: {fn}")
        elif kind == "asset":
            if not a.get("figma_name") or not a.get("source") or not a.get("target"):
                die(f"asset에 figma_name/source/target 없음: {a.get('figma_name') or a.get('target')}")
            t = Path(str(a["target"]))
            if t.is_absolute() or ".." in t.parts:
                die(f"asset target은 레포 상대 경로여야 함: {a['target']}")
            if not repo_path(a["source"]).is_file():
                die(f"asset source 없음: {a['source']}")
        else:
            die(f"apply kind 오류: {kind}")


def apply_map_rows(entries):
    map_file = profile_file("UI 컴포넌트.map", "map_row")
    lines = map_file.read_text().split("\n")
    conflicts, dirty = 0, False
    for a in entries:
        dn, op = a["data_name"], a.get("op")
        start, end = table_rows(lines, MAP_HEADER)
        hit = next((i for i in range(start, end) if row_matches(lines[i], dn)), None)
        if op == "add":
            if hit is None:
                lines.insert(end, f"| `{dn}` | {a['component']} | {a.get('note') or ''} | {a['evidence']} |")
                print(f"ADDED map_row {dn}")
                dirty = True
            elif cells(lines[hit])[1] == a["component"]:
                print(f"SKIP map_row {dn} (같은 행 있음)")
            else:
                print(f"CONFLICT map_row {dn}: 대응표는 '{cells(lines[hit])[1]}', 결정은 '{a['component']}'")
                conflicts += 1
        elif op == "replace":
            if hit is None:
                print(f"CONFLICT map_row {dn}: replace인데 대응표에 행이 없음")
                conflicts += 1
                continue
            c = cells(lines[hit])
            if c[1] == a["component"]:
                print(f"SKIP map_row {dn} (이미 {a['component']})")
            elif c[1] == a["expect"]:
                note = a.get("note") or c[2]
                lines[hit] = f"| {c[0]} | {a['component']} | {note} | {a['evidence']} |"
                print(f"REPLACED map_row {dn}")
                dirty = True
            else:
                print(f"CONFLICT map_row {dn}: 대응표가 그사이 바뀜: 현재 '{c[1]}', 기대 '{a['expect']}'")
                conflicts += 1
        elif op == "append_issue":
            if hit is None:
                print(f"CONFLICT map_row {dn}: append_issue인데 대응표에 행이 없음")
                conflicts += 1
                continue
            c, issue = cells(lines[hit]), a["issue"]
            after = c[2].split("사용 이슈:", 1)[1] if "사용 이슈:" in c[2] else ""
            if re.search(rf"(?<![\w-]){re.escape(issue)}(?![\w-])", after):
                print(f"SKIP map_row {dn} (이슈 {issue} 이미 있음)")
                continue
            if "사용 이슈:" in c[2]:
                c[2] = f"{c[2]}, {issue}"
            elif c[2] in ("", "—", "-"):
                c[2] = f"사용 이슈: {issue}"
            else:
                c[2] = f"{c[2]}; 사용 이슈: {issue}"
            lines[hit] = "| " + " | ".join(c) + " |"
            print(f"UPDATED map_row {dn} (사용 이슈 +{issue})")
            dirty = True
        else:
            die(f"map_row op 오류: {op} ({dn})")
    if dirty:
        map_file.write_text("\n".join(lines))
    return conflicts, ([map_file] if dirty else [])


def apply_token_rows(entries):
    token_file = profile_file("디자인 토큰.map", "token_row")
    lines = token_file.read_text().split("\n")
    conflicts, dirty = 0, False
    for a in entries:
        fn, op = a["figma_name"], a["op"]
        start, end = table_rows(lines, TOKEN_HEADER)
        hit = next((i for i in range(start, end) if token_row_matches(lines[i], fn)), None)
        cur = bare(cells(lines[hit])[1]) if hit is not None else None
        if op == "add":
            if hit is None:
                lines.insert(end, f"| `{fn}` | {token_cell(a['token'])} | {a['value']} | {a['evidence']} |")
                print(f"ADDED token_row {fn}")
                dirty = True
            elif cur == bare(a["token"]):
                print(f"SKIP token_row {fn} (같은 행 있음)")
            else:
                print(f"CONFLICT token_row {fn}: 대응표는 '{cur}', 결정은 '{a['token']}'")
                conflicts += 1
        else:  # replace
            if hit is None:
                print(f"CONFLICT token_row {fn}: replace인데 대응표에 행이 없음")
                conflicts += 1
            elif cur == bare(a["token"]):
                print(f"SKIP token_row {fn} (이미 {a['token']})")
            elif cur == bare(a["expect"]):
                lines[hit] = f"| {cells(lines[hit])[0]} | {token_cell(a['token'])} | {a['value']} | {a['evidence']} |"
                print(f"REPLACED token_row {fn}")
                dirty = True
            else:
                print(f"CONFLICT token_row {fn}: 대응표가 그사이 바뀜: 현재 '{cur}', 기대 '{a['expect']}'")
                conflicts += 1
    if dirty:
        token_file.write_text("\n".join(lines))
    return conflicts, ([token_file] if dirty else [])


def apply_assets(entries):
    conflicts, changed = 0, []
    for a in entries:
        src, dst = repo_path(a["source"]), repo_path(a["target"])
        if not src.is_file():
            die(f"asset source 없음: {a['source']}")
        if dst.exists():
            if filecmp.cmp(src, dst, shallow=False):
                print(f"SKIP asset {a['target']} (같은 파일 있음)")
            else:
                print(f"CONFLICT asset {a['target']}: 다른 내용의 파일이 이미 있음")
                conflicts += 1
            continue
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst)
        print(f"COPIED asset {a['target']}")
        changed.append(dst)
    return conflicts, changed


def main(argv):
    if len(argv) != 2 or argv[0] != "spec" or not argv[1].isdigit():
        die("usage: apply-ui-decisions.py spec <number>")
    state = ROOT / ".impl-spec" / f"{argv[0]}-{argv[1]}.json"
    if not state.is_file():
        die(f"상태 파일 없음: {rel(state)}", 2)
    data = json.loads(state.read_text())
    entries = [a for d in data.get("decisions", []) for a in (d.get("apply") or [])]
    if not entries:
        print("apply 없음")
        return 0
    validate(entries)
    conflicts, changed = 0, []
    rows = [a for a in entries if a["kind"] == "map_row"]
    if rows:
        c, ch = apply_map_rows(rows)
        conflicts, changed = conflicts + c, changed + ch
    toks = [a for a in entries if a["kind"] == "token_row"]
    if toks:
        c, ch = apply_token_rows(toks)
        conflicts, changed = conflicts + c, changed + ch
    c, ch = apply_assets([a for a in entries if a["kind"] == "asset"])
    conflicts, changed = conflicts + c, changed + ch
    for p in changed:
        print(f"CHANGED {rel(p)}")
    return 3 if conflicts else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
