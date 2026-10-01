# Slider and shortcut polish

September 30, 2026. Follow-up to the consolidated LiTiL revision.

- Intelligence has a button-green (`#123C2E`) track and a stronger bloom/pixel effect at Genius. Sentence Complexity uses orange (`#ED692B`) with the same treatment at Lawyer.
- Tracks are now 14 points tall, with a 22-point white thumb, a brighter particle field along the track and rising colored pixels. A native NSSlider retains tick snapping, movement commands, target/action updates and accessibility. Reduce Motion removes particle animation; disabled sliders do not animate.
- Shortcut rows show the assignment and relevant errors. One shared note explains both controls. Duplicate generic warnings and success messages are removed; specific OS/key-conflict caveats remain and are deduplicated.

Validation: 114 core tests passed; 4 Mac tests passed, including native movement commands, accessible value updates, persistence/error handling and native renders. The initial direct synthetic keyDown test was unsuitable in a hidden window: vanilla NSSlider behaves the same way. The final test exercises AppKit moveRight/moveLeft and accessibility increment, without claiming physical-key acceptance. Native screenshots were visually checked for aligned particles, stronger green/orange treatment, and compact Home/End guidance: [maximum settings](slider-polish/settings-lawyer.png), [normal settings](slider-polish/settings-balanced.png).

Release build and signature verification are recorded with this local delivery. No provider inference, source replacement, startup registration or human acceptance is claimed for this visual follow-up. Earlier live/replacement receipts remain separate and unchanged.

## Exact green correction

The user subsequently supplied **#102D23** as the exact green. The shared action token now uses that value for buttons, the Intelligence track, bloom and colored particles. The earlier screenshots above retain the original reference-derived green; they are historical renders. The local release bundle was rebuilt for the corrected color.
