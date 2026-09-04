import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/models/stock_transaction_model.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_providers.dart';
import '../../data/models/dental_procedure_catalog_model.dart';
import '../../data/models/dental_procedure_log_model.dart';
import '../../data/models/tooth_chart_entry_model.dart';
import '../providers/dental_providers.dart';

const Color _accentTeal = Color(0xFF0D9488);

/// Bottom sheet form to record a procedure performed or planned for a patient.
class DentalProcedureLogSheet extends ConsumerStatefulWidget {
  final String patientId;
  final String? preselectedToothNumber;
  final String? visitId;

  const DentalProcedureLogSheet({
    super.key,
    required this.patientId,
    this.preselectedToothNumber,
    this.visitId,
  });

  @override
  ConsumerState<DentalProcedureLogSheet> createState() =>
      _DentalProcedureLogSheetState();
}

class _DentalProcedureLogSheetState
    extends ConsumerState<DentalProcedureLogSheet> {
  final TextEditingController _procedureNameController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _materialsController = TextEditingController();
  final TextEditingController _teethInputController = TextEditingController();

  DateTime _performedAt = DateTime.now();
  String _selectedStatus = 'completed';
  String? _selectedCatalogId;
  String? _selectedVisitId;
  final Set<String> _selectedTeeth = {};

  // Phase 3: Consumable deduction state
  String? _selectedConsumableId;
  int _deductQuantity = 1;

  String get _currentDoctorId =>
      FirebaseAuth.instance.currentUser?.uid ?? 'doc_dental';

  @override
  void initState() {
    super.initState();
    _selectedVisitId = widget.visitId;
    if (widget.preselectedToothNumber != null &&
        widget.preselectedToothNumber!.isNotEmpty) {
      _selectedTeeth.add(widget.preselectedToothNumber!);
    }
  }

  @override
  void dispose() {
    _procedureNameController.dispose();
    _notesController.dispose();
    _materialsController.dispose();
    _teethInputController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _performedAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _performedAt = picked);
    }
  }

  void _onCatalogItemSelected(DentalProcedureCatalogModel proc) {
    setState(() {
      _selectedCatalogId = proc.id;
      _procedureNameController.text = proc.name;
    });
  }

  Future<void> _saveProcedure() async {
    final procName = _procedureNameController.text.trim();
    if (procName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or enter a procedure name')),
      );
      return;
    }

    final now = DateTime.now();
    final logId = const Uuid().v4();
    final repo = ref.read(dentalRepositoryProvider);

    final log = DentalProcedureLogModel(
      id: logId,
      doctorId: _currentDoctorId,
      patientId: widget.patientId,
      visitId: _selectedVisitId,
      procedureCatalogId: _selectedCatalogId,
      procedureName: procName,
      toothNumbers: _selectedTeeth.toList()..sort(),
      notationSystem: 'fdi',
      status: _selectedStatus,
      notes: _notesController.text.trim(),
      materials: _materialsController.text.trim().isNotEmpty
          ? _materialsController.text.trim()
          : null,
      performedAt: _performedAt,
      createdAt: now,
      updatedAt: now,
      syncStatus: 'pending',
    );

    await repo.saveProcedureLog(log);

    // Phase 3: Deduct consumable inventory if completed and item selected
    if (_selectedStatus == 'completed' &&
        _selectedConsumableId != null &&
        _deductQuantity > 0) {
      try {
        await ref.read(inventoryRepositoryProvider).recordTransaction(
              medicineId: _selectedConsumableId!,
              type: StockTransactionType.dispense,
              quantity: _deductQuantity,
              note: 'Used in Dental Procedure: $procName (Log ID: $logId)',
              linkedVisitId: _selectedVisitId,
            );
      } catch (e) {
        debugPrint('Phase 3 Consumable deduction error: $e');
      }
    }

    // If teeth are specified, also create a tooth chart entry for each tooth to reflect in Odontogram
    for (final tooth in _selectedTeeth) {
      final toothEntry = ToothChartEntryModel(
        id: const Uuid().v4(),
        doctorId: _currentDoctorId,
        patientId: widget.patientId,
        toothNumber: tooth,
        notationSystem: 'fdi',
        treatment: procName,
        condition: _selectedStatus == 'completed' ? 'restored' : null,
        procedureLogId: logId,
        notes: _notesController.text.trim(),
        recordedAt: _performedAt,
        createdAt: now,
        updatedAt: now,
        syncStatus: 'pending',
      );
      await repo.saveToothChartEntry(toothEntry);
    }

    ref.invalidate(patientProcedureLogProvider(widget.patientId));
    ref.invalidate(patientToothChartProvider(widget.patientId));
    if (_selectedVisitId != null) {
      ref.invalidate(visitProcedureLogProvider(_selectedVisitId!));
    }

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(dentalCatalogProvider(_currentDoctorId));
    final visitsAsync = ref.watch(visitsForPatientProvider(widget.patientId));
    final inventoryAsync = ref.watch(medicinesStreamProvider);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Log Dental Procedure',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Scrollable Form
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Catalog quick pick chips
                  catalogAsync.maybeWhen(
                    data: (catalog) {
                      if (catalog.isEmpty) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Quick Pick from Catalog',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 36,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: catalog.length,
                              separatorBuilder: (context, sepIndex) => const SizedBox(width: 8),
                              itemBuilder: (context, i) {
                                final item = catalog[i];
                                final isSelected = _selectedCatalogId == item.id;
                                return ActionChip(
                                  backgroundColor: isSelected
                                      ? const Color(0xFFCCFBF1)
                                      : const Color(0xFFF1F5F9),
                                  label: Text(
                                    item.name,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isSelected
                                          ? _accentTeal
                                          : const Color(0xFF334155),
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                  onPressed: () => _onCatalogItemSelected(item),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      );
                    },
                    orElse: () => const SizedBox.shrink(),
                  ),

                  // Procedure Name TextField
                  TextField(
                    controller: _procedureNameController,
                    decoration: const InputDecoration(
                      labelText: 'Procedure Name *',
                      hintText: 'e.g. Root Canal Treatment',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Teeth involved chips & input
                  Row(
                    children: [
                      const Icon(Icons.tag, size: 18, color: Color(0xFF64748B)),
                      const SizedBox(width: 6),
                      const Text(
                        'Teeth Involved (FDI Notation)',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      if (_selectedTeeth.isNotEmpty)
                        TextButton(
                          onPressed: () => setState(() => _selectedTeeth.clear()),
                          child: const Text('Clear', style: TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (_selectedTeeth.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: _selectedTeeth.map((tooth) {
                        return Chip(
                          label: Text('Tooth $tooth'),
                          backgroundColor: const Color(0xFFCCFBF1),
                          labelStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _accentTeal,
                          ),
                          deleteIcon: const Icon(Icons.close, size: 14),
                          onDeleted: () {
                            setState(() => _selectedTeeth.remove(tooth));
                          },
                        );
                      }).toList(),
                    )
                  else
                    const Text(
                      'No specific tooth (Whole mouth / General)',
                      style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    ),

                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _teethInputController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            hintText: 'Add tooth # (e.g. 16, 26, 47)',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (val) {
                            final trimmed = val.trim();
                            if (trimmed.isNotEmpty) {
                              setState(() {
                                _selectedTeeth.add(trimmed);
                                _teethInputController.clear();
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: _accentTeal,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.add, size: 18),
                        onPressed: () {
                          final trimmed = _teethInputController.text.trim();
                          if (trimmed.isNotEmpty) {
                            setState(() {
                              _selectedTeeth.add(trimmed);
                              _teethInputController.clear();
                            });
                          }
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Status chips
                  const Text(
                    'Status',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Completed'),
                        selected: _selectedStatus == 'completed',
                        selectedColor: const Color(0xFFDCFCE7),
                        onSelected: (sel) {
                          if (sel) setState(() => _selectedStatus = 'completed');
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('In Progress'),
                        selected: _selectedStatus == 'inProgress',
                        selectedColor: const Color(0xFFFEF08A),
                        onSelected: (sel) {
                          if (sel) setState(() => _selectedStatus = 'inProgress');
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Planned'),
                        selected: _selectedStatus == 'planned',
                        selectedColor: const Color(0xFFE2E8F0),
                        onSelected: (sel) {
                          if (sel) setState(() => _selectedStatus = 'planned');
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Date Row
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(
                            'Date: ${DateFormat('dd MMM yyyy').format(_performedAt)}',
                            style: const TextStyle(fontSize: 13),
                          ),
                          onPressed: _pickDate,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Optional Visit Link
                  visitsAsync.maybeWhen(
                    data: (visits) {
                      if (visits.isEmpty) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DropdownButtonFormField<String?>(
                            initialValue: _selectedVisitId,
                            decoration: const InputDecoration(
                              labelText: 'Link to Appointment Visit (Optional)',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('No linked visit'),
                              ),
                              ...visits.map((v) => DropdownMenuItem<String?>(
                                    value: v.id,
                                    child: Text(
                                      '${DateFormat('dd MMM yyyy').format(v.scheduledStart)} — ${v.address.isNotEmpty ? v.address : 'Visit'}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )),
                            ],
                            onChanged: (val) {
                              setState(() => _selectedVisitId = val);
                            },
                          ),
                          const SizedBox(height: 16),
                        ],
                      );
                    },
                    orElse: () => const SizedBox.shrink(),
                  ),

                  // Notes TextField
                  TextField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Clinical Notes',
                      hintText: 'Diagnosis, pulp status, prep details...',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Materials used TextField
                  TextField(
                    controller: _materialsController,
                    decoration: const InputDecoration(
                      labelText: 'Materials Used (Optional)',
                      hintText: 'e.g. Composite shade A2, Gutta-percha 25 0.04...',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Phase 3: Chairside Consumable Stock Deduction
                  inventoryAsync.maybeWhen(
                    data: (items) {
                      final dentalItems = items.where((i) {
                        if (!i.isActive) return false;
                        final cat = i.category.toLowerCase();
                        return cat.contains('dental') ||
                            cat == 'consumable' ||
                            cat == 'restorative' ||
                            cat == 'anesthetic';
                      }).toList();

                      if (dentalItems.isEmpty) return const SizedBox.shrink();

                      final selectedItem = dentalItems.cast<MedicineModel?>().firstWhere(
                            (i) => i?.id == _selectedConsumableId,
                            orElse: () => null,
                          );

                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.inventory_2_outlined, size: 16, color: _accentTeal),
                                SizedBox(width: 6),
                                Text(
                                  'Deduct Consumable (Chairside)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String?>(
                              initialValue: _selectedConsumableId,
                              decoration: const InputDecoration(
                                labelText: 'Select Consumable (Optional)',
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('None (no inventory deduction)'),
                                ),
                                ...dentalItems.map((item) {
                                  return DropdownMenuItem<String?>(
                                    value: item.id,
                                    child: Text(
                                      '${item.name} (${item.currentStock} ${item.unit} left)',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }),
                              ],
                              onChanged: (val) {
                                setState(() => _selectedConsumableId = val);
                              },
                            ),
                            if (selectedItem != null) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  if (selectedItem.isLowStock)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFEE2E2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.warning_amber_rounded, size: 12, color: Color(0xFF991B1B)),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Low: ${selectedItem.currentStock} ${selectedItem.unit}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF991B1B),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    Text(
                                      'In Stock: ${selectedItem.currentStock} ${selectedItem.unit}',
                                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                    ),
                                  const Spacer(),
                                  const Text(
                                    'Deduct: ',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                                    color: Colors.redAccent,
                                    onPressed: _deductQuantity > 1
                                        ? () => setState(() => _deductQuantity--)
                                        : null,
                                  ),
                                  Text(
                                    '$_deductQuantity',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline, size: 20),
                                    color: _accentTeal,
                                    onPressed: () => setState(() => _deductQuantity++),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                    orElse: () => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),

            // Save button
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _accentTeal,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _saveProcedure,
                child: const Text(
                  'Save Procedure Log',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
