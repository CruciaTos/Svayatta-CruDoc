# CruDoc — Dentist Specialization — Phase Roadmap

Repo audited: `CruciaTos/Svayatta-CruDoc` (cloned, read directly — not from memory).

## 0. Blunt finding before any of this gets built

"Login for dentists" already exists — sort of. The auth screen already has a full specialty picker (`lib/core/models/doctor_specialty.dart`) covering 10 specialties including Dentist: its own label, tagline, teal theme, icon, demo credentials (`dental@crudoc.com`), and a `quickActions` list (`Tooth Chart, Procedure Log, Sterilization, Dental Inv.`). Specialty gets saved to Firestore on selection (`specialty_provider.dart`) and streamed back after login via `activeDoctorSpecialtyProvider`.

But it's a skin, not a feature set. `quickActions` isn't referenced anywhere outside that one file — not rendered on any dashboard. Everywhere else specialty shows up (dashboard header, prescription/report headers), it's display-text only. None of the four dental quick actions exist as real screens, models, or Firestore collections. So the actual gap isn't login — it's that picking "Dentist" today unlocks nothing a General Physician account can't already do.

Also flagging: `firestore.rules` at repo root is still the Firebase default placeholder, hard-expiring `2026-08-07` — that's already past. If that's what's actually deployed, every Firestore read/write is currently being denied. Whoever starts Phase 0 should confirm what's live in the Firebase console (there's a second file, `firestore_super_admin.rules`, that looks like the real ruleset but isn't named what `firebase deploy` reads by default) before building new collections against a dead backend.

## 1. Design constraints — apply to every phase
- Premium, clean, minimal. Match the restraint of the existing specialty theming (soft gradient + accent color) — don't reskin the whole app per specialty.
- Motion stays functional only (sheet/tab transitions). No bespoke or attention-grabbing animation.
- Reuse existing patterns before inventing new ones: sqflite-first local + Firestore sync (the patients/visits pattern), Riverpod providers, existing sheet/dialog conventions.
- New visual assets (icon set, empty-state illustration) can come from Higgsfield — static image/icon output only, to stay consistent with the "not distracting" brief.

## 2. Core feature list — Dentist specialization
- **Tooth Chart (Odontogram)** — per-patient visual chart, tap a tooth to log condition/treatment, per-tooth history
- **Procedure Log** — dental procedure catalog (scaling, filling, RCT, extraction, crown, implant, etc.), logged per visit, optionally linked to specific teeth
- **Dental Inventory** — consumables specific to a dental clinic (composite, anesthetic cartridges, burs, disposables), as an extension of the existing inventory module
- **Sterilization Log** — autoclave cycle records for compliance, clinic-level, not patient-linked
- **Dental treatment plan / quote** — multi-procedure estimate, feeding the existing invoice screen instead of a new one
- **Dashboard quick actions** — the four labels already sitting unused in `doctor_specialty.dart`, finally wired to real navigation

### Optional AI expansion track

These capabilities are outside the core dental data scope above. They should be treated as a separate, opt-in track. The existing `crudoc-ai-voice-scribe-feature-plan.md` already covers a generic consultation scribe, so dental AI should add dental context rather than create another generic chat screen.

#### AI-A. Dental chairside scribe
- Extend the existing scribe concept with dental fields: tooth numbers, surfaces, periodontal findings, anesthesia, procedure performed, materials, post-op instructions, and follow-up interval.
- Extract only what was spoken or selected; never infer a diagnosis or treatment from silence.
- Produce an editable draft and require explicit dentist confirmation before writing to the chart.
- Small packets: dental note schema, dental vocabulary prompt, tooth-number validation, draft review fields, confirmed-record mapping, offline queue, audit tests.
- Risk: medium. This is the best first AI feature because it saves time without requiring image diagnosis.

#### AI-B. Treatment-plan copilot
- Turn confirmed chart findings and selected procedures into a draft treatment plan with sequence, alternatives, estimated visits, and questions to discuss with the patient.
- Separate clinical suggestions from fees and invoices; prices must come from the clinic catalog, never from the model.
- Show the source facts used for every suggestion so the dentist can detect an incorrect tooth or procedure.
- Small packets: fact extraction, plan draft model, sequencing rules, alternatives UI, dentist approval, invoice handoff, regression fixtures.
- Risk: medium-high. It must be advisory and must not automatically schedule, prescribe, or finalize treatment.

#### AI-C. Patient education and post-operative instructions
- Generate plain-language explanations for a confirmed procedure, aftercare instructions, warning signs, medication instructions entered by the dentist, and follow-up reminders.
- Support clinic-approved templates and languages rather than allowing unconstrained medical advice.
- Let the dentist edit and approve the message before sending it by the existing messaging channel.
- Small packets: template library, structured input contract, multilingual generation, reading-level check, dentist approval, send-history audit.
- Risk: medium. Generated instructions must be bounded by approved content and clearly marked for review.

#### AI-D. Dental image review assistant
- Accept intraoral photographs, bitewing images, panoramic images, or uploaded reports and return a structured list of visual observations with confidence and image regions where supported.
- Label output as an assistant observation, not a diagnosis. The dentist must confirm, reject, or edit every observation.
- Store the original image, model version, prompt/configuration version, reviewer, and final confirmed finding separately.
- Start with image quality checks, tooth/region labeling, and comparison over time before attempting pathology suggestions.
- Small packets: secure image upload, image metadata, quality classifier, tooth-region annotation, side-by-side comparison, observation review, model/version audit, retention policy.
- Risk: high. Do not make this the first AI feature; validate the model, vendor, jurisdiction, consent, and clinical governance first.

#### AI-E. Intraoral photo progression comparison
- Compare dentist-captured images from different visits after alignment and show possible visual change, such as increased redness, swelling, plaque, or visible lesion size.
- Present side-by-side images and a change explanation; do not claim that a change is clinically significant without dentist review.
- Small packets: capture guidance, image alignment, same-region matching, change visualization, review annotation, patient-consent and deletion flow.
- Risk: high. This is safer as a measurement and comparison tool than as an autonomous diagnostic system.

