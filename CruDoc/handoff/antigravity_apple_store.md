# Antigravity tasks: get CruDoc ready for the iPhone App Store and the Mac App Store

You are fixing config files and a few screens in this codebase. This whole file
is your brief. Claude (the lead) reviews your work at the GATE and updates this
file. The reasons behind each task are in `docs/apple_store_readiness_audit.md`
(read it once, do not edit it).

## ▶ DO NOW

**Do every task in Part A (A1..A9), Part B (B1..B7), Part D (D1..D3), Part E
(E1..E4) and Part F (F1..F2), in that order.** Stop only at the GATE line at the
end of Part F. Part C is for the human and Claude, not you.

Anywhere a task says "STOP", that means: skip that part, write one line in your
report saying what and why, and carry on with the next task.

---

## Rules

> Project: `C:\Soham\Kamachya_Goshti\Svayatta_CruDoc\CruDoc`, a Flutter app on
> Firebase. You are on **Windows**: you cannot run Xcode, `pod install`,
> `flutter build ios` or `flutter build macos`. So **nothing in this file can be
> proven by building**. Do the edits exactly, check them as the task says, and in
> your report mark every Apple-side result "not built (no Mac)".
> - Change ONLY the files a task names (you may create the new files it
>   names). Do not reformat, rename or "improve" other code. Run `dart format`
>   only on Dart files you changed or created.
> - Never deploy, never `git commit` / `git push`.
> - Never put a real secret (API key, token, password) in a file. Use the
>   placeholders the task names.
> - UI: read `CruDoc/.claude/rules/crudoc-ui.md` first and follow it (colours
>   from `context.cru`, `CruSpace`, `CruRadius`, `CruType`). One filled button
>   per dialog. Copy existing dialogs (`PatientDialog`, `CruFormDialog`) instead
>   of inventing widgets.
> - Property lists (`.plist`, `.entitlements`, `.xcprivacy`) are XML: keep them
>   valid. After editing one, check it with
>   `python -c "import plistlib,sys; plistlib.load(open(sys.argv[1],'rb'))" <file>`
>   (no output means valid).
> - Never run the whole `flutter test` suite. Run only test files a task names.
> - If the code you find does not match the task, skip that task, say what you
>   found, and carry on.

**How to work (no pauses):** write all tasks first. Run `flutter analyze lib`
ONCE at the end of Part B and fix what it reports in files you changed. Run slow
commands in the background. Do not stop to ask questions; make the conservative
choice, note it, and carry on.

---

## Facts you need

| Thing | Where |
|---|---|
| iOS app | `ios/Runner/` (`Info.plist`, `AppDelegate.swift`, `GoogleService-Info.plist`), project `ios/Runner.xcodeproj/project.pbxproj` |
| macOS app | `macos/Runner/` (`Info.plist`, `DebugProfile.entitlements`, `Release.entitlements`, `Configs/AppInfo.xcconfig`), project `macos/Runner.xcodeproj/project.pbxproj` |
| Bundle ID (keep) | `com.crudoc.app` |
| Sign-in screen | `lib/features/auth/presentation/auth_screen.dart` (`_handleGoogleSignIn`, line ~589; the Google button, line ~799) and `lib/core/services/auth_service.dart` |
| Settings (desktop) | `lib/features/settings/presentation/desktop_settings_screen.dart`; phone: `lib/features/mobile/mobile_more.dart` |
| Plan purchase screens | `lib/features/subscription/presentation/` (`subscription_billing_page.dart`, `plan_upgrade_card.dart`, `feature_upgrade_sheet.dart`, `payment_checkout_sheet.dart`); callers: `desktop_settings_screen.dart` line ~753, `mobile_more.dart` line ~257, `lib/core/router/app_router.dart` line ~72 |
| Cloud AI calls | `lib/core/services/gemini_json_client.dart`, `lib/core/services/voice_transcription_service.dart`, `lib/features/scan/data/scan_reader.dart`, `lib/features/voice/services/voice_form_ai.dart`, `lib/features/patients/services/patient_voice_fill_service.dart` |
| Bonjour service | `_crudoc._tcp` (`lib/features/files/lan/lan_mdns_service.dart`) |
| Callable client | `lib/core/services/callable_client.dart` |

---

# PART A: config files

## A1. iOS `Info.plist`

File: `ios/Runner/Info.plist`. Inside the top-level `<dict>`:

1. Add

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>CruDoc finds other CruDoc devices in your clinic on the same Wi-Fi so you can send files to colleagues and connect to your scanner or imaging server.</string>
<key>NSBonjourServices</key>
<array>
	<string>_crudoc._tcp</string>
</array>
<key>UIBackgroundModes</key>
<array>
	<string>remote-notification</string>
</array>
```

2. Replace the text of `NSPhotoLibraryUsageDescription` with:
`CruDoc lets you pick photos and scans from your library to attach to a patient's record or to a supplier bill.`
3. Do NOT add `ITSAppUsesNonExemptEncryption` (the human decides; see Part C).

## A2. iOS entitlements (push, Sign in with Apple)

1. Create `ios/Runner/Runner.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>aps-environment</key>
	<string>development</string>
	<key>com.apple.developer.applesignin</key>
	<array>
		<string>Default</string>
	</array>
</dict>
</plist>
```

(`development` is switched to production by the distribution profile when
archiving; do not change it.)
2. In `ios/Runner.xcodeproj/project.pbxproj`, the **Runner app target** has three
build-configuration blocks (Debug, Release, Profile) that contain
`PRODUCT_BUNDLE_IDENTIFIER = com.crudoc.app;` (not `.RunnerTests`; currently at
lines ~375, ~554, ~576). In each of those three blocks add the line
`CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;` next to the other
`CODE_SIGN_*` / `CURRENT_PROJECT_VERSION` lines. Also register the file like
`Info.plist` is registered (a `PBXFileReference` with
`lastKnownFileType = text.plist.entitlements; path = Runner.entitlements;`, and
an entry in the `Runner` group next to `Info.plist`, line ~117). Use a new
unique 24-character uppercase hex id.

