import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/consent_dialog.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/specialties/oralmed/oralmed_history.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Supported sedation / anaesthesia planned modalities.
enum SedationModality {
  iv('IV sedation'),
  oral('Oral sedation'),
  inhalation('Inhalation (N2O)'),
  ga('General Anaesthesia (GA)');

  final String label;
  const SedationModality(this.label);
}

/// Model for the pre-operative anaesthesia assessment.
class PreopAssessment {
  final int asa;
  final double? weightKg;
  final double? heightCm;
  final int fastingSolidsHours;
  final int fastingClearHours;
  final int mallampati;
  final String airwayNotes;
  final String allergies;
  final String medications;
  final int? lastMeal;
  final bool escort;
  final String consentId;

  const PreopAssessment({
    this.asa = 1,
    this.weightKg,
    this.heightCm,
    this.fastingSolidsHours = 6,
    this.fastingClearHours = 2,
    this.mallampati = 1,
    this.airwayNotes = '',
    this.allergies = '',
    this.medications = '',
    this.lastMeal,
    this.escort = true,
    this.consentId = '',
  });

  double? get bmi {
    if (weightKg == null || heightCm == null || heightCm! <= 0) return null;
    final hMeters = heightCm! / 100.0;
    return weightKg! / (hMeters * hMeters);
  }

