// desktop_scribe_draft_review_screen.dart
//
// Desktop-native replacement for [ScribeDraftReviewScreen]. Presented as a
// centered Dialog (max 640 px wide) immediately after the recording dialog
// closes, so the doctor never leaves the desktop shell. All fields are
// editable — same rules as the mobile review screen:
//
//   • The Confirm button is locked until the doctor has either scrolled past
//     the first 120 px of content OR edited at least one field.
//   • Tapping Confirm → saves edits → calls confirmNote → closes dialog (true).
//   • Tapping Discard → confirm prompt → discardNote → closes dialog (false).
//
// Colour tokens match desktop_scribe_recording_screen.dart and the rest of
// the desktop palette (desktop_patient_details_screen.dart).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/scribe/data/providers/scribe_providers.dart';

// ---------- Palette (matches desktop_scribe_recording_screen.dart) ----------
const Color _kTextPrimary   = Color(0xFF1F2937);
const Color _kTextSecondary = Color(0xFF6B7280);
const Color _kBorder        = Color(0xFFE2E8F0);
const Color _kAccentBlue    = Color(0xFF2563EB);
const Color _kAccentBlueBg  = Color(0xFFEFF6FF);
const Color _kRed           = Color(0xFFDC2626);
const Color _kGreen         = Color(0xFF16A34A);
const Color _kSurface       = Color(0xFFF8FAFC);
const Color _kAmber         = Color(0xFFD97706);
const Color _kAmberBg       = Color(0xFFFFFBEB);

/// Opens the desktop draft-review dialog for [note].
///
/// Returns `true` if the doctor confirmed the note, `false` otherwise.
Future<bool> showDesktopScribeDraftReviewDialog(
  BuildContext context, {
  required ConsultationNote note,
  Patient? patient,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DesktopDraftReviewDialog(note: note, patient: patient),
  );
  return result ?? false;
}

// ---------------------------------------------------------------------------

class _DesktopDraftReviewDialog extends ConsumerStatefulWidget {
  final ConsultationNote note;
  final Patient? patient;

  const _DesktopDraftReviewDialog({required this.note, this.patient});

  @override
  ConsumerState<_DesktopDraftReviewDialog> createState() =>
      _DesktopDraftReviewDialogState();
}

