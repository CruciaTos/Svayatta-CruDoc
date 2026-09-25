# Prompts for Claude Code

Put this whole folder in the repo at `design/dashboard-redesign/` first.

---

## 1. Kickoff (send in Plan mode)

```
Redesign the Dashboard screen to match the design in @design/dashboard-redesign/

Read first:
- @design/dashboard-redesign/DESIGN_SPEC.md — the source of truth for every colour, size, radius and behaviour
- design/dashboard-redesign/screens/day.png and evening.png — the target look (open them)
- design/dashboard-redesign/reference/day.html and evening.html — use these when you need an exact measurement

Then inspect how the app works today: the current dashboard screen and its widgets, how the theme is set up, the Riverpod providers, and the repositories and models for visits, patients, revenue and inventory.

Constraints:
- Keep the existing architecture: feature-first folders, Riverpod, and the repositories (e.g. VisitRepository) as the only data source. Widgets must not talk to SQLite or Firestore directly.
- Put all tokens in one place: a ThemeExtension for colours with Day and Evening variants, plus type, radius and spacing constants. No hard-coded colours in widgets.
- Bundle the Geist TTFs from design/dashboard-redesign/fonts/ as assets and register the family in pubspec.yaml.
- Never show sample or fabricated data. If the data behind an element doesn't exist yet (for example token number, vitals, allergies, follow-ups, lab results, UPI/cash split, or a "waiting" visit status), hide that element and list it as a gap. Do not add fields to models or change the database without asking me.
- Changing the global palette will affect other screens. List which ones, and don't change their layouts.

Give me a plan with:
1. The files you will create or change.
2. A table mapping every dashboard element in the spec to its data source (an existing provider or repository method, or "gap").
3. These phases, each ending with `flutter analyze` passing:
   - Phase 1: tokens, theme and fonts
   - Phase 2: shared widgets (card, capsule button, segmented control, status dot, monogram, chips, icon tile, progress ring)
   - Phase 3: dashboard layout with real data, Day appearance
   - Phase 4: Evening appearance, Wrap up card, time-aware greeting, automatic Day/Evening switching with a setting
   - Phase 5: remove the old dashboard widgets that are no longer used; check the layout at 1440, 1280, 1024 and 800 px wide

Stop after the plan. We'll implement one phase at a time.
```

---

## 2. After you approve the plan

```
Implement Phase 1 only. Run flutter analyze, summarise what changed, then stop.
```

Repeat for each phase ("Implement Phase 2 only…").

---

## 3. Visual check (after Phase 3 and Phase 4)

```
Write a golden test that renders the dashboard at 1440×1148 with fake providers (test code only) in the Day appearance, loading the bundled Geist font so text renders correctly. Generate the golden, open the image, and compare it with design/dashboard-redesign/screens/day.png. List every difference in spacing, size, colour or radius, fix them, and repeat until it matches. Then do the same for Evening at 1440×988 against screens/evening.png.
```

---

## 4. Answering gaps

When the plan lists gaps (for example "no token number on Visit"), decide per gap, then say for example:

```
Gap decisions: add tokenNumber (int) to Visit and assign it on check-in; hide vitals for now; follow-ups — use visits with a follow-up date, add followUpDate (DateTime?) to Visit. Update the plan, then continue with the current phase.
```
