# Anti-slop skill 0.3: evaluation

This is the first live evaluation of the skill as ported to the consolidated LiTiL prompt 0.3, with its five Sentence Complexity levels and constant em-dash removal. The earlier prompt 0.2 evaluation ([skill-eval.md](skill-eval.md)) is kept as a historical record. The harness is in [`scripts/skill-eval/`](../scripts/skill-eval/README.md). Per-test results, expectations and every reply are in [live/skill-eval-0.3.json](live/skill-eval-0.3.json).

| Item | Value |
|---|---|
| Skill tested | `.claude/skills/anti-slop/` at commit `89e5610` (branch `claude/anti-slop-skill`): prompt 0.3's instruction body and the five Sentence Complexity levels, verbatim. `sync-skill.py --check` and the 14 helper-script unit tests passed beforehand. |
| Date | October 19, 2026 |
| Runtime | Official Claude Code CLI 2.1.303, `claude -p`, on macOS (Darwin 27.0.0), signed in with the CLI's own claude.ai account sign-in (`apiKeySource: none`, no API key) |
| Environment | The runner was started under `env -i` with only `HOME`, `USER`, `LOGNAME`, `SHELL`, `LANG`, `TMPDIR` and `PATH`. Without that, the harness would have passed the Claude desktop app's session variables (such as its effort setting and host sign-in channel) to every test session. Each session used the CLI's own sign-in, default model and default effort. |
| Model | The CLI default; the harness does not choose one. A probe session run just before the evaluation reported `claude-opus-5-5`. The harness does not record the model per session. |
| Test set | 54 tests: the 18 cases in `fixtures/editorial-cases.json`, each phrased as a person would ask, at Balanced, Caveman and Lawyer (`evals/evals.json`). Plain and Polished were not tested. |
| Configurations | **With skill**: a fresh project folder whose `.claude/skills/anti-slop` holds a copy of the skill, so Claude Code decides for itself whether to load it. **Without skill**: the same request in an empty folder. Both had the same tools. |
| Grading | Blind. Each case's six replies were saved under shuffled letters. A judge and an adversarial fidelity checker read all six, and an arbiter settled any disagreement about meaning. Required literals (`must_preserve`) were checked by script against the proposed replacement. All grader agents ran on `claude-opus-5-5` through Claude Code's Workflow tool. |
| Text | Synthetic fixture text only |

## What this shows and what it does not

On this corpus, a Claude Code session with the 0.3 skill installed edits much more the way the app's contract asks than the same model without the skill. It keeps meaning and legal wording, leaves good text alone, invents nothing and gives one clean replacement. That held in 48 of 54 tests on every expectation, against none of 54 without the skill. It does **not** show human-judged editorial quality: every grade here comes from a model, and the legal cases still need the human review in ACCEPTANCE.md. It doesn't cover Codex or the Mac app, which are measured separately ([IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md)).

## Results

Pass counts out of 54 tests (18 per level), or out of 45 for required literals, because 15 of the 18 cases list them.

| Expectation | **With skill** | Without skill |
|---|---|---|
| No material change of meaning | **51** | 13 |
| Required literals kept exactly | **40/45** | 13/45 |
| Meets the case's own rule | **51** | 20 |
| Proportional: good text left alone | **53** | 11 |
| No invented facts, numbers or examples | **53** | 15 |
| One clean, copyable replacement | **53** | 3 |
| No judgment about AI authorship | **54** | 54 |
| Tests passing every expectation | **48** | 0 |
| Mean pass rate | **96.3%** | 34.6% |
| Judge's quality score (1–5), mean | **4.61** | 2.02 |
| Sessions that loaded the skill | **53** | — |

By Sentence Complexity level, with skill / without skill:

| Expectation | Balanced | Caveman | Lawyer |
|---|---|---|---|
| No material change of meaning | 17 / 6 | 16 / 4 | 18 / 3 |
| Required literals kept exactly (of 15) | 14 / 5 | 13 / 5 | 13 / 3 |
| Meets the case's own rule | 17 / 9 | 17 / 4 | 17 / 7 |
| Proportional: good text left alone | 17 / 5 | 18 / 5 | 18 / 1 |
| No invented facts, numbers or examples | 17 / 4 | 18 / 10 | 18 / 1 |
| One clean, copyable replacement | 17 / 0 | 18 / 3 | 18 / 0 |
| No judgment about AI authorship | 18 / 18 | 18 / 18 | 18 / 18 |
| Mean pass rate | 95.2% / 37.7% | 96.0% / 39.6% | 97.5% / 26.6% |
| Judge's quality score, mean | 4.61 / 2.17 | 4.56 / 2.22 | 4.67 / 1.67 |

Without the skill, the usual failures are a change summary or critique around the edit, extra alternative versions, and suggested example figures or names (for example "review time dropped about 30% for the Payments and Search teams"). Asked to "make it sound certain", all three replies without the skill dropped "may". Those plain sessions answered as a helpful writing assistant; they were never told the app's rules, so the gap measures what the skill adds, not a flaw in the baseline.

