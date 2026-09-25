Redesign the Patients feature (the Patients list and the Patient details screen) to match the designs in design/patients-redesign/. The dashboard redesign is already done: reuse its design tokens, theme, Geist font and shared widgets exactly as they are, and don't create a second set. Follow .claude/rules/crudoc-ui.md and design/dashboard-redesign/DESIGN_SPEC.md for every colour, type, radius and spacing rule.

WHAT'S IN design/patients-redesign/
- screens/ — the target look for every state. Open them:
  patients-1-table-all, patients-2-split-all-selected, patients-3-split-balance-due, patients-4-table-balance-due, patients-5-first-week, patient-details
- html/ — the design source files. Use them for exact sizes, colours and copy.
  - PatientsHybrid.dc.html is the Patients list to build: a working prototype with all its states.
  - Patient.dc.html is the Patient details screen.
  - PatientsFirstWeek.dc.html is the first-run state.
  - Patients.dc.html and PatientsPreview.dc.html are static snapshots of the two list modes.
  These files use a design-tool template syntax ({{...}} holes, <sc-for>, <sc-if>, and a Component class inside <script type="text/x-dc"> that holds demo data and state). Read it as a description of states and behaviour, not as code to port. Every name and number in them is demo data.

FIRST
1. If git has uncommitted changes, stop and tell me. Otherwise create and switch to branch feat/patients-redesign.
2. Study the current Patients list and Patient details screens, their providers, and the patient, visit, treatment/package and payment models and repositories.
3. Write design/patients-redesign/IMPLEMENTATION_PLAN.md: the files you'll change, and a table mapping every element described below to its real data source (an existing provider or repository method) or "GAP".

HARD RULES
- Keep the architecture: feature-first folders, Riverpod, and repositories as the only data source (local-first SQLite with Firestore sync). Widgets never touch SQLite or Firestore.
- Don't change models, schemas or sync code. Anything without data is a GAP: hide that element and record it. Never show sample or placeholder data.
- One filled Ink Blue button per region. Amber = needs attention (waiting, overdue, balance due). Red = allergies only. Violet = AI (Scribe) only. Green = done or paid.
- Sentence-case section headings; no ALL CAPS headings.
- Remove the floating chatbot button from these screens.

PATIENTS LIST — LAYOUT
- Header: "Patients" large title, then one line "<total> patients · <n> new this month". Right: "Import / Export" (secondary) and "Add patient" (the only filled button).
- Remove: the gender donut, the four stat cards, the "No." column, Date of birth, Updated, the "Active" status pill, and the per-row view/edit icons.
- Full-width 44 px search bar: "Search by name, phone, patient ID or condition", with a Sort button beside it.
- Filter chips, single select, with live counts: All · Last 7 days · Follow-up overdue (amber dot) · Balance due (amber dot) · In treatment · New this month. Hide any chip whose count is 0, except All.

PATIENTS LIST — BEHAVIOUR
The screen has two modes. The app picks the mode from what the user does; there is no toggle.
1. Table mode (default, nothing selected): full-width table with columns Patient (monogram, name, "ID · phone" with the phone grouped 5+5), Age · sex, Condition and treatment ("session x of y"), Last visit (date + time), Next visit (date + time, or amber "Overdue" with "since <date>", or "—"), Balance (amber when above 0, "—" when 0), and a chevron. When sorted by last visit, group rows under "Seen today", "Past 7 days" and "Earlier", each with its count.
2. Clicking a row selects it and switches to split mode:
   - The list becomes compact two-line rows: name and treatment on the left; on the right, the last visit, or the amount due + "since <date>" under Balance due, or days overdue under Follow-up overdue.
   - A 420 px preview pane slides in on the right (240 ms, easeOutCubic).
   - The selected row gets the accent-tint background and a white monogram with accent-coloured initials; separators next to it are hidden.
   - Clicking another row swaps the preview; the list keeps its scroll position.
3. Closing the pane (× button or Esc) returns to table mode.
4. Work-through filters open straight into split mode with the first patient selected:
   - Balance due: sorted by amount due, highest first, with a summary strip above the list: "₹X outstanding · N patients · oldest due D days" and a "Send reminders" (WhatsApp) button.
   - Follow-up overdue: sorted by most overdue, with the strip "N patients · longest overdue D days" and "Message all".
   - All other filters open in table mode with no strip.
