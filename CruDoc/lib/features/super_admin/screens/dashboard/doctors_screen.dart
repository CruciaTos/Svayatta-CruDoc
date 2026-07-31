import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/doctor_provider.dart';
import '../../models/doctor_model.dart';
import '../../config/enums.dart';
import '../../services/doctor_service.dart';
import '../../services/audit_log_service.dart';

/// Doctor Management Screen with list, search, and filters.
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
  bool _showFilters = false;

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

  @override
  Widget build(BuildContext context) {
    final doctorState = ref.watch(doctorListProvider);
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Column(
      children: [
        // Header Section
        Padding(
          padding: EdgeInsets.all(isMobile ? 16 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Doctor Management',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  if (doctorState.isLoading)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: 'Refresh',
                    onPressed: () {
                      ref.read(doctorListProvider.notifier).loadDoctors(refresh: true);
                    },
                  ),
                  ElevatedButton.icon(
                    onPressed: _showCreateDoctorDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Doctor'),
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Search & Filter Row
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search by name, email, phone...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  ref
                                      .read(doctorListProvider.notifier)
                                      .setSearchQuery('');
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        isDense: true,
                      ),
                      onChanged: (v) {
                        ref
                            .read(doctorListProvider.notifier)
                            .setSearchQuery(v);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                      _showFilters ? Icons.filter_list_off : Icons.filter_list,
                    ),
                    onPressed: () =>
                        setState(() => _showFilters = !_showFilters),
                    tooltip: 'Toggle Filters',
                  ),
                ],
              ),

              // Filters
              if (_showFilters) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      label: const Text('All'),
                      selected: _selectedStatus == null,
                      onSelected: (_) {
                        setState(() => _selectedStatus = null);
                        ref
                            .read(doctorListProvider.notifier)
                            .setStatusFilter(null);
                      },
                    ),
                    ...DoctorStatus.values.map((status) {
                      return FilterChip(
                        label: Text(status.label),
                        selected: _selectedStatus == status,
                        onSelected: (_) {
                          setState(
                              () => _selectedStatus = _selectedStatus == status ? null : status);
                          ref
                              .read(doctorListProvider.notifier)
                              .setStatusFilter(_selectedStatus);
                        },
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    const Text('Plan: ', style: TextStyle(fontWeight: FontWeight.w500)),
                    ...SubscriptionPlan.values.map((plan) {
                      return ChoiceChip(
                        label: Text(plan.label, style: const TextStyle(fontSize: 12)),
                        selected: _selectedPlan == plan,
                        onSelected: (_) {
                          setState(() =>
                              _selectedPlan = _selectedPlan == plan ? null : plan);
                        },
                      );
                    }),
                  ],
                ),
              ],
            ],
          ),
        ),

        const Divider(height: 1),

        // Error State
        if (doctorState.errorMessage != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(doctorState.errorMessage!)),
                ],
              ),
            ),
          ),

        // Loading Indicator
        if (doctorState.isLoading && doctorState.doctors.isEmpty)
          const Expanded(
            child: Center(child: CircularProgressIndicator()),
          ),

        // Empty State
        if (!doctorState.isLoading && doctorState.doctors.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline,
                      size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text('No doctors found',
                      style: TextStyle(
                          fontSize: 18, color: Colors.grey[600])),
                  const SizedBox(height: 8),
                  Text('Create a new doctor account to get started',
                      style: TextStyle(color: Colors.grey[500])),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {},
                    child: const Text('Add Doctor'),
                  ),
                ],
              ),
            ),
          ),

        // Doctor List
        if (doctorState.doctors.isNotEmpty)
          Expanded(
            child: isMobile
                ? _buildMobileList(doctorState)
                : _buildTable(doctorState),
          ),
      ],
    );
  }

  Widget _buildMobileList(DoctorListState state) {
    return RefreshIndicator(
      onRefresh: () => ref.read(doctorListProvider.notifier).loadDoctors(refresh: true),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: state.doctors.length + (state.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == state.doctors.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            );
          }
          final doctor = state.doctors[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                child: Text(
                  doctor.name.isNotEmpty ? doctor.name[0].toUpperCase() : '?',
                  style: TextStyle(
                      color: Theme.of(context).primaryColor,
                      fontWeight: FontWeight.bold),
                ),
              ),
              title: Text(doctor.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${doctor.email} • ${doctor.clinicName}'),
              trailing: _statusBadge(doctor.status),
              onTap: () {},
            ),
          );
        },
      ),
    );
  }

  Widget _buildTable(DoctorListState state) {
    return SingleChildScrollView(
      controller: _scrollController,
      child: DataTable(
        columnSpacing: 16,
        headingRowHeight: 48,
        dataRowMinHeight: 48,
        dataRowMaxHeight: 56,
        columns: const [
          DataColumn(label: Text('Name', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Email', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Plan', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Storage', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
        rows: state.doctors.map((doctor) {
          return DataRow(cells: [
            DataCell(Text(doctor.name)),
            DataCell(Text(doctor.email, style: const TextStyle(fontSize: 13))),
            DataCell(_planBadge(doctor.subscriptionPlan)),
            DataCell(_statusBadge(doctor.status)),
            DataCell(LinearProgressIndicator(
              value: doctor.storageUsagePercent / 100,
              backgroundColor: Colors.grey[200],
            )),
            DataCell(PopupMenuButton<String>(
              onSelected: (v) => _handleDoctorAction(v, doctor),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                const PopupMenuItem(value: 'suspend', child: Text('Suspend')),
                const PopupMenuItem(value: 'reset_pwd', child: Text('Reset Password')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
              icon: const Icon(Icons.more_vert),
            )),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _statusBadge(DoctorStatus status) {
    final colors = {
      DoctorStatus.active: Colors.green,
      DoctorStatus.suspended: Colors.red,
      DoctorStatus.trial: Colors.orange,
      DoctorStatus.expired: Colors.grey,
      DoctorStatus.pending: Colors.blue,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: (colors[status] ?? Colors.grey).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: (colors[status] ?? Colors.grey).withValues(alpha: 0.3)),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 12,
          color: colors[status] ?? Colors.grey,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _planBadge(SubscriptionPlan plan) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        plan.label,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).primaryColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _handleDoctorAction(String action, DoctorModel doctor) {
    switch (action) {
      case 'edit':
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

  /// Shows a dialog to create a new doctor.
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
                    value: specialization,
                    decoration: const InputDecoration(
                      labelText: 'Specialization',
                      border: OutlineInputBorder(),
                    ),
                    items: ['General Physician', 'Cardiologist', 'Dermatologist', 'Pediatrician', 'Neurologist', 'Orthopedic', 'ENT Specialist', 'Ophthalmologist', 'Dentist', 'Psychiatrist']
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
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
                  DropdownButtonFormField<SubscriptionPlan>(
                    value: selectedPlan,
                    decoration: const InputDecoration(
                      labelText: 'Subscription Plan',
                      border: OutlineInputBorder(),
                    ),
                    items: SubscriptionPlan.values
                        .map((p) => DropdownMenuItem(value: p, child: Text('${p.label} - \$${p.monthlyPrice.toStringAsFixed(0)}/mo')))
                        .toList(),
                    onChanged: (v) => setDialogState(() => selectedPlan = v ?? SubscriptionPlan.starter),
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: ${e.toString().replaceFirst("Exception: ", "")}')),
                        );
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