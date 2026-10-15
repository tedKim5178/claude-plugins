#!/usr/bin/env python3
"""화면 확인 결과를 사람이 보는 비교 리포트(report.html)로 만든다.

Usage:
  visual-report.py [--fragment] <state_file> <output_dir> [--results <results.json>]

입력:
- state_file의 `visual_cases` — analyze 단계에서 승인된 확인 계획
  [{id, todo_id, scenario, condition, kind: target|regression, expect}]
- results.json (기본: {output_dir}/results.json) — visual-verifier가 쓴 실제 결과
  {device, build, commit, entry, mock_files: [], not_verified: [], observations: [],
   results: [{case_id, verdict: PASS|FAIL|MANUAL, evidence, screenshot, layout?, layout_na?}],
   extra_cases: [{id, todo_id, scenario, condition, kind, expect, verdict, evidence, screenshot, layout?, layout_na?}]}
  screenshot은 output_dir 안의 파일 이름이다.
  layout = [{element, expect, actual, ok: bool}] — ui-spec 배치를 기기에서 잰 결과. layout_na = 재지 않은 사유.

동작:
- 같은 scenario끼리 한 줄로 묶고 condition별로 나란히 놓는다 (target 먼저).
- 계획에 있는데 결과가 없는 케이스는 NOT_RUN("확인 안 함")으로 싣는다 — 조용히 빠지지 않는다.
- PASS·FAIL은 스크린샷 파일이 있어야 한다. 증거 없는 판정은 거부한다.
- layout에 ok:false가 있으면 PASS를 거부한다. 상태 파일에 ui_specs가 있으면 target 케이스의 PASS는
  layout(비어 있지 않음) 또는 layout_na가 있어야 한다 — 요소 유무만 보고 PASS하지 않는다.
- {output_dir}/report.html을 쓰고 stdout에 `REPORT {경로} — PASS a / FAIL b / MANUAL c / NOT_RUN d`.
  --fragment면 doctype/html/head/body 껍데기 없이 쓴다 (Artifact 게시용).

종료 코드: 0 성공 / 1 입력 오류 (아무것도 쓰지 않는다)
"""
import html
import json
import os
import sys

VERDICTS = ("PASS", "FAIL", "MANUAL")
LABEL = {"PASS": "통과", "FAIL": "실패", "MANUAL": "수동 확인 필요", "NOT_RUN": "확인 안 함"}
KIND = {"target": "대상", "regression": "회귀"}


def fail(msg):
    print(msg, file=sys.stderr)
    sys.exit(1)


def esc(v):
    return html.escape("" if v is None else str(v), quote=True)


def load(path, what):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        fail(f"{what} 없음: {path}")
    except json.JSONDecodeError as e:
        fail(f"{what} JSON 오류: {path}: {e}")


def check_shot(out_dir, case_id, verdict, shot):
    if not shot:
        if verdict in ("PASS", "FAIL"):
            fail(f"{case_id}: {verdict}인데 screenshot 없음 — 증거 없는 판정은 싣지 않는다")
        return
    if os.path.isabs(shot) or ".." in shot.replace("\\", "/").split("/"):
        fail(f"{case_id}: screenshot은 출력 디렉토리 안의 파일 이름이어야 함: {shot}")
    if not os.path.isfile(os.path.join(out_dir, shot)):
        fail(f"{case_id}: screenshot 파일 없음: {shot}")


def check_layout(case_id, verdict, kind, r, need):
    lay = r.get("layout")
    if lay is not None:
        if not isinstance(lay, list):
            fail(f"{case_id}: layout은 배열이어야 함")
        for it in lay:
            if not isinstance(it, dict) or not it.get("element") or not it.get("expect") \
                    or not isinstance(it.get("ok"), bool):
                fail(f"{case_id}: layout 항목은 element·expect·ok(bool)가 있어야 함: {it}")
        bad = [it["element"] for it in lay if not it["ok"]]
        if bad and verdict == "PASS":
            fail(f"{case_id}: 레이아웃 불일치({', '.join(bad)})가 있는데 PASS — FAIL로 적는다")
    if need and verdict == "PASS" and kind == "target" and not lay and not r.get("layout_na"):
        fail(f"{case_id}: PASS인데 layout 측정이 없음 — ui-spec 배치를 재서 layout에 적거나 layout_na에 사유를 적는다")