## A3. iOS privacy manifest, and bundle `GoogleService-Info.plist`

1. Create `ios/Runner/PrivacyInfo.xcprivacy`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSPrivacyTracking</key>
	<false/>
	<key>NSPrivacyTrackingDomains</key>
	<array/>
	<key>NSPrivacyCollectedDataTypes</key>
	<array>
		<!-- repeat this dict for each type below -->
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeHealth</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
	</array>
	<key>NSPrivacyAccessedAPITypes</key>
	<array>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategoryUserDefaults</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array><string>CA92.1</string></array>
		</dict>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array><string>C617.1</string></array>
		</dict>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategoryDiskSpace</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array><string>E174.1</string></array>
		</dict>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategorySystemBootTime</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array><string>35F9.1</string></array>
		</dict>
	</array>
</dict>
</plist>
```

Write one collected-data `<dict>` (same shape as the Health one) for each of
these `NSPrivacyCollectedDataType…` values: `Name`, `EmailAddress`,
`PhoneNumber`, `Health`, `Contacts`, `AudioData`, `PhotosorVideos`,
`PreciseLocation`, `UserID`, `OtherUserContent`. All Linked = true, Tracking =
false, purpose `NSPrivacyCollectedDataTypePurposeAppFunctionality`.
2. Register BOTH `ios/Runner/PrivacyInfo.xcprivacy` and the existing
`ios/Runner/GoogleService-Info.plist` as bundle resources in
`ios/Runner.xcodeproj/project.pbxproj` (today neither is in the project). Copy
how `Assets.xcassets` is registered: (a) a `PBXFileReference` line (e.g.
`lastKnownFileType = text.xml; path = PrivacyInfo.xcprivacy;` and
`lastKnownFileType = text.plist.xml; path = GoogleService-Info.plist;`), (b) a
`PBXBuildFile` line `… in Resources`, (c) the file in the `Runner` group
(line ~115 area), (d) the build file in the Runner target's
`PBXResourcesBuildPhase` (line ~215-225). New ids: unique 24-character
uppercase hex. STOP this part if the structure differs from what is described.

## A4. iOS minimum version

Set the minimum iOS version to **15.5**:
`ios/Runner.xcodeproj/project.pbxproj` every `IPHONEOS_DEPLOYMENT_TARGET = 13.0;`
(lines ~353, ~479, ~530) becomes `15.5`. If `ios/Flutter/AppFrameworkInfo.plist`
has a `MinimumOSVersion` key, set it to `15.5` too.

## A5. Google Maps key out of the source

1. `ios/Runner/AppDelegate.swift`: replace the hard-coded call
   `GMSServices.provideAPIKey("YOUR_GOOGLE_MAPS_API_KEY")` with:

```swift
if let key = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
   !key.isEmpty, !key.hasPrefix("$(") {
  GMSServices.provideAPIKey(key)
}
```

   Keep the rest of the file. Update the comment above it to say the key comes
   from `ios/Flutter/Secrets.xcconfig`.
2. `ios/Runner/Info.plist`: add `<key>GMSApiKey</key><string>$(GOOGLE_MAPS_API_KEY)</string>`.
3. `ios/Flutter/Debug.xcconfig` and `Release.xcconfig` (and `Profile.xcconfig` if
   it exists): add a first line `#include? "Secrets.xcconfig"` (the `?` means
   "skip if missing").
4. Create `ios/Flutter/Secrets.example.xcconfig` containing
   `GOOGLE_MAPS_API_KEY = PUT_YOUR_KEY_HERE`.
5. Add `Flutter/Secrets.xcconfig` to `ios/.gitignore`.

## A6. macOS `Info.plist` and app name

1. `macos/Runner/Configs/AppInfo.xcconfig`: `PRODUCT_NAME = CruDoc`.
2. `macos/Runner/Info.plist`: add inside the top `<dict>`:

```xml
<key>CFBundleDisplayName</key>
<string>CruDoc</string>
<key>LSApplicationCategoryType</key>
<string>public.app-category.medical</string>
<key>NSMicrophoneUsageDescription</key>
<string>CruDoc uses the microphone to record consultation audio for the AI Voice Scribe and to understand voice commands. Recordings are deleted after the doctor reviews them.</string>
<key>NSCameraUsageDescription</key>
<string>CruDoc uses the camera to scan notes, reports and supplier bills.</string>
<key>NSContactsUsageDescription</key>
<string>CruDoc checks your contacts' phone numbers to show colleagues already on CruDoc, so you can invite them to your clinic. Your contacts aren't stored.</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>CruDoc turns what you say into commands, like booking an appointment or opening a patient.</string>
<key>NSLocalNetworkUsageDescription</key>
<string>CruDoc finds other CruDoc devices in your clinic on the same Wi-Fi so you can send files to colleagues and connect to your scanner or imaging server.</string>
<key>NSBonjourServices</key>
<array>
	<string>_crudoc._tcp</string>
</array>
<key>CFBundleURLTypes</key>
<array>
	<dict>
		<key>CFBundleTypeRole</key>
		<string>Editor</string>
		<key>CFBundleURLSchemes</key>
		<array>
			<string>com.googleusercontent.apps.474729174031-gtf53g9053lilt2cebjgkvinvj0kopkh</string>
		</array>
	</dict>
</array>
```

   (macOS 15 and later also asks before an app uses the local network, so it
   needs the same two keys as iOS; the URL scheme is the same one `ios/Runner/Info.plist` already has).

## A7. macOS entitlements (the big one: without these the sandboxed app has no internet)

Edit BOTH `macos/Runner/DebugProfile.entitlements` and
`macos/Runner/Release.entitlements`. Keep what is there. Both files must end up
containing these keys (add the missing ones):

