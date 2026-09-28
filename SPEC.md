# Product specification

## Purpose and editorial position

Anti-slop helps a writer remove formulaic filler, repetition, inflated wording and awkward boilerplate while retaining meaning and recognizable voice. Its model acts as a **context-aware copy editor**. It does not determine authorship, calculate an AI score or promise detection avoidance. An em dash is punctuation, not proof of authorship; explicit punctuation preferences may still affect editing.

The product should feel like a small native writing utility. The central experience has one selection, one proposal and one apply action. There is no chat history or dashboard.

## Required first-release behavior

| ID | Requirement |
|---|---|
| P01 | macOS first; selected text inside an app is the input. |
| P02 | A user-assigned supported single key or combination activates the panel. |
| P03 | Capture the original text and identity of its source before the panel takes editing focus. |
| P04 | Use bounded, available nearby text and source hints to infer likely purpose/audience. Missing context remains unknown. |
| P05 | Place a compact floating panel beside the selection when bounds are available, choosing a side with room. |
| P06 | Report truthful progress, then a short tentative intent description and the editable proposed text. |
| P07 | The user can edit the proposal without a later model event overwriting those edits. |
| P08 | **Anti-slop** explicitly applies the final editor contents to the original selection as plain text. |
| P09 | Validate the original target immediately before applying; dismiss only after confirmed replacement. |
| P10 | Close/Escape cancels without changing the source. Failure or stale source retains the useful draft. |
| P11 | First launch opens the same settings screen later available through the panel gear and a persistent app/menu entry. |
| P12 | Settings support connection readiness, shortcut assignment, No AI Slop/Humanizer/None, simpler wording, an optional guide, and custom writing instructions. |
| P13 | The primary prompt is internal and developer-versioned. Normal product UI exposes only concise settings. |
| P14 | Support both Codex and Claude Code through official local runtimes and the user's own normal sign-in; no API-token entry in initial UI. |
| P15 | Preserve legal-professional wording and effects: defined terms, obligations, permissions, party names, dates, conditions, citations and cross-references. |

## Normal journey

1. On first launch, settings shows what is ready and what needs setup. The user assigns a key, connects through the supported runtime's normal sign-in when needed, and optionally changes writing preferences. No separate onboarding wizard.
2. The user selects a passage in another app and presses the assigned key.
3. Anti-slop captures the source and selection. When usable text is captured, the panel appears and reports context reading and rewriting only as those operations occur.
4. A concise line, such as “Looks like a product update,” describes the inferred purpose. If evidence is insufficient, use “Context unclear.” Inferred intent is not presented as certain.
5. The proposed text fills the editor. The user accepts it as-is or edits it. Source text remains unchanged.
6. Clicking **Anti-slop**, or the proposed Command-Return accelerator, revalidates and replaces the exact original selection. Successful verification closes the panel.

## Selection and context boundaries

Only the selected text can change. Nearby material helps interpret tone, references, terminology and grammatical joins; it does not authorize expanding the selection or adding claims found elsewhere. A partial selection must preserve needed leading/trailing whitespace and fit the untouched text on both sides. A confirmed document boundary differs from an unavailable boundary.

Context collection is on demand. Begin with text exposed for the focused editable control, selected range, a small excerpt before/after, app identity, and an available document title/type hint. Do not scan other windows, open the underlying file just because its title is visible, traverse folders, or collect full documents by default. Screenshots/OCR and continuous screen recording are not MVP dependencies. If accessibility supplies only selected text, conservative selected-text-only editing is valid.

No selection, a nontext selection, inaccessible text, or a secure input field produces a clear local message without submitting an empty request. A selection beyond the configured limit is refused with a request to select less; never silently truncate it. The limits are proposed in [ARCHITECTURE.md](ARCHITECTURE.md).

## Fidelity requirements

Preserve facts, names, numbers, units, conditions, exceptions, negation, commitments, chronology, attribution, meaningful hedges, quotes, citations, URLs and technical identifiers. For legal-professional writing, also preserve defined terms, party names, dates, cross-references and distinctions among shall, must and may. Do not alter obligations, permissions or legal effect. The app is an editor, not a legal-advice or citation-verification system. Do not invent personal experiences, opinions, statistics or explanatory details to make text appear human. Keep the original language unless the writer explicitly requests translation. Preserve code; prose/comments may be edited only where their boundary is clear. No code refactoring workflow is required.

Already-good text may return unchanged. A simplification preference may reduce complexity without weakening technical precision. Compression cannot remove a meaningful “may,” “only,” “some,” or condition. Custom writer instructions guide style within these core limits.

## Replacement and recovery

Store a local source snapshot with enough identity to avoid pasting into the newly focused Anti-slop editor or an unrelated app. A return to the source is an implementation step, not proof that the original target is still valid. Verify source identity, editability, selected range/text and available revision evidence before mutation. If any required evidence is unavailable or mismatched, block automatic replacement and preserve the draft.

Prefer native accessibility replacement where actually supported; a conservative clipboard/paste fallback may be implemented only with target validation and verification. Do not retry an uncertain write automatically: the first write may already have succeeded. A failure may offer contextual **Copy draft** and **Select text again** actions; these are recovery controls, not a second primary action in the normal panel. New selection never receives an old draft silently.

For substantive original text, a blank or whitespace-only user-edited draft disables apply with concise feedback. The app rechecks this guard immediately before replacement; deleting source content via an empty rewrite is not an MVP behavior.

Clipboard preservation and source-app undo must be tested on the supported baseline. Full rich text/formatting fidelity and universal app compatibility are not promised.

## Scope exclusions

Deferred: selected desktop files, bulk/batch editing, app-specific integrations, Office-specific behavior, rich text preservation, Windows, cloud backend, billing/subscriptions for this app, analytics, auto-updates, a skill marketplace, arbitrary plugin execution, AI-authorship detection and a public release. A compatible runtime may use cloud inference and consume the user's account allowance; “local runtime” does not mean offline or unlimited.

## Definition of first runnable success

A local Mac build opens settings, registers a supported chosen key, captures plain text from one documented baseline control, obtains a real schema-valid account-backed revision, lets the user edit it, and replaces only the original selection after explicit apply. Cancellation, stale selection and failed apply are demonstrated. Report that exact supported baseline, runtime version, model if observable, and evidence; do not describe this as compatibility with every app. One provider may establish this first runnable milestone; MVP completion requires both Codex and Claude Code to pass the provider and end-to-end criteria.
