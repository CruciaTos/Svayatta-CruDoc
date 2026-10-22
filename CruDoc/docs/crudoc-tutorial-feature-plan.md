# CruDoc first-run tutorial (guided tour) — build spec

> Hand this file to Claude Code. Read the whole file before writing any code.

## 0. Before you start

1. Read `.claude/rules/crudoc-ui.md` and `design/dashboard-redesign/DESIGN_SPEC.md`. Every rule there applies to the tour (tokens, colours, radii, spacing, motion, Geist, tabular figures).
2. Read these files so you know where the tour plugs in:
   - `lib/features/shell/presentation/responsive_shell.dart` (onboarding → shell hand-off, `kDesktopBreakpoint = 900`)
   - `lib/features/shell/presentation/desktop_shell.dart` (sidebar, search focus node, Ctrl shortcuts)
   - `lib/features/shell/components/cru_sidebar.dart` (nav groups and items)
   - `lib/features/dashboard/presentation/widgets/dashboard_header.dart` (`Add patient`, `New appointment`)
   - `lib/features/dashboard/presentation/widgets/up_next_card.dart`
   - `lib/features/mobile/mobile_shell.dart`, `mobile_nav_bar.dart`, `mobile_home.dart`, `mobile_island.dart`, `mobile_more.dart`
   - `lib/features/onboarding/presentation/onboarding_flow.dart` (how `onboarding` is saved to the profile)
   - `lib/core/services/demo_session_service.dart`
