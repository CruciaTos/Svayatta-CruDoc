import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/models/device_session.dart';
import '../../../../core/services/device_session_service.dart';

/// Interactive card widget displaying active doctor login sessions with
/// real-time status and remote logout / device revocation capabilities.
class ActiveSessionsCard extends StatefulWidget {
  final String doctorId;

  const ActiveSessionsCard({
    super.key,
    required this.doctorId,
  });

  @override
  State<ActiveSessionsCard> createState() => _ActiveSessionsCardState();
}

class _ActiveSessionsCardState extends State<ActiveSessionsCard> {
  bool _isRevoking = false;

  IconData _getPlatformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'android':
        return Icons.phone_android_rounded;
      case 'ios':
        return Icons.phone_iphone_rounded;
      case 'windows':
        return Icons.laptop_windows_rounded;
      case 'macos':
        return Icons.laptop_mac_rounded;
      case 'linux':
        return Icons.computer_rounded;
      case 'web':
        return Icons.language_rounded;
      default:
        return Icons.devices_rounded;
    }
  }

  String _formatLastActive(DateTime dateTime, bool isCurrent) {
    if (isCurrent) return 'Active now (This device)';
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 2) return 'Active just now';
    if (diff.inMinutes < 60) return 'Active ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Active ${diff.inHours}h ago';
    if (diff.inDays < 7) return 'Active ${diff.inDays}d ago';
    return DateFormat('MMM d, h:mm a').format(dateTime);
  }

  Future<void> _revokeSession(DeviceSession session) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 22),
            SizedBox(width: 8),
            Text('Revoke Device Session', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Text(
          'Are you sure you want to log out ${session.deviceName}? The doctor will need to log in again on that device.',
          style: const TextStyle(fontSize: 14, color: Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log Out Device'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isRevoking = true);
    try {
      await DeviceSessionService.instance.revokeSession(widget.doctorId, session.sessionId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Session for ${session.deviceName} was terminated.'),
          backgroundColor: const Color(0xFF0F172A),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to revoke session: $e'),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isRevoking = false);
    }
  }

  Future<void> _revokeAllOthers() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.phonelink_erase_rounded, color: Color(0xFFDC2626), size: 22),
            SizedBox(width: 8),
            Text('Log Out All Other Devices', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ],
        ),
        content: const Text(
          'This will terminate all active logins except this current device. Continue?',
          style: TextStyle(fontSize: 14, color: Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log Out All Others'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isRevoking = true);
    try {
      await DeviceSessionService.instance.revokeAllOtherSessions(widget.doctorId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All other device sessions have been terminated.'),
          backgroundColor: Color(0xFF0F172A),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to revoke sessions: $e'),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isRevoking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.doctorId.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<List<DeviceSession>>(
      stream: DeviceSessionService.instance.watchActiveSessions(widget.doctorId),
      builder: (context, snapshot) {
        final sessions = snapshot.data ?? [];
        final hasOtherSessions = sessions.any((s) => !s.isCurrentDevice);

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1E293B).withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.devices_rounded,
                      color: Color(0xFF2563EB),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Active Devices & Sessions',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            if (sessions.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${sessions.length} active',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF059669),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Manage devices where your account is currently signed in',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              const SizedBox(height: 12),

              if (snapshot.connectionState == ConnectionState.waiting && sessions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                )
              else if (sessions.isEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF64748B)),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'This device is currently active.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: sessions.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final session = sessions[index];
                    final isCurrent = session.isCurrentDevice;

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? const Color(0xFF2563EB).withValues(alpha: 0.04)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isCurrent
                              ? const Color(0xFF2563EB).withValues(alpha: 0.2)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? const Color(0xFF2563EB).withValues(alpha: 0.12)
                                  : const Color(0xFFE2E8F0),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              _getPlatformIcon(session.platform),
                              size: 20,
                              color: isCurrent
                                  ? const Color(0xFF2563EB)
                                  : const Color(0xFF475569),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        session.deviceName,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF0F172A),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isCurrent) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF2563EB),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'THIS DEVICE',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _formatLastActive(session.lastActiveAt, isCurrent),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                                    color: isCurrent
                                        ? const Color(0xFF059669)
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!isCurrent)
                            IconButton(
                              tooltip: 'Log out this device',
                              onPressed: _isRevoking ? null : () => _revokeSession(session),
                              icon: const Icon(
                                Icons.logout_rounded,
                                size: 18,
                                color: Color(0xFFDC2626),
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            ),
                        ],
                      ),
                    );
                  },
                ),

              if (hasOtherSessions) ...[
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _isRevoking ? null : _revokeAllOthers,
                  icon: const Icon(Icons.phonelink_erase_rounded, size: 16),
                  label: const Text(
                    'Log Out All Other Devices',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFFECACA)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                    minimumSize: const Size.fromHeight(40),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
