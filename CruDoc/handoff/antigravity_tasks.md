# Antigravity tasks (Gemini 3.8 Flash, medium)

Paste ONE task at a time into Antigravity. Wait for it to finish, run the
check at the end, then paste the next. If a check fails twice, stop and
bring the error back to Claude.

Paste this header before every task:

> Project: Flutter app in `C:\Soham\Kamachya_Goshti\Svayatta_CruDoc\CruDoc`.
> Shared widgets/theme live in `C:\Soham\Kamachya_Goshti\Svayatta_CruDoc\crudoc_shared`.
> Rules: read `CruDoc/.claude/rules/crudoc-ui.md` first and follow it (use
> `context.cru` colours, `CruSpace`, `CruRadius`, `CruType`; never hard-code
> colours or sizes). Change ONLY the files named in the task. Do not
> reformat other code. Do not run `flutter run`. When done, run
> `dart analyze <the files you changed>` and fix every error.

---

## Task 1 — Grey out disabled buttons in onboarding (small)

File: `CruDoc/lib/features/onboarding/presentation/onboarding_flow.dart`

1. Find the `CruButton` whose label is `'Continue'` / `'Start free trial'` /
   `'Create account'` (inside the `Row` near the bottom of `build`).
2. Wrap that `CruButton` in:
   ```dart
   AnimatedOpacity(
     duration: const Duration(milliseconds: 200),
     curve: Curves.easeOutCubic,
     opacity: _canContinue && !_saving ? 1 : 0.4,
     child: /* the existing CruButton */,
   )
   ```
3. Keep the `Expanded` as the outermost widget.

Check: `dart analyze lib/features/onboarding` shows no errors.

---

## Task 2 — Feature usage log for Super Admin (client side)

Goal: every time a doctor opens a paid feature, write one event so the
Super Admin can see what each trial user uses.

Step 2a. Create `CruDoc/lib/core/services/feature_usage_service.dart`:
```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Records which features each doctor uses, for the Super Admin.
/// One counter doc per feature: users/{uid}/feature_usage/{moduleKey}.
class FeatureUsageService {
  FeatureUsageService._();

  /// Features already logged this app session (avoid a write per tap).
  static final Set<String> _seen = {};

  static Future<void> log(String moduleKey) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !_seen.add(moduleKey)) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('feature_usage')
          .doc(moduleKey)
          .set({
        'moduleKey': moduleKey,
        'opens': FieldValue.increment(1),
        'lastUsedAt': FieldValue.serverTimestamp(),
        'firstUsedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}
```
NOTE: `firstUsedAt` gets overwritten on each write. That is acceptable
for now; do not try to fix it.

Step 2b. Find where the desktop shell switches screens. Open
`CruDoc/lib/features/shell/presentation/desktop_shell.dart` and search for
`DesktopTab`. Find the method or callback that runs when the selected tab
changes (search for `onNavigate`). In that callback add one line:
`FeatureUsageService.log(tab.name);` (import the service).

Step 2c. Do the same in `CruDoc/lib/features/mobile/mobile_shell.dart`
where the bottom nav tab changes.

Check: `dart analyze lib/core/services/feature_usage_service.dart lib/features/shell lib/features/mobile` has no errors.

STOP after Task 2 and tell me the exact lines you changed in 2b and 2c.

---

## Task 3 — Super Admin: "Trial users" table (separate repo)

Repo: `C:\Soham\Kamachya_Goshti\CrudocSuper-admin` (it imports
`../Svayatta_CruDoc/crudoc_shared`).

1. Find the screen that lists doctors (search for `collection('users')`).
2. Add a new tab or section titled "Trial users". Query:
   `FirebaseFirestore.instance.collection('users').where('status', isEqualTo: 'trial')`.
3. Show one row per doctor with these columns:
   - Name: `displayName`
   - Practice: `onboarding.practiceType` (solo / clinic)
   - Choice: `onboarding.featureChoice` (suggested / picked)
   - Trial ends: `expiresDate` (format dd MMM yyyy)
   - Loyalty: `loyalty.stamps` + "/5"
4. Tapping a row opens a list read from
   `users/{uid}/feature_usage` showing `moduleKey`, `opens`, `lastUsedAt`.

Check: `flutter analyze` in that repo has no errors.

---

## Task 4 — Trial "try a feature" moment (do after you add the meme)

Prerequisite (you, not the AI): put your meme video/gif at
`CruDoc/assets/images/trial/meme.gif` and a cat loading gif at
`CruDoc/assets/images/trial/cat.gif`, and add the folder
`assets/images/trial/` under `flutter: assets:` in `CruDoc/pubspec.yaml`.

Step 4a. Create `CruDoc/lib/features/subscription/presentation/trial_unlock_sheet.dart`
with a function
`Future<bool> showTrialUnlockSheet(BuildContext context, FeaturePricingItem item)`
that opens a bottom sheet (phone) / dialog (desktop) and runs these
stages one after another using a `Timer`/`Future.delayed`, with an
`AnimatedSwitcher` (220 ms, easeOutCubic) between them:
1. 0.0–4.0 s: feature title + description, cat gif, a `CruProgressBar`
   filling from 0 to 1, caption "Downloading {title}…".
2. 4.0–5.2 s: text "Proceeding to payment…" with a `CruProgressBar`.
3. 5.2–7.2 s: the meme gif full width, caption "Trial pe paise lega? Sorry, you continue 🙏".
4. Then close the sheet and return `true`.
Add a small "Skip" `CruLink` at the top right that jumps to stage 4.

Step 4b. After it returns true, unlock the feature: add the module key to
`users/{uid}.enabledModules` with
`FieldValue.arrayUnion([item.moduleKey])`, and call
`FeatureUsageService.log('unlock_${item.moduleKey}')`.

Step 4c. STOP here. Do not wire it into locked screens yet. Tell me the
file path, and Claude will wire it.

Check: `dart analyze lib/features/subscription` has no errors.

---

## Not for Antigravity (needs Claude or you)
- Moving loyalty stamps to a Cloud Function (security).
- Redeploying functions before 2026-10-30 (needs your secrets).
- Tooth chart redraw, Gemini AI items, dental sync — too context-heavy for Flash.
