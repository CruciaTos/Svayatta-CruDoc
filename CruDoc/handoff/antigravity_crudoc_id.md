# Antigravity brief: CruDoc ID (find anyone on CruDoc by their ID)

Paste this whole file into Antigravity. It is a standalone brief.

## ▶ DO NOW

Do Tasks 1 to 9 in order, then run the Checks once at the end. Then **GATE: stop and report.** Do not deploy anything.

## What we're building

Today two people on CruDoc can only find each other if one has the other's phone number or email in their contacts, or if a doctor chose to be listed in the directory. This adds a **CruDoc ID** for every account:

- Every account gets a permanent, unique ID of 8 characters, shown as `K7Q9-2XMB`. It uses Crockford letters (no I, L, O or U), so it reads aloud and types cleanly. It is made the first time it's needed and never changes.
- Settings › Profile shows "Your CruDoc ID" with a Copy button.
- Typing someone's CruDoc ID finds them even if they aren't in your contacts and aren't listed:
  - Referrals › "Find a doctor on CruDoc" (to link a contact or send a referral).
  - Settings › Team › "Add a person" (invite by CruDoc ID instead of a phone number).
- Privacy: only the exact ID finds someone (no partial matches, no lists). One person can look up 60 IDs an hour. People who turned off being found (`users/{uid}.discoverable == false`) are not found. Staff can be invited by ID, but only doctors can receive referrals.

How it's stored: `users/{uid}.crudocId` holds the ID without the dash (`"K7Q92XMB"`). `crudoc_ids/{id}` holds `{uid}`, so the ID stays unique and can be looked up. Only the Cloud Functions read or write `crudoc_ids`. No new Cloud Function is added: the ID actions go into the existing `referralNetwork` and `clinicTeam` callables, so nothing needs new access settings.

## Rules (how to work)

- Work without pausing. Write every task first, then run all Checks once at the end. Run slow commands in the background and carry on.
- Change only the files named in each task. Do not rename, move or reformat anything else. The working copy has other unfinished changes: leave every other file as it is.
- Do not delete any file. Do not commit. Do not run `firebase deploy`, `gcloud`, `flutter run` or a release build.
- If a step doesn't match the code you see (a name or line is different), skip that step, write down what you saw, and carry on. Only the GATE stops the run.
- Paths are relative to the `CruDoc/` folder. Cloud Functions are in `functions/` (TypeScript), the app is in `lib/`.
- UI rules: colours, text styles, radii and spacing come from the design tokens (`context.cru`, `CruType`, `CruRadius`, `CruSpace`, `CruSize`). No new `Color(0x…)`, no `Colors.*`, no `fontSize:`.

---

## Task 1: Server helpers (new file)

Create `functions/src/crudoc-id.ts` with exactly this content:

