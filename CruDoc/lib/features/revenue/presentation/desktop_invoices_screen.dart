import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:doctor_management_app/features/revenue/data/models/invoice_model.dart';
import 'package:doctor_management_app/features/revenue/repo/invoice_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/repo/patient_repository.dart';
import 'package:doctor_management_app/features/shell/components/shell_background.dart';

/// Desktop version of the Invoices tab.
///
/// A fully realized, desktop-native invoice management dashboard.
/// Features stat cards, a DataTable for seamless viewing, and
/// interactive dialogs for creating and managing invoices.
/// Wrapped in a centered container to respect the side navigation.
class DesktopInvoicesScreen extends StatefulWidget {
  const DesktopInvoicesScreen({super.key});

  @override
  State<DesktopInvoicesScreen> createState() => _DesktopInvoicesScreenState();
}

class _DesktopInvoicesScreenState extends State<DesktopInvoicesScreen> {
  final InvoiceRepository _repository = InvoiceRepository();
  final TextEditingController _searchController = TextEditingController();

  String _selectedFilter = 'All'; // 'All', 'Paid', 'Pending', 'Overdue'
  String _searchQuery = '';

  bool _isSeeding = false;

  Future<void> _seedSampleInvoicesToFirebase() async {
    setState(() => _isSeeding = true);
    try {
      final samples = [
        {
          'patientName': 'Gargi Mhatre',
          'service': 'fever',
          'amount': 200.0,
          'status': 'Paid',
          'notes': 'Initial visit billing',
          'dueDate': DateTime(2026, 8, 18),
        },
        {
          'patientName': 'Nidhi Parab',
          'service': 'Clinical Services',
          'amount': 0.0,
          'status': 'Paid',
          'notes': 'Follow up consultation',
          'dueDate': DateTime(2026, 8, 18),
        },
        {
          'patientName': 'Nidhi Parab',
          'service': 'fever',
          'amount': 333.0,
          'status': 'Paid',
          'notes': 'Medicine & Diagnostics',
          'dueDate': DateTime(2026, 8, 18),
        },
      ];

      for (final s in samples) {
        await _repository.createInvoice(
          patientName: s['patientName'] as String,
          service: s['service'] as String,
          amount: s['amount'] as double,
          status: s['status'] as String,
          notes: s['notes'] as String,
          dueDate: s['dueDate'] as DateTime,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Real invoices populated in Firebase database!'),
            backgroundColor: Color(0xFF16A34A),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error seeding Firebase: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSeeding = false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openCreateInvoiceDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 800),
          child: _CreateInvoiceDialog(
            onSave: (name, service, amount, status, notes, dueDate, patientId) async {
              await _repository.createInvoice(
                patientName: name,
                service: service,
                amount: amount,
                status: status,
                notes: notes,
                dueDate: dueDate,
                patientId: patientId,
              );
            },
          ),
        ),
      ),
    );
  }

  void _showInvoiceDetails(InvoiceModel invoice) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: _InvoiceDetailsDialog(
            invoice: invoice,
            onStatusChanged: (newStatus) async {
              if (invoice.doctorId != 'sample') {
                await _repository.updateInvoiceStatus(invoice.id, newStatus);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            onDelete: () async {
              if (invoice.doctorId != 'sample') {
                await _repository.deleteInvoice(invoice.id);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: ShellBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: StreamBuilder<List<InvoiceModel>>(
                stream: _repository.watchInvoices(),
                builder: (context, snapshot) {
                  final allInvoices = snapshot.data ?? <InvoiceModel>[];

                  final filteredInvoices = allInvoices.where((inv) {
                    final matchesStatus = _selectedFilter == 'All' ||
                        inv.status.toLowerCase() == _selectedFilter.toLowerCase();
                    final query = _searchQuery.toLowerCase().trim();
                    final matchesSearch = query.isEmpty ||
                        inv.patientName.toLowerCase().contains(query) ||
                        inv.service.toLowerCase().contains(query) ||
                        inv.id.toLowerCase().contains(query);

                    return matchesStatus && matchesSearch;
                  }).toList();

                  final totalInvoiced = allInvoices.fold<double>(
                      0.0, (sum, item) => sum + item.amount);
                  final paidTotal = allInvoices
                      .where((i) => i.isPaid)
                      .fold<double>(0.0, (sum, item) => sum + item.amount);
                  final pendingTotal = allInvoices
                      .where((i) => i.isPending)
                      .fold<double>(0.0, (sum, item) => sum + item.amount);
                  final overdueTotal = allInvoices
                      .where((i) => i.isOverdue)
                      .fold<double>(0.0, (sum, item) => sum + item.amount);

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- Desktop Header ---
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Invoices & Billing',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _isSeeding ? null : _seedSampleInvoicesToFirebase,
                                  icon: _isSeeding
                                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Icon(Icons.cloud_upload_outlined, size: 16),
                                  label: Text(_isSeeding ? 'Saving...' : 'Seed Data'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF2563EB),
                                    side: const BorderSide(color: Color(0xFF2563EB)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  onPressed: _openCreateInvoiceDialog,
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                  label: const Text('New Invoice'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2563EB),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // --- Stats Row ---
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            children: [
                              _MetricCard(
                                icon: Icons.receipt_long_rounded,
                                iconColor: const Color(0xFF2563EB),
                                iconBg: const Color(0xFFEFF6FF),
                                title: 'Total Invoiced',
                                amount: '₹${totalInvoiced.toInt()}',
                              ),
                              const SizedBox(width: 12),
                              _MetricCard(
                                icon: Icons.check_circle_rounded,
                                iconColor: const Color(0xFF16A34A),
                                iconBg: const Color(0xFFDCFCE7),
                                title: 'Paid Invoices',
                                amount: '₹${paidTotal.toInt()}',
                              ),
                              const SizedBox(width: 12),
                              _MetricCard(
                                icon: Icons.hourglass_top_rounded,
                                iconColor: const Color(0xFFD97706),
                                iconBg: const Color(0xFFFEF3C7),
                                title: 'Pending',
                                amount: '₹${pendingTotal.toInt()}',
                              ),
                              const SizedBox(width: 12),
                              _MetricCard(
                                icon: Icons.warning_amber_rounded,
                                iconColor: const Color(0xFFDC2626),
                                iconBg: const Color(0xFFFEE2E2),
                                title: 'Overdue',
                                amount: '₹${overdueTotal.toInt()}',
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // --- Toolbar: Search & Filters ---
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final bool isWide = constraints.maxWidth > 700;
                              return Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 16,
                                runSpacing: 16,
                                children: [
                                  // Search Bar
                                  Container(
                                    width: isWide ? 300 : 200,
                                    height: 40,
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.search_rounded, size: 18, color: Color(0xFF64748B)),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: TextField(
                                            controller: _searchController,
                                            onChanged: (val) => setState(() => _searchQuery = _repository.sanitizeInput(val)),
                                            decoration: const InputDecoration(
                                              hintText: 'Search invoices...',
                                              border: InputBorder.none,
                                              hintStyle: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                                            ),
                                          ),
                                        ),
                                        if (_searchController.text.isNotEmpty)
                                          IconButton(
                                            icon: const Icon(Icons.clear, size: 16, color: Color(0xFF64748B)),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                            onPressed: () {
                                              setState(() {
                                                _searchController.clear();
                                                _searchQuery = '';
                                              });
                                            },
                                          ),
                                      ],
                                    ),
                                  ),

                                  // Filter Pills
                                  Wrap(
                                    spacing: 8,
                                    children: ['All', 'Paid', 'Pending', 'Overdue'].map((filter) {
                                      final isSelected = _selectedFilter == filter;
                                      return InkWell(
                                        onTap: () => setState(() => _selectedFilter = filter),
                                        borderRadius: BorderRadius.circular(10),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: isSelected ? const Color(0xFF2563EB) : Colors.white,
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0)),
                                          ),
                                          child: Text(
                                            filter,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600,
                                              color: isSelected ? Colors.white : const Color(0xFF475569),
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),

                        const SizedBox(height: 16),

                        // --- Data Table Card ---
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: filteredInvoices.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.receipt_long_outlined, size: 48, color: Color(0xFFCBD5E1)),
                                        const SizedBox(height: 12),
                                        Text('No ${_selectedFilter.toLowerCase()} invoices found', style: const TextStyle(color: Color(0xFF64748B), fontSize: 15)),
                                      ],
                                    ),
                                  )
                                : SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: SingleChildScrollView(
                                      child: DataTable(
                                        headingRowColor: MaterialStateProperty.all(const Color(0xFFF8FAFC)),
                                        headingTextStyle: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF64748B), fontSize: 12),
                                        dataRowHeight: 68,
                                        columnSpacing: 24,
                                        horizontalMargin: 16,
                                        columns: const [
                                          DataColumn(label: Text('INVOICE ID')),
                                          DataColumn(label: Text('PATIENT')),
                                          DataColumn(label: Text('SERVICE')),
                                          DataColumn(label: Text('AMOUNT')),
                                          DataColumn(label: Text('DATE')),
                                          DataColumn(label: Text('STATUS')),
                                          DataColumn(label: Text(''), numeric: true),
                                        ],
                                        rows: filteredInvoices.map((inv) {
                                          final isPaid = inv.isPaid;
                                          final isPending = inv.isPending;
                                          final statusBg = isPaid
                                              ? const Color(0xFFDCFCE7)
                                              : (isPending ? const Color(0xFFFEF3C7) : const Color(0xFFFEE2E2));
                                          final statusText = isPaid
                                              ? const Color(0xFF15803D)
                                              : (isPending ? const Color(0xFFB45309) : const Color(0xFFB91C1C));

                                          return DataRow(
                                            onSelectChanged: (_) => _showInvoiceDetails(inv),
                                            cells: [
                                              DataCell(Text(inv.id, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF0F172A)))),
                                              DataCell(Text(inv.patientName.isEmpty ? 'General Patient' : inv.patientName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF334155)))),
                                              DataCell(Text(inv.service, style: const TextStyle(fontSize: 13, color: Color(0xFF475569)))),
                                              DataCell(Text('₹${inv.amount.toInt()}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF0F172A)))),
                                              DataCell(Text(DateFormat('MMM dd, yyyy').format(inv.date), style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)))),
                                              DataCell(
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                  decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(20)),
                                                  child: Text(inv.status, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: statusText)),
                                                ),
                                              ),
                                              DataCell(
                                                IconButton(
                                                  icon: const Icon(Icons.visibility_outlined, size: 20, color: Color(0xFF64748B)),
                                                  onPressed: () => _showInvoiceDetails(inv),
                                                  tooltip: 'View Details',
                                                ),
                                              ),
                                            ],
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==============================================================================
// WIDGET COMPONENTS (Adapted from Original Code)
// ==============================================================================

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String amount;

  const _MetricCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.amount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: iconColor, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF64748B))),
          const SizedBox(height: 2),
          Text(amount, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
        ],
      ),
    );
  }
}

