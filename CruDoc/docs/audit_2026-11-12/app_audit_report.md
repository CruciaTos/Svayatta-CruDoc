# CruDoc app audit: quality report and work packages

Date: 12 November 2026. Branch read: `main` (commit `e851370`). Method: six grep-based inventories (in `raw/`), then a second pass that opened the code to check every P1 finding and a sample of the rest. Nobody ran the app on a device. Read section 6 before you trust any number.

---

## 1. Summary

Overall: a good design system that most screens use; the work left is simpler forms, honest errors, one look, and phone and tablet fit. **Five biggest problems:**
1. Forms are too long and not uniform. The patient dialog has 10 boxes, the referral and PACS forms 16, and the homeopathy case sheet about 180 field call sites with no Enter-key handling.
2. Errors are rough. Raw exception text (`$e`) reaches the user in 13 places, and 107 `catch {}` blocks swallow errors; about half of the ones I opened hide a failure the user should see.
3. There is no shared loading, empty or error widget. Each feature builds its own (4 copies of `_LoadError`, 3 of `_NoMatches`, plus other empty widgets), and there are two dialog shells.
4. The layout has one switch at 900 px. A tablet held upright gets the stretched phone layout. About 17 desktop screens are opened inside the phone shell and nobody has checked them at phone width.
5. Some buttons lead nowhere: Patients "Import / Export" says "not available yet", inventory "Add Item" does nothing, and WhatsApp campaigns are offered but not available.
**Five biggest opportunities:**
1. One change in `cru_form.dart` (Enter saves, "More details" expander, keyboard presets) improves 67 form dialogs.
2. One friendly-error helper on the existing top "island" notice fixes 13 raw-error sites.
3. Shared skeleton, empty and error widgets give every list the same three states.
4. Missing features owners expect: automatic recalls and reminders, partial payments and refunds, CSV export, owner reports, Hindi/Marathi patient messages.
5. Two cheap speed wins: limit the visits listener by date, and show the app before the sync work finishes.

---

## 2. How to read this

**Priority.** P1 hurts users every day. P2 is visible polish. P3 is nice to have.
**Effort.** S is under 2 hours. M is under a day. L is more than a day.
**Who suits a package.** Dev = Flutter developer. Des = designer. QA = tester. BE = backend (Cloud Functions).
**The "where" column.** `file:line` is relative to `CruDoc/lib` unless it starts with `crudoc_shared/`. A folder means "start here, then look around". `(checked)` means I opened that location on 12 Nov 2026 and it was true. Rows without the mark come from the inventories and were not opened. Every P1 row that cites code is checked.
**Files and counts.** All counts are grep counts, so treat them as estimates. When I re-counted and got a different number from the inventory, I used mine and listed the difference in Appendix B.
**Central fixes first.** In each package the shared-widget or helper changes come first, then per-screen tasks grouped by feature. Do the central ones first: they make the per-screen tasks smaller.
**Counts in this report:** 226 tasks. By package: A 56, B 44, C 27, D 26, E 24, F 18, G 19, H 12. By priority: P1 39, P2 123, P3 64. By effort: S 122, M 89, L 15. The ten most important tasks are A1, A20, A23, B1 with B2 to B7, B10, D1, D2, E1, F1 and G1.

