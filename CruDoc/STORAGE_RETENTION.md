# Cloud Storage tiering and retention

Bucket: `gs://svayatta-crudoc-dev.firebasestorage.app` (asia-south1).
Applied on 30 September 2026. Keep this file, `lifecycle.json` and the live
bucket in step: change the file first, then apply it.

## What is live

| Setting | Value |
|---|---|
| Default storage class | Standard |
| Autoclass | On, final class Archive. A file moves down after 30 / 90 / 365 days unopened and back to Standard when opened. No retrieval or early-deletion fees. Files under 128 KiB stay in Standard. |
| Delete rules | `lifecycle.json` (below) |
| Soft delete | 7 days |
| Public access prevention | Enforced. Firebase download URLs still work; public IAM grants on the bucket are refused. |
| Access rules | `storage.rules`, tested in `tests/storage-rules` |

## Retention decisions

| Files | Kept for | Deleted by |
|---|---|---|
| Prescriptions, invoices, treatment plans, X-rays, clinical photos, lab reports | Until the patient's record is erased on request. Minimum period to be confirmed with legal (medical-records rules, DPDP Act). | Never automatically. No lifecycle rule touches `doctors/*/patients/`. |
| Encrypted database backups (`*.enc`) | 365 days | Lifecycle rule |
| Revenue CSV exports (`*.csv`) | 90 days | Lifecycle rule |
| Voice recordings (`voice-scratch/`) | 14 days | Lifecycle rule |
| Clinic logo and signature, inventory receipts, sterilization strips | Kept | Never automatically |

Lifecycle rules can't match wildcards inside a path, only a prefix or a file
ending. That is why each deletable kind has its own folder or ending; keep it
so when adding file types, and never add a rule that could match clinical
files.

## Applying a change

```bash
gcloud storage buckets update gs://svayatta-crudoc-dev.firebasestorage.app --lifecycle-file=lifecycle.json
gcloud storage buckets describe gs://svayatta-crudoc-dev.firebasestorage.app
```

## Sign-off

- [ ] Owner: backup (365 d) and export (90 d) periods
- [ ] Legal: minimum retention for clinical files