```ts
import * as admin from "firebase-admin";
import {FieldValue} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import * as crypto from "crypto";

/**
 * CruDoc IDs: every account's permanent, unique ID ("K7Q9-2XMB"), so two
 * people can find each other without having each other's number.
 *
 * Stored as `users/{uid}.crudocId` ("K7Q92XMB", no dash) and claimed in
 * `crudoc_ids/{id}` = {uid}, which only the functions read or write (see
 * firestore.rules). Lookups are exact (no partial matches, no listing) and
 * rate-limited, so IDs can't be guessed through the app.
 */

export const CRUDOC_IDS = "crudoc_ids";
export const CRUDOC_ID_LENGTH = 8;
/** How many IDs one person may look up per hour. */
export const LOOKUPS_PER_HOUR = 60;

/** Crockford base32: no I, L, O or U, so an ID reads aloud and types cleanly. */
const ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

/** A new random ID like "K7Q92XMB" (32^8, about a trillion of them). */
export function newCrudocId(): string {
  const bytes = crypto.randomBytes(CRUDOC_ID_LENGTH);
  let id = "";
  for (let i = 0; i < CRUDOC_ID_LENGTH; i++) id += ALPHABET[bytes[i] % 32];
  return id;
}

/**
 * What someone typed, as a stored ID: case, spaces and dashes don't matter,
 * a leading "CD" is dropped, O reads as 0 and I or L as 1. Null when it
 * can't be an ID.
 */
export function normalizeCrudocId(raw: unknown): string | null {
  let s = String(raw ?? "").toUpperCase().replace(/[\s-]/g, "");
  if (s.length === CRUDOC_ID_LENGTH + 2 && s.startsWith("CD")) s = s.slice(2);
  s = s.replace(/O/g, "0").replace(/[IL]/g, "1");
  if (s.length !== CRUDOC_ID_LENGTH) return null;
  return [...s].every((ch) => ALPHABET.includes(ch)) ? s : null;
}

/** "K7Q92XMB" -> "K7Q9-2XMB", how the app shows it. */
export function formatCrudocId(id: string): string {
  return `${id.slice(0, 4)}-${id.slice(4)}`;
}

/**
 * [uid]'s CruDoc ID, made and claimed the first time it is asked for. Only
 * for someone with a profile (`users/{uid}`): writing a bare document would
 * make an unknown account look like a doctor elsewhere.
 */
export async function ensureCrudocId(uid: string): Promise<string> {
  const db = admin.firestore();
  const userRef = db.collection("users").doc(uid);
  for (let attempt = 0; attempt < 5; attempt++) {
    const id = newCrudocId();
    const claimRef = db.collection(CRUDOC_IDS).doc(id);
    const got = await db.runTransaction(async (tx) => {
      const user = await tx.get(userRef);
      if (!user.exists) {
        throw new HttpsError("failed-precondition", "Finish setting up your profile first.");
      }
      const mine = user.data()?.crudocId;
      if (typeof mine === "string" && mine.length === CRUDOC_ID_LENGTH) return mine;
      const claim = await tx.get(claimRef);
      if (claim.exists) return null; // taken: try another
      tx.set(claimRef, {uid, createdAt: FieldValue.serverTimestamp()});
      tx.update(userRef, {crudocId: id});
      return id;
    });
    if (got) return got;
  }
  throw new HttpsError("internal", "Couldn't make your CruDoc ID. Try again.");
}

/** Who holds [id] (already normalized), or null. */
export async function uidForCrudocId(id: string): Promise<string | null> {
  const snap = await admin.firestore().collection(CRUDOC_IDS).doc(id).get();
  const uid = snap.data()?.uid;
  return typeof uid === "string" && uid ? uid : null;
}
```

## Task 2: Referrals callable — "my ID" and "find by ID"

File: `functions/src/referrals.ts`

1. Under the existing import lines at the top (after the line that imports from `./crypto/patientCipher`), add:

```ts
import {
  ensureCrudocId, formatCrudocId, normalizeCrudocId, uidForCrudocId, LOOKUPS_PER_HOUR,
} from "./crudoc-id";
```

2. Find the comment block that starts `* One callable, one action per request, like clinicTeam:` (around line 667). Just above that comment block (after the closing `}` of `async function attachmentUrl`), add these two functions:

