# Anti-slop — local macOS app

Anti-slop is a small menu-bar app. You select text in another Mac app and press the key you assigned. It shows a floating panel with an editable rewrite, and replaces only the original selection when you press **Anti-slop**. The product specification is the package at the repository root, starting with [DEVELOPMENT_HANDOFF.md](../DEVELOPMENT_HANDOFF.md). Current evidence and limits are in [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md).

## Prerequisites

| Need | Why |
|---|---|
| macOS 13 Ventura or later | Deployment target (SwiftUI + AppKit) |
| Xcode 15 or later, or Swift 5.9+ command-line tools | Builds the Swift package; CI uses the `macos-15` runner image |
| **Claude Code** CLI, signed in with your Claude account (`claude auth login`) | Required AI connection. Anti-slop runs the unmodified official CLI. |
| **Codex** CLI, signed in with ChatGPT (`codex login`) | Required AI connection. Anti-slop runs `codex exec`. |
| Accessibility permission for Anti-slop | Lets it read the selection you trigger on and replace it. macOS asks on first use. |

Anti-slop has no API-key field. It never reads provider credential stores, and it never forwards `ANTHROPIC_API_KEY`, `OPENAI_API_KEY` or similar variables to the runtimes. If a runtime is set up for API-key billing, the settings screen says so and Anti-slop won't use it.

## Build and run

```sh
cd app
./scripts/build-app.sh          # builds release and assembles build/Anti-slop.app (ad-hoc signed)
open build/Anti-slop.app
```

On first launch the settings screen opens. It is the same screen the menu-bar item and the panel's gear open later. Then:

1. Choose **Claude Code** or **Codex**. Open **Manage** to sign in through the provider's own tool (it opens in Terminal) or to **Check again**. **Ready** appears only after a real, harmless request succeeds.
2. Choose **Assign anti-slop key** and press any key or combination. The screen explains known conflicts and real macOS limits, and it never substitutes a different key.
3. Adjust the writing style, the toggles, an optional pasted guide and **Custom writing instructions**, then choose **Done**.
4. Grant Accessibility access when asked (System Settings › Privacy & Security › Accessibility).
5. Select text in TextEdit, which is the verified baseline, and press your key.

In the panel, ordinary Return inserts a newline, ⌘Return or **Anti-slop** applies, and Escape or ✕ closes without changing anything. If the original selection changed, the draft stays in the panel; use **Copy draft** or **Use current selection**. If you have no key, or a broken one, you can still use the menu-bar item (**Rewrite Selection**, **Settings…**), or relaunch the app, which reopens settings.

Because the build is ad-hoc signed, macOS may ask for Accessibility permission again after a rebuild. To avoid that, set `SIGN_IDENTITY` to a local development certificate.

### Developer fixture mode

`open build/Anti-slop.app --args --fixture-provider` swaps in a deterministic local provider. The panel labels its output "Fixture preview — not live AI", and settings show the connection as "Fixture only (not live)". Use it only to work on the interaction; it is not a live connection.

## Checks

For the full on-Mac pass (tests, bundle, readiness for both providers, the TextEdit probe, live end-to-end rewrites in the real app, and the Codex corpus) run `./scripts/mac-acceptance.sh` after signing in to both runtimes and quitting TextEdit. It writes receipts to `evidence/mac/<timestamp>/`. The individual commands are:

```sh
cd app
swift test                                            # unit/contract tests (also run on Linux)
swift run antislop-eval readiness --provider claude-code
swift run antislop-eval readiness --provider codex
swift run antislop-eval corpus --provider claude-code --out evidence/live/claude-code-corpus.json
swift run antislop-eval corpus --provider codex --out evidence/live/codex-corpus.json
swift run -c release antislop-axprobe textedit --out probe.json   # drives TextEdit; quit TextEdit first
swift run -c release antislop-axprobe e2e --app build/Anti-slop.app --live --provider codex --out e2e.json
```

`antislop-eval` sends the synthetic fixture corpus (`../fixtures/editorial-cases.json`) through the same provider adapters the app uses. Never point it at private text. `antislop-axprobe` needs Accessibility permission for the terminal that runs it. It opens its own temporary TextEdit documents and checks capture, verified replacement, undo, selection/text/focus drift and the clipboard fallback. `--allow-quit-textedit` also force-quits TextEdit to test the closed-app case, so use it only when no documents of yours are open.

## Anti-slop as a Claude skill

`.claude/skills/anti-slop/` packages the same editing behavior as a skill, for use in a conversation instead of the Mac app. Claude Code sessions in this repository pick it up automatically. To use it elsewhere, copy the folder to `~/.claude/skills/anti-slop/`, or upload the packaged `.skill` file in Claude's skill settings.

The skill carries the primary prompt's instruction body and both profiles' rule bodies verbatim, plus the MIT notices and the response schema. It never calls a CLI or another model: the assistant that loads it does the editing itself. After changing anything in `../prompts`, `../third_party` or `../schemas/rewrite-response.schema.json`, run `python3 scripts/sync-skill.py`. A unit test fails if the skill drifts. The evaluation harness, the helper-script tests and how to rerun them are in `scripts/skill-eval/README.md`; the latest results are in [evidence/skill-eval.md](evidence/skill-eval.md).

## Layout

| Path | Contents |
|---|---|
| `Sources/AntiSlopCore` | Foundation-only logic: contracts, validation, prompt composition, context, settings, provider adapters, process runner, session state, replacement checks, placement, shortcut assessment. Builds and tests on Linux too. |
| `Sources/AntiSlopCore/Generated/EmbeddedPrompts.swift` | Generated by `scripts/embed-prompts.py` from `../prompts` and the `../third_party` licenses. A test fails if it drifts. |
| `Sources/AntiSlopMac` | AppKit/SwiftUI/Accessibility/Carbon layer (macOS only). |
| `Sources/AntiSlop` | App entry point. |
| `Sources/antislop-eval`, `Sources/antislop-axprobe` | Evaluation and real-app probe tools. |
| `Tests/AntiSlopCoreTests` | XCTest suite, including fake `claude`/`codex` runtimes. |
| `evidence/` | Sanitized receipts from live runs (synthetic fixture text only). |
