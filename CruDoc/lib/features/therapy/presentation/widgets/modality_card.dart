import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/therapy/data/modality_catalog.dart';
import 'package:doctor_management_app/features/therapy/domain/modality_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Patient Details card: the electrotherapy and thermal treatments given,
/// grouped by the session they were given in.
///
/// Settings are shown, not hidden behind a tap. The whole reason this log
/// exists is that "had ultrasound" is not a record of treatment, so the card
/// would be pointless if it only said that.
class ModalityCard extends ConsumerWidget {
  const ModalityCard({super.key, required this.patient});

  final Patient patient;

  /// Sessions shown before the card stops growing. The rest are reached
  /// through the day rows above, which already carry the recent history.
  static const _maxDays = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final recs = ref.watch(
      patientRecordsProvider((
        patientId: patient.id,
        kind: RecKind.physioModality,
      )),
    );
    final apps = modalityApplications(recs.value ?? const <DentalRecord>[]);
    final days = modalityDays(apps);
    final tally = modalityTallyLine(apps);
    final incomplete = [
      for (final a in apps)
        if (a.isIncomplete) a,
    ];

    return CruCard(
      semanticLabel: 'Electrotherapy and modalities',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CruIconTile(
                icon: CruIcons.sparkleSingle,
                tone: incomplete.isNotEmpty
                    ? CruTileTone.amber
                    : CruTileTone.neutral,
              ),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Electrotherapy',
                      style: CruType.headline.w600.tint(c.label),
                    ),
                    const SizedBox(height: CruSpace.s2),
                    Text(
                      apps.isEmpty
                          ? 'TENS, IFT, ultrasound and the rest, with their '
                                'settings'
                          : (incomplete.isNotEmpty
                                ? '${incomplete.length} logged without full '
                                      'settings'
                                : tally!),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: CruType.caption.tabular.tint(
                        incomplete.isNotEmpty ? c.amberText : c.label2,
                      ),
                    ),
                  ],
                ),
              ),
              CruCapsuleButton(
                label: apps.isEmpty ? 'Log' : '+ Log',
                icon: apps.isEmpty ? CruIcons.plus : null,
                onPressed: () => showModalitySheet(context, ref, patient),
              ),
            ],
          ),
          for (final day in days.take(_maxDays)) ...[
            const SizedBox(height: CruSpace.s12),
            Text(
              DentalFormat.date(day.day),
              style: CruType.groupLabel.tabular.tint(c.label3),
            ),
            for (final a in day.applications)
              InkWell(
                borderRadius: BorderRadius.circular(CruRadius.control),
                onTap: () =>
                    showModalitySheet(context, ref, patient, existing: a),
                child: Padding(
                  padding: const EdgeInsets.only(top: CruSpace.s8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              [
                                a.label,
                                if (a.site.trim().isNotEmpty) a.site.trim(),
                              ].join(' · '),
                              style: CruType.body.w600.tint(c.label),
                            ),
                            if (a.settingsLine.isNotEmpty)
                              Text(
                                a.settingsLine,
                                style: CruType.caption.tabular.tint(c.label2),
                              ),
                            if (a.note.trim().isNotEmpty)
                              Text(
                                a.note.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: CruType.caption.tint(c.label3),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: CruSpace.s12),
                      Text(
                        a.minutes == null ? '—' : '${a.minutes} min',
                        style: CruType.caption.tabular.tint(
                          a.minutes == null ? c.amberText : c.label2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          if (days.length > _maxDays)
            Padding(
              padding: const EdgeInsets.only(top: CruSpace.s12),
              child: Text(
                '${days.length - _maxDays} earlier '
                'session${days.length - _maxDays == 1 ? '' : 's'} not shown',
                style: CruType.caption.tabular.tint(c.label3),
              ),
            ),
        ],
      ),
    );
  }
}

