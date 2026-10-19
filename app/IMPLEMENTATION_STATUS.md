# Implementation status

**Current LiTiL revision (September 30):** see [the current revision evidence](evidence/litil-revision.md). The selectable-profile/custom-instruction controls and model dropdowns below are historical. Current code uses the consolidated prompt, capability and sentence-complexity sliders, LiTiL colors/branding and launch-at-login. Live Codex smoke requests now pass on this Mac; the current Claude adapter reports sign-in needed. The remaining content is retained as historical evidence, not a current readiness claim.

Updated September 28, 2026. Branch `claude/anti-slop-macos-dev-ay9m4k`. Build and run instructions: [README.md](README.md).

**Bottom line: MVP is not complete.** New real-UI checks on the macOS runner found and fixed a crash that ended the app right after every confirmed replacement (the text itself was always replaced correctly first). The app compiles on macOS. On a real macOS runner it captures and replaces TextEdit text with verified results, and the whole app loop has run end to end with the labelled fixture provider and, through each real provider adapter, with stub Claude Code and Codex runtimes. The Claude Code adapter has run live, 54 of 54 corpus requests, through the official CLI with its own account sign-in, but in the Linux development container, not inside the Mac app. **Codex has not run live**: this container's network policy blocks every OpenAI host. The combined "real provider + real Mac replacement" walkthrough and all human acceptance items still need the user's Mac.

## September 30 changes (not yet checked in the real UI)

The user asked for three changes. They are implemented and pass the automated tests (**Auto**: 102 tests on macOS 27, Swift 6.4, up from 82), but none has been through the macOS probe or a person yet. The CI workflow is disabled, so the Mac-CI rows below record the earlier ⌘Return behavior.

