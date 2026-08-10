import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/revenue/data/models/invoice_model.dart';
import 'package:doctor_management_app/features/revenue/repo/invoice_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/repo/patient_repository.dart';
import 'package:doctor_management_app/features/shell/components/shell_background.dart';

class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
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

  void _openCreateInvoiceSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _CreateInvoiceSheet(
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
    );
  }

  void _showInvoiceDetails(InvoiceModel invoice) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _InvoiceDetailsSheet(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return ShellBackground(
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Header Section: Action Bar + Page Title
                  Row(
                    children: [
                      if (Navigator.canPop(context))
                        InkWell(
                          onTap: () => Navigator.pop(context),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x08000000),
                                  blurRadius: 6,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(
                                  Icons.arrow_back_rounded,
                                  size: 18,
                                  color: Color(0xFF0F172A),
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Back',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Invoices & Billing',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Horizontal Metric Cards (4 Cards inspired by Web UI)
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

                  const SizedBox(height: 14),

                  // Search & Create Invoice Section (Compact & Sleek Sizing)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x06000000),
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 36,
                            child: TextField(
                              controller: _searchController,
                              onChanged: (val) {
                                setState(() {
                                  _searchQuery =
                                      _repository.sanitizeInput(val);
                                });
                              },
                              style: const TextStyle(
                                  fontSize: 12.5, color: Color(0xFF0F172A)),
                              decoration: InputDecoration(
                                hintText: 'Search invoice #, patient...',
                                hintStyle: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF94A3B8),
                                ),
                                prefixIcon: const Icon(
                                  Icons.search_rounded,
                                  size: 17,
                                  color: Color(0xFF64748B),
                                ),
                                prefixIconConstraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, size: 15),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 28,
                                          minHeight: 28,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _searchController.clear();
                                            _searchQuery = '';
                                          });
                                        },
                                      )
                                    : null,
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 0,
                                ),
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _openCreateInvoiceSheet,
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF1E78FF),
                                    Color(0xFF1D4ED8)
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x261E78FF),
                                    blurRadius: 6,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.add_rounded,
                                  size: 20,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Filter Pills Row (Shifted below Search Bar Box)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children:
                          ['All', 'Paid', 'Pending', 'Overdue'].map((filter) {
                        final isSelected = _selectedFilter == filter;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: InkWell(
                            onTap: () {
                              setState(() => _selectedFilter = filter);
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF1E78FF)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF1E78FF)
                                      : const Color(0xFFE2E8F0),
                                  width: 1,
                                ),
                                boxShadow: isSelected
                                    ? const [
                                        BoxShadow(
                                          color: Color(0x331E78FF),
                                          blurRadius: 6,
                                          offset: Offset(0, 2),
                                        ),
                                      ]
                                    : const [
                                        BoxShadow(
                                          color: Color(0x06000000),
                                          blurRadius: 4,
                                          offset: Offset(0, 1),
                                        ),
                                      ],
                              ),
                              child: Text(
                                filter,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: isSelected
                                      ? Colors.white
                                      : const Color(0xFF475569),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Table Header / Invoices Section Card (Only This Section Scrolls!)
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          // Column Headers (Matching Web Table Columns)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(16),
                              ),
                            ),
                            child: const Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    'INVOICE & PATIENT',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF64748B),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    'AMOUNT',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF64748B),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    'STATUS',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF64748B),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 36), // Space for action button
                              ],
                            ),
                          ),

                          const Divider(height: 1, color: Color(0xFFE2E8F0)),

                          // Scrollable Rows List
                          Expanded(
                            child: filteredInvoices.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.receipt_long_outlined,
                                          size: 40,
                                          color: Color(0xFFCBD5E1),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'No ${_selectedFilter.toLowerCase()} invoices found in Firebase',
                                          style: const TextStyle(
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        OutlinedButton.icon(
                                          onPressed: _isSeeding
                                              ? null
                                              : _seedSampleInvoicesToFirebase,
                                          icon: _isSeeding
                                              ? const SizedBox(
                                                  width: 14,
                                                  height: 14,
                                                  child:
                                                      CircularProgressIndicator(
                                                          strokeWidth: 2),
                                                )
                                              : const Icon(
                                                  Icons.cloud_upload_outlined,
                                                  size: 16),
                                          label: Text(_isSeeding
                                              ? 'Saving to Firebase...'
                                              : 'Populate Sample Invoices to Firebase'),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor:
                                                const Color(0xFF2563EB),
                                            side: const BorderSide(
                                                color: Color(0xFF2563EB)),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.separated(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    padding: EdgeInsets.zero,
                                    itemCount: filteredInvoices.length,
                                    separatorBuilder: (_, _) => const Divider(
                                      height: 1,
                                      color: Color(0xFFF1F5F9),
                                    ),
                                    itemBuilder: (context, index) {
                                      final inv = filteredInvoices[index];
                                      return _InvoiceTableRow(
                                        invoice: inv,
                                        onViewDetails: () =>
                                            _showInvoiceDetails(inv),
                                      );
                                    },
                                  ),
                          ),
                        ],
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
  );
}
}

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
      width: 140,
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
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            amount,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceTableRow extends StatelessWidget {
  final InvoiceModel invoice;
  final VoidCallback onViewDetails;

  const _InvoiceTableRow({
    required this.invoice,
    required this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    final isPaid = invoice.isPaid;
    final isPending = invoice.isPending;

    final statusBg = isPaid
        ? const Color(0xFFDCFCE7)
        : (isPending ? const Color(0xFFFEF3C7) : const Color(0xFFFEE2E2));

    final statusText = isPaid
        ? const Color(0xFF15803D)
        : (isPending ? const Color(0xFFB45309) : const Color(0xFFB91C1C));

    final dateFormat = DateFormat('MMM dd, yyyy');

    return InkWell(
      onTap: onViewDetails,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // Invoice ID & Patient Info
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    invoice.id,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    invoice.patientName.isEmpty
                        ? 'General Patient'
                        : invoice.patientName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${invoice.service} • ${dateFormat.format(invoice.date)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF94A3B8),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Amount
            Expanded(
              flex: 2,
              child: Text(
                '₹${invoice.amount.toInt()}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),

            // Status Badge (Light green rounded pill for Paid matching image)
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  invoice.status,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusText,
                  ),
                ),
              ),
            ),

            // Actions (Eye Icon)
            IconButton(
              icon: const Icon(
                Icons.visibility_outlined,
                size: 18,
                color: Color(0xFF64748B),
              ),
              onPressed: onViewDetails,
              tooltip: 'View Receipt',
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
    DateTime? dueDate,
    String? patientId,
  ) onSave;

  const _CreateInvoiceSheet({required this.onSave});

  @override
  State<_CreateInvoiceSheet> createState() => _CreateInvoiceSheetState();
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
  _MedicineItem({
    required this.name,
    required this.dosage,
    required this.price,
  });
}

class _CreateInvoiceSheetState extends State<_CreateInvoiceSheet> {
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

    // 1. Try fetching from Firestore users collection under uid
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final candidate = (data['fullName'] ??
            data['full_name'] ??
            data['doctorName'] ??
            data['doctor_name'] ??
            data['name'] ??
            data['displayName'] ??
            data['userName']) as String?;

        if (candidate != null &&
            candidate.trim().isNotEmpty &&
            candidate.trim().toLowerCase() != 'doctor') {
          resolvedName = candidate.trim();
        } else {
          final fn = (data['firstName'] ?? data['first_name']) as String?;
          final ln = (data['lastName'] ?? data['last_name']) as String?;
          if (fn != null &&
              fn.trim().isNotEmpty &&
              fn.trim().toLowerCase() != 'doctor') {
            resolvedName = ln != null && ln.trim().isNotEmpty
                ? '${fn.trim()} ${ln.trim()}'
                : fn.trim();
          }
        }
      }

      // If not found by doc(uid), query users where email == user.email
      if (resolvedName == null &&
          user.email != null &&
          user.email!.trim().isNotEmpty) {
        final emailQ = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: user.email!.trim().toLowerCase())
            .get();
        if (emailQ.docs.isNotEmpty) {
          final data = emailQ.docs.first.data();
          final candidate = (data['fullName'] ??
              data['full_name'] ??
              data['doctorName'] ??
              data['doctor_name'] ??
              data['name'] ??
              data['displayName']) as String?;
          if (candidate != null &&
              candidate.trim().isNotEmpty &&
              candidate.trim().toLowerCase() != 'doctor') {
            resolvedName = candidate.trim();
          }
        }
      }
    } catch (_) {}

    // 2. Try FirebaseAuth currentUser.displayName
    if (resolvedName == null &&
        user.displayName != null &&
        user.displayName!.trim().isNotEmpty &&
        user.displayName!.trim().toLowerCase() != 'doctor') {
      resolvedName = user.displayName!.trim();
    }

    // 3. Try formatting email handle (e.g. smit@gmail.com -> Smit)
    if (resolvedName == null &&
        user.email != null &&
        user.email!.trim().isNotEmpty) {
      final rawName = user.email!.split('@').first;
      final cleanHandle = rawName.replaceAll(RegExp(r'\d+$'), '');
      final parts =
          cleanHandle.split(RegExp(r'[._-]')).where((p) => p.isNotEmpty);
      if (parts.isNotEmpty) {
        final formatted = parts
            .map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase())
            .join(' ');
        if (formatted.toLowerCase() != 'doctor') {
          resolvedName = formatted;
        }
      }
    }

    // Default fallback
    resolvedName ??= 'Smit';

    final finalDoctorTitle = resolvedName.toLowerCase().startsWith('dr')
        ? resolvedName
        : 'Dr. $resolvedName';

    if (mounted) {
      setState(() => _doctorName = finalDoctorTitle);
    }
  }

  double get _calculatedTotal {
    double tTotal =
        _treatments.fold(0.0, (sum, item) => sum + item.price);
    double mTotal =
        _medicines.fold(0.0, (sum, item) => sum + item.price);
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
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    try {
      final patientName = _patientController.text.trim();
      final totalAmount = _calculatedTotal;

      // Construct description summary of treatments & medicines
      final List<String> servicesList = [];
      if (_treatments.isNotEmpty) {
        servicesList.add(
            'Treatments: ${_treatments.map((t) => t.name).join(", ")}');
      }
      if (_medicines.isNotEmpty) {
        servicesList
            .add('Medicines: ${_medicines.map((m) => m.name).join(", ")}');
      }
      final serviceSummary = servicesList.isNotEmpty
          ? servicesList.join(' | ')
          : 'Consultation & Services';

      final notes = _clinicalNotesController.text.trim();

      await widget.onSave(
        patientName,
        serviceSummary,
        totalAmount,
        'Paid', // Default generated status
        notes,
        _selectedDate,
        _selectedPatient?.id,
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating invoice: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF2563EB);
    final dateFormat = DateFormat('dd/MM/yyyy');

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Royal Blue Header Banner (Matching Image Top Bar)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              color: primaryBlue,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.medical_services_rounded,
                  color: Colors.white,
                  size: 24,
                ),
                const SizedBox(width: 8),
                const Text(
                  'cru.doc',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 22),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // 2. Scrollable Form Body
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date, Time & Doctor Card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Date & Time Row
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: _pickDate,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: const Color(0xFFCBD5E1)),
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          dateFormat.format(_selectedDate),
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF0F172A),
                                          ),
                                        ),
                                        const Spacer(),
                                        const Icon(
                                          Icons.calendar_today_outlined,
                                          size: 16,
                                          color: Color(0xFF64748B),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: InkWell(
                                  onTap: _pickTime,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: const Color(0xFFCBD5E1)),
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          _selectedTime.format(context),
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF0F172A),
                                          ),
                                        ),
                                        const Spacer(),
                                        const Icon(
                                          Icons.access_time,
                                          size: 16,
                                          color: Color(0xFF64748B),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          // Doctor Label
                          Text(
                            'Doctor: $_doctorName',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF334155),
                            ),
                          ),

                          const SizedBox(height: 10),

                          // Patient Search Autocomplete Field
                          StreamBuilder<List<Patient>>(
                            stream: _patientRepository.watchPatients(),
                            builder: (context, snapshot) {
                              final allPatients = snapshot.data ?? <Patient>[];
                              final query = _patientQuery.toLowerCase().trim();

                              final suggestions = query.isEmpty
                                  ? <Patient>[]
                                  : allPatients.where((p) {
                                      final nameMatch = p.fullName
                                          .toLowerCase()
                                          .contains(query);
                                      final phoneMatch = p.phone
                                          .toLowerCase()
                                          .contains(query);
                                      return nameMatch || phoneMatch;
                                    }).toList();

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  TextFormField(
                                    controller: _patientController,
                                    onChanged: (val) {
                                      setState(() {
                                        _patientQuery = val;
                                        _showSuggestions = true;
                                        _selectedPatient = null;
                                      });
                                    },
                                    decoration: InputDecoration(
                                      hintText:
                                          'Search Existing Patient or Add New Name',
                                      hintStyle: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF94A3B8),
                                      ),
                                      prefixIcon: const Icon(
                                        Icons.person_search_outlined,
                                        size: 20,
                                        color: Color(0xFF64748B),
                                      ),
                                      suffixIcon: _patientController
                                              .text.isNotEmpty
                                          ? IconButton(
                                              icon: const Icon(Icons.clear,
                                                  size: 18),
                                              onPressed: () {
                                                setState(() {
                                                  _patientController.clear();
                                                  _patientQuery = '';
                                                  _showSuggestions = false;
                                                  _selectedPatient = null;
                                                });
                                              },
                                            )
                                          : null,
                                      filled: true,
                                      fillColor: Colors.white,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: const BorderSide(
                                            color: Color(0xFFCBD5E1)),
                                      ),
                                    ),
                                    validator: (val) =>
                                        val == null || val.trim().isEmpty
                                            ? 'Please enter patient name'
                                            : null,
                                  ),

                                  // Floating Autocomplete Suggestions Dropdown
                                  if (_showSuggestions &&
                                      suggestions.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Container(
                                      constraints:
                                          const BoxConstraints(maxHeight: 180),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        border: Border.all(
                                            color: const Color(0xFFCBD5E1)),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.08),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: ListView.separated(
                                        shrinkWrap: true,
                                        itemCount: suggestions.length > 5
                                            ? 5
                                            : suggestions.length,
                                        separatorBuilder: (_, _) => const Divider(
                                            height: 1, color: Color(0xFFF1F5F9)),
                                        itemBuilder: (context, index) {
                                          final p = suggestions[index];
                                          return InkWell(
                                            onTap: () {
                                              setState(() {
                                                _patientController.text =
                                                    p.fullName;
                                                _selectedPatient = p;
                                                _showSuggestions = false;
                                                _patientQuery = p.fullName;

                                                // If patient has notes, auto-fill
                                                if (p.notes.isNotEmpty) {
                                                  _clinicalNotesController
                                                      .text = p.notes;
                                                  _showClinicalNotes = true;
                                                }
                                              });
                                            },
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 8,
                                              ),
                                              child: Row(
                                                children: [
                                                  CircleAvatar(
                                                    radius: 14,
                                                    backgroundColor:
                                                        const Color(0xFFEFF6FF),
                                                    child: Text(
                                                      p.firstName.isNotEmpty
                                                          ? p.firstName[0]
                                                              .toUpperCase()
                                                          : 'P',
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color:
                                                            Color(0xFF2563EB),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          p.fullName,
                                                          style:
                                                              const TextStyle(
                                                            fontSize: 13,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: Color(
                                                                0xFF0F172A),
                                                          ),
                                                        ),
                                                        Text(
                                                          '${p.gender} • ${p.phone.isEmpty ? "No phone" : p.phone}',
                                                          style:
                                                              const TextStyle(
                                                            fontSize: 11,
                                                            color: Color(
                                                                0xFF64748B),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const Icon(
                                                    Icons.north_west_rounded,
                                                    size: 14,
                                                    color: Color(0xFF94A3B8),
                                                  ),
                                                ],
                                              ),
                                            ),
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

                    // Clinical Notes Card
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          InkWell(
                            onTap: () {
                              setState(() =>
                                  _showClinicalNotes = !_showClinicalNotes);
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  const Text(
                                    'Clinical Notes:',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  const Spacer(),
                                  Icon(
                                    _showClinicalNotes
                                        ? Icons.remove
                                        : Icons.add,
                                    size: 20,
                                    color: const Color(0xFF334155),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_showClinicalNotes)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                              child: TextFormField(
                                controller: _clinicalNotesController,
                                maxLines: 2,
                                decoration: const InputDecoration(
                                  hintText:
                                      'Enter patient observations, diagnosis, or clinical notes...',
                                  hintStyle: TextStyle(
                                      fontSize: 12, color: Color(0xFF94A3B8)),
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Treatment Section Card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Treatment:',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextFormField(
                                  controller: _treatmentNameController,
                                  decoration: const InputDecoration(
                                    hintText:
                                        'Treatment (e.g. Followup Consulta...)',
                                    hintStyle: TextStyle(
                                        fontSize: 12, color: Color(0xFF94A3B8)),
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 8),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: _treatmentPriceController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    hintText: 'Price (₹)',
                                    hintStyle: TextStyle(
                                        fontSize: 12, color: Color(0xFF94A3B8)),
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 8),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: _addTreatment,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryBlue,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 12),
                                ),
                                child: const Text('Add',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),

                          // Treatment items list
                          if (_treatments.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Column(
                              children: _treatments.map((item) {
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        item.name,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        '₹${item.price.toInt()}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: primaryBlue,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      InkWell(
                                        onTap: () {
                                          setState(() =>
                                              _treatments.remove(item));
                                        },
                                        child: const Icon(
                                          Icons.close,
                                          size: 16,
                                          color: Colors.red,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Medicine Section Card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Medicine:',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextFormField(
                                  controller: _medicineNameController,
                                  decoration: const InputDecoration(
                                    hintText: 'Medicine (e.g. Tab Ran...)',
                                    hintStyle: TextStyle(
                                        fontSize: 11, color: Color(0xFF94A3B8)),
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 8),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: _dosageController,
                                  decoration: const InputDecoration(
                                    hintText: 'Dosage (e.g. 1-0-1)',
                                    hintStyle: TextStyle(
                                        fontSize: 11, color: Color(0xFF94A3B8)),
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 8),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: _medicinePriceController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    hintText: 'Price (₹)',
                                    hintStyle: TextStyle(
                                        fontSize: 11, color: Color(0xFF94A3B8)),
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 8),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              ElevatedButton(
                                onPressed: _addMedicine,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryBlue,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                ),
                                child: const Text('Add',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),

                          // Medicine items list
                          if (_medicines.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Column(
                              children: _medicines.map((item) {
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF0FDF4),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        item.name,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (item.dosage.isNotEmpty)
                                        Text(
                                          ' (${item.dosage})',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                      const Spacer(),
                                      Text(
                                        '₹${item.price.toInt()}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF16A34A),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      InkWell(
                                        onTap: () {
                                          setState(() =>
                                              _medicines.remove(item));
                                        },
                                        child: const Icon(
                                          Icons.close,
                                          size: 16,
                                          color: Colors.red,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Total Calculation Banner
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: primaryBlue.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Calculated Total Amount:',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E3A8A),
                            ),
                          ),
                          Text(
                            '₹${_calculatedTotal.toInt()}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: primaryBlue,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Action Buttons Footer
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
                                color: const Color(0xFF2563EB)
                                    .withValues(alpha: 0.35),
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
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
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
                                      const Icon(Icons.receipt_long_rounded,
                                          size: 20, color: Colors.white),
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
              Text(
                invoice.id,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: onDelete,
              ),
            ],
          ),
          const Divider(),
          const SizedBox(height: 8),
          _detailRow('Patient Name', invoice.patientName),
          _detailRow('Service / Description', invoice.service),
          _detailRow('Amount Charged', '₹${invoice.amount.toInt()}'),
          _detailRow('Date Created', dateFormat.format(invoice.date)),
          if (invoice.dueDate != null)
            _detailRow('Due Date', dateFormat.format(invoice.dueDate!)),
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
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
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF64748B),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }
}
