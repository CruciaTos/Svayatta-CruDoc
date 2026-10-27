# Clinic file sharing: send to a colleague, keep one copy per file

Plan written 2026-10-27. No code yet. Tasks are sized so each one can be handed to Antigravity (Gemini Flash) as a separate brief later. Tasks marked **Claude** are the hard or security-critical parts that Claude should write or review.

---

## 1. In short

1. **One copy per file in the cloud.** Each file gets a fingerprint (a SHA-256 hash of its bytes). The bucket stores each clinic's files by fingerprint. Two records for the same file point at the same stored copy. Nothing is uploaded twice. This works without any Wi-Fi sharing, and it saves the most storage, so it ships first.
2. **"Send to colleague" in Files.** Pick a file, pick a colleague, done. The colleague gets an "Incoming" card and taps Accept. The file then shows in their Files for that patient. No second upload happens: their record points at the same stored copy.
3. **Direct on the clinic Wi-Fi.** If both devices are on the same Wi-Fi, the file's bytes go straight from one device to the other over an encrypted connection. Phone ↔ PC ↔ phone. If they are not on the same network, or the Wi-Fi blocks devices from talking to each other, the same send goes through the cloud copy instead. The person sending does not have to choose.
4. **Works without internet.** If the internet is down but the Wi-Fi is up, devices still find each other and send files. Everything syncs to the cloud later.
5. **Safe.** Only devices registered to the same clinic can connect. Every connection is encrypted (TLS). Both sides check permissions: people without "See clinical records" cannot receive patient files. Patient notes and conditions are never part of a file transfer.

---

## 2. What exists today (and what we build on)

| Area | Today | What this plan reuses |
|---|---|---|
| Files records | `patient_files` and `file_folders` in Firestore, synced per person by `lib/features/files/data/files_cloud_sync.dart`. Each file always belongs to a patient. A file's `visibleTo` copies its top-level folder; a file with no folder is private to its owner (`followsRoot` in `firestore.rules`). | The record shape. A received file becomes a normal record owned by the person who received it. |
| Bytes in the bucket | One object per file: `patient-files/{clinic}/{patient}/{fileId}/original` plus a progressive JPEG `.../view` for pictures (`medical_storage_service.dart`). Storage rules read the file's record to decide who may download (`storage.rules` line ~153). | The progressive view and streaming viewer (`progressive_picture.dart`, `streamToFile`) work unchanged. Only the path changes. |
| Upload queue | `StorageSyncQueue` (`lib/core/services/storage_sync_queue.dart`) copies bytes into `pending_uploads`, uploads, then calls a link handler (`files.storagePath`, `files.viewPath`) that writes the path into the record. Refused uploads leave the file as `localOnly`. | The queue gets one new step: check whether the clinic already has this fingerprint before uploading. |
| Deleting | `FilesRepository._deleteFileRow` marks the record deleted **and deletes the bucket object straight away**. | This must change. With shared copies, the app must never delete the stored copy itself. |
| Device storage limit | `LocalStorageManager` removes a local copy only when `_copyIsInCloud` confirms the cloud has it. | Same check. A copy received over Wi-Fi and not yet in the cloud is never removed. |
| Storage usage count | `storageUsedGB` is set to 0 at sign-up and summed by Super Admin (`functions/src/super-admin.ts`). **Nothing keeps it current.** | Phase 1 makes it accurate, counting each stored copy once per clinic. |
| PACS link | `dicom_net` has an HTTP server (`DicomWebServer`, plain `HttpServer.bind`) and a DICOM C-STORE receiver (`DimseServer`, plain TCP). Neither is encrypted. The only check is the AE title. `pacs_connection.dart` lists the device's IPv4 addresses and already skips Android's 192.0.0.4 CLAT address. Tested Pixel ↔ Windows on 2026-10-22. | The patterns: a Dart server inside the app, address listing, the receiver inbox → "Add to worklist" flow (used later for sending radiology studies). **Not** the transport itself: clinic sharing needs encryption and clinic-only access, which plain C-STORE cannot give. |
| Clinic team | `clinics/{c}/members/{uid}` with `perms` (12 keys in `lib/core/clinic/clinic_permission.dart`). Rules read the member doc on every request. `clinicalAccessScope: 'assigned'` limits doctors to their patients (`clinic_access.dart`). The `clinicTeam` callable adds and removes members. | Who may send and receive. Removing a member also removes their devices. |
| Encryption keys | Members share the clinic's data key (`EncryptionKeyManager`, `FieldCipher`). File names and thumbnails are encrypted in Firestore. | The offer documents encrypt names and thumbnails the same way. |
| Packages | `crypto`, `encrypt`, `flutter_secure_storage`, `connectivity_plus`, `firebase_messaging`, `flutter_local_notifications` are already in `pubspec.yaml`. Nothing for local discovery (mDNS) or making certificates. | New packages: one for mDNS (Phase 5) and one for creating a self-signed certificate (Phase 3). The spike picks them. |
| Windows installer | Inno Setup script at `installer/CruDoc.iss`. | It adds a Windows Firewall rule so the PC can receive. |

One more thing found: no Cloud Function or rule checks file contents against a fingerprint today, and there is no device registry. Both are new.

---

## 3. How it fits together

