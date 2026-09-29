import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/errors/visit_exceptions.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_builder.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/shell/appt_cap_notice.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/shell/appt_format.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/patient_dialogs.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/features/voice/presentation/voice_dialog_hook.dart';

/// Opens Reschedule for [item]. Returns the new start when the visit was
/// moved, otherwise null.
Future<DateTime?> showRescheduleVisitDialog(
  BuildContext context, {
  required ApptItem item,
  DateTime? initialStart,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (_) => RescheduleVisitDialog(item: item, initialStart: initialStart),
  );
}

/// Date + time, then `VisitRepository.rescheduleVisit`. Overlap warnings
/// ask first; the cap of 4 and same-patient double bookings show inline
/// under the time field.
class RescheduleVisitDialog extends ConsumerStatefulWidget {
  const RescheduleVisitDialog({super.key, required this.item, this.initialStart});

  final ApptItem item;

  /// Prefill (e.g. a suggested slot); defaults to the current start.
  final DateTime? initialStart;

  @override
  ConsumerState<RescheduleVisitDialog> createState() =>
      _RescheduleVisitDialogState();
}

class _RescheduleVisitDialogState extends ConsumerState<RescheduleVisitDialog>
    with VoiceDialogHook<RescheduleVisitDialog> {
  late DateTime _date;
  late TimeOfDay _time;
  bool _saving = false;

  /// Cap of 4 refused this start; shows [ApptCapNotice].
  DateTime? _capAt;
  DateTime? _capNextFree;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = widget.initialStart ?? widget.item.start;
    _date = ApptsBuilder.dateOnly(s);
    _time = TimeOfDay.fromDateTime(s);
  }

  DateTime get _start =>
      DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

  void _clearErrors() {
    _capAt = null;
    _capNextFree = null;
    _error = null;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(_date.year - 1),
      lastDate: DateTime(_date.year + 2, 12, 31),
    );
    if (picked != null && mounted) {
      setState(() {
        _date = ApptsBuilder.dateOnly(picked);
        _clearErrors();
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null && mounted) {
      setState(() {
        _time = picked;
        _clearErrors();
      });
    }
  }

  void _useSlot(DateTime slot) {
    setState(() {
      _date = ApptsBuilder.dateOnly(slot);
      _time = TimeOfDay.fromDateTime(slot);
      _clearErrors();
    });
  }

  @override
  void onVoiceFill(VoiceFill f) {
    if (f.date == null && f.time == null) return;
    setState(() {
      if (f.date != null) _date = ApptsBuilder.dateOnly(f.date!);
      if (f.time != null) _time = f.time!;
      _clearErrors();
    });
  }

  @override
  void onVoiceConfirm() => _save();

  @override
  String get voiceKind => 'reschedule';

  Future<void> _save({bool acknowledgeOverlap = false}) async {
    if (_saving) return;
    final start = _start;
    if (start == widget.item.start) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = true;
      _clearErrors();
    });
    try {
      await ref.read(visitRepositoryProvider).rescheduleVisit(
            widget.item.id,
            newStart: start,
            acknowledgeOverlap: acknowledgeOverlap,
          );
      if (!mounted) return;
      Navigator.of(context).pop(start);
    } on VisitOverlapWarning catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final ok = await _confirmOverlap(e);
      if (ok == true && mounted) await _save(acknowledgeOverlap: true);
    } on VisitOverlapLimitExceededException {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _capAt = start;
        _capNextFree = apptNextFreeSlot(
          ref,
          start: start,
          durationMinutes: widget.item.durationMinutes,
          excludeVisitId: widget.item.id,
        );
      });
    } on SamePatientDoubleBookingException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '${widget.item.firstName} already has a visit at '
            '${ApptFormat.time(e.conflict.scheduledStart)} that overlaps '
            'this time.';
      });
    } on VisitException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = "Couldn't reschedule. Try again.";
      });
    }
  }

  Future<bool?> _confirmOverlap(VisitOverlapWarning e) {
    final n = e.conflicts.length;
    final first = e.conflicts.isEmpty ? null : e.conflicts.first;
    final body = first == null
        ? 'This time overlaps another visit.'
        : n == 1
            ? 'Another visit is booked at ${ApptFormat.time(first.scheduledStart)}.'
            : '$n other visits overlap this time.';
    return showDialog<bool>(
      context: context,
      builder: (ctx) => PatientDialog(
        title: 'Book both at this time?',
        cancelLabel: 'Go back',
        confirmLabel: 'Book both',
        onConfirm: () => Navigator.of(ctx).pop(true),
        body: Text(
          '$body Up to $kMaxOverlappingVisits visits can share a time.',
          style: CruType.text.tabular.tint(ctx.cru.label2),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final item = widget.item;
    return PatientDialog(
      title: 'Reschedule',
      cancelLabel: 'Cancel',
      confirmLabel: _saving ? 'Saving…' : 'Reschedule',
      onConfirm: () => _save(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${item.name} · now ${ApptFormat.range(item.start, item.end)}, '
            '${ApptFormat.dateLine(item.start)}',
            style: CruType.text.tabular.tint(c.label2),
          ),
          const SizedBox(height: CruSpace.s16),
          const _FieldLabel('Date'),
          const SizedBox(height: CruSpace.s6),
          _PickerField(
            icon: CruIcons.calendar,
            value: ApptFormat.dateLine(_date),
            semanticLabel: 'Date, ${ApptFormat.dateLine(_date)}',
            onTap: _pickDate,
          ),
          const SizedBox(height: CruSpace.s14),
          const _FieldLabel('Time'),
          const SizedBox(height: CruSpace.s6),
          _PickerField(
            icon: CruIcons.clock,
            value: ApptFormat.range(
              _start,
              _start.add(Duration(minutes: item.durationMinutes)),
            ),
            semanticLabel: 'Time, ${ApptFormat.time(_start)}',
            onTap: _pickTime,
          ),
          if (_capAt != null) ...[
            const SizedBox(height: CruSpace.s8),
            ApptCapNotice(at: _capAt!, nextFree: _capNextFree, onPick: _useSlot),
          ] else if (_error != null) ...[
            const SizedBox(height: CruSpace.s8),
            ApptInlineError(_error!),
          ],
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: CruType.subhead.w500.tint(context.cru.label2));
}

/// A 44 px inset field that opens a picker (same look as PatientDialog
/// text fields).
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.icon,
    required this.value,
    required this.semanticLabel,
    required this.onTap,
  });

  final CruIconData icon;
  final String value;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruPressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      scaleOnPress: false,
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        height: CruSize.actionButton,
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s14),
        decoration: ShapeDecoration(
          color: hovered ? cruHoverShade(c.inset, c) : c.inset,
          shape: cruShape(CruRadius.control),
        ),
        child: Row(
          children: [
            CruIcon(icon, size: 17, strokeWidth: 2, color: c.label2),
            const SizedBox(width: CruSpace.s10),
            Expanded(
              child: Text(
                value,
                style: CruType.input.tabular.tint(c.label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            CruIcon(CruIcons.chevronDown, size: 16, color: c.label3),
          ],
        ),
      ),
    );
  }
}
