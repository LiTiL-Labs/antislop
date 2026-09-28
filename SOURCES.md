# Sources and evidence ledger

Prepared September 28, 2026. Product decisions come from the user's conversation, including the final changes to custom instructions, key assignment and required Claude Code support for a legal-professional audience. Public documentation below supports feasibility investigations; it is not evidence that this app has already integrated the APIs.

## Editorial references

The two first-release references are [No AI Slop by Peter Yang](https://github.com/petergyang/no-ai-slop) and [Humanizer by Siqi Chen / blader](https://github.com/blader/humanizer). Exact pinned snapshots, license notices, source URLs, Git blob verification and SHA256 checks are in [third_party/PROVENANCE.md](third_party/PROVENANCE.md) and [manifest.json](third_party/manifest.json). The application uses reviewed adaptations, not upstream agent workflows.

Caveman, Stop Slop and Elements of Style were explored earlier but are not the requested two profiles. The historical shortlist and primary draft remain outside this package. Their existence is research history, not a requirement to implement every candidate.

## Provider documentation

| Source | Narrow established fact | Unproven implementation work |
|---|---|---|
| [OpenAI authentication](https://learn.chatgpt.com/docs/auth) | Supported Codex account sign-in and runtime status routes are documented. | The user's chosen installed runtime/account is ready and usable by this new app. |
| [Codex noninteractive mode](https://learn.chatgpt.com/docs/non-interactive-mode) | Noninteractive execution, saved CLI authentication and schema-constrained final output are documented. | Correct version-specific invocation, isolation, cancellation, output parsing and account limits in Anti-slop. |
| [Codex App Server](https://learn.chatgpt.com/docs/app-server) | Rich product embedding exists; documentation distinguishes stable surfaces and experimental/production-qualified transports/commands. | Whether adopting it is necessary or suitable for this compact initial workflow. Reverify exact version/transport status. |
| [Claude Code programmatic mode](https://code.claude.com/docs/en/headless) | Official CLI supports programmatic requests and structured response options. | App adapter behavior, capability restriction and actual account-backed rewrite. |
| [Claude Code authentication](https://code.claude.com/docs/en/authentication) | Own-account runtime authentication is documented. | Correct active credential mode and billing/allowances on the installed runtime. |
| [Claude Code legal and compliance](https://code.claude.com/docs/en/legal-and-compliance) | Terms distinguish end-user sign-in to an unmodified official binary from prohibited third-party Claude.ai login and credential intermediation. | Validate Anti-slop's exact integration against current conditions; no claim of blanket permission for every SDK/product route. |

The Claude page includes both the own-binary sign-in allowance and restrictions; omitting either would misstate the candidate integration. Preserve the official binary, normal provider-owned sign-in and each end user's own agreement/billing. The app must not collect, store or relay Claude.ai credentials. Claude Code remains required; an unresolved route is a blocker to report, not a reason to silently remove support.

Earlier exploration checked local CLI version/help, not live inference or credential contents. This package author re-opened the official pages; it did not sign in, inspect tokens, call a model or prove a desktop-to-CLI shared session. Account access and limits are current-runtime facts to validate in development. “Local” describes the installed runtime and UI, not a promise of offline inference.

## macOS documentation

- [NSAccessibilityProtocol](https://developer.apple.com/documentation/appkit/nsaccessibilityprotocol): accessibility text/selection-related interfaces.
- [AXUIElementSetAttributeValue](https://developer.apple.com/documentation/applicationservices/1460434-axuielementsetattributevalue): attribute mutation API.

Attribute exposure/write support varies by control and app. Documented APIs do not prove universal selection reading or replacement. Revalidate targets, refuse unsafe writes, test a real generic plain-text baseline, and record supported behavior. Office/rich text is outside the initial proof.

## Visual and prompt history

The ready and processing comps illustrate the agreed floating panel. Settings v3 reflects both providers and the final key/custom-instructions choices. All three are generated static images, not running screens. Generation provenance for the final settings edit is bundled in [assets/settings-generation.md](assets/settings-generation.md).

The internal prompt version 0.2 develops the earlier standalone 0.1 draft with custom writer instructions, tone preference, pinned-profile composition and legal fidelity. No model evaluation has been performed for this package. Its authored fixture examples are proposed expectations.

## Development-agent portability

Packaging version 0.2.1 uses a neutral development kickoff and a minimal `CLAUDE.md` that imports `AGENTS.md` with native `@` syntax. [Claude Code memory documentation](https://code.claude.com/docs/en/memory#agentsmd) describes native AGENTS support with version/configuration limitations and the import fallback. The shared implementation rules remain in one file. This packaging update does not configure or execute Claude Code, install anything, touch credentials, or change the app's required Codex and Claude Code providers.
