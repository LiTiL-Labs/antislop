# Development kickoff — Anti Slop Button

## Current product revision — September 30, 2026

The LiTiL Labs revision supersedes the historical profile/custom-instruction/model-control descriptions below. The implemented app lives in `app/`; this is no longer a specification-only checkout.

- One hidden LiTiL Anti-Slop prompt combines the original editor with reviewed No AI Slop and Humanizer guidance. There are no selectable profiles or custom writer instructions. Em-dash removal is always on for editable prose; protected literals and legal meaning remain intact.
- **Intelligence** chooses supported provider model/effort presets: Room Temp, Average, Smart, Genius. **Sentence Complexity** independently chooses Caveman, Plain, Balanced, Polished, Lawyer. These replace raw model/reasoning controls and Simplify wording/Keep my tone.
- Sliders use their native theme below maximum. Genius adds a button-green track, stronger bloom and pixels, and a highlighted box; Lawyer uses orange. At maximum, color and effects fade from 50% alpha on the left to 100% on the right. Native thumbs stay centered and unclipped, and Reduce Motion removes particles. Screen titles use exact orange `#ED692B`; primary buttons use user-specified dark green `#102D23`.
- The **Anti-Slop** Settings title stays pinned above the scrolling controls, just as Done stays pinned below. A resident menu-bar entry reopens Settings. **Launch at login** defaults on and registers through macOS when Done saves settings; registration failures and required OS approval remain visible.
- The Settings footer links **LiTiL Labs - Law bro edition** to `https://litil.ai`. Unchanged MIT notices remain bundled as files; the licenses menu item and window are removed.
- The two keybindings, exact original selection identity, explicit Apply, provider-owned authentication, legal fidelity and no-tool runtime restrictions remain required.

See [app/README.md](app/README.md), [PROMPTING.md](PROMPTING.md) and [app/evidence/litil-revision.md](app/evidence/litil-revision.md) for current behavior and evidence. Historical requirements below apply only where compatible with this revision.


## Authorized task

Implement **Anti-slop**, a new lightweight macOS selected-text editing app, using this package as the canonical specification. The user has finished product exploration and authorized moving into development. Start with a runnable local vertical slice and continue dependency-ready slices through the full required MVP. This brief is self-contained; the linked documents provide details and fixtures.

This directory contains a specification and visual/reference assets, not an existing app. Establish the local development project in the chosen local development workspace; preserve unrelated files and the source handoff. Inspect an existing checkout before assuming it is empty. Do not create or modify an unrelated repository. Record build prerequisites and how to run locally.

## Product to build

A user selects text in a normal Mac text app and presses a personally assigned key. Anti-slop captures the exact selection plus bounded available context, presents a small floating panel adjacent to it, reports actual processing status, and returns a tentative one-line intent and an editable rewrite. The user edits or accepts it, then presses the single primary **Anti-slop** button to replace the original selection with final plain text. Dismiss only after confirmed replacement. Cancel makes no change. Target drift or failure retains the useful draft and never pastes into an unrelated foreground control.

The panel uses a quiet warm off-white shell, white editor, soft corners, fine borders, thin icons, restrained shadows and subtle readable translucency. It enters with a short slide/fade, respecting reduced motion/transparency. Header: title, settings, close. Main body: editable rewrite. Footer: primary action and a quiet hint naming the apply key (the assigned anti-slop key; Command-Return only without one). Ordinary Return inserts a newline. No dashboard, chat log or large toolbar.

Onboarding is the same single settings screen reached later through the gear and an app/menu recovery entry. It includes both AI connections, **Assign anti-slop key**, No AI Slop/Humanizer/None, Simplify wording, Keep my tone, optional writing guide, custom writing instructions and Done. Record whatever supported single key or combination the user chooses; do not limit them to function keys or silently remap. Surface real OS restrictions and known conflicts. Keep a way back to settings without the shortcut.

**Codex and Claude Code are both required first-release providers.** Use official local runtimes with the user's own normal account sign-in; no API-token entry. A first vertical slice may support one before the other, but full MVP cannot omit Claude. Legal professionals are an important audience and specifically use Claude Code. Candidate routes are Codex noninteractive execution and the unmodified official Claude Code CLI; validate current supported invocation, authentication, isolation, structured output and account conditions. Do not extract/intermediate tokens, assume desktop login proves CLI readiness or silently switch to API billing. If a required route fails, report the concrete blocker rather than dropping the provider.

## Internal editing behavior

The agent is a context-aware copy editor, not an AI-authorship detector. Core rules preserve facts, voice, uncertainty, scope, negation, conditions, names/numbers, quotes, URLs and code. For legal writing preserve defined terms, party names, shall/must/may, obligations, permissions, dates, exceptions, citations and cross-references. Do not add legal advice, fact-checking or citation-repair promises. Already-good text may remain unchanged.

The **primary prompt remains internal**. Settings expose **Custom writing instructions**, not a prompt inspector. Compose fixed fidelity/scope/output rules, compatible custom instructions/preferences, optional guide and exactly one reviewed profile. No AI Slop is the recommended default; Humanizer is the alternative; None uses the core only. Curated profile files live in prompts/profiles; unchanged MIT upstream snapshots, revisions and notices live in third_party. Do not execute their full workflows or install them globally.

The model returns only a validated structured proposal. The app owns capture, placement, request cancellation, edit ownership and explicit replacement. Prompt wording is not a runtime security boundary: constrain provider capabilities and prevent ambient tools/hooks/project instructions from gaining access to source documents. Default logs contain no private text or credentials.

## First execution sequence

1. Read [DECISIONS.md](DECISIONS.md), [SPEC.md](SPEC.md), [UX.md](UX.md) and [ARCHITECTURE.md](ARCHITECTURE.md). Review [current visual references](assets/README.md). SwiftUI + AppKit is the recommended native starting point; justify any change.
2. Establish the local build and inspect current supported Codex/Claude Code runtime capabilities without exposing secrets. Choose a documented standard text-control baseline.
3. Build the settings/shortcut/capture/panel/explicit-replacement loop. Use labelled fixtures for development, then prove a real first provider request and real replacement.
4. Complete both required providers, settings persistence, prompt composition and resilience. Follow [IMPLEMENTATION.md](IMPLEMENTATION.md) in dependency order.
5. Run meaningful automated checks and separate live provider/source tests. Use [ACCEPTANCE.md](ACCEPTANCE.md) and [fixtures](fixtures/README.md); record failures and human review distinctly.
6. Deliver a runnable local build, run instructions, evidence and remaining compatibility limits. Keep the status honest: fixture preview is not live inference; generated images are not working UI; API documentation is not end-to-end proof.

Proceed without repeatedly asking to continue. Ask only for a material product choice, required user sign-in/OS approval, unavailable capability or an irreducible block. Continue independent work while sign-in/permission is pending.

## Explicit boundaries

Generic plain-text editing first. Word/PowerPoint were examples, not required first app adapters. Selected desktop files are deferred. No rich-format promise, all-app compatibility claim, Windows build, cloud service, website, billing, analytics, auto-update system, legal-advice feature or public release. No remote push/publish/deploy authority is inferred. Preserve the user-approved simple UX.

## Report back

State what can actually be run, how to run it, which providers/controls were live-tested, which automated checks passed, which fidelity cases failed or passed review, what the user still needs to accept, and any exact blocker. Do not mark MVP complete until both provider choices and the real replacement path meet the recorded acceptance requirements.