#### AI-F. Preventive risk and recall assistant
- Combine confirmed history, missed appointments, hygiene procedures, questionnaire answers, and dentist-entered risk factors to suggest recall timing and outreach lists.
- Prefer deterministic clinical rules for thresholds; use AI only to summarize reasons and draft outreach copy.
- Make every recommendation explainable: “overdue cleaning,” “missed follow-up,” or “dentist-entered risk factor,” not an opaque score alone.
- Small packets: feature contract, rules-based baseline, explanation text, recall queue, dentist override, outcome tracking.
- Risk: medium. Avoid presenting a population-risk estimate as a diagnosis.

#### AI-G. Clinical note and chart quality reviewer
- Check a draft or finalized note for missing tooth number, surface, procedure status, consent, anesthesia, material, post-op instruction, or follow-up fields where relevant.
- Flag omissions and contradictions without rewriting the record automatically.
- Examples: a procedure log references tooth 36 but the note says tooth 26; an extraction has no post-op instructions; a completed procedure has no linked visit.
- Small packets: procedure-specific completeness rules, contradiction detector, review panel, dentist override, audit trail.
- Risk: low-medium. This is a strong early feature because it reviews documentation rather than making a clinical decision.

#### AI-H. Dental coding and claim pre-check
- Suggest likely billing/service codes from a confirmed procedure record, then show the evidence and let staff select the final code.
- Keep code sets versioned by country and payer; never treat a model-generated code as authoritative.
- Start with missing-field and mismatch checks before code suggestion.
- Small packets: code-set import, deterministic validation, candidate suggestion, evidence display, staff approval, invoice/claim export test.
- Risk: medium-high. Regulatory and payer accuracy requirements vary significantly by location.

#### AI-I. Existing-module intelligence overlays
- Do not build a second inventory, appointment, billing, or messaging module. Add optional intelligence to the modules CruDoc already has.
- Inventory overlay: forecast likely usage, explain unusual stock movement, and suggest reorder timing while keeping the existing inventory records and approval workflow authoritative.
- Appointment overlay: estimate chair time, identify likely follow-up needs, and prioritize reminders without denying care or labeling patients unfairly.
- Revenue overlay: explain unpaid or unusual invoice patterns and surface missing links between visits, procedures, and invoices; never alter financial records automatically.
- Messaging overlay: draft personalized recall and post-operative messages using confirmed clinical facts; require approval through the existing messaging flow.
- Small packets: read-only data adapter, deterministic baseline, suggestion model, explanation panel, existing-module handoff, override tracking, outcome evaluation.
- Risk: low-medium operationally, but medium where patient prioritization or financial decisions are involved.

#### Recommended AI order

1. **AI-G — Chart quality reviewer:** bounded, testable, and immediately useful.
2. **AI-A — Dental chairside scribe:** strongest time-saving feature, building on the existing scribe plan.
3. **AI-C — Patient education:** valuable after confirmed procedure data exists.
4. **AI-F — Preventive recall assistant:** begin with deterministic rules and add generated explanations later.
5. **AI-B — Treatment-plan copilot:** add after chart and procedure data are trustworthy.
6. **AI-I — Existing-module intelligence overlays:** add only as read-only suggestions over the current inventory, appointments, revenue, and messaging modules.
7. **AI-D/E — Image review and progression:** only after governance, consent, validation, and secure image infrastructure are ready.
8. **AI-H — Coding and claim pre-check:** add only after jurisdiction and payer requirements are confirmed.

#### AI guardrails for every packet

- The model never writes a clinical, billing, or compliance record without human confirmation.
- Every generated value is visibly marked as generated until confirmed.
- Store model/configuration version, input record IDs, reviewer, decision, and timestamp for auditability.
- Send the minimum necessary data to the model; do not include unrelated patient history by default.
- Do not train a model on patient data unless the clinic has an explicit, documented basis and consent policy.
- Provide a non-AI workflow for every essential task so a model outage never blocks patient care.
- Add adversarial fixtures for wrong tooth numbers, invented findings, contradictory notes, prompt injection in uploaded text, and malformed model output.

### AI expansion delivery phases

The following phases are for the optional AI track only. They do not create replacement versions of existing CruDoc modules. Each phase can be handed to a smaller model as a sequence of narrow packets.

#### AI-0 — Shared AI foundation

**Goal:** create one controlled path for AI features instead of scattering provider calls through screens.

- **AI-0.1 Capability inventory:** list existing AI entry points, scribe behavior, chatbot behavior, OCR behavior, model providers, keys, feature flags, and data destinations. Mark each as reuse, replace, or leave untouched.
- **AI-0.2 AI gateway contract:** define one service boundary for prompt/model calls, structured output, retries, timeouts, cancellation, and usage metadata.
- **AI-0.3 Sensitive-data policy:** classify audio, transcript, images, notes, messages, and identifiers. Define what may leave the device and what must be redacted.
- **AI-0.4 Human-review contract:** define generated, reviewed, confirmed, rejected, and expired states shared by every AI feature.
- **AI-0.5 Audit event model:** store feature name, model/configuration version, source record IDs, reviewer, decision, and timestamps without storing unnecessary prompt payloads.
- **AI-0.6 Evaluation fixtures:** create synthetic dental cases for normal, ambiguous, contradictory, incomplete, multilingual, and adversarial inputs.
- **AI-0.7 Failure and fallback behavior:** verify every AI feature has a manual path and a useful error state when offline, rate-limited, unavailable, or malformed.
- **Checkpoint:** no AI feature proceeds until the gateway, privacy, audit, review-state, and fixture contracts are approved.

#### AI-1 — Dental clinical memory and record search

