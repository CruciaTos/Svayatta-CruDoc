import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/services/callable_client.dart';

import '../domain/abha_profile.dart';

/// An ABDM action the server refused, with a message to show.
class AbdmException implements Exception {
  const AbdmException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Client for the `abdm` Cloud Function (`functions/src/abdm/index.ts`).
class AbdmApi {
  AbdmApi({CallableClient? functions})
    : _functions = functions ?? CallableClient();

  static final AbdmApi instance = AbdmApi();

  final CallableClient _functions;

  Future<({String? flowId, List<AbhaSearchAccount> accounts})> searchMobile(
    String mobile,
  ) async {
    final data = await _call('searchMobile', {'mobile': mobile});
    final rawList = data['accounts'];
    final accounts = rawList is List
        ? rawList
              .whereType<Map>()
              .map(
                (m) => AbhaSearchAccount.fromMap(Map<String, dynamic>.from(m)),
              )
              .toList()
        : <AbhaSearchAccount>[];
    return (flowId: data['flowId'] as String?, accounts: accounts);
  }

  Future<AbhaAddressSearchResult> searchAddress(String abhaAddress) async {
    final data = await _call('searchAddress', {'abhaAddress': abhaAddress});
    final rawMethods = data['methods'];
    final methods = rawMethods is List
        ? rawMethods.map((e) => e.toString()).toList()
        : <String>[];
    return AbhaAddressSearchResult(
      flowId: data['flowId'] as String? ?? '',
      methods: methods,
      name: data['name'] as String? ?? '',
      mobileMasked: data['mobileMasked'] as String? ?? '',
    );
  }

  Future<({String flowId, String message, int resendsLeft})> sendOtp({
    required String kind,
    required String channel,
    required String identifier,
    String? index,
    String? flowId,
    bool? consent,
  }) async {
    final data = await _call('sendOtp', {
      'kind': kind,
      'channel': channel,
      'identifier': identifier,
      'index': ?index,
      'flowId': ?flowId,
      'consent': ?consent,
    });
    return (
      flowId: data['flowId'] as String? ?? '',
      message: data['message'] as String? ?? 'OTP sent',
      resendsLeft: (data['resendsLeft'] as num?)?.toInt() ?? 0,
    );
  }

  Future<AbhaVerifyResult> verifyOtp({
    required String flowId,
    required String otp,
    String? mobile,
  }) async {
    final data = await _call('verifyOtp', {
      'flowId': flowId,
      'otp': otp,
      'mobile': ?mobile,
    });
    final rawProfile = data['profile'];
    final profileMap = rawProfile is Map
        ? Map<String, dynamic>.from(rawProfile)
        : <String, dynamic>{};
    return AbhaVerifyResult(
      profile: AbhaProfile.fromMap(profileMap),
      isNew: data['isNew'] as bool? ?? false,
      needsMobileOtp: data['needsMobileOtp'] as bool? ?? false,
      existingPatientId: data['existingPatientId'] as String?,
    );
  }

  Future<List<String>> suggestAddress(String flowId) async {
    final data = await _call('suggestAddress', {'flowId': flowId});
    final raw = data['addresses'];
    return raw is List ? raw.map((e) => e.toString()).toList() : <String>[];
  }

  Future<String> setAddress({
    required String flowId,
    required String abhaAddress,
  }) async {
    final data = await _call('setAddress', {
      'flowId': flowId,
      'abhaAddress': abhaAddress,
    });
    return data['abhaAddress'] as String? ?? abhaAddress;
  }

  Future<AbhaCardData> card(String flowId) async {
    final data = await _call('card', {'flowId': flowId});
    return AbhaCardData(
      contentType: data['contentType'] as String? ?? 'image/png',
      base64: data['base64'] as String? ?? '',
    );
  }

  Future<({bool linked, String? existingPatientId})> link({
    required String flowId,
    required String patientId,
  }) async {
    final data = await _call('link', {
      'flowId': flowId,
      'patientId': patientId,
    });
    return (
      linked: data['linked'] as bool? ?? false,
      existingPatientId: data['existingPatientId'] as String?,
    );
  }

  Future<({String? hipId, String? qrBaseUrl})> facility() async {
    final data = await _call('facility');
    return (
      hipId: data['hipId'] as String?,
      qrBaseUrl: data['qrBaseUrl'] as String?,
    );
  }

  Future<Map<String, dynamic>> _call(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    try {
      final raw = await _functions.call('abdm', {
        'action': action,
        'clinicId': ClinicSession.instance.tenantId,
        ...data,
      });
      return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    } on CallableException catch (e) {
      throw AbdmException(_messageFor(e));
    } catch (_) {
      throw const AbdmException("Couldn't reach CruDoc. Try again.");
    }
  }

  static String _messageFor(CallableException e) => switch (e.code) {
    'resource-exhausted' ||
    'already-exists' ||
    'failed-precondition' ||
    'invalid-argument' ||
    'not-found' =>
      e.message.isNotEmpty ? e.message : "That didn't work. Try again.",
    'permission-denied' =>
      e.message.isNotEmpty
          ? e.message
          : "You don't have permission to do that.",
    'unauthenticated' => 'Sign in again to continue.',
    _ => "Couldn't reach CruDoc. Try again.",
  };
}
