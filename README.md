# Anti-Slop · LiTiL Labs

A native macOS menu-bar app for editing selected plain text. Select text in another app, press your rewrite key, review or edit the proposal, then press the key again or **Anti-slop** to replace that exact selection. A separate detection key lists quoted writing-pattern findings without changing the source.

The implementation is in [app](app/README.md). Build locally with:

```sh
cd app
./scripts/build-app.sh
open build/Anti-slop.app
```

App builds use the local **Developer ID Application: LiTiL Labs, Inc. (5N876P35QC)** certificate by default and verify the signature. See [build instructions](app/README.md) for explicit signing overrides.

Settings is also onboarding. Choose Codex or Claude Code, assign both keys, set **Intelligence** (AI capability) and **Sentence Complexity** (prose), and choose Done. **Launch at login** defaults on; macOS owns registration and approval. The resident menu-bar icon always offers Settings.

A single hidden LiTiL Anti-Slop prompt combines the original editor and reviewed No AI Slop/Humanizer guidance. Em-dash removal is constant, with factual/legal fidelity and protected literal content taking precedence. No profile selector or custom writing instructions remain. An optional pasted style guide remains supported.

Intelligence presets are Room Temp, Average, Smart and Genius. Sentence Complexity runs Caveman, Plain, Balanced, Polished and Lawyer. Genius has a green bloom and pixels; Lawyer has the same effect in orange. Titles use `#ED692B` and primary buttons use `#102D23`.

Both providers use their official local runtime and provider-owned account sign-in. The model only proposes text; native code owns the captured selection and validated explicit replacement. No API-token extraction, tool execution from source material, file mode, rich-format promise, analytics or cloud service is included.

- [Current decisions](DECISIONS.md)
- [Prompt composition](PROMPTING.md)
- [Architecture and safety](ARCHITECTURE.md)
- [Current revision evidence](app/evidence/litil-revision.md)
- [Implementation history](app/IMPLEMENTATION_STATUS.md)
- [Pinned sources and licenses](third_party/PROVENANCE.md)

The original handoff and receipts remain historical evidence; their old selectable-profile/custom-instruction controls are superseded by the September 30 LiTiL revision. Source snapshots and MIT license notices remain unchanged, with the notices included as files in the app bundle. The licenses menu item and window have been removed.