**Goal:** let a dentist ask questions about one patient’s existing records and receive cited answers, without autonomous diagnosis.

- **AI-1.1 Record scope:** define searchable sources: visits, confirmed scribe notes, tooth history, procedures, prescriptions, reports, messages, and attachments. Exclude drafts by default.
- **AI-1.2 Patient isolation:** enforce patient and clinic scope before retrieval; test direct access with another doctor and another patient.
- **AI-1.3 Timeline normalizer:** build a deterministic chronological view with tooth number, procedure, author, date, and source record ID.
- **AI-1.4 Search query parser:** support questions such as “When was tooth 36 last treated?” and “Which procedures remain open?” without allowing broad unrestricted database queries.
- **AI-1.5 Citation response:** show the exact source record and date behind every answer; show “not found” instead of guessing.
- **AI-1.6 Review and correction:** allow the dentist to flag an incorrect answer and preserve that feedback for evaluation, not silent model training.
- **AI-1.7 Offline behavior:** provide deterministic filters and timeline search when the model is unavailable.
- **Checkpoint:** answer quality is tested for wrong-tooth, wrong-patient, missing-record, and contradictory-history cases.

#### AI-2 — Dental case presentation and consultation assistant

**Goal:** help the dentist explain a confirmed case clearly to a patient or colleague.

- **AI-2.1 Fact bundle:** collect only confirmed findings, images selected by the dentist, procedure history, and approved treatment-plan data.
- **AI-2.2 Dentist-facing summary:** generate a concise case summary with known facts, open questions, and missing information clearly separated.
- **AI-2.3 Patient-facing explanation:** create plain-language explanations of the confirmed condition and proposed options without adding new diagnoses.
- **AI-2.4 Option comparison:** show benefits, limitations, visits, risks, and alternatives from dentist-authored templates or approved knowledge, not invented claims.
- **AI-2.5 Consent conversation draft:** generate questions the dentist should discuss and a checklist of topics; do not generate a legal consent record automatically.
- **AI-2.6 Share/print review:** reuse existing PDF/report infrastructure only after dentist approval and show generated content as a draft until confirmed.
- **AI-2.7 Language and reading level:** support clinic-approved languages and a selectable reading level, with a clear review step for translation quality.
- **Checkpoint:** the patient-facing output must be traceable to confirmed source facts and must never silently include draft AI findings.

#### AI-3 — Dental documentation quality and safety reviewer

**Goal:** identify missing or contradictory documentation before a note is finalized.

- **AI-3.1 Procedure rule matrix:** define required fields for examination, filling, extraction, root canal, crown, implant, scaling, and other catalog procedures.
- **AI-3.2 Deterministic checks first:** detect missing tooth, surface, visit, status, consent, material, anesthesia, post-op, and follow-up fields without using an LLM.
- **AI-3.3 Contradiction checks:** compare tooth numbers, procedure status, dates, fees, and linked visits across records.
- **AI-3.4 AI explanation layer:** use AI only to explain the warning in readable language and suggest what to review.
- **AI-3.5 Review panel:** let the dentist dismiss, correct, or defer each warning with a reason.
- **AI-3.6 Finalization gate:** optionally block finalization only for clinic-configured hard requirements; never block emergency documentation on a model timeout.
- **AI-3.7 Audit and metrics:** measure false positives, dismissed warnings, corrected warnings, and unresolved warnings.
- **Checkpoint:** a record can be finalized manually, but every configured hard warning is explicit and auditable.

#### AI-4 — Preventive care and follow-up intelligence

**Goal:** improve continuity of care using existing appointments, messaging, and patient records.

- **AI-4.1 Rules baseline:** define deterministic triggers for overdue cleaning, missed post-op review, unfinished treatment plan, and missing recall date.
- **AI-4.2 Patient segmentation:** distinguish active treatment, maintenance, post-operative, inactive, and high-priority review queues using explainable rules.
- **AI-4.3 Follow-up summary:** summarize why a patient is on a queue using source dates and confirmed facts.
- **AI-4.4 Message draft:** create a draft in the existing messaging system with approved clinic tone and language.
- **AI-4.5 Dentist/staff approval:** require a user to review recipient, facts, timing, and message before sending.
- **AI-4.6 Outcome tracking:** record sent, delivered, replied, booked, ignored, and opted-out states without treating response behavior as clinical truth.
- **AI-4.7 Bias review:** check whether the queue unfairly deprioritizes patients based on protected or irrelevant attributes.
- **Checkpoint:** every recommendation has an explanation and a manual filter; no patient is silently excluded from care.

#### AI-5 — Existing-module intelligence adapters

**Goal:** add AI assistance around current CruDoc workflows without creating duplicate modules.

- **AI-5.1 Inventory adapter:** read confirmed procedures and existing stock movements; produce a reorder suggestion with source quantities and confidence.
- **AI-5.2 Appointment adapter:** summarize expected chair-time uncertainty and suggest buffers; never auto-cancel or reject an appointment.
- **AI-5.3 Revenue adapter:** identify records needing human reconciliation, such as a completed visit with no invoice or an invoice with no visit link.
- **AI-5.4 Messaging adapter:** draft recall, post-op, and treatment-plan messages from approved facts and templates.
- **AI-5.5 Suggestion presentation:** show suggestions beside the existing module, not in a replacement dashboard.
- **AI-5.6 Approval and handoff:** use the existing create/edit flows after the user accepts a suggestion; preserve the original source and user decision.
- **AI-5.7 Evaluation:** compare suggestions with staff decisions and measure correction rate before enabling automation-like shortcuts.
- **Checkpoint:** existing modules remain fully usable with AI disabled and no AI suggestion mutates data automatically.

#### AI-6 — Image intelligence readiness

**Goal:** prepare for image assistance safely before attempting clinical image interpretation.

