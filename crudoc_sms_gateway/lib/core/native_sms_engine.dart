import 'package:flutter/services.dart';

/// Flutter wrapper around the Kotlin MethodChannel for native Android SMS sending.
class NativeSmsEngine {
  NativeSmsEngine._();
  static final NativeSmsEngine instance = NativeSmsEngine._();

  static const _channel = MethodChannel('com.svayatta.crudoc_sms_gateway/sms');

  /// Sends an SMS via the native Android SmsManager.
  /// Returns a result map with `status` ("sent" or "failed") and optional `error`.
  Future<Map<String, dynamic>> sendSms({
    required String phone,
    required String message,
    int simSlot = 0,
  }) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'sendSms',
        {
          'phone': phone,
          'message': message,
          'simSlot': simSlot,
        },
      );
      return result ?? {'status': 'failed', 'error': 'Null response from native'};
    } on PlatformException catch (e) {
      return {'status': 'failed', 'error': e.message ?? 'Platform error'};
    } catch (e) {
      return {'status': 'failed', 'error': e.toString()};
    }
  }

  /// Returns SIM card information from the native Android layer.
  Future<Map<String, dynamic>> getSimInfo() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('getSimInfo');
      return result ?? {'simCount': 0, 'sims': [], 'simState': 0, 'hasIccCard': false};
    } catch (e) {
      return {'simCount': 0, 'sims': [], 'simState': 0, 'hasIccCard': false};
    }
  }
}