// ==============================================================================
// CREATE INVOICE DIALOG (Desktop Optimized)
// ==============================================================================

class _CreateInvoiceDialog extends StatefulWidget {
  final Future<void> Function(
    String name,
    String service,
    double amount,
    String status,
    String notes,
    DateTime? dueDate,
    String? patientId,
  ) onSave;

  const _CreateInvoiceDialog({required this.onSave, super.key});

  @override
  State<_CreateInvoiceDialog> createState() => _CreateInvoiceDialogState();
}

class _TreatmentItem {
  final String name;
  final double price;
  _TreatmentItem({required this.name, required this.price});
}

class _MedicineItem {
  final String name;
  final String dosage;
  final double price;
  _MedicineItem({required this.name, required this.dosage, required this.price});
}

class _CreateInvoiceDialogState extends State<_CreateInvoiceDialog> {
  final _formKey = GlobalKey<FormState>();
  final PatientRepository _patientRepository = PatientRepository();

  // Patient & Header Controllers
  final _patientController = TextEditingController();
  final _clinicalNotesController = TextEditingController();

  // Search autocomplete state
  String _patientQuery = '';
  bool _showSuggestions = false;
  Patient? _selectedPatient;

  // Treatment Controllers
  final _treatmentNameController = TextEditingController();
  final _treatmentPriceController = TextEditingController();