```ts
/** The caller's own CruDoc ID ("K7Q9-2XMB"), made the first time. */
async function myCrudocId(request: CallableRequest) {
  const uid = requireUid(request);
  return {crudocId: formatCrudocId(await ensureCrudocId(uid))};
}

/**
 * The person whose CruDoc ID was typed: exact match only, never a list.
 * Not found when they turned off being found. `isDoctor` says whether
 * they can receive a referral.
 */
async function findByCrudocId(request: CallableRequest) {
  const uid = requireUid(request);
  const id = normalizeCrudocId(request.data?.crudocId);
  if (!id) {
    throw new HttpsError("invalid-argument",
      "A CruDoc ID is 8 letters and numbers, like K7Q9-2XMB.");
  }
  await spend(uid, "crudocIdLookup", 1, LOOKUPS_PER_HOUR, 3600_000,
    "That's a lot of lookups. Try again in an hour.");
  const found = await uidForCrudocId(id);
  if (found === uid) {
    throw new HttpsError("invalid-argument", "That's your own CruDoc ID.");
  }
  const notFound = () => new HttpsError("not-found",
    "No one on CruDoc has that ID. Check it and try again.");
  if (!found) throw notFound();
  const doctor = await loadDoctor(found);
  if (doctor) {
    if (!doctor.discoverable) throw notFound();
    return {...cardJson(doctor), crudocId: formatCrudocId(id), isDoctor: true};
  }
  const user = (await admin.firestore().collection("users").doc(found).get()).data();
  if (!user || user.discoverable === false) throw notFound();
  const name = decryptProfileField(user.name, found) ||
    decryptProfileField(user.displayName, found) || "CruDoc user";
  return {
    uid: found, name, specialty: "", clinicName: "", city: "", handle: "",
    crudocId: formatCrudocId(id), isDoctor: false,
  };
}
```

3. In that same comment block, after the line `*   attachmentUrl        a short-lived link to one attached file`, add two lines:

```ts
 *   myCrudocId           your own CruDoc ID, made the first time
 *   findByCrudocId       the one person with a CruDoc ID you typed
```

4. In the `switch` inside `export const referralNetwork`, after `case "attachmentUrl": return attachmentUrl(request);` add:

```ts
    case "myCrudocId": return myCrudocId(request);
    case "findByCrudocId": return findByCrudocId(request);
```

## Task 3: Team invites by CruDoc ID (server)

File: `functions/src/clinic.ts`

1. With the other imports at the top, add:

```ts
import {normalizeCrudocId, uidForCrudocId} from "./crudoc-id";
```

2. Find `case "invite": {` (around line 916). Inside it, replace exactly these lines:

```ts
      const rawPhone = typeof data.phone === "string" ? data.phone.trim() : "";
      const rawEmail = typeof data.email === "string" ? data.email.trim() : "";

      if ((rawPhone && rawEmail) || (!rawPhone && !rawEmail)) {
        throw new HttpsError("invalid-argument", "Provide exactly one of phone or email.");
      }
```

with:

```ts
      let rawPhone = typeof data.phone === "string" ? data.phone.trim() : "";
      let rawEmail = typeof data.email === "string" ? data.email.trim() : "";

      // Invited by CruDoc ID: the invite goes to that account's phone (or
      // verified email), exactly as if it had been typed in.
      if (typeof data.crudocId === "string" && data.crudocId.trim()) {
        if (rawPhone || rawEmail) {
          throw new HttpsError("invalid-argument",
            "Invite by a CruDoc ID, a phone number or an email, not more than one.");
        }
        const id = normalizeCrudocId(data.crudocId);
        if (!id) {
          throw new HttpsError("invalid-argument",
            "A CruDoc ID is 8 letters and numbers, like K7Q9-2XMB.");
        }
        const idUid = await uidForCrudocId(id);
        const account = idUid && await isDiscoverable(idUid) ?
          await admin.auth().getUser(idUid).catch(() => null) : null;
        if (!account) {
          throw new HttpsError("not-found",
            "No one on CruDoc has that ID. Check it and try again.");
        }
        if (account.uid === caller.uid) {
          throw new HttpsError("invalid-argument", "That's your own CruDoc ID.");
        }
        if (account.phoneNumber) {
          rawPhone = account.phoneNumber;
        } else if (account.email && account.emailVerified) {
          rawEmail = account.email;
        } else {
          throw new HttpsError("failed-precondition",
            "That person hasn't added a phone number to CruDoc yet. Invite them by phone instead.");
        }
      }

      if ((rawPhone && rawEmail) || (!rawPhone && !rawEmail)) {
        throw new HttpsError("invalid-argument", "Provide exactly one of phone or email.");
      }
```

