# Clinic redesign: implementation report

Branch `feat/clinic-redesign`, from `feat/patients-redesign` (`4803d5a`). Plan: `IMPLEMENTATION_PLAN.md`. Builder requests for shared files: `NEEDS.md`.

This was a UI/UX pass only. Every screen reads existing repositories through Riverpod providers. No model, schema or sync code changed, and Queue was not touched; Appointments only reads `todaysQueueProvider` from it.

## What was built

### Appointments (`lib/features/appointments/`)
- **Shell**, in `presentation/appointments_screen.dart` and `widgets/shell/`:
  - header with Today, ‹ › and the title;
  - a summary line per view, with an amber "· n overlap(s) to sort out" on the Day view;
  - a Day / Week / Month / Agenda segmented control, a search dialog and "New appointment" as the only filled button;
  - keyboard: ← → steps and T jumps to today.
- **Shared logic**, in `domain/appointments_models.dart` and `domain/appointments_builder.dart`. Everything is pure code, and a single status mapping covers every view.
  - The status mapping combines the visit's status with today's queue: done, missed, in consultation, waiting and booked.
  - Overlapping visits are grouped transitively and laid out in columns, assigned greedily by start time.
  - The next free slot is calculated here, as are day counts, the default selection and the drawn time range.
- **State**, in `data/providers/appointments_providers.dart`. The controller holds the current view, the date being shown and the selection.
- **Day view**, in `widgets/day/`:
  - Grid at 1.6 px per minute. Blocks are one line or two depending on length and use the status colours.
  - A live "now" line with a time pill in the gutter.
  - Overlap columns, the amber gutter bar and "n at once" pill, and a legend.
  - Right column: mini month calendar, the selected-appointment card (waiting pill, token, New/Returning, allergy chip, Reschedule / Cancel / Open patient) and the overlap card.
  - The overlap card shows each visit's booking date and a suggestion: "Move <name> to <slot>", a WhatsApp checkbox, a Move button, and an "Other time" link. Moving shows a snackbar with Undo for 5 seconds.
  - Clicking empty time opens New appointment prefilled at that time. Double-clicking a block opens the visit details.
  - Below 1200 px the right column becomes a sheet.
- **Week view**, in `widgets/week/`: 1.2 px per minute, column headers with counts and an amber overlap dot, today's column tinted with the now line, 22 px "First L." blocks, and overlap columns.
- **Month view**, in `widgets/month/`: rounded date tiles showing "N seen", "N missed" and "N booked", with today's accent "N seen so far". A 384 px day panel lists the day's appointments with "Book on this day" and "Open day". Below 1200 px the panel becomes a sheet.
- **Agenda**, in `widgets/agenda/`: the next 30 days, grouped under date headers.
- **Reschedule** (`reschedule_visit_dialog.dart`, new) and **New appointment** (`desktop_schedule_visit_dialog.dart`, which gained `initialStart`):
  - When the repository refuses a fifth overlapping visit, both show "4 visits already at 12:30 PM. That's the most CruDoc allows at one time." under the time field, with a chip for the next free slot.
  - Reschedule also asks for confirmation on an overlap warning, and shows a message inline when the same patient is already booked at that time.

### Inventory (`lib/features/inventory/`)
- **Screen**, in `presentation/inventory_screen.dart` and `widgets/`:
  - header with the stock value;
  - Items / Orders / Vendors / Usage segmented control, search (Ctrl F), a list/grid toggle remembered in `InventoryViewPreferences`, and sort;
  - filter chips with counts, the amber run-out strip, the list view (64 px rows, level bar, "Lasts", next expiry) and the grid view (104 px tiles with a vial and reorder notch);
  - a 384 px item panel with eyebrow, stock block, 14-day usage bars, batch, reorder suggestion and "Adjust stock";
  - keyboard: ↑ ↓ in the list, arrow keys in the grid, Enter opens the item. Below 1200 px the panel becomes a sheet.
- **Calculations**, in `domain/` and `data/providers/inventory_view_providers.dart`:
  - daily use is `dispense` stock movements over the last 14 days;
  - the usual order is the median of the item's `restock` quantities;
  - "Lasts" is stock ÷ daily use;
  - "Expiring soon" means within 60 days.
- **Orders / Vendors / Usage tabs**: the existing tabs, hosted through public wrappers added to `desktop_inventory_list_screen.dart`.

### Revenue (`lib/features/revenue/`)
- **Screen**, in `presentation/revenue_overview_screen.dart` and `widgets/overview/`:
  - header with the period subtitle, "Record expense" and "Record payment";
  - Overview / Invoices control, and a Today / Week / Month / Year control that drives every figure;
  - glance strip: Collected compared with the same days of the previous period, Expenses with its top descriptions, Net as a share of collections, and Pending with patient count and oldest age;
  - Collections by day chart: today in accent; closed and future days as stubs;
  - Transactions with All / Money in / Money out; each row opens Transaction Details;
  - Pending payments with "Mark paid" and "Send reminders on WhatsApp".
- **Calculations**, in `domain/` and `data/providers/revenue_view_providers.dart`.
- **Restyled to tokens only**: `desktop_add_transaction_dialog.dart` keeps "Paid to" / "Received from" and gained optional prefill parameters; `transaction_details.dart` too.

### Shared wiring
- `desktop_shell.dart`: tab 2 → `InventoryScreen`, tab 3 → `RevenueOverviewScreen`, tab 4 → `AppointmentsScreen`. They pad their own page, and the floating chatbot is hidden on all three.
- Removed the replaced `desktop_events_screen.dart` and `desktop_revenue_screen.dart`. Nothing else referenced them.

