Redesign three features to match the designs in design/clinic-redesign/:
- Appointments: Day, Week and Month views, plus how overlapping visits look and get sorted out.
- Inventory: a list view and a compact grid view, both with an item side panel.
- Revenue.

Queue is out of scope. Don't touch it.

The dashboard and Patients redesigns are already done. Reuse their design tokens, theme, Geist font and shared widgets exactly as they are, and don't create a second set. Follow .claude/rules/crudoc-ui.md and design/dashboard-redesign/DESIGN_SPEC.md for every colour, type, radius and spacing rule.

======================================================================
HOW TO RUN THIS — READ FIRST
======================================================================
You are the lead agent. The work runs in three stages:
- A: parallel recon and a plan
- B: parallel build
- C: integration, analysis and fixing. This happens at the very end, and only then.

During stages A and B:
- Nobody runs `flutter analyze`, `flutter test`, `build_runner`, `flutter pub get`, a build, the app, or git. That includes you and every subagent.
- Nobody stops to chase analyzer errors. Write careful code and keep going. All checking and fixing happens in stage C.

STAGE A — recon (parallel, read-only)
0. If git has uncommitted changes, stop and tell me. Otherwise create and switch to branch `feat/clinic-redesign`.
1. In ONE message, launch three Explore subagents so they run at the same time:
   1. Appointments and visits:
      - Visit model and VisitStatus
      - VisitRepository, including the overlap check (hard cap of 4 at once) and the exception it throws
      - create and reschedule flows, and the visit details screen
      - clinic working hours, session times and slot length settings
      - any WhatsApp sending path
      - createdAt, and any assigned-staff field on visits
   2. Inventory:
      - item model and repository
      - stock movements and dispensing history
      - batches and expiry dates
      - suppliers and orders
      - reorder level and usual order quantity
      - categories
   3. Revenue and shared UI:
      - revenue repository and transaction model
      - the existing Transaction Details screen, and the Add Transaction form with "paid to"
      - the dashboard's theme, tokens and shared widgets (glance card, segmented control, chips, capsule buttons, monogram, card, side-panel sheet)
      - routes and the app shell
      - test setup (golden tests, bundled fonts, fake providers)
      - whether the project uses code generation
2. From their reports, write design/clinic-redesign/IMPLEMENTATION_PLAN.md with:
   - for each builder in stage B, the exact files and folders it OWNS (creates or edits); no file may be owned by two builders
   - the existing shared widgets each builder should import
   - a data map: every element described below → the provider or repository method it reads, or "GAP"
   - the interfaces between builders, e.g. the WeekView and MonthView widget signatures the Appointments shell will host

STAGE B — build (parallel)
3. In ONE message, launch four general-purpose subagents so they run at the same time:
   - Builder 1: the Appointments shell, the Day view and overlaps
   - Builder 2: the Appointments Week and Month views, as body widgets with the signatures from the plan
   - Builder 3: Inventory
   - Builder 4: Revenue
   Give each builder four things: its section of this prompt, the GLOBAL RULES, its file-ownership list, and the html/ files and screens/ PNGs for its screens.
4. Rules for every builder:
   - Edit only the files you own. Never edit shared files: theme, tokens, router or shell, models, repositories, pubspec.yaml.
   - If you need a change in a shared file, add it to design/clinic-redesign/NEEDS.md under your name, work around it locally, and carry on.
   - If you need a new widget another builder might also need, build it in your own feature folder. The lead merges duplicates in stage C.
   - Write golden tests for each of your screens in screens/:
     - 1440 px wide
     - fake providers in test code only
     - the bundled Geist font
     Don't run them.
   - Don't run analyze, tests, build_runner, pub get, the app or git. Don't wait for the other builders.
   - Finish by returning three lists: the files you changed, every GAP, and anything unfinished.
5. While the builders run, don't edit their files.

STAGE C — integrate, analyse, fix (sequential, only now)
6. Integrate:
   - Apply NEEDS.md: routes, shell, pubspec and shared widgets.
   - Wire WeekView and MonthView into the Appointments shell.
   - Merge duplicate widgets into the shared set.
