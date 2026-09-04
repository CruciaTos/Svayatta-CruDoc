import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:doctor_management_app/features/revenue/data/models/invoice_model.dart';
import 'package:doctor_management_app/features/revenue/data/services/invoice_local_service.dart';
import '../../data/models/treatment_plan_line_item_model.dart';
import '../../data/models/dental_procedure_catalog_model.dart';
import '../providers/dental_providers.dart';

const Color _accentTeal = Color(0xFF0D9488);

/// Treatment Plan and Quote Management Sheet.
///
/// Allows dentists to draft multi-procedure quotes, reorder, adjust prices,
/// and convert accepted treatment items into an official CruDoc Invoice.
class DentalTreatmentPlanSheet extends ConsumerStatefulWidget {
  final String patientId;
  final String patientName;

  const DentalTreatmentPlanSheet({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  @override
  ConsumerState<DentalTreatmentPlanSheet> createState() =>
      _DentalTreatmentPlanSheetState();
}

class _DentalTreatmentPlanSheetState
    extends ConsumerState<DentalTreatmentPlanSheet> {
  String get _currentDoctorId =>
      FirebaseAuth.instance.currentUser?.uid ?? 'doc_dental';

  Future<void> _addItemDialog({TreatmentPlanLineItemModel? existing}) async {
    final catalogAsync = ref.read(dentalCatalogProvider(_currentDoctorId));
    final catalog = catalogAsync.maybeWhen(data: (l) => l, orElse: () => <DentalProcedureCatalogModel>[]);

    final nameController = TextEditingController(text: existing?.procedureName ?? '');
    final priceController = TextEditingController(
      text: existing?.estimatedPrice != null ? existing!.estimatedPrice.toStringAsFixed(0) : '',
    );
    final teethController = TextEditingController(
      text: existing?.toothNumbers.join(', ') ?? '',
    );
    String? selectedCatalogId = existing?.procedureCatalogId;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(existing == null ? 'Add Treatment Item' : 'Edit Treatment Item'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (catalog.isNotEmpty) ...[
                      DropdownButtonFormField<String?>(
                        initialValue: selectedCatalogId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'From Catalog (Optional)'),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('Custom Entry')),
                          ...catalog.map((c) => DropdownMenuItem<String?>(
                                value: c.id,
                                child: Text('${c.name} (${c.code})'),
                              )),
                        ],
                        onChanged: (val) {
                          setDialogState(() {
                            selectedCatalogId = val;
                            if (val != null) {
                              final item = catalog.firstWhere((c) => c.id == val);
                              nameController.text = item.name;
                              if (item.defaultPrice != null) {
                                priceController.text = item.defaultPrice!.toStringAsFixed(0);
                              }
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Procedure Name *',
                        hintText: 'e.g. Root Canal Treatment',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: teethController,
                      decoration: const InputDecoration(
                        labelText: 'Teeth (Optional)',
                        hintText: 'e.g. 16, 26',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: priceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Estimated Fee (₹) *',
                        hintText: 'e.g. 4500',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _accentTeal),
                  onPressed: () {
                    if (nameController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Procedure Name is required')),
                      );
                      return;
                    }
                    Navigator.pop(ctx, true);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true) {
      final now = DateTime.now();
      final teethList = teethController.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final price = double.tryParse(priceController.text.trim()) ?? 0.0;

      final item = TreatmentPlanLineItemModel(
        id: existing?.id ?? const Uuid().v4(),
        doctorId: _currentDoctorId,
        patientId: widget.patientId,
        treatmentPlanId: 'tp_${widget.patientId}',
        procedureCatalogId: selectedCatalogId,
        procedureName: nameController.text.trim(),
        toothNumbers: teethList,
        estimatedPrice: price,
        sequence: existing?.sequence ?? 0,
        status: existing?.status ?? 'proposed',
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        syncStatus: 'pending',
      );

      await ref.read(dentalRepositoryProvider).saveTreatmentPlanLineItem(item);
      ref.invalidate(patientTreatmentPlanProvider(widget.patientId));
    }
  }

  Future<void> _updateItemStatus(TreatmentPlanLineItemModel item, String newStatus) async {
    await ref.read(dentalRepositoryProvider).updateTreatmentPlanLineItemStatus(item.id, newStatus);
    ref.invalidate(patientTreatmentPlanProvider(widget.patientId));
  }

  Future<void> _deleteItem(TreatmentPlanLineItemModel item) async {
    await ref.read(dentalRepositoryProvider).deleteTreatmentPlanLineItem(item.id);
    ref.invalidate(patientTreatmentPlanProvider(widget.patientId));
  }

  Future<void> _generateInvoice(List<TreatmentPlanLineItemModel> items) async {
    // Only invoice items that are accepted or proposed and not already invoiced
    final invoiceableItems = items
        .where((i) => (i.status == 'accepted' || i.status == 'proposed'))
        .toList();

    if (invoiceableItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No proposed or accepted treatment items to invoice.')),
      );
      return;
    }

    final totalAmount = invoiceableItems.fold<double>(
      0.0,
      (sum, item) => sum + item.estimatedPrice,
    );

    final serviceDescriptions = invoiceableItems.map((item) {
      if (item.toothNumbers.isNotEmpty) {
        return '${item.procedureName} (Tooth ${item.toothNumbers.join(", ")})';
      }
      return item.procedureName;
    }).join('; ');

    final fullServiceName = 'Dental: $serviceDescriptions';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Generate Invoice'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Patient: ${widget.patientName}'),
            const SizedBox(height: 8),
            Text('Items: ${invoiceableItems.length}'),
            const SizedBox(height: 4),
            Text(
              'Total Amount: ₹${totalAmount.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            Text(
              'Service Summary:\n$fullServiceName',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _accentTeal),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create Invoice'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final now = DateTime.now();
      final invoiceId = 'INV-${now.year}-${now.millisecondsSinceEpoch.toString().substring(7)}';

      final invoice = InvoiceModel(
        id: invoiceId,
        doctorId: _currentDoctorId,
        patientId: widget.patientId,
        patientName: widget.patientName,
        service: fullServiceName,
        amount: totalAmount,
        status: 'Pending',
        date: now,
        notes: 'Generated from Dental Treatment Plan',
        createdAt: now,
        updatedAt: now,
      );

      // Upsert into local SQLite invoices table
      await InvoiceLocalService().upsertInvoice(invoice);

      // Mark treatment plan items as invoiced
      final repo = ref.read(dentalRepositoryProvider);
      for (final item in invoiceableItems) {
        await repo.updateTreatmentPlanLineItemStatus(item.id, 'invoiced');
      }

      ref.invalidate(patientTreatmentPlanProvider(widget.patientId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invoice $invoiceId created successfully (₹${totalAmount.toStringAsFixed(0)})'),
            backgroundColor: _accentTeal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating invoice: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(patientTreatmentPlanProvider(widget.patientId));

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
            // Top Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Treatment Plan & Quote',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        widget.patientName,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Item List
            Expanded(
              child: itemsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(child: Text('Error loading treatment plan: $err')),
                data: (items) {
                  if (items.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.request_quote_outlined, size: 48, color: Color(0xFF94A3B8)),
                          const SizedBox(height: 12),
                          const Text(
                            'No treatment plan items yet',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Add proposed procedures to build a treatment quote.',
                            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: _accentTeal),
                            icon: const Icon(Icons.add),
                            label: const Text('Add Procedure Item'),
                            onPressed: () => _addItemDialog(),
                          ),
                        ],
                      ),
                    );
                  }

                  final totalProposedOrAccepted = items
                      .where((i) => i.status == 'proposed' || i.status == 'accepted')
                      .fold<double>(0.0, (sum, i) => sum + i.estimatedPrice);

                  return Column(
                    children: [
                      // List of items
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: items.length,
                          separatorBuilder: (context, sepIndex) => const Divider(height: 1),
                          itemBuilder: (context, idx) {
                            final item = items[idx];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(vertical: 4),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.procedureName,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        decoration: item.status == 'declined'
                                            ? TextDecoration.lineThrough
                                            : null,
                                        color: item.status == 'declined'
                                            ? Colors.grey
                                            : const Color(0xFF0F172A),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '₹${item.estimatedPrice.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Row(
                                children: [
                                  if (item.toothNumbers.isNotEmpty)
                                    Text(
                                      'Teeth: ${item.toothNumbers.join(", ")} • ',
                                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                    ),
                                  _buildStatusBadge(item.status),
                                ],
                              ),
                              trailing: PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert, size: 20),
                                onSelected: (action) {
                                  if (action == 'edit') {
                                    _addItemDialog(existing: item);
                                  } else if (action == 'delete') {
                                    _deleteItem(item);
                                  } else {
                                    _updateItemStatus(item, action);
                                  }
                                },
                                itemBuilder: (ctx) => [
                                  const PopupMenuItem(value: 'proposed', child: Text('Mark Proposed')),
                                  const PopupMenuItem(value: 'accepted', child: Text('Mark Accepted')),
                                  const PopupMenuItem(value: 'declined', child: Text('Mark Declined')),
                                  const PopupMenuDivider(),
                                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete', style: TextStyle(color: Colors.red)),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),

                      // Quote summary & actions card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          border: Border(top: BorderSide(color: Colors.grey.shade200)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Estimated Quote Total:',
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                ),
                                Text(
                                  '₹${totalProposedOrAccepted.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                    color: _accentTeal,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.add, size: 16),
                                    label: const Text('Add Item'),
                                    onPressed: () => _addItemDialog(),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: FilledButton.icon(
                                    style: FilledButton.styleFrom(backgroundColor: _accentTeal),
                                    icon: const Icon(Icons.receipt_long, size: 16),
                                    label: const Text('Create Invoice'),
                                    onPressed: () => _generateInvoice(items),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color fg;
    switch (status.toLowerCase()) {
      case 'accepted':
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF166534);
        break;
      case 'invoiced':
        bg = const Color(0xFFCCFBF1);
        fg = const Color(0xFF0F766E);
        break;
      case 'declined':
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFF991B1B);
        break;
      case 'proposed':
      default:
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFF92400E);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }
}
