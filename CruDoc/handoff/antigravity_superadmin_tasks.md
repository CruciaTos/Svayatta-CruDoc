# Antigravity tasks: Super Admin "Trial users" tab

Repo: `C:\Soham\Kamachya_Goshti\CrudocSuper-admin` (Flutter web, Riverpod).
Paste the HEADER, then ONE task. Run the check. Next task only if it passes.
If a check fails twice, stop and bring the error to Claude.

## HEADER (paste before every task)

> Project: Flutter web app in `C:\Soham\Kamachya_Goshti\CrudocSuper-admin`.
> It imports shared widgets from `package:crudoc_shared/widgets/cru/cru.dart`
> (CruCard, CruButton, CruIcons, CruType, CruSpace, CruRadius, `context.cru`
> colours). Never hard-code colours, font sizes or spacing; use those tokens.
> Copy the style of `lib/screens/dashboard/receptionist_lines_screen.dart`.
> Change ONLY the files named in the task. Do not reformat other code.
> Do not edit anything in `../Svayatta_CruDoc`. When done, run
> `flutter analyze lib` and fix every error you introduced.

Data you will read (already live in Firestore, written by the clinic app):
- `users/{uid}` fields:
  - `displayName` (String), `email` (String)
  - `status` (String: "trial", "active", "expired", ...)
  - `expiresDate` (Timestamp, may be missing)
  - `specialty` (String)
  - `enabledModules` (List<String>)
  - `onboarding` (Map, may be missing):
    `practiceType` ("solo"/"clinic"), `featureChoice` ("suggested"/"picked"),
    `chosenModules` (List<String>), `completedAt` (Timestamp)
  - `loyalty` (Map, may be missing):
    `stamps` (int 0-5), `stampedMonths` (List<String> like "2026-10"),
    `freeMonthsClaimed` (int)
- `users/{uid}/feature_usage/{moduleKey}` docs (may be empty for now):
  `moduleKey` (String), `opens` (int), `lastUsedAt` (Timestamp)

Every field may be missing. Always use `?.` and `??` with a fallback of
"—" for text and 0 for numbers. Never crash on a missing field.

---

## Task S1: Model for one trial row

Create `lib/models/trial_user_model.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// One doctor as shown on the Trial users tab.
class TrialUserModel {
  const TrialUserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.status,
    required this.specialty,
    this.practiceType,
    this.featureChoice,
    this.chosenModules = const [],
    this.expiresDate,
    this.onboardedAt,
    this.stamps = 0,
    this.freeMonthsClaimed = 0,
  });

  final String id;
  final String name;
  final String email;
  final String status;
  final String specialty;
  final String? practiceType;
  final String? featureChoice;
  final List<String> chosenModules;
  final DateTime? expiresDate;
  final DateTime? onboardedAt;
  final int stamps;
  final int freeMonthsClaimed;

  int? get daysLeft => expiresDate?.difference(DateTime.now()).inDays;

  static DateTime? _date(Object? v) => v is Timestamp
      ? v.toDate()
      : v is String
      ? DateTime.tryParse(v)
      : null;

  factory TrialUserModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final ob = d['onboarding'] is Map ? d['onboarding'] as Map : const {};
    final lo = d['loyalty'] is Map ? d['loyalty'] as Map : const {};
    return TrialUserModel(
      id: doc.id,
      name: (d['displayName'] as String?)?.trim().isNotEmpty == true
          ? d['displayName'] as String
          : '—',
      email: d['email'] as String? ?? '—',
      status: d['status'] as String? ?? '—',
      specialty: d['specialty'] as String? ?? '—',
      practiceType: ob['practiceType'] as String?,
      featureChoice: ob['featureChoice'] as String?,
      chosenModules: [
        for (final m in (ob['chosenModules'] as List?) ?? const []) '$m',
      ],
      expiresDate: _date(d['expiresDate']),
      onboardedAt: _date(ob['completedAt']),
      stamps: ((lo['stamps'] as num?) ?? 0).toInt(),
      freeMonthsClaimed: ((lo['freeMonthsClaimed'] as num?) ?? 0).toInt(),
    );
  }
}

/// One feature a doctor has opened.
class FeatureUsageModel {
  const FeatureUsageModel({
    required this.moduleKey,
    required this.opens,
    this.lastUsedAt,
  });

  final String moduleKey;
  final int opens;
  final DateTime? lastUsedAt;

  factory FeatureUsageModel.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const {};
    final last = d['lastUsedAt'];
    return FeatureUsageModel(
      moduleKey: d['moduleKey'] as String? ?? doc.id,
      opens: ((d['opens'] as num?) ?? 0).toInt(),
      lastUsedAt: last is Timestamp ? last.toDate() : null,
    );
  }
}
```

Check: `flutter analyze lib/models/trial_user_model.dart` shows no errors.

---

## Task S2: Providers