5. Remember, per filter, whether the pane was open or closed for the rest of the session.
6. Keyboard: Ctrl F focuses search; ↑/↓ move the selection in split mode; Enter opens the full profile; Esc closes the pane.
7. Search filters live as you type (about 150 ms debounce), ignores spaces in phone numbers, and keeps the current filter. If a shared search-normalisation utility already exists, reuse it.
8. Double-clicking a row, pressing Enter, or the ↗ button in the pane opens Patient details. Coming back must restore the filter, sort, scroll position, selection and pane state.
9. Below 1200 px wide, the preview slides over the list as a sheet with a dim backdrop instead of splitting. Below 800 px, tapping a row opens Patient details directly.
10. Fixed row heights (64 px table, 62 px compact) so nothing jumps. Skeleton rows while loading. Load more on scroll, with a footer "Showing N of M".
11. Row hover uses the inset fill. Motion is 200–250 ms with no bounce, and respects reduced-motion settings.

PREVIEW PANE, top to bottom
- 56 px monogram, name, "age · sex · patient ID"; a ↗ button to open the full profile; a × button to close.
- Chips: allergy (red with a warning icon if the patient has one, otherwise neutral "No known allergies") and phone.
- Three action tiles: Call, WhatsApp, New visit.
- Money:
  - Balance above 0: "Balance due", the amount, "₹paid of ₹total paid", a green progress bar, a filled "Record payment" button, and a "Send a payment reminder" link.
  - Balance 0: "Paid in full · ₹total" with a green check and no filled button.
- Under Follow-up overdue: put an amber "Follow-up overdue since <date>" block with a filled "Book follow-up" button first, and make Record payment tinted instead of filled, so there's still only one filled button.
- Treatment: plan name, a progress bar (Ink Blue, green when complete), and "x of y done · Next: <date, time>" (amber if the next session is overdue).
- Last note: timestamp and the note text clamped to 3 lines.
- An "Open full profile" outline button.

FIRST-WEEK STATE (screens/patients-5-first-week.png)
While the clinic has fewer than 10 patients, hide the filter chips and show a panel below the list:
- "Bring your existing patients into CruDoc"
- "Import from Excel" (CSV or XLSX) and "Download the template"
- three hint cards
With 0 patients, show only the panel.

PATIENT DETAILS
- Top bar: a "‹ Patients" back link (restores list state as above). Right: Edit (secondary), a "…" menu, and "New visit" (filled).
- Identity header, not in a card: 76 px monogram; name as a large title; "age · sex · patient ID · Patient since <date>"; chips for allergy and phone; Call and WhatsApp capsule buttons on the right.
- Facts strip, reusing the dashboard's glance card: treatment progress ring "x of y sessions done", Next visit, Last visit, Balance due (amber dot, "of ₹total package").
- Treatment plan card:
  - Plan name with tooth/condition and start date.
  - A vertical stepper: done steps with a green check; the next step with an Ink Blue ring and a "Next" pill; future steps hollow, with a "Book" capsule if not booked.
  - Below it, the package: total, a green paid bar, "₹paid paid · ₹due due" (due in amber), and a "Record payment" capsule.
- Clinical notes:
  - A one-line composer, "Add a note for today's visit", that grows when focused; Ctrl+Enter saves.
  - A Scribe mic button in AI violet.
  - Notes are listed newest first. Notes dictated with Scribe carry a violet tag "Dictated with Scribe · reviewed by <doctor>".
- Visits card: Upcoming and Past sections. Each row has a date tile (month + day), a title, weekday + time, and a status. A past visit that was never completed shows "not recorded" in amber with an "Update" button — never "Pending".
- Medical history card: label/value rows (Condition, Allergies, Medications, Systemic, Tobacco, Last X-ray), then "Recorded at registration · updated <date>".
- Fix the old contradictions: sessions completed, last session and the visits timeline must all come from the same visit and treatment data.

PHASES
After each phase, `flutter analyze` must be clean and existing tests must pass; then commit.
1. The plan above.
2. Shared pieces: reuse existing widgets; add only what's missing (compact row, preview pane shell, stepper, date tile, summary strip).
3. Patients list: table mode, filters, search, sort, grouping.
4. Split mode, preview pane, work-through filters, keyboard, state restore, narrow-width sheet.
5. First-week state.
6. Patient details.
7. Golden tests at 1440 px wide for every state in screens/, using fake providers in test code only and the bundled Geist font. Compare each golden with its PNG and fix the differences until they match.

FINISH by writing design/patients-redesign/IMPLEMENTATION_REPORT.md and summarising it to me:
- what was built;
- every GAP, which element is hidden because of it, and the model change you'd propose;
- anything you couldn't match, and why;
- the list of commits.
