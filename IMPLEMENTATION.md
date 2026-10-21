# Development slices

## Current product revision — September 30, 2026

The LiTiL Labs revision supersedes the historical profile/custom-instruction/model-control descriptions below. The implemented app lives in `app/`; this is no longer a specification-only checkout.

- One hidden LiTiL Anti-Slop prompt combines the original editor with reviewed No AI Slop and Humanizer guidance. There are no selectable profiles or custom writer instructions. Em-dash removal is always on for editable prose; protected literals and legal meaning remain intact.
- **Intelligence** chooses supported provider model/effort presets: Room Temp, Average, Smart, Genius. **Sentence Complexity** independently chooses Caveman, Plain, Balanced, Polished, Lawyer. These replace raw model/reasoning controls and Simplify wording/Keep my tone.
- Sliders use their native theme below maximum. Genius adds a button-green track, stronger bloom and pixels, and a highlighted box; Lawyer uses orange. At maximum, color and effects fade from 50% alpha on the left to 100% on the right. Native thumbs stay centered and unclipped, and Reduce Motion removes particles. Screen titles use exact orange `#ED692B`; primary buttons use user-specified dark green `#102D23`.
- The **Anti-Slop** Settings title stays pinned above the scrolling controls, just as Done stays pinned below. A resident menu-bar entry reopens Settings. **Launch at login** defaults on and registers through macOS when Done saves settings; registration failures and required OS approval remain visible.
- The Settings footer links **LiTiL Labs - Law bro edition** to `https://litil.ai`. Unchanged MIT notices remain bundled as files; the licenses menu item and window are removed.
- The two keybindings, exact original selection identity, explicit Apply, provider-owned authentication, legal fidelity and no-tool runtime restrictions remain required.

See [app/README.md](app/README.md), [PROMPTING.md](PROMPTING.md) and [app/evidence/litil-revision.md](app/evidence/litil-revision.md) for current behavior and evidence. Historical requirements below apply only where compatible with this revision.


The user authorized moving this product into development. Build a local Mac app from this specification, preserve the scope, and proceed through dependency-ready slices without repeated continuation questions. Do not publish, deploy, push a repository or add a service as an implied part of the local build.

Maintain a short implementation status file with each slice's evidence, known failures and next step. A screenshot, mock provider or fixture-backed preview is never a completed live integration.

## Slice 0 — establish the project and prove constraints

Read the canonical package, inspect the chosen project location and existing state, preserve unrelated files, and choose a justified native build setup. Record macOS/SDK/runtime versions and the first supported text-control baseline. Adopt SwiftUI + AppKit unless concrete evidence supports a simpler suitable alternative.

Verify official runtime presence and supported invocation/auth methods for **both Codex and Claude Code**, without reading credential stores. Recheck current provider documentation where behavior is uncertain. Establish the simplest supported way to constrain capabilities, bypass ambient project instructions/hooks without bypassing authentication, request structured output and cancel work. A provider limitation must be recorded rather than hidden.

Exit: project builds; known choices and provider feasibility findings are recorded. OS permissions or account sign-in may need the user's own action; continue independent UI/core work while that is pending.

## Slice 1 — first runnable local vertical slice

Implement the resident shell, same-screen settings, shortcut recorder, supported key registration, generic plain-text capture, adjacent panel and explicit replacement transaction. Use a clearly labelled fixture provider only to develop the interaction quickly; it must not show a real connection as Ready.

Connect either required real provider first, with a harmless readiness check and a schema-valid rewrite. Demonstrate select → key → progress → editable proposal → explicit apply → verified replacement on one real baseline application. Demonstrate cancel, a deliberately changed original selection and a failed apply that preserves the draft. Keep clipboard and native undo evidence separate.

Exit: a runnable local build and a brief exact walkthrough with the actual provider/baseline tested. This is the first runnable milestone, not full MVP completion.

## Slice 2 — both provider connections and complete settings

Finish the second required provider adapter. Provide separate connection readiness, normal sign-in/Manage and error recovery. Ensure a user's provider choice is honored, not silently substituted. Prove account-backed behavior without accidental API-key billing. No token-entry UI.

Complete persistence and atomic Done behavior for arbitrary supported key/combination (anti-slop and slop-detection keys), Intelligence, Sentence Complexity, optional guide and Launch at login. (Revised September 30, 2026: this replaces No AI Slop/Humanizer/None, Simplify wording, Keep my tone and custom writer instructions.) Remove/reassign a shortcut without losing settings access. Changes affect subsequent rewrites, preserving any current edited draft.

Exit: both providers pass real readiness and rewrite checks; restart preserves settings; selecting each Sentence Complexity level demonstrably changes composition; core prompt remains internal. A Claude Code implementation blocker is an explicit incomplete MVP requirement, never grounds for declaring a Codex-only MVP finished.

## Slice 3 — context, editorial fidelity and resilient transactions

Implement bounded before/after context, unknown-boundary handling, source hints and exact partial-selection preservation. Add schema/size validation, cancellation, duplicate-trigger protection, session/edit revisions, clipboard concurrency and target drift checks. Confirm code/protected quotes are not rewritten.

Run the authored corpus across both providers under the consolidated prompt (before September 30, 2026: across all three profile states). Examine legal defined terms, shall/must/may, obligations, parties, dates, exceptions, citations and cross-references. Investigate all material fidelity failures and revise the prompt conservatively. Meaning violations block completion even when prose sounds smoother.

Exit: meaningful automated checks and a recorded live editorial sample distinguish acceptable alternatives from failures. Tests cover adverse provider and target states, not just the normal example.

## Slice 4 — visual polish and local acceptance

Implement the agreed warm light material, compact editor, placement, short slide/fade and restrained controls. Test actual multi-display/edge placement, dynamic text, keyboard focus, screen-reader labels, Reduce Motion and Reduce Transparency. Keep final draft visible on error; hide only after confirmed success or explicit dismissal.

Review a real end-to-end build against [ACCEPTANCE.md](ACCEPTANCE.md). Provide a local run/build command, supported baseline list, test results and a concise human acceptance guide. Do not treat the generated comps as completed UI or motion validation.

Exit: full required MVP demonstrated locally, with residual compatibility limits stated. Public packaging, signing/notarization beyond local needs and release distribution are separate work.

## Validation discipline

Write meaningful tests for state transitions, target verification, schema validation, prompt composition and data-preservation boundaries. Avoid tests that only repeat strings in implementation. Use a deterministic adapter for app-state cases, then separate live-provider runs for each runtime. Avoid needless repeated account-consuming evaluation once relevant checks pass, unless code/prompt changes or failures justify it.

Use real text-control and external-app checks for capture/replace; mocks cannot prove accessibility behavior. Use human review for voice, editing quality, legal effect and motion. Persist sanitized receipts with exact runtime/model and build information, without copying private source content to general logs.