  // Medicine Controllers
  final _medicineNameController = TextEditingController();
  final _dosageController = TextEditingController();
  final _medicinePriceController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();

  bool _showClinicalNotes = false;
  bool _isSubmitting = false;

  final List<_TreatmentItem> _treatments = [];
  final List<_MedicineItem> _medicines = [];

  String _doctorName = 'Dr. Smit';

  @override
  void initState() {
    super.initState();
    _loadDoctorName();
  }

  Future<void> _loadDoctorName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    String? resolvedName;

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final candidate = (data['fullName'] ?? data['full_name'] ?? data['doctorName'] ?? data['doctor_name'] ?? data['name'] ?? data['displayName'] ?? data['userName']) as String?;
        if (candidate != null && candidate.trim().isNotEmpty && candidate.trim().toLowerCase() != 'doctor') {
          resolvedName = candidate.trim();
        } else {
          final fn = (data['firstName'] ?? data['first_name']) as String?;
          final ln = (data['lastName'] ?? data['last_name']) as String?;
          if (fn != null && fn.trim().isNotEmpty && fn.trim().toLowerCase() != 'doctor') {
            resolvedName = ln != null && ln.trim().isNotEmpty ? '${fn.trim()} ${ln.trim()}' : fn.trim();
          }
        }
      }

      if (resolvedName == null && user.email != null && user.email!.trim().isNotEmpty) {
        final emailQ = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: user.email!.trim().toLowerCase()).get();
        if (emailQ.docs.isNotEmpty) {
          final data = emailQ.docs.first.data();
          final candidate = (data['fullName'] ?? data['full_name'] ?? data['doctorName'] ?? data['doctor_name'] ?? data['name'] ?? data['displayName']) as String?;
          if (candidate != null && candidate.trim().isNotEmpty && candidate.trim().toLowerCase() != 'doctor') {
            resolvedName = candidate.trim();
          }
        }
      }
    } catch (_) {}

    if (resolvedName == null && user.displayName != null && user.displayName!.trim().isNotEmpty && user.displayName!.trim().toLowerCase() != 'doctor') {
      resolvedName = user.displayName!.trim();
    }

    if (resolvedName == null && user.email != null && user.email!.trim().isNotEmpty) {
      final rawName = user.email!.split('@').first;
      final cleanHandle = rawName.replaceAll(RegExp(r'\d+$'), '');
      final parts = cleanHandle.split(RegExp(r'[._-]')).where((p) => p.isNotEmpty);
      if (parts.isNotEmpty) {
        final formatted = parts.map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase()).join(' ');
        if (formatted.toLowerCase() != 'doctor') {
          resolvedName = formatted;
        }
      }
    }

    resolvedName ??= 'Smit';
    final finalDoctorTitle = resolvedName.toLowerCase().startsWith('dr') ? resolvedName : 'Dr. $resolvedName';

    if (mounted) setState(() => _doctorName = finalDoctorTitle);
  }

  double get _calculatedTotal {
    double tTotal = _treatments.fold(0.0, (sum, item) => sum + item.price);
    double mTotal = _medicines.fold(0.0, (sum, item) => sum + item.price);
    return tTotal + mTotal;
  }

  @override
  void dispose() {
    _patientController.dispose();
    _clinicalNotesController.dispose();
    _treatmentNameController.dispose();
    _treatmentPriceController.dispose();
    _medicineNameController.dispose();
    _dosageController.dispose();
    _medicinePriceController.dispose();
    super.dispose();
  }

  void _addTreatment() {
    final name = _treatmentNameController.text.trim();
    final priceStr = _treatmentPriceController.text.trim();
    if (name.isEmpty) return;
    final price = double.tryParse(priceStr) ?? 0.0;
    setState(() {
      _treatments.add(_TreatmentItem(name: name, price: price));
      _treatmentNameController.clear();
      _treatmentPriceController.clear();
    });
  }

  void _addMedicine() {
    final name = _medicineNameController.text.trim();
    final dosage = _dosageController.text.trim();
    final priceStr = _medicinePriceController.text.trim();
    if (name.isEmpty) return;
    final price = double.tryParse(priceStr) ?? 0.0;
    setState(() {
      _medicines.add(_MedicineItem(name: name, dosage: dosage, price: price));
      _medicineNameController.clear();
      _dosageController.clear();
      _medicinePriceController.clear();
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _selectedTime);
    if (picked != null) setState(() => _selectedTime = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    try {
      final patientName = _patientController.text.trim();
      final totalAmount = _calculatedTotal;
      final List<String> servicesList = [];
      if (_treatments.isNotEmpty) servicesList.add('Treatments: ${_treatments.map((t) => t.name).join(", ")}');
      if (_medicines.isNotEmpty) servicesList.add('Medicines: ${_medicines.map((m) => m.name).join(", ")}');
      final serviceSummary = servicesList.isNotEmpty ? servicesList.join(' | ') : 'Consultation & Services';
      final notes = _clinicalNotesController.text.trim();

      // Single-line call ensures the LSP doesn't break on parentheses
      await widget.onSave(patientName, serviceSummary, totalAmount, 'Paid', notes, _selectedDate, _selectedPatient?.id);

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error generating invoice: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF2563EB);
    final dateFormat = DateFormat('dd/MM/yyyy');

    return Container(
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Transparent Header (formerly blue)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.medical_services_rounded, color: primaryBlue, size: 24),
                const SizedBox(width: 8),
                const Text('cru.doc', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: primaryBlue, letterSpacing: -0.5)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close, color: primaryBlue, size: 22), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),

          // 2. Scrollable Body
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date, Time & Doctor
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: InkWell(
                                onTap: _pickDate,
                                child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFCBD5E1))), child: Row(
                                  children: [Text(dateFormat.format(_selectedDate), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))), const Spacer(), const Icon(Icons.calendar_today_outlined, size: 16, color: Color(0xFF64748B))],
                                )),
                              )),
                              const SizedBox(width: 10),
                              Expanded(child: InkWell(
                                onTap: _pickTime,
                                child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFCBD5E1))), child: Row(
                                  children: [Text(_selectedTime.format(context), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))), const Spacer(), const Icon(Icons.access_time, size: 16, color: Color(0xFF64748B))],
                                )),
                              )),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text('Doctor: $_doctorName', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF334155))),
                          const SizedBox(height: 10),
                          // Patient search
                          StreamBuilder<List<Patient>>(
                            stream: _patientRepository.watchPatients(),
                            builder: (context, snapshot) {
                              final allPatients = snapshot.data ?? <Patient>[];
                              final query = _patientQuery.toLowerCase().trim();
                              final suggestions = query.isEmpty ? <Patient>[] : allPatients.where((p) => p.fullName.toLowerCase().contains(query) || p.phone.toLowerCase().contains(query)).toList();
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  TextFormField(
                                    controller: _patientController,
                                    onChanged: (val) { setState(() { _patientQuery = val; _showSuggestions = true; _selectedPatient = null; }); },
                                    decoration: InputDecoration(
                                      hintText: 'Search Existing Patient or Add New Name',
                                      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                                      prefixIcon: const Icon(Icons.person_search_outlined, size: 20, color: Color(0xFF64748B)),
                                      suffixIcon: _patientController.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { setState(() { _patientController.clear(); _patientQuery = ''; _showSuggestions = false; _selectedPatient = null; }); }) : null,
                                      filled: true,
                                      fillColor: Colors.white,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                    ),
                                    validator: (val) => val == null || val.trim().isEmpty ? 'Please enter patient name' : null,
                                  ),
                                  if (_showSuggestions && suggestions.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Container(
                                      constraints: const BoxConstraints(maxHeight: 180),
                                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFCBD5E1)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 4))]),
                                      child: ListView.separated(
                                        shrinkWrap: true,
                                        itemCount: suggestions.length > 5 ? 5 : suggestions.length,
                                        separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                        itemBuilder: (context, index) {
                                          final p = suggestions[index];
                                          return InkWell(
                                            onTap: () {
                                              setState(() {
                                                _patientController.text = p.fullName;
                                                _selectedPatient = p;
                                                _showSuggestions = false;
                                                _patientQuery = p.fullName;
                                                if (p.notes.isNotEmpty) { _clinicalNotesController.text = p.notes; _showClinicalNotes = true; }
                                              });
                                            },
                                            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Row(children: [
                                              CircleAvatar(radius: 14, backgroundColor: const Color(0xFFEFF6FF), child: Text(p.firstName.isNotEmpty ? p.firstName[0].toUpperCase() : 'P', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF2563EB)))),
                                              const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(p.fullName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))), Text('${p.gender} • ${p.phone.isEmpty ? "No phone" : p.phone}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)))])),
                                              const Icon(Icons.north_west_rounded, size: 14, color: Color(0xFF94A3B8)),
                                            ])),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Clinical Notes
                    Container(
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE2E8F0))),
                      child: Column(children: [
                        InkWell(
                          onTap: () => setState(() => _showClinicalNotes = !_showClinicalNotes),
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), child: Row(children: [const Text('Clinical Notes:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))), const Spacer(), Icon(_showClinicalNotes ? Icons.remove : Icons.add, size: 20, color: const Color(0xFF334155))])),
                        ),
                        if (_showClinicalNotes) Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 14), child: TextFormField(controller: _clinicalNotesController, maxLines: 2, decoration: const InputDecoration(hintText: 'Enter patient observations, diagnosis, or clinical notes...', hintStyle: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)), border: OutlineInputBorder()))),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    // Treatments
                    Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE2E8F0))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Treatment:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(flex: 3, child: TextFormField(controller: _treatmentNameController, decoration: const InputDecoration(hintText: 'Treatment (e.g. Followup Consulta...)', hintStyle: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8), border: OutlineInputBorder()))),
                        const SizedBox(width: 8),
                        Expanded(flex: 2, child: TextFormField(controller: _treatmentPriceController, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'Price (₹)', hintStyle: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8), border: OutlineInputBorder()))),
                        const SizedBox(width: 8),
                        ElevatedButton(onPressed: _addTreatment, style: ElevatedButton.styleFrom(backgroundColor: primaryBlue, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)), child: const Text('Add', style: TextStyle(fontWeight: FontWeight.w700))),
                      ]),
                      if (_treatments.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Column(children: _treatments.map((item) => Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(8)), child: Row(children: [Text(item.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)), const Spacer(), Text('₹${item.price.toInt()}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: primaryBlue)), const SizedBox(width: 6), InkWell(onTap: () => setState(() => _treatments.remove(item)), child: const Icon(Icons.close, size: 16, color: Colors.red))]))).toList()),
                      ],
                    ])),
                    const SizedBox(height: 14),
                    // Medicines
                    Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE2E8F0))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Medicine:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(flex: 3, child: TextFormField(controller: _medicineNameController, decoration: const InputDecoration(hintText: 'Medicine (e.g. Tab Ran...)', hintStyle: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8), border: OutlineInputBorder()))),
                        const SizedBox(width: 6),
                        Expanded(flex: 2, child: TextFormField(controller: _dosageController, decoration: const InputDecoration(hintText: 'Dosage (e.g. 1-0-1)', hintStyle: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8), border: OutlineInputBorder()))),
                        const SizedBox(width: 6),
                        Expanded(flex: 2, child: TextFormField(controller: _medicinePriceController, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'Price (₹)', hintStyle: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8), border: OutlineInputBorder()))),
                        const SizedBox(width: 6),
                        ElevatedButton(onPressed: _addMedicine, style: ElevatedButton.styleFrom(backgroundColor: primaryBlue, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)), child: const Text('Add', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                      ]),
                      if (_medicines.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Column(children: _medicines.map((item) => Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(8)), child: Row(children: [Text(item.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)), if (item.dosage.isNotEmpty) Text(' (${item.dosage})', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))), const Spacer(), Text('₹${item.price.toInt()}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF16A34A))), const SizedBox(width: 6), InkWell(onTap: () => setState(() => _medicines.remove(item)), child: const Icon(Icons.close, size: 16, color: Colors.red))]))).toList()),
                      ],
                    ])),
                    const SizedBox(height: 20),
                    // Total Calculation Banner
                    Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(12), border: Border.all(color: primaryBlue.withOpacity(0.3))), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Calculated Total Amount:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1E3A8A))), Text('₹${_calculatedTotal.toInt()}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: primaryBlue))])),
                    const SizedBox(height: 20),
                    // Action Buttons - CLEANED UP PARENTHESES
                    Column(
                      children: [
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF2563EB).withOpacity(0.35),
                                blurRadius: 14,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _isSubmitting ? null : _submit,
                              borderRadius: BorderRadius.circular(14),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (_isSubmitting)
                                      const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    else
                                      const Icon(
                                        Icons.receipt_long_rounded,
                                        size: 20,
                                        color: Colors.white,
                                      ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _isSubmitting
                                          ? 'Generating & Saving Invoice...'
                                          : 'Generate & Save Invoice',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==============================================================================
// INVOICE DETAILS DIALOG (Desktop Optimized)
// ==============================================================================

class _InvoiceDetailsDialog extends StatelessWidget {
  final InvoiceModel invoice;
  final Function(String newStatus) onStatusChanged;
  final VoidCallback onDelete;

  const _InvoiceDetailsDialog({
    required this.invoice,
    required this.onStatusChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM dd, yyyy');

    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(invoice.id, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
              IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: onDelete),
            ],
          ),
          const Divider(),
          const SizedBox(height: 8),
          _detailRow('Patient Name', invoice.patientName),
          _detailRow('Service / Description', invoice.service),
          _detailRow('Amount Charged', '₹${invoice.amount.toInt()}'),
          _detailRow('Date Created', dateFormat.format(invoice.date)),
          if (invoice.dueDate != null) _detailRow('Due Date', dateFormat.format(invoice.dueDate!)),
          _detailRow('Current Status', invoice.status),
          if (invoice.notes.isNotEmpty) _detailRow('Notes', invoice.notes),
          const SizedBox(height: 20),
          if (!invoice.isPaid)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => onStatusChanged('Paid'),
                icon: const Icon(Icons.check_circle, color: Colors.white),
                label: const Text('Mark as Paid'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
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
          Text(title, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
        ],
      ),
    );
  }
}