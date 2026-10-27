import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Helper for Windows network profile check and firewall configuration (Task N8).
abstract final class WindowsFirewallHelper {
  /// Opens Windows network status settings so the user can change their Wi-Fi profile
  /// from "Public" to "Private" if Windows Firewall is blocking LAN sharing.
  static Future<bool> openNetworkStatusSettings() async {
    if (!Platform.isWindows) return false;
    try {
      final uri = Uri.parse('ms-settings:network-status');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return true;
      }
    } catch (e) {
      debugPrint('[WindowsFirewallHelper] Failed to open network settings: $e');
    }
    return false;
  }
}
