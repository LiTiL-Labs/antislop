# macOS runner evidence

Source: the `macOS build and checks` workflow ([`.github/workflows/macos.yml`](../../.github/workflows/macos.yml)) on branch `claude/anti-slop-macos-dev-ay9m4k`, job `build-and-check`. The first 15 TextEdit checks and the first 7 app checks were identical on runs 3, 4, 6, 7, 10 and 17. The key, recorder and editing checks were added in runs 13–17. Latest full pass: run 19, commit `7e67374` (run 17, commit `a519bd2`, was identical).

| Item | Value |
|---|---|
| Runner | GitHub-hosted `macos-15-arm64` image 20260907.0337 |
| macOS | 15.7.9 (24G830) |
| Toolchain | Xcode 16.4, Apple Swift 6.1.2, target arm64-apple-macosx |
| Build | `swift build -c release`: every target, including the AppKit/SwiftUI/Accessibility layer, compiles |
| Unit tests | `swift test`: 82 tests, 0 failures (the same suite also passes on Linux, Swift 6.1.3) |
| Baseline app | TextEdit, plain-text document (AppKit `NSTextView`) |

These runs use synthetic text only. The full-app checks use the labelled **fixture provider**, so they prove the interaction and replacement path, not a live AI connection. Key presses are synthetic HID events posted by the probe on the runner's US layout, not a person at a physical keyboard. The runner grants Accessibility to the probe process, so the first-run permission prompt is not tested either.

## TextEdit probe (`antislop-axprobe textedit`): same capture and replace code as the app

| Check | Result | Detail |
|---|---|---|
| accessibility_trusted | PASS | process is trusted |
| open_textedit | PASS | focused element role AXTextArea |
| capture_exact_selection | PASS | selected text matched exactly |
| capture_context | PASS | before and after are known excerpts ("Intro sentence stays. " / " Closing sentence stays.\n") |
| capture_bounds | PASS | selection bounds 443×13 pt |
| capture_source_hint | PASS | app TextEdit, title `anti-slop-probe-a.txt`, type "plain text document" |
| replace_confirmed | PASS | Accessibility `AXSelectedText` write, confirmed by reading back |
| replace_surroundings_intact | PASS | whole document equals the expected splice |
| undo_restores_original | PASS | ⌘Z restored the original after the Accessibility write |
| drift_selection_blocks | PASS | `blocked(selectionChanged)`, document untouched |
| drift_text_blocks | PASS | `blocked(textChanged)` after an edit elsewhere in the document |
| drift_focus_blocks | PASS | `blocked(focusMoved)`; the unrelated document and the original are both intact |
| paste_fallback_confirmed | PASS | clipboard-and-⌘V fallback confirmed by read-back |
| paste_fallback_restores_clipboard | PASS | the prior clipboard (a sentinel) was restored |
| partial_selection_exact | PASS | a mid-word selection ("ilo" in "pilot") and a span with a boundary space at each end (" may reduce ") were each captured exactly and spliced exactly (A14) |
| app_closed_blocks | PASS | `blocked(appClosed)` after TextEdit quit |

## Full app (`antislop-axprobe e2e`): real bundle, real hotkey, fixture provider

| Check | Result | Detail |
|---|---|---|
| e2e_launch | PASS | `Anti-slop.app` launched with a settings file assigning ⌃⌥⌘J |
| e2e_panel_appears | PASS | real HID key events triggered the Carbon hotkey; the floating panel appeared |
| e2e_escape_no_change | PASS | Escape closed the panel; the document was unchanged |
| e2e_apply_replaces_selection | PASS | ⌘Return applied the draft; only the selection changed |
| e2e_panel_closes_after_apply | PASS | the panel dismissed after confirmed replacement, and the app is still running |
| e2e_settings_without_key | PASS | with no key assigned, launch opened the settings screen |

### Key assignment on the real settings screen (A04, A05)

| Check | Result | Detail |
|---|---|---|
| recorder_records_combination | PASS | **Assign anti-slop key**, then ⌃⌥⌘K: "Current key: ⌃⌥⌘K" and "…is ready to use after you choose Done." |
| recorder_refuses_invalid_keeps_previous | PASS | Fn+J was refused with the Fn/Globe explanation; ⌃⌥⌘K stayed assigned |
| recorder_cancel_keeps_previous | PASS | **Cancel** during recording kept ⌃⌥⌘K |
| done_saves_new_key | PASS | **Done** wrote `key_code 40` with command, control and option to the settings file |
| new_key_triggers | PASS | the newly assigned ⌃⌥⌘K opened the panel from TextEdit |

### Unmodified single-key trigger and editing in the panel (A03, A06, A28, A30)

