import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dental/data/models/dental_procedure_catalog_model.dart';
import 'package:doctor_management_app/features/dental/data/models/dental_procedure_log_model.dart';
import 'package:doctor_management_app/features/dental/data/models/tooth_chart_entry_model.dart';
import 'package:doctor_management_app/features/dental/data/models/treatment_plan_line_item_model.dart';
import 'package:doctor_management_app/features/dental/domain/dental_chart.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_icons.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_desktop_providers.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_providers.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/revenue/presentation/desktop_create_invoice_dialog.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

const _uuid = Uuid();

/// A tooth number in a 44 px tile, coloured by its state.
class ToothBadge extends StatelessWidget {
  const ToothBadge({super.key, required this.tooth, required this.state});

  final String tooth;
  final ToothState state;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final colors = toothColors(c, state);
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: state == ToothState.healthy ? c.inset : colors.fill,
        shape: cruShape(CruRadius.iconTile),
      ),
      child: Text(
        tooth,
        style: CruType.callout.w600.tabular.tint(
          state == ToothState.healthy ? c.label : colors.text,
        ),
      ),
    );
  }
}

// ======================================================= record a finding

Future<bool> showToothFindingDialog(
  BuildContext context, {
  required Patient patient,
  required String tooth,
  ToothChartEntryModel? latest,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _ToothFindingDialog(
      patient: patient,
      tooth: tooth,
      latest: latest,
    ),
  );
  return saved == true;
}

class _ToothFindingDialog extends ConsumerStatefulWidget {
  const _ToothFindingDialog({
    required this.patient,
    required this.tooth,
    required this.latest,
  });

  final Patient patient;
  final String tooth;
  final ToothChartEntryModel? latest;

  @override
  ConsumerState<_ToothFindingDialog> createState() =>
      _ToothFindingDialogState();
}

