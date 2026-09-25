import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/specialties/anaesthesia/preop_dialog.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Specification of a dental local anaesthetic formula and max dosage parameters.
class LocalAnaestheticSpec {
  final String name;
  final double concentrationPercent;
  final double cartridgeVolumeMl;
  final double maxMgPerKg;
  final double absoluteMaxMg;
  final bool hasAdrenaline;

  const LocalAnaestheticSpec({
    required this.name,
    required this.concentrationPercent,
    required this.cartridgeVolumeMl,
    required this.maxMgPerKg,
    required this.absoluteMaxMg,
    this.hasAdrenaline = false,
  });

  /// Formula: concentration % × 10 × volume in ml = mg per cartridge.
  double get mgPerCartridge => concentrationPercent * 10.0 * cartridgeVolumeMl;

  /// Maximum safe dose in mg for the given patient weight in kg.
  double maxDoseMg(double weightKg) =>
      math.min(weightKg * maxMgPerKg, absoluteMaxMg);

  /// Maximum cartridge count for the given patient weight in kg.
  double maxCartridges(double weightKg) =>
      maxDoseMg(weightKg) / mgPerCartridge;
}

/// Constant formulary list of local anaesthetics (AN4 spec table).
/// Clinicians must check these values against their local national/institutional formulary.
const localAnaestheticsList = <LocalAnaestheticSpec>[
  LocalAnaestheticSpec(
    name: 'Lidocaine 2% + adrenaline',
    concentrationPercent: 2.0,
    cartridgeVolumeMl: 1.8,
    maxMgPerKg: 4.4,
    absoluteMaxMg: 300.0,
    hasAdrenaline: true,
  ),
  LocalAnaestheticSpec(
    name: 'Articaine 4% + adrenaline',
    concentrationPercent: 4.0,
    cartridgeVolumeMl: 1.7,
    maxMgPerKg: 7.0,
    absoluteMaxMg: 500.0,
    hasAdrenaline: true,
  ),
  LocalAnaestheticSpec(
    name: 'Mepivacaine 3% plain',
    concentrationPercent: 3.0,
    cartridgeVolumeMl: 1.8,
    maxMgPerKg: 4.4,
    absoluteMaxMg: 300.0,
    hasAdrenaline: false,
  ),
  LocalAnaestheticSpec(
    name: 'Prilocaine 4%',
    concentrationPercent: 4.0,
    cartridgeVolumeMl: 1.8,
    maxMgPerKg: 8.0,
    absoluteMaxMg: 600.0,
    hasAdrenaline: false,
  ),
  LocalAnaestheticSpec(
    name: 'Bupivacaine 0.5% + adrenaline',
    concentrationPercent: 0.5,
    cartridgeVolumeMl: 1.8,
    maxMgPerKg: 1.3,
    absoluteMaxMg: 90.0,
    hasAdrenaline: true,
  ),
];

/// One administered drug entry.
class DrugLogEntry {
  final int at;
  final String drug;
  final double dose;
  final String unit;
  final String route;
  final String note;

  const DrugLogEntry({
    required this.at,
    required this.drug,
    required this.dose,
    required this.unit,
    required this.route,
    this.note = '',
  });

