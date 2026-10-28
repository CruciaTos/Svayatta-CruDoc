import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/features/settings/domain/call_forwarding.dart';

/// The clinic's AI receptionist line (`voice_lines/{aiNumber}`), written by
/// the server. Patients call [publishedNumber], which forwards to [aiNumber].
class VoiceLine {
  const VoiceLine({
    required this.aiNumber,
    required this.status,
    required this.doctorIds,
    this.publishedNumber,
  });

  /// 12 digits starting 91 (the document id).
  final String aiNumber;

  /// The doctor's own number, the one that forwards. Null until set up.
  final String? publishedNumber;

  /// pending_test, active or paused.
  final String status;
  final List<String> doctorIds;

  bool get waitingForTestCall => status == 'pending_test';
  bool get paused => status == 'paused';

  static VoiceLine? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final digits = indianNumberDigits(doc.id);
    if (digits == null) return null;
    final d = doc.data() ?? const {};
    final status = d['status'];
    return VoiceLine(
      aiNumber: digits,
      publishedNumber: indianNumberDigits(d['publishedNumber'] as String?),
      status: status == 'active' || status == 'paused'
          ? status as String
          : 'pending_test',
      doctorIds: [
        for (final id in (d['doctorIds'] as List?) ?? const [])
          if (id is String) id,
      ],
    );
  }
}

/// The signed-in person's AI line: the clinic's line that books for them,
/// else the clinic's first line. Null when the clinic has none.
final clinicVoiceLineProvider = StreamProvider<VoiceLine?>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  final clinicId = ref.watch(clinicAccessProvider).value?.clinicId ?? uid;
  if (uid == null || clinicId == null) return Stream.value(null);
  // firestore.rules lets a list through only when it is narrowed to one
  // clinic, so the query has to filter on doctorId.
  return FirebaseFirestore.instance
      .collection('voice_lines')
      .where('doctorId', isEqualTo: clinicId)
      .snapshots()
      .map((snap) {
        final lines = [
          for (final doc in snap.docs) ?VoiceLine.fromDoc(doc),
        ];
        if (lines.isEmpty) return null;
        return lines.firstWhere(
          (l) => l.doctorIds.contains(uid),
          orElse: () => lines.first,
        );
      });
});

ForwardPlatform get currentForwardPlatform {
  if (kIsWeb) return ForwardPlatform.other;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => ForwardPlatform.android,
    TargetPlatform.iOS => ForwardPlatform.ios,
    _ => ForwardPlatform.other,
  };
}

/// What the phone says about the SIM it calls from (Android only).
class CallingSim {
  const CallingSim({required this.network, required this.sure});
  final PhoneNetwork network;

  /// False on a dual-SIM phone that asks which SIM each time.
  final bool sure;
}

/// Native helpers in android/.../MainActivity.kt.
class CallForwardingPlatform {
  static const _channel = MethodChannel('crudoc/call_forwarding');

  static Future<CallingSim?> callingSim() async {
    if (currentForwardPlatform != ForwardPlatform.android) return null;
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('callingSim');
      if (m == null) return null;
      final jio = isJioSim(
        name: m['name'] as String?,
        mccMnc: m['mccMnc'] as String?,
      );
      return CallingSim(
        network: jio ? PhoneNetwork.jio : PhoneNetwork.other,
        sure: m['sure'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  /// Opens the dialler with [number] (a plain number or a forwarding code)
  /// filled in. Nothing is dialled until the doctor presses call.
  static Future<bool> dial(String number) async {
    if (currentForwardPlatform == ForwardPlatform.android) {
      try {
        final ok = await _channel.invokeMethod<bool>('dial', {'number': number});
        if (ok == true) return true;
      } on MissingPluginException {
        // An app built before the channel existed: fall through.
      } catch (_) {}
    }
    try {
      // Uri encodes '#' as %23, which Android's dialler decodes. iOS refuses
      // codes with * or #, so callers only send plain numbers there.
      return await launchUrl(Uri(scheme: 'tel', path: number));
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openCallSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openCallSettings') ?? false;
    } catch (_) {
      return false;
    }
  }
}

final callingSimProvider = FutureProvider<CallingSim?>(
  (ref) => CallForwardingPlatform.callingSim(),
);
