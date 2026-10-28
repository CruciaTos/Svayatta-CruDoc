import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/settings/domain/call_forwarding.dart';

void main() {
  group('codes', () {
    test('every call and missed calls, from any number format', () {
      for (final raw in ['8064261740', '+91 80642 61740', '918064261740', '08064261740']) {
        expect(forwardOnCode(ForwardMode.all, raw), '**21*+918064261740#');
        expect(forwardOnCode(ForwardMode.missed, raw), '**004*+918064261740#');
      }
    });

    test('turning off', () {
      expect(forwardOffCode(ForwardMode.all), '##21#');
      expect(forwardOffCode(ForwardMode.missed), '##004#');
    });

    test('not an Indian number', () {
      expect(forwardOnCode(ForwardMode.all, '12345'), isNull);
      expect(forwardOnCode(ForwardMode.all, '+14155550100'), isNull);
    });

    test('display and dialable forms', () {
      expect(formatIndianNumber('918064261740'), '+91 80642 61740');
      expect(dialableIndianNumber('8064261740'), '+918064261740');
    });
  });

  group('method', () {
    ForwardMethod m(ForwardPlatform p, PhoneNetwork n, ForwardMode mode) =>
        forwardMethod(platform: p, network: n, mode: mode);

    test('Android opens the dialler', () {
      expect(
        m(ForwardPlatform.android, PhoneNetwork.other, ForwardMode.all),
        ForwardMethod.dial,
      );
      expect(
        m(ForwardPlatform.android, PhoneNetwork.jio, ForwardMode.missed),
        ForwardMethod.dial,
      );
    });

    test('iPhone and computers copy the code', () {
      expect(
        m(ForwardPlatform.ios, PhoneNetwork.other, ForwardMode.all),
        ForwardMethod.copyCode,
      );
      expect(
        m(ForwardPlatform.other, PhoneNetwork.other, ForwardMode.missed),
        ForwardMethod.copyCode,
      );
    });

    test('Jio, every call: phone settings everywhere', () {
      for (final p in ForwardPlatform.values) {
        expect(
          m(p, PhoneNetwork.jio, ForwardMode.all),
          ForwardMethod.phoneSettings,
        );
      }
    });
  });

  test('Jio SIM detection', () {
    expect(isJioSim(name: 'Jio 4G'), isTrue);
    expect(isJioSim(name: 'JIO'), isTrue);
    expect(isJioSim(name: '', mccMnc: '405857'), isTrue);
    expect(isJioSim(name: '', mccMnc: '405840'), isTrue);
    expect(isJioSim(name: 'airtel', mccMnc: '40410'), isFalse);
    expect(isJioSim(name: 'Vi India', mccMnc: '40420'), isFalse);
  });
}
