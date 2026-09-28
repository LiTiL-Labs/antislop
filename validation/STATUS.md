# Validation status

Package version 0.2.1 · September 28, 2026

This is a validated specification handoff, not an implemented app. The checks below concern document/package integrity and authored contracts only.

This patch changes handoff portability only: the canonical kickoff is agent-neutral and `CLAUDE.md` imports the shared `AGENTS.md`. The previous kickoff filename is a short compatibility pointer. Product requirements, prompt/schema versions, editorial fixtures, profiles, source snapshots and images are unchanged.

## Completed package checks

- Canonical requirements reviewed against the final conversation: both Codex and Claude Code required; legal-professional fidelity; supported user-chosen keys; internal core prompt with custom writer instructions; generic plain text; final settings v3.
- Three static PNG comps visually inspected; the final settings image includes both provider choices and the current controls. These images do not prove account readiness or motion.
- Seven upstream files independently verified against recorded byte lengths, SHA256 and Git blob SHA-1, with pinned commits and preserved MIT notices. No skill installed or executed.
- JSON syntax, all authored local Markdown links, required file inventory and final decision consistency checked. The actual `@AGENTS.md` import resolves inside the package; canonical authored references use the neutral kickoff. No current authored instruction directs development specifically into Codex.
- The portability patch was compared with the prior package: all product/UX/architecture/prompt/profile/schema/fixture content, source snapshots and image assets retain their prior hashes. Changes are limited to entrypoints, handoff naming, source/validation notes and archive/checksum metadata.
- Three schemas checked against the full JSON Schema Draft 2020-12 metaschema using an isolated scratch installation of `jsonschema`; all three examples validated. All 18 fixture requests and illustrative response objects validated, including declared protected strings and boundary consistency. Negative cases cover missing required nullable note, empty replacement, extra output properties and unknown provider.
- Independent review found and corrected a tone-off example that lost meaning, specified the empty user-edited draft guard through apply, and clarified that the response note key is required but nullable.
- Package SHA256 manifest, ZIP integrity, exact archive inventory and every archived file byte checked.

The independent root review initially used standard-library coverage of schema keywords; the final package check added full metaschema validation. Neither type of schema check proves editorial quality.

## Not performed here

No app code was built, no runtime was signed into, no credential store was read, no live model request was made, and no selection was replaced in another application for this package. Authored editorial cases remain **not_run**. API documentation establishes candidate capabilities only. Clipboard, undo, actual animations, source-app compatibility and human acceptance remain development checks.

Full MVP completion requires both provider integrations and real generic replacement evidence. Human review must verify writing quality and preservation of legal meaning. A successful package validation does not satisfy those product criteria.

## Recheck the package

Run `python3 validation/validate.py` from the package root. With `jsonschema` installed in an isolated environment, this also performs full schema validation; otherwise it clearly reports that check as not run. An optional argument points to the ZIP for byte/inventory validation. The script performs no model requests or source-app actions.

See [ACCEPTANCE.md](../ACCEPTANCE.md) for the implementation acceptance matrix and [DEVELOPMENT_HANDOFF.md](../DEVELOPMENT_HANDOFF.md) for the execution brief.
