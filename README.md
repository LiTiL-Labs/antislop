# Anti-slop — development handoff

Package version 0.2.1 · September 28, 2026 · Project label: **Anti Slop Button**

Build a small Mac app that rewrites selected text in place. A user selects text in another app, presses a personally assigned key, reviews or edits a context-aware proposal in a floating panel, and presses **Anti-slop** to replace only that selection with plain text.

**Codex and Claude Code are both required first-release AI connections**, using supported local runtimes and the user's own normal account sign-in. Legal professionals are an important target audience, so preserved obligations, defined terms and qualifications are acceptance requirements.

This package is the development specification. It contains no working app and makes no claim of a successful live provider request or cross-app replacement. Screens are visual concepts. Fixtures define intended behavior, not measured model results. See [validation status](validation/STATUS.md).

## Start here

1. [DEVELOPMENT_HANDOFF.md](DEVELOPMENT_HANDOFF.md): self-contained execution brief and first deliverable.
2. [SPEC.md](SPEC.md): product requirements and boundaries.
3. [UX.md](UX.md): panel, settings, shortcut assignment, visual treatment, motion and recovery.
4. [ARCHITECTURE.md](ARCHITECTURE.md): recommended native architecture and safety of replacement.
5. [PROMPTING.md](PROMPTING.md): internal prompt, custom instructions and selectable profiles.
6. [IMPLEMENTATION.md](IMPLEMENTATION.md) and [ACCEPTANCE.md](ACCEPTANCE.md): runnable slices and proof requirements.

The latest decisions are explicit: one settings screen is onboarding; **Custom writing instructions** is the user-facing customization field; the core prompt remains internal; **Assign anti-slop key** records the user's chosen supported single key or combination; generic plain text comes first. [DECISIONS.md](DECISIONS.md) records superseded concepts so they do not return during implementation.

For Claude Code, [CLAUDE.md](CLAUDE.md) imports the shared [AGENTS.md](AGENTS.md) instructions directly. The development brief is coding-agent-neutral; Codex and Claude Code remain equally required AI connections in the app. This packaging-only update leaves prompt/schema version 0.2 and all product requirements unchanged.

## Package map

| Location | Purpose |
|---|---|
| [AGENTS.md](AGENTS.md) | Shared project-specific implementation constraints |
| [CLAUDE.md](CLAUDE.md) | Claude Code entrypoint importing the shared instructions |
| [prompts/primary.md](prompts/primary.md) | Versioned internal copy-editor instructions |
| [prompts/profiles/README.md](prompts/profiles/README.md) | Profile selection, adaptation and provenance |
| [prompts/profiles/no-ai-slop.md](prompts/profiles/no-ai-slop.md) | Light-edit default profile |
| [prompts/profiles/humanizer.md](prompts/profiles/humanizer.md) | Alternative pattern-review profile |
| [schemas/README.md](schemas/README.md) | Proposed portable contracts and examples |
| [fixtures/README.md](fixtures/README.md) | Representative editorial and interaction cases |
| [assets/README.md](assets/README.md) | Current visual references and interpretation |
| [third_party/PROVENANCE.md](third_party/PROVENANCE.md) | Pinned upstream source, licenses and checksums |
| [SOURCES.md](SOURCES.md) | Evidence, official references and known limitations |
| [validation/STATUS.md](validation/STATUS.md) | Package checks versus unperformed product validation |

No AI Slop and Humanizer are two **alternative reviewed style profiles**, not two entire autonomous skill workflows stacked together. The original sources and license notices are bundled separately. Selecting no profile still runs the core editor.

Development starts with a local native vertical slice, followed by bounded completion of settings, profiles, context and resilience. Publishing, cloud services, billing, file-selection mode, per-app adapters and rich-format fidelity are outside this handoff.
