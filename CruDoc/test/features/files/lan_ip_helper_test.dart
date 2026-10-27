import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_management_app/features/files/lan/lan_ip_helper.dart';

void main() {
  group('LanIpHelper Unit Tests', () {
    test('identifies valid and invalid LAN IPv4 addresses', () {
      expect(LanIpHelper.isValidLanAddress('192.168.1.10'), isTrue);
      expect(LanIpHelper.isValidLanAddress('10.0.0.5'), isTrue);
      expect(LanIpHelper.isValidLanAddress('172.16.0.1'), isTrue);

      // Invalid / rejected
      expect(LanIpHelper.isValidLanAddress('127.0.0.1'), isFalse); // Loopback
      expect(LanIpHelper.isValidLanAddress('192.0.0.4'), isFalse); // Android CLAT
      expect(LanIpHelper.isValidLanAddress('169.254.1.1'), isFalse); // Link-local
      expect(LanIpHelper.isValidLanAddress('255.255.255.255'), isFalse);
      expect(LanIpHelper.isValidLanAddress('invalid-ip'), isFalse);
      expect(LanIpHelper.isValidLanAddress('300.1.1.1'), isFalse);
    });

    test('tests /24 subnet matching accurately', () {
      expect(
        LanIpHelper.isSameSubnet('192.168.1.100', '192.168.1.50'),
        isTrue,
      );
      expect(
        LanIpHelper.isSameSubnet('10.0.5.2', '10.0.5.99'),
        isTrue,
      );
      expect(
        LanIpHelper.isSameSubnet('192.168.1.100', '192.168.2.100'),
        isFalse,
      );
      expect(
        LanIpHelper.isSameSubnet('10.0.1.5', '192.168.1.5'),
        isFalse,
      );
    });

    test('filters matching subnet IPs for peer discovery', () {
      final myIps = ['192.168.1.25', '10.0.0.10'];
      final peerIps = ['192.168.1.42', '172.16.0.5', '10.0.0.88', '192.168.2.1'];

      final matched = LanIpHelper.matchingSubnetIps(
        myIps: myIps,
        peerIps: peerIps,
      );

      expect(matched, containsAll(['192.168.1.42', '10.0.0.88']));
      expect(matched, isNot(contains('172.16.0.5')));
      expect(matched, isNot(contains('192.168.2.1')));
    });
  });
}
