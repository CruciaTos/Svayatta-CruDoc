# Clinic redesign: implementation plan

Branch `feat/clinic-redesign`, from `feat/patients-redesign` (`4803d5a`). Spec: `PROMPT.md`, `html/`, `screens/`. Rules: `.claude/rules/crudoc-ui.md` and `design/dashboard-redesign/DESIGN_SPEC.md`.

UI/UX pass only. Screens read existing repositories through providers. No model, schema or sync changes. An element with no data behind it is hidden and recorded as a GAP. Queue is not touched (read-only use of `todaysQueueProvider`).

## Facts from recon that shape the design

- **No code generation** is used (build_runner is a dev dependency, but there are no `*.g.dart`/`*.freezed.dart` files, and models and providers are hand-written). Stage C skips build_runner.
- **Riverpod 3** (`Notifier`, `NotifierProvider`; `StateProvider` only via `flutter_riverpod/legacy.dart`). Test overrides: `import 'package:flutter_riverpod/misc.dart' show Override;`.
- **Clinic working hours, sessions, closed days and slot length are not stored anywhere.**
- `Visit` has no token, "how booked", assigned staff or allergy fields. Token comes from today's queue (`QueueEntry.linkedVisitId`). Allergies come from the homeopathy case sheet, as on Patients.
- `VisitRepository.createVisit` has its overlap check commented out; only `rescheduleVisit` enforces the cap of 4 (`VisitOverlapLimitExceededException`).
- Inventory has no batches table, no suppliers table, no purchase orders, no form, no usual order quantity, no item type, no lead time. Stock movements exist (`StockTransactionModel`), per item via `InventoryRepository.getTransactionsForMedicine`.
- Revenue entries have no payment method and no category/service field. `PendingPayment` rows have a date and a patient.
- The desktop shell shows the floating chatbot on every tab except Dashboard and Patients (`desktop_shell.dart:357`). The lead hides it on Inventory (2), Revenue (3) and Appointments (4).
- Tabs: `DesktopTab` inventory 2, revenue 3, appointments 4. New screens pad themselves with `CruSpace.mainPadding` like `PatientsScreen`; the lead moves them into the shell's self-padding branch.

## Shared pieces every builder imports (do not create a second set)

- `package:doctor_management_app/shared/widgets/cru/cru.dart`: exports the theme and every Cru widget. Colours: `context.cru` (`canvas, surface, inset, track, label, label2, label3, separator, hairline, accent, accentText, accentTint, accentWash, amber, amberText, amberTint, green, greenText, greenTint, redText, redTint, allergyChipFill, allergyChipText, cardShadow, paneShadow, segmentShadow, onAccent`). Tokens: `CruType` (`largeTitle, title, title2, metric, amount, headline, row, callout, text, subhead, caption, micro, groupLabel, chip`; `.tabular`, `.w500`, `.w600`, `.tint(c)`), `CruRadius` (`card 24, control 12, iconTile 10, strip 16, panel 14, bar 6, barStub 2, thinBar 3, full`), `CruSpace` (`s4…s32, cardGap 20, stackGap 22, mainPadding`), `CruSize` (`rightColumn 384, tableRow 64, tableHeader 44, capsule 30, pill 26, chip 30, filterChip 36, searchBar 44, squareButton 36, segmentHeight 36, iconTile 36, progressBar 6`), `CruBreakpoint` (`splitPane 1200`), `CruMotion` (`fast, standard, pane, curve, of(context)`).
- Widgets: `CruButton` (kinds primary/secondary/inset/tinted/outline), `CruCapsuleButton` (kind inset/tinted/surface, icon), `CruSquareButton`, `CruIconButton`, `CruLink`, `CruPressable`, `CruCard`, `cruShape`, `CruSeparator`, `CruSegmentedControl<T>` + `CruSegment<T>`, `CruStatusDot`, `CruMonogram`, `CruChip`, `CruPill`, `CruIconTile` (+`CruTileTone`), `CruProgressBar`, `CruInfoPill` (tone allergy), `CruKeycap`, `CruIcon` + `CruIcons`.
- Dashboard: `GlanceStrip`, `GlanceLabel`, `GlanceMetric`, `GlanceCaption`, `GlanceCellSkeleton` (`features/dashboard/presentation/widgets/glance_card.dart`); `SkeletonBox`, `SkeletonCard` (`.../widgets/skeleton.dart`); `DashFormat` (`features/dashboard/domain/dashboard_format.dart`: `rupees`, `time`, `timeRange`, `dateLine`, `shortDate`, `weekday`, `plural`); `dashboardNowProvider`.
- Patients: `KnownAllergies.parse` and `DetailsCardHeader`/`DetailsSectionLabel` (`features/patients/presentation/widgets/details/details_common.dart`); `PatientDialog` (`features/patients/presentation/widgets/patient_dialogs.dart`); `PatientFormat` (`features/patients/domain/patients_builder.dart`); the split/sheet pattern with backdrop in `patients_screen.dart` (299–426) and `patient_preview_pane.dart`.
- Tests: copy the pattern of `test/patients/patients_harness.dart` and `test/patients/patients_fixtures.dart` (`loadGeist`, sidebar overrides, `setViewSize`). Goldens: `@Tags(['golden'])`, `library;`, `setUpAll(loadGeist)`, 1440 px wide, dpr 1.5, `matchesGoldenFile('goldens/<name>.png')`.

