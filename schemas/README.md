# Proposed data contracts

These JSON Schemas are version 0.2 design contracts, not a working provider client. They use JSON Schema Draft 2020-12. Provider adapters may translate the response schema to the supported subset without weakening application validation.

- [settings.schema.json](settings.schema.json) / [example](settings.example.json): local preferences only; no secrets or live readiness claim.
- [rewrite-request.schema.json](rewrite-request.schema.json) / [example](rewrite-request.example.json): model-visible task data, without native target handles or clipboard content.
- [rewrite-response.schema.json](rewrite-response.schema.json) / [example](rewrite-response.example.json): exact final object accepted by the preview.

The settings example uses Codex merely as a valid stored choice, not a requirement to prefer it over Claude Code. First launch may preselect an already-ready supported runtime; if both or neither are ready, present a clear choice. Both providers are mandatory for MVP.

Further host-side invariants:

- Reject whitespace-only source and unexpected secure/nontext controls before calling a provider.
- For `nearby_context`, `unavailable` requires null text. `document_boundary` requires an empty string. `known_excerpt` requires supplied text. Do not represent missing context as a known document boundary.
- Profile `none` pairs with revision `none`; the two bundled profiles pair with revision `0.2`. The app maps IDs to trusted rule resources and upstream pins, never arbitrary paths.
- Response validation rejects whitespace-only replacement for substantive source; exact unchanged source is valid. No wrapper prose, extra fields or partial parse.
- A shortcut's code/modifiers are a proposed normalized record. Actual interception support, reserved keys, layout/display labeling and conflicts are runtime-validated; a valid JSON object does not establish a working shortcut.
- Native request/session identity, generation/edit revisions, target handles, source fingerprints and apply verification remain private app state. The model cannot select the target.

Limit choices are proposed starting points from [ARCHITECTURE.md](../ARCHITECTURE.md). Persist schema versions and migrate preferences without silently dropping writer instructions or reassigning keys.
