# Requests for shared files

Builders: add requests for shared files (theme, tokens, `cru/` widgets, router, shell, models, repositories, `pubspec.yaml`) under your own heading. Say what you need and where you worked around it locally.

## Builder 1 (Appointments shell, Day, overlaps)

- **Sizes with no token** (private consts, all in `widgets/day/`): `DayGridMetrics` in `day_grid_metrics.dart` (block radius 8, ring 2, now line 2 / dot 10 / gutter pill 18, marker bar 4, break band 44, top inset 8); mini calendar cell 34 and circle 30 (`mini_month_calendar.dart`); selected-card monogram 44 (`selected_appointment_card.dart`); checkbox 18 with radius 5 (`overlap_card.dart`); "New" tag 20 (`overlap_visit_row.dart`); header summary line 18 (`widgets/shell/appts_header.dart`). Suggest `CruRadius.block = 8` and `CruSize.monogramCard = 44`, shared with Builder 2's `WeekMetrics`.
- **Page title 26/32** has no non-tabular token; the header uses `CruType.amount` (26/32 w600, tabular). A `CruType.pageTitle` would be cleaner.
- **Selected card name 18/24**: no token; used `CruType.headline` (17/22).
- **Side sheet with backdrop**: `widgets/shell/appts_side_sheet.dart` (`ApptsSideSheet`), a third copy of the Patients pattern next to Builder 2's `MonthSheetBackdrop`; worth one shared `cru/` widget.
- **Double-click**: same as Builder 2, blocks detect the second click themselves (`day_block.dart`).
- **Shell (lead)**: tab 4 → `AppointmentsScreen` in the self-padding branch, chatbot hidden (as planned).
- **Repository**: `VisitRepository.createVisit` has its overlap check commented out, so the inline "4 visits already at …" notice in New appointment (`desktop_schedule_visit_dialog.dart`) can't fire until it's re-enabled. Reschedule and Move use `rescheduleVisit`, which enforces it.
- **Model proposals (report, not for this pass)**: `Visit.overlapAcknowledgedAt` (Keep both, the grey kept state and legend item); clinic working hours, sessions, closed days and slot length (session labels, break band, Open slots today, mini calendar closed days); `Visit.bookedVia` ("by phone").

## Builder 2 (Week, Month, Agenda)

- **Sizes with no token** (worked around as private consts): `widgets/week/week_metrics.dart` (`WeekMetrics`: gutter 60, block 22, block inset 3, date circle 34, now dot 10, now pill 18, break band 30) and `widgets/month/month_metrics.dart` (`MonthMetrics`: tile 112, date row/circle 26, panel row 50, time column 76, past tile alpha 0.55). Promote to `CruSize` if wanted.
- **11 px text** (Week now pill "11:48", the small "AM"/"PM" in the Month panel) has no type token; used `CruType.micro` (11.5).
- **12 px regular text** (Week column count line, Month tile "N seen") has no token; used `CruType.caption` (12.5).
- **Backdrop**: copied the Patients `_Backdrop` into `widgets/month/month_sheet.dart` (`MonthSheetBackdrop`, `MonthSheetSlide`); worth merging into `cru/` with the Patients one.
- **Double-click**: `CruPressable` has no `onDoubleTap`; Month tiles detect a second click within `kDoubleTapTimeout` themselves (`month_tile.dart`) so single-click selection isn't delayed.
- `ApptTimeLabel` ("9:30" + small "AM") lives in `widgets/month/appt_time_label.dart` and is shared with Agenda; Builder 1 may want it for Day.

## Builder 3 (Inventory)