class _DesktopDraftReviewDialogState
    extends ConsumerState<_DesktopDraftReviewDialog> {
  // ---- Form controllers ----
  late TextEditingController _chiefComplaintCtrl;
  late TextEditingController _adviceCtrl;
  late TextEditingController _confidenceCtrl;
  late TextEditingController _bpCtrl;
  late TextEditingController _tempCtrl;
  late TextEditingController _pulseCtrl;

  // Editable lists
  late List<String> _symptoms;
  late List<String> _diagnoses;
  late List<NotedMedicine> _medicines;

  // Follow-up date
  DateTime? _followUpDate;

  // State
  bool _isBusy        = false;
  bool _hasInteracted = false;
  final _scrollCtrl   = ScrollController();

  // Chip add-field controllers (one per section)
  final _symptomAddCtrl   = TextEditingController();
  final _diagnosisAddCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final n = widget.note;
    _chiefComplaintCtrl = TextEditingController(text: n.chiefComplaint);
    _adviceCtrl         = TextEditingController(text: n.advice);
    _confidenceCtrl     = TextEditingController(text: n.confidenceNote);
    _bpCtrl             = TextEditingController(text: n.vitals['bp']    ?? '');
    _tempCtrl           = TextEditingController(text: n.vitals['temp']  ?? '');
    _pulseCtrl          = TextEditingController(text: n.vitals['pulse'] ?? '');
    _symptoms           = List<String>.from(n.symptoms);
    _diagnoses          = List<String>.from(n.diagnosisSuggestions);
    _medicines          = List<NotedMedicine>.from(n.medicines);
    _followUpDate       = n.followUpDate;

    _scrollCtrl.addListener(() {
      if (_scrollCtrl.offset > 120 && !_hasInteracted) {
        setState(() => _hasInteracted = true);
      }
    });
  }

  @override
  void dispose() {
    _chiefComplaintCtrl.dispose();
    _adviceCtrl.dispose();
    _confidenceCtrl.dispose();
    _bpCtrl.dispose();
    _tempCtrl.dispose();
    _pulseCtrl.dispose();
    _symptomAddCtrl.dispose();
    _diagnosisAddCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _markInteracted() {
    if (!_hasInteracted) setState(() => _hasInteracted = true);
  }

  // ---- Build current note from form state ----

  ConsultationNote _buildCurrentNote() {
    return widget.note.copyWith(
      chiefComplaint:       _chiefComplaintCtrl.text.trim(),
      symptoms:             _symptoms.where((s) => s.trim().isNotEmpty).toList(),
      diagnosisSuggestions: _diagnoses.where((d) => d.trim().isNotEmpty).toList(),
      medicines:            _medicines.where((m) => m.name.trim().isNotEmpty).toList(),
      advice:               _adviceCtrl.text.trim(),
      followUpDate:         _followUpDate,
      clearFollowUpDate:    _followUpDate == null,
      vitals: {
        'bp':    _bpCtrl.text.trim().isEmpty   ? null : _bpCtrl.text.trim(),
        'temp':  _tempCtrl.text.trim().isEmpty  ? null : _tempCtrl.text.trim(),
        'pulse': _pulseCtrl.text.trim().isEmpty ? null : _pulseCtrl.text.trim(),
      },
      confidenceNote: _confidenceCtrl.text.trim(),
    );
  }

  // ---- Actions ----

  Future<void> _confirm() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    final repo = ref.read(consultationNoteRepositoryProvider);
    try {
      final updated = _buildCurrentNote();
      await repo.saveNote(updated);
      await repo.confirmNote(updated);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to confirm note: $e'),
            backgroundColor: _kRed,
          ),
        );
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _discard() async {
    if (_isBusy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Discard this draft?',
          style: TextStyle(color: _kTextPrimary, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'The AI draft will be deleted and no changes will be made to the '
          'patient record.',
          style: TextStyle(color: _kTextSecondary, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep reviewing',
                style: TextStyle(color: _kAccentBlue)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard',
                style: TextStyle(
                    color: _kRed, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _isBusy = true);
    final repo = ref.read(consultationNoteRepositoryProvider);
    try {
      await repo.discardNote(widget.note);
      if (mounted) Navigator.of(context).pop(false);
    } catch (_) {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 780),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            _buildAiBanner(),
            Flexible(
              child: ListView(
                controller: _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                children: [
                  _buildSection(
                    label: 'CHIEF COMPLAINT',
                    child: _buildTextField(_chiefComplaintCtrl,
                        hint: 'e.g. Headache for 3 days'),
                  ),
                  const SizedBox(height: 14),
                  _buildSection(
                    label: 'SYMPTOMS',
                    child: _buildChipEditor(
                      items: _symptoms,
                      addCtrl: _symptomAddCtrl,
                      hint: 'Add symptom…',
                      chipColor: const Color(0xFF0EA5E9),
                      onUpdate: (v) => setState(() {
                        _symptoms = v;
                        _markInteracted();
                      }),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildSection(
                    label: 'DIAGNOSIS SUGGESTIONS',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.patient != null &&
                            widget.patient!.diagnosis.isNotEmpty)
                          _buildExistingDiagnosesChip(),
                        const SizedBox(height: 8),
                        _buildChipEditor(
                          items: _diagnoses,
                          addCtrl: _diagnosisAddCtrl,
                          hint: 'Add diagnosis…',
                          chipColor: const Color(0xFF7C3AED),
                          onUpdate: (v) => setState(() {
                            _diagnoses = v;
                            _markInteracted();
                          }),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildSection(
                    label: 'MEDICINES',
                    child: _buildMedicinesEditor(),
                  ),
                  const SizedBox(height: 14),
                  _buildSection(
                    label: 'ADVICE / PLAN',
                    child: _buildTextField(_adviceCtrl,
                        hint: 'e.g. Rest, stay hydrated…', maxLines: 4),
                  ),
                  const SizedBox(height: 14),
                  _buildSection(
                    label: 'VITALS (if mentioned)',
                    child: _buildVitalsRow(),
                  ),
                  const SizedBox(height: 14),
                  _buildSection(
                    label: 'FOLLOW-UP DATE',
                    child: _buildFollowUpPicker(),
                  ),
                  if (_confidenceCtrl.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _buildConfidenceNote(),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  // ---- Sub-widgets ----

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _kAccentBlueBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.description_outlined,
                color: _kAccentBlue, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Review Clinical Note',
                  style: TextStyle(
                    color: _kTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  widget.patient?.fullName ?? 'Unknown Patient',
                  style: const TextStyle(
                      color: _kTextSecondary, fontSize: 12.5),
                ),
              ],
            ),
          ),
          // DRAFT badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _kAmberBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: _kAmber.withValues(alpha: 0.4)),
            ),
            child: const Text(
              'DRAFT',
              style: TextStyle(
                color: _kAmber,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 14, 24, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kAccentBlueBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kAccentBlue.withValues(alpha: 0.25)),
      ),
      child: const Row(
        children: [
          Icon(Icons.auto_awesome_rounded, color: _kAccentBlue, size: 16),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'AI-generated draft — review and edit every field before '
              'confirming. Only you can approve what goes into the patient record.',
              style: TextStyle(
                color: _kAccentBlue,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({required String label, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _kTextSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController ctrl, {
    String hint = '',
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      minLines: 1,
      onChanged: (_) => _markInteracted(),
      style: const TextStyle(color: _kTextPrimary, fontSize: 13.5),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(color: _kTextSecondary, fontSize: 13),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kAccentBlue, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildChipEditor({
    required List<String> items,
    required TextEditingController addCtrl,
    required String hint,
    required Color chipColor,
    required ValueChanged<List<String>> onUpdate,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (items.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items.asMap().entries.map((e) {
              return Chip(
                label: Text(
                  e.value,
                  style: TextStyle(color: chipColor, fontSize: 12.5),
                ),
                backgroundColor: chipColor.withValues(alpha: 0.08),
                side: BorderSide(
                    color: chipColor.withValues(alpha: 0.3)),
                deleteIconColor:
                    chipColor.withValues(alpha: 0.7),
                onDeleted: () {
                  final updated = List<String>.from(items)
                    ..removeAt(e.key);
                  onUpdate(updated);
                },
                padding:
                    const EdgeInsets.symmetric(horizontal: 4),
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: addCtrl,
                style: const TextStyle(
                    color: _kTextPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: const TextStyle(
                      color: _kTextSecondary, fontSize: 13),
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _kBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _kBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                        color: _kAccentBlue, width: 1.5),
                  ),
                ),
                onSubmitted: (val) {
                  if (val.trim().isEmpty) return;
                  onUpdate([...items, val.trim()]);
                  addCtrl.clear();
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add_circle_outline,
                  color: _kAccentBlue, size: 22),
              onPressed: () {
                final val = addCtrl.text.trim();
                if (val.isEmpty) return;
                onUpdate([...items, val]);
                addCtrl.clear();
              },
              tooltip: 'Add',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildExistingDiagnosesChip() {
    final existing = widget.patient!.diagnosis;
    return Container(
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Existing diagnoses on record:',
            style:
                TextStyle(color: _kTextSecondary, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: existing.map((d) {
              return Chip(
                label: Text(
                  d,
                  style:
                      const TextStyle(color: _kGreen, fontSize: 12),
                ),
                backgroundColor:
                    _kGreen.withValues(alpha: 0.08),
                side: BorderSide(
                    color: _kGreen.withValues(alpha: 0.3)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 4),
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicinesEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._medicines.asMap().entries.map((e) =>
            _buildMedicineRow(e.key, e.value)),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: () => setState(() {
            _medicines.add(const NotedMedicine(name: ''));
            _markInteracted();
          }),
          icon: const Icon(Icons.add, size: 16, color: _kAccentBlue),
          label: const Text(
            'Add medicine',
            style: TextStyle(color: _kAccentBlue, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildMedicineRow(int index, NotedMedicine med) {
    final nameCtrl   = TextEditingController(text: med.name);
    final dosageCtrl = TextEditingController(text: med.dosage);
    final instrCtrl  = TextEditingController(text: med.instructions);

    void update() => setState(() {
          _medicines[index] = NotedMedicine(
            name:         nameCtrl.text,
            dosage:       dosageCtrl.text,
            instructions: instrCtrl.text,
          );
          _markInteracted();
        });

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: nameCtrl,
                  onChanged: (_) => update(),
                  style: const TextStyle(
                      color: _kTextPrimary, fontSize: 13),
                  decoration: _fieldDeco('Medicine name'),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline,
                    color: _kRed, size: 20),
                onPressed: () =>
                    setState(() => _medicines.removeAt(index)),
                tooltip: 'Remove',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: dosageCtrl,
                  onChanged: (_) => update(),
                  style: const TextStyle(
                      color: _kTextPrimary, fontSize: 12.5),
                  decoration: _fieldDeco('Dosage'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: instrCtrl,
                  onChanged: (_) => update(),
                  style: const TextStyle(
                      color: _kTextPrimary, fontSize: 12.5),
                  decoration: _fieldDeco('Instructions'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
            color: _kTextSecondary, fontSize: 12),
        filled: true,
        fillColor: _kSurface,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: _kAccentBlue, width: 1.5),
        ),
      );

  Widget _buildVitalsRow() {
    return Row(
      children: [
        Expanded(child: _buildVitalField(_bpCtrl,    'BP (mmHg)')),
        const SizedBox(width: 8),
        Expanded(child: _buildVitalField(_tempCtrl,  'Temp (°F/°C)')),
        const SizedBox(width: 8),
        Expanded(child: _buildVitalField(_pulseCtrl, 'Pulse (bpm)')),
      ],
    );
  }

  Widget _buildVitalField(
      TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      onChanged: (_) => _markInteracted(),
      style: const TextStyle(color: _kTextPrimary, fontSize: 13),
      decoration: _fieldDeco(hint),
    );
  }

  Widget _buildFollowUpPicker() {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _followUpDate ??
              DateTime.now().add(const Duration(days: 7)),
          firstDate: DateTime.now(),
          lastDate:
              DateTime.now().add(const Duration(days: 365 * 2)),
        );
        if (picked != null) {
          setState(() {
            _followUpDate  = picked;
            _hasInteracted = true;
          });
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded,
                color: _kTextSecondary, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _followUpDate != null
                    ? DateFormat('d MMM yyyy')
                        .format(_followUpDate!)
                    : 'No follow-up date (click to set)',
                style: TextStyle(
                  color: _followUpDate != null
                      ? _kTextPrimary
                      : _kTextSecondary,
                  fontSize: 13,
                ),
              ),
            ),
            if (_followUpDate != null)
              GestureDetector(
                onTap: () =>
                    setState(() => _followUpDate = null),
                child: const Icon(Icons.close,
                    color: _kTextSecondary, size: 16),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfidenceNote() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kAmberBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: _kAmber.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline,
              color: _kAmber, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI Confidence Note',
                  style: TextStyle(
                    color: _kAmber,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _confidenceCtrl.text,
                  style: const TextStyle(
                    color: _kTextSecondary,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _kBorder)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_hasInteracted)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'Scroll through or edit a field to enable Confirm',
                style: TextStyle(
                    color: _kTextSecondary, fontSize: 11.5),
                textAlign: TextAlign.center,
              ),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isBusy ? null : _discard,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kRed,
                    side: BorderSide(
                        color: _kRed.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(
                        vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(12)),
                  ),
                  child: const Text('Discard',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed:
                      (_isBusy || !_hasInteracted) ? null : _confirm,
                  icon: _isBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white),
                        )
                      : const Icon(
                          Icons.check_circle_outline_rounded,
                          size: 18),
                  label: const Text(
                    'Confirm & Save',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        const Color(0xFFE2E8F0),
                    disabledForegroundColor:
                        const Color(0xFF94A3B8),
                    padding: const EdgeInsets.symmetric(
                        vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
