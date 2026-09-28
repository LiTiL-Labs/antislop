# UI and interaction specification

## Visual direction

Use the supplied [ready editor](assets/ready-editor.png), [processing editor](assets/processing-editor.png) and [current settings](assets/settings.png) as visual references. They express the approved quiet, warm, light native direction; they are not implementation screenshots or pixel-perfect functional contracts. Written requirements govern behavior and final controls.

The shell is warm off-white, the editor white, corners softly rounded, borders fine, shadows restrained and icons thin. A small amount of background material/translucency gives depth while text stays crisp. Do not lower the entire window's opacity: content must remain fully legible. This is inspired by the visual restraint of Codex/ChatGPT, not branded as either product.

Candidate implementation tokens, adjustable after native review:

| Token | Starting value |
|---|---|
| Shell / editor | warm off-white `#F7F6F3` / white `#FFFFFF` |
| Primary / secondary text | `#232322` / `#656563` |
| Border | 1 pt neutral border with sufficient contrast |
| Primary action | near-black fill, white label, 10–12 pt radius |
| Panel / editor radius | 18–20 pt / 12–14 pt |
| Panel width | about 430 pt; adapt within 360–560 pt and screen bounds |
| Panel height | content-responsive; editor scrolls before window exceeds visible screen |
| Insets / gaps | 16–20 pt outer, 10–14 pt between sections |
| Typography | native system face, roughly 13 pt support text and 15–16 pt editor text |
| Icons | native outline symbols with accessible labels |

These are engineering starting values, not user-mandated measurements. Respect system text scaling, contrast, Reduce Transparency and Reduce Motion. Maintain visible keyboard focus and appropriate contrast even over a bright or complex desktop.

## Floating panel anatomy

1. Header: **Anti-slop**, settings gear, close. No large toolbar.
2. Status/intent: one compact line, with progress indicator during real work. Use “Reading context…” only during capture/enrichment; then “Rewriting…”. On completion use a tentative result, such as “Looks like a product update.”
3. Main white editor: proposed replacement after validation. It is editable when ready, scrollable for longer passages, and supports ordinary native selection, copy, paste and undo.
4. Footer: subtle proposed Command-Return hint and one dark primary **Anti-slop** button. Disable during capture, generation, validation, invalid/stale target, or applying.

For a substantive original selection, an empty or whitespace-only user-edited draft disables **Anti-slop** and Command-Return, with “Enter replacement text to apply.” Recheck immediately before replacement. Clearing a preview is not an authorized delete action.

A single model call may return intent and rewrite together. Do not add a separate detector model merely to animate a stage. If no verified interim intent exists, leave the honest “Rewriting…” state until the result arrives. Do not invent progress percentages.

## Placement and animation

Capture selection bounds before moving focus. Prefer a nearby side with adequate space; try right, left, below, above using actual screen geometry. Clamp to the current display's usable frame, avoid covering the selected text when feasible, and handle multiple displays and scale factors. If no side fits, minimize overlap and retain a visible connection to the selection. When bounds are unavailable, use a stable position near the source window or pointer and do not claim exact anchoring.

Proposed entrance: 160–220 ms ease-out fade with 8–12 pt slide from the chosen edge. No bounce, large travel, or constant shimmer. Exit is brief and occurs after confirmed apply or explicit dismissal. With Reduce Motion use no slide; with Reduce Transparency use an opaque shell. Static comps do not validate any of these behaviors.

## State behavior

| State | Visible content | Allowed actions and exit |
|---|---|---|
| Needs setup | Same settings screen with concise readiness rows | Assign key, sign in/check, grant required OS access, Done |
| Capturing | Panel or lightweight status after trigger | Cancel; no apply and no source write |
| Generating | Spinner/status, stable reserved editor area | Cancel/settings; apply disabled |
| Ready | Tentative intent, editable proposal, primary action | Edit, apply, settings, dismiss |
| Editing | User's current text, unchanged intent or concise note | Apply current draft; late results cannot overwrite |
| Applying | “Replacing text…” and disabled apply | Single transaction; no duplicate submissions |
| Recoverable error | Useful draft retained plus short explanation | Contextual retry/check connection/copy/reselect, as relevant |
| Target changed | “The original selection changed. Your draft is safe.” | Copy or explicitly select again; no automatic paste |
| Done | Panel closes after verification | Focus returns to source; native undo verified where supported |

