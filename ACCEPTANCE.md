# Acceptance and proof requirements

All product checks below are **not run in this handoff**. The package includes plans, source snapshots, schemas, fixtures and comps only. Change each check's status only after recording the relevant evidence. Preserve the distinction between automated/fixture proof, a live provider request, real cross-app behavior and human acceptance.

## Functional acceptance matrix

| ID | Given / action | Required result | Evidence type |
|---|---|---|---|
| A01 | First launch; later open panel gear | Identical settings surface and persisted values; no wizard | UI + real launch |
| A02 | No shortcut or a broken shortcut | App/menu entry still opens settings and allows recovery | Real UI |
| A03 | Assign a supported ordinary single key | Exact recorded key becomes trigger; known conflict/consumption explained; no F-key restriction | Real keyboard |
| A04 | Assign a modified combination; cancel or fail reassignment | Correct binding, cancel/invalid assignment preserves previous valid key | State + real keyboard |
| A05 | Reserved/uninterceptable key or known conflict | Honest specific feedback; no silent remap or false registration success | Real keyboard |
| A06 | Type in Anti-slop editor/custom field/recorder; hold trigger | Ordinary input works under chosen suspension policy; no repeated requests | Real keyboard |
| A07 | Save settings and relaunch | Provider, key, style, tone, simplification, guide and custom text survive | Automated + launch |
| A08 | Choose Codex and complete official account sign-in | Real harmless readiness and rewrite succeed; no API-token entry or token copying | Live Codex |
| A09 | Choose Claude Code and complete official own-account sign-in | Unmodified supported runtime performs readiness and rewrite; no intermediated credentials | Live Claude Code |
| A10 | Runtime installed but signed out, limit reached, model unavailable or offline | Truthful state/action; no Ready merely from installation; no silent provider/billing switch | Stub + live representative |
| A11 | No selection, read-only/secure/nontext control or oversized text | Clear local failure; no source mutation or empty/truncated submission | Unit + real source |
| A12 | Supported selected prose | Exact selection and available bounds captured before panel focus | Real source |
| A13 | Context absent or partly available | Unknown represented explicitly; conservative edit; intent tentative | Contract + live model |
| A14 | Partial word/sentence plus boundary spaces | Only selection replaced; grammatical join and necessary spaces preserved | Unit + live source/model |
| A15 | Change selected profile or choose None | Exactly the matching bundled rule body, or no profile, enters the request | Automated composition |
| A16 | Save/clear custom instructions or guide | Next request includes exact saved text or none; current draft unchanged | Automated + UI |
| A17 | Custom instructions conflict with uncertainty/obligation | Core fidelity wins; compatible style portion applies | Both live providers |
| A18 | Keep my tone on/off | On retains authorial register; off may neutralize it without inventing personality or changing claims | Live model + human |
| A19 | Ordinary rewrite | One validated intent/replacement/note object; no critique in replacement | Automated + both live |
| A20 | Already-good passage | Unchanged output accepted, without forced artificial rewriting | Both live + human |
| A21 | Meaningful may/only/some/negation/condition | No substantive strengthening, weakening or loss | Both live + human |
| A22 | Legal clauses and synthetic citations | Exact protected terms, parties, dates, quotes/citations/cross-references; same obligations, permissions and exceptions | Both live + legal-writing review |
| A23 | Code, URLs, quotes and identifiers | Protected material remains exact; no refactoring | Automated + both live |
| A24 | Embedded source directions resembling instructions | No tools/files/actions; content stays data | Runtime restrictions + adversarial fixture |
| A25 | Generating or applying | Apply disabled; truthful status; no invented percent or intent stage | State + UI |
| A26 | User edits preview; delayed or stale provider event arrives | User edits remain; stale event discarded | Automated state |
| A27 | Escape/close; settings open; duplicate trigger | No source mutation; cancellation blocks late results; settings preserves useful draft; no duplicate panels | State + real UI |
| A28 | Explicit Anti-slop button or the anti-slop key pressed in the panel while ready (Command-Return without a key) | Final edited contents used once; Return alone adds newline. For substantive source, empty/whitespace-only editor buffer disables apply with concise feedback and is rejected again immediately before mutation. | State + real UI |
| A29 | Original source changes/closes or another field gains focus | Apply blocks; no paste into unrelated field; draft retained | Real adversarial interaction |
| A30 | Verified apply succeeds | Only original selection changes, surrounding text intact, panel closes after verification | Real source |
| A31 | Apply fails or completion is uncertain | Draft retained, honest recovery, no automatic duplicate paste | Stub + real failure |
| A32 | Clipboard fallback; user copies elsewhere during transaction | Anti-slop does not overwrite newer clipboard; preserves supported prior content when it still owns clipboard | Automated + real clipboard |
| A33 | Source undo after successful apply | Native undo works on declared supported baseline, or limitation is documented before claiming support | Real source |
| A34 | Malformed/extra/empty/oversized response, timeout or cancellation | Never inserted; concise retry/recovery; no implicit provider switch | Automated adapter |
| A35 | Selection near screen edge or on another display | Visible bounded panel; avoid covering selection when feasible; fallback honest | Real displays |
| A36 | Keyboard and screen reader; increased text; reduce motion/transparency | Named controls, coherent focus, readable layout, appropriate announcements and system preferences | Human accessibility |
| A37 | Settings and panel inspection | Custom instructions present; core prompt remains internal; both provider choices and final two profiles present | Human UI review |
| A38 | Diagnostic/output review | No document text, writer instructions, clipboard or credentials in default logs | Code + runtime check |

## Editorial evaluation protocol

Run [18 cases](fixtures/editorial-cases.json) with Codex and Claude Code using No AI Slop, Humanizer and None. Record which combinations actually ran and the exact available model/runtime versions. Review factual/legal invariants before judging smoothness or brevity. Treat stylistic example outputs as examples, not the sole correct strings.

The initial target is zero material fidelity violations in the representative corpus. Passing this small corpus does not prove universal correctness. Add regression cases for failures observed during human use; protect approved source material appropriately. No AI detector score is an acceptance measure.

## Real end-to-end walkthrough

1. Launch the local build; use the single settings screen to select a ready provider and assign a supported key. Save one custom writer preference.
2. Open the declared external plain-text baseline, enter a test paragraph with meaningful hedging, select a middle passage and trigger the app.
3. Verify the panel's placement/progress, read the tentative intent, edit one word in the proposal and apply. Confirm the exact replacement and unchanged surrounding text. Test native undo.
4. Repeat with the other required provider, then with Humanizer and core-only. Confirm the saved custom preference appears in behavior/composition.
5. During another request, change the original selection or focus an unrelated field. Apply must not insert there; the draft stays available.
6. Exercise cancel, expired/failed connection, malformed fixture response and failed replacement. Ensure each source remains safe and failure does not destroy edits.
7. Check a legal clause with defined terms, a shall/may distinction and a citation. Review the resulting effect, not just literal token presence.
8. Try the animation, readable translucency, keyboard flow, screen-reader controls and settings recovery. Static comps do not pass this step.

## Completion report format

Report build/run instructions and exact tested baseline; automated checks passed/failed; live Codex evidence; live Claude Code evidence; replacement/clipboard/undo evidence; editorial review findings; and remaining human acceptance items. An unavailable provider or unproven replacement leaves MVP incomplete. A local success is not a public release or an all-app compatibility claim.