```
 Dr A's phone                                   Dr B's PC
 ───────────                                    ─────────
 Files → Send to colleague → Dr B
   │
   ├─ 1. Writes an "offer" (Firestore, when online) ──────►  Incoming card appears
   │                                                         (push notification if closed)
   ├─ 2. Same Wi-Fi?  Yes → connects directly (TLS) ──────►  Accept → pulls bytes from A
   │                  No  → nothing more to do               Accept → downloads from the
   │                                                         clinic's cloud copy
   │
   └─ 3. A's normal upload queue puts the file in the cloud ONCE,
         at clinic-blobs/{clinic}/{fingerprint}/original
         B's new record points at that same copy. No second upload.
```

There is one idea of an **offer** ("Dr A wants to give you this file"). It can travel two ways (direct over Wi-Fi, or through Firestore) and the bytes can travel two ways (direct, or from the cloud copy). Every combination ends the same way: Dr B gets their own record pointing at the clinic's single stored copy.

---

## 4. Design

### 4.1 One copy per file (the storage saving)

**Fingerprint.** When a file is added, the app computes its SHA-256 hash (64 hex characters). For big DICOMs this runs in a background isolate and reads the file in pieces. A 250 MB file takes about 1–2 s on a PC and 3–6 s on a phone. The fingerprint is saved in the local `patient_files` table (new column `sha256`) and in the Firestore record (new field `sha256`).

**Where bytes live.**
- Original: `clinic-blobs/{clinicId}/{sha256}/original`
- Progressive view (pictures): `clinic-blobs/{clinicId}/{sha256}/view`

Copies are shared **within one clinic only**. Two clinics with the same file each keep their own copy. Sharing across clinics would reveal that another clinic holds a file, and clinics must stay separate.

**The stored-copy record (Firestore):** `clinics/{clinicId}/blobs/{sha256}`

| Field | Meaning |
|---|---|
| `sizeBytes` | Size of the original |
| `contentType` | e.g. `application/pdf` |
| `state` | `ready` once the server has checked the fingerprint, or `bad` if the bytes did not match |
| `hasView` | true once the progressive view is stored |
| `refCount` | How many file records point here (kept by the server) |
| `zeroSince` | When `refCount` last fell to 0; empty otherwise |
| `purgeNow` | Set for erasure requests: skip the waiting period |
| `uploadedBy`, `createdAt` | Who first uploaded, when |

References are kept in `clinics/{clinicId}/blobs/{sha256}/refs/{fileId}`, one small doc per file record. Using one doc per record (rather than just adding or subtracting a number) makes the count safe when a Cloud Function runs twice for the same change, which Firebase allows.

**What counts as a reference:** a `patient_files` record that has `sha256` and is not deleted. It counts even before it has a `storagePath`, so a record waiting for its upload still protects the copy.

**Uploading (the new queue step).**
1. Before uploading a Files original, read `clinics/{c}/blobs/{sha}`.
2. If `state == 'ready'`: skip the upload. Write `storagePath = clinic-blobs/{c}/{sha}/original` into the record (the existing link handler does this). Do the same for `viewPath` if `hasView`, and skip making the view.
3. If missing: upload to the blob path. Storage rules allow **create only**: no overwriting, no deleting.
4. If the upload is refused because the object already exists (another device won the race), treat it as success and link the path.

**Server checks (Cloud Functions, asia-south1).**
- `onBlobFinalized` (Storage trigger on `clinic-blobs/`): reads the uploaded original, recomputes SHA-256, and compares it with the name in the path.
  - Match: create or update the blob doc with `state: 'ready'` and add the size to the clinic's usage.
  - No match: delete the object, set `state: 'bad'`, and write an audit entry.
  - For `view` objects: set `hasView: true`.
- `onPatientFileWritten` (Firestore trigger on `patient_files/{fileId}`): works out the old and new reference, then adds or removes the `refs/{fileId}` doc and adjusts `refCount` in a transaction. When the count reaches 0 it sets `zeroSince`. When the count rises above 0 it clears it.
- `cleanUpBlobs` (daily schedule): deletes the original, view and blob doc for every blob where `refCount == 0` and `zeroSince` is more than 7 days ago, or right away when `purgeNow` is set. It subtracts the size from usage.

The 7-day wait covers: undo, offers still in flight, and devices that were offline when someone else deleted the last synced record. If a blob was removed and a device still has a pending record and local bytes, its queue simply uploads it again. Uploads are by fingerprint, so this is always safe.

**Clients also check.** After every download or Wi-Fi transfer, the receiving app recomputes the fingerprint before saving. A mismatch is discarded and retried. This stops a bad upload (on purpose or by accident) from ever being shown as the real file.

**Reading.** Storage rule for `clinic-blobs/{clinicId}/{sha}/{name}`: read if the person has `clinical.view` in that clinic. Only someone who knows the fingerprint can ask for the file, and the fingerprint is only visible in records they are allowed to see. See decision D3 for the stricter option.

**Deleting.** The app stops deleting bucket objects for blob-backed files. It only marks the record deleted, and the server does the rest. The storage rule has no delete for `clinic-blobs/`, so even older app versions cannot remove a shared copy. Their delete attempt fails quietly, which the current code already tolerates.

