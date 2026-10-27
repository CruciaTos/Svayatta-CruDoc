# Antigravity brief: connect the restored features

Paste this whole file into Antigravity. It is a standalone brief.

## ▶ DO NOW

Do Tasks 1 to 8 in order, then run the Checks once at the end. Stop after the Checks and report.

## Rules (how to work)

- Work without pausing. Write every task first, then run all Checks once at the end.
- Change only the files named below. Do not rename, move or reformat anything else.
- Do not delete any file. Do not run `flutter run` or a release build. Do not commit.
- If a step doesn't match the code you see (a name or line is different), skip that step, write down what you saw, and carry on.
- All paths are relative to the `CruDoc/` folder (the Flutter app).
- UI rules: colours, text styles, radii and spacing come from the design tokens (`context.cru`, `CruType`, `CruRadius`, `CruSpace`). No `Color(0x…)`, no `Colors.red/green/orange/white`, no `fontSize:` in the files you touch. Red is only for allergies; amber means waiting or needs attention; green means done. One filled button per region.

## Background

These five pieces were deleted by mistake and restored in commit `b240800`. They are finished but nothing opens them yet:

| File | What it is |
|---|---|
| `lib/features/dental/specialties/anaesthesia/drug_log.dart` | `DrugLogDialog`: drugs given during a sedation case, with the local anaesthetic max-dose calculator |
| `lib/features/dental/specialties/publichealth/dmft.dart` | `patientDmftProvider`: the patient's DMFT / dmft score from the tooth chart |
| `lib/features/revenue/data/providers/procedure_payments.dart` | `ProcedurePayments.record` and `procedurePaymentsProvider`: payments towards one logged procedure |
| `lib/features/update/presentation/update_banner.dart`, `update_available_dialog.dart`, `update_progress_sheet.dart` | The "update available" banner, the dialog with Update now / Later / Skip, and the download progress sheet |
| `lib/features/dental/presentation/dental_inventory_screen.dart` | `DentalInventoryScreen`: dental consumables (composites, cartridges, burs) |

Leave `lib/core/update/platform/ios_update_installer.dart` alone. It stays unused until iOS ships (see the comment in `update_installer_factory.dart`).

---

## Task 1: Drug log row on the dental records card

File: `lib/features/dental/records/dental_records_card.dart`

1. Add this import next to the other `specialties/anaesthesia` import:

```dart
import 'package:doctor_management_app/features/dental/specialties/anaesthesia/drug_log.dart';
```

2. Find the row titled `'Sedation & Pre-op'` (it opens `PreopDialog`). Right after that whole `row(...)` call and its comma, add:

```dart
          if (sedationCases.isNotEmpty)
            row(
              CruIcons.flask,
              'Drug log',
              () {
                final n = SedationCase.fromRecord(
                  sedationCases.first,
                ).drugs.length;
                return n == 0
                    ? 'No doses logged yet'
                    : '$n ${n == 1 ? 'dose' : 'doses'} logged';
              }(),
              () => showDialog<void>(
                context: context,
                builder: (_) => DrugLogDialog(
                  patient: patient,
                  sedationCase: SedationCase.fromRecord(sedationCases.first),
                ),
              ),
            ),
```

The row only shows when the patient has a sedation case, because the drug log saves into that case.

---

## Task 2: DMFT score on the tooth chart (public health dentists)

File: `lib/features/dental/presentation/desktop/tooth_chart_card.dart`, class `_ToothChartCardState`.

1. Add these imports:

```dart
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/features/dental/dental_features.dart';
import 'package:doctor_management_app/features/dental/specialties/publichealth/dmft.dart';
```

2. In `build`, right after the `final counts = [ ... ];` list, add:

```dart
    final showDmft = ref
        .watch(dentalFeaturesProvider)
        .contains(DentalFeature.publicHealth);
    final dmft = showDmft && counts.isNotEmpty
        ? ref.watch(patientDmftProvider(widget.patient.id)).value
        : null;
```

3. In the `header` Column, after the `Text(...)` that shows `counts.join(' · ')`, add:

