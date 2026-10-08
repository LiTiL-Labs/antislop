#!/usr/bin/env python3
"""Keep the anti-slop skill in step with the canonical prompt sources.

The skill (default: .claude/skills/anti-slop) carries the primary prompt's
instruction body and each reviewed profile's rule body verbatim, between
BEGIN/END canonical markers, plus byte-identical copies of the upstream MIT
notices. This script refreshes those regions from ../prompts and ../third_party,
using the same section rule as PromptLibrary.section: the text after
"## <name>" up to the next level-2 heading, trimmed.

    python3 app/scripts/sync-skill.py            # refresh the skill in place
    python3 app/scripts/sync-skill.py --check    # exit 1 if the skill has drifted
    python3 app/scripts/sync-skill.py --skill-dir PATH [--check]
"""
import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# (file inside the skill, canonical source relative to the repo root, section name)
BLOCKS = [
    ("SKILL.md", "prompts/primary.md", "Instruction body"),
    ("references/profiles/no-ai-slop.md", "prompts/profiles/no-ai-slop.md", "Editorial rule body"),
    ("references/profiles/humanizer.md", "prompts/profiles/humanizer.md", "Editorial rule body"),
]
LICENSES = [
    ("licenses/no-ai-slop-LICENSE.txt", "third_party/no-ai-slop/LICENSE"),
    ("licenses/humanizer-LICENSE.txt", "third_party/humanizer/LICENSE"),
]


def section(markdown: str, name: str) -> str:
    lines = markdown.split("\n")
    try:
        start = lines.index(f"## {name}")
    except ValueError:
        sys.exit(f"missing section '## {name}'")
    body = []
    for line in lines[start + 1:]:
        if line.startswith("## "):
            break
        body.append(line)
    text = "\n".join(body).strip()
    if not text:
        sys.exit(f"empty section '## {name}'")
    return text


def fill(doc: str, source: str, body: str, where: str) -> str:
    pattern = re.compile(
        r"(<!-- BEGIN canonical: " + re.escape(source) + r"[^\n]*-->\n)(.*?)(<!-- END canonical: " + re.escape(source) + r" -->)",
        re.S,
    )
    matches = pattern.findall(doc)
    if len(matches) != 1:
        sys.exit(f"{where}: expected exactly one canonical block for {source}, found {len(matches)}")
    return pattern.sub(lambda m: m.group(1) + body + "\n" + m.group(3), doc)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--skill-dir", type=Path, default=ROOT / ".claude" / "skills" / "anti-slop")
    parser.add_argument("--check", action="store_true", help="report drift instead of rewriting")
    args = parser.parse_args()
    skill = args.skill_dir.resolve()
    drift = []

    for rel, source, name in BLOCKS:
        path = skill / rel
        current = path.read_text(encoding="utf-8")
        body = section((ROOT / source).read_text(encoding="utf-8"), name)
        updated = fill(current, source, body, rel)
        if updated != current:
            drift.append(rel)
            if not args.check:
                path.write_text(updated, encoding="utf-8")

    for rel, source in LICENSES:
        path = skill / rel
        data = (ROOT / source).read_bytes()
        if not path.exists() or path.read_bytes() != data:
            drift.append(rel)
            if not args.check:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)

    # Compiled bytecode must never ship in the skill.
    caches = sorted(str(p.relative_to(skill)) for p in skill.rglob("*") if p.name == "__pycache__" or p.suffix == ".pyc")
    if caches:
        drift.extend(caches)
        if not args.check:
            import shutil
            for rel in caches:
                path = skill / rel
                if path.is_dir():
                    shutil.rmtree(path, ignore_errors=True)
                elif path.exists():
                    path.unlink()

    if args.check:
        if drift:
            print("anti-slop skill has drifted from the canonical sources: " + ", ".join(drift))
            print("run: python3 app/scripts/sync-skill.py")
            return 1
        print("anti-slop skill matches prompts/ and third_party/ notices")
        return 0
    print("refreshed: " + (", ".join(drift) if drift else "nothing (already in sync)"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