**Storage-limit accounting.** Usage is counted **per clinic, once per stored copy**. `onBlobFinalized` adds, `cleanUpBlobs` subtracts. The total goes into `clinics/{c}.storageBytes` and is mirrored into the existing `storageUsedGB` field that Super Admin reads. Files not yet moved to the new layout are counted by the backfill (below). Enforcing the plan's limit is a later step (X5); this phase only makes the number right.

**Moving existing files (backfill).** A Node admin script (`functions/scripts/backfill_blobs.ts`), run by the user with their own Google login, not a callable. This avoids the org-policy 403 that callables hit. For each `patient_files` record with an old `patient-files/...` path and no `sha256`:
1. Stream the object and compute SHA-256.
2. If the clinic has no blob for it, copy it server-side to the blob path (no download fees). Copy the view too if there is one.
3. Update the record: `sha256`, `storagePath`, `viewPath`, `updatedAt`. Devices pick up the change through their normal sync.
4. A second run with `--delete-old`, at least 7 days later, deletes old objects that no record points to any more.

`--dry-run` prints how many files, how many duplicates and how many bytes would be saved, and changes nothing. The script can be run again safely. On 2026-10-08 the dev bucket was empty, so running this soon is cheap. Do it before more clinics join.

**Rules changes, summarised.**
- `storage.rules`: new `match /clinic-blobs/{clinicId}/{sha}/{name}`. Read: `clinical.view`. Create: `clinical.edit`, `resource == null`, `name in ['original','view']`, the same type and size limits as today. No update. No delete.
- `firestore.rules`:
  - `validFile` accepts an optional `sha256` (64 lowercase hex characters). If `storagePath` starts with `clinic-blobs/`, it must equal `clinic-blobs/{doctorId}/{sha256}/original` (the same check applies to `viewPath`). This stops a record pointing at another clinic's or another file's copy.
  - `clinics/{c}/blobs/**`: members with `clinical.view` can read. Only the server writes.

**Radiology studies** (`doctors/{c}/patients/{p}/clinical/imaging/...`) keep their own layout for now. The imaging-view Cloud Run service and `getImagingView` depend on those paths. Moving them is task X3.

### 4.2 "Send to colleague" is an offer

An offer is one Firestore doc per file: `clinics/{clinicId}/file_offers/{offerId}`. The offer id is a UUID made by the sender, so the same offer sent over Wi-Fi and through Firestore is recognised as one.

| Field | Meaning |
|---|---|
| `from`, `to` | Sender uid, recipient uid |
| `batchId` | Groups files sent together ("3 files for Ramesh K.") |
| `fileId` | The sender's record id (for the sender's own "Sent" history only) |
| `sha256`, `sizeBytes`, `contentType` | What the file is |
| `patientId` | Which patient. The recipient's app shows the name from its own patient list; the offer never carries it |
| `name`, `thumb` | Encrypted with `FieldCipher`, like `patient_files` |
| `status` | `sent` → `accepted` / `declined` / `cancelled` |
| `via` | `lan` or `cloud`, for information |
| `createdAt`, `expireAt` | `expireAt` = 30 days later. A Firestore TTL policy deletes old offers automatically |

Rules:
- **Create:** `from == auth.uid`; the sender has `clinical.view`; `to` is an active member of the same clinic and is not the sender.
- **Read:** only `from` or `to`.
- **Update:** the recipient may change only `status` (to accepted or declined); the sender may change only `status` (to cancelled).
- **Delete:** nobody. TTL removes old offers.

**Accepting** creates the recipient's **own** `patient_files` record:
- new id, `ownerUid` = recipient, the same `patientId`
- no folder, so `visibleTo = [recipient]`. This already passes `followsRoot` in today's rules.
- `sha256`, name, type, size, thumbnail
- `receivedFrom: { uid, offerId }`

If the cloud copy is already `ready`, `storagePath` and `viewPath` are set straight away. If not, they stay empty, and a small "link when ready" check fills them in later. That check runs when Files opens and after each sync: for the person's own records with `sha256` but no `storagePath`, read the blob doc and, if ready, patch the paths.

The recipient's new record is a reference, so the shared copy is protected for as long as either person keeps the file. Deleting "my copy" never affects the colleague's.

A push notification tells the recipient about a new offer when the app is closed and online. It is sent by a Firestore trigger on `file_offers` and reuses the app's existing push sending.

**Audit.** Sending and accepting each write an `access_logs` entry (`file.send`, `file.receive`) in the person's own name, which the current rules allow. Entries made offline are queued and written when the device is back online. DPDP rules expect access logs to be kept, so these count towards that.

### 4.3 Which devices are trusted (device registry)

Every install creates its own **device identity** the first time sharing is used:
- a random `deviceId` (16 characters)
- a private key (ECDSA P-256), kept in `flutter_secure_storage` (Android Keystore on phones, Windows DPAPI on PCs) and never sent anywhere
- a self-signed TLS certificate made from that key, valid 5 years

The device registers itself at `clinics/{clinicId}/devices/{deviceId}`:

| Field | Meaning |
|---|---|
| `uid` | The person it belongs to |
| `name` | "Reception PC", "Dr Mehta's Pixel"; the person can rename it |
| `platform` | `android` / `windows` |
| `certPem`, `certSha256` | The certificate, and its fingerprint for pinning |
| `lan` | `{ ips: [...], port, updatedAt }`: where to reach it on the local network (see 4.4) |
| `lastSeenAt`, `createdAt` | |

Rules:
- **Read:** any active member of the clinic.
- **Create:** only the person themselves (`uid == auth.uid`) while they are an active member.
- **Update:** only by the owner. `certSha256`, `certPem` and `uid` can never change; a new key means a new device.
- **Delete:** the owner, or anyone with the `team` permission.

The `clinicTeam` function's remove-member action also deletes that person's devices. No new callable is needed for any of this, which avoids the domain-restricted-sharing 403 problem.

**Why not a clinic-signed certificate?** Signing device certificates would need a server signing key (Cloud KMS) and a callable. The registry gives the same result with less: a device is trusted when it proves it holds the private key for a certificate listed in the registry. Only the device's own owner can write that entry, and the owner must be an active member.

### 4.4 Finding colleagues on the Wi-Fi (discovery)

There are two ways, used together.

**A. Through Firestore (when online, the usual case).** On app start and whenever the network changes (`connectivity_plus`), each device writes its local IPv4 addresses and listening port into its registry doc. The address list skips:
- 192.0.0.x (Android CLAT, as `pacs_connection.dart` already does)
- 169.254.x.x (link-local)
- VPN and virtual adapters (Hyper-V, WSL, VirtualBox)

To check whether a colleague is nearby, the app tries their listed addresses that share a subnet with one of its own. It tries them in parallel with a 1.5-second timeout. If one answers and passes the security check (4.5), the colleague is "Nearby". This needs no special permissions and works even where multicast is blocked.

**B. mDNS / DNS-SD (works with no internet; Phase 5).** Each device advertises the service `_crudoc._tcp` on the local network. This is the same system printers and Chromecasts use. The advert carries only `v=1`, the random `deviceId` and the port: no clinic name, no person's name. Other devices browse for `_crudoc._tcp`, look each `deviceId` up in their cached registry, and ignore anything that isn't from their clinic.
- **Android:** the system `NsdManager`, through a Flutter package (`bonsoir` first choice, `nsd` second; the spike confirms which works on Windows too). Needs the `CHANGE_WIFI_MULTICAST_STATE` permission in the manifest. No location permission is needed. Browsing runs only while the send sheet or Files is open, to save battery.
- **Windows:** Windows 10 and later have built-in DNS-SD (the system DNS client answers mDNS), so the app does not open UDP port 5353 itself. The spike must confirm this on Private and Public network profiles.

We do not read the Wi-Fi name (SSID). On Android that needs location permission, and subnet matching is enough.

### 4.5 The connection: encryption, transfer, resume

**Transport:** HTTPS (TLS 1.3) served from inside the app with Dart's `HttpServer.bindSecure`, using the device's own certificate. This is the same kind of server as `DicomWebServer`, but encrypted. Dart's TLS comes from BoringSSL, so we do not invent any cryptography ourselves.

**The client checks the server:** `HttpClient` with no trusted roots and a `badCertificateCallback` that accepts the certificate only if its SHA-256 equals the `certSha256` in the registry for the device it meant to reach (pinning). A stranger on the Wi-Fi cannot pretend to be a colleague's device.

**The server checks the client** (inside the encrypted connection):
1. `GET /v1/hello` → `{ deviceId, nonce }`. The nonce is a random 32 bytes that is only good for 60 seconds.
2. `POST /v1/session` with `{ deviceId, signature }`. The signature is the client device key signing `"crudoc-lan-v1" | serverDeviceId | nonce | clientCertSha256`. The server checks that:
   - the device is in its registry for this clinic,
   - its owner is an active member, and
   - the signature is valid.

   It then returns a random session token valid for 15 minutes. A challenge is used instead of timestamps, so wrong clocks on offline devices don't matter.

**Endpoints after the session:**
- `POST /v1/offers`: the sender delivers an offer (same fields as 4.2).
- `GET /v1/blobs/{sha256}` with `Range: bytes=N-`: the recipient pulls the bytes. The server serves a fingerprint **only if it named that fingerprint in an offer to this caller that is still open**. A colleague cannot pull any file they like from someone's device just by knowing its fingerprint.
- `POST /v1/offers/{id}/status`: tells the sender "accepted" or "declined" straight away. When online, Firestore carries this too.

**Pull, not push.** The recipient downloads, so it always knows how much it has, and resuming is simple:
- Bytes go to `lan_inbox/{offerId}.part` in the app's private support folder.
- Each request asks for the next 8 MB (each one a separate HTTP request, so a dropped Wi-Fi costs at most one piece).
- On a drop it retries with back-off (1, 2, 5, 10, 30 s) and continues from the last byte written.
- When complete, it checks the SHA-256, renames the file into place and creates the record.
- A 250 MB DICOM on ordinary clinic Wi-Fi (5–30 MB/s) takes about 10–60 seconds.

**Port:** fixed port 47811 when free, otherwise any free port. The real port is always published in the registry and the mDNS advert, so a busy port never breaks anything.