3. Confirm each target listed in section 4 actually exists where this spec says. If one doesn't, tell me and propose the nearest equivalent before building around it.
4. Do not add a third-party tour/showcase package. Build it in-house (it's small, and it must follow our design tokens exactly).

## 1. What we're building

A short, Duolingo-style guided tour shown once to a first-time user, right after onboarding. The app stays visible underneath; the screen dims and a spotlight cut-out highlights one real UI element at a time, with a small card explaining it.

- Core features only. **6–8 steps per platform, max.** Each step's body is one sentence, ideally under 15 words.
- Every step has **Next** and **Skip**. Steps after the first also have **Back**. Last step's Next reads **Done**.
- Step counter `2 of 7` plus progress dots.
- Two separate tours: **desktop** (width ≥ `kDesktopBreakpoint`) and **phone** (MobileShell). The UIs differ, so the steps differ.
- Can be replayed any time from Settings.

## 2. When it shows

Show the tour automatically when **all** are true:
- The shell (Desktop or Mobile) is on screen and the clinic access/profile has loaded (not during `_loading`).
- The user has no tour record for this platform at the current `kTutorialVersion` (see section 6).
- No other overlay/dialog is up (clinic invite from `ClinicInviteWatcher`, referral announcement, update prompt, onboarding). If one appears mid-tour, pause the tour and resume on the same step once it's closed.

Cases:
- **New doctor finishing onboarding**: starts after `OnboardingFlow.onDone`, on first frame of the shell, after a ~400 ms settle delay.
- **Clinic members (doctor/staff who joined, they skip onboarding)**: also get the tour on first entry. Steps whose feature they can't access are dropped (section 5).
- **Existing users who already used the app before this ships**: do NOT auto-show. Treat profiles with `onboarding.completedAt` older than the release, or any existing patients, as "seen". Ask me if you'd rather show it once to everyone.
- **Demo mode** (`DemoSessionService.isDemoMode`): show it every fresh demo session, never write the record to Firestore (local only).
- Resizing the window across the breakpoint mid-tour: end the current tour silently (don't mark it seen) and let the other platform's tour logic decide.

## 3. Behaviour

- **Next**: advance. Enter, Space and → also advance on desktop.
- **Back**: previous step. ← also goes back on desktop.
- **Skip**: ends immediately, no confirm dialog. Record `skippedAt` + the step index. Show a small snackbar/toast: *"You can take the tour again from Settings."* Esc also skips on desktop.
- **Done** (last step): record `completedAt`.
- Taps on the dimmed area do nothing (don't advance, don't close). Taps inside the spotlight do nothing either; the user is learning, not acting. (Keep it non-interactive for v1.)
- Android back button / system back gesture = Back; on step 1 it = Skip.
- If a step's target isn't on screen (feature disabled, widget not built, empty state), skip that step automatically and don't count it in `N of M`.
- If the target is inside a scrollable, scroll it into view first (`Scrollable.ensureVisible`, 250 ms).
- Re-measure the spotlight on resize, rotation, text-size change and scroll.
- Steps that need a different tab (e.g. Schedule on phone) switch to that tab before spotlighting. When the tour ends, return the user to Home/Dashboard.
- Do not create, seed or fake any data for the tour. Rule from `crudoc-ui.md`: never show sample data. If a list is empty, spotlight its button or empty state instead.

## 4. The steps

Copy is a draft; keep it plain and short. Doctor-facing, Indian English is fine, no exclamation marks except the welcome.

### Desktop tour (`TutorialPlatform.desktop`)

| # | Target | Title | Body |
|---|--------|-------|------|
| 1 | none (centred card) | Welcome to CruDoc | A 1-minute tour of the essentials. Skip any time. |
| 2 | Sidebar (`CruSidebar`) | Everything lives here | Today, Patients and Clinic tools. Ctrl + B hides it. |
| 3 | Search field (the one `_searchFocusNode` focuses) | Find anyone fast | Search patients by name or phone. Press Ctrl + K from anywhere. |
| 4 | `Add patient` button in `dashboard_header.dart` | Add a patient | Register a new patient in under a minute. |
| 5 | `New appointment` button in `dashboard_header.dart` | Book a visit | Schedule appointments; they show up in Schedule and the queue. |
| 6 | Up next card (`up_next_card.dart`) | Who's next | Your next patient, always at the top of the dashboard. |
| 7 | Sidebar item `Scribe` | AI scribe | Speak during the visit; CruDoc drafts the notes for you. |
| 8 | Account menu / avatar (where Settings opens) | You're set | Settings, plan and this tour again live here. |

If the Up next card isn't rendered (no appointments today), spotlight the `Schedule` sidebar item for step 6 with body: *"Today's appointments and walk-ins, in order."*

### Phone tour (`TutorialPlatform.mobile`)

| # | Target | Title | Body |
|---|--------|-------|------|
| 1 | none (centred card) | Welcome to CruDoc | A quick look at the essentials. Skip any time. |
| 2 | Home tab, Up next card in `mobile_home.dart` (fallback: Home nav item) | Your day at a glance | Who's next and what's waiting, right on Home. |
| 3 | Nav item `Schedule` | Schedule | Today's visits. Swipe a row right to check someone in. |
| 4 | Nav item `Patients` (then its Add patient button if visible) | Patients | All your patients. Tap + to add a new one. |
| 5 | Nav item `Tasks` | Tasks | Follow-ups and to-dos so nothing slips. |
| 6 | Black pill at the top (`mobile_island.dart`) | Quick actions | Tap the pill for quick actions while you work. |
| 7 | Nav item `More` | You're set | Revenue, settings and this tour again are in More. |

Verify the gesture copy against `showMobileGestureGuide` in `mobile_more.dart` so the tour and that guide agree.

Specialty-specific items (dental, radiology, homeopathy, therapy) are **not** in v1. Keep the step list data-driven so we can add them later per specialty.

## 5. Role and module gating

- Before showing a step, check the same guards the shell uses (`clinicAllowsMobileTab`, `DoctorFeatureGuard`, enabled modules). If the user can't open that feature, drop the step.
- Scribe step only if the scribe/AI module is enabled for this account.
- Staff without patient access: drop patient steps. Never spotlight something the user would get a "not available" screen for.

## 6. Persistence

Store per user, per platform, versioned:

```
profiles/{uid}.tutorial = {
  desktop: { version: 1, completedAt | skippedAt: Timestamp, lastStep: int },
  mobile:  { version: 1, completedAt | skippedAt: Timestamp, lastStep: int },
}
```

- Use whatever profile write path `onboarding_flow.dart` uses (merge write, don't overwrite other fields). Check `firestore.rules` allows the user to write `tutorial` on their own profile; update the rules if not, and show me the rules diff.
- Mirror to `shared_preferences` (`crudoc.tutorial.<platform>.v<version>`) so it never flashes on start while the profile is loading, and so it works offline. Either source saying "seen" = seen.
- `const kTutorialVersion = 1;` in one place. Bumping it re-shows the tour (for future big redesigns).
- Log `tutorial_started`, `tutorial_completed`, `tutorial_skipped (step)` through `feature_usage_service.dart` if it fits; don't add a new analytics dependency.

## 7. Replay

- **Desktop**: in `desktop_settings_screen.dart`, add a row *"Take the tour again"* (help icon). Tapping it closes settings, goes to Dashboard, starts the desktop tour from step 1.
- **Phone**: in `mobile_more.dart` settings list, directly under *"How the phone app works"*, add *"Take the tour again"* with the same `MobileRow` + `MobileIconTile(icon: CruIcons.help, tone: MobileTone.slate)` style.
- Replaying never changes `skippedAt`; finishing it sets `completedAt`.

## 8. Visual design (follow crudoc-ui.md; these are the specifics)

- **Scrim**: full-screen dim over the app, using an existing scrim/overlay token from the colour ThemeExtension (add one to `crudoc_shared` tokens if missing, don't hard-code). Works in light and dark appearance.
- **Spotlight**: a rounded-rect cut-out around the target, padded 8 px, radius = target's own radius + 8 (inner radius = outer − inset rule). Circular targets (avatar, nav icons) get a round cut-out. Thin 2 px accent ring around the cut-out is allowed (Ink Blue = "now" state).
- **Card**: card radius 24, padding 20, max width 360 desktop / screen width − 32 on phone. Placed below the target if there's room, else above; on phone prefer above the nav bar. A small pointer/notch toward the target is optional; skip it if it complicates things.
- **Card contents**: title (title3-style token), body (body token, secondary label colour), then a footer row: `Skip` (plain text/capsule, left), dots + `2 of 7` (tabular figures, centre or left), `Back` (inset fill) and `Next`/`Done` (the one filled Ink Blue button, right).
- Welcome card (step 1): centred, no spotlight, uses the app mark. Buttons: `Start tour` (filled) and `Skip`.
- The Scribe step is about AI: a small violet AI badge on the card is allowed there and only there.
- **Motion**: 200–250 ms, `easeOutCubic`, no bounce. Spotlight morphs from previous target to the next (animate rect + radius); card cross-fades and slides 8 px. Respect reduced-motion (`MediaQuery.disableAnimations`): no morph, instant swaps.
- Text size: must not clip at the app's largest text-size setting (`appearance_provider.dart`).

## 9. Architecture

Create `lib/features/tutorial/`:

```
tutorial/
  data/
    tutorial_repository.dart     // read/write Firestore + shared_preferences, version check
  domain/
    tutorial_step.dart           // id, targetKey (TutorialTarget enum), title, body, optional prepare() e.g. switch tab, isAvailable(ref)
    tutorial_steps.dart          // desktopSteps, mobileSteps (data only, copy lives here)
  presentation/
    tutorial_controller.dart     // Riverpod Notifier: idle/running(stepIndex)/paused; next, back, skip, finish, start(platform)
    tutorial_overlay.dart        // OverlayEntry: scrim painter + spotlight + card, keyboard + back handling
    tutorial_card.dart
    tutorial_target.dart         // TutorialTarget enum + a TutorialAnchor widget that registers a GlobalKey
```

- Targets are marked by wrapping the real widget: `TutorialAnchor(target: TutorialTarget.addPatient, child: ...)`. Anchors register into a provider map; the overlay reads `RenderBox` bounds from them. Keep the wrapping minimal; no layout changes to the wrapped widgets.
- Start logic lives in one place: a `TutorialGate` widget around the `DesktopShell` / `MobileShell` returned by `ResponsiveShell`, which checks the conditions in section 2 and calls `controller.start(platform)`.
- Scrim cut-out: `CustomPainter` with `Path.combine(PathOperation.difference, ...)`, wrapped in a pointer-absorbing layer.
- Accessibility: card is a focus trap with `Semantics(liveRegion: true)` announcing `"Step 2 of 7. Find anyone fast. Search patients..."`; buttons have semantic labels; tab order Skip → Back → Next.
- Don't touch business logic in any feature screen beyond adding `TutorialAnchor` wrappers and the two replay rows.

## 10. Tests

Add widget tests under `test/features/tutorial/`:
- Shows after onboarding `onDone`; doesn't show when record exists at current version; shows again after version bump.
- Next/Back/Skip/Done transitions and the persisted fields.
- Missing target is skipped and the counter adjusts.
- Gated step (module disabled) is dropped.
- Demo mode writes nothing to Firestore.
- Esc/Enter/arrow keys on desktop; system back on phone.
- Resize across breakpoint ends tour without marking seen.

Run `flutter analyze` and the test suite; both must pass with no new warnings.

## 11. Done when

- [ ] Fresh account: onboarding → tour appears on desktop and (separately) on phone.
- [ ] Every step spotlights the correct real element, in light and dark, at default and largest text size, at 900 px, 1280 px and 1920 px wide, and on a small phone (360 × 640).
- [ ] Skip at any step ends it, toast shown, never auto-shows again.
- [ ] Replay works from desktop Settings and phone More.
- [ ] Staff account sees only steps for features they can open.
- [ ] No hard-coded colours/radii/spacing/fonts; no sample data; no new packages.
- [ ] `flutter analyze` clean, tests green.

## 12. Work order

1. Show me the step list with the exact widget each `TutorialAnchor` will wrap (file + line) before coding. Wait for my OK.
2. Build `tutorial/` (domain → data → controller → overlay/card).
3. Add anchors, `TutorialGate`, replay rows, Firestore rules change.
4. Tests, `flutter analyze`, then a short summary of what changed and anything you couldn't do.
