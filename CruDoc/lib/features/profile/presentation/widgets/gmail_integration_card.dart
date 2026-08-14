import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/features/messaging/data/providers/gmail_auth_providers.dart';

/// Card widget displayed on the Doctor Profile Screen to manage Gmail integration.
///
/// Features:
/// - Displays real-time Gmail connection state (Connected vs Not Connected).
/// - Shows connected Gmail address and active status badge.
/// - One-tap Connect and Disconnect flows with clean error feedback.
class GmailIntegrationCard extends ConsumerStatefulWidget {
  const GmailIntegrationCard({super.key});

  @override
  ConsumerState<GmailIntegrationCard> createState() => _GmailIntegrationCardState();
}

class _GmailIntegrationCardState extends ConsumerState<GmailIntegrationCard> {
  bool _isLoading = false;

  Future<void> _handleConnect() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(gmailConnectionProvider.notifier).connect();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not connect Gmail: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleDisconnect() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Disconnect Gmail?'),
        content: const Text(
          'Automatic appointment confirmation emails will stop being sent until you reconnect.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        await ref.read(gmailConnectionProvider.notifier).disconnect();
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(gmailConnectionProvider);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Icon + Title + Status Badge
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEA4335).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.mail_rounded,
                  color: Color(0xFFEA4335),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Gmail Notifications',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      connectionState.when(
                        data: (email) => email != null && email.isNotEmpty
                            ? email
                            : 'Not Connected',
                        loading: () => 'Checking connection...',
                        error: (_, __) => 'Not Connected',
                      ),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: connectionState.when(
                          data: (email) => email != null && email.isNotEmpty
                              ? const Color(0xFF0D9488)
                              : const Color(0xFF64748B),
                          loading: () => const Color(0xFF64748B),
                          error: (_, __) => const Color(0xFF64748B),
                        ),
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Status Badge
              connectionState.when(
                data: (email) {
                  final isConnected = email != null && email.isNotEmpty;
                  return _buildStatusBadge(isConnected);
                },
                loading: () => const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                error: (_, __) => _buildStatusBadge(false),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Description
          const Text(
            'Automatically sends a professional confirmation email to patients when an appointment is booked.',
            style: TextStyle(
              fontSize: 12.5,
              color: Color(0xFF64748B),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          // Action Button
          connectionState.when(
            data: (email) {
              final isConnected = email != null && email.isNotEmpty;
              return _buildActionButton(isConnected);
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => _buildActionButton(false),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(bool isConnected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isConnected
            ? const Color(0xFF16A34A).withValues(alpha: 0.1)
            : const Color(0xFF64748B).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isConnected
              ? const Color(0xFF16A34A).withValues(alpha: 0.25)
              : const Color(0xFF64748B).withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isConnected ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 13,
            color: isConnected ? const Color(0xFF16A34A) : const Color(0xFF64748B),
          ),
          const SizedBox(width: 4),
          Text(
            isConnected ? 'Active' : 'Off',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: isConnected ? const Color(0xFF16A34A) : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(bool isConnected) {
    if (isConnected) {
      return OutlinedButton.icon(
        onPressed: _isLoading ? null : _handleDisconnect,
        icon: _isLoading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.link_off_rounded, size: 16),
        label: const Text('Disconnect Gmail'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFEF4444),
          side: const BorderSide(color: Color(0xFFFCA5A5)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } else {
      return ElevatedButton.icon(
        onPressed: _isLoading ? null : _handleConnect,
        icon: _isLoading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.add_link_rounded, size: 17),
        label: const Text('Connect Gmail Account'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1E78FF),
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }
}
