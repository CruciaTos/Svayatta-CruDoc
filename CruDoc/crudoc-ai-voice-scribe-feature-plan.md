# CruDoc — AI Voice Scribe — Implementation Plan

Repo audited: `CruciaTos/Svayatta-CruDoc` (fetched directly via the GitHub API — not from memory).
Scope: record the doctor–patient conversation during a visit, transcribe it, extract a structured clinical note (chief complaint, symptoms, diagnosis suggestions, medicines, advice), and let the doctor review-and-confirm it into the patient's record. "Fill out the form" below means: the existing `Patient.diagnosis` / `Patient.notes` fields, plus a new structured consultation-note record — there's no single existing "form" this maps onto 1:1, see §0.4.

---

## 0. Blunt findings before any of this gets built

1. **Voice input in this app is entirely fake today.** `chatbot/widgets/voice_input_modal.dart` has a method literally named `_startListeningSimulation()`, a canned list of pretend transcriptions, and a comment reading "Simulate realistic voice speech recognition transcription." There is no microphone capture anywhere in the codebase — `pubspec.yaml` has no `record`, `speech_to_text`, `flutter_sound`, or `permission_handler`. This feature isn't "wire up the existing voice input to a new destination," it's building real audio capture from zero.
2. **`chatbot_service.dart`'s Gemini integration is the wrong pattern to copy.** It calls the raw REST endpoint directly from the Flutter client (`chatbot_service.dart:32-33`) with `_apiKey = 'YOUR_GEMINI_API_KEY'` — a placeholder that, if ever filled in with a real key, ships inside the Android/iOS/Windows binary for anyone to extract. It also targets `gemini-2.0-flash`, a model generation Google has been actively retiring. The correct pattern is already sitting in this repo, unused: `.claude/skills/firebase-ai-logic-basics/` documents the `firebase_ai` client SDK (`FirebaseAI.googleAI(auth: FirebaseAuth.instance)`), which authenticates via Firebase Auth instead of an embedded key. This plan uses that, not the chatbot's approach.
3. **`ai_assistant` already exists as a feature module and already promises this exact feature.** `feature_management_provider.dart:204-214` describes it as *"AI-powered clinical notes summarization, diagnosis suggestions, and LLM chat interface across patient records"* — gated to the `clinic` and `enterprise` plans (`enums.dart:164-192`), already in `DoctorFeatureGuard.defaultModules` (`doctor_feature_guard.dart:14`). This feature should hook into that flag rather than invent a new one — see §9.
4. **`medical_records` is already a scoped Firestore subcollection with nothing built on it.** `firestore_super_admin.rules:75-77` defines `match /medical_records/{recordId} { allow read, write: if isDoctor(userId); }`, sibling to `patients` and `revenue`. There is no corresponding Dart model, service, or repo anywhere in `lib/` — grepped the full tree, zero hits for "medical_record," "consultation," "transcript," or "scribe." It was rules-first and never built on. This is the natural home for the scribe's output (§7).
5. **`Visit` already has placeholder fields for exactly this.** `visits_model.dart:172-182` carries `treatmentType` and `therapistNotes`, both nullable and unused, under a comment reading *"so invoicing, packages, treatment tracking, therapist notes, reminders, and calendar sync can be wired up later without a schema migration."* This is a second natural attachment point, at the per-visit level rather than the whole-patient level (§8).
6. **`firestore.rules` — the file `firebase deploy` actually reads — is still the wide-open default, and it's now further expired than when this was last flagged.** It's `allow read, write: if request.time < timestamp.date(2026, 8, 7)` (`firestore.rules:12`). Today is August 17, 2026 — ten days past that date. If this is the ruleset actually deployed, every Firestore read/write in the app, including whatever this feature adds, is currently being denied. Not new to this feature, but it blocks it just as much as it blocks everything else, so it's listed here again rather than assumed already fixed.
7. **Firebase App Check becomes mandatory for Firebase AI Logic on November 2, 2026** — confirmed directly from Firebase's current docs, not from training data (this postdates most model knowledge). That's about 11 weeks out from today. App Check isn't optional hardening for this feature, it's a hard dependency with a real deadline — see §5.
8. **Recording a patient's conversation with their doctor is a different category of thing than typing a note, and needs a policy decision before it needs code.** Storing audio of a clinical conversation is more sensitive than the message logs or invoices this app already handles, and in most places doing so requires the patient's knowledge/consent at minimum. This needs an explicit answer from whoever owns clinical/compliance decisions for the practice before this ships — not something to default silently in code. Flagging as a hard blocker on the *recording* specifically, the same way the messaging plan flagged DLT registration as a hard blocker on SMS specifically (§12).
9. **Not directly relevant, but worth knowing:** this repo already runs a second, unrelated voice system — `voice-receptionist/` is a standalone Python service (Pipecat + Twilio + **Sarvam AI** for STT/TTS + Gemini for the LLM) that answers phone calls and books appointments. Different scope entirely (phone triage, not in-person consultation capture), but it establishes that this team already has a Sarvam AI account and has already chosen Sarvam specifically for Hindi/English speech — relevant to the transcription-engine decision in §12.