The app was relaunched with `` ` `` (grave accent, no modifiers) as its key.

| Check | Result | Detail |
|---|---|---|
| single_key_triggers | PASS | pressing `` ` `` in TextEdit opened the panel; TextEdit received no character (A03) |
| held_key_one_activation | PASS | the key held with auto-repeat, then released: one panel, and the draft contains no repeated characters (A06) |
| assigned_key_types_in_panel | PASS | inside the panel, `` ` `` typed normally; keyboard focus stayed in the draft editor (A06) |
| return_inserts_newline | PASS | Return added a newline and did not apply; the editor read `"Edited by hand`\nsecond line."` (A28) |
| edited_draft_applied_once | PASS | ⌘Return put exactly that edited draft over the selection, once (A28, A30) |
| panel_closes_after_edited_apply | PASS | the panel closed and the app kept running |
| key_triggers_again_after_panel | PASS | back in TextEdit the key opened the panel again, so the trigger resumed after the panel closed (A06) |
| blank_draft_not_applied | PASS | with the editor emptied, ⌘Return changed nothing and the panel said "Enter replacement text to apply." (A28) |
| typing_continues_after_blocked_apply | PASS | typing right after the refused apply went into the editor |
| escape_after_edits_no_change | PASS | Escape closed the panel and left the document unchanged (A27) |

## Full app, live mode, with stub runtimes (`e2e --live`): not live AI

This step puts two clearly labelled stub CLIs ([`scripts/ci/fake-claude`](../scripts/ci/fake-claude), [`fake-codex`](../scripts/ci/fake-codex)) in `~/.local/bin`, where the app's runtime discovery looks. The real app then goes through its real provider path: discovery, version and `--help` checks, readiness, the isolated invocation, the stream or event guard, response validation, the panel, and verified replacement. It shows the in-app plumbing for both providers works. It says nothing about live model quality, sign-in or network behavior.

| Check | Claude Code stub | Codex stub |
|---|---|---|
| e2e_launch, e2e_panel_appears, e2e_escape_no_change | PASS | PASS |
| live_proposal | PASS: "The pilot may reduce errors for some teams (stub)." | PASS: "… (codex stub)." |
| live_apply_replaces_selection | PASS: only the selection changed | PASS: only the selection changed |
| live_panel_closes_app_keeps_running | PASS | PASS |

Finding and fix: on its first run (run 9, commit `cd96e93`) this step failed because runtime discovery rejected the stub's version string `0.0.0-stub`. The version parser accepted only all-numeric versions, so a real pre-release Claude Code or Codex build (for example `0.160.0-alpha.2`) would also have been reported as incompatible. The parser now keeps semver pre-release and build suffixes, a unit test covers it, and run 10 (commit `15db632`) passed. When no proposal appears, the probe now records the panel's own status text, so a failed live run explains itself.

## Defects these checks found and fixed

1. **Crash after every confirmed replacement (fixed in `a519bd2`).** After a confirmed apply, the app closed its panel from inside the session-change callback. Closing cancelled the session, and cancelling a finished session still sent a change notification. The callback saw the same succeeded session and closed again, recursing until the stack overflowed. The replacement had already been written and verified, so the earlier checks passed ("panel closed" was really "process gone"). A user would have seen Anti-slop quit after each successful replacement. It showed up when the single-key probe pressed the key again after an apply: the key reached TextEdit, and the app's lifecycle log stopped at the apply. `SessionCoordinator.cancel()` now notifies only on a real change, a unit test reproduces the pattern (it fails on the old code with 50 notifications), `closePanel` cancels only active work, and every "panel closed" check now also requires the app to be running, in live runs too.
2. **Held single-key trigger could type into the draft (fixed in `e718847`).** The key is unregistered while Anti-slop is active, so a held key's auto-repeat reached the panel. The panel now drops the trigger key's auto-repeat and release until the key comes up or another key is pressed.
3. **Pre-release runtime versions rejected (fixed in `15db632`).** See the stub section above.
4. **Invisible active state after closing (hardened in `81cbb20`, `7e67374`).** If Anti-slop is still the active app with no panel or settings window after the panel closes, it now hides itself, so the previous app returns and the trigger resumes. Every place that brings Anti-slop forward unhides it first, so a later panel is never ordered front inside a hidden app. Doing the same after settings close stalled run 18 and was reverted. The app logs content-free lifecycle lines (trigger result, suspend/resume status, focus return) that CI prints.

Probe-only problems fixed along the way: the typed-text events inherited a stale Command flag (so "h" hid the app), SwiftUI plain-style buttons are found by their press action, and the menu-bar item's window is no longer counted as a panel.

## Rendered UI (Vision OCR and sampled colors of real screenshots)

The app renders its own windows when `ANTISLOP_SNAPSHOT_DIR` is set (developer/CI only), and `screencapture` also captures the panel window. `scripts/inspect-shots.swift` OCRs each image and samples colors. Run 6:

| Surface | Text found (top to bottom) | Colors sampled |
|---|---|---|
| Panel, generating (430×340 pt) | "Anti-slop", close ✕, spinner "Rewriting…", "⌘ Return to apply", "Anti-slop" button | shell #F8F7F5 (token #F7F6F3 over material), editor #FFFEFF, button #CDCDC9 (disabled) |
| Panel, ready (430×317 pt) | "Anti-slop", "Fixture: looks like plain te…" plus the "Fixture preview — not live AI" badge, the draft, the fixture note, "⌘ Return to apply", "Anti-slop" button | shell #F8F7F5, editor #FFFEFF, button #292928 (enabled, near-black) |
| Settings (540×644 pt, top of scroll) | "Settings", "Keyboard shortcut", "Not set", "Assign anti-slop key", "Choose any supported key or combination.", "AI connection", "Codex" / "Claude Code", "Claude account • Fixture only (not live)", "Manage", the data-flow line, "Style guidance", "No AI Slop" / "Humanizer" / "None", "Light, proportional edits. Recommended.", "Simplify wording", "Keep my tone", "More writing options" | white |

Finding and fix: in run 6, OCR of the self-rendered ready panel read only the end of the draft ("…luce errors for some teams"), positioned left of the editor inset. The editor was changed to the standard scrolling-text-view setup, and new drafts now start scrolled to the beginning. Run 7 (commit `41e369e`) re-checked it: the self-rendered and the window-server (`screencapture -l`) images both read "The pilot may reduce errors for some teams" inside the editor. The run-7 window-server captures also show "Rewriting…" with the disabled button while generating, and the intent, draft, note and enabled button when ready. All 15 TextEdit checks, all 7 end-to-end checks and all 80 unit tests passed again.

Not covered here: live providers (no credentials are placed in CI; `scripts/mac-acceptance.sh` runs the same checks against the user's own signed-in runtimes), VoiceOver, motion quality, multiple displays, first-run permission prompts, and real-user keyboard layouts.
