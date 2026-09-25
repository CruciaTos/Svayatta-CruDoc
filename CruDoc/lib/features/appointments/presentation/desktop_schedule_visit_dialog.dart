import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/core/errors/visit_exceptions.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/core/services/google_places_service.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/repo/visits_repo.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/shell/appt_cap_notice.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/shell/appt_format.dart';
import 'package:doctor_management_app/features/messaging/data/services/whatsapp_template_service.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/patient_dialogs.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/features/appointments/presentation/patient_picker_dialog.dart';
import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/core/services/maps_key.dart';

/// Opens the desktop Schedule visit form.
///
/// Returns `true` if a visit was successfully scheduled.
Future<bool> showDesktopScheduleVisitDialog(
  BuildContext context, {
  required Patient patient,
  required VisitRepository visitRepository,
  DateTime? initialDate,
  DateTime? initialStart,
  VisitType initialType = VisitType.clinic,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => DesktopScheduleVisitDialog(
      patient: patient,
      visitRepository: visitRepository,
      initialDate: initialDate,
      initialStart: initialStart,
      initialType: initialType,
    ),
  );
  return result ?? false;
}

class DesktopScheduleVisitDialog extends ConsumerStatefulWidget {
  const DesktopScheduleVisitDialog({
    super.key,
    required this.patient,
    required this.visitRepository,
    this.initialDate,
    this.initialStart,
    this.initialType = VisitType.clinic,
  });

  final Patient patient;
  final VisitRepository visitRepository;
  final DateTime? initialDate;

  /// Prefills date and time (a click on empty calendar time or an open
  /// slot). Takes precedence over [initialDate].
  final DateTime? initialStart;

  /// Home visits are offered to physiotherapists only.
  final VisitType initialType;

  @override
  ConsumerState<DesktopScheduleVisitDialog> createState() =>
      _DesktopScheduleVisitDialogState();
}

