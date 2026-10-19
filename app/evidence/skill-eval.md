# Anti-slop skill — evaluation

> **Historical (October 19, 2026).** This evaluation measured the skill as built for primary prompt 0.2, with its No AI Slop, Humanizer and core-only styles. The skill now carries the consolidated LiTiL prompt 0.3 and the five Sentence Complexity levels, and `evals/evals.json` now holds the 18 cases under Balanced, Caveman and Lawyer. The 0.3 skill has not been evaluated yet, so nothing below describes it.

The skill is `.claude/skills/anti-slop/`. It carries the primary prompt 0.2 instruction body and both reviewed 0.2 profile rule bodies verbatim, kept in step by `scripts/sync-skill.py` and a unit test. The harness that produced these results is in [`scripts/skill-eval/`](../scripts/skill-eval/README.md). Round 3's per-test results and replies are in [live/skill-eval-round3.json](live/skill-eval-round3.json).

| Item | Value |
|---|---|
| Runtime | Official Claude Code CLI 2.1.293, `claude -p`, in the Linux development container, using the CLI's own account sign-in (no API key) |
| Model | The account default; the harness does not choose one |
| Test set | 54 tests: the 18 cases in `fixtures/editorial-cases.json`, each phrased as a person would ask, under No AI Slop, Humanizer and core rules only (`evals/evals.json`) |
| Configurations | **With skill**: a fresh project folder whose `.claude/skills/anti-slop` holds a copy of the skill, so Claude Code decides for itself whether to load it. **Without skill**: the same request in an empty folder. |
| Grading | Blind. Each case's six replies are saved under shuffled letters. A judge and an adversarial fidelity checker read all six; an arbiter settles any disagreement about meaning. Required literals (`must_preserve`) are checked by script against the proposed replacement. |
| Text | Synthetic fixture text only |

## What this shows and what it does not

It shows that, on this corpus, a Claude Code session with the skill installed edits the way the app's contract asks: it keeps meaning and legal wording, leaves good text alone and gives one clean replacement, much more reliably than the same model without the skill. It does **not** show human-judged editorial quality: every grade here is a model's, and the legal cases still need the human review in ACCEPTANCE.md. It does not cover Codex or the Mac app, which are measured separately ([IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md)).

## Results

Three rounds. Each round graded a fresh set of with-skill replies against the same 54 tests. Round 3 is the skill as committed, apart from one later checker fix (see Caveats).

| Round | Skill tested |
|---|---|
| 1 | First draft |
| 2 | The 31 review findings below fixed (among them: checker copies only in a temporary folder; propose before writing to a file), plus round 1's lessons: always read the chosen profile file; a note never suggests example facts or numbers; "make it certain" keeps meaningful hedges |
| 3 | Round 2 plus three rules from round 2's misses: dropping casual tone keeps attribution ("I think" may become "I believe", not vanish); a note is never a change summary; say nothing about process (checker, scratch files, permissions) |

Pass counts out of 54 tests, or 45 for required literals (15 of the 18 cases list them). In round 3 the without-skill replies are round 2's, graded again blind alongside the new with-skill replies.

| Expectation | Round 1 with | Round 2 with | **Round 3 with** | Round 3 without |
|---|---|---|---|---|
| No material change of meaning | 53 | 53 | **54** | 17 |
| Required literals kept exactly | 44/45 | 45/45 | **45/45** | 17/45 |
| Meets the case's own rule | 51 | 51 | **54** | 23 |
| Proportional: good text left alone | 53 | 53 | **54** | 16 |
| No invented facts, numbers or examples | 50 | 52 | **54** | 21 |
| One clean, copyable replacement | 53 | 51 | **54** | 3 |
| No judgment about AI authorship | 54 | 54 | **54** | 53 |
| Mean pass rate | 96.9% | 97.3% | **100%** | 40.4% |
| Judge's quality score (1–5), mean | 4.74 | 4.61 | **4.83** | 2.02 |
| Sessions that loaded the skill | 53 | 53 | **54** | — |

Round 3 cost: about 77,000 tokens per with-skill request against 23,000 without (loading the skill and the profile), and about 0.9 s more time.

