#!/usr/bin/env python3
"""Build grader input from CLI runs, and write grading.json files from grader output.

    python3 grading_io.py build  --evals EVALS --iteration-dir DIR > grade-args.json
    python3 grading_io.py write  --evals EVALS --iteration-dir DIR --graded graded.json
"""
import argparse
import json
import re
import sys
from pathlib import Path

FENCE = re.compile(r"(`{3,})text\n(.*?)\n\1", re.S)


def load(evals_path, it_dir):
    evals = json.loads(Path(evals_path).read_text())["evals"]
    runs = {}
    for e in evals:
        for config in ("with_skill", "without_skill"):
            p = Path(it_dir) / f"eval-{e['id']}-{e['name']}" / config / "run-1" / "run.json"
            if p.exists():
                runs[(e["id"], config)] = json.loads(p.read_text())
    return evals, runs


def build(a):
    """Write each reply to a blind file named by a shuffled letter; the graders read those files."""
    import hashlib
    evals, runs = load(a.evals, a.iteration_dir)
    blind = Path(a.iteration_dir) / "blind"
    cases = {}
    for e in evals:
        c = cases.setdefault(e["case_id"], {k: e[k] for k in ("passage", "review_rule", "acceptable_example", "cue_literals", "must_preserve")} | {"case_id": e["case_id"], "responses": []})
        ask = e["prompt"][: -len(e["passage"])].rstrip() if e["prompt"].endswith(e["passage"]) else e["prompt"]
        for config in ("with_skill", "without_skill"):
            r = runs.get((e["id"], config))
            if r:
                c["responses"].append({"id": e["id"], "config": config, "ask": ask, "reply": r.get("reply") or "(no reply)"})
    for c in cases.values():
        # Deterministic shuffle so neither position nor file name reveals the configuration.
        c["responses"].sort(key=lambda r: hashlib.sha256(f"{c['case_id']}:{r['id']}:{r['config']}".encode()).hexdigest())
        d = blind / c["case_id"]
        d.mkdir(parents=True, exist_ok=True)
        for i, r in enumerate(c["responses"]):
            r["label"] = "ABCDEF"[i]
            f = d / f"response-{r['label']}.md"
            f.write_text(r.pop("reply"), encoding="utf-8")
            r["file"] = str(f)
    json.dump({"cases": list(cases.values())}, sys.stdout, ensure_ascii=False)


def replacement_for(reply, passage, judged):
    m = FENCE.search(reply or "")
    if m:
        return m.group(2), "fenced block in the reply"
    if reply and re.search(r"no changes needed", reply, re.I) and "```" not in reply:
        return passage, "reply says no changes needed"
    return judged, "grader's exact copy of the proposed replacement"


def write(a):
    evals, runs = load(a.evals, a.iteration_dir)
    by_id = {e["id"]: e for e in evals}
    graded = json.loads(Path(a.graded).read_text())
    if isinstance(graded, dict) and "result" in graded:
        graded = graded["result"]
    n = 0
    for case in graded:
        if not case or case.get("error"):
            print("skipped case", case and case.get("case_id"), file=sys.stderr)
            continue
        for g in case["graded"]:
            e, j, s, arb = by_id[g["id"]], g["judge"] or {}, g["skeptic"] or {}, g["arbiter"]
            run = runs[(g["id"], g["config"])]
            rep, how = replacement_for(run.get("reply"), e["passage"], j.get("replacement_text", ""))
            exp = []
            if e["must_preserve"]:
                missing = [x for x in e["must_preserve"] if x not in rep]
                exp.append({"text": e["expectations"][0], "passed": not missing,
                            "evidence": (f"missing: {missing}" if missing else "all present") + f" (replacement from {how})"})
            fid_ev = f"judge: {j.get('fidelity_evidence', '')} | skeptic: {s.get('detail', '')}"
            if arb:
                fid_ev += f" | arbiter: {arb.get('reasoning', '')}"
            exp.append({"text": "No material change of meaning: claims, certainty, negation, conditions, obligations, names and numbers all survive",
                        "passed": bool(g["fidelity_ok_final"]), "evidence": fid_ev})
            exp.append({"text": "Meets the case rule: " + e["review_rule"], "passed": bool(j.get("rule_met")), "evidence": j.get("rule_evidence", "")})
            exp.append({"text": "Proportional edit: already-good text is left alone", "passed": bool(j.get("proportional")), "evidence": j.get("proportional_evidence", "")})
            exp.append({"text": "Suggests no invented facts, numbers, examples or opinions", "passed": not j.get("invented_content", True), "evidence": "judge: invented_content=" + str(j.get("invented_content"))})
            exp.append({"text": "Gives one clean, copyable replacement with no change summary, critique or draft-and-final pair", "passed": bool(j.get("single_clean_result")), "evidence": j.get("clean_evidence", "")})
            exp.append({"text": "Makes no judgment about whether the text was written by AI", "passed": not j.get("authorship_judgment", True), "evidence": "judge: authorship_judgment=" + str(j.get("authorship_judgment"))})
            passed = sum(x["passed"] for x in exp)
            run_dir = Path(a.iteration_dir) / f"eval-{e['id']}-{e['name']}" / g["config"] / "run-1"
            grading = {"expectations": exp, "summary": {"passed": passed, "failed": len(exp) - passed, "total": len(exp), "pass_rate": round(passed / len(exp), 4)},
                       "execution_metrics": {"total_tool_calls": len(run.get("tools") or []), "errors_encountered": 0 if run.get("rc") == 0 else 1},
                       "quality": j.get("quality"), "skill_triggered": run.get("skill_triggered"), "replacement_text": rep}
            (run_dir / "grading.json").write_text(json.dumps(grading, ensure_ascii=False, indent=2), encoding="utf-8")
            meta = {"eval_id": e["id"], "eval_name": e["name"], "prompt": e["prompt"], "assertions": e["expectations"]}
            for d in (run_dir.parents[1], run_dir.parent):
                (d / "eval_metadata.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
            n += 1
    print(f"wrote {n} grading.json files", file=sys.stderr)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["build", "write"])
    ap.add_argument("--evals", required=True)
    ap.add_argument("--iteration-dir", required=True)
    ap.add_argument("--graded")
    a = ap.parse_args()
    build(a) if a.mode == "build" else write(a)