---

## 1. Scope for v1 (assumptions — flag if wrong)

- **In scope:** a "Start Scribe" action from the existing visit screen (`VisitDetailsPage`, `visit_details.dart`). Doctor records the consultation; on stop, the audio is transcribed and analyzed into a structured draft (chief complaint, symptoms, diagnosis suggestions, medicines mentioned, advice/follow-up); the doctor sees an **editable** draft and must explicitly confirm before anything is saved; confirming appends the diagnosis into `Patient.diagnosis`, a summary into `Patient.notes`, and saves the full structured note as a new record linked to the visit and patient.
- **Out of scope (call out if actually needed):** live/real-time transcription while the doctor is talking (Gemini's Live API exists but is preview-only and adds real architectural cost — v1 is record-then-process, not streaming); speaker diarization (labeling which parts were the doctor vs. the patient) — treated as a single transcript, which is enough for a clinical note but not a legal-grade record; auto-populating the `prescription_generator` module (itself a separate, not-yet-built, `clinic`+ feature) — medicines mentioned stay as descriptive text inside the note for v1; multi-language UI — the *audio* can be Hindi/English mixed, the app UI stays English.
- **Hard requirement, not a default that can quietly change:** nothing is written to `Patient` or `Visit` until the doctor has looked at the draft and tapped Confirm. No field auto-populates silently. This isn't a style choice — an AI-suggested diagnosis is exactly the kind of output that must never reach a patient record without a clinician looking at it first.

---

## 2. Architecture overview

```
┌──────────────────────────────────────────────────────────────────────┐
│ VisitDetailsPage (existing screen — visit_details.dart)              │
│   + new "Start Scribe" action, gated on 'ai_assistant' module (§9)   │
└───────────────────────────────┬────────────────────────────────────┘
                                 ▼
                    ScribeRecordingSheet
              (mic capture via `record` package,
               writes audio to local app storage)
                                 │ on stop
                                 ▼
                    ScribeProcessingService
        ┌───────────────────────┴───────────────────────┐
        │ online: send now                                │ offline: queue locally
        ▼                                                  ▼
FirebaseAI.googleAI(auth: FirebaseAuth.instance)   local queue (sqflite),
  .generativeModel(model: <current Flash model,     retried by
   via Remote Config — never hardcoded, see §5>)     connectivity_plus listener
  .generateContent([audio inline or GCS URI,         (already a dependency)
                     structured-output JSON schema])            │
        │                                                        │
        └───────────────────────┬────────────────────────────────┘
                                 ▼
                    ScribeDraftReviewScreen
          (every field editable — chief complaint, symptoms,
           diagnosis suggestions, medicines, advice, vitals)
                                 │ doctor taps Confirm
                                 ▼
                    ConsultationNoteRepository
        ┌────────────────────────┼────────────────────────┐
        ▼                        ▼                          ▼
 local sqflite table     users/{doctorId}/           PatientRepository
 `consultation_notes`    medical_records/{id}         .updatePatient()
 (offline-first,         (Firestore — rule            → merges diagnosis,
  mirrors patients/      already exists, §0.4/§7)       appends to notes
  visits pattern)                                     VisitRepository
                                                        → sets therapistNotes
```

Why record-then-process instead of streaming: the Live API (for real-time bidirectional audio) is explicitly Preview-only per Firebase's own docs — no SLA, can change in backwards-incompatible ways. Building a clinical feature on a preview API is a bigger bet than this plan wants to make for v1. Batch processing after the visit also matches how a doctor actually works — reviewing and correcting a draft after the conversation, not fighting with a live transcript popping up mid-consultation.

---

## 3. New dependencies

```yaml
dependencies:
  # ... existing ...
  firebase_ai: ^3.0.0   # NOT firebase_vertexai — that's the old/renamed package.
  record: ^6.0.0        # mic capture. Confirmed to support Android, iOS, AND
                         # Windows (via record_windows, MediaFoundation — no
                         # gap like the google_sign_in/Windows one flagged in
                         # the messaging plan). Its own hasPermission()/
                         # start() handle the OS permission prompt, so
                         # permission_handler is NOT needed as a separate dep.
```

That's it — deliberately not adding a second STT SDK (see §12 open decision #1 before assuming this list is final), not adding `googleapis` for the same "too heavy for one endpoint" reasoning the messaging plan used for Gmail.

---

## 4. Recording flow & platform notes

- `record`'s `AudioRecorder.hasPermission()` triggers the native mic-permission prompt on Android/iOS; Windows doesn't require a runtime prompt the same way but does need the mic capability declared.
- Recommended format: AAC/M4A at a modest bitrate — good enough for speech transcription, keeps file size manageable. A ~15-minute consultation at a speech-appropriate bitrate lands comfortably under Gemini's ~20MB inline-data ceiling; a longer one (home visits can run long — see `kMaxVisitDurationMinutes = 480` in `visits_model.dart:15`) will not. Don't assume every consultation is short: route through Cloud Storage for Firebase + pass the file's URL to Gemini as the default path, not an edge case, per the skill's own guidance for anything over the inline limit.
- Audio is written to local device storage the moment recording stops, before any network call — this is what makes the offline path in §10 possible at all.

---

## 5. Gemini call design

- Use `FirebaseAI.googleAI(auth: FirebaseAuth.instance).generativeModel(...)` — not a raw REST call with an embedded key like `chatbot_service.dart` does today. This also means App Check has to be set up (§0.7) — required for AI Logic from Nov 2, 2026 regardless, so treat it as in-scope for this feature rather than a future task.
- **Model name:** don't hardcode a specific string (the bundled skill explicitly warns against this, and the messaging plan's own experience with `gemini-2.0-flash` going stale in `chatbot_service.dart` is a live example of why). Pull it from Firebase Remote Config, defaulting to whatever the current Flash-tier model is per Firebase's models doc at build time (Gemini 3.x Flash family as of this writing) — cheap enough for per-consultation volume, multimodal audio input is supported.
- **Structured output:** request a JSON schema response rather than free text, so the draft screen has real fields to populate instead of parsing prose. Rough shape:
  ```json
  {
    "chiefComplaint": "string",
    "symptoms": ["string"],
    "diagnosisSuggestions": ["string"],
    "medicines": [{"name": "string", "dosage": "string", "instructions": "string"}],
    "advice": "string",
    "followUpDate": "string | null",
    "vitalsIfMentioned": {"bp": "string | null", "temp": "string | null", "pulse": "string | null"},
    "transcriptSummaryConfidenceNote": "string"
  }
  ```