Create `lib/providers/trial_user_provider.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/trial_user_model.dart';

/// Doctors who finished onboarding, newest first. Includes trial and
/// converted (paid) doctors so conversion is visible.
final trialUsersProvider = StreamProvider<List<TrialUserModel>>((ref) {
  return FirebaseFirestore.instance
      .collection('users')
      .where('status', whereIn: ['trial', 'active', 'expired'])
      .snapshots()
      .map((snap) {
        final list = snap.docs
            .map(TrialUserModel.fromDoc)
            .where((u) => u.onboardedAt != null)
            .toList();
        list.sort((a, b) => b.onboardedAt!.compareTo(a.onboardedAt!));
        return list;
      });
});

/// Features one doctor has opened, most used first.
final featureUsageProvider =
    StreamProvider.family<List<FeatureUsageModel>, String>((ref, uid) {
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('feature_usage')
      .snapshots()
      .map((snap) {
        final list = snap.docs.map(FeatureUsageModel.fromDoc).toList();
        list.sort((a, b) => b.opens.compareTo(a.opens));
        return list;
      });
});
```

If the analyzer says `StreamProvider.family` does not exist, look at how
`lib/providers/receptionist_line_provider.dart` imports Riverpod and use
the same import (it may need `package:flutter_riverpod/legacy.dart`).

Check: `flutter analyze lib/providers/trial_user_provider.dart` has no errors.

---

## Task S3: The Trial users screen

Create `lib/screens/dashboard/trial_users_screen.dart` with a
`ConsumerWidget` named `SuperAdminTrialUsersScreen`.

Layout, top to bottom (copy padding and title style from
`receptionist_lines_screen.dart`):

1. Title "Trial users". Under it, one line of summary text:
   "{N} onboarded · {T} on trial · {P} paid · {E} expired", where the
   counts come from `status` ("trial" / "active" / "expired").
2. A `CruCard` holding a table (use a `Column` of rows, not `DataTable`).
   One header row, then one row per doctor with these columns:
   - Doctor: `name` (bold) with `email` under it (smaller, grey)
   - Specialty
   - Practice: "Solo" / "Clinic" / "—"
   - Features: "Suggested" or "Picked ({chosenModules.length})"
   - Status: "Trial · {daysLeft} days left", "Paid", or "Expired".
     If daysLeft < 0 show "Trial ended".
   - Loyalty: "{stamps}/5" (use tabular figures:
     `CruType.text.tabular`). If freeMonthsClaimed > 0 append
     " · {freeMonthsClaimed} free claimed".
   Put a `CruSeparator()` between rows.
3. Tapping a row opens a dialog (Task S4).
4. Loading: show a `CircularProgressIndicator` centred.
   Error: show the error text. Empty list: show
   "No doctors have finished onboarding yet."

On narrow screens (width < 900) show each doctor as a stacked card
instead of a table row (name, then the other values as label: value lines).

Check: `flutter analyze lib/screens/dashboard/trial_users_screen.dart`
has no errors.

---

## Task S4: Feature usage dialog

In the same file, add
`void showFeatureUsageDialog(BuildContext context, TrialUserModel user)`.
It opens a `Dialog` (max width 520) with:
- Title: the doctor's name.
- Line: "Turned on at signup: " + `chosenModules` joined by ", " (or "none").
- A list from `ref.watch(featureUsageProvider(user.id))` (wrap the dialog
  body in a `Consumer`). Each row: `moduleKey`, "{opens} opens",
  and `lastUsedAt` formatted as `dd MMM, HH:mm` with
  `DateFormat('dd MMM, HH:mm')` from `package:intl/intl.dart`.
- Empty list text: "No feature use recorded yet."
- A "Close" `CruButton` with `kind: CruButtonKind.inset`.

Call it from the row tap in Task S3.

Check: `flutter analyze lib/screens/dashboard/trial_users_screen.dart`
has no errors.

---

## Task S5: Add the tab to the sidebar

Edit exactly these three places:

1. `lib/providers/ui_provider.dart`: in `enum SuperAdminTab`, add
   `trialUsers,` right after `doctors,`. In the `label` switch add:
   ```dart
   case SuperAdminTab.trialUsers:
     return 'Trial users';
   ```
2. `lib/screens/main_shell.dart`, the nav list near the top (group
   'OVERVIEW'): right after the `_AdminNavItem` whose tab is
   `SuperAdminTab.doctors`, add:
   ```dart
   _AdminNavItem(
     tab: SuperAdminTab.trialUsers,
     label: 'Trial users',
     icon: CruIcons.userCheck,
   ),
   ```
3. `lib/screens/main_shell.dart`, method `_buildContent`: add
   ```dart
   case SuperAdminTab.trialUsers:
     return const SuperAdminTrialUsersScreen();
   ```
   and import `dashboard/trial_users_screen.dart` the same way the other
   screens are imported.

If the analyzer reports another `switch` on `SuperAdminTab` that is now
missing a case (for example keyboard shortcuts or a badge switch), add
the `trialUsers` case there too, copying what `doctors` does. Do NOT add
a keyboard shortcut.

Check: `flutter analyze lib` shows no errors. Then run
`flutter build web --release` and confirm it finishes.

STOP here. Tell the user "S1-S5 done, build passed". Do NOT deploy.

---

## Deploy (the user does this, or asks Claude)

From `C:\Soham\Kamachya_Goshti\CrudocSuper-admin`:
1. `flutter build web --release`
2. Delete `build/web/.env.local` if it exists.
3. `npx vercel deploy --prod --cwd build/web`
Live at https://superadmin.svayatta.in

Note: the Firestore rule that lets Super Admin read `feature_usage` is
already deployed (2026-10-03). Feature usage stays empty until the clinic
app's Task 2 (in `antigravity_tasks.md`) is done and shipped.