**Work covered elsewhere (do not redo).** Security, privacy and compliance: `docs/security_plan.md` (SEC-* tasks: encryption keys, 2FA, App Check, audit logs, DPDP, VAPT, ISO 27001). Apple App Store and Mac App Store: `docs/apple_store_readiness_audit.md` and `handoff/antigravity_apple_store.md` (12 of 41 checks pass; Mac build and console steps are the owner's). Everyday workflow gaps (quick patient, duplicate phone warning, booking overlap, follow-up booking, cancel notices, partial payments, refunds, close the day): `handoff/antigravity_workflow_gaps.md`, Phases 1 to 4, "Done: nothing yet". Old UI that still differs from the Calm Clinical design: `docs/ui-audit-2026-10-23.md` (most rows are done; its open item "Spec decisions" is about the phone blue palette, the Day sidebar card and the Up next card). Where this report touches the same ground it says so.

---

## 3. Work packages

### Package A. Forms and data entry

**Goal.** Every form is short, fast with the keyboard, and behaves the same. A doctor can register a patient or save a record without touching the mouse.
**Why it matters to a doctor.** Forms are the work. A shorter form saves minutes every patient, and a form that asks for something already known (age and date of birth, patient name on a certificate) feels careless.
**Suits.** Dev, Des, QA.

**The form standard (every form must pass all ten points)**
1. **Keyboard.** Enter or the Next key moves to the next box. Enter in the last single-line box saves. In a multi-line box Enter adds a line. Ctrl+Enter and Ctrl+S always save (already built in `CruFormDialog`).
2. **Focus.** The first empty box is focused when the form opens.
3. **Keyboard type.** Phone: phone pad. Number: number pad. Amount: decimal pad with the rupee prefix. Email: email keyboard. Names: capitalise words.
4. **Errors.** Shown under the box (`CruFieldError`). A save failure goes in the form's `notice` line above the footer. Never a pop-up and never raw exception text.
5. **Required boxes.** One rule for the whole app: a box with the "Optional" tag is optional; a box without it is required and shows "Enter <name>" under the box when empty. Remove hand-made asterisks (such as `'Patient Name *'` in `queue/presentation/check_in_dialog.dart:450`).
6. **One primary button.** Always at the bottom right of the form footer, labelled with the same verb (Save). Cancel is secondary at its left. Use `CruFormDialog` on every platform.
7. **Size.** At most about 8 boxes visible. Everything else is behind "More details" (a collapsed section) or filled automatically.
8. **Nothing asked twice.** If the app already knows it (patient name, age, doctor, today's date), fill it and show it as text.
9. **Smart defaults.** Date = today, doctor = the signed-in doctor, status = derived from other boxes.
10. **Unsaved changes.** Closing a changed form asks before discarding (already built in `CruFormDialog`, `cru_form.dart:70-80` (checked)).

**What already exists (checked).** `CruTextField` defaults to the Next action (`crudoc_shared/lib/widgets/cru/cru_form.dart:756-760`). `CruFormDialog` binds Ctrl+Enter and Ctrl+S (`:103-106`). Errors show under the box through `CruFieldFrame`. There is an `optional` tag (106 uses), an `autofocus` option (31 uses), and `CruFormDialog` has a `notice` line for save failures. What is missing is Enter-saves-on-last-box, the "More details" expander, keyboard presets and a focus-first rule.

#### A. Central fixes

| ID | Task | Where | Priority | Effort | Done when |
|---|---|---|---|---|---|
| A1 | Make Enter in the last single-line box save the form. Give `CruFormDialog` a scope that tells the last `CruTextField` to call `onSubmit` on Enter. Keep Ctrl+Enter and Ctrl+S. Multi-line boxes keep Enter = new line. Covers 67 `CruFormDialog` uses in 47 files with no per-screen edit. | `crudoc_shared/lib/widgets/cru/cru_form.dart:28-105` (checked), `:535-775` (checked) | P1 | M | Open Add patient, type in the last box, press Enter: it saves. In a notes box Enter adds a line. Ctrl+Enter still saves. |
| A2 | Test Enter-to-next on Windows and on a phone. The field already sets the Next action and Flutter normally moves focus by itself; the inventory suspected it fails on Windows and I could not confirm either way. If it fails, map Enter to `NextFocusIntent` in a `Shortcuts` widget around the dialog. | `crudoc_shared/lib/widgets/cru/cru_form.dart:746-772` (checked) | P1 | S | On Windows, in Add patient, Enter in First name lands in Last name. Tab order matches the visual order. Same on an Android phone with the Next key. |
| A3 | Add `CruFormMore`: a "More details" expander (AnimatedSize 250 ms, closed by default, remembers open state while the dialog is open). Every simplification below needs it. | `crudoc_shared/lib/widgets/cru/cru_form.dart:323` (checked: `CruFormSection` is here; the new widget goes beside it) | P1 | S | A form can wrap boxes in `CruFormMore`; they are hidden until tapped; a box with an error inside opens the section by itself. |
| A4 | Required-box rule: add `required: true` to `CruTextField`, which adds the "Enter <name>" validator and shows the error under the box. Delete hand-made asterisks. | `crudoc_shared/lib/widgets/cru/cru_form.dart:535-600` (checked), `queue/presentation/check_in_dialog.dart:450` (checked) | P2 | S | Leaving a required box empty and pressing Save shows the message under that box and focuses it. |
| A5 | Keyboard presets: `CruTextField.phone`, `.amount`, `.number`, `.email`, `.name` set the keyboard type, input filter, autofill hints and action in one place. Then check the 243 `CruTextField` constructions: only 70 `TextInputType.phone/number/email` uses exist. | `crudoc_shared/lib/widgets/cru/cru_form.dart` | P2 | M | Every phone, amount and email box in the list in the PR shows the right keyboard on a phone. No letters accepted in an amount box. |
| A6 | Focus the first empty box when a `CruFormDialog` opens (today only 31 `autofocus: true` uses). | `crudoc_shared/lib/widgets/cru/cru_form.dart:28` | P2 | S | Open any form dialog: the cursor is already in the first empty box. |
| A7 | One dialog shell. `DentalPanelDialog` (55 uses) and `CruFormDialog` (67 uses) do the same job with different code. Make `DentalPanelDialog` a thin wrapper over `CruFormDialog` so A1, A3 and A6 reach dental too. | `features/dental/presentation/desktop/dental_ui.dart:941-964` (checked) | P2 | M | A dental dialog and a patient dialog have the same header, footer, shortcuts and discard prompt. |
| A8 | Save errors go to the form's `notice` line, not a pop-up. Known pop-up cases: the case sheet and the template editor. | `features/homeopathy/presentation/homeopathy_case_taking_sheet.dart:842` (checked), `core/pdf/presentation/editor/template_editor_screen.dart:516` (checked) | P2 | S | Force a save failure: the message appears above the Save button and the form stays open. |
| A9 | One `CruMoneyField` (rupee prefix, digits and one decimal point, tabular figures). The patient dialog uses a hand-made filter `[0-9.,]` that accepts "1.2.3". | `features/patients/presentation/desktop_add_edit_patient_dialog.dart:818-822` (checked) | P2 | S | Typing "1.2.3" is refused. The same widget is used in invoice, transaction, medicine price and consultation fee boxes. |
| A10 | One `CruAgeField` that fills age from date of birth or the other way. The patient dialog has both as separate boxes. | `features/patients/presentation/desktop_add_edit_patient_dialog.dart:692,708` (checked) | P2 | S | Typing a date of birth shows the age; typing an age leaves date of birth empty and saves the age only. |
| A11 | Replace the 54 raw `TextField` / `TextFormField` (33 files) with `CruTextField` so A1 to A6 reach them. Known: `patients/presentation/patient_form.dart:452` (checked), `homeopathy/presentation/widgets/homeopathy_form_helpers.dart:144` (checked), `features/mobile/mobile_kit.dart:1506` (checked), report editor (2), prescription sheet (5), campaign composers (5 each), dental inventory screen (7), form builder (3). | `grep -rnE "TextField\(\|TextFormField\(" lib` | P2 | M | The same grep returns only the search lift field and the `CruTextField` implementation. |

#### A. Per-screen tasks (grouped by feature)

| ID | Task | Where | Priority | Effort | Done when |
|---|---|---|---|---|---|
| A20 | **Patients, desktop Add/Edit dialog.** 10 boxes now. Keep visible: First name, Last name, Mobile, Sex. Merge Date of birth and Age (A10). Move Email, Conditions, Notes and Package balance behind "More details". Package balance does not belong in a create dialog; show it only when editing. See the form table below. Align with R1/R2 "quick patient" in `handoff/antigravity_workflow_gaps.md`. | `features/patients/presentation/desktop_add_edit_patient_dialog.dart:646-822` (checked) | P1 | M | A new patient can be saved with four boxes. Enter walks through them. Age and date of birth are one box. |
| A21 | **Patients, phone Add/Edit sheet.** Use the same field list as A20 (one source for both). Replace the raw `TextFormField`. | `features/patients/presentation/patient_form.dart:420,452,744` (checked) | P1 | M | Phone and desktop show the same boxes in the same order. No raw field remains in the file. |
| A22 | Standardise the patients search boxes and the one raw field in patient dialogs. | `features/patients/presentation/patients_search_bar.dart`, `patient_dialogs.dart` | P3 | S | Search boxes use one widget, same height and clear button. |
| A23 | **Revenue, Create invoice dialog.** About 16 boxes in 6 sections. Remove the Status box (derive it from Amount received). Show Payment mode only when Amount received is above 0. Default Due date to Invoice date. Hide Invoice number and Set number (Auto) behind More details. Default Attending doctor to the signed-in doctor and show the box only when the clinic has more than one doctor. Move Clinical notes and Round off behind More details. Line items: Enter in the last box of a row adds the next row. | `features/revenue/presentation/desktop_create_invoice_dialog.dart:846-1068` (checked) | P1 | M | A standard invoice is created with: patient, one or more items, amount received. All else is automatic or under More details. |
| A24 | Replace the private text field and the duplicated treatment/medicine adders with `CruTextField` and one `_LineItemAdder`. | `features/revenue/presentation/desktop_create_invoice_dialog.dart:1152-1182,1221-1256,1585-1668` | P2 | S | The private field class is deleted; one adder widget serves both. |
| A25 | Add-transaction dialog: replace the raw field, use `CruMoneyField` (A9). | `features/revenue/presentation/desktop_add_transaction_dialog.dart` | P2 | S | No raw field; amount filter matches A9. |
| A26 | Invoice screen search box to the standard search widget. | `features/revenue/presentation/desktop_invoices_screen.dart` | P3 | S | Same search widget as patients. |
| A27 | **Inventory, Add/Edit medicine dialog.** 10 boxes plus photo. Keep visible: Name, Unit (default "pcs"), In stock, Price per unit, Expiry date. Merge "Alert at" and "Good at" into one "Low-stock alert" (derive "Good at" as twice the alert). Move Supplier and Batch number behind More details. Suggest Category from the name. | `features/inventory/presentation/desktop_add_edit_medicine_dialog.dart:590-729` (checked) | P1 | M | A medicine can be saved with five boxes. Low-stock colours still work. |
| A28 | Bill review dialog: Enter moves to the next row. | `features/inventory/presentation/desktop_bill_review_dialog.dart` | P2 | M | In the review table, Enter on the last box of a row focuses the first box of the next row. |
| A29 | Stock adjustment dialog and inventory search field: use the shared scope and search widget. | `features/inventory/presentation/stock_adjustment_dialog.dart`, `inventory_search_field.dart` | P3 | S | Same behaviour as A1. |
| A30 | **Homeopathy case-taking sheet.** About 180 field call sites (106 `_buildTextField` plus 76 `HomeopathyFormField`), 0 uses of `textInputAction` or `onSubmitted` (checked). Split into 4 steps: (1) Presenting complaint, (2) Modalities and generals, (3) Mind, past and family history, (4) Examination and prescription. Show only step 1 and the analysis open; all other sections collapsed by default (AnimatedSize). Ask the clinic's homeopath which fields are used rarely and put those behind More details. | `features/homeopathy/presentation/homeopathy_case_taking_sheet.dart:2741` (checked), `.../widgets/homeopathy_extended_form_sections.dart` | P1 | L | A first consultation is saved from step 1 alone. Enter walks through the boxes in a section. The sheet opens in under one second on a mid-range laptop (QA measures). |
| A31 | Make `HomeopathyFormField` wrap `CruTextField` with the voice button as `trailing`. Fixes all ~180 sites at once. | `features/homeopathy/presentation/widgets/homeopathy_form_helpers.dart:101-144` (checked) | P1 | M | The helper contains no raw `TextField`; the voice button still works. |
| A32 | Patient details raw field to `CruTextField`. | `features/homeopathy/presentation/homeopathy_patient_details_screen.dart` | P2 | S | No raw field. |
| A33 | **Dental, root canal (endo) record.** About 14 boxes in one scroll. Split into three groups: Diagnosis (Tooth from the chart, Pulpal, Periapical, EPT reading), Canals (repeatable rows: working length, reference, master file), Obturation (Technique, Material, Sealer, Obturated on = today). Instructions and Notes behind More details. | `features/dental/records/endo_dialog.dart:385-705` (checked labels) | P1 | M | A record is saved with the tooth, two diagnosis values and one canal. Tooth is pre-filled from the chart selection. |
| A34 | **Dental, anaesthesia pre-op.** 13 boxes. Fill Weight and Height from the patient record when known; BMI stays calculated. Pull Known allergies and Current medications from the patient's medical history card, do not ask again. Default fasting hours (solids 6, clear fluids 2). Airway notes behind More details. Do not ask for consent here if a signed consent exists (see A36). | `features/dental/specialties/anaesthesia/preop_dialog.dart:441-629` (checked labels) | P1 | M | For a patient with a medical history, allergies and medications appear without typing. |
| A35 | **Dental, referral dialogs.** The referral has Patient, Reason, Teeth, Clinical findings, Question, Urgency, Files; the contact form has 8 boxes. Contact: keep Name and Phone (WhatsApp) visible, plus Specialty and Clinic; move Email, City, Standard turnaround and Notes behind More details; fill all from the CruDoc ID lookup when found. Referral: Teeth from the chart selection, Clinical findings from the latest chart note, Urgency default "Routine", Patient from the open patient. | `features/dental/referrals/referral_dialogs.dart:365-852` (checked labels) | P1 | M | Referring from an open patient with a tooth selected needs only Reason and a contact. |
| A36 | Consent dialog: Name, Date of birth and Gender come from the patient (check whether they already do; not confirmed), Date = today, Relationship only appears when the signer is not the patient, Witness behind More details. | `features/dental/records/consent_dialog.dart:479-541` (checked labels) | P2 | S | Signing for the patient needs only the signature. |
| A37 | Standardise the remaining dental dialogs (procedure, treatment plan, recall, perio staging, scaling and root planing, clinical forms): Enter next, last box saves, More details for notes and materials. | `features/dental/presentation/desktop/dental_dialogs.dart`, `dental/records/clinical_forms.dart`, `recalls.dart`, `perio_staging.dart`, `srp_dialog.dart` | P2 | M | Each dialog passes the ten-point standard. |
| A38 | Form builder and form fill: replace raw fields with `CruTextField`; check that the submit label reads sensibly (`form_fill.dart:176` says "Submit response" while editing, "Edit response" while reading (checked); use "Save" and "Edit"). | `features/dental/specialties/forms/form_builder.dart` (checked: 3 raw fields), `form_fill.dart:176` (checked) | P2 | M | No raw field; button says Save/Edit. |
| A39 | Dental inventory screen: raw `DropdownButtonFormField` at `:86` (checked) and raw text fields (7) to `CruDropdownField` / `CruTextField`. | `features/dental/presentation/dental_inventory_screen.dart:86` (checked) | P2 | M | No raw form control remains. |
| A40 | Lab case dialog: move to `CruFormDialog` standard (20 raw matches in the inventory, not opened). | `features/dental/specialties/prostho/lab_case_dialog.dart` | P2 | S | Same header/footer/shortcuts as other dialogs. |
| A41 | Drug log and charting page raw fields. | `features/dental/specialties/anaesthesia/drug_log.dart`, `features/dental/presentation/desktop/charting_page.dart` | P2 | S | No raw field. |
| A42 | Radiology report editor: replace 2 raw fields, keep Enter = newline in the report body. | `features/radiology/presentation/reports/report_editor_screen.dart` (checked: 2 raw fields) | P2 | M | The findings box takes new lines; other boxes follow the standard. |
| A43 | PACS dialogs (16 boxes): keep Name and DICOMweb address visible; put Sign-in (username/password) and "Receiving" (AE title, port) behind an "Advanced" section; add a "Test connection" button. Worklist search: Patient name and ID visible, Accession, From, To, Modality behind filters. | `features/radiology/presentation/pacs_dialogs.dart:219-975` (checked labels) | P2 | M | A standard PACS is added with two boxes and a test button. |
| A44 | Other radiology raw fields (dialogs, side panel, report kit) and the template manager. | `features/radiology/presentation/radiology_dialogs.dart`, `viewer/side_panel.dart`, `report_kit.dart`, `template_manager.dart` | P3 | S | No raw field. |
| A45 | **Scribe, prescription sheet.** 9 labelled boxes plus drug rows, 5 raw fields. Patient name and Age/gender: show as text from the patient, not boxes (check current behaviour; not confirmed). Vitals, Lab tests, Diet advice behind More details. Drug rows: dose and frequency from preset pickers; duration derived from quantity. | `features/scribe/presentation/prescription_generation_sheet.dart:312-454` (checked labels) | P1 | M | A prescription for a known patient is made with complaints, diagnosis and drug rows only. |
| A46 | Session note screen: keep newline on Enter; standard otherwise. | `features/scribe/presentation/session_note_screen.dart` | P3 | S | Enter adds a line. |
| A47 | **Campaigns.** Two composers for one job: desktop modal (1678 lines) and phone sheet (1376 lines), 5 raw fields in each. Build one responsive composer. | `features/campaigns/presentation/post_campaign_modal.dart` (checked: 1,678 lines, 5 raw fields), `mobile_post_campaign_sheet.dart` (checked: 1,376 lines, 5 raw fields) | P2 | L | One composer widget; phone and desktop differ only in the shell (dialog or sheet). |
| A48 | Campaign analytics date range: use the shared date picker. | `features/campaigns/presentation/campaign_analytics_dialog.dart` | P3 | S | Uses `CruDateTile`. |
| A49 | **Appointments, schedule visit.** Two forms for one job: desktop dialog (Date, Time, Length, Doctor, Place, Maps link, Reason, Notes, address) and phone sheet (Date, Time, Duration, Doctor, Home address, Maps link). One form. Hide Doctor when the clinic has one doctor. Show Place, address and Maps link only for a home visit. Notes behind More details. Length default from the specialty. One word: "Length" on desktop and "Duration" on phone today. | `features/appointments/presentation/desktop_schedule_visit_dialog.dart:642-1008` (checked labels), `schedule_visit_sheet.dart:335-417` (checked labels) | P1 | M | Booking a clinic visit needs Patient, Date, Time. A home visit adds the address. Both platforms use the same widget. |
| A50 | Appointments raw search fields (patient picker, session details) to the standard search widget. | `features/appointments/presentation/patient_picker_dialog.dart`, `session_details_sheet.dart`, `desktop_session_details_dialog.dart` | P2 | S | No raw search field. |
| A51 | **Queue, check-in.** 4 boxes, 1 raw. Registered patient: name and phone are text; only Reason (optional) and Doctor (default) remain. Walk-in: Name (required), Phone. | `features/queue/presentation/check_in_dialog.dart:206-481` (checked labels) | P2 | S | A registered patient is checked in with one tap and Enter. |
| A52 | **Files.** Replace raw fields in `files_bars.dart`; standard for rename and transfer dialogs. | `features/files/presentation/files_dialogs.dart`, `files_bars.dart`, `compose_transfer_dialog.dart` | P3 | S | No raw field. |
| A53 | **Settings, Clinic details** (14 boxes). Group in cards. Card 1 Identity: Clinic name, Phone, Address. Card 2 Billing: GSTIN, UPI ID, Terms on bills; "Name shown when paying" defaults to Clinic name. Behind More details: Tagline, Website, Registration number, Clinic timings, Footer note, document numbering. | `features/settings/presentation/documents/clinic_details_tab.dart:383-672` (checked labels) | P2 | M | A new clinic fills 3 + 3 boxes; the rest are optional and collapsed. |
| A54 | **Settings, My details.** "Medical council" and "Council name" look like one question asked twice (check the code; not confirmed). Merge. Direct phone and Direct email default to the clinic's and move behind More details. | `features/settings/presentation/documents/my_details_tab.dart:527-589` (checked labels) | P2 | S | One council box. Direct contacts are optional. |
| A55 | Templates tab and delete-account dialog: standard scope only. | `features/settings/presentation/documents/templates_tab.dart`, `delete_account_dialog.dart` | P3 | S | Enter submits where it makes sense. |
| A56 | **Todos.** Title, due date, priority: Enter in Title saves; due date defaults to today. | `features/todos/presentation/todo_dialog.dart` | P2 | S | Typing a title and pressing Enter creates the to-do. |
| A57 | **Reports, certificates and medical report sheet.** Patient details come from the patient, not boxes. 1 raw field in the report sheet. | `features/reports/presentation/certificate_dialog.dart`, `medical_report_generation_sheet.dart` | P2 | S | A certificate for an open patient needs only the certificate text and dates. |
| A58 | **Team.** Invite sheet: Enter sends the invite. | `features/team/presentation/invite_sheet.dart`, `role_editor_sheet.dart` | P3 | S | Enter submits. |
| A59 | **Scan.** Confirmation forms (bill: 8 boxes, record: 3, note: 2): fill from the scan result, Enter next. | `features/scan/presentation/scan_bill_page.dart`, `scan_record_page.dart`, `scan_note_page.dart` | P2 | M | After a scan the boxes are already filled; the doctor only confirms. |
| A60 | **Dashboard.** Search field to the standard search widget. | `features/dashboard/presentation/dashboard_search_field.dart` | P3 | S | Same widget as other search boxes. |
| A61 | **Onboarding.** Keep to the fewest boxes; Enter next; loyalty card raw field. | `features/onboarding/presentation/onboarding_flow.dart`, `doctor_loyalty_card.dart` | P2 | S | Onboarding is completed with the keyboard only. |
| A62 | **Support.** Feedback dialog raw field. | `features/support/presentation/feedback_dialog.dart` | P3 | S | No raw field. |
| A63 | **Therapy.** Physio photo notes: standard scope. | `features/therapy/presentation/physio_photos_dialog.dart` | P3 | S | Enter behaviour as standard. |
| A64 | **Auth.** `phone_auth_sheet.dart:263-295` is the best form in the app (done + onSubmitted); copy its pattern. Check the sign-in screen's Enter flow. | `features/auth/presentation/phone_auth_sheet.dart:263-295`, `auth_screen.dart` | P2 | S | On the sign-in screen, Enter submits at each step. |

No forms to change: `tutorial`, `voice`, `subscription`, `update`, `tasks`, `messaging`, `profile`, `mobile` (the one raw field in `mobile_kit.dart:1506` is in A11).

#### A. The worst forms: what to remove, merge, fill automatically or hide

Box counts come from the labels in the code. Proposals are design advice; before removing a box, check how the code uses its value.

| Form | Boxes now | Keep visible | Merge | Fill automatically | Behind "More details" | Remove |
|---|---|---|---|---|---|---|
| Patient add/edit (desktop) | 10 | First name, Last name, Mobile, Sex | Date of birth + Age | Age from date of birth | Email, Conditions, Notes | Package balance (show only when editing) |
| Create invoice | about 16 | Patient, items, Amount received | Status folds into Amount received | Status, Due date, Attending doctor, Invoice number, Round off | Clinical notes, Invoice number, Round off | Status box |
| Medicine add/edit | 10 + photo | Name, Unit, In stock, Price, Expiry | Alert at + Good at | Good at = 2 x alert, Category from name | Supplier, Batch number | none |
| Homeopathy case sheet | about 180 call sites | Chief complaint, analysis | Repeated "duration/onset" style boxes per symptom | Patient details, last visit's medicines | Everything except step 1 | Boxes nobody uses (ask the homeopath) |
| Root canal record | about 14 | Tooth, Pulpal, Periapical, one canal | Canal rows repeat | Tooth, Obturated on = today | Instructions, Notes, extra canals | none |
| Anaesthesia pre-op | 13 | Procedure, anaesthesia, ASA, Mallampati | none | Weight, Height, allergies, medications, fasting defaults | Airway notes | Consent (use the consent record) |
| Referral and contact | 16 | Reason, contact name, phone | none | Teeth, findings, patient, contact from CruDoc ID | Email, City, Turnaround days, Notes | none |
| Prescription | 9 + drug rows | Complaints, Diagnosis, drug rows | Dose + frequency as one preset | Patient name, Age/gender, duration | Vitals, Lab tests, Diet advice | none |
| Clinic details | 14 | Name, Phone, Address, GSTIN, UPI ID | none | "Name shown when paying" = clinic name | Tagline, Website, Registration, Timings, Footer, numbering | none |
| My details | 9 | Name on documents, Qualifications, Specialty, Registration number | Medical council + Council name | none | Direct phone, Direct email | none |
| Schedule visit | 8 to 9 | Patient, Date, Time | Length/Duration one word | Doctor (solo clinic), Length from specialty | Notes | Place, address, Maps link unless home visit |
| PACS add | 16 | Name, address | none | AE title, port defaults | Sign-in, Receiving | none |
| Check-in | 4 | Reason (optional) | none | Name and phone (registered patient) | none | Phone for registered patients |

---

### Package B. Animations, transitions and screen states

**Goal.** The app feels calm and finished. Things move in one consistent way, and every list has a loading, an empty and an error state in plain words.
**Why it matters to a doctor.** A blank panel or a raw message like "FirebaseException: permission-denied" makes a doctor think data is lost. A smooth, predictable app feels safe.
**Suits.** Dev, Des, QA.

**The motion standard**

*Names (one place: `crudoc_shared/lib/theme/cru_tokens.dart:240-255` (checked), class `CruMotion`)*

| Name | Time | Use |
|---|---|---|
| `quick` (new) | 120 ms | Press, hover, selection highlight, checkbox |
| `fast` | 200 ms | Tab content change, row add or remove, field focus, small fades |
| `standard` | 250 ms | Dialogs, sheets, panels, expanding sections |
| `slow` (new) | 400 ms | Full-screen route on desktop, number count-up, rare large moves |
| `pane` 240, `strip` 220 | | Keep as aliases of `standard` so nothing breaks |

Curves: `curve` = easeOutCubic for things entering; `curveExit` (new) = easeInCubic for leaving; `curveMove` (new) = easeInOutCubic for things that move across the screen. Always use `CruMotion.of(context, ...)`; it returns zero when the person asked for reduced motion. No `Duration(milliseconds: ...)` literals in feature code (there are 138 now, 30 different values).

*Which transition for what*

| Event | Transition |
|---|---|
| Open a screen on desktop | Fade plus 16 px slide up, `standard`. Sidebar tab change: crossfade the content, `fast`; the header stays still. |
| Open a screen on a phone | Platform default push; swipes slide content only and keep the header pinned. |
| Open a dialog | Fade plus scale 0.97 to 1, `standard`. |
| Open a bottom sheet | Slide up with `curve`, scrim fades in, `standard`. |
| Switch tabs or sections | Crossfade (`AnimatedSwitcher`), `fast`. No slide. |
| Add or remove a list row | Size and fade, `fast` (`AnimatedList` or `AnimatedSize`). Today 0 uses of `AnimatedList`. |
| Expand or collapse a panel | `AnimatedSize` plus child fade, `standard`. |
| Selection (row, chip, tooth) | Colour and outline tween, `quick`. |
| Save, delete, check-in confirmed | One short message (island) and, on phones, a light haptic. |

*Screen states (every list and table must have all three)*

1. **Loading:** a skeleton that has the same shape as the content (not a spinner). Spinners only inside buttons. Skeleton fades into content (`fast`).
2. **Empty:** an icon, one plain sentence and one action button ("Add your first patient"). A search with no results says what was searched and offers "Clear search".
3. **Error:** a plain sentence ("We could not load your patients."), a "Try again" button, and the technical text only in the log. Never `$e`.

**What already exists (checked).** `CruMotion` has 4 durations and a reduced-motion guard. There is one notice path: `showIsland` in `core/utils/app_notice.dart:51` (141 calls in 65 files), and the toast look comes from the theme (`ui-audit-2026-10-23.md`, "One toast style app-wide"). Skeletons exist only for appointments (`DaySkeleton`, `WeekSkeleton`) and the dashboard glance card. No shared empty-state or error-state widget exists (dental has its own `DentalEmptyState`, `dental_ui.dart:804`).

#### B. Central fixes

| ID | Task | Where | Priority | Effort | Done when |
|---|---|---|---|---|---|
| B1 | Friendly-error helper on the existing island: `AppNotice.error(context, 'Could not save. Try again.', error: e, onRetry: ...)`. It logs the raw error with `debugPrint` and shows only plain text with an optional Try again action. Then apply it to B2 to B7. | `core/utils/app_notice.dart:51` (checked) | P1 | S | Calling it with an exception shows no exception text on screen; the log has it. |
| B2 | Remove raw errors from the dashboard: `say('Could not start the consultation: $e')` and `Text('$e')` in a SnackBar. | `features/dashboard/presentation/dashboard_actions.dart:265,299` (checked) | P1 | S | Force each failure: a plain sentence appears. |
| B3 | Remove raw errors on the phone: schedule (2), island, home (2). | `features/mobile/mobile_schedule.dart:1067,1262` (checked), `mobile_island.dart:151` (checked), `mobile_home.dart:152,445` (checked) | P1 | S | Same as B2 on a phone. |
| B4 | Remove raw errors in Files: transfers sheet and send sheet. Add a Try again action. | `features/files/presentation/transfers_sheet.dart:124` (checked), `send_sheet.dart:153` (checked) | P1 | S | A failed send shows "Could not send. Try again." with a working retry. |
| B5 | Voice overlay: `'Voice is off: $e'` becomes a plain sentence plus an "Open settings" action. | `features/voice/presentation/voice_overlay.dart:100` (checked) | P1 | S | With the microphone blocked, the overlay explains how to fix it. |
| B6 | Case sheet save failure: plain sentence, keep the form open (see A8). | `features/homeopathy/presentation/homeopathy_case_taking_sheet.dart:842` (checked) | P1 | S | Failure shows no exception text. |
| B7 | PDF template editor: `'Save failed: $e'` and `'Could not render preview: $e'`. | `core/pdf/presentation/editor/template_editor_screen.dart:516,576` (checked) | P1 | S | Same as B2. |
| B8 | Other raw error text (not opened): campaign analytics retry, update installer, editor panels, LAN client. | `features/campaigns/presentation/campaign_analytics_dialog.dart:92` (checked), `core/update/platform/update_installer.dart:57,87` (checked), `core/pdf/presentation/editor/editor_panels.dart:326` (checked), `:1104`, `features/files/lan/lan_client.dart:291` (checked) | P2 | S | Same as B2. |
| B9 | Triage the 107 one-line `catch {}` blocks. I opened 8: about half hide a failure the user should see (WhatsApp link fails silently at `scribe/presentation/prescription_generation_sheet.dart:706` (checked); profile writes at `settings/presentation/documents/my_details_tab.dart:480` and `clinic_details_tab.dart:270` (checked); cancelling a file offer at `files/data/colleague_send.dart:133` (checked)); the rest are harmless cleanup (stopping the recorder, `desktop_settings_screen.dart:588` sign-out (checked)). By feature: files 18, radiology 13, settings 7, scribe 6, messaging 6, dental 4, voice 4. For each: either show a message (`AppNotice.error`) or add a one-line comment saying why silence is right. | `grep -rnE "catch \(_\) \{\}" lib` (checked count 107) | P2 | M | Every remaining empty catch has a comment. The user-facing ones show a message in a forced-failure test. |
| B10 | Shared `CruSkeleton`, `CruEmptyState` (icon, sentence, one action) and `CruErrorState` (sentence, Try again). Replace the private copies: `_LoadError` x4, `_NoMatches` x3 (`files/presentation/files_screen.dart:857`, `inventory/presentation/inventory_screen.dart:645`, `patients/presentation/patients_screen.dart:547`), and the per-feature empty widgets (`_EmptyFiles`, `_EmptyInventory`, `DentalEmptyState`, queue `_EmptySlot`, dashboard `_Empty`). | `crudoc_shared/lib/widgets/cru/` (new), listed files (checked) | P1 | M | A screen with no data, a failed load and a slow load each show the matching shared widget in a widget test. |
| B11 | Motion tokens: add `quick`, `slow`, `curveExit`, `curveMove`; migrate the 138 `Duration(milliseconds: ...)` literals (30 different values; voice 22, radiology 30, files 16) to tokens; add a lint or grep check in CI. | `crudoc_shared/lib/theme/cru_tokens.dart:240-255` (checked) | P2 | M | `grep -rn "Duration(milliseconds" lib/features` returns only values with a comment. |
| B12 | One shared route transition for GoRouter and `Navigator` pushes (22 route-class uses). | `core/router/app_router.dart`, `features/mobile/mobile_more.dart` (`pushMobile`) | P2 | M | Desktop screen opens use the same fade-slide. Phone keeps the platform push. |
| B13 | One sheet helper `showCruSheet` (handle, radius, padding, keyboard inset) for the 32 `showModalBottomSheet` calls, and one confirm dialog helper for the 14 `AlertDialog` uses. (The dialog theme already gives `AlertDialog` the card look, so the gap is small.) No `CruSheet` exists today (0 references). | `grep -rn "showModalBottomSheet\|AlertDialog(" lib` (checked counts) | P2 | M | All sheets share the same handle and radius; a delete confirmation looks identical everywhere. |
| B14 | List and consolidate feedback helpers (`mobileSay`, `say`, `_say`, `_toast`, SnackBar via `ScaffoldMessenger`: 156 `SnackBar(` constructions). Check that each wraps `showIsland`; route the ones that do not. | `grep -rn "SnackBar(" lib` (checked count) | P2 | M | One notice path; Undo works the same everywhere. |
| B15 | Light haptic helper (17 `HapticFeedback` uses, none in shared) for check-in, save, delete confirm. | `crudoc_shared/lib/` (new helper) | P3 | S | A phone gives a light tap on check-in and save. |
| B16 | Replace list/table spinners with skeletons (58 `CircularProgressIndicator` uses; campaigns 9, radiology 9, dental 8). Keep spinners inside buttons. | `features/campaigns`, `features/radiology`, `features/dental` | P2 | M | List screens show skeleton rows while loading. |

#### B. Where animations and states are missing, feature by feature

(From the motion inventory; counts are estimates and nothing here was run.)

| ID | Task | Where | Priority | Effort | Done when |
|---|---|---|---|---|---|
| B20 | **Appointments.** Crossfade skeleton to content; slide content when changing day/week/month. | `features/appointments/presentation/widgets` | P2 | M | Changing day slides the grid; skeleton fades out. |
| B21 | **Auth.** Phone-to-OTP step transition; gentle feedback on a wrong code. | `features/auth/presentation/phone_auth_sheet.dart` | P3 | S | Steps crossfade; wrong code shakes or fades red once. |
| B22 | **Campaigns.** Replace 9 spinners with skeleton rows (B16); analytics numbers count up. | `features/campaigns/presentation` | P2 | S | No list spinner remains. |
| B23 | **Dashboard.** Stat counters tween; new schedule item fades in. | `features/dashboard/presentation/widgets` | P3 | S | Numbers animate on change. |
| B24 | **Dental.** Tooth selection highlight tween; procedure rows insert and remove with animation; spinners to skeletons. | `features/dental/presentation/desktop` | P2 | M | Selecting a tooth fades the highlight in `quick`. |
| B25 | **Files.** Transfer progress tween; thumbnail fade-in; errors visible (B4, B9). | `features/files/presentation` | P3 | S | Progress bars move smoothly. |
| B26 | **Homeopathy.** Section expand with `AnimatedSize` (with A30); save confirmation message. | `features/homeopathy/presentation` | P2 | S | Sections open smoothly; a saved case shows a message. |
| B27 | **Inventory.** Stock bar tween; row removal animation; item panel slide-in. | `features/inventory/presentation` | P3 | S | Changing stock animates the bar. |
| B28 | **Mobile.** Tab content crossfade; nav bar selection tween. | `features/mobile/mobile_shell.dart`, `mobile_nav_bar.dart` | P3 | M | Tab change crossfades; header stays still. |
| B29 | **Onboarding.** Step page transition; progress tween. | `features/onboarding/presentation` | P3 | S | Steps move in one direction. |
| B30 | **Patients.** Row highlight tween; row removal animation. (The preview pane already uses `CruMotion.pane`.) | `features/patients/presentation/widgets/list` | P3 | S | Selecting a row fades the highlight. |
| B31 | **Queue.** Insert and remove animation for entries; haptic on check-in. | `features/queue/presentation/desktop_queue_screen.dart` | P2 | S | A checked-in patient slides into the list. |
| B32 | **Radiology.** Study list skeleton; fade on study load; tool-switch crossfade. | `features/radiology/viewer`, `features/radiology/presentation` | P2 | M | Opening a study fades in; list shows a skeleton first. |
| B33 | **Reports.** Save feedback on certificates and report sheet. | `features/reports/presentation` | P3 | S | A saved certificate shows a message. |
| B34 | **Revenue.** Chart bars grow; new transaction row inserts. | `features/revenue/presentation` | P3 | S | Chart animates on load. |
| B35 | **Scan.** Capture flash feedback; result card reveal. | `features/scan/presentation` | P3 | S | A capture gives visible feedback. |
| B36 | **Scribe.** Recording pulse; note section expand. | `features/scribe/presentation` | P3 | S | Recording shows a pulse. |
| B37 | **Settings.** Section crossfade; when a toggle fails to save, revert it and show a message. | `features/settings/presentation/desktop_settings_screen.dart` | P2 | S | Failed toggle returns to its old state with a message. |
| B38 | **Shell.** Sidebar collapse tween; content crossfade on route change; header fade. | `features/shell/presentation/desktop_shell.dart`, `components/cru_sidebar.dart` | P3 | S | Collapsing the sidebar animates. |
| B39 | **Subscription.** Plan card selection tween; success state after payment; checkout sheet uses the standard sheet. | `features/subscription/presentation` | P2 | S | A paid plan shows a success state. |
| B40 | **Support.** Ticket send state ("Sending", "Sent"). | `features/support/presentation/feedback_dialog.dart` | P3 | S | Button shows progress then confirmation. |
| B41 | **Tasks.** Completed task strike-through tween; keep list skeleton. | `features/tasks/presentation/all_tasks_screen.dart` | P3 | S | Ticking a task animates. |
| B42 | **Team.** Invite sheet transition; member insert animation. | `features/team/presentation` | P3 | S | New member row fades in. |
| B43 | **Therapy.** Muscle chart highlight tween; photo compare slide. | `features/therapy/presentation` | P3 | S | Selection tweens. |
| B44 | **Todos.** Check animation; reminder list insert. | `features/todos/presentation` | P3 | S | Ticking animates. |
| B45 | **Tutorial.** Spotlight tween between steps. | `features/tutorial/presentation` | P3 | S | Spotlight glides between targets. |
| B46 | **Update.** Progress tween; error state with Try again (no raw text, see B8). | `features/update/presentation` | P2 | S | A failed download shows a plain message and Try again. |
| B47 | **Voice.** Bubble enter and exit; waveform tween; 22 duration literals to tokens (B11). | `features/voice/presentation` | P3 | S | No raw durations in `features/voice`. |

Not applicable: `messaging` (15 files, all data layer, no screens: its 6 silent catches are in B9) and `profile` (one data file, `doctor_name_change_policy.dart`).

---

### Package C. Design consistency

**Goal.** One look and one set of words across desktop and phone, Day and Evening.
**Why it matters to a doctor.** Trust. A button that says "Remove" on one screen and "Delete" on another makes a doctor hesitate before a destructive tap.
**Suits.** Des, Dev.

**The consistency standard**

*Shared widget replaces raw widget*

| Raw widget | Use instead |
|---|---|
| `TextField`, `TextFormField` | `CruTextField` |
| `DropdownButtonFormField`, `DropdownButton` | `CruDropdownField` |
| `Switch`, `SwitchListTile` | `CruSwitch`, `CruSwitchRow` |
| `ElevatedButton`, `TextButton`, `FilledButton` | `CruButton` (kinds), `CruCapsuleButton` |
| `IconButton` | `CruIconButton` |
| `AlertDialog`, custom dialogs | `CruFormDialog` (confirm helper from B13) |
| `showModalBottomSheet` | `showCruSheet` (B13, to build) |
| `ChoiceChip`, `FilterChip` | `CruFilterChip` (C5, to build) |
| `SnackBar` | `AppNotice` through `showIsland` (B14) |
| `PopupMenuButton`, `DropdownMenu` | `CruMenuButton` (C6, to build) |
| `ListTile` | a `CruPressable` row |
| `Icons.*` | `CruIcon(CruIcons.*)` |
| `Colors.*`, `Color(0x...)` | colours from `context.cru` / `CruColors` |
| `TextStyle(...)`, `fontSize:` | `CruType.*` |
| literal radius | `CruRadius.*` |
| `CircularProgressIndicator` in a list | `CruSkeleton` (B10) |

*Colours and text sizes only from the theme.* No `Color(0x...)` and no `fontSize:` outside the theme files, the dental tooth artwork, the loyalty-card artwork and PDF templates. A text size below 11 needs a written reason.
*One word for each action.* **Save** for forms that keep data. **Done** only to close a read-only sheet. **Delete** for anything destroyed. **Remove** only to detach a link (remove a tag, unlink a patient). **Cancel** to abort an edit. **Close** for read-only dialogs. **Back** only for navigation. **Try again** for errors (one wording, not "Retry"). **Undo** after a delete.

**What already exists (checked).** 10 widget files in `crudoc_shared/lib/widgets/cru`, a token set (`CruColors`, `CruType`, `CruSpace`, `CruRadius`, `CruSize`), 1,066 `CruIcon` uses. Material `AlertDialog` is styled by the theme so it already looks like a card.

#### C. Central fixes

| ID | Task | Where | Priority | Effort | Done when |
|---|---|---|---|---|---|
| C1 | Write the copy guide (the verb rules above) and do one pass. Counts now: Save 17, Done 42, Delete 30, Remove 24, Cancel 46, Close 43, Back 32, Retry 3, Try again 11 (checked). Known mismatches: 'Remove' on desktop vs 'Delete' on phone for the same action (`appointments/presentation/desktop_session_details_dialog.dart:150`), "Length" vs "Duration" (A49), "Submit response" (A38). | `docs/` (new guide); search `lib` for the quoted words 'Done', 'Remove', 'Close', 'Retry' (counts checked) | P1 | S | The guide exists; the same action has the same word on desktop and phone; "Retry" is gone. |
| C2 | Add semantic colour tokens (danger, success, warning, info, per-feature tint) and fold the 273 `Color(0x...)` literals in 28 files (checked count) onto them. Start with `mobile_kit.dart`, `mobile_backdrop.dart`, `loyalty_card_view.dart`, `cru_sidebar.dart`. | `crudoc_shared/lib/theme/cru_colors.dart` | P2 | L | `grep -rn "Color(0x" lib/features` returns only artwork files, each with a comment. |
| C3 | Decide the phone blue palette first (the open item in `docs/ui-audit-2026-10-23.md`), then make `mobile_kit.dart` a thin wrapper over the Cru tokens and delete its own palette (`MobileBlue` neon/deep/penn/lavender) and the 37 hard-coded colours in `mobile_backdrop.dart`. | `features/mobile/mobile_kit.dart:49-54` (checked), `features/mobile/mobile_backdrop.dart:46-50` (checked) | P2 | M | The phone follows Day and Evening from the same tokens as the desktop. |
| C4 | Sidebar: 17 colour literals and Material icons for navigation. Use `CruColors` and `CruIcon`. | `features/shell/components/cru_sidebar.dart` (checked 17), `features/shell/presentation/desktop_shell.dart:221-226` (checked) | P2 | S | Sidebar has no literal colour and no `Icons.*`. |
| C5 | Build `CruFilterChip` / `CruChoiceChip` on the existing `CruChip` tokens; replace the 77 `ChoiceChip` / `FilterChip` uses. | `crudoc_shared/lib/widgets/cru/cru_indicators.dart` | P2 | S | Chips look the same on every screen. |
| C6 | Build `CruMenuButton` (popup menu) and use it for the 16 `PopupMenuButton`, 21 `DropdownMenu` and 35 `DropdownButton` uses (inventory counts, not re-counted). | `crudoc_shared/lib/widgets/cru/` | P2 | M | One menu look across the app. |
| C7 | Extract the duplicated private widgets: `_Row` x7, `_StatusPill` x4, `_SectionLabel` x4, `_Bars` x4, `_Chip` x3, `_OptionRow` x3, `_FileRow` x3 (counts checked). (`_LoadError` and `_NoMatches` are in B10.) | search `lib` for private classes named `_Row`, `_StatusPill`, `_SectionLabel`, `_Bars`, `_Chip`, `_OptionRow`, `_FileRow` (counts checked) | P2 | M | The grep returns nothing; features use `CruPill`, `CruSectionLabel`, `CruBarChart`, `CruRow`. |
| C8 | Extend `CruType` with the sizes actually used (9 to 10, 13, 15, 28) and replace the 123 `TextStyle(` and 115 `fontSize:` literals. Sizes 8 to 10 are small for reading; review each. | `crudoc_shared/lib/theme/cru_type.dart` | P2 | M | No `fontSize:` outside theme and artwork. |
| C9 | Decide the spacing and radius scale (the code uses about 109 different spacing values; tokens exist for 2 to 24 and 32) and migrate. | `crudoc_shared/lib/theme/cru_tokens.dart` | P3 | L | Odd values (1.5, 3, 5, 7, 9, 13, 15 ...) are gone from layouts. |
| C10 | Icons: move Material `Icons.*` (194 uses) to `CruIcon`: shell 37, campaigns 44, appointments 24, reports 18. Add missing glyphs. | `features/shell`, `features/campaigns`, `features/appointments`, `features/reports` | P3 | M | `grep -rn "Icons\." lib/features` is under 20. |

#### C. Per-screen tasks (grouped by feature)

| ID | Task | Where | Priority | Effort | Done when |
|---|---|---|---|---|---|
| C20 | **Appointments.** Delete confirmation uses a raw `AlertDialog` and `Text('Delete')`; use the confirm helper. Merge the two near-duplicate session detail surfaces (dialog 21 raw matches, sheet 29) into one body widget. Replace `_StatusPill`, `_SectionLabel`. | `features/appointments/presentation/session_details_sheet.dart:169,204` (checked), `desktop_session_details_dialog.dart` | P2 | M | One body widget; delete confirm matches others. |
| C21 | **Campaigns.** Composer: ChoiceChips and DropdownButton to Cru; colours to tokens (26 literals); 44 Material icons. Colours in `campaign_enums.dart` (18) move to a presentation palette. | `features/campaigns/presentation/post_campaign_modal.dart` (checked: 2 `ChoiceChip`), `data/models/campaign_enums.dart` | P2 | M | No raw chip or dropdown. |
| C22 | **Dental.** Dental inventory screen raw controls (A39); lab case dialog (A40); ortho slider's own colours and TextStyle; 73 TextStyle/fontSize literals in the feature. Tooth artwork colours stay but move to a named dental palette file. | `features/dental/presentation/dental_inventory_screen.dart:86` (checked), `specialties/ortho/ortho_slider.dart`, `presentation/desktop/chart/tooth_render.dart` | P2 | M | Dental has no raw form control. |
| C23 | **Files.** Action menu, nearby sharing settings, incoming card, send sheet raw widgets; duplicate `_FileRow` (2) to one `CruFileRow`; file-type colours to a token map. | `features/files/presentation` | P2 | M | One `CruFileRow`; menus via `CruMenuButton`. |
| C24 | **Inventory.** Raw dialog and menu in `inventory_actions.dart` (11); filter chips duplicate (`inventory_filter_chips.dart:47`); a Cru table widget for the list screen. | `features/inventory/presentation` | P2 | M | No private chip class. |
| C25 | **Mobile.** Colours in nav bar (16) and island (12), revenue (28), tasks (26); 42 TextStyle literals; `_Bars` and `_StatusPill` duplicates. | `features/mobile` | P2 | M | See C3. |
| C26 | **Radiology.** 65 raw matches, 24 TextStyle literals; `_SectionLabel`, `_Row` duplicates; keep painter colours in one viewer palette file. | `features/radiology` | P2 | M | Palette file exists; no duplicate `_SectionLabel`. |
| C27 | **Patients.** `patient_actions.dart` direct `ScaffoldMessenger` calls (B14); duplicate `_Section`, `_FileRow`, `_Row`. | `features/patients/presentation` | P2 | S | Uses shared widgets and `AppNotice`. |
| C28 | **Settings.** The inventory said AI assistance and call forwarding use `SwitchListTile`; I found none in `features/settings` (4 elsewhere in `lib`), so only the duplicate `_Row` in the storage section remains. | `features/settings/presentation/storage_section.dart:222`, other `SwitchListTile` in `lib` (4, checked) | P3 | S | Shared row widget; no `SwitchListTile`. |
| C29 | **Revenue.** Duplicate `_StatusPill`; migrate spacing literals. | `features/revenue/presentation/desktop_invoices_screen.dart:638` (checked: private `_StatusPill`) | P2 | S | Uses `CruPill`. |
| C30 | **Subscription.** Paywall screen: 2 raw `TextButton`s and 2 raw spinners in the Apple checkout list (the inventory said 12 raw; I found 5 matches); check tone and copy of the paywall. | `features/subscription/presentation/apple_checkout_list.dart:219,227` (checked) | P2 | S | Only `CruButton` used on the paywall. |
| C31 | **Update.** The update dialog, banner and progress sheet are the only files still using the old `AppColors` palette (3 files, 30 uses, checked), plus 20 TextStyle/fontSize literals and no Cru widget. `docs/ui-audit-2026-10-23.md` says `AppColors` is no longer used; that is no longer true here. Rebuild on `CruFormDialog` and tokens. | `features/update/presentation/update_available_dialog.dart:55` (checked), `update_banner.dart`, `update_progress_sheet.dart` | P2 | M | No `AppColors`, no literals; uses Cru widgets. |
| C32 | **Therapy.** Comparison dialog raw widgets and 14 colour literals; Material icons. | `features/therapy/presentation/physio_comparison_dialog.dart` | P2 | S | Uses `CruFormDialog` and tokens. |
| C33 | **Scan.** Camera overlay colours (19) and PDF text styles use named constants. | `features/scan/presentation/document_camera_page.dart`, `data/record_pdf.dart` | P3 | S | Overlay palette constant exists. |
| C34 | **Onboarding.** Loyalty card art colours (42) to a named constants file. | `features/onboarding/presentation/loyalty_card_view.dart` | P3 | S | Colours in one file with a comment. |
| C35 | **Voice.** Duplicate `_Bars`. | `features/voice/presentation/voice_bubble.dart`, `voice_overlay.dart` | P3 | S | Shared bar widget. |
| C36 | **Queue, todos, tutorial, team, auth, dashboard, support, tasks, profile, messaging, reports.** Mostly on the design system. Migrate the few raw widgets (queue 9, todos 5, tutorial 3, team 4, auth 1, dashboard 10); reports has 18 Material icons on 2 files. | those feature folders | P3 | S | Raw-widget count under 3 per feature. |

---

### Package D. Phones and tablets

**Goal.** Every screen a doctor can open works at phone width, tablet width and desktop width, with a finger and without a mouse.
**Why it matters to a doctor.** The phone is used in the corridor and on home visits; a tablet sits at reception. A screen that clips or needs hover is a screen that is not used.
**Suits.** Dev, Des, QA.

**The device standard**

| Width | Layout | Must work |
|---|---|---|
| Phone (under 600 dp) | Bottom tab bar, one column, dialogs become near-full-screen cards, sheets from the bottom | Every field reachable with the keyboard open; nothing clipped at 320 dp; text at 130 percent |
| Tablet (600 to 899 dp, and tablets in landscape) | Side rail or two-pane (list and detail); dialogs centred, max 720 wide | Both portrait and landscape; touch only |
| Desktop (900 dp and up) | Sidebar, panes, keyboard shortcuts, hover as a bonus | Whole screen usable by keyboard |

*Rules for all.* Touch targets at least 44 by 44 dp on phone and tablet (`CruSize.actionButton` is 44; `CruSize.control` is 40). Nothing may need hover or right-click: every hover or context action also has a tap or long-press. Tooltips are not the only label. No fixed width above the screen width; use `maxWidth` (the Cru dialog shells already do). Text must not clip at 130 percent text size. Keep the safe areas (notch, home bar).

**What already exists (checked).** The shell switches at one breakpoint, 900 dp (`features/shell/presentation/responsive_shell.dart:23,116`). `CruFormDialog` and `DentalPanelDialog` use the width as `maxWidth`, so a "960" dialog shrinks on a phone (`cru_form.dart:117`, `dental_ui.dart:963`). Importantly, the phone does not lack as many screens as the inventory said: `mobileDestinationScreen` in `features/mobile/mobile_more.dart:93-112` (checked) opens 17 desktop screens inside the phone shell (and one phone page, campaigns): inventory, scribe, settings, treatment plans, sterilization, procedures, radiology worklist and reports, referrers, recalls, perio patients, dental referrals, forms, lab cases, emergency protocols, files and documents. Queue sits on the Schedule tab and the Home card (`mobile_shell.dart:99-103`, `mobile_home.dart:134,445`). Only dental charting is marked "a desktop screen" (`mobile_more.dart`).

#### D. Central fixes

| ID | Task | Where | Priority | Effort | Done when |
|---|---|---|---|---|---|
| D1 | Add a tablet tier. Today widths 768 to 899 dp (iPad portrait) get the stretched phone shell with a 5-tab bar, and landscape tablets get the full desktop sidebar. Add a 600 to 899 dp layout: side rail plus list and detail panes; keep one shared constant for all breakpoints (replace the separate `< 900` in the voice overlay and `shortestSide >= 600` in CBCT). | `features/shell/presentation/responsive_shell.dart:23,116` (checked), `features/voice/presentation/voice_overlay.dart:286`, `features/radiology/cbct/cbct_device.dart:18` | P1 | M | At 768 and 820 dp wide, the app shows a rail and two panes, not a stretched tab bar. Rotating keeps the open patient. |
| D2 | Phone-width pass on the 17 desktop screens opened in the phone shell (list in the section above). Mark each pass or fail; fix the fails. Known risk: wide tables, side panels, 24 horizontal scroll views. | `features/mobile/mobile_more.dart:93-112` (checked) | P1 | L | A QA sheet lists all 17 screens at 360 by 800 dp with pass/fail and screenshots. Fails have tasks. |
| D3 | Touch targets: find icon buttons under 44 dp on phone and tablet (85 matches of compact density, small `iconSize` or zero padding, not opened). Add a minimum size in `CruIconButton` for touch devices. | `crudoc_shared/lib/widgets/cru/cru_extras.dart`, `cru_pressable.dart` | P2 | M | Every tappable icon on phone has a 44 dp hit area (checked with the layout inspector on 5 key screens). |
| D4 | Hover audit: 15 files use `MouseRegion` or `onHover`. Each hover-only action needs a tap or long-press. I checked the tooth detail view: its hover only highlights, and tapping works through `onTapUp` (`features/dental/presentation/desktop/tooth_detail_view.dart:1403-1415` (checked)), so no change there. | `grep -rlE "onHover\|MouseRegion" lib` (checked count 15) | P2 | S | The list of 15 files has a note each: "hover is cosmetic" or "tap added". |
| D5 | Right-click menus (the inventory counted 7 files; I found 4 using `onSecondaryTap`): add a long-press menu on touch. | search `lib` for `onSecondaryTap` (checked: 4 files) | P2 | S | Long-press shows the same menu on a phone. |
| D6 | Keyboard safety: the phone scaffold sets `resizeToAvoidBottomInset: false` (`features/mobile/mobile_shell.dart:188` (checked)). Only one text field sits directly in the phone screens (`mobile_kit.dart:1506`, handled by `shared/widgets/search_lift.dart`); all forms live in sheets and dialogs. So this is low risk, but test every sheet with the keyboard open. | `features/mobile/mobile_shell.dart:188` (checked) | P3 | S | On a phone, with the keyboard open, the focused box is visible in every form sheet (QA list). |
| D7 | Text scale and fixed card heights: `kMobileRevenueCardHeight = 236` can clip at large text; only 8 `textScaler` references exist. Test the phone app at 130 percent text and fix clips. | `features/mobile/mobile_revenue.dart:310` (checked) | P2 | S | At 130 percent text no text is cut off on Home, Schedule, Patients, Tasks, More. |
| D8 | Safe areas: only 3 `SafeArea` uses in `features/mobile` (not opened). Check the island, the wave screen and full-screen pages on a device with a notch and a home bar. | `features/mobile/mobile_island.dart`, `mobile_wave.dart` | P2 | S | No content under the notch or home bar. |
| D9 | Tooltips (16) used as the only label: add visible labels on phone. | `grep -rn "Tooltip(" lib` | P3 | S | Icon-only buttons have a text label on phone or a clear icon. |
| D10 | Tables use custom widgets with 24 horizontal scroll views: add a fade or scrollbar edge and a minimum column width. | `grep -rn "Axis.horizontal" lib` | P3 | M | Scrollable tables show that they scroll. |
| D11 | Visible keyboard focus ring in Cru widgets, and a Tab-order test on desktop. | `crudoc_shared/lib/widgets/cru` | P2 | M | Tab moves through a form in reading order with a visible ring. |

#### D. Per-screen tasks (grouped by feature)

| ID | Task | Where | Priority | Effort | Done when |
|---|---|---|---|---|---|
| D20 | **Dental charting on tablet.** Charting is a desktop screen only (`mobile_more.dart`). The tooth chart is the core of a dental clinic; make it work on a tablet in landscape first, then portrait; check touch size of teeth. | `features/mobile/mobile_more.dart:173` (checked: "Charting is a desktop screen"), `features/dental/presentation/desktop/charting_page.dart`, `tooth_detail_view.dart` | P1 | L | On an iPad in landscape a dentist selects a tooth and records a surface finding with one hand. |
| D21 | **Dental dialogs at phone width.** Ortho slider has fixed heights (440 at `ortho_slider.dart:329` (checked), 480, 700); photo series dialog at 960 max width. Make heights fractions of the available space; the width is already a maximum. Perio staging and form fill: check tooth grids at 360 dp. | `features/dental/specialties/ortho/ortho_slider.dart`, `ortho_photos.dart`, `records/perio_staging.dart`, `specialties/forms/form_fill.dart` | P2 | M | The ortho slider is usable at 360 by 800 dp. |
| D22 | **Template editor.** Fixed 800 by 700 content (`core/pdf/presentation/editor/template_editor_screen.dart:537` (checked)): state that the editor is desktop and tablet only and hide the phone entry point. | `core/pdf/presentation/editor/template_editor_screen.dart:537` (checked) | P2 | S | A phone shows "Use a tablet or computer to edit templates". |
| D23 | **Radiology.** CBCT is blocked below 600 dp: show a clear "Use a tablet or computer" message. Test the phone viewer (`viewer_phone_bar.dart`) on a real DICOM study; test the viewer on a tablet. | `features/radiology/cbct/cbct_device.dart:18`, `features/radiology/viewer/viewer_phone_bar.dart` | P2 | M | CBCT shows the message on a phone; a study opens, pans and zooms on a phone and a tablet. |
| D24 | **Campaigns.** Analytics dialog is capped at 880 by 720 (a maximum, so it shrinks), but whether the phone shows analytics at all was not checked; add a phone layout or a link to desktop. | `features/campaigns/presentation/campaign_analytics_dialog.dart:35` (checked) | P2 | M | Phone shows analytics summary or a clear message. |
| D25 | **Inventory.** Phone reuses the desktop screen and the desktop add/edit dialog; check list, add, stock adjust, bill review at 360 dp. | `features/inventory/presentation` | P2 | M | Add a medicine and adjust stock on a phone without clipping. |
| D26 | **Queue.** Present on the phone (Schedule tab and Home card). Check parity with the desktop queue: check in, call next, complete, reorder. | `features/queue`, `features/mobile/mobile_home.dart` | P2 | S | A receptionist runs the whole queue from a tablet or phone. |
| D27 | **Scribe.** Opens the desktop screen on the phone; check recording and review at phone width; consider capture-only mode. | `features/scribe/presentation/desktop_scribe_screen.dart` | P2 | M | A consultation can be recorded and the note reviewed on a phone. |
| D28 | **Files.** Phone opens the desktop `FilesScreen`; check the panel layout and drag actions (hold-to-share) on touch. | `features/files/presentation/files_screen.dart`, `widgets/files_panel.dart` | P2 | M | Browse, preview and send a file on a phone. |
| D29 | **Settings.** Phone opens `DesktopSettingsScreen` sections; verify every setting is reachable and fits. | `features/settings/presentation/desktop_settings_screen.dart` | P2 | M | Every settings section opens and scrolls on a phone. |
| D30 | **Homeopathy, therapy, reports.** Not in the phone destination list. Decide the phone and tablet scope for each: homeopathy case sheet (with A30), muscle chart on a tablet first, certificates. | `features/homeopathy`, `features/therapy/muscle_chart`, `features/reports` | P2 | L | A written scope per specialty and the first tablet screen works. |
| D31 | **Team.** Phone has only the invite picker; add member list and roles for the owner on phone, or document it as desktop only. | `features/team/presentation` | P3 | M | Owner can see members and change a role from a phone, or the app says where to do it. |
| D32 | **Appointments.** Patient picker dialog max 540 by 620: confirm keyboard inset on phone. | `features/appointments/presentation/patient_picker_dialog.dart:91` (checked) | P3 | S | Picker is usable with the keyboard open on a phone. |
| D33 | **Update.** Desktop-only installer: hide on phone; phones update through the store or the APK path (see F7). | `features/update/presentation/update_launcher.dart` | P3 | S | No installer UI on iOS. |
| D34 | **Support, subscription, onboarding, tutorial, profile, messaging, auth, todos, tasks, revenue, patients, dashboard.** Already have phone variants or shared flows. Include them in the device pass of D2 and H8. | those feature folders | P3 | S | Included in the QA sheet. |

---

### Package E. Speed and optimisation

**Goal.** Screens open fast and stay smooth, on a mid-range Android phone and an ordinary clinic PC.
**Why it matters to a doctor.** A patient is waiting. A chart that stutters, or a sign-in that waits on a sync, costs minutes across a day.
**Suits.** Dev.

**The speed rules**
1. Lists that can grow use `ListView.builder` (or slivers). A `ListView(children: [...])` is allowed only for a fixed, short set. (54 `ListView(` constructions today; not all are a problem.)
2. Small rebuild areas. Use `ref.watch(provider.select(...))`, or split the widget, so one field change does not rebuild a whole screen. Today: 860 `ref.watch` calls and 68 `select` calls.
3. Heavy work (DICOM, zip, image decode, big JSON, export) runs off the main thread: `Isolate.run` or `compute`. (Mostly true already: the radiology reads the inventory flagged are inside `Isolate.run`, see Appendix B.)
4. Images are decoded at the size shown: pass `cacheWidth` or `cacheHeight` to `Image.file`, `Image.memory`, `Image.network`. Today 2 uses of `cacheWidth` against 38 image constructions.
5. Streams, timers, controllers and focus nodes are cancelled or disposed (`dispose`, `ref.onDispose`). There are 55 `.snapshots()` calls, 20 `Timer.periodic`, 560 `TextEditingController` creations.
6. Firestore reads are bounded: a date range or `.limit()`. Only 11 `.limit(` calls exist.
7. Startup shows the app first; background work does not block the first screen.
8. Measure before and after. Use the Flutter profiler on a mid-range phone and report frame time, not a feeling.

**What already exists (checked).** Isolates are used for DICOM, imports and previews. The LAN and radiology catch-up work at startup is not awaited. Shipped assets are small: `assets/images/teeth` 4.4 MB, `muscle_viewer` 6.3 MB, `cbct_viewer` 3.9 MB, `dental3d` 2.6 MB. The app is not bloated by the 20 MB `Inter.zip` or the 227 MB `bonebox_teeth` folder: `pubspec.yaml` does not list them (see F14).

#### E. Central fixes

| ID | Task | Where | Priority | Effort | Done when |
|---|---|---|---|---|---|
| E1 | Limit the visits listener by date. It listens to all of a doctor's `appointments` and `visitations` forever. Use a window (for example the visible range plus a month on each side) and widen it on demand. | `features/appointments/data/repo/visits_repo.dart:98-108` (checked) | P1 | S | With 5,000 test visits the schedule opens as fast as with 50 (QA records both times). |
| E2 | Startup: after sign-in the app waits for the encryption key, the local database check, the migration and the sync start (`main.dart:197-200` (checked)). Measure time to first screen on a mid-range phone and a PC. If over 2 seconds, show the shell first and run migration and sync behind a thin progress strip. The key and database check must stay first. | `main.dart:197-200` (checked) | P1 | M | Time to first usable screen is measured before and after; target under 2 s on the reference phone. |
| E3 | Image decode sizes: add `cacheWidth` to thumbnail and grid images. Confirmed: ortho slider photos (`dental/specialties/ortho/ortho_slider.dart:385` (checked)), file thumbnails from memory (`files/presentation/widgets/file_thumb.dart:79` (checked; the file branch at `:104` already sets it)). Not opened: physio photos and comparison, scan flow, side panel, scribe thumbs, settings logos. | `grep -rnE "Image\.(file\|memory\|network)\(" lib` (checked count 38) | P2 | S | A photo grid of 50 images scrolls at 60 fps in profile mode on the reference phone. |
| E4 | `select()` on the big providers. Start with dental (133 `ref.watch`), radiology (93), appointments (93), mobile (87), patients (74). Profile first and fix the screens that rebuild most. | `features/dental`, `features/radiology`, `features/appointments`, `features/mobile`, `features/patients` | P2 | M | The profiler's rebuild count for the patient details screen drops when one field changes. |
| E5 | Batch per-row deletes inside loops. | `core/services/firestore_sync_service.dart:380-384` (checked), `features/files/data/files_repository.dart:1334-1338` (checked) | P2 | S | One transaction or batch per sync pass. |
| E6 | Bound the remaining listeners with date ranges or limits: revenue (`features/revenue/repo/revenue_repo.dart:171,195`, `invoice_repo.dart:103` (checked: no limit)), inventory, campaigns, todos (2 unbounded), team (4), doc repository (3). The activity log already has a limit (`team/presentation/activity_log_view.dart:60`) and the WhatsApp and file-blob listeners watch single documents, so they are fine. | files listed | P2 | S | Each listener has a range or limit and a comment. |
| E7 | Patient list loading: the listener returns every patient of the clinic (`features/patients/data/repo/patient_repository.dart:290` (checked)). This is acceptable for the local-first design only up to a point: measure with 5,000 patients; if slow, page or search in the local database. | `features/patients/data/repo/patient_repository.dart:285-296` (checked) | P2 | M | Patients screen opens in under 1 second with 5,000 test patients. |
| E8 | Cancel session-long listeners on sign-out and verify (55 `.snapshots()` calls): `main.dart:270`, `core/clinic/clinic_session.dart:308,341,444`, `core/services/device_session_service.dart`, `features/subscription/data/doctor_subscription_service.dart` (3 on one document: merge). | files listed | P2 | S | After sign-out the debug log shows no listener events. |
| E9 | Controller and timer audit: 7 files flagged for controllers without `dispose` (appointment_actions, forms_screen, ortho_photos, nearby_sharing_settings, homeopathy_patient_details_screen, rad_import_flow, physio_photos_dialog); the 20 `Timer.periodic` sites must cancel. Replace the 16 ms timer in the drag helper with a `Ticker`. | `features/appointments/presentation/widgets/shell/appt_drag.dart:172` (checked), 7 files listed | P2 | S | Each file has dispose for each controller; no timer survives its screen. |
| E10 | Move calculations out of `build`: team statistics. | `features/team/presentation/team_analytics_view.dart:96` (checked) | P3 | S | Stats compute once per data change. |

#### E. Per-screen tasks (grouped by feature)

| ID | Task | Where | Priority | Effort | Done when |
|---|---|---|---|---|---|
| E20 | **Radiology viewer.** `viewer_screen.dart` is 3,054 lines with 54 `setState` calls (checked). Profile pan and zoom on a large study. If the whole viewer rebuilds, move viewport state to a notifier and repaint only the canvas (`RepaintBoundary`, `CustomPainter`). | `features/radiology/viewer/viewer_screen.dart`, `viewport.dart` | P2 | L | Pan and zoom hold 60 fps on a 2000 by 3000 pixel X-ray on the reference PC. |
| E21 | **Radiology files.** Sync file reads in other places (inventory listed `viewer_export.dart:161,170`, `cbct_pack.dart:326-464`, `rvg_capture_dialog.dart:161,499`): open each and move to async if on the UI thread. (The three the inventory called worst are already inside isolates.) | `features/radiology/viewer/viewer_export.dart`, `cbct/cbct_pack.dart`, `presentation/rvg_capture_dialog.dart` | P3 | S | No sync file call on the UI thread in these files. |
| E22 | **Dental chart.** `tooth_art.dart` (2,827 lines): check `shouldRepaint` and add `RepaintBoundary`; 133 `ref.watch` calls in the feature (E4); sync file calls in `lab_case_export.dart:271` (checked) and `scan_viewer_placeholder.dart:27-74`. | `features/dental/presentation/desktop/chart/tooth_art.dart` (checked: 2,827 lines) | P2 | M | Selecting a tooth repaints only that tooth (profiler). |
| E23 | **Homeopathy.** The 2,906-line case sheet builds ~180 boxes at once. Lazy-build per step (with A30). Share one amplitude timer in the two voice sheets. | `features/homeopathy/presentation` | P2 | M | First paint of the sheet under 300 ms. |
| E24 | **Patients and mobile.** `select()` (E4); phone notifications built as a column (`features/mobile/mobile_notifications.dart:212`): use a builder. | `features/patients`, `features/mobile` | P2 | S | Notifications list is a builder list. |
| E25 | **Queue.** 2,009-line screen with a 30-second timer: one clock notifier; split panels. | `features/queue/presentation/desktop_queue_screen.dart` | P2 | M | One timer; panels split into files. |
| E26 | **Files.** Pause the colleague strip's network refresh when it is off-screen or the app is in the background. Cache previews by path and modification time. | `features/files/presentation/widgets/colleague_strip.dart:79` (checked: `Timer.periodic` refresh) | P2 | S | No network calls from the strip while hidden. |
| E27 | **Therapy.** Four full-size `Image.file` in comparison and photo cards, plus file-exists checks in `build`. | `features/therapy/presentation/physio_comparison_dialog.dart`, `physio_photos_dialog.dart`, `widgets/physio_photos_card.dart` | P2 | S | Photos use `cacheWidth`; no sync check in build. |
| E28 | **Scan.** Page images shown at full size in the review list (the inventory also suspected the camera page, but `document_camera_page.dart:818` is a 40 px thumbnail, so only the review flow needs work). | `features/scan/presentation/scan_flow.dart:211,266,336` | P2 | M | Scan flow stays smooth with 10 pages. |
| E29 | **Scribe.** Two tickers (250 ms and a processing ticker): use one and stop when idle. | `features/scribe/presentation/scribe_session_controller.dart` | P3 | S | One ticker. |
| E30 | **Messaging, support, subscription, todos, team, campaigns.** Listener limits and merges (E6, E8); subscription: merge 3 listeners on one user document. | those feature folders | P2 | S | Counts of listeners per screen written down. |
| E31 | **Revenue and inventory.** The invoice dialog (1,756 lines, 27 `setState`) to a notifier; inventory list screen (1,733 lines): move filter and sort out of `build`. | `features/revenue/presentation/desktop_create_invoice_dialog.dart` (checked: 27 `setState`), `features/inventory/presentation/desktop_inventory_list_screen.dart` | P2 | M | Typing in an invoice row does not rebuild the whole dialog. |
| E32 | **Settings, onboarding, update, tutorial, auth, voice, tasks, shell, reports, profile.** Small items: logo images with `cacheWidth`; one `select()` for nav state in the shell (19 watches); `Image.network` in the loyalty card; `update_launcher.dart:46` timer cancel. Voice and tasks are covered by the file splits in F13. | those feature folders | P3 | S | Items closed one by one. |
| E33 | **Lazy-load big bundles** (optional): muscle viewer 6.3 MB and CBCT viewer 3.9 MB ship in every install. | `assets/muscle_viewer`, `assets/cbct_viewer` | P3 | M | Not needed for speed; do only if app size becomes an issue. |

---

### Package F. Unfinished work and project clean-up

**Goal.** No button leads nowhere. The repo is tidy, so a new developer can find things.
**Why it matters to a doctor.** A dead button is the fastest way to lose trust. Clean code is what makes the other packages cheaper.
**Suits.** Dev, QA.

**The hygiene rules.** (1) A control that does nothing is hidden, disabled with a reason, or built. (2) A message that says "not available yet" appears only when the person cannot reach it from the screen they are on. (3) A source file stays under about 1,000 lines. (4) One document per topic, one format. (5) No logs, patches, zips or test debris in git.

#### F. Dead ends and unfinished features

| ID | Task | Where | Priority | Effort | Done when |
|---|---|---|---|---|---|
| F1 | Patients "Import / Export" shows "Import and export aren't available yet." Build CSV export and import (the packages are already in `pubspec.yaml`; this is item P6 in the workflow gaps brief) or hide the button until then. | `features/patients/presentation/patient_actions.dart:217` (checked), `widgets/list/patients_header.dart:109` (checked), `widgets/list/patients_first_week_panel.dart:16` | P1 | M | Export saves a CSV of all patients; import reads one; no "not available" message remains. |
| F2 | Inventory "Add Item" button on a vendor row has an empty `onPressed` and the comment "Mock action for adding item to vendor". Wire it to the add-to-vendor flow or hide it. | `features/inventory/presentation/desktop_inventory_list_screen.dart:618` (checked) | P1 | S | Tapping it adds an item to that vendor, or the button is gone. |
| F3 | WhatsApp is shown as a campaign channel with the hint "Available once your clinic connects its own WhatsApp number. Use Email for now." and dispatch throws "not available yet". Confirm the channel cannot be selected; if it can, disable it until the clinic connects its own number. | `features/campaigns/data/services/campaign_dispatch_service.dart:56-58` (checked), `presentation/post_campaign_modal.dart:1067` (checked), `mobile_post_campaign_sheet.dart:678` (checked) | P3 | S | A clinic without its own number cannot pick WhatsApp, and sees why. |
| F4 | Five tip rows in the phone gesture-tips sheet have `onTap: () {}`, so they ripple and do nothing. Make them plain rows. | `features/mobile/mobile_more.dart:611-639` (checked at 611) | P2 | S | Tapping a tip row does nothing and shows no ripple. |
| F5 | Disabled camera button (`onPressed: null`) in the inventory action sheet: show it as a real action or remove it. | `features/inventory/presentation/widgets/inventory_actions.dart:91,116` (checked at 91) | P3 | S | No dead button in the sheet. |
| F6 | The prosthodontic scan viewer is a placeholder (233 lines, "Honest placeholder note") used from the lab case dialog. Build a real viewer or show a clear empty state. | `features/dental/specialties/prostho/scan_viewer_placeholder.dart:178` (checked: 233 lines, "Honest placeholder note"), `lab_case_dialog.dart:622` | P2 | M | A lab case with a scan file opens something useful, or says plainly that viewing is not built. |
| F7 | The Android in-app updater works: `MainActivity.kt:30-36` handles `installApk` (checked). But the Dart code still throws an error text that says the bridge "is not implemented yet" if the handler is missing. Update that text, then test one real update on a phone (permission prompt, install). | `core/update/platform/android_update_installer.dart:118-130` (checked), `android/app/src/main/kotlin/com/crudoc/app/MainActivity.kt:30` (checked) | P2 | S | A test update installs from inside the app on a phone. |
| F8 | Test payments: the checkout sheet can show a "complete test payment" button when the server says `mock`. The server only allows it when `PLAN_PAYMENTS_MOCK=true` and the project is on an allow-list or starts with `demo-` (`functions/src/plan-payments.ts:119-123` (checked)). Confirm the production environment has no `PLAN_PAYMENTS_MOCK`; also hide the button outside debug builds. | `features/subscription/presentation/payment_checkout_sheet.dart:129-141,470` (checked) | P3 | S | A production build never shows the test button; env check noted in the release checklist (H9). |
| F9 | The progressive DICOM loading flag `RAD_PROGRESSIVE` is a build option (`rad_progressive_flag.dart:10`, checked: `bool.fromEnvironment('RAD_PROGRESSIVE')` forces it on, otherwise a remote check decides). Decide the default and write it in the release checklist. | `features/radiology/data/rad_progressive_flag.dart:10` (checked) | P2 | S | Default recorded; release script passes it or not on purpose. |
| F10 | Demo login is off by default (`core/services/demo_session_service.dart:14-17` (checked)). Make sure no release script passes `CRUDOC_DEMO_LOGIN=true` or the emulator flags (`main.dart:57-65`). | `core/services/demo_session_service.dart:14-17` (checked) | P3 | S | Release scripts reviewed; a release build cannot reach the emulators. |
| F11 | The only `TODO` in `lib` is the stronger key option: `core/services/encryption_key_manager.dart:123` (checked). It belongs to the security plan (SEC-* tasks). Keep it there. | `core/services/encryption_key_manager.dart:123` (checked) | P2 | M | The security plan item exists and links this line. |
| F12 | Replace 263 `debugPrint` calls by one logger with levels; remove verbose logs in release; check no patient names or phone numbers are logged (the security plan lists logs with names). | `grep -rn "debugPrint(" lib` (checked count 263) | P3 | M | One logger; logs have no personal data in release. |
| F13 | Split the huge files. 53 files are over 1,000 lines and 20 over 1,500 (checked). Largest, by feature: voice (`voice_controller.dart` 3,120 (checked), `voice_command.dart` 2,181), radiology (`viewer/viewer_screen.dart` 3,054 (checked), `report_editor_screen.dart` 1,730, `ceph_screen.dart` 1,503), homeopathy (`homeopathy_case_taking_sheet.dart` 2,906 (checked), `homeopathy_case_sheet.dart` 1,676, extended sections 1,666), dental (`tooth_art.dart` 2,827 (checked), `tooth_detail_view.dart` 2,318, `perio_chart_screen.dart` 1,713), queue (2,009), core (`local_database_service.dart` 2,004, `firestore_sync_service.dart` 1,659), mobile (`mobile_kit.dart` 1,832, `mobile_schedule.dart` 1,747, `mobile_tasks.dart` 1,499), revenue (invoice dialog 1,756), inventory (1,733), campaigns (1,678), settings (1,575). Split along the seams listed in the inventory, one file per task, only when you are already changing that file. | the files named | P2 | L | The named file is under 1,000 lines, tests still pass. |
| F14 | Repo weight (nothing here ships in the app). `tool/voice_server/.venv.old-empty` has 723 tracked files (checked); `assets/fonts/Inter.zip` 20 MB is tracked but not bundled (checked); two tracked zips (`crudoc-clinic-handoff.zip`, `crudoc-patients-handoff.zip`), a tracked `.mp4`, `build_log.txt`, `app.html`, `flutter_01.png`, `functions/upload-test-001.txt`, patch files (`doctor-data-isolation-and-encryption.patch`, `invoice-to-inventory.patch`, and `appointment-visitation-cards.patch`, `fixes.patch`, `phase4-fixes.patch` at the repository root) (checked via `git ls-files`). The 227 MB `bonebox_teeth` folder is git-ignored and not bundled (checked). Remove with `git rm --cached` and add ignore rules. | repository root, `CruDoc/tool/voice_server`, `CruDoc/assets/fonts` | P2 | S | `git ls-files` shows none of these; a fresh clone is smaller. |
| F15 | Move one-off scripts (`migrate_admin_clinical_access.js`, `seed_emulator_clinic.js`, `seed_emulator_referrals.js`, `set_admin_claims.js`, `setup_super_admin_complete.js`) into `tool/` and plan documents (`crudoc-ai-voice-scribe-feature-plan.md` and four others) into `docs/`. | `CruDoc/` root | P3 | S | Root has only project files. |
| F16 | Documents: one format per document (`security_plan.md` + `.pdf`, `ai_receptionist_plan.md` + `.pdf`, `whatsapp-meta-status.md` + `.docx`, `CRUDOC_DENTAL_HANDOFF.md` + `.docx`), one location (`whatsapp_shared_number.md` is in both `docs/` and `handoff/`). Archive the superseded `ai_receptionist_own_server_plan.md`. Move finished Antigravity briefs (25 `antigravity_*.md` in `handoff/`) to `handoff/archive/`. | `CruDoc/docs`, `CruDoc/handoff` | P3 | S | One copy per document; the briefs still open are the only ones left in `handoff/`. |
| F17 | Decide what to do with near-empty feature folders: `tasks` (one screen), `profile` (one data file), `messaging` (data only). Either fold them into a neighbouring feature or write down why they exist. | `features/tasks`, `features/profile`, `features/messaging` | P3 | S | A note in each folder or the folders are merged. |
| F18 | The open item in `docs/ui-audit-2026-10-23.md`: spec decisions (Day sidebar gradient card, Up next card, phone blue palette). Decide, then update either the code or the spec. | `docs/ui-audit-2026-10-23.md` | P2 | S | Each of the three has a written decision. |

---

### Package G. What is still missing and what to build next

**Goal.** Match what a clinic owner expects from clinic software, in the order that protects the clinic's money and patients.
**Why it matters to a doctor.** Missed follow-ups and unpaid dues are lost income; no export is a lock-in fear; no consent is a legal risk.
**Suits.** Dev, BE, Des; the owner decides priority.

**How I judged.** I used general knowledge of clinic and dental software and checked `lib/features` and `lib/core` by search before saying anything is missing. "Present but unfinished" means code exists. "Missing" means I found nothing; a search can miss things, so the owner should confirm with the team before building. Sizes are rough: S under 2 hours, M under a day, L days.

**What the app already has (checked by search).** Dental recalls with rules and statuses (`features/dental/records/recalls.dart`), treatment plans with estimates (`features/dental/presentation/desktop/treatment_plans_screen.dart`, "Estimate" in `dental_dialogs.dart`), dental consent (`consent_dialog.dart`), lab cases for prosthodontics, twelve staff permissions (`core/clinic/clinic_permission.dart`), a team activity log and access audit (`team/presentation/activity_log_view.dart`, `core/services/access_audit_service.dart`), a clinic switcher, invoices with refunds started (`revenue/data/models/invoice_bill.dart`), an end-of-day wrap-up card (`dashboard/presentation/widgets/wrap_up_card.dart`), email campaigns, a local-first database with cloud sync, and a prescription sheet.

#### G. Present but unfinished

| ID | Task | Where | Priority | Effort | Done when |
|---|---|---|---|---|---|
| G1 | **Automatic recalls and reminders.** Why: the biggest source of repeat revenue. Dental recalls exist, and `followUpReminderText` exists as a message the staff send by hand (`features/patients/presentation/patient_actions.dart:212`), but automatic sending before a visit or at a recall date needs a scheduled Cloud Function and a messaging vendor decision (`antigravity_workflow_gaps.md`, "Not for Antigravity"). Non-dental clinics have no recall list. | `features/dental/records/recalls.dart` (checked), `features/patients/presentation/patient_actions.dart:212` (checked), `functions/` | P1 | L | A patient due for recall receives a message without staff action; staff see "sent" and replies. Works for non-dental specialties. |
| G2 | **Partial payments, refunds, close the day.** Why: unpaid dues and cash reconciliation. Planned as M1 to M3 in `handoff/antigravity_workflow_gaps.md` (Phase 4, not done). | `features/revenue/data/models/invoice_bill.dart` (checked by search for refund), `handoff/antigravity_workflow_gaps.md` (checked: Phase 4, "Done: nothing yet") | P1 | M | Record a part payment on an invoice, refund it, and see a day summary that matches cash. |
| G3 | **CSV export and a full-data export button.** Why: owners fear lock-in, and the privacy law gives patients rights to their data. The Import / Export button is a dead end (F1); `security_plan.md` section 3.9 covers the legal side. | `features/patients/presentation/patient_actions.dart:217` (checked), `features/settings` | P1 | M | Settings has "Download my clinic data" producing patients, visits, invoices as CSV or a zip. |
| G4 | **Treatment estimate for every specialty.** Why: patients approve cost before treatment. Dental has plans and estimates; other specialties have none. A printable estimate with accept is not confirmed even for dental. | `features/dental/presentation/desktop/treatment_plans_screen.dart`, `core/pdf` | P2 | M | A doctor prints or sends an estimate and records "accepted". |
| G5 | **Consent forms outside dental.** Why: procedures in physiotherapy, radiology contrast and general clinics need consent. Dental consent and anaesthesia consent exist (`consent_dialog.dart`, `preop_dialog.dart`). The workflow brief lists generic consent as work the lead keeps. | `features/dental/records/consent_dialog.dart`, `core/pdf` | P2 | M | A generic consent template can be signed on a tablet and attached to the patient. |
| G6 | **Lab work tracking for all clinics.** Why: dental labs and diagnostic send-outs need due dates. Exists for prosthodontic cases (`features/dental/specialties/prostho/lab_cases_screen.dart`). Work orders outside prosthodontics are also on the "lead keeps" list. | `features/dental/specialties/prostho` | P2 | M | A lab order has status, due date and a reminder when overdue. |
| G7 | **Prescription tools.** Why: speed and safety. The prescription sheet exists (`scribe/presentation/prescription_generation_sheet.dart`). Not confirmed: a drug list with search, saved prescription templates ("lead keeps" list), allergy warnings against the patient's history. | `features/scribe`, `core/pdf` | P2 | L | Choosing a drug suggests dose and frequency; a known allergy shows a warning. |
| G8 | **Audit trail of changes.** Why: disputes and compliance. Present: access log and activity log. Not confirmed: who edited or deleted a clinical or money record, and when. | `core/services/access_audit_service.dart`, `features/team/presentation/activity_log_view.dart` | P2 | M | Opening a record shows its edit history; deletes are listed. |
| G9 | **Owner reports.** Why: owners judge the clinic by monthly numbers. `reports` today means certificates and medical reports only (2 files); revenue has an overview and the team has analytics. Missing: one monthly pack (collections, pending dues by patient, new patients, no-show rate, income per doctor, stock value) as PDF and spreadsheet. | `features/reports`, `features/revenue`, `features/team/presentation/team_analytics_view.dart` | P2 | M | The owner downloads a monthly report that matches the revenue screen. |
| G10 | **Visible offline and sync status.** Why: local-first is a selling point, but a doctor needs to see "saved on this device, not yet synced". Not confirmed whether such a status is shown. | `core/services/firestore_sync_service.dart`, `features/shell` | P2 | S | A small indicator shows offline, syncing and synced; a QA test with the network off shows saves are kept. |
| G11 | **Languages.** Why: patient-facing messages and documents in Hindi or Marathi. There is no localisation: `intl` is a dependency but there is no `flutter_localizations`, no `.arb`, and about 358 literal `Text('...')` in features. Start with patient-facing messages and printed documents, not the whole UI. | `features/messaging/data/services/whatsapp_template_service.dart`, `core/pdf` | P2 | L | A clinic can send the appointment reminder and print the invoice in Hindi or Marathi. |
| G12 | **Multi-branch owner view.** Why: a clinic with two locations. A clinic switcher exists (`features/shell/components/cru_sidebar.dart`); a combined view across branches and branch-wise reports were not found. | `core/clinic`, `features/shell` | P3 | L | The owner sees combined and per-branch revenue. |

#### G. Missing

| ID | Task | Where | Priority | Effort | Done when |
|---|---|---|---|---|---|
| G20 | **Instalment or payment plan for long treatments.** Why: dental, ortho and physio packages are paid over months. Search found no "instalment" or "payment plan". (Patients have a "Package balance" box; check how it is used before replacing it.) | `features/revenue`, `features/patients` | P2 | M | A treatment of 30,000 rupees can be split into dated instalments with reminders. |
| G21 | **Insurance and TPA claims.** Why: some clinics bill insurers. "Insurance" appears only as a payment mode in the transaction dialog. | `features/revenue/presentation/desktop_add_transaction_dialog.dart` | P3 | L | A claim has status, amount, rejection note. |
| G22 | **Patient-facing booking link or portal.** Why: fewer phone calls, 24-hour booking. Nothing found. The AI receptionist plan covers phone calls (`docs/ai_receptionist_final_plan.md`). | `functions/`, new folder | P3 | L | A patient books a slot from a link; staff approve. |
| G23 | **Patient merge and archive.** Why: duplicate patients are certain. Archive/restore (P5) and merge are on the "later" and "lead keeps" lists. | `features/patients` | P2 | M | Two patient records merge with visits, files and invoices kept. |
| G24 | **Waiting-room display board and "items used on a visit".** Why: reception polish; stock accuracy. Listed as F1 and F2 in the workflow brief "LATER". | `features/queue`, `features/inventory` | P3 | M | A second screen shows "Now serving / Next"; a visit records stock used. |
| G25 | **Stock alerts for expiry and low stock.** Why: expired medicines are a safety and cost issue. Expiry date and low-stock colours exist in the item dialog; a daily alert is not confirmed. | `features/inventory` | P2 | S | The owner gets a daily list of items expiring in 30 days or below the alert level. |
| G26 | **No-show tracking and waiting list.** Why: empty slots cost money. Not confirmed anywhere. | `features/appointments` | P3 | M | A missed visit is marked, and a cancelled slot offers the next waiting patient. |

---

### Package H. Testing and release quality

**Goal.** Nothing reaches a clinic that a tester has not opened on a real device.
**Why it matters to a doctor.** Software bugs happen in front of a patient.
**Suits.** QA, Dev.

**The checklist a tester runs on every screen before it is called done**

1. Opens without errors in the log; loading state shows a skeleton, then content.
2. Empty state: one sentence and one action. Error state: plain words and Try again (turn the network off to see it).
3. Keyboard: Tab and Enter work (A-standard); Escape closes dialogs; focus ring visible.
4. Phone 360 by 800, tablet 820 by 1180 (portrait and landscape), desktop 1366 by 768: nothing clipped, no horizontal page scroll, text at 130 percent.
5. Touch targets at least 44 dp; nothing needs hover.
6. Day and Evening themes both look right; no hard-coded colour.
7. Same words as the copy guide (C1); no English-only typos.
8. Save, edit, delete and undo each work and show one clear message.
9. Works offline (save, then reconnect) where the feature is meant to; no personal data in the log.
10. Screen reader labels on icon-only buttons.
11. Close the screen: no timer or listener keeps running (debug log).
12. A second user (receptionist role) sees only what the role permits.

**Features with no tests (checked: no test file refers to the feature folder).** `auth`, `profile`, `reports`, `tasks`, `therapy`, `todos`, `update`. Thin (1 to 4 files): `campaigns` 1, `scan` 2, `onboarding` 2, `subscription` 3, `support` 3, `tutorial` 3, `mobile` 4. There are 122 test files in `test/` plus a few under `integration_test/`; the test names suggest dental, patients, appointments, dashboard, queue, radiology and revenue are covered best.

**Manual passes still pending, according to the documents.**
- Two-account test on phone and PC, including a receptionist account, for clinic file sharing: `docs/clinic_lan_file_sharing_plan.md:361`.
- Clinic team login: "not yet run on a device": `handoff/antigravity_clinic_team.md:135`.
- Documents and PDF templates: list for the owner to try on the phone and PC: `handoff/antigravity_documents_pdf.md:2262`.
- Workflow gaps: GATE 1 (after Phase 1) and GATE 2 (after Phase 4): `handoff/antigravity_workflow_gaps.md`.
- Dental 3D viewer: gates waiting for owner phone and PC checks: `handoff/antigravity_dental3d.md`.
- AI receptionist pilot and gate 1: `docs/ai_receptionist_final_plan.md`.
- Apple builds on a Mac, signing and TestFlight: `docs/apple_store_readiness_audit.md`.
- From the owner's own project notes (not confirmed in a document in the repo): phone tests for the CruDoc ID and referrers features, patient-details clean-up, progressive file viewing, the PACS simulator link and the scan quick action.

#### H. Tasks

| ID | Task | Where | Priority | Effort | Done when |
|---|---|---|---|---|---|
| H1 | Put the 12-point screen checklist above into the pull-request template and ask the reviewer to tick it. | process task (no code to check): `.github/` or `docs/` | P1 | S | Every PR shows the checklist. |
| H2 | Device test matrix: one Android phone (360 by 800), one iPad or Android tablet, one Windows laptop (1366 by 768), plus text size 130 percent and Evening theme. Run the checklist on the top 15 screens and file the results as tasks. | process task (no code to check): QA sheet | P1 | M | A filled QA sheet with screenshots for 15 screens. |
| H3 | Add tests for sign-in (`auth`): phone OTP flow, wrong code, Enter key. Zero tests today. | `test/` (new), `features/auth` (checked: no test file refers to it) | P1 | M | Tests pass in CI and fail if the sign-in screen breaks. |
| H4 | Add tests for money and send paths with thin coverage: subscription checkout (3 refs), campaign dispatch (1 ref), scan bill to inventory (2 refs). | `test/` (checked: 3, 1 and 2 test files refer to subscription, campaigns and scan) | P1 | M | Each path has at least a happy-path and a failure test. |
| H5 | Smoke tests for the other untested features: `update` (version compare, checksum), `todos`, `tasks`, `reports` (certificate text), `profile` (name change policy), `therapy`. | `test/` | P2 | M | One test file per feature. |
| H6 | Windows keyboard integration test for the form standard (Enter next, Enter saves the last box, Ctrl+Enter) using the existing `integration_test/` folder. Run after A1 and A2. | `integration_test/` | P2 | M | The test passes on a Windows machine. |
| H7 | Golden tests for the new shared widgets (`CruSkeleton`, `CruEmptyState`, `CruErrorState`, `CruFormMore`, `CruFilterChip`) in Day and Evening. Goldens already exist (`test/goldens`, appointments). | `test/goldens` | P2 | S | Goldens committed and passing. |
| H8 | Forced-failure test pass for B2 to B9: simulate each failure and confirm no exception text appears. | QA sheet (checked: the 13 sites are the rows B2 to B7) | P1 | S | A list of the 13 sites, each marked pass. |
| H9 | Release checklist: no emulator flags, demo login off, test payments off (F8, F10), `RAD_PROGRESSIVE` decision (F9), version and update manifest, installer, store steps (Apple audit). | `docs/` (new) | P2 | S | A one-page list signed before each release. |
| H10 | Check whether CI runs `flutter analyze` and the tests on every push. Not confirmed from the files I read. | CI settings | P2 | S | A green check is required before merge. |
| H11 | Finish the pending manual passes listed above; each gets a dated result in the matching document. | documents above (checked: lines cited in the list) | P1 | M | Each document has "tested on <date> on <device>". |
| H12 | Accessibility check: screen reader labels (837 `semanticLabel` / `Semantics` uses exist; check icon-only buttons), contrast of grey text in Evening, text size 130 percent. | QA sheet | P2 | M | A list of failures filed as tasks. |

---

## 4. Quick wins

The 25 highest-value tasks under 2 hours (effort S). Do these in the first week.

| Rank | ID | What | Why |
|---|---|---|---|
| 1 | A2 | Test Enter-to-next on Windows and phone | Decides how much of A1 is needed |
| 2 | B1 | Friendly-error helper | Unlocks B2 to B7 |
| 3 | B2 | Dashboard raw errors | Seen on the home screen |
| 4 | B3 | Phone raw errors | Seen on the phone every day |
| 5 | B4 | Files raw errors | Seen in sending files |
| 6 | B5 | Voice overlay message | Microphone problems are common |
| 7 | B6 | Case sheet save failure text | Doctors lose trust if a save fails with code text |
| 8 | B7 | PDF editor errors | Same |
| 9 | C1 | Copy guide and verb pass | Cheap and visible |
| 10 | F2 | Inventory "Add Item" dead button | Fix or hide in minutes |
| 11 | A8 | Save errors in the form's notice line | Cheap; avoids pop-ups |
| 12 | F4 | Tip rows with no action | Removes fake buttons |
| 13 | F7 | Android update text and one real test | Confirms updates work |
| 14 | E1 | Limit the visits listener by date | Speed for every long-time clinic |
| 15 | A3 | "More details" expander | Prerequisite for 10 form tasks |
| 16 | A6 | Focus the first box | Saves a click on every form |
| 17 | A9 | Money box widget | Prevents bad amounts |
| 18 | A10 | Age and date of birth in one box | Nothing asked twice |
| 19 | C4 | Sidebar colours and icons | Seen on every screen |
| 20 | C5 | Filter chip widget | Fixes 77 raw chips |
| 21 | D4 | Hover audit | Quick safety check for touch |
| 22 | D7 | 130 percent text check | Finds clipped text fast |
| 23 | E5 | Batch per-row deletes | Faster sync |
| 24 | H1 | Checklist in the PR template | Prevents repeat problems |
| 25 | H8 | Forced-failure pass | Proves B2 to B9 work |

---

## 5. Suggested order of work for a small team (four weeks)

Assume four people: two Flutter developers (Dev 1, Dev 2), one designer/Flutter person (Des), one tester (QA). Backend help is needed for G1 only.

**Week 1: foundations that make everything else smaller.**
- Dev 1: A1, A2, A3, A6 (the form scope), then A20, A21 (patients forms).
- Dev 2: B1 to B7 (error text), B10 (shared skeleton, empty, error widgets).
- Des: C1 (copy guide), motion token table B11 (design only), F18 (spec decisions), tablet layout design for D1.
- QA: H1, H2 (device matrix), start D2 (the 17 desktop screens at phone width); repeat A2 on Windows.

**Week 2: the worst forms and dead ends.**
- Dev 1: A23 (invoice), A27 (medicine), A49 (schedule visit), A31 then A30 (homeopathy).
- Dev 2: F1 (CSV), F2, F3, F4, F7, E1, E2 (measure first).
- Des: C5, C6 (chip and menu widgets), C4, B13 sheet helper.
- QA: H8, H3, forced-failure passes, report D2 results.

**Week 3: dental and scribe forms, tablet tier, state widgets in screens.**
- Dev 1: A33, A34, A35, A45, A7 (one dialog shell).
- Dev 2: D1 (tablet tier), D20 start, B20 to B32 (screens get skeletons, empty and error states first; animations after).
- Des: C2, C3 (colour tokens, phone palette), C7 (shared duplicates).
- QA: D3, D7, D8; H4, H5; Evening theme sweep.

**Week 4: polish, speed, hygiene.**
- Dev 1: E3, E4, E6, E8, E9; F14 (repo clean-up); start F13 splits on files being touched.
- Dev 2: A47 (one campaign composer), G2 (partial payments and refund brief), G3 (export).
- Des: B12 route transition, C8 type scale, remaining per-feature animation tasks.
- QA: H6, H7, H11 (pending manual passes), regression of the full checklist on the top 15 screens.

**What can run in parallel.** Package C (design tokens and widgets), package E (speed) and package F (clean-up) do not touch the same files as A and B until week 3, so they run beside them. Do A1/A3 before the per-form tasks, B1/B10 before the per-screen state tasks, D1 before any tablet screen work. G1 (recalls and reminders) needs a messaging vendor decision from the owner and a backend person; start that decision in week 1 so G1 can begin after week 4.

---

## 6. What this audit did not cover or could not confirm

- **Nobody ran the app.** Everything is a reading of the code on 12 Nov 2026, on `main` at commit `e851370`. Visual problems, real speed and keyboard behaviour on Windows were not observed. Task A2, D2, E2 and H2 exist to find out.
- **The inventories were grep-based.** Counts are estimates. When I re-counted, several differed (Appendix B). Where I did not re-count, the number comes from the inventory.
- **What I opened.** I opened the code for 97 of the 226 task rows (43 percent): 37 of the 39 P1 rows (the other 2, H1 and H2, are process tasks with no code), and 60 of the 187 P2 and P3 rows (32 percent). I also re-counted about 30 headline numbers. Every P1 row was opened. Rows without "(checked)" come from the inventories and may be wrong; the first thing the owner of such a task should do is open the file.
- **Several inventory findings were wrong** and were dropped (Appendix B). That is a warning about the unchecked P2 and P3 rows: expect a few more false alarms.
- **Not read in detail.** Form behaviour for dental clinical forms, PACS dialogs, scan pages and others: I read the box labels only. Whether a box is already pre-filled was not confirmed; the form proposals say "check first".
- **Not audited.** Cloud Functions code (only one file for the mock-payment guard), Firestore rules, the Super Admin app (`CrudocSuper-admin`), the separate side projects (`voice-receptionist`, `imaging-service`, `cbct_viewer`, `dental3d`), iOS and macOS project files, installer scripts.
- **Security, compliance and App Store work** are covered in `docs/security_plan.md` and `docs/apple_store_readiness_audit.md` and were not redone.
- **Accessibility** (screen reader, contrast) was not tested; H12 covers it.
- **The "missing feature" list in package G is judgement,** based on general knowledge of clinic software and searches of the code. The owner should confirm each with the team before building.
- **Branch note.** The main folder was on `main` when I read it. The dental fixes made by the earlier workers (uncommitted work in a separate copy, saved as `CruDoc/dental3d/tmp/wt_uncommitted_2026-11-12.patch`) were not reviewed; findings about dental files describe `main`.

---

## Appendix A. Feature coverage index

Every folder under `CruDoc/lib/features` and where to find its tasks. (`core/` and `crudoc_shared` are covered in the central-fix tables.)

| Feature | Forms | States and motion | Design | Phone and tablet | Speed | Unfinished | Missing features | Tests |
|---|---|---|---|---|---|---|---|---|
| appointments | A49, A50 | B20, B3 | C20 | D32, D1 | E1, E9 | F13 | G26 | H2 |
| auth | A64 | B21 | C36 | D34 | E32 | F10 | none | H3 |
| campaigns | A47, A48 | B22, B16 | C21 | D24 | E30 | F3 | G22 | H4 |
| dashboard | A60 | B2, B23 | C36 | D34 | E32 | none | G9 | H2 |
| dental | A33 to A41 | B24 | C22 | D20, D21 | E22 | F6 | G4, G5, G6 | H2 |
| files | A52 | B4, B25 | C23 | D28 | E26 | none | none | H11 |
| homeopathy | A30 to A32 | B6, B26 | A30 | D30 | E23 | F13 | none | H5 |
| inventory | A27 to A29 | B27 | C24 | D25 | E31 | F2, F5 | G25 | H2 |
| messaging | none (data only) | B9 | none | none | E30 | F17 | G1, G11 | none |
| mobile | A11 | B3, B28 | C3, C25 | D6, D7, D8 | E24 | F4 | none | H2 |
| onboarding | A61 | B29 | C34 | D34 | E32 | none | none | H5 |
| patients | A20 to A22 | B30 | C27 | D34 | E7 | F1 | G3, G23 | H2 |
| profile | none | none | C36 | none | E32 | F17 | none | H5 |
| queue | A51 | B31 | C36 | D26 | E25 | none | G24 | H2 |
| radiology | A42 to A44 | B32 | C26 | D23 | E20, E21 | F9 | none | H2 |
| reports | A57 | B33 | C36 | D30 | E32 | none | G9 | H5 |
| revenue | A23 to A26 | B34 | C29 | D34 | E6, E31 | none | G2, G20, G21 | H2 |
| scan | A59 | B35 | C33 | D34 | E28 | none | none | H4 |
| scribe | A45, A46 | B36 | C36 | D27 | E29 | none | G7 | H2 |
| settings | A53 to A55 | B37 | C28 | D29 | E32 | none | G3 | H2 |
| shell | none | B38 | C4 | D1 | E32 | none | G10, G12 | H2 |
| subscription | none | B39 | C30 | D34 | E30 | F8 | none | H4 |
| support | A62 | B40 | C36 | D34 | E30 | none | none | H5 |
| tasks | none | B41 | C36 | D34 | E32 | F17 | none | H5 |
| team | A58 | B42 | C36 | D31 | E10, E30 | none | G8 | H2 |
| therapy | A63 | B43 | C32 | D30 | E27 | none | none | H5 |
| todos | A56 | B44 | C36 | D34 | E30 | none | none | H5 |
| tutorial | none | B45 | C36 | D34 | E32 | none | none | H2 |
| update | none | B46 | C31 | D33 | E32 | F7 | none | H5 |
| voice | none | B5, B47 | C35 | D1 | E32 | F13 | none | H2 |

## Appendix B. Where this report corrects the inventories

Read these before acting on the raw files in `raw/`.

| Inventory claim | What the code shows |
|---|---|
| `files_actions.dart:53,139,307`: errors only `debugPrint`, user sees nothing | Each shows a message (`say(...)` or a floating notice). Not a defect. |
| Radiology sync reads (`rad_view_pixels.dart:67`, `radiology_providers.dart:411`, `thumbnail_strip.dart:21`) block the UI | They are inside `Isolate.run` or an isolate helper. Not on the UI thread. |
| `Inter.zip` (20 MB) and `bonebox_teeth` (227 MB) bloat the app | Not listed in `pubspec.yaml`. `bonebox_teeth` is git-ignored; `Inter.zip` is only repository weight. Shipped assets total about 17 MB. |
| Android in-app update "not implemented" | `MainActivity.kt:30-36` handles `installApk`. Only the fallback error text is stale (F7). |
| Mock checkout runs in the shipping UI | The server enables it only with `PLAN_PAYMENTS_MOCK=true` on an allow-listed project (`plan-payments.ts:119-123`). Kept as P3 (F8). |
| Dead filter buttons in `desktop_campaigns_screen.dart:288`, `worklist_screen.dart:342`, `lab_cases_screen.dart:210` | Visual anchors inside a working `PopupMenuButton`. Not dead. |
| Appointment `onTap: () {}` at `appointments_agenda_view.dart:147` and the week/day grids | The agenda one is a morph-transition copy of a row. Not confirmed dead; left out. |
| messaging and profile have no loading, empty or error states | They have no screens (data layer only). |
| Fixed dialog widths (960, 920, 660 ...) break phones | Dialog widths are `maxWidth` in both `CruFormDialog` (`cru_form.dart:117`) and `DentalPanelDialog` (`dental_ui.dart:963`). Only the fixed heights and the template editor need work (D21, D22). |
| Tooth detail view is hover-only | It also handles `onTapUp` (`tooth_detail_view.dart:1410-1415`). |
| `activity_log_view.dart:60` has no limit | It has `.limit(_limit)`. |
| `whatsapp_repository.dart` and `files_repository.dart:668` have unbounded snapshots | Both watch a single document. |
| Queue, inventory, scribe, files, settings, campaigns have no phone screen | `mobile_more.dart:93-112` opens these desktop screens inside the phone shell. The open question is whether they fit (D2). Only dental charting is truly desktop-only. |
| Keyboard shortcut help overlay missing | "Help and shortcuts rebuilt" is marked done in `docs/ui-audit-2026-10-23.md`. Dropped. |
| `CruSheet` and `showCru*` exist in shared widgets | There are 0 references. They must be built (B13). |
| 537 Cru constructions in 100 files | `CruTextField(` is 243 constructions in 68 files; other Cru field types are extra. |
| 28 `showModalBottomSheet`, 55 image constructions, 35 files over 1,000 lines, 388 bonebox files, 23 `Timer.periodic` | I counted 32, 38, 53 (20 over 1,500), 36, 20. |
| `SwitchListTile` in settings AI assistance and call forwarding | None found in `features/settings` (4 in the rest of `lib`). |
| `AppColors` is gone from the app (`ui-audit-2026-10-23.md`) | Still used by the update feature (3 files, 30 uses): `update_available_dialog.dart:55`, `update_banner.dart`, `update_progress_sheet.dart` (C31). |
| Scan camera page swaps a full image every frame (`document_camera_page.dart:818`) | It is a 40 px page thumbnail. Not a problem. |
| WhatsApp campaign channel is an error path | The composer shows it with an explanatory hint (`post_campaign_modal.dart:1065`); whether it can be selected is not confirmed (F3). |
| No Cru toast helper, so every SnackBar has its own style | The toast look comes from the theme and one island notice (`showIsland`, 141 calls in 65 files); the real gap is message content and the many helper names (B1, B14). |

## Reference check

Checked on 12 Nov 2026 against the code in `CruDoc/lib` and `crudoc_shared/lib`. Every row in packages A to F that cites a file (133 of 195 rows; the rest cite only folders, grep commands or processes) was checked for the file's existence. Where a line number is given, the code 5 lines either side was read: all 30 P1 rows in A to F and 62 other rows, 92 in total.

- Rows checked (file reference): 133
- Rows where the file reference was right: 126
- Rows wrong: 7
- Wrong P1 rows: A21 and D1

| Task ID | What is wrong | Corrected path or line |
|---|---|---|
| A21 (P1) | Line 420 is a `CruTextField` wrapper, not a raw field. The raw `TextFormField` is at line 452. | `features/patients/presentation/patient_form.dart:452` (drop 420) |
| D1 (P1) | `voice_overlay.dart:286` already uses the shared `kDesktopBreakpoint`, not a literal `< 900`, so there is nothing to replace there. The `shortestSide >= 600` in `cbct_device.dart:18` is correct. | `features/voice/presentation/voice_overlay.dart:286` (already shared; remove from D1 scope) |
| A22 (P3) | Wrong folders. The search box is in `widgets/list/`; the dialogs file is in `widgets/`. | `features/patients/presentation/widgets/list/patients_search_bar.dart`; `features/patients/presentation/widgets/patient_dialogs.dart` |
| A29 (P3) | Wrong folder for the search field. | `features/inventory/presentation/widgets/inventory_search_field.dart` |
| A60 (P3) | Wrong folder for the search field. | `features/dashboard/presentation/widgets/dashboard_search_field.dart` |
| A36 (P2) | The row says Name, Date of birth and Gender are "not confirmed" as coming from the patient. Name and Date of birth already come from the patient at lines 479 to 482 (`patient.fullName`, `patient.dateOfBirth`). Gender was not checked. | `features/dental/records/consent_dialog.dart:479-482` |
| D3 (P2) | `CruIconButton` is not in `cru_extras.dart`. It is defined in `cru_button.dart`. | `crudoc_shared/lib/widgets/cru/cru_button.dart:279` |

Not checked: counts and claims that have no file or line (for example "17 screens", "54 setState calls", "0 uses of onSubmitted"), and the content of rows whose file was found but whose cited line was not read.