7. If the project uses code generation, run build_runner once. Then run `flutter analyze` and fix everything until it's clean. Then run all existing tests and fix every failure.
8. Generate the goldens. Compare each with its PNG in screens/ and fix the differences until they match.
9. Commit once per feature (appointments, inventory, revenue) with clear messages.
10. Write design/clinic-redesign/IMPLEMENTATION_REPORT.md and summarise it to me:
    - what was built
    - every GAP, which element is hidden because of it, and the model change you'd propose
    - anything that doesn't match the design, and why
    - the list of commits

======================================================================
WHAT'S IN design/clinic-redesign/
======================================================================
- screens/ is the target look. Open every PNG:
  - appointments-1-day
  - appointments-2-day-overlap
  - appointments-3-week
  - appointments-4-month
  - inventory-1-list
  - inventory-2-grid
  - revenue
- html/ holds the design source for exact sizes, colours and copy:
  - ApptsDay, ApptsOverlap, ApptsWeek and ApptsMonth for Appointments
  - Inventory (list) and InventoryGrid for Inventory
  - Revenue
  These files use a design-tool template syntax: {{...}} holes, <sc-for> and <sc-if>. Read them as a description, not as code to port.
  Every name and number in them is demo data. The shared demo day is Wednesday 23 September, 11:48 AM.

======================================================================
GLOBAL RULES (every builder)
======================================================================
Architecture and data
- Keep the architecture: feature-first folders, Riverpod, and repositories as the only data source (local-first SQLite with Firestore sync). Widgets never touch SQLite or Firestore.
- Don't change models, schemas or sync code.
- You may derive values inside providers from existing data, such as average daily use from stock movements.
- Anything with no data is a GAP: hide that element and record it. Never show sample or placeholder data.

Colour and buttons
- One filled Ink Blue button per region.
- Amber means needs attention. Red is for allergies only. Violet is for AI (Scribe) only. Green means done or paid.

Text and numbers
- All numbers use tabular figures.
- Money uses Indian grouping with no paise, e.g. ₹1,50,000: NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).
- Dates look like "Wednesday, 23 September". Times look like "9:30 AM".
- Headings are in sentence case. No ALL CAPS.

Motion and layout
- Motion is 200–250 ms with no bounce, and respects reduced-motion settings.
- Fixed row and tile heights, so nothing jumps.
- Show skeletons while loading.
- Below 1200 px wide, every right-hand panel becomes a sheet. It slides in over the content with a dim backdrop and opens when something is selected.

Screens
- Remove the floating chatbot button from these screens.

======================================================================
APPOINTMENTS — SHELL (Builder 1)
======================================================================
The shell is shared by Day, Week and Month.

Header
- Left: "Today" (secondary), then ‹ › icon buttons that step one day, week or month, then the title and one summary line:
  - Day title "Wednesday, 23 September"; summary "<n> appointments · <n> seen · <n> in consultation · <n> waiting". If any unsorted overlap exists, append "· <n> overlap(s) to sort out" in amber.
  - Week title "21 to 27 September"; summary "<n> appointments · <n> seen · <n> missed".
  - Month title "September 2026"; summary "<n> appointments · <n> seen so far".
- Right:
  - a Day / Week / Month / Agenda segmented control (hide Agenda if the app has no agenda list)
  - a search icon button
  - "New appointment", the only filled button

Status styles
- There is one mapping from VisitStatus, used by Day, Week and overlaps:
  - done: inset fill, green check, secondary text
  - missed: inset fill, strikethrough, tertiary text
  - in consultation: accent-tint fill, accent text
  - waiting (arrived): amber-tint fill, amber text
  - booked: white fill with a hairline

Keyboard
- ← and → step back and forward. T jumps to today.

======================================================================
APPOINTMENTS — DAY (Builder 1)
======================================================================
Grid card
- The day shows sessions from the clinic's working hours.
- Each session has a label, e.g. "Morning session · 9:30 AM to 1:30 PM · 11 booked".
- Scale: 1.6 px per minute, with an hour line and label every hour.
- The gap between sessions collapses into one band, "Break · 1:30 to 5:00 PM", which is not drawn to scale.
- If working hours aren't stored, that's a GAP. Draw one continuous range from the first to the last appointment, rounded out to whole hours, with no break band.

