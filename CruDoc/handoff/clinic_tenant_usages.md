# Clinic Tenant Usages Analysis (Task T8)

## Claude's review (GATE 3, 2026-10-07) — follow this in T9

**UNSURE rows decided**
- `clinic_session.dart:37` (`tenantId` itself): leave as is.
- `web_dashboard_view.dart:3220` (`doctorUid` on the invoice): **USER** — who made it. Leave.
- `messaging_repository.dart:45–46, 55, 208, 215`: **USER** — the email goes out from
  the person's own Gmail and the email log is theirs. Leave the whole file unchanged
  (this overrides the TENANT label on the getter at 45–46).

**Corrections**
- `access_audit_service.dart:64`: split it — `'doctorId': ClinicSession.instance.tenantId`,
  `'actorUid': uid` (the signed-in user). Skip logging if either is null.
- **Missed by the T8 search (it only matched `currentUser`), TENANT — change these too:**
  - `lib/features/patients/data/providers/patient_providers.dart:24–27`:
    `loadForDoctor(user.uid)` → the tenant id.
  - `lib/features/patients/data/repo/patient_repository.dart:193–297`:
    every `loadForDoctor(user.uid)` and `.where('doctorId', isEqualTo: user.uid)`
    (lines ~195, 212, 248, 255, 293, 297) → the tenant id.
- Missed and **USER** (leave): `feature_usage_service.dart:26`, `doctor_profile_helper.dart:77,150`,
  `auth_screen.dart` (profile and device sessions), `loyalty_card.dart`, `onboarding_flow.dart:199`,
  `desktop_invoices_screen.dart:1233` and `invoices_screen.dart:1041` (the doctor's name on the
  invoice), `web_dashboard_view.dart:129–259` (profile), `profile_screen.dart:409`,
  `desktop_settings_screen.dart:1217` (devices), `doctor_subscription_service.dart:62`,
  `post_campaign_modal.dart:178`.
- After T9's edits, run `grep -rnE "\b(user|u)\??!?\.uid\b|currentUser(\?|!)?\.uid" lib --include=*.dart`
  and check that no TENANT use is left.

Everything else: as classified in the table below.

---


This document inventories every occurrence of `currentUser.uid`, `_currentDoctorId`, and `_signedInDoctorId` in `lib/**/*.dart`.

Classification rules from brief:
- **TENANT**: written to or filtered on a `doctorId` field (Firestore or SQLite), used in `doctors/$x/` storage path, doc id of `doctor_keys`, `doctor_settings`, `feature_flags`, `whatsapp_connections`, `clinics`, or passed to `EncryptionKeyManager.loadForDoctor`, `LocalDatabaseService.ensureLocalDataMatchesSignedInDoctor`, `_databaseFileNameForDoctor`, `FirestoreSyncService`, `StorageSyncQueue`, `AccessAuditService` (`doctorId` field).
- **USER**: `users/$x` or subcollections (`active_sessions`, `medical_records`, `campaigns`, `recipients`, `feature_usage`), `actorUid`, `voice-scratch/doctors/$x`, `subscriptions`, `payment_transactions`, `upgrade_requests`, `support_tickets`, `notifications`, `DeviceSessionService`, profile/greeting (`DoctorProfileHelper`), Gmail integration.
- **UNSURE**: usages where context is ambiguous or dual-purpose.

