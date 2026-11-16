# CruDoc AI tool registry

The LLM never touches CruDoc directly. It sees a list of **tools** (name, description, typed inputs), picks one, and the app runs the matching Dart handler and returns a short JSON result. This file is the list and the rules.

Code: `lib/features/ai_tools/` — `core/` (types, registry, executor, agent loop) and `tools/` (one file per group).

## Rules

1. **Tools wrap existing repositories** (`patientRepositoryProvider`, `visitRepositoryProvider`, …). Never raw SQL or Firestore, so validation, encryption, sync and offline still apply.
2. **Risk levels**
   - `read` — runs at once.
   - `write` — runs, returns an `undo` so the UI can show an Undo snackbar.
   - `confirm` — the executor asks the user (confirm card) before running: money, outgoing messages, prescriptions, clinical sign-off, bulk changes, anything leaving the device.
   - **No hard-delete tools.** Cancel / archive / soft-delete only, and those are `confirm`.
3. **Permission gate** — every tool names a `ClinicPermission`. The registry only hands the model tools the signed-in role can use (`ClinicAccess.can`). The executor re-checks at run time.
4. **IDs, not names** — write tools take IDs. The model must call a `find_*` tool first; if more than one match comes back it must ask the user which.
5. **Fixed values are enums** — tooth (FDI 11–48, 51–85), surfaces, visit status, payment mode, channel, screen. Stops the model inventing values.
6. **Context slicing** — tools carry `groups`. The agent sends only the groups that fit the current screen + `core` (≈15–25 tools per request) to save tokens and cut mistakes.
7. **Small results, minimum patient data** — results return IDs, names, dates, counts. No full histories unless a `get_*` tool is asked for it.
8. **Audit** — every executed call is logged: who, tool, args (patient IDs only), result, time. Sink is `AiToolAudit` (in-memory now; Firestore `ai_tool_logs` needs a rules change before turning on).
9. **AI consent** — the agent refuses to run without `AiConsent.granted` and the `ai` permission.
10. **One definition, three callers** — in-app agent, voice overlay, and (later) the Pipecat phone receptionist. The receptionist gets only `phone_safe` tools, re-implemented server-side against the same names and schemas.

## Tool list

Legend: **R** read · **W** write+undo · **C** confirm · perm = `ClinicPermission`.

### core / navigation (always sent)
| tool | risk | perm | inputs | backed by |
|---|---|---|---|---|
| `open_screen` | R | — | screen (enum from voice_navigation targets), patientId? | voice navigation targets / router |
| `open_patient` | R | patientsView | patientId, tab? (overview, clinical, visits, files, payments) | patient details route |
| `search_everything` | R | patientsView | query | patients + visits + invoices + files (client-side) |
| `get_today_overview` | R | schedule | — | todaysVisitsProvider, todaysQueueProvider, pendingPaymentsProvider |
| `get_current_context` | R | — | — | screen, open patient, selected date (from caller) |
| `get_clinic_info` | R | — | — | activeClinicProvider, clinic doctors |
| `list_doctors` | R | schedule | — | clinic doctors provider |

### patients
| tool | risk | perm | inputs | backed by |
|---|---|---|---|---|
| `find_patient` | R | patientsView | query (name/phone/CruDoc ID), limit? | filteredPatientsProvider / patient summaries |
| `get_patient_summary` | R | patientsView | patientId | getPatient + billing + last visit |
| `get_patient_medical_alerts` | R | clinicalView | patientId | patient conditions/allergies |
| `get_patient_history` | R | clinicalView | patientId, limit? | visitsForPatientProvider + notes |
| `create_patient` | W | patientsEdit | firstName, lastName?, phone?, dob?, age?, gender?, email?, address?, conditions[]? | createPatient |
| `update_patient` | W | patientsEdit | patientId, fields (phone, email, address, dob, gender, name) | updatePatient |
| `add_medical_condition` | W | clinicalEdit | patientId, condition | updatePatient |
| `set_doctors_note` | W | clinicalEdit | patientId, note | updateDoctorsNote |
| `find_duplicate_patients` | R | patientsView | name?, phone? | patient summaries |
| `archive_patient` | C | patientsEdit | patientId, reason | deletePatient (soft) |

