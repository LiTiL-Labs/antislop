#!/usr/bin/env python3
"""Compare protected content between an original passage and its rewrite.

A review cue for the final fidelity check, not a verdict. It counts literal
items in both texts and reports any that the rewrite has fewer of (lost) or,
for categories where an addition changes meaning, more of (added):

  url, email, quotation, number, month, reference (Section 4.2, clause 9(b),
  § 12(b), Exhibit A), citation (Smith v. Jones, 123 F.3d 456), term
  (capitalized words that are not just sentence openers, and acronyms), code
  (backtick spans, identifiers, operators), modal (shall, must, may, will, can,
  could, might, should, would), limiter (not, no, never, nothing, nobody,
  nowhere, non-, only, except, unless, without, until, ...), hedge (some,
  most, likely, approximately, ...), plus leading/trailing whitespace and line
  endings. Contractions are expanded before counting (won't = will not,
  can't = can not, we'll = we will).

Equivalent wording can be correct even when flagged ("roughly" for "about").
A lost "not", "may" or "Section 4.2", or an added "must", "not" or number,
usually means meaning changed. An empty report is not proof of fidelity: the
script only knows these literal forms.

    python3 protected_terms.py --original original.txt --rewrite rewrite.txt
    python3 protected_terms.py --pair pair.json        # {"original": ..., "rewrite": ...}; - for stdin
    add --json for machine-readable output

Exit status: 0 for a completed check (read the output), 2 on a usage or input error.
"""
import argparse
import json
import re
import sys
from collections import Counter

MONTHS = set(("January February March April May June July August September October November December "
              "Jan Feb Mar Apr Jun Jul Aug Sep Sept Oct Nov Dec").split())
MODALS = set("shall must may will can could might should would".split())
LIMITERS = set(("not no never none nor neither nothing nobody nowhere without only except unless until "
                "before after notwithstanding solely provided subject if").split())
HEDGES = set(("some many most few several often usually generally typically approximately about around "
              "roughly nearly almost likely unlikely possibly perhaps probably potentially apparently "
              "appears seems suggests suggest partially partly").split())
# Capitalized words that commonly open a sentence or clause; not treated as terms on their own.
OPENERS = set("""a an the this that these those it its in on at by for from to of and or but if when
while where as so then there here we i you he she they our my your their his her is are was were be
honestly basically overall finally first second third also however moreover furthermore additionally
please note based subject""".split())
CITATION_SIGNALS = OPENERS | {"under", "see", "cf.", "per", "following", "accord", "contra", "compare", "citing"}
# Categories where an increase in the rewrite can change meaning or add an invented fact.
ADDITION_MATTERS = ("modal", "limiter", "number", "month", "reference", "citation", "url", "email", "quotation")
# Categories counted from free text, where a literal can also survive inside a longer match.
LITERAL_FALLBACK = ("term", "quotation", "reference", "citation", "code")

