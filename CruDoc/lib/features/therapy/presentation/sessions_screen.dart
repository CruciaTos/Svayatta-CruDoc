import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/utils/app_notice.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/revenue/presentation/desktop_create_invoice_dialog.dart';
import 'package:doctor_management_app/features/therapy/domain/physio_extras_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Adds today's visit to [pkg] and offers an undo.
Future<void> useSession(
  BuildContext context,
  WidgetRef ref,
  SessionPackage pkg,
) async {
  if (pkg.completed) return;
  final at = DateTime.now();
  await saveDentalRecord(ref, pkg.record.copyWith(data: pkg.dataWithUse(at)));
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showIsland(
      SnackBar(
        content: Text('Session used · ${pkg.left - 1} left'),
        behavior: SnackBarBehavior.floating,
        width: 420,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => saveDentalRecord(
            ref,
            pkg.record.copyWith(data: pkg.dataWithoutUse(at)),
          ),
        ),
      ),
    );
}

/// Raises the invoice for a package sale and records it on the package.
///
/// A package is paid for up front and the sessions draw it down, so there is
/// one invoice per package rather than one per session. It goes through the
/// clinic's own invoice dialog, so the tax rate, payment mode, numbering and
/// PDF are the same here as anywhere else in CruDoc — nothing about tax is
/// decided in the physiotherapy code.
Future<void> billPackage(
  BuildContext context,
  WidgetRef ref,
  Patient patient,
  SessionPackage pkg,
) async {
  final invoice = await showDesktopCreateInvoiceDialog(
    context,
    initialPatient: patient,
    initialTreatmentName: pkg.name.trim().isEmpty
        ? 'Session package'
        : pkg.name.trim(),
    initialTreatmentPrice: pkg.price,
    initialNotes:
        '${pkg.total} session package'
        '${pkg.validUntil == null ? '' : ', valid until '
                  '${DentalFormat.date(pkg.validUntil!)}'}',
  );
  if (invoice == null) return;
  await saveDentalRecord(
    ref,
    pkg.record.copyWith(data: pkg.dataWithInvoice(invoice.id)),
  );
}

/// Sheet to start a new package.
Future<void> showNewPackageSheet(
  BuildContext context,
  WidgetRef ref,
  Patient patient,
) async {
  final data = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _PackageSheet(),
  );
  if (data == null) return;
  final record = DentalRecord.create(patient.id, RecKind.physioPackage, data);
  await saveDentalRecord(ref, record);
  // Billed from here while the patient is still at the desk, rather than
  // leaving it to be remembered later.
  final pkg = SessionPackage.fromRecord(record);
  if (!context.mounted || !pkg.needsInvoice) return;
  await billPackage(context, ref, patient, pkg);
}

class _PackageSheet extends StatefulWidget {
  const _PackageSheet();

  @override
  State<_PackageSheet> createState() => _PackageSheetState();
}

class _PackageSheetState extends State<_PackageSheet> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _note = TextEditingController();
  int _total = 10;
  DateTime? _valid;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _valid ?? now.add(const Duration(days: 90)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (picked != null) setState(() => _valid = picked);
  }

  void _save() {
    final price = double.tryParse(_price.text.trim());
    final name = _name.text.trim();
    Navigator.of(context).pop(<String, dynamic>{
      'name': name.isEmpty ? '$_total-session package' : name,
      'total': _total,
      'price': ?price,
      if (_valid != null) 'validUntil': _valid!.millisecondsSinceEpoch,
      'note': _note.text.trim(),
      'used': <int>[],
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            CruSpace.s16,
            0,
            CruSpace.s16,
            CruSpace.s16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CruTextField(
                label: 'Package name',
                controller: _name,
                optional: true,
                hint: 'e.g. Knee rehab',
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: CruSpace.s16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Number of sessions',
                      style: CruType.body.w600.tint(c.label),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fewer',
                    icon: const Icon(Icons.remove_rounded),
                    onPressed: _total > 1
                        ? () => setState(() => _total--)
                        : null,
                  ),
                  SizedBox(
                    width: CruSpace.s32,
                    child: Text(
                      '$_total',
                      textAlign: TextAlign.center,
                      style: CruType.headline.w600.tabular.tint(c.label),
                    ),
                  ),
                  IconButton(
                    tooltip: 'More',
                    icon: const Icon(Icons.add_rounded),
                    onPressed: _total < 99
                        ? () => setState(() => _total++)
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: CruSpace.s8),
              CruTextField(
                label: 'Price',
                controller: _price,
                optional: true,
                prefix: '₹',
                tabular: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
              ),
              const SizedBox(height: CruSpace.s16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _valid == null
                          ? 'No expiry date'
                          : 'Valid until ${DentalFormat.date(_valid!)}',
                      style: CruType.body.tint(c.label),
                    ),
                  ),
                  if (_valid != null)
                    IconButton(
                      tooltip: 'Clear date',
                      icon: Icon(Icons.close_rounded, color: c.label2),
                      onPressed: () => setState(() => _valid = null),
                    ),
                  CruCapsuleButton(
                    label: _valid == null ? 'Set valid until' : 'Change',
                    onPressed: _pickDate,
                  ),
                ],
              ),
              const SizedBox(height: CruSpace.s16),
              CruMoreFields(
                label: 'Note',
                open: _note.text.isNotEmpty,
                children: [
                  CruTextField(
                    label: 'Note',
                    controller: _note,
                    optional: true,
                    textInputAction: TextInputAction.done,
                  ),
                ],
              ),
              const SizedBox(height: CruSpace.s16),
              CruButton(label: 'Save package', expand: true, onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}