- **AI-6.1 Image inventory:** identify current image picker, storage, attachment, report, and deletion capabilities before adding new upload paths.
- **AI-6.2 Consent and retention:** define whether images are clinical records, how long they remain, who can view them, and how patient deletion works.
- **AI-6.3 Quality checks:** implement blur, darkness, glare, crop, and missing-tooth-region checks before any clinical observation model.
- **AI-6.4 Region and tooth annotation:** let the dentist mark the relevant tooth or region manually; do not rely on an unverified detector initially.
- **AI-6.5 Longitudinal comparison:** provide secure side-by-side comparison of dentist-selected images before adding automated change claims.
- **AI-6.6 Observation review:** if a validated model is later introduced, show image region, confidence, model version, and accept/reject/edit controls.
- **AI-6.7 Governance gate:** require clinical validation, vendor review, jurisdiction review, and a pilot before pathology suggestions are enabled.
- **Checkpoint:** image upload and comparison are useful without a diagnostic model, so the feature remains safe if model access is disabled.

#### AI-7 — Personal dental prevention coach

**Goal:** provide patient education and habit support based on dentist-approved plans, not autonomous medical advice.

- **AI-7.1 Approved knowledge base:** create clinic-approved content for brushing, flossing, diet, appliance care, post-op care, and warning signs.
- **AI-7.2 Personalization inputs:** allow only dentist-selected goals, procedure status, appliance type, language, and reminder preference.
- **AI-7.3 Conversation boundaries:** reject diagnosis, emergency treatment, medication changes, and unrelated medical questions; route urgent symptoms to clinic contact instructions.
- **AI-7.4 Patient consent:** capture opt-in, channel, frequency, language, and unsubscribe state.
- **AI-7.5 Human escalation:** provide a clear “contact clinic” path and surface unanswered or concerning messages to staff.
- **AI-7.6 Outcome review:** measure engagement and appointment follow-through without claiming that engagement equals improved oral health.
- **Checkpoint:** the coach can educate and remind, but it cannot prescribe, diagnose, or replace a dental visit.

#### AI-8 — Pilot, evaluation, and controlled rollout

**Goal:** make AI features measurable and reversible before broad release.

- **AI-8.1 Feature flags:** gate each capability independently by clinic, specialty, plan, role, and platform.
- **AI-8.2 Pilot cohort:** choose synthetic data first, then one consenting test clinic with named reviewers.
- **AI-8.3 Quality thresholds:** define acceptable citation accuracy, correction rate, false-warning rate, latency, cost, and outage behavior per feature.
- **AI-8.4 Safety review:** run wrong-patient, wrong-tooth, hallucination, prompt-injection, privacy, bias, and malformed-output tests.
- **AI-8.5 Cost controls:** add per-doctor and per-clinic quotas, model fallback, caching only for non-sensitive content, and a visible usage monitor.
- **AI-8.6 Rollback:** disable generation while retaining manual workflows and previously confirmed records.
- **AI-8.7 Post-release review:** inspect audit events, user corrections, support tickets, and clinical-owner feedback before expanding the pilot.
- **Checkpoint:** no AI feature becomes a default workflow until its quality, safety, cost, and rollback criteria are met.

## 3. Phase plan

The phases below are deliberately split into small work packets. A packet should be completed in one focused session, reviewed, and tested before the next packet starts. A smaller model should not implement an entire numbered phase unless all of that phase's packets are explicitly requested.

### Phase 0 — Data foundation and rules

**Goal:** establish contracts and persistence without building user-facing screens.

#### 0.1 — Repository reconnaissance
- Locate the patient, visit, inventory, invoice, Firestore service, local SQLite, model, repository, and Riverpod provider patterns.
- Record the exact paths and names that the later packets must reuse.
- Do not change code.
- Done when the implementer can name the nearest existing analogue for each new dental model.
- Check: compile or test the repository exactly as it was before this packet.

#### 0.2 — Firestore deployment decision
- Compare `firestore.rules` with `firestore_super_admin.rules` and inspect `firebase.json` deployment configuration.
- Confirm in the Firebase console which ruleset is deployed; do not infer deployment from filenames.
- Decide which file is authoritative and document the decision in this roadmap.
- Do not deploy rules as part of this packet.
- Done when there is a written answer to: “Which rules file does deployment use, and is the deployed version usable?”
- Check: use Firebase rules validation or a read-only rules inspection where available.

#### 0.3 — Dental data contract
- Define fields, types, required/optional status, defaults, timestamps, IDs, and ownership fields for:
	- dental procedure catalog entries
	- tooth chart entries
	- procedure log entries
	- sterilization log entries
	- future treatment-plan line items
- Decide whether tooth numbers use Universal Numbering, FDI, or Palmer notation. Store the notation/version with the chart or clinic configuration.
- Decide how soft deletion, audit timestamps, doctor ID, clinic ID, and patient ID are represented.
- Done when the contract can be reviewed without opening the UI.
- Check: every field maps cleanly to Dart and Firestore-supported types.

#### 0.4 — Firestore collection paths and indexes
- Write the exact collection/subcollection paths and query shapes.
- Define required composite indexes only for queries that are actually needed.
- Document tenant/doctor isolation expectations for every collection.
- Done when no later packet needs to invent a collection name or query shape.
- Check: run Firestore emulator/index validation if configured; otherwise perform a rules/query review.

#### 0.5 — Rules test cases
- Add allow/deny scenarios for signed-out users, the owning doctor, another doctor, another clinic, and super-admin access where applicable.
- Include patient subcollection access tests for tooth charts and procedure logs.
- Include clinic-level access tests for sterilization logs.
- Done when the test cases express the security contract, even if the rules implementation is deferred.
- Check: run the existing rules test command or document why it is unavailable.

#### 0.6 — Dart model: dental procedure catalog
- Add only the catalog model, serialization, deserialization, copy/update behavior, and equality used by the repository.
- Do not add screens, seeded data, or procedure logging yet.
- Done when a catalog object round-trips through the project’s existing serialization pattern.
- Check: focused model test plus analyzer on changed files.