If you need a widget that's missing, build it inside your own feature folder. The lead merges duplicates in stage C.

## File ownership

No file is owned by two builders. Everything not listed is read-only for builders. Shared files (theme, tokens, `cru/` widgets, router, `desktop_shell.dart`, models, repositories, services, `pubspec.yaml`) are lead-only: write requests to `design/clinic-redesign/NEEDS.md` under your name and work around them locally.

### Lead (written before stage B, then stage C)
- `lib/features/appointments/domain/appointments_models.dart` (written): `ApptsView`, `ApptStatus`, `OverlapKind`, `ApptItem`, `OverlapGroup`, `ClinicSession`, `DayRange`, `ApptDayCounts`.
- `lib/features/appointments/domain/appointments_builder.dart` (written): `ApptsBuilder` (items, forDay, inRange, groups, latestBooked, range, snap, nextFreeSlot, counts, defaultSelection, weekStart, weekDays, monthGrid), `kApptSnapMinutes`.
- `lib/features/appointments/data/providers/appointments_providers.dart` (written): `apptsNowProvider`, `apptItemsProvider`, `apptDayItemsProvider(day)`, `apptDayGroupsProvider(day)`, `apptDayCountsProvider(day)`, `ApptsState`, `ApptsController`, `apptsControllerProvider`.
- `lib/features/appointments/presentation/widgets/appt_status_style.dart` (written): `ApptStatusStyle.of(status, colors)`.
- Stage C: `desktop_shell.dart`, `cru/` merges, `NEEDS.md`, deleting replaced screens, goldens, commits, report.

Builder 1 may **add** members to the four lead files above (never rename, remove or change a signature). Builder 2 only reads them.

### Builder 1: Appointments shell, Day, overlaps
- `lib/features/appointments/presentation/appointments_screen.dart` (new): `class AppointmentsScreen extends ConsumerStatefulWidget { const AppointmentsScreen({super.key}); }`. Header, segmented control, keyboard, hosts the four bodies.
- `lib/features/appointments/presentation/appointment_actions.dart` (stub written by lead; Builder 1 fills the bodies, keeping the signatures of `ApptActions.newAppointment`, `openVisit`, `reschedule`).
- `lib/features/appointments/presentation/reschedule_visit_dialog.dart` (new).
- `lib/features/appointments/presentation/desktop_schedule_visit_dialog.dart` (edit): add an optional `DateTime? initialStart` (date and time) to `showDesktopScheduleVisitDialog` and the widget; show the cap exception inline under the time field with a next-free-slot chip.
- `lib/features/appointments/presentation/widgets/shell/**`, `widgets/day/**` (new).
- `test/appointments/appointments_fixtures.dart`, `test/appointments/appointments_harness.dart`, `test/appointments/appointments_day_golden_test.dart` (new).

### Builder 2: Week, Month, Agenda
- `lib/features/appointments/presentation/widgets/week/**` (new): `class AppointmentsWeekView extends ConsumerWidget { const AppointmentsWeekView({super.key}); }`.
- `lib/features/appointments/presentation/widgets/month/**` (new): `class AppointmentsMonthView extends ConsumerWidget { const AppointmentsMonthView({super.key}); }` (grid + its own 384 px day panel).
- `lib/features/appointments/presentation/widgets/agenda/**` (new): `class AppointmentsAgendaView extends ConsumerWidget { const AppointmentsAgendaView({super.key}); }`.
- `test/appointments/appointments_week_fixtures.dart`, `test/appointments/appointments_week_month_golden_test.dart` (new).