### Tests
- **Goldens** at 1440 px wide with bundled Geist and fake providers, in `test/appointments/goldens/`, `test/inventory/goldens/` and `test/revenue/goldens/`: `appointments_1_day`, `appointments_2_day_overlap`, `appointments_3_week`, `appointments_4_month`, `inventory_1_list`, `inventory_2_grid` and `revenue`.
- **Unit tests** for the revenue calculations and the inventory builder.

## GAPs: what is hidden, and the model change I'd propose

| GAP | Hidden or changed | Proposed change (additive) |
|---|---|---|
| Clinic working hours and sessions | Session labels ("Morning session · … · 10 booked") and the break band. Day and Week draw one continuous range from the first to the last appointment, rounded to whole hours. The next-free-slot search is limited to that range. | `clinicHours` on the doctor profile (`users/{uid}`): a list of sessions `{label, start, end}` per weekday, edited in Settings → Practice |
| Closed days | Grey closed days in the mini calendar, the grey Week column and "Closed" Month tiles; Revenue's "Closed on Sundays" legend | `closedWeekdays` plus a holidays list, in the same settings |
| Slot length | The "Open slots today" card; Month capacity bar, "N open", "Almost full" and legend; "N open" in the day panel. Clicks on empty time snap to 15 minutes. | `slotMinutes` in the same settings |
| Keep both, a decision to keep an overlap | The "Keep both" button and caption, the grey "kept" gutter bar and its legend item. Every future overlap counts as unsorted. | `Visit.overlapAcknowledgedAt` (DateTime?) |
| Assigned staff on visits | Nothing can treat an overlap as automatically kept | `Visit.assignedTo` (staff id) |
| How a visit was booked | "· by phone" in overlap rows | `Visit.bookedVia` (enum: phone, walk-in, WhatsApp, online) |
| Item form and pack size | The unit (e.g. "Strips") shows where "Tablet · strip of 15" would go | `MedicineModel.form` and `packSize` |
| Item type (medicine or instrument) | Instruments' "no vial" and "Not used up"; every item is treated alike | `MedicineModel.itemType` |
| Usual order quantity | Worked out as the median restock quantity. An item never restocked has no vial fill, level bar, "usual order Y" or suggestion quantity. | `MedicineModel.usualOrderQty` |
| Batches | One batch row per item, from `batchNumber` and `expiryDate`, with no quantity and no "Use first" tag | A `medicine_batches` table: code, expiry, quantity |
| Suppliers and lead time | "usually arrives in N days, before you run out" | A `suppliers` table with `leadTimeDays`, linked from items by `supplierId` |
| Purchase orders | "Order all N" in the strip and "Order <qty>" in the panel. "New order" opens the existing Orders (reorder queue) tab. | `purchase_orders` and `purchase_order_lines` tables with a draft status |
| Usage history is thin | Most usage is never logged: prescriptions don't deduct stock, and the edit dialog writes stock directly without a stock movement. Items without dispense records show "—" for Lasts. If no item has usage, the Lasts column, "days left", the usage chart and the "Runs out soonest" sort are hidden. | Record `dispense` movements from prescriptions, and log a stock movement for every stock change the edit dialog makes |
| Payment method | "UPI ₹x · Cash ₹y" and the method in transaction rows | `RevenueEntry.method` (upi, cash, card, bank) |
| Service or category on transactions | The By service card | `RevenueEntry.category` (consultation, procedure, lab, medicine, …) |
| Expenses screen | The Expenses tab; Money out in Transactions covers it | none |

## Where the build differs from the design, and why

- **Appointments**
  - **Day and Week grids** are taller than the mock-ups, because there are no working hours to collapse into a break band. The Day goldens are 1180 px tall and the Week card scrolls.
  - **Day header** drops "in consultation" and "waiting" when an overlap needs sorting out, as the overlap mock-up does. The grid still shows both states.
  - **The 4-at-once notice in New appointment can't fire yet.** `VisitRepository.createVisit` has its overlap check commented out, so the cap is only enforced by Reschedule and Move. Re-enabling it is a repository change and was out of scope for this pass.
  - **Mark paid (Revenue)** opens a prefilled confirmation and settles that patient's pending rows with the call the old screen used, `markVisitationPaymentPaid`. It doesn't open Record payment, because recording income separately would count the money twice.
- **Revenue**
  - **Chart bars** use the `track` grey like the dashboard, a little lighter than the mock-up's `#C5CDD8`. No chart colour token exists yet (requested in NEEDS.md).
  - **Today period**: the chart shows the current week with today highlighted, since a single bar tells you nothing. **Year** shows one bar per month.
- **Inventory**
  - **Reorder suggestion** appears only when an item is low or will run out within 7 days.
  - **Invoices tab** hosts the existing `DesktopInvoicesScreen` unchanged. Its token restyle, the lowest priority item, wasn't done.
- **Fixture data**: the goldens use smaller fixtures than the mock-ups (17 inventory items instead of 49; the clinic specialty is Dentist).

## Integration notes
- **Code generation**: none; no build_runner step was needed.
- **Analyzer**: `flutter analyze` reports no errors. Warnings and infos remain only in files this pass didn't change: auth, campaigns, `web_dashboard_view`, `desktop_invoices_screen`, `invoices_screen`, `bill_generation_sheet` and the dental tests. The new and edited code is clean.
- **Not yet merged**: the shared-widget requests in `NEEDS.md`. These are new icons (cart, list, grid, pill, receipt, chat), size tokens, a chart colour, and one shared side sheet with backdrop in place of four copies. They're left for a follow-up because each builder's local version works and matches the design.

## Commits
See the summary in the chat; one commit per feature on `feat/clinic-redesign`.
