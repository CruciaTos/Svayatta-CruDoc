import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_builder.dart';
import 'package:doctor_management_app/features/appointments/presentation/desktop_schedule_visit_dialog.dart';
import 'package:doctor_management_app/features/appointments/presentation/reschedule_visit_dialog.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_view_providers.dart';
import 'package:doctor_management_app/features/inventory/domain/inventory_models.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/patients/data/providers/patients_list_providers.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';
import 'package:doctor_management_app/features/patients/presentation/desktop_add_edit_patient_dialog.dart';
import 'package:doctor_management_app/features/revenue/data/providers/revenue_view_providers.dart';
import 'package:doctor_management_app/features/revenue/domain/revenue_models.dart';
import 'package:doctor_management_app/features/settings/data/appearance_preferences.dart';
import 'package:doctor_management_app/features/settings/data/appearance_provider.dart';
import 'package:doctor_management_app/features/settings/presentation/desktop_settings_screen.dart';
import 'package:doctor_management_app/features/shell/components/cru_sidebar.dart';

import 'domain/name_matcher.dart';
import 'domain/voice_command.dart';
import 'domain/voice_navigation.dart';
import 'presentation/voice_dialog_hook.dart';
import 'services/speech_engine.dart';

/// One answer the pill offers: said or tapped.
class VoiceChoice {
  const VoiceChoice(this.label, {this.detail, this.words = const []});

  final String label;

  /// Second line ("34 M · ···3210 · next Fri").
  final String? detail;

  /// Other ways to say it ("monthly", "this month").
  final List<String> words;
}

/// A question the pill is asking. It expands into a card of [options]
/// until one is said or tapped.
class VoiceAsk {
  const VoiceAsk({
    required this.prompt,
    required this.options,
    required this.onPick,
    this.match,
  });

  final String prompt;
  final List<VoiceChoice> options;
  final Future<void> Function(int index) onPick;

  /// Understands answers beyond the options' words ("the 34-year-old").
  final int? Function(VoiceCommand cmd, String text)? match;
}

/// Turns live transcripts into app actions. Opening a screen or a form
/// happens while the doctor is still talking; saving waits for "confirm"
/// (or a tap on the form's own Save).
class VoiceController {
  VoiceController(this._ref, this._context) {
    VoiceBus.missing.addListener(_onMissing);
    VoiceBus.refused.addListener(_onRefused);
    VoiceBus.openKind.addListener(_onFormKind);
  }

  final WidgetRef _ref;
  final BuildContext Function() _context;

  /// What the app understood, for the on-screen strip. Shown instead of
  /// the raw transcript so mishearings don't distract.
  final understood = ValueNotifier<String?>(null);

  /// Everything the open form needs has been heard: prompt for "confirm".
  final ready = ValueNotifier<bool>(false);

  /// What the open form still needs ("Still need: sex, mobile").
  final hint = ValueNotifier<String?>(null);

  /// The form voice opened and is still driving, if any.
  VoiceIntent? _open;

  /// This utterance already opened something; later partials only fill.
  bool _acted = false;
  List<Patient> _patients = const [];
  Patient? _patient;
  DateTime? _date;
  TimeOfDay? _time;

  /// New patient's name as heard so far (Add patient only).
  String? _newName;

  /// The patient the doctor was last dealing with, for "book him…",
  /// "move her appointment…". Set when voice opens or books a patient.
  Patient? _focus;

  /// A patient added by voice, found by name once the list refreshes.
  String? _focusName;

  /// Opened by voice during this utterance, so the final (more accurate)
  /// pass can correct the quick live pass.
  Patient? _openedNow;
  bool _formOpenedNow = false;

  /// The last booking voice saved or moved, so "nah, make it today 6 pm"
  /// changes that booking instead of making a second one.
  ({Patient patient, String visitId, DateTime at})? _recent;

  /// The visit the open Reschedule form is moving, and where it was.
  String? _openVisitId;
  DateTime? _openVisitStart;

  /// The last change voice made, for "undo": 'booked', 'moved',
  /// 'cancelled' or 'added'.
  ({
    String kind,
    String who,
    String? visitId,
    String? patientId,
    DateTime? oldStart,
  })?
  _lastAction;

  /// Where the open Reschedule form stood when this utterance began, so
  /// "push it by an hour" moves from there once, not again on every
  /// partial.
  DateTime? _shiftBase;

  /// Upcoming visits, for finding free slots without waiting.
  List<Visit> _upcoming = const [];

  /// The question the pill is asking, if any.
  final asking = ValueNotifier<VoiceAsk?>(null);

  /// Notes dictated in earlier utterances, and in the current one. Kept
  /// apart because every partial re-sends the current utterance's notes.
  String _notesBefore = '';
  String? _notesNow;
  Timer? _saveCheck;

  /// Call on talk-key down.
  Future<void> beginUtterance() async {
    _acted = false;
    _answeredLive = null;
    // A fresh command starts with a clean response line; with a form or a
    // question open, what's been understood so far stays as context.
    if (_open == null && asking.value == null) understood.value = null;
    _shiftBase =
        _open == VoiceIntent.reschedule && _date != null && _time != null
        ? DateTime(
            _date!.year,
            _date!.month,
            _date!.day,
            _time!.hour,
            _time!.minute,
          )
        : null;
    _navNow = null;
    _openedNow = null;
    _formOpenedNow = false;
    if (_notesNow != null) {
      _notesBefore = _joinNotes(_notesBefore, _notesNow!);
      _notesNow = null;
    }
    try {
      _patients = await _ref.read(patientsStreamProvider.future);
    } catch (_) {
      _patients = _ref.read(patientsStreamProvider).value ?? const [];
    }
    SpeechEngine.instance.hints = [
      for (final p in _patients) p.fullName.trim(),
    ];
    final added = _focusName?.toLowerCase();
    if (added != null) {
      final p = _patients
          .where((p) => p.fullName.trim().toLowerCase() == added)
          .firstOrNull;
      if (p != null) {
        _focus = p;
        _lastAction = (
          kind: 'added',
          who: p.fullName,
          visitId: null,
          patientId: p.id,
          oldStart: null,
        );
      }
      _focusName = null;
    }
    try {
      _upcoming = await _ref.read(upcomingVisitsProvider.future);
    } catch (_) {}
  }

