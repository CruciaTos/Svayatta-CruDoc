# Forms and data entry audit (partial, sampled)

Coverage: counts are grep counts across lib/. Per-screen detail is sampled (about 12 forms read), not exhaustive. Read-only pass; no files changed.

## Summary
1. Shared field is `CruTextField` (crudoc_shared/lib/widgets/cru/cru_form.dart:535). Its default `textInputAction` is `next` (line 756-760), but it has no default `onSubmitted`, so Enter-to-next depends on each caller.
2. Plain Enter does not submit any form centrally. `CruFormDialog` (cru_form.dart:28-105) only binds Ctrl+Enter and Ctrl+S to `onSubmit`.
3. Raw Material `TextField`/`TextFormField` constructions: 54 occurrences in 33 files, bypassing the shared field.
4. Homeopathy case-taking sheet has 0 `textInputAction`/`onSubmitted` uses and about 150 field-like call sites in one file.
5. Only about 65 files use `textInputAction`/`onSubmitted`/`onFieldSubmitted`/`FocusNode`; about 100 files have Cru or raw field constructions.

## Per-feature table
| feature | forms sampled | inputs (approx) | Enter-to-next | Enter-submits-last | notes |
|---|---|---|---|---|---|
| patients | desktop_add_edit_patient_dialog | 7 + picker + tags | no explicit | no (Ctrl+S only) | First/last name validators, age, phone, email; good keyboard types |
| revenue | desktop_create_invoice_dialog | 16+ | partial (2 explicit done+submit) | yes for add-treatment/medicine rows only | 6 sections, dense; line-item adder duplicates |
| inventory | desktop_add_edit_medicine_dialog | 13 | no explicit | no | 4 sections; count and price fields |
| auth | phone_auth_sheet | 2 | yes (done + onSubmitted) | yes (send / verify) | Best-practice example in repo |
| homeopathy | homeopathy_case_taking_sheet | about 150 hits, 40+ fields | none | none | _buildTextField at line 2741 wraps HomeopathyFormField; long, voice-enabled |
| dental | endo_dialog, preop_dialog, consent_dialog, referral_dialogs, clinic_details (settings) | 14, 13, 7, 16, 14 | not checked | not checked | Not read in detail |
| radiology | pacs_dialogs, radiology_dialogs, report_editor_screen | 16, 4, 8 | not checked | not checked | Report editor uses raw TextField (2 spots) |
| scribe | prescription_generation_sheet | 14 (5 raw) | not checked | not checked | Mixes raw and Cru fields |
| inventory bill | desktop_bill_review_dialog | 8 | not checked | not checked | |
| campaigns | post_campaign_modal, mobile_post_campaign_sheet | 5 + 5 raw each | not checked | not checked | Duplicate desktop/mobile forms |
| appointments | desktop_schedule_visit_dialog, schedule_visit_sheet | 8, 3 | not checked | not checked | Desktop and mobile duplicates |
| files | files_dialogs, compose_transfer_dialog | 3, 2 | not checked | not checked | |
| settings | my_details_tab, clinic_details_tab, templates_tab | 8, 14, 5 | not checked | not checked | |
| queue | check_in_dialog | 4 (1 raw) | not checked | not checked | Small, quick win candidate |
| todos | todo_dialog | 4 | not checked | not checked | |
| shell/dashboard | dashboard_search_field, desktop_shell | 6, 9 | search fields | n/a | |
| reports | certificate_dialog, medical_report_generation_sheet | 5, 1 | not checked | not checked | |
| team | invite_sheet, role_editor_sheet | 2, 1 | not checked | not checked | |
| scan | scan_bill_page, scan_record_page, scan_note_page | 8, 3, 2 | not checked | not checked | |
| onboarding | onboarding_flow, doctor_loyalty_card | 2, 1 | not checked | not checked | |
| support | feedback_dialog | 1 | not checked | not checked | |
| therapy | physio_photos_dialog | 2 | not checked | not checked | |
| tutorial, voice, mobile, subscription, update, tasks, messaging, campaigns, scribe | no or few inputs found in grep | n/a | n/a | n/a | Not read; grep shows only a handful of hits |

