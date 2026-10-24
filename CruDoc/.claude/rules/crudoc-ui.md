---
paths:
  - "lib/**/*.dart"
---

# CruDoc UI rules (Calm Clinical)

Full spec: design/dashboard-redesign/DESIGN_SPEC.md

- Never hard-code colours, radii, font sizes or spacing in widgets. Use the design tokens (colour ThemeExtension, type styles, radius and space constants).
- Ink Blue (accent) is only for: app mark, the one primary action, the Up next card, progress rings, "now" states, links. No other blue anywhere.
- Red is only for allergies and patient safety. Violet is only for AI-generated content. Amber means waiting. Green means done.
- One filled button per region. Secondary actions use inset fill; list actions use capsule buttons.
- Radii: cards 24; anything inset 12 px inside a card, buttons and inputs 12; icon tiles 10; chips, pills and avatars fully round. Inner radius = outer radius − inset.
- Spacing uses the 4-pt grid: 4, 8, 12, 16, 20, 24, 32.
- All numbers (times, counts, rupees, vitals) use tabular figures.
- Font is Geist, bundled as an asset. Never fetch fonts at runtime.
- Never show sample or fabricated data in app code. If data is missing, hide the element.
- Patient avatars are grey monograms, never coloured.
- Motion: 200–250 ms, easeOutCubic, no bounce.
- "Same box" transitions are opt-in: use them only when asked for a particular element, never by default. When asked (full guide: design/motion-transitions.md; reference: Schedule Week ⇄ Day): the tapped element is one box that grows on all four sides into the next view's card, and its contents transform in place into the next view's contents (positions, sizes, styles, scale lerp; differing looks cross-fade inside the same moving rect). The last frame must equal the destination, so the hand-over is invisible; scroll and selection carry across both ways; reverse is the same motion backwards. No end-of-motion swaps, clip-window reveals or slide-ins. Verify with rendered frames and a pixel diff of last frame vs destination.
