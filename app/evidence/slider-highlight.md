# Stronger slider effects and restored box highlight · 2026-09-30

At the user's request, Genius and Lawyer now have stronger bloom, more/larger/brighter pixels, and a restored colored card outline and glow. The outline uses the existing continuous rounded shape with a 1-point inset stroke to retain smooth corners.

The native appearance below maximum, native thumb geometry, 50%–100% directional track/effect fade, fixed Settings header/footer, exact brand colors and Reduce Motion behavior remain intact. The stronger effects fit within the same control bounds.

Validation: all six Mac tests passed with native render evidence enabled. Visually reviewed [normal and maximum settings](slider-highlight/slider-states.png) and [the full Settings view](slider-highlight/settings-lawyer.png). The release app rebuilt successfully, passed strict signature verification, and reports `Developer ID Application: LiTiL Labs, Inc. (5N876P35QC)` with team `5N876P35QC`. `git diff --check` passed.

These are native fixture renders, not live inference or physical-key acceptance. No provider, replacement, signing-policy or startup behavior changed. The existing app process was left running; reopen the built bundle to load the update.