### Builder 3: Inventory
- `lib/features/inventory/presentation/inventory_screen.dart` (new): `class InventoryScreen extends ConsumerStatefulWidget { const InventoryScreen({super.key}); }`.
- `lib/features/inventory/presentation/widgets/**` (new).
- `lib/features/inventory/domain/**` (new): models and pure builder (low, daily use, lasts, expiring, sort, filter, run-out strip).
- `lib/features/inventory/data/providers/inventory_view_providers.dart` (new).
- `lib/features/inventory/data/inventory_view_preferences.dart` (new): SharedPreferences wrapper for list/grid (pattern: `features/settings/data/appearance_preferences.dart` + `appearance_provider.dart`).
- `lib/features/inventory/presentation/desktop_inventory_list_screen.dart` (edit): make the Orders, Vendors and Usage tab widgets public so `InventoryScreen` can host them; keep their behaviour.
- `test/inventory/**` (new).

### Builder 4: Revenue
- `lib/features/revenue/presentation/revenue_overview_screen.dart` (new): `class RevenueOverviewScreen extends ConsumerStatefulWidget { const RevenueOverviewScreen({super.key}); }`.
- `lib/features/revenue/presentation/widgets/overview/**` (new).
- `lib/features/revenue/domain/**` (new): period maths, comparison, chart buckets, pending grouping.
- `lib/features/revenue/data/providers/revenue_view_providers.dart` (new): e.g. `pendingPaymentsProvider` (from `RevenueRepository.watchPendingPayments`), period controller, overview view data.
- `lib/features/revenue/presentation/desktop_add_transaction_dialog.dart` (edit): restyle to tokens only, keep "paid to"; may add optional prefill params.
- `lib/features/revenue/presentation/transaction_details.dart` (edit): restyle to tokens only.
- `lib/features/revenue/presentation/desktop_invoices_screen.dart` (edit): token restyle only, behaviour unchanged; lowest priority.
- `test/revenue/**` (new).

## Interfaces between builders

