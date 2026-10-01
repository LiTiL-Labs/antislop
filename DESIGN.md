# Anti-Slop · LiTiL Labs interface

The native Mac app has three user screens: Settings/onboarding, rewrite preview, and slop findings. Keep editing central; settings are a single scrollable column between the pinned Anti-Slop title and pinned Done/footer row.

## Tokens

| Token | Value | Use |
|---|---|---|
| Orange | `#ED692B` (user supplied) | Large bold screen titles, Lawyer track and bloom/pixels |
| Green | `#102D23` (user supplied) | Primary buttons, Genius track and bloom/pixels, selected-control labels |
| Shell | `#FCFBF9` | Opaque warm surface behind orange titles for large-text contrast |
| Editor/card | White | Editable text and settings controls |
| Primary text | `#232322` | Body text and section titles |
| Secondary text | `#656563` | Helpers and status |
| Border | Primary at 12% | Quiet outlines |

Settings title is 30-point bold; panel titles are 22-point bold. Keep the exact orange on large text, not small body copy. Body text uses native system fonts. Spacing follows 4/8-point increments, with existing compact panel metrics retained. Primary actions have white labels on dark green. Native control focus and keyboard behavior remain available.

## Components and behavior

- `StepSlider`: title/current value, native AppKit slider and thumb, directly clickable labels. Below maximum, the bar keeps its native theme. Native tick snapping, keyboard navigation, focus ring and accessibility remain. Intelligence has four stops; Sentence Complexity has five. The slider exposes a named accessibility label and the current word value; label buttons also expose selected state. Cards use a shared continuous rounded shape with a 1-point inset border, neutral below maximum and branded at maximum.
- Maximum-level styling: Genius uses the same dark green as buttons; Lawyer uses the exact orange. The 12-point track fades from 50% brand alpha at the left to 100% at the right. Stronger bloom and larger, brighter animated pixels follow the same directional fade. A colored card outline with the same fade and an outer glow highlight the maximum setting. The bar and particles use the native thumb's coordinate system so the thumb remains centered and unclipped. Reduce Motion removes particles while retaining static color/bloom, box highlight and the selected text. Disabled sliders return to native styling and do not animate.
- Keyboard shortcuts use one shared usage note. Successful assignment changes the key badge; errors remain beside the affected key and specific OS/conflict caveats appear once below the shared note.
- `SettingsView`: key assignments, provider/readiness, Intelligence with resolved model/effort, Sentence Complexity, optional guide, launch-at-login, and conditional Accessibility setup. The orange Anti-Slop title, Done and the LiTiL link stay visible while content scrolls between the header and footer dividers. Close leaves the draft unsaved.
- `PrimaryButtonStyle`: shared green theme in all three screens; disabled state remains distinct.
- `PanelView`: the original adjacent preview/findings structure and explicit replacement controls. No additional dashboard or chat UI.
- Menu bar: template icon with an AS fallback, accessible label, Settings recovery, rewrite/detection actions, LiTiL link and Quit. License notices remain bundled as files; there is no licenses menu item or window.
- Startup: default-on draft preference, applied through macOS on Done. Failures keep Settings open, explain that other settings saved, and offer OS Login Items. Fixture mode never registers a login item.

The app uses native fixed-width utility windows: 540-point Settings with vertical scrolling capped to the current display, and a 430-point adjacent editor. No web/mobile layout is introduced. Source selection identity and explicit Apply stay outside model control.
