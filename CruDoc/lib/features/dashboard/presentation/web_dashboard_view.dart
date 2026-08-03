import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  int _selectedNavIndex = 0; // 0: Dashboard, 1: Appointments, 2: Patients, 3: Inventory, 4: Revenue, 5: Invoices
  String _selectedStatusFilter = 'All Status';
  bool _hideRevenue = false;
  final TextEditingController _searchController = TextEditingController();

  // ==================== INVOICE SECTION STATE ====================
  final TextEditingController _invoiceSearchController = TextEditingController();
  String _invoiceStatusFilter = 'All';

  // Invoices List (Stored securely in state)
  final List<Map<String, dynamic>> _invoicesList = [];

  /// Sanitizes user input to prevent injection attacks (XSS, script injection, control characters)
  String _sanitizeInput(String input) {
    return input
        .replaceAll(RegExp(r'<[^>]*>'), '') // Strip HTML tags
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '') // Strip control characters
        .trim();
  }

  Map<String, dynamic>? _latestDbUserData;

  String _getFormattedDoctorName(User? user, [Map<String, dynamic>? dbData]) {
    final data = dbData ?? _latestDbUserData;

    if (data != null) {
      // 1. Check explicit Full Name fields first
      final fullName = (data['fullName'] ?? 
                        data['full_name'] ?? 
                        data['doctorName'] ?? 
                        data['doctor_name'] ?? 
                        data['name'] ?? 
                        data['displayName'] ?? 
                        data['userName']) as String?;

      if (fullName != null && fullName.trim().isNotEmpty) {
        final clean = fullName.trim();
        return clean.toLowerCase().startsWith('dr') ? clean : 'Dr. $clean';
      }

      // 2. Combine First Name + Last Name if stored in separate fields
      final firstName = (data['firstName'] ?? data['first_name'] ?? data['givenName']) as String?;
      final lastName = (data['lastName'] ?? data['last_name'] ?? data['familyName']) as String?;

      if (firstName != null && firstName.trim().isNotEmpty) {
        final combined = ((lastName != null && lastName.trim().isNotEmpty)
                ? '${firstName.trim()} ${lastName.trim()}'
                : firstName.trim())
            .trim();
        return combined.toLowerCase().startsWith('dr') ? combined : 'Dr. $combined';
      }
    }

    // 3. Check Auth user display name
    if (user?.displayName != null && user!.displayName!.trim().isNotEmpty) {
      final name = user.displayName!.trim();
      return name.toLowerCase().startsWith('dr') ? name : 'Dr. $name';
    }

    return 'Doctor';
  }

  String get _doctorName =>
      _getFormattedDoctorName(FirebaseAuth.instance.currentUser, _latestDbUserData);

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

      case 5:
        // Tab 5: Invoices & Billing Management (Web Exclusive)
        return _buildInvoicesWorkspace(context);

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
          _buildSidebarNavItem(5, Icons.receipt_long_outlined, 'Invoices'),

          const Spacer(),

          // Bottom Section: Log Out
          InkWell(
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                context.go('/auth');
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



          // Add Patient Primary Button (Top Navigation Bar)
          ElevatedButton.icon(
            onPressed: _openAddPatient,
            icon: const Icon(Icons.add_rounded, size: 16),
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

          // Doctor Avatar Profile (Live Database Stream)
          Builder(
            builder: (context) {
              final user = FirebaseAuth.instance.currentUser;
              if (user == null) {
                return Row(
                  children: const [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Color(0xFF334155),
                      child: Icon(Icons.person, color: Colors.white, size: 18),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Dr. Guest',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                );
              }

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: (user.email != null && user.email!.isNotEmpty)
                    ? FirebaseFirestore.instance
                        .collection('users')
                        .where('email', isEqualTo: user.email!.toLowerCase().trim())
                        .snapshots()
                    : null,
                builder: (context, snapshot) {
                  Map<String, dynamic>? dbData;
                  if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                    dbData = snapshot.data!.docs.first.data();
                    _latestDbUserData = dbData;
                  }

                  final displayName = _getFormattedDoctorName(user, dbData);
                  final initial = displayName.replaceAll('Dr. ', '').trim().isNotEmpty
                      ? displayName.replaceAll('Dr. ', '').trim()[0].toUpperCase()
                      : 'D';

                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ProfileScreen()),
                      );
                    },
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: const Color(0xFF2563EB),
                          child: Text(
                            initial,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          displayName,
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
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
        final visitsAsync = ref.watch(allVisitsWithPatientsProvider);

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
                      data: (rawVisits) {
                        final visits = rawVisits.where((vw) {
                          if (_selectedStatusFilter == 'Completed') {
                            return vw.visit.status == vmodel.VisitStatus.completed;
                          }
                          if (_selectedStatusFilter == 'Scheduled') {
                            return vw.visit.status == vmodel.VisitStatus.scheduled;
                          }
                          return true;
                        }).toList();

                        return Text(
                          '${visits.length} All Appointments',
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        );
                      },
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
                data: (rawVisits) {
                  final visits = rawVisits.where((vw) {
                    if (_selectedStatusFilter == 'Completed') {
                      return vw.visit.status == vmodel.VisitStatus.completed;
                    }
                    if (_selectedStatusFilter == 'Scheduled') {
                      return vw.visit.status == vmodel.VisitStatus.scheduled;
                    }
                    return true;
                  }).toList();

                  if (visits.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(
                          'No visits or appointments found in database.',
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

  // ==================== INVOICES WORKSPACE (WEB ONLY) ====================

  Widget _buildInvoicesWorkspace(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('invoices')
          .snapshots(),
      builder: (context, snapshot) {
        List<Map<String, dynamic>> allInvoices = List.from(_invoicesList);

        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          final dbInvoices = snapshot.data!.docs.map((doc) {
            final data = Map<String, dynamic>.from(doc.data());
            data['id'] = doc.id;
            return data;
          }).toList();

          final dbIds = dbInvoices.map((e) => e['id'].toString()).toSet();
          allInvoices = [
            ...dbInvoices,
            ..._invoicesList.where((e) => !dbIds.contains(e['id'].toString())),
          ];
        }

        // Input sanitization on search filter
        final searchQuery = _sanitizeInput(_invoiceSearchController.text.toLowerCase());

        final filteredInvoices = allInvoices.where((inv) {
          final name = (inv['patientName'] ?? '').toString().toLowerCase();
          final id = (inv['id'] ?? '').toString().toLowerCase();
          final service = (inv['service'] ?? '').toString().toLowerCase();
          final status = (inv['status'] ?? '').toString();

          final matchesSearch = searchQuery.isEmpty ||
              name.contains(searchQuery) ||
              id.contains(searchQuery) ||
              service.contains(searchQuery);

          final matchesStatus = _invoiceStatusFilter == 'All' ||
              status.toLowerCase() == _invoiceStatusFilter.toLowerCase();

          return matchesSearch && matchesStatus;
        }).toList();

        // Financial calculations
        double totalInvoiced = allInvoices.fold(0.0, (sum, i) => sum + ((i['amount'] as num?)?.toDouble() ?? 0.0));
        double paidTotal = allInvoices
            .where((i) => i['status'] == 'Paid')
            .fold(0.0, (sum, i) => sum + ((i['amount'] as num?)?.toDouble() ?? 0.0));
        double pendingTotal = allInvoices
            .where((i) => i['status'] == 'Pending')
            .fold(0.0, (sum, i) => sum + ((i['amount'] as num?)?.toDouble() ?? 0.0));
        double overdueTotal = allInvoices
            .where((i) => i['status'] == 'Overdue')
            .fold(0.0, (sum, i) => sum + ((i['amount'] as num?)?.toDouble() ?? 0.0));

        final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header title & action
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Invoices & Billing',
                    style: TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Manage patient bills, payment receipts, and pending invoices securely',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => _showCreateInvoiceDialog(context),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Create Invoice'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Stat Summary Cards
          Row(
            children: [
              Expanded(
                child: _buildInvoiceStatCard(
                  title: 'Total Invoiced',
                  amount: currencyFormat.format(totalInvoiced),
                  icon: Icons.receipt_long_rounded,
                  color: const Color(0xFF2563EB),
                  bg: const Color(0xFFEFF6FF),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildInvoiceStatCard(
                  title: 'Paid Invoices',
                  amount: currencyFormat.format(paidTotal),
                  icon: Icons.check_circle_outline_rounded,
                  color: const Color(0xFF10B981),
                  bg: const Color(0xFFECFDF5),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildInvoiceStatCard(
                  title: 'Pending',
                  amount: currencyFormat.format(pendingTotal),
                  icon: Icons.hourglass_top_rounded,
                  color: const Color(0xFFF59E0B),
                  bg: const Color(0xFFFFFBEB),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildInvoiceStatCard(
                  title: 'Overdue',
                  amount: currencyFormat.format(overdueTotal),
                  icon: Icons.warning_amber_rounded,
                  color: const Color(0xFFEF4444),
                  bg: const Color(0xFFFEF2F2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Filter & Search Controls Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                // Search Input with Sanitization
                Expanded(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: TextField(
                      controller: _invoiceSearchController,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'Search by Invoice #, Patient Name, Service...',
                        hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                        prefixIcon: Icon(Icons.search_rounded, color: Color(0xFF94A3B8), size: 18),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Status Filter Chips
                Wrap(
                  spacing: 8,
                  children: ['All', 'Paid', 'Pending', 'Overdue'].map((status) {
                    final isSelected = _invoiceStatusFilter == status;
                    return ChoiceChip(
                      label: Text(
                        status,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                        ),
                      ),
                      selected: isSelected,
                      onSelected: (val) {
                        if (val) {
                          setState(() => _invoiceStatusFilter = status);
                        }
                      },
                      selectedColor: const Color(0xFFEFF6FF),
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      showCheckmark: false,
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Invoices Data Table Card
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                // Table Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  child: const Row(
                    children: [
                      Expanded(flex: 2, child: Text('INVOICE ID', style: _thStyle)),
                      Expanded(flex: 3, child: Text('PATIENT NAME', style: _thStyle)),
                      Expanded(flex: 3, child: Text('SERVICE / DESCRIPTION', style: _thStyle)),
                      Expanded(flex: 2, child: Text('DUE DATE', style: _thStyle)),
                      Expanded(flex: 2, child: Text('AMOUNT', style: _thStyle)),
                      Expanded(flex: 2, child: Text('STATUS', style: _thStyle)),
                      Expanded(flex: 2, child: Text('ACTIONS', style: _thStyle)),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),

                // Table Rows
                if (filteredInvoices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(
                      child: Text(
                        'No invoices found matching your criteria',
                        style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
                      ),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filteredInvoices.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    itemBuilder: (context, index) {
                      final inv = filteredInvoices[index];
                      final status = (inv['status'] ?? 'Pending').toString();
                      Color statusColor;
                      Color statusBg;

                      if (status == 'Paid') {
                        statusColor = const Color(0xFF10B981);
                        statusBg = const Color(0xFFECFDF5);
                      } else if (status == 'Pending') {
                        statusColor = const Color(0xFFF59E0B);
                        statusBg = const Color(0xFFFFFBEB);
                      } else {
                        statusColor = const Color(0xFFEF4444);
                        statusBg = const Color(0xFFFEF2F2);
                      }

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        child: Row(
                          children: [
                            // ID
                            Expanded(
                              flex: 2,
                              child: Text(
                                inv['id'] ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            // Patient Name
                            Expanded(
                              flex: 3,
                              child: Text(
                                inv['patientName'] ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF334155),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            // Service
                            Expanded(
                              flex: 3,
                              child: Text(
                                inv['service'] ?? '-',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            // Due Date
                            Expanded(
                              flex: 2,
                              child: Text(
                                inv['dueDate'] ?? '',
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            // Amount
                            Expanded(
                              flex: 2,
                              child: Text(
                                currencyFormat.format(inv['amount'] ?? 0),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            // Status Badge
                            Expanded(
                              flex: 2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusBg,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  status,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            // Actions
                            Expanded(
                              flex: 2,
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.visibility_outlined, size: 18, color: Color(0xFF64748B)),
                                    tooltip: 'View Details',
                                    onPressed: () => _showInvoiceDetailsDialog(context, inv),
                                  ),
                                  if (status != 'Paid')
                                    IconButton(
                                      icon: const Icon(Icons.check_circle_outline_rounded, size: 18, color: Color(0xFF10B981)),
                                      tooltip: 'Mark Paid',
                                      onPressed: () {
                                        setState(() {
                                          inv['status'] = 'Paid';
                                        });
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Invoice ${inv['id']} marked as Paid!'),
                                            backgroundColor: const Color(0xFF10B981),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  },
);
}

  Widget _buildInvoiceStatCard({
    required String title,
    required String amount,
    required IconData icon,
    required Color color,
    required Color bg,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                amount,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showCreateInvoiceDialog(BuildContext context) {
    final patientNameCtrl = TextEditingController();
    final clinicalNotesCtrl = TextEditingController();
    final treatmentNameCtrl = TextEditingController();
    final treatmentPriceCtrl = TextEditingController();
    final medicineNameCtrl = TextEditingController();
    final medicineDosageCtrl = TextEditingController();
    final medicinePriceCtrl = TextEditingController();
    final discountCtrl = TextEditingController(text: '0');

    DateTime selectedDate = DateTime.now();
    TimeOfDay selectedTime = TimeOfDay.now();

    List<Map<String, dynamic>> treatmentsList = [];
    List<Map<String, dynamic>> medicinesList = [];
    bool isNotesExpanded = false;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // Live financial calculations (treatments + medicines)
            final double treatmentFees = treatmentsList.fold(
                0.0, (sum, item) => sum + ((item['price'] as num?)?.toDouble() ?? 0.0));
            final double medicineFees = medicinesList.fold(
                0.0, (sum, item) => sum + ((item['price'] as num?)?.toDouble() ?? 0.0));
            final double fees = treatmentFees + medicineFees;
            final double discount = double.tryParse(discountCtrl.text.trim()) ?? 0.0;
            final double total = (fees - discount).clamp(0.0, double.infinity);

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: 680,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.88,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header Bar (Harmonized Royal Blue Gradient)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.local_hospital_rounded, color: Colors.white, size: 24),
                              SizedBox(width: 10),
                              const Text(
                'cru.doc',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  fontFamily: AppColors.headingFontFamily,
                ),
              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.white),
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                          ),
                        ],
                      ),
                    ),

                    // Main Scrollable Form Body
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. Date, Time & Doctor/Patient Header Box
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      // Date Picker Trigger
                                      Expanded(
                                        child: InkWell(
                                          onTap: () async {
                                            final picked = await showDatePicker(
                                              context: context,
                                              initialDate: selectedDate,
                                              firstDate: DateTime(2020),
                                              lastDate: DateTime(2030),
                                            );
                                            if (picked != null) {
                                              setModalState(() => selectedDate = picked);
                                            }
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 10),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: const Color(0xFFCBD5E1)),
                                            ),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  DateFormat('dd/MM/yyyy').format(selectedDate),
                                                  style: const TextStyle(
                                                      fontWeight: FontWeight.w600, fontSize: 13),
                                                ),
                                                const Icon(Icons.calendar_month_rounded,
                                                    size: 18, color: Color(0xFF64748B)),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // Time Picker Trigger
                                      Expanded(
                                        child: InkWell(
                                          onTap: () async {
                                            final picked = await showTimePicker(
                                              context: context,
                                              initialTime: selectedTime,
                                            );
                                            if (picked != null) {
                                              setModalState(() => selectedTime = picked);
                                            }
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 10),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: const Color(0xFFCBD5E1)),
                                            ),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  selectedTime.format(context),
                                                  style: const TextStyle(
                                                      fontWeight: FontWeight.w600, fontSize: 13),
                                                ),
                                                const Icon(Icons.access_time_rounded,
                                                    size: 18, color: Color(0xFF64748B)),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  // Doctor Info Field
                                  Row(
                                    children: [
                                      const Text('Doctor: ',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF475569),
                                              fontSize: 13)),
                                      Text(
                                        _doctorName,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF0F172A),
                                            fontSize: 14),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  // Patient Search / Add New
                                  TextField(
                                    controller: patientNameCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Search Patient or Add New',
                                      hintText: 'e.g. Ravi Teja',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.person_search_rounded, size: 20),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // 2. Clinical Notes Section (Expandable card matching image)
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFCBD5E1)),
                              ),
                              child: Column(
                                children: [
                                  InkWell(
                                    onTap: () =>
                                        setModalState(() => isNotesExpanded = !isNotesExpanded),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 10),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text(
                                            'Clinical Notes:',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: Color(0xFF0F172A)),
                                          ),
                                          Icon(
                                            isNotesExpanded
                                                ? Icons.remove_rounded
                                                : Icons.add_rounded,
                                            color: const Color(0xFF0F172A),
                                            size: 20,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (isNotesExpanded)
                                    Padding(
                                      padding:
                                          const EdgeInsets.fromLTRB(14, 0, 14, 12),
                                      child: TextField(
                                        controller: clinicalNotesCtrl,
                                        maxLines: 3,
                                        decoration: const InputDecoration(
                                          hintText: 'Enter clinical observations, symptoms or diagnosis notes...',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // 3. Treatment Section (Matching image layout)
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFCBD5E1)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Treatment:',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: Color(0xFF0F172A)),
                                  ),
                                  const SizedBox(height: 10),
                                  // Treatment Input Row
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: TextField(
                                          controller: treatmentNameCtrl,
                                          decoration: const InputDecoration(
                                            hintText: 'Treatment (e.g. Followup Consultation)',
                                            isDense: true,
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        flex: 2,
                                        child: TextField(
                                          controller: treatmentPriceCtrl,
                                          keyboardType: TextInputType.number,
                                          decoration: const InputDecoration(
                                            hintText: 'Price (₹)',
                                            isDense: true,
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: const Color(0xFF2563EB),
                                          backgroundColor: const Color(0xFFEFF6FF),
                                          side: const BorderSide(color: Color(0xFF2563EB)),
                                          shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(8)),
                                        ),
                                        onPressed: () {
                                          final name = _sanitizeInput(treatmentNameCtrl.text);
                                          final price = double.tryParse(
                                                  treatmentPriceCtrl.text.trim()) ??
                                              0.0;
                                          if (name.isNotEmpty && price > 0) {
                                            setModalState(() {
                                              treatmentsList
                                                  .add({'name': name, 'price': price});
                                              treatmentNameCtrl.clear();
                                              treatmentPriceCtrl.clear();
                                            });
                                          }
                                        },
                                        child: const Text('Add',
                                            style: TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  // Added Treatments List
                                  if (treatmentsList.isNotEmpty)
                                    Column(
                                      children: treatmentsList.asMap().entries.map((entry) {
                                        final idx = entry.key;
                                        final item = entry.value;
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 4),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  item['name'],
                                                  style: const TextStyle(
                                                      fontWeight: FontWeight.w500,
                                                      fontSize: 13),
                                                ),
                                              ),
                                              Text(
                                                '₹ ${(item['price'] as double).toStringAsFixed(0)}',
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.close_rounded,
                                                    color: Color(0xFFEF4444), size: 18),
                                                onPressed: () {
                                                  setModalState(() {
                                                    treatmentsList.removeAt(idx);
                                                  });
                                                },
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // 4. Medicine Section (Matching image layout)
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFCBD5E1)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Medicine:',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: Color(0xFF0F172A)),
                                  ),
                                  const SizedBox(height: 10),
                                  // Medicine Input Row
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: TextField(
                                          controller: medicineNameCtrl,
                                          decoration: const InputDecoration(
                                            hintText: 'Medicine (e.g. Tab Rantac 150mg)',
                                            isDense: true,
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        flex: 2,
                                        child: TextField(
                                          controller: medicineDosageCtrl,
                                          decoration: const InputDecoration(
                                            hintText: 'Dosage (e.g. 1-1-1 3d)',
                                            isDense: true,
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        flex: 2,
                                        child: TextField(
                                          controller: medicinePriceCtrl,
                                          keyboardType: TextInputType.number,
                                          decoration: const InputDecoration(
                                            hintText: 'Price (₹)',
                                            isDense: true,
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: const Color(0xFF2563EB),
                                          backgroundColor: const Color(0xFFEFF6FF),
                                          side: const BorderSide(color: Color(0xFF2563EB)),
                                          shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(8)),
                                        ),
                                        onPressed: () {
                                          final medName = _sanitizeInput(medicineNameCtrl.text);
                                          final dosage = _sanitizeInput(medicineDosageCtrl.text);
                                          final price = double.tryParse(medicinePriceCtrl.text.trim()) ?? 0.0;
                                          if (medName.isNotEmpty) {
                                            setModalState(() {
                                              medicinesList.add(
                                                  {'name': medName, 'dosage': dosage, 'price': price});
                                              medicineNameCtrl.clear();
                                              medicineDosageCtrl.clear();
                                              medicinePriceCtrl.clear();
                                            });
                                          }
                                        },
                                        child: const Text('Add',
                                            style: TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  // Added Medicines List
                                  if (medicinesList.isNotEmpty)
                                    Column(
                                      children: medicinesList.asMap().entries.map((entry) {
                                        final idx = entry.key;
                                        final item = entry.value;
                                        final price = (item['price'] as num?)?.toDouble() ?? 0.0;
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 4),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      item['name'],
                                                      style: const TextStyle(
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 13),
                                                    ),
                                                    if ((item['dosage'] as String).isNotEmpty)
                                                      Text(
                                                        item['dosage'],
                                                        style: const TextStyle(
                                                            color: Color(0xFF64748B),
                                                            fontSize: 11),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              if (price > 0)
                                                Text(
                                                  '₹ ${price.toStringAsFixed(0)}',
                                                  style: const TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 13),
                                                ),
                                              IconButton(
                                                icon: const Icon(Icons.close_rounded,
                                                    color: Color(0xFFEF4444), size: 18),
                                                onPressed: () {
                                                  setModalState(() {
                                                    medicinesList.removeAt(idx);
                                                  });
                                                },
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // 5. Financial Calculation Box (Fees, Discount, Total)
                            Align(
                              alignment: Alignment.centerRight,
                              child: Container(
                                width: 260,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('Fees:',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF475569))),
                                        Text(fees.toStringAsFixed(0),
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF0F172A))),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('Discount:',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF475569))),
                                        SizedBox(
                                          width: 80,
                                          child: TextField(
                                            controller: discountCtrl,
                                            keyboardType: TextInputType.number,
                                            textAlign: TextAlign.end,
                                            onChanged: (_) => setModalState(() {}),
                                            decoration: const InputDecoration(
                                              isDense: true,
                                              contentPadding: EdgeInsets.symmetric(
                                                  horizontal: 8, vertical: 6),
                                              border: OutlineInputBorder(),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Divider(height: 16, color: Color(0xFFCBD5E1)),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('Total:',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w900,
                                                fontSize: 16,
                                                color: Color(0xFF0F172A))),
                                        Text(total.toStringAsFixed(0),
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w900,
                                                fontSize: 16,
                                                color: Color(0xFF2563EB))),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Dialog Actions Footer
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                            child: const Text('Cancel',
                                style: TextStyle(color: Color(0xFF64748B))),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.receipt_long_rounded, size: 18),
                            label: const Text('Generate & Save Invoice',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            onPressed: () {
                              final patientName =
                                  _sanitizeInput(patientNameCtrl.text);
                              if (patientName.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Please enter a patient name'),
                                    backgroundColor: Color(0xFFEF4444),
                                  ),
                                );
                                return;
                              }

                              final serviceSummary = treatmentsList.isNotEmpty
                                  ? treatmentsList.map((e) => e['name']).join(', ')
                                  : 'Clinical Services';

                              final newId =
                                  'INV-${selectedDate.year}-00${_invoicesList.length + 1}';
                              final issueDateStr =
                                  DateFormat('MMM dd, yyyy').format(selectedDate);
                              final dueDateStr = DateFormat('MMM dd, yyyy')
                                  .format(selectedDate.add(const Duration(days: 14)));

                              final newInvoiceObj = {
                                'id': newId,
                                'patientName': patientName,
                                'issueDate': issueDateStr,
                                'dueDate': dueDateStr,
                                'amount': total,
                                'fees': fees,
                                'discount': discount,
                                'status': 'Pending',
                                'service': serviceSummary,
                                'treatments': treatmentsList,
                                'medicines': medicinesList,
                                'clinicalNotes':
                                    _sanitizeInput(clinicalNotesCtrl.text),
                                'createdAt': DateTime.now().millisecondsSinceEpoch,
                                'doctorUid': FirebaseAuth.instance.currentUser?.uid ?? '',
                              };

                              setState(() {
                                _invoicesList.insert(0, newInvoiceObj);
                              });

                              // Persist directly to Database (Cloud Firestore)
                              try {
                                FirebaseFirestore.instance
                                    .collection('invoices')
                                    .doc(newId)
                                    .set(newInvoiceObj);
                              } catch (e) {
                                debugPrint('Firestore database error: $e');
                              }

                              Navigator.of(dialogCtx).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content:
                                      Text('Clinical Invoice $newId created!'),
                                  backgroundColor: const Color(0xFF10B981),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showInvoiceDetailsDialog(BuildContext context, Map<String, dynamic> inv) {
    final treatments = (inv['treatments'] as List<dynamic>?) ?? [];
    final medicines = (inv['medicines'] as List<dynamic>?) ?? [];
    final status = (inv['status'] ?? 'Pending').toString();
    final isPaid = status == 'Paid';

    final double totalAmount = (inv['amount'] as num?)?.toDouble() ?? 0.0;
    final double payments = isPaid ? totalAmount : 0.0;
    final double balance = isPaid ? 0.0 : totalAmount;

    final currencyFormat = NumberFormat.currency(symbol: '', decimalDigits: 0);

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Container(
            width: 580,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.9,
            ),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Brand & Close Action
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.local_hospital_rounded, color: Color(0xFF2563EB), size: 24),
                          SizedBox(width: 8),
                          Text(
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
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                        onPressed: () => Navigator.of(dialogCtx).pop(),
                      ),
                    ],
                  ),
                  const Divider(height: 20, color: Color(0xFFE2E8F0)),

                  // Header Meta: Date, Bill No, Patient Name
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Date: ${inv['issueDate'] ?? ''}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Color(0xFF0F172A)),
                      ),
                      Text(
                        'Bill No: ${inv['id'] ?? ''}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Color(0xFF0F172A)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Patient Name: ${inv['patientName'] ?? 'Ravi Teja'}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Color(0xFF475569)),
                  ),
                  const SizedBox(height: 16),

                  // Main Itemized Table (Matching uploaded image grid borders)
                  Table(
                    border: TableBorder.all(color: Colors.black87, width: 1),
                    columnWidths: const {
                      0: FlexColumnWidth(4),
                      1: FlexColumnWidth(1),
                      2: FlexColumnWidth(2),
                      3: FlexColumnWidth(2),
                      4: FlexColumnWidth(2),
                    },
                    children: [
                      // Header Row
                      TableRow(
                        decoration: const BoxDecoration(color: Color(0xFFF1F5F9)),
                        children: [
                          _buildGridCell('', isHeader: true),
                          _buildGridCell('Qty.', isHeader: true, alignRight: true),
                          _buildGridCell('Rate', isHeader: true, alignRight: true),
                          _buildGridCell('Amt.', isHeader: true, alignRight: true),
                          _buildGridCell('Net', isHeader: true, alignRight: true),
                        ],
                      ),
                      // Date Subheader inside table
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Text(
                              (inv['issueDate'] ?? '').toString(),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                          _buildGridCell(''),
                          _buildGridCell(''),
                          _buildGridCell(''),
                          _buildGridCell(''),
                        ],
                      ),
                      // Treatments Rows
                      ...treatments.map((t) {
                        final item = t as Map<String, dynamic>;
                        final price = (item['price'] as num?)?.toDouble() ?? 0.0;
                        final priceStr = currencyFormat.format(price);
                        return TableRow(
                          children: [
                            _buildGridCell(item['name'] ?? ''),
                            _buildGridCell('1', alignRight: true),
                            _buildGridCell(priceStr, alignRight: true),
                            _buildGridCell(priceStr, alignRight: true),
                            _buildGridCell(priceStr, alignRight: true),
                          ],
                        );
                      }),
                      // Medicines Rows
                      ...medicines.map((m) {
                        final item = m as Map<String, dynamic>;
                        final price = (item['price'] as num?)?.toDouble() ?? 0.0;
                        final priceStr = currencyFormat.format(price);
                        final nameWithDosage = (item['dosage'] ?? '').toString().isNotEmpty
                            ? '${item['name']} (${item['dosage']})'
                            : (item['name'] ?? '').toString();
                        return TableRow(
                          children: [
                            _buildGridCell(nameWithDosage),
                            _buildGridCell('1', alignRight: true),
                            _buildGridCell(priceStr, alignRight: true),
                            _buildGridCell(priceStr, alignRight: true),
                            _buildGridCell(priceStr, alignRight: true),
                          ],
                        );
                      }),
                      // Fallback row if no items
                      if (treatments.isEmpty && medicines.isEmpty)
                        TableRow(
                          children: [
                            _buildGridCell((inv['service'] ?? 'General Consultation').toString()),
                            _buildGridCell('1', alignRight: true),
                            _buildGridCell(currencyFormat.format(totalAmount), alignRight: true),
                            _buildGridCell(currencyFormat.format(totalAmount), alignRight: true),
                            _buildGridCell(currencyFormat.format(totalAmount), alignRight: true),
                          ],
                        ),
                      // Total Row
                      TableRow(
                        decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
                        children: [
                          _buildGridCell('Total', isHeader: true, alignRight: true),
                          _buildGridCell(''),
                          _buildGridCell(''),
                          _buildGridCell(currencyFormat.format(totalAmount),
                              isHeader: true, alignRight: true),
                          _buildGridCell(currencyFormat.format(totalAmount),
                              isHeader: true, alignRight: true),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Financial Summary Table (Right Aligned Grid matching image)
                  Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: 220,
                      child: Table(
                        border: TableBorder.all(color: Colors.black87, width: 1),
                        columnWidths: const {
                          0: FlexColumnWidth(2),
                          1: FlexColumnWidth(2),
                        },
                        children: [
                          TableRow(children: [
                            _buildGridCell('Amount:', alignRight: true, isHeader: true),
                            _buildGridCell(currencyFormat.format(totalAmount), alignRight: true),
                          ]),
                          TableRow(children: [
                            _buildGridCell('Total:', alignRight: true, isHeader: true),
                            _buildGridCell(currencyFormat.format(totalAmount), alignRight: true),
                          ]),
                          TableRow(children: [
                            _buildGridCell('Payments:', alignRight: true, isHeader: true),
                            _buildGridCell(
                              isPaid ? '-${currencyFormat.format(payments)}' : '0',
                              alignRight: true,
                            ),
                          ]),
                          TableRow(children: [
                            _buildGridCell('Balance:', alignRight: true, isHeader: true),
                            _buildGridCell(currencyFormat.format(balance),
                                alignRight: true, isHeader: true),
                          ]),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Payment Details Section (Matching image text)
                  const Text(
                    'Payment Details:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  if (isPaid)
                    Text(
                      'Rs. ${currencyFormat.format(totalAmount)}/- on ${inv['issueDate']} by Online / Cash',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF334155)),
                    )
                  else
                    const Text(
                      'Payment Pending',
                      style: TextStyle(fontSize: 12, color: Color(0xFFEF4444), fontWeight: FontWeight.w600),
                    ),
                  const SizedBox(height: 24),

                  // Signature / Clinic Section (Right Aligned matching image)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text(
                          'For CruDoc Medical Clinic',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF475569)),
                        ),
                        const SizedBox(height: 6),
                        // Signature Container Box
                        Container(
                          width: 140,
                          height: 50,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'Anil Sharma',
                            style: TextStyle(
                              fontFamily: 'Cursive',
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E3A8A),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Dr. $_doctorName',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF334155)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Action Footer Bar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.print_rounded, size: 18),
                        label: const Text('Print Receipt'),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Printing Bill Receipt...'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                      ),
                      Row(
                        children: [
                          if (!isPaid)
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () async {
                                setState(() {
                                  inv['status'] = 'Paid';
                                });
                                try {
                                  await FirebaseFirestore.instance
                                      .collection('invoices')
                                      .doc(inv['id'].toString())
                                      .update({'status': 'Paid'});
                                } catch (e) {
                                  debugPrint('Database update note: $e');
                                }
                                Navigator.of(dialogCtx).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Invoice ${inv['id']} marked as Paid!'),
                                    backgroundColor: const Color(0xFF10B981),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                              child: const Text('Mark Paid'),
                            ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGridCell(String text, {bool isHeader = false, bool alignRight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(
        text,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          fontWeight: isHeader ? FontWeight.bold : FontWeight.w500,
          fontSize: 12,
          color: const Color(0xFF0F172A),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 13)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A), fontSize: 13),
          ),
        ),
      ],
    );
  }
}