- **Views read the controller, not constructor params.** `ref.watch(apptsControllerProvider)` gives `view`, `anchor`, `selectedVisitId`, `selectedGroupStart`, `monthSelected`. Week and Month use `anchor` (week containing it / its month).
- **Navigation from Week/Month:** `ref.read(apptsControllerProvider.notifier).openDay(date, visitId: id)`; Month tile tap: `.selectMonthDay(date)`.
- **Actions:** `ApptActions.newAppointment(context, ref, day: d)` / `(…, start: t)`, `ApptActions.openVisit(context, item)`, `ApptActions.reschedule(context, ref, item)`.
- **Data:** `apptItemsProvider` (all), `apptDayItemsProvider(date)`, `apptDayGroupsProvider(date)` (columns for overlaps), `apptDayCountsProvider(date)`, `ApptsBuilder.range(items, day)` for the drawn hours (Week passes all 7 days' items so columns share one range), `ApptStatusStyle.of`.
- **Harness (Builder 1 writes, Builder 2 calls):**
  `Future<void> pumpAppointments(WidgetTester tester, {required List<Visit> visits, required List<Patient> patients, List<QueueEntry> queue = const [], required DateTime now, ApptsView view = ApptsView.day, DateTime? anchor, String? selectedVisitId, DateTime? monthSelected, Size size = const Size(1440, 1024)})` in `test/appointments/appointments_harness.dart`. It mounts `AppointmentsScreen` inside the sidebar layout and overrides `apptsControllerProvider` with the given initial state.
- **Shell (lead, stage C):** tab 4 → `AppointmentsScreen`, tab 2 → `InventoryScreen`, tab 3 → `RevenueOverviewScreen`; chatbot hidden on all three.

## Element → data source

### Appointments
| Element | Source |
|---|---|
| Visits, status | `apptItemsProvider` ← `allVisitsProvider`, `patientsStreamProvider`, `todaysQueueProvider`; status via `ApptsBuilder.items` (visit status + queue) |
| Waiting "· 8 min" | queue `checkedInAt` → `ApptItem.waitMinutes` |
| Token n | today's `QueueEntry.tokenNumber` via `linkedVisitId` (shown only when present) |
| Age · sex | `Patient.age`, `Patient.gender` |
| New / Returning | `ApptItem.isNewPatient` (first non-cancelled visit) |
| Reason | `Visit.treatmentType` (or queue reason) |
| Allergy chip | `homeopathyCaseSheetProvider(patientId)` → `KnownAllergies.parse(...medicalHistory.allergies)`; hidden when none |
| Sessions, session labels, break band | **GAP** (no working hours) → one continuous range, first→last appointment rounded to hours (`ApptsBuilder.range`) |
| Closed days (mini calendar grey, Week "Closed" column, Month "Closed" tile) | **GAP** → not drawn |
| Open slots today | **GAP** (slot length + hours) → card hidden |
| Empty-time click snapping | slot length **GAP** → snaps to `kApptSnapMinutes` (15, the dialog's smallest duration) |
| Month capacity bar, "N open", "Almost full", legend | **GAP** (hours ÷ slot length) → hidden, "N booked" only |
| Month day panel summary | "9 booked · first at 9:30 AM" (open count GAP) |
| Overlap groups and columns | `apptDayGroupsProvider` (`ApptsBuilder.groups`) |
| "Booked <date>" | `Visit.createdAt` |
| "how booked" (by phone) | **GAP** → omitted |
| Suggested move | `ApptsBuilder.latestBooked` + `ApptsBuilder.nextFreeSlot` (within the drawn range, since hours are a GAP) |
| Move | `VisitRepository.rescheduleVisit` (via `visitRepositoryProvider`); Undo = reschedule back with `acknowledgeOverlap: true` |
| WhatsApp checkbox | `whatsappRepositoryProvider.sendAppointmentConfirmation(visit: moved)` |
| Keep both, kept (grey) state, grey legend item | **GAP** (nothing stores the decision; no assigned-staff field) → hidden |
| Cap message | `VisitOverlapLimitExceededException` from `rescheduleVisit` (and `createVisit` if its check is re-enabled) |
| Agenda | exists in the old screen → rebuilt as `AppointmentsAgendaView` |
| Visit details | `showSessionDetailsSheet(context, VisitWithPatient(visit:, patient:))` |

### Inventory
| Element | Source |
|---|---|
| Items | `medicinesStreamProvider` (active only) |
| "₹ in stock" | Σ `currentStock × unitPrice` (items with a price) |
| Low | `currentStock <= reorderThreshold` |
| Daily use, 14 bars, Lasts | `dispense` movements over the last 14 days from `InventoryRepository.getTransactionsForMedicine` per item, in a provider (closed days are a **GAP**, so 14 calendar days). No usage for an item → "—"; no usage for any item → Lasts column and "days left" hidden, default sort Stock level |
| Usual order qty (vial fill, level bar, "usual order Y", suggestion qty) | derived: median `restock` quantity for the item; none → hidden for that item |
| Reorder notch, "Reorder at X" | `reorderThreshold` |
| Form | **GAP** → `unit` shown in its place |
| Instrument (no vial, "Not used up") | **GAP** (no item type) → every item treated alike |
| Expiring soon (60 days) | `expiryDate` |
| Batches | one row from `batchNumber` + `expiryDate`; multiple batches and per-batch quantity are a **GAP** ("Use first" hidden) |
| Supplier | `supplierName` (free text); lead time **GAP** → arrival clause dropped |
| Categories chips | distinct `category` values with counts |
| New order / Order all / "Order <qty>" | **GAP** (no purchase-order flow): Order all and Order <qty> hidden; New order opens the existing Orders (reorder queue) tab |
| Orders / Vendors / Usage tabs | existing widgets from `desktop_inventory_list_screen.dart` |
| Add item, Edit item | `showDesktopAddEditMedicineDialog` |
| Archive | confirm, then `InventoryRepository.deleteMedicine` (soft delete) |
| Adjust stock | `showStockAdjustmentDialog` |
| Enter | `MedicineDetailScreen(medicine:)` via `Navigator.push` |
| List/grid memory | new `InventoryViewPreferences` (SharedPreferences) |

### Revenue
| Element | Source |
|---|---|
| Entries | `recentRevenueEntriesProvider` (all, newest first), filtered by period in providers |
| Collected / Expenses / Net | income / expense sums in the period; comparison vs the same day range of the previous period |
| Expenses caption | the top expense descriptions (the Add Transaction form saves the chosen category as the description) |
| Pending | `RevenueRepository.watchPendingPayments()` (new provider), grouped per patient, `date` for age |
| Collections by day | daily income; today in accent; a past day with no collections is a flat stub (same rule as the dashboard); future = outline stub |
| UPI · Cash split, method in rows | **GAP** → hidden |
| By service card | **GAP** (no category/service field) → hidden |
| "Closed on Sundays" legend | **GAP** → hidden |
| Transactions | entries in period, All / Money in / Money out |
| Row tap | `TransactionDetailsPage(entry:)` (restyled) |
| Record payment / Record expense | `showDesktopAddTransactionDialog(context, initialKind: …)` (restyled, keeps "paid to") |
| Mark paid | prefilled confirm → the repository call the old screen uses (`VisitRepository.markVisitationPaymentPaid` / `RevenueRepository.markPendingPaymentAsPaid`) |
| Send reminders on WhatsApp | `WhatsAppTemplateService.buildDirectWhatsAppUrl` + `launchUrl`, one capsule per patient (pattern: `patients_reminders_sheet.dart`) |
| Invoices tab | existing `DesktopInvoicesScreen(isSubScreen: true)` |
| Expenses tab | no separate screen → hidden |
