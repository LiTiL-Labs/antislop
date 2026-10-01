# LiTiL Anti-Slop revision validation

September 30, 2026. Native macOS 27 / arm64 local checks. This records the consolidated prompt and controls revision; older receipts remain unchanged.

## Implemented

One hidden LiTiL prompt; old profiles/custom instructions/toggles removed; constant em-dash removal with literal/legal fidelity; capability presets and independent sentence complexity; orange `#ED692B` titles on all three screens; green `#123C2E` primary buttons; Lawyer bloom/pixels with Reduce Motion; menu-bar recovery; default-on launch-at-login preference; LiTiL footer link; licenses retained in the menu and bundle. Current schemas/prompts are 0.3; 0.2 settings migrate without losing either shortcut, provider, optional guide or saved model preference.

## Evidence

- **Automated:** 114 AntiSlopCore tests plus 3 AntiSlopMac tests passed. Coverage includes old-settings migration and removal of hidden custom instructions, all five prose levels in both modes, supported capability resolution for both providers, no invented effort/delegation, provider adapters, cancellation, selection identity, explicit replacement, persistence and failed-save UI behavior.
- **Native renders:** Settings (Balanced and Lawyer), rewrite and detection views rendered with SwiftUI/AppKit and synthetic fixture text. Orange headers, green primary buttons, Lawyer glow/pixels and pinned Settings footer visually reviewed. These are native rendered views, not live model or human-acceptance proof. See [Settings](litil-ui/settings-lawyer.png), [rewrite](litil-ui/rewrite.png) and [detection](litil-ui/detection.png).
- **Live account-backed Codex:** 3/3 synthetic requests returned valid proposals through the production adapter on runtime 0.159.2. [Receipt](live/codex-litil-smoke.json). Agent review: filler removed without strengthening “may”/“some teams”; legal obligation preserved including Section 4.2, parties, shall, 10 Business Days and written exception; em dash removed while preserving the offline-mode exception. This is a focused smoke test, not a complete editorial corpus acceptance.
- **Claude Code:** live model catalog loaded, including Opus, Sonnet and Haiku. The production adapter's account readiness reported “Sign-in needed: Sign in to Claude Code with your Claude account.” No live Claude rewrite result is claimed. Both providers remain implemented; fake-runtime tests passed.
- **Real replacement:** the local TextEdit fixture probe exercises the built app, actual Accessibility capture, global key events, edited drafts, explicit Apply and cancel. The initial run passed replacement checks but failed three recorder assertions because the probe looked for the obsolete “Current key:” accessibility label. The probe now targets “Current anti-slop key:”; the [final rerun](litil-textedit-e2e.json) passed **21/21 checks**, including all three recorder assertions.
- **Package checks:** 8 current document/source checks passed, including byte/hash verification of all seven upstream files. Full Python JSON Schema metaschema checks were skipped because `jsonschema` is not installed; Swift contract/schema checks passed. Original handoff checksums remain historical.
- **Build:** local release app assembled and ad-hoc signed at `app/build/Anti-slop.app`; both upstream license files copied into Contents/Resources/Licenses. No publishing or remote push.

## Remaining human/OS checks

Human visual acceptance, physical-key/VoiceOver review, and a real logout/login cycle remain unperformed. Startup is implemented with Apple's [SMAppService mainApp API](https://developer.apple.com/documentation/servicemanagement/smappservice): the default-on preference registers when Done saves; required approval/failure keeps Settings open with actionable text. Fixture checks deliberately do not register startup. The running user's older app process was preserved; restart that copy to load the rebuilt app, then save Settings.

Original `SHA256SUMS`, third-party source snapshots and historical receipts are preserved. `validation/validate.py` checks current docs/schema examples and migrated historical fixtures; original-package checksum verification is now opt-in with `--verify-original-checksums` against an original handoff copy.
