import 'package:flutter/widgets.dart';

import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/scribe/data/models/physio_findings.dart';
import 'package:doctor_management_app/features/scribe/services/scribe_live_extractor.dart';

/// Editable state for one medicine row. Owns its controllers so typing
/// never loses the cursor, and carries a stable [id] for widget keys so
/// removing a row doesn't shift text into its neighbour.
class ScribeMedicineRow {
  ScribeMedicineRow(this.id, NotedMedicine medicine)
    : name = TextEditingController(text: medicine.name),
      dosage = TextEditingController(text: medicine.dosage),
      instructions = TextEditingController(text: medicine.instructions);

  final int id;
  final TextEditingController name;
  final TextEditingController dosage;
  final TextEditingController instructions;

  NotedMedicine get value => NotedMedicine(
    name: name.text.trim(),
    dosage: dosage.text.trim(),
    instructions: instructions.text.trim(),
  );

  void dispose() {
    name.dispose();
    dosage.dispose();
    instructions.dispose();
  }
}

/// Editable state for one row of a physio table (ROM, MMT, HEP...), one
/// controller per column of its [PhysioTableSpec].
class ScribeTableRow {
  ScribeTableRow(this.id, PhysioTableSpec spec, Map<String, String> values)
    : cells = {
        for (final c in spec.columns)
          c.key: TextEditingController(text: values[c.key] ?? ''),
      };

  final int id;
  final Map<String, TextEditingController> cells;

  Map<String, String> get value => {
    for (final e in cells.entries) e.key: e.value.text.trim(),
  };

  void dispose() {
    for (final c in cells.values) {
      c.dispose();
    }
  }
}

/// Holds the doctor's edits to an AI draft. Shared by the mobile review
/// screen and the desktop review phase so both edit notes identically.
class ScribeDraftFormController extends ChangeNotifier {
  ScribeDraftFormController(this.original)
    : chiefComplaint = TextEditingController(text: original.chiefComplaint),
      advice = TextEditingController(text: original.advice),
      bp = TextEditingController(text: original.vitals['bp'] ?? ''),
      temp = TextEditingController(text: original.vitals['temp'] ?? ''),
      pulse = TextEditingController(text: original.vitals['pulse'] ?? ''),
      symptoms = List<String>.of(original.symptoms),
      diagnoses = List<String>.of(original.diagnosisSuggestions),
      _followUpDate = original.followUpDate {
    for (final m in original.medicines) {
      medicines.add(ScribeMedicineRow(_nextRowId++, m));
    }
    final physio = original.physio;
    for (final spec in PhysioFindings.textSpecs) {
      physioText[spec.key] = TextEditingController(
        text: physio.textOf(spec.key),
      );
    }
    for (final spec in PhysioFindings.listSpecs) {
      physioLists[spec.key] = List<String>.of(physio.listOf(spec.key));
      physioListInputs[spec.key] = TextEditingController();
    }
    for (final spec in PhysioFindings.tableSpecs) {
      physioTables[spec.key] = [
        for (final r in physio.tableOf(spec.key))
          ScribeTableRow(_nextRowId++, spec, r),
      ];
    }
    for (final c in _textControllers) {
      c.addListener(notifyListeners);
    }
    for (final row in medicines) {
      _listenToRow(row);
    }
    for (final spec in PhysioFindings.tableSpecs) {
      for (final row in physioTables[spec.key]!) {
        _listenToTableRow(spec, row);
      }
    }
  }

  final ConsultationNote original;

  final TextEditingController chiefComplaint;
  final TextEditingController advice;
  final TextEditingController bp;
  final TextEditingController temp;
  final TextEditingController pulse;

  /// Inputs for the "add symptom / diagnosis" fields.
  final TextEditingController symptomInput = TextEditingController();
  final TextEditingController diagnosisInput = TextEditingController();

  final List<String> symptoms;
  final List<String> diagnoses;
  final List<ScribeMedicineRow> medicines = [];

