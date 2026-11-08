# Apple readiness audit: iPhone App Store and Mac App Store

Date: 2026-11-08. Static review of `CruDoc/ios`, `CruDoc/macos`, `pubspec.yaml`
and the app code, on Windows. **Nothing was built**: Xcode, `pod install`,
signing and TestFlight need a Mac (or a macOS CI runner). A "pass" below means
the setting is present; it does not prove the build works.

Result: **not ready.** Of 41 checks, 12 pass, 25 fail, and 4 are partial, a
note, or need a decision from you. The "Needs you" list at the end is work in
Apple's and Firebase's websites. The fixes the code can make are in
`handoff/antigravity_apple_store.md`.

## iPhone (and iPad) app

| # | Check | Result | Notes |
|---|---|---|---|
| 1 | One bundle ID everywhere | Pass | `com.crudoc.app` in iOS, macOS and `firebase_options.dart` |
| 2 | `GoogleService-Info.plist` present | Pass | `ios/Runner/` |
| 3 | Usage strings: microphone, speech, camera, photos, location, contacts | Pass | all six present and specific |
| 4 | Photo-library text matches real use | Fail | says "attach medicine receipts"; the app also attaches patient files and X-rays |
| 5 | Local-network permission | **Fail** | the app browses `_crudoc._tcp` (Bonjour) and shares over the LAN, but `NSLocalNetworkUsageDescription` and `NSBonjourServices` are missing: iOS 14+ then denies local-network access without ever asking, so discovery finds nothing and LAN connections fail (it does not crash) |
| 6 | Push notifications set up | **Fail** | `firebase_messaging` is used, but there is no `Runner.entitlements` (`aps-environment`) and no `UIBackgroundModes: remote-notification` |
| 7 | App privacy manifest (`PrivacyInfo.xcprivacy`) | **Fail** | none in the app (required for App Store uploads) |
| 8 | Export-compliance key `ITSAppUsesNonExemptEncryption` | Fail | missing; the app uses encryption (SQLCipher, AES), so Apple asks on every upload. The right value is your call (see "Needs you") |
| 9 | Minimum iOS version | Fail | set to 13.0; `firebase_core` 4.x and ML Kit need about 15.5, so `pod install` will fail |
| 10 | Google Maps key | **Fail** | `AppDelegate.swift` has the placeholder `YOUR_GOOGLE_MAPS_API_KEY` |
| 11 | `Podfile` in the repo | Note | none; Flutter creates it on the first iOS build on a Mac |
| 12 | App icon | Pass | all sizes; the 1024 px icon is RGB (no transparency, as required) |
| 13 | Launch screen, iPad orientations | Pass | |
| 14 | Google sign-in URL scheme | Pass | in `Info.plist` |
| 15 | Self-update code disabled on Apple platforms | Pass | `update_launcher.dart` only runs on Android and Windows |

## Mac app (Mac App Store)

| # | Check | Result | Notes |
|---|---|---|---|
| 16 | App Sandbox on | Pass | required for the Mac App Store |
| 17 | Outgoing network | **Fail** | no `com.apple.security.network.client` in either entitlements file: in the sandbox the app cannot reach Firebase at all |
| 18 | Microphone | **Fail** | no `device.audio-input` entitlement and no `NSMicrophoneUsageDescription` |
| 19 | Camera | **Fail** | no `device.camera` entitlement and no `NSCameraUsageDescription` |
| 20 | File open / save | **Fail** | no `files.user-selected.read-write` (file picker, PDF save) |
| 21 | Printing | Fail | no `com.apple.security.print` |
| 22 | Keychain | **Fail** | no `keychain-access-groups`: sign-in and secure storage break in the sandbox |
| 23 | Contacts | Fail | contacts are used (colleague invites) but there is no addressbook entitlement or usage string |
| 24 | Local network / LAN sharing | Fail | needs `network.server` in the Release file (only Debug has it) |
| 25 | App name | Fail | `PRODUCT_NAME = doctor_management_app`, so the app shows as that |
| 26 | App category `LSApplicationCategoryType` | Fail | required for the Mac App Store |
| 27 | Privacy manifest | Fail | none |
| 28 | Firebase for macOS | Needs you | `firebase_options.dart` reuses the iOS app id; no macOS `GoogleService-Info.plist` |
| 29 | Google sign-in on Mac | Fail | no URL scheme in `macos/Runner/Info.plist` |
| 30 | iOS/Android-only plugins | Fail | ML Kit text recognition and the document scanner have no macOS support; calls must be hidden on Mac |
| 31 | Push on Mac | Pass | the app already skips it on Mac |

## App Review rules (both stores)

| # | Rule | Result | What the code does |
|---|---|---|---|
| 32 | 5.1.1(v) In-app account deletion | **Fail** | no delete-account anywhere |
| 33 | 4.8 Sign in with Apple (the app offers Google sign-in) | **Fail** | Google, email and phone only |
| 34 | 3.1.1 Buying features inside the app | **Fail** | paid modules are bought in-app by UPI (`payment_checkout_sheet.dart`). Apple requires its own in-app purchase for this, or no purchase screen on Apple devices |
| 35 | 5.1.1(i) Privacy policy link in the app | **Fail** | no privacy policy or terms link found |
| 36 | 5.1.2(i) Ask before sending personal data to an AI provider | **Fail** | patient audio, text and scans go to Gemini (Firebase AI) with no consent step; settings only has an information card |
| 37 | 1.4.1 Medical apps: AI output must be reviewed | Partial | PDFs carry a disclaimer; the scribe screens show no "review before use" line |
| 38 | 2.5.2 No downloading app code | Pass | updater is off on Apple platforms |
| 39 | 5.1.3 Health data not used for advertising | Pass | no ad SDK found |
| 40 | 2.1 Reviewer can log in | Pass (needs notes) | demo accounts on `@crudoc.com` exist; put one in the review notes |
| 41 | Contacts: say what happens to them | Needs you | the permission text says contacts are not stored; the privacy label must match |

## Needs you (Apple / Firebase websites; cannot be done in code)

1. **Apple Developer Program** membership, App Store Connect records for iOS and macOS (bundle `com.crudoc.app`).
2. **Plan purchases on Apple devices: use Apple in-app purchase (decided).** The handoff's Part D builds it (one monthly subscription per paid module); Claude writes the server check. Apple takes 15% (Small Business Program) or 30%. Hiding purchases and selling only on the web is NOT a safe alternative: rule 3.1.3(b) lets an app unlock plans bought elsewhere only if the same plans are also sold in the app.
3. **Export compliance:** whether the app qualifies for the encryption exemption; set `ITSAppUsesNonExemptEncryption` accordingly.
4. **Privacy policy and terms URLs** (the handoff leaves empty constants to fill in), a support URL, and the App Privacy "nutrition label" answers (health, contacts, audio, photos, identifiers, diagnostics).
5. **Sign in with Apple:** enable the provider in the Firebase console (Services ID, key, team ID) and the capability on the App ID.
6. **Push:** upload an APNs key to Firebase.
7. **Firebase macOS app:** register it and add its `GoogleService-Info.plist`.
8. **Google Maps iOS key:** create it and put it in `ios/Flutter/Secrets.xcconfig` (see handoff, task A5).
9. **Build and upload from a Mac** (or Codemagic / a GitHub macOS runner): `pod install`, archive, TestFlight; screenshots (iPhone 6.9", iPad 13", Mac), age rating, review notes with a demo login.
