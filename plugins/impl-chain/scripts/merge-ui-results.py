#!/usr/bin/env python3
"""figma-ui-spec 결과 JSON을 analyze draft에 병합한다 (analyze-spec Step 4-1).

Usage: merge-ui-results.py <draft.json> <result.json>...

- result.json = figma-ui-spec이 `{figma_dir}/ui-spec/{name}.result.json`에 쓴 파일
  {group, screens, file, auto:[{key,question,answer,evidence,apply}], questions:[{key,question,candidates,evidence,apply_by_answer,recommended_reason?}]}
- draft의 `ui_results`([{file, result_path}])에 등록하고(같은 `file`이면 교체 = 그룹 재실행),
  등록된 모든 결과로 UI 유래 decisions(by claude)·open_questions를 **처음부터 다시 만든다**.
  그래서 몇 번을 돌려도 같은 결과가 나오고, 재실행한 그룹의 이전 기여분은 남지 않는다.
- 병합 규칙
  - auto: 같은 key·같은 answer → decision 하나 (todo_ids 합집합). answer가 다르면 질문으로 올린다.
  - questions: 같은 key → 하나로 (candidates 합집합·순서 유지, apply_by_answer 이어붙임, todo_ids 합집합,
    ui_spec = 첫 그룹 파일, ui_spec_also = 나머지). recommended = candidates[0].
  - 사용자가 이미 답한 key(decisions by != claude, 같은 key)는 다시 질문으로 만들지 않는다.
    단, 재실행한 그룹 파일에서 나온 사용자 답은 지운다 (analyze Step 7 규칙: 그 그룹의 결정은 다시 받는다).
- todo_ids = draft todo 중 figma_screens가 그 결과의 screens와 겹치는 것 (todo 순서).
stdout: 결과마다 `MERGED {file}: auto {a} / questions {q}` + 마지막 줄 `conflicts {c}`.
exit 1: 입력 형식 오류 (draft는 바뀌지 않는다).
"""
import json
import sys