**When the server runs:**
- **Windows:** while CruDoc is open.
- **Android:** while the app is open, and for 2 minutes after it goes to the background. During an active transfer, a foreground service with a visible notification ("Receiving 3 files from Dr Mehta") keeps it running, which Android requires. When the app is closed, nothing listens. Online, the push notification brings the person back. Offline, the sender's offer waits (4.7).

### 4.6 Who may send and receive

Checks happen in three places: the sender's screen, the recipient's device, and finally the Firestore rules. Each one alone would block a wrong transfer.

| Situation | Result |
|---|---|
| Sender can see the file in Files | Can send it. Files already needs `clinical.view`. |
| Recipient has `clinical.view` **and** `clinical.edit` | Can receive and keep it (creating their record needs `clinical.edit`). |
| Recipient has `clinical.view` only | Shown greyed: "Can't save files". See decision D2. |
| Recipient lacks `clinical.view` (receptionist, accountant…) | Shown greyed: "Can't receive patient files". Their device refuses such offers even if one arrives. |
| Clinic uses "assigned patients" and the recipient doctor isn't assigned to this patient | Shown greyed: "Not assigned to this patient". Their device refuses too. |
| Recipient removed from the clinic, or their device removed | Not listed. Connections are refused. |
| Solo doctor (no team) | "Send to colleague" is not shown at all. |

**What travels:** the file's bytes, its name, type, size, thumbnail and the patient's id. Nothing else. Patient notes, conditions, prescriptions and visit records are never part of a transfer. The recipient's app shows the patient's name from its own patient list, which already follows the clinic's rules.

### 4.7 No internet (Wi-Fi up, internet down)

- **Finding each other:** mDNS (4.4 B).
- **Trusting each other:** each device keeps a local copy of the clinic's device registry and member list (with permissions), saved at every sync with the time it was saved. Nearby sharing works offline only if that copy is **less than 7 days old** on both devices (decision D5). After that it shows "Connect to the internet once to keep sharing". This limits how long a removed member's device could still connect while everything is offline.
- **Sending:** the offer goes directly to the recipient's device. The Firestore offer and the audit entry wait in a small local queue and are written when the sender is back online.
- **Accepting:** the recipient's new record is saved locally as `pending`, like any record made offline, and syncs later.
- **The cloud copy:**
  - The sender's upload queue already holds the file and uploads it when the internet returns.
  - The recipient's device does not upload. It waits 2 hours, then checks the blob doc. If the copy is still missing (for example, the sender's phone was lost), it uploads from its own bytes. Uploads are by fingerprint, so at most one copy ever lands.
  - The received local copy is never removed by the device storage limit until the cloud has it.
- **Recipient not reachable:** if the recipient's device isn't on the network (phone app closed), the offer waits on the sender's device. It is delivered as soon as the recipient appears (mDNS sees them) or, once online, through Firestore. The sender sees "Waiting for Dr B to open CruDoc".

### 4.8 Different networks: fall back to the cloud

If no colleague device answers within 1.5 seconds, the send goes through the cloud with no extra step for the sender. Typical reasons: they are at home, on mobile data, on a guest network, or the router keeps Wi-Fi devices apart ("AP isolation"). The offer goes to Firestore. The recipient accepts and opens the file from the clinic's single cloud copy, streaming progressively as today.

If the registry says a colleague's device is on the same subnet but it never answers, the app shows a one-line hint once: *"Your Wi-Fi may be a guest network that blocks devices from talking to each other. Files will go through the cloud."*

### 4.9 Screens in Files

Keep controls where they already are, and add nothing that doesn't earn its place.

- **Send to colleague:** in the file's ⋯ menu and in the multi-select bar, next to Move. Hidden for solo doctors.
- **Send sheet:** a list of colleagues: name, role, and one status line:
  - 🟢 *Nearby · Reception PC*
  - ☁ *Will go through the cloud*
  - greyed with the reason from 4.6

  Tap a person to send immediately. The sheet turns into progress rows. If a person has two nearby devices, a small chip lets the sender pick one; by default the PC wins, since it is always on.
- **Incoming card:** at the top of Files, shown only while offers are waiting:
  - "Dr Mehta · 3 files for Ramesh K.", with thumbnails, and **Accept** / **Decline** buttons.
  - The first time a person sends you something, the accept prompt has a checkbox "Always accept from Dr Mehta" (decision D1).
  - An OS notification appears when an offer arrives: a local notification on the Wi-Fi path, a push notification on the cloud path.
- **Where accepted files go:** into that patient's files, with no folder (so private to the recipient), labelled "From Dr Mehta" (decision D6).
- **Progress:** each transfer row shows a bar, "via Wi-Fi · 12 MB/s" or "via cloud", and Cancel. Outgoing transfers show in a small tray at the bottom of Files while they run.
- **Settings → Files → Nearby sharing:**
  - an on/off switch (default on)
  - this device's name
  - the list of the person's own devices, with Remove
  - on Windows, a "Check firewall" helper (see Risks)

---

## 5. Decisions to confirm

Each has a recommended default. The plan assumes the default unless the user says otherwise.

