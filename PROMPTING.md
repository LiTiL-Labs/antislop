# LiTiL Anti-Slop prompt composition

Prompt and current request/settings schema version: **0.3**. Original source snapshots and historical evaluation receipts are unchanged.

## One internal editorial standard

[prompts/primary.md](prompts/primary.md) combines the original copy editor with the reviewed No AI Slop and Humanizer guidance: smallest useful edits, direct wording, proportional pattern checks, natural sentence variety, removal of filler/inflation/formula, and no invented personality or facts. The two old adaptations under `prompts/profiles` are historical provenance, not runtime choices. No upstream skill workflow is executed.

Em dashes are removed from editable prose, using punctuation that preserves the logical relationship. Exact quotations, code, URLs, citations, identifiers and defined terms remain literal. Facts, uncertainty, shall/must/may, obligations, permissions, exceptions, party names, cross-references and conditions always outrank style.

Detection uses [prompts/detect.md](prompts/detect.md), the same consolidated editorial standard with a different response contract. It returns exact quotes and pattern findings only, never a replacement or authorship score. Its separate contract prevents the rewrite instructions from leaking into detection mode.

## Controls and precedence

1. Fixed fidelity, boundaries, literal protection, no-action rules and output contract.
2. **Sentence Complexity**: Caveman, Plain, Balanced (default), Polished, Lawyer. Each value maps to fixed developer-authored guidance. Caveman remains grammatical and faithful; Lawyer permits precise clauses without inventing legal effect or adding filler.
3. Compatible optional pasted style guide, serialized as data.

**Intelligence** is independent of prose complexity. It resolves Room Temp, Average, Smart (default), Genius to models and supported effort levels from the selected account's live catalog. Known Claude families use Haiku / Sonnet / Sonnet / Opus; the two Sonnet levels prefer medium / high effort. Known Codex families use Luna or Mini / Luna or Mini / Sol or Codex / Astra, with low / medium / high / maximum supported effort. The first current catalog entry in the preferred family wins. Missing families fall back within the same provider to an offered model. Unknown catalogs use their advertised default or first model. No unlisted model or unsupported effort is invented, and delegating `ultra` is excluded. The resolved model/effort is visible under the control. Limited catalogs may yield shared presets.

There are no custom writer instructions, profile choices, Simplify wording, Keep my tone or Avoid em dashes switches. Old settings decode without those fields; they never reach a new provider request. Existing provider choices, both keybindings, optional guide and model preferences survive migration; the visible Intelligence preset resolves on Done when the catalog is available. Catalog failure preserves the saved model.

## Runtime and contracts

Canonical prompts are compiled into the binary with `app/scripts/embed-prompts.py`; source correspondence is tested. User source text, nearby context, source hints and guide content stay in safely serialized JSON data. The model never receives native selection handles or authority to replace text. Provider isolation, response validation and explicit host-side Apply remain unchanged.

Schema 0.2 settings and historical corpus inputs decode to the 0.3 contract. New saves omit removed preferences. The evaluator now runs only the `litil` prompt. Its historical fixture expectations concerning custom instructions or tone switches are obsolete; older receipts do not measure this prompt. New corpus results require editorial review, distinct from JSON validation and real replacement tests.

The prompt is hidden in ordinary UI. The previously authorized `--debug-prompts` developer inspector remains the only full-prompt view. MIT notices remain embedded and bundled as license files, accessible from the menu independently of the LiTiL footer link.
