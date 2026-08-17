import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/scribe/data/repo/consultation_note_repository.dart';
import 'package:doctor_management_app/features/scribe/data/providers/scribe_providers.dart';

/// Full-screen review screen shown after the AI produces a draft consultation note.
///
/// Every field is editable so the doctor can correct any AI error before
/// confirming. The Confirm button only activates after the doctor has
/// scrolled past all the content (or tapped at least one field), so
/// that a draft cannot be accidentally confirmed at a glance.
///
/// Tapping Confirm calls [ConsultationNoteRepository.confirmNote], which
/// writes the note to the patient record and Visit. Tapping Discard calls
/// [ConsultationNoteRepository.discardNote] (no patient-record changes).
class ScribeDraftReviewScreen extends ConsumerStatefulWidget {
  final ConsultationNote note;
  final Patient? patient;

  const ScribeDraftReviewScreen({
    super.key,
    required this.note,
    this.patient,
  });

  @override
  ConsumerState<ScribeDraftReviewScreen> createState() =>
      _ScribeDraftReviewScreenState();
}

class _ScribeDraftReviewScreenState
    extends ConsumerState<ScribeDraftReviewScreen> {
  // ---- Form controllers (one per editable field) ----
  late TextEditingController _chiefComplaintController;
  late TextEditingController _adviceController;
  late TextEditingController _confidenceController;

  // Editable lists
  late List<String> _symptoms;
  late List<String> _diagnosisSuggestions;
  late List<NotedMedicine> _medicines;

  // Editable vitals
  late TextEditingController _bpController;
  late TextEditingController _tempController;
  late TextEditingController _pulseController;

  // Follow-up date
  DateTime? _followUpDate;

  // State
  bool _isBusy = false;
  bool _hasInteracted = false; // unlocks Confirm button after first interaction
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final n = widget.note;
    _chiefComplaintController = TextEditingController(text: n.chiefComplaint);
    _adviceController = TextEditingController(text: n.advice);
    _confidenceController = TextEditingController(text: n.confidenceNote);
    _symptoms = List<String>.from(n.symptoms);
    _diagnosisSuggestions = List<String>.from(n.diagnosisSuggestions);
    _medicines = List<NotedMedicine>.from(n.medicines);
    _bpController = TextEditingController(text: n.vitals['bp'] ?? '');
    _tempController = TextEditingController(text: n.vitals['temp'] ?? '');
    _pulseController = TextEditingController(text: n.vitals['pulse'] ?? '');
    _followUpDate = n.followUpDate;

    _scrollController.addListener(() {
      if (_scrollController.offset > 100 && !_hasInteracted) {
        setState(() => _hasInteracted = true);
      }
    });
  }

  @override
  void dispose() {
    _chiefComplaintController.dispose();
    _adviceController.dispose();
    _confidenceController.dispose();
    _bpController.dispose();
    _tempController.dispose();
    _pulseController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ---- Build current draft from form state ----

  ConsultationNote _buildCurrentNote() {
    return widget.note.copyWith(
      chiefComplaint: _chiefComplaintController.text.trim(),
      symptoms: _symptoms.where((s) => s.trim().isNotEmpty).toList(),
      diagnosisSuggestions:
          _diagnosisSuggestions.where((d) => d.trim().isNotEmpty).toList(),
      medicines:
          _medicines.where((m) => m.name.trim().isNotEmpty).toList(),
      advice: _adviceController.text.trim(),
      followUpDate: _followUpDate,
      clearFollowUpDate: _followUpDate == null,
      vitals: {
        'bp': _bpController.text.trim().isEmpty
            ? null
            : _bpController.text.trim(),
        'temp': _tempController.text.trim().isEmpty
            ? null
            : _tempController.text.trim(),
        'pulse': _pulseController.text.trim().isEmpty
            ? null
            : _pulseController.text.trim(),
      },
      confidenceNote: _confidenceController.text.trim(),
    );
  }

  // ---- Actions ----

  Future<void> _confirm() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);

    final repo = ref.read(consultationNoteRepositoryProvider);
    try {
      final updated = _buildCurrentNote();
      // Save the doctor's edits first
      await repo.saveNote(updated);
      // Then confirm
      await repo.confirmNote(updated);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Clinical note confirmed and saved to patient record.'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to confirm note: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _discard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2A313C),
        title: const Text(
          'Discard this note?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'The AI draft will be discarded and the recording deleted. '
          'No changes will be made to the patient record.',
          style: TextStyle(color: Color(0xFF8A9BB0)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Keep reviewing',
              style: TextStyle(color: Color(0xFF4A90D9)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Discard',
              style: TextStyle(color: Color(0xFFE57373)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isBusy = true);
    final repo = ref.read(consultationNoteRepositoryProvider);
    try {
      await repo.discardNote(widget.note);
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  // ---- UI ----

  static const _cardColor = Color(0xFF232A35);
  static const _sectionColor = Color(0xFF1B2430);
  static const _accent = Color(0xFF4A90D9);
  static const _textWhite = Colors.white;
  static const _textMuted = Color(0xFF8A9BB0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _sectionColor,
      body: Column(
        children: [
          _buildAppBar(),
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                _buildAiBanner(),
                const SizedBox(height: 16),
                _buildSection(
                  label: 'CHIEF COMPLAINT',
                  child: _buildTextField(_chiefComplaintController,
                      hint: 'e.g. Headache for 3 days'),
                ),
                const SizedBox(height: 16),
                _buildSection(
                  label: 'SYMPTOMS',
                  child: _buildChipEditor(
                    items: _symptoms,
                    hint: 'Add symptom…',
                    onUpdate: (items) => setState(() => _symptoms = items),
                  ),
                ),
                const SizedBox(height: 16),
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
                        items: _diagnosisSuggestions,
                        hint: 'Add diagnosis…',
                        color: const Color(0xFF7986CB),
                        onUpdate: (items) =>
                            setState(() => _diagnosisSuggestions = items),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildSection(
                  label: 'MEDICINES',
                  child: _buildMedicinesEditor(),
                ),
                const SizedBox(height: 16),
                _buildSection(
                  label: 'ADVICE / PLAN',
                  child: _buildTextField(
                    _adviceController,
                    hint: 'e.g. Rest, stay hydrated…',
                    maxLines: 4,
                  ),
                ),
                const SizedBox(height: 16),
                _buildSection(
                  label: 'VITALS (if mentioned)',
                  child: _buildVitalsRow(),
                ),
                const SizedBox(height: 16),
                _buildSection(
                  label: 'FOLLOW-UP DATE',
                  child: _buildFollowUpPicker(),
                ),
                if (_confidenceController.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildConfidenceNote(),
                ],
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildAppBar() {
    return Container(
      color: const Color(0xFF1B2430),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new,
                    color: Colors.white, size: 18),
                onPressed: _isBusy ? null : _discard,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Review Clinical Note',
                      style: TextStyle(
                        color: _textWhite,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        fontFamily: AppColors.headingFontFamily,
                      ),
                    ),
                    Text(
                      widget.patient?.fullName ?? 'Unknown Patient',
                      style: const TextStyle(
                        color: _textMuted,
                        fontSize: 12,
                        fontFamily: AppColors.bodyFontFamily,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE65100).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: const Color(0xFFE65100).withValues(alpha: 0.4),
                  ),
                ),
                child: const Text(
                  'DRAFT',
                  style: TextStyle(
                    color: Color(0xFFFFB74D),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    fontFamily: AppColors.bodyFontFamily,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAiBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome_rounded, color: _accent, size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'AI-generated draft — review and edit every field before '
              'confirming. Only you can approve what goes into the patient record.',
              style: TextStyle(
                color: _accent,
                fontSize: 12.5,
                fontFamily: AppColors.bodyFontFamily,
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
        color: _cardColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              fontFamily: AppColors.bodyFontFamily,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller, {
    String hint = '',
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      minLines: 1,
      onChanged: (_) {
        if (!_hasInteracted) setState(() => _hasInteracted = true);
      },
      style: const TextStyle(
        color: _textWhite,
        fontSize: 14,
        fontFamily: AppColors.bodyFontFamily,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            TextStyle(color: _textMuted.withValues(alpha: 0.6), fontSize: 14),
        filled: true,
        fillColor: const Color(0xFF2A313C),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _buildChipEditor({
    required List<String> items,
    required String hint,
    Color color = const Color(0xFF4FC3F7),
    required ValueChanged<List<String>> onUpdate,
  }) {
    final controller = TextEditingController();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...items.asMap().entries.map((entry) {
              return Chip(
                label: Text(
                  entry.value,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontFamily: AppColors.bodyFontFamily,
                  ),
                ),
                backgroundColor: color.withValues(alpha: 0.1),
                side: BorderSide(color: color.withValues(alpha: 0.3)),
                deleteIconColor: color.withValues(alpha: 0.7),
                onDeleted: () {
                  final updated = List<String>.from(items)
                    ..removeAt(entry.key);
                  onUpdate(updated);
                  if (!_hasInteracted) setState(() => _hasInteracted = true);
                },
                padding: const EdgeInsets.symmetric(horizontal: 4),
              );
            }),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                style: const TextStyle(
                  color: _textWhite,
                  fontSize: 13,
                  fontFamily: AppColors.bodyFontFamily,
                ),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: TextStyle(
                      color: _textMuted.withValues(alpha: 0.6), fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFF2A313C),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  isDense: true,
                ),
                onSubmitted: (val) {
                  if (val.trim().isEmpty) return;
                  onUpdate([...items, val.trim()]);
                  controller.clear();
                  if (!_hasInteracted) setState(() => _hasInteracted = true);
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, color: _accent),
              onPressed: () {
                final val = controller.text.trim();
                if (val.isEmpty) return;
                onUpdate([...items, val]);
                controller.clear();
                if (!_hasInteracted) setState(() => _hasInteracted = true);
              },
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
        color: const Color(0xFF263238),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Existing diagnoses on record:',
            style: TextStyle(
              color: _textMuted,
              fontSize: 11,
              fontFamily: AppColors.bodyFontFamily,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: existing.map((d) {
              return Chip(
                label: Text(
                  d,
                  style: const TextStyle(
                    color: Color(0xFF80CBC4),
                    fontSize: 12,
                    fontFamily: AppColors.bodyFontFamily,
                  ),
                ),
                backgroundColor: const Color(0xFF00695C).withValues(alpha: 0.15),
                side: BorderSide(
                    color: const Color(0xFF80CBC4).withValues(alpha: 0.3)),
                padding: const EdgeInsets.symmetric(horizontal: 4),
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
        ..._medicines.asMap().entries.map((entry) {
          final i = entry.key;
          final med = entry.value;
          return _buildMedicineRow(i, med);
        }),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () {
            setState(() {
              _medicines.add(const NotedMedicine(name: ''));
            });
            if (!_hasInteracted) setState(() => _hasInteracted = true);
          },
          icon: const Icon(Icons.add, size: 16, color: _accent),
          label: const Text(
            'Add medicine',
            style: TextStyle(
              color: _accent,
              fontSize: 13,
              fontFamily: AppColors.bodyFontFamily,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMedicineRow(int index, NotedMedicine med) {
    final nameCtrl = TextEditingController(text: med.name);
    final dosageCtrl = TextEditingController(text: med.dosage);
    final instrCtrl = TextEditingController(text: med.instructions);

    void update() {
      setState(() {
        _medicines[index] = NotedMedicine(
          name: nameCtrl.text,
          dosage: dosageCtrl.text,
          instructions: instrCtrl.text,
        );
      });
      if (!_hasInteracted) setState(() => _hasInteracted = true);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A313C),
        borderRadius: BorderRadius.circular(10),
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
                      color: _textWhite,
                      fontSize: 13,
                      fontFamily: AppColors.bodyFontFamily),
                  decoration: _fieldDecoration('Medicine name'),
                ),
              ),
              IconButton(
                icon:
                    const Icon(Icons.remove_circle_outline, color: Color(0xFFE57373), size: 20),
                onPressed: () {
                  setState(() => _medicines.removeAt(index));
                },
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
                      color: _textWhite,
                      fontSize: 12,
                      fontFamily: AppColors.bodyFontFamily),
                  decoration: _fieldDecoration('Dosage'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: instrCtrl,
                  onChanged: (_) => update(),
                  style: const TextStyle(
                      color: _textWhite,
                      fontSize: 12,
                      fontFamily: AppColors.bodyFontFamily),
                  decoration: _fieldDecoration('Instructions'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: _textMuted.withValues(alpha: 0.6), fontSize: 12),
      filled: true,
      fillColor: const Color(0xFF1B2430),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      isDense: true,
    );
  }

  Widget _buildVitalsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildVitalField(_bpController, 'BP (mmHg)'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildVitalField(_tempController, 'Temp (°F/°C)'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildVitalField(_pulseController, 'Pulse (bpm)'),
        ),
      ],
    );
  }

  Widget _buildVitalField(TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      onChanged: (_) {
        if (!_hasInteracted) setState(() => _hasInteracted = true);
      },
      style: const TextStyle(
        color: _textWhite,
        fontSize: 13,
        fontFamily: AppColors.bodyFontFamily,
      ),
      decoration: _fieldDecoration(hint),
    );
  }

  Widget _buildFollowUpPicker() {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate:
              _followUpDate ?? DateTime.now().add(const Duration(days: 7)),
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: const ColorScheme.dark(
                primary: Color(0xFF4A90D9),
                onPrimary: Colors.white,
                surface: Color(0xFF2A313C),
                onSurface: Colors.white,
              ),
            ),
            child: child!,
          ),
        );
        if (picked != null) {
          setState(() {
            _followUpDate = picked;
            _hasInteracted = true;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF2A313C),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded,
                color: _textMuted, size: 16),
            const SizedBox(width: 10),
            Text(
              _followUpDate != null
                  ? DateFormat('d MMM yyyy').format(_followUpDate!)
                  : 'No follow-up date (tap to set)',
              style: TextStyle(
                color: _followUpDate != null ? _textWhite : _textMuted,
                fontSize: 13,
                fontFamily: AppColors.bodyFontFamily,
              ),
            ),
            const Spacer(),
            if (_followUpDate != null)
              GestureDetector(
                onTap: () => setState(() => _followUpDate = null),
                child: const Icon(Icons.close, color: _textMuted, size: 16),
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
        color: const Color(0xFFE65100).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFFE65100).withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline,
              color: Color(0xFFFFB74D), size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI Confidence Note',
                  style: TextStyle(
                    color: Color(0xFFFFB74D),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    fontFamily: AppColors.bodyFontFamily,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _confidenceController.text,
                  style: const TextStyle(
                    color: Color(0xFFBCAAA4),
                    fontSize: 12.5,
                    fontFamily: AppColors.bodyFontFamily,
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: const BoxDecoration(
        color: Color(0xFF1B2430),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_hasInteracted)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  'Scroll through or edit a field to enable Confirm',
                  style: TextStyle(
                    color: Color(0xFF8A9BB0),
                    fontSize: 11.5,
                    fontFamily: AppColors.bodyFontFamily,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isBusy ? null : _discard,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE57373),
                      side: const BorderSide(color: Color(0xFFE57373), width: 1),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      'Discard',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        fontFamily: AppColors.bodyFontFamily,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: (_isBusy || !_hasInteracted) ? null : _confirm,
                    icon: _isBusy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle_outline_rounded,
                            size: 18),
                    label: const Text(
                      'Confirm & Save',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFamily: AppColors.bodyFontFamily,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.white12,
                      disabledForegroundColor: Colors.white24,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
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
