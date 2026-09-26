import 'dart:async';

import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/patients/data/models/patient.dart';

/// What voice sends to an open form.
sealed class VoiceEvent {
  const VoiceEvent();
}

/// Fields heard so far. Null means "not said"; keep what the form has.
class VoiceFill extends VoiceEvent {
  const VoiceFill({
    this.date,
    this.time,
    this.firstName,
    this.lastName,
    this.age,
    this.dateOfBirth,
    this.gender,
    this.phone,
    this.email,
    this.conditions = const [],
    this.notes,
    this.balance,
    this.reason,
    this.durationMinutes,
    this.homeVisit,
    this.address,
    this.sendWhatsApp,
    this.addToQueue,
    this.others = const [],
  });

  final DateTime? date;
  final TimeOfDay? time;
  final String? firstName;
  final String? lastName;
  final int? age;
  final DateTime? dateOfBirth;
  final String? gender;
  final String? phone;
  final String? email;

  /// Add to what the form has; never removes.
  final List<String> conditions;

  /// Everything voice has dictated into Notes so far, so re-sending it
  /// replaces rather than repeats.
  final String? notes;
  final double? balance;
  final String? reason;
  final int? durationMinutes;

  /// true = home visit, false = clinic.
  final bool? homeVisit;
  final String? address;
  final bool? sendWhatsApp;
  final bool? addToQueue;

  /// Other patients booked together.
  final List<Patient> others;
}

class VoiceConfirm extends VoiceEvent {
  const VoiceConfirm();
}

class VoiceCancel extends VoiceEvent {
  const VoiceCancel();
}

/// Carries voice events from the controller to whichever form is open.
abstract final class VoiceBus {
  static final _events = StreamController<VoiceEvent>.broadcast();

  /// The latest fill, so a form that opens a frame after the speech was
  /// heard still gets it. Cleared when the voice-opened form closes.
  static VoiceFill? last;

  /// Required fields the open form is still missing, as the form sees
  /// them (including anything typed by hand).
  static final missing = ValueNotifier<List<String>>(const []);

  /// The voice-ready form on screen, however it was opened: 'addPatient',
  /// 'editPatient', 'appointment' or 'reschedule'. Lets voice fill forms
  /// the doctor opened by hand.
  static final openKind = ValueNotifier<String?>(null);

  /// A voice-driven form is on screen and has taken the pending fill.
  static final formReady = ValueNotifier<bool>(false);

  /// Bumped when "confirm" was refused because of [missing].
  static final refused = ValueNotifier<int>(0);

  static Stream<VoiceEvent> get events => _events.stream;

  static void emit(VoiceEvent e) {
    if (e is VoiceFill) last = e;
    _events.add(e);
  }
}

/// Add to a dialog's State to let voice fill it, save it and close it:
///
/// ```dart
/// class _MyDialogState extends State<MyDialog> with VoiceDialogHook<MyDialog> {
///   @override
///   void onVoiceFill(VoiceFill f) => setState(() { ... });
///   @override
///   void onVoiceConfirm() => _save();
///   @override
///   List<String> voiceMissing() => [if (_name.text.isEmpty) 'name'];
/// }
/// ```
mixin VoiceDialogHook<T extends StatefulWidget> on State<T> {
  StreamSubscription<VoiceEvent>? _voiceSub;

  void onVoiceFill(VoiceFill fill);
  void onVoiceConfirm();

  /// Closes without the "Discard changes?" question: the doctor already
  /// said "cancel".
  void onVoiceCancel() => Navigator.of(context).pop();

  /// Required fields still empty, in plain words ("last name").
  List<String> voiceMissing() => const [];

  /// What this form is (see [VoiceBus.openKind]).
  String? get voiceKind => null;

  void _publishMissing() => VoiceBus.missing.value = voiceMissing();

  @override
  void initState() {
    super.initState();
    _voiceSub = VoiceBus.events.listen((e) {
      if (!mounted) return;
      switch (e) {
        case VoiceFill():
          onVoiceFill(e);
          _publishMissing();
        case VoiceConfirm():
          _publishMissing();
          if (VoiceBus.missing.value.isEmpty) {
            onVoiceConfirm();
          } else {
            VoiceBus.refused.value++;
          }
        case VoiceCancel():
          onVoiceCancel();
      }
    });
    final pending = VoiceBus.last;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (pending != null) onVoiceFill(pending);
      _publishMissing();
      VoiceBus.formReady.value = true;
      VoiceBus.openKind.value = voiceKind;
    });
  }

  @override
  void dispose() {
    _voiceSub?.cancel();
    VoiceBus.missing.value = const [];
    VoiceBus.formReady.value = false;
    VoiceBus.openKind.value = null;
    super.dispose();
  }
}