#### 0.7 — Dart models: tooth chart and procedure log
- Add the smallest models required by the data contract.
- Represent a tooth condition/treatment as typed values where the codebase supports enums; preserve unknown future values during deserialization if that is the local convention.
- Keep the procedure log separate from the tooth chart so a procedure can be linked to zero, one, or many teeth.
- Done when valid, empty, and partially populated records round-trip without data loss.
- Check: focused serialization tests.

#### 0.8 — Dart model: sterilization log
- Add the clinic-level sterilization cycle model with date/time, operator/staff, load description or item references, result, notes, and audit fields.
- Keep patient ID out of this model unless the data contract explicitly changes.
- Done when pass/fail and incomplete/draft states are represented intentionally.
- Check: focused model test and analyzer.

#### 0.9 — Local persistence adapters
- Add SQLite table definitions/migrations only for the models approved in 0.6–0.8.
- Follow the existing database version and migration mechanism.
- Define conflict behavior for local edits versus Firestore sync before implementing sync.
- Done when a record can be inserted, read, updated, and deleted locally in a test database.
- Check: migration test from the current schema version.

#### 0.10 — Firestore repositories and providers
- Add repositories and Riverpod providers for catalog, patient dental records, and sterilization logs.
- Keep providers unconnected to UI until Phase 1 or later.
- Expose loading, empty, error, and refresh states consistently with nearby providers.
- Done when a test or small harness can load each record type through the public provider/repository API.
- Check: repository tests using mocks/emulator plus analyzer.

#### 0.11 — Seed catalog data
- Create a small versioned seed list for common procedures: consultation, scaling, filling, root canal, extraction, crown, implant, and other agreed clinic procedures.
- Make seeding idempotent; never duplicate entries on repeated startup.
- Do not silently overwrite clinic-customized prices or names.
- Done when a new clinic receives usable starter data and an existing clinic keeps its edits.
- Check: run the seed operation twice and verify stable results.

#### 0.12 — Phase 0 integration checkpoint
- Review models, migrations, repositories, providers, seed behavior, and rules together.
- Resolve naming or ownership inconsistencies before UI work begins.
- Done when Phase 1 can consume stable APIs without adding temporary persistence code.
- Check: full analyzer and the narrowest available unit/integration test suite.

### Phase 1 — Tooth chart

**Goal:** provide a dentist-only, patient-specific odontogram with history.

#### 1.1 — Patient-details integration point
- Identify the patient details route, tabs, sheets, and responsive desktop/mobile variants.
- Add a dentist-only placeholder entry point without implementing the chart.
- Hide the entry point, rather than merely disabling it, for non-dentists.
- Done when a Dentist can reach a clearly labeled empty chart surface and other specialties cannot see it.
- Check: test both specialty states and verify route behavior.

#### 1.2 — Tooth numbering and chart layout
- Implement the static chart using the numbering convention selected in 0.3.
- Include stable tooth hit targets, labels, arch/quadrant grouping, and responsive constraints.
- Do not add persistence or condition editing yet.
- Done when all supported teeth render correctly on narrow and wide layouts.
- Check: widget test for tooth count, labels, and layout overflow.

#### 1.3 — Tooth visual states
- Map neutral, healthy, condition-present, treated, missing, and unknown states to restrained visual tokens.
- Keep the visual state derived from model data rather than local paint-only flags.
- Done when a fixture chart renders every supported state consistently.
- Check: widget test with a fixture containing each state.

#### 1.4 — Tooth selection and detail sheet
- Make a tooth selectable and open the existing sheet/dialog style used by the app.
- Show tooth number, current state, last update, and history summary.
- Do not save edits yet.
- Done when selection works with keyboard/touch/mouse as supported by the platform.
- Check: widget test that selects a tooth and opens the correct details.

#### 1.5 — Condition and treatment editor
- Add the smallest editor for condition, treatment/status, notes, and optional date.
- Validate required values and support cancel without mutation.
- Done when the editor returns a validated domain object rather than directly changing the widget state.
- Check: validation tests for empty, valid, cancel, and invalid input.

#### 1.6 — Save one tooth locally
- Connect the editor to the local repository for one patient and one tooth.
- Refresh the chart from persisted data after save.
- Done when closing and reopening the patient retains the tooth state offline.
- Check: repository/widget integration test.

#### 1.7 — Per-tooth history
- Add chronological history for the selected tooth.
- Show who changed it and when where the existing audit data supports it.
- Keep the current state distinct from historical events.
- Done when multiple edits remain visible in correct order.
- Check: fixture test with repeated edits and equal timestamps.

#### 1.8 — Firestore synchronization
- Connect the existing sync pattern after local behavior is stable.
- Handle offline edits, retry, duplicate events, and remote refresh according to the conflict decision in 0.9.
- Done when local-first behavior remains usable without a network.
- Check: emulator/offline integration test if available; otherwise a deterministic repository test.

#### 1.9 — Tooth chart access and regression checkpoint
- Verify specialty gating, patient isolation, loading, empty, error, and permission-denied states.
- Check mobile and desktop patient-details entry points.
- Done when the chart is usable as a standalone patient-details feature.
- Check: analyzer, focused widget tests, and a manual smoke test on both layouts.

### Phase 2 — Procedure log and treatment quotes

**Goal:** catalog and record dental procedures, then reuse existing invoice creation.

#### 2.1 — Catalog read-only screen
- Display seeded and clinic-customized procedures with search/filter.
- Keep this separate from editing until read behavior is proven.
- Done when a dentist can find a procedure quickly.
- Check: provider/widget tests for loading, empty, search, and error states.

