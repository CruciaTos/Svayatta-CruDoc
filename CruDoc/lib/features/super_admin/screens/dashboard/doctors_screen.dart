import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/doctor_provider.dart';
import '../../models/doctor_model.dart';
import '../../config/enums.dart';
import '../../services/doctor_service.dart';
import '../../services/audit_log_service.dart';

/// Doctor Management Screen for Super Admin.
class SuperAdminDoctorsScreen extends ConsumerStatefulWidget {
  const SuperAdminDoctorsScreen({super.key});

  @override
  ConsumerState<SuperAdminDoctorsScreen> createState() =>
      _SuperAdminDoctorsScreenState();
}

class _SuperAdminDoctorsScreenState
    extends ConsumerState<SuperAdminDoctorsScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  DoctorStatus? _selectedStatus;
  SubscriptionPlan? _selectedPlan;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(doctorListProvider.notifier).loadDoctors(refresh: true);
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final state = ref.read(doctorListProvider);
      if (!state.isLoading && state.hasMore) {
        ref.read(doctorListProvider.notifier).loadDoctors();
      }
    }
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _selectedStatus = null;
      _selectedPlan = null;
    });
    final notifier = ref.read(doctorListProvider.notifier);
    notifier.setSearchQuery('');
    notifier.setStatusFilter(null);
  }

  @override
  Widget build(BuildContext context) {
    final doctorState = ref.watch(doctorListProvider);
    final notifier = ref.read(doctorListProvider.notifier);
    final isMobile = MediaQuery.of(context).size.width < 768;
    final doctors = doctorState.doctors;

    return SingleChildScrollView(
      controller: _scrollController,
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 1. Header Bar ──────────────────────────────────────
          _buildHeaderBar(context, notifier, doctors.length, doctorState.isLoading),

          const SizedBox(height: 20),

          // ── 2. Search & Filter Bar ─────────────────────────────
          _buildSearchAndFilters(context, doctorState, notifier, isMobile),

          const SizedBox(height: 24),

          // ── 3. Doctors Table / List Card ───────────────────────
          _buildDoctorsTableCard(context, doctorState, doctors, isMobile),
        ],
      ),
    );
  }

  // ====================== 1. HEADER BAR ==========================
  Widget _buildHeaderBar(
    BuildContext context,
    var notifier,
    int doctorCount,
    bool isLoading,
  ) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Doctor Management',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$doctorCount Doctors',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Manage all registered doctors, subscriptions, and feature access',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        IconButton(
          onPressed: isLoading
              ? null
              : () => notifier.loadDoctors(refresh: true),
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Refresh List',
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: _showCreateDoctorDialog,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Doctor'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }

  // ==================== 2. SEARCH & FILTERS ======================
  Widget _buildSearchAndFilters(
    BuildContext context,
    doctorState,
    var notifier,
    bool isMobile,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => notifier.setSearchQuery(val),
                  decoration: InputDecoration(
                    hintText: 'Search by name, email, phone...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              notifier.setSearchQuery('');
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Colors.grey.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Status Filter Chips
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildStatusChip(context, notifier, null, 'All Status',
                      _selectedStatus == null),
                  const SizedBox(width: 6),
                  ...DoctorStatus.values.map((status) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _buildStatusChip(
                        context,
                        notifier,
                        status,
                        status.label,
                        _selectedStatus == status,
                      ),
                    );
                  }),
                ],
              ),
              const SizedBox(width: 8),
              // Subscription Plan Chips
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildPlanChip(context, null, 'All Plans', _selectedPlan == null),
                  const SizedBox(width: 6),
                  ...SubscriptionPlan.values.map((plan) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _buildPlanChip(
                        context,
                        plan,
                        plan.label,
                        _selectedPlan == plan,
                      ),
                    );
                  }),
                ],
              ),
              // Clear Filters
              if (_searchController.text.isNotEmpty ||
                  _selectedStatus != null ||
                  _selectedPlan != null)
                TextButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.restart_alt_rounded, size: 16),
                  label: const Text('Clear Filters', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(
    BuildContext context,
    var notifier,
    DoctorStatus? status,
    String label,
    bool isSelected,
  ) {
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          color: isSelected
              ? Theme.of(context).primaryColor
              : Colors.grey[700],
        ),
      ),
      selected: isSelected,
      onSelected: (_) {
        setState(() => _selectedStatus = status);
        notifier.setStatusFilter(status);
      },
      selectedColor: Theme.of(context).primaryColor.withValues(alpha: 0.12),
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected
              ? Theme.of(context).primaryColor
              : Colors.grey.withValues(alpha: 0.3),
        ),
      ),
      showCheckmark: false,
    );
  }

  Widget _buildPlanChip(
    BuildContext context,
    SubscriptionPlan? plan,
    String label,
    bool isSelected,
  ) {
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          color: isSelected
              ? Theme.of(context).primaryColor
              : Colors.grey[700],
        ),
      ),
      selected: isSelected,
      onSelected: (_) {
        setState(() => _selectedPlan = plan);
        // If there's a plan filter in your provider, call it here
      },
      selectedColor: Theme.of(context).primaryColor.withValues(alpha: 0.12),
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected
              ? Theme.of(context).primaryColor
              : Colors.grey.withValues(alpha: 0.3),
        ),
      ),
      showCheckmark: false,
    );
  }

  // ==================== 3. DOCTORS TABLE CARD ====================
  Widget _buildDoctorsTableCard(
    BuildContext context,
    doctorState,
    List<DoctorModel> doctors,
    bool isMobile,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Desktop Table Header
          if (!isMobile)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.05),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: const Row(
                children: [
                  Expanded(flex: 3, child: Text('NAME', style: _thStyle)),
                  Expanded(flex: 4, child: Text('EMAIL', style: _thStyle)),
                  Expanded(flex: 2, child: Text('PLAN', style: _thStyle)),
                  Expanded(flex: 2, child: Text('STATUS', style: _thStyle)),
                  Expanded(flex: 2, child: Text('STORAGE', style: _thStyle)),
                  SizedBox(
                      width: 90,
                      child: Text('ACTIONS',
                          style: _thStyle, textAlign: TextAlign.center)),
                ],
              ),
            ),

          if (!isMobile) const Divider(height: 1),

          // Loading, Empty, or List
          if (doctorState.isLoading && doctors.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (doctors.isEmpty)
            Padding(
              padding: const EdgeInsets.all(48),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.people_outline,
                        size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 12),
                    Text(
                      'No doctors found matching your criteria',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Adjust your filters or create a new doctor account',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              children: [
                for (int i = 0; i < doctors.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  isMobile
                      ? _buildMobileDoctorCard(context, doctors[i])
                      : _buildDesktopDoctorRow(context, doctors[i]),
                ],
                if (doctorState.hasMore)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  // Desktop Row
  Widget _buildDesktopDoctorRow(BuildContext context, DoctorModel doctor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          // Name + Avatar
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor:
                      Theme.of(context).primaryColor.withValues(alpha: 0.12),
                  child: Text(
                    doctor.name.isNotEmpty
                        ? doctor.name[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    doctor.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Email
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doctor.email,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                if (doctor.clinicName.isNotEmpty)
                  Text(
                    doctor.clinicName,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),

          // Plan Badge
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _planBadge(doctor.subscriptionPlan),
            ),
          ),

          // Status Badge
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _statusBadge(doctor.status),
            ),
          ),

          // Storage Bar
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                LinearProgressIndicator(
                  value: doctor.storageUsagePercent / 100,
                  backgroundColor: Colors.grey[200],
                  color: doctor.storageUsagePercent > 90
                      ? Colors.red
                      : Theme.of(context).primaryColor,
                ),
                const SizedBox(height: 2),
                Text(
                  '${doctor.storageUsagePercent.toStringAsFixed(0)}% used',
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                ),
              ],
            ),
          ),

          // Actions
          SizedBox(
            width: 90,
            child: Align(
              alignment: Alignment.centerRight,
              child: PopupMenuButton<String>(
                onSelected: (v) => _handleDoctorAction(v, doctor),
                offset: const Offset(0, 40),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit Details')),
                  const PopupMenuItem(value: 'suspend', child: Text('Suspend Account')),
                  const PopupMenuItem(value: 'reset_pwd', child: Text('Reset Password')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete Doctor')),
                ],
                icon: const Icon(Icons.more_vert_rounded),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Mobile Card
  Widget _buildMobileDoctorCard(BuildContext context, DoctorModel doctor) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor:
                    Theme.of(context).primaryColor.withValues(alpha: 0.12),
                child: Text(
                  doctor.name.isNotEmpty
                      ? doctor.name[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doctor.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      doctor.email,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              _statusBadge(doctor.status),
              PopupMenuButton<String>(
                onSelected: (v) => _handleDoctorAction(v, doctor),
                offset: const Offset(0, 40),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit Details')),
                  const PopupMenuItem(value: 'suspend', child: Text('Suspend Account')),
                  const PopupMenuItem(value: 'reset_pwd', child: Text('Reset Password')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete Doctor')),
                ],
                icon: const Icon(Icons.more_vert_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _planBadge(doctor.subscriptionPlan),
              const SizedBox(width: 8),
              if (doctor.clinicName.isNotEmpty)
                Text(
                  doctor.clinicName,
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: doctor.storageUsagePercent / 100,
                  backgroundColor: Colors.grey[200],
                  color: doctor.storageUsagePercent > 90
                      ? Colors.red
                      : Theme.of(context).primaryColor,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${doctor.storageUsagePercent.toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Status & Plan Badges ──────────────────────────────────────
  Widget _statusBadge(DoctorStatus status) {
    final colors = {
      DoctorStatus.active: Colors.green,
      DoctorStatus.suspended: Colors.red,
      DoctorStatus.trial: Colors.orange,
      DoctorStatus.expired: Colors.grey,
      DoctorStatus.pending: Colors.blue,
    };
    final color = colors[status] ?? Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _planBadge(SubscriptionPlan plan) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        plan.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).primaryColor,
        ),
      ),
    );
  }

  // ─── Actions Handling ──────────────────────────────────────────
  void _handleDoctorAction(String action, DoctorModel doctor) {
    switch (action) {
      case 'edit':
        // Implement edit functionality
        break;
      case 'suspend':
        _showConfirmDialog(
          'Suspend Doctor',
          'Are you sure you want to suspend ${doctor.name}?',
          () async {
            try {
              final doctorService = SuperAdminDoctorService();
              final auditService = SuperAdminAuditLogService();
              await doctorService.suspendDoctor(doctor.id, reason: 'Suspended by admin');
              await auditService.logAction(
                actionType: AuditActionType.suspendedAccount,
                targetDoctorName: doctor.name,
                targetDoctorEmail: doctor.email,
              );
              if (mounted) {
                ref.read(doctorListProvider.notifier).loadDoctors(refresh: true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Doctor suspended successfully')),
                );
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: ${e.toString().replaceFirst("Exception: ", "")}')),
                );
              }
            }
          },
        );
        break;
      case 'delete':
        _showConfirmDialog(
          'Delete Doctor',
          'Are you sure you want to permanently delete ${doctor.name}? This action cannot be undone.',
          () async {
            try {
              final doctorService = SuperAdminDoctorService();
              final auditService = SuperAdminAuditLogService();
              await doctorService.deleteDoctor(doctor.id);
              await auditService.logAction(
                actionType: AuditActionType.deletedDoctor,
                targetDoctorName: doctor.name,
                targetDoctorEmail: doctor.email,
              );
              if (mounted) {
                ref.read(doctorListProvider.notifier).loadDoctors(refresh: true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Doctor deleted successfully')),
                );
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: ${e.toString().replaceFirst("Exception: ", "")}')),
                );
              }
            }
          },
        );
        break;
      case 'reset_pwd':
        _showConfirmDialog(
          'Reset Password',
          'Send password reset email to ${doctor.email}?',
          () async {
            try {
              final doctorService = SuperAdminDoctorService();
              await doctorService.resetDoctorPassword(doctor.id, doctor.email);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password reset email sent')),
                );
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: ${e.toString().replaceFirst("Exception: ", "")}')),
                );
              }
            }
          },
        );
        break;
    }
  }

  // ─── Create Doctor Dialog ──────────────────────────────────────
  Future<void> _showCreateDoctorDialog() async {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final passwordController = TextEditingController();
    final clinicNameController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String specialization = 'General Physician';
    SubscriptionPlan selectedPlan = SubscriptionPlan.starter;
    bool isLoading = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create New Doctor'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email *',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      if (!v.contains('@')) return 'Invalid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Phone',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: specialization,
                    decoration: const InputDecoration(
                      labelText: 'Specialization',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      'General Physician', 'Cardiologist', 'Dermatologist',
                      'Pediatrician', 'Neurologist', 'Orthopedic',
                      'ENT Specialist', 'Ophthalmologist', 'Dentist', 'Psychiatrist'
                    ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                    onChanged: (v) => setDialogState(() => specialization = v ?? 'General Physician'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: clinicNameController,
                    decoration: const InputDecoration(
                      labelText: 'Clinic Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: passwordController,
                    decoration: const InputDecoration(
                      labelText: 'Password *',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    validator: (v) {
                      if (v == null || v.length < 6) return 'Min 6 characters';
                      return null;
                    },
                  ),
                  if (isLoading) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() => isLoading = true);
                      try {
                        final doctorService = SuperAdminDoctorService();
                        final auditService = SuperAdminAuditLogService();
                        await doctorService.createDoctor(
                          name: nameController.text.trim(),
                          email: emailController.text.trim(),
                          phone: phoneController.text.trim(),
                          specialization: specialization,
                          clinicName: clinicNameController.text.trim(),
                          country: 'India',
                          timeZone: 'Asia/Kolkata',
                          subscriptionPlan: selectedPlan,
                          storageLimitGB: selectedPlan.storageLimitGB,
                          password: passwordController.text,
                        );
                        await auditService.logAction(
                          actionType: AuditActionType.createdDoctor,
                          targetDoctorName: nameController.text.trim(),
                          targetDoctorEmail: emailController.text.trim(),
                        );
                        if (ctx.mounted) Navigator.of(ctx).pop(true);
                      } catch (e) {
                        setDialogState(() => isLoading = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: ${e.toString().replaceFirst("Exception: ", "")}')),
                          );
                        }
                      }
                    },
              child: isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Create Doctor'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    clinicNameController.dispose();

    if (result == true && mounted) {
      ref.read(doctorListProvider.notifier).loadDoctors(refresh: true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Doctor created successfully!')),
      );
    }
  }

  void _showConfirmDialog(String title, String message, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onConfirm();
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }
}

const TextStyle _thStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w800,
  color: Color(0xFF64748B),
  letterSpacing: 0.5,
);