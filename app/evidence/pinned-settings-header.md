# Pinned Settings title and LiTiL signing · 2026-09-30

The orange Anti-Slop title is now a fixed header above the settings ScrollView, with the existing Done/footer row fixed below. The settings controls and notices scroll between them.

Native fixture renders were checked at the [top](pinned-settings-header/settings-balanced.png) and [bottom](pinned-settings-header/settings-scrolled.png) of the same 540 × 820 window. Both keep the title and Done visible. Six Mac tests passed, including the optional native render pass; the render helper scrolls the actual NSScrollView to its bottom before capturing that state.

`./scripts/build-app.sh` rebuilt `build/Anti-slop.app` and passed `codesign --verify --deep --strict`. Signature inspection confirmed:

```text
Authority=Developer ID Application: LiTiL Labs, Inc. (5N876P35QC)
Authority=Developer ID Certification Authority
Authority=Apple Root CA
TeamIdentifier=5N876P35QC
Identifier=local.antislop.app
```

The build script now defaults to that exact LiTiL certificate name. Explicit `SIGN_IDENTITY` overrides remain supported; failures do not silently fall back to ad-hoc signing. The result is a locally signed build. No notarization, upload or distribution was performed. The existing app process was not restarted.