  factory DrugLogEntry.fromJson(Map<String, dynamic> json) {
    return DrugLogEntry(
      at: (json['at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      drug: json['drug'] as String? ?? '',
      dose: (json['dose'] as num?)?.toDouble() ?? 0.0,
      unit: json['unit'] as String? ?? 'mg',
      route: json['route'] as String? ?? 'IV',
      note: json['note'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'at': at,
        'drug': drug,
        'dose': dose,
        'unit': unit,
        'route': route,
        'note': note,
      };
}

/// Dialog for logging drugs, calculating local anaesthetic limits, and reviewing running totals.
class DrugLogDialog extends ConsumerStatefulWidget {
  const DrugLogDialog({
    super.key,
    required this.patient,
    this.sedationCase,
    this.initialWeightKg,
  });

  final Patient patient;
  final SedationCase? sedationCase;
  final double? initialWeightKg;

  @override
  ConsumerState<DrugLogDialog> createState() => _DrugLogDialogState();
}

class _DrugLogDialogState extends ConsumerState<DrugLogDialog> {
  late List<DrugLogEntry> _drugs;
  late double _weightKg;

  // New drug input controllers
  final _drugCtrl = TextEditingController();
  final _doseCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String _unit = 'mg';
  String _route = 'IV';

  static const _commonDrugs = [
    'Midazolam',
    'Fentanyl',
    'Propofol',
    'Ketamine',
    'Lidocaine 2% + adrenaline',
    'Articaine 4% + adrenaline',
    'Mepivacaine 3% plain',
    'Bupivacaine 0.5% + adrenaline',
    'Atropine',
    'Glycopyrrolate',
    'Flumazenil',
    'Naloxone',
    'Ondansetron',
    'Dexamethasone',
  ];

  static const _units = ['mg', 'mcg', 'ml', 'cartridges'];
  static const _routes = ['IV', 'Infiltration', 'Nerve block', 'IM', 'Oral', 'Inhalation'];

  @override
  void initState() {
    super.initState();
    _weightKg = widget.sedationCase?.preop.weightKg ??
        widget.initialWeightKg ??
        60.0;

    _drugs = widget.sedationCase != null
        ? widget.sedationCase!.drugs.map(DrugLogEntry.fromJson).toList()
        : [];
  }

  @override
  void dispose() {
    _drugCtrl.dispose();
    _doseCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _addDrug() {
    final name = _drugCtrl.text.trim();
    final dose = double.tryParse(_doseCtrl.text.trim());
    if (name.isEmpty || dose == null || dose <= 0) {
      recToast(context, 'Please enter a valid drug name and dose');
      return;
    }

    final entry = DrugLogEntry(
      at: DateTime.now().millisecondsSinceEpoch,
      drug: name,
      dose: dose,
      unit: _unit,
      route: _route,
      note: _noteCtrl.text.trim(),
    );

    setState(() {
      _drugs.add(entry);
      _drugCtrl.clear();
      _doseCtrl.clear();
      _noteCtrl.clear();
    });

    _persist();
  }

  void _removeDrug(int index) {
    setState(() => _drugs.removeAt(index));
    _persist();
  }

  Future<void> _persist() async {
    final sc = widget.sedationCase;
    if (sc != null) {
      final updated = sc.record.copyWith(
        data: {
          ...sc.record.data,
          'drugs': _drugs.map((d) => d.toJson()).toList(),
        },
      );
      await saveDentalRecord(ref, updated);
    }
  }

  /// Running total administered per drug name & unit.
  Map<String, double> get _drugTotals {
    final totals = <String, double>{};
    for (final d in _drugs) {
      final key = '${d.drug} (${d.unit})';
      totals[key] = (totals[key] ?? 0.0) + d.dose;
    }
    return totals;
  }

  /// Calculates cartridges given so far for a specific local anaesthetic.
  double _cartridgesGiven(LocalAnaestheticSpec spec) {
    double total = 0.0;
    for (final d in _drugs) {
      final match = d.drug.toLowerCase().contains(spec.name.split(' ').first.toLowerCase());
      if (match) {
        if (d.unit == 'cartridges') {
          total += d.dose;
        } else if (d.unit == 'mg') {
          total += d.dose / spec.mgPerCartridge;
        } else if (d.unit == 'ml') {
          total += d.dose / spec.cartridgeVolumeMl;
        }
      }
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;

    return DentalPanelDialog(
      title: 'Drug & Anaesthetic Log',
      subtitle: '${widget.patient.fullName} · Patient weight: ${_weightKg.toStringAsFixed(1)} kg',
      width: 920,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Local Anaesthetic Maximum-Dose Calculator
          Container(
            padding: const EdgeInsets.all(CruSpace.s16),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(CruRadius.control),
              border: Border.all(color: c.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        CruIcon(CruIcons.box, size: 18, color: c.accent),
                        const SizedBox(width: CruSpace.s8),
                        Text(
                          'Local Anaesthetic Maximum-Dose Calculator',
                          style: CruType.callout.w600.tint(c.label),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Weight: ', style: CruType.caption.tint(c.label2)),
                        SizedBox(
                          width: 60,
                          child: TextFormField(
                            initialValue: _weightKg.toStringAsFixed(0),
                            keyboardType: TextInputType.number,
                            style: CruType.caption.w600.tabular.tint(c.label),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (val) {
                              final parsed = double.tryParse(val);
                              if (parsed != null && parsed > 0) {
                                setState(() => _weightKg = parsed);
                              }
                            },
                          ),
                        ),
                        Text(' kg', style: CruType.caption.tint(c.label2)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: CruSpace.s12),

                // Table of LA doses
                Table(
                  columnWidths: const {
                    0: FlexColumnWidth(2.2),
                    1: FlexColumnWidth(1.2),
                    2: FlexColumnWidth(1.2),
                    3: FlexColumnWidth(1.2),
                    4: FlexColumnWidth(1.4),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    TableRow(
                      decoration: BoxDecoration(color: c.inset),
                      children: [
                        _th('Anaesthetic', c),
                        _th('Max Dose', c),
                        _th('Max Cartridges', c),
                        _th('Given So Far', c),
                        _th('Cartridges Left', c),
                      ],
                    ),
                    for (final spec in localAnaestheticsList) ...[
                      _laTableRow(spec, c),
                    ],
                  ],
                ),
                const SizedBox(height: CruSpace.s10),

                // Formulary disclaimer note
                Row(
                  children: [
                    CruIcon(CruIcons.help, size: 14, color: c.label3),
                    const SizedBox(width: CruSpace.s6),
                    Expanded(
                      child: Text(
                        'Check against your local formulary. Dose limits must be reduced in elderly, medically compromised, or pediatric patients.',
                        style: CruType.micro.tint(c.label3),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: CruSpace.s16),

          // Drug entry section
          Container(
            padding: const EdgeInsets.all(CruSpace.s16),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(CruRadius.control),
              border: Border.all(color: c.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Administer Medication', style: CruType.callout.w600.tint(c.label)),
                const SizedBox(height: CruSpace.s8),

                // Quick drug chips
                Wrap(
                  spacing: CruSpace.s6,
                  runSpacing: CruSpace.s6,
                  children: [
                    for (final drug in _commonDrugs)
                      DentalChoiceChip(
                        label: drug,
                        selected: _drugCtrl.text == drug,
                        onTap: () {
                          setState(() {
                            _drugCtrl.text = drug;
                            if (drug.contains('adrenaline') || drug.contains('plain')) {
                              _unit = 'cartridges';
                              _route = 'Infiltration';
                            } else if (drug == 'Fentanyl') {
                              _unit = 'mcg';
                              _route = 'IV';
                            } else {
                              _unit = 'mg';
                              _route = 'IV';
                            }
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: CruSpace.s12),

                // Entry row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      flex: 3,
                      child: CruTextField(
                        label: 'Drug name',
                        controller: _drugCtrl,
                        hint: 'e.g. Midazolam',
                      ),
                    ),
                    const SizedBox(width: CruSpace.s8),
                    Expanded(
                      flex: 2,
                      child: CruTextField(
                        label: 'Dose',
                        controller: _doseCtrl,
                        hint: 'e.g. 2.0',
                      ),
                    ),
                    const SizedBox(width: CruSpace.s8),
                    Expanded(
                      flex: 2,
                      child: CruFieldFrame(
                        label: 'Unit',
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: _unit,
                            items: [
                              for (final u in _units)
                                DropdownMenuItem(value: u, child: Text(u, style: CruType.body.tint(c.label))),
                            ],
                            onChanged: (u) => setState(() => _unit = u ?? 'mg'),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: CruSpace.s8),
                    Expanded(
                      flex: 2,
                      child: CruFieldFrame(
                        label: 'Route',
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: _route,
                            items: [
                              for (final r in _routes)
                                DropdownMenuItem(value: r, child: Text(r, style: CruType.body.tint(c.label))),
                            ],
                            onChanged: (r) => setState(() => _route = r ?? 'IV'),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: CruSpace.s8),
                    CruButton(
                      label: 'Record',
                      icon: CruIcons.plus,
                      kind: CruButtonKind.primary,
                      onPressed: _addDrug,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: CruSpace.s16),

          // Running Totals & Administered Log
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Running totals column
              Expanded(
                flex: 4,
                child: Container(
                  padding: const EdgeInsets.all(CruSpace.s16),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(CruRadius.control),
                    border: Border.all(color: c.hairline),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Running Totals', style: CruType.callout.w600.tint(c.label)),
                      const SizedBox(height: CruSpace.s10),
                      if (_drugTotals.isEmpty)
                        Text('No medications logged yet.', style: CruType.caption.tint(c.label3))
                      else
                        for (final entry in _drugTotals.entries) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: CruSpace.s4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    entry.key,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: CruType.caption.tint(c.label),
                                  ),
                                ),
                                Text(
                                  entry.value.toStringAsFixed(1),
                                  style: CruType.caption.w600.tabular.tint(c.accent),
                                ),
                              ],
                            ),
                          ),
                          const CruSeparator(),
                        ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: CruSpace.s16),

              // Log list column
              Expanded(
                flex: 6,
                child: Container(
                  padding: const EdgeInsets.all(CruSpace.s16),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(CruRadius.control),
                    border: Border.all(color: c.hairline),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Administration Log (${_drugs.length})', style: CruType.callout.w600.tint(c.label)),
                          Text(
                            'Latest first',
                            style: CruType.micro.tint(c.label3),
                          ),
                        ],
                      ),
                      const SizedBox(height: CruSpace.s10),
                      if (_drugs.isEmpty)
                        Text('No administration records.', style: CruType.caption.tint(c.label3))
                      else
                        for (var i = _drugs.length - 1; i >= 0; i--) ...[
                          _drugRow(_drugs[i], i, c),
                          if (i > 0) const CruSeparator(),
                        ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  TableRow _laTableRow(LocalAnaestheticSpec spec, CruColors c) {
    final maxMg = spec.maxDoseMg(_weightKg);
    final maxCart = spec.maxCartridges(_weightKg);
    final givenCart = _cartridgesGiven(spec);
    final leftCart = math.max(0.0, maxCart - givenCart);
    final pctUsed = maxCart > 0 ? (givenCart / maxCart) * 100 : 0.0;

    final isOver100 = pctUsed >= 100.0;
    final isOver80 = pctUsed >= 80.0 && !isOver100;

    final Color badgeBg;
    final Color badgeFg;
    if (isOver100) {
      badgeBg = c.redTint;
      badgeFg = c.redText;
    } else if (isOver80) {
      badgeBg = c.amberTint;
      badgeFg = c.amberText;
    } else {
      badgeBg = c.inset;
      badgeFg = c.label2;
    }

    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s8, vertical: CruSpace.s6),
          child: Text(spec.name, style: CruType.caption.w600.tint(c.label)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s8, vertical: CruSpace.s6),
          child: Text('${maxMg.toStringAsFixed(0)} mg', style: CruType.caption.tabular.tint(c.label)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s8, vertical: CruSpace.s6),
          child: Text('${maxCart.toStringAsFixed(1)} carts', style: CruType.caption.tabular.tint(c.label)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s8, vertical: CruSpace.s6),
          child: Text('${givenCart.toStringAsFixed(1)} carts', style: CruType.caption.tabular.tint(c.label)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s8, vertical: CruSpace.s6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${leftCart.toStringAsFixed(1)} carts', style: CruType.caption.w600.tabular.tint(c.label)),
              const SizedBox(width: CruSpace.s6),
              if (givenCart > 0)
                CruPill(
                  text: '${pctUsed.toStringAsFixed(0)}%',
                  background: badgeBg,
                  foreground: badgeFg,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _th(String text, CruColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s8, vertical: CruSpace.s8),
      child: Text(text, style: CruType.micro.w600.tint(c.label2)),
    );
  }

  Widget _drugRow(DrugLogEntry entry, int index, CruColors c) {
    final timeStr = DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(entry.at));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CruSpace.s6),
      child: Row(
        children: [
          Text(timeStr, style: CruType.caption.w600.tabular.tint(c.label2)),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${entry.drug} — ${entry.dose} ${entry.unit} (${entry.route})',
                    style: CruType.caption.w600.tint(c.label)),
                if (entry.note.isNotEmpty)
                  Text(entry.note, style: CruType.micro.tint(c.label3)),
              ],
            ),
          ),
          CruIconButton(
            icon: CruIcons.close,
            size: CruSize.squareButton,
            semanticLabel: 'Delete entry',
            onPressed: () => _removeDrug(index),
          ),
        ],
      ),
    );
  }
}
