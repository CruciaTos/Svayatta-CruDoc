# Dashboard redesign — implementation plan

Branch: `feat/dashboard-redesign`. Source of truth: `DESIGN_SPEC.md`.
Flutter 3.41.6 (has `RoundedSuperellipseBorder`), Riverpod 3.3, go_router.

## 1. What exists today

| Area | Today |
|---|---|
| Desktop shell | `features/shell/presentation/desktop_shell.dart`: white floating sidebar (220/76 px) over an animated cyan "grainient" background, specialty card, mobile-app promo, floating draggable chatbot button. `ResponsiveShell` switches to the mobile `Shell` below **900 px**. |
| Desktop dashboard | `features/dashboard/presentation/desktop_dashboard_screen.dart` (2 247 lines): header with duplicate date/doctor chips, Consultations + Total Patients cards, Quick Actions (buttons have no handlers), Recent Patients table, Activity Logs, Your Appointments, Upcoming Visits, **static "AI Smart Insights"**, **static "Pending Tasks"** (hard-coded "Interview", "Team Meeting"…). |
| Theme | `ThemeData` built inline in `main.dart` from `AppColors` (seed `#2D9CDB`, Plus Jakarta Sans). No ThemeExtension, no dark theme. |
| Data | Riverpod providers over repositories (SQLite local-first + Firestore sync). |

## 2. Files

### Create
| File | Purpose |
|---|---|
| `assets/fonts/Geist/Geist-{Regular,Medium,SemiBold,Bold}.ttf` + `OFL.txt` | Bundled Geist (copied from `design/dashboard-redesign/fonts/`) |
| `lib/core/theme/cru_colors.dart` | `CruColors` ThemeExtension: `day`, `evening`, `onInk(day/evening)`; brand scale; shadows |
| `lib/core/theme/cru_type.dart` | `CruType` text styles (Geist, tabular figures helper) |
| `lib/core/theme/cru_tokens.dart` | `CruRadius`, `CruSpace`, `CruMotion`, `CruSize` constants |
| `lib/core/theme/cru_theme.dart` | `CruTheme.day()` / `CruTheme.evening()` ThemeData; `CruAppearance` enum |
| `lib/shared/widgets/cru/*.dart` | Shared widgets: `CruCard`, `CruButton` (filled / secondary / tinted / inset), `CruCapsuleButton`, `CruSegmentedControl`, `CruStatusDot`, `CruMonogram`, `CruChip`/`CruPill`, `CruIconTile`, `CruProgressRing`, `CruIcon` (stroke icons painted from the reference SVG paths, so goldens need no icon font), `CruPressable` (hover fill / 0.98 press / reduced motion) |
| `lib/features/dashboard/domain/dashboard_models.dart` | Pure view models (glance, up next, schedule rows, attention items, collections, wrap-up) |
| `lib/features/dashboard/domain/dashboard_builder.dart` | Pure functions that turn repository data + `now` into those view models (unit-testable) |
| `lib/features/dashboard/data/providers/dashboard_providers.dart` | Riverpod providers that read the **existing** providers and call the builder; `dashboardClockProvider` (ticks every 30 s) |
| `lib/features/dashboard/data/providers/doctor_identity_provider.dart` | Stream providers wrapping `DoctorProfileHelper.watchDoctorProfile` and `DoctorSubscriptionService.watchSubscriptionInfo`, so widgets never touch Firestore |
| `lib/features/dashboard/data/appearance_preferences.dart` + `providers/appearance_provider.dart` | Auto / Day / Evening setting (shared_preferences) and the resolved appearance |
| `lib/features/dashboard/presentation/dashboard_screen.dart` | New desktop dashboard (responsive) |
| `lib/features/dashboard/presentation/widgets/*.dart` | `DashboardHeader`, `GlanceCard`, `UpNextCard`, `ScheduleCard`, `NeedsAttentionCard`, `CollectionsCard`, `WrapUpCard`, `DashboardSearchField` |
| `lib/features/shell/components/cru_sidebar.dart` | New sidebar (groups, clinic switcher, trial footer, account menu), expanded 248 px / collapsed icons |
| `lib/features/shell/presentation/desktop_shell_layout.dart` | Pure layout (sidebar + content) used by `DesktopShell` and by the golden tests |
| `test/dashboard/dashboard_builder_test.dart` | Unit tests for the data mapping |
| `test/dashboard/dashboard_layout_test.dart` | No-overflow tests at 1440 / 1280 / 1024 / 800 px |
| `test/dashboard/dashboard_golden_test.dart` + `goldens/` | Day 1440×1148, Evening 1440×988 (fake providers, Geist loaded) |