### appointments
| tool | risk | perm | inputs | backed by |
|---|---|---|---|---|
| `list_appointments` | R | schedule | date or from/to, doctorId?, status? | allVisitsProvider |
| `get_appointment` | R | schedule | visitId | getVisit |
| `find_free_slots` | R | schedule | date, durationMinutes, doctorId? | visits for day + clinic hours |
| `list_patient_appointments` | R | schedule | patientId, upcomingOnly? | visitsForPatientProvider |
| `book_appointment` | W | schedule | patientId, date, time, durationMinutes?, doctorId?, reason?, homeVisit?, address? | createVisit |
| `reschedule_appointment` | W | schedule | visitId, date?, time?, shiftMinutes? | rescheduleVisit |
| `set_appointment_status` | W | schedule | visitId, status (done, missed, confirmed) | updateStatus |
| `cancel_appointment` | C | schedule | visitId, reason? | cancelVisit |
| `add_to_group` | W | schedule | visitId, patientId | addToGroup |
| `send_appointment_confirmation` | C | messaging | visitId | MessagingRepository.sendAppointmentConfirmation |

### queue
| tool | risk | perm | inputs | backed by |
|---|---|---|---|---|
| `list_queue` | R | schedule | waitingOnly? | todaysQueueProvider / waitingQueueProvider |
| `check_in_patient` | W | schedule | visitId or patientId | addToToken / markArrived |
| `call_next` | W | schedule | — | first waiting → start |
| `start_consultation` | W | schedule | entryId or patientId | same path as voice startConsultation |
| `complete_queue_entry` | W | schedule | entryId | complete |
| `cancel_queue_entry` | C | schedule | entryId | cancel |

### dental (only when dental features are on)
| tool | risk | perm | inputs | backed by |
|---|---|---|---|---|
| `get_tooth_chart` | R | clinicalView | patientId, tooth? | tooth chart entries |
| `add_tooth_finding` | W | clinicalEdit | patientId, tooth, surfaces[]?, condition, note? | saveToothChartEntry |
| `remove_tooth_finding` | C | clinicalEdit | entryId | deleteToothChartEntry |
| `list_procedure_catalog` | R | clinicalView | query? | catalog |
| `get_treatment_plan` | R | clinicalView | patientId | plan line items |
| `add_treatment_plan_item` | W | clinicalEdit | patientId, tooth?, procedureId, fee?, note? | saveTreatmentPlanLineItem |
| `set_treatment_item_status` | W | clinicalEdit | itemId, status (planned, accepted, in_progress, done, declined) | updateTreatmentPlanLineItemStatus |
| `log_procedure` | W | clinicalEdit | patientId, tooth?, procedureId, note? | saveProcedureLog |
| `record_perio` | W | clinicalEdit | patientId, tooth, site (MB,B,DB,ML,L,DL), depth, recession?, bleeding?, suppuration? | dental records |
| `log_sterilization` | W | inventory | cycle, load, result, operator? | saveSterilizationLog |
| `list_referrals` | R | clinicalView | direction (incoming, outgoing) | referral providers |

### clinical notes / scribe / prescriptions
| tool | risk | perm | inputs | backed by |
|---|---|---|---|---|
| `add_clinical_note` | W | clinicalEdit | patientId, text, visitId? | consultation note repo |
| `get_consultation_note` | R | clinicalView | noteId or visitId | getNote |
| `update_consultation_note` | W | clinicalEdit | noteId, section (complaint, findings, diagnosis, plan, advice), text | updateSessionNote |
| `draft_prescription` | C | clinicalEdit | patientId, items[{drug, dose, frequency, days, instructions}] | inventory medicines + note; never auto-signed |
| `get_homeopathy_case` | R | clinicalView | patientId | getCaseSheetForPatient |
| `add_homeopathy_session_note` | W | clinicalEdit | patientId, text, remedy?, potency? | saveSessionNote |