/// All packages for a patient, newest first, with their usage dates.
class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key, required this.patient});

  final Patient patient;

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    SessionPackage p,
  ) async {
    final ok = await confirmDental(
      context,
      title: 'Delete this package?',
      body:
          '"${p.name}" and its ${p.used.length} recorded session${p.used.length == 1 ? '' : 's'} will be removed.',
      action: 'Delete',
    );
    if (ok) await deleteDentalRecord(ref, p.record);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final recs = ref.watch(
      patientRecordsProvider((
        patientId: patient.id,
        kind: RecKind.physioPackage,
      )),
    );
    final packages = sessionPackages(recs.value ?? const <DentalRecord>[]);
    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(
        title: Text(patient.fullName),
        actions: [
          CruCapsuleButton(
            label: 'New package',
            icon: CruIcons.plus,
            onPressed: () => showNewPackageSheet(context, ref, patient),
          ),
          const SizedBox(width: CruSpace.s12),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(CruSpace.s16),
        children: [
          if (packages.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: CruSpace.s24),
              child: Center(
                child: Text(
                  'No packages yet.',
                  style: CruType.caption.tint(c.label3),
                ),
              ),
            ),
          for (final p in packages)
            Padding(
              padding: const EdgeInsets.only(bottom: CruSpace.s8),
              child: CruCard(
                padding: const EdgeInsets.fromLTRB(
                  CruSpace.s16,
                  CruSpace.s12,
                  CruSpace.s4,
                  CruSpace.s12,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name, style: CruType.body.w600.tint(c.label)),
                          const SizedBox(height: CruSpace.s2),
                          Text(
                            '${p.used.length} of ${p.total} used · started ${DentalFormat.date(p.date)}'
                            '${p.price != null ? ' · ₹${_money(p.price!)}' : ''}'
                            '${p.validUntil != null ? ' · valid until ${DentalFormat.date(p.validUntil!)}' : ''}',
                            style: CruType.caption.tabular.tint(c.label2),
                          ),
                          if (p.needsInvoice)
                            Text(
                              'Not billed yet',
                              style: CruType.caption.tint(c.amberText),
                            ),
                          if (p.note.isNotEmpty)
                            Text(p.note, style: CruType.caption.tint(c.label2)),
                          if (p.used.isNotEmpty) ...[
                            const SizedBox(height: CruSpace.s8),
                            Text(
                              [
                                for (final u in p.used)
                                  DentalFormat.shortDate(u),
                              ].join(' · '),
                              style: CruType.caption.tabular.tint(c.label),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (p.needsInvoice)
                      CruCapsuleButton(
                        label: 'Bill',
                        onPressed: () => billPackage(context, ref, patient, p),
                      ),
                    IconButton(
                      tooltip: 'Delete',
                      icon: Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: c.label2,
                      ),
                      onPressed: () => _delete(context, ref, p),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _money(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

/// "₹1500" style text for a package price.
String packageMoney(double v) => '₹${_money(v)}';