PATTERNS = {
    "url": re.compile(r"https?://[^\s<>\"']+"),
    "email": re.compile(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+"),
    "quotation": re.compile(
        r"\"(?:[^\"\n]|\n(?![ \t]*\n))+\"|“(?:[^”\n]|\n(?![ \t]*\n))+”|«(?:[^»\n]|\n(?![ \t]*\n))+»"
        r"|(?<![\w’])‘[^‘’\n]+’(?!\w)|(?<![\w'])'[^'\n]+'(?!\w)"),
    "reference": re.compile(
        r"(?:\b(?:[Ss]ections?|[Cc]lauses?|[Aa]rticles?|[Ss]chedules?|[Ee]xhibits?|[Aa]nnex(?:es)?|"
        r"[Aa]ppendi(?:x|ces)|[Pp]aragraphs?|[Rr]ule)|§§?)\s*(?:\d+(?:\.\d+)*|[A-Z]{1,4}\b)(?:\([A-Za-z0-9]+\))*"),
    "citation": re.compile(r"\b[A-Z][\w.&'-]*(?:\s[A-Z][\w.&'-]*)*\s+v\.\s+[A-Z][\w.&'-]*(?:\s[A-Z][\w.&'-]*)*"
                           r"|\b\d+\s+(?:[A-Z][A-Za-z]{0,4}\.\s?)+(?:\d[a-z]{1,2}\s)?\s*\d+\b"),
    "number": re.compile(r"(?<![\w.])[-−]?[$€£¥]?(?:\d(?:[\d,]*\d)?(?:\.\d+)*|\.\d+)(?:%|st|nd|rd|th)?"),
    "code": re.compile(r"`[^`\n]+`|\b[a-z]+[A-Z]\w*\b|\b[A-Za-z]+_\w+\b|\w+\(\)|&&|\|\||==|!=|->|::"),
}
BULLET = re.compile(r"(?:^|\n)[ \t]*(?:[-*•+]|\d+[.)]|#+)[ \t]+$")


def strip_url(u: str) -> str:
    return u.rstrip(".,;:!?)]}'\"`*>")


def citation_core(c: str) -> str:
    parts = c.rstrip(".,;:").split()
    # Drop leading sentence openers or signals ("In", "Under", "See") but keep a word before "v.".
    while len(parts) > 1 and parts[1] != "v." and parts[0].lower() in CITATION_SIGNALS:
        parts.pop(0)
    return " ".join(parts)


def starts_sentence(text: str, i: int) -> bool:
    raw = text[:i]
    before = raw.rstrip()
    if before == "" or before[-1] in ".!?:;\"“(" or before.endswith("--"):
        return True
    if BULLET.search(raw):
        return True
    gap = raw[len(before):]
    if "\n" not in gap:
        return False
    if gap.count("\n") >= 2:
        return True
    prev = before.rsplit("\n", 1)[-1].strip()
    # A greeting ("Hi Sam,") or a short heading line ends the previous sentence; a hard wrap does not.
    return prev.endswith(",") or len(prev.split()) <= 6


def terms(text: str) -> Counter:
    """Capitalized words that are not merely sentence openers, plus acronyms and multiword names."""
    found = Counter()
    for m in re.finditer(r"(?<![\w'’-])[^\W\d_](?:[\w'’&.-]*[^\W_])?", text):
        word = m.group(0).rstrip(".")
        if not word or not word[0].isupper():
            continue
        if word.isupper() and len(word) >= 2:
            found[word] += 1
            continue
        if word.lower() in OPENERS:
            continue
        if not starts_sentence(text, m.start()):
            found[word] += 1
            continue
        if word.lower() in CITATION_SIGNALS:
            # "See Smith v. Jones": a signal opening a citation, not the start of a name.
            continue
        nxt = re.match(r"[ \t]+([^\W\d_])", text[m.end():])
        if nxt and nxt.group(1).isupper():
            # "Acme LLC", "Émilie Dupont" at a sentence start: the name continues.
            found[word] += 1
    return found


def norm_tokens(text: str) -> list:
    """Lowercased word tokens with contractions expanded and hyphenated words split."""
    out = []
    for tok in re.findall(r"[^\W\d_][\w'’-]*", text):
        for part in tok.lower().replace("’", "'").split("-"):
            if not part:
                continue
            if part.endswith("n't"):
                stem = {"wo": "will", "ca": "can", "sha": "shall"}.get(part[:-3], part[:-3])
                out += [stem, "not"]
            elif part == "cannot":
                out += ["can", "not"]
            elif part.endswith("'ll"):
                out += [part[:-3], "will"]
            elif part.endswith("'d"):
                out += [part[:-2], "would"]
            else:
                out.append(part)
    return out


def inventory(text: str) -> dict:
    inv = {}
    for name, pattern in PATTERNS.items():
        items = pattern.findall(text)
        if name == "url":
            items = [strip_url(u) for u in items]
        elif name == "citation":
            items = [citation_core(c) for c in items]
        inv[name] = Counter(items)
    inv["month"] = Counter(w for w in re.findall(r"[A-Za-z]+", text) if w in MONTHS)
    inv["term"] = terms(text)
    toks = norm_tokens(text)
    inv["modal"] = Counter(t for t in toks if t in MODALS)
    limiter = Counter(t for t in toks if t in LIMITERS)
    non = len(re.findall(r"\bnon-(?=\w)|\bnon(?!e\b|etheless\b|sense|ce\b)(?=[a-z])", text, re.I))
    if non:
        limiter["non-"] = non
    inv["limiter"] = limiter
    inv["hedge"] = Counter(t for t in toks if t in HEDGES)
    return inv


def literal_count(item: str, text: str) -> int:
    return len(re.findall(r"(?<![\w@/.-])" + re.escape(item) + r"(?![\w@/-])", text)) if item else 0


def line_endings(text: str) -> tuple:
    return text.count("\r\n"), len(re.findall(r"(?<!\r)\n", text)), len(re.findall(r"\r(?!\n)", text))


def compare(original: str, rewrite: str) -> list:
    a, b = inventory(original), inventory(rewrite)
    flags = []
    for category in a:
        for item, n in sorted(a[category].items()):
            m = b[category].get(item, 0)
            if category in LITERAL_FALLBACK and m < n:
                m = max(m, literal_count(item, rewrite))
            if m < n:
                flags.append({"change": "lost", "category": category, "item": item, "original": n, "rewrite": m})
    for category in ADDITION_MATTERS:
        for item, m in sorted(b[category].items()):
            n = a[category].get(item, 0)
            if category in LITERAL_FALLBACK and m > n:
                n = max(n, literal_count(item, original))
            if m > n:
                flags.append({"change": "added", "category": category, "item": item, "original": n, "rewrite": m})
    lead = re.match(r"\s*", original).group(0), re.match(r"\s*", rewrite).group(0)
    trail = re.search(r"\s*$", original).group(0), re.search(r"\s*$", rewrite).group(0)
    if lead[0] != lead[1]:
        flags.append({"change": "changed", "category": "whitespace", "item": "leading", "original": repr(lead[0]), "rewrite": repr(lead[1])})
    if trail[0] != trail[1]:
        flags.append({"change": "changed", "category": "whitespace", "item": "trailing", "original": repr(trail[0]), "rewrite": repr(trail[1])})
    if original.strip() and rewrite.strip():
        ea, eb = line_endings(original), line_endings(rewrite)
        style = lambda e: "CRLF" if e[0] and not (e[1] or e[2]) else "LF" if e[1] and not (e[0] or e[2]) else "CR" if e[2] and not (e[0] or e[1]) else "mixed" if sum(e) else "none"
        if sum(ea) and sum(eb) and style(ea) != style(eb):
            flags.append({"change": "changed", "category": "whitespace", "item": "line endings", "original": style(ea), "rewrite": style(eb)})
    return flags


def read_text(path: str) -> str:
    with open(path, encoding="utf-8", newline="") as f:
        return f.read()


def main() -> int:
    parser = argparse.ArgumentParser(description="Protected-content cue for an Anti-slop rewrite.")
    parser.add_argument("--original", help="file with the original passage")
    parser.add_argument("--rewrite", help="file with the rewritten passage")
    parser.add_argument("--pair", help='JSON file (or - for stdin) with string fields "original" and "rewrite"')
    parser.add_argument("--json", action="store_true", help="print machine-readable JSON")
    args = parser.parse_args()
    try:
        if args.pair:
            data = json.load(sys.stdin if args.pair == "-" else open(args.pair, encoding="utf-8"))
            if not isinstance(data, dict) or not all(isinstance(data.get(k), str) for k in ("original", "rewrite")):
                print("cannot read input: --pair needs a JSON object with string fields original and rewrite", file=sys.stderr)
                return 2
            original, rewrite = data["original"], data["rewrite"]
        elif args.original and args.rewrite:
            original, rewrite = read_text(args.original), read_text(args.rewrite)
            # A file written by an editor often ends with one terminator the passage did not have.
            for t in ("\r\n", "\n", "\r"):
                if original.endswith(t) and rewrite.endswith(t):
                    original, rewrite = original[: -len(t)], rewrite[: -len(t)]
                    break
        else:
            parser.print_usage(sys.stderr)
            return 2
    except UnicodeDecodeError:
        print("cannot read input: not valid UTF-8", file=sys.stderr)
        return 2
    except (OSError, json.JSONDecodeError) as e:
        print(f"cannot read input: {getattr(e, 'strerror', None) or e.__class__.__name__}", file=sys.stderr)
        return 2
    flags = compare(original, rewrite)
    if args.json:
        print(json.dumps({"flags": flags}, ensure_ascii=False, indent=2))
        return 0
    if not flags:
        print("Nothing flagged among the items this script counts. That is not proof of fidelity: read both versions side by side.")
        return 0
    groups = [("lost", "Occur less often in the rewrite (review each; equivalent wording may be fine):"),
              ("added", "Occur more often in the rewrite (an added not, must, number or date can change meaning):"),
              ("changed", "Whitespace changes (matter when the passage joins untouched text):")]
    for change, heading in groups:
        items = [f for f in flags if f["change"] == change]
        if items:
            print(heading)
            for f in items:
                print(f"  {f['category']}: {f['item']!r} {f['original']} -> {f['rewrite']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