- **System prompt must instruct the model to only extract what was actually said** — never infer a diagnosis the doctor didn't state, never fill a field with a plausible-sounding guess, and to leave a field empty/null rather than fabricate. This matters more here than in the chatbot use case: a hallucinated symptom in a chat reply is an annoyance, a hallucinated one in a patient's chart is a clinical-safety issue. Pair this with the §1 hard requirement that a doctor must confirm before anything saves — the prompt discipline and the human-in-the-loop step are both needed, neither replaces the other.

---

## 6. Data model sketch

Hand-rolled to match `Patient`/`Visit`'s existing style (no freezed/json_serializable):

```dart
// data/models/consultation_note.dart
enum ConsultationNoteStatus { draft, confirmed, discarded }

class ConsultationNote {
  final String id;
  final String doctorId;
  final String patientId;
  final String visitId;

  final String transcript;
  final String chiefComplaint;
  final List<String> symptoms;
  final List<String> diagnosisSuggestions;
  final List<Medicine> medicines;          // {name, dosage, instructions}
  final String advice;
  final DateTime? followUpDate;
  final Map<String, String?> vitals;       // bp/temp/pulse, only if mentioned

  final bool consentGiven;
  final DateTime? consentAt;

  /// Null once the raw audio is deleted per retention policy (§12.2) —
  /// the structured note and transcript can outlive the audio itself.
  final String? audioStoragePath;

  final ConsultationNoteStatus status;
  final DateTime createdAt;
  final DateTime? confirmedAt;
}
```