  Future<void> onTranscript(VoiceTranscript t) async {
    final cmd = VoiceCommand.parse(t.text, DateTime.now());

    // "Stop listening" turns hands-free off.
    if (RegExp(
      r'\b(stop listening|turn off hands ?free|hands ?free off|go to sleep|stop hands ?free)\b',
    ).hasMatch(t.text.toLowerCase())) {
      if (t.isFinal) {
        await SpeechEngine.instance.setHandsFree(false);
        understood.value = 'Hands-free off';
      }
      return;
    }

    // A voice-ready form the doctor opened by hand: fill it too.
    final kind = VoiceBus.openKind.value;
    if (_open == null && kind != null) _adopt(kind);

    // With a form open, a question on the pill (a spelling) is answered
    // first; anything else carries on filling the form.
    final pendingAsk = asking.value;
    if (_open != null && pendingAsk != null) {
      final i = _matchChoice(pendingAsk, cmd, t.text);
      if (i != null) {
        if (t.isFinal) await pickChoice(i);
        return;
      }
      if (t.isFinal) asking.value = null;
    }

    if (_open != null) {
      if (_switchTo != null) return;
      if (t.isFinal && cmd.intent == VoiceIntent.confirm) {
        _confirm();
      } else if (t.isFinal && cmd.intent == VoiceIntent.cancel) {
        VoiceBus.emit(const VoiceCancel());
      } else if (!_switchedPatient(cmd, t.isFinal)) {
        _fill(cmd);
        if (t.isFinal && cmd.confirmAtEnd) unawaited(_confirmWhenReady());
        if (t.isFinal && !cmd.confirmAtEnd) _askSpelling();
      }
      return;
    }
    if (!_acted && _isUndo(t.text)) {
      if (t.isFinal) {
        _acted = true;
        await _undo();
      }
      return;
    }
    if (_acted) {
      // The accurate final pass heard a different patient than the quick
      // live pass that opened this one: open the right one.
      final opened = _openedNow;
      if (t.isFinal && opened != null && cmd.name.isNotEmpty) {
        final m = matchPatient(cmd.name, _patients);
        if (m.isSure && m.best!.id != opened.id) {
          _openedNow = m.best;
          _focus = m.best;
          understood.value = 'Opened ${m.best!.fullName}';
          DashboardActions.openPatient(_context(), m.best!);
        }
      }
      return;
    }

    // An answer to the question on the pill ("this month", "the second
    // one", "yes"). A new command instead moves on.
    final question = asking.value;
    if (question != null) {
      const newCommand = {
        VoiceIntent.addPatient,
        VoiceIntent.addAppointment,
        VoiceIntent.reschedule,
        VoiceIntent.editPatient,
        VoiceIntent.openPatient,
      };
      final i = newCommand.contains(cmd.intent)
          ? null
          : _matchChoice(question, cmd, t.text);
      if (i != null) {
        if (t.isFinal) await pickChoice(i);
        return;
      }
      if (t.isFinal) asking.value = null;
    }

    if (_tryNavigate(t, cmd)) return;

    // "Rahul Patel tomorrow at 5" with no verb is a booking.
    var intent = cmd.intent;
    if (intent == VoiceIntent.none &&
        cmd.name.isNotEmpty &&
        (cmd.date != null || cmd.time != null)) {
      intent = VoiceIntent.addAppointment;
    }
    // "The last patient", "the next patient" on their own: open them.
    if (intent == VoiceIntent.none && _patientRef(t.text) != null) {
      intent = (cmd.date != null || cmd.time != null)
          ? VoiceIntent.addAppointment
          : VoiceIntent.openPatient;
    }

    // "Nah, make it today 6 pm", "book his appointment to Friday" right
    // after a booking: move that booking rather than make another.
    final recent = _recent;
    if (recent != null && _changesRecent(cmd, intent, t.text, recent)) {
      _acted = true;
      _focus = recent.patient;
      _formOpenedNow = true;
      _start(VoiceIntent.reschedule, recent.patient);
      final opened = await _openReschedule(
        recent.patient,
        visitId: recent.visitId,
        cmd: cmd,
      );
      if (opened && t.isFinal && cmd.confirmAtEnd) {
        unawaited(_confirmWhenReady());
      }
      return;
    }

    // "His email is …", "her phone number is …" about the patient in
    // focus: edit their record.
    if (intent == VoiceIntent.none &&
        cmd.name.isEmpty &&
        _focus != null &&
        _refersBack(t.text, VoiceIntent.editPatient) &&
        (cmd.phone != null ||
            cmd.email != null ||
            cmd.dateOfBirth != null ||
            cmd.age != null ||
            cmd.notes != null ||
            cmd.conditions.isNotEmpty)) {
      intent = VoiceIntent.editPatient;
    }

    switch (intent) {
      case VoiceIntent.none:
        final knownName =
            cmd.name.isNotEmpty &&
            matchPatient(cmd.name, _patients).score >= 0.6;
        if (t.isFinal && !knownName) await _semanticNavigate(t.text);
        return;
      case VoiceIntent.confirm:
      case VoiceIntent.cancel:
        return;
      case VoiceIntent.cancelAppointment:
        await _askCancel(cmd, t);
      case VoiceIntent.markDone:
      case VoiceIntent.markMissed:
      case VoiceIntent.recordPayment:
      case VoiceIntent.addNote:
        await _withPatient(cmd, intent, t.isFinal, t.text);
      case VoiceIntent.editPatient:
        final opened = await _withPatient(cmd, intent, t.isFinal, t.text);
        if (opened && t.isFinal && cmd.confirmAtEnd) {
          unawaited(_confirmWhenReady());
        }
      case VoiceIntent.addPatient:
        _acted = true;
        _start(VoiceIntent.addPatient, null);
        _fill(cmd);
        _track(
          showDesktopAddEditPatientDialog(
            _context(),
            repository: _ref.read(patientRepositoryProvider),
          ).then((saved) => saved == true),
        );
        if (t.isFinal && !cmd.confirmAtEnd) _askSpelling();
        if (t.isFinal && cmd.confirmAtEnd) unawaited(_confirmWhenReady());
      case VoiceIntent.openPatient:
      case VoiceIntent.addAppointment:
      case VoiceIntent.reschedule:
        final opened = await _withPatient(cmd, intent, t.isFinal, t.text);
        if (opened && t.isFinal && cmd.confirmAtEnd) {
          unawaited(_confirmWhenReady());
        }
    }
  }

  /// "...no, Rahul Shah" while a booking for someone else is open: reopen
  /// the same form for the right patient, keeping what was said.
  Patient? _switchTo;

  bool _switchedPatient(VoiceCommand cmd, bool isFinal) {
    final selfCorrect = isFinal && _formOpenedNow;
    if (!(cmd.corrected || selfCorrect) || cmd.name.isEmpty) return false;
    if (_open != VoiceIntent.addAppointment &&
        _open != VoiceIntent.reschedule) {
      return false;
    }
    final m = matchPatient(cmd.name, _patients);
    if (!m.isSure || m.best!.id == _patient?.id) return false;
    _date = cmd.date ?? _date;
    _time = cmd.time ?? _time;
    _switchTo = m.best;
    _focus = m.best;
    understood.value = '${_label(_open!)} · ${m.best!.fullName}';
    VoiceBus.emit(const VoiceCancel());
    return true;
  }

