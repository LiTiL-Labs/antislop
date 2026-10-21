# Evaluation fixtures

[editorial-cases.json](editorial-cases.json) contains 18 authored examples. `acceptable_example` demonstrates one faithful result; equivalent faithful edits can also pass. Do not force every provider to match a single stylistic string. `must_preserve` identifies important literals but is not a complete semantic check. All cases begin as **not_run**.

Run the corpus with Codex and Claude Code under the consolidated LiTiL prompt, for example `swift run antislop-eval corpus --provider claude-code` from `app/`. That gives 36 representative provider cases before Sentence Complexity variations. Before September 30, 2026 each case also ran under No AI Slop, Humanizer and None, for 108. The stored requests still use the 0.2 request format (`style_profile_id: no-ai-slop`, no Sentence Complexity); the app and `validation/validate.py` read them as the consolidated prompt at Balanced. Use the same supported account configuration, record actual model/runtime details and do not call an unavailable combination passed. A provider failure is evidence of a failed/unperformed request, not a poor editorial output.

Legal citation strings here are synthetic test material, not verified cases or legal advice. The acceptance target is exact citation preservation. Add user-approved realistic passages for human evaluation without storing sensitive source text in general diagnostic logs.

Interaction tests additionally need fixtures/stubs for late responses, malformed JSON, oversized/empty output, timeout, changed target, changed clipboard, cancelled sign-in, provider limits and failed/uncertain insertion. These control app behavior; they do not establish live connectivity or actual accessibility compatibility. See [ACCEPTANCE.md](../ACCEPTANCE.md).
