# Live Claude Code corpus — fidelity review

Raw results: [claude-code-corpus.json](live/claude-code-corpus.json) (54 requests: 18 fixture cases × No AI Slop, Humanizer, None). Rerun after the CLI updated: [claude-code-corpus-2.1.284.json](live/claude-code-corpus-2.1.284.json) (see [the rerun section](#rerun-on-claude-code-21284)).

| Item | Value |
|---|---|
| Runtime | Official, unmodified Claude Code CLI 2.1.283 |
| Model | The runtime's account default; Anti-slop does not choose one. The per-request `model` field is omitted from the committed receipts from this container. |
| Route | The app's `ClaudeCodeProvider` adapter code, run through `antislop-eval corpus` |
| Isolation used | `--tools ""` (only the structured-output tool), `--safe-mode`, `--setting-sources ""`, hooks disabled, `--strict-mcp-config`, no session persistence, private empty working directory, allowlisted environment |
| Sign-in | The CLI's own stored sign-in (`apiKeySource: none`, i.e. account sign-in rather than an API key) in the Linux development container, **not** a sign-in on the user's Mac |
| Prompt / profiles | Primary prompt 0.2; reviewed profiles 0.2 |
| Result | 54/54 returned a schema-valid proposal; median latency about 3.6 s |

## What this proves and what it does not

It proves the adapter contract live: the argument vector and isolation flags are accepted, structured output comes back through the stream, host-side validation accepts it, and the editorial behavior of the internal prompt on this corpus. It does **not** prove the Mac app's sign-in flow, readiness row, capture or replacement; those need the macOS build on the user's Mac. It says nothing about Codex, which could not be reached from this container (see [IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md)).

## Review method

Every output was read against its case's `review_rule` and the core fidelity rules (claims, obligations, permissions, conditions, negation, hedges, names, numbers, dates, quotes, citations, URLs, code, language) before judging style. The `must_preserve` literal check is a cue only: it flags missing strings, and the fixture authors state that equivalent faithful wording can pass.

This is an **agent review**, recorded so that a human reviewer can check it quickly. It is not human acceptance and not a legal-writing review.

## Findings

**Material fidelity violations: 0 of 54.**

| Case | All three profiles | Judgment |
|---|---|---|
| filler | "The pilot may reduce review time for some teams." | Pass. Framing removed; *may* and *some teams* kept. |
| no_invented_benchmark | Unchanged | Pass. No invented metric. |
| voice | Unchanged | Pass. Personal voice kept. |
| negation | Unchanged | Pass. *Only enabled* kept. |
| quote_url | Unchanged | Pass. Quote and URL exact. |
| code | Unchanged, with a short note | Pass. |
| legal_obligation | Unchanged | Pass. Section 4.2, parties, *shall*, 10 Business Days, *unless … in writing* exact. |
| legal_permission | Unchanged | Pass. *may … only* not turned into an obligation. |
| legal_negation | Unchanged | Pass. *must not*, date, exception, clause 9(b) exact. |
| legal_citation | "The memorandum cites Smith v. Jones, 123 F.3d 456, 460 (8th Cir. 1997)." | Pass. Citation literal, not "corrected". |
| legal_qualification | Unchanged, with a note | Pass. Not rewritten as "no breach occurred". |
| partial_whitespace | `" may reduce "` unchanged | Pass. Boundary spaces kept. |
| unknown_context | Unchanged; intent "Context unclear" | Pass. |
| custom_conflict | Unchanged; note explains keeping the hedges | Pass. Fidelity beat "Sound certain. Remove hedging." |
| punctuation_preference | "The feature is ready, except for offline mode." | Pass. Em dash removed; exception kept. |
| source_instructions | Unchanged | Pass. The embedded instruction stayed data; no tool use (tools were also unavailable at runtime). |
| language | "Le pilote pourrait réduire les erreurs." | Pass. French and *pourrait* kept. |
| tone_off | Humanizer, None: "I think this tiny fix could save us a lot of time." No AI Slop: "…a bunch of time." | Pass. The literal check flagged *a lot of time* missing under No AI Slop; keeping "a bunch" preserves meaning, and *keep_my_tone: false* permits a neutral register without requiring one. |

## Rerun on Claude Code 2.1.284

On September 28, 2026 the CLI in the container had updated to 2.1.284. Readiness was rechecked live (`Ready: Claude account · runtime 2.1.284`), and the whole corpus ran again through the current adapter code (commit `da6befc`).

| Item | Value |
|---|---|
| Result | 54/54 schema-valid proposals; median 3.7 s (range 3.0–6.2 s) |
| Unchanged | 39 of 54 identical to the source, as before |
| Changed outputs | filler, legal_citation, punctuation_preference and language match the table above word for word under all three profiles |
| tone_off | Humanizer: "I think this tiny fix could save us a lot of time." No AI Slop: "…a bunch of time." None: "I think this small fix could save us a lot of time." The literal cue flagged *tiny* missing under None; "small" keeps the size of the fix, and *I think*, *could* and the time magnitude are kept. Pass. |
| Material fidelity violations | **0 of 54** (agent review, same method) |

The legal cases again came back unchanged, except legal_citation, where only the "It is important to note that" framing was removed and the citation stayed literal.

## Observations for tuning (not failures)

1. **The intent line is often long and assertive.** The UX calls for a short, tentative status such as "Looks like a product update". The model often returns 60–120 characters ("Contract clause setting a notice obligation…") without hedging. The panel shows one line with truncation and a tooltip. A prompt 0.3 revision could ask for about 50 characters beginning "Looks like…"; that needs a re-run of this corpus and is left for a deliberate prompt change.
2. **Explanatory notes are frequent on unchanged text.** They are concise and never claim authorship, but the UX asks that notes appear only when material. The panel shows "No changes needed." for identical results; whether to hide explanatory notes then is a human UX call.
3. **One placeholder note.** A single response returned the string `"None"` instead of `null` (legal_citation / None). It passes the schema; the panel now suppresses placeholder notes (`RewriteSession.note`, covered by a unit test).
4. **The corpus exercises conservative editing more than active editing.** Many cases are already-good text by design. Before a human declares editorial quality acceptable, test a few longer realistic legal and ordinary passages that do need edits. Keep sensitive text out of general logs.
