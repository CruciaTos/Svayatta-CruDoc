import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import '../../config/enums.dart';
import '../../models/doctor_model.dart';
import '../../providers/doctor_provider.dart';
import '../../services/audit_log_service.dart';
import '../../services/doctor_service.dart';

/// Doctor and Clinic Management Screen redesigned into the CruDoc Calm Clinical design system.
/// Supports search, status/plan filtering, tenant creation, suspension, and password resets.
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
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.all(isMobile ? 16 : 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header Bar
          _buildHeaderBar(
            context,
            notifier,
            doctors.length,
            doctorState.isLoading,
          ),

          const SizedBox(height: CruSpace.s20),

          // 2. Search & Filter Bar
          _buildSearchAndFilters(context, notifier),

          const SizedBox(height: CruSpace.s24),

          // 3. Doctors Table Card
          _buildDoctorsTableCard(context, doctorState, doctors, isMobile),
        ],
      ),
    );
  }

  // ===========================================================================
  // 1. HEADER BAR
  // ===========================================================================
  Widget _buildHeaderBar(
    BuildContext context,
    DoctorListNotifier notifier,
    int doctorCount,
    bool isLoading,
  ) {
    final c = context.cru;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Doctors & Clinics',
                    style: CruType.largeTitle.tint(c.label),
                  ),
                  const SizedBox(width: CruSpace.s12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: ShapeDecoration(
                      color: c.accentTint,
                      shape: cruShape(CruRadius.full),
                    ),
                    child: Text(
                      '$doctorCount Registered',
                      style: CruType.caption.w600.tabular.tint(c.accentText),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CruSpace.s4),
              Text(
                'Tenant accounts, subscription tiers, hardware bridge allocations, and platform access.',
                style: CruType.text.tint(c.label2),
              ),
            ],
          ),
        ),
        CruButton(
          label: 'Refresh',
          kind: CruButtonKind.secondary,
          icon: CruIcons.sparkle,
          onPressed: isLoading
              ? null
              : () => notifier.loadDoctors(refresh: true),
        ),
        const SizedBox(width: CruSpace.s10),
        CruButton(
          label: 'Add Doctor',
          kind: CruButtonKind.primary,
          icon: CruIcons.userPlus,
          onPressed: _showCreateDoctorDialog,
        ),
      ],
    );
  }

  // ===========================================================================
  // 2. SEARCH & FILTER BAR
  // ===========================================================================
  Widget _buildSearchAndFilters(
    BuildContext context,
    DoctorListNotifier notifier,
  ) {
    final c = context.cru;

    return CruCard(
      padding: const EdgeInsets.all(CruSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search Input
          SizedBox(
            height: 40,
            child: TextField(
              controller: _searchController,
              onChanged: (val) => notifier.setSearchQuery(val),
              style: CruType.text.tint(c.label),
              decoration: InputDecoration(
                hintText:
                    'Search by doctor name, email, clinic, or specialization...',
                hintStyle: CruType.text.tint(c.label3),
                filled: true,
                fillColor: c.inset,
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(10),
                  child: CruIcon(CruIcons.search, size: 16, color: c.label3),
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: CruIcon(
                          CruIcons.close,
                          size: 14,
                          color: c.label3,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          notifier.setSearchQuery('');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CruRadius.control),
                  borderSide: BorderSide(color: c.hairline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CruRadius.control),
                  borderSide: BorderSide(color: c.hairline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CruRadius.control),
                  borderSide: BorderSide(color: c.accent, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: CruSpace.s12),

          // Filter Chips Wrap
          Wrap(
            spacing: CruSpace.s8,
            runSpacing: CruSpace.s8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Status:', style: CruType.caption.w600.tint(c.label3)),
              _buildCruFilterPill(
                label: 'All',
                selected: _selectedStatus == null,
                onTap: () {
                  setState(() => _selectedStatus = null);
                  notifier.setStatusFilter(null);
                },
              ),
              for (final status in DoctorStatus.values)
                _buildCruFilterPill(
                  label: status.label,
                  selected: _selectedStatus == status,
                  onTap: () {
                    setState(() => _selectedStatus = status);
                    notifier.setStatusFilter(status);
                  },
                ),
              const SizedBox(width: CruSpace.s12),
              Text('Plan:', style: CruType.caption.w600.tint(c.label3)),
              _buildCruFilterPill(
                label: 'All Plans',
                selected: _selectedPlan == null,
                onTap: () => setState(() => _selectedPlan = null),
              ),
              for (final plan in SubscriptionPlan.values)
                _buildCruFilterPill(
                  label: plan.label,
                  selected: _selectedPlan == plan,
                  onTap: () => setState(() => _selectedPlan = plan),
                ),
              if (_searchController.text.isNotEmpty ||
                  _selectedStatus != null ||
                  _selectedPlan != null) ...[
                const SizedBox(width: CruSpace.s8),
                CruPressable(
                  onTap: _clearFilters,
                  builder: (ctx, hovered) => Text(
                    'Reset filters',
                    style: CruType.caption.w600.tint(c.accentText),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCruFilterPill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final c = context.cru;
    return CruPressable(
      onTap: onTap,
      scaleOnPress: false,
      builder: (ctx, hovered) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: ShapeDecoration(
            color: selected
                ? c.accent
                : hovered
                ? c.hoverFill
                : c.inset,
            shape: cruShape(
              CruRadius.full,
              side: BorderSide(color: c.hairline),
            ),
          ),
          child: Text(
            label,
            style: CruType.caption
                .copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                )
                .tint(selected ? CruBrand.white : c.label2),
          ),
        );
      },
    );
  }

  // ===========================================================================
  // 3. DOCTORS TABLE CARD
  // ===========================================================================
  Widget _buildDoctorsTableCard(
    BuildContext context,
    DoctorListState doctorState,
    List<DoctorModel> doctors,
    bool isMobile,
  ) {
    final c = context.cru;

    final filteredDoctors = doctors.where((d) {
      if (_selectedPlan != null && d.subscriptionPlan != _selectedPlan) {
        return false;
      }
      return true;
    }).toList();

    return CruCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Table Column Headers
          if (!isMobile)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: c.inset,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(CruRadius.card),
                ),
                border: Border(bottom: BorderSide(color: c.hairline)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      'DOCTOR & CLINIC',
                      style: CruType.groupLabel.tint(c.label3),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'SPECIALTY & EMAIL',
                      style: CruType.groupLabel.tint(c.label3),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'TIER PLAN',
                      style: CruType.groupLabel.tint(c.label3),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'ACCOUNT STATUS',
                      style: CruType.groupLabel.tint(c.label3),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'CLOUD STORAGE',
                      style: CruType.groupLabel.tint(c.label3),
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text(
                      'ACTIONS',
                      style: CruType.groupLabel.tint(c.label3),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),

          // Loading State
          if (doctorState.isLoading && filteredDoctors.isEmpty)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            )
          // Empty State
          else if (filteredDoctors.isEmpty)
            Padding(
              padding: const EdgeInsets.all(48),
              child: Center(
                child: Column(
                  children: [
                    CruIcon(CruIcons.patients, size: 40, color: c.label3),
                    const SizedBox(height: CruSpace.s12),
                    Text(
                      'No doctors found matching filters',
                      style: CruType.headline.tint(c.label),
                    ),
                    const SizedBox(height: CruSpace.s4),
                    Text(
                      'Try resetting filters or create a new doctor account above.',
                      style: CruType.text.tint(c.label2),
                    ),
                  ],
                ),
              ),
            )
          // Rows
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredDoctors.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: c.hairline),
              itemBuilder: (ctx, index) {
                final doc = filteredDoctors[index];
                return isMobile
                    ? _buildMobileRow(c, doc)
                    : _buildDesktopRow(c, doc);
              },
            ),

          if (doctorState.hasMore)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: CruButton(
                  label: 'Load More Doctors',
                  kind: CruButtonKind.secondary,
                  onPressed: () =>
                      ref.read(doctorListProvider.notifier).loadDoctors(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDesktopRow(CruColors c, DoctorModel doctor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          // Doctor & Clinic Name
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CruMonogram(name: doctor.name, size: 34),
                const SizedBox(width: CruSpace.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doctor.name,
                        style: CruType.row.tint(c.label),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        doctor.clinicName.isNotEmpty
                            ? doctor.clinicName
                            : 'Independent Practice',
                        style: CruType.caption.tint(c.label3),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Specialty & Email
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doctor.specialization.isNotEmpty
                      ? doctor.specialization
                      : 'General Practice',
                  style: CruType.caption.w600.tint(c.label2),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  doctor.email,
                  style: CruType.caption.tint(c.label3),
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
              child: _buildPlanBadge(c, doctor.subscriptionPlan),
            ),
          ),

          // Status Badge with dot
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildStatusBadge(c, doctor.status),
            ),
          ),

          // Storage Bar
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CruProgressBar(
                  value: (doctor.storageUsagePercent / 100).clamp(0.0, 1.0),
                  color: doctor.storageUsagePercent > 85 ? c.redText : c.accent,
                ),
                const SizedBox(height: CruSpace.s4),
                Text(
                  '${doctor.storageUsagePercent.toStringAsFixed(0)}% of ${doctor.storageLimitGB.toStringAsFixed(0)}GB',
                  style: CruType.caption.tabular.tint(c.label3),
                ),
              ],
            ),
          ),

          // Action Menu
          SizedBox(
            width: 80,
            child: Align(
              alignment: Alignment.centerRight,
              child: PopupMenuButton<String>(
                icon: CruIcon(CruIcons.more, size: 16, color: c.label2),
                onSelected: (v) => _handleDoctorAction(v, doctor),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'suspend',
                    child: Text(
                      doctor.status == DoctorStatus.suspended
                          ? 'Reactivate Account'
                          : 'Suspend Account',
                      style: CruType.text.tint(c.label),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'reset_pwd',
                    child: Text(
                      'Send Password Reset',
                      style: CruType.text.tint(c.label),
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      'Delete Doctor',
                      style: CruType.text.tint(c.redText),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileRow(CruColors c, DoctorModel doctor) {
    return Padding(
      padding: const EdgeInsets.all(CruSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CruMonogram(name: doctor.name, size: 34),
              const SizedBox(width: CruSpace.s10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(doctor.name, style: CruType.row.tint(c.label)),
                    Text(doctor.email, style: CruType.caption.tint(c.label3)),
                  ],
                ),
              ),
              _buildStatusBadge(c, doctor.status),
            ],
          ),
          const SizedBox(height: CruSpace.s10),
          Row(
            children: [
              _buildPlanBadge(c, doctor.subscriptionPlan),
              const SizedBox(width: CruSpace.s10),
              Expanded(
                child: Text(
                  doctor.clinicName,
                  style: CruType.caption.tint(c.label2),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              PopupMenuButton<String>(
                icon: CruIcon(CruIcons.more, size: 16, color: c.label2),
                onSelected: (v) => _handleDoctorAction(v, doctor),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'suspend',
                    child: Text('Suspend Account', style: CruType.text),
                  ),
                  PopupMenuItem(
                    value: 'reset_pwd',
                    child: Text('Reset Password', style: CruType.text),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      'Delete Doctor',
                      style: TextStyle(color: c.redText),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(CruColors c, DoctorStatus status) {
    final (dot, bg, fg) = switch (status) {
      DoctorStatus.active => (CruDotKind.done, c.greenTint, c.greenText),
      DoctorStatus.suspended => (CruDotKind.inactive, c.redTint, c.redText),
      DoctorStatus.trial => (CruDotKind.waiting, c.amberTint, c.amberText),
      DoctorStatus.pending => (CruDotKind.booked, c.accentTint, c.accentText),
      DoctorStatus.expired => (CruDotKind.inactive, c.inset, c.label3),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: ShapeDecoration(color: bg, shape: cruShape(CruRadius.full)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CruStatusDot(dot, size: 6),
          const SizedBox(width: CruSpace.s6),
          Text(status.label, style: CruType.caption.w600.tint(fg)),
        ],
      ),
    );
  }

  Widget _buildPlanBadge(CruColors c, SubscriptionPlan plan) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: ShapeDecoration(
        color: c.inset,
        shape: cruShape(CruRadius.full, side: BorderSide(color: c.hairline)),
      ),
      child: Text(plan.label, style: CruType.caption.w600.tint(c.label)),
    );
  }

  // ===========================================================================
  // 4. ACTION HANDLERS
  // ===========================================================================
  void _handleDoctorAction(String action, DoctorModel doctor) {
    switch (action) {
      case 'suspend':
        _showConfirmDialog(
          title: doctor.status == DoctorStatus.suspended
              ? 'Reactivate Doctor'
              : 'Suspend Doctor',
          message:
              'Are you sure you want to change platform status for ${doctor.name}?',
          onConfirm: () async {
            try {
              final doctorService = SuperAdminDoctorService();
              final auditService = SuperAdminAuditLogService();
              if (doctor.status == DoctorStatus.suspended) {
                await doctorService.activateDoctor(doctor.id);
                await auditService.logAction(
                  actionType: AuditActionType.updatedDoctor,
                  targetDoctorName: doctor.name,
                  targetDoctorEmail: doctor.email,
                );
              } else {
                await doctorService.suspendDoctor(
                  doctor.id,
                  reason: 'Suspended by admin',
                );
                await auditService.logAction(
                  actionType: AuditActionType.suspendedAccount,
                  targetDoctorName: doctor.name,
                  targetDoctorEmail: doctor.email,
                );
              }
              if (mounted) {
                ref
                    .read(doctorListProvider.notifier)
                    .loadDoctors(refresh: true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Doctor status updated successfully'),
                  ),
                );
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            }
          },
        );
        break;
      case 'delete':
        _showConfirmDialog(
          title: 'Delete Doctor Account',
          message:
              'Are you sure you want to permanently delete ${doctor.name}? This action cannot be undone.',
          onConfirm: () async {
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
                ref
                    .read(doctorListProvider.notifier)
                    .loadDoctors(refresh: true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Doctor deleted successfully')),
                );
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            }
          },
        );
        break;
      case 'reset_pwd':
        _showConfirmDialog(
          title: 'Reset Password',
          message: 'Send an account password reset email to ${doctor.email}?',
          onConfirm: () async {
            try {
              final doctorService = SuperAdminDoctorService();
              await doctorService.resetDoctorPassword(doctor.id, doctor.email);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Password reset email sent successfully'),
                  ),
                );
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            }
          },
        );
        break;
    }
  }

  // ===========================================================================
  // 5. CREATE DOCTOR DIALOG
  // ===========================================================================
  Future<void> _showCreateDoctorDialog() async {
    final c = context.cru;
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final passwordController = TextEditingController();
    final clinicNameController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String specialization = 'Dentist';
    SubscriptionPlan selectedPlan = SubscriptionPlan.professional;
    bool isSubmitting = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: c.surface,
          shape: cruShape(CruRadius.card),
          title: Row(
            children: [
              CruIcon(CruIcons.userPlus, size: 20, color: c.accent),
              const SizedBox(width: CruSpace.s10),
              Text('Create Doctor Account', style: CruType.title.tint(c.label)),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      style: CruType.text.tint(c.label),
                      decoration: InputDecoration(
                        labelText: 'Doctor Full Name *',
                        hintText: 'Dr. Jane Smith',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            CruRadius.control,
                          ),
                        ),
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: CruSpace.s12),
                    TextFormField(
                      controller: emailController,
                      style: CruType.text.tint(c.label),
                      decoration: InputDecoration(
                        labelText: 'Email Address *',
                        hintText: 'jane@clinic.com',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            CruRadius.control,
                          ),
                        ),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        if (!v.contains('@')) return 'Invalid email';
                        return null;
                      },
                    ),
                    const SizedBox(height: CruSpace.s12),
                    TextFormField(
                      controller: clinicNameController,
                      style: CruType.text.tint(c.label),
                      decoration: InputDecoration(
                        labelText: 'Clinic / Practice Name *',
                        hintText: 'Apex Dental Care',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            CruRadius.control,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: CruSpace.s12),
                    DropdownButtonFormField<String>(
                      initialValue: specialization,
                      decoration: InputDecoration(
                        labelText: 'Clinical Specialization',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            CruRadius.control,
                          ),
                        ),
                      ),
                      items:
                          [
                                'Dentist',
                                'Endodontist',
                                'Periodontist',
                                'Orthodontist',
                                'Oral & Maxillofacial Radiologist',
                                'Prosthodontist',
                                'Pediatric Dentist',
                                'Oral Pathologist',
                                'Oral Surgeon',
                                'General Physician',
                                'Dermatologist',
                                'Cardiologist',
                              ]
                              .map(
                                (s) =>
                                    DropdownMenuItem(value: s, child: Text(s)),
                              )
                              .toList(),
                      onChanged: (v) =>
                          setDialogState(() => specialization = v ?? 'Dentist'),
                    ),
                    const SizedBox(height: CruSpace.s12),
                    DropdownButtonFormField<SubscriptionPlan>(
                      initialValue: selectedPlan,
                      decoration: InputDecoration(
                        labelText: 'Subscription Plan Tier',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            CruRadius.control,
                          ),
                        ),
                      ),
                      items: SubscriptionPlan.values
                          .map(
                            (p) => DropdownMenuItem(
                              value: p,
                              child: Text(
                                '${p.label} (${p.storageLimitGB.toStringAsFixed(0)}GB Quota)',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setDialogState(
                        () => selectedPlan = v ?? SubscriptionPlan.professional,
                      ),
                    ),
                    const SizedBox(height: CruSpace.s12),
                    TextFormField(
                      controller: passwordController,
                      style: CruType.text.tint(c.label),
                      decoration: InputDecoration(
                        labelText: 'Account Temporary Password *',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            CruRadius.control,
                          ),
                        ),
                      ),
                      obscureText: true,
                      validator: (v) =>
                          v == null || v.length < 6 ? 'Min 6 characters' : null,
                    ),
                    if (isSubmitting) ...[
                      const SizedBox(height: CruSpace.s16),
                      const LinearProgressIndicator(),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            CruButton(
              label: 'Cancel',
              kind: CruButtonKind.secondary,
              onPressed: isSubmitting
                  ? null
                  : () => Navigator.of(ctx).pop(false),
            ),
            CruButton(
              label: 'Create Account',
              kind: CruButtonKind.primary,
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() => isSubmitting = true);
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
                        setDialogState(() => isSubmitting = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('Error: $e')));
                        }
                      }
                    },
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
        const SnackBar(content: Text('Doctor account created successfully!')),
      );
    }
  }

  void _showConfirmDialog({
    required String title,
    required String message,
    required VoidCallback onConfirm,
  }) {
    final c = context.cru;
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: c.surface,
        shape: cruShape(CruRadius.card),
        title: Text(title, style: CruType.title.tint(c.label)),
        content: Text(message, style: CruType.text.tint(c.label2)),
        actions: [
          CruButton(
            label: 'Cancel',
            kind: CruButtonKind.secondary,
            onPressed: () => Navigator.of(dialogCtx).pop(),
          ),
          CruButton(
            label: 'Confirm',
            kind: CruButtonKind.primary,
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              onConfirm();
            },
          ),
        ],
      ),
    );
  }
}
