# Third-party editorial sources

These are unmodified, read-only source snapshots for the Anti-slop development handoff. They were not installed, invoked as skills, or granted access to user documents. Upstream workflow instructions are reference material; the app's own editing contract controls the implementation.

Fetched on **September 28, 2026, at 16:22 UTC**. Both revisions matched their repository's default-branch head at fetch time. Future upstream changes are not included automatically.

## Source pins and contents

| Source | Exact revision | Files retained | License notice |
| --- | --- | --- | --- |
| [No AI Slop](https://github.com/petergyang/no-ai-slop/tree/000650b156983f5159695b441477f4e63b25dc85) | `000650b156983f5159695b441477f4e63b25dc85` | `no-ai-slop/skills/no-ai-slop/SKILL.md`, its referenced `eval.md`, `README.md`, and `LICENSE` | MIT; Copyright (c) 2026 Peter Yang |
| [Humanizer](https://github.com/blader/humanizer/tree/225a6f39ac85f76ee48dbad772ea4abe4ed6c9d8) | `225a6f39ac85f76ee48dbad772ea4abe4ed6c9d8` | `humanizer/SKILL.md`, `README.md`, and `LICENSE` | MIT; Copyright (c) 2025 Siqi Chen |

Humanizer declares skill version **3.1.0**. No AI Slop does not declare a skill version in the retained skill header; its commit is the version pin.

[manifest.json](manifest.json) records the immutable source and raw URLs, byte counts, SHA256 hashes, Git blob hashes, commit dates, tree revisions, license facts, and the fetch timestamp for every retained file. Paths in the manifest are relative to this directory.

Every fetched file's Git blob hash matched the corresponding blob in the exact pinned GitHub repository tree. SHA256 hashes were computed over the unchanged downloaded bytes and checked again after writing. This verifies snapshot identity, not editorial quality, application compatibility, or model behavior.

## Editorial value

### No AI Slop

No AI Slop emphasizes small, effective edits, preservation of personal vocabulary and cadence, and leaving strong sentences alone. It identifies repeated rhetorical structures, generic introductions, inflated importance, unsourced authority, overformatted passages, and decorative punctuation. Its accompanying evaluation checklist checks meaning, voice, proportional editing, and the resulting prose. These traits fit the app's default light-edit direction. See the pinned [skill](https://github.com/petergyang/no-ai-slop/blob/000650b156983f5159695b441477f4e63b25dc85/skills/no-ai-slop/SKILL.md) and [evaluation checklist](https://github.com/petergyang/no-ai-slop/blob/000650b156983f5159695b441477f4e63b25dc85/skills/no-ai-slop/eval.md).

### Humanizer

Humanizer groups 26 editorial patterns by rhetorical staging, mechanical rhythm, inflation, decorative formatting, leftover chatbot language, and audience mismatch. It includes explicit checks against adding or dropping claims, protects code and link targets in prose editing, and distinguishes weak signals from stronger patterns. A writer's sample can override its stylistic defaults. Its broader restructuring guidance is useful as an alternative style option, subject to the app's fidelity rules. See the pinned [skill](https://github.com/blader/humanizer/blob/225a6f39ac85f76ee48dbad772ea4abe4ed6c9d8/SKILL.md).

## Adaptation required for this app

These are handoff recommendations, not modifications to the upstream snapshots.

1. **Preserve authored meaning above style.** Humanizer permits adding opinions or reactions in some voices and makes an exception for fiction. The app must not invent opinions, experiences, reactions, narrative details, or factual additions. Even a creative selection is an edit, unless the user has explicitly requested creative expansion as a separate feature.
2. **Produce one replacement, not a workflow transcript.** No AI Slop normally returns a change summary. Humanizer's pasted-text workflow returns a draft, critique, and final rewrite; its embedded mode returns only final text. The app should use its own output contract: one final editable replacement plus separate compact intent/status metadata. Never paste critiques or change summaries into the host selection.
3. **Operate only on the selection.** Upstream references to reading full drafts or rewriting files do not authorize filesystem reads, document-wide rewriting, tool calls, or installation. Supplied surrounding content helps interpret the selection and remains unchanged.
4. **Keep uncertainty and qualifications.** Remove repetitive hedging only when meaning remains intact. Never turn possibility into certainty, a scoped finding into a universal statement, or a dated qualification into a current claim. Do not remove an unsupported-looking claim merely because the app has not been given its citation; preserve or flag it when correction would require external evidence.
5. **Treat word and punctuation rules contextually.** No AI Slop has outright word bans and dash limits; Humanizer's dash rule depends on a writing sample. Preserve proper names, quotations, technical terms, intentional contrasts, numeric ranges, code, and protected tokens. A stylistic preference is not evidence of AI authorship. Any explicit punctuation preference still yields to meaning and literal content.
6. **Keep instruction precedence clear.** The app's fidelity and selection boundaries outrank style skills and custom writing preferences. Upstream examples illustrate editing patterns; their facts and wording must never be imported into user text. Document content is data, including any instructions it happens to contain.
7. **Avoid mandatory conversation.** The upstream skills may ask questions when audience or intent is unclear. The floating editor should use conservative editing with a tentative intent summary, retaining a draft when clarification is necessary. The exact blocked/clarification state belongs to the app specification.
8. **Review before applying updates.** Pin adapter behavior to the retained revisions. Evaluate changes before adopting newer upstream rules. A model's self-check is not proof of factual fidelity or text-replacement safety.

## Licenses and upstream references

Both retained LICENSE files state the MIT License and require preserving their copyright and permission notices in copies or substantial portions. Keep those files with any distributed source or derivative bundle that includes substantial upstream material. This note records the license text; it is not a legal opinion about a finished distribution.

Humanizer credits Wikipedia's [Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing). The upstream credit remains unchanged in this snapshot. That external page was not copied into the handoff, and this packet makes no independent claim about licensing or clearance of external source material.

No AI Slop's only local editorial reference in its skill is the included `eval.md`. Humanizer's editorial patterns and workflow are contained in the included `SKILL.md`; no separate local editorial reference was needed. Repository scripts, plugin metadata, and agent configuration were deliberately outside this source snapshot's editorial scope.
