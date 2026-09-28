# macOS runner evidence

Source: the `macOS build and checks` workflow ([`.github/workflows/macos.yml`](../../.github/workflows/macos.yml)) on branch `claude/anti-slop-macos-dev-ay9m4k`, run 3 (commit `59a2fd3`), job `build-and-check`.

| Item | Value |
|---|---|
| Runner | GitHub-hosted `macos-15-arm64` image 20260907.0337 |
| macOS | 15.7.9 (24G830) |
| Toolchain | Xcode 16.4, Apple Swift 6.1.2, target arm64-apple-macosx |
| Build | `swift build -c release`: every target, including the AppKit/SwiftUI/Accessibility layer, compiles |
| Unit tests | `swift test`: 80 tests, 0 failures (the same suite also passes on Linux, Swift 6.1.3) |
| Baseline app | TextEdit, plain-text document (AppKit `NSTextView`) |

These runs use synthetic text only. The full-app checks use the labelled **fixture provider**, so they prove the interaction and replacement path, not a live AI connection. The runner grants Accessibility to the probe process, so they do not test the first-run permission prompt either.

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
| app_closed_blocks | PASS | `blocked(appClosed)` after TextEdit quit |

## Full app (`antislop-axprobe e2e`): real bundle, real hotkey, fixture provider

| Check | Result | Detail |
|---|---|---|
| e2e_launch | PASS | `Anti-slop.app` launched with a settings file assigning ⌃⌥⌘J |
| e2e_panel_appears | PASS | real HID key events triggered the Carbon hotkey; the floating panel appeared |
| e2e_escape_no_change | PASS | Escape closed the panel; the document was unchanged |
| e2e_apply_replaces_selection | PASS | ⌘Return applied the draft; only the selection changed |
| e2e_panel_closes_after_apply | PASS | the panel dismissed after confirmed replacement |
| e2e_settings_without_key | PASS | with no key assigned, launch opened the settings screen |

Not covered here: live providers (no credentials are placed in CI), VoiceOver, motion quality, multiple displays, first-run permission prompts, and real-user keyboard layouts.