Everything after this in the `invite` case stays as it is (it already finds the account by phone and puts the invite in their app).

## Task 4: Firestore rules

File: `firestore.rules`

1. Find the block `match /doctor_handles/{handle} {` (around line 682). Right after its closing `}`, add:

```
    // Which uid holds each CruDoc ID (functions/src/crudoc-id.ts). Server
    // only: IDs are looked up one at a time through the functions, so they
    // can't be listed or guessed in bulk.
    match /crudoc_ids/{id} {
      allow read, write: if false;
    }
```

2. Inside `match /users/{userId} {`, the text `'lastPaymentAmount', 'lastPaymentMethod', 'trialStartedAt']));` appears **twice** (once in `allow create`, once in `allow update`). In **both** places, replace it with:

```
'lastPaymentAmount', 'lastPaymentMethod', 'trialStartedAt', 'crudocId']));
```

This stops anyone setting or changing their own CruDoc ID from the app. Change nothing else in the rules.

## Task 5: Server tests

1. Create `functions/test/crudoc-id.test.js`:

```js
/**
 * Tests for CruDoc IDs (src/crudoc-id.ts): the pure helpers.
 *
 * Run with:  npm run build && node test/crudoc-id.test.js
 */
const assert = require('assert');
const {newCrudocId, normalizeCrudocId, formatCrudocId, CRUDOC_ID_LENGTH} =
  require('../lib/crudoc-id');

// New IDs: 8 characters from the Crockford alphabet, different each time.
const seen = new Set();
for (let i = 0; i < 2000; i++) {
  const id = newCrudocId();
  assert.strictEqual(id.length, CRUDOC_ID_LENGTH);
  assert.match(id, /^[0-9A-HJKMNP-TV-Z]{8}$/);
  seen.add(id);
}
assert.ok(seen.size > 1990, 'IDs repeat far too often');

// Forgiving input.
assert.strictEqual(normalizeCrudocId('k7q9-2xmb'), 'K7Q92XMB');
assert.strictEqual(normalizeCrudocId(' K7Q9 2XMB '), 'K7Q92XMB');
assert.strictEqual(normalizeCrudocId('CD-K7Q9-2XMB'), 'K7Q92XMB');
assert.strictEqual(normalizeCrudocId('KOQ9-2XMB'), 'K0Q92XMB'); // O reads as 0
assert.strictEqual(normalizeCrudocId('KIQ9-2XML'), 'K1Q92XM1'); // I and L read as 1

// Not IDs.
assert.strictEqual(normalizeCrudocId('K7Q9-2XM'), null);
assert.strictEqual(normalizeCrudocId('K7Q9-2XMBB'), null);
assert.strictEqual(normalizeCrudocId('K7Q9-2XMU'), null); // U is never used
assert.strictEqual(normalizeCrudocId('K7Q9_2XMB'), null);
assert.strictEqual(normalizeCrudocId(''), null);
assert.strictEqual(normalizeCrudocId(undefined), null);

assert.strictEqual(formatCrudocId('K7Q92XMB'), 'K7Q9-2XMB');
console.log('crudoc-id: all tests passed');
```

2. In `functions/package.json`, in the `"test"` script, add ` && node test/crudoc-id.test.js` at the very end, before the closing quote.

## Task 6: App API

File: `lib/features/dental/referrals/referral_network.dart`

1. Right after the `CruDocDoctor` class (it ends just before the comment `/// The signed-in doctor's own directory listing`), add:

```dart
/// Someone found by their CruDoc ID. Only doctors can receive referrals.
class CrudocPerson {
  const CrudocPerson({
    required this.doctor,
    required this.crudocId,
    required this.isDoctor,
  });

  /// Their name (and, for a doctor, specialty, clinic and city).
  final CruDocDoctor doctor;

  /// "K7Q9-2XMB".
  final String crudocId;
  final bool isDoctor;

  factory CrudocPerson.fromMap(Map<String, dynamic> m) => CrudocPerson(
    doctor: CruDocDoctor.fromMap(m),
    crudocId: m['crudocId'] as String? ?? '',
    isDoctor: m['isDoctor'] == true,
  );
}

/// Whether [text] could be a CruDoc ID ("K7Q9-2XMB": any case, spaces or
/// dashes, an optional "CD" in front, O for 0 and I or L for 1). Mirrors
/// normalizeCrudocId in functions/src/crudoc-id.ts.
bool looksLikeCrudocId(String text) {
  var s = text.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  if (s.length == 10 && s.startsWith('CD')) s = s.substring(2);
  s = s.replaceAll('O', '0').replaceAll(RegExp('[IL]'), '1');
  return RegExp(r'^[0-9A-HJKMNP-TV-Z]{8}$').hasMatch(s);
}
```

2. Inside `class ReferralNetworkApi`, right after the `matchContacts` method (it ends with `return out;` and `}`), add:

```dart
  /// The signed-in person's CruDoc ID ("K7Q9-2XMB"), made the first time.
  Future<String> myCrudocId() async {
    final data = await _call('myCrudocId');
    return data['crudocId'] as String? ?? '';
  }

  /// The one person with CruDoc ID [id]. Throws [ReferralNetworkException]
  /// when no one has it, or they turned off being found.
  Future<CrudocPerson> findByCrudocId(String id) async {
    final data = await _call('findByCrudocId', {'crudocId': id.trim()});
    return CrudocPerson.fromMap(data);
  }
```

3. Right after `final myDirectoryCardProvider = ...;` (it ends with `});`), add:

```dart
/// The signed-in person's CruDoc ID, made the first time it's asked for.
/// Empty in the demo.
final myCrudocIdProvider = FutureProvider<String>((ref) async {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null || DemoSessionService.isDemoMode) return '';
  return ReferralNetworkApi.instance.myCrudocId();
});
```

## Task 7: "Find a doctor on CruDoc" also takes a CruDoc ID

File: `lib/features/dental/referrals/referral_share_flows.dart`, class `_FindDoctorDialogState` (around line 981).

1. Under `String _searched = '';` add:

```dart
  /// Why a typed CruDoc ID found no doctor (shown when nothing else matches).
  String? _idNote;
```

2. Replace the whole `_search()` method with:

```dart
  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.length < 2) return;
    setState(() {
      _searching = true;
      _idNote = null;
    });
    try {
      // A CruDoc ID finds that one person, listed or not. A name can look
      // like an ID too, so the directory is searched either way.
      CruDocDoctor? byId;
      if (looksLikeCrudocId(q)) {
        try {
          final person = await ReferralNetworkApi.instance.findByCrudocId(q);
          if (person.isDoctor) {
            byId = person.doctor;
          } else {
            _idNote =
                "${person.doctor.name} is on CruDoc but isn't a doctor, so "
                "they can't receive referrals.";
          }
        } on ReferralNetworkException catch (e) {
          _idNote = e.message;
        }
      }
      final found = await searchDirectory(
        q,
        selfUid: FirebaseAuth.instance.currentUser?.uid,
      );
      if (mounted) {
        setState(
          () => _results = [
            ?byId,
            for (final d in found)
              if (d.uid != byId?.uid) d,
          ],
        );
      }
    } catch (_) {
      if (mounted) recToast(context, 'Couldn\'t search right now. Try again.');
    } finally {
      if (mounted) {
        setState(() {
          _searching = false;
          _searched = q;
        });
      }
    }
  }
```

3. In `build`, change the dialog subtitle from `'Doctors who chose to be listed'` to `'Listed doctors, or anyone by their CruDoc ID'`.

4. Change the field label from `'Name, @handle, specialty or city'` to `'Name, @handle, CruDoc ID, specialty or city'`.

5. Replace the empty-results message block:

```dart
          if (_results.isEmpty && _searched.isNotEmpty && !_searching)
            Text(
              'No listed doctor matches "$_searched". If they use CruDoc, '
              'save their phone number: it is matched even if they aren\'t '
              'listed.',
              style: CruType.caption.tint(c.label2),
            ),
```

with:

```dart
          if (_results.isEmpty && _searched.isNotEmpty && !_searching)
            Text(
              _idNote ??
                  'No listed doctor matches "$_searched". Ask them for their '
                      'CruDoc ID (Settings › Profile), or save their phone '
                      'number: either finds them even if they aren\'t listed.',
              style: CruType.caption.tint(c.label2),
            ),
```

## Task 8: "Your CruDoc ID" in Settings › Profile

File: `lib/features/settings/presentation/desktop_settings_screen.dart`

1. Add these imports with the others at the top, if they aren't there already:

```dart
import 'package:flutter/services.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_network.dart';
```

2. In the profile section's `build` (it returns `_Stack([ const DoctorLoyaltyCard(), _SettingsCard(title: 'Specialty', ...), _SettingsCard(title: 'Sign-in', ...) ])`, around line 575), add `const _CrudocIdCard(),` as a new item **between** the Specialty card and the Sign-in card.

3. At the end of the profile section (just above the comment line `// PLAN & BILLING`, or the `// ====` line above it), add:

```dart
/// "Your CruDoc ID": anyone on CruDoc can find you with it, to send you a
/// referral or invite you to their clinic, even without your number.
class _CrudocIdCard extends ConsumerWidget {
  const _CrudocIdCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(myCrudocIdProvider);
    final value = id.value ?? '';
    return _SettingsCard(
      title: 'Your CruDoc ID',
      description:
          'Share it so anyone on CruDoc can find you, to send you a referral '
          "or invite you to their clinic, even if they don't have your number.",
      child: _ActionRow(
        title: id.isLoading
            ? 'Loading…'
            : id.hasError
            ? "Couldn't load it. Check the connection."
            : value,
        detail: value.isEmpty ? null : 'Only this exact ID finds you.',
        action: value.isEmpty
            ? const SizedBox.shrink()
            : CruCapsuleButton(
                label: 'Copy',
                kind: CruCapsuleKind.surface,
                height: CruSize.control,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: value));
                  _toast(context, 'CruDoc ID copied');
                },
              ),
      ),
    );
  }
}
```

## Task 9: Invite by CruDoc ID (app)

1. File: `lib/core/clinic/clinic_team_api.dart`, method `invite(...)` (around line 161):
   - Add a parameter `String? crudocId,` right after `String? email,`.
   - In the map sent to `_call('invite', {...})`, add `'crudocId': ?crudocId,` right after `'email': ?email,`.

2. File: `lib/features/team/presentation/invite_sheet.dart`, class `_InviteDialogState`:

   a. Under `final _phone = TextEditingController();` add:

```dart
  final _crudocId = TextEditingController();

  /// Invite by CruDoc ID instead of a phone number.
  bool _byId = false;
```

   b. In `dispose()`, under `_phone.dispose();` add `_crudocId.dispose();`.

   c. Add this import with the others at the top:

```dart
import 'package:doctor_management_app/features/dental/referrals/referral_network.dart';
```

   d. In `_send(...)`, replace these lines:

```dart
    if (name.isEmpty || _phone.text.trim().isEmpty) {
      setState(() => _notice = 'Add a name and a phone number.');
      return;
    }
    final phone = invitePhoneE164(_phone.text);
    if (phone == null) {
      setState(
        () => _notice = 'Enter a 10-digit mobile number, or the full number '
            'starting with +.',
      );
      return;
    }
```

   with:

```dart
    final crudocId = _crudocId.text.trim();
    if (_byId) {
      if (name.isEmpty || !looksLikeCrudocId(crudocId)) {
        setState(
          () => _notice = 'Add a name and their CruDoc ID, like K7Q9-2XMB.',
        );
        return;
      }
    } else if (name.isEmpty || _phone.text.trim().isEmpty) {
      setState(() => _notice = 'Add a name and a phone number.');
      return;
    }
    final phone = _byId ? null : invitePhoneE164(_phone.text);
    if (!_byId && phone == null) {
      setState(
        () => _notice = 'Enter a 10-digit mobile number, or the full number '
            'starting with +.',
      );
      return;
    }
```

   e. In the same method, in the `ClinicTeamApi.instance.invite(` call, change `phone: phone,` to:

```dart
        phone: phone,
        crudocId: _byId ? crudocId : null,
```

   and change `_sentTo = phone;` to `_sentTo = phone ?? '';`.

   (Someone invited by ID is always already on CruDoc, so the "Invite sent" screen shows and the phone number isn't needed.)

   f. In `build`, replace the phone field:

```dart
          CruTextField(
            label: 'Phone number',
            controller: _phone,
            prefix: _phone.text.trimLeft().startsWith('+') ? null : '+91',
            keyboardType: TextInputType.phone,
            tabular: true,
            onChanged: (_) => setState(() {}),
          ),
```

   with:

```dart
          CruSegmentedControl<bool>(
            semanticLabel: 'Invite by',
            segments: const [
              CruSegment(false, 'Phone number'),
              CruSegment(true, 'CruDoc ID'),
            ],
            selected: _byId,
            onChanged: (v) => setState(() {
              _byId = v;
              _notice = null;
            }),
          ),
          const SizedBox(height: CruSpace.s12),
          if (_byId)
            CruTextField(
              label: 'CruDoc ID',
              controller: _crudocId,
              hint: 'K7Q9-2XMB',
              textCapitalization: TextCapitalization.characters,
              tabular: true,
            )
          else
            CruTextField(
              label: 'Phone number',
              controller: _phone,
              prefix: _phone.text.trimLeft().startsWith('+') ? null : '+91',
              keyboardType: TextInputType.phone,
              tabular: true,
              onChanged: (_) => setState(() {}),
            ),
```

   g. Change the dialog subtitle `'Invite them by phone number. They join from CruDoc on their phone.'` (it is split over two lines as `'Invite them by phone number. They join from CruDoc on '` and `'their phone.'`) to:

```dart
      subtitle: 'Invite them by phone number or CruDoc ID. They join from '
          'CruDoc on their phone.',
```

---

## Checks (run once, at the end)

1. Cloud Functions, from the `functions/` folder:

```
npm run build
node test/crudoc-id.test.js
node test/referrals.test.js
node test/clinic.test.js
node test/clinic-actions.test.js
```

   All must pass. If `npm run build` fails, fix only the lines you added.

2. The app, from the `CruDoc/` folder:

```
flutter analyze lib/features/dental/referrals lib/features/team/presentation lib/features/settings/presentation/desktop_settings_screen.dart lib/core/clinic/clinic_team_api.dart
```

   Fix any error or warning in the lines you added. Ignore issues in lines you didn't touch, but list them in your report.

3. Don't run the app: the new server code isn't deployed yet, so the ID can't load.

## GATE: stop here and report

Report: each task done or skipped (with what you saw), and the Check results. Do not deploy.

For Soham, after review (not for Antigravity): deploy from the `CruDoc/` folder with

```
$env:FUNCTIONS_DISCOVERY_TIMEOUT=90; firebase deploy --only "functions:referralNetwork,functions:clinicTeam,firestore:rules" --project svayatta-crudoc-dev
```

Both callables already exist and are reachable, so no `--no-invoker-iam-check` step is needed. Then test with two accounts: Settings › Profile shows an ID on each. Account B types A's ID in Referrals › Contacts › New contact › Find on CruDoc, and A appears. In Settings › Team › Add a person › CruDoc ID, B's ID sends the invite straight into B's app.