Empty folders: none confirmed empty. Not checked for lib/features/subscription, lib/features/update, lib/features/tasks, lib/features/messaging (no field hits in the initial grep).

## Detailed findings
| feature | file:line | what | suggested change | priority | effort |
|---|---|---|---|---|---|
| shared | crudoc_shared/lib/widgets/cru/cru_form.dart:535-609 | `CruTextField` has no default `onSubmitted`; Enter/Next behaviour is per call site (only ~67 call sites pass onSubmitted/textInputAction) | Add a `CruFormScope` (FocusTraversalGroup + `onSubmitted` default that calls `nextFocus()`; last field calls the form submit). Plain Enter = next, Ctrl+Enter = save. Fixes every field at once | P1 | M |
| shared | crudoc_shared/lib/widgets/cru/cru_form.dart:28-105 | `CruFormDialog` binds only Ctrl+Enter / Ctrl+S to submit; plain Enter on the last field does nothing | Wrap in the scope above; last field submits on Enter when no multiline | P1 | S |
| shared | cru_form.dart:746-772 | `TextInputAction.next` is set but on desktop the Enter key may not trigger it (needs verification on Windows) | Test on Windows desktop; if not moving focus, use a `Shortcuts`/`Actions` mapping for Enter to `NextFocusIntent` | P1 | S |
| shared | cru_form.dart:1295-1304 | `CruTagField` submits on onSubmitted only | Keep; confirm Enter adds tag and moves on | P2 | S |
| homeopathy | homeopathy_case_taking_sheet.dart:2741 | `_buildTextField` wraps `HomeopathyFormField`, which is not a Cru field; 0 next/submit handling; 40+ labels (Chief problem, Location, Sensation, Onset, Duration, Frequency, etc.) in one scroll | Switch to `CruTextField` via the helper; group into collapsible sections; Enter moves to next; split the sheet into 3-4 steps | P1 | L |
| homeopathy | homeopathy_form_helpers.dart:102 | `HomeopathyFormField` uses raw `TextField` and has voice button | Make it wrap `CruTextField` with a `trailing` voice button | P1 | M |
| homeopathy | homeopathy_patient_details_screen.dart | 1 raw TextField | Replace with Cru field | P2 | S |
| patients | desktop_add_edit_patient_dialog.dart:648-822 | 7 fields plus picker and tags; no explicit next; last field `done`+`_save` (line 821-822) is good; other fields rely on default | Apply shared scope; split optional fields (email, address, referrer) behind "More details" | P1 | S |
| patients | patient_dialogs.dart (9 CruTextField, 1 raw) | Raw TextField at one spot | Replace with Cru | P2 | S |
| patients | patient_form.dart | 2 Cru, 1 raw | Replace raw field | P2 | S |
| patients | patients_search_bar.dart, patients_screen.dart | search boxes; raw in search bar | Standardise search field component | P2 | S |
| revenue | desktop_create_invoice_dialog.dart:846-953 | 16+ inputs across 6 sections (Patient, Billing, Items, Notes); two pickers and a line-item adder | Auto-fill: patient-to-billing defaults, derive invoice number and due date; collapse Notes; each line item row Enter moves to next row | P1 | M |
| revenue | desktop_create_invoice_dialog.dart:1152-1182, 1221-1256 | Treatment and medicine adders duplicate the same 4-field pattern | Extract one `_LineItemAdder` widget | P2 | S |
| revenue | desktop_create_invoice_dialog.dart:1585-1668 | Private field widget with `textInputAction` default `next`; duplicate of shared Cru field | Delete and use `CruTextField` | P2 | S |
| revenue | desktop_create_invoice_dialog.dart (1 raw TextField) | Raw field | Replace | P2 | S |
| revenue | desktop_add_transaction_dialog.dart (7 Cru, 1 raw) | Raw field | Replace; check amount formatter | P2 | S |
| revenue | desktop_invoices_screen.dart (search raw) | search field | Standardise | P3 | S |
| inventory | desktop_add_edit_medicine_dialog.dart:590-729 | 13 inputs in 4 sections; 3 count fields use `digitsOnly`; no textInputAction | Derive expiry from batch; drop separate 'unit' if default; Enter next | P1 | M |
| inventory | desktop_bill_review_dialog.dart (8 Cru) | review table of editable rows; no next-row Enter | Row-level Enter moves to next row | P2 | M |
| inventory | stock_adjustment_dialog.dart (3 Cru, 2 onSubmit) | Good partial: already submits | Use shared scope | P3 | S |
| inventory | inventory_search_field.dart, inventory_toolbar.dart | raw search field | Standardise | P3 | S |
| auth | phone_auth_sheet.dart:263-295 | Phone and OTP fields with done/onSubmitted | Reference pattern; reuse | P3 | S |
| auth | auth_screen.dart (3 Cru, 2 raw-ish onSubmit) | Mixed | Check login Enter flow | P2 | S |
| dental | endo_dialog.dart (14 Cru) | Many clinical fields in one dialog | Split into steps; Enter next | P1 | M |
| dental | preop_dialog.dart (13 Cru) | Anaesthesia pre-op 13 inputs | Split; some values derivable (age from DOB, weight-based doses) | P1 | M |
| dental | referral_dialogs.dart (16 Cru) | Referral; probably name/phone duplicated from patient | Pre-fill from patient, drop duplicates | P1 | M |
| dental | clinical_forms.dart, consent_dialog.dart (7), recalls.dart (9), perio_staging.dart (6), srp_dialog.dart | Clinical forms | Standardise; not individually read | P2 | M |
| dental | dental_dialogs.dart (16 Cru) | Mixed dialogs | Not read in detail | P2 | M |
| dental | specialties/forms/form_builder.dart (5 Cru, 3 raw) | Form builder itself uses raw fields | Use Cru field for builder and fill form | P2 | M |
| dental | dental_inventory_screen.dart (7 raw) | Raw fields | Replace | P2 | S |
| dental | charting_page.dart (7 Cru, 1 raw) | Chart search/notes | Replace raw | P2 | S |
| dental | drug_log.dart (5 Cru, 1 raw) | Drug log | Replace raw; amounts formatter | P2 | S |
| radiology | pacs_dialogs.dart (16 Cru) | PACS server config: host, port, AE title, etc. | Group under "Advanced"; defaults | P2 | M |
| radiology | report_editor_screen.dart (8 Cru, 2 raw) | Report editor | Replace raw; keep Enter in multiline | P1 | M |
| radiology | radiology_dialogs.dart (raw 1), side_panel.dart (raw 1), report_kit.dart (raw 1) | Raw fields | Replace | P2 | S |
| radiology | template_manager.dart (6 Cru) | Template editor | Enter next | P3 | S |
| scribe | prescription_generation_sheet.dart (14 Cru, 5 raw) | Prescription lines (dose, freq, duration) | Preset dose/frequency pickers; derive duration from quantity | P1 | M |
| scribe | session_note_screen.dart (2 Cru) | Multiline notes | Keep newline | P3 | S |
| campaigns | post_campaign_modal.dart (5 raw) and mobile_post_campaign_sheet.dart (5 raw) | Duplicate desktop and mobile forms, all raw | Single form widget with responsive layout | P1 | M |
| campaigns | campaign_analytics_dialog.dart (1 raw) | Date range | Use shared date picker | P3 | S |
| appointments | desktop_schedule_visit_dialog.dart (8 Cru) and schedule_visit_sheet.dart (3 Cru) | Duplicate desktop/mobile schedule forms | Merge; derive end time from duration | P1 | M |
| appointments | patient_picker_dialog.dart, session_details_sheet.dart, desktop_session_details_dialog.dart (raw 1 each) | Raw search fields | Replace | P2 | S |
| appointments | appointment_actions.dart (1 Cru, 2 onSubmit) | Quick action | OK | P3 | S |
| queue | check_in_dialog.dart (4 Cru, 1 raw) | Check-in: name, phone, reason | Small; auto-fill from patient; Enter next | P2 | S |
| files | files_dialogs.dart (3 Cru, 2 onSubmit), compose_transfer_dialog.dart (2 Cru) | Mixed | Replace raw in files_bars.dart | P2 | S |
| settings | clinic_details_tab.dart (14 Cru), my_details_tab.dart (8 Cru) | Clinic and doctor profile, many fields | Group, derive address parts, Enter next | P1 | M |
| settings | templates_tab.dart (5 Cru, 4 onSubmit) | Mixed | OK | P3 | S |
| settings | delete_account_dialog.dart (2 Cru) | Confirm text | Keep | P3 | S |
| todos | todo_dialog.dart (4 Cru) | Title, due, priority | Enter submits title | P2 | S |
| reports | certificate_dialog.dart (5 Cru), medical_report_generation_sheet.dart (raw 1) | Certificate fields (patient details duplicated) | Pre-fill from patient | P2 | S |
| team | invite_sheet.dart (2 Cru), role_editor_sheet.dart | Invite by phone | Enter submits | P3 | S |
| scan | scan_bill_page.dart (8 Cru), scan_record_page.dart (3), scan_note_page.dart (2) | Post-scan confirmation forms | Enter next; derivable fields from OCR | P2 | M |
| dashboard | dashboard_search_field.dart (6 Cru incl. raw 1), dashboard_header.dart (4) | Search | Standardise | P3 | S |
| onboarding | onboarding_flow.dart (2 Cru), doctor_loyalty_card.dart (1 Cru, 1 raw) | Onboarding inputs | Enter next; keep short | P2 | S |
| support | feedback_dialog.dart (1 Cru, 1 raw) | Feedback | Replace raw | P3 | S |
| therapy | physio_photos_dialog.dart (2 Cru) | Photo notes | OK | P3 | S |
| tutorial | tutorial_overlay.dart (4 hits) | Not a form; quick scan only | Ignore | P3 | S |