- **Slop-detection mode.** A second assigned key (and the menu item **Check Selection for Slop**) opens the panel as a **Slop check**: an internal prompt ([prompts/detect.md](../prompts/detect.md)) plus the selected profile as reference, with its own validated contract (`summary` plus up to 12 `{quote, issue}` findings). A quote that isn't an exact substring of the selection is dropped, never shown. There is no score and no authorship claim. It never applies; the anti-slop key or **Anti-slop** rewrites the same captured selection. Auto: validator, composition, coordinator, and both adapters against fake runtimes. Not live-tested with either provider.
- **Any key, including a lone modifier.** Right/Left ⌘ ⌥ ⌃ ⇧, Fn and Caps Lock can be assigned on their own. They fire on a lone press and release (under 1 s, nothing else pressed in between), watched by a global modifier monitor that needs the Accessibility access the app already has. Auto: advisor and detector state machine. Fn/Globe combinations and media keys are still refused, because macOS doesn't deliver them to apps as registrable shortcuts.
- **The anti-slop key applies in the panel.** Pressing the assigned key again applies the ready rewrite, and ⌘Return applies only when no key is assigned. As a result, a plain character key (for example `` ` ``) can no longer be typed into the draft; settings warns about this. The TextEdit probe was updated to apply with the assigned key, but it has not been run.

**Model and reasoning selection (also September 30).** Settings lists models from the runtime itself: Claude Code's `initialize` control handshake (the Agent SDK's route, run with the same no-tools isolation and no inference) and `codex debug models` (only models marked for listing). The choice is saved per connection and sent as `--model`/`--effort` (Claude Code) or `--model` plus `-c model_reasoning_effort=…` (Codex; the key is accepted under `--strict-config`). Codex's `ultra` level is not offered because it delegates to sub-agents. Real listing ran against Claude Code 2.1.233 and codex-cli 0.159.2 on this Mac (`antislop-eval models`), and the settings screen showed the live Codex list. A live rewrite with a chosen model and level has **not** been run. The debug window shows the requested model and level and the model the runtime reports (Claude Code reports it in its init event; for Codex the app doesn't read one yet, so it shows "not reported").

## Evidence types used here

| Label | Meaning |
|---|---|
| **Auto** | XCTest suite (82 tests), run on Linux (Swift 6.1.3) and on macOS 15.7.9 (Xcode 16.4, Swift 6.1.2, arm64) in the `macOS build and checks` workflow |
| **Mac-CI** | `antislop-axprobe` on the GitHub-hosted macOS runner: real TextEdit, real Accessibility, real keyboard events, the real app bundle ([results](evidence/macos-ci.md)) |
| **Fixture** | The development `FixtureProvider`, clearly labelled in the UI. It is never a live connection. |
| **Stub-CI** | The real app on the macOS runner calling labelled stub `claude`/`codex` scripts through its real provider path ([results](evidence/macos-ci.md#full-app-live-mode-with-stub-runtimes-e2e---live-not-live-ai)). It proves the plumbing, not a live AI connection. |
| **Live-Claude** | The official Claude Code CLI (2.1.283, and 2.1.284 on a full rerun) driven by the app's adapter code, from the Linux container, using the CLI's own stored account sign-in |
| **Not run / Human** | Needs the user's Mac, sign-in or judgment |

## Slices

| Slice | State | Evidence and notes |
|---|---|---|
| 0 — project and constraints | Done | SwiftPM package in `app/` (SwiftUI + AppKit, as recommended). The deployment target is macOS 13, the smallest target that covers the SwiftUI APIs used (`scrollContentBackground`, switch tint). Provider CLIs inspected; findings below. Handoff files are unchanged (`SHA256SUMS` verifies). |
| 1 — first runnable vertical slice | Built; proven in parts | Mac-CI + Fixture: hotkey → capture → panel → ⌘Return → verified replacement, Escape cancel, drift blocking. Live-Claude: real schema-valid rewrites. Stub-CI: the same loop through each provider adapter in the real app. **Not yet in one flow on a Mac with a live provider**; `scripts/mac-acceptance.sh` runs that check. |
| 2 — both providers and full settings | Code complete; Codex live blocked | Both adapters implemented and tested against fake runtimes, and both ran end to end inside the real app with stub runtimes (Stub-CI). Codex flags were validated against the real codex-cli 0.158.0 (`--strict-config`), but it could not make a live request here. All settings persist atomically (Auto). |
| 3 — context, fidelity, resilience | Done for Claude | Bounded context, unknown boundaries, partial selections, revisions, stale-result discard, clipboard ownership, drift checks (Auto, Mac-CI). Corpus: 54/54 validated and 0 material fidelity violations in agent review, on CLI 2.1.283 and again on 2.1.284 ([review](evidence/claude-code-corpus-review.md)). Codex corpus not run. |
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
| A03 | **Passed (Mac-CI)** | An unmodified `` ` `` assigned as the key triggered the panel from TextEdit, and TextEdit received no character. Conflict and consumption explanations and the absence of an F-key restriction: Auto. Key presses are synthetic HID events on the runner; a person at a physical keyboard is still a human check. |
| A04 | **Passed (Mac-CI)** | On the real settings screen: ⌃⌥⌘K recorded; Fn+J refused and ⌃⌥⌘K kept; **Cancel** kept it; **Done** saved `key_code 40` + ⌃⌥⌘ and the new key opened the panel. Validate-before-replace is in `HotKeyManager.apply`. |
| A05 | Partly passed | Mac-CI: an Fn/Globe combination got the specific "macOS doesn't let apps register Fn/Globe combinations" message and nothing was remapped. Auto: reserved keys, modifier-only and system shortcuts read from `com.apple.symbolichotkeys` plus defaults. A system-reserved chord pressed live (e.g. ⌘Space) was not tested, because the system takes it before any app. |
| A06 | **Passed (Mac-CI)** | Holding the key with auto-repeat gave one panel and no repeated characters in the draft (a fix, see [defects](evidence/macos-ci.md#defects-these-checks-found-and-fixed)). The key typed normally inside the panel, and it triggered again once the panel closed. The recorder receives keys while recording. Typing the key in the custom-instructions field was not probed. |
| A07 | Tested | Auto (save/reload of every field, atomic write, unreadable file preserved). Mac-CI: the app loaded a settings file on launch. |
| A08 | **Blocked here; ready for the user's Mac** | Codex live request impossible here (network policy). Fake-runtime tests, real-CLI flag validation, and Stub-CI in-app proposal and apply only. |
| A09 | Live outside the app | Live-Claude: readiness and 54 rewrites through the adapter. Stub-CI: in-app proposal and apply. On-Mac sign-in and live in-app rewrite not yet run. |
| A10 | Stub + one live case | Auto: signed out, API key, cloud-provider switch, limit, auth error, offline, timeout. Live: real Codex 0.158.0 reported "Sign-in needed" when signed out. |
| A11 | Logic tested | Auto: empty, whitespace-only, oversized (no truncation). Capture refuses secure fields and non-editable controls; a real secure field was not tested. |
| A12 | **Passed (Mac-CI)** | Exact selection, known excerpts, bounds and source hint captured from TextEdit. |
| A13 | Passed | Auto + Live-Claude (`unknown_context`: unchanged, "Context unclear"). |
| A14 | **Passed (Mac-CI + live model)** | Mac-CI: a mid-word selection and a span with boundary spaces were captured and spliced exactly in TextEdit. Auto + Live-Claude `partial_whitespace`. |
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
| A27 | Passed (Auto + Mac-CI) | Escape in the real app changed nothing, also after edits in the panel; a duplicate trigger focuses the existing panel. |
| A28 | **Passed (Mac-CI)** | Return added a newline without applying; ⌘Return applied the final edited draft once; with an empty editor ⌘Return changed nothing and the panel said "Enter replacement text to apply."; typing continued in the editor afterwards. The pre-mutation recheck is Auto. |
| A29 | **Passed (Mac-CI)** | Moved selection, edited text, focus in another document and a quit app all blocked the write; nothing was written to the unrelated document. |
| A30 | **Passed (Mac-CI)** | Only the selection changed, verified by reading the whole document back. The panel closes after confirmation and the app keeps running (a crash here was found and fixed, see [defects](evidence/macos-ci.md#defects-these-checks-found-and-fixed)). |
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

## Anti-slop skill

`.claude/skills/anti-slop/` packages the same editing contract (consolidated prompt 0.3 and the Sentence Complexity levels) for use in a Claude conversation, outside the Mac app. It never calls a CLI or another model, and it is not part of the MVP. A unit test keeps its prompt, complexity guidance, notices and schema identical to the app's. The 0.3 skill was evaluated live on October 19, 2026: 54 blind-graded `claude -p` tests (18 cases at Balanced, Caveman and Lawyer) on Claude Code CLI 2.1.303. Replies with the skill kept meaning in 51 of 54 tests and met every expectation in 48, against 13 and 0 without the skill ([evaluation](evidence/skill-eval-0.3.md)). One session did not load the skill and dropped a hedge. Four misses were Caveman or Lawyer edits to text that needed none. One was only a required phrase that the reply capitalized. Those grades came from model judges, one run per test; human review is still needed. The earlier prompt 0.2 evaluation is kept as a historical record ([skill-eval.md](evidence/skill-eval.md)).

## CI note

`.github/workflows/macos.yml` runs on pushes to this development branch that touch `app/`, `prompts/`, `fixtures/`, `schemas/` or `third_party/`, and on manual dispatch. It uses a GitHub-hosted macOS runner (about 2 minutes a run; macOS minutes count at a multiple of Linux minutes on private repositories), plus four short Linux jobs that print screenshots into their logs. No secrets are used, and no provider credentials exist in CI. Remove or narrow the workflow if you don't want it to spend Actions minutes.

## What the user needs to do

1. Sign in to both runtimes with your own accounts: `claude auth login` and `codex login` (choose ChatGPT). Anti-slop never asks for a token.
2. Give your terminal app Accessibility access (System Settings › Privacy & Security › Accessibility). Save your documents and quit TextEdit.
3. Run the automated on-Mac acceptance pass, and don't type or click while it runs (about 5–10 minutes, most of it the Codex corpus):
   ```sh
   cd app && ./scripts/mac-acceptance.sh        # add --claude-corpus to rerun the Claude corpus on the Mac too
   ```
   It runs the tests, builds the app, checks readiness for both providers with a harmless request, runs the TextEdit probe, runs a live end-to-end rewrite through the real app for Claude Code and then Codex (hotkey → panel → live proposal → ⌘Return → verified replacement), and runs the 54-request Codex corpus. It uses synthetic text only.
4. Send back the folder it prints (`app/evidence/mac/<timestamp>/`), or just the summary at the end of its output. The receipts contain the synthetic fixture text and model rewrites of it, never credentials. I'll review the Codex corpus for fidelity and record the results here.
5. Walk through ACCEPTANCE.md's human items: the legal-clause review, voice/tone quality, motion and translucency, VoiceOver, key assignment with a single key and with a reserved key, and multi-display placement. Open `build/Anti-slop.app` for these; it is the same app the script tested.

The same live checks can be run one at a time with the commands in [README.md](README.md#checks).