  /// Physiotherapy fields, keyed by the spec keys in [PhysioFindings].
  final Map<String, TextEditingController> physioText = {};
  final Map<String, List<String>> physioLists = {};
  final Map<String, TextEditingController> physioListInputs = {};
  final Map<String, List<ScribeTableRow>> physioTables = {};

  int _nextRowId = 0;

  final Set<SoapSection> _expandedSections = {};

  /// Whether the form shows every field in [section], including empty ones.
  /// A manual note starts fully expanded; an AI draft shows only what the
  /// AI filled so the physio isn't scrolling past twenty blank boxes.
  bool isSectionExpanded(SoapSection section) =>
      originalWasEmpty || _expandedSections.contains(section);

  void toggleSection(SoapSection section) {
    if (!_expandedSections.remove(section)) _expandedSections.add(section);
    notifyListeners();
  }

  DateTime? _followUpDate;
  DateTime? get followUpDate => _followUpDate;

  final Map<String, int> _revealKeys = {};
  final Set<String> _pendingFields = {};

  int revealKeyFor(String fieldKey) => _revealKeys[fieldKey] ?? 0;
  bool isPending(String fieldKey) => _pendingFields.contains(fieldKey);

  void setFieldPending(String fieldKey, bool pending) {
    if (pending) {
      if (_pendingFields.add(fieldKey)) notifyListeners();
    } else {
      if (_pendingFields.remove(fieldKey)) notifyListeners();
    }
  }

  void updateChiefComplaint(String text) {
    final clean = text.trim();
    if (clean.isEmpty || chiefComplaint.text.trim() == clean) return;
    chiefComplaint.text = clean;
    _revealKeys['chiefComplaint'] = (_revealKeys['chiefComplaint'] ?? 0) + 1;
    _pendingFields.remove('chiefComplaint');
    notifyListeners();
  }

  void mergeSymptoms(List<String> newSymptoms) {
    var changed = false;
    for (final s in newSymptoms) {
      final clean = s.trim();
      if (clean.isEmpty) continue;
      if (!symptoms.any((e) => e.toLowerCase() == clean.toLowerCase())) {
        symptoms.add(clean);
        changed = true;
      }
    }
    if (changed) {
      _revealKeys['symptoms'] = (_revealKeys['symptoms'] ?? 0) + 1;
      _pendingFields.remove('symptoms');
      notifyListeners();
    }
  }

  void mergeDiagnoses(List<String> newDiagnoses) {
    var changed = false;
    for (final d in newDiagnoses) {
      final clean = d.trim();
      if (clean.isEmpty) continue;
      if (!diagnoses.any((e) => e.toLowerCase() == clean.toLowerCase())) {
        diagnoses.add(clean);
        changed = true;
      }
    }
    if (changed) {
      _revealKeys['diagnoses'] = (_revealKeys['diagnoses'] ?? 0) + 1;
      _pendingFields.remove('diagnoses');
      notifyListeners();
    }
  }

  void mergeMedicines(List<NotedMedicine> newMedicines) {
    var changed = false;
    for (final med in newMedicines) {
      final name = med.name.trim();
      if (name.isEmpty) continue;
      final existing = medicines
          .where((r) => r.name.text.trim().toLowerCase() == name.toLowerCase())
          .firstOrNull;
      if (existing == null) {
        final row = ScribeMedicineRow(_nextRowId++, med);
        medicines.add(row);
        _listenToRow(row);
        changed = true;
      } else {
        if (med.dosage.isNotEmpty && existing.dosage.text.trim() != med.dosage.trim()) {
          existing.dosage.text = med.dosage.trim();
          changed = true;
        }
        if (med.instructions.isNotEmpty &&
            existing.instructions.text.trim() != med.instructions.trim()) {
          existing.instructions.text = med.instructions.trim();
          changed = true;
        }
      }
    }
    if (changed) {
      _revealKeys['medicines'] = (_revealKeys['medicines'] ?? 0) + 1;
      _pendingFields.remove('medicines');
      notifyListeners();
    }
  }

