#!/usr/bin/env python3
"""Regression tests for the anti-slop skill's two helper scripts.

    python3 app/scripts/skill-eval/test_skill_scripts.py

Stdlib only. Bytecode writing is off so no __pycache__ lands inside the skill.
"""
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
SCRIPTS = ROOT / ".claude" / "skills" / "anti-slop" / "scripts"


def load(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


pt = load("protected_terms")
vr = load("validate_response")


def run(script, *args, stdin=None):
    return subprocess.run([sys.executable, "-B", str(SCRIPTS / script), *args], input=stdin,
                          capture_output=True, text=True, encoding="utf-8")


def flags(original, rewrite):
    return {(f["change"], f["category"], f["item"]) for f in pt.compare(original, rewrite)}


class ProtectedTermsTests(unittest.TestCase):
    def test_identical_fixture_passages_flag_nothing(self):
        cases = json.loads((ROOT / "fixtures" / "editorial-cases.json").read_text(encoding="utf-8"))["cases"]
        for c in cases:
            text = c["request"]["selected_text"]
            self.assertEqual(pt.compare(text, text), [], c["id"])

    def test_lost_negation_and_contractions(self):
        self.assertIn(("lost", "limiter", "not"), flags("The report does not include Q3.", "The report includes Q3."))
        self.assertIn(("lost", "limiter", "not"), flags("We can't ship it.", "We can ship it."))
        self.assertEqual(flags("We won't ship it.", "We will not ship it."), set())
        self.assertIn(("lost", "limiter", "nothing"), flags("Nothing was removed.", "Something was removed."))
        self.assertIn(("lost", "limiter", "non-"), flags("A non-exclusive licence.", "An exclusive licence."))

    def test_modal_swap_is_lost_and_added(self):
        f = flags("The Supplier may notify Acme LLC.", "The Supplier must notify Acme LLC.")
        self.assertIn(("lost", "modal", "may"), f)
        self.assertIn(("added", "modal", "must"), f)
        self.assertNotIn(("lost", "term", "Acme"), f)

    def test_references_and_citations(self):
        self.assertIn(("lost", "reference", "Section 4.2"), flags("Notice under Section 4.2 applies.", "Notice under the contract applies."))
        self.assertIn(("lost", "reference", "§ 12(b)"), flags("See § 12(b).", "See the rule."))
        self.assertIn(("lost", "reference", "Exhibit A"), flags("Attached as Exhibit A.", "Attached below."))
        cite = "Smith v. Jones, 123 F.3d 456, 460 (8th Cir. 1997)."
        self.assertEqual(flags("See " + cite, "The memo cites " + cite), set())

    def test_numbers_dates_and_additions(self):
        self.assertEqual(flags("Deliver by 30 June 2027.", "Deliver by June 30, 2027."), set())
        self.assertIn(("lost", "number", "30"), flags("Pay within 30 days.", "Pay within a month."))
        self.assertIn(("added", "number", "40%"), flags("Search is faster now.", "Search is 40% faster now."))

    def test_urls_quotes_and_terms(self):
        self.assertEqual(flags("Visit https://example.org/a?b=1.", "See https://example.org/a?b=1"), set())
        self.assertIn(("lost", "quotation", '"may be incomplete"'),
                      flags('It says "may be incomplete" here.', "It says it may be incomplete here."))
        f = flags("The Receiving Party may disclose it.", "The recipient may disclose it.")
        self.assertIn(("lost", "term", "Receiving"), f)
        self.assertIn(("lost", "term", "Party"), f)
        self.assertEqual(flags("However, the team shipped.", "The team shipped."), set())

    def test_hedges_and_whitespace(self):
        self.assertIn(("lost", "hedge", "likely"), flags("It will likely help.", "It will help."))
        f = flags(" may reduce ", "may reduce")
        self.assertIn(("changed", "whitespace", "leading"), f)
        self.assertIn(("changed", "whitespace", "trailing"), f)
        self.assertIn(("changed", "whitespace", "line endings"), flags("one\r\ntwo", "one\ntwo"))

    def test_cli_files_pair_json_and_errors(self):
        with tempfile.TemporaryDirectory() as d:
            o, r, bad = Path(d, "o.txt"), Path(d, "r.txt"), Path(d, "bad.txt")
            o.write_bytes("Line one.\r\nIt may help.\r\n".encode())
            r.write_bytes("Line one.\r\nIt helps.\r\n".encode())
            bad.write_bytes(b"\xff\xfe")
            out = run("protected_terms.py", "--original", str(o), "--rewrite", str(r), "--json")
            self.assertEqual(out.returncode, 0)
            self.assertEqual([(f["change"], f["item"]) for f in json.loads(out.stdout)["flags"]], [("lost", "may")])
            same = run("protected_terms.py", "--original", str(o), "--rewrite", str(o))
            self.assertEqual(same.returncode, 0)
            self.assertIn("not proof of fidelity", same.stdout)
            self.assertEqual(run("protected_terms.py", "--original", str(bad), "--rewrite", str(o)).returncode, 2)
        pair = run("protected_terms.py", "--pair", "-", "--json", stdin=json.dumps({"original": "Only enabled accounts.", "rewrite": "Enabled accounts."}))
        self.assertEqual(pair.returncode, 0)
        self.assertIn("only", {f["item"] for f in json.loads(pair.stdout)["flags"]})
        self.assertEqual(run("protected_terms.py", "--pair", "-", stdin="[1]").returncode, 2)
        self.assertEqual(run("protected_terms.py").returncode, 2)


class ValidateResponseTests(unittest.TestCase):
    def ok(self, **overrides):
        obj = {"intent": "Looks like a pilot update", "rewritten_text": "The pilot may help.", "note": None}
        obj.update(overrides)
        return json.dumps(obj)

    def test_limits_and_keys_match_the_response_schema(self):
        schema = json.loads((ROOT / "schemas" / "rewrite-response.schema.json").read_text(encoding="utf-8"))
        self.assertEqual(set(vr.KEYS), set(schema["properties"]))
        self.assertEqual(set(vr.KEYS), set(schema["required"]))
        self.assertFalse(schema["additionalProperties"])
        props = schema["properties"]
        self.assertEqual(vr.LIMITS["intent"], props["intent"]["maxLength"])
        self.assertEqual(vr.LIMITS["rewritten_text"], props["rewritten_text"]["maxLength"])
        self.assertEqual(vr.LIMITS["note"], props["note"]["anyOf"][0]["maxLength"])

    def test_accepts_the_schema_example(self):
        example = (ROOT / "schemas" / "rewrite-response.example.json").read_text(encoding="utf-8")
        self.assertIsNone(vr.validate(example, "It is worth noting that the pilot may reduce review time."))
        self.assertIsNone(vr.validate(self.ok(note="Kept the hedge."), None))

    def test_rejects_shape_problems(self):
        self.assertEqual(vr.validate(self.ok()[:-1] + ', "extra": 1}', None), "unexpected property extra")
        self.assertEqual(vr.validate(json.dumps({"intent": "x", "rewritten_text": "y"}), None), "missing property note")
        self.assertEqual(vr.validate(self.ok(note=""), None), "note is empty")
        self.assertEqual(vr.validate(self.ok(intent=""), None), "intent is empty")
        self.assertEqual(vr.validate(self.ok(note=3), None), "wrong type for note")
        self.assertEqual(vr.validate("[]", None), "response was not exactly one JSON object")
        self.assertEqual(vr.validate("```json\n" + self.ok() + "\n```", None), "response was not exactly one JSON object")
        self.assertEqual(vr.validate("Here it is: " + self.ok(), None), "response was not exactly one JSON object")
        self.assertEqual(vr.validate("{not json", None), "response was not JSON")

    def test_lengths_count_code_points(self):
        astral = "\U0001D538"  # one code point, two UTF-16 units
        self.assertIsNone(vr.validate(self.ok(intent=astral * 160), None))
        self.assertEqual(vr.validate(self.ok(intent=astral * 161), None), "intent exceeds its limit")
        self.assertEqual(vr.validate(self.ok(note="n" * 241), None), "note exceeds its limit")

    def test_blank_replacement_rule(self):
        self.assertEqual(vr.validate(self.ok(rewritten_text="   "), "Real text."), "blank replacement for substantive source")
        self.assertIsNone(vr.validate(self.ok(rewritten_text="   "), "  "))

    def test_cli_exit_codes_never_echo_text(self):
        secret = "Confidential draft sentence."
        out = run("validate_response.py", "-", stdin=self.ok(rewritten_text=secret, extra=1))
        self.assertEqual(out.returncode, 1)
        self.assertNotIn(secret, out.stdout + out.stderr)
        self.assertEqual(run("validate_response.py", "-", stdin=self.ok()).returncode, 0)
        self.assertEqual(run("validate_response.py", "/nonexistent/response.json").returncode, 2)


if __name__ == "__main__":
    unittest.main()
