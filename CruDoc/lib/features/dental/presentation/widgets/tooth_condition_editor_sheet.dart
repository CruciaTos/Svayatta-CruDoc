import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:crudoc_shared/theme/cru_colors.dart';
import '../../data/models/tooth_chart_entry_model.dart';
import '../../domain/tooth_numbering.dart';
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
    final surface = Theme.of(context).extension<CruColors>()?.surface ??
        (Theme.of(context).brightness == Brightness.dark
            ? CruColors.evening.surface
            : CruColors.day.surface);
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: surface,
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
  CruColors get _c =>
      Theme.of(context).extension<CruColors>() ??
      (Theme.of(context).brightness == Brightness.dark
          ? CruColors.evening
          : CruColors.day);

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
    _notesController = TextEditingController(
      text: widget.existingEntry?.notes ?? '',
    );
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
        const SnackBar(
          content: Text('Please select a condition, treatment, or add a note.'),
        ),
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
        final numbering =
            ref.read(toothNumberingProvider).value ?? ToothNumbering.fdi;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saved entry for Tooth ${toothLabel(widget.toothNumber, numbering)}',
            ),
          ),
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
    final numbering =
        ref.watch(toothNumberingProvider).value ?? ToothNumbering.fdi;
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
                        'Tooth ${toothLabel(widget.toothNumber, numbering)}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: _c.label,
                        ),
                      ),
                      Text(
                        getToothName(widget.toothNumber),
                        style: TextStyle(
                          fontSize: 12,
                          color: _c.label2,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: _c.label2),
                  onPressed: () => Navigator.pop(context, false),
                ),
              ],
            ),

            Divider(height: 24, color: _c.separator),

            // Section: Surface
            Text(
              'TOOTH SURFACE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: _c.label2,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _surfaces.map((s) {
                final isSelected = _selectedSurface == s;
                return ChoiceChip(
                  label: Text(
                    s.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      color: isSelected ? _c.accent : _c.label,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: _c.accent.withValues(alpha: 0.15),
                  backgroundColor: _c.inset,
                  side: BorderSide(color: isSelected ? _c.accent : _c.separator),
                  onSelected: (selected) {
                    setState(() => _selectedSurface = selected ? s : null);
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // Section: Condition
            Text(
              'CLINICAL FINDING / CONDITION',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: _c.label2,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _conditions.map((c) {
                final isSelected = _selectedCondition == c;
                return ChoiceChip(
                  label: Text(
                    c,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected ? Colors.redAccent : _c.label,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: Colors.redAccent.withValues(alpha: 0.15),
                  backgroundColor: _c.inset,
                  side: BorderSide(color: isSelected ? Colors.redAccent : _c.separator),
                  onSelected: (selected) {
                    setState(() => _selectedCondition = selected ? c : null);
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // Section: Treatment
            Text(
              'TREATMENT / PROCEDURE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: _c.label2,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _treatments.map((t) {
                final isSelected = _selectedTreatment == t;
                return ChoiceChip(
                  label: Text(
                    t,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected ? const Color(0xFF2563EB) : _c.label,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: const Color(0xFF2563EB).withValues(alpha: 0.15),
                  backgroundColor: _c.inset,
                  side: BorderSide(color: isSelected ? const Color(0xFF2563EB) : _c.separator),
                  onSelected: (selected) {
                    setState(() => _selectedTreatment = selected ? t : null);
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // Section: Clinical Notes
            Text(
              'CLINICAL NOTES',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: _c.label2,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _notesController,
              maxLines: 3,
              style: TextStyle(fontSize: 13, color: _c.label),
              decoration: InputDecoration(
                hintText: 'Add clinical notes for this tooth...',
                hintStyle: TextStyle(fontSize: 13, color: _c.label2),
                filled: true,
                fillColor: _c.inset,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: _c.separator),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: _c.separator),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: _c.accent, width: 1.5),
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
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: _c.separator),
                      foregroundColor: _c.label,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _isSaving ? null : _handleSave,
                    style: FilledButton.styleFrom(
                      backgroundColor: _c.accent,
                      foregroundColor: _c.onAccent,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _isSaving
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: _c.onAccent,
                              strokeWidth: 2,
                            ),
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