#### 2.2 — Catalog administration
- Add create, edit, archive, restore, and price validation according to existing permissions.
- Prevent archived procedures from appearing as new choices while preserving old logs.
- Done when catalog changes do not rewrite historical records.
- Check: repository tests for archive and historical snapshot behavior.

#### 2.3 — Procedure log entry form
- Add procedure, date, visit link, selected teeth, fee, status, notes, and practitioner fields as approved by the contract.
- Make tooth selection optional and dentist-only.
- Done when a valid procedure log can be composed before saving.
- Check: form validation tests.

#### 2.4 — Save and list procedure logs
- Persist logs locally first and list them on the patient/visit surface.
- Add edit/cancel rules explicitly; do not silently mutate finalized records.
- Done when a patient’s procedure history is readable and ordered.
- Check: integration test for create, reload, and archive/correction behavior.

#### 2.5 — Link procedures to visits
- Resolve the existing visit ID and patient ID from the current navigation context.
- Reject mismatched patient/visit combinations.
- Done when logs appear in the correct visit without duplicating patient records.
- Check: repository test for valid and mismatched links.

#### 2.6 — Treatment-plan draft
- Add a draft treatment plan containing ordered procedure line items, optional tooth references, quantities, and estimated fees.
- Keep drafts separate from completed procedure logs.
- Done when a plan can be saved and reopened without creating an invoice.
- Check: model/repository round-trip test.

#### 2.7 — Reuse invoice creation
- Map approved treatment-plan lines into the existing invoice creation flow.
- Do not create a second invoice screen or duplicate tax/discount logic.
- Define what happens when a procedure price changes after a draft was created.
- Done when generating an invoice produces the same invoice model and validation as other invoices.
- Check: focused mapping test plus existing invoice tests.

#### 2.8 — Procedure sync and permissions
- Add Firestore sync, ownership checks, and permission-denied UI using established patterns.
- Preserve local history when sync is unavailable.
- Done when procedure logs and plans obey the same clinic/doctor isolation rules as patient data.
- Check: rules/repository tests and analyzer.

#### 2.9 — Phase 2 checkpoint
- Test catalog, log, tooth links, visit links, treatment plan, invoice handoff, and historical stability together.
- Done when a complete procedure can be recorded without manual database edits.
- Check: end-to-end smoke flow on a test patient.

### Phase 3 — Dental inventory

**Goal:** extend the existing inventory instead of creating a parallel stock system.

#### 3.1 — Inventory extension decision
- Inspect the current medicine/inventory category, units, batches, expiry, stock movement, and supplier fields.
- Decide the smallest compatible representation for dental consumables.
- Do not add procedure deduction yet.
- Done when the extension is documented against the existing model.
- Check: existing inventory tests still pass.

#### 3.2 — Dental category and units
- Add dental-consumable classification and supported units only where the current model permits it.
- Include examples such as composite, anesthetic cartridges, burs, gloves, masks, and sterilization pouches.
- Done when dental items can be created and filtered with existing inventory behavior.
- Check: model and filter tests.

#### 3.3 — Dental item entry/edit
- Add or extend the inventory form with dental-specific fields only where needed.
- Preserve existing medicine workflows for non-dental users.
- Done when dental and medicine items can coexist without branching into separate repositories.
- Check: form regression tests.

#### 3.4 — Stock movement audit
- Confirm every increase/decrease has a source, quantity, unit, timestamp, and actor.
- Add an explicit adjustment path for corrections.
- Done when stock cannot change through an untracked direct mutation.
- Check: stock movement tests.

#### 3.5 — Procedure consumption rules
- Define a small configurable consumption recipe per procedure, for example composite quantity for a filling.
- Make recipes optional and editable; never hard-code clinical quantities in the UI.
- Done when the system can preview expected deductions before applying them.
- Check: recipe calculation tests including zero, fractional, and insufficient stock.

#### 3.6 — Apply deduction after procedure completion
- Deduct stock only at the agreed procedure status, not while a draft is being edited.
- Make the operation idempotent so retries do not deduct twice.
- Record the procedure log ID as the source.
- Done when completing a procedure creates exactly one auditable stock movement.
- Check: retry, duplicate-submit, and insufficient-stock tests.

#### 3.7 — Inventory warnings and permissions
- Add low-stock, expired, and insufficient-stock states using existing inventory conventions.
- Verify dentists can view/use stock only within the intended clinic scope.
- Done when inventory problems are visible before procedure completion.
- Check: permission and boundary-condition tests.

#### 3.8 — Phase 3 checkpoint
- Run a complete flow: create dental item, receive stock, configure recipe, log procedure, complete procedure, inspect movement and remaining stock.
- Done when the flow works offline and syncs without duplicate deductions.
- Check: end-to-end test or documented manual smoke test if no harness exists.

### Phase 4 — Sterilization log

**Goal:** record clinic-level autoclave cycles without patient linkage.

#### 4.1 — Sterilization list and empty state
- Add a dentist/clinic-level entry point following existing list-screen conventions.
- Implement loading, empty, error, and date filtering states.
- Done when historical cycles can be browsed without creating records.
- Check: widget/provider tests.

#### 4.2 — Cycle form
- Add cycle date/time, machine or autoclave identifier, operator, load/items, cycle parameters if required, result, and notes.
- Make pass/fail and incomplete states explicit.
- Done when invalid or incomplete cycles cannot be submitted as passed.
- Check: form validation tests.

#### 4.3 — Save, edit, and audit behavior
- Persist locally first and define whether completed cycles are immutable or correction-versioned.
- Show created/updated metadata where the app already uses audit information.
- Done when compliance history cannot disappear through ordinary editing.
- Check: repository tests for create, correction, and archive behavior.

#### 4.4 — Sync and clinic isolation
- Add Firestore sync and rules for clinic-level access.
- Explicitly test that patient IDs are never required or written.
- Done when a sterilization record remains clinic-level on every persistence path.
- Check: serialization, repository, and rules tests.

