# Historical reviewed style profiles

**Superseded September 30, 2026:** the application now uses the consolidated [LiTiL primary prompt](../primary.md). These adaptations remain as provenance; they are neither selected nor embedded at runtime. The source snapshots and MIT notices are unchanged. The following documents the original two-profile design.

These short application profiles are adaptations for a selected-text copy editor. They are not globally installed agent skills. The app's primary prompt and output schema govern every profile. Bundle exactly one rule body per request, or none. The reviewed profile version is `0.2` and is independent of upstream commit/version.

| UI choice | App ID | Editorial role | Upstream pin |
|---|---|---|---|
| No AI Slop | `no-ai-slop` | Recommended default; light, proportional edits | `000650b156983f5159695b441477f4e63b25dc85` |
| Humanizer | `humanizer` | Alternative broader review of rhetorical patterns | `225a6f39ac85f76ee48dbad772ea4abe4ed6c9d8` |
| None | `none` | Primary prompt only | No third-party profile |

Original sources are retained unchanged under [third_party](../../third_party/PROVENANCE.md), with immutable URLs, hashes and both MIT licenses. No AI Slop is by Peter Yang; Humanizer is by Siqi Chen / blader. Keep the notices with derivatives/distribution. Humanizer's external Wikipedia credit remains in its original source; no external Wikipedia page has been republished here.

## Adaptations and omitted workflow

- Preserve all authored claims, legal effect and meaningful uncertainty above source style rules.
- Omit No AI Slop's normal change-summary output and Humanizer's multi-stage draft/critique/final presentation. Only the app's structured final replacement is returned.
- Do not adopt Humanizer's permission to add a reaction/opinion or creative detail. The app may retain the author's existing personal voice but cannot invent it.
- Treat blanket vocabulary/punctuation bans as contextual pattern checks. Protect names, quotations, defined terms, technical syntax and deliberate writing choices.
- Do not read a full file, invoke tools, ask the provider to install plugins or change its wider session. All supplied context is bounded by the app.
- Keep conservative editing possible when the purpose is uncertain. Already-good passages are valid unchanged outputs.

Profile updates need a new internal profile revision, a reviewed upstream pin if applicable, and re-evaluation of the representative corpus. Do not fetch upstream HEAD at runtime.