| File : Line | Code | Classification | Why |
|---|---|---|---|
| lib/core/clinic/clinic_session.dart:37 | `String? get tenantId => access?.clinicId ?? FirebaseAuth.instance.currentUser?.uid;` | **UNSURE** | ClinicSession tenantId definition fallback to current auth user UID in solo practice. |
| lib/core/clinic/clinic_session.dart:224 | `final uid = _lastLoadedUid ?? FirebaseAuth.instance.currentUser?.uid;` | **USER** | Current auth user UID used to re-run load() on reload(). |
| lib/core/pdf/services/generated_document_sync.dart:40 | `final doctorId = FirebaseAuth.instance.currentUser?.uid;` | **TENANT** | Storage path doctors/$x/ and SQLite generated_documents document prefix. |
| lib/core/pdf/services/generated_document_sync.dart:71 | `final doctorId = FirebaseAuth.instance.currentUser?.uid;` | **TENANT** | Storage path doctors/$x/ and SQLite generated_documents document prefix. |
| lib/core/providers/specialty_provider.dart:58 | `.doc(currentUser.uid);` | **USER** | Specialty and dentalFeatures are per-user in users/{uid}. |
| lib/core/providers/specialty_provider.dart:62 | `currentUser.uid,` | **USER** | Specialty and dentalFeatures are per-user in users/{uid}. |
| lib/core/providers/specialty_provider.dart:206 | `.doc(currentUser.uid);` | **USER** | Specialty and dentalFeatures are per-user in users/{uid}. |
| lib/core/services/access_audit_service.dart:64 | `final uid = FirebaseAuth.instance.currentUser?.uid;` | **TENANT** | doctorId field in access_logs (also currently used for actorUid). |
| lib/core/services/firestore_sync_service.dart:94 | `final doctorId = _currentDoctorId;` | **TENANT** | Passed to FirestoreSyncService for tenant doctorId collection sync. |
| lib/core/services/firestore_sync_service.dart:202 | `String? get _currentDoctorId => FirebaseAuth.instance.currentUser?.uid;` | **TENANT** | Passed to FirestoreSyncService for tenant doctorId collection sync. |
| lib/core/services/firestore_sync_service.dart:206 | `final doctorId = _currentDoctorId;` | **TENANT** | Passed to FirestoreSyncService for tenant doctorId collection sync. |
| lib/core/services/initial_firestore_migration_service.dart:39 | `final doctorId = FirebaseAuth.instance.currentUser?.uid;` | **TENANT** | Passed to ensureLocalDataMatchesSignedInDoctor and migrates collections by doctorId. |
| lib/core/services/local_database_service.dart:57 | `FirebaseAuth.instance.currentUser?.uid ?? 'signed_out';` | **TENANT** | Passed to _databaseFileNameForDoctor for local database filename. |
| lib/core/services/medical_storage_service.dart:475 | `final uid = FirebaseAuth.instance.currentUser?.uid;` | **TENANT** | Verified against doctorId in _requireSignedInAs for doctors/$x/ paths. |
| lib/core/services/storage_sync_queue.dart:154 | `_currentDoctorId = currentDoctorId ?? _signedInDoctorId,` | **TENANT** | Storage queue tenant identifier for doctor scoped storage operations under doctors/$x/ and SQLite queue filtering. |
| lib/core/services/storage_sync_queue.dart:184 | `final String? Function() _currentDoctorId;` | **TENANT** | Storage queue tenant identifier for doctor scoped storage operations under doctors/$x/ and SQLite queue filtering. |
| lib/core/services/storage_sync_queue.dart:280 | `final doctorId = _currentDoctorId();` | **TENANT** | Storage queue tenant identifier for doctor scoped storage operations under doctors/$x/ and SQLite queue filtering. |
| lib/core/services/storage_sync_queue.dart:394 | `final doctorId = _currentDoctorId();` | **TENANT** | Storage queue tenant identifier for doctor scoped storage operations under doctors/$x/ and SQLite queue filtering. |
| lib/core/services/storage_sync_queue.dart:427 | `final doctorId = _currentDoctorId();` | **TENANT** | Storage queue tenant identifier for doctor scoped storage operations under doctors/$x/ and SQLite queue filtering. |
| lib/core/services/storage_sync_queue.dart:436 | `final doctorId = _currentDoctorId();` | **TENANT** | Storage queue tenant identifier for doctor scoped storage operations under doctors/$x/ and SQLite queue filtering. |
| lib/core/services/storage_sync_queue.dart:453 | `final doctorId = _currentDoctorId();` | **TENANT** | Storage queue tenant identifier for doctor scoped storage operations under doctors/$x/ and SQLite queue filtering. |
| lib/core/services/storage_sync_queue.dart:485 | `final doctorId = _currentDoctorId();` | **TENANT** | Storage queue tenant identifier for doctor scoped storage operations under doctors/$x/ and SQLite queue filtering. |
| lib/core/services/storage_sync_queue.dart:504 | `if (_currentDoctorId() != doctorId) break;` | **TENANT** | Storage queue tenant identifier for doctor scoped storage operations under doctors/$x/ and SQLite queue filtering. |
| lib/core/services/storage_sync_queue.dart:712 | `static String? _signedInDoctorId() {` | **TENANT** | Storage queue tenant identifier for doctor scoped storage operations under doctors/$x/ and SQLite queue filtering. |
| lib/core/services/storage_sync_queue.dart:714 | `final uid = FirebaseAuth.instance.currentUser?.uid;` | **TENANT** | Storage queue tenant identifier for doctor scoped storage operations under doctors/$x/ and SQLite queue filtering. |
| lib/core/utils/doctor_feature_guard.dart:44 | `.doc(currentUser.uid)` | **USER** | Reads users/{uid} for account enabled modules (T15 branches non-owners to clinics/{tenantId}). |
| lib/core/utils/doctor_profile_helper.dart:26 | `.doc(currentUser.uid);` | **USER** | Doctor profile and greetings are stored under users/{uid}. |
| lib/core/utils/doctor_profile_helper.dart:193 | `currentUser.uid,` | **USER** | Doctor profile and greetings are stored under users/{uid}. |
| lib/core/utils/doctor_profile_helper.dart:197 | `currentUser.uid,` | **USER** | Doctor profile and greetings are stored under users/{uid}. |
| lib/core/utils/doctor_profile_helper.dart:202 | `.doc(currentUser.uid);` | **USER** | Doctor profile and greetings are stored under users/{uid}. |
| lib/core/utils/doctor_profile_helper.dart:236 | `.doc(currentUser.uid);` | **USER** | Doctor profile and greetings are stored under users/{uid}. |
| lib/features/appointments/data/repo/visits_repo.dart:62 | `String get _currentDoctorId {` | **TENANT** | doctorId field in appointments and visitations collections. |
| lib/features/appointments/data/repo/visits_repo.dart:63 | `final uid = FirebaseAuth.instance.currentUser?.uid;` | **TENANT** | doctorId field in appointments and visitations collections. |
| lib/features/appointments/data/repo/visits_repo.dart:97 | `final doctorId = _currentDoctorId;` | **TENANT** | doctorId field in appointments and visitations collections. |
| lib/features/appointments/data/repo/visits_repo.dart:226 | `doctorId: _currentDoctorId,` | **TENANT** | doctorId field in appointments and visitations collections. |
| lib/features/auth/presentation/auth_screen.dart:590 | `await DeviceSessionService.instance.registerNewSession(currentUser.uid);` | **USER** | Passed to DeviceSessionService.registerNewSession under users/{uid}/active_sessions. |
| lib/features/campaigns/data/repo/campaign_repository.dart:20 | `String get _currentDoctorId {` | **USER** | Campaigns and recipients subcollections are owned per-user under users/{uid}. |
| lib/features/campaigns/data/repo/campaign_repository.dart:21 | `return _auth.currentUser?.uid ?? 'anonymous';` | **USER** | Campaigns and recipients subcollections are owned per-user under users/{uid}. |
| lib/features/campaigns/data/repo/campaign_repository.dart:39 | `: _currentDoctorId;` | **USER** | Campaigns and recipients subcollections are owned per-user under users/{uid}. |
| lib/features/campaigns/data/repo/campaign_repository.dart:54 | `: _currentDoctorId;` | **USER** | Campaigns and recipients subcollections are owned per-user under users/{uid}. |
| lib/features/campaigns/data/repo/campaign_repository.dart:80 | `final doctorId = doctorIdOverride ?? _currentDoctorId;` | **USER** | Campaigns and recipients subcollections are owned per-user under users/{uid}. |
| lib/features/campaigns/data/services/campaign_dispatch_service.dart:496 | `final currentDoctorId = FirebaseAuth.instance.currentUser?.uid;` | **USER** | Campaigns and recipients subcollections are owned per-user under users/{uid}. |
| lib/features/campaigns/presentation/desktop_campaigns_screen.dart:47 | `String get _currentDoctorId =>` | **USER** | Campaigns and recipients subcollections are owned per-user under users/{uid}. |
| lib/features/campaigns/presentation/desktop_campaigns_screen.dart:48 | `FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';` | **USER** | Campaigns and recipients subcollections are owned per-user under users/{uid}. |
| lib/features/campaigns/presentation/desktop_campaigns_screen.dart:72 | `_currentDoctorId,` | **USER** | Campaigns and recipients subcollections are owned per-user under users/{uid}. |
| lib/features/campaigns/presentation/mobile_campaigns_screen.dart:29 | `String get _currentDoctorId =>` | **USER** | Campaigns and recipients subcollections are owned per-user under users/{uid}. |
| lib/features/campaigns/presentation/mobile_campaigns_screen.dart:30 | `FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';` | **USER** | Campaigns and recipients subcollections are owned per-user under users/{uid}. |
| lib/features/campaigns/presentation/mobile_campaigns_screen.dart:91 | `_currentDoctorId,` | **USER** | Campaigns and recipients subcollections are owned per-user under users/{uid}. |
| lib/features/campaigns/presentation/mobile_post_campaign_sheet.dart:1226 | `final doctorId = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';` | **USER** | Campaigns and recipients subcollections are owned per-user under users/{uid}. |
| lib/features/dashboard/presentation/web_dashboard_view.dart:1618 | `final currentDoctorId = FirebaseAuth.instance.currentUser?.uid ?? '';` | **TENANT** | Filters invoices collection where doctorId == currentDoctorId. |
| lib/features/dashboard/presentation/web_dashboard_view.dart:3220 | `FirebaseAuth.instance.currentUser?.uid ??` | **UNSURE** | Written to doctorUid field in clinical invoice (could be creator/attending doctor UID or tenant doctorId). |
| lib/features/dashboard/presentation/web_dashboard_view.dart:3231 | `FirebaseAuth.instance.currentUser?.uid ??` | **TENANT** | Written to doctorId field in invoices collection. |
| lib/features/dental/presentation/dental_patient_details_screen.dart:55 | `String get _currentDoctorId =>` | **TENANT** | Clinical dental records are scoped to clinic/tenant doctorId. |
| lib/features/dental/presentation/dental_patient_details_screen.dart:56 | `FirebaseAuth.instance.currentUser?.uid ?? 'doc_dental';` | **TENANT** | Clinical dental records are scoped to clinic/tenant doctorId. |
| lib/features/dental/presentation/dental_patient_details_screen.dart:729 | `doctorId: _currentDoctorId,` | **TENANT** | Clinical dental records are scoped to clinic/tenant doctorId. |
| lib/features/dental/presentation/dental_procedure_catalog_screen.dart:26 | `String get _currentDoctorId =>` | **TENANT** | Procedure catalog is scoped to the clinic/tenant doctorId. |
| lib/features/dental/presentation/dental_procedure_catalog_screen.dart:27 | `FirebaseAuth.instance.currentUser?.uid ?? 'doc_dental';` | **TENANT** | Procedure catalog is scoped to the clinic/tenant doctorId. |
| lib/features/dental/presentation/dental_procedure_catalog_screen.dart:166 | `doctorId: _currentDoctorId,` | **TENANT** | Procedure catalog is scoped to the clinic/tenant doctorId. |
| lib/features/dental/presentation/dental_procedure_catalog_screen.dart:180 | `ref.invalidate(dentalCatalogProvider(_currentDoctorId));` | **TENANT** | Procedure catalog is scoped to the clinic/tenant doctorId. |
| lib/features/dental/presentation/dental_procedure_catalog_screen.dart:191 | `ref.invalidate(dentalCatalogProvider(_currentDoctorId));` | **TENANT** | Procedure catalog is scoped to the clinic/tenant doctorId. |
| lib/features/dental/presentation/dental_procedure_catalog_screen.dart:196 | `final count = await DentalCatalogSeed.seedIfNeeded(repo, _currentDoctorId);` | **TENANT** | Procedure catalog is scoped to the clinic/tenant doctorId. |
| lib/features/dental/presentation/dental_procedure_catalog_screen.dart:197 | `ref.invalidate(dentalCatalogProvider(_currentDoctorId));` | **TENANT** | Procedure catalog is scoped to the clinic/tenant doctorId. |
| lib/features/dental/presentation/dental_procedure_catalog_screen.dart:228 | `final rawCatalog = ref.watch(dentalCatalogProvider(_currentDoctorId));` | **TENANT** | Procedure catalog is scoped to the clinic/tenant doctorId. |
| lib/features/dental/presentation/dental_sterilization_screen.dart:26 | `String get _currentDoctorId =>` | **TENANT** | Sterilization log entries are scoped to the clinic/tenant doctorId. |
| lib/features/dental/presentation/dental_sterilization_screen.dart:27 | `FirebaseAuth.instance.currentUser?.uid ?? 'doc_dental';` | **TENANT** | Sterilization log entries are scoped to the clinic/tenant doctorId. |
| lib/features/dental/presentation/dental_sterilization_screen.dart:240 | `doctorId: _currentDoctorId,` | **TENANT** | Sterilization log entries are scoped to the clinic/tenant doctorId. |
| lib/features/dental/presentation/dental_sterilization_screen.dart:252 | `ref.invalidate(sterilizationLogProvider(_currentDoctorId));` | **TENANT** | Sterilization log entries are scoped to the clinic/tenant doctorId. |
| lib/features/dental/presentation/dental_sterilization_screen.dart:267 | `final logsAsync = ref.watch(sterilizationLogProvider(_currentDoctorId));` | **TENANT** | Sterilization log entries are scoped to the clinic/tenant doctorId. |
| lib/features/dental/presentation/providers/dental_desktop_providers.dart:14 | `return user?.uid ?? FirebaseAuth.instance.currentUser?.uid ?? 'doc_dental';` | **TENANT** | Dental providers scoped to the clinic/tenant doctorId. |
| lib/features/dental/presentation/widgets/dental_procedure_log_sheet.dart:53 | `String get _currentDoctorId =>` | **TENANT** | Procedure logs are scoped to the clinic/tenant doctorId. |
| lib/features/dental/presentation/widgets/dental_procedure_log_sheet.dart:54 | `FirebaseAuth.instance.currentUser?.uid ?? 'doc_dental';` | **TENANT** | Procedure logs are scoped to the clinic/tenant doctorId. |
| lib/features/dental/presentation/widgets/dental_procedure_log_sheet.dart:111 | `doctorId: _currentDoctorId,` | **TENANT** | Procedure logs are scoped to the clinic/tenant doctorId. |
| lib/features/dental/presentation/widgets/dental_procedure_log_sheet.dart:154 | `doctorId: _currentDoctorId,` | **TENANT** | Procedure logs are scoped to the clinic/tenant doctorId. |
| lib/features/dental/presentation/widgets/dental_procedure_log_sheet.dart:183 | `final catalogAsync = ref.watch(dentalCatalogProvider(_currentDoctorId));` | **TENANT** | Procedure logs are scoped to the clinic/tenant doctorId. |
| lib/features/dental/presentation/widgets/dental_treatment_plan_sheet.dart:34 | `String get _currentDoctorId =>` | **TENANT** | Treatment plans are scoped to the clinic/tenant doctorId. |
| lib/features/dental/presentation/widgets/dental_treatment_plan_sheet.dart:35 | `FirebaseAuth.instance.currentUser?.uid ?? 'doc_dental';` | **TENANT** | Treatment plans are scoped to the clinic/tenant doctorId. |
| lib/features/dental/presentation/widgets/dental_treatment_plan_sheet.dart:38 | `final catalogAsync = ref.read(dentalCatalogProvider(_currentDoctorId));` | **TENANT** | Treatment plans are scoped to the clinic/tenant doctorId. |
| lib/features/dental/presentation/widgets/dental_treatment_plan_sheet.dart:174 | `doctorId: _currentDoctorId,` | **TENANT** | Treatment plans are scoped to the clinic/tenant doctorId. |
| lib/features/dental/presentation/widgets/dental_treatment_plan_sheet.dart:287 | `doctorId: _currentDoctorId,` | **TENANT** | Treatment plans are scoped to the clinic/tenant doctorId. |
| lib/features/homeopathy/data/repo/homeopathy_repository.dart:22 | `String get _currentDoctorId {` | **TENANT** | doctorId field in homeopathy_case_sheets (Firestore and SQLite). |
| lib/features/homeopathy/data/repo/homeopathy_repository.dart:23 | `final uid = FirebaseAuth.instance.currentUser?.uid;` | **TENANT** | doctorId field in homeopathy_case_sheets (Firestore and SQLite). |
| lib/features/homeopathy/data/repo/homeopathy_repository.dart:140 | `final doctorId = _currentDoctorId;` | **TENANT** | doctorId field in homeopathy_case_sheets (Firestore and SQLite). |
| lib/features/homeopathy/data/repo/homeopathy_repository.dart:194 | `final doctorId = _currentDoctorId;` | **TENANT** | doctorId field in homeopathy_case_sheets (Firestore and SQLite). |
| lib/features/homeopathy/data/services/homeopathy_local_service.dart:28 | `String get _currentDoctorId => FirebaseAuth.instance.currentUser?.uid ?? '';` | **TENANT** | doctorId field in homeopathy_case_sheets (Firestore and SQLite). |
| lib/features/homeopathy/data/services/homeopathy_local_service.dart:70 | `final doctorId = _currentDoctorId;` | **TENANT** | doctorId field in homeopathy_case_sheets (Firestore and SQLite). |
| lib/features/homeopathy/data/services/homeopathy_local_service.dart:89 | `final doctorId = _currentDoctorId;` | **TENANT** | doctorId field in homeopathy_case_sheets (Firestore and SQLite). |
| lib/features/inventory/data/repo/inventory_repository.dart:28 | `String get _currentDoctorId {` | **TENANT** | doctorId field in Firestore medicines and stock_transactions collections. |
| lib/features/inventory/data/repo/inventory_repository.dart:29 | `final uid = FirebaseAuth.instance.currentUser?.uid;` | **TENANT** | doctorId field in Firestore medicines and stock_transactions collections. |
| lib/features/inventory/data/repo/inventory_repository.dart:44 | `doctorId: _currentDoctorId,` | **TENANT** | doctorId field in Firestore medicines and stock_transactions collections. |
| lib/features/inventory/data/repo/inventory_repository.dart:80 | `.where('doctorId', isEqualTo: _currentDoctorId)` | **TENANT** | doctorId field in Firestore medicines and stock_transactions collections. |
| lib/features/inventory/data/repo/inventory_repository.dart:251 | `doctorId: _currentDoctorId,` | **TENANT** | doctorId field in Firestore medicines and stock_transactions collections. |
| lib/features/inventory/data/repo/inventory_repository.dart:276 | `doctorId: _currentDoctorId,` | **TENANT** | doctorId field in Firestore medicines and stock_transactions collections. |
| lib/features/inventory/data/repo/inventory_repository.dart:299 | `.where('doctorId', isEqualTo: _currentDoctorId)` | **TENANT** | doctorId field in Firestore medicines and stock_transactions collections. |
| lib/features/inventory/data/repo/inventory_repository.dart:319 | `.where('doctorId', isEqualTo: _currentDoctorId)` | **TENANT** | doctorId field in Firestore medicines and stock_transactions collections. |
| lib/features/inventory/data/services/inventory_local_service.dart:43 | `String _currentDoctorId() {` | **TENANT** | doctorId field in SQLite medicines and stock_transactions queries and writes. |
| lib/features/inventory/data/services/inventory_local_service.dart:44 | `final uid = FirebaseAuth.instance.currentUser?.uid;` | **TENANT** | doctorId field in SQLite medicines and stock_transactions queries and writes. |
| lib/features/inventory/data/services/inventory_local_service.dart:117 | `whereArgs: [medicineId, _currentDoctorId()],` | **TENANT** | doctorId field in SQLite medicines and stock_transactions queries and writes. |
| lib/features/inventory/data/services/inventory_local_service.dart:134 | `whereArgs: [medicineId, _currentDoctorId()],` | **TENANT** | doctorId field in SQLite medicines and stock_transactions queries and writes. |
| lib/features/inventory/data/services/inventory_local_service.dart:177 | `whereArgs: [transaction.medicineId, _currentDoctorId()],` | **TENANT** | doctorId field in SQLite medicines and stock_transactions queries and writes. |
| lib/features/inventory/data/services/inventory_local_service.dart:223 | `whereArgs: [transaction.medicineId, _currentDoctorId()],` | **TENANT** | doctorId field in SQLite medicines and stock_transactions queries and writes. |
| lib/features/inventory/data/services/inventory_local_service.dart:239 | `whereArgs: [medicineId, _currentDoctorId()],` | **TENANT** | doctorId field in SQLite medicines and stock_transactions queries and writes. |
| lib/features/inventory/data/services/inventory_local_service.dart:267 | `whereArgs: [_currentDoctorId()],` | **TENANT** | doctorId field in SQLite medicines and stock_transactions queries and writes. |
| lib/features/inventory/data/services/inventory_local_service.dart:282 | `whereArgs: [_currentDoctorId()],` | **TENANT** | doctorId field in SQLite medicines and stock_transactions queries and writes. |
| lib/features/messaging/data/providers/reminder_settings_providers.dart:48 | `final uid = FirebaseAuth.instance.currentUser?.uid;` | **USER** | Writes WhatsApp reminders preference directly to users/{uid}. |
| lib/features/messaging/data/repo/messaging_repository.dart:45 | `String get _currentDoctorId {` | **TENANT** | Getter for doctorId used in messaging repository. |
| lib/features/messaging/data/repo/messaging_repository.dart:46 | `final uid = _auth.currentUser?.uid;` | **TENANT** | Getter for doctorId used in messaging repository. |
| lib/features/messaging/data/repo/messaging_repository.dart:55 | `final doctorId = _currentDoctorId;` | **UNSURE** | Used in sendAppointmentConfirmation; references Gmail (per-user) and visit records (tenant). |
| lib/features/messaging/data/repo/messaging_repository.dart:208 | `final doctorId = _currentDoctorId;` | **UNSURE** | Queries SQLite email logs by doctorId. Gmail is per-user, but SQLite log table schema may use doctorId. |
| lib/features/messaging/data/repo/messaging_repository.dart:215 | `final doctorId = _currentDoctorId;` | **UNSURE** | Queries SQLite email logs by doctorId. Gmail is per-user, but SQLite log table schema may use doctorId. |
| lib/features/messaging/data/repo/whatsapp_repository.dart:59 | `String get _currentDoctorId {` | **TENANT** | Doc id of whatsapp_connections is the tenant doctorId. |
| lib/features/messaging/data/repo/whatsapp_repository.dart:63 | `final uid = _auth?.currentUser?.uid;` | **TENANT** | Doc id of whatsapp_connections is the tenant doctorId. |
| lib/features/messaging/data/repo/whatsapp_repository.dart:81 | `_currentDoctorId,` | **TENANT** | Doc id of whatsapp_connections is the tenant doctorId. |
| lib/features/messaging/data/services/gmail_auth_service.dart:65 | `String get _currentDoctorId {` | **USER** | Gmail OAuth integration and tokens are per-user. |
| lib/features/messaging/data/services/gmail_auth_service.dart:66 | `final uid = FirebaseAuth.instance.currentUser?.uid;` | **USER** | Gmail OAuth integration and tokens are per-user. |
| lib/features/messaging/data/services/gmail_auth_service.dart:86 | `final doctorId = _currentDoctorId;` | **USER** | Gmail OAuth integration and tokens are per-user. |
| lib/features/messaging/data/services/gmail_auth_service.dart:141 | `final doctorId = _currentDoctorId;` | **USER** | Gmail OAuth integration and tokens are per-user. |
| lib/features/messaging/data/services/gmail_auth_service.dart:157 | `final doctorId = _currentDoctorId;` | **USER** | Gmail OAuth integration and tokens are per-user. |
| lib/features/messaging/data/services/gmail_auth_service.dart:195 | `final doctorId = _currentDoctorId;` | **USER** | Gmail OAuth integration and tokens are per-user. |
| lib/features/mobile/mobile_campaigns.dart:27 | `FirebaseAuth.instance.currentUser?.uid ?? 'anonymous',` | **USER** | Campaigns and recipients subcollections are owned per-user under users/{uid}. |
| lib/features/onboarding/presentation/onboarding_flow.dart:526 | `holderId: FirebaseAuth.instance.currentUser?.uid,` | **USER** | Loyalty card holderId references user profile. |
| lib/features/patients/data/repo/patient_repository.dart:32 | `String get _currentDoctorId {` | **TENANT** | doctorId field in patients collection or tenant queries. |
| lib/features/patients/data/repo/patient_repository.dart:33 | `final uid = FirebaseAuth.instance.currentUser?.uid;` | **TENANT** | doctorId field in patients collection or tenant queries. |
| lib/features/patients/data/repo/patient_repository.dart:105 | `doctorId: _currentDoctorId,` | **TENANT** | doctorId field in patients collection or tenant queries. |
| lib/features/patients/data/repo/patient_repository.dart:122 | `await EncryptionKeyManager.instance.loadForDoctor(_currentDoctorId);` | **TENANT** | Passed to EncryptionKeyManager.loadForDoctor for tenant encryption key. |
| lib/features/patients/data/repo/patient_repository.dart:155 | `await EncryptionKeyManager.instance.loadForDoctor(_currentDoctorId);` | **TENANT** | Passed to EncryptionKeyManager.loadForDoctor for tenant encryption key. |
| lib/features/patients/data/services/medical_document_local_service.dart:19 | `String get _currentDoctorId => FirebaseAuth.instance.currentUser?.uid ?? '';` | **TENANT** | doctorId field in SQLite medical documents. |
| lib/features/patients/data/services/medical_document_local_service.dart:46 | `final doctorId = _currentDoctorId;` | **TENANT** | doctorId field in SQLite medical documents. |
| lib/features/patients/data/services/medical_document_local_service.dart:58 | `final doctorId = _currentDoctorId;` | **TENANT** | doctorId field in SQLite medical documents. |
| lib/features/patients/data/services/patient_local_service.dart:38 | `String get _currentDoctorId => FirebaseAuth.instance.currentUser?.uid ?? '';` | **TENANT** | doctorId field in SQLite patients table. |
| lib/features/patients/data/services/patient_local_service.dart:112 | `whereArgs: [patientId, _currentDoctorId],` | **TENANT** | doctorId field in SQLite patients table. |
| lib/features/patients/data/services/patient_local_service.dart:145 | `whereArgs: [_currentDoctorId],` | **TENANT** | doctorId field in SQLite patients table. |
| lib/features/patients/data/services/patient_local_service.dart:196 | `whereArgs: [_currentDoctorId],` | **TENANT** | doctorId field in SQLite patients table. |
| lib/features/patients/data/services/patient_local_service.dart:213 | `? _currentDoctorId` | **TENANT** | doctorId field in SQLite patients table. |
| lib/features/queue/data/repo/queue_repository.dart:41 | `String get _currentDoctorId {` | **TENANT** | doctorId field in Firestore walk_in_queue collection. |
| lib/features/queue/data/repo/queue_repository.dart:42 | `final uid = FirebaseAuth.instance.currentUser?.uid;` | **TENANT** | doctorId field in Firestore walk_in_queue collection. |
| lib/features/queue/data/repo/queue_repository.dart:106 | `doctorId: _currentDoctorId,` | **TENANT** | doctorId field in Firestore walk_in_queue collection. |
| lib/features/queue/data/services/queue_local_service.dart:43 | `String get _currentDoctorId => FirebaseAuth.instance.currentUser?.uid ?? '';` | **TENANT** | doctorId field in SQLite walk_in_queue table queries and writes. |
| lib/features/queue/data/services/queue_local_service.dart:95 | `: _currentDoctorId;` | **TENANT** | doctorId field in SQLite walk_in_queue table queries and writes. |
| lib/features/queue/data/services/queue_local_service.dart:143 | `final doctorId = _currentDoctorId;` | **TENANT** | doctorId field in SQLite walk_in_queue table queries and writes. |
| lib/features/queue/data/services/queue_local_service.dart:165 | `final doctorId = _currentDoctorId;` | **TENANT** | doctorId field in SQLite walk_in_queue table queries and writes. |
| lib/features/queue/data/services/queue_local_service.dart:183 | `final doctorId = _currentDoctorId;` | **TENANT** | doctorId field in SQLite walk_in_queue table queries and writes. |
| lib/features/queue/data/services/queue_local_service.dart:199 | `final doctorId = _currentDoctorId;` | **TENANT** | doctorId field in SQLite walk_in_queue table queries and writes. |
| lib/features/queue/data/services/queue_local_service.dart:229 | `doctorId: _currentDoctorId,` | **TENANT** | doctorId field in SQLite walk_in_queue table queries and writes. |
| lib/features/queue/data/services/queue_local_service.dart:268 | `whereArgs: [_currentDoctorId, groupId, dateKey],` | **TENANT** | doctorId field in SQLite walk_in_queue table queries and writes. |
| lib/features/queue/data/services/queue_local_service.dart:280 | `whereArgs: [_currentDoctorId, groupId, dateKey],` | **TENANT** | doctorId field in SQLite walk_in_queue table queries and writes. |
| lib/features/radiology/data/radiology_providers.dart:34 | `return user?.uid ?? FirebaseAuth.instance.currentUser?.uid ?? 'doc_omr';` | **TENANT** | radDoctorIdProvider resolves tenant doctorId for radiology studies. |
| lib/features/revenue/repo/invoice_repo.dart:24 | `String get _currentDoctorId {` | **TENANT** | doctorId field in Firestore invoices collection. |
| lib/features/revenue/repo/invoice_repo.dart:25 | `final uid = _auth.currentUser?.uid;` | **TENANT** | doctorId field in Firestore invoices collection. |
| lib/features/revenue/repo/invoice_repo.dart:81 | `final doctorId = _currentDoctorId;` | **TENANT** | doctorId field in Firestore invoices collection. |
| lib/features/revenue/repo/invoice_repo.dart:128 | `final doctorId = _currentDoctorId;` | **TENANT** | doctorId field in Firestore invoices collection. |
| lib/features/revenue/repo/invoice_repo.dart:170 | `final doctorId = _currentDoctorId;` | **TENANT** | doctorId field in Firestore invoices collection. |
| lib/features/revenue/repo/invoice_repo.dart:184 | `final doctorId = _currentDoctorId;` | **TENANT** | doctorId field in Firestore invoices collection. |
| lib/features/revenue/repo/revenue_repo.dart:26 | `String get _currentDoctorId {` | **TENANT** | doctorId field in Firestore revenue_entries and pending_payments collections. |
| lib/features/revenue/repo/revenue_repo.dart:27 | `final uid = FirebaseAuth.instance.currentUser?.uid;` | **TENANT** | doctorId field in Firestore revenue_entries and pending_payments collections. |
| lib/features/revenue/repo/revenue_repo.dart:78 | `doctorId: _currentDoctorId,` | **TENANT** | doctorId field in Firestore revenue_entries and pending_payments collections. |
| lib/features/revenue/repo/revenue_repo.dart:111 | `final uid = FirebaseAuth.instance.currentUser?.uid;` | **TENANT** | doctorId field in Firestore revenue_entries and pending_payments collections. |
| lib/features/revenue/repo/revenue_repo.dart:146 | `final doctorId = FirebaseAuth.instance.currentUser?.uid;` | **TENANT** | doctorId field in Firestore revenue_entries and pending_payments collections. |
| lib/features/revenue/repo/revenue_repo.dart:181 | `.where('doctorId', isEqualTo: _currentDoctorId)` | **TENANT** | doctorId field in Firestore revenue_entries and pending_payments collections. |
| lib/features/revenue/repo/revenue_repo.dart:253 | `doctorId: _currentDoctorId,` | **TENANT** | doctorId field in Firestore revenue_entries and pending_payments collections. |
| lib/features/scribe/data/repo/consultation_note_repository.dart:36 | `String get _currentDoctorId {` | **USER** | Scribe notes live under users/{uid}/medical_records. |
| lib/features/scribe/data/repo/consultation_note_repository.dart:37 | `final uid = FirebaseAuth.instance.currentUser?.uid;` | **USER** | Scribe notes live under users/{uid}/medical_records. |
| lib/features/scribe/data/repo/consultation_note_repository.dart:377 | `.doc(_currentDoctorId)` | **USER** | Scribe notes live under users/{uid}/medical_records. |
| lib/features/scribe/data/services/scribe_audio_sync.dart:29 | `final doctorId = FirebaseAuth.instance.currentUser?.uid;` | **USER** | Voice dictation scratch path voice-scratch/doctors/{uid} is per-user. |
| lib/features/scribe/presentation/scribe_session_controller.dart:178 | `final doctorId = FirebaseAuth.instance.currentUser?.uid ?? 'local_doctor';` | **USER** | Scribe session audio and consultation notes are per-user. |
| lib/features/scribe/presentation/scribe_session_controller.dart:373 | `final doctorId = FirebaseAuth.instance.currentUser?.uid ?? '';` | **USER** | Scribe session audio and consultation notes are per-user. |
| lib/features/scribe/presentation/scribe_session_controller.dart:405 | `final doctorId = FirebaseAuth.instance.currentUser?.uid ?? 'local_doctor';` | **USER** | Scribe session audio and consultation notes are per-user. |
