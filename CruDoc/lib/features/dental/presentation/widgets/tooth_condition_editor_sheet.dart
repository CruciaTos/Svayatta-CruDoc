import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/tooth_chart_entry_model.dart';
import '../providers/dental_providers.dart';
import 'odontogram_view.dart';

/// Clean modal bottom sheet for logging conditions and treatments on a selected tooth.
class ToothConditionEditorSheet extends ConsumerStatefulWidget {
  final String doctorId;
  final String patientId;
  final String toothNumber;
  final ToothChartEntryModel? existingEntry;

  const ToothConditionEditorSheet({
    super.key,
    required this.doctorId,
    required this.patientId,
    required this.toothNumber,
    this.existingEntry,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String doctorId,
    required String patientId,
    required String toothNumber,
    ToothChartEntryModel? existingEntry,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => ToothConditionEditorSheet(
        doctorId: doctorId,
        patientId: patientId,
        toothNumber: toothNumber,
        existingEntry: existingEntry,
      ),
    );
  }

  @override
  ConsumerState<ToothConditionEditorSheet> createState() =>
      _ToothConditionEditorSheetState();
}

class _ToothConditionEditorSheetState
    extends ConsumerState<ToothConditionEditorSheet> {
  final _uuid = const Uuid();
  late final TextEditingController _notesController;

  String? _selectedSurface;
  String? _selectedCondition;
  String? _selectedTreatment;
  bool _isSaving = false;

  static const _surfaces = [
    'mesial',
    'distal',
    'occlusal',
    'buccal',
    'lingual',
    'incisal',
    'cervical',
  ];

  static const _conditions = [
    'caries',
    'fractured',
    'missing',
    'unerupted',
    'impacted',
    'restored',
    'rootCanal',
  ];

  static const _treatments = [
    'filling',
    'extraction',
    'crown',
    'bridge',
    'implant',
    'scaling',
    'rct',
  ];

  @override
  void initState() {
    super.initState();
    _selectedSurface = widget.existingEntry?.surface;
    _selectedCondition = widget.existingEntry?.condition;
    _selectedTreatment = widget.existingEntry?.treatment;
    _notesController = TextEditingController(text: widget.existingEntry?.notes ?? '');
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (_selectedCondition == null &&
        _selectedTreatment == null &&
        _notesController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a condition, treatment, or add a note.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final now = DateTime.now();
      final entry = ToothChartEntryModel(
        id: _uuid.v4(),
        doctorId: widget.doctorId,
        patientId: widget.patientId,
        toothNumber: widget.toothNumber,
        notationSystem: 'fdi',
        surface: _selectedSurface,
        condition: _selectedCondition,
        treatment: _selectedTreatment,
        notes: _notesController.text.trim(),
        recordedAt: now,
        createdAt: now,
        updatedAt: now,
        syncStatus: 'synced',
      );

      await ref.read(dentalRepositoryProvider).saveToothChartEntry(entry);
      ref.invalidate(patientToothChartProvider(widget.patientId));

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved entry for Tooth ${widget.toothNumber}')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save tooth entry: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tooth ${widget.toothNumber}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        getToothName(widget.toothNumber),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF64748B)),
                  onPressed: () => Navigator.pop(context, false),
                ),
              ],
            ),

            const Divider(height: 24, color: Color(0xFFE2E8F0)),

            // Section: Surface
            const Text(
              'TOOTH SURFACE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _surfaces.map((s) {
                final isSelected = _selectedSurface == s;
                return ChoiceChip(
                  label: Text(s.toUpperCase(), style: const TextStyle(fontSize: 11)),
                  selected: isSelected,
                  selectedColor: const Color(0xFFCCFBF1),
                  onSelected: (selected) {
                    setState(() => _selectedSurface = selected ? s : null);
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // Section: Condition
            const Text(
              'CLINICAL FINDING / CONDITION',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _conditions.map((c) {
                final isSelected = _selectedCondition == c;
                return ChoiceChip(
                  label: Text(c, style: const TextStyle(fontSize: 12)),
                  selected: isSelected,
                  selectedColor: const Color(0xFFFEE2E2),
                  onSelected: (selected) {
                    setState(() => _selectedCondition = selected ? c : null);
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // Section: Treatment
            const Text(
              'TREATMENT / PROCEDURE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _treatments.map((t) {
                final isSelected = _selectedTreatment == t;
                return ChoiceChip(
                  label: Text(t, style: const TextStyle(fontSize: 12)),
                  selected: isSelected,
                  selectedColor: const Color(0xFFDBEAFE),
                  onSelected: (selected) {
                    setState(() => _selectedTreatment = selected ? t : null);
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // Section: Clinical Notes
            const Text(
              'CLINICAL NOTES',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _notesController,
              maxLines: 3,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Add clinical notes for this tooth...',
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),

            const SizedBox(height: 20),

            // Actions: Cancel & Save
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _isSaving ? null : _handleSave,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0D9488),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Save Entry'),
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