## Central fix (one change, many screens)
- Add `CruFormScope` in crudoc_shared cru_form.dart: a `FocusTraversalGroup` plus `Shortcuts` mapping Enter to `NextFocusIntent`, and a default `onSubmitted` in `CruTextField` that calls `FocusScope.of(context).nextFocus()` unless `multiline` or it is the last field, in which case it calls the scope's submit callback. Wire `CruFormDialog.onSubmit` to that callback.
- Covers every CruTextField call site (about 537 Cru constructions in 100 files) with no per-screen edits.
- Raw TextField/TextFormField (54 constructions, 33 files) need a one-time swap to `CruTextField` to get the same behaviour.

## Counts
- Raw TextField/TextFormField constructions: 54 in 33 files.
- Cru field and picker constructions: about 537 in 100 files.
- Files with textInputAction/onSubmitted/FocusNode/autofocus: 65 (193 hits).
- Files with onSubmitted/onFieldSubmitted/textInputAction-next/done explicit: about 32.
- Homeopathy case-taking sheet: 150 hits, 0 explicit Enter handlers.
- Forms with more than 8 inputs (sampled): desktop_create_invoice_dialog (16), pacs_dialogs (16), referral_dialogs (16), dental_dialogs (16), endo_dialog (14), prescription_generation_sheet (14), clinic_details_tab (14), desktop_add_edit_medicine_dialog (13), preop_dialog (13), desktop_add_edit_patient_dialog (12), homeopathy_case_taking_sheet (40+ labelled fields).