class _DesktopScheduleVisitDialogState
    extends ConsumerState<DesktopScheduleVisitDialog> {
  static const _durations = [15, 30, 45, 60, 90];

  static const _quickReasons = [
    'General consultation',
    'Follow-up visit',
    'Dental scaling & polishing',
  ];

  final _reason = TextEditingController();

  /// Others seen in the same slot (a couple, a family), each with their
  /// own reason.
  final List<(Patient, TextEditingController)> _others = [];
  final _address = TextEditingController();
  final _mapsLink = TextEditingController();
  final _notes = TextEditingController();

  late DateTime _date;
  TimeOfDay _time = const TimeOfDay(hour: 10, minute: 0);
  int _duration = 30;
  VisitType _type = VisitType.clinic;
  bool _sendWhatsApp = true;
  bool _addToQueue = true;

  double? _lat;
  double? _lng;

  bool _dirty = false;
  bool _saving = false;
  String? _notice;

  /// Refused at this start by the cap of 4; shown under the time field
  /// with the next free slot.
  DateTime? _capAt;
  DateTime? _capNextFree;

  /// The same patient is already booked at an overlapping time.
  String? _timeError;

  @override
  void initState() {
    super.initState();
    if (ref.read(isPhysiotherapyProvider)) _type = widget.initialType;
    _date = widget.initialDate ?? DateTime.now().add(const Duration(days: 1));
    final start = widget.initialStart;
    if (start != null) {
      _date = DateTime(start.year, start.month, start.day);
      _time = TimeOfDay.fromDateTime(start);
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    for (final (_, c) in _others) {
      c.dispose();
    }
    _address.dispose();
    _mapsLink.dispose();
    _notes.dispose();
    super.dispose();
  }

  DateTime get _start =>
      DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

  bool get _canWhatsApp =>
      WhatsAppTemplateService.isValidWhatsAppPhone(widget.patient.phone);

  String? _trimmedOrNull(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  void _edited([Object? _]) {
    setState(() {
      _dirty = true;
      _notice = null;
    });
  }

  void _timeEdited() {
    _dirty = true;
    _notice = null;
    _capAt = null;
    _capNextFree = null;
    _timeError = null;
  }

  static String _dateLabel(DateTime d) {
    final line = ApptFormat.dateLine(d);
    return d.year == DateTime.now().year ? line : '$line ${d.year}';
  }

  Future<void> _pickDate() async {
    final firstDate = DateTime.now().subtract(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      // A past day can be prefilled from the calendar; keep the picker valid.
      initialDate: _date.isBefore(firstDate) ? firstDate : _date,
      firstDate: firstDate,
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      helpText: 'Visit date',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date = picked;
      _timeEdited();
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      helpText: 'Start time',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _time = picked;
      _timeEdited();
    });
  }

  void _useSlot(DateTime slot) {
    setState(() {
      _date = DateTime(slot.year, slot.month, slot.day);
      _time = TimeOfDay.fromDateTime(slot);
      _timeEdited();
    });
  }

  Future<void> _addOther() async {
    final picked = await showPatientPickerDialog(
      context,
      title: 'Who else is coming?',
    );
    if (picked == null || !mounted) return;
    final taken = picked.id == widget.patient.id ||
        _others.any((o) => o.$1.id == picked.id);
    if (taken) return;
    setState(() => _others.add((picked, TextEditingController())));
    _edited();
  }

  void _removeOther(int i) {
    setState(() => _others.removeAt(i).$2.dispose());
    _edited();
  }

  Future<void> _submit({bool acknowledgeOverlap = false}) async {
    if (_saving) return;

    setState(() {
      _saving = true;
      _notice = null;
      _capAt = null;
      _capNextFree = null;
      _timeError = null;
    });

    final scheduledStart = _start;
    final now = DateTime.now();

    Visit visitFor(String patientId, String? reason, {String? notes}) => Visit(
      id: '',
      patientId: patientId,
      scheduledStart: scheduledStart,
      durationMinutes: _duration,
      address: _type == VisitType.home ? _address.text.trim() : 'Clinic',
      latitude: _lat,
      longitude: _lng,
      mapsLink: _trimmedOrNull(_mapsLink),
      visitType: _type,
      status: VisitStatus.scheduled,
      treatmentType: reason,
      therapistNotes: notes,
      createdAt: now,
      updatedAt: now,
    );

    final visit = Visit(
      id: '',
      patientId: widget.patient.id,
      scheduledStart: scheduledStart,
      durationMinutes: _duration,
      address: _type == VisitType.home ? _address.text.trim() : 'Clinic',
      latitude: _lat,
      longitude: _lng,
      mapsLink: _trimmedOrNull(_mapsLink),
      visitType: _type,
      status: VisitStatus.scheduled,
      treatmentType: _trimmedOrNull(_reason),
      therapistNotes: _trimmedOrNull(_notes),
      createdAt: now,
      updatedAt: now,
    );

    try {
      // Seen together: one visit per patient, sharing a group (and, in
      // the queue, one token).
      final saved = _others.isEmpty
          ? [
              visit.copyWith(
                id: await widget.visitRepository.createVisit(
                  visit,
                  acknowledgeOverlap: acknowledgeOverlap,
                ),
              ),
            ]
          : await widget.visitRepository.createVisitGroup(
              [
                visit,
                for (final (p, reason) in _others)
                  visitFor(p.id, _trimmedOrNull(reason)),
              ],
              acknowledgeOverlap: acknowledgeOverlap,
            );

      final isQueueEnabled = ref.read(isQueueFeatureEnabledProvider);
      if (isQueueEnabled && _addToQueue && _type == VisitType.clinic) {
        try {
          final queueRepo = ref.read(queueRepositoryProvider);
          for (final v in saved) {
            await queueRepo.checkInVisit(v);
          }
        } catch (e) {
          debugPrint('Could not auto-add appointment to queue: $e');
        }
      }

      if (!mounted) return;

      if (_sendWhatsApp && _canWhatsApp) {
        final message = WhatsAppTemplateService.buildConfirmationMessage(
          visit: visit,
          patient: widget.patient,
          doctorName: 'Doctor',
        );
        final uri = WhatsAppTemplateService.buildDirectWhatsAppUrl(
          rawPhone: widget.patient.phone,
          message: message,
        );
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on VisitOverlapWarning catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final proceed = await _confirmOverlap(e);
      if (proceed == true && mounted) {
        await _submit(acknowledgeOverlap: true);
      }
    } on VisitOverlapLimitExceededException {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _capAt = scheduledStart;
        _capNextFree = apptNextFreeSlot(
          ref,
          start: scheduledStart,
          durationMinutes: _duration,
        );
      });
    } on SamePatientDoubleBookingException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _timeError =
            '${widget.patient.firstName} already has a visit at '
            '${ApptFormat.time(e.conflict.scheduledStart)} that overlaps '
            'this time.';
      });
    } on VisitException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _notice = switch (e) {
          InactivePatientException() =>
            '${widget.patient.firstName} is archived. Restore them before '
                'booking a visit.',
          PatientNotFoundException() =>
            "This patient's record couldn't be found. Close and choose "
                'them again.',
          GeocodingException() =>
            "Couldn't find that address on the map. Check it or pick a "
                'suggestion.',
          _ => e.message,
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _notice =
            "Couldn't book this visit. Check your connection and try "
            'again.';
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
    final patient = widget.patient;
    final phone = patient.phone.trim();
    final queueOn =
        ref.watch(isQueueFeatureEnabledProvider) && _type == VisitType.clinic;
    final showAfter = _canWhatsApp || queueOn;
    final start = _start;

    return CruFormDialog(
      title: 'Schedule a visit',
      subtitle: phone.isEmpty
          ? patient.fullName
          : '${patient.fullName} · $phone',
      leading: CruMonogram(name: patient.fullName, size: CruSize.iconTile),
      submitLabel: 'Book visit',
      onSubmit: _submit,
      busy: _saving,
      dirty: _dirty,
      notice: _notice,
      footerHint: 'Ctrl + Enter to book',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CruFormSection(
            first: true,
            title: 'When',
            description: 'Day, start time and how long to keep free.',
            children: [
              CruFieldRow(
                flex: const [1, 1],
                children: [
                  CruPickerField(
                    label: 'Date',
                    icon: CruIcons.calendar,
                    value: _dateLabel(_date),
                    placeholder: 'Pick a date',
                    onTap: _pickDate,
                  ),
                  CruPickerField(
                    label: 'Time',
                    icon: CruIcons.clock,
                    value: ApptFormat.range(
                      start,
                      start.add(Duration(minutes: _duration)),
                    ),
                    placeholder: 'Pick a time',
                    onTap: _pickTime,
                    error: _timeError,
                  ),
                ],
              ),
              if (_capAt != null)
                ApptCapNotice(
                  at: _capAt!,
                  nextFree: _capNextFree,
                  onPick: _useSlot,
                ),
              CruFieldFrame(
                label: 'Length',
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: CruSegmentedControl<int>(
                    semanticLabel: 'Visit length',
                    segments: [
                      for (final d in _durations) CruSegment(d, '$d min'),
                    ],
                    selected: _duration,
                    onChanged: (v) => setState(() {
                      _duration = v;
                      _timeEdited();
                    }),
                  ),
                ),
              ),
            ],
          ),
          // Home visits are a physiotherapy workflow; everyone else books
          // at the clinic.
          if (ref.watch(isPhysiotherapyProvider))
            CruFormSection(
              title: 'Where',
              description: 'At the clinic or at the patient’s home.',
              children: [
                CruFieldFrame(
                  label: 'Place',
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: CruSegmentedControl<VisitType>(
                      semanticLabel: 'Visit place',
                      segments: const [
                        CruSegment(VisitType.clinic, 'Clinic'),
                        CruSegment(VisitType.home, 'Home visit'),
                      ],
                      selected: _type,
                      onChanged: (v) {
                        _type = v;
                        _edited();
                      },
                    ),
                  ),
                ),
                if (_type == VisitType.home) ...[
                  _AddressField(
                    controller: _address,
                    onChanged: _edited,
                    onPlaceSelected: (lat, lng) {
                      _lat = lat;
                      _lng = lng;
                      _edited();
                    },
                  ),
                  CruTextField(
                    label: 'Google Maps link',
                    optional: true,
                    controller: _mapsLink,
                    hint: 'https://maps.app.goo.gl/…',
                    keyboardType: TextInputType.url,
                    onChanged: _edited,
                  ),
                ],
              ],
            ),
          CruFormSection(
            title: 'Seen together',
            description: 'A couple or family in the same slot. Each gets '
                'their own visit and history.',
            children: [
              for (var i = 0; i < _others.length; i++)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: CruTextField(
                        label: 'Reason for ${_others[i].$1.fullName}',
                        optional: true,
                        controller: _others[i].$2,
                        hint: 'Knee pain, follow-up…',
                        onChanged: (_) => _edited(),
                      ),
                    ),
                    const SizedBox(width: CruSpace.s8),
                    CruSquareButton(
                      icon: CruIcons.close,
                      semanticLabel: 'Remove ${_others[i].$1.firstName}',
                      tooltip: 'Remove ${_others[i].$1.firstName}',
                      onPressed: () => _removeOther(i),
                    ),
                  ],
                ),
              if (_others.length + 1 < kMaxGroupPatients)
                Align(
                  alignment: Alignment.centerLeft,
                  child: CruCapsuleButton(
                    label: _others.isEmpty
                        ? 'Add another patient'
                        : 'Add one more',
                    icon: CruIcons.userPlus,
                    onPressed: _addOther,
                  ),
                ),
            ],
          ),
          CruFormSection(
            title: 'Visit',
            description: 'Why they’re coming and anything to prepare.',
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  CruTextField(
                    label: 'Reason',
                    optional: true,
                    controller: _reason,
                    hint: 'Follow-up, consultation, procedure…',
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: _edited,
                  ),
                  const SizedBox(height: CruSpace.s8),
                  Wrap(
                    spacing: CruSpace.s6,
                    runSpacing: CruSpace.s6,
                    children: [
                      for (final r in _quickReasons)
                        IntrinsicWidth(
                          child: CruCapsuleButton(
                            label: r,
                            height: CruSize.rowCapsule,
                            semanticLabel: 'Use reason, $r',
                            onPressed: () {
                              _reason.text = r;
                              _edited();
                            },
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              CruTextField(
                label: 'Notes',
                optional: true,
                controller: _notes,
                maxLines: 3,
                hint: 'Complaints, equipment to bring, preparation…',
                textCapitalization: TextCapitalization.sentences,
                onChanged: _edited,
              ),
            ],
          ),
          if (showAfter)
            CruFormSection(
              title: 'After booking',
              description: 'What happens once the visit is saved.',
              children: [
                if (_canWhatsApp)
                  _OptionRow(
                    title: 'Send confirmation on WhatsApp',
                    detail: 'Opens WhatsApp with the visit details for $phone.',
                    value: _sendWhatsApp,
                    onChanged: (v) {
                      _sendWhatsApp = v;
                      _edited();
                    },
                  ),
                if (queueOn)
                  _OptionRow(
                    title: 'Add to the queue',
                    detail: 'Gives them a token in today’s clinic queue.',
                    value: _addToQueue,
                    onChanged: (v) {
                      _addToQueue = v;
                      _edited();
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Address with Google Places suggestions. Picking one fills the field
/// and hands back its coordinates; free text is kept as typed.
class _AddressField extends ConsumerStatefulWidget {
  const _AddressField({
    required this.controller,
    required this.onChanged,
    required this.onPlaceSelected,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final void Function(double lat, double lng) onPlaceSelected;

  @override
  ConsumerState<_AddressField> createState() => _AddressFieldState();
}

class _AddressFieldState extends ConsumerState<_AddressField> {
  final _places = GooglePlacesService.instance;
  final _focus = FocusNode();

  List<PlacePrediction> _predictions = const [];
  bool _loading = false;

  /// The last search ran and found nothing.
  bool _noMatch = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focus.removeListener(_onFocus);
    _focus.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (_focus.hasFocus) return;
    // Let a tap on a suggestion land before the list goes away.
    Future.delayed(CruMotion.fast, () {
      if (mounted && !_focus.hasFocus) {
        setState(() => _predictions = const []);
      }
    });
  }

  void _onChanged(String value) {
    widget.onChanged(value);
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 3) {
      setState(() {
        _predictions = const [];
        _loading = false;
        _noMatch = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      // Nearest to the doctor (or else the clinic) first.
      final near = await searchOriginNow(ref);
      final results = await _places.autocomplete(query, near: near);
      if (!mounted || widget.controller.text.trim() != query) return;
      setState(() {
        _predictions = results;
        _loading = false;
        _noMatch = results.isEmpty;
      });
    });
  }

  Future<void> _pick(PlacePrediction p) async {
    widget.controller.text = p.description;
    setState(() {
      _predictions = const [];
      _loading = true;
    });
    final details = await _places.getPlaceDetails(p.placeId);
    if (!mounted) return;
    setState(() => _loading = false);
    if (details == null) return;
    if (details.formattedAddress.isNotEmpty) {
      widget.controller.text = details.formattedAddress;
    }
    widget.onPlaceSelected(details.latitude, details.longitude);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    // Watching starts finding where the doctor is while they type.
    final origin = ref.watch(addressSearchOriginProvider);
    final from = origin.value;
    final noKey = ref.watch(mapsKeyProvider).value?.isEmpty ?? false;
    final help = noKey
        ? "Address search isn't set up yet. Type the full address."
        : _noMatch
            ? 'No matching places. Keep typing, or enter the full address.'
            : from != null
                ? 'Nearest to ${from.fromYou ? 'you' : 'the clinic'} first. '
                    'Pick one to pin it on the map.'
                : origin.isLoading
                    ? 'Pick a suggestion to pin it on the map.'
                    : 'Pick a suggestion to pin it on the map. Turn on '
                        'location, or add the clinic address in Settings, '
                        'to see nearby places first.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CruTextField(
          label: 'Address',
          controller: widget.controller,
          focusNode: _focus,
          hint: 'Street, landmark or flat',
          help: help,
          textCapitalization: TextCapitalization.words,
          trailing: _loading
              ? Text('Searching…', style: CruType.caption.tint(c.label3))
              : null,
          onChanged: _onChanged,
        ),
        if (_predictions.isNotEmpty) ...[
          const SizedBox(height: CruSpace.s6),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: ShapeDecoration(
              color: c.surface,
              shape: cruShape(
                CruRadius.control,
                side: BorderSide(color: c.hairline),
              ),
              shadows: c.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _predictions.length && i < 5; i++) ...[
                  if (i > 0) const CruSeparator(),
                  _Suggestion(
                    prediction: _predictions[i],
                    onTap: () => _pick(_predictions[i]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Suggestion extends StatelessWidget {
  const _Suggestion({required this.prediction, required this.onTap});

  final PlacePrediction prediction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final secondary = prediction.secondaryText.trim();
    final m = prediction.distanceMeters;
    final distance = m == null
        ? null
        : m < 1000
            ? '$m m'
            : m < 100000
                ? '${(m / 1000).toStringAsFixed(1)} km'
                : '${(m / 1000).round()} km';
    return CruPressable(
      onTap: onTap,
      semanticLabel: prediction.description,
      scaleOnPress: false,
      builder: (context, hovered) => Container(
        color: hovered ? c.hoverFill : c.surface,
        padding: const EdgeInsets.symmetric(
          horizontal: CruSpace.s14,
          vertical: CruSpace.s10,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    prediction.mainText,
                    style: CruType.text.w500.tint(c.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (secondary.isNotEmpty) ...[
                    const SizedBox(height: CruSpace.s2),
                    Text(
                      secondary,
                      style: CruType.caption.tint(c.label3),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (distance != null) ...[
              const SizedBox(width: CruSpace.s12),
              Text(distance, style: CruType.caption.tabular.tint(c.label2)),
            ],
          ],
        ),
      ),
    );
  }
}

/// A checkbox with a title and a line of detail.
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.title,
    required this.detail,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String detail;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Semantics(
      checked: value,
      child: CruPressable(
        onTap: () => onChanged(!value),
        semanticLabel: title,
        scaleOnPress: false,
        builder: (context, hovered) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: CruMotion.of(context, CruMotion.fast),
              curve: CruMotion.curve,
              width: CruSize.formTagClose,
              height: CruSize.formTagClose,
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: value ? c.label : (hovered ? c.inset : c.surface),
                shape: cruShape(
                  CruRadius.keycap,
                  side: BorderSide(
                    color: value ? c.label : c.separator,
                    width: 1.5,
                  ),
                ),
              ),
              child: value
                  ? CruIcon(
                      CruIcons.check,
                      size: 14,
                      strokeWidth: 2.4,
                      color: c.surface,
                    )
                  : null,
            ),
            const SizedBox(width: CruSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: CruType.text.w500.tint(c.label)),
                  const SizedBox(height: CruSpace.s2),
                  Text(detail, style: CruType.caption.tabular.tint(c.label3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
