import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:doctor_management_app/features/subscription/data/upgrade_request_model.dart';
import 'package:doctor_management_app/features/subscription/data/doctor_subscription_service.dart';

/// Screen in Super Admin panel to review and approve/reject doctor feature upgrade requests.
class SuperAdminUpgradeRequestsScreen extends StatefulWidget {
  const SuperAdminUpgradeRequestsScreen({super.key});

  @override
  State<SuperAdminUpgradeRequestsScreen> createState() =>
      _SuperAdminUpgradeRequestsScreenState();
}

class _SuperAdminUpgradeRequestsScreenState
    extends State<SuperAdminUpgradeRequestsScreen> {
  UpgradeRequestStatus? _statusFilter;
  bool _isProcessing = false;

  Future<void> _approveRequest(UpgradeRequest request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Approve Upgrade Request?'),
        content: Text(
          'This will enable ${request.requestedModules.length} modules for ${request.doctorName} and extend their subscription by 30 days from today.\n\nTotal Monthly: ₹${request.totalMonthlyPrice.toStringAsFixed(0)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
            ),
            child: const Text('Approve & Activate'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isProcessing = true);
    try {
      final now = DateTime.now();
      final newExpiresDate = now.add(const Duration(days: 30));
      final firestore = FirebaseFirestore.instance;

      // 1. Update user document
      await firestore.collection('users').doc(request.doctorId).update({
        'enabledModules': request.requestedModules,
        'status': 'active',
        'expiresDate': Timestamp.fromDate(newExpiresDate),
        'lastPaymentDate': Timestamp.fromDate(now),
      });

      // 2. Update doctor_settings if exists
      try {
        await firestore.collection('doctor_settings').doc(request.doctorId).set(
          {
            'doctorId': request.doctorId,
            'enabledModules': request.requestedModules,
            'lastModified': Timestamp.fromDate(now),
          },
          SetOptions(merge: true),
        );
      } catch (_) {}

      // 3. Mark request as approved
      await firestore.collection('upgrade_requests').doc(request.id).update({
        'status': UpgradeRequestStatus.approved.value,
        'processedAt': Timestamp.fromDate(now),
        'processedBy': 'Super Admin',
      });

      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Successfully activated ${request.requestedModules.length} modules for ${request.doctorName} (Valid until ${DateFormat('dd MMM yyyy').format(newExpiresDate)})',
            ),
            backgroundColor: const Color(0xFF16A34A),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to approve request: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _rejectRequest(UpgradeRequest request) async {
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Reject Upgrade Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reject upgrade request for ${request.doctorName}?'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason for Rejection (Optional)',
                hintText: 'e.g. Payment not received, invalid transaction ID',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isProcessing = true);
    try {
      final now = DateTime.now();
      await FirebaseFirestore.instance
          .collection('upgrade_requests')
          .doc(request.id)
          .update({
        'status': UpgradeRequestStatus.rejected.value,
        'rejectionReason': reasonController.text.trim(),
        'processedAt': Timestamp.fromDate(now),
        'processedBy': 'Super Admin',
      });

      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upgrade request rejected for ${request.doctorName}'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reject request: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  String _getModuleTitle(String moduleKey) {
    for (final item in DoctorSubscriptionService.availableFeatures) {
      if (item.moduleKey == moduleKey) return item.title;
    }
    return moduleKey;
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Doctor Upgrade Requests',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('All Requests', null),
                  const SizedBox(width: 8),
                  _buildFilterChip('Pending', UpgradeRequestStatus.pending),
                  const SizedBox(width: 8),
                  _buildFilterChip('Approved', UpgradeRequestStatus.approved),
                  const SizedBox(width: 8),
                  _buildFilterChip('Rejected', UpgradeRequestStatus.rejected),
                ],
              ),
            ),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('upgrade_requests')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          var requests = docs
              .map((doc) => UpgradeRequest.fromFirestore(doc))
              .toList();

          // Sort newest first
          requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));

          // Filter by status if selected
          if (_statusFilter != null) {
            requests = requests.where((r) => r.status == _statusFilter).toList();
          }

          if (requests.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.inbox_rounded,
                    size: 56,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _statusFilter == null
                        ? 'No upgrade requests found'
                        : 'No ${_statusFilter!.label} requests',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Upgrade requests submitted by doctors will appear here.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final req = requests[index];
              return _buildRequestCard(req, currencyFormatter);
            },
          );
        },
      ),
    );
  }

  Widget _buildFilterChip(String label, UpgradeRequestStatus? status) {
    final isSelected = _statusFilter == status;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _statusFilter = status),
      selectedColor: const Color(0xFF1E78FF).withValues(alpha: 0.15),
      checkmarkColor: const Color(0xFF1E78FF),
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: isSelected ? const Color(0xFF1E78FF) : const Color(0xFF64748B),
      ),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isSelected ? const Color(0xFF1E78FF) : const Color(0xFFE2E8F0),
        ),
      ),
    );
  }

  Widget _buildRequestCard(
    UpgradeRequest req,
    NumberFormat currencyFormatter,
  ) {
    final isPending = req.status == UpgradeRequestStatus.pending;
    final isApproved = req.status == UpgradeRequestStatus.approved;

    final badgeColor = isPending
        ? const Color(0xFFD97706)
        : (isApproved ? const Color(0xFF16A34A) : const Color(0xFFDC2626));
    final badgeBg = isPending
        ? const Color(0xFFFEF3C7)
        : (isApproved ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2));

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isPending ? const Color(0xFFFCD34D) : const Color(0xFFE2E8F0),
          width: isPending ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Doctor Info & Status Badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFF1E78FF).withValues(alpha: 0.12),
                  child: Text(
                    req.doctorName.isNotEmpty
                        ? req.doctorName.substring(0, 1).toUpperCase()
                        : 'D',
                    style: const TextStyle(
                      color: Color(0xFF1E78FF),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        req.doctorName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${req.doctorEmail} • Plan: ${req.currentPlan.toUpperCase()}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    req.status.label.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: badgeColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 12),

            // Requested Modules List
            Text(
              'REQUESTED MODULES (${req.requestedModules.length}):',
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: req.requestedModules.map((modKey) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _getModuleTitle(modKey),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),

            // Pricing & Submission Time
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TOTAL MONTHLY AMOUNT',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                    Text(
                      currencyFormatter.format(req.totalMonthlyPrice),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1E78FF),
                      ),
                    ),
                  ],
                ),
                Text(
                  'Submitted: ${DateFormat('dd MMM yyyy, hh:mm a').format(req.createdAt)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),

            // Action Buttons for Pending Requests
            if (isPending) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isProcessing ? null : () => _rejectRequest(req),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                        side: const BorderSide(color: Color(0xFFFCA5A5)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Reject',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _isProcessing ? null : () => _approveRequest(req),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text(
                        'Approve & Activate 1 Month',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