### Change
| File | Change |
|---|---|
| `pubspec.yaml` | Register `Geist` family (400/500/600/700) |
| `lib/main.dart` | Use `CruTheme.day()` as the app theme |
| `lib/features/shell/presentation/desktop_shell.dart` | Neutral canvas instead of the grainient background; new sidebar; Day/Evening theme scoped to shell + dashboard; floating chatbot button kept only on non-dashboard tabs (dashboard uses "Ask CruDoc" in search); non-dashboard screens wrapped in the Day theme so they stay readable in the evening |
| `lib/features/chatbot/presentation/chatbot_screen.dart` | Optional `initialPrompt` to prefill the question typed in the dashboard search (not sent automatically) |
| `lib/core/utils/doctor_profile_helper.dart` | Add `tryFormatDoctorName` / `tryFormatClinicName` that return `null` instead of the hard-coded fallbacks ("Dr. Vinit Parab", "CruDoc Healthcare"); existing methods keep their behaviour |
| `lib/features/settings/presentation/desktop_settings_screen.dart` | One "Appearance: Auto / Day / Evening" row (no layout change) |

### Remove (phase 6)
`desktop_dashboard_screen.dart` (old widgets), the unused duplicate `features/dashboard/providers/Recent activity provider.dart`, `GrainientBackground`, `SidebarSpecialtyCard` and the download card if nothing else uses them. `recent_activity_provider.dart` and `activity_item.dart` stay (mobile dashboard uses them).

### Other screens affected by the palette
The global theme changes (Ink Blue primary, Geist default font, canvas scaffold). Screens that hard-code their colours (most of them: Patients, Inventory, Revenue, Appointments, Campaigns, Scribe, Queue, Settings, mobile dashboard) keep their look apart from the default font. Screens reading `Theme.of(context).colorScheme` get Ink Blue instead of `#2D9CDB`. No layout changes. Evening is **not** applied app-wide: those screens paint light panels and rely on default dark text, so a global dark theme would make them unreadable. Evening is therefore scoped to the shell chrome + dashboard.

## 3. Element → data source

Providers named below already exist unless marked *new (derived)*. A *derived* provider only combines existing providers; it never reads SQLite/Firestore itself.

| Spec element | Data source | Status |
|---|---|---|
| **Sidebar** app mark, wordmark | static | ✓ |
| Clinic switcher: clinic name, specialty | `DoctorProfileHelper.watchDoctorProfile` via *new* `doctorProfileProvider`; `tryFormatClinicName`, `formatSpecialty` | ✓ (hidden letter tile/name if no clinic name set) |
| Clinic switcher action | existing `showSpecialtySwitcherDialog` | ✓ (one clinic per doctor; it switches specialty) |
| Queue item waiting count | `todaysQueueProvider` (status `waiting`) | ✓ |
| Footer "Free trial · N days left" + Upgrade | `DoctorSubscriptionService.watchSubscriptionInfo` via *new* `subscriptionInfoProvider` (`daysRemaining`, `doctorStatus`, `planName`); `FeatureUpgradeSheet.show` | ✓ (hidden when no expiry) |
| Profile row name | `doctorProfileProvider` + `tryFormatDoctorName` | ✓ |
| Account menu: appearance, settings, help, log out | *new* `appearanceModeProvider`; existing screens; `AuthService.signOut` | ✓ |
| Mobile-app download in account menu | the old card had no link or action | **GAP** (hidden) |
| **Header** date, greeting | clock | ✓ |
| Greeting name | `doctorProfileProvider` | ✓ |
| Search: patients | `patientsStreamProvider` | ✓ |
| Search: "Ask CruDoc" | `ChatbotScreen.show(initialPrompt:)` | ✓ |
| Add patient | `showAddPatientSheet` | ✓ |
| New visit | `CheckInDialog.show` → `QueueRepository.checkIn` | ✓ |
| **Glance** Seen today "5 of 13", ring, "8 still to see" | `todaysQueueProvider` + `todaysVisitsProvider` (completed vs total, cancelled excluded) | ✓ |
| Waiting now count | `todaysQueueProvider` (`QueueStatus.waiting`) | ✓ |
| Average wait | `now − QueueEntry.checkedInAt` over waiting tokens | ✓ |
| Follow-ups due / overdue | no follow-up date on `Visit` or `Patient`; `ConsultationNote.followUpDate` is only an AI-extracted draft value with no cross-patient query | **GAP** (cell hidden) |
| Collected today | `recentRevenueEntriesProvider` (income, not deleted, today) | ✓ |
| "↑ ₹600 vs last Wednesday" | same provider, same weekday −7 days | ✓ |
| **Up next** = earliest waiting | `todaysQueueProvider` ordered like `QueueRepository.callNext` (urgent first, then token number) | ✓ |
| Token number | `QueueEntry.tokenNumber` | ✓ |
| Wait pill | `QueueEntry.checkedInAt` | ✓ |
| Name, age, sex | `patientsStreamProvider` (`Patient.age`, `gender`); walk-ins use `walkInName` | ✓ |
| Returning / New patient | `allVisitsProvider` (earlier visit exists?) + `Patient.createdAt` | ✓ |
| Last visit date + last diagnosis | `allVisitsProvider` (latest earlier visit), `Patient.diagnosis.last` | ✓ |
| Reason for visit | `QueueEntry.reason`, else linked `Visit.treatmentType` | ✓ (hidden if empty) |
| Allergy chip / "No known allergies" | no allergy field on `Patient` | **GAP** |
| BP / Temp / SpO₂ / Weight chips, "Recorded 11:41 by front desk" | no pre-consultation vitals record (`ConsultationNote.vitals` is captured during the consultation, and has no weight or SpO₂) | **GAP** (whole "Alerts and vitals" block hidden) |
| Start consultation | `QueueRepository.callNext` + `startConsultation` | ✓ |
| View history | `DesktopPatientDetailsScreen` | ✓ (hidden for unregistered walk-ins) |
| "…" menu | `QueueRepository.skip` / `cancel`, open Queue | ✓ (no reschedule for walk-in tokens) |
| Empty state "No one waiting · next booking at 12:30" | `todaysVisitsProvider` (next scheduled, not yet checked in) | ✓ |
| **Schedule** rows (time, name, age/sex, reason) | `todaysVisitsProvider` ∪ `todaysQueueProvider` joined with `patientsStreamProvider` | ✓ |
| Row status In consultation / Waiting · N min / Booked / done | `QueueStatus`, `VisitStatus` | ✓ |
| Visit type text "Follow-up" | no visit-purpose field | **GAP** (shows Returning / New patient / Walk-in / Home visit instead) |
| Header count + time range | same | ✓ |
| Segmented All / Waiting n / Done n | same | ✓ |
| Completed collapse, future-session collapse | same; evening session starts at the default 17:00 | ✓ |
| "That's the last booking for today." + Add a walk-in | same; `CheckInDialog` | ✓ |
| **Needs attention** stock | `lowStockMedicinesProvider`, `expiringMedicinesProvider` | ✓ ("about N days left" needs a consumption rate: **GAP**; shows reorder level instead) |
| Needs attention labs (HbA1c result) | no lab results model | **GAP** |
| Needs attention follow-ups overdue | see follow-ups | **GAP** |
| **Insights** (AI) | nothing generates AI insights from records; violet is reserved for AI output, so rule-based numbers can't be shown there | **GAP** (card hidden; static insights removed) |
| **Collections** total, 7 bars, today label | `recentRevenueEntriesProvider` | ✓ |
| UPI / Cash split | `RevenueEntry` has no payment method | **GAP** (line hidden) |
| **Wrap up** "N patients left" | queue + visits | ✓ |
| "clinic closes at 8:00 PM" | no clinic hours stored | **GAP** (clause hidden) |
| Prescriptions to sign | nothing to sign exists; closest real record is AI Scribe drafts awaiting review (`notesForVisitProvider` per today's visit, `ConsultationNoteStatus.draft`) | shown as "N scribe notes to review" (label changed, real data) |
| Overdue follow-ups | see follow-ups | **GAP** |
| Match today's cash | no payment method / cash drawer | **GAP** |
| Tomorrow · N booked, first at … | `upcomingVisitsProvider` | ✓ |
| Close the day | no end-of-day workflow in any repository | **GAP** (button hidden) |
| Appearance Auto / Day / Evening | *new* `appearanceModeProvider` (shared_preferences), clock | ✓ (evening start = default 17:00; clinic-specific start is a GAP) |

## 4. Phases (each ends with `flutter analyze` introducing no new issues, tests passing, a commit)

Baseline before any change: `flutter analyze` reports 118 pre-existing issues (0 errors, 13 warnings, 105 infos); one existing test (`dental_phase2_catalog_and_procedure_test.dart`) already hangs and fails. "Clean" below means no new issues, and new or changed files have no issues.

1. **Tokens, theme, fonts**: `cru_*` theme files, Geist assets, `main.dart` theme.
2. **Shared widgets**: `lib/shared/widgets/cru/`.
3. **Dashboard, Day appearance**: domain builder + providers, new sidebar and shell layout, dashboard widgets, responsive at 1440 / 1280 / 1024 / 800 (layout tests). Wire into `DesktopShell`; the search opens the assistant; floating button hidden on the dashboard.
4. **Evening**: evening tokens in the shell, Wrap up card, time-aware greeting, Auto/Day/Evening setting and auto switching.
5. **Visual check**: goldens at 1440×1148 (Day) and 1440×988 (Evening), rendered at 1.5× so they line up with `screens/*.png`; compare and iterate.
6. **Cleanup**: delete the old dashboard widgets and dead shell code.

## 5. Known constraint
`ResponsiveShell` shows the **mobile** shell below 900 px. The dashboard layout itself is built and tested down to 800 px (sidebar collapsed to icons), but the app will only show it at 800 px if `kDesktopBreakpoint` is lowered. That would expose the other desktop screens at widths they weren't built for, so this plan leaves it unchanged.