CSS = """
:root{--bg:#f4f5f9;--surface:#fff;--ink:#131a36;--muted:#5b6382;--line:#d9dcea;--accent:#12205a;
--pass:#0f7a4d;--pass-bg:#dff3e8;--fail:#b3261e;--fail-bg:#fbe1df;--warn:#8a5a00;--warn-bg:#fbeecb;
--mono:ui-monospace,"SF Mono",Menlo,Consolas,monospace}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#0d1124;--surface:#171c36;--ink:#eceefa;
--muted:#a2a9c8;--line:#2c3358;--accent:#9db0ff;--pass:#5fd6a0;--pass-bg:#12382a;--fail:#ff9a92;--fail-bg:#45191a;
--warn:#f0c060;--warn-bg:#3b2f0d;color-scheme:dark}}
:root[data-theme="dark"]{--bg:#0d1124;--surface:#171c36;--ink:#eceefa;--muted:#a2a9c8;--line:#2c3358;--accent:#9db0ff;
--pass:#5fd6a0;--pass-bg:#12382a;--fail:#ff9a92;--fail-bg:#45191a;--warn:#f0c060;--warn-bg:#3b2f0d;color-scheme:dark}
body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.6 system-ui,-apple-system,"Apple SD Gothic Neo","Malgun Gothic",sans-serif}
.page{max-width:1080px;margin:0 auto;padding-inline:20px;padding-block:36px 64px;display:flex;flex-direction:column;gap:36px}
header{display:flex;flex-direction:column;gap:10px}
.meta{font-family:var(--mono);font-size:12px;color:var(--muted);overflow-wrap:anywhere}
h1{font-size:26px;line-height:1.3;margin:0;text-wrap:balance}
h2{font-size:19px;margin:0;text-wrap:balance}
p{margin:0;max-width:70ch}
.wrap{background:var(--surface);border:1px solid var(--line);border-radius:12px;overflow-x:auto}
table{border-collapse:collapse;width:100%;min-width:520px;font-size:14px}
th,td{text-align:left;padding:9px 14px;border-bottom:1px solid var(--line);vertical-align:top}
thead th{font-size:12px;color:var(--muted)}
tbody tr:last-child td{border-bottom:0}
.num{font-variant-numeric:tabular-nums}
.chip{display:inline-block;font-size:12px;font-weight:600;padding:2px 9px;border-radius:999px;white-space:nowrap}
.PASS{background:var(--pass-bg);color:var(--pass)}.FAIL{background:var(--fail-bg);color:var(--fail)}
.MANUAL,.NOT_RUN{background:var(--warn-bg);color:var(--warn)}
.scenario{display:flex;flex-direction:column;gap:14px}
.scenario-head{border-top:2px solid var(--ink);padding-top:12px}
.shots{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:20px;align-items:start}
figure{margin:0;display:flex;flex-direction:column;gap:9px;min-width:0}
figure img{width:100%;max-width:100%;height:auto;display:block;border-radius:14px;border:1px solid var(--line);background:var(--surface)}
.noshot{border:1px dashed var(--line);border-radius:14px;padding:22px 16px;color:var(--muted);font-size:13.5px}
figcaption{display:flex;flex-direction:column;gap:4px;font-size:13.5px;overflow-wrap:anywhere}
.top{display:flex;flex-wrap:wrap;gap:6px;align-items:center}
.cond{font-weight:600}.target .cond{color:var(--accent)}
.sub{font-family:var(--mono);font-size:11.5px;color:var(--muted)}
.layout{margin:0;padding-left:16px;font-size:12.5px;gap:2px}
.layout .bad{color:var(--fail);font-weight:600}
.notes{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:26px}
.notes>div{display:flex;flex-direction:column;gap:8px;min-width:0}
ul{margin:0;padding-left:18px;display:flex;flex-direction:column;gap:5px}
li{overflow-wrap:anywhere}
"""