Blocks
- Height is the visit's duration × 1.6 px, minus 2.
- A visit of 20 minutes or less is one line: name, " · reason" (ellipsis), and the start time on the right.
- A longer visit shows two lines: name with "start to end" on the right, then the reason.

Now line
- Today only: a 2 px Ink Blue line, a dot, and a time pill in the gutter. It updates every minute.

Right column (384 px)
- Mini month calendar: today is a filled blue circle, the selected date is a tint circle, closed days are grey.
- Selected appointment card:
  - status pill (e.g. "Waiting · 8 min") and the time range
  - 44 px monogram, name, "age · sex · New/Returning · Token n" (show the token only if one exists)
  - the reason
  - a red allergy chip, if the patient has an allergy
  - Reschedule, Cancel, and "Open patient ›"
- "Open slots today": chips, one per free slot. The slot length comes from settings. Tapping a chip opens New appointment prefilled with that time.

Behaviour
- The default selection is the first patient waiting; otherwise the next upcoming visit.
- Click a block to select it. Double-click it to open the existing visit details screen.
- Click empty time to open New appointment prefilled at that time, snapped to the slot grid.

======================================================================
APPOINTMENTS — OVERLAPPING VISITS (Builder 1)
See screens/appointments-2-day-overlap.png and html/ApptsOverlap.dc.html.
======================================================================
Layout
- Two visits overlap when start < other.end and other.start < end. Group overlaps transitively.
- Assign columns greedily by start time, the way Apple Calendar does. Each block in a group is 1/columns wide with a 4 px gap. Heights stay true to duration.

The cap of 4
- At most 4 visits can share a moment. VisitRepository already enforces this, so don't duplicate the rule in the UI.
- When the repository rejects a fifth visit in New appointment or Reschedule, show its exception inline under the time field: "4 visits already at 12:30 PM. That's the most CruDoc allows at one time." Offer the next free slot as a chip.

Three kinds of overlap
1. Unsorted and in the future:
   - a 4 px amber bar in the gutter spanning the overlap
   - an amber pill "<n> at once"
   - it counts in the header summary
2. Kept:
   - a grey bar in the gutter (the chart grey), with no pill and no count
3. In the past (the overlap ended before now):
   - blocks side by side, with no marker

Selecting an unsorted overlap
- Clicking a block in an unsorted group selects the whole group. Every block in it gets a 2 px Ink Blue ring.
- The right column's appointment card is replaced by the overlap card:
  - an amber pill "<n> visits at 12:30 PM" and the time range
  - one row per visit: monogram, name, a "New" tag, "reason · how booked", and on the right "Booked <date>" or "Booked today <time>"
  - a suggestion box on accent-wash:
    - "Move <first name> to <slot>"
    - "<She/He> booked later, and <slot> is the next free slot."
    - Always suggest moving the most recently booked visit (by createdAt) to the next free slot of the same length, in the same session or a later session today.
  - a checkbox, "Send <first name> the new time on WhatsApp", ticked by default. Show it only if a WhatsApp send path exists; otherwise it's a GAP.
  - buttons: "Move to <slot>" (filled, the only filled button in that column), "Keep both" (inset), and an "Other time" link that opens Reschedule
  - a caption: "Keep both when a nurse or a second doctor will see one of them. Up to 4 visits can share a time."

Actions
- Move uses the repository's reschedule. Show a snackbar, "Moved <name> to <slot> · Undo", for 5 seconds.
- Keep both needs somewhere to remember the decision:
  - If visits have an assigned-staff field and the overlapping visits are assigned to different people, treat the overlap as kept automatically.
  - If nothing can store the decision, it's a GAP: hide "Keep both" and the grey kept state, and propose an additive field (e.g. overlapAcknowledgedAt) in the report.

Legend
- Show it under the grid only on days that have an overlap. Amber: "Overlap to sort out". Grey: "Overlap you kept, such as a nurse seeing someone in parallel".