Misses by round, with skill:

- **Round 1:** the only fidelity miss was the one session that did not load the skill (`custom_conflict`, which dropped "may"). Three replies wrote out an example figure for the author to add, such as "Search results now load 40% faster" or "improved outcomes in 7 of 10 patients" (use your real figures).
- **Round 2:** `tone_off` removed "I think" from the status-report version; one `legal_citation` reply explained that it had skipped the checker; one `code` session did not load the skill and offered two rewritten code versions. One `legal_permission` judgment was made against the wrong reply: the judge's quoted text belongs to another letter in the same case, so that miss is a grading error.
- **Round 3:** none by the judges.

### A second read of round 3

Every with-skill reply in round 3 was also read directly. No reply changes meaning; every legal clause, citation, negation, quotation, URL, partial selection and the French sentence is preserved. Three replies break the skill's own presentation rules in small ways the judges accepted:

- `no_invented_benchmark` (Humanizer) adds two sentences after the replacement saying the line is vague and could name the area that improved.
- `partial_whitespace` (Humanizer) opens with "I left your selection exactly as it was" and closes with a sentence on why "may" matters, instead of stopping at "No changes needed."
- `legal_obligation` (No AI Slop) writes "Left unchanged." with a note that the clause does not say what must be notified, instead of "No changes needed."

Separately, one `tone_off` reply drops "us" ("could save a considerable amount of time"). This read, like the judges, counts that as part of the requested change to a neutral register.

The three slips are in the wording around the text, not in the text itself, and the rules already forbid them. They were left as they are, so the skill that ships is the one that was tested.

## Triggering

`scripts/skill-eval/trigger-eval.json` holds 20 requests: 10 that should use the skill, phrased without naming it ("my manager says my update sounds like ChatGPT wrote it"), and 10 near-misses that should not (AI detection, new writing, summaries, translation, fact-checking, code cleanup, typo-only proofreading). Each ran three times in a fresh `claude -p` session with the real skill installed, using the same description that ships.

| Requests | Runs that loaded the skill |
|---|---|
| Should trigger (10) | 30/30 |
| Should not trigger (10) | 0/30 |

skill-creator's own `run_eval.py` scored the same set 10/20, because it tests a temporary stand-in command file rather than an installed skill; in that setup the should-trigger requests rarely fired. The installed-skill result is the one that reflects use. All 54 corpus sessions in round 3 also loaded the skill.

## Review of the skill text

While round 1 ran, 41 review agents audited the first draft against the canonical prompt, profiles, contract and composer from four angles (fidelity to the canonical sources, safety, usability and the helper scripts). 31 findings were confirmed: 3 high, 11 medium and 17 low. All were fixed before round 2. The three high findings were the same issue: the optional checker's scratch files would have been written into the user's folder. The checker now runs only on copies in a temporary folder, written with the file tool, never through shell strings.

`scripts/skill-eval/test_skill_scripts.py` is a unit test for the two helper scripts. Among other things, it checks that the validator's keys and limits match `schemas/rewrite-response.schema.json`.

## Caveats

- Model judges, not people. Where judge and checker disagreed on fidelity, an arbiter decided; in round 3 that happened 4 times, all for replies without the skill. One round-2 judgment was made against the wrong reply (see round 2 above).
- One run per test and configuration, on one account default model and one CLI version. The rates are not confidence intervals.
- The optional checker (`protected_terms.py`) rarely ran in these sessions (0, 2 and 1 of 54 runs in the three rounds). The one reply that said why reported that writing a scratch folder needed approval, which non-interactive `claude -p` cannot give. These results therefore measure the instructions alone; the checker is covered by its unit test, not by this evaluation. After round 3 the checker stopped counting a citation signal that opens a sentence ("See Smith v. Jones") as a defined term; that is the only difference between the skill tested in round 3 and the committed one.
- Without skill means a plain session given the same request. It is a baseline for the skill's effect, not a comparison with the Mac app.
- The skill makes the core prompt readable to anyone who has the skill. The app still keeps it internal, as DECISIONS.md requires; share the `.skill` file with that in mind.