Settings may open while a draft exists; preserve that draft in memory. A settings change affects the **next** rewrite, avoiding silent regeneration over user edits. Closing while work is pending cancels the request; delayed completions are discarded by request identity. Ordinary Return inserts a newline. Proposed Command-Return applies only when enabled. Escape/close cancels without mutation. A repeated global trigger while this panel is active should focus the existing panel rather than create duplicates; it must not auto-apply.

## One settings screen for first launch and later use

Use the same screen, reachable from the panel gear, app launch and a small menu-bar/app menu entry. This recovery route works even when no shortcut is assigned or an assigned key is unusable. No separate onboarding wizard.

| Section/control | Behavior |
|---|---|
| AI connection | Show the supported runtime and truthful readiness: unavailable, sign-in needed, checking, ready, account limit/error. Required choices: **Codex** and **Claude Code**, each with its own readiness and normal provider-owned sign-in. No API-token field. Do not imply one connection signs into the other. **Manage** opens connection details/actions in this same screen; it offers the selected runtime's official sign-in or a readiness recheck, without handling credentials. |
| **Assign anti-slop key** | Enter recording mode, capture the next key or combination the user chooses, show it for confirmation. Let the user cancel and reassign. Do not impose spare-function-key suggestions as a constraint. |
| Writing style | One compact mutually exclusive choice: **No AI Slop** (recommended default), **Humanizer**, or **None** (core editing only). Short helper text describes each, not an entire skill document. |
| **Simplify wording** | Small optional toggle. Prefer familiar wording when it preserves precision. Default off; the comp illustrates an enabled choice rather than the factory default. |
| **Keep my tone** | Default on: retain the author's register, cadence, humor and emotional tone. Off permits a neutral register appropriate to the inferred audience and selected style, while custom instructions may specify another register. It never permits invented opinions, personality, facts or relaxed legal/factual fidelity. |
| Punctuation | Optional compact “Avoid em dashes” preference, default off; no authorship claim. This may be placed in a small expanded writing-options area to preserve simplicity. |
| Writing guide / **Add guide** | Expands a short name and pasted-excerpt field in this same screen; supports edit/remove. Proposed MVP avoids document imports/web fetching; no guide is required. |
| **Custom writing instructions** | Multiline text area with a short placeholder, such as “Keep my tone direct and friendly. Retain technical terms.” Persist locally, apply to subsequent requests, allow clearing. |
| OS access | Brief status/help appears when a capability actually needs permission. Explain what access enables. Accessibility is a likely requirement; request other access only if the chosen implementation needs it. |
| **Done** | Validate and atomically save edited preferences, then close settings. Incomplete setup may be saved; reopening shows what remains before rewriting can run. Invalid key assignment leaves the prior valid assignment intact. |

Do not show raw provider output, developer prompts, token accounting controls or transport jargon in ordinary flows. The private instructions still live as developer-readable versioned files in this package. Third-party attribution can be a small standard acknowledgements entry outside the rewrite flow.

## Shortcut recording and overriding

The user's requirement is open assignment: the chosen supported key becomes the Anti-slop trigger. Single keys and combinations are both valid candidates. macOS reserves some keys and exposes some hardware keys differently; record what is received, validate that registration can work, and explain a real limitation. Do not silently substitute a different shortcut or claim universal conflict detection.

Show known conflicts with the OS or Anti-slop; warn when an assigned ordinary key will be consumed in other apps. Unknown app-specific conflicts cannot be reliably promised away. Validate the new binding before replacing the old one. A user can cancel, remove or reassign through settings without invoking the shortcut.

Candidate engineering default: suspend the trigger while Anti-slop's own editor, custom-instructions text area or recorder has focus, so assigned characters do not break editing. This is an implementation recommendation, not a quoted user decision. Holding a key should produce one activation, not repeated model requests. Test supported single-key assignment as well as combinations, layout differences, input methods and system focus transitions.

## Feedback tone and accessibility

Use short concrete feedback: “Select some text first,” “Finish signing in to Codex,” “Couldn't replace the original selection. Your draft is safe.” Never blame the writer or label their passage as AI-written. Notes are concise and shown only when material.

Every icon needs a screen-reader name. Tab order follows the visual layout. Announce the ready/error state without repeatedly reading the whole draft. Keep text readable at increased size, buttons operable by keyboard and state differences perceivable without color alone. Test actual motion and screen-reader behavior; screenshots cannot prove them.
