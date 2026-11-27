import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_management_app/features/abdm/domain/abha_consent.dart';
import 'package:doctor_management_app/features/abdm/domain/abha_input.dart';

void main() {
  group('ABHA input detection and validation', () {
    test('detects 14-digit ABHA number, 12-digit Aadhaar, 10-digit mobile, address', () {
      expect(detectAbhaInput('91123456789012'), AbhaInputType.abhaNumber);
      expect(detectAbhaInput('91-1234-5678-9012'), AbhaInputType.abhaNumber);
      expect(detectAbhaInput('1234 5678 9012'), AbhaInputType.aadhaar);
      expect(detectAbhaInput('9876543210'), AbhaInputType.mobile);
      expect(detectAbhaInput('rohit.sharma'), AbhaInputType.abhaAddress);
      expect(detectAbhaInput('rohit@sbx'), AbhaInputType.abhaAddress);
      expect(detectAbhaInput('12345'), AbhaInputType.invalid);
      expect(detectAbhaInput('   '), AbhaInputType.invalid);
    });

    test('formats ABHA number with dashes', () {
      expect(formatAbhaNumber('91123456789012'), '91-1234-5678-9012');
    });

    test('evaluates ABHA address rules', () {
      expect(AbhaAddressRules.evaluate('rohit_1234').isValid, isTrue);
      expect(AbhaAddressRules.evaluate('rohit.s_1').isValid, isTrue);
      expect(AbhaAddressRules.evaluate('short').lengthOk, isFalse);
      expect(AbhaAddressRules.evaluate('a.b.c12345').specialCountOk, isFalse);
      expect(AbhaAddressRules.evaluate('.rohit1234').edgesOk, isFalse);
      expect(AbhaAddressRules.evaluate('rohit1234_').edgesOk, isFalse);
      expect(AbhaAddressRules.evaluate('rohit-1234').charsOk, isFalse);
    });
  });

  group('ABHA consent text', () {
    test('matches exact length and SHA-256 of official M1 consent', () {
      expect(abhaConsentText.length, 1692);
      final hash = sha256.convert(utf8.encode(abhaConsentText)).toString();
      expect(
        hash,
        'b883572b9234795827158bda1160c26c3adcc0bf0e3c10e9b8e81aa1aef259fe',
      );
    });
  });
}
