#!/usr/bin/env python3
"""Run each eval prompt through a real `claude -p` session, with and without the skill.

with_skill: a fresh project folder whose .claude/skills/anti-slop holds the skill,
so Claude Code discovers it the way a user's project would and decides itself
whether to use it. without_skill: the same prompt in an empty folder. Both get
the same tools. Results land in the skill-creator workspace layout:
  <ws>/iteration-N/eval-<id>-<name>/<config>/run-1/{outputs/reply.md, timing.json, run.json}
"""
import argparse
import json
import os
import shutil
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

TOOLS = ["Skill", "Read", "Write", "Glob", "Bash(python3:*)", "Bash(mkdir:*)", "Bash(cat:*)", "Bash(ls:*)"]


def run_one(e, config, skill, ws, iteration, runs_root, timeout):
    run_dir = ws / f"iteration-{iteration}" / f"eval-{e['id']}-{e['name']}" / config / "run-1"
    if (run_dir / "run.json").exists():
        return json.loads((run_dir / "run.json").read_text())
    proj = runs_root / f"{e['id']}-{config}"
    shutil.rmtree(proj, ignore_errors=True)
    proj.mkdir(parents=True)
    if config == "with_skill":
        shutil.copytree(skill, proj / ".claude" / "skills" / "anti-slop", ignore=shutil.ignore_patterns("evals", "__pycache__"))
    env = {k: v for k, v in os.environ.items() if k not in ("CLAUDECODE", "ANTHROPIC_API_KEY", "CLAUDE_CODE_ENTRYPOINT")}
    cmd = ["claude", "-p", e["prompt"], "--output-format", "stream-json", "--verbose",
           "--no-session-persistence", "--allowedTools", *TOOLS]
    t0 = time.time()
    try:
        p = subprocess.run(cmd, cwd=proj, env=env, capture_output=True, text=True, timeout=timeout)
        lines = p.stdout.splitlines()
        rc = p.returncode
    except subprocess.TimeoutExpired as x:
        lines = (x.stdout or b"").decode() .splitlines() if isinstance(x.stdout, bytes) else (x.stdout or "").splitlines()
        rc = "timeout"
    elapsed = time.time() - t0
    tools, skills_used, result, usage, duration_ms, transcript = [], [], None, {}, None, []
    for line in lines:
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            continue
        if ev.get("type") == "assistant":
            for block in ev.get("message", {}).get("content", []):
                if block.get("type") == "tool_use":
                    tools.append(block.get("name"))
                    inp = block.get("input", {})
                    if block.get("name") == "Skill":
                        skills_used.append(inp.get("skill") or inp.get("command") or json.dumps(inp))
                    transcript.append(f"- tool {block.get('name')}: {json.dumps(inp, ensure_ascii=False)[:300]}")
                elif block.get("type") == "text" and block.get("text"):
                    transcript.append(f"- text: {block['text'][:300]}")
        elif ev.get("type") == "result":
            result = ev.get("result")
            usage = ev.get("usage") or {}
            duration_ms = ev.get("duration_ms")
    tokens = sum(int(usage.get(k) or 0) for k in ("input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"))
    out = run_dir / "outputs"
    out.mkdir(parents=True, exist_ok=True)
    (out / "reply.md").write_text(result or "(no reply)", encoding="utf-8")
    (run_dir / "transcript.md").write_text("\n".join(transcript), encoding="utf-8")
    secs = (duration_ms or elapsed * 1000) / 1000
    (run_dir / "timing.json").write_text(json.dumps({"total_tokens": tokens, "duration_ms": int(secs * 1000), "total_duration_seconds": round(secs, 1)}))
    triggered = any("anti-slop" in s for s in skills_used) or any(
        "anti-slop" in t and ("SKILL.md" in t) for t in transcript)
    rec = {"id": e["id"], "name": e["name"], "config": config, "rc": rc, "reply": result, "tools": tools,
           "skills_used": skills_used, "skill_triggered": triggered, "seconds": round(secs, 1), "tokens": tokens}
    (run_dir / "run.json").write_text(json.dumps(rec, ensure_ascii=False, indent=2), encoding="utf-8")
    return rec


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--skill", required=True, type=Path)
    ap.add_argument("--evals", required=True, type=Path)
    ap.add_argument("--workspace", required=True, type=Path)
    ap.add_argument("--iteration", type=int, default=1)
    ap.add_argument("--ids", default="", help="comma-separated eval ids (default all)")
    ap.add_argument("--configs", default="with_skill,without_skill")
    ap.add_argument("--jobs", type=int, default=6)
    ap.add_argument("--timeout", type=int, default=300)
    a = ap.parse_args()
    evals = json.loads(a.evals.read_text())["evals"]
    if a.ids:
        keep = {int(x) for x in a.ids.split(",")}
        evals = [e for e in evals if e["id"] in keep]
    runs_root = Path("/tmp/claude-0/skill-eval-runs") / f"iteration-{a.iteration}"
    jobs = [(e, c) for e in evals for c in a.configs.split(",")]
    done = 0
    with ThreadPoolExecutor(a.jobs) as pool:
        futs = {pool.submit(run_one, e, c, a.skill, a.workspace, a.iteration, runs_root, a.timeout): (e, c) for e, c in jobs}
        for f in as_completed(futs):
            e, c = futs[f]
            done += 1
            try:
                r = f.result()
                print(f"[{done}/{len(jobs)}] {e['name']} {c}: rc={r['rc']} {r['seconds']}s skill={r['skill_triggered']} tools={r['tools']}", flush=True)
            except Exception as x:
                print(f"[{done}/{len(jobs)}] {e['name']} {c}: ERROR {x!r}", flush=True)


if __name__ == "__main__":
    main()