  factory PreopAssessment.fromJson(Map<String, dynamic> json) {
    return PreopAssessment(
      asa: (json['asa'] as num?)?.toInt() ?? 1,
      weightKg: (json['weightKg'] as num?)?.toDouble(),
      heightCm: (json['heightCm'] as num?)?.toDouble(),
      fastingSolidsHours: (json['fastingSolidsHours'] as num?)?.toInt() ?? 6,
      fastingClearHours: (json['fastingClearHours'] as num?)?.toInt() ?? 2,
      mallampati: (json['mallampati'] as num?)?.toInt() ?? 1,
      airwayNotes: json['airwayNotes'] as String? ?? '',
      allergies: json['allergies'] as String? ?? '',
      medications: json['medications'] as String? ?? '',
      lastMeal: (json['lastMeal'] as num?)?.toInt(),
      escort: json['escort'] as bool? ?? true,
      consentId: json['consentId'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'asa': asa,
        'weightKg': weightKg,
        'heightCm': heightCm,
        'fastingSolidsHours': fastingSolidsHours,
        'fastingClearHours': fastingClearHours,
        'mallampati': mallampati,
        'airwayNotes': airwayNotes,
        'allergies': allergies,
        'medications': medications,
        'lastMeal': lastMeal,
        'escort': escort,
        'consentId': consentId,
      };
}

/// Full record model for a sedation / anaesthesia case episode.
class SedationCase {
  final String id;
  final String patientId;
  final String procedure;
  final String planned;
  final PreopAssessment preop;
  final List<Map<String, dynamic>> vitals;
  final List<Map<String, dynamic>> drugs;
  final Map<String, dynamic>? recovery;
  final String status; // 'planned' | 'inProgress' | 'recovery' | 'discharged'
  final DateTime recordedAt;
  final DentalRecord record;

  const SedationCase({
    required this.id,
    required this.patientId,
    required this.procedure,
    required this.planned,
    required this.preop,
    required this.vitals,
    required this.drugs,
    this.recovery,
    required this.status,
    required this.recordedAt,
    required this.record,
  });

  factory SedationCase.fromRecord(DentalRecord r) {
    final d = r.data;
    return SedationCase(
      id: r.id,
      patientId: r.patientId,
      procedure: d['procedure'] as String? ?? 'Dental procedure',
      planned: d['planned'] as String? ?? 'IV sedation',
      preop: d['preop'] is Map<String, dynamic>
          ? PreopAssessment.fromJson(d['preop'] as Map<String, dynamic>)
          : (d['preop'] is Map
              ? PreopAssessment.fromJson(Map<String, dynamic>.from(d['preop'] as Map))
              : const PreopAssessment()),
      vitals: (d['vitals'] as List?)?.map((v) => Map<String, dynamic>.from(v as Map)).toList() ?? [],
      drugs: (d['drugs'] as List?)?.map((v) => Map<String, dynamic>.from(v as Map)).toList() ?? [],
      recovery: d['recovery'] is Map ? Map<String, dynamic>.from(d['recovery'] as Map) : null,
      status: d['status'] as String? ?? 'planned',
      recordedAt: r.recordedAt,
      record: r,
    );
  }
}

/// Pre-operative Anaesthesia Assessment Dialog (AN2).
class PreopDialog extends ConsumerStatefulWidget {
  const PreopDialog({
    super.key,
    required this.patient,
    this.initialCase,
    this.onStartCase,
  });

  final Patient patient;
  final SedationCase? initialCase;
  final void Function(SedationCase sedationCase)? onStartCase;

  @override
  ConsumerState<PreopDialog> createState() => _PreopDialogState();
}

class _PreopDialogState extends ConsumerState<PreopDialog> {
  final _procedure = TextEditingController();
  final _airwayNotes = TextEditingController();
  final _allergies = TextEditingController();
  final _medications = TextEditingController();
  final _weight = TextEditingController();
  final _height = TextEditingController();
  final _fastingSolids = TextEditingController(text: '6');
  final _fastingClear = TextEditingController(text: '2');

  SedationModality _modality = SedationModality.iv;
  int _asa = 1;
  int _mallampati = 1;
  bool _escort = true;
  String _consentId = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final c = widget.initialCase;
    if (c != null) {
      _procedure.text = c.procedure;
      _modality = SedationModality.values.firstWhere(
        (m) => m.label == c.planned,
        orElse: () => SedationModality.iv,
      );
      final p = c.preop;
      _asa = p.asa;
      _mallampati = p.mallampati;
      _escort = p.escort;
      _consentId = p.consentId;
      _airwayNotes.text = p.airwayNotes;
      _allergies.text = p.allergies;
      _medications.text = p.medications;
      if (p.weightKg != null) _weight.text = p.weightKg!.toStringAsFixed(1);
      if (p.heightCm != null) _height.text = p.heightCm!.toStringAsFixed(0);
      _fastingSolids.text = p.fastingSolidsHours.toString();
      _fastingClear.text = p.fastingClearHours.toString();
    } else {
      _procedure.text = 'Surgical extractions / Dental procedure';
      // Prefill patient known allergies if available
      final omRecords = ref.read(
        patientRecordsProvider((patientId: widget.patient.id, kind: RecKind.omHistory)),
      ).value;
      if (omRecords != null && omRecords.isNotEmpty) {
        final omAllergies = omAllergyText(omRecords.firstOrNull);
        if (omAllergies != null && omAllergies.isNotEmpty) {
          _allergies.text = omAllergies;
        }
      }
    }
  }

  @override
  void dispose() {
    _procedure.dispose();
    _airwayNotes.dispose();
    _allergies.dispose();
    _medications.dispose();
    _weight.dispose();
    _height.dispose();
    _fastingSolids.dispose();
    _fastingClear.dispose();
    super.dispose();
  }

  double? get _calculatedBmi {
    final w = double.tryParse(_weight.text.trim());
    final h = double.tryParse(_height.text.trim());
    if (w != null && h != null && h > 0) {
      final hm = h / 100.0;
      return w / (hm * hm);
    }
    return null;
  }

  Future<SedationCase?> _saveInternal({required String targetStatus}) async {
    final w = double.tryParse(_weight.text.trim());
    final h = double.tryParse(_height.text.trim());
    final fSolids = int.tryParse(_fastingSolids.text.trim()) ?? 6;
    final fClear = int.tryParse(_fastingClear.text.trim()) ?? 2;

    final preopData = PreopAssessment(
      asa: _asa,
      weightKg: w,
      heightCm: h,
      fastingSolidsHours: fSolids,
      fastingClearHours: fClear,
      mallampati: _mallampati,
      airwayNotes: _airwayNotes.text.trim(),
      allergies: _allergies.text.trim(),
      medications: _medications.text.trim(),
      escort: _escort,
      consentId: _consentId,
    );

    final now = DateTime.now();
    final c = widget.initialCase;

    if (c == null) {
      final record = DentalRecord.create(
        widget.patient.id,
        RecKind.sedationCase,
        {
          'procedure': _procedure.text.trim(),
          'planned': _modality.label,
          'preop': preopData.toJson(),
          'vitals': <Map<String, dynamic>>[],
          'drugs': <Map<String, dynamic>>[],
          'recovery': null,
          'status': targetStatus,
        },
        at: now,
      );
      await saveDentalRecord(ref, record);
      return SedationCase.fromRecord(record);
    } else {
      final updated = c.record.copyWith(
        data: {
          ...c.record.data,
          'procedure': _procedure.text.trim(),
          'planned': _modality.label,
          'preop': preopData.toJson(),
          'status': targetStatus,
        },
      );
      await saveDentalRecord(ref, updated);
      return SedationCase.fromRecord(updated);
    }
  }

  Future<void> _submitPlanned() async {
    setState(() => _busy = true);
    try {
      final sc = await _saveInternal(targetStatus: 'planned');
      if (mounted) {
        recToast(context, 'Pre-op assessment saved as planned');
        Navigator.of(context).pop(sc);
      }
    } catch (e) {
      if (mounted) recToast(context, 'Error saving pre-op: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startCase() async {
    setState(() => _busy = true);
    try {
      final sc = await _saveInternal(targetStatus: 'inProgress');
      if (mounted) {
        recToast(context, 'Case started');
        Navigator.of(context).pop(sc);
        if (sc != null && widget.onStartCase != null) {
          widget.onStartCase!(sc);
        }
      }
    } catch (e) {
      if (mounted) recToast(context, 'Error starting case: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final bmi = _calculatedBmi;

    final fSolids = int.tryParse(_fastingSolids.text.trim()) ?? 6;
    final fClear = int.tryParse(_fastingClear.text.trim()) ?? 2;
    final fastingInadequate = fSolids < 6 || fClear < 2;
    final needsEscort = (_modality == SedationModality.iv || _modality == SedationModality.ga) && !_escort;
    final isHighAsa = _asa >= 3;
    final hasAllergies = _allergies.text.trim().isNotEmpty;

    return CruFormDialog(
      title: 'Pre-operative Assessment',
      subtitle: '${widget.patient.fullName} (${widget.patient.age}y, ${widget.patient.gender.toUpperCase()})',
      width: 680,
      busy: _busy,
      submitLabel: 'Save assessment',
      onSubmit: _submitPlanned,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // RED ALLERGY ALERT BANNER (CRITICAL SAFETY)
          if (hasAllergies) ...[
            Container(
              padding: const EdgeInsets.all(CruSpace.s12),
              decoration: BoxDecoration(
                color: c.redTint,
                borderRadius: BorderRadius.circular(CruRadius.control),
                border: Border.all(color: c.redText),
              ),
              child: Row(
                children: [
                  CruIcon(CruIcons.warning, size: 20, color: c.redText),
                  const SizedBox(width: CruSpace.s10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ALLERGY ALERT',
                          style: CruType.caption.w600.tint(c.redText),
                        ),
                        Text(
                          _allergies.text.trim(),
                          style: CruType.callout.w600.tint(c.redText),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: CruSpace.s12),
          ],

          // AMBER WARNINGS
          if (fastingInadequate || needsEscort || isHighAsa) ...[
            Container(
              padding: const EdgeInsets.all(CruSpace.s12),
              decoration: BoxDecoration(
                color: c.amberTint,
                borderRadius: BorderRadius.circular(CruRadius.control),
                border: Border.all(color: c.amberText),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CruIcon(CruIcons.warning, size: 16, color: c.amberText),
                      const SizedBox(width: CruSpace.s8),
                      Text(
                        'PRE-OPERATIVE CLINICAL ALERTS',
                        style: CruType.caption.w600.tint(c.amberText),
                      ),
                    ],
                  ),
                  const SizedBox(height: CruSpace.s6),
                  if (fastingInadequate)
                    Text(
                      '• Inadequate fasting: Guidelines recommend min 6h for solids and 2h for clear fluids to prevent aspiration.',
                      style: CruType.caption.tint(c.amberText),
                    ),
                  if (needsEscort)
                    Text(
                      '• Escort required: IV sedation and GA require a dedicated responsible adult escort before discharge.',
                      style: CruType.caption.tint(c.amberText),
                    ),
                  if (isHighAsa)
                    Text(
                      '• ASA $_asa: Patient has severe systemic condition. Consider hospital setting with full anaesthetic coverage.',
                      style: CruType.caption.tint(c.amberText),
                    ),
                ],
              ),
            ),
            const SizedBox(height: CruSpace.s12),
          ],

          // Procedure & Planned Modality
          CruTextField(
            label: 'Planned Procedure',
            controller: _procedure,
          ),
          const SizedBox(height: CruSpace.s12),

          CruFieldFrame(
            label: 'Planned Anaesthesia / Sedation',
            child: Wrap(
              spacing: CruSpace.s8,
              children: [
                for (final m in SedationModality.values)
                  DentalChoiceChip(
                    label: m.label,
                    selected: _modality == m,
                    onTap: () => setState(() => _modality = m),
                  ),
              ],
            ),
          ),
          const SizedBox(height: CruSpace.s12),

          // ASA Physical Status chips
          CruFieldFrame(
            label: 'ASA Physical Status',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: CruSpace.s8,
                  runSpacing: CruSpace.s6,
                  children: [
                    for (var i = 1; i <= 5; i++)
                      DentalChoiceChip(
                        label: 'ASA $i: ${_asaMeaning(i)}',
                        selected: _asa == i,
                        onTap: () => setState(() => _asa = i),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: CruSpace.s12),

          // Anthropometrics (Weight, Height, BMI)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: CruTextField(
                  label: 'Weight (kg)',
                  controller: _weight,
                  hint: 'e.g. 65',
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: CruTextField(
                  label: 'Height (cm)',
                  controller: _height,
                  hint: 'e.g. 170',
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: CruFieldFrame(
                  label: 'Calculated BMI',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: CruSpace.s6),
                    child: Text(
                      bmi != null
                          ? '${bmi.toStringAsFixed(1)} kg/m² (${_bmiCategory(bmi)})'
                          : '—',
                      style: CruType.callout.w600.tabular.tint(c.label),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s12),

          // Fasting hours
          Row(
            children: [
              Expanded(
                child: CruTextField(
                  label: 'Fasting Solids (hours)',
                  controller: _fastingSolids,
                  hint: 'Min 6 hours',
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: CruTextField(
                  label: 'Fasting Clear Fluids (hours)',
                  controller: _fastingClear,
                  hint: 'Min 2 hours',
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s12),

          // Airway & Mallampati
          CruFieldFrame(
            label: 'Mallampati Airway Classification',
            child: Wrap(
              spacing: CruSpace.s8,
              runSpacing: CruSpace.s6,
              children: [
                for (var i = 1; i <= 4; i++)
                  DentalChoiceChip(
                    label: 'Class $i: ${_mallampatiMeaning(i)}',
                    selected: _mallampati == i,
                    onTap: () => setState(() => _mallampati = i),
                  ),
              ],
            ),
          ),
          const SizedBox(height: CruSpace.s8),

          CruTextField(
            label: 'Airway Notes (neck mobility, mouth opening, loose teeth)',
            controller: _airwayNotes,
            hint: 'Normal neck extension, 45mm incisal opening, no loose teeth',
          ),
          const SizedBox(height: CruSpace.s12),

          // Allergies (Red text styling when present)
          CruTextField(
            label: 'Known Drug Allergies (Red flag)',
            controller: _allergies,
            hint: 'e.g. Penicillin, Sulfa, Latex (leave blank if None known)',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: CruSpace.s12),

          // Current medications
          CruTextField(
            label: 'Current Medications',
            controller: _medications,
            hint: 'e.g. Metformin 500mg, Amlodipine 5mg',
          ),
          const SizedBox(height: CruSpace.s12),

          // Escort Present toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12, vertical: CruSpace.s8),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(CruRadius.control),
              border: Border.all(color: c.hairline),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Responsible Adult Escort Present', style: CruType.callout.w600.tint(c.label)),
                      Text(
                        'Adult must remain in clinic during procedure and escort patient home.',
                        style: CruType.caption.tint(c.label2),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _escort,
                  activeThumbColor: c.accent,
                  onChanged: (val) => setState(() => _escort = val),
                ),
              ],
            ),
          ),
          const SizedBox(height: CruSpace.s12),

          // Consent link
          CruFieldFrame(
            label: 'Surgical & Sedation Informed Consent',
            child: Row(
              children: [
                CruIcon(CruIcons.box, size: 16, color: _consentId.isNotEmpty ? c.accent : c.label3),
                const SizedBox(width: CruSpace.s8),
                Expanded(
                  child: Text(
                    _consentId.isNotEmpty ? 'Informed Consent Linked (#${_consentId.substring(0, 6)})' : 'No surgical consent attached',
                    style: CruType.caption.tint(_consentId.isNotEmpty ? c.label : c.label3),
                  ),
                ),
                CruCapsuleButton(
                  label: _consentId.isNotEmpty ? 'View / Change' : 'Take consent',
                  icon: CruIcons.pen,
                  onPressed: () => showConsentDialog(
                    context,
                    widget.patient,
                    type: ConsentType.surgical,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: CruSpace.s20),

          // Action row
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              CruButton(
                label: 'Save planned',
                kind: CruButtonKind.secondary,
                onPressed: _busy ? null : _submitPlanned,
              ),
              const SizedBox(width: CruSpace.s12),
              CruButton(
                label: 'Start case now',
                icon: CruIcons.arrowUpRight,
                kind: CruButtonKind.primary,
                onPressed: _busy ? null : _startCase,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _asaMeaning(int asa) => switch (asa) {
        1 => 'Normal healthy patient',
        2 => 'Mild systemic disease',
        3 => 'Severe systemic disease',
        4 => 'Constant threat to life',
        5 => 'Moribund patient',
        _ => '',
      };

  static String _mallampatiMeaning(int m) => switch (m) {
        1 => 'Pillars, uvula visible',
        2 => 'Uvula partially visible',
        3 => 'Soft palate only',
        4 => 'Hard palate only',
        _ => '',
      };

  static String _bmiCategory(double bmi) {
    if (bmi < 18.5) return 'Underweight';
    if (bmi < 25.0) return 'Normal weight';
    if (bmi < 30.0) return 'Overweight';
    return 'Obese';
  }
}
