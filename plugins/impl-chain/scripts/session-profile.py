#!/usr/bin/env python3
"""Claude Code 세션 기록에서 체인이 어디에 시간을 썼는지 요약한다 (읽기 전용).

Usage:
  session-profile.py <session_dir_or_jsonl> [--top N]

  <session>   ~/.claude/projects/{레포 폴더}/{session-id}  (또는 그 .jsonl)
              메인 기록 {session-id}.jsonl과 서브에이전트 기록 {session-id}/subagents/*.jsonl을 읽는다.

출력 (에이전트마다 한 블록, 메인 먼저 그다음 시작 순):
  - 모델, 경과 시간, 모델이 생성에 쓴 시간(도구 결과를 받은 뒤 다음 응답까지), 출력 토큰
  - 컨텍스트 최대 크기(토큰), API 오류 수, 자동 압축(compact) 횟수, 실패한 도구 호출 수
  - 도구별 호출 수 · 걸린 시간 · 결과 크기 (텍스트 / 이미지 나눠서)
  - 가장 오래 걸린 도구 호출 N개 (도구 이름과 걸린 시간만)

코드·문구·응답 내용은 출력하지 않는다 — 시간·횟수·크기만. 회사 레포 세션에서 돌려 결과를 공유해도 된다.
종료 코드: 0 / 1 입력 오류
"""
import collections
import glob
import json
import os
import sys
from datetime import datetime

FIGMA = "mcp__plugin_figma_figma__"


def ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


def short(name):
    if name.startswith(FIGMA):
        return "figma:" + name[len(FIGMA):]
    if name.startswith("mcp__"):
        return name.split("__", 2)[-1]
    return name


def sizes(content):
    """tool_result 내용의 (텍스트 바이트, 이미지 수, 이미지 바이트)."""
    if isinstance(content, str):
        return len(content.encode()), 0, 0
    txt = img = n_img = 0
    for x in content or []:
        if not isinstance(x, dict):
            continue
        if x.get("type") == "image":
            n_img += 1
            img += len(json.dumps(x))
        else:
            txt += len(json.dumps(x.get("text", x)).encode())
    return txt, n_img, img


def load(path):
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return rows


def profile(path, label, top):
    rows = load(path)
    timed = [r for r in rows if r.get("timestamp")]
    if not timed:
        return None
    t0, t1 = ts(timed[0]["timestamp"]), ts(timed[-1]["timestamp"])
    pend = {}
    stat = collections.defaultdict(lambda: {"n": 0, "sec": 0.0, "txt": 0, "img": 0, "n_img": 0, "err": 0})
    calls = []
    model = None
    out_by_msg = {}
    peak_ctx = 0
    gen = 0.0
    last_result = None
    api_err = compact = 0
    for r in timed:
        t = ts(r["timestamp"])
        typ = r.get("type")
        if typ == "system":
            if r.get("subtype") == "api_error":
                api_err += 1
            elif "compact" in str(r.get("subtype", "")):
                compact += 1
            continue
        m = r.get("message") or {}
        content = m.get("content") if isinstance(m.get("content"), list) else []
        if typ == "assistant":
            model = model or m.get("model")
            u = m.get("usage") or {}
            mid = m.get("id") or id(r)
            out_by_msg[mid] = max(out_by_msg.get(mid, 0), u.get("output_tokens", 0))
            peak_ctx = max(peak_ctx, u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0)
                           + u.get("cache_creation_input_tokens", 0))
            if last_result is not None:
                gen += max(0.0, t - last_result)
                last_result = None
            for c in content:
                if c.get("type") == "tool_use":
                    pend[c.get("id")] = (short(c.get("name", "?")), t)
        elif typ == "user":
            for c in content:
                if c.get("type") != "tool_result" or c.get("tool_use_id") not in pend:
                    continue
                name, st = pend.pop(c["tool_use_id"])
                s = stat[name]
                txt, n_img, img = sizes(c.get("content"))
                s["n"] += 1
                s["sec"] += t - st
                s["txt"] += txt
                s["img"] += img
                s["n_img"] += n_img
                s["err"] += 1 if c.get("is_error") else 0
                calls.append((t - st, name))
                last_result = t
    return {
        "label": label, "model": model or "?", "start": t0, "wall": t1 - t0, "gen": gen,
        "out": sum(out_by_msg.values()), "peak_ctx": peak_ctx, "api_err": api_err, "compact": compact,
        "stat": stat, "slow": sorted(calls, reverse=True)[:top],
    }


def fmt_min(sec):
    return f"{sec / 60:.1f}m"


def kb(b):
    return f"{b // 1000}KB"


def show(p):
    s = p["stat"]
    errs = sum(v["err"] for v in s.values())
    print(f'\n== {p["label"]} — {p["model"]}')
    print(f'   경과 {fmt_min(p["wall"])} · 모델 생성 {fmt_min(p["gen"])} · 출력 {p["out"]} tok · '
          f'컨텍스트 최대 {p["peak_ctx"]} tok · API 오류 {p["api_err"]} · 압축 {p["compact"]} · 도구 실패 {errs}')
    for name, v in sorted(s.items(), key=lambda kv: -kv[1]["sec"]):
        img = f' + 이미지 {v["n_img"]}장 {kb(v["img"])}' if v["n_img"] else ""
        err = f' · 실패 {v["err"]}' if v["err"] else ""
        print(f'   {name:38s} {v["n"]:4d}회 {fmt_min(v["sec"]):>7s}  텍스트 {kb(v["txt"])}{img}{err}')
    if p["slow"]:
        print("   가장 오래 걸린 호출: " + ", ".join(f"{n} {sec:.0f}s" for sec, n in p["slow"]))


def main(argv):
    top = 5
    pos = []
    i = 0
    while i < len(argv):
        if argv[i] == "--top":
            i += 1
            if i >= len(argv) or not argv[i].isdigit():
                print("--top 숫자 필요", file=sys.stderr)
                sys.exit(1)
            top = int(argv[i])
        else:
            pos.append(argv[i])
        i += 1
    if len(pos) != 1:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        sys.exit(1)
    base = pos[0][:-6] if pos[0].endswith(".jsonl") else pos[0].rstrip("/")
    main_file = base + ".jsonl"
    subs = sorted(glob.glob(os.path.join(base, "subagents", "*.jsonl")))
    if not os.path.isfile(main_file) and not subs:
        print(f"세션 기록 없음: {main_file} / {base}/subagents/", file=sys.stderr)
        sys.exit(1)

    profiles = []
    if os.path.isfile(main_file):
        p = profile(main_file, "메인", top)
        if p:
            profiles.append(p)
    agents = []
    for f in subs:
        meta = f[:-6] + ".meta.json"
        label = os.path.basename(f)[:-6]
        try:
            with open(meta, encoding="utf-8") as mf:
                md = json.load(mf)
            label = f'{md.get("agentType", "?")} ({md.get("description", "")})'
        except (OSError, json.JSONDecodeError):
            pass
        p = profile(f, label, top)
        if p:
            agents.append(p)
    profiles += sorted(agents, key=lambda p: p["start"])
    if not profiles:
        print("타임스탬프가 있는 기록 없음", file=sys.stderr)
        sys.exit(1)

    print(f"세션: {base}")
    print("서브에이전트 경과 시간 합계(병렬 실행이면 실제 시간보다 크다): "
          + fmt_min(sum(p["wall"] for p in agents)))
    for p in profiles:
        show(p)


if __name__ == "__main__":
    main(sys.argv[1:])