  void updateAdvice(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return;
    final current = advice.text.trim();
    if (!current.toLowerCase().contains(clean.toLowerCase())) {
      advice.text = current.isEmpty ? clean : '$current\n• $clean';
      _revealKeys['advice'] = (_revealKeys['advice'] ?? 0) + 1;
      _pendingFields.remove('advice');
      notifyListeners();
    }
  }

  void updateVitals({String? newBp, String? newTemp, String? newPulse}) {
    var changed = false;
    if (newBp != null && newBp.trim().isNotEmpty && bp.text.trim() != newBp.trim()) {
      bp.text = newBp.trim();
      _revealKeys['bp'] = (_revealKeys['bp'] ?? 0) + 1;
      _pendingFields.remove('bp');
      changed = true;
    }
    if (newTemp != null && newTemp.trim().isNotEmpty && temp.text.trim() != newTemp.trim()) {
      temp.text = newTemp.trim();
      _revealKeys['temp'] = (_revealKeys['temp'] ?? 0) + 1;
      _pendingFields.remove('temp');
      changed = true;
    }
    if (newPulse != null && newPulse.trim().isNotEmpty && pulse.text.trim() != newPulse.trim()) {
      pulse.text = newPulse.trim();
      _revealKeys['pulse'] = (_revealKeys['pulse'] ?? 0) + 1;
      _pendingFields.remove('pulse');
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void updatePain({String? now, String? worst, String? location, String? nature}) {
    var changed = false;
    if (now != null && now.isNotEmpty && physioText['painNow']?.text.trim() != now.trim()) {
      physioText['painNow']?.text = now.trim();
      _revealKeys['painNow'] = (_revealKeys['painNow'] ?? 0) + 1;
      _pendingFields.remove('painNow');
      changed = true;
    }
    if (worst != null && worst.isNotEmpty && physioText['painWorst']?.text.trim() != worst.trim()) {
      physioText['painWorst']?.text = worst.trim();
      _revealKeys['painWorst'] = (_revealKeys['painWorst'] ?? 0) + 1;
      _pendingFields.remove('painWorst');
      changed = true;
    }
    if (nature != null && nature.isNotEmpty && physioText['painNature']?.text.trim() != nature.trim()) {
      physioText['painNature']?.text = nature.trim();
      _revealKeys['painNature'] = (_revealKeys['painNature'] ?? 0) + 1;
      _pendingFields.remove('painNature');
      changed = true;
    }
    if (location != null && location.isNotEmpty) {
      final locs = physioLists['painLocation'];
      if (locs != null && !locs.any((l) => l.toLowerCase() == location.trim().toLowerCase())) {
        locs.add(location.trim());
        _revealKeys['painLocation'] = (_revealKeys['painLocation'] ?? 0) + 1;
        _pendingFields.remove('painLocation');
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  void mergeLiveExtraction(ScribeLiveExtraction ext) {
    for (final field in ext.cuedFields) {
      _pendingFields.add(field);
    }
    if (ext.chiefComplaint != null) {
      updateChiefComplaint(ext.chiefComplaint!);
    }
    if (ext.symptoms.isNotEmpty) {
      mergeSymptoms(ext.symptoms);
    }
    if (ext.diagnoses.isNotEmpty) {
      mergeDiagnoses(ext.diagnoses);
    }
    if (ext.medicines.isNotEmpty) {
      mergeMedicines(ext.medicines);
    }
    if (ext.advice != null) {
      updateAdvice(ext.advice!);
    }
    if (ext.bp != null || ext.temp != null || ext.pulse != null) {
      updateVitals(newBp: ext.bp, newTemp: ext.temp, newPulse: ext.pulse);
    }
    if (ext.painNow != null ||
        ext.painWorst != null ||
        ext.painLocation != null ||
        ext.painNature != null) {
      updatePain(
        now: ext.painNow,
        worst: ext.painWorst,
        location: ext.painLocation,
        nature: ext.painNature,
      );
    }
    if (ext.followUpDate != null) {
      setFollowUpDate(ext.followUpDate);
    }
    if (ext.aggravating.isNotEmpty) {
      final list = physioLists['aggravating'];
      if (list != null) {
        for (final item in ext.aggravating) {
          if (!list.any((x) => x.toLowerCase() == item.toLowerCase())) {
            list.add(item);
            _revealKeys['aggravating'] = (_revealKeys['aggravating'] ?? 0) + 1;
            _pendingFields.remove('aggravating');
          }
        }
      }
    }
    if (ext.easing.isNotEmpty) {
      final list = physioLists['easing'];
      if (list != null) {
        for (final item in ext.easing) {
          if (!list.any((x) => x.toLowerCase() == item.toLowerCase())) {
            list.add(item);
            _revealKeys['easing'] = (_revealKeys['easing'] ?? 0) + 1;
            _pendingFields.remove('easing');
          }
        }
      }
    }
    if (ext.functionalLimits.isNotEmpty) {
      final list = physioLists['functionalLimits'];
      if (list != null) {
        for (final item in ext.functionalLimits) {
          if (!list.any((x) => x.toLowerCase() == item.toLowerCase())) {
            list.add(item);
            _revealKeys['functionalLimits'] =
                (_revealKeys['functionalLimits'] ?? 0) + 1;
            _pendingFields.remove('functionalLimits');
          }
        }
      }
    }
    if (ext.onset != null && ext.onset!.isNotEmpty) {
      final c = physioText['onset'];
      if (c != null && c.text.trim().isEmpty) {
        c.text = ext.onset!;
        _revealKeys['onset'] = (_revealKeys['onset'] ?? 0) + 1;
        _pendingFields.remove('onset');
      }
    }
    if (ext.history != null && ext.history!.isNotEmpty) {
      final c = physioText['history'];
      if (c != null && c.text.trim().isEmpty) {
        c.text = ext.history!;
        _revealKeys['history'] = (_revealKeys['history'] ?? 0) + 1;
        _pendingFields.remove('history');
      }
    }
    if (ext.patientGoals != null && ext.patientGoals!.isNotEmpty) {
      final c = physioText['patientGoals'];
      if (c != null && c.text.trim().isEmpty) {
        c.text = ext.patientGoals!;
        _revealKeys['patientGoals'] = (_revealKeys['patientGoals'] ?? 0) + 1;
        _pendingFields.remove('patientGoals');
      }
    }
    notifyListeners();
  }

  bool _reviewed = false;

  /// The doctor's explicit "I've checked this" acknowledgement.
  bool get reviewed => _reviewed;

  List<TextEditingController> get _textControllers => [
    chiefComplaint,
    advice,
    bp,
    temp,
    pulse,
    ...physioText.values,
  ];

  /// True when the AI returned nothing usable (or this is a manual note
  /// that hasn't been started).
  bool get originalWasEmpty => _isEmptyNote(original);

  /// True when there is nothing worth saving yet.
  bool get isEmpty => _isEmptyNote(toNote());

  bool get canConfirm => _reviewed && !isEmpty;

  void setReviewed(bool value) {
    _reviewed = value;
    notifyListeners();
  }

  void addSymptom([String? value]) =>
      _addTo(symptoms, value ?? symptomInput.text, symptomInput);

  void removeSymptom(int index) {
    symptoms.removeAt(index);
    notifyListeners();
  }

  void addDiagnosis([String? value]) =>
      _addTo(diagnoses, value ?? diagnosisInput.text, diagnosisInput);

  void removeDiagnosis(int index) {
    diagnoses.removeAt(index);
    notifyListeners();
  }

  ScribeMedicineRow addMedicine() {
    final row = ScribeMedicineRow(_nextRowId++, const NotedMedicine(name: ''));
    medicines.add(row);
    _listenToRow(row);
    notifyListeners();
    return row;
  }

  void removeMedicine(ScribeMedicineRow row) {
    medicines.remove(row);
    // Defer disposal until the row's TextFields have been unmounted.
    WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose());
    notifyListeners();
  }

  void addPhysioListItem(String key, [String? value]) {
    final input = physioListInputs[key]!;
    _addTo(physioLists[key]!, value ?? input.text, input);
  }

  void removePhysioListItem(String key, int index) {
    physioLists[key]!.removeAt(index);
    notifyListeners();
  }

  ScribeTableRow addTableRow(PhysioTableSpec spec) {
    final row = ScribeTableRow(_nextRowId++, spec, const {});
    physioTables[spec.key]!.add(row);
    _listenToTableRow(spec, row);
    notifyListeners();
    return row;
  }

  void removeTableRow(String key, ScribeTableRow row) {
    physioTables[key]!.remove(row);
    WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose());
    notifyListeners();
  }

  void setFollowUpDate(DateTime? date) {
    _followUpDate = date;
    notifyListeners();
  }

  /// The draft with the doctor's edits applied (blank entries dropped).
  ConsultationNote toNote() {
    String? vital(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    return original.copyWith(
      chiefComplaint: chiefComplaint.text.trim(),
      symptoms: symptoms.where((s) => s.trim().isNotEmpty).toList(),
      diagnosisSuggestions: diagnoses
          .where((d) => d.trim().isNotEmpty)
          .toList(),
      medicines: medicines
          .map((r) => r.value)
          .where((m) => m.name.isNotEmpty)
          .toList(),
      advice: advice.text.trim(),
      followUpDate: _followUpDate,
      clearFollowUpDate: _followUpDate == null,
      vitals: {'bp': vital(bp), 'temp': vital(temp), 'pulse': vital(pulse)},
      physio: _physioValue(),
      updatedAt: DateTime.now(),
    );
  }

  PhysioFindings _physioValue() {
    return PhysioFindings.fromJson({
      for (final e in physioText.entries) e.key: e.value.text,
      for (final e in physioLists.entries) e.key: e.value,
      for (final e in physioTables.entries)
        e.key: e.value.map((r) => r.value).toList(),
    });
  }

  void _addTo(List<String> list, String raw, TextEditingController input) {
    final value = raw.trim();
    input.clear();
    if (value.isEmpty) return;
    final exists = list.any((e) => e.toLowerCase() == value.toLowerCase());
    if (!exists) list.add(value);
    notifyListeners();
  }

  void _listenToRow(ScribeMedicineRow row) {
    row.name.addListener(notifyListeners);
  }

  /// Only the identity column affects emptiness, so only it rebuilds.
  void _listenToTableRow(PhysioTableSpec spec, ScribeTableRow row) {
    row.cells[spec.columns.first.key]!.addListener(notifyListeners);
  }

  static bool _isEmptyNote(ConsultationNote n) =>
      n.chiefComplaint.trim().isEmpty &&
      n.symptoms.isEmpty &&
      n.diagnosisSuggestions.isEmpty &&
      n.medicines.isEmpty &&
      n.advice.trim().isEmpty &&
      n.followUpDate == null &&
      n.vitals.values.every((v) => v == null || v.trim().isEmpty) &&
      n.physio.isEmpty;

  bool _isDisposed = false;
  bool get isDisposed => _isDisposed;

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    for (final c in [
      ..._textControllers,
      symptomInput,
      diagnosisInput,
      ...physioListInputs.values,
    ]) {
      c.dispose();
    }
    for (final row in medicines) {
      row.dispose();
    }
    for (final rows in physioTables.values) {
      for (final row in rows) {
        row.dispose();
      }
    }
    super.dispose();
  }
}
