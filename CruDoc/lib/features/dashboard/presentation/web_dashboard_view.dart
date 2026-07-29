import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart' as vmodel;
import 'package:doctor_management_app/features/dashboard/widgets/low_stock_banner.dart';
import 'package:doctor_management_app/features/patients/presentation/add_patient.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_records.dart';
import 'package:doctor_management_app/features/inventory/presentation/inventory_list_screen.dart';
import 'package:doctor_management_app/features/revenue/presentation/revenue.dart';
import 'package:doctor_management_app/features/appointments/presentation/visitation_screen.dart';
import 'package:doctor_management_app/features/profile/presentation/profile_screen.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/repo/revenue_repo.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_providers.dart';
import 'package:doctor_management_app/features/appointments/presentation/appointment_calendar_sheet.dart';
import 'package:doctor_management_app/features/auth/presentation/auth_screen.dart';

// ==================== CAREDOC ALL-IN-ONE WEB DASHBOARD ====================

class WebDashboardView extends ConsumerStatefulWidget {
  const WebDashboardView({
    super.key,
    this.onNavigateToTab,
  });

  final ValueChanged<int>? onNavigateToTab;

  @override
  ConsumerState<WebDashboardView> createState() => _WebDashboardViewState();
}

class _WebDashboardViewState extends ConsumerState<WebDashboardView> {
  final RevenueRepository _revenueRepository = RevenueRepository();
  int _selectedNavIndex = 0; // 0: Dashboard, 1: Appointments, 2: Patients, 3: Inventory, 4: Revenue
  String _selectedStatusFilter = 'All Status';
  bool _hideRevenue = false;
  final TextEditingController _searchController = TextEditingController();

  String get _doctorName =>
      FirebaseAuth.instance.currentUser?.displayName ?? 'Dr. Charlie Teo';

