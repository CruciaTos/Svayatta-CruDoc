import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/features/revenue/presentation/desktop_create_invoice_dialog.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

// ============================================================ referrer

/// Add or edit a referring dentist. Returns the saved referrer.
Future<RadReferrer?> showRadReferrerDialog(
  BuildContext context, {
  RadReferrer? existing,
  String initialName = '',
}) =>
    showDialog<RadReferrer>(
      context: context,
      builder: (_) => _ReferrerDialog(existing: existing, initialName: initialName),
    );

class _ReferrerDialog extends ConsumerStatefulWidget {
  const _ReferrerDialog({required this.existing, required this.initialName});

  final RadReferrer? existing;
  final String initialName;

  @override
  ConsumerState<_ReferrerDialog> createState() => _ReferrerDialogState();
}

class _ReferrerDialogState extends ConsumerState<_ReferrerDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? widget.initialName);
  late final _clinic = TextEditingController(text: widget.existing?.clinic ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _email = TextEditingController(text: widget.existing?.email ?? '');
  late final _city = TextEditingController(text: widget.existing?.city ?? '');
  late final _reg = TextEditingController(text: widget.existing?.regNo ?? '');
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');
  bool _saving = false;
  bool _dirty = false;
  bool _submitted = false;
  String? _notice;

  @override
  void dispose() {
    for (final c in [_name, _clinic, _phone, _email, _city, _reg, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _edited() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _notice = null;
    });
    try {
      final e = widget.existing;
      final r = RadReferrer(
        id: e?.id ?? radId('ref_'),
        name: _name.text.trim(),
        clinic: _clinic.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        city: _city.text.trim(),
        regNo: _reg.text.trim(),
        notes: _notes.text.trim(),
        createdAt: e?.createdAt ?? DateTime.now(),
      );
      await ref.read(radiologyProvider).saveReferrer(r, isNew: e == null);
      if (mounted) Navigator.of(context).pop(r);
    } catch (_) {
      setState(() {
        _saving = false;
        _notice = "Couldn't save the referrer. Try again.";
      });
    }
  }

  Future<void> _delete() async {
    final e = widget.existing;
    if (e == null) return;
    final ok = await confirmDental(
      context,
      title: 'Delete ${e.name}?',
      body: 'Their studies stay on the worklist; they just no longer show who referred them.',
      action: 'Delete',
    );
    if (!ok || !mounted) return;
    await ref.read(radiologyProvider).deleteReferrer(e);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return CruFormDialog(
      title: widget.existing == null ? 'Add referrer' : 'Edit referrer',
      subtitle: 'A dentist or clinic that sends scans to you',
      leading: const CruIconTile(icon: RadIcons.referrer, tone: CruTileTone.accent),
      submitLabel: widget.existing == null ? 'Add referrer' : 'Save changes',
      onSubmit: _save,
      busy: _saving,
      dirty: _dirty,
      notice: _notice,
      footerHint: 'Ctrl + Enter to save',
      body: Form(
        key: _form,
        autovalidateMode:
            _submitted ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CruFormSection(
              first: true,
              title: 'Who',
              description: 'Printed on reports and statements.',
              children: [
                CruFieldRow(children: [
                  CruTextField(
                    label: 'Name',
                    controller: _name,
                    autofocus: widget.existing == null,
                    hint: 'Dr. Anjali Shah',
                    textCapitalization: TextCapitalization.words,
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Add their name.' : null,
                    onChanged: (_) => _edited(),
                  ),
                  CruTextField(
                    label: 'Clinic',
                    optional: true,
                    controller: _clinic,
                    hint: 'Smile Dental Care',
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => _edited(),
                  ),
                ]),
                CruFieldRow(children: [
                  CruTextField(
                    label: 'City',
                    optional: true,
                    controller: _city,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => _edited(),
                  ),
                  CruTextField(
                    label: 'Registration no.',
                    optional: true,
                    controller: _reg,
                    onChanged: (_) => _edited(),
                  ),
                ]),
              ],
            ),
            CruFormSection(
              title: 'Contact',
              description: 'Where reports and urgent findings go.',
              children: [
                CruFieldRow(children: [
                  CruTextField(
                    label: 'Phone / WhatsApp',
                    optional: true,
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    tabular: true,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                    onChanged: (_) => _edited(),
                  ),
                  CruTextField(
                    label: 'Email',
                    optional: true,
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return null;
                      return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)
                          ? null
                          : 'Check the email address.';
                    },
                    onChanged: (_) => _edited(),
                  ),
                ]),
                CruTextField(
                  label: 'Notes',
                  optional: true,
                  controller: _notes,
                  maxLines: 2,
                  hint: 'Prefers reports on WhatsApp',
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => _edited(),
                ),
                if (widget.existing != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: CruLink(label: 'Delete this referrer', onPressed: _delete),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================ pickers

/// Pick a referrer (or add one). Returns the referrer, or null.
Future<RadReferrer?> pickRadReferrer(BuildContext context, {String? selectedId}) =>
    showDialog<RadReferrer>(
      context: context,
      builder: (_) => _ReferrerPicker(selectedId: selectedId),
    );

class _ReferrerPicker extends ConsumerStatefulWidget {
  const _ReferrerPicker({this.selectedId});

  final String? selectedId;

  @override
  ConsumerState<_ReferrerPicker> createState() => _ReferrerPickerState();
}

class _ReferrerPickerState extends ConsumerState<_ReferrerPicker> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final all = ref.watch(radReferrersProvider).value ?? const <RadReferrer>[];
    final q = _q.trim().toLowerCase();
    final shown = all
        .where((r) =>
            q.isEmpty ||
            r.name.toLowerCase().contains(q) ||
            r.clinic.toLowerCase().contains(q) ||
            r.city.toLowerCase().contains(q))
        .toList();
    return DentalPanelDialog(
      title: 'Referred by',
      subtitle: 'Pick the dentist who sent this scan',
      width: CruSize.dialog + 120,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(CruSpace.s8, CruSpace.s8, CruSpace.s8, CruSpace.s8),
            child: DentalSearchField(
              controller: _search,
              hint: 'Search name, clinic or city',
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.all(CruSpace.s16),
              child: Text(
                all.isEmpty ? 'No referrers yet. Add the first one.' : 'No one matches.',
                style: CruType.subhead.tint(c.label2),
              ),
            ),
          for (final r in shown)
            DentalListRow(
              semanticLabel: r.name,
              onTap: () => Navigator.of(context).pop(r),
              minHeight: 48,
              child: Row(
                children: [
                  CruMonogram(name: r.name, size: CruSize.monogramRow),
                  const SizedBox(width: CruSpace.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.name, style: CruType.callout.tint(c.label)),
                        if (r.clinic.isNotEmpty || r.city.isNotEmpty)
                          Text(
                            [r.clinic, r.city].where((s) => s.isNotEmpty).join(' · '),
                            style: CruType.caption.tint(c.label2),
                          ),
                      ],
                    ),
                  ),
                  if (r.id == widget.selectedId)
                    CruIcon(CruIcons.check, size: 16, strokeWidth: 2.2, color: c.label),
                ],
              ),
            ),
        ],
      ),
      footer: Row(
        children: [
          CruButton(
            label: 'Add referrer',
            icon: CruIcons.plus,
            kind: CruButtonKind.secondary,
            onPressed: () async {
              final added = await showRadReferrerDialog(context, initialName: _search.text.trim());
              if (added != null && context.mounted) Navigator.of(context).pop(added);
            },
          ),
          const Spacer(),
          CruButton(
            label: 'Cancel',
            kind: CruButtonKind.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// Pick one of the clinic's patients. Returns the patient, or null.
Future<Patient?> pickRadPatient(
  BuildContext context, {
  String initialQuery = '',
  String title = 'Link to a patient',
  String subtitle = 'The study shows on their record',
}) =>
    showDialog<Patient>(
      context: context,
      builder: (_) => _PatientPicker(initialQuery: initialQuery, title: title, subtitle: subtitle),
    );

class _PatientPicker extends ConsumerStatefulWidget {
  const _PatientPicker({required this.initialQuery, required this.title, required this.subtitle});

  final String initialQuery;
  final String title;
  final String subtitle;

  @override
  ConsumerState<_PatientPicker> createState() => _PatientPickerState();
}

class _PatientPickerState extends ConsumerState<_PatientPicker> {
  late final _search = TextEditingController(text: widget.initialQuery);
  late String _q = widget.initialQuery;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final all = ref.watch(patientsStreamProvider).value ?? const <Patient>[];
    final q = _q.trim().toLowerCase();
    final shown = all
        .where((p) => !p.isArchived)
        .where((p) => q.isEmpty || p.fullName.toLowerCase().contains(q) || p.phone.contains(q))
        .take(60)
        .toList();
    return DentalPanelDialog(
      title: widget.title,
      subtitle: widget.subtitle,
      width: CruSize.dialog + 120,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(CruSpace.s8),
            child: DentalSearchField(
              controller: _search,
              hint: 'Search name or phone',
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.all(CruSpace.s16),
              child: Text('No patient matches.', style: CruType.subhead.tint(c.label2)),
            ),
          for (final p in shown)
            DentalListRow(
              semanticLabel: p.fullName,
              onTap: () => Navigator.of(context).pop(p),
              minHeight: 48,
              child: Row(
                children: [
                  CruMonogram(name: p.fullName, size: CruSize.monogramRow),
                  const SizedBox(width: CruSpace.s12),
                  Expanded(
                    child: Text(p.fullName, style: CruType.callout.tint(c.label)),
                  ),
                  Text(
                    [
                      '${p.age} y',
                      if (p.gender.isNotEmpty) p.gender,
                      if (p.phone.isNotEmpty) p.phone,
                    ].join(' · '),
                    style: CruType.caption.tabular.tint(c.label2),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================ fees

/// The fee list: what reading each study type costs.
Future<void> showRadFeesDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _FeesDialog());

class _FeesDialog extends ConsumerStatefulWidget {
  const _FeesDialog();

  @override
  ConsumerState<_FeesDialog> createState() => _FeesDialogState();
}

class _FeesDialogState extends ConsumerState<_FeesDialog> {
  final Map<String, TextEditingController> _amounts = {};
  final Map<String, TextEditingController> _labels = {};

  @override
  void dispose() {
    for (final c in [..._amounts.values, ..._labels.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveFee(RadFee f) async {
    final amount = double.tryParse(_amounts[f.id]!.text.trim()) ?? f.amount;
    final label = _labels[f.id]!.text.trim();
    await ref.read(radiologyProvider).saveFee(RadFee(
          id: f.id,
          label: label.isEmpty ? f.label : label,
          modality: f.modality,
          amount: amount,
        ));
  }

  Future<void> _add() async {
    await ref.read(radiologyProvider).saveFee(RadFee(
          id: radId('fee_'),
          label: 'New study type',
          modality: RadModality.other,
          amount: 0,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final fees = ref.watch(radFeesProvider).value;
    return DentalPanelDialog(
      title: 'Reading fees',
      subtitle: 'Filled in when a study is added; you can change it per study',
      leading: const CruIconTile(icon: CruIcons.rupee, tone: CruTileTone.neutral),
      body: fees == null
          ? const SizedBox(height: 120)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final f in fees)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: CruSpace.s8, vertical: CruSpace.s6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 110,
                          child: PopupMenuButton<RadModality>(
                            tooltip: 'Study type',
                            initialValue: f.modality,
                            onSelected: (m) => ref.read(radiologyProvider).saveFee(RadFee(
                                  id: f.id,
                                  label: f.label,
                                  modality: m,
                                  amount: f.amount,
                                )),
                            itemBuilder: (_) => [
                              for (final m in RadModality.values)
                                PopupMenuItem(value: m, child: Text(m.label)),
                            ],
                            child: RadModalityBadge(f.modality, width: 96),
                          ),
                        ),
                        const SizedBox(width: CruSpace.s12),
                        Expanded(
                          child: _InlineField(
                            controller: _labels.putIfAbsent(
                                f.id, () => TextEditingController(text: f.label)),
                            onDone: () => _saveFee(f),
                          ),
                        ),
                        const SizedBox(width: CruSpace.s12),
                        SizedBox(
                          width: 120,
                          child: _InlineField(
                            prefix: '₹',
                            tabular: true,
                            controller: _amounts.putIfAbsent(
                                f.id,
                                () => TextEditingController(
                                    text: f.amount.toStringAsFixed(0))),
                            formatters: [FilteringTextInputFormatter.digitsOnly],
                            onDone: () => _saveFee(f),
                          ),
                        ),
                        CruIconButton(
                          icon: RadIcons.trash,
                          semanticLabel: 'Remove ${f.label}',
                          tooltip: 'Remove',
                          onPressed: () => ref.read(radiologyProvider).deleteFee(f),
                        ),
                      ],
                    ),
                  ),
                if (fees.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(CruSpace.s16),
                    child: Text('No fees yet.', style: CruType.subhead.tint(c.label2)),
                  ),
              ],
            ),
      footer: Row(
        children: [
          CruButton(
            label: 'Add study type',
            icon: CruIcons.plus,
            kind: CruButtonKind.secondary,
            onPressed: _add,
          ),
          const Spacer(),
          CruButton(label: 'Done', onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }
}

/// A compact text box that saves when you leave it or press Enter.
class _InlineField extends StatefulWidget {
  const _InlineField({
    required this.controller,
    required this.onDone,
    this.prefix,
    this.tabular = false,
    this.formatters,
  });

  final TextEditingController controller;
  final VoidCallback onDone;
  final String? prefix;
  final bool tabular;
  final List<TextInputFormatter>? formatters;

  @override
  State<_InlineField> createState() => _InlineFieldState();
}

class _InlineFieldState extends State<_InlineField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) widget.onDone();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final style = widget.tabular ? CruType.subhead.tabular : CruType.subhead;
    return Container(
      height: CruSize.control,
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
      decoration: ShapeDecoration(color: c.inset, shape: cruShape(CruRadius.control)),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          if (widget.prefix != null) ...[
            Text(widget.prefix!, style: style.tint(c.label2)),
            const SizedBox(width: CruSpace.s4),
          ],
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              inputFormatters: widget.formatters,
              style: style.tint(c.label),
              cursorColor: c.accent,
              decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none),
              onSubmitted: (_) => widget.onDone(),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================ audit log

/// Who opened, changed, signed or exported what.
Future<void> showRadAuditDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _AuditDialog());

class _AuditDialog extends ConsumerWidget {
  const _AuditDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final events = ref.watch(radAuditProvider).value;
    final now = DateTime.now();
    final groups = <String, List<RadAuditEvent>>{};
    for (final e in (events ?? const <RadAuditEvent>[]).take(400)) {
      (groups[DentalFormat.day(e.at, now)] ??= []).add(e);
    }
    return DentalPanelDialog(
      title: 'Audit log',
      subtitle: 'Every study and report opened, changed, signed, exported or shared',
      leading: const CruIconTile(icon: RadIcons.history, tone: CruTileTone.neutral),
      body: events == null
          ? const SizedBox(height: 120)
          : events.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(CruSpace.s16),
                  child: Text('Nothing recorded yet.', style: CruType.subhead.tint(c.label2)),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final g in groups.entries) ...[
                      DentalGroupLabel(g.key),
                      for (final e in g.value)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: CruSpace.s12, vertical: CruSpace.s6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 76,
                                child: Text(RadFormat.time(e.at),
                                    style: CruType.subhead.tabular.tint(c.label2)),
                              ),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(children: [
                                    TextSpan(
                                        text: e.action,
                                        style: CruType.subhead.w600.tint(c.label)),
                                    if (e.detail.isNotEmpty)
                                      TextSpan(
                                          text: ' · ${e.detail}',
                                          style: CruType.subhead.tint(c.label2)),
                                  ]),
                                ),
                              ),
                              if (e.by.isNotEmpty)
                                Text(e.by, style: CruType.caption.tint(c.label3)),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
    );
  }
}

// ============================================================ invoice

/// Opens the clinic's invoice form for a study's reading fee.
Future<void> invoiceRadStudy(BuildContext context, WidgetRef ref, RadStudy s) async {
  final patients = ref.read(patientsStreamProvider).value ?? const <Patient>[];
  Patient? patient;
  for (final p in patients) {
    if (p.id == s.patientId) patient = p;
  }
  final fee = s.fee;
  final invoice = await showDesktopCreateInvoiceDialog(
    context,
    initialPatient: patient,
    initialTreatmentName: '${s.modality.label} reading',
    initialTreatmentPrice: fee,
    initialNotes: 'Radiology report · ${RadFormat.date(s.studyDate)}',
  );
  if (invoice != null) {
    await ref.read(radiologyProvider).saveStudy(
          s.copyWith(invoiced: true),
          auditAction: 'Invoiced',
          detail: s.patientName,
        );
  }
}

// ============================================================ dose log

/// Exposure values read from each study's DICOM files (kVp, mA, time,
/// mAs, DAP): one patient's, or every study's when [patientId] is null.
Future<void> showRadDoseLogDialog(BuildContext context, {String? patientId, String? name}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _DoseLogDialog(patientId: patientId, name: name),
    );

class _DoseLogDialog extends ConsumerWidget {
  const _DoseLogDialog({this.patientId, this.name});

  final String? patientId;
  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final studies = (ref.watch(radStudiesProvider).value ?? const <RadStudy>[])
        .where((s) => patientId == null || s.patientId == patientId)
        .toList()
      ..sort((a, b) => b.studyDate.compareTo(a.studyDate));
    final withDose = studies.where((s) => !s.dose.isEmpty).toList();
    final totalDap = withDose.fold<double>(0, (t, s) => t + (s.dose.dap ?? 0));
    String n(double? v, String unit, [int digits = 0]) =>
        v == null ? '—' : '${v.toStringAsFixed(digits)} $unit';

    Widget head(String t, double w, {bool right = false}) => SizedBox(
          width: w,
          child: Text(t,
              textAlign: right ? TextAlign.right : TextAlign.left,
              style: CruType.caption.w600.tint(c.label3)),
        );

    return DentalPanelDialog(
      title: 'Radiation dose log',
      subtitle: name == null ? 'Every study with exposure values' : name!,
      leading: const CruIconTile(icon: RadIcons.dose, tone: CruTileTone.neutral),
      width: CruSize.formDialog,
      body: withDose.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(CruSpace.s16),
              child: Text(
                studies.isEmpty
                    ? 'No studies yet.'
                    : 'None of these scans recorded exposure values in their files.',
                style: CruType.subhead.tint(c.label2),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      CruSpace.s12, CruSpace.s8, CruSpace.s12, CruSpace.s6),
                  child: Row(children: [
                    head('Date', 96),
                    head('Study', 72),
                    Expanded(child: head('Patient', 0)),
                    head('kVp', 64, right: true),
                    head('mA', 64, right: true),
                    head('Time', 72, right: true),
                    head('DAP', 96, right: true),
                  ]),
                ),
                for (final s in withDose)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: CruSpace.s12, vertical: CruSpace.s8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 96,
                          child: Text(RadFormat.date(s.studyDate),
                              style: CruType.subhead.tabular.tint(c.label2)),
                        ),
                        SizedBox(width: 72, child: Text(s.modality.short, style: CruType.subhead.tint(c.label))),
                        Expanded(
                          child: Text(s.patientName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: CruType.subhead.tint(c.label)),
                        ),
                        for (final (v, w) in [
                          (n(s.dose.kvp, ''), 64.0),
                          (n(s.dose.ma, '', 1), 64.0),
                          (n(s.dose.exposureMs == null ? null : s.dose.exposureMs! / 1000, 's', 1), 72.0),
                          (n(s.dose.dap, '', 2), 96.0),
                        ])
                          SizedBox(
                            width: w,
                            child: Text(v.trim(),
                                textAlign: TextAlign.right,
                                style: CruType.subhead.tabular.tint(c.label)),
                          ),
                      ],
                    ),
                  ),
                const CruSeparator(),
                Padding(
                  padding: const EdgeInsets.all(CruSpace.s12),
                  child: Text(
                    '${withDose.length} of ${studies.length} studies recorded exposure'
                    '${totalDap > 0 ? ' · total DAP ${totalDap.toStringAsFixed(2)} (the unit the scanner used)' : ''}',
                    style: CruType.caption.tabular.tint(c.label2),
                  ),
                ),
              ],
            ),
    );
  }
}
