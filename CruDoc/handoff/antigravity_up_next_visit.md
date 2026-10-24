# Antigravity brief: green Home visit card + Start visit opens maps

Paste this whole file into Antigravity. It is a standalone brief.

## ▶ DO NOW

Do Task 1, Task 2 and Task 3 in order, then run the Checks once at the end. Stop after the Checks and report.

## Rules (how to work)

- Work without pausing. Write every task first, then run all Checks once at the end.
- Change only the files named below. Do not rename, move or reformat anything else.
- Do not run `flutter run` or a release build. Do not commit.
- If a step doesn't match the code you see (a name or line is different), skip that step, write down what you saw, and carry on.
- All paths are relative to the `CruDoc/` folder (the Flutter app).

## Background

On the phone home screen (`lib/features/mobile/mobile_home.dart`) a home visit shows on a green card:

- `_BookedCard` shows "Up next · Home visit" with a **Start visit** button. Today the button only checks the patient in (`_checkIn`).
- `_NowCard` shows "Home visit" for a home-visit patient already waiting.

Both cards take their colours from the class `_VisitInk` (around line 109). The user wants:

1. The green to be the bright green of the Pronto ad background (fresh, light green, not the current dark bottle green).
2. **Start visit** to open Google Maps at the patient's home address.

---

## Task 1: Pronto green colours

File: `lib/features/mobile/mobile_home.dart`

Find:

```dart
abstract final class _VisitInk {
  static const gradient = [Color(0xFF0D3B2B), Color(0xFF178060)];
  static const border = Color(0xFF6FD9AC);
  static const accent = Color(0xFFBDF2D8);
}
```

Replace with:

```dart
/// The home-visit card colours: the bright green of the Pronto ad.
abstract final class _VisitInk {
  static const gradient = [Color(0xFF12A060), Color(0xFF22BF78)];
  static const border = Color(0xFF8BE6BA);
  static const accent = Color(0xFFE3FBEF);
}
```

Do not change anything else in the cards. The title stays white.

---

## Task 2: give each home visit a maps link

### 2a. Add a field to `ScheduleItem`

File: `lib/features/dashboard/domain/dashboard_models.dart`, class `ScheduleItem` (around line 28).

1. In the constructor, after `this.visitId,` add `this.mapsUrl,`
2. After the line `final String? visitId;` add:

```dart

  /// Google Maps link to a home visit's address; null for clinic visits or
  /// when no address was saved.
  final String? mapsUrl;
```

### 2b. Fill it in the builder

File: `lib/features/dashboard/domain/dashboard_builder.dart`

1. Add this private function near the other small helpers in the file (for example right after the `_clean` function):

```dart
/// A Google Maps link for a home visit: the saved maps link, else the
/// geocoded point, else a search for the address. Null otherwise.
String? _mapsUrl(Visit? v) {
  if (v == null || v.visitType != VisitType.home) return null;
  final link = v.mapsLink?.trim();
  if (link != null && link.isNotEmpty) {
    return link.startsWith('http://') || link.startsWith('https://')
        ? link
        : 'https://$link';
  }
  final String query;
  if (v.latitude != null && v.longitude != null) {
    query = '${v.latitude},${v.longitude}';
  } else {
    final address = v.address.trim();
    if (address.isEmpty) return null;
    query = address;
  }
  return 'https://www.google.com/maps/search/?api=1'
      '&query=${Uri.encodeComponent(query)}';
}
```

2. There are three `ScheduleItem(` calls in this file (around lines 187, 214 and 476). Add one line to each, right after its `visitId: ...,` line:
   - First one (queue entries, uses `visit`): `mapsUrl: _mapsUrl(visit),`
   - Second one (inside `for (final v in todaysVisits)`): `mapsUrl: _mapsUrl(v),`
   - Third one (merging a group, uses `i`): `mapsUrl: i.mapsUrl,`

`Visit` and `VisitType` are already imported in this file. If the analyzer says they aren't, add the same import the file uses elsewhere for `VisitType`.

---

## Task 3: Start visit opens maps

File: `lib/features/mobile/mobile_home.dart`

1. Add this import with the other `package:` imports at the top:

```dart
import 'package:url_launcher/url_launcher.dart';
```

2. In class `_BookedCard`, right after the `_checkIn` method ends (around line 441), add:

```dart
  /// Start visit: open Google Maps at the home address, then check in.
  Future<void> _startVisit(BuildContext context, WidgetRef ref) async {
    final url = item.mapsUrl;
    if (url == null) {
      mobileSay(context, 'No address saved for ${item.firstName}.');
    } else {
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && context.mounted) mobileSay(context, 'Could not open maps.');
    }
    if (context.mounted) await _checkIn(context, ref);
  }
```

3. In the same class's `build`, find the button:

```dart
                  _InkButton(
                    label: home ? 'Start visit' : 'Check in ${item.firstName}',
                    icon: home ? CruIcons.play : CruIcons.userCheck,
                    onPressed: () => _checkIn(context, ref),
                  ),
```

Change only the `onPressed` line to:

```dart
                    onPressed: () =>
                        home ? _startVisit(context, ref) : _checkIn(context, ref),
```

Do not touch `_NowCard`'s "Start session" button.

---

## Checks (run once, at the end)

1. `flutter analyze lib/features/mobile/mobile_home.dart lib/features/dashboard` → no new errors or warnings.
2. If the folder `test/features/dashboard` exists: `flutter test test/features/dashboard` → all pass.

## Report back

- Which tasks are done, and any step you skipped and why.
- The output of both Checks.
