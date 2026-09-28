# Implementation status

Updated September 28, 2026. Branch `claude/anti-slop-macos-dev-ay9m4k`. Build and run instructions: [README.md](README.md).

**Bottom line: MVP is not complete.** The app compiles on macOS. On a real macOS runner it captures and replaces TextEdit text with verified results, and the whole app loop has run end to end with the labelled fixture provider. The Claude Code adapter has run live, 54 of 54 corpus requests, through the official CLI with its own account sign-in, but in the Linux development container, not inside the Mac app. **Codex has not run live**: this container's network policy blocks every OpenAI host. The combined "real provider + real Mac replacement" walkthrough and all human acceptance items still need the user's Mac.

## Evidence types used here

| Label | Meaning |
|---|---|
| **Auto** | XCTest suite (80 tests), run on Linux (Swift 6.1.3) and on macOS 15.7.9 (Xcode 16.4, Swift 6.1.2, arm64) in the `macOS build and checks` workflow |
| **Mac-CI** | `antislop-axprobe` on the GitHub-hosted macOS runner: real TextEdit, real Accessibility, real keyboard events, the real app bundle ([results](evidence/macos-ci.md)) |
| **Fixture** | The development `FixtureProvider`, clearly labelled in the UI. It is never a live connection. |
| **Live-Claude** | The official Claude Code CLI 2.1.283 driven by the app's adapter code, from the Linux container, using the CLI's own stored account sign-in |
| **Not run / Human** | Needs the user's Mac, sign-in or judgment |

## Slices

