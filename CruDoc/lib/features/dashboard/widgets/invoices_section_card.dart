import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/revenue/data/models/invoice_model.dart';
import 'package:doctor_management_app/features/revenue/repo/invoice_repo.dart';

class InvoicesSectionCard extends StatefulWidget {
  const InvoicesSectionCard({super.key});

  @override
  State<InvoicesSectionCard> createState() => _InvoicesSectionCardState();
}

class _InvoicesSectionCardState extends State<InvoicesSectionCard> {
  final InvoiceRepository _repository = InvoiceRepository();
  String _selectedFilter = 'All'; // 'All', 'Paid', 'Pending'

  void _openCreateInvoiceSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _CreateInvoiceSheet(
        onSave: (name, service, amount, status, notes) async {
          await _repository.createInvoice(
            patientName: name,
            service: service,
            amount: amount,
            status: status,
            notes: notes,
          );
        },
      ),
    );
  }

  void _showInvoiceDetails(BuildContext context, InvoiceModel invoice) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _InvoiceDetailsSheet(
        invoice: invoice,
        onStatusChanged: (newStatus) async {
          await _repository.updateInvoiceStatus(invoice.id, newStatus);
          if (ctx.mounted) Navigator.pop(ctx);
        },
        onDelete: () async {
          await _repository.deleteInvoice(invoice.id);
          if (ctx.mounted) Navigator.pop(ctx);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<InvoiceModel>>(
      stream: _repository.watchInvoices(),
      builder: (context, snapshot) {
        final allInvoices = snapshot.data ?? <InvoiceModel>[];

        final filteredInvoices = allInvoices.where((inv) {
          if (_selectedFilter == 'All') return true;
          return inv.status.toLowerCase() == _selectedFilter.toLowerCase();
        }).toList();

        final totalInvoiced = allInvoices.fold<double>(
            0.0, (sum, item) => sum + item.amount);
        final paidTotal = allInvoices
            .where((i) => i.isPaid)
            .fold<double>(0.0, (sum, item) => sum + item.amount);
        final pendingTotal = allInvoices
            .where((i) => i.isPending)
            .fold<double>(0.0, (sum, item) => sum + item.amount);

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.slateBlue.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      color: AppColors.slateBlue,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Invoices & Receipts',
                          style: AppColors.sectionHeading,
                        ),
                        Text(
                          '${allInvoices.length} total invoices',
                          style: AppColors.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => _openCreateInvoiceSheet(context),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.slateBlue,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, color: Colors.white, size: 16),
                          SizedBox(width: 4),
                          Text(
                            'Create',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Metrics Row
              Row(
                children: [
                  Expanded(
                    child: _SummaryMetricPill(
                      label: 'Total',
                      amount: '₹${totalInvoiced.toInt()}',
                      color: AppColors.slateBlue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SummaryMetricPill(
                      label: 'Paid',
                      amount: '₹${paidTotal.toInt()}',
                      color: const Color(0xFF10B981),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SummaryMetricPill(
                      label: 'Pending',
                      amount: '₹${pendingTotal.toInt()}',
                      color: const Color(0xFFF59E0B),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Filter Tabs
              Row(
                children: ['All', 'Paid', 'Pending'].map((filter) {
                  final isSelected = _selectedFilter == filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                        filter,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected
                              ? AppColors.slateBlue
                              : AppColors.textSecondary,
                        ),
                      ),
                      selected: isSelected,
                      selectedColor:
                          AppColors.slateBlue.withValues(alpha: 0.15),
                      backgroundColor: Colors.transparent,
                      side: BorderSide(
                        color: isSelected
                            ? AppColors.slateBlue
                            : Colors.grey.withValues(alpha: 0.3),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      onSelected: (val) {
                        if (val) {
                          setState(() => _selectedFilter = filter);
                        }
                      },
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 12),

              // Invoice Item List
              if (snapshot.connectionState == ConnectionState.waiting &&
                  allInvoices.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.slateBlue,
                    ),
                  ),
                )
              else if (filteredInvoices.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      'No ${_selectedFilter.toLowerCase()} invoices found',
                      style: AppColors.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredInvoices.length > 5
                      ? 5
                      : filteredInvoices.length,
                  separatorBuilder: (_, _) => const Divider(height: 16),
                  itemBuilder: (context, index) {
                    final inv = filteredInvoices[index];
                    return _InvoiceRowItem(
                      invoice: inv,
                      onTap: () => _showInvoiceDetails(context, inv),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SummaryMetricPill extends StatelessWidget {
  final String label;
  final String amount;
  final Color color;

  const _SummaryMetricPill({
    required this.label,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            amount,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceRowItem extends StatelessWidget {
  final InvoiceModel invoice;
  final VoidCallback onTap;

  const _InvoiceRowItem({
    required this.invoice,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isPaid = invoice.isPaid;
    final statusColor = isPaid
        ? const Color(0xFF10B981)
        : (invoice.isOverdue ? const Color(0xFFEF4444) : const Color(0xFFF59E0B));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isPaid ? Icons.check_circle_outline : Icons.pending_actions,
                color: statusColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    invoice.patientName.isEmpty ? 'General Patient' : invoice.patientName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${invoice.id} • ${invoice.service}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${invoice.amount.toInt()}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    invoice.status,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
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

class _CreateInvoiceSheet extends StatefulWidget {
  final Future<void> Function(
    String name,
    String service,
    double amount,
    String status,
    String notes,
  ) onSave;

  const _CreateInvoiceSheet({required this.onSave});

  @override
  State<_CreateInvoiceSheet> createState() => _CreateInvoiceSheetState();
}

class _CreateInvoiceSheetState extends State<_CreateInvoiceSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _serviceController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  String _status = 'Pending';
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _serviceController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    try {
      final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
      await widget.onSave(
        _nameController.text.trim(),
        _serviceController.text.trim(),
        amount,
        _status,
        _notesController.text.trim(),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving invoice: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Create New Invoice', style: AppColors.sectionHeading),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Patient Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (val) =>
                    val == null || val.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _serviceController,
                decoration: const InputDecoration(
                  labelText: 'Service / Treatment',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.medical_services),
                ),
                validator: (val) =>
                    val == null || val.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Amount (₹)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.currency_rupee),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'Required';
                        if (double.tryParse(val.trim()) == null) return 'Invalid';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _status,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                        DropdownMenuItem(value: 'Paid', child: Text('Paid')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _status = val);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (Optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.note),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.slateBlue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Save Invoice',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InvoiceDetailsSheet extends StatelessWidget {
  final InvoiceModel invoice;
  final Function(String newStatus) onStatusChanged;
  final VoidCallback onDelete;

  const _InvoiceDetailsSheet({
    required this.invoice,
    required this.onStatusChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM dd, yyyy');

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(invoice.id, style: AppColors.sectionHeading),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: onDelete,
              ),
            ],
          ),
          const Divider(),
          const SizedBox(height: 8),
          _detailRow('Patient', invoice.patientName),
          _detailRow('Service', invoice.service),
          _detailRow('Amount', '₹${invoice.amount.toInt()}'),
          _detailRow('Date', dateFormat.format(invoice.date)),
          _detailRow('Status', invoice.status),
          if (invoice.notes.isNotEmpty) _detailRow('Notes', invoice.notes),
          const SizedBox(height: 20),
          if (!invoice.isPaid)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => onStatusChanged('Paid'),
                icon: const Icon(Icons.check_circle, color: Colors.white),
                label: const Text('Mark as Paid'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _detailRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(color: AppColors.textSecondary)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
