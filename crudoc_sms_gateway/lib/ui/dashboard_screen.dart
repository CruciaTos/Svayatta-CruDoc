import 'dart:async';
import 'dart:convert';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/gateway_server.dart';
import '../core/models.dart';
import '../core/native_sms_engine.dart';
import 'theme.dart';

/// Main dashboard screen for the CruDoc SMS Gateway.
///
/// Shows real-time gateway status, SIM info, pairing QR code,
/// and a scrollable list of recent SMS activity.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  final _server = GatewayServer.instance;
  final _battery = Battery();
  final _networkInfo = NetworkInfo();

  GatewayStatus _status = GatewayStatus.offline;
  int _batteryLevel = 0;
  String _localIp = '—';
  Map<String, dynamic> _simInfo = {};
  bool _isPaired = false;
  final List<SmsLogEntry> _logs = [];
  bool _permissionsGranted = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _init();
  }

  Future<void> _init() async {
    await _checkPermissions();
    await _refreshDeviceInfo();
    _server.onStatusChanged = (s) => setState(() => _status = s);
    _server.onSmsLog = (entry) => setState(() {
      _logs.insert(0, entry);
      if (_logs.length > 100) _logs.removeLast();
    });
    if (_permissionsGranted) {
      await _server.start();
    }
    _isPaired = await _server.isPaired();
    setState(() {});
  }

  Future<void> _checkPermissions() async {
    final smsStatus = await Permission.sms.status;
    final phoneStatus = await Permission.phone.status;
    _permissionsGranted = smsStatus.isGranted && phoneStatus.isGranted;
    if (!_permissionsGranted) {
      _status = GatewayStatus.permissionDenied;
    }
  }

  Future<void> _requestPermissions() async {
    final results = await [Permission.sms, Permission.phone].request();
    final sms = results[Permission.sms] ?? PermissionStatus.denied;
    final phone = results[Permission.phone] ?? PermissionStatus.denied;
    _permissionsGranted = sms.isGranted && phone.isGranted;
    if (_permissionsGranted) {
      await _refreshDeviceInfo();
      await _server.start();
    } else {
      _status = GatewayStatus.permissionDenied;
    }
    setState(() {});
  }

  Future<void> _refreshDeviceInfo() async {
    try {
      _batteryLevel = await _battery.batteryLevel;
      _localIp = (await _networkInfo.getWifiIP()) ?? '—';
      _simInfo = await NativeSmsEngine.instance.getSimInfo();
    } catch (_) {}
    setState(() {});
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: AppTheme.glowCard(AppTheme.accentBlue),
                    child: const Icon(Icons.sms_outlined, color: AppTheme.accentBlue, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('CruDoc SMS Gateway', style: AppTheme.heading),
                        const SizedBox(height: 2),
                        Text('Local SIM-based SMS dispatch', style: AppTheme.caption),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _refreshDeviceInfo,
                    icon: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // ── Permission Banner ──
              if (!_permissionsGranted) _buildPermissionBanner(),

              // ── Status Card ──
              _buildStatusCard(),

              const SizedBox(height: 16),

              // ── Device Info Row ──
              Row(
                children: [
                  Expanded(child: _buildInfoTile('Local IP', _localIp, Icons.wifi_rounded)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildInfoTile('Port', '${_server.port}', Icons.lan_outlined)),
                ],
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(child: _buildInfoTile('Battery', '$_batteryLevel%', Icons.battery_std_rounded)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildInfoTile(
                    'SIM',
                    _simInfo['simCount']?.toString() ?? '0',
                    Icons.sim_card_outlined,
                  )),
                ],
              ),

              const SizedBox(height: 16),

              // ── SIM Details ──
              if ((_simInfo['sims'] as List?)?.isNotEmpty == true) _buildSimDetails(),

              const SizedBox(height: 16),

              // ── Pairing Section ──
              _buildPairingSection(),

              const SizedBox(height: 24),

              // ── Activity Log ──
              Text('Recent Activity', style: AppTheme.subheading),
              const SizedBox(height: 12),
              if (_logs.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  decoration: AppTheme.cardDecoration,
                  child: Column(
                    children: [
                      Icon(Icons.inbox_outlined, size: 40, color: AppTheme.textMuted),
                      const SizedBox(height: 8),
                      Text('No SMS activity yet', style: AppTheme.caption),
                    ],
                  ),
                )
              else
                ..._logs.take(50).map(_buildLogTile),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Widgets ─────────────────────────────────────────────

  Widget _buildPermissionBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.glowCard(AppTheme.accentOrange),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: AppTheme.accentOrange, size: 20),
              const SizedBox(width: 8),
              Text('Permissions Required', style: AppTheme.subheading.copyWith(color: AppTheme.accentOrange)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'SMS and Phone permissions are needed for the gateway to send messages via SIM.',
            style: AppTheme.body,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _requestPermissions,
              icon: const Icon(Icons.security_rounded, size: 18),
              label: const Text('Grant Permissions'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentOrange,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    final statusColor = AppTheme.statusColor(_status.name);
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: _status == GatewayStatus.ready || _status == GatewayStatus.online
              ? AppTheme.glowCard(statusColor)
              : AppTheme.cardDecoration,
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor.withValues(
                    alpha: _status == GatewayStatus.ready ? _pulseAnimation.value : 1.0,
                  ),
                  boxShadow: [
                    if (_status == GatewayStatus.ready)
                      BoxShadow(
                        color: statusColor.withValues(alpha: 0.4),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Gateway Status', style: AppTheme.caption),
                    const SizedBox(height: 4),
                    Text(
                      _status.label,
                      style: AppTheme.heading.copyWith(
                        color: statusColor,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
              ),
              // Server toggle
              if (_permissionsGranted)
                Switch(
                  value: _server.isRunning,
                  activeThumbColor: AppTheme.accentGreen,
                  onChanged: (on) async {
                    if (on) {
                      await _server.start();
                    } else {
                      await _server.stop();
                    }
                    setState(() {});
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoTile(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration,
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTheme.caption),
                const SizedBox(height: 2),
                Text(value, style: AppTheme.mono),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimDetails() {
    final sims = (_simInfo['sims'] as List?) ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SIM Cards', style: AppTheme.subheading),
        const SizedBox(height: 8),
        ...sims.map((sim) {
          final s = sim as Map;
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: AppTheme.cardDecoration,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.accentGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.sim_card, size: 20, color: AppTheme.accentGreen),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SIM ${(s['slot'] ?? 0) + 1}', style: AppTheme.subheading.copyWith(fontSize: 14)),
                      Text(s['carrier']?.toString() ?? 'Unknown', style: AppTheme.body),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildPairingSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.cardDecoration,
      child: _isPaired ? _buildPairedView() : _buildUnpairedView(),
    );
  }

  Widget _buildPairedView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.link_rounded, size: 20, color: AppTheme.accentGreen),
            const SizedBox(width: 8),
            Text('Paired with CruDoc PC', style: AppTheme.subheading.copyWith(color: AppTheme.accentGreen)),
          ],
        ),
        const SizedBox(height: 8),
        Text('Gateway ID: ${_server.gatewayId ?? "—"}', style: AppTheme.caption),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () async {
              await _server.unpair();
              _isPaired = false;
              setState(() {});
            },
            icon: const Icon(Icons.link_off_rounded, size: 18),
            label: const Text('Unpair'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.accentRed,
              side: const BorderSide(color: AppTheme.accentRed, width: 1),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUnpairedView() {
    return FutureBuilder<Map<String, String>>(
      future: _server.getPairingInfo(),
      builder: (context, snapshot) {
        final info = snapshot.data ?? {};
        final qrData = jsonEncode({
          'type': 'crudoc_sms_gateway',
          'gatewayId': info['gatewayId'] ?? '',
          'ip': info['ip'] ?? '',
          'port': info['port'] ?? '8080',
        });

        return Column(
          children: [
            Row(
              children: [
                const Icon(Icons.qr_code_2_rounded, size: 20, color: AppTheme.accentBlue),
                const SizedBox(width: 8),
                Text('Pair with CruDoc PC', style: AppTheme.subheading),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Scan this QR code from CruDoc Windows to pair this gateway.',
              style: AppTheme.body,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text('Gateway ID', style: AppTheme.caption),
            const SizedBox(height: 4),
            SelectableText(info['gatewayId'] ?? '—', style: AppTheme.mono.copyWith(fontSize: 11)),
          ],
        );
      },
    );
  }

  Widget _buildLogTile(SmsLogEntry entry) {
    final statusColor = AppTheme.statusColor(entry.status);
    final timeStr =
        '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
        '${entry.timestamp.minute.toString().padLeft(2, '0')}:'
        '${entry.timestamp.second.toString().padLeft(2, '0')}';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(entry.phone, style: AppTheme.mono.copyWith(fontSize: 13)),
                    const Spacer(),
                    Text(timeStr, style: AppTheme.caption),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  entry.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body.copyWith(fontSize: 12),
                ),
                if (entry.error != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    entry.error!,
                    style: AppTheme.caption.copyWith(color: AppTheme.accentRed),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              entry.status.toUpperCase(),
              style: AppTheme.caption.copyWith(
                color: statusColor,
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