```dart
        if (dmft != null) ...[
          const SizedBox(height: CruSpace.s2),
          Text(
            [
              'DMFT ${dmft.total}',
              if (dmft.primaryTotal > 0) 'dmft ${dmft.primaryTotal}',
            ].join(' · '),
            style: CruType.subhead.tabular.tint(c.label2),
          ),
        ],
```

---

## Task 3: New file for the procedure payment dialog

Create `lib/features/dental/presentation/desktop/procedure_payment_dialog.dart` with exactly this:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dental/data/models/dental_procedure_log_model.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/revenue/data/providers/procedure_payments.dart';
import 'package:doctor_management_app/features/revenue/data/providers/revenue_providers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Takes a payment towards one logged procedure. It is saved as ordinary
/// income for the patient, so it shows in Revenue too.
Future<void> showProcedurePaymentDialog(
  BuildContext context, {
  required Patient patient,
  required DentalProcedureLogModel log,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ProcedurePaymentDialog(patient: patient, log: log),
  );
}

class _ProcedurePaymentDialog extends ConsumerStatefulWidget {
  const _ProcedurePaymentDialog({required this.patient, required this.log});

  final Patient patient;
  final DentalProcedureLogModel log;

  @override
  ConsumerState<_ProcedurePaymentDialog> createState() =>
      _ProcedurePaymentDialogState();
}