class _ToothFindingDialogState extends ConsumerState<_ToothFindingDialog> {
  ToothCondition? _condition;
  ToothTreatment? _treatment;
  final Set<ToothSurface> _surfaces = {};
  final _notes = TextEditingController();
  DateTime _date = DateTime.now();
  bool _saving = false;
  bool _dirty = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    // Start from what's on the chart now.
    final l = widget.latest;
    _condition = DentalChart.condition(l?.condition);
    _treatment = DentalChart.treatment(l?.treatment);
    _surfaces.addAll(DentalChart.surfaces(l?.surface));
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _notice = null;
    });
    try {
      final now = DateTime.now();
      final at = DateTime(_date.year, _date.month, _date.day, now.hour,
          now.minute, now.second);
      await ref.read(dentalRepositoryProvider).saveToothChartEntry(
            ToothChartEntryModel(
              id: _uuid.v4(),
              doctorId: ref.read(dentalDoctorIdProvider),
              patientId: widget.patient.id,
              toothNumber: widget.tooth,
              condition: _condition?.name,
              treatment: _treatment?.name,
              surface: DentalChart.storeSurfaces(_surfaces),
              notes: _notes.text.trim(),
              recordedAt: at,
              createdAt: now,
              updatedAt: now,
              syncStatus: 'pending',
            ),
          );
      refreshDentalPatient(ref, widget.patient.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _saving = false;
        _notice = "Couldn't save the finding. Try again.";
      });
    }
  }

  void _edited() {
    if (!_dirty) setState(() => _dirty = true);
  }

  @override
  Widget build(BuildContext context) {
    final state = DentalChart.stateOf(ToothChartEntryModel(
      id: '',
      doctorId: '',
      patientId: '',
      toothNumber: widget.tooth,
      condition: _condition?.name,
      treatment: _treatment?.name,
      recordedAt: _date,
      createdAt: _date,
      updatedAt: _date,
    ));
    return CruFormDialog(
      title: 'Tooth ${widget.tooth}',
      subtitle: '${DentalChart.name(widget.tooth)} · ${widget.patient.fullName}',
      leading: ToothBadge(tooth: widget.tooth, state: state),
      submitLabel: 'Save finding',
      onSubmit: _save,
      busy: _saving,
      dirty: _dirty,
      notice: _notice,
      footerHint: 'Ctrl + Enter to save',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CruFormSection(
            first: true,
            title: 'Finding',
            description: 'What you see on this tooth today.',
            children: [
              CruFieldFrame(
                label: 'Condition',
                child: DentalChipWrap<ToothCondition?>(
                  options: const [null, ...ToothCondition.values],
                  label: (c) => c == null ? 'Healthy' : DentalChart.conditionLabel(c),
                  isSelected: (c) => c == _condition,
                  onTap: (c) {
                    setState(() => _condition = c);
                    _edited();
                  },
                ),
              ),
              CruFieldFrame(
                label: 'Treatment done',
                optional: true,
                child: DentalChipWrap<ToothTreatment?>(
                  options: const [null, ...ToothTreatment.values],
                  label: (t) => t == null ? 'None' : DentalChart.treatmentLabel(t),
                  isSelected: (t) => t == _treatment,
                  onTap: (t) {
                    setState(() => _treatment = t);
                    _edited();
                  },
                ),
              ),
              CruFieldFrame(
                label: 'Surfaces',
                optional: true,
                help: 'Mesial, distal, occlusal, buccal, lingual, incisal, cervical.',
                child: DentalChipWrap<ToothSurface>(
                  options: ToothSurface.values,
                  label: (s) =>
                      '${DentalChart.surfaceLetter(s)} · ${DentalChart.surfaceLabel(s)}',
                  isSelected: _surfaces.contains,
                  onTap: (s) {
                    setState(() =>
                        _surfaces.contains(s) ? _surfaces.remove(s) : _surfaces.add(s));
                    _edited();
                  },
                ),
              ),
            ],
          ),
          CruFormSection(
            title: 'Notes',
            children: [
              CruFieldRow(
                children: [
                  CruPickerField(
                    label: 'Date',
                    icon: CruIcons.calendar,
                    value: DentalFormat.date(_date),
                    placeholder: 'Pick a date',
                    trailing: DentalFormat.sameDay(_date, DateTime.now())
                        ? const CruInfoPill(text: 'Today')
                        : null,
                    onTap: () async {
                      final d = await pickDentalDate(context,
                          initial: _date, last: DateTime.now());
                      if (d != null) {
                        setState(() => _date = d);
                        _edited();
                      }
                    },
                  ),
                  const SizedBox.shrink(),
                ],
              ),
              CruTextField(
                label: 'Notes',
                optional: true,
                controller: _notes,
                maxLines: 3,
                hint: 'Sensitive to cold, deep pocket distal…',
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => _edited(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =================================================== procedure picking

/// Catalog chips plus a name field: pick a procedure or type one.
class _ProcedurePicker extends ConsumerWidget {
  const _ProcedurePicker({
    required this.name,
    required this.selectedId,
    required this.onPick,
    required this.onTyped,
  });

  final TextEditingController name;
  final String? selectedId;
  final ValueChanged<DentalProcedureCatalogModel> onPick;
  final VoidCallback onTyped;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = (ref.watch(dentalProcedureListProvider).value ?? const [])
        .where((p) => p.isActive && !p.isDeleted)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (catalog.isNotEmpty)
          CruFieldFrame(
            label: 'From your procedures',
            child: DentalChipWrap<DentalProcedureCatalogModel>(
              options: catalog,
              label: (p) => p.name,
              isSelected: (p) => p.id == selectedId,
              onTap: onPick,
            ),
          ),
        CruTextField(
          label: 'Procedure',
          controller: name,
          hint: 'Root canal treatment, composite filling…',
          help: catalog.isEmpty
              ? 'Add your procedures and fees under Procedures in the sidebar '
                  'to pick them here.'
              : null,
          textCapitalization: TextCapitalization.sentences,
          validator: (v) =>
              (v ?? '').trim().isEmpty ? 'Name the procedure.' : null,
          onChanged: (_) => onTyped(),
        ),
      ],
    );
  }
}

String? _validateTeeth(String? v, {required bool required}) {
  final text = (v ?? '').trim();
  if (text.isEmpty) return required ? 'Add the teeth, like 16, 17.' : null;
  final r = DentalChart.parseTeeth(text);
  if (r.invalid != null) return '"${r.invalid}" isn\'t a tooth number (FDI).';
  return null;
}

// ======================================================= log a procedure

Future<bool> showProcedureLogDialog(
  BuildContext context, {
  required Patient patient,
  List<String> teeth = const [],
  DentalProcedureLogModel? existing,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _ProcedureLogDialog(
      patient: patient,
      teeth: teeth,
      existing: existing,
    ),
  );
  return saved == true;
}

class _ProcedureLogDialog extends ConsumerStatefulWidget {
  const _ProcedureLogDialog({
    required this.patient,
    required this.teeth,
    required this.existing,
  });

  final Patient patient;
  final List<String> teeth;
  final DentalProcedureLogModel? existing;

  @override
  ConsumerState<_ProcedureLogDialog> createState() =>
      _ProcedureLogDialogState();
}

class _ProcedureLogDialogState extends ConsumerState<_ProcedureLogDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _teeth;
  late final TextEditingController _materials;
  late final TextEditingController _notes;
  String? _catalogId;
  String _catalogCode = '';
  bool _needsTeeth = false;
  late DentalProcedureStatus _status;
  late DateTime _date;
  bool _saving = false;
  bool _dirty = false;
  bool _submitted = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.procedureName ?? '');
    _teeth = TextEditingController(
        text: (e?.toothNumbers ?? widget.teeth).join(', '));
    _materials = TextEditingController(text: e?.materials ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _catalogId = e?.procedureCatalogId;
    _status = e == null
        ? DentalProcedureStatus.completed
        : DentalProcedureStatus.fromString(e.status);
    _date = e?.performedAt ?? DateTime.now();
  }

  @override
  void dispose() {
    _name.dispose();
    _teeth.dispose();
    _materials.dispose();
    _notes.dispose();
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
      final repo = ref.read(dentalRepositoryProvider);
      final doctorId = ref.read(dentalDoctorIdProvider);
      final teeth = DentalChart.parseTeeth(_teeth.text).teeth;
      final now = DateTime.now();
      final e = widget.existing;
      final log = DentalProcedureLogModel(
        id: e?.id ?? _uuid.v4(),
        doctorId: doctorId,
        patientId: widget.patient.id,
        visitId: e?.visitId,
        procedureCatalogId: _catalogId,
        procedureName: _name.text.trim(),
        toothNumbers: teeth,
        status: _status.code,
        notes: _notes.text.trim(),
        materials: _materials.text.trim().isEmpty ? null : _materials.text.trim(),
        performedAt: _date,
        createdAt: e?.createdAt ?? now,
        updatedAt: now,
        syncStatus: 'pending',
      );
      await repo.saveProcedureLog(log);
      // A completed procedure shows on the tooth chart.
      final wasCompleted = e != null &&
          DentalProcedureStatus.fromString(e.status) ==
              DentalProcedureStatus.completed;
      final t = DentalChart.treatmentForProcedure(_catalogCode, log.procedureName);
      if (_status == DentalProcedureStatus.completed && !wasCompleted && t != null) {
        for (final tooth in teeth) {
          await repo.saveToothChartEntry(ToothChartEntryModel(
            id: _uuid.v4(),
            doctorId: doctorId,
            patientId: widget.patient.id,
            toothNumber: tooth,
            treatment: t.name,
            condition: t == ToothTreatment.extraction ? ToothCondition.missing.name : null,
            procedureLogId: log.id,
            notes: log.procedureName,
            recordedAt: _date,
            createdAt: now,
            updatedAt: now,
            syncStatus: 'pending',
          ));
        }
      }
      refreshDentalPatient(ref, widget.patient.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      setState(() {
        _saving = false;
        _notice = "Couldn't save the procedure. Try again.";
      });
    }
  }

  Future<void> _delete() async {
    final e = widget.existing;
    if (e == null) return;
    final ok = await confirmDental(
      context,
      title: 'Remove this procedure?',
      body: '${e.procedureName} on ${DentalFormat.date(e.performedAt)} will '
          'be removed from ${widget.patient.firstName}\'s record.',
      action: 'Remove',
    );
    if (!ok || !mounted) return;
    await ref.read(dentalRepositoryProvider).deleteProcedureLog(e.id);
    refreshDentalPatient(ref, widget.patient.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final t = DentalChart.treatmentForProcedure(_catalogCode, _name.text);
    return CruFormDialog(
      title: widget.existing == null ? 'Log procedure' : 'Procedure',
      subtitle: widget.patient.fullName,
      leading: const CruIconTile(icon: DentalIcons.tooth, tone: CruTileTone.accent),
      submitLabel: widget.existing == null ? 'Log procedure' : 'Save changes',
      onSubmit: _save,
      busy: _saving,
      dirty: _dirty,
      notice: _notice,
      footerHint: _status == DentalProcedureStatus.completed && t != null
          ? 'Completing it marks ${DentalChart.treatmentLabel(t).toLowerCase()} on the chart.'
          : 'Ctrl + Enter to save',
      body: Form(
        key: _form,
        autovalidateMode: _submitted
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CruFormSection(
              first: true,
              title: 'Procedure',
              description: 'What was done and on which teeth.',
              children: [
                _ProcedurePicker(
                  name: _name,
                  selectedId: _catalogId,
                  onPick: (p) {
                    setState(() {
                      _catalogId = p.id;
                      _catalogCode = p.code;
                      _needsTeeth = p.requiresToothSelection;
                      _name.text = p.name;
                    });
                    _edited();
                  },
                  onTyped: () {
                    setState(() {
                      _catalogId = null;
                      _catalogCode = '';
                    });
                    _edited();
                  },
                ),
                CruFieldRow(
                  children: [
                    CruTextField(
                      label: 'Teeth',
                      optional: !_needsTeeth,
                      controller: _teeth,
                      hint: '16, 17',
                      tabular: true,
                      validator: (v) => _validateTeeth(v, required: _needsTeeth),
                      onChanged: (_) => _edited(),
                    ),
                    CruPickerField(
                      label: 'Date',
                      icon: CruIcons.calendar,
                      value: DentalFormat.date(_date),
                      placeholder: 'Pick a date',
                      trailing: DentalFormat.sameDay(_date, DateTime.now())
                          ? const CruInfoPill(text: 'Today')
                          : null,
                      onTap: () async {
                        final d = await pickDentalDate(context, initial: _date);
                        if (d != null) {
                          setState(() => _date = d);
                          _edited();
                        }
                      },
                    ),
                  ],
                ),
                CruFieldFrame(
                  label: 'Status',
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: CruSegmentedControl<DentalProcedureStatus>(
                      semanticLabel: 'Status',
                      segments: const [
                        CruSegment(DentalProcedureStatus.planned, 'Planned'),
                        CruSegment(DentalProcedureStatus.inProgress, 'In progress'),
                        CruSegment(DentalProcedureStatus.completed, 'Completed'),
                      ],
                      selected: _status,
                      onChanged: (s) {
                        setState(() => _status = s);
                        _edited();
                      },
                    ),
                  ),
                ),
              ],
            ),
            CruFormSection(
              title: 'Notes',
              children: [
                CruTextField(
                  label: 'Materials',
                  optional: true,
                  controller: _materials,
                  hint: 'Composite A2, 2 cartridges lignocaine…',
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => _edited(),
                ),
                CruTextField(
                  label: 'Notes',
                  optional: true,
                  controller: _notes,
                  maxLines: 3,
                  hint: 'How it went, what to watch for',
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => _edited(),
                ),
                if (widget.existing != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: CruLink(
                      label: 'Remove this procedure',
                      onPressed: _delete,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================================== plan items

Future<bool> showPlanItemDialog(
  BuildContext context, {
  required Patient patient,
  List<String> teeth = const [],
  TreatmentPlanLineItemModel? existing,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _PlanItemDialog(
      patient: patient,
      teeth: teeth,
      existing: existing,
    ),
  );
  return saved == true;
}

class _PlanItemDialog extends ConsumerStatefulWidget {
  const _PlanItemDialog({
    required this.patient,
    required this.teeth,
    required this.existing,
  });

  final Patient patient;
  final List<String> teeth;
  final TreatmentPlanLineItemModel? existing;

  @override
  ConsumerState<_PlanItemDialog> createState() => _PlanItemDialogState();
}

class _PlanItemDialogState extends ConsumerState<_PlanItemDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _teeth;
  late final TextEditingController _price;
  String? _catalogId;
  DentalProcedureCatalogModel? _picked;
  late TreatmentPlanItemStatus _status;
  bool _saving = false;
  bool _dirty = false;
  bool _submitted = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.procedureName ?? '');
    _teeth = TextEditingController(
        text: (e?.toothNumbers ?? widget.teeth).join(', '));
    _price = TextEditingController(
        text: e == null || e.estimatedPrice <= 0
            ? ''
            : e.estimatedPrice.round().toString());
    _catalogId = e?.procedureCatalogId;
    _status = e == null
        ? TreatmentPlanItemStatus.proposed
        : TreatmentPlanItemStatus.fromString(e.status);
  }

  @override
  void dispose() {
    _name.dispose();
    _teeth.dispose();
    _price.dispose();
    super.dispose();
  }

  void _edited() {
    if (!_dirty) setState(() => _dirty = true);
  }

  /// The catalog fee, per tooth when it's charged per tooth.
  void _suggestPrice() {
    final p = _picked;
    if (p == null || p.defaultPrice == null) return;
    final n = DentalChart.parseTeeth(_teeth.text).teeth.length;
    final total = p.defaultPrice! * (p.requiresToothSelection && n > 1 ? n : 1);
    _price.text = total.round().toString();
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _notice = null;
    });
    try {
      final repo = ref.read(dentalRepositoryProvider);
      final existingItems =
          await repo.getTreatmentPlanLineItems(widget.patient.id);
      final planId = widget.existing?.treatmentPlanId ??
          (existingItems.isEmpty ? _uuid.v4() : existingItems.first.treatmentPlanId);
      final nextSeq = existingItems.isEmpty
          ? 1
          : existingItems.map((i) => i.sequence).reduce((a, b) => a > b ? a : b) + 1;
      final now = DateTime.now();
      final e = widget.existing;
      await repo.saveTreatmentPlanLineItem(TreatmentPlanLineItemModel(
        id: e?.id ?? _uuid.v4(),
        doctorId: ref.read(dentalDoctorIdProvider),
        patientId: widget.patient.id,
        treatmentPlanId: planId,
        procedureCatalogId: _catalogId,
        procedureName: _name.text.trim(),
        toothNumbers: DentalChart.parseTeeth(_teeth.text).teeth,
        estimatedPrice: double.tryParse(_price.text.trim()) ?? 0,
        sequence: e?.sequence ?? nextSeq,
        status: _status.code,
        createdAt: e?.createdAt ?? now,
        updatedAt: now,
        syncStatus: 'pending',
      ));
      refreshDentalPatient(ref, widget.patient.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      setState(() {
        _saving = false;
        _notice = "Couldn't save the plan. Try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CruFormDialog(
      title: widget.existing == null ? 'Add to treatment plan' : 'Plan item',
      subtitle: widget.patient.fullName,
      leading: const CruIconTile(icon: DentalIcons.plan, tone: CruTileTone.accent),
      submitLabel: widget.existing == null ? 'Add to plan' : 'Save changes',
      onSubmit: _save,
      busy: _saving,
      dirty: _dirty,
      notice: _notice,
      footerHint: 'Ctrl + Enter to save',
      body: Form(
        key: _form,
        autovalidateMode: _submitted
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CruFormSection(
              first: true,
              title: 'Procedure',
              description: 'What you recommend, on which teeth, for how much.',
              children: [
                _ProcedurePicker(
                  name: _name,
                  selectedId: _catalogId,
                  onPick: (p) {
                    setState(() {
                      _catalogId = p.id;
                      _picked = p;
                      _name.text = p.name;
                      _suggestPrice();
                    });
                    _edited();
                  },
                  onTyped: () {
                    setState(() {
                      _catalogId = null;
                      _picked = null;
                    });
                    _edited();
                  },
                ),
                CruFieldRow(
                  children: [
                    CruTextField(
                      label: 'Teeth',
                      optional: true,
                      controller: _teeth,
                      hint: '16, 17',
                      tabular: true,
                      validator: (v) => _validateTeeth(v, required: false),
                      onChanged: (_) {
                        setState(_suggestPrice);
                        _edited();
                      },
                    ),
                    CruTextField(
                      label: 'Estimate',
                      optional: true,
                      controller: _price,
                      prefix: '₹',
                      hint: '0',
                      tabular: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      onChanged: (_) => _edited(),
                    ),
                  ],
                ),
                CruFieldFrame(
                  label: 'Status',
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: CruSegmentedControl<TreatmentPlanItemStatus>(
                      semanticLabel: 'Status',
                      segments: [
                        const CruSegment(TreatmentPlanItemStatus.proposed, 'Proposed'),
                        const CruSegment(TreatmentPlanItemStatus.accepted, 'Accepted'),
                        if (widget.existing != null) ...const [
                          CruSegment(TreatmentPlanItemStatus.declined, 'Declined'),
                          CruSegment(TreatmentPlanItemStatus.invoiced, 'Invoiced'),
                        ],
                      ],
                      selected: _status,
                      onChanged: (s) {
                        setState(() => _status = s);
                        _edited();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================= plan manager

Future<void> showTreatmentPlanDialog(
  BuildContext context, {
  required Patient patient,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _TreatmentPlanDialog(patient: patient),
    );

class _TreatmentPlanDialog extends ConsumerWidget {
  const _TreatmentPlanDialog({required this.patient});

  final Patient patient;

  Future<void> _setStatus(
    WidgetRef ref,
    TreatmentPlanLineItemModel i,
    TreatmentPlanItemStatus s,
  ) async {
    await ref
        .read(dentalRepositoryProvider)
        .updateTreatmentPlanLineItemStatus(i.id, s.code);
    refreshDentalPatient(ref, patient.id);
  }

  Future<void> _move(
    WidgetRef ref,
    List<TreatmentPlanLineItemModel> items,
    int from,
    int to,
  ) async {
    final repo = ref.read(dentalRepositoryProvider);
    final a = items[from], b = items[to];
    final now = DateTime.now();
    await repo.saveTreatmentPlanLineItem(
        a.copyWith(sequence: b.sequence, updatedAt: now));
    await repo.saveTreatmentPlanLineItem(
        b.copyWith(sequence: a.sequence, updatedAt: now));
    refreshDentalPatient(ref, patient.id);
  }

  Future<void> _invoice(
    BuildContext context,
    WidgetRef ref,
    List<TreatmentPlanLineItemModel> accepted,
  ) async {
    final names = accepted.map((i) => i.procedureName.trim()).join(', ');
    final lines = [
      for (final i in accepted)
        '${i.procedureName}'
            '${DentalChart.teethText(i.toothNumbers) == null ? '' : ' (${DentalChart.teethText(i.toothNumbers)})'}'
            ' · ${DashFormat.rupees(i.estimatedPrice)}',
    ].join('\n');
    final invoice = await showDesktopCreateInvoiceDialog(
      context,
      initialPatient: patient,
      initialTreatmentName: names,
      initialNotes: lines,
    );
    if (invoice == null) return;
    for (final i in accepted) {
      await ref
          .read(dentalRepositoryProvider)
          .updateTreatmentPlanLineItemStatus(i.id, TreatmentPlanItemStatus.invoiced.code);
    }
    refreshDentalPatient(ref, patient.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final items = [...(ref.watch(patientTreatmentPlanProvider(patient.id)).value ?? const <TreatmentPlanLineItemModel>[])]
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    double sum(TreatmentPlanItemStatus s) => items
        .where((i) => TreatmentPlanItemStatus.fromString(i.status) == s)
        .fold(0.0, (t, i) => t + i.estimatedPrice);
    final accepted = items
        .where((i) =>
            TreatmentPlanItemStatus.fromString(i.status) ==
            TreatmentPlanItemStatus.accepted)
        .toList();
    final proposed = items
        .where((i) =>
            TreatmentPlanItemStatus.fromString(i.status) ==
            TreatmentPlanItemStatus.proposed)
        .toList();

    return DentalPanelDialog(
      title: 'Treatment plan',
      subtitle: patient.fullName,
      leading: const CruIconTile(icon: DentalIcons.plan, tone: CruTileTone.accent),
      body: items.isEmpty
          ? DentalEmptyState(
              icon: DentalIcons.plan,
              title: 'No treatment plan yet',
              body: 'Add the procedures you recommend, with teeth and fees. '
                  '${patient.firstName} can accept them one by one.',
              actions: [
                CruButton(
                  label: 'Add procedure',
                  icon: CruIcons.plus,
                  onPressed: () => showPlanItemDialog(context, patient: patient),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const CruSeparator(indent: 48),
                  _PlanRow(
                    index: i,
                    item: items[i],
                    onEdit: () => showPlanItemDialog(context,
                        patient: patient, existing: items[i]),
                    onAction: (a) async {
                      switch (a) {
                        case _PlanAction.accept:
                          await _setStatus(ref, items[i], TreatmentPlanItemStatus.accepted);
                        case _PlanAction.propose:
                          await _setStatus(ref, items[i], TreatmentPlanItemStatus.proposed);
                        case _PlanAction.decline:
                          await _setStatus(ref, items[i], TreatmentPlanItemStatus.declined);
                        case _PlanAction.invoiced:
                          await _setStatus(ref, items[i], TreatmentPlanItemStatus.invoiced);
                        case _PlanAction.up:
                          if (i > 0) await _move(ref, items, i, i - 1);
                        case _PlanAction.down:
                          if (i < items.length - 1) await _move(ref, items, i, i + 1);
                        case _PlanAction.edit:
                          await showPlanItemDialog(context,
                              patient: patient, existing: items[i]);
                        case _PlanAction.remove:
                          final ok = await confirmDental(
                            context,
                            title: 'Remove from the plan?',
                            body: '${items[i].procedureName} will be taken off '
                                '${patient.firstName}\'s plan.',
                            action: 'Remove',
                          );
                          if (ok) {
                            await ref
                                .read(dentalRepositoryProvider)
                                .deleteTreatmentPlanLineItem(items[i].id);
                            refreshDentalPatient(ref, patient.id);
                          }
                      }
                    },
                  ),
                ],
                const SizedBox(height: CruSpace.s12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
                  child: Text(
                    [
                      if (sum(TreatmentPlanItemStatus.proposed) > 0)
                        '${DashFormat.rupees(sum(TreatmentPlanItemStatus.proposed))} proposed',
                      if (sum(TreatmentPlanItemStatus.accepted) > 0)
                        '${DashFormat.rupees(sum(TreatmentPlanItemStatus.accepted))} accepted',
                      if (sum(TreatmentPlanItemStatus.invoiced) > 0)
                        '${DashFormat.rupees(sum(TreatmentPlanItemStatus.invoiced))} invoiced',
                    ].join(' · '),
                    style: CruType.subhead.tabular.tint(c.label2),
                  ),
                ),
              ],
            ),
      footer: items.isEmpty
          ? null
          : Row(
              children: [
                CruButton(
                  label: 'Add procedure',
                  kind: CruButtonKind.secondary,
                  icon: CruIcons.plus,
                  onPressed: () => showPlanItemDialog(context, patient: patient),
                ),
                const Spacer(),
                if (proposed.isNotEmpty) ...[
                  CruButton(
                    label: 'Accept all proposed',
                    kind: CruButtonKind.inset,
                    onPressed: () async {
                      for (final i in proposed) {
                        await ref.read(dentalRepositoryProvider).updateTreatmentPlanLineItemStatus(
                            i.id, TreatmentPlanItemStatus.accepted.code);
                      }
                      refreshDentalPatient(ref, patient.id);
                    },
                  ),
                  const SizedBox(width: CruSpace.s10),
                ],
                CruButton(
                  label: accepted.isEmpty
                      ? 'Invoice accepted'
                      : 'Invoice ${DashFormat.rupees(sum(TreatmentPlanItemStatus.accepted))}',
                  onPressed: accepted.isEmpty
                      ? null
                      : () => _invoice(context, ref, accepted),
                ),
              ],
            ),
    );
  }
}

enum _PlanAction { accept, propose, decline, invoiced, up, down, edit, remove }

class _PlanRow extends StatelessWidget {
  const _PlanRow({
    required this.index,
    required this.item,
    required this.onEdit,
    required this.onAction,
  });

  final int index;
  final TreatmentPlanLineItemModel item;
  final VoidCallback onEdit;
  final ValueChanged<_PlanAction> onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final status = TreatmentPlanItemStatus.fromString(item.status);
    final declined = status == TreatmentPlanItemStatus.declined;
    final teeth = DentalChart.teethText(item.toothNumbers);
    return DentalListRow(
      semanticLabel: '${item.procedureName}, ${status.label}',
      onTap: onEdit,
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: ShapeDecoration(color: c.inset, shape: const CircleBorder()),
            child: Text('${index + 1}', style: CruType.caption.w600.tabular.tint(c.label2)),
          ),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.procedureName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.callout.tint(declined ? c.label3 : c.label).copyWith(
                        decoration: declined ? TextDecoration.lineThrough : null,
                      ),
                ),
                if (teeth != null)
                  Text(teeth, style: CruType.subhead.tabular.tint(c.label2)),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          Text(
            item.estimatedPrice > 0 ? DashFormat.rupees(item.estimatedPrice) : '—',
            style: CruType.row.tabular.tint(declined ? c.label3 : c.label),
          ),
          const SizedBox(width: CruSpace.s12),
          planStatusPill(c, item.status),
          const SizedBox(width: CruSpace.s4),
          PopupMenuButton<_PlanAction>(
            tooltip: 'More',
            onSelected: onAction,
            color: c.surface,
            shape: cruShape(CruRadius.control, side: BorderSide(color: c.hairline)),
            itemBuilder: (_) => [
              if (status != TreatmentPlanItemStatus.accepted)
                _item(c, _PlanAction.accept, 'Mark accepted'),
              if (status != TreatmentPlanItemStatus.proposed)
                _item(c, _PlanAction.propose, 'Mark proposed'),
              if (status != TreatmentPlanItemStatus.invoiced)
                _item(c, _PlanAction.invoiced, 'Mark invoiced'),
              if (status != TreatmentPlanItemStatus.declined)
                _item(c, _PlanAction.decline, 'Mark declined'),
              const PopupMenuDivider(),
              _item(c, _PlanAction.up, 'Move up'),
              _item(c, _PlanAction.down, 'Move down'),
              _item(c, _PlanAction.edit, 'Edit'),
              _item(c, _PlanAction.remove, 'Remove'),
            ],
            child: SizedBox(
              width: CruSize.squareButton,
              height: CruSize.squareButton,
              child: Center(
                child: CruIcon(CruIcons.more, size: 18, color: c.label2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static PopupMenuItem<_PlanAction> _item(CruColors c, _PlanAction a, String label) =>
      PopupMenuItem(
        value: a,
        height: CruSize.control,
        child: Text(label, style: CruType.text.tint(c.label)),
      );
}
