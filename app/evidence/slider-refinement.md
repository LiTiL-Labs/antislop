# Slider refinement · 2026-09-30

Follow-up to the user's thumb-clipping, alignment, corner and intensity feedback.

- Below maximum, both controls use AppKit's native bar and thumb. Green (`#102D23`) and orange (`#ED692B`) tracks appear only at enabled Genius/Lawyer settings.
- Maximum tracks fade from 50% color alpha at the left to 100% at the right. Softer bloom and pixels follow the same directional fade. Bloom is clipped outside the track so it does not increase the track's specified alpha.
- The native thumb replaces the oversized custom circle. The maximum track and pixels share its coordinate system. Card fill and neutral 1-point border use the same continuous rounded shape; the colored card outline and outer card glow are removed.
- Reduce Motion stops the animation and omits particles; static maximum color and bloom remain.

Validation: six Mac tests passed, including native movement/accessibility actions, maximum-only state, thumb clearance and vertical alignment at three widths for both four- and five-stop sliders. Native render fixtures were visually inspected: [normal and maximum controls together](slider-refinement/slider-states.png), [maximum Settings](slider-refinement/settings-lawyer.png), [normal Settings](slider-refinement/settings-balanced.png). The release bundle at `build/Anti-slop.app` rebuilt successfully and passed `codesign --verify --deep --strict`.

These are native view fixture renders and geometry checks, not live provider requests or physical-key acceptance. Provider/replacement code did not change. The existing running app was not restarted; quit and reopen the rebuilt bundle to see these changes. Earlier `slider-polish` screenshots remain historical evidence.
