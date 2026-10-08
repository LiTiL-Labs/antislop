#!/usr/bin/env python3
"""Check an Anti-slop response object against the response contract (0.2).

Mirrors the app's host-side validator: exactly one JSON object with exactly
the keys intent, rewritten_text and note; intent 1-160 characters; note null or
1-240 characters; rewritten_text 1-40,000 characters; and a passage with real
content never comes back blank. Lengths count Unicode code points. Text
wrapped in prose or a code fence is rejected rather than extracted, so the
wrong text can never be applied.

    python3 validate_response.py response.json [--original original.txt]
    cat response.json | python3 validate_response.py - [--original original.txt]

Exit status: 0 valid, 1 invalid, 2 usage error. Messages never echo the text.
"""
import argparse
import json
import sys

LIMITS = {"intent": 160, "rewritten_text": 40000, "note": 240}
KEYS = ("intent", "rewritten_text", "note")


def validate(raw: str, original: "str | None") -> "str | None":
    trimmed = raw.strip()
    if not trimmed:
        return "response was not JSON"
    try:
        obj = json.loads(trimmed)
    except json.JSONDecodeError:
        return "response was not JSON" if trimmed.startswith("{") else "response was not exactly one JSON object"
    if not isinstance(obj, dict):
        return "response was not exactly one JSON object"
    for key in sorted(obj):
        if key not in KEYS:
            return f"unexpected property {key}"
    for key in KEYS:
        if key not in obj:
            return f"missing property {key}"
    intent, rewritten, note = obj["intent"], obj["rewritten_text"], obj["note"]
    if not isinstance(intent, str):
        return "wrong type for intent"
    if not isinstance(rewritten, str):
        return "wrong type for rewritten_text"
    if note is not None and not isinstance(note, str):
        return "wrong type for note"
    if intent == "":
        return "intent is empty"
    if len(intent) > LIMITS["intent"]:
        return "intent exceeds its limit"
    if rewritten == "":
        return "rewritten_text is empty"
    if len(rewritten) > LIMITS["rewritten_text"]:
        return "rewritten_text exceeds its limit"
    if note is not None:
        if note == "":
            return "note is empty"
        if len(note) > LIMITS["note"]:
            return "note exceeds its limit"
    if original is not None and rewritten.strip() == "" and original.strip() != "":
        return "blank replacement for substantive source"
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate an Anti-slop response object.")
    parser.add_argument("response", help="JSON file, or - for stdin")
    parser.add_argument("--original", help="file holding the original passage (enables the no-blank rule)")
    args = parser.parse_args()
    try:
        raw = sys.stdin.read() if args.response == "-" else open(args.response, encoding="utf-8").read()
        original = open(args.original, encoding="utf-8").read() if args.original else None
    except OSError as e:
        print(f"cannot read input: {e.strerror}", file=sys.stderr)
        return 2
    except UnicodeDecodeError:
        print("cannot read input: not valid UTF-8", file=sys.stderr)
        return 2
    problem = validate(raw, original)
    if problem:
        print(f"invalid: {problem}")
        return 1
    print("valid Anti-slop response")
    return 0


if __name__ == "__main__":
    sys.exit(main())