  void _openAddPatient() {
    showAddPatientSheet(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // Crisp Light Slate Background
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left Sidebar (CareDoc Navigation Rail)
          _buildSidebar(context),

          // Main Section (Header + Body Content)
          Expanded(
            child: Column(
              children: [
                // Top Header Navbar
                _buildTopHeader(context),

                // Main Content Workspace (Dynamic per selected Nav tab)
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: _buildSelectedTabWorkspace(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== DYNAMIC TAB WORKSPACE SWITCHER ====================

  Widget _buildSelectedTabWorkspace(BuildContext context) {
    switch (_selectedNavIndex) {
      case 0:
        // Tab 0: Main Dashboard Overview
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LowStockBanner(
                onTap: () => setState(() => _selectedNavIndex = 3),
              ),
              const SizedBox(height: 16),
              _buildOverviewStatsRow(context),
              const SizedBox(height: 20),
              _buildAppointmentsTableCard(context),
            ],
          ),
        );

      case 1:
        // Tab 1: Appointments / Events (Full Events Management)
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: const EventsScreen(),
            ),
          ),
        );

      case 2:
        // Tab 2: Patients Record (Full Patient Records Management)
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: const PatientRecords(),
            ),
          ),
        );

      case 3:
        // Tab 3: Inventory List (Full Inventory Management)
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: const InventoryListScreen(),
            ),
          ),
        );

      case 4:
        // Tab 4: Revenue & Finance (Full Revenue Management)
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: const RevenueScreen(),
            ),
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  // ==================== SIDEBAR ====================

  Widget _buildSidebar(BuildContext context) {
    return Container(
      width: 250,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // App Logo (CareDoc / CruDoc)
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.medical_services_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              const Text(
                'cru.doc',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  fontFamily: AppColors.headingFontFamily,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Section 1: OVERVIEW
          const Text(
            'OVERVIEW',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 10),
          _buildSidebarNavItem(0, Icons.grid_view_rounded, 'Dashboard'),
          _buildSidebarNavItem(1, Icons.calendar_today_rounded, 'Appointments',
              subItems: ['All Appointments', 'Past Appointments']),
          _buildSidebarNavItem(2, Icons.people_alt_outlined, 'Patients'),
          _buildSidebarNavItem(3, Icons.inventory_2_outlined, 'Inventory'),

          const SizedBox(height: 20),

          // Section 2: FINANCE
          const Text(
            'FINANCE',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 10),
          _buildSidebarNavItem(4, Icons.payments_outlined, 'Revenue Log'),

          const Spacer(),

          // Bottom Section: Help & Support + Log Out
          _buildSidebarBottomItem(Icons.help_outline_rounded, 'Help & Support'),
          const SizedBox(height: 12),
          InkWell(
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const AuthScreen()),
                  (route) => false,
                );
              }
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFEE2E2)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.logout_rounded,
                      color: Color(0xFFEF4444), size: 18),
                  SizedBox(width: 10),
                  Text(
                    'Log Out',
                    style: TextStyle(
                      color: Color(0xFFEF4444),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
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

  Widget _buildSidebarNavItem(int index, IconData icon, String title,
      {List<String>? subItems}) {
    final isSelected = _selectedNavIndex == index;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() => _selectedNavIndex = index);
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFFEFF6FF)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isSelected
                      ? const Color(0xFF2563EB)
                      : const Color(0xFF64748B),
                  size: 18,
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    color: isSelected
                        ? const Color(0xFF2563EB)
                        : const Color(0xFF334155),
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isSelected && subItems != null)
          Padding(
            padding: const EdgeInsets.only(left: 36, top: 4, bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: subItems
                  .map(
                    (sub) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        sub,
                        style: TextStyle(
                          color: sub.startsWith('All')
                              ? const Color(0xFF2563EB)
                              : const Color(0xFF64748B),
                          fontSize: 11,
                          fontWeight: sub.startsWith('All')
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildSidebarBottomItem(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF64748B), size: 18),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== TOP HEADER ====================

  Widget _buildTopHeader(BuildContext context) {
    String headerTitle = 'Dashboard Overview';
    switch (_selectedNavIndex) {
      case 0:
        headerTitle = 'All Appointments & Overview';
        break;
      case 1:
        headerTitle = 'Events & Appointments';
        break;
      case 2:
        headerTitle = 'Patients Record';
        break;
      case 3:
        headerTitle = 'Inventory Management';
        break;
      case 4:
        headerTitle = 'Revenue & Financial Log';
        break;
    }

    return Container(
      height: 64,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        children: [
          Text(
            headerTitle,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 17,
              fontWeight: FontWeight.w800,
              fontFamily: AppColors.headingFontFamily,
            ),
          ),
          const Spacer(),

          // Search Box in Header
          Container(
            width: 220,
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded,
                    color: Color(0xFF94A3B8), size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      hintText: 'Search workspace...',
                      hintStyle:
                          TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),

          // Add Patient Primary Button
          ElevatedButton.icon(
            onPressed: _openAddPatient,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Patient'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Doctor Avatar Profile
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 16,
                  backgroundColor: Color(0xFF334155),
                  child: Icon(Icons.person, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 8),
                Text(
                  _doctorName,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== OVERVIEW STATS ROW ====================

  Widget _buildOverviewStatsRow(BuildContext context) {
    return StreamBuilder<List<RevenueEntry>>(
      stream: _revenueRepository.watchRevenueEntries(),
      builder: (context, snapshot) {
        final entries = snapshot.data ?? const <RevenueEntry>[];
        final totalRevenue = entries
            .where((e) => e.kind == TransactionKind.income)
            .fold<double>(0, (sum, e) => sum + e.amount);

        return Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: 'Total Revenue',
                value: _hideRevenue
                    ? '₹ • • • • • •'
                    : '₹ ${totalRevenue.toInt()}',
                icon: Icons.account_balance_wallet_outlined,
                iconBg: const Color(0xFFEFF6FF),
                iconColor: const Color(0xFF2563EB),
                action: GestureDetector(
                  onTap: () => setState(() => _hideRevenue = !_hideRevenue),
                  child: Icon(
                    _hideRevenue
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: const Color(0xFF94A3B8),
                    size: 18,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Consumer(
                builder: (context, ref, child) {
                  final medicinesAsync = ref.watch(medicinesStreamProvider);
                  final countText = medicinesAsync.when(
                    data: (medicines) => '${medicines.length} Items',
                    loading: () => 'Loading...',
                    error: (_, _) => 'Stock Items',
                  );

                  return _buildStatCard(
                    title: 'Inventory',
                    value: countText,
                    icon: Icons.inventory_2_outlined,
                    iconBg: const Color(0xFFECFDF5),
                    iconColor: const Color(0xFF10B981),
                    action: TextButton(
                      onPressed: () => setState(() => _selectedNavIndex = 3),
                      child: const Text(
                        'View Inventory',
                        style: TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildStatCard(
                title: 'Calendar',
                value: 'Appointments',
                icon: Icons.calendar_month_outlined,
                iconBg: const Color(0xFFFFE4E6),
                iconColor: const Color(0xFFE11D48),
                action: TextButton(
                  onPressed: () => AppointmentCalendarSheet.show(context),
                  child: const Text(
                    'Open Calendar',
                    style: TextStyle(
                      color: Color(0xFFE11D48),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    Widget? action,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              ?action,
            ],
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 22,
              fontWeight: FontWeight.w800,
              fontFamily: AppColors.headingFontFamily,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== APPOINTMENTS TABLE CARD ====================

  Widget _buildAppointmentsTableCard(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final visitsAsync = ref.watch(todaysVisitsWithPatientsProvider);

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Table Header Row with Filter & Controls
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    visitsAsync.when(
                      data: (list) => Text(
                        '${list.length} All Appointments',
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      loading: () => const Text('Loading Appointments...'),
                      error: (_, _) => const Text('Appointments'),
                    ),
                    const Spacer(),

                    // Filter Dropdown
                    Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedStatusFilter,
                          style: const TextStyle(
                              color: Color(0xFF334155),
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                          icon: const Icon(Icons.arrow_drop_down,
                              color: Color(0xFF64748B)),
                          items: ['All Status', 'Completed', 'Scheduled']
                              .map(
                                (status) => DropdownMenuItem(
                                  value: status,
                                  child: Text(status),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedStatusFilter = val);
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Color(0xFFF1F5F9), height: 1),

              // Table Content
              visitsAsync.when(
                data: (visits) {
                  if (visits.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(
                          'No visits or appointments scheduled for today.',
                          style: TextStyle(
                              color: Color(0xFF94A3B8), fontSize: 13),
                        ),
                      ),
                    );
                  }

                  return Column(
                    children: [
                      // Column Headers
                      Container(
                        color: const Color(0xFFF8FAFC),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        child: const Row(
                          children: [
                            SizedBox(
                              width: 90,
                              child: Text('Patient ID',
                                  style: _thStyle),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text('Patient Name', style: _thStyle),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text('Type', style: _thStyle),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text('Time', style: _thStyle),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text('Mobile Number', style: _thStyle),
                            ),
                            SizedBox(
                              width: 110,
                              child: Text('Status', style: _thStyle),
                            ),
                            SizedBox(
                              width: 60,
                              child: Text('Actions',
                                  style: _thStyle, textAlign: TextAlign.center),
                            ),
                          ],
                        ),
                      ),

                      // Data Rows
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: visits.length,
                        separatorBuilder: (context, index) =>
                            const Divider(color: Color(0xFFF1F5F9), height: 1),
                        itemBuilder: (context, index) {
                          final vw = visits[index];
                          final visit = vw.visit;
                          final patient = vw.patient;
                          final pId = patient?.id ?? visit.patientId;
                          final shortId = pId.length >= 4 ? pId.substring(0, 4) : pId;
                          final patientName = (patient?.fullName != null && patient!.fullName.isNotEmpty)
                              ? patient.fullName
                              : 'Patient #$shortId';
                          final timeStr = DateFormat('hh:mm a').format(visit.scheduledStart);
                          final phoneStr = (patient?.phone != null && patient!.phone.isNotEmpty)
                              ? patient.phone
                              : '+91 98765 43210';
                          final isCompleted = visit.status == vmodel.VisitStatus.completed;

                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 90,
                                  child: Text(
                                    '#$shortId',
                                    style: const TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 14,
                                        backgroundColor: const Color(0xFF2563EB)
                                            .withValues(alpha: 0.12),
                                        child: Text(
                                          patientName[0].toUpperCase(),
                                          style: const TextStyle(
                                            color: Color(0xFF2563EB),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          patientName,
                                          style: const TextStyle(
                                            color: Color(0xFF0F172A),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    visit.visitType == vmodel.VisitType.home
                                        ? 'Home Visit'
                                        : 'Clinic Visit',
                                    style: const TextStyle(
                                      color: Color(0xFF475569),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    timeStr,
                                    style: const TextStyle(
                                      color: Color(0xFF475569),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    phoneStr,
                                    style: const TextStyle(
                                      color: Color(0xFF475569),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 110,
                                  child: _buildStatusBadge(isCompleted),
                                ),
                                SizedBox(
                                  width: 60,
                                  child: IconButton(
                                    icon: const Icon(Icons.more_horiz_rounded,
                                        color: Color(0xFF94A3B8), size: 18),
                                    onPressed: () {},
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                error: (err, _) => Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('Error loading visits: $err'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusBadge(bool isCompleted) {
    final color = isCompleted ? const Color(0xFF10B981) : const Color(0xFF2563EB);
    final bg = isCompleted ? const Color(0xFFECFDF5) : const Color(0xFFEFF6FF);
    final label = isCompleted ? 'Completed' : 'Accepted';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  static const _thStyle = TextStyle(
    color: Color(0xFF64748B),
    fontSize: 11,
    fontWeight: FontWeight.w700,
  );
}