Cost: the median with-skill session used about 57,000 tokens against 24,000 without. The extra turn that loads the skill accounts for the difference. Median time was 5.5 s with the skill and 6.2 s without, because the with-skill replies are shorter. All 108 sessions exited cleanly.

### Misses with the skill

Six of the 54 with-skill tests missed at least one expectation:

- **`custom_conflict`, Balanced** ("Make it sound certain. Remove hedging."): the only session that did not load the skill. It dropped "may", changed "some cases" to "some patients" and offered an example with "40% of patients". The same case was the one session that skipped the skill in the 0.2 evaluation's first round. The Caveman and Lawyer versions of the request loaded the skill and kept the passage unchanged with a note.
- **`quote_url`, Caveman**: `The report says "may be incomplete." See https://example.org/a?b=1.` The period moved inside the quotation marks, so the quoted text is no longer exact. The judges counted this as a change of meaning, a broken case rule and a missing literal.
- **`legal_qualification`, Caveman**: "we have not identified evidence of a material breach" became "we found no evidence of a material breach", and "Based solely on" became "Based only on". Both judges read "found no evidence" as a more definite finding than the original's negative assurance.
- **`legal_qualification`, Lawyer**: "Based solely on the documents reviewed" became "On the basis solely of the documents reviewed". The judges found no change of meaning, so this miss is the required literal only. The edit is still unneeded: the Balanced reply correctly left the sentence alone.
- **`voice`, Lawyer**: "I loved how weird the ending was." became "I loved the strangeness of the ending." The case rule asks to keep personal voice; the Balanced and Caveman replies left it unchanged.
- **`punctuation_preference`, Lawyer**: "Except for offline mode, the feature is ready." The judges found the meaning intact. The miss comes from the literal check, which is case-sensitive and looks for "except for offline mode".

Four of these misses are Caveman or Lawyer edits to text that the same skill left alone at Balanced. The level guidance says already-good sentences may stay unchanged, but at those two levels the model sometimes rewrote them anyway.

### A second read of the with-skill replies

Every with-skill reply was also read directly, outside the grading. Apart from the misses above, no reply changes meaning. Every legal clause, citation, defined term, negation, URL, the partial selection with its boundary spaces, the code and the French sentence came back intact. No reply mentions the checker, scratch files or permissions, and no session called any tool other than the skill itself. Some replies break the skill's own presentation rules in small ways the judges accepted:

- `legal_negation`, Balanced writes "No changes needed." and then adds a sentence saying why, instead of stopping there.
- `custom_conflict`, Lawyer follows "Left unchanged." with a three-sentence note; the rule allows one.
- `unknown_context`, Lawyer writes "I've left it unchanged." instead of "Left unchanged.".
- `legal_obligation`, Lawyer leaves the clause unchanged with a note that it doesn't say what must be notified. That is accurate, but the clause needed no note.
- `source_instructions`, Balanced gives the intent "Looks like an instruction to someone revising files." The passage is a sentence reporting that a draft contains that instruction. The reply correctly treated the quoted direction as text and took no action.

In `tone_off` all three replies keep the author's attribution ("I think" or "I believe") and "could". "Tiny" became "small" or "minor", and "a bunch of time" became "a lot of time", "considerable time" or "a considerable amount of time". The judges accepted these as the neutral register the request asked for.

## Grading notes

- Judge and checker disagreed about meaning five times, all for replies without the skill, and an arbiter decided each one.
- The first judge for `custom_conflict` returned entries for only two of the case's six replies (the grading schema does not require all six). The whole case was graded again with the same unchanged script: one judge and one checker, which agreed on every reply. The second grading is the one recorded for all six replies. Every other case's judge covered all six. For each judged reply, the judge's quoted replacement was checked against that reply's own text to confirm no letters were mixed up.
- In total: 41 grading agents in the main pass and 2 in the re-grade.

## Comparison with the 0.2 evaluation

The 0.2 skill's final round scored 100% with the skill and 40.4% without ([skill-eval.md](skill-eval.md)). These numbers are not directly comparable. The prompt, the style settings (three profiles then, three Sentence Complexity levels now), the CLI version, the platform, the default model and the without-skill replies all differ, and each figure comes from one run.

## Caveats

- Model judges, not people. The graders ran on the same model as the sessions they graded, so a shared bias is possible. Human review of meaning and voice, especially on the legal cases, is still required before claiming editorial quality.
- One run per test and configuration, on one model, one CLI version and one account. The rates are not confidence intervals; a single changed reply moves a count by one.
- Triggering was measured only through these 54 sessions (53 loaded the skill). The 20-request `trigger-eval.json` set was not rerun for the 0.3 description.
- The optional checker (`protected_terms.py`) ran in none of the 54 with-skill sessions. These results measure the skill's instructions alone; the checker is covered by its unit test.
- The required-literal check is an exact, case-sensitive substring match, so a sentence-initial capital ("Except") counts as a miss even when nothing else changed.
- Both configurations ran with this account's own user-level skills, plugins and hooks present. Those were the same for both configurations.
- "Without skill" means a plain session given the same request. It is a baseline for the skill's effect, not a comparison with the Mac app.
