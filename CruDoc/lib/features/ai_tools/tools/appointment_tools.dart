import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/errors/visit_exceptions.dart';
import 'package:doctor_management_app/features/ai_tools/core/ai_tool.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/messaging/data/repo/messaging_repository.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';

const int _maxItems = 15;
const int _dayStartHour = 9;
const int _dayEndHour = 20;
const int _slotStepMinutes = 15;

String _two(int n) => n.toString().padLeft(2, '0');
String _dateStr(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
String _timeStr(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

DateTime? _parseDate(Object? v) {
  if (v is! String) return null;
  final d = DateTime.tryParse(v.trim());
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

({int h, int m})? _parseTime(Object? v) {
  if (v is! String) return null;
  final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(v.trim());
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  if (h > 23 || min > 59) return null;
  return (h: h, m: min);
}

String _humanWhen(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ap = d.hour < 12 ? 'am' : 'pm';
  return '$h12:${_two(d.minute)} $ap on ${d.day} ${months[d.month - 1]}';
}

Future<String?> _patientName(AiToolContext ctx, String patientId) async {
  try {
    final p = await ctx.read(patientRepositoryProvider).getPatient(patientId);
    return p?.fullName.trim();
  } catch (_) {
    return null;
  }
}

Future<Map<String, Object?>> _visitJson(AiToolContext ctx, Visit v) async => {
  'visitId': v.id,
  'patientId': v.patientId,
  'patientName': await _patientName(ctx, v.patientId),
  'date': _dateStr(v.scheduledStart),
  'time': _timeStr(v.scheduledStart),
  'durationMinutes': v.durationMinutes,
  'status': v.status.value,
  'type': v.visitType.value,
  if (v.attendingDoctorUid.isNotEmpty) 'doctorId': v.attendingDoctorUid,
  if (v.treatmentType != null && v.treatmentType!.isNotEmpty)
    'reason': v.treatmentType,
};

Future<List<Map<String, Object?>>> _visitList(
  AiToolContext ctx,
  List<Visit> visits,
) => Future.wait([for (final v in visits.take(_maxItems)) _visitJson(ctx, v)]);

AiToolResult _visitError(Object e) => e is VisitException
    ? AiToolResult.error(e.message)
    : AiToolResult.error('Could not complete that: $e');

String? _s(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

List<AiTool> appointmentTools() => [
  AiTool(
    name: 'list_appointments',
    description:
        'Lists appointments for one date or a date range, optionally by '
        'doctor or status. Use to answer "who is booked today/tomorrow".',
    group: AiToolGroup.appointments,
    risk: AiToolRisk.read,
    permission: ClinicPermission.schedule,
    params: const {
      'date': AiParam.date('A single day', required: false),
      'from': AiParam.date('Range start (inclusive)', required: false),
      'to': AiParam.date('Range end (inclusive)', required: false),
      'doctorId': AiParam.string('Attending doctor id', required: false),
      'status': AiParam.enumOf(
        ['scheduled', 'completed', 'cancelled', 'missed'],
        'Only this status',
        required: false,
      ),
    },
    run: (ctx, args) async {
      final date = _parseDate(args['date']);
      final from = date ?? _parseDate(args['from']);
      final to = date ?? _parseDate(args['to']) ?? from;
      if (from == null) {
        return AiToolResult.error('Give a date, or from and to dates.');
      }
      final end = DateTime(to!.year, to.month, to.day + 1);
      final status = _s(args['status']);
      final doctorId = _s(args['doctorId']);
      final all = await ctx.read(allVisitsProvider.future);
      final hits = all
          .where(
            (v) =>
                !v.isDeleted &&
                !v.scheduledStart.isBefore(from) &&
                v.scheduledStart.isBefore(end) &&
                (status == null || v.status.value == status) &&
                (doctorId == null || v.attendingDoctorUid == doctorId),
          )
          .toList()
        ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
      return AiToolResult.ok({
        'total': hits.length,
        'appointments': await _visitList(ctx, hits),
      });
    },
  ),
  AiTool(
    name: 'get_appointment',
    description: 'Gets one appointment by id. Use after a list or find step.',
    group: AiToolGroup.appointments,
    risk: AiToolRisk.read,
    permission: ClinicPermission.schedule,
    params: const {'visitId': AiParam.string('Appointment id')},
    run: (ctx, args) async {
      final v = await ctx
          .read(visitRepositoryProvider)
          .getVisit(_s(args['visitId']) ?? '');
      if (v == null || v.isDeleted) {
        return AiToolResult.error('No appointment with that id.');
      }
      return AiToolResult.ok({'appointment': await _visitJson(ctx, v)});
    },
  ),
  AiTool(
    name: 'find_free_slots',
    description:
        'Finds open start times on a date for an appointment of a given '
        'length. Use before booking when the user has not named a time.',
    group: AiToolGroup.appointments,
    risk: AiToolRisk.read,
    permission: ClinicPermission.schedule,
    phoneSafe: true,
    params: const {
      'date': AiParam.date('Day to search'),
      'durationMinutes': AiParam.integer(
        'Appointment length in minutes',
        min: kMinVisitDurationMinutes,
        max: kMaxVisitDurationMinutes,
      ),
      'doctorId': AiParam.string('Attending doctor id', required: false),
    },
    run: (ctx, args) async {
      final day = _parseDate(args['date']);
      if (day == null) return AiToolResult.error('Date must be YYYY-MM-DD.');
      final minutes = (args['durationMinutes'] as num?)?.toInt() ?? 30;
      final doctorId = _s(args['doctorId']);
      final all = await ctx.read(allVisitsProvider.future);
      final busy = [
        for (final v in all)
          if (!v.isDeleted &&
              v.status == VisitStatus.scheduled &&
              v.scheduledStart.year == day.year &&
              v.scheduledStart.month == day.month &&
              v.scheduledStart.day == day.day &&
              (doctorId == null || v.attendingDoctorUid == doctorId))
            (v.scheduledStart, v.scheduledEnd),
      ];
      final now = DateTime.now();
      final end = DateTime(day.year, day.month, day.day, _dayEndHour);
      var t = DateTime(day.year, day.month, day.day, _dayStartHour);
      final slots = <String>[];
      while (!t.add(Duration(minutes: minutes)).isAfter(end) &&
          slots.length < _maxItems) {
        final e = t.add(Duration(minutes: minutes));
        final clash = busy.any((b) => t.isBefore(b.$2) && e.isAfter(b.$1));
        if (!clash && t.isAfter(now)) slots.add(_timeStr(t));
        t = t.add(const Duration(minutes: _slotStepMinutes));
      }
      return AiToolResult.ok({
        'date': _dateStr(day),
        'durationMinutes': minutes,
        'freeStartTimes': slots,
        'note': 'Searched $_dayStartHour:00 to $_dayEndHour:00.',
      });
    },
  ),
  AiTool(
    name: 'list_patient_appointments',
    description:
        "Lists one patient's appointments, newest first. Use to find the "
        'appointment to reschedule or cancel.',
    group: AiToolGroup.appointments,
    risk: AiToolRisk.read,
    permission: ClinicPermission.schedule,
    phoneSafe: true,
    params: const {
      'patientId': AiParam.string('Patient id'),
      'upcomingOnly': AiParam.boolean(
        'Only future scheduled ones',
        required: false,
      ),
    },
    run: (ctx, args) async {
      final id = _s(args['patientId']) ?? '';
      final upcoming = args['upcomingOnly'] == true;
      final all = await ctx.read(visitsForPatientProvider(id).future);
      final now = DateTime.now();
      final hits = all
          .where(
            (v) =>
                !v.isDeleted &&
                (!upcoming ||
                    (v.status == VisitStatus.scheduled &&
                        v.scheduledEnd.isAfter(now))),
          )
          .toList()
        ..sort(
          (a, b) => upcoming
              ? a.scheduledStart.compareTo(b.scheduledStart)
              : b.scheduledStart.compareTo(a.scheduledStart),
        );
      return AiToolResult.ok({
        'total': hits.length,
        'appointments': await _visitList(ctx, hits),
      });
    },
  ),
  AiTool(
    name: 'book_appointment',
    description:
        'Books an appointment for an existing patient at a date and time. '
        'Find the patient id first; check free slots if unsure. A clash with '
        'another booking returns an error to relay to the user.',
    group: AiToolGroup.appointments,
    risk: AiToolRisk.write,
    permission: ClinicPermission.schedule,
    phoneSafe: true,
    params: const {
      'patientId': AiParam.string('Patient id'),
      'date': AiParam.date('Day of the appointment'),
      'time': AiParam.time('Start time'),
      'durationMinutes': AiParam.integer(
        'Length in minutes (default 30)',
        required: false,
        min: kMinVisitDurationMinutes,
        max: kMaxVisitDurationMinutes,
      ),
      'doctorId': AiParam.string('Attending doctor id', required: false),
      'reason': AiParam.string('Reason for visit', required: false),
      'homeVisit': AiParam.boolean(
        'True if at the patient home',
        required: false,
      ),
      'address': AiParam.string('Home visit address', required: false),
    },
    run: (ctx, args) async {
      final patientId = _s(args['patientId']);
      final day = _parseDate(args['date']);
      final t = _parseTime(args['time']);
      if (patientId == null) return AiToolResult.error('patientId is required.');
      if (day == null || t == null) {
        return AiToolResult.error('Need date YYYY-MM-DD and time HH:MM.');
      }
      final start = DateTime(day.year, day.month, day.day, t.h, t.m);
      final home = args['homeVisit'] == true;
      final address = _s(args['address']) ?? '';
      if (home && address.isEmpty) {
        return AiToolResult.error('A home visit needs an address.');
      }
      final name = await _patientName(ctx, patientId);
      if (name == null) return AiToolResult.error('No patient with that id.');
      final now = DateTime.now();
      final repo = ctx.read(visitRepositoryProvider);
      try {
        final id = await repo.createVisit(
          Visit(
            id: '',
            patientId: patientId,
            scheduledStart: start,
            durationMinutes: (args['durationMinutes'] as num?)?.toInt() ?? 30,
            address: home ? address : '',
            visitType: home ? VisitType.home : VisitType.clinic,
            status: VisitStatus.scheduled,
            treatmentType: _s(args['reason']),
            attendingDoctorUid: _s(args['doctorId']) ?? '',
            createdAt: now,
            updatedAt: now,
          ),
        );
        return AiToolResult.ok(
          {
            'visitId': id,
            'patientName': name,
            'date': _dateStr(start),
            'time': _timeStr(start),
          },
          summary: 'Booked $name for ${_humanWhen(start)}',
          undo: () => repo.cancelVisit(id),
        );
      } catch (e) {
        return _visitError(e);
      }
    },
  ),
  AiTool(
    name: 'reschedule_appointment',
    description:
        'Moves an appointment to a new date and/or time, or shifts it by a '
        'number of minutes (negative = earlier). Give date/time or '
        'shiftMinutes.',
    group: AiToolGroup.appointments,
    risk: AiToolRisk.write,
    permission: ClinicPermission.schedule,
    phoneSafe: true,
    params: const {
      'visitId': AiParam.string('Appointment id'),
      'date': AiParam.date('New day', required: false),
      'time': AiParam.time('New start time', required: false),
      'shiftMinutes': AiParam.integer(
        'Minutes to move by, negative for earlier',
        required: false,
      ),
    },
    run: (ctx, args) async {
      final repo = ctx.read(visitRepositoryProvider);
      final v = await repo.getVisit(_s(args['visitId']) ?? '');
      if (v == null || v.isDeleted) {
        return AiToolResult.error('No appointment with that id.');
      }
      final day = _parseDate(args['date']);
      final t = _parseTime(args['time']);
      final shift = (args['shiftMinutes'] as num?)?.toInt();
      if (day == null && t == null && shift == null) {
        return AiToolResult.error('Give a date, a time, or shiftMinutes.');
      }
      var start = v.scheduledStart;
      if (day != null || t != null) {
        final d = day ?? start;
        start = DateTime(
          d.year,
          d.month,
          d.day,
          t?.h ?? start.hour,
          t?.m ?? start.minute,
        );
      }
      if (shift != null) start = start.add(Duration(minutes: shift));
      final old = v.scheduledStart;
      try {
        await repo.rescheduleVisit(v.id, newStart: start);
        final name = await _patientName(ctx, v.patientId) ?? 'The patient';
        return AiToolResult.ok(
          {
            'visitId': v.id,
            'patientName': name,
            'date': _dateStr(start),
            'time': _timeStr(start),
            'previousDate': _dateStr(old),
            'previousTime': _timeStr(old),
          },
          summary: 'Moved $name to ${_humanWhen(start)}',
          undo: () =>
              repo.rescheduleVisit(v.id, newStart: old, acknowledgeOverlap: true),
        );
      } catch (e) {
        return _visitError(e);
      }
    },
  ),
  AiTool(
    name: 'set_appointment_status',
    description:
        'Marks an appointment done, missed, or back to scheduled (reopen). '
        'Marking a clinic appointment done also records the standard fee as '
        'paid, as the app does.',
    group: AiToolGroup.appointments,
    risk: AiToolRisk.write,
    permission: ClinicPermission.schedule,
    params: const {
      'visitId': AiParam.string('Appointment id'),
      'status': AiParam.enumOf(['done', 'missed', 'scheduled'], 'New status'),
    },
    run: (ctx, args) async {
      final repo = ctx.read(visitRepositoryProvider);
      final v = await repo.getVisit(_s(args['visitId']) ?? '');
      if (v == null || v.isDeleted) {
        return AiToolResult.error('No appointment with that id.');
      }
      final next = switch (_s(args['status'])) {
        'done' => VisitStatus.completed,
        'missed' => VisitStatus.missed,
        'scheduled' => VisitStatus.scheduled,
        _ => null,
      };
      if (next == null) {
        return AiToolResult.error('Status must be done, missed or scheduled.');
      }
      final before = v.status;
      try {
        await repo.updateStatus(v.id, next);
        final name = await _patientName(ctx, v.patientId) ?? 'The patient';
        return AiToolResult.ok(
          {
            'visitId': v.id,
            'patientName': name,
            'status': next.value,
            'previousStatus': before.value,
          },
          summary: '$name\'s appointment marked ${next.value}',
          undo: () => repo.updateStatus(v.id, before),
        );
      } catch (e) {
        return _visitError(e);
      }
    },
  ),
  AiTool(
    name: 'cancel_appointment',
    description:
        'Cancels an appointment (kept in history as cancelled). Pass '
        'patientName and when only to word the confirm card.',
    group: AiToolGroup.appointments,
    risk: AiToolRisk.confirm,
    permission: ClinicPermission.schedule,
    phoneSafe: true,
    params: const {
      'visitId': AiParam.string('Appointment id'),
      'reason': AiParam.string('Why it is cancelled', required: false),
      'patientName': AiParam.string(
        'Patient name, for the confirm card',
        required: false,
      ),
      'when': AiParam.string(
        'Appointment time in words, for the confirm card',
        required: false,
      ),
    },
    confirmText: (args) {
      final n = _s(args['patientName']);
      final w = _s(args['when']);
      return 'Cancel ${n == null ? 'this' : '$n\'s'} appointment'
          '${w == null ? '' : ' ($w)'}?';
    },
    run: (ctx, args) async {
      final repo = ctx.read(visitRepositoryProvider);
      final v = await repo.getVisit(_s(args['visitId']) ?? '');
      if (v == null || v.isDeleted) {
        return AiToolResult.error('No appointment with that id.');
      }
      if (v.status == VisitStatus.cancelled) {
        return AiToolResult.error('That appointment is already cancelled.');
      }
      final before = v.status;
      final reason = _s(args['reason']);
      final oldNotes = v.therapistNotes;
      try {
        await repo.cancelVisit(v.id);
        if (reason != null) {
          final note = 'Cancelled: $reason';
          await repo.updateVisit(v.id, {
            'therapistNotes': (oldNotes == null || oldNotes.isEmpty)
                ? note
                : '$oldNotes\n$note',
          });
        }
        final name = await _patientName(ctx, v.patientId) ?? 'The patient';
        return AiToolResult.ok(
          {
            'visitId': v.id,
            'patientName': name,
            'date': _dateStr(v.scheduledStart),
            'time': _timeStr(v.scheduledStart),
            'status': 'cancelled',
          },
          summary: 'Cancelled $name\'s appointment on ${_humanWhen(v.scheduledStart)}',
          undo: () async {
            await repo.updateStatus(v.id, before);
            if (reason != null) {
              await repo.updateVisit(v.id, {'therapistNotes': oldNotes ?? ''});
            }
          },
        );
      } catch (e) {
        return _visitError(e);
      }
    },
  ),
  AiTool(
    name: 'add_to_group',
    description:
        "Adds another patient to an existing appointment (seen together, "
        'e.g. a couple or parent and child): same slot and token.',
    group: AiToolGroup.appointments,
    risk: AiToolRisk.write,
    permission: ClinicPermission.schedule,
    params: const {
      'visitId': AiParam.string('Lead appointment id'),
      'patientId': AiParam.string('Patient to add'),
    },
    run: (ctx, args) async {
      final repo = ctx.read(visitRepositoryProvider);
      final lead = await repo.getVisit(_s(args['visitId']) ?? '');
      final patientId = _s(args['patientId']);
      if (lead == null || lead.isDeleted) {
        return AiToolResult.error('No appointment with that id.');
      }
      if (patientId == null) return AiToolResult.error('patientId is required.');
      final name = await _patientName(ctx, patientId);
      if (name == null) return AiToolResult.error('No patient with that id.');
      if (lead.patientId == patientId) {
        return AiToolResult.error('That patient is already on it.');
      }
      final now = DateTime.now();
      try {
        final added = await repo.addToGroup(
          lead,
          Visit(
            id: '',
            patientId: patientId,
            scheduledStart: lead.scheduledStart,
            durationMinutes: lead.durationMinutes,
            address: lead.address,
            visitType: lead.visitType,
            status: VisitStatus.scheduled,
            attendingDoctorUid: lead.attendingDoctorUid,
            createdAt: now,
            updatedAt: now,
          ),
        );
        return AiToolResult.ok(
          {
            'visitId': added.visitId,
            'groupId': added.groupId,
            'patientName': name,
            'date': _dateStr(lead.scheduledStart),
            'time': _timeStr(lead.scheduledStart),
          },
          summary: 'Added $name to the ${_humanWhen(lead.scheduledStart)} appointment',
          undo: () => repo.cancelVisit(added.visitId),
        );
      } catch (e) {
        return _visitError(e);
      }
    },
  ),
  AiTool(
    name: 'send_appointment_confirmation',
    description:
        'Sends the patient an appointment confirmation message again. Use '
        'only when the user asks to send or resend one.',
    group: AiToolGroup.appointments,
    risk: AiToolRisk.confirm,
    permission: ClinicPermission.messaging,
    params: const {
      'visitId': AiParam.string('Appointment id'),
      'patientName': AiParam.string(
        'Patient name, for the confirm card',
        required: false,
      ),
    },
    confirmText: (args) {
      final n = _s(args['patientName']);
      return 'Send ${n ?? 'the patient'} an appointment '
          'confirmation?';
    },
    run: (ctx, args) async {
      final v = await ctx
          .read(visitRepositoryProvider)
          .getVisit(_s(args['visitId']) ?? '');
      if (v == null || v.isDeleted) {
        return AiToolResult.error('No appointment with that id.');
      }
      try {
        final sent = await MessagingRepository().sendAppointmentConfirmation(
          visit: v,
        );
        if (!sent) {
          return AiToolResult.error(
            'The message was not sent. Check the clinic email connection and '
            "the patient's contact details.",
          );
        }
        final name = await _patientName(ctx, v.patientId) ?? 'the patient';
        return AiToolResult.ok(
          {'visitId': v.id, 'sent': true},
          summary: 'Confirmation sent to $name',
        );
      } catch (e) {
        return AiToolResult.error('Could not send: $e');
      }
    },
  ),
];