  /// Saves once the form is on screen and has taken what was said.
  Future<void> _confirmWhenReady() async {
    for (var i = 0; i < 60 && !VoiceBus.formReady.value; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (_open != null) _confirm();
  }

  /// Returns whether a form was opened.
  Future<bool> _withPatient(
    VoiceCommand cmd,
    VoiceIntent intent,
    bool isFinal,
    String text,
  ) async {
    final label = _label(intent);
    if (cmd.name.isEmpty) {
      // "The last patient", "the next patient", "the newest patient".
      final kind = _patientRef(text);
      if (kind != null) {
        _acted = true;
        final p = await _resolveRef(kind);
        if (p != null) return _actOn(cmd, intent, p, isFinal);
        _acted = false;
        if (isFinal) {
          understood.value = switch (kind) {
            'next' => 'Nobody is booked next',
            'newest' => 'No patients yet',
            _ => 'No patient seen yet',
          };
        }
        return false;
      }
      // "Book him tomorrow", "move her appointment to Friday".
      final focus = _focus;
      if (focus != null && _refersBack(text, intent)) {
        return _actOn(cmd, intent, focus, isFinal);
      }
      // "The patient ending 3210", "number 98765 43210" (not a number
      // being put into their record).
      final ending =
          cmd.phoneEnding ??
          (intent == VoiceIntent.editPatient ? null : cmd.phone);
      if (ending != null) {
        String digits(String s) => s.replaceAll(RegExp(r'\D'), '');
        final hits = _patients
            .where((p) => digits(p.phone).endsWith(ending))
            .toList();
        if (hits.length == 1) return _actOn(cmd, intent, hits.first, isFinal);
        if (isFinal) {
          if (hits.isEmpty) {
            understood.value = 'No patient with a number ending $ending';
          } else {
            _askPatient(hits.take(4).toList(), (p) async {
              await _actOn(cmd, intent, p, true);
            });
          }
        }
        return false;
      }
      // "Mark as done", "paid 500": about whoever was just dealt with.
      const quick = {
        VoiceIntent.markDone,
        VoiceIntent.markMissed,
        VoiceIntent.recordPayment,
        VoiceIntent.addNote,
      };
      if (focus != null && quick.contains(intent)) {
        return _actOn(cmd, intent, focus, isFinal);
      }
      understood.value = '$label…';
      return false;
    }
    final match = matchPatient(cmd.name, _patients);
    if (!match.isSure && match.runnerUp != null) {
      // Several fit. Said which ("the 34-year-old", "ending 3210"), or one
      // of them is who the doctor was just dealing with: go ahead.
      final tied = match.tied.take(4).toList();
      final chosen =
          _pickDetail(cmd, text, tied, inline: true) ??
          tied.where((p) => p.id == _focus?.id).firstOrNull;
      if (chosen != null) return _actOn(cmd, intent, chosen, isFinal);
    }
    if (!match.isSure) {
      // Keep listening; only ask once the doctor has finished.
      final q = cmd.name.toLowerCase();
      final hits = _patients
          .where((p) => p.fullName.toLowerCase().contains(q))
          .length;
      if (!isFinal) {
        understood.value = '$label…';
      } else if (intent == VoiceIntent.openPatient && hits > 2) {
        _showPatientSearch(q, hits);
      } else if (match.runnerUp != null) {
        final tied = match.tied.take(4).toList();
        _askPatient(tied, (p) async {
          final opened = await _actOn(cmd, intent, p, true);
          if (opened && cmd.confirmAtEnd) unawaited(_confirmWhenReady());
        });
      } else if (intent == VoiceIntent.openPatient &&
          await _semanticNavigate(text)) {
        // "Show me who owes me money": a place, not a patient.
      } else {
        understood.value = 'No patient called "${cmd.name}"';
      }
      return false;
    }
    return _actOn(cmd, intent, match.best!, isFinal);
  }

  /// Which patient "the last / next / newest patient" means, if said:
  /// 'last' (last seen), 'next' (next booked) or 'newest' (last added).
  static String? _patientRef(String text) {
    final s = text.toLowerCase();
    if (!RegExp(r'\b(patient|one|person)\b').hasMatch(s)) return null;
    if (RegExp(
      r'\b(newest|latest|recently added|last added|just added)\b',
    ).hasMatch(s)) {
      return 'newest';
    }
    // "last name" is a field, not a patient.
    if (RegExp(r'\b(last|previous|prev|earlier)\b(?! name)').hasMatch(s)) {
      return 'last';
    }
    if (RegExp(r'\bnext\b').hasMatch(s)) return 'next';
    return null;
  }

  Patient? _byId(String id) => _patients.where((p) => p.id == id).firstOrNull;

  /// The patient seen most recently, with when; falls back to the one
  /// added or updated most recently when nobody has been seen yet.
  Future<({Patient patient, DateTime? seen})?> _lastSeen() async {
    try {
      final last = await _ref.read(lastVisitPerPatientProvider.future);
      final seen = last.entries
          .where((e) => _byId(e.key) != null)
          .fold<MapEntry<String, Visit>?>(
            null,
            (best, e) =>
                best == null ||
                    e.value.scheduledStart.isAfter(best.value.scheduledStart)
                ? e
                : best,
          );
      if (seen != null) {
        return (patient: _byId(seen.key)!, seen: seen.value.scheduledStart);
      }
    } catch (_) {}
    if (_patients.isEmpty) return null;
    final p = _patients.reduce(
      (a, b) => a.updatedAt.isAfter(b.updatedAt) ? a : b,
    );
    return (patient: p, seen: null);
  }

  Future<Patient?> _resolveRef(String kind) async {
    switch (kind) {
      case 'newest':
        return _patients.isEmpty
            ? null
            : _patients.reduce(
                (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
              );
      case 'next':
        final now = DateTime.now();
        final v = _upcoming
            .where(
              (v) =>
                  v.status == VisitStatus.scheduled &&
                  v.scheduledStart.isAfter(now),
            )
            .firstOrNull;
        return v == null ? null : _byId(v.patientId);
      default:
        return (await _lastSeen())?.patient;
    }
  }

  static final _pronoun = RegExp(
    r'\b(him|her|his|them|their|this patient|that patient|same patient)\b',
  );

  bool _refersBack(String text, VoiceIntent intent) {
    final s = text.toLowerCase();
    return _pronoun.hasMatch(s) ||
        (intent == VoiceIntent.reschedule && RegExp(r'\bit\b').hasMatch(s));
  }

  /// "Shah", "Rahul Shah", "the first one", "the other one".
  /// Puts a question on the pill; it expands with [options].
  void _ask(
    String prompt,
    List<VoiceChoice> options,
    Future<void> Function(int index) onPick, {
    int? Function(VoiceCommand cmd, String text)? match,
  }) {
    hint.value = null;
    ready.value = false;
    understood.value = prompt;
    asking.value = VoiceAsk(
      prompt: prompt,
      options: options,
      onPick: onPick,
      match: match,
    );
  }

  /// Answers the open question with option [index] (said or tapped).
  Future<void> pickChoice(int index) async {
    final q = asking.value;
    if (q == null || index < 0 || index >= q.options.length) return;
    asking.value = null;
    _acted = true;
    understood.value = q.options[index].label;
    await q.onPick(index);
  }

  int? _matchChoice(VoiceAsk q, VoiceCommand cmd, String text) {
    final custom = q.match?.call(cmd, text);
    if (custom != null) return custom;
    // The words as said, plus the parsed name, so a spelled-out answer
    // ("S A M E E R") matches "Sameer".
    final s =
        ' ${text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ' ')} ${cmd.name} ';
    for (var i = 0; i < q.options.length; i++) {
      final o = q.options[i];
      for (final w in [o.label.toLowerCase(), ...o.words]) {
        if (s.contains(' $w ')) return i;
      }
    }
    const ordinals = [
      ['first', '1st'],
      ['second', '2nd'],
      ['third', '3rd'],
      ['fourth', '4th'],
    ];
    for (var i = 0; i < q.options.length && i < ordinals.length; i++) {
      if (ordinals[i].any((o) => s.contains(' $o '))) return i;
    }
    return null;
  }

  /// "Which Rahul Patel?" with what tells them apart; [then] runs for the
  /// one said or tapped.
  void _askPatient(List<Patient> tied, Future<void> Function(Patient) then) {
    final sameName =
        tied.map((p) => p.fullName.trim().toLowerCase()).toSet().length == 1;
    _ask(
      sameName ? 'Which ${tied.first.fullName}?' : 'Which patient?',
      [for (final p in tied) VoiceChoice(p.fullName, detail: _describe(p))],
      (i) => then(tied[i]),
      match: (cmd, text) {
        final p = _pickDetail(cmd, text, tied);
        return p == null ? null : tied.indexOf(p);
      },
    );
  }

  /// Which of [choices] was meant: "the first one", "the 34-year-old",
  /// "ending 3210", "the older one", "the female one", "the one coming
  /// Friday", or the rest of the name. [inline] is the original command
  /// ("book Rahul Patel, the 34-year-old, …"): only details said on
  /// purpose count there, not stray numbers or dates.
  Patient? _pickDetail(
    VoiceCommand cmd,
    String text,
    List<Patient> choices, {
    bool inline = false,
  }) {
    if (choices.isEmpty) return null;
    Patient? only(Iterable<Patient> it) => it.length == 1 ? it.first : null;
    String digits(String s) => s.replaceAll(RegExp(r'\D'), '');
    final s = ' ${text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ' ')} ';

    if (!inline) {
      if (choices.length > 2 && RegExp(r' (third|3rd) ').hasMatch(s)) {
        return choices[2];
      }
      if (RegExp(r' (second|2nd|latter) ').hasMatch(s)) return choices[1];
      if (RegExp(r' (first|1st|former|top) ').hasMatch(s)) return choices.first;
      if (RegExp(r' (last|bottom) ').hasMatch(s)) return choices.last;
      if (choices.length == 2 && RegExp(r' other ').hasMatch(s)) {
        return choices.last;
      }
    }
    final ending =
        cmd.phoneEnding ??
        (inline ? null : RegExp(r' (\d{3,}) ').firstMatch(s)?.group(1));
    if (ending != null) {
      final p = only(choices.where((c) => digits(c.phone).endsWith(ending)));
      if (p != null) return p;
    }
    final age =
        cmd.age ??
        (inline
            ? null
            : int.tryParse(
                RegExp(r' (\d{1,3}) ').firstMatch(s)?.group(1) ?? '',
              ));
    if (age != null) {
      final p = only(choices.where((c) => c.age == age));
      if (p != null) return p;
    }
    if (RegExp(r' (older|elder|oldest|senior) ').hasMatch(s)) {
      return choices.reduce((a, b) => a.age >= b.age ? a : b);
    }
    if (RegExp(r' (younger|youngest|junior) ').hasMatch(s)) {
      return choices.reduce((a, b) => a.age <= b.age ? a : b);
    }
    final gender = cmd.gender;
    if (gender != null) {
      final p = only(
        choices.where((c) => c.gender.toLowerCase() == gender.toLowerCase()),
      );
      if (p != null) return p;
    }
    if (inline) return null;
    final day = cmd.date;
    if (day != null) {
      final p = only(
        choices.where(
          (c) => _upcoming.any(
            (v) =>
                v.patientId == c.id &&
                ApptsBuilder.sameDay(v.scheduledStart, day),
          ),
        ),
      );
      if (p != null) return p;
    }
    if (cmd.name.isEmpty) return null;
    final m = matchPatient(cmd.name, choices);
    return m.best != null && m.score >= 0.5 && m.runnerUp == null
        ? m.best
        : null;
  }

  /// "34 M · ···3210 · next Fri 2 Oct": what tells same-named patients
  /// apart.
  String _describe(Patient p) {
    final phone = p.phone.replaceAll(RegExp(r'\D'), '');
    final next = _upcoming
        .where((v) => v.patientId == p.id && v.status == VisitStatus.scheduled)
        .firstOrNull;
    return [
      [
        '${p.age}',
        if (p.gender.isNotEmpty) p.gender[0].toUpperCase(),
      ].join(' '),
      if (phone.length >= 4) '···${phone.substring(phone.length - 4)}',
      if (next != null)
        'next ${DateFormat('EEE d MMM').format(next.scheduledStart)}',
    ].join(' · ');
  }

  /// Does [intent] for patient [p]. Returns whether a form was opened.
  Future<bool> _actOn(
    VoiceCommand cmd,
    VoiceIntent intent,
    Patient p,
    bool isFinal,
  ) async {
    _acted = true;
    _focus = p;
    switch (intent) {
      case VoiceIntent.openPatient:
        understood.value = 'Opened ${p.fullName}';
        _openedNow = p;
        _history.add(_ref.read(shellCurrentTabProvider));
        DashboardActions.openPatient(_context(), p);
        return false;
      case VoiceIntent.addAppointment:
        _formOpenedNow = true;
        _start(VoiceIntent.addAppointment, p);
        _fill(cmd);
        _openAppointment(p);
        return true;
      case VoiceIntent.reschedule:
        _formOpenedNow = true;
        _start(VoiceIntent.reschedule, p);
        return _openReschedule(p, cmd: cmd);
      case VoiceIntent.editPatient:
        _formOpenedNow = true;
        _start(VoiceIntent.editPatient, p);
        _fill(cmd);
        _track(
          showDesktopAddEditPatientDialog(
            _context(),
            patient: p,
            repository: _ref.read(patientRepositoryProvider),
          ).then((saved) => saved == true),
        );
        return true;
      case VoiceIntent.markDone:
      case VoiceIntent.markMissed:
      case VoiceIntent.recordPayment:
      case VoiceIntent.addNote:
        // These change records: act on the final words only.
        if (!isFinal) {
          _acted = false;
          understood.value = '${_label(intent)} · ${p.fullName}';
          return false;
        }
        switch (intent) {
          case VoiceIntent.markDone:
            await _setStatus(p, VisitStatus.completed);
          case VoiceIntent.markMissed:
            await _setStatus(p, VisitStatus.missed);
          case VoiceIntent.recordPayment:
            await _askPayment(p, cmd.payment ?? 0);
          default:
            await _addNote(p, cmd.notes ?? '');
        }
        return false;
      default:
        return false;
    }
  }

  // ── Quick actions: status, payment, note ─────────────────────────────

  /// Old status or old notes, for undoing 'status' and 'note'.
  String? _undoText;

  Future<void> _setStatus(Patient p, VisitStatus status) async {
    final today = await _ref.read(todaysVisitsProvider.future);
    final visit = today
        .where((v) => v.patientId == p.id && v.status != VisitStatus.cancelled)
        .firstOrNull;
    if (visit == null) {
      understood.value = 'No visit today for ${p.fullName}';
      return;
    }
    final old = visit.status;
    try {
      await _ref.read(visitRepositoryProvider).updateStatus(visit.id, status);
    } catch (e) {
      understood.value = "Couldn't update: $e";
      return;
    }
    _undoText = old.name;
    _lastAction = (
      kind: 'status',
      who: p.fullName,
      visitId: visit.id,
      patientId: p.id,
      oldStart: null,
    );
    understood.value = status == VisitStatus.completed
        ? 'Marked done · ${p.fullName}'
        : 'Marked no-show · ${p.fullName}';
  }

  /// "Rahul paid 500": asks first, then records it on today's visit (or
  /// the last unpaid one).
  Future<void> _askPayment(Patient p, double amount) async {
    if (amount <= 0) {
      understood.value = 'How much did ${p.fullName} pay?';
      return;
    }
    final today = await _ref.read(todaysVisitsProvider.future);
    Visit? visit = today
        .where(
          (v) =>
              v.patientId == p.id &&
              !v.isPaid &&
              v.status != VisitStatus.cancelled,
        )
        .firstOrNull;
    if (visit == null) {
      final last = await _ref.read(lastVisitPerPatientProvider.future);
      final v = last[p.id];
      if (v != null && !v.isPaid) visit = v;
    }
    if (visit == null) {
      understood.value = 'No unpaid visit for ${p.fullName}';
      return;
    }
    final v = visit;
    final money =
        '₹${NumberFormat.decimalPattern('en_IN').format(amount.round())}';
    _ask(
      'Record $money from ${p.fullName} for ${_when(v.scheduledStart)}?',
      const [
        VoiceChoice(
          'Yes, record it',
          words: ['yes', 'yeah', 'confirm', 'sure', 'do it', 'record it'],
        ),
        VoiceChoice('No', words: ['no', 'nope', 'nah', 'dont', 'cancel']),
      ],
      (i) async {
        if (i == 1) {
          understood.value = 'Not recorded';
          return;
        }
        try {
          await _ref
              .read(visitRepositoryProvider)
              .recordPayment(v.id, amount: amount);
          understood.value = '$money recorded · ${p.fullName}';
        } catch (e) {
          understood.value = "Couldn't record: $e";
        }
      },
    );
  }

  /// "Add a note to his file: allergic to penicillin".
  Future<void> _addNote(Patient p, String note) async {
    if (note.trim().isEmpty) {
      understood.value = 'What should the note say?';
      return;
    }
    final old = (_byId(p.id) ?? p).notes;
    final text = [
      old.trim(),
      note.trim(),
    ].where((s) => s.isNotEmpty).join('\n');
    try {
      await _ref.read(patientRepositoryProvider).updateDoctorsNote(p.id, text);
    } catch (e) {
      understood.value = "Couldn't add the note: $e";
      return;
    }
    _undoText = old;
    _lastAction = (
      kind: 'note',
      who: p.fullName,
      visitId: null,
      patientId: p.id,
      oldStart: null,
    );
    understood.value = 'Note added · ${p.fullName}';
  }

  // ── Spelling of a new patient's name ─────────────────────────────────

  /// Name parts already asked about, so each is asked once.
  final _spellAsked = <String>{};

  /// Ways [word] could be written: as heard, as another patient writes a
  /// name that sounds the same, and the common Indian variants (Samir /
  /// Sameer, Puja / Pooja, Preeti / Priti). Heard first; at most three.
  List<String> _spellings(String word) {
    final w = word.toLowerCase();
    final out = <String>[w];
    void add(String v) {
      if (v != w && v.length > 2 && !out.contains(v)) out.add(v);
    }

    for (final p in _patients) {
      for (final part in p.fullName.toLowerCase().split(' ')) {
        if (soundsAlike(part, w) && part != w) add(part);
      }
    }
    if (w.contains('ee')) add(w.replaceFirst('ee', 'i'));
    if (w.contains('oo')) add(w.replaceFirst('oo', 'u'));
    if (w.contains('aa')) add(w.replaceFirst('aa', 'a'));
    // Preethi / Preeti; not Smith / Smit.
    if (RegExp('th[aeiou]').hasMatch(w)) add(w.replaceFirst('th', 't'));
    // "samir" → "sameer", "sunil" → "suneel": an i before the last
    // consonant; "puja" → "pooja": a u before the last syllable.
    final i = RegExp(r'[^aeiou]i[^aeiou]$').firstMatch(w);
    if (i != null) {
      add('${w.substring(0, i.start + 1)}ee${w.substring(i.start + 2)}');
    }
    final u = RegExp(r'[^aeiou]u[^aeiou]a$').firstMatch(w);
    if (u != null) {
      add('${w.substring(0, u.start + 1)}oo${w.substring(u.start + 2)}');
    }
    return out.take(3).toList();
  }

  /// After a new patient's name is heard, asks how an ambiguous part is
  /// spelled: first name, then surname.
  void _askSpelling() {
    final name = _newName;
    if (_open != VoiceIntent.addPatient || name == null) return;
    if (asking.value != null) return;
    final parts = name.split(' ');
    for (var k = 0; k < parts.length && k < 2; k++) {
      final part = k == 0 ? parts.first : parts.sublist(1).join(' ');
      if (part.contains(' ') || _spellAsked.contains(part.toLowerCase())) {
        continue;
      }
      final options = _spellings(part);
      _spellAsked.add(part.toLowerCase());
      if (options.length < 2) continue;
      final taken = {
        for (final p in _patients)
          for (final w in p.fullName.toLowerCase().split(' ')) w,
      };
      _ask(
        'How is "${_title(part)}" spelled?',
        [
          for (var i = 0; i < options.length; i++)
            VoiceChoice(
              _title(options[i]),
              detail: i == 0
                  ? 'as heard'
                  : taken.contains(options[i])
                  ? 'as another patient writes it'
                  : null,
              words: [options[i]],
            ),
        ],
        (i) async {
          final chosen = _title(options[i]);
          final now = (_newName ?? name).split(' ');
          if (k == 0) {
            now[0] = chosen;
          } else {
            now
              ..removeRange(1, now.length)
              ..add(chosen);
          }
          _newName = now.join(' ');
          VoiceBus.emit(
            VoiceFill(
              firstName: k == 0 ? chosen : null,
              lastName: k == 0 ? null : chosen,
            ),
          );
          understood.value = 'Add patient · $_newName';
          _askSpelling();
        },
      );
      return;
    }
  }

  // ── Forms opened by hand ─────────────────────────────────────────────

  /// Voice is filling a form it didn't open.
  bool _adopted = false;

  void _adopt(String kind) {
    _start(switch (kind) {
      'addPatient' => VoiceIntent.addPatient,
      'editPatient' => VoiceIntent.editPatient,
      'reschedule' => VoiceIntent.reschedule,
      _ => VoiceIntent.addAppointment,
    }, null);
    _adopted = true;
  }

  void _onFormKind() {
    if (VoiceBus.openKind.value != null || !_adopted) return;
    _adopted = false;
    _open = null;
    _patient = null;
    ready.value = false;
    hint.value = null;
  }

  static final _changeCue = RegExp(
    r'\b(nah|no|nope|actually|instead|rather|change|make it|move|shift|'
    r'switch|one thing|wait|sorry|update|put it|keep it)\b',
  );
  static final _bookingRef = RegExp(
    r'\b(his|her|their|that|the|this|same) (appointment|booking|visit|slot)\b',
  );
  static final _another = RegExp(
    r'\b(another|one more|also|second|additional|extra|as well|too|new appointment)\b',
  );

  /// Is [text] changing the booking just made, rather than a new one?
  bool _changesRecent(
    VoiceCommand cmd,
    VoiceIntent intent,
    String text,
    ({Patient patient, String visitId, DateTime at}) r,
  ) {
    if (DateTime.now().difference(r.at) > const Duration(minutes: 15)) {
      return false;
    }
    final s = text.toLowerCase();
    if (_another.hasMatch(s)) return false;
    final changing = _changeCue.hasMatch(s) || _bookingRef.hasMatch(s);
    final timed =
        cmd.date != null ||
        cmd.time != null ||
        cmd.shiftMinutes != null ||
        cmd.slot != null;
    final fits = switch (intent) {
      VoiceIntent.addAppointment => changing,
      VoiceIntent.reschedule => true,
      VoiceIntent.none => changing && timed,
      _ => false,
    };
    if (!fits) return false;
    if (cmd.name.isEmpty) return true;
    final m = matchPatient(cmd.name, _patients);
    return (m.isSure && m.best!.id == r.patient.id) ||
        (m.score >= 0.7 && m.tied.any((p) => p.id == r.patient.id));
  }

  /// "Cancel Rahul's appointment", "nah, cancel it": asks first.
  Future<void> _askCancel(
    VoiceCommand cmd,
    VoiceTranscript t, {
    Patient? chosen,
  }) async {
    if (!t.isFinal) {
      understood.value = 'Cancel appointment…';
      return;
    }
    Patient? p;
    String? visitId;
    final recent = _recent;
    if (chosen != null) {
      p = chosen;
      if (recent != null && recent.patient.id == p.id) {
        visitId = recent.visitId;
      }
    } else if (cmd.name.isNotEmpty) {
      final m = matchPatient(cmd.name, _patients);
      if (!m.isSure) {
        if (m.runnerUp == null) {
          understood.value = 'No patient called "${cmd.name}"';
          return;
        }
        final tied = m.tied.take(4).toList();
        final pick =
            _pickDetail(cmd, t.text, tied, inline: true) ??
            tied.where((c) => c.id == recent?.patient.id).firstOrNull ??
            tied.where((c) => c.id == _focus?.id).firstOrNull;
        if (pick == null) {
          _askPatient(tied, (c) => _askCancel(cmd, t, chosen: c));
          return;
        }
        p = pick;
      } else {
        p = m.best;
      }
      if (recent != null && recent.patient.id == p!.id) {
        visitId = recent.visitId;
      }
    } else if (recent != null) {
      p = recent.patient;
      visitId = recent.visitId;
    } else {
      p = _focus;
    }
    if (p == null) {
      understood.value = 'Whose appointment?';
      return;
    }
    final visits = await _ref.read(upcomingVisitsProvider.future);
    final mine = visits.where((v) => v.patientId == p!.id);
    final visit =
        (visitId == null
            ? null
            : mine.where((v) => v.id == visitId).firstOrNull) ??
        mine.firstOrNull;
    if (visit == null) {
      understood.value = '${p.fullName} has no upcoming appointment';
      return;
    }
    _acted = true;
    _focus = p;
    final who = p;
    _ask(
      'Cancel ${who.fullName}, ${_when(visit.scheduledStart)}?',
      const [
        VoiceChoice(
          'Yes, cancel it',
          words: [
            'yes',
            'yeah',
            'confirm',
            'sure',
            'do it',
            'go ahead',
            'cancel it',
          ],
        ),
        VoiceChoice(
          'No, keep it',
          words: [
            'no',
            'nope',
            'nah',
            'keep',
            'dont',
            'leave',
            'never',
            'cancel',
          ],
        ),
      ],
      (i) async {
        if (i == 1) {
          understood.value = 'Kept the appointment';
          return;
        }
        await _ref.read(visitRepositoryProvider).cancelVisit(visit.id);
        if (_recent?.visitId == visit.id) _recent = null;
        _lastAction = (
          kind: 'cancelled',
          who: who.fullName,
          visitId: visit.id,
          patientId: who.id,
          oldStart: visit.scheduledStart,
        );
        understood.value =
            'Cancelled · ${who.fullName}, ${_when(visit.scheduledStart)}';
      },
    );
  }

  /// Remembers the visit a voice booking just created (the newest one).
  Future<void> _rememberBooking(Patient p) async {
    final visits = await _ref
        .read(visitRepositoryProvider)
        .watchUpcomingVisits()
        .first;
    final mine = visits.where((v) => v.patientId == p.id).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (mine.isEmpty) return;
    _recent = (patient: p, visitId: mine.first.id, at: DateTime.now());
    _lastAction = (
      kind: 'booked',
      who: p.fullName,
      visitId: mine.first.id,
      patientId: p.id,
      oldStart: null,
    );
  }

  String _when(DateTime start) {
    final now = DateTime.now();
    final day = ApptsBuilder.sameDay(start, now)
        ? 'today'
        : ApptsBuilder.sameDay(start, now.add(const Duration(days: 1)))
        ? 'tomorrow'
        : DateFormat('EEE d MMM').format(start);
    return '$day ${_fmtTime(TimeOfDay.fromDateTime(start))}';
  }

  void _openAppointment(Patient p) {
    _track(
      showDesktopScheduleVisitDialog(
        _context(),
        patient: p,
        visitRepository: _ref.read(visitRepositoryProvider),
        initialStart: _startTime,
      ),
    );
  }

  Future<bool> _openReschedule(
    Patient p, {
    String? visitId,
    VoiceCommand? cmd,
  }) async {
    final visits = await _ref.read(upcomingVisitsProvider.future);
    final mine = visits.where((v) => v.patientId == p.id);
    final visit =
        (visitId == null
            ? null
            : mine.where((v) => v.id == visitId).firstOrNull) ??
        mine.firstOrNull;
    if (visit == null) {
      understood.value = '${p.fullName} has no upcoming appointment';
      _open = null;
      _patient = null;
      return false;
    }
    _openVisitId = visit.id;
    _openVisitStart = visit.scheduledStart;
    if (cmd != null) _fill(cmd);
    final item = ApptsBuilder.items(
      visits: [visit],
      patients: [p],
      todaysQueue: const [],
      now: DateTime.now(),
    ).first;
    final ctx = _context();
    if (!ctx.mounted) return false;
    _track(
      showRescheduleVisitDialog(
        ctx,
        item: item,
        initialStart: _startTime,
      ).then((moved) => moved != null),
    );
    return true;
  }

  // ── Moving around the app ──────────────────────────────────────────

  /// The question already answered live in this utterance.
  String? _answeredLive;

  /// Where this utterance already navigated to, so later partials only
  /// act when the target changes ("schedule" → "schedule for Friday").
  NavTarget? _navNow;

  /// Tabs visited by voice, for "go back".
  final _history = <int>[];

  List<({int tab, String label})> _visibleTabs() => [
    ...sidebarTabs(
      dentist: _ref.read(isDentistProvider),
      radiologist: _ref.read(isOralRadiologistProvider),
      sub: _ref.read(activeDentalSubspecialtyProvider),
    ),
    (tab: DesktopTab.settings, label: 'Settings'),
  ];

  /// Screens, "go back", "help" and quick questions. Returns true when
  /// the utterance was about those rather than a patient or a form.
  bool _tryNavigate(VoiceTranscript t, VoiceCommand cmd) {
    const forms = {
      VoiceIntent.addPatient,
      VoiceIntent.reschedule,
      VoiceIntent.confirm,
      VoiceIntent.editPatient,
      VoiceIntent.cancelAppointment,
    };
    final result = resolveNavigation(t.text, _visibleTabs(), DateTime.now());
    // Questions first: "when is Rahul's next appointment?" names a patient.
    if (result is NavAsk) {
      // Answered live, while still talking, once the words already make a
      // whole question; each distinct question once per utterance. Ones
      // that might need the choice card wait for the final words.
      final needsCard =
          result.question == VoiceQuestion.patientNext ||
          (result.question == VoiceQuestion.revenue && result.period == null);
      final key =
          '${result.question}|${result.date}|${result.period}|${result.slot}';
      if (t.isFinal
          ? key != _answeredLive
          : !needsCard && key != _answeredLive) {
        _answeredLive = t.isFinal ? null : key;
        unawaited(_answer(result));
      }
      return true;
    }
    // "Open the last patient" is a patient, not the Patients screen.
    if (_patientRef(t.text) != null) return false;
    if (forms.contains(cmd.intent)) return false;
    // A patient's name wins: "open Rahul Patel", "show Priya's file".
    if (cmd.name.isNotEmpty && matchPatient(cmd.name, _patients).isSure) {
      return false;
    }
    switch (result) {
      case NavNone():
        if (t.isFinal && cmd.intent == VoiceIntent.cancel) {
          final nav = Navigator.of(_context(), rootNavigator: true);
          if (nav.canPop()) {
            nav.pop();
          } else if (_recent != null) {
            // Nothing to close: "cancel it" means the booking just made.
            unawaited(_askCancel(cmd, t));
          }
          return true;
        }
        return false;
      case NavUnavailable(:final tab):
        understood.value = "${DesktopTab.label(tab)} isn't in your sidebar";
        return true;
      case NavHelp():
        understood.value =
            'Try: "book Rahul tomorrow at 5 and confirm" · "add patient…" · '
            '"move Priya to Friday" · "open Rahul" · "show low stock" · '
            '"who owes me money?" · "dark mode" · "who\'s next?"';
        return true;
      case NavBack():
        if (t.isFinal) _goBack();
        return true;
      case NavAsk():
        if (t.isFinal) unawaited(_answer(result));
        return true;
      case NavScreen(:final target):
        if (!target.sameAs(_navNow)) {
          _navNow = target;
          _navigate(target);
        }
        return true;
    }
  }

  void _navigate(NavTarget target) {
    final tab = target.tab;
    String? name;
    if (tab != null) {
      final go = _ref.read(shellNavigatorProvider);
      if (go == null) {
        understood.value = "Can't switch screens here";
        return;
      }
      // Close any page or dialog on top first.
      Navigator.of(_context(), rootNavigator: true).popUntil((r) => r.isFirst);
      final from = _ref.read(shellCurrentTabProvider);
      if (from != tab && (_history.isEmpty || _history.last != from)) {
        _history.add(from);
      }
      go(tab);
      final appts = _ref.read(apptsControllerProvider.notifier);
      if (target.view != null) appts.setView(target.view!);
      if (target.date != null) appts.goTo(target.date!);
      name = tab == DesktopTab.queue ? 'Queue' : DesktopTab.label(tab);
    }
    final spots = [for (final id in target.spots) ?_applySpot(id)];

    understood.value = [
      ?name,
      ...spots,
      if (target.view != null && target.date == null)
        '${target.view!.label} view',
      if (target.date != null) DateFormat('EEE d MMM').format(target.date!),
    ].join(' · ');
  }

  /// Opens one in-screen spot; returns its name for the pill.
  String? _applySpot(String id) {
    void section(SettingsSection s) =>
        _ref.read(settingsSectionProvider.notifier).state = s;
    void theme(AppearanceMode m) =>
        unawaited(_ref.read(appearanceModeProvider.notifier).select(m));
    final inventory = _ref.read(inventoryControllerProvider.notifier);
    final revenue = _ref.read(revenueViewControllerProvider.notifier);
    final patients = _ref.read(patientsListControllerProvider.notifier);
    void patientFilter(PatientFilter f) {
      patients.closeDetails();
      patients.setQuery('');
      patients.setFilter(f);
    }

    switch (id) {
      case 'settings.profile':
        section(SettingsSection.profile);
      case 'settings.clinic':
        section(SettingsSection.clinic);
      case 'settings.accounts':
        section(SettingsSection.accounts);
      case 'settings.devices':
        section(SettingsSection.devices);
      case 'settings.appearance':
        section(SettingsSection.appearance);
      case 'settings.dental':
        section(SettingsSection.dental);
      case 'settings.radiology':
        section(SettingsSection.radiology);
      case 'settings.about':
        section(SettingsSection.about);
      case 'theme.evening':
        theme(AppearanceMode.evening);
      case 'theme.day':
        theme(AppearanceMode.day);
      case 'theme.auto':
        theme(AppearanceMode.auto);
      case 'inventory.items':
        inventory.setTab(InventoryTab.items);
        inventory.setFilter(InventoryFilter.all);
      case 'inventory.orders':
        inventory.setTab(InventoryTab.orders);
      case 'inventory.vendors':
        inventory.setTab(InventoryTab.vendors);
      case 'inventory.usage':
        inventory.setTab(InventoryTab.usage);
      case 'inventory.low':
        inventory.setTab(InventoryTab.items);
        inventory.setFilter(InventoryFilter.low);
      case 'inventory.expiring':
        inventory.setTab(InventoryTab.items);
        inventory.setFilter(InventoryFilter.expiring);
      case 'revenue.overview':
        revenue.setTab(RevenueTab.overview);
      case 'revenue.invoices':
        revenue.setTab(RevenueTab.invoices);
      case 'revenue.in':
        revenue.setFilter(TxnFilter.moneyIn);
      case 'revenue.out':
        revenue.setFilter(TxnFilter.moneyOut);
      case 'revenue.period.today':
        revenue.setPeriod(RevenuePeriod.today);
        return 'Today';
      case 'revenue.period.week':
        revenue.setPeriod(RevenuePeriod.week);
        return 'This week';
      case 'revenue.period.month':
        revenue.setPeriod(RevenuePeriod.month);
        return 'This month';
      case 'revenue.period.year':
        revenue.setPeriod(RevenuePeriod.year);
        return 'This year';
      case 'patients.overdue':
        patientFilter(PatientFilter.followUpOverdue);
      case 'patients.balance':
        patientFilter(PatientFilter.balanceDue);
      case 'patients.treatment':
        patientFilter(PatientFilter.inTreatment);
      case 'patients.new':
        patientFilter(PatientFilter.newThisMonth);
      case 'patients.recent':
        patientFilter(PatientFilter.last7Days);
      case 'patients.all':
        patientFilter(PatientFilter.all);
      case 'action.newVisit':
        unawaited(DashboardActions.newVisit(_context()));
    }
    return voiceSpots.where((s) => s.id == id).firstOrNull?.label;
  }

  /// "Find Sharma" with several Sharmas: the Patients list, searched.
  void _showPatientSearch(String query, int count) {
    _navigate(const NavTarget(tab: DesktopTab.patients));
    final patients = _ref.read(patientsListControllerProvider.notifier);
    patients.closeDetails();
    patients.setFilter(PatientFilter.all);
    patients.setQuery(query);
    understood.value = '$count patients match "$query"';
  }

  /// Phrasings the rules don't know ("who hasn't paid me yet"): the
  /// meaning-matcher picks the closest place, if it is close enough.
  Future<bool> _semanticNavigate(String text) async {
    if (text.trim().split(RegExp(r'\s+')).length < 2) return false;
    final hit = await SpeechEngine.instance.closestMeaning(
      text,
      semanticOptions(_visibleTabs()),
    );
    if (hit == null || hit.$2 < 0.5) return false;
    final target = targetFromOption(hit.$1);
    if (target == null) return false;
    _navigate(target);
    return true;
  }

  void _goBack() {
    final nav = Navigator.of(_context(), rootNavigator: true);
    if (nav.canPop()) {
      nav.pop();
      understood.value = 'Back';
      return;
    }
    final go = _ref.read(shellNavigatorProvider);
    if (go == null) return;
    final tab = _history.isEmpty ? DesktopTab.dashboard : _history.removeLast();
    go(tab);
    understood.value = 'Back to ${DesktopTab.label(tab)}';
  }

  /// Answers in the pill from what the app already has on hand.
  Future<void> _answer(NavAsk ask) async {
    String name(String patientId) =>
        _patients.where((p) => p.id == patientId).firstOrNull?.fullName ??
        'a patient';
    final now = DateTime.now();
    switch (ask.question) {
      case VoiceQuestion.countPatients:
        understood.value = 'You have ${_patients.length} patients';
      case VoiceQuestion.lastPatient:
        final last = await _lastSeen();
        if (last == null) {
          understood.value = 'No patient seen yet';
        } else {
          _focus = last.patient;
          understood.value = last.seen == null
              ? 'Last: ${last.patient.fullName}'
              : 'Last seen: ${last.patient.fullName} · ${_when(last.seen!)}';
        }
      case VoiceQuestion.nextPatient:
        final visits = await _ref.read(upcomingVisitsProvider.future);
        final next = visits
            .where(
              (v) =>
                  v.status == VisitStatus.scheduled &&
                  v.scheduledStart.isAfter(now),
            )
            .firstOrNull;
        understood.value = next == null
            ? 'Nobody else is booked'
            : 'Next: ${name(next.patientId)} at '
                  '${_fmtTime(TimeOfDay.fromDateTime(next.scheduledStart))}'
                  '${ApptsBuilder.sameDay(next.scheduledStart, now) ? '' : ', ${DateFormat('EEE d MMM').format(next.scheduledStart)}'}';
      case VoiceQuestion.countAppointments:
        final day = ask.date ?? now;
        final isToday = ApptsBuilder.sameDay(day, now);
        final visits = isToday
            ? await _ref.read(todaysVisitsProvider.future)
            : await _ref.read(upcomingVisitsProvider.future);
        final count = visits
            .where(
              (v) =>
                  ApptsBuilder.sameDay(v.scheduledStart, day) &&
                  v.status != VisitStatus.cancelled,
            )
            .length;
        final when = isToday
            ? 'today'
            : ApptsBuilder.sameDay(day, now.add(const Duration(days: 1)))
            ? 'tomorrow'
            : 'on ${DateFormat('EEE d MMM').format(day)}';
        understood.value = count == 0
            ? 'No appointments $when'
            : '$count appointment${count == 1 ? '' : 's'} $when';
      case VoiceQuestion.waiting:
        final n = _ref.read(waitingNowCountProvider);
        understood.value = n == 0
            ? 'Nobody is waiting'
            : '$n waiting${n == 1 ? '' : ' now'}';
      case VoiceQuestion.patientNext:
        Patient? p;
        if (ask.name.isNotEmpty) {
          final m = matchPatient(ask.name, _patients);
          if (m.isSure) {
            p = m.best;
          } else if (m.runnerUp != null) {
            final tied = m.tied.take(4).toList();
            p = tied.where((c) => c.id == _focus?.id).firstOrNull;
            if (p == null) {
              _askPatient(tied, (c) async {
                _focus = c;
                await _answer(const NavAsk(VoiceQuestion.patientNext));
              });
              return;
            }
          }
        } else {
          p = _focus;
        }
        if (p == null) {
          understood.value = ask.name.isEmpty
              ? 'Whose appointment?'
              : 'No patient called "${ask.name}"';
          return;
        }
        _focus = p;
        final visits = await _ref.read(upcomingVisitsProvider.future);
        final next = visits
            .where(
              (v) => v.patientId == p!.id && v.status == VisitStatus.scheduled,
            )
            .firstOrNull;
        understood.value = next == null
            ? '${p.fullName} has no upcoming appointment'
            : '${p.fullName} · ${_when(next.scheduledStart)}';
      case VoiceQuestion.freeSlot:
        final slot = _findSlot(ask.date, ask.slot ?? 'any');
        understood.value = slot == null
            ? 'No free slot ${ask.date == null ? 'this week' : 'that day'}'
            : 'First free slot: ${_when(slot)}';
      case VoiceQuestion.revenue:
        if (ask.period == null) {
          const periods = ['today', 'week', 'month', 'year'];
          _ask(
            'Collected over which period?',
            const [
              VoiceChoice('Today', words: ['today', 'daily', 'day']),
              VoiceChoice('This week', words: ['week', 'weekly']),
              VoiceChoice('This month', words: ['month', 'monthly']),
              VoiceChoice('This year', words: ['year', 'yearly', 'annual']),
            ],
            (i) => _answer(NavAsk(VoiceQuestion.revenue, period: periods[i])),
          );
          return;
        }
        final period = switch (ask.period) {
          'week' => RevenuePeriod.week,
          'month' => RevenuePeriod.month,
          'year' => RevenuePeriod.year,
          _ => RevenuePeriod.today,
        };
        _ref.read(revenueViewControllerProvider.notifier).setPeriod(period);
        RevenueOverview? o;
        for (var i = 0; i < 60; i++) {
          o = _ref.read(revenueOverviewProvider);
          if (o != null) break;
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        final label = switch (period) {
          RevenuePeriod.today => 'today',
          RevenuePeriod.week => 'this week',
          RevenuePeriod.month => 'this month',
          RevenuePeriod.year => 'this year',
        };
        understood.value = o == null
            ? "Revenue isn't loaded yet"
            : '₹${NumberFormat.decimalPattern('en_IN').format(o.collected.round())}'
                  ' collected $label';
    }
  }

  // ── Free slots and undo ──────────────────────────────────────────────

  /// The first free [minutes]-long start in [part] of [day] ('morning' 9–12,
  /// 'afternoon' 12–5, 'evening' 5–9, 'any' 9–9), on the 15-minute grid,
  /// not before now. With no [day], looks through the next week.
  DateTime? _findSlot(
    DateTime? day,
    String part, {
    int minutes = 30,
    String? excludeVisitId,
  }) {
    final (from, to) = switch (part) {
      'morning' => (9, 12),
      'afternoon' => (12, 17),
      'evening' => (17, 21),
      _ => (9, 21),
    };
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = day == null
        ? [for (var i = 0; i < 7; i++) today.add(Duration(days: i))]
        : [ApptsBuilder.dateOnly(day)];
    for (final d in days) {
      var t = DateTime(d.year, d.month, d.day, from);
      final end = DateTime(d.year, d.month, d.day, to);
      if (t.isBefore(now)) {
        final q = now.minute % 15 == 0
            ? now.minute
            : now.minute + 15 - now.minute % 15;
        t = DateTime(
          now.year,
          now.month,
          now.day,
          now.hour,
        ).add(Duration(minutes: q));
      }
      final busy = [
        for (final v in _upcoming)
          if (v.id != excludeVisitId &&
              v.status == VisitStatus.scheduled &&
              ApptsBuilder.sameDay(v.scheduledStart, d))
            (
              v.scheduledStart,
              v.scheduledStart.add(Duration(minutes: v.durationMinutes)),
            ),
      ];
      while (!t.add(Duration(minutes: minutes)).isAfter(end)) {
        final e = t.add(Duration(minutes: minutes));
        if (!busy.any((b) => t.isBefore(b.$2) && e.isAfter(b.$1))) return t;
        t = t.add(const Duration(minutes: 15));
      }
    }
    return null;
  }

  static bool _isUndo(String text) {
    final s = text.toLowerCase();
    return RegExp(r'\b(undo|revert)\b').hasMatch(s) ||
        s.contains('take that back') ||
        s.contains('reverse that');
  }

  /// Reverses the last change voice made.
  Future<void> _undo() async {
    final a = _lastAction;
    if (a == null) {
      understood.value = 'Nothing to undo';
      return;
    }
    _lastAction = null;
    final visits = _ref.read(visitRepositoryProvider);
    try {
      switch (a.kind) {
        case 'booked':
          await visits.cancelVisit(a.visitId!);
          _recent = null;
          understood.value = 'Undone · ${a.who}\'s booking removed';
        case 'moved':
          await visits.rescheduleVisit(
            a.visitId!,
            newStart: a.oldStart!,
            acknowledgeOverlap: true,
          );
          understood.value = 'Undone · ${a.who} back to ${_when(a.oldStart!)}';
        case 'cancelled':
          await visits.updateStatus(a.visitId!, VisitStatus.scheduled);
          understood.value = 'Undone · ${a.who}\'s appointment restored';
        case 'status':
          await visits.updateStatus(
            a.visitId!,
            VisitStatus.values.byName(_undoText ?? 'scheduled'),
          );
          understood.value = 'Undone · ${a.who}\'s visit status restored';
        case 'note':
          await _ref
              .read(patientRepositoryProvider)
              .updateDoctorsNote(a.patientId!, _undoText ?? '');
          understood.value = 'Undone · ${a.who}\'s note removed';
        case 'added':
          await _ref
              .read(patientRepositoryProvider)
              .deletePatient(a.patientId!);
          if (_focus?.id == a.patientId) _focus = null;
          understood.value = 'Undone · ${a.who} removed';
      }
    } catch (e) {
      understood.value = "Couldn't undo: $e";
    }
  }

  void _start(VoiceIntent intent, Patient? p) {
    _open = intent;
    _patient = p;
    _date = null;
    _time = null;
    _newName = null;
    _spellAsked.clear();
    _notesBefore = '';
    _notesNow = null;
    VoiceBus.last = null;
    VoiceBus.missing.value = const [];
  }

  /// Sends what was heard to the open form and updates the strip.
  void _fill(VoiceCommand cmd) {
    final open = _open!;
    var date = cmd.date;
    var time = cmd.time;
    String? slotNote;
    final booking =
        open == VoiceIntent.addAppointment || open == VoiceIntent.reschedule;
    final shift = cmd.shiftMinutes;
    final base = _shiftBase ?? _openVisitStart;
    if (open == VoiceIntent.reschedule &&
        shift != null &&
        time == null &&
        base != null) {
      final moved = base.add(Duration(minutes: shift));
      date = ApptsBuilder.dateOnly(moved);
      time = TimeOfDay.fromDateTime(moved);
      slotNote = '${shift > 0 ? '+' : '−'}${shift.abs()} min';
    }
    if (booking && time == null && cmd.slot != null) {
      final found = _findSlot(
        date ?? _date,
        cmd.slot!,
        excludeVisitId: open == VoiceIntent.reschedule ? _openVisitId : null,
      );
      if (found != null) {
        date = ApptsBuilder.dateOnly(found);
        time = TimeOfDay.fromDateTime(found);
        slotNote = 'first free slot';
      }
    }
    _date = date ?? _date;
    _time = time ?? _time;

    // New patient's name: said explicitly ("surname Shah"), or the
    // left-over words of the utterance that asked to add them. Left-over
    // words later on ("…born in 1990") must not overwrite the name.
    String? first = cmd.firstName, last = cmd.lastName;
    if (open == VoiceIntent.addPatient &&
        first == null &&
        last == null &&
        cmd.name.isNotEmpty &&
        (cmd.intent == VoiceIntent.addPatient ||
            cmd.corrected ||
            _newName == null)) {
      final words = cmd.name.split(' ').map(_title).toList();
      first = words.first;
      last = words.length > 1 ? words.sublist(1).join(' ') : null;
    }
    // A later "S A M I R" (or a re-said "Sameer") fixes the part of the
    // name it sounds like, instead of being ignored or added.
    final said = cmd.name.trim();
    if (open == VoiceIntent.addPatient &&
        first == null &&
        last == null &&
        _newName != null &&
        said.isNotEmpty &&
        !said.contains(' ')) {
      final parts = _newName!.split(' ');
      final lastPart = parts.length > 1 ? parts.sublist(1).join(' ') : '';
      if (soundsAlike(parts.first.toLowerCase(), said)) {
        first = _title(said);
      } else if (lastPart.isNotEmpty &&
          soundsAlike(lastPart.toLowerCase(), said)) {
        last = _title(said);
      }
    }
    if (open == VoiceIntent.addPatient && (first != null || last != null)) {
      final parts = (_newName ?? '').split(' ');
      final f = first ?? (parts.first.isEmpty ? null : parts.first);
      final l = last ?? (parts.length > 1 ? parts.sublist(1).join(' ') : null);
      _newName = [f, l].whereType<String>().join(' ');
    }

    if (cmd.notes != null) _notesNow = cmd.notes;
    final notes = _notesNow == null
        ? null
        : _joinNotes(_notesBefore, _notesNow!);

    // Other patients booked together, for a new appointment.
    final others = <Patient>[];
    if (open == VoiceIntent.addAppointment) {
      for (final n in [cmd.name, ...cmd.otherNames]) {
        if (n.length < 3) continue;
        final m = matchPatient(n, _patients);
        if (m.isSure && m.best!.id != _patient?.id) others.add(m.best!);
      }
    }
    // "Suffering from tooth pain" is the visit reason on an appointment.
    final reason =
        cmd.reason ??
        (open != VoiceIntent.addPatient && cmd.conditions.isNotEmpty
            ? cmd.conditions.join(', ')
            : null);

    VoiceBus.emit(
      VoiceFill(
        date: date,
        time: time,
        firstName: first,
        lastName: last,
        age: cmd.age,
        dateOfBirth: cmd.dateOfBirth,
        gender: cmd.gender,
        phone: cmd.phone,
        email: cmd.email,
        conditions: cmd.conditions,
        notes: notes,
        balance: cmd.balance,
        reason: reason,
        durationMinutes: cmd.durationMinutes,
        homeVisit: cmd.homeVisit,
        address: cmd.address,
        sendWhatsApp: cmd.sendWhatsApp,
        addToQueue: cmd.addToQueue,
        others: others,
      ),
    );

    // The strip: who, when, then what this utterance just added.
    final dupes = open == VoiceIntent.addPatient && _newName != null
        ? _patients
              .where(
                (p) =>
                    p.fullName.trim().toLowerCase() ==
                    _newName!.trim().toLowerCase(),
              )
              .toList()
        : const <Patient>[];
    final heard = <String>[
      if (dupes.isNotEmpty)
        'already have ${dupes.length == 1 ? 'a' : dupes.length} $_newName '
            '(${_describe(dupes.first)})',
      ?slotNote,
      if (cmd.dateOfBirth != null)
        'born ${DateFormat('d MMM y').format(cmd.dateOfBirth!)}'
      else if (cmd.age != null)
        '${cmd.age} yrs',
      ?cmd.gender,
      ?cmd.phone,
      ?cmd.email,
      ...cmd.conditions,
      if (cmd.notes != null) 'note added',
      if (cmd.balance != null) '₹${cmd.balance!.toStringAsFixed(0)}',
      if (cmd.durationMinutes != null) '${cmd.durationMinutes} min',
      ?reason,
      if (cmd.homeVisit != null) cmd.homeVisit! ? 'home visit' : 'in clinic',
      if (cmd.address != null) 'address set',
      if (cmd.sendWhatsApp != null)
        cmd.sendWhatsApp! ? 'WhatsApp on' : 'no WhatsApp',
      if (cmd.addToQueue != null) cmd.addToQueue! ? 'add to queue' : 'no queue',
      for (final o in others) '+ ${o.fullName}',
    ];
    understood.value = [
      _label(open),
      if (_patient != null) _patient!.fullName,
      ?_newName,
      if (_date != null) DateFormat('EEE d MMM').format(_date!),
      if (_time != null) _fmtTime(_time!),
      ...heard,
    ].join(' · ');
    _updateReady();
  }

  void _confirm() {
    if (VoiceBus.missing.value.isNotEmpty) {
      _onRefused();
      return;
    }
    understood.value = 'Saving…';
    VoiceBus.emit(const VoiceConfirm());
    // Still open a moment later: a field failed the form's own checks.
    _saveCheck?.cancel();
    _saveCheck = Timer(const Duration(milliseconds: 2500), () {
      if (_open != null && understood.value == 'Saving…') {
        understood.value = "Couldn't save yet · check the highlighted field";
      }
    });
  }

  void _onMissing() {
    final missing = VoiceBus.missing.value;
    hint.value = _open == null || missing.isEmpty
        ? null
        : 'Still need: ${missing.join(', ')}';
    _updateReady();
  }

  void _onRefused() {
    final missing = VoiceBus.missing.value;
    if (_open == null || missing.isEmpty) return;
    understood.value = "Can't save yet · say the ${missing.join(', ')}";
  }

  void _updateReady() {
    final complete = VoiceBus.missing.value.isEmpty;
    ready.value = switch (_open) {
      VoiceIntent.addPatient => complete && _newName != null,
      VoiceIntent.addAppointment => complete && _date != null && _time != null,
      VoiceIntent.reschedule => _date != null || _time != null,
      VoiceIntent.editPatient => complete,
      _ => false,
    };
  }

  /// Clears voice state once the form closes, however it closed.
  void _track(Future<bool> closed) {
    final who = _patient?.fullName ?? _newName;
    closed
        .then((saved) {
          if (_switchTo != null) return;
          if (saved && _open == VoiceIntent.addPatient) _focusName = _newName;
          final booked = _patient;
          if (saved && booked != null) {
            if (_open == VoiceIntent.addAppointment) {
              unawaited(_rememberBooking(booked));
            } else if (_open == VoiceIntent.reschedule &&
                _openVisitId != null) {
              _recent = (
                patient: booked,
                visitId: _openVisitId!,
                at: DateTime.now(),
              );
              _lastAction = (
                kind: 'moved',
                who: booked.fullName,
                visitId: _openVisitId,
                patientId: booked.id,
                oldStart: _openVisitStart,
              );
            }
          }
          understood.value = saved ? ['Saved', ?who].join(' · ') : 'Cancelled';
        })
        .whenComplete(() {
          final next = _switchTo;
          if (next != null) {
            _switchTo = null;
            _patient = next;
            if (_open == VoiceIntent.reschedule) {
              unawaited(_openReschedule(next));
            } else {
              _openAppointment(next);
            }
            return;
          }
          _saveCheck?.cancel();
          ready.value = false;
          hint.value = null;
          _open = null;
          _patient = null;
          _notesBefore = '';
          _notesNow = null;
          VoiceBus.last = null;
        });
  }

  DateTime? get _startTime {
    if (_date == null && _time == null) return null;
    final d = _date ?? DateTime.now().add(const Duration(days: 1));
    final t = _time ?? const TimeOfDay(hour: 10, minute: 0);
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  static String _joinNotes(String a, String b) =>
      [a, b].where((s) => s.isNotEmpty).join('. ');

  static String _label(VoiceIntent i) => switch (i) {
    VoiceIntent.openPatient => 'Open patient',
    VoiceIntent.addPatient => 'Add patient',
    VoiceIntent.addAppointment => 'Add appointment',
    VoiceIntent.reschedule => 'Reschedule',
    VoiceIntent.editPatient => 'Edit patient',
    VoiceIntent.cancelAppointment => 'Cancel appointment',
    VoiceIntent.markDone => 'Mark done',
    VoiceIntent.markMissed => 'Mark no-show',
    VoiceIntent.recordPayment => 'Record payment',
    VoiceIntent.addNote => 'Add note',
    _ => '',
  };

  static String _fmtTime(TimeOfDay t) =>
      DateFormat('h:mm a').format(DateTime(2000, 1, 1, t.hour, t.minute));

  static String _title(String w) =>
      w.isEmpty ? w : w[0].toUpperCase() + w.substring(1);

  void dispose() {
    asking.dispose();
    VoiceBus.missing.removeListener(_onMissing);
    VoiceBus.refused.removeListener(_onRefused);
    VoiceBus.openKind.removeListener(_onFormKind);
    _saveCheck?.cancel();
    understood.dispose();
    ready.dispose();
    hint.dispose();
  }
}