#### 4.5 — Phase 4 checkpoint
- Run create, reopen, filter, fail, correction, offline, and permission-denied flows.
- Done when sterilization is a complete standalone feature.
- Check: focused integration test and analyzer.

### Phase 5 — Navigation, headers, and polish

**Goal:** expose completed capabilities cleanly and finish the dentist-specific experience.

#### 5.1 — Quick-action contract
- Map `Tooth Chart`, `Procedure Log`, `Sterilization`, and `Dental Inv.` to real destinations.
- Define behavior for unavailable or not-yet-built destinations; do not leave dead buttons.
- Done when every displayed dentist quick action has a tested destination.
- Check: navigation tests for Dentist and non-Dentist specialties.

#### 5.2 — Dashboard placement and responsive behavior
- Render quick actions in the existing dashboard action area or established specialty section.
- Keep labels, icons, disabled states, and ordering consistent with the current dashboard design.
- Done when actions are discoverable on desktop and mobile without crowding existing actions.
- Check: widget tests and narrow/wide layout smoke test.

#### 5.3 — Dental patient-details navigation
- Add chart and procedure-log entries to patient details only for dentists.
- Ensure deep links carry patient ID and visit context safely.
- Done when back navigation returns to the correct patient/visit surface.
- Check: route/deep-link tests.

#### 5.4 — Dental prescription/report header variant
- Replace the plain specialty label swap with a treatment-plan-aware variant only where the document contains dental treatment data.
- Preserve existing headers for non-dental documents and other specialties.
- Done when generated/previewed documents remain backward compatible.
- Check: document snapshot or golden tests.

#### 5.5 — Empty, error, and permission states
- Review every new screen for first-use empty state, offline state, sync failure, and permission denial.
- Keep copy concise and actionable; avoid decorative assets until behavior is stable.
- Done when no new screen leaves a blank or endlessly loading surface.
- Check: state fixture tests.

#### 5.6 — Visual consistency pass
- Match existing specialty accent, spacing, sheets, typography, icon treatment, and motion.
- Add static assets only if they solve a real comprehension problem and are licensed/approved for the project.
- Done when the dental feature set looks like one product rather than a separate mini-app.
- Check: desktop/mobile visual review and overflow scan.

#### 5.7 — Accessibility and interaction pass
- Check semantics, labels, focus order, keyboard activation, touch target sizes, contrast, and screen-reader descriptions for the chart and action controls.
- Done when core workflows are usable without relying only on color or pointer hover.
- Check: accessibility inspection plus manual keyboard traversal on desktop.

#### 5.8 — Full regression checkpoint
- Run analyzer, formatter, unit/widget/integration tests, Firestore rules tests, and the existing app smoke flow.
- Verify non-dentist accounts still see the original experience.
- Done when the implementation is ready for staged release behind the intended specialty gate.
- Check: record exact commands and results in the handoff note.

## 4. Cross-cutting considerations

These are not optional polish items. They affect multiple packets and should be resolved before the first implementation packet that depends on them.

### 4.1 — Clinical terminology and numbering
- Get one dentist to approve the tooth numbering system, condition names, treatment names, and status transitions.
- Decide whether a tooth can have multiple simultaneous conditions and treatments.
- Decide how extracted, missing, unerupted, primary, and replaced teeth are represented.
- Never infer a clinical condition from a color alone; store an explicit value and show a legend.
- Version the terminology if future changes could make old records ambiguous.

### 4.2 — Record immutability and corrections
- Decide which records are drafts, editable records, finalized records, or correction-only records.
- Do not overwrite finalized clinical or compliance history without an audit event.
- Define who may correct a procedure, tooth event, invoice source, inventory deduction, or sterilization cycle.
- Decide whether corrections append a new event or create a version chain.

### 4.3 — Authorization is not only UI gating
- Specialty checks in Flutter are for user experience, not security.
- Firestore rules and repository methods must independently enforce doctor, clinic, role, and patient access.
- Test direct document access for a non-dentist even when the screen is hidden.
- Decide whether assistants, receptionists, hygienists, and clinic admins have different permissions.

### 4.4 — Privacy, retention, and exports
- Confirm whether dental records require additional consent, retention, export, or deletion behavior in the target jurisdiction.
- Ensure exports and invoices include only the minimum necessary clinical data.
- Define account deletion, patient deletion, clinic deletion, and legal-retention behavior before adding destructive actions.
- Check logs, analytics, crash reports, and backups for accidental clinical-data leakage.

### 4.5 — Backup, migration, and rollback
- Back up production data before rules, schema, seed, or migration changes.
- Make every migration forward-only, repeatable, and observable.
- Define how a partially completed migration is detected and resumed.
- Prepare a rollback plan for app versions that understand different record shapes.
- Test an old record with a newer app and an unknown future field with the current app.

### 4.6 — Offline and concurrency behavior
- Define what happens when two devices edit the same tooth, procedure plan, catalog price, or stock item.
- Prefer append-only events for clinical history and stock movements where possible.
- Show sync conflict or stale-data status instead of silently choosing a value.
- Test airplane mode, expired auth, token refresh, retry, duplicate submit, and app termination during save.

### 4.7 — Dates, time zones, and money
- Store timestamps consistently and display them in the clinic/user time zone.
- Decide whether a sterilization cycle belongs to its start date, end date, or local calendar day.
- Store money using the project’s existing safe representation; do not calculate from formatted strings.
- Define currency, tax, rounding, discount, and price-snapshot behavior for treatment plans and invoices.

### 4.8 — Performance and scale
- Set practical limits for teeth history, procedure history, catalog size, inventory movements, and sterilization records.
- Paginate or window long histories rather than loading an entire patient record by default.
- Avoid one Firestore listener per tooth; load the chart as one bounded patient resource where possible.
- Test a patient with a long history and a clinic with a large catalog before calling the feature complete.

