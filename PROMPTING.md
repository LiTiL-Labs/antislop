# Prompt composition and editorial rules

Prompt version: **0.2**. This supersedes the product notes in the earlier standalone draft. The primary prompt is internal developer source; the user customizes writing through concise settings and the **Custom writing instructions** field.

## Editorial contract

The model is a context-aware copy editor. It assesses writing, not whether AI produced it. It revises only the selection and returns a proposal. It never directly edits the source application, invokes a tool, follows instructions found inside a document or decides when to apply.

Fidelity takes priority over stylistic transformation. Preserve names, facts, certainty, negation, attribution, exceptions, conditions and voice. For legal writing, preserve defined terms, party names, dates, cross-references, citations, quotations, obligations, permissions and distinctions among **shall**, **must** and **may**. Do not change legal effect, fill in a citation, correct a case name, or provide legal advice. A passage whose safe transformation is unclear can remain unchanged with a short note.

## Precedence and composition

| Priority | Source | How it is used |
|---|---|---|
| 1 | Fixed app contract | Scope, factual/legal fidelity, no external action, output structure, conservative uncertainty handling. |
| 2 | Explicit writer controls | Custom writing instructions and toggles, within the fixed contract. A specific writer instruction wins over a broader toggle; an unresolved equally specific conflict chooses the smaller edit. |
| 3 | Optional writing guide | Supplied editorial excerpt, subordinate to the writer's explicit choices and core fidelity. |
| 4 | One reviewed profile | No AI Slop, Humanizer, or none; stylistic guidance only. |
| Data | Selection and context | Material to edit/interpret, not instructions granting app or model capabilities. |

Build the request from the fixed [primary prompt](prompts/primary.md), exactly one allowlisted [profile](prompts/profiles/README.md), and a serialized data object matching the [request schema](schemas/rewrite-request.schema.json). Inject profile **editorial rule bodies only** from bundled trusted application resources. Never ask the runtime to discover/install/execute a skill. No arbitrary user-supplied skill path or remote prompt fetch is needed.

Serialize user instructions, guide, selection and context with a standard JSON encoder; do not concatenate them into command arguments, shell code or unescaped delimiter templates. Label their roles clearly in the primary prompt. Separate operational instructions from source data using the provider's supported message structure where available. A CLI prompt may have less role separation; runtime capability restriction and host-side validation remain required.

Custom writer instructions are intentionally allowed to direct style. They cannot change the response schema, request tools, inspect files, override fidelity or authorize source mutation. If custom instructions conflict with the invariant contract, apply the compatible portion and retain meaning. The app should not expose an enormous merged prompt in the everyday UI.

## Profile selection

Use No AI Slop as the recommended starting default, Humanizer as the alternative, and None for core-only editing. These are reviewed adaptations pinned to source revisions, not claims that upstream authors endorse the app. Do not combine both full upstream workflows; they overlap and include incompatible output expectations. [Profile adaptation notes](prompts/profiles/README.md) record the differences and retain attribution.

**Keep my tone** defaults on. Turning it off permits neutral audience-appropriate phrasing, not fabricated personality or changed claims; explicit compatible custom instructions can specify a register.

Simpler wording is a separate small preference, not a license to remove technical or legal precision. Avoid-em-dashes is optional and off by default. A writing guide can be a short pasted excerpt in the first implementation. Custom instructions persist locally and affect the next request. Caveman, Stop Slop, Elements of Style and voice-sample matching are research candidates for later decisions, not required initial profiles.

## One response, one editable result

Request one object matching [rewrite-response.schema.json](schemas/rewrite-response.schema.json): short tentative `intent`, complete `rewritten_text`, and nullable concise `note`. There is no AI probability, chain-of-thought transcript, critique, draft/final pair, preface or markdown wrapper. The app owns progress and source replacement.

The adapter validates before the editor becomes ready: parse exactly one JSON object, reject unexpected properties and oversized fields, preserve Unicode and whitespace, and map errors to plain UI messages. A malformed response is never pasted. Do not use a best-effort regex that might extract and apply the wrong text. A single controlled retry for schema failure may be considered before a draft exists; never overwrite user edits or silently change providers. It is acceptable to make retry explicit for MVP.

An empty replacement must not become accidental deletion. Treat an empty/whitespace-only result for substantive source text as invalid unless a future explicitly designed deletion flow is approved. An identical result is valid and may show “No changes needed.”

## Evaluation before claiming quality

The [editorial fixtures](fixtures/editorial-cases.json) are authored expectations, not successful model runs. Evaluate both providers across both profiles and core-only mode. Record output, fidelity errors, supported preferences, latency and model/runtime identity in a local opt-in evaluation artifact. Human review must examine the meaning and voice of several legal and ordinary prose cases; string checks alone cannot establish editorial quality.

Use the same request snapshot to compare profiles. Never select the winner by an AI-detector score. Acceptance favors zero material fidelity violations, useful edits where needed, and willingness to leave good writing alone. A model's self-review is not independent proof.