def fail(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        fail(f"{path}: {e}")


def check_result(path, r):
    for k in ("group", "screens", "file"):
        if not r.get(k):
            fail(f"{path}: 필수 필드 없음 — {k}")
    for a in r.get("auto", []):
        if not a.get("key") or "answer" not in a:
            fail(f"{path}: auto 항목에 key/answer 없음")
    for q in r.get("questions", []):
        if not q.get("key") or not q.get("candidates"):
            fail(f"{path}: questions 항목에 key/candidates 없음")


def union(a, b):
    return a + [x for x in b if x not in a]


def main():
    if len(sys.argv) < 3:
        fail("usage: merge-ui-results.py <draft.json> <result.json>...")
    draft_path, new_paths = sys.argv[1], sys.argv[2:]
    draft = load(draft_path)

    registry = list(draft.get("ui_results", []))
    rerun_files = set()
    for p in new_paths:
        r = load(p)
        check_result(p, r)
        entry = {"file": r["file"], "result_path": p}
        idx = next((i for i, e in enumerate(registry) if e["file"] == r["file"]), None)
        if idx is None:
            registry.append(entry)
        else:
            registry[idx] = entry
            rerun_files.add(r["file"])

    results = []
    for e in registry:
        r = load(e["result_path"])
        check_result(e["result_path"], r)
        results.append(r)

    todos = draft.get("todo_items", [])

    def todo_ids_for(screens):
        return [t["id"] for t in todos if set(t.get("figma_screens") or []) & set(screens)]

    # key → [(file, item, todo_ids)]
    autos, questions = {}, {}
    for r in results:
        tids = todo_ids_for(r["screens"])
        for a in r.get("auto", []):
            autos.setdefault(a["key"], []).append((r["file"], a, tids))
        for q in r.get("questions", []):
            questions.setdefault(q["key"], []).append((r["file"], q, tids))

    # 기존 decisions: UI 유래 claude 결정은 다시 만든다. 재실행 그룹에서 나온 사용자 답은 지운다.
    def from_rerun(d):
        files = [d.get("ui_spec")] + list(d.get("ui_spec_also", []))
        return any(f in rerun_files for f in files if f)

    kept_decisions = [d for d in draft.get("decisions", [])
                      if not (d.get("ui_spec") and (d.get("by") == "claude" or from_rerun(d)))]
    answered = {d.get("key") for d in kept_decisions if d.get("key")}
    kept_questions = [q for q in draft.get("open_questions", []) if not q.get("ui_spec")]

    new_decisions, new_questions, conflicts = [], [], 0

    for key, items in autos.items():
        if key in answered:
            continue
        answers = []
        for _, a, _ in items:
            if a["answer"] not in answers:
                answers.append(a["answer"])
        files = []
        for f, _, _ in items:
            if f not in files:
                files.append(f)
        tids = []
        for _, _, t in items:
            tids = union(tids, t)
        first = items[0][1]
        if len(answers) == 1 and key not in questions:
            d = {"key": key, "ui_spec": files[0], "question": first.get("question", key), "answer": answers[0],
                 "evidence": first.get("evidence"), "by": "claude", "todo_ids": tids, "apply": first.get("apply", [])}
            if len(files) > 1:
                d["ui_spec_also"] = files[1:]
            new_decisions.append(d)
        else:
            # 그룹 간 자동 결정이 다르거나 다른 그룹이 같은 key를 질문으로 냈다 → 질문으로 합친다
            conflicts += 1
            aba = {}
            for _, a, _ in items:
                aba.setdefault(a["answer"], [])
                aba[a["answer"]] = aba[a["answer"]] + [x for x in a.get("apply", []) if x not in aba[a["answer"]]]
            questions.setdefault(key, [])
            questions[key] = [(files[0], {"key": key, "question": first.get("question", key) + " (그룹 간 자동 결정이 다름)",
                                          "candidates": answers,
                                          "evidence": "; ".join(f"{f}: {a['answer']} ({a.get('evidence')})" for f, a, _ in items),
                                          "apply_by_answer": aba}, tids)] + questions[key]
            for f, _, t in items[1:]:
                questions[key].append((f, {"key": key, "candidates": [], "apply_by_answer": {}}, t))

    for key, items in questions.items():
        if key in answered:
            continue
        cands, aba, tids, files = [], {}, [], []
        question, evidence, reason = None, [], None
        for f, q, t in items:
            cands = union(cands, q.get("candidates", []))
            for c, ap in (q.get("apply_by_answer") or {}).items():
                aba[c] = aba.get(c, []) + list(ap)
            tids = union(tids, t)
            if f not in files:
                files.append(f)
            question = question or q.get("question")
            if q.get("evidence") and q["evidence"] not in evidence:
                evidence.append(q["evidence"])
            reason = reason or q.get("recommended_reason")
        oq = {"key": key, "ui_spec": files[0], "question": question or key, "candidates": cands,
              "recommended": cands[0], "evidence": "; ".join(evidence), "apply_by_answer": aba, "todo_ids": tids}
        if reason:
            oq["recommended_reason"] = reason
        if len(files) > 1:
            oq["ui_spec_also"] = files[1:]
        new_questions.append(oq)

    draft["ui_results"] = registry
    draft["ui_specs"] = [{"group": r["group"], "screens": r["screens"], "file": r["file"]} for r in results]
    draft["decisions"] = kept_decisions + new_decisions
    draft["open_questions"] = kept_questions + new_questions

    with open(draft_path, "w") as f:
        json.dump(draft, f, ensure_ascii=False, indent=2)

    for r in results:
        print(f"MERGED {r['file']}: auto {len(r.get('auto', []))} / questions {len(r.get('questions', []))}")
    print(f"conflicts {conflicts}")


if __name__ == "__main__":
    main()