### 4.9 — Observability and support
- Add non-sensitive event logging for sync failures, migration failures, rejected stock deductions, and permission denials.
- Include correlation IDs or record IDs in technical logs without logging clinical notes or unnecessary patient details.
- Define what support staff can inspect when a user reports “the tooth chart disappeared” or “stock deducted twice.”
- Add a diagnostic path for rules-version mismatch and failed seed/migration state.

### 4.10 — Release strategy
- Ship data contracts, rules, and dormant code before exposing navigation where a staged rollout requires it.
- Gate new screens behind Dentist specialty and, if needed, a clinic-level feature flag.
- Pilot with one test clinic before enabling inventory deduction or invoice generation broadly.
- Roll out read-only history before enabling destructive or financially meaningful actions.
- Define success criteria and a kill switch for each risky capability.

### 4.11 — Localization and accessibility
- Keep all user-facing labels translatable; do not use enum names as display copy.
- Check long translated labels in quick actions, procedure names, errors, and tooth history.
- Provide text/semantic alternatives for chart colors, icons, and status marks.
- Verify keyboard, touch, screen reader, contrast, and large-text behavior before visual sign-off.

### 4.12 — Test fixture discipline
- Create deterministic fixtures for a new patient, a full adult chart, a pediatric/mixed chart if supported, procedure history, inventory, and sterilization cycles.
- Never use real patient data in fixtures, screenshots, logs, or bug reports.
- Keep fixtures compatible with both local persistence and Firestore emulator tests.
- Add at least one regression fixture for every production bug found during rollout.

## 5. Dependency and release map

Use this order when assigning work. Packets in the same lane may run in parallel only after their listed prerequisite checkpoint is complete.

### 5.1 — Required gates
- **Gate A — Repository and production safety:** 0.1–0.5, cross-cutting 4.1–4.6, and the real Firestore deployment decision must be complete before new collections or rules are trusted.
- **Gate B — Stable dental data layer:** 0.6–0.12 must pass before tooth chart, procedure log, sterilization UI, or AI retrieval work uses the new records.
- **Gate C — Confirmed clinical records:** Phase 1 and Phase 2 checkpoints must pass before treatment-plan AI, record search, documentation QA, or preventive intelligence relies on dental data.
- **Gate D — AI foundation:** AI-0 must pass before any feature sends patient data to a model or stores AI audit events.
- **Gate E — Pilot readiness:** AI-8 must pass before enabling an AI feature for a real clinic beyond the named pilot cohort.

### 5.2 — Parallel work lanes
- **Core data lane:** Phase 0 → Phase 1 → Phase 2 → Phase 5 navigation.
- **Clinic operations lane:** Phase 4 can follow Phase 0 and can proceed independently of the tooth chart; Phase 3 should only extend the existing inventory after the procedure data contract is stable.
- **AI documentation lane:** AI-0 → AI-3; AI-A chairside scribe may reuse the existing scribe implementation but must use the shared AI-0 contracts.
- **AI memory lane:** AI-0 → AI-1, then AI-2 after confirmed procedure/treatment-plan data exists.
- **AI continuity lane:** AI-0 → AI-4, then AI-5 adapters after each existing module’s read-only data contract is verified.
- **AI image lane:** AI-0 → AI-6; do not start model-based image observations until the AI-6 governance gate passes.
- **AI patient lane:** AI-0 → AI-7, after approved education content and messaging consent behavior are available.

### 5.3 — Recommended release slices
- **Slice 1:** data contracts, rules tests, local persistence, and no visible UI.
- **Slice 2:** dentist-only tooth chart read/write with local-first behavior.
- **Slice 3:** procedure catalog, procedure history, and treatment-plan drafts without AI.
- **Slice 4:** sterilization records and existing-inventory procedure linkage.
- **Slice 5:** quick actions, patient-details navigation, and regression hardening.
- **Slice 6:** AI-0 foundation plus AI-3 documentation reviewer in shadow/read-only mode.
- **Slice 7:** AI-A scribe specialization, AI-1 clinical record search, and AI-2 case presentation after review metrics are acceptable.
- **Slice 8:** preventive, patient education, and existing-module intelligence overlays.
- **Slice 9:** image readiness first; image observations only after a separate clinical validation decision.

### 5.4 — Packet sizing rule
- A packet should normally touch one domain boundary: one model, one repository, one screen state, one provider, or one test slice.
- Split a packet again if it needs more than one independent migration, more than one new user workflow, or both UI and synchronization changes without an existing analogue.
- A packet is not complete when the code merely compiles; its stated behavior check and failure state must also pass.
- A packet may be skipped only with a written reason and an explicit note that no later packet depends on its output.

### 5.5 — Team handoff template
- **Packet completed:** ID and title.
- **Changed files:** exact paths.
- **Behavior delivered:** one or two sentences.
- **Validation:** command/check and result.
- **Known limitations:** explicit, including unavailable tooling or unverified platforms.
- **Data/rules impact:** migrations, collections, indexes, permissions, or none.
- **Next packet:** one ID only, with its prerequisite confirmed.

## 6. How to run one small packet

For each packet, give the implementer only one packet ID, for example `1.4 — Tooth selection and detail sheet`. The implementer should:

1. Reconfirm the current repository state and read the nearest existing analogue.
2. State the files it expects to touch before editing.
3. Implement only that packet and any strictly necessary compile fix.
4. Run the packet’s check immediately.
5. Report changed files, test result, assumptions, and the next packet.
6. Append a short handoff note below this section.

Do not combine packets merely because they touch the same feature. Combining is allowed only when a packet cannot compile or be tested independently and the dependency is stated explicitly.

## 7. Handoff notes for the next account
Each phase's session should reconfirm current repo state (it may have shifted since this doc was written), implement only its phase, and append a short "what changed / what's still open" note at the bottom of this file before handing off. If a later phase needs something an earlier one didn't define, that's a flag to raise — not something to quietly patch around.