---

## 7. Storage: Firestore + local + encryption

- **Firestore:** `users/{doctorId}/medical_records/{recordId}` — reuses the rule that already exists (`firestore_super_admin.rules:75-77`), sibling to `patients`/`visits`/`revenue`, so nothing new needs writing there. (The §0.6 blocker about the *actually-deployed* `firestore.rules` still applies to this collection like every other one — confirm which ruleset is really live before assuming this write path works.)
- **Local:** new `consultation_notes` sqflite table, following the existing naming convention (`patients`, `visits`, `revenue_entries`, `medicines`, `email_log` — see `local_database_service.dart:308-483`), offline-first like the rest of the app.
- **Encryption:** `transcript`, `chiefComplaint`, `symptoms`, `diagnosisSuggestions`, `advice`, and `medicines` are all free-text PHI and should go through `FieldCipher` (`field_cipher.dart`) exactly like `Patient.notes` and `Patient.diagnosis` already do — this feature shouldn't introduce a second, inconsistent way of protecting clinical text.
- **Raw audio**, if retained at all (§12.2), goes to Firebase Storage under a path scoped to `doctorId`/`patientId` — never inline in Firestore or the local DB. It's a materially more sensitive artifact than the message logs the existing `firestore_super_admin.rules` already protects, so its storage rules need their own explicit review, not an assumption that the `medical_records` document rule covers it.

---

## 8. Patient / Visit auto-fill wiring

- On Confirm: merge `diagnosisSuggestions` into `Patient.diagnosis` — dedupe against what's already there, cap at `Patient.maxDiagnoses` (4, per `patient.dart:39`), and if the merge would overflow that cap, put the overflow into `Patient.notes` instead of silently dropping it. Written through the existing `PatientRepository.updatePatient()` (`patient_repository.dart:137`) — no new patient-write path needed.
- A summary (chief complaint + advice) gets appended via the same repository, following the pattern `updateDoctorsNote(patientId, note)` already uses (`patient_repository.dart:169`).
- At the visit level, the confirmed note's advice/plan populates `Visit.therapistNotes`, and `treatmentType` if it can be inferred — using fields that were explicitly reserved for this (`visits_model.dart:178-181`), so no schema migration is needed on `Visit` either.
- Repeating from §1 because it's the most important constraint in this whole plan: **all of the above only happens after the doctor taps Confirm on the draft.** Nothing in this section runs automatically off the raw model output.

---

## 9. Feature gating

Hooks into the module key that already exists rather than adding a new one:

- `DoctorFeatureGuard.defaultModules` already includes `'ai_assistant'` (`doctor_feature_guard.dart:14`).
- `SubscriptionPlan.includedModules` already gates it to `clinic` and `enterprise` (`enums.dart:174`, `:189`).
- `feature_management_provider.dart:204-214`'s existing description for `aiAssistant` already matches this feature almost word-for-word — worth confirming with whoever owns the super-admin panel that this *is* what that description was written for, rather than assuming.

Separate, pre-existing issue that doesn't block this specifically (the entry point here lives inside `VisitDetailsPage`, not a new side-nav tab) but is worth knowing about: the messaging plan already flagged that `DoctorFeatureGuard.getModuleKeyForTab()`'s tab-index mapping is off-by-one against `DesktopShell`'s actual tab order. Still unresolved as far as this audit could tell — doesn't affect this feature's gating today, but would if a dedicated "Scribe" tab is ever added later.

---

## 10. Error handling / edge cases