class _ProcedurePaymentDialogState
    extends ConsumerState<_ProcedurePaymentDialog> {
  final _amount = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      recToast(context, 'Enter the amount received.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ProcedurePayments.record(
        ref.read(revenueRepositoryProvider),
        procedureLogId: widget.log.id,
        patientId: widget.patient.id,
        patientName: widget.patient.fullName,
        amount: amount,
        description: 'Payment · ${widget.log.procedureName}',
        date: DateTime.now(),
        visitId: widget.log.visitId,
      );
      if (!mounted) return;
      recToast(context, 'Payment saved');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      recToast(context, "Couldn't save the payment: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final payments = ref.watch(procedurePaymentsProvider(widget.patient.id));
    final paid = payments?[widget.log.id] ?? 0;
    return DentalPanelDialog(
      title: 'Take payment',
      subtitle: '${widget.patient.fullName} · ${widget.log.procedureName}',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          CruTextField(
            label: 'Amount received',
            controller: _amount,
            prefix: '₹',
            autofocus: true,
            tabular: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            onSubmitted: (_) => _save(),
          ),
          if (paid > 0) ...[
            const SizedBox(height: CruSpace.s8),
            Text(
              '${DashFormat.rupees(paid)} received so far for this procedure.',
              style: CruType.subhead.tabular.tint(c.label2),
            ),
          ],
        ],
      ),
      footer: Row(
        children: [
          const Spacer(),
          CruButton(
            label: 'Cancel',
            kind: CruButtonKind.secondary,
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: CruSpace.s8),
          CruButton(
            label: _saving ? 'Saving…' : 'Save payment',
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}
```

---

## Task 4: Payment button and "paid" line on the Procedures card

File: `lib/features/dental/presentation/desktop/tooth_chart_card.dart`, class `_DentalProceduresCardState`.

1. Add these imports:

```dart
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/procedure_payment_dialog.dart';
import 'package:doctor_management_app/features/revenue/data/providers/procedure_payments.dart';
```

2. In `build`, right after `final shown = _all ? logs : logs.take(5).toList();` add:

```dart
    final paid =
        ref.watch(procedurePaymentsProvider(widget.patient.id)) ??
        const <String, double>{};
```

3. In each row, the subtitle `Text` builds a list with `DentalChart.teethText(...)` and `DentalFormat.date(shown[i].performedAt)`. After `DentalFormat.date(shown[i].performedAt),` add:

```dart
                              if ((paid[shown[i].id] ?? 0) > 0)
                                '${DashFormat.rupees(paid[shown[i].id]!)} paid',
```

4. In the same row, find `procedureStatusPill(c, shown[i].status),`. Right before it (after the `const SizedBox(width: CruSpace.s8),` that sits before it) add:

```dart
                    CruCapsuleButton(
                      label: 'Payment',
                      onPressed: () => showProcedurePaymentDialog(
                        context,
                        patient: widget.patient,
                        log: shown[i],
                      ),
                    ),
                    const SizedBox(width: CruSpace.s8),
```

---

## Task 5: Install button in Settings → About

File: `lib/features/settings/presentation/desktop_settings_screen.dart`, class `_AboutSectionState`.

1. Add these imports:

```dart
import 'package:doctor_management_app/core/update/models/app_release.dart';
import 'package:doctor_management_app/features/update/presentation/update_available_dialog.dart';
```

2. Under the field `String? _status;` add:

```dart
  AppRelease? _release;
```

3. In `_check()`, inside the `setState(() { ... })` that sets `_status = switch (result) {...}`, add this line first:

```dart
        _release = result is UpdateAvailable ? result.release : null;
```

4. In `build`, in the `_ActionRow` titled `'Updates'`, replace its `action: CruButton(...)` with:

```dart
          action: _release != null
              ? CruButton(
                  label: 'Install update',
                  icon: CruIcons.download,
                  onPressed: () =>
                      showUpdateAvailableDialog(context, _release!),
                )
              : CruButton(
                  label: _checking ? 'Checking…' : 'Check for updates',
                  kind: CruButtonKind.secondary,
                  onPressed: _checking ? null : _check,
                ),
```

---

## Task 6: Restyle the update banner and add the launch check

File: `lib/features/update/presentation/update_banner.dart`

1. Remove the line `import 'package:crudoc_shared/theme/app_colors.dart';`. Add these imports if they are missing:

```dart
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
```

2. In `UpdateBanner.build`, keep everything up to and including `if (forceUpdate || dismissedForSession) return const SizedBox.shrink();`. Replace everything after it (the whole `return SafeArea(...)`) with:

```dart
    final c = context.cru;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          CruSpace.s16,
          CruSpace.s8,
          CruSpace.s16,
          0,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            CruSpace.s12,
            CruSpace.s8,
            CruSpace.s8,
            CruSpace.s8,
          ),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(CruRadius.control),
            border: Border.all(color: c.cardBorder),
          ),
          child: Row(
            children: [
              const CruIconTile(
                icon: CruIcons.download,
                tone: CruTileTone.accent,
              ),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Update available',
                      style: CruType.callout.w600.tint(c.label),
                    ),
                    Text(
                      'Version ${release.version} is ready to install.',
                      style: CruType.subhead.tint(c.label2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: CruSpace.s8),
              CruCapsuleButton(
                label: 'Update',
                onPressed: () => showUpdateAvailableDialog(context, release),
              ),
              const SizedBox(width: CruSpace.s4),
              CruSquareButton(
                icon: CruIcons.close,
                secondary: true,
                semanticLabel: 'Dismiss',
                tooltip: 'Not now',
                onPressed: () =>
                    ref.read(updateControllerProvider.notifier).remindLater(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

3. At the end of the file add:

```dart
/// Checks for a newer version once after sign-in (Android and Windows
/// release builds only). A normal update shows [UpdateBanner]; a forced
/// one opens the update dialog straight away.
Future<void> checkForUpdateOnLaunch(BuildContext context, WidgetRef ref) async {
  if (kIsWeb || kDebugMode) return;
  if (!Platform.isAndroid && !Platform.isWindows) return;
  try {
    await ref.read(updateControllerProvider.notifier).checkForUpdate();
  } catch (_) {
    return; // Offline or no release feed: try again next launch.
  }
  if (!context.mounted) return;
  final result = ref.read(updateControllerProvider).checkResult;
  if (result is UpdateAvailable &&
      (result.release.manifest?.forceUpdate ?? false)) {
    await showUpdateAvailableDialog(context, result.release);
  }
}
```

---

## Task 7: Show the banner and run the check in both shells

### 7a. PC

File: `lib/features/shell/presentation/desktop_shell.dart`

1. Add the import:

```dart
import 'package:doctor_management_app/features/update/presentation/update_banner.dart';
```

2. In `initState`, inside the existing `WidgetsBinding.instance.addPostFrameCallback((_) { ... })`, after the `ref.read(shellNavigatorProvider.notifier).state = ...;` statement, add:

```dart
      unawaited(checkForUpdateOnLaunch(context, ref));
```

3. Find `content: content,` (around line 606, inside `DesktopShellLayout`). Replace it with:

```dart
                  content: Column(
                    children: [
                      const UpdateBanner(),
                      Expanded(child: content),
                    ],
                  ),
```

### 7b. Phone

File: `lib/features/mobile/mobile_shell.dart`

1. Add at the top, as the first import: `import 'dart:async';`. Also add:

```dart
import 'package:doctor_management_app/features/update/presentation/update_banner.dart';
```

2. In `initState`, inside the existing `addPostFrameCallback`, after the `ref.read(mobileTabSwitcherProvider.notifier).state = ...;` statement, add:

```dart
      unawaited(checkForUpdateOnLaunch(context, ref));
```

3. Find the `Stack` whose first child is `Positioned.fill(child: MobileBackdrop(pages: _pages)),`. Its last child is the `Positioned(...)` holding `MobileNavBar`. Right after that `Positioned(...)` and its comma, before the Stack's closing `],`, add:

```dart
                      const Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: UpdateBanner(),
                      ),
```

---

## Task 8: Restyle the update dialog and progress sheet, and the dental inventory screen

### 8a. Update dialog and progress sheet

Files: `lib/features/update/presentation/update_available_dialog.dart` and `lib/features/update/presentation/update_progress_sheet.dart`.

Replace the old styling using this table. Do not change any logic, text or `onPressed` handlers.

| Old | New |
|---|---|
| `fontFamily: AppColors.bodyFontFamily,` | delete the line |
| `AppColors.textPrimary`, `AppColors.sectionHeading` colour | `c.label` |
| `AppColors.textSecondary`, `AppColors.slateBlue` | `c.label2` |
| `AppColors.cardSurface` | `c.surface` |
| `AppColors.divider` | `c.separator` |
| `AppColors.chartBarLight` | `c.accent` |
| `AppColors.chartBarLight.withValues(alpha: …)` | `c.accentTint` |
| `style: AppColors.sectionHeading` | `style: CruType.headline.tint(c.label)` |
| `style: AppColors.bodyLarge` | `style: CruType.body.tint(c.label)` |
| `style: AppColors.bodyMedium` | `style: CruType.subhead.tint(c.label2)` |
| `style: AppColors.bodySmall` | `style: CruType.caption.tint(c.label2)` |
| `Colors.redAccent` (failed download) | `c.label2` (a failed download is neutral, not red) |
| `Colors.white` | `c.onAccent` |
| `TextStyle(fontSize: 18, …)` | `CruType.headline.tint(…)` |
| `TextStyle(fontSize: 14, …)` | `CruType.callout.tint(…)` (add `.w600` if it was bold or w600) |
| `TextStyle(fontSize: 13, …)` | `CruType.subhead.tint(…)` |
| `TextStyle(fontSize: 12, …)` | `CruType.caption.tint(…)` |
| `BorderRadius.circular(16)` or `(24)` | `BorderRadius.circular(CruRadius.card)` |
| `BorderRadius.circular(8)` | `BorderRadius.circular(CruRadius.control)` |
| `LinearProgressIndicator` colours | `color: c.accent, backgroundColor: c.track` |
| `ElevatedButton` / `FilledButton` ("Update now", "Retry") | `CruButton(label: '…', onPressed: …)` |
| `OutlinedButton` / `TextButton` ("Later", "Skip", "Close") | `CruButton(label: '…', kind: CruButtonKind.secondary, onPressed: …)` |

- Put `final c = context.cru;` at the top of each `build` that uses `c`. Remove `const` from widgets that now use `c`.
- Replace `import 'package:crudoc_shared/theme/app_colors.dart';` with `import 'package:doctor_management_app/shared/widgets/cru/cru.dart';` (skip if cru.dart is already imported).
- When done, neither file contains the word `AppColors`.

### 8b. Dental supplies button in Inventory

File: `lib/features/inventory/presentation/widgets/inventory_header.dart`, class `InventoryHeader`. Copy how `onSterilization` works.

1. Add the constructor parameter `this.onDentalSupplies,` after `this.onSterilization,`. Add the field after `final VoidCallback? onSterilization;`:

```dart

  /// Opens dental consumables; null hides the button (not a dentist).
  final VoidCallback? onDentalSupplies;
```

2. In the compact layout, right after the `if (onSterilization != null) ...[ ... CruSquareButton(...) ],` block, add:

```dart
          if (onDentalSupplies != null) ...[
            const SizedBox(width: CruSpace.s8),
            CruSquareButton(
              icon: DentalIcons.tooth,
              secondary: true,
              semanticLabel: 'Dental supplies',
              tooltip: 'Dental supplies',
              onPressed: onDentalSupplies,
            ),
          ],
```

3. In the wide layout, right after the `if (onSterilization != null) ...[ ... CruButton(label: 'Sterilization', ...) ],` block, add:

```dart
        if (onDentalSupplies != null) ...[
          const SizedBox(width: CruSpace.s10),
          CruButton(
            label: 'Dental supplies',
            kind: CruButtonKind.secondary,
            icon: DentalIcons.tooth,
            onPressed: onDentalSupplies,
          ),
        ],
```

File: `lib/features/inventory/presentation/inventory_screen.dart`

4. Add the import:

```dart
import 'package:doctor_management_app/features/dental/presentation/dental_inventory_screen.dart';
```

5. After the `_openSterilization()` method add:

```dart
  void _openDentalSupplies() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const DentalInventoryScreen()),
    );
  }
```

6. In `InventoryHeader(...)`, after `onSterilization: sterilization ? _openSterilization : null,` add:

```dart
      onDentalSupplies: ref.watch(isDentistProvider) ? _openDentalSupplies : null,
```

### 8c. Restyle the dental inventory screen

File: `lib/features/dental/presentation/dental_inventory_screen.dart`. Replace the old styling using this table (it already has `final c = context.cru;` in `build`; add it to other `build` methods that need it). Do not change any logic or text.

| Old | New |
|---|---|
| `Color(0xFF2563EB)`, `Color(0xFF1E3A8A)` | `c.accent` |
| FAB `backgroundColor` / `foregroundColor` | `c.primaryButtonFill` / `c.primaryButtonText` |
| `Color(0xFF0F172A)` | `c.label` |
| `Color(0xFF64748B)` | `c.label2` |
| `Color(0xFF94A3B8)` | `c.label3` |
| `Color(0xFFF8FAFC)`, `Color(0xFFF1F5F9)` | `c.inset` |
| `Colors.red`, `Colors.redAccent`, `Colors.orange`, `Color(0xFF991B1B)` | `c.amberText` (low stock or expiry is "needs attention", not red) |
| `Color(0xFFFEE2E2)` | `c.amberTint` |
| `Colors.green` | `c.greenText` |
| `Color(0xFFDCFCE7)` | `c.greenTint` |
| `Color(0xFF0D9488)` | `c.tealText` |
| `Colors.white` | `c.onAccent` on an accent fill, otherwise `c.surface` |
| `Colors.transparent` | keep |
| `fontSize: 18` | `CruType.headline` |
| `fontSize: 16` | `CruType.callout.w600` |
| `fontSize: 14`, `13.5`, `13` | `CruType.subhead` |
| `fontSize: 12`, `11`, `10` | `CruType.caption` |
| AppBar title `TextStyle(color: c.label)` | `CruType.headline.tint(c.label)` |

When you turn a `TextStyle(fontSize: …, color: X)` into a `CruType` style, keep the colour with `.tint(X)` and keep bold with `.w600`.

---

## Checks (run once, at the end)

1. `flutter analyze`: no errors, and no new warnings in the files you touched.
2. `grep -n "AppColors" lib/features/update/presentation/` prints nothing.
3. `grep -nE "Color\(0x|Colors\.(red|redAccent|green|orange|white)|fontSize" lib/features/dental/presentation/dental_inventory_screen.dart lib/features/update/presentation/` prints nothing.

## Report

For each task 1–8: done, or skipped with what you saw. Paste the last lines of `flutter analyze`. List anything you were unsure about.

For the user to try in the app afterwards (not for Antigravity):
- A dental patient with a sedation case: Records → **Drug log** opens, the max-dose numbers follow the patient's weight.
- A dentist with **Public health** turned on: the tooth chart header shows **DMFT n**.
- Procedures card → **Payment** → save ₹500: the row shows "₹500 paid", and the payment appears in Revenue.
- Settings → About → Check for updates: when a newer release exists, the button becomes **Install update** and opens the dialog.
- Inventory as a dentist: **Dental supplies** opens the consumables page in the new colours.