```xml
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.network.client</key><true/>
<key>com.apple.security.network.server</key><true/>
<key>com.apple.security.device.audio-input</key><true/>
<key>com.apple.security.device.camera</key><true/>
<key>com.apple.security.files.user-selected.read-write</key><true/>
<key>com.apple.security.print</key><true/>
<key>com.apple.security.personal-information.location</key><true/>
<key>com.apple.security.personal-information.addressbook</key><true/>
<key>com.apple.developer.applesignin</key>
<array><string>Default</string></array>
<key>keychain-access-groups</key>
<array><string>$(AppIdentifierPrefix)com.crudoc.app</string></array>
```

`DebugProfile.entitlements` keeps its existing
`com.apple.security.cs.allow-jit` (Debug only). `Release.entitlements` must NOT
have `allow-jit`. Do not add any other entitlement.

## A8. macOS privacy manifest

Copy the finished `ios/Runner/PrivacyInfo.xcprivacy` to
`macos/Runner/PrivacyInfo.xcprivacy` unchanged. Register it in
`macos/Runner.xcodeproj/project.pbxproj` the same way as in A3 (copy how
`Assets.xcassets` is registered: `PBXFileReference`, `PBXBuildFile … in Resources`,
the Runner group, the Runner target's `PBXResourcesBuildPhase` at line ~293-300).
STOP this part if the structure differs.

## A9. macOS minimum version

In `macos/Runner.xcodeproj/project.pbxproj`, `MACOSX_DEPLOYMENT_TARGET = 10.15;`
becomes `11.0` (every occurrence). Leave everything else.

### Part A check

Run the `plistlib` check (see Rules) on every `.plist`, `.entitlements` and
`.xcprivacy` file you edited or created, in `ios/` and `macos/`. Paste "all
valid" or the failures.

---

# PART B: app code

## B1. Privacy policy and Terms links

1. Create `lib/core/legal_links.dart`:

```dart
/// The two links Apple (and Google) require inside the app. The human fills
/// these in before submission; an empty value hides the link row.
const String kPrivacyPolicyUrl = '';
const String kTermsUrl = '';
```

2. Create `lib/core/widgets/legal_links_row.dart`: a small `StatelessWidget`
   `LegalLinksRow` that shows "Privacy policy" and "Terms" as quiet text
   buttons (`CruType.caption`, `context.cru.label3`), each opening its URL with
   `launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)`, and
   showing nothing at all when both constants are empty.
3. Show it (a) at the bottom of the sign-in screen
   (`auth_screen.dart`, under the form), (b) in Settings: at the bottom of
   `desktop_settings_screen.dart` and in `mobile_more.dart` (find the end of the
   list; keep the change small).

## B2. Sign in with Apple (Apple and Mac only)

1. `pubspec.yaml`: add `sign_in_with_apple: ^7.0.1` and `crypto` is already
   there. Run `flutter pub get`.
2. `lib/core/services/auth_service.dart`: add

```dart
Future<UserCredential> signInWithApple() async {
  final raw = _randomNonce();
  final nonce = sha256.convert(utf8.encode(raw)).toString();
  final apple = await SignInWithApple.getAppleIDCredential(
    scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
    nonce: nonce,
  );
  final credential = OAuthProvider('apple.com').credential(
    idToken: apple.identityToken,
    rawNonce: raw,
    accessToken: apple.authorizationCode,
  );
  final result = await _auth.signInWithCredential(credential);
  // Apple only sends the name the first time: keep it.
  final given = apple.givenName?.trim() ?? '';
  final family = apple.familyName?.trim() ?? '';
  if ((result.user?.displayName ?? '').isEmpty && (given + family).isNotEmpty) {
    await result.user?.updateDisplayName('$given $family'.trim());
  }
  return result;
}
```

   with a private `_randomNonce([int length = 32])` using `Random.secure()`
   over the characters `0-9A-Za-z-._`. Use the same imports/`_auth` field the
   file already uses; add `dart:convert`, `dart:math`, `package:crypto/crypto.dart`.
3. `auth_screen.dart`: next to the Google button (line ~799) add a **Sign in
   with Apple** button, shown only when `Platform.isIOS || Platform.isMacOS`
   (not on the web). Use `SignInWithAppleButton` from the package with the
   style that matches the theme (black in the light theme, white in the dark
   theme). Its handler must do exactly what `_handleGoogleSignIn` (line ~589)
   does after it has a `UserCredential` (create/load the user profile, route
   on): copy that code path; do not duplicate the Google-specific parts. Show
   errors the same way, and treat the user cancelling as "do nothing".
4. Apple requires this button to be at least as prominent as the Google one:
   same height and width.

## B3. Account deletion (App Review 5.1.1(v))

Claude is writing the server function `deleteAccount` (a callable). You write
the app side, calling it by name through the callable client
(`lib/core/services/callable_client.dart`; look at how another caller uses it).
Expected reply: `{ok: true}`.

1. Create `lib/features/settings/presentation/delete_account_dialog.dart` with
   `Future<bool> showDeleteAccountDialog(BuildContext context, WidgetRef ref)`
   (a `PatientDialog`-style dialog, copy `PatientDialog` from
   `lib/features/patients/presentation/widgets/patient_dialogs.dart`):
   - Title "Delete your account?". Body, plain words: "This permanently deletes
     your CruDoc login. If you own a clinic, it also deletes the clinic's
     patients, visits, files and invoices. This cannot be undone."
   - A text field: "Type DELETE to confirm". The confirm button ("Delete
     account", destructive red text per the red-only-for-safety rule: use the
     existing red style the other destructive dialogs use) stays disabled until
     the text equals `DELETE`.
   - On confirm: re-authenticate if Firebase says it is needed
     (`requires-recent-login`): for Google use `AuthService`'s Google flow, for
     email ask for the password, for Apple call `signInWithApple()`; then call
     the callable `deleteAccount`; then `FirebaseAuth.instance.signOut()` and
     return `true`. Show a spinner while working and the error text on failure.
     For an Apple-sign-in user, before calling the callable, also call
     `FirebaseAuth.instance.revokeTokenWithAuthorizationCode(code)` with the
     `authorizationCode` you got from the fresh Apple sign-in (Apple requires the
     token to be revoked on deletion).
2. Add a **Delete account** row at the bottom of Settings (`desktop_settings_screen.dart`,
   and `mobile_more.dart`), above the legal links row, quiet style (not a
   filled button). After it returns `true`, go to the sign-in screen the same
   way the existing "Sign out" row does.
3. If a callable client helper needs a new method, add the smallest one.
   STOP (skip) if you cannot find where Sign out is done; report it.

## B4. Keep the UPI checkout off Apple devices (App Review 3.1.1)

Apple does not allow buying app features inside the app except through Apple's
purchase system. On iPhone, iPad and Mac the UPI checkout must never appear:
plans are bought there with Apple in-app purchase (Part D). In this task you
only close the UPI door and leave a clearly marked place for Part D to fill.
**Nothing in the app may tell doctors to pay elsewhere.**

1. Create `lib/core/utils/store_policy.dart`:

```dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Apple's rules: no buying features inside the app on iPhone, iPad or Mac.
bool get storePurchasesAllowed =>
    kIsWeb || !(Platform.isIOS || Platform.isMacOS);
```

2. In `subscription_billing_page.dart`: when `!storePurchasesAllowed`, do not
   show the UPI price list or checkout. Show the read-only plan card (plan name,
   valid-until line, which modules are on: the existing widgets for that) and,
   under it, a `// PART D: Apple checkout goes here` comment where Part D will
   put the Apple purchase list. No "Pay by UPI", no link, no mention of the web
   or of paying elsewhere.
3. In `plan_upgrade_card.dart` and its use in `mobile_more.dart` (line ~257):
   when `!storePurchasesAllowed`, keep the card and its `onOpen` (it opens the
   billing page); only remove any UPI-specific wording/price from the card.
4. In `feature_upgrade_sheet.dart` and wherever a locked module opens it (search
   `DoctorFeatureGuard.require` / `PlanModules.instance.require`): when
   `!storePurchasesAllowed`, never open `PaymentCheckoutSheet`; open the
   billing page instead (Part D makes it purchasable).
5. Do not delete any purchase code; only gate it.

## B5. Ask before using the cloud AI (App Review 5.1.2(i))

Patient audio, text and scans are sent to Google's Gemini (through Firebase AI)
for scribe notes, voice commands, scan reading and form filling. The doctor must
agree first, and be able to withdraw.

1. Create `lib/core/services/ai_consent.dart`:

```dart
import 'package:shared_preferences/shared_preferences.dart';

/// The doctor's choice about sending data to the cloud AI. Stored per device.
class AiConsent {
  static const _key = 'ai.consent.v1'; // 'yes' | 'no' | unset
  static bool? _cached;

  static Future<bool?> read() async {
    if (_cached != null) return _cached;
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_key);
    return _cached = v == null ? null : v == 'yes';
  }

  static Future<void> set(bool granted) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, granted ? 'yes' : 'no');
    _cached = granted;
  }

  /// True only when the doctor said yes.
  static Future<bool> get granted async => (await read()) == true;
}

class AiConsentRequired implements Exception {
  const AiConsentRequired();
  @override
  String toString() =>
      'AI is off. Turn it on in Settings > AI assistance to use this.';
}
```

2. In each of the five cloud-AI files listed under "Facts", add at the top of
   the function that actually calls the model:
   `if (!await AiConsent.granted) throw const AiConsentRequired();`
   Where that function's callers already catch errors and show `e.toString()`
   or a generic message, this is enough. STOP (skip) for any file where the call
   site is not obvious; report it.
3. Ask once: after the first sign-in (find where the app routes to the home
   screen for a signed-in doctor; if that is unclear, show it from the dashboard
   screen's `initState`/first build, once, when `AiConsent.read()` returns
   null) show a dialog (copy `PatientDialog`):
   Title "Use AI features?". Body: "CruDoc can use Google's Gemini AI to write
   session notes from your recordings, understand voice commands, read scanned
   pages and fill forms. When you use these, the audio, text or image you give
   it, which can include patient details, is sent to Google to be processed.
   Google does not use it to train its models. You can change this any time in
   Settings > AI assistance." Buttons: "Allow" (filled) and "Not now". Store the
   answer with `AiConsent.set`.
4. `lib/features/settings/presentation/ai_assistance_section.dart`: add a switch
   "Use cloud AI" bound to `AiConsent` (read on build, `set` on change).
5. Do not claim "Google does not use it to train" unless the existing text in
   `ai_assistance_section.dart` ("Privacy & Security Guarantee") already says
   so; if it does not, remove that sentence from the dialog.

## B6. Hide features that do not exist on Mac

`google_mlkit_text_recognition` and `cunning_document_scanner` are
iOS/Android only. Files: `lib/features/inventory/data/services/ocr_service.dart`,
`lib/features/scan/data/scan_capture.dart` and the buttons/screens that call
them (search for `OcrService`, `ScanCapture`, `scan_flow`).

1. Add to `store_policy.dart`: `bool get documentScanSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);`
2. Where the **Scan** quick action and the "scan a supplier bill" buttons are
   shown, hide them when `!documentScanSupported` (the picker/file route, if
   there is one, stays). Do not delete code.
3. Make sure no top-level code in those two files runs on macOS (no plugin call
   at import or `initState`). STOP if you cannot tell; report it.

## B7. "Review before use" line on AI drafts (App Review 1.4.1)

In `lib/features/scribe/presentation/prescription_generation_sheet.dart`, and
the session-notes review screen of the scribe (find it under
`lib/features/scribe/presentation/`: the screen where the doctor reads the AI
draft before saving), add one quiet caption (`CruType.caption`, label3 colour)
near the top of the draft: "AI draft. Review and correct before you use it."
Same line on `lib/features/reports/presentation/medical_report_generation_sheet.dart`.
One line, no dialog.

---

# PART D: buy plans with Apple in-app purchase (iPhone, iPad, Mac)

How it works. Each paid module in `featureCatalog`
(`crudoc_shared/lib/subscription/feature_catalog.dart`, the items with
`isBaseModule: false`) becomes one **auto-renewable monthly subscription** in
App Store Connect, each in its OWN subscription group (so a doctor can hold
several at once). Product id for a module:
`com.crudoc.app.<moduleKey>.monthly` (for example
`com.crudoc.app.revenue.monthly`). The human creates these in App Store Connect
(Part C). Claude writes the server callable that checks the purchase with Apple
and switches the module on. You write the app side against this contract:

- Callable name: `verifyApplePurchase` (call it like other callables, via
  `lib/core/services/callable_client.dart`).
- Request: `{productId: String, transactionId: String, receipt: String}`, where
  `receipt` is `purchaseDetails.verificationData.serverVerificationData`.
- Reply: `{ok: true}` on success. On failure the callable throws; show its
  message.
- After a successful reply the app re-reads the plan the normal way (the
  existing subscription provider refresh); do not set modules locally.

Apple's rules for the screen: show Apple's own price strings
(`ProductDetails.price`, never our own rupee figure), the length ("1 month"),
that it renews automatically until cancelled, a **Restore purchases** button, a
link to manage subscriptions, and links to the privacy policy and terms.

## D1. The purchase service

1. `pubspec.yaml`: add `in_app_purchase: ^3.2.3`. Run `flutter pub get`.
2. Create `lib/features/subscription/data/apple_iap_service.dart`:

```dart
import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:crudoc_shared/subscription/feature_catalog.dart';

/// The product id Apple sells a module under.
String appleProductId(String moduleKey) => 'com.crudoc.app.$moduleKey.monthly';

class AppleIapService {
  AppleIapService({
    InAppPurchase? store,
    required this.verify,
  }) : _store = store ?? InAppPurchase.instance;

  final InAppPurchase _store;

  /// Sends a purchase to the server (the `verifyApplePurchase` callable).
  /// Throws if the server refuses.
  final Future<void> Function(PurchaseDetails purchase) verify;

  StreamSubscription<List<PurchaseDetails>>? _sub;

  /// Apple's products for every paid module, by module key.
  Future<Map<String, ProductDetails>> products() async {
    if (!await _store.isAvailable()) return const {};
    final paid = [
      for (final f in featureCatalog)
        if (!f.isBaseModule) f.moduleKey,
    ];
    final response = await _store.queryProductDetails({
      for (final k in paid) appleProductId(k),
    });
    return {
      for (final p in response.productDetails)
        for (final k in paid)
          if (p.id == appleProductId(k)) k: p,
    };
  }

  /// Starts listening for purchase updates (call once, before any buy or
  /// restore). [onResult] gets (purchase, errorMessage?) per update.
  void listen(void Function(PurchaseDetails, String?) onResult) {
    _sub ??= _store.purchaseStream.listen((list) async {
      for (final p in list) {
        if (p.status == PurchaseStatus.pending) continue;
        if (p.status == PurchaseStatus.error ||
            p.status == PurchaseStatus.canceled) {
          if (p.pendingCompletePurchase) await _store.completePurchase(p);
          onResult(
            p,
            p.status == PurchaseStatus.canceled ? null : p.error?.message,
          );
          continue;
        }
        // purchased or restored: the server must agree before we finish it.
        try {
          await verify(p);
          if (p.pendingCompletePurchase) await _store.completePurchase(p);
          onResult(p, null);
        } catch (e) {
          onResult(p, '$e');
        }
      }
    });
  }

  Future<void> buy(ProductDetails product) =>
      _store.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product));

  Future<void> restore() => _store.restorePurchases();

  void dispose() => _sub?.cancel();
}
```

   (Apple subscriptions go through `buyNonConsumable` in this package. If the
   `in_app_purchase` version you get has a different method name, use the
   package's documented subscription purchase method and note it in your
   report.)
3. Where `verify` is created (D2) it must call the callable
   `verifyApplePurchase` with `purchase.productID`, `purchase.purchaseID ?? ''`
   and `purchase.verificationData.serverVerificationData`.

## D2. The Apple checkout list

Create `lib/features/subscription/presentation/apple_checkout_list.dart`: a
`ConsumerStatefulWidget` `AppleCheckoutList` (no scaffold; it goes inside a
page). It:

1. Creates an `AppleIapService` in `initState` (with the callable-based
   `verify`), calls `listen(...)`, loads `products()`, and disposes the service.
2. Shows one row per paid module in `featureCatalog` that Apple returned a
   product for: title and description from the catalog, Apple's `price` string
   and "per month" on the right, and an inset **Buy** button (a "Active" quiet
   label instead when the module is already on: use the same
   `isModuleUnlocked` check `subscription_billing_page.dart` uses). Hide
   modules Apple did not return (do not show our own prices).
3. While a purchase is in flight, disable that row's button and show a small
   spinner. On `onResult` with an error show a snackbar with the message; on
   success refresh the plan (invalidate the same provider the billing page
   reads) and show "Plan updated".
4. Under the list: a text button **Restore purchases** (calls `restore()`), a
   text button **Manage subscriptions**
   (`launchUrl(Uri.parse('https://apps.apple.com/account/subscriptions'), mode: LaunchMode.externalApplication)`),
   the renewal line "Subscriptions renew every month until you cancel. Cancel
   at least 24 hours before the end of the period in your Apple ID settings.
   Payment is charged to your Apple ID.", and the `LegalLinksRow` from B1.
5. If `products()` returns empty, show "Purchases aren't available right now."
   and nothing else (do not show prices).

## D3. Put the list where Part B left the placeholder

In `subscription_billing_page.dart`, replace the `// PART D: Apple checkout goes
here` comment with `const AppleCheckoutList()`, shown only when
`!storePurchasesAllowed` (the Apple platforms). Nothing else changes: other
platforms keep the UPI checkout exactly as it is.

---

# PART E: Wi-Fi file sharing on iPhone, iPad and Mac

The sharing code (`lib/features/files/lan/`, `data/wifi_offers.dart`) already
works on Android and Windows. On Apple devices three things differ, and this
part handles them:

1. **Permission.** The first time the app uses the local network, iOS asks
   "CruDoc would like to find and connect to devices on your local network".
   Part A already adds the two Info.plist keys that make this question appear.
   We must not let it pop up cold at launch: explain first, ask second.
2. **Foreground only.** iOS stops a suspended app's server and Bonjour advert
   within seconds, and there is no always-on notification like Android's. So
   Wi-Fi transfer works while CruDoc is open on the iPhone. The existing
   fallback (the send sheet's "☁ Will go through the cloud", and the server
   push `onFileOfferCreated` in `functions/src/file_offers.ts`) covers the
   rest. We only have to make the app resume cleanly and tell the doctor.
3. **If the answer was "Don't Allow"**, iOS gives no error we can rely on:
   discovery simply finds nothing. We show help with a button to the iPhone's
   Settings.

All of E applies only when `Platform.isIOS || Platform.isMacOS`. Do not change
how Android and Windows behave.

## E1. Start only after the doctor says yes (Apple only)

1. Create `lib/features/files/lan/lan_startup.dart`:

```dart
import 'package:shared_preferences/shared_preferences.dart';

/// Lets screens start nearby sharing after the doctor agrees (Apple devices).
/// `main.dart` sets [starter] each time a clinic opens.
class LanStartup {
  static Future<void> Function()? starter;

  /// Apple devices ask the doctor first; everywhere else it is on already.
  static const askedKey = 'crudoc.lan.askedApple';

  static Future<bool> hasAsked() async =>
      (await SharedPreferences.getInstance()).getBool(askedKey) ?? false;

  static Future<void> markAsked() async =>
      (await SharedPreferences.getInstance()).setBool(askedKey, true);
}
```

2. `lib/main.dart`, `_startLanServices`: right after the existing
   `if (!(prefs.getBool('crudoc.lan.enabled') ?? true)) return;` line add, for
   Apple devices only:
   `if ((Platform.isIOS || Platform.isMacOS) && !(prefs.getBool(LanStartup.askedKey) ?? false)) return;`
   and, at the top of the function body (before any early return), register
   `LanStartup.starter = () => _startLanServices(access, myUid);`. Add the
   imports. Do not move or rename anything else.
3. Create `lib/features/files/presentation/widgets/nearby_ask_card.dart`: a
   small card `NearbyAskCard` (copy the look of another quiet info card in
   `lib/features/files/presentation/`), shown at the top of the Files screen
   only when `(Platform.isIOS || Platform.isMacOS)` and `LanStartup.hasAsked()`
   is false and `LanStartup.starter != null`. Text: title "Send files to
   colleagues on clinic Wi-Fi", body "CruDoc will ask to find devices on your
   local network. Say Allow so files can go straight between your devices
   without the internet. You can change this later in Settings." Buttons:
   "Turn on" (filled; calls `LanStartup.markAsked()` then
   `await LanStartup.starter?.call()`, then hides the card) and "Not now"
   (quiet; hides the card for this session only; it shows again next launch).
   Add the card to `files_screen.dart` (find the top of the screen's column;
   keep the change small).

## E2. If nearby devices do not show up (Apple only)

1. In `lib/features/files/presentation/nearby_sharing_settings.dart` (the
   `NearbySharingSettingsCard`), below the existing rows add, Apple only, a
   quiet text block: "Colleagues not showing up? On this device open Settings,
   then CruDoc, and turn on Local Network. Both devices must be on the same
   Wi-Fi, and the clinic's Wi-Fi must allow devices to see each other
   (guest Wi-Fi often does not)." and a text button **Open Settings** that does
   `launchUrl(Uri.parse('app-settings:'))` (import `url_launcher`).
2. In `lib/features/files/presentation/send_sheet.dart`, where it shows
   "☁ Will go through the cloud" (line ~266), no change in behaviour; only on
   Apple devices add a caption under that line when the colleague is not nearby:
   "Not on the same Wi-Fi, or CruDoc is closed on their phone." Skip if the
   text is not easy to add there; report it.

## E3. Resume cleanly when the app comes back (Apple only)

1. `lib/features/files/data/wifi_offers.dart`: add a public method on
   `WifiOffers`: `Future<void> checkNow() => _tryWaiting();` (leave
   `_tryWaiting` private and unchanged).
2. Create `lib/features/files/lan/lan_lifecycle.dart`:

```dart
import 'dart:io' show Platform;
import 'package:flutter/widgets.dart';
import 'package:doctor_management_app/features/files/data/wifi_offers.dart';
import 'package:doctor_management_app/features/files/lan/lan_mdns_service.dart';
import 'package:doctor_management_app/features/files/lan/lan_server.dart';

/// iOS suspends the server and the Bonjour advert in the background. When the
/// app is back in front, bring them up again and look for waiting files.
class LanLifecycle with WidgetsBindingObserver {
  LanLifecycle._();
  static final LanLifecycle instance = LanLifecycle._();
  bool _on = false;

  void start() {
    if (_on || !(Platform.isIOS || Platform.isMacOS)) return;
    _on = true;
    WidgetsBinding.instance.addObserver(this);
  }

  void stop() {
    if (!_on) return;
    WidgetsBinding.instance.removeObserver(this);
    _on = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    () async {
      final port = await LanServer.instance.start(); // no-op if running
      await LanMdnsService.instance.stopBroadcast();
      await LanMdnsService.instance.startBroadcast(port: port);
      await WifiOffers.instance.checkNow();
    }();
  }
}
```

   First read `LanServer.start()` in `lan_server.dart`: if calling it while it is
   already running would start a second server or change the port, then check
   for a running state (a getter such as `isRunning` / `port`) and only call
   `start()` when it is stopped, otherwise reuse the current port. STOP (skip
   E3) if you cannot do this safely; report it.
3. `lib/main.dart`: in `_runLanServices` add `LanLifecycle.instance.start();`
   after `WifiOffers.instance.start(...)`, and in the `close:` block add
   `LanLifecycle.instance.stop();` before `WifiOffers.instance.stop();`.
4. `lib/features/files/presentation/transfer_progress_tray.dart`: when a
   transfer is in progress and the platform is Apple, show one quiet line:
   "Keep CruDoc open until this finishes." (`CruType.caption`, label3 colour).

## E4. Apple device name and platform

`lib/features/files/lan/device_identity.dart`:
- in `_load`, `_platform`: add `Platform.isIOS ? 'ios' : Platform.isMacOS ? 'macos' :`
  in front of the existing fallback (keep the `android` and `windows` cases).
- in `_defaultDeviceName`, the last line: return `'iPhone'` when `Platform.isIOS`,
  `'Mac'` when `Platform.isMacOS`, otherwise the existing Android/Windows
  fallback.
Before changing `_platform`, search the project for other code that switches on
that string (`'android'`, `'windows'`) and make sure `'ios'` / `'macos'` fall
into a sensible default there; report what you found.

---

# PART F: AirDrop (iPhone, iPad, Mac)

Apple gives apps no way to open AirDrop directly, list AirDrop devices, or pick
a recipient. What an app can do is (a) put AirDrop in the system share sheet,
and (b) be offered as "Open in CruDoc" when a file arrives. That is all Part F
builds. It is a second route next to the Wi-Fi sharing of Part E, for people
outside the clinic or devices not on the clinic Wi-Fi.

Apple devices only (`Platform.isIOS || Platform.isMacOS`). A Mac receiving an
AirDrop always puts the file in Downloads (it never goes straight into an app),
so receiving in F2 is iPhone and iPad only; on a Mac the doctor drags the file
in from Downloads, which `desktop_drop` already supports.

## F1. "Share (AirDrop…)" on a file

1. In `lib/features/files/presentation/files_actions.dart` add, near
   `sendToColleague` (line ~534):

```dart
/// Opens the system share sheet (AirDrop, Messages, Mail…) for [file].
static Future<void> shareOutside(BuildContext context, PatientFile file) async {
  final box = context.findRenderObject() as RenderBox?;
  final origin = box == null
      ? null
      : box.localToGlobal(Offset.zero) & box.size; // iPad needs this
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => PatientDialog(
      title: 'Share outside CruDoc?',
      cancelLabel: 'Cancel',
      confirmLabel: 'Share',
      onConfirm: () => Navigator.of(ctx).pop(true),
      body: Text(
        'A shared copy leaves CruDoc\'s protection. Share it only with '
        'someone who is allowed to see this patient\'s record.',
        style: CruType.text.tint(ctx.cru.label2),
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  File? temp;
  try {
    final local = await FilesRepository.instance.localCopy(file);
    final dir = await getTemporaryDirectory();
    temp = await File('${dir.path}/${file.name}').writeAsBytes(
      await local.readAsBytes(),
      flush: true,
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(temp.path, mimeType: file.contentType)],
        sharePositionOrigin: origin,
      ),
    );
  } catch (_) {
    messenger?.showSnackBar(
      const SnackBar(
        content: Text("Couldn't share this file. Try again."),
        behavior: SnackBarBehavior.floating,
      ),
    );
  } finally {
    try {
      await temp?.delete();
    } catch (_) {}
  }
}
```

   Check first what `FilesRepository.instance.localCopy` returns (a `File`, or
   something with a path or bytes) and use it correctly; the sketch assumes a
   `File`. Imports: `dart:io`, `package:share_plus/share_plus.dart`,
   `package:path_provider/path_provider.dart`, `patient_dialogs.dart`
   (`PatientDialog`) as other files do. Keep the temporary copy's name equal to
   the file's name, and always delete it afterwards.
2. Show it, Apple only (`Platform.isIOS || Platform.isMacOS`), as a menu / action
   item **"Share (AirDrop…)"** next to where "Send to colleague" is offered:
   find the callers of `FilesActions.sendToColleague` (the file row menu in
   `lib/features/files/presentation/widgets/` and the file viewer's top bar in
   `file_viewer.dart`) and add the item beside it, using the same style and a
   share icon from `CruIcons` (if none exists, reuse the closest one; do not
   add new icon assets). Pass the widget's own `context` so the iPad popover
   anchors to it.

## F2. "Open in CruDoc" when a file arrives by AirDrop (iPhone and iPad)

1. `ios/Runner/Info.plist`: add inside the top-level `<dict>`:

```xml
<key>LSSupportsOpeningDocumentsInPlace</key>
<false/>
<key>CFBundleDocumentTypes</key>
<array>
	<dict>
		<key>CFBundleTypeName</key>
		<string>PDF document</string>
		<key>CFBundleTypeRole</key>
		<string>Viewer</string>
		<key>LSHandlerRank</key>
		<string>Alternate</string>
		<key>LSItemContentTypes</key>
		<array><string>com.adobe.pdf</string></array>
	</dict>
	<dict>
		<key>CFBundleTypeName</key>
		<string>Image</string>
		<key>CFBundleTypeRole</key>
		<string>Viewer</string>
		<key>LSHandlerRank</key>
		<string>Alternate</string>
		<key>LSItemContentTypes</key>
		<array><string>public.image</string></array>
	</dict>
	<dict>
		<key>CFBundleTypeName</key>
		<string>DICOM image</string>
		<key>CFBundleTypeRole</key>
		<string>Viewer</string>
		<key>LSHandlerRank</key>
		<string>Alternate</string>
		<key>LSItemContentTypes</key>
		<array><string>org.nema.dicom</string></array>
	</dict>
</array>
<key>UTImportedTypeDeclarations</key>
<array>
	<dict>
		<key>UTTypeIdentifier</key>
		<string>org.nema.dicom</string>
		<key>UTTypeDescription</key>
		<string>DICOM image</string>
		<key>UTTypeConformsTo</key>
		<array><string>public.data</string></array>
		<key>UTTypeTagSpecification</key>
		<dict>
			<key>public.filename-extension</key>
			<array><string>dcm</string></array>
		</dict>
	</dict>
</array>
```

   ("Alternate" rank: CruDoc is offered, but never made the default PDF or image
   app.)
2. `pubspec.yaml`: add `app_links: ^6.4.0`; run `flutter pub get`. (It reports
   every URL the app is opened with, including `file://` ones; if the version you
   get has a different API than `AppLinks().uriLinkStream` and
   `AppLinks().getInitialLink()`, use the package's documented equivalents.)
3. Create `lib/features/files/data/incoming_open_in.dart`: a class
   `IncomingOpenIn` with `static void start()` (iOS only; do nothing elsewhere;
   safe to call twice) that listens to the app-links stream and also checks the
   initial link. For each `file` URI: take `uri.toFilePath()`, ignore it if the
   file does not exist, and add the path to a pending list. A small flush
   routine adds the pending paths with
   `FilesActions.addPaths(context, paths)` where `context` is
   `appRouter.routerDelegate.navigatorKey.currentContext` (import
   `lib/core/router/app_router.dart`, as `voice_overlay.dart` does). It flushes
   only when `FirebaseAuth.instance.currentUser != null` and that context is not
   null; otherwise it retries every 2 seconds for up to 2 minutes, then drops
   the files. That sends the doctor through the normal "Add files" dialog,
   where they pick the patient, so nothing is filed without a person choosing.
4. `lib/main.dart`: call `IncomingOpenIn.start();` once, after the app and router
   are set up (find where `runApp` is called and add it just before; one line).
5. This cannot be tested here (no iPhone). In your report say "AirDrop receive:
   not tested (no iPhone)". If `app_links` does not exist for the project's
   Dart/Flutter versions, skip F2 and report it.

### Part B, D, E and F check

`flutter analyze lib` once; fix what it reports in files you changed. Then write
the report.

**GATE: STOP HERE. Report every file you changed or created, the output of the
plist check and of `flutter analyze`, each task you skipped with the reason, and
the line "Apple builds: not built (no Mac)".**

---

# PART C: not for Antigravity

**The human (Soham) does these on Apple's and Firebase's websites, then on a Mac
or a macOS CI runner:**

1. Join the Apple Developer Program; create the App IDs for `com.crudoc.app`
   (iOS and macOS) with Push Notifications and Sign in with Apple switched on;
   create the App Store Connect records.
2. Fill `kPrivacyPolicyUrl` and `kTermsUrl` in `lib/core/legal_links.dart`; have
   the policy pages live and covering patient data, AI processing, and
   deletion.
3. Decide export compliance (encryption: SQLCipher/AES) and then add
   `ITSAppUsesNonExemptEncryption` to both `Info.plist` files.
4. Firebase console: enable the Apple provider; upload the APNs key; register
   the macOS app and add its `GoogleService-Info.plist`; create the iOS Google
   Maps key and put it in `ios/Flutter/Secrets.xcconfig`.
5. App Store Connect: privacy "nutrition label" answers (health, contacts,
   audio, photos, location, identifiers, user content; none used for tracking),
   age rating, screenshots (iPhone 6.9", iPad 13", Mac), support URL, review
   notes with a demo login (an `@crudoc.com` demo account).
6. In-app purchase setup in App Store Connect: sign the **Paid Apps agreement**
   and add bank and tax details; join the **App Store Small Business Program**
   (Apple's commission is then 15% instead of 30%; check you qualify); create
   one **auto-renewable subscription group per paid module**, each with one
   monthly subscription whose product id is exactly
   `com.crudoc.app.<moduleKey>.monthly` (module keys: see
   `featureCatalog`, items that are not base modules); pick an Apple price
   point for each (Apple's price points are fixed steps, and Apple keeps its
   cut, so you may want to raise the rupee price); fill each product's name,
   description and review screenshot; create an **In-App Purchase key**
   (App Store Connect, Users and Access, Integrations) and give Claude the key
   id and issuer id (never paste the key file into chat: put it in the
   Firebase secret store when Claude asks); create **sandbox testers**; and set
   the "App Store Server Notifications" URL to the function URL Claude gives you.
7. On a Mac: `flutter pub get`, `cd ios && pod install`, open the workspace,
   set the signing team, build, archive, upload to TestFlight; same for macOS.
   Test a purchase with a sandbox tester. Fix anything the Mac build reports
   (Claude can help from the log).

**Claude keeps:**
- The `deleteAccount` Cloud Function (deletes Auth user, clinic data, storage;
  handles owners vs members).
- The `verifyApplePurchase` Cloud Function (checks the purchase with Apple's
  App Store Server API, switches the module on in the same way
  `writePaidPlan` does for UPI) and the App Store Server Notifications
  endpoint (renewals, cancellations, refunds switch the module off).
- Firestore rules / sync changes, and anything the first Mac build reveals.

## Done

(nothing yet)
