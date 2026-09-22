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