In Week and Month (Builder 2 applies the same rule; this isn't drawn, so keep it this small)
- Week: blocks in an overlap group split the day column the same way. A day with an unsorted overlap gets a small amber dot after the count in its column header.
- Month: a small amber dot next to the date number on those days.

======================================================================
APPOINTMENTS — WEEK (Builder 2)
======================================================================
- Columns run Monday to Sunday. Scale: 1.2 px per minute. Every column shares the same sessions and break band.
- Column header:
  - weekday, then the date; today's date sits in a filled blue circle
  - a count line: past days "11 seen · 1 missed"; today and future days "13 booked"; closed days "Closed", with the whole column in inset grey
- Today's column is filled with accent-wash, and the now line runs across it with a time pill in the gutter.
- Blocks are 22 px tall and show "First L." in the status colours.
- Click a block to open the Day view on that date with that visit selected. Click a column header to open that Day.

======================================================================
APPOINTMENTS — MONTH (Builder 2)
======================================================================
Each date is its own rounded tile. This is intentional.
- Tiles: radius 16, 8 px gaps, 112 px tall, and no container card.
- Past days: tile at 55% white with a hairline. Shows "N seen", plus "1 missed" on its own line when there's one.
- Today:
  - a white tile, with the date in a filled blue circle
  - "N booked", the capacity bar and "N open"
  - an Ink Blue line, "5 seen so far"
- Future days:
  - a solid white tile with a soft shadow
  - "N booked", a 4 px capacity bar and "N open"
  - The bar is booked ÷ the day's slots, and turns amber at 85% full or more; "N open" then turns amber and bold.
- Closed days: a transparent tile with a hairline outline and "Closed".
- Days from other months: a bare number in tertiary grey.
- Selected day: accent-wash fill with a 2 px Ink Blue ring.
- Legend: "Booked of <slots> slots" and "Almost full".
- Capacity is the day's working hours ÷ slot length. If that's unknown, it's a GAP: hide the bar and the "open" counts, and show "N booked" only.

Right day panel (384 px)
- an eyebrow: "Today", "Tomorrow" or the weekday
- the title, e.g. "Thursday, 24 September"
- a summary: "9 booked · 12 open · first at 9:30 AM"
- one row per appointment: time, name, reason
- buttons: "Book on this day" (tint) and "Open day" (inset)
- The default selection is tomorrow. Click a tile to select it. Double-click it to open that Day.

======================================================================
INVENTORY (Builder 3) — screens/inventory-1-list.png and inventory-2-grid.png
======================================================================
Header
- "Inventory", with the subtitle "<n> items · ₹<value> in stock".
- Right: "New order" (secondary, cart icon) and "Add item" (filled).

Toolbar
- an Items / Orders / Vendors / Usage segmented control (show only the sections that exist in the app)
- search, "Search items, batches or suppliers"
- a list/grid view toggle (two icon buttons with aria-pressed), remembered with the app's existing preferences
- sort, default "Runs out soonest"; also Name, Stock level and Expiry

Chips
- All, Low stock (amber dot) and Expiring soon (amber dot), then one chip per category, each with its count.
- Hide chips whose count is 0, except All.

Below the chips: two columns
- a flexible left column
- a 384 px item panel on the right, always present:
  - It starts on the first item in the current sort and follows the selection.
  - The selected row or tile gets an accent-wash fill and an Ink Blue ring.

Definitions (computed in providers)
- Low: stock ≤ reorder level.
- Daily use: the average use over the last 14 open days, from stock movements or dispensing records.
- Lasts: stock ÷ daily use. If there's no usage history, it's a GAP: hide Lasts and "days left", and default the sort to stock level.
- Expiring soon: the next batch expires within 60 days.

Left column, top: the run-out strip
- an amber strip, "<n> items will run out this week", with their names and "<k> orders, one per supplier"
- an "Order all <n>" capsule, which creates one draft order per supplier through the existing order flow (a GAP if there is none)
- Show the strip only when n > 0. It's the same in both views.

List view
- Columns:
  - Item: a 36 px icon tile (amber tint when low), the name, and the form
  - In stock: quantity and unit (amber when low), with a 96 px level bar under it
  - Lasts: "about 4 days", in bold amber when 7 days or less
  - Next expiry: amber, with "in 5 weeks" under it, when within 60 days
  - a chevron
- Rows are 64 px. The footer shows "Showing N of M". Load more on scroll.

Grid view
- Compact tiles in 3 columns, 104 px tall. Each tile has:
  - a vial on the left, 14 × 78 px:
    - It fills to stock ÷ usual order quantity: chart grey normally, amber when low.
    - A 2 px white notch marks the reorder level.
    - Instruments have no vial.
  - the name and the form
  - a big quantity with its unit
  - a right-hand slot:
    - "<n> days left" (bold amber when low)
    - or "Expires in <month>" in amber, when the item expires before it runs out
    - or "Not used up" for instruments
- There is no per-tile Restock button. Ordering lives in the strip and the panel.
- Footer legend: "Vial shows stock against your usual order · the notch is your reorder level", and "Showing N of M".

Item panel, top to bottom
1. The eyebrow:
   - amber "Runs out in about N days" when low
   - amber "Expires in <month>" when expiring
   - otherwise "Lasts about N weeks" in secondary grey
2. The name (20 px), "form · category", and a "…" menu (Edit item, Archive).
3. The stock block on inset grey, radius 16:
   - a 20 × 76 vial
   - the big quantity (amber when low)
   - "Reorder at X · usual order Y"
   - "₹price a <unit> · supplier"
4. "Used in the last 2 weeks": 14 bars, with closed days as a flat stub and today in Ink Blue. On the right: "<total> · about <n> a day".
5. "Batches": one row per batch with its code, "Expires <Mon yyyy>" and quantity. The earliest expiry gets a "Use first" tag; batches are used first-expiry-first-out.
6. The reorder suggestion on accent-wash:
   - "Order <usual qty> <unit> from <supplier>"
   - "₹<cost> · usually arrives in <n> days, before you run out" (drop the arrival clause if lead time is unknown)
7. Buttons: "Order <qty> <unit>" (tint) and "Adjust stock" (inset).

Keyboard
- List: ↑ and ↓ move the selection.
- Grid: the arrow keys move the selection.
- Both: Enter opens the existing item details or edit screen.

If usual order quantity or reorder level isn't stored, that's a GAP. Hide the vial fill or the notch accordingly, and propose the fields in the report.

======================================================================
REVENUE (Builder 4) — screens/revenue.png
======================================================================
Header
- "Revenue", with a subtitle for the period, e.g. "September 2026 · 1 to 23 September".
- Right: "Record expense" (secondary) and "Record payment" (filled).
- Both open the EXISTING Add Transaction form, which keeps "paid to". Restyle it to the tokens only.

Controls
- An Overview / Invoices / Expenses segmented control on the left. Keep any existing Invoices or Expenses screens, restyled to the tokens; hide a tab that doesn't exist.
- A Today / Week / Month / Year segmented control on the right. It drives every figure on the screen.

Glance card (reuse the dashboard's)
- Collected: "↑ 6% vs August, same days" in green or amber, comparing the same day range of the previous period.
- Expenses: its top categories.
- Net: "42% of collections".
- Pending: amber dot, "3 patients · oldest 17 days".

Collections by day
- One bar per day of the period.
- Today's bar is Ink Blue. Closed days are a flat grey stub; future days are an empty outline stub.
- Y labels: ₹0, ₹2k, ₹4k. Top right: "UPI ₹x · Cash ₹y".
- Legend: Collected, "Today · ₹x", and "Closed on Sundays" (use whichever days are closed).

By service (384 px)
- Rows for Consultations, Procedures, Lab tests and Medicines: amount and %, with bars scaled to the largest row.
- Show this card only if transactions carry a service or category; otherwise it's a GAP.

Transactions
- An All / Money in / Money out segmented control.
- Rows: day and time, an icon tile, the payer or item, "what · method", and the amount on the right. Money out is secondary grey with a minus sign.
- Tapping a row opens the EXISTING Transaction Details screen, restyled to the tokens only.
- Footer: "Today · ₹x in · ₹y out", and "See all transactions".

Pending payments (384 px)
- One row per patient with a balance above 0, oldest first.
- The date line is amber when the balance is over 14 days old.
- A "Mark paid" capsule opens Record payment, prefilled.
- A "Send reminders on WhatsApp" tint button, shown only if a WhatsApp path exists.