- **Offline at the time of recording** — this needs a genuinely different answer than the messaging plan's "show an offline state, don't queue." A failed email can just be re-sent later with no real cost. A consultation the doctor already conducted can't be un-had — the audio has to be captured and preserved locally regardless of connectivity (§4 already does this), queued, and processed automatically once connectivity returns, with the doctor notified that a draft is ready for review. Home visits especially (`home_visits` module, `Visit.visitType == VisitType.home`) are the realistic case where this triggers.
- **Malformed/partial JSON from the model:** retry once with a stricter re-prompt; if it still fails, fall back to showing the raw transcript with all structured fields empty, so the doctor can fill them by hand rather than losing the recording's value entirely.
- **Silence or a too-short recording:** detect before calling the model at all (don't spend an API call on dead air) and prompt the doctor to re-record.
- **Draft never confirmed:** auto-discard the raw audio after a set number of days even if the doctor never opens the review screen — unreviewed PHI shouldn't sit indefinitely just because nobody acted on it. (The transcript/structured guess can be discarded on the same timer, or kept — depends on §12.2's retention answer.)
- **Diagnosis list overflow beyond the 4-item cap:** as in §8, dedupe, cap, and put the overflow in notes — never a silent drop.

---

## 11. Testing

Matching the existing low-ceremony baseline (`test/widget_test.dart` is still the default counter test; `mocktail` is already a dev dependency per `pubspec.yaml`, same as the messaging plan assumed):

- `ScribeProcessingService`: mock the `firebase_ai` call, assert the JSON-schema request shape and that malformed/partial responses are handled per §10, not just the happy path.
- `ConsultationNoteRepository`: test the confirm → local-save → Firestore-sync → Patient/Visit-update chain with fakes, in the same isolated-unit style as the existing `doctor_encryption_service_test.dart`-style tests.
- Explicitly **not** testing real microphone capture or actual transcription quality in CI — no practical way to do that without a real device and real audio. Worth a manual test checklist item (record a real consultation-length sample, confirm the draft looks right, confirm Windows recording actually works) instead.

---

## 12. Suggested build order

1. **Resolve the two non-technical blockers first** — confirm which Firestore ruleset is actually deployed (§0.6), and get a real answer on consent/retention from whoever owns clinical/compliance decisions (§0.8). Both block trusting anything built after them.
2. **Firebase AI Logic backend provisioning + App Check setup** (`firebase-tools init ailogic`, per the bundled skill) — needed before Nov 2, 2026 regardless of this feature, so do it now rather than treating it as optional hardening.
3. **Audio capture standalone** — verify `record` actually works on Android, iOS, and Windows before touching any UI.
4. **Gemini structured-output call** — verify against a handful of real sample consultation recordings via a throwaway script, the same way the messaging plan verified a real email/SMS before wiring the client.
5. **Data layer** — `ConsultationNote` model, local table, `FieldCipher` wiring (§6–7; the Firestore rule already exists, nothing to add there).
6. **Draft review UI** — every field editable, since the doctor must always be able to correct anything before Confirm.
7. **Wire into `VisitDetailsPage`** + the `Patient`/`Visit` auto-fill from §8.
8. **Feature-flag verification** — confirm a `starter`/`professional` doctor doesn't see it, `clinic`+ does.
9. **Offline queue + retry** — last, once the online happy path is solid.

---

## Open decisions needed before coding starts

1. **Gemini's native multimodal audio input, or Sarvam STT feeding text into Gemini?** Gemini-direct is simpler (one vendor, no server hop, matches the bundled skill's guidance). Sarvam is already used elsewhere in this repo (`voice-receptionist/`) specifically because it's tuned for Hindi/English code-switching, which is realistic for an Indian clinic floor — worth a real accuracy comparison on actual recorded samples before picking, not a default.
2. **Retention:** keep raw audio permanently, for a limited window, or delete immediately once the doctor confirms the draft? Changes the Storage rules design and the compliance story from §0.8 — needs an answer, not an assumption.
3. **Consent mechanic:** a verbal on-recording disclosure, or an explicit in-app checkbox/toggle captured before the mic starts? Either way, the consent event itself likely needs to be its own stored, auditable field (`consentGiven`/`consentAt` in §6 assumes this) rather than just a UI-only gate that leaves no record.
4. **When a new note's diagnosis suggestions overlap or conflict with what's already on `Patient.diagnosis` from a prior visit**, should the review screen show the existing list so the doctor edits one unified set, or does confirming always append as new entries (subject to the §8 dedupe/cap)? Affects how the review screen is actually laid out.
5. **Do medicines mentioned in a confirmed note stay purely descriptive for v1**, or is there an expectation they'll feed the not-yet-built `prescription_generator` module later? Doesn't block v1 either way, but changes whether the `Medicine` model in §6 should be designed with that reuse in mind now.