def render_case(c):
    v = c["verdict"]
    shot = c.get("screenshot")
    if shot:
        media = f'<img src="{esc(shot)}" alt="{esc(c["scenario"])} — {esc(c["condition"])}" loading="lazy">'
    else:
        media = f'<div class="noshot">{esc(LABEL[v])} — 스크린샷 없음</div>'
    extra = ' · 계획에 없던 케이스' if c.get("extra") else ""
    ev = f'<span>{esc(c["evidence"])}</span>' if c.get("evidence") else ""
    lay = c.get("layout") or []
    if lay:
        n_ok = sum(1 for it in lay if it["ok"])
        items = "".join(
            f'<li class="{"ok" if it["ok"] else "bad"}">{"✓" if it["ok"] else "✗"} {esc(it["element"])} — '
            f'기대 {esc(it["expect"])}{" / 실제 " + esc(it["actual"]) if it.get("actual") else ""}</li>'
            for it in lay)
        ev += f'<span>레이아웃 {n_ok}/{len(lay)}</span><ul class="layout">{items}</ul>'
    elif c.get("layout_na"):
        ev += f'<span>레이아웃 측정 안 함: {esc(c["layout_na"])}</span>'
    return (
        f'<figure class="{esc(c["kind"])}" data-case="{esc(c["id"])}">{media}<figcaption>'
        f'<div class="top"><span class="cond">{esc(c["condition"])}</span>'
        f'<span class="chip {v}">{esc(LABEL[v])}</span></div>'
        f'<span>기대: {esc(c["expect"])}</span>{ev}'
        f'<span class="sub">{esc(c["id"])} · {esc(c["todo_id"])} · {esc(KIND[c["kind"]])}{extra}</span>'
        f'</figcaption></figure>'
    )


def render_list(title, items, empty):
    body = "".join(f"<li>{esc(i)}</li>" for i in items) if items else f"<li>{esc(empty)}</li>"
    return f"<div><h2>{esc(title)}</h2><ul>{body}</ul></div>"


