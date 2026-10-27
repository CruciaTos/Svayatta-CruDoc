import 'dart:io';

/// Utilities for discovering and filtering local LAN IPv4 addresses (Task K3, 4.4).
abstract final class LanIpHelper {
  /// Regexp for network interface names belonging to VPNs or virtual adapters
  /// that should not be advertised for clinic LAN file sharing.
  static final RegExp _virtualAdapterRegex = RegExp(
    r'(vEthernet|WSL|Hyper-V|VirtualBox|VMware|docker|tun|tap|wg)',
    caseSensitive: false,
  );

  /// Lists all valid IPv4 local addresses for this machine, excluding:
  /// - Loopback (127.0.0.1)
  /// - Android CLAT (192.0.0.x)
  /// - Link-local (169.254.x.x)
  /// - Virtual adapters and VPNs
  static Future<List<String>> getLocalIpv4Addresses() async {
    final ips = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      for (final iface in interfaces) {
        if (_virtualAdapterRegex.hasMatch(iface.name)) continue;

        for (final addr in iface.addresses) {
          final ip = addr.address.trim();
          if (isValidLanAddress(ip)) {
            ips.add(ip);
          }
        }
      }
    } catch (_) {}
    return ips;
  }

  /// Checks if an IPv4 address is suitable for clinic LAN sharing.
  static bool isValidLanAddress(String ip) {
    if (ip == '127.0.0.1') return false;
    if (ip.startsWith('192.0.0.')) return false; // Android CLAT
    if (ip.startsWith('169.254.')) return false; // Link-local
    if (ip.startsWith('0.') || ip == '255.255.255.255') return false;

    // Check basic IPv4 pattern
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return false;
    }
    return true;
  }

  /// Tests whether two IPv4 addresses belong to the same `/24` subnet
  /// (i.e. first three octets match).
  static bool isSameSubnet(String ip1, String ip2) {
    final p1 = ip1.split('.');
    final p2 = ip2.split('.');
    if (p1.length != 4 || p2.length != 4) return false;
    return p1[0] == p2[0] && p1[1] == p2[1] && p1[2] == p2[2];
  }

  /// Returns peer IP addresses that share a `/24` subnet with at least one local IP.
  static List<String> matchingSubnetIps({
    required List<String> myIps,
    required List<String> peerIps,
  }) {
    final matched = <String>[];
    for (final peerIp in peerIps) {
      if (myIps.any((myIp) => isSameSubnet(myIp, peerIp))) {
        matched.add(peerIp);
      }
    }
    return matched;
  }
}
