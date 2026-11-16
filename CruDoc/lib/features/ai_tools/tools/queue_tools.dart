import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/errors/queue_exceptions.dart';
import 'package:doctor_management_app/core/errors/visit_exceptions.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/features/ai_tools/core/ai_tool.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/queue/data/model/queue_entry_model.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';
import 'package:doctor_management_app/features/queue/data/repo/queue_repository.dart';

const int _maxItems = 15;

String _two(int n) => n.toString().padLeft(2, '0');
String _timeStr(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

String? _s(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

Future<String> _nameOf(AiToolContext ctx, QueueEntry e) async {
  final id = e.patientId;
  if (id != null && id.isNotEmpty) {
    try {
      final p = await ctx.read(patientRepositoryProvider).getPatient(id);
      if (p != null) return p.fullName.trim();
    } catch (_) {}
  }
  return e.walkInName ?? 'the patient';
}

Future<Map<String, Object?>> _entryJson(AiToolContext ctx, QueueEntry e) async =>
    {
      'entryId': e.id,
      'token': e.tokenNumber,
      if (e.patientId != null) 'patientId': e.patientId,
      'patientName': await _nameOf(ctx, e),
      'status': e.status.value,
      'priority': e.priority.value,
      'time': _timeStr(e.checkedInAt),
      if (e.isPrebooked) 'visitId': e.linkedVisitId,
      if (e.reason != null && e.reason!.isNotEmpty) 'reason': e.reason,
    };

AiToolResult _err(Object e) {
  if (e is QueueAlreadyServingException) {
    return AiToolResult.error(
      'Another patient is already being served. Finish or cancel that '
      'consultation first.',
    );
  }
  if (e is QueueException) return AiToolResult.error(e.message);
  if (e is VisitException) return AiToolResult.error(e.message);
  return AiToolResult.error('Could not complete that: $e');
}

AiToolResult? _queueOff(AiToolContext ctx) =>
    ctx.read(isQueueFeatureEnabledProvider)
    ? null
    : AiToolResult.error('The queue feature is turned off for this clinic.');

Future<List<QueueEntry>> _today(AiToolContext ctx) async =>
    (await ctx.read(queueRepositoryProvider).getTodaysQueue())
        .where((e) => !e.isDeleted)
        .toList();

/// Same sequence as the voice command: reuse the patient's open token, else
/// their booked visit's token, else a fresh check-in.
Future<({QueueEntry entry, bool created})> _tokenFor(
  AiToolContext ctx,
  String patientId,
) async {
  final repo = ctx.read(queueRepositoryProvider);
  final today = await _today(ctx);
  final open = today
      .where(
        (e) =>
            e.patientId == patientId &&
            (e.status == QueueStatus.waiting || e.isActiveServing),
      )
      .firstOrNull;
  if (open != null) return (entry: open, created: false);
  final visits = await ctx.read(todaysVisitsProvider.future);
  final booked = visits
      .where(
        (v) =>
            v.patientId == patientId &&
            v.visitType == VisitType.clinic &&
            v.status == VisitStatus.scheduled,
      )
      .firstOrNull;
  final entry = booked != null
      ? await repo.checkInVisit(booked)
      : await repo.checkIn(patientId: patientId);
  return (entry: entry, created: true);
}

List<AiTool> queueTools() => [
  AiTool(
    name: 'list_queue',
    description:
        "Lists today's queue tokens in call order. Use to see who is "
        'waiting or being seen.',
    group: AiToolGroup.queue,
    risk: AiToolRisk.read,
    permission: ClinicPermission.schedule,
    params: const {
      'waitingOnly': AiParam.boolean('Only waiting tokens', required: false),
    },
    run: (ctx, args) async {
      final off = _queueOff(ctx);
      if (off != null) return off;
      final waitingOnly = args['waitingOnly'] == true;
      final all = await ctx.read(todaysQueueProvider.future);
      final hits =
          all
              .where(
                (e) =>
                    !e.isDeleted &&
                    (!waitingOnly || e.status == QueueStatus.waiting),
              )
              .toList()
            ..sort((a, b) {
              final ra = a.priority == QueuePriority.urgent ? 0 : 1;
              final rb = b.priority == QueuePriority.urgent ? 0 : 1;
              if (ra != rb) return ra.compareTo(rb);
              return a.tokenNumber.compareTo(b.tokenNumber);
            });
      return AiToolResult.ok({
        'total': hits.length,
        'entries': await Future.wait([
          for (final e in hits.take(_maxItems)) _entryJson(ctx, e),
        ]),
      });
    },
  ),
  AiTool(
    name: 'check_in_patient',
    description:
        'Checks a patient into today\'s queue as arrived. Give the '
        'appointment id for a booked patient, or the patient id for a '
        'walk-in.',
    group: AiToolGroup.queue,
    risk: AiToolRisk.write,
    permission: ClinicPermission.schedule,
    params: const {
      'visitId': AiParam.string('Booked appointment id', required: false),
      'patientId': AiParam.string('Patient id', required: false),
    },
    run: (ctx, args) async {
      final off = _queueOff(ctx);
      if (off != null) return off;
      final visitId = _s(args['visitId']);
      final patientId = _s(args['patientId']);
      if (visitId == null && patientId == null) {
        return AiToolResult.error('Give visitId or patientId.');
      }
      final repo = ctx.read(queueRepositoryProvider);
      try {
        QueueEntry entry;
        var created = false;
        if (visitId != null) {
          final visit = await ctx.read(visitRepositoryProvider).getVisit(visitId);
          if (visit == null || visit.isDeleted) {
            return AiToolResult.error('No appointment with that id.');
          }
          if (visit.visitType != VisitType.clinic) {
            return AiToolResult.error('Home visits do not use the queue.');
          }
          final existing = (await _today(ctx))
              .where((e) => e.linkedVisitId == visit.id)
              .firstOrNull;
          entry = existing ?? await repo.checkInVisit(visit);
          created = existing == null;
          if (entry.status == QueueStatus.waiting) {
            await repo.markArrived(entry.id);
          }
        } else {
          final r = await _tokenFor(ctx, patientId!);
          entry = r.entry;
          created = r.created;
        }
        final name = await _nameOf(ctx, entry);
        return AiToolResult.ok(
          {
            'entryId': entry.id,
            'token': entry.tokenNumber,
            'patientName': name,
            'status': entry.status.value,
            'alreadyInQueue': !created,
          },
          summary: created
              ? 'Checked in $name · token ${entry.tokenNumber}'
              : '$name is already in the queue · token ${entry.tokenNumber}',
          // Only a token created by this call can be undone.
          undo: created ? () => repo.softDeleteEntry(entry.id) : null,
        );
      } catch (e) {
        return _err(e);
      }
    },
  ),
  AiTool(
    name: 'call_next',
    description:
        'Calls the next waiting patient (urgent first, then token order) and '
        'starts their consultation. Fails if someone is already being seen.',
    group: AiToolGroup.queue,
    risk: AiToolRisk.write,
    permission: ClinicPermission.schedule,
    run: (ctx, args) async {
      final off = _queueOff(ctx);
      if (off != null) return off;
      final repo = ctx.read(queueRepositoryProvider);
      final concurrent = ctx.read(isPhysiotherapyProvider);
      try {
        final today = await _today(ctx);
        var entry = today
            .where((e) => e.status == QueueStatus.called)
            .firstOrNull;
        entry ??= await repo.callNext(allowConcurrent: concurrent);
        final started = await repo.startConsultation(entry.id);
        final name = await _nameOf(ctx, started);
        return AiToolResult.ok(
          {
            'entryId': started.id,
            'token': started.tokenNumber,
            'patientName': name,
            'status': started.status.value,
          },
          summary: 'Started consultation · $name',
        );
      } on QueueEmptyException {
        return AiToolResult.error('Nobody is waiting in the queue.');
      } catch (e) {
        return _err(e);
      }
    },
  ),
  AiTool(
    name: 'start_consultation',
    description:
        'Starts the consultation for a patient: calls their token in '
        '(checking them in first if they have none today). Give entryId or '
        'patientId.',
    group: AiToolGroup.queue,
    risk: AiToolRisk.write,
    permission: ClinicPermission.schedule,
    params: const {
      'entryId': AiParam.string('Queue entry id', required: false),
      'patientId': AiParam.string('Patient id', required: false),
    },
    run: (ctx, args) async {
      final off = _queueOff(ctx);
      if (off != null) return off;
      final entryId = _s(args['entryId']);
      final patientId = _s(args['patientId']);
      if (entryId == null && patientId == null) {
        return AiToolResult.error('Give entryId or patientId.');
      }
      final repo = ctx.read(queueRepositoryProvider);
      final concurrent = ctx.read(isPhysiotherapyProvider);
      try {
        QueueEntry? entry;
        var created = false;
        if (entryId != null) {
          entry = await repo.getEntry(entryId);
          if (entry == null || entry.isDeleted) {
            return AiToolResult.error('No queue entry with that id.');
          }
        } else {
          final r = await _tokenFor(ctx, patientId!);
          entry = r.entry;
          created = r.created;
        }
        if (entry.status == QueueStatus.inConsultation) {
          QueueRepository.reannounceConsultation(entry);
        } else {
          if (entry.status != QueueStatus.called) {
            entry = await repo.callEntry(entry.id, allowConcurrent: concurrent);
          }
          entry = await repo.startConsultation(entry.id);
        }
        final name = await _nameOf(ctx, entry);
        return AiToolResult.ok(
          {
            'entryId': entry.id,
            'token': entry.tokenNumber,
            'patientName': name,
            'status': entry.status.value,
            'checkedInNow': created,
          },
          summary: 'Started consultation · $name',
        );
      } catch (e) {
        return _err(e);
      }
    },
  ),
  AiTool(
    name: 'complete_queue_entry',
    description:
        'Marks a queue token completed, i.e. the patient has been seen.',
    group: AiToolGroup.queue,
    risk: AiToolRisk.write,
    permission: ClinicPermission.schedule,
    params: const {'entryId': AiParam.string('Queue entry id')},
    run: (ctx, args) async {
      final off = _queueOff(ctx);
      if (off != null) return off;
      try {
        final done = await ctx
            .read(queueRepositoryProvider)
            .complete(_s(args['entryId']) ?? '');
        final name = await _nameOf(ctx, done);
        return AiToolResult.ok(
          {
            'entryId': done.id,
            'token': done.tokenNumber,
            'patientName': name,
            'status': done.status.value,
          },
          summary: 'Completed $name · token ${done.tokenNumber}',
        );
      } catch (e) {
        return _err(e);
      }
    },
  ),
  AiTool(
    name: 'cancel_queue_entry',
    description:
        'Cancels a queue token for the day (patient left, or checked in by '
        'mistake). A booked appointment linked to it is cancelled too. Pass '
        'patientName only to word the confirm card.',
    group: AiToolGroup.queue,
    risk: AiToolRisk.confirm,
    permission: ClinicPermission.schedule,
    params: const {
      'entryId': AiParam.string('Queue entry id'),
      'patientName': AiParam.string(
        'Patient name, for the confirm card',
        required: false,
      ),
    },
    confirmText: (args) {
      final n = _s(args['patientName']);
      return "Cancel ${n == null ? 'this' : '$n\'s'} queue token? Any linked "
          'appointment is cancelled too.';
    },
    run: (ctx, args) async {
      final off = _queueOff(ctx);
      if (off != null) return off;
      final repo = ctx.read(queueRepositoryProvider);
      try {
        final entry = await repo.getEntry(_s(args['entryId']) ?? '');
        if (entry == null || entry.isDeleted) {
          return AiToolResult.error('No queue entry with that id.');
        }
        final name = await _nameOf(ctx, entry);
        await repo.cancel(entry.id);
        return AiToolResult.ok(
          {
            'entryId': entry.id,
            'token': entry.tokenNumber,
            'patientName': name,
            'status': 'cancelled',
          },
          summary: 'Cancelled $name · token ${entry.tokenNumber}',
        );
      } catch (e) {
        return _err(e);
      }
    },
  ),
];