def main(argv):
    fragment = False
    results_path = None
    pos = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--fragment":
            fragment = True
        elif a == "--results":
            i += 1
            if i >= len(argv):
                fail("--results 값 필요")
            results_path = argv[i]
        else:
            pos.append(a)
        i += 1
    if len(pos) != 2:
        fail("usage: visual-report.py [--fragment] <state_file> <output_dir> [--results <results.json>]")
    state_path, out_dir = pos
    if not os.path.isdir(out_dir):
        fail(f"출력 디렉토리 없음: {out_dir}")
    state = load(state_path, "상태 파일")
    res = load(results_path or os.path.join(out_dir, "results.json"), "results.json")

    planned = state.get("visual_cases") or []
    need_layout = bool(state.get("ui_specs"))
    by_id = {c["id"]: c for c in planned}
    got = {}
    for r in res.get("results") or []:
        cid = r.get("case_id")
        if cid not in by_id:
            fail(f"results의 case_id {cid}가 상태 파일 visual_cases에 없음 — 계획에 없는 케이스는 extra_cases에 적는다")
        if r.get("verdict") not in VERDICTS:
            fail(f"{cid}: verdict는 PASS|FAIL|MANUAL: {r.get('verdict')}")
        check_shot(out_dir, cid, r["verdict"], r.get("screenshot"))
        check_layout(cid, r["verdict"], by_id[cid].get("kind"), r, need_layout)
        got[cid] = r

    cases = []
    for c in planned:
        r = got.get(c["id"])
        cases.append({**c, "verdict": r["verdict"] if r else "NOT_RUN",
                      "evidence": (r or {}).get("evidence"), "screenshot": (r or {}).get("screenshot"),
                      "layout": (r or {}).get("layout"), "layout_na": (r or {}).get("layout_na")})
    for x in res.get("extra_cases") or []:
        for k in ("id", "todo_id", "scenario", "condition", "expect"):
            if not x.get(k):
                fail(f"extra_cases 항목에 {k} 없음: {x.get('id', '?')}")
        if x.get("kind") not in KIND:
            fail(f"{x['id']}: kind는 target|regression")
        if x.get("verdict") not in VERDICTS:
            fail(f"{x['id']}: verdict는 PASS|FAIL|MANUAL: {x.get('verdict')}")
        check_shot(out_dir, x["id"], x["verdict"], x.get("screenshot"))
        check_layout(x["id"], x["verdict"], x["kind"], x, need_layout)
        cases.append({**x, "extra": True})

    counts = {v: sum(1 for c in cases if c["verdict"] == v) for v in ("PASS", "FAIL", "MANUAL", "NOT_RUN")}

    scenarios = []
    for c in cases:
        if c["scenario"] not in scenarios:
            scenarios.append(c["scenario"])
    sections = []
    for s in scenarios:
        group = [c for c in cases if c["scenario"] == s]
        group.sort(key=lambda c: 0 if c["kind"] == "target" else 1)  # 안정 정렬 — 계획 순서 유지
        sections.append(
            f'<section class="scenario"><div class="scenario-head"><h2>{esc(s)}</h2></div>'
            f'<div class="shots">\n{chr(10).join(render_case(c) for c in group)}\n</div></section>'
        )

    todos = {t.get("id"): t for t in state.get("todo_items") or []}
    rows = []
    for tid in dict.fromkeys(c["todo_id"] for c in cases):
        mine = [c for c in cases if c["todo_id"] == tid]
        cell = " ".join(
            f'<span class="chip {v}">{esc(LABEL[v])} {n}</span>'
            for v in ("PASS", "FAIL", "MANUAL", "NOT_RUN")
            for n in [sum(1 for c in mine if c["verdict"] == v)] if n
        )
        rows.append(f'<tr><td>{esc(tid)}</td><td>{esc((todos.get(tid) or {}).get("desc", ""))}</td>'
                    f'<td class="num">{len(mine)}</td><td>{cell}</td></tr>')

    key = f'{state.get("issue_type", "")} #{state.get("issue_number", "")}'
    title = f'화면 확인 {key}'
    meta = " · ".join(esc(x) for x in (key, res.get("commit"), res.get("device"), res.get("build")) if x)
    not_run = [f'{c["id"]} {c["scenario"]} — {c["condition"]} (계획에 있었으나 확인 안 함)'
               for c in cases if c["verdict"] == "NOT_RUN"]
    setup = ([res["entry"]] if res.get("entry") else []) + [f"mock: {m}" for m in res.get("mock_files") or []]

    body = (
        f'<div class="page"><header><span class="meta">{meta}</span>'
        f'<h1>{esc(state.get("issue_title", ""))}</h1>'
        f'<p>같은 화면을 조건별로 나란히 놓았습니다. 대상 케이스가 먼저, 회귀 케이스가 뒤에 옵니다.</p></header>'
        f'<div class="wrap"><table><thead><tr><th>todo</th><th>내용</th><th>케이스</th><th>결과</th></tr></thead>'
        f'<tbody>{"".join(rows)}</tbody></table></div>'
        f'\n{chr(10).join(sections)}\n'
        f'<section class="notes">'
        f'{render_list("어떻게 만든 화면인가", setup, "기록 없음")}'
        f'{render_list("확인하지 못한 것", not_run + list(res.get("not_verified") or []), "없음")}'
        f'{render_list("화면에서 눈에 띈 다른 점", res.get("observations") or [], "없음")}'
        f'</section></div>'
    )
    head = f"<title>{esc(title)}</title>\n<style>{CSS}</style>\n"
    if fragment:
        doc = head + body + "\n"
    else:
        doc = ('<!doctype html>\n<html lang="ko">\n<head>\n<meta charset="utf-8">\n'
               '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
               f'{head}</head>\n<body>\n{body}\n</body>\n</html>\n')

    out = os.path.join(out_dir, "report.html")
    tmp = out + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(doc)
    os.replace(tmp, out)
    print(f'REPORT {out} — PASS {counts["PASS"]} / FAIL {counts["FAIL"]} / '
          f'MANUAL {counts["MANUAL"]} / NOT_RUN {counts["NOT_RUN"]}')


if __name__ == "__main__":
    main(sys.argv[1:])