### billing / revenue
| tool | risk | perm | inputs | backed by |
|---|---|---|---|---|
| `get_patient_dues` | R | billing | patientId | patientBillingProvider |
| `list_pending_payments` | R | billing | — | pendingPaymentsProvider |
| `list_invoices` | R | billing | patientId?, from?, to?, status? | invoices |
| `get_invoice` | R | billing | invoiceId | invoice repo |
| `draft_invoice` | C | billing | patientId, items[{name, qty, rate, taxPercent?}], discount? | createInvoice (draft) |
| `record_payment` | C | billing | visitId or pendingPaymentId or invoiceId, amount, mode (cash, upi, card, bank, other) | recordPayment / markPendingPaymentAsPaid |
| `cancel_invoice` | C | billing | invoiceId, reason | cancelInvoice |
| `get_revenue_summary` | R | revenue | period (today, week, month, custom), from?, to? | revenueOverviewProvider |
| `get_recent_revenue` | R | revenue | limit? | recentRevenueEntriesProvider |

### inventory
| tool | risk | perm | inputs | backed by |
|---|---|---|---|---|
| `find_stock_item` | R | inventory | query | medicinesStreamProvider |
| `list_low_stock` | R | inventory | — | lowStockMedicinesProvider |
| `list_expiring_stock` | R | inventory | withinDays? | expiringMedicinesProvider |
| `add_stock_item` | W | inventory | name, unit, quantity, minQuantity?, expiry?, price? | createMedicine |
| `record_stock_movement` | W | inventory | itemId, type (in, out, adjust), quantity, note? | recordTransaction |
| `list_stock_purchases` | R | inventory | limit? | stockPurchasesProvider |

### tasks / to-do / lab
| tool | risk | perm | inputs | backed by |
|---|---|---|---|---|
| `list_todos` | R | — | includeDone? | myTodosProvider |
| `add_todo` | W | — | text, due?, patientId?, pinned? | TodoRepository.save |
| `complete_todo` | W | — | todoId | complete (undo = reopen) |
| `list_lab_cases` | R | clinicalView | status? | dental records (lab) |
| `create_lab_case` | W | clinicalEdit | patientId, type, lab, due, tooth?, shade?, note? | dental records |

### files / imaging
| tool | risk | perm | inputs | backed by |
|---|---|---|---|---|
| `list_patient_files` | R | clinicalView | patientId, kind? | patientFilesProvider |
| `list_recent_files` | R | clinicalView | limit? | recentFilesProvider |
| `open_file` | R | clinicalView | fileId | files viewer route |
| `list_radiology_studies` | R | clinicalView | patientId? | radStudiesProvider |
| `list_radiology_reports` | R | clinicalView | patientId?, status? | radReportsProvider |

### messaging / campaigns
| tool | risk | perm | inputs | backed by |
|---|---|---|---|---|
| `get_message_status` | R | messaging | visitId | WhatsApp / email logs |
| `list_failed_reminders` | R | messaging | — | failedRemindersProvider |
| `send_reminder` | C | messaging | patientId, channel (whatsapp, email), template, visitId? | messaging repo / Gmail send |
| `list_campaigns` | R | messaging | — | campaign repo |
| `draft_campaign` | C | messaging | name, channel, audience filter, message | createCampaign (not dispatched) |

### team / reports
| tool | risk | perm | inputs | backed by |
|---|---|---|---|---|
| `list_team_members` | R | team | — | clinicMembersProvider |
| `generate_medical_report` | C | clinicalView | patientId, type | MedicalPdfService |

### Not tools (deliberately)
Hard deletes, settings changes, role/permission changes, subscription, sign-out, sending files to other doctors, campaign dispatch. The AI can open the screen; the human does it.

## Phone receptionist subset (`phone_safe`)
`find_patient` (phone match only), `find_free_slots`, `book_appointment`, `reschedule_appointment`, `cancel_appointment`, `list_patient_appointments`, `get_clinic_info`, `list_doctors`. Server-side copies in `functions/` later.

## Build order
1. Core: types, registry, executor (permission + confirm + undo + audit), agent loop on `firebase_ai` (manual function-call loop, max 8 steps).
2. Tool groups (parallel): patients+core, appointments+queue, dental+clinical, billing+inventory, tasks+files+messaging+team.
3. Wire: voice overlay → agent when keyword rules return `none`; then a text field.
