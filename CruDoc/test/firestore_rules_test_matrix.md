# Firestore Security Rules Test Matrix — CruDoc Dental Specialization (Packet 0.5)

This document formalizes the security and data isolation contract for the dental specialization collections in Cloud Firestore, derived from Data Contract 0.3 & 0.4 (`crudoc-dentist-data-contract.md`).

---

## 1. Target Collections & Paths

| Collection Path | Scope | Primary Tenant Key | PHI / Sensitive Fields |
|---|---|---|---|
| `dental_procedure_catalog/{id}` | Clinic / Doctor Reference Data | `doctorId` | None (clinic configuration) |
| `tooth_chart_entries/{id}` | Patient Clinical Log | `doctorId`, `patientId` | `notes` (**Encrypted**) |
| `procedure_log_entries/{id}` | Patient Clinical Log | `doctorId`, `patientId` | `notes`, `materials` (**Encrypted**) |
| `sterilization_log_entries/{id}` | Clinic / Sterilization Log | `doctorId` (No `patientId`) | None (compliance operational log) |
| `treatment_plan_line_items/{id}` | Patient Quote / Line Item | `doctorId`, `patientId` | None (line items, catalog links) |

---

## 2. Authorization Rules Specification

For every collection listed above, access is strictly governed by the authenticated user's Firebase Auth UID matching `resource.data.doctorId` (or `request.resource.data.doctorId` on create):

```cel
// Security Rule Contract for dental collections
match /dental_procedure_catalog/{docId} {
  allow read, update, delete: if request.auth != null && request.auth.uid == resource.data.doctorId;
  allow create: if request.auth != null && request.auth.uid == request.resource.data.doctorId;
}

match /tooth_chart_entries/{docId} {
  allow read, update, delete: if request.auth != null && request.auth.uid == resource.data.doctorId;
  allow create: if request.auth != null && request.auth.uid == request.resource.data.doctorId;
}

match /procedure_log_entries/{docId} {
  allow read, update, delete: if request.auth != null && request.auth.uid == resource.data.doctorId;
  allow create: if request.auth != null && request.auth.uid == request.resource.data.doctorId;
}

match /sterilization_log_entries/{docId} {
  allow read, update, delete: if request.auth != null && request.auth.uid == resource.data.doctorId;
  allow create: if request.auth != null && request.auth.uid == request.resource.data.doctorId;
}

match /treatment_plan_line_items/{docId} {
  allow read, update, delete: if request.auth != null && request.auth.uid == resource.data.doctorId;
  allow create: if request.auth != null && request.auth.uid == request.resource.data.doctorId;
}
```

---

## 3. Allow / Deny Scenario Matrix

| Scenario ID | Operation | User Identity | Document Data (`doctorId`) | Expected Outcome | Rationale |
|---|---|---|---|---|---|
| **RULE-01** | `read` | Signed-out (`auth == null`) | `doc_123` | **DENY** | Unauthenticated access is completely forbidden. |
| **RULE-02** | `create` | Signed-out (`auth == null`) | `doc_123` | **DENY** | Unauthenticated creation forbidden. |
| **RULE-03** | `read` | Doctor A (`auth.uid == "doc_A"`) | `doc_A` | **ALLOW** | Owning doctor reading own clinic/patient record. |
| **RULE-04** | `create` | Doctor A (`auth.uid == "doc_A"`) | `doc_A` | **ALLOW** | Owning doctor creating record with matching `doctorId`. |
| **RULE-05** | `update` | Doctor A (`auth.uid == "doc_A"`) | `doc_A` | **ALLOW** | Owning doctor updating own record. |
| **RULE-06** | `delete` | Doctor A (`auth.uid == "doc_A"`) | `doc_A` | **ALLOW** | Owning doctor deleting own record. |
| **RULE-07** | `read` | Doctor B (`auth.uid == "doc_B"`) | `doc_A` | **DENY** | Doctor B attempting to read Doctor A's patient/clinic records. |
| **RULE-08** | `create` | Doctor B (`auth.uid == "doc_B"`) | `doc_A` | **DENY** | Doctor B trying to forge `doctorId: "doc_A"` on creation. |
| **RULE-09** | `update` | Doctor B (`auth.uid == "doc_B"`) | `doc_A` | **DENY** | Doctor B attempting to modify Doctor A's record. |
| **RULE-10** | `delete` | Doctor B (`auth.uid == "doc_B"`) | `doc_A` | **DENY** | Doctor B attempting to delete Doctor A's record. |
| **RULE-11** | `create` | Doctor A (`auth.uid == "doc_A"`) | Missing `doctorId` | **DENY** | Schema validation requires `doctorId` on create. |
| **RULE-12** | `read` | Sterilization Log | Doctor A (`auth.uid == "doc_A"`) | **ALLOW** | Doctor reading clinic-level sterilization cycle without `patientId`. |
| **RULE-13** | `read` | Sterilization Log | Doctor B (`auth.uid == "doc_B"`) | **DENY** | Doctor B reading Doctor A's sterilization log. |

---

## 4. Test Execution Status

- **Firebase Emulator Rules Suite**: CruDoc currently does not ship with an active `firebase.json` emulator configuration for `rules:test`.
- **Validation**: Rules contract defined above matches the flat top-level collection isolation enforced across existing repositories (`patient_repository.dart`, `homeopathy_repository.dart`, `medicine_model.dart`).