| Slice | State | Evidence and notes |
|---|---|---|
| 0 — project and constraints | Done | SwiftPM package in `app/` (SwiftUI + AppKit, as recommended). The deployment target is macOS 13, the smallest target that covers the SwiftUI APIs used (`scrollContentBackground`, switch tint). Provider CLIs inspected; findings below. Handoff files are unchanged (`SHA256SUMS` verifies). |
| 1 — first runnable vertical slice | Built; proven in parts | Mac-CI + Fixture: hotkey → capture → panel → ⌘Return → verified replacement, Escape cancel, drift blocking. Live-Claude: real schema-valid rewrites. **Not yet in one flow on a Mac with a live provider**; `antislop-axprobe e2e --live` is that check. |
| 2 — both providers and full settings | Code complete; Codex live blocked | Both adapters implemented and tested against fake runtimes. Codex flags were validated against the real codex-cli 0.158.0 (`--strict-config`), but it could not make a live request here. All settings persist atomically (Auto). |
| 3 — context, fidelity, resilience | Done for Claude | Bounded context, unknown boundaries, partial selections, revisions, stale-result discard, clipboard ownership, drift checks (Auto, Mac-CI). Corpus: 54/54 validated and 0 material fidelity violations in agent review ([review](evidence/claude-code-corpus-review.md)). Codex corpus not run. |
| 4 — visual polish and local acceptance | Implemented; human review pending | Warm shell, material, placement, slide/fade, Reduce Motion/Transparency handling. Real screenshots from the macOS runner were checked by OCR and color sampling ([evidence](evidence/macos-ci.md#rendered-ui-vision-ocr-and-sampled-colors-of-real-screenshots)). Motion, VoiceOver and multi-display need a human. |

## Provider findings

**Claude Code (verified live, CLI 2.1.283).** Anti-slop runs the unmodified `claude` binary:

```
claude --print --output-format stream-json --verbose --json-schema <wire schema> --tools "" \
  --strict-mcp-config --no-session-persistence --system-prompt <primary prompt + one profile> \
  --safe-mode --setting-sources "" --settings '{"disableAllHooks":true}' \
  --disable-slash-commands --permission-prompts none        # request data on stdin
```

- The stream's `init` event was observed to report `tools: ["StructuredOutput"]` (the schema mechanism only), `mcp_servers: []`, `skills: []` and `apiKeySource: "none"`. The adapter stops the process if any other tool, any MCP server or any API-key source appears, or if the model emits a tool call other than `StructuredOutput`.
- `--bare` was rejected on purpose. It skips hooks and CLAUDE.md, but it also forces `ANTHROPIC_API_KEY` authentication and never reads the account sign-in, which would break own-account use.
- Readiness means `claude auth status --json` (`loggedIn`, `authMethod`, `apiProvider`) plus a harmless live request. Sign-in runs `claude auth login --claudeai` in Terminal.
- The child environment is an allowlist: inherited `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, Bedrock/Vertex switches and similar variables never reach it. The allowlisted environment still authenticated through the CLI's own stored sign-in.

**Codex (flags verified, live blocked; codex-cli 0.158.0 installed from npm into a scratch directory).**

```
codex exec --json --ephemeral --skip-git-repo-check --ignore-user-config --ignore-rules --strict-config \
  --sandbox read-only --cd <empty dir> --output-schema <file> --output-last-message <file> \
  -c approval_policy="never" -c web_search="disabled" -c project_doc_max_bytes=0 \
  -c history.persistence="none" -c developer_instructions="<primary prompt + one profile>" \
  --disable <each enabled tool feature reported by `codex features list`> -        # data on stdin
```

- `--strict-config` rejects unknown override keys, and `--disable` rejects unknown features. The adapter therefore reads `codex features list` and disables only tool-granting features that exist in the installed version (hooks, shell, plugins, apps, browser, computer use, multi-agent and so on). A future rename fails loudly instead of silently weakening isolation.
- The JSONL guard stops the run if any item other than `agent_message`, `reasoning` or `error` appears (a command, file change, MCP or web call).
- Readiness means `codex login status` (ChatGPT sign-in required; an API-key login is shown as "Needs attention" and never used) plus a harmless live request. Sign-in runs `codex login` in Terminal.
- **Blocker:** in this container `api.openai.com`, `chatgpt.com` and `auth.openai.com` are denied by the environment's network policy, and Codex is signed out. Live Codex evidence has to come from the user's Mac, or from this environment after the network policy allows those hosts and the user completes `codex login --device-auth` here.

## Acceptance matrix (ACCEPTANCE.md)

| ID | Status | Evidence |
|---|---|---|
| A01 | Implemented; partly shown | One `SettingsView` serves first launch, the gear and the menu. Mac-CI: launching with no key opens settings. Human UI check pending. |
| A02 | Implemented; partly shown | Menu-bar **Rewrite Selection** and **Settings…**, plus reopening the app. Mac-CI shows the no-key launch. |
| A03 | Logic tested | Auto (single letters and F-keys allowed with an explanation; no F-key restriction). Real single-key press not run. |
| A04 | Combination shown live | Mac-CI: ⌃⌥⌘J registered and triggered by real HID events. Validate-before-replace is in `HotKeyManager.apply`. Cancel/invalid reassignment is a human check. |
| A05 | Logic tested | Auto: reserved keys, modifier-only, Fn, and system shortcuts read from `com.apple.symbolichotkeys` plus defaults. Registration errors are reported, never remapped. Real keyboard not run. |
| A06 | Implemented | Trigger suspended while Anti-slop is active; key repeat gives one activation. Not run live. |
| A07 | Tested | Auto (save/reload of every field, atomic write, unreadable file preserved). Mac-CI: the app loaded a settings file on launch. |
| A08 | **Blocked** | Codex live request impossible here (network policy). Fake-runtime tests and real-CLI flag validation only. |
| A09 | Live outside the app | Live-Claude: readiness and 54 rewrites through the adapter. On-Mac sign-in and in-app rewrite not yet run. |
| A10 | Stub + one live case | Auto: signed out, API key, cloud-provider switch, limit, auth error, offline, timeout. Live: real Codex 0.158.0 reported "Sign-in needed" when signed out. |
| A11 | Logic tested | Auto: empty, whitespace-only, oversized (no truncation). Capture refuses secure fields and non-editable controls; a real secure field was not tested. |
| A12 | **Passed (Mac-CI)** | Exact selection, known excerpts, bounds and source hint captured from TextEdit. |
| A13 | Passed | Auto + Live-Claude (`unknown_context`: unchanged, "Context unclear"). |
| A14 | Passed (unit + live model) | Auto + Live-Claude `partial_whitespace`. A real partial-word selection was not probed. |
| A15 | Passed (Auto) | Exactly one rule body, or none, is composed. |
| A16 | Passed (Auto) | The next request carries the saved text; an in-flight draft is not regenerated. |
| A17 | Claude passed | Live-Claude `custom_conflict`: fidelity won. Codex not run. |
| A18 | Claude passed (agent review) | `tone_off` kept the belief, the hedge and the magnitude. Human review pending. Codex not run. |
| A19 | Claude passed | 54/54 validated single objects. Codex not run. |
| A20 | Claude passed | Good text returned unchanged (39 of 54 results were identical to the source). Human review pending. |
| A21 | Claude passed | may/only/some/negation all preserved. |
| A22 | Claude passed (agent review) | Legal clauses and citation preserved exactly. **Legal-writing review by a human is pending.** |
| A23 | Passed | Auto + Live-Claude (`code`, `quote_url`). |
| A24 | Passed (Claude) | Runtime: no tools; the guard aborts on tool use (Auto with fakes). Live-Claude `source_instructions`. |
| A25 | Passed (Auto) | Apply disabled while generating or applying; status is "Rewriting…" with no invented progress. |
| A26 | Passed (Auto) | Late or stale results never overwrite user edits. |
| A27 | Passed (Auto + Mac-CI) | Escape in the real app changed nothing; a duplicate trigger focuses the existing panel. |
| A28 | Passed (Auto + Mac-CI fixture) | ⌘Return applied once; blank-draft guard. Return-for-newline was not exercised live. |
| A29 | **Passed (Mac-CI)** | Moved selection, edited text, focus in another document and a quit app all blocked the write; nothing was written to the unrelated document. |
| A30 | **Passed (Mac-CI)** | Only the selection changed, verified by reading the whole document back. The real app panel closes after confirmation. |
| A31 | Stub-tested | Auto: failed/uncertain outcomes keep the draft and disable re-apply. A real failing control was not probed. |
| A32 | Passed (Auto + Mac-CI) | Real clipboard restored after a confirmed paste; newer user copies are never overwritten (Auto). |
| A33 | **Passed (Mac-CI)** | ⌘Z in TextEdit restored the original after an Accessibility write. |
| A34 | Passed (Auto) | Malformed, extra-field, wrapped, empty, oversized, timeout and cancel cases are never inserted. |
| A35 | Logic tested | Auto placement: right/left/below/above, clamping, second display, unanchored. Real displays not run. |
| A36 | Human | Labels, announcements and Reduce Motion/Transparency are implemented; not tested with VoiceOver. |
| A37 | Human | Custom instructions are present, no prompt inspector exists, and both providers and both profiles are present. Needs the user's review. |
| A38 | Tested | Auto: diagnostics contain no content. Logs use `os.Logger` with sanitized strings only. |

## Remaining limits

- **Supported baseline:** TextEdit plain-text documents (AppKit `NSTextView`). Other apps may work but are not claimed. The clipboard fallback is used only when a control's selected text isn't writable over Accessibility. It is never used after an attempted Accessibility write, so apps whose Accessibility writes are ignored will report failure rather than risk a double insert.
- Rich text formatting is not preserved (plain text by design). Word, PowerPoint and file mode are out of scope.
- The ad-hoc signed local build may need Accessibility permission re-granted after rebuilds.
- A GUI app doesn't inherit the shell `PATH`. Runtimes are found in standard install locations or through the login shell's `command -v`. Unusual installs may need a symlink in `/usr/local/bin` or `~/.local/bin`.
- Proxies are forwarded only if set in the app's environment. Corporate proxy setups configured only in shell profiles may need attention.
- Latency: Claude Code median about 3.6 s (range 3.0–5.8 s) on the corpus. The rewrite timeout starts at 90 s.
- Intent lines from the model are often longer and less tentative than the UX examples (see the [corpus review](evidence/claude-code-corpus-review.md)). A prompt 0.3 tweak is proposed, not made.

## CI note

`.github/workflows/macos.yml` runs on pushes to this development branch that touch `app/`, `prompts/`, `fixtures/`, `schemas/` or `third_party/`, and on manual dispatch. It uses a GitHub-hosted macOS runner (about 2 minutes a run; macOS minutes count at a multiple of Linux minutes on private repositories), plus four short Linux jobs that print screenshots into their logs. No secrets are used, and no provider credentials exist in CI. Remove or narrow the workflow if you don't want it to spend Actions minutes.

## What the user needs to do

1. On the Mac: `cd app && ./scripts/build-app.sh && open build/Anti-slop.app`, then grant Accessibility access.
2. Sign in to both runtimes with your own accounts (settings › Manage), or run `claude auth login` and `codex login` yourself.
3. Run the one-command live checks (TextEdit must not be open with your documents):
   `swift build -c release && .build/release/antislop-axprobe e2e --app build/Anti-slop.app --live --provider claude-code --out claude-e2e.json`, then the same with `--provider codex`.
4. Run the Codex corpus: `swift run antislop-eval corpus --provider codex --out evidence/live/codex-corpus.json`.
5. Walk through ACCEPTANCE.md's human items: the legal-clause review, voice/tone quality, motion and translucency, VoiceOver, key assignment with a single key and with a reserved key, and multi-display placement.