- **Icons missing from `CruIcons`**: `cart` (New order), `list` and `grid` (view toggle), `pill` (tablet/capsule/strip items). Local copies in `lib/features/inventory/presentation/widgets/inventory_style.dart` (`InventoryIcons`); cart/list/grid paths from `html/Inventory.dc.html`, the pill is the mock-up's rotated capsule converted to a path. The mock-up's hand/sachet/thermometer tiles need an item type (GAP), so other items use `CruIcons.box`.
- **Chart grey**: the mock-up's `--chart` (#C5CDD8) has no token. Inventory mixes it as `Color.lerp(track, label3, 0.3)` (`inventoryChartGrey`) for stock fills, level bars and usage bars, because `track` is also the vial/bar background and they'd be indistinguishable. Suggest `CruColors.chart` (Day #C5CDD8; Evening to taste), shared with Builder 4.
- **Sizes with no token** (`InventorySize` in `inventory_style.dart`): list columns 124 / 116 / 100 with gap 20; level bar 96 × 4; row ring 1.5, tile ring 2; grid tile 104 tall, radius 20, gap 14, two columns below 600 px; vials 14 × 78 (tile), 20 × 76 (panel), 8 × 18 (legend), notch 2; usage chart 64 tall with 14 px labels, 6 px gaps, 3 px stub; batch code column 76. Grid tile quantity 22/26 has no type token (`inventoryTileQuantity`); the panel's 30 px quantity uses `CruType.largeTitle.tabular`.
- **Dialog**: Archive confirm reuses the Patients `PatientDialog` (`patient_dialogs.dart`); worth a generic `CruConfirmDialog` in `cru/`.
- **Side sheet with backdrop**: a fourth copy of the Patients pattern (`_Backdrop` / `_SlideIn` in `inventory_screen.dart`); same ask as Builders 1 and 2.
- **Shell (lead)**: tab 2 → `InventoryScreen()` in the self-padding branch, chatbot hidden. The old `DesktopInventoryScreen` class can go once the shell switches, but keep `desktop_inventory_list_screen.dart`: it now hosts `InventoryOrdersTab`, `InventoryVendorsTab` and `InventoryUsageTab` (wrappers at the end of the file around the private tab widgets).
- **Model proposals (report, not for this pass)**: `MedicineModel.usualOrderQty` (today derived as the median restock), `form` and `packSize` ("Tablet · strip of 15"), `itemType` (medicine / consumable / instrument: vial, "Not used up"), a batches table (per-batch quantity, "Use first"), supplier records with lead time ("usually arrives in 2 days"), purchase orders ("Order all", "Order 50 strips").

## Builder 4 (Revenue)

- **Icons missing from `CruIcons`**: `receipt` (Record expense, money-out rows, the expense dialog) and `chat` (Send reminders on WhatsApp). Local copies in `lib/features/revenue/presentation/widgets/overview/revenue_icons.dart` (`RevenueIcons`), paths from `html/Revenue.dc.html`. Promote to `CruIcons` and swap the references.
- **Sizes with no token** (private consts): Collections chart geometry in `widgets/overview/collections_by_day_card.dart` (plot 140, top room 10, x label 14, y label column 28, grid left 36, bars left 44, max bar width 48, legend swatch 10); transaction row 56 and day/time column 76 in `widgets/overview/transaction_row.dart` (`kTxnRowHeight`, `kTxnWhenWidth`); Add Transaction dialog frame 860 × 740 (`desktop_add_transaction_dialog.dart`); Transaction details max content width 640 (`transaction_details.dart`). The glance arrow (13 px, stroke 2.4, gap 3) copies the dashboard's Collected today values.
- **11 px text** (chart tick and day labels, the small "AM"/"PM" in transaction rows) has no type token; used `CruType.micro` (11.5), as Builder 2.
- **Chart bar colour**: the mock-up's `--chart` (#C5CDD8) has no token; bars use `track` like the dashboard's Collections card. The flat closed-day stub uses `track` too (mock-up: `--inset-2`).
- **Monogram + name + amber amount rows** and the WhatsApp reminders dialog repeat the Patients `patients_reminders_sheet.dart` pattern (`widgets/overview/pending_actions.dart`); worth one shared reminders dialog in stage C.
- **Shell (lead)**: tab 3 → `RevenueOverviewScreen()` in the self-padding branch, chatbot hidden. The old `desktop_revenue_screen.dart` can go once the shell switches (the new screen doesn't import it).