/// Log an application, or open one to correct it.
Future<void> showModalitySheet(
  BuildContext context,
  WidgetRef ref,
  Patient patient, {
  ModalityApplication? existing,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _ModalitySheet(patient: patient, existing: existing),
);

class _ModalitySheet extends ConsumerStatefulWidget {
  const _ModalitySheet({required this.patient, required this.existing});

  final Patient patient;
  final ModalityApplication? existing;

  @override
  ConsumerState<_ModalitySheet> createState() => _ModalitySheetState();
}

class _ModalitySheetState extends ConsumerState<_ModalitySheet> {
  late ModalityDef? _modality = widget.existing == null
      ? null
      : modalityById(widget.existing!.modalityId);
  late final TextEditingController _site = TextEditingController(
    text: widget.existing?.site ?? '',
  );
  late final TextEditingController _minutes = TextEditingController(
    text: widget.existing?.minutes?.toString() ?? '',
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.existing?.note ?? '',
  );

  /// Typed values by parameter id. Choices and numbers both live here, since
  /// what is stored either way is the text the physio settled on.
  late final Map<String, String> _values = {...?widget.existing?.params};

  /// Controllers for the number fields, made as modalities are chosen and
  /// kept so switching back to a modality does not wipe what was typed.
  final Map<String, TextEditingController> _numberControllers = {};

  bool _saving = false;

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    _site.dispose();
    _minutes.dispose();
    _note.dispose();
    for (final c in _numberControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(ModalityParam p) =>
      _numberControllers.putIfAbsent(
        p.id,
        () => TextEditingController(text: _values[p.id] ?? '')
          ..addListener(() {
            final text = _numberControllers[p.id]!.text.trim();
            if (text.isEmpty) {
              _values.remove(p.id);
            } else {
              _values[p.id] = text;
            }
          }),
      );

  Future<void> _save() async {
    final m = _modality;
    if (m == null) return;
    setState(() => _saving = true);
    final data = ModalityApplication.toData(
      modalityId: m.id,
      site: _site.text.trim(),
      minutes: int.tryParse(_minutes.text.trim()),
      params: _values,
      note: _note.text.trim(),
    );
    final old = widget.existing;
    await saveDentalRecord(
      ref,
      old != null
          ? old.record.copyWith(data: data)
          : DentalRecord.create(
              widget.patient.id,
              RecKind.physioModality,
              data,
            ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final app = widget.existing;
    if (app == null) return;
    final ok = await confirmDental(
      context,
      title: 'Delete this application?',
      body:
          '${app.summaryLine} will be removed from the treatment log. '
          'A treatment that was given is normally corrected, not deleted.',
      action: 'Delete',
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    await deleteDentalRecord(ref, app.record);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final m = _modality;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          CruSpace.s16,
          0,
          CruSpace.s16,
          CruSpace.s16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isNew ? 'Log a treatment' : 'Treatment given',
              style: CruType.headline.tint(c.label),
            ),
            const SizedBox(height: CruSpace.s4),
            Text(
              m == null ? 'Which machine, then what it was set to.' : m.name,
              style: CruType.caption.tint(c.label2),
            ),
            const SizedBox(height: CruSpace.s16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: CruSpace.s8,
                      runSpacing: CruSpace.s8,
                      children: [
                        for (final d in kModalities)
                          DentalChoiceChip(
                            label: d.short,
                            selected: m?.id == d.id,
                            onTap: () => setState(() => _modality = d),
                          ),
                      ],
                    ),
                    if (m != null) ...[
                      const SizedBox(height: CruSpace.s16),
                      _Cautions(modality: m),
                      const SizedBox(height: CruSpace.s16),
                      CruTextField(
                        label: 'Site',
                        controller: _site,
                        hint: 'R knee, lower back, L shoulder',
                        textCapitalization: TextCapitalization.sentences,
                      ),
                      const SizedBox(height: CruSpace.s12),
                      for (final p in m.params) ...[
                        _ParamField(
                          param: p,
                          value: _values[p.id],
                          controller: p.isChoice ? null : _controllerFor(p),
                          onChoose: (v) => setState(() {
                            if (v == null) {
                              _values.remove(p.id);
                            } else {
                              _values[p.id] = v;
                            }
                          }),
                          onPreset: (v) => setState(() {
                            _values[p.id] = v;
                            _controllerFor(p).text = v;
                          }),
                        ),
                        const SizedBox(height: CruSpace.s12),
                      ],
                      _Minutes(
                        controller: _minutes,
                        presets: m.minutePresets,
                        onPreset: (v) => setState(() => _minutes.text = v),
                      ),
                      const SizedBox(height: CruSpace.s12),
                      CruTextField(
                        label: 'Note',
                        controller: _note,
                        hint: 'How the patient responded',
                        optional: true,
                        maxLines: 2,
                        textCapitalization: TextCapitalization.sentences,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: CruSpace.s16),
            CruButton(
              label: _saving
                  ? 'Saving…'
                  : (_isNew ? 'Log treatment' : 'Save changes'),
              expand: true,
              onPressed: _saving || m == null ? null : _save,
            ),
            if (!_isNew) ...[
              const SizedBox(height: CruSpace.s8),
              CruCapsuleButton(
                label: 'Delete',
                onPressed: _saving ? null : _delete,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The contraindications for the chosen modality.
///
/// Amber, never red: red in CruDoc belongs to allergies and patient safety
/// alarms, and this is a list to read rather than a warning that something
/// is already wrong. Nothing here blocks logging — the physio decides, and
/// the app's job is to put the list in front of them while they do.
class _Cautions extends StatefulWidget {
  const _Cautions({required this.modality});

  final ModalityDef modality;

  @override
  State<_Cautions> createState() => _CautionsState();
}

class _CautionsState extends State<_Cautions> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final list = widget.modality.cautions;
    if (list.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(CruSpace.s12),
      decoration: BoxDecoration(
        color: c.amberTint,
        borderRadius: BorderRadius.circular(CruRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Check before applying — ${list.length} '
                    'contraindication${list.length == 1 ? '' : 's'}',
                    style: CruType.caption.w600.tint(c.amberText),
                  ),
                ),
                Icon(
                  _open
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: c.amberText,
                ),
              ],
            ),
          ),
          if (_open)
            for (final x in list)
              Padding(
                padding: const EdgeInsets.only(top: CruSpace.s4),
                child: Text('· $x', style: CruType.caption.tint(c.amberText)),
              ),
        ],
      ),
    );
  }
}

/// One machine setting: chips for a choice, a number field with quick values
/// for everything else.
class _ParamField extends StatelessWidget {
  const _ParamField({
    required this.param,
    required this.value,
    required this.controller,
    required this.onChoose,
    required this.onPreset,
  });

  final ModalityParam param;
  final String? value;

  /// Null for a choice parameter, which has nothing to type into.
  final TextEditingController? controller;
  final ValueChanged<String?> onChoose;
  final ValueChanged<String> onPreset;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;

    if (param.isChoice) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(param.label, style: CruType.callout.tint(c.label)),
          if (param.help.isNotEmpty)
            Text(param.help, style: CruType.caption.tint(c.label3)),
          const SizedBox(height: CruSpace.s8),
          Wrap(
            spacing: CruSpace.s8,
            runSpacing: CruSpace.s8,
            children: [
              for (final option in param.presets)
                DentalChoiceChip(
                  label: option,
                  selected: value == option,
                  // Tapping the chosen setting again clears it, so a mis-tap
                  // can be undone without inventing a different setting.
                  onTap: () => onChoose(value == option ? null : option),
                ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CruTextField(
          label: param.unit.isEmpty
              ? param.label
              : '${param.label} (${param.unit})',
          controller: controller!,
          hint: param.presets.isEmpty ? '' : param.presets.first,
          help: param.help.isEmpty ? null : param.help,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          tabular: true,
        ),
        if (param.presets.isNotEmpty) ...[
          const SizedBox(height: CruSpace.s8),
          Wrap(
            spacing: CruSpace.s8,
            runSpacing: CruSpace.s8,
            children: [
              for (final p in param.presets)
                DentalChoiceChip(
                  label: param.unit.isEmpty ? p : '$p ${param.unit}',
                  selected: value == p,
                  tabular: true,
                  onTap: () => onPreset(p),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Treatment time, with the modality's usual times as shortcuts.
class _Minutes extends StatelessWidget {
  const _Minutes({
    required this.controller,
    required this.presets,
    required this.onPreset,
  });

  final TextEditingController controller;
  final List<String> presets;
  final ValueChanged<String> onPreset;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CruTextField(
          label: 'Time (minutes)',
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          tabular: true,
        ),
        const SizedBox(height: CruSpace.s8),
        Wrap(
          spacing: CruSpace.s8,
          runSpacing: CruSpace.s8,
          children: [
            for (final p in presets)
              DentalChoiceChip(
                label: '$p min',
                selected: controller.text.trim() == p,
                tabular: true,
                onTap: () => onPreset(p),
              ),
          ],
        ),
      ],
    );
  }
}
