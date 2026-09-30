# Decisions and superseded proposals

Version 0.2 reflects the final direction in the September 28 conversation. Explicit user corrections override earlier discussion, screenshots and the historical prompt draft.

## Committed product choices

| Decision | Rationale or boundary |
|---|---|
| Mac first; selected in-app text first | Files selected on the desktop are a possible later extension. |
| Generic plain-text replacement | Word and PowerPoint were examples, not initial app-integration deliverables. |
| Context-aware copy editor | Improve prose without claiming AI detection or changing facts. |
| Floating, editable preview with explicit Anti-slop apply | The user can edit the proposal before committing it. |
| One settings screen serves onboarding and later preferences | Keep setup and daily use small and consistent. |
| Arbitrary supported chosen key or combination | The user chooses what key gets overridden, subject to real OS constraints. |
| Core prompt stays internal; custom writing instructions are exposed | Keep the product simple while giving the writer useful control. |
| No AI Slop and Humanizer are the two requested style references | Final two-profile interpretation of the recommendation discussion; No AI Slop recommended by default. |
| Slop-detection mode on its own assigned key (September 30) | Lists the passages that read as filler, inflation or formula, each quoted exactly from the selection with the pattern named. It never proposes or applies text and never scores or guesses authorship. The panel's **Anti-slop** button (or the anti-slop key) rewrites that same selection. |
| Any key can be assigned, including a modifier key on its own (September 30) | Right ⌥, Fn, Caps Lock and similar keys trigger on a lone press and release. Real OS limits still apply: Fn/Globe combinations and hardware media keys cannot be assigned. |
| The anti-slop key also applies inside the panel (September 30) | Pressing the same key again applies the ready rewrite, replacing the proposed Command-Return accelerator. Command-Return applies only when no key is assigned. |
| Model and reasoning level are chosen in settings (September 30) | Choices come from the connected runtime's own list (Claude Code's initialize handshake, `codex debug models`), are saved per connection, and default to the runtime's own default. Codex's delegating "ultra" level is not offered because Anti-slop's isolation disables sub-agents. |
| Both Codex and Claude Code account-backed local runtimes, no token-entry setup | Claude Code is a required first-release option, reflecting the legal-professional audience; desktop installation alone does not prove callable access. |

## Explicit reversals: do not revive these

- **Full prompt viewer / “View instructions” drawer:** superseded by the user's request for a custom writer-instructions text box. Do not implement a raw primary-prompt inspector in ordinary settings. The one exception, requested on September 30, is a developer-only debug window behind the `--debug-prompts` launch flag, which shows the full prompt and raw model response in memory only.
- **Spare function keys as the assigned-key model:** superseded by “Assign anti-slop key” recording the user's chosen supported key or combination. Function keys are examples of possible keys, not a whitelist.
- **Natural / Plain English / Caveman as the final preset trio:** earlier visual exploration only. The package's reviewed style profiles are No AI Slop and Humanizer. Simpler wording is a small separate preference. Caveman is a future candidate requiring adaptation.
- **App-specific Word/PowerPoint proof as the first gate:** superseded by a generic plain-text baseline. Do not block the first runnable slice on Office automation or rich-format fidelity.
- **Detecting AI authorship:** not the adopted editorial role. Punctuation and writing patterns do not justify an authorship score. Slop-detection mode (above) flags writing patterns only; it is not authorship detection and has no score.
- **Command-Return as the apply accelerator, and the assigned key typing normally inside the panel:** superseded on September 30 by the anti-slop key applying inside the panel.
- **Historical settings image and prompt v0.1 product notes:** retained outside this package as earlier artifacts, but noncanonical. Use the revised settings image and current documents here.

## Recommended engineering defaults

These are proposed implementation choices, not additional user quotes: SwiftUI plus AppKit; a compact menu-bar recovery entry; Codex CLI and the unmodified Claude Code CLI as required provider adapters; one active rewrite; one profile at a time; the anti-slop key applies inside the panel (Command-Return only without a key); ordinary Return newline; Escape dismiss; local preferences with Done commit; bounded context; a pasted guide excerpt; suppress the global trigger while Anti-slop is active.

The first implementation may refine a default when evidence shows a simpler or more reliable option. Record the reason and update affected docs without reopening already settled product choices.

## Open choices to resolve through implementation

| Choice | Next useful evidence |
|---|---|
| Supported macOS baseline and build target | Inspect available Xcode/SDK and choose the smallest justified deployment requirement. |
| Exact shortcut interception API and permission needs | Prototype single-key and modified-key capture/registration; verify conflict and input-focus behavior. |
| Baseline capture and replacement capabilities | A native standard text control plus one real external plain-text application. |
| Safe Codex runtime configuration | Verify current installed binary, auth readiness, structured output, bounded capabilities, cancellation and data retention behavior. |
| Model and timeout/size budgets | Measure a small representative corpus on an available account model; do not hard-code an unsupported model. |
| Claude Code connection implementation | Required for MVP. Validate the official unmodified-runtime route, own-account sign-in, permitted credential use, billing and capability restrictions; surface a concrete blocker if it fails. |
| Packaging/signing | Local development first. Public distribution is a separate authorization and readiness decision. |

None of these requires postponing the shell/fixture preview. Real-provider and real-replacement milestones remain explicitly unverified until tested.