| # | Question | Recommended default |
|---|---|---|
| D1 | Should received files need a tap to accept? | Ask each time. The prompt offers "Always accept from this person". |
| D2 | Can someone with "See clinical records" but not "Write clinical records" receive? | No in v1: they can't create a record under today's rules. Shown greyed. Revisit if clinics ask. |
| D3 | Who can download a stored copy? | Any member with `clinical.view` who knows its fingerprint. Simple, works with today's streaming viewer, needs no new callable. Stricter option for later: per-file 10-minute links from a callable, like `getImagingView` (X6). |
| D4 | How long after the last record is deleted is the copy kept? | 7 days. Erasure requests skip the wait (`purgeNow`). |
| D5 | How long can a device share offline without syncing? | 7 days. |
| D6 | Where do accepted files appear? | In the patient's files, no folder, labelled "From Dr X". |
| D7 | Whose storage does a shared copy count against? | The clinic's, counted once. |

---

## 6. Phases and tasks

Each phase ships something useful by itself and ends at a GATE: a check by the user and Claude before the next phase starts. Effort is in working days for one developer. Antigravity is usually faster on simple UI and slower on anything subtle.

### Phase 0: Try the risky parts first (1–2 days) · Claude

| Task | What | Done when |
|---|---|---|
| S1 | mDNS spike: a throwaway Flutter page that advertises and browses `_crudoc._tcp` with `bonsoir` (then `nsd` if needed) on the Pixel and the Windows PC, both directions. Try the Windows network set to Private and to Public. | A short report: which package, which Android permission, what Windows does on Public. |
| S2 | TLS spike: make a self-signed ECDSA certificate in Dart (`basic_utils`, or another package if it can't), serve with `HttpServer.bindSecure`, connect from the other device with fingerprint pinning, sign and verify a challenge, and send a 250 MB file in 8 MB Range pieces, with one Wi-Fi drop in the middle. | Works Pixel ↔ PC; speed noted; resume works. |
| S3 | Router checklist for the clinic: is there a guest network, is AP isolation on, are 2.4/5 GHz on the same network? | A note in this doc's Risks section. |

**GATE 0:** pick the packages and confirm the transport. If S2 fails on either platform, stop and rethink the transport before Phase 3.

### Phase 1: One copy per file in the cloud (4–6 days)

Saves storage on its own, with no Wi-Fi sharing yet.

| Task | Who | What | Check |
|---|---|---|---|
| B1 | Antigravity | Compute SHA-256 when a file is added (`FilesRepository.addFilesWithIds`), streaming in an isolate. Add a `sha256` column to the local `patient_files` table (migration in `local_database_service.dart`), the `PatientFile` model, `toLocalMap`/`fromLocalMap`, and `files_cloud_sync.dart` (both directions). | Adding a file stores a 64-character hash locally and in Firestore. |
| B2 | Claude | `storage.rules`: `clinic-blobs/` match (read `clinical.view`; create only, no overwrite, no delete; type and size limits). Rule tests. | Emulator tests pass: overwrite refused, delete refused, other clinic refused. |
| B3 | Claude | `firestore.rules`: `sha256` format in `validFile`; `storagePath`/`viewPath` must match the fingerprint when they point at `clinic-blobs/`; `clinics/{c}/blobs/**` read-only for clinical members. Rule tests. | Tests pass. |
| B4 | Claude | Functions: `onBlobFinalized`, `onPatientFileWritten` (refs and count, safe to run twice), `cleanUpBlobs` (daily, 7 days, `purgeNow`), usage counting into `clinics/{c}.storageBytes` and `storageUsedGB`. Add a dev-only setting to shorten the 7 days to 1 minute for testing. | Unit tests for the reference maths; emulator run. |
| B5 | Antigravity | Upload step in `StorageSyncQueue` for `UploadKind.patientFile` / `patientFileView`: check the blob doc, then skip and link, or upload to `clinic-blobs/...`. Treat "already exists" as success. Skip making the view if `hasView`. New path helpers in `MedicalStorageService` (`blobOriginalPath`, `blobViewPath`). | The same PDF added twice uploads once (watch the bucket). |
| B6 | Antigravity | Download step: when a record has `sha256`, use the blob path. Verify the hash after a full download (`downloadToFile`; for `streamToFile`, check once complete). A mismatch deletes the local copy and shows "File damaged, trying again". | Opening still streams progressively; a tampered file is rejected. |
| B7 | Antigravity | `_deleteFileRow`: don't delete objects under `clinic-blobs/` (keep the old behaviour for old `patient-files/` paths). | Deleting one of two records leaves the other openable. |
| B8 | Claude | `functions/scripts/backfill_blobs.ts` with `--dry-run` and `--delete-old`. | Dry run on dev prints counts; a real run moves the test files. |
| B9 | User + Claude | Deploy rules and functions. Check first that nothing blocks function deploys (an earlier note said a missing secret did). Phone + PC test: same file for two patients → one object; delete one → the other opens; delete both → gone after the test grace time; usage number goes up and down. | All pass. |

**GATE 1.**

### Phase 2: "Send to colleague" through the cloud (3–4 days)

Useful everywhere, even before direct Wi-Fi.

| Task | Who | What | Check |
|---|---|---|---|
| O1 | Claude (rules) + Antigravity (model) | `file_offers` model and repository. Rules plus tests (4.2). Firestore TTL policy on `expireAt` (the user enables it in the console, or Claude adds it to `firestore.indexes.json` field overrides). | Rule tests pass: a stranger can't read; the recipient can only change `status`. |
| O2 | Antigravity | Send sheet (4.9) with the eligibility rules from 4.6, using the synced member list and `clinic_access.dart` for patient scope. Hidden for solo clinics. | A receptionist account is greyed with the right reason. |
| O3 | Antigravity | Incoming card: Accept creates the recipient's record (4.2); Decline sets the status. "Link when ready" check. "From Dr X" label on the file row. | A two-account test: file appears for B and opens from the same cloud copy. |
| O4 | Claude | Push notification on a new offer (trigger on `clinics/{c}/file_offers/{id}`), reusing the existing push sending. | B's phone gets a notification with the app closed. |
| O5 | Antigravity | `access_logs` entries `file.send` / `file.receive`. | Entries visible to the clinic admin. |

**GATE 2:** two-account test on phone and PC, including a receptionist account.

### Phase 3: Trusted devices (2–3 days)

| Task | Who | What | Check |
|---|---|---|---|
| K1 | Claude | Device identity: `deviceId`, ECDSA key, self-signed certificate, stored in secure storage. Code taken from the S2 spike. New file `lib/features/files/lan/device_identity.dart`. | Same identity after an app restart; a new one after reinstall. |
| K2 | Claude | Registry doc and rules plus tests (4.3). `clinicTeam` remove-member also deletes that person's devices (`functions/src/clinic.ts`). | Tests pass: can't register for someone else; can't change a certificate. |
| K3 | Antigravity | Presence: write local IPs (with the skip list from 4.4), port and `lastSeenAt` on start and on network change. | The PC's registry doc shows its 192.168.x.x address. |
| K4 | Antigravity | Settings → Files → Nearby sharing: switch, device name, my devices with Remove. | Removing a device deletes its doc. |

**GATE 3:** Claude reviews the identity and registry code.

### Phase 4: Direct transfer on the same Wi-Fi (5–7 days)

| Task | Who | What | Check |
|---|---|---|---|
| N1 | Claude | LAN server `lib/features/files/lan/lan_server.dart`: `bindSecure`, `/v1/hello`, `/v1/session` (challenge, registry, member and signature checks), session tokens. | Unit test: a wrong signature, unknown device or removed member is refused. |
| N2 | Antigravity | Routes `/v1/offers`, `/v1/blobs/{sha}` (only fingerprints offered to this caller; Range support), `/v1/offers/{id}/status`. | Asking for an un-offered fingerprint returns 403. |
| N3 | Claude | LAN client: choose addresses (same subnet first, parallel, 1.5 s), pin the certificate, open a session. | Connects Pixel ↔ PC; a fake server with another certificate is rejected. |
| N4 | Antigravity | Pull with resume: `.part` files in `lan_inbox/`, 8 MB pieces, back-off, hash check, then the same accept path as O3. | A 250 MB DICOM resumes after Wi-Fi is toggled. |
| N5 | Antigravity | Route chooser on Send: Wi-Fi if a recipient device answers, otherwise the cloud. The Firestore offer is written either way when online (`via` field). | Same Wi-Fi → "via Wi-Fi"; phone on mobile data → "via cloud". |
| N6 | Antigravity | Progress UI (4.9): outgoing tray, incoming progress, speed, Cancel. | Visible on phone and PC. |
| N7 | Antigravity | Recipient upload delay: a Wi-Fi-received file with no cloud copy goes into the queue with a 2-hour "not before" time; the copy is checked again before uploading. | Only one object lands when both devices go online. |
| N8 | Antigravity + Claude review | Windows Firewall: in `installer/CruDoc.iss` `[Run]`, add an allow rule for the CruDoc exe on **Private and Domain** profiles only. In-app helper: if the current network is Public, explain and open `ms-settings:network-status`. | A fresh install receives without a firewall pop-up on a Private network. |
| N9 | Antigravity | Android: foreground service (type `dataSync`) only during transfers, with its notification; server stops 2 minutes after the app is backgrounded. | A transfer survives switching apps mid-way. |

**GATE 4:** Pixel ↔ PC on the clinic Wi-Fi; 250 MB resume test; a guest network falls back to the cloud.

### Phase 5: Works without internet (3–4 days)

| Task | Who | What | Check |
|---|---|---|---|
| M1 | Antigravity | mDNS advertise and browse with the package chosen in S1. The advert carries only `v`, `deviceId`, `port`. Browse only while Files or the send sheet is open. | With the router's internet unplugged, devices see each other. |
| M2 | Antigravity | Offline trust copy: registry and member list saved locally with a saved-at time; the 7-day rule and its message. | Setting the saved-at time back 8 days shows the message. |
| M3 | Antigravity | Offline offers: deliver over Wi-Fi only; queue the Firestore offer and audit entry; offline accept → pending record. | Everything appears in Firestore after reconnecting. |
| M4 | Antigravity | Waiting offers: retry delivery when the recipient's device appears; "Waiting for Dr B to open CruDoc". | Opening B's app delivers the waiting offer. |

**GATE 5:** a full offline test with the router's internet unplugged.

### Phase 6: Later, if wanted

| Task | What |
|---|---|
| X1 | **Quick send from device:** a receptionist scans a referral letter at the front desk and sends it to the doctor's PC. The sender needs only clinic membership (they captured the bytes themselves); the doctor picks the patient on Accept. Staff still never *receive* patient files. |
| X2 | **Send a radiology study** to a colleague through the same channel, landing in their radiology inbox → "Add to worklist" (reuses `RadReceiverNotifier`'s inbox flow). |
| X3 | Move radiology originals into the clinic blob store (needs changes to the imaging-view service and `getImagingView`). |
| X4 | One copy per file on the device too (local cache by fingerprint). |
| X5 | Storage screen shows "Saved by keeping one copy: 1.2 GB"; enforce the plan's storage limit now that usage is accurate. |
| X6 | Stricter downloads: per-file short-lived links from a callable (decision D3). |

---

## 7. Risks and how we handle them

| Risk | What happens | Handling |
|---|---|---|
| Android stops background apps | A phone with CruDoc closed can't receive directly. | Foreground service during transfers; push notification when online; offers wait when offline. Accept that a closed phone app doesn't receive offline. |
| Android multicast and battery saver | Some phones drop mDNS packets when the screen is off. | Online discovery goes through Firestore, not mDNS. Browse only while the screen is open. |
| Windows Firewall prompt | The first time the app listens, Windows asks; on a "Public" network inbound connections are blocked. | The installer adds a Private/Domain rule; an in-app helper explains how to mark the clinic Wi-Fi Private. We do not open Public networks. |
| Guest Wi-Fi or AP isolation | Devices on the same Wi-Fi can't reach each other. | Automatic cloud fallback, plus a one-time hint. |
| Separate networks (VLANs, mesh oddities, 2.4/5 GHz split) | Not "nearby". | Cloud fallback. The spike's router checklist notes the clinic's setup. |
| mDNS blocked by the router | Offline discovery fails. | Online path still works. Offline sharing isn't possible on that router; say so in the helper. |
| Stranger on the clinic Wi-Fi | Can see that a CruDoc device exists. | The advert has no names; the connection needs a registered device key; TLS hides the content. |
| Someone uploads wrong bytes under a fingerprint | The shared copy would be wrong. | The server rechecks every upload and deletes mismatches; every client rechecks after download. |
| Shared-copy reading is looser than per-file visibility (D3) | A clinical member who once saw a private file's record could still fetch it later by its fingerprint. | Accepted for v1 (they could have saved it anyway); X6 tightens it. Removed members lose all access immediately through the member check. |
| Removed member while offline | Their device could still connect to offline colleagues. | At most 7 days (D5); online, refused at once. |
| Old app versions | They upload to old paths and try to delete shared copies. | Old paths keep working; deletes of shared copies are refused by rules. Re-run the backfill until the minimum app version is raised. |
| Phone lost with received files | Files on the device. | Received files live in app-private storage like other Files copies. The known gap that the Windows database is not encrypted (2026-10-04 audit) also applies here; fix it under the security plan. |
| India DPDP Act and Rules | Duty of reasonable security, logs, erasure, purpose limits. | Data stays inside the clinic on the LAN and in asia-south1 in the cloud. TLS in transit. Send/receive audit logs. Clinic-only access. Erasure removes the shared copy without the 7-day wait (`purgeNow`). Note: NMC/DCI rules require keeping medical records for 3 years, which can override erasure, so erasure stays a clinic decision, not automatic. |
| Gemini Flash and security code | Subtle mistakes in the handshake or rules. | Those tasks are marked Claude (B2–B4, B8, K1–K2, N1, N3), and every phase has a gate. |
| Firebase trigger runs twice | Counts could drift. | One ref doc per record makes counting safe to repeat. |

---

## 8. Rough effort

| Phase | What ships | Days (one developer) |
|---|---|---|
| 0 | Spike report | 1–2 |
| 1 | One copy per file in the cloud, accurate storage usage, backfill | 4–6 |
| 2 | Send to colleague (through the cloud) | 3–4 |
| 3 | Trusted devices | 2–3 |
| 4 | Direct send on the same Wi-Fi | 5–7 |
| 5 | Works without internet | 3–4 |
| **Core total** | | **18–26** |
| 6 | Extras (pick and choose) | 1–3 each |

Phases 1 and 2 can ship to users before any Wi-Fi code exists. Phase 1 alone delivers the storage saving.

---

## 9. Words used in this plan

- **Fingerprint / SHA-256 hash:** a 64-character code computed from a file's bytes. The same file always gives the same code; a different file practically never does.
- **Blob / stored copy:** the one copy of a file's bytes in the bucket, named by its fingerprint.
- **Reference:** a file record that points at a stored copy. The copy is deleted only when no references are left (after a 7-day wait).
- **Offer:** "Dr A wants to give you this file"; the recipient accepts or declines.
- **mDNS / DNS-SD:** the way devices announce themselves on a local network without a server (printers, Chromecast).
- **TLS:** the encryption used by HTTPS websites.
- **Pinning:** accepting only one specific, known certificate, not any certificate.
- **AP isolation:** a router setting (common on guest Wi-Fi) that stops Wi-Fi devices from talking to each other.
- **Foreground service:** an Android mode that lets an app keep working in the background while showing a notification.
