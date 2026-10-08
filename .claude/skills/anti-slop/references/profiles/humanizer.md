# Humanizer: reviewed style profile 0.2

The alternative: a broader review of rhetorical patterns. Adapted from Siqi Chen / blader's Humanizer, pinned at upstream commit `225a6f39ac85f76ee48dbad772ea4abe4ed6c9d8` (upstream version 3.1.0); MIT notice in `../../licenses/humanizer-LICENSE.txt`. This adaptation narrows the upstream pattern catalog to faithful editing of the passage. It does not adopt the upstream permission to add reactions, opinions or creative details. The core contract in `SKILL.md` outranks every rule here.

## Editorial rule body

<!-- BEGIN canonical: prompts/profiles/humanizer.md "Editorial rule body" (profile 0.2). Keep verbatim; app/scripts/sync-skill.py checks and refreshes this block. -->
Review the passage for inflated significance, vague attribution, promotional adjectives, repetitive rhetorical staging, mechanical rhythm, unnecessary formatting and leftover conversational-assistant framing. Correct a pattern only when it creates a concrete problem for this passage's purpose and audience.

Retain the writer's existing point of view, reactions, formality and deliberate rhythm. Vary sentence construction naturally where repetition is distracting, without inserting opinions, personal experiences, intentional errors or invented creative details.

Prefer concrete verbs and source-supported statements to inflated abstractions. Cut duplicative explanation without deleting real facts, attribution, scope, uncertainty or qualifications. Unsupported-looking content must not be replaced by an invented source or stronger claim.

Reduce repetitive “not X but Y” constructions, automatic triplets, empty summations, title-like labels and generic encouragement only when they add no meaning. Preserve useful lists, true contrasts, quotations, legal enumerations and exact defined terms.

Evaluate dashes, words and sentence length in context. Respect compatible explicit writer preferences without treating punctuation as an authorship signal. For legal or technical material, precision outranks conversational ease.

Perform any self-check internally. Return only the final structured app response; no preliminary draft, critique, separate final version or authorship judgment. Already-clear text may remain unchanged.
<!-- END canonical: prompts/profiles/humanizer.md -->
