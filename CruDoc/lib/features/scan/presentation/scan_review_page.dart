import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/appointments/presentation/patient_picker_dialog.dart';
import 'package:doctor_management_app/features/files/data/files_repository.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/note_editing.dart';
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/session_choices.dart';
import 'package:doctor_management_app/features/patients/data/providers/session_files_provider.dart';
import 'package:doctor_management_app/features/scan/data/scan_capture.dart';
import 'package:doctor_management_app/features/scan/presentation/scan_flow.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// One photo being reviewed.
class _Shot {
  _Shot(this.page, this.patient);

  ScannedPage page;
  final TextEditingController note = TextEditingController();
  final FocusNode noteFocus = FocusNode();

  /// The note is being written.
  bool writing = false;
  Patient? patient;

  /// The session it also goes in; null: under the patient only, which is
  /// how every photo starts.
  Visit? visit;

  /// How it is shown: quarter turns clockwise (not wrapped, so the picture
  /// always turns the short way), then mirrored left to right.
  int turns = 0;
  bool mirrored = false;

  /// A note is being written or has been.
  bool get noted => writing || note.text.trim().isNotEmpty;

  bool get isTurned => turns % 4 != 0 || mirrored;

  /// The picture with the turns and mirroring written into it.
  Future<ScannedPage> finished() async =>
      isTurned ? await ScanCapture.turned(page, turns, mirrored) : page;
}

/// What happens after Done: the photos just taken, one at a time and swiped
/// through. Each has its own patient (tapped on the picture; held, it
/// becomes every photo's), note and session, and can be retaken, turned,
/// mirrored or removed. Saving puts them in those patients' files.
///
/// [patient] starts every photo on that patient. The AI uses of a scan
/// (session note, record, supplier bill) are behind "Use with AI".
class ScanReviewPage extends ConsumerStatefulWidget {
  const ScanReviewPage({
    super.key,
    required this.pages,
    this.patient,
    required this.inventory,
    required this.revenue,
  });

  final List<ScannedPage> pages;
  final Patient? patient;
  final bool inventory;
  final bool revenue;

  @override
  ConsumerState<ScanReviewPage> createState() => _ScanReviewPageState();
}

class _ScanReviewPageState extends ConsumerState<ScanReviewPage> {
  /// The session lines and Save under the photo.
  static const double _panelHeight = 154;

  late final List<_Shot> _shots = [
    for (final p in widget.pages) _Shot(p, widget.patient),
  ];

  /// Saved or removed; their text boxes are let go with the page.
  final List<_Shot> _gone = [];

  final PageController _pager = PageController(viewportFraction: 0.9);
  int _index = 0;

  /// Saving, or preparing the pictures.
  bool _busy = false;

  @override
  void dispose() {
    _pager.dispose();
    for (final s in _shots.followedBy(_gone)) {
      s.note.dispose();
      s.noteFocus.dispose();
    }
    super.dispose();
  }

  // ---- Patient and session -----------------------------------------------

  /// The patient's recent sessions; null when they could not be read.
  Future<List<Visit>?> _sessionsOf(Patient patient) async {
    try {
      final all = await ref
          .read(visitRepositoryProvider)
          .watchVisitsForPatient(patient.id)
          .first
          .timeout(const Duration(seconds: 4));
      return sessionChoices(all, DateTime.now()).take(12).toList();
    } catch (e) {
      debugPrint('[ScanReview] visits unavailable: $e');
      return null;
    }
  }

  void _give(_Shot shot, Patient patient) {
    if (shot.patient?.id == patient.id) return;
    shot
      ..patient = patient
      ..visit = null;
  }

  Future<void> _assign(_Shot shot) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    final patient = await showPatientPickerDialog(
      mobileRoot(context),
      title: 'Whose photo is this?',
    );
    if (patient == null || !mounted) return;
    setState(() => _give(shot, patient));
  }

  /// This photo's patient for every photo.
  void _useForAll(_Shot from) {
    final patient = from.patient;
    if (patient == null || _busy) return;
    MobileHaptics.commit();
    setState(() {
      for (final s in _shots) {
        _give(s, patient);
      }
    });
    mobileSay(context, 'All photos set to ${patient.fullName}.');
  }

  /// "Yes": which of the patient's recent sessions the photo goes in.
  /// Backing out leaves it as it was.
  Future<void> _pickSession(_Shot shot) async {
    final patient = shot.patient;
    if (patient == null || _busy) return;
    FocusScope.of(context).unfocus();
    final choices = await _sessionsOf(patient);
    if (!mounted) return;
    if (choices == null || choices.isEmpty) {
      mobileSay(
        context,
        choices == null
            ? "Couldn't read the sessions. Try again."
            : '${patient.firstName} has no recent sessions.',
      );
      return;
    }
    final now = DateTime.now();
    await showMobileActionSheet(
      context,
      title: 'Which session?',
      subtitle: patient.fullName,
      actions: [
        for (final v in choices)
          MobileSheetAction(
            label: sessionLabel(v, now),
            icon: v.id == shot.visit?.id ? CruIcons.check : CruIcons.calendar,
            tone: v.id == shot.visit?.id ? MobileTone.blue : MobileTone.slate,
            onTap: () => setState(() => shot.visit = v),
          ),
      ],
    );
  }

  // ---- The note ----------------------------------------------------------

  /// Opens this photo's note under it, with the keyboard.
  void _writeNote(_Shot shot) {
    if (_busy || shot.writing) return;
    MobileHaptics.select();
    setState(() => shot.writing = true);
    // The field is there once this frame is built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && shot.writing) shot.noteFocus.requestFocus();
    });
  }

  void _noteDone(_Shot shot) {
    if (!shot.writing) return;
    shot.noteFocus.unfocus();
    setState(() => shot.writing = false);
  }

  /// How tall the note under a photo is: room to write in while writing,
  /// then just what it says, up to three lines.
  double _noteHeight(BuildContext context, _Shot shot) {
    final scaler = MediaQuery.textScalerOf(context);
    final text = shot.note.text.trim();
    if (shot.writing || text.isEmpty) return scaler.scale(19) * 4 + 60;
    final painter = TextPainter(
      text: TextSpan(text: text, style: MobileType.subhead),
      textDirection: Directionality.of(context),
      textScaler: scaler,
      maxLines: 3,
    )..layout(maxWidth: MediaQuery.sizeOf(context).width * 0.9 - 84);
    final height = painter.height;
    painter.dispose();
    return math.max(52, height + 24);
  }

  // ---- The picture -------------------------------------------------------

  Future<void> _retake(_Shot shot) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    final List<ScannedPage> pages;
    try {
      pages = await ScanCapture.capture(mobileRoot(context), maxPages: 1);
    } on ScanCaptureException catch (e) {
      if (mounted) mobileSay(context, e.message);
      return;
    }
    if (pages.isEmpty || !mounted) return;
    setState(() {
      shot
        ..page = pages.first
        ..turns = 0
        ..mirrored = false;
    });
  }

  void _rotate(_Shot shot) {
    if (_busy) return;
    MobileHaptics.select();
    // Anticlockwise as seen, whether or not the picture is mirrored.
    setState(() => shot.turns += shot.mirrored ? 1 : -1);
  }

  void _mirror(_Shot shot) {
    if (_busy) return;
    MobileHaptics.select();
    setState(() => shot.mirrored = !shot.mirrored);
  }

  Future<bool> _confirm(String title, String body, String yes) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(yes),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _remove(_Shot shot) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    final yes = await _confirm(
      'Remove this photo?',
      'It has not been saved.',
      'Remove',
    );
    if (!yes || !mounted) return;
    setState(() {
      _shots.remove(shot);
      _gone.add(shot);
      if (_index >= _shots.length) _index = math.max(0, _shots.length - 1);
    });
    if (_shots.isEmpty) Navigator.of(context).pop();
  }

  Future<List<ScannedPage>?> _finishedPages() async {
    try {
      return [for (final s in _shots) await s.finished()];
    } catch (e) {
      debugPrint('[ScanReview] could not prepare a picture: $e');
      if (mounted) mobileSay(context, "Couldn't prepare the photo. Try again.");
      return null;
    }
  }

  Future<void> _open(int index) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    final pages = await _finishedPages();
    if (pages != null && mounted) openScanPages(context, pages, index);
  }

  // ---- Leaving -----------------------------------------------------------

  Future<void> _leave() async {
    if (_busy) return;
    final yes = await _confirm(
      'Discard the photos?',
      'They have not been saved to any patient.',
      'Discard',
    );
    if (yes && mounted) Navigator.of(context).pop();
  }

  Future<void> _useWithAi() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    final navigator = Navigator.of(context);
    final root = mobileRoot(context);
    final pages = await _finishedPages();
    if (pages == null || !root.mounted) return;
    await showScanUses(
      root,
      pages: pages,
      patient: widget.patient,
      clinical: true,
      inventory: widget.inventory,
      revenue: widget.revenue,
      leaving: navigator.pop,
    );
  }

  Future<void> _save() async {
    if (_busy) return;
    final missing = _shots.indexWhere((s) => s.patient == null);
    if (missing >= 0) {
      // Show the photo that still needs someone, and ask.
      FocusScope.of(context).unfocus();
      if (missing != _index) {
        await _pager.animateToPage(
          missing,
          duration: CruMotion.standard,
          curve: CruMotion.curve,
        );
      }
      if (mounted) await _assign(_shots[missing]);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final root = mobileRoot(context);
    final day = DateFormat('d MMM yyyy').format(DateTime.now());
    final total = _shots.length;
    final names = <String>{};
    var unlinked = false;
    try {
      while (_shots.isNotEmpty) {
        final first = _shots.first;
        final patient = first.patient!;
        final visit = first.visit;
        // Photos going to the same place are saved together.
        final batch = _shots
            .where(
              (s) => s.patient!.id == patient.id && s.visit?.id == visit?.id,
            )
            .toList();
        names.add(patient.firstName);
        final sources = <FileSource>[];
        for (var i = 0; i < batch.length; i++) {
          final page = await batch[i].finished();
          sources.add(
            FileSource(
              name: batch.length == 1
                  ? 'Photo $day.jpg'
                  : 'Photo $day (${i + 1} of ${batch.length}).jpg',
              sizeBytes: page.jpeg.lengthInBytes,
              bytes: page.jpeg,
              note: batch[i].note.text,
            ),
          );
        }
        final ids = await FilesRepository.instance.addFilesWithIds(
          sources,
          patientId: patient.id,
        );
        // They are kept from here on: a second try must not add them again.
        _shots.removeWhere(batch.contains);
        _gone.addAll(batch);
        try {
          await setFilesVisit(ref, patient.id, ids, visit);
        } catch (e) {
          debugPrint('[ScanReview] session link failed: $e');
          unlinked = true;
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      if (root.mounted) {
        final count = total == 1 ? '1 photo' : '$total photos';
        final whom = names.length == 1
            ? "${names.single}'s files"
            : '${names.length} patients’ files';
        mobileSay(
          root,
          unlinked
              ? 'Saved $count to $whom, but the session could not be set.'
              : 'Saved $count to $whom.',
        );
      }
    } catch (e) {
      debugPrint('[ScanReview] save failed: $e');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _index = 0;
      });
      if (_pager.hasClients) _pager.jumpToPage(0);
      mobileSay(context, "Couldn't save the photos. Try again.");
    }
  }

  // ---- UI ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // A dark room for looking at photos, in the app's own evening colours.
    return Theme(
      data: CruTheme.evening(),
      child: Builder(builder: _body),
    );
  }

  Widget _body(BuildContext context) {
    final count = _shots.length;
    final unassigned = _shots.where((s) => s.patient == null).length;
    // The session and Save sit where the keyboard comes up. They give their
    // room to it exactly as it rises, so the photo moves once and smoothly.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final foot = MediaQuery.viewPaddingOf(context).bottom;
    final below = math.max(_panelHeight + foot, keyboard);
    final visible = (1 - keyboard / _panelHeight).clamp(0.0, 1.0);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.black,
          resizeToAvoidBottomInset: false,
          body: SafeArea(
            bottom: false,
            child: count == 0
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _topBar(context),
                      _toolRow(context, _shots[_index], count),
                      Expanded(
                        child: PageView.builder(
                          controller: _pager,
                          // The neighbours are ready before they are swiped
                          // to.
                          allowImplicitScrolling: true,
                          itemCount: count,
                          onPageChanged: (i) {
                            for (final s in _shots) {
                              _noteDone(s);
                            }
                            MobileHaptics.select();
                            setState(() => _index = i);
                          },
                          itemBuilder: (context, i) {
                            final s = _shots[i];
                            return _PhotoPage(
                              key: ObjectKey(s),
                              shot: s,
                              number: i + 1,
                              // Holding the patient only means something
                              // when a photo has someone else, or no one.
                              others: _shots.any(
                                (o) => o.patient?.id != s.patient?.id,
                              ),
                              enabled: !_busy,
                              presence: s.noted ? 1 : 0,
                              noteHeight: _noteHeight(context, s),
                              turns: s.turns.toDouble(),
                              flip: s.mirrored ? -1 : 1,
                              duration: CruMotion.of(
                                context,
                                CruMotion.standard,
                              ),
                              // Closing is the same motion backwards.
                              curve: s.noted
                                  ? CruMotion.curve
                                  : CruMotion.curve.flipped,
                              onOpen: () => s.writing ? _noteDone(s) : _open(i),
                              onRemove: () => _remove(s),
                              onPatient: () => _assign(s),
                              onUseForAll: () => _useForAll(s),
                              onNote: () => _writeNote(s),
                              onNoteDone: () => _noteDone(s),
                            );
                          },
                        ),
                      ),
                      SizedBox(
                        height: below,
                        child: ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.topCenter,
                            minHeight: _panelHeight,
                            maxHeight: _panelHeight,
                            child: IgnorePointer(
                              ignoring: visible < 0.5,
                              child: Opacity(
                                opacity: visible,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _sessionPanel(context, _shots[_index]),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        MobileMetrics.gutter,
                                        CruSpace.s8,
                                        MobileMetrics.gutter,
                                        CruSpace.s12,
                                      ),
                                      child: MobilePrimaryButton(
                                        label: _busy
                                            ? 'Saving…'
                                            : unassigned > 0
                                            ? 'Assign a patient to save'
                                            : count == 1
                                            ? 'Save 1 photo'
                                            : 'Save $count photos',
                                        icon: unassigned > 0
                                            ? null
                                            : CruIcons.check,
                                        onPressed: _busy ? null : _save,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    final c = context.cru;
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          const SizedBox(width: CruSpace.s8),
          IconButton(
            onPressed: _leave,
            tooltip: 'Close',
            icon: const CruIcon(CruIcons.close, color: Colors.white),
          ),
          const SizedBox(width: CruSpace.s4),
          Expanded(
            child: Text(
              'Review photos',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MobileType.headline.tint(Colors.white),
            ),
          ),
          CruPressable(
            onTap: _useWithAi,
            semanticLabel: widget.inventory
                ? 'Use with AI: session note, record or bill'
                : 'Use with AI: session note or record',
            builder: (context, _) => Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
              decoration: ShapeDecoration(
                color: c.aiTint,
                shape: const StadiumBorder(),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CruIcon(CruIcons.sparkle, size: 16, color: c.ai),
                  const SizedBox(width: CruSpace.s6),
                  Text('Use with AI', style: MobileType.subhead.tint(c.ai)),
                ],
              ),
            ),
          ),
          const SizedBox(width: CruSpace.s16),
        ],
      ),
    );
  }

  /// Which photo this is, and what can be done to the picture.
  Widget _toolRow(BuildContext context, _Shot shot, int count) {
    Widget tool(IconData icon, String label, VoidCallback onTap) => IconButton(
      onPressed: _busy ? null : onTap,
      tooltip: label,
      icon: Icon(icon, size: 22, color: Colors.white),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
      child: Row(
        children: [
          const SizedBox(width: CruSpace.s8),
          Text(
            '${_index + 1} / $count',
            style: MobileType.headline
                .tint(Colors.white)
                .copyWith(fontFeatures: CruType.tabular),
          ),
          const Spacer(),
          tool(Icons.photo_camera_outlined, 'Retake', () => _retake(shot)),
          tool(
            Icons.rotate_90_degrees_ccw_outlined,
            'Rotate',
            () => _rotate(shot),
          ),
          tool(Icons.flip_rounded, 'Mirror', () => _mirror(shot)),
        ],
      ),
    );
  }

  /// The session of the photo in view, for its patient: none unless "Yes"
  /// and a session is chosen. Always the same height, so nothing jumps while
  /// swiping.
  Widget _sessionPanel(BuildContext context, _Shot shot) {
    final c = context.cru;
    final patient = shot.patient;
    final visit = shot.visit;
    final Widget content;
    if (patient == null) {
      content = Center(
        child: Text(
          'Assign a patient to add this photo to a session',
          textAlign: TextAlign.center,
          style: MobileType.subhead.tint(c.label3),
        ),
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 44,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    "Add to ${patient.firstName}'s session?",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MobileType.row.tint(c.label),
                  ),
                ),
                const SizedBox(width: CruSpace.s12),
                CruSegmentedControl<bool>(
                  semanticLabel: 'Add to a session',
                  segments: const [
                    CruSegment(true, 'Yes'),
                    CruSegment(false, 'No'),
                  ],
                  selected: visit != null,
                  onChanged: (yes) {
                    if (_busy) return;
                    if (yes) {
                      _pickSession(shot);
                    } else {
                      setState(() => shot.visit = null);
                    }
                  },
                ),
              ],
            ),
          ),
          if (visit != null)
            CruPressable(
              onTap: () => _pickSession(shot),
              scaleOnPress: false,
              semanticLabel: 'Change the session',
              builder: (context, _) => SizedBox(
                height: 36,
                child: Row(
                  children: [
                    CruIcon(CruIcons.calendar, size: 16, color: c.label3),
                    const SizedBox(width: CruSpace.s8),
                    Expanded(
                      child: Text(
                        sessionLabel(visit, DateTime.now()),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MobileType.subhead
                            .tint(c.label2)
                            .copyWith(fontFeatures: CruType.tabular),
                      ),
                    ),
                    CruIcon(CruIcons.chevronRight, size: 16, color: c.label3),
                  ],
                ),
              ),
            )
          else
            SizedBox(
              height: 36,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Saved under ${patient.firstName} only',
                  style: MobileType.subhead.tint(c.label3),
                ),
              ),
            ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MobileMetrics.gutter,
        CruSpace.s4,
        MobileMetrics.gutter,
        0,
      ),
      child: SizedBox(height: 80, child: content),
    );
  }
}

/// One photo filling the page: its remove button, whose it is on the lower
/// left, and its note.
///
/// The note is "the same box" (design/motion-transitions.md): the "Add note"
/// button on the picture grows into the card under it while the picture
/// makes room, and shrinks back into the button. [presence] is how far that
/// has gone.
class _PhotoPage extends ImplicitlyAnimatedWidget {
  const _PhotoPage({
    super.key,
    required this.shot,
    required this.number,
    required this.others,
    required this.enabled,
    required this.presence,
    required this.noteHeight,
    required this.turns,
    required this.flip,
    required this.onOpen,
    required this.onRemove,
    required this.onPatient,
    required this.onUseForAll,
    required this.onNote,
    required this.onNoteDone,
    required super.duration,
    super.curve,
  });

  final _Shot shot;
  final int number;
  final bool others;
  final bool enabled;
  final double presence;
  final double noteHeight;
  final double turns;
  final double flip;
  final VoidCallback onOpen;
  final VoidCallback onRemove;
  final VoidCallback onPatient;
  final VoidCallback onUseForAll;
  final VoidCallback onNote;
  final VoidCallback onNoteDone;

  @override
  ImplicitlyAnimatedWidgetState<_PhotoPage> createState() => _PhotoPageState();
}

class _PhotoPageState extends AnimatedWidgetBaseState<_PhotoPage> {
  Tween<double>? _presence;
  Tween<double>? _height;
  Tween<double>? _turns;
  Tween<double>? _flip;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    Tween<double> make(dynamic v) => Tween<double>(begin: v as double);
    _presence = visitor(_presence, widget.presence, make) as Tween<double>?;
    _height = visitor(_height, widget.noteHeight, make) as Tween<double>?;
    _turns = visitor(_turns, widget.turns, make) as Tween<double>?;
    _flip = visitor(_flip, widget.flip, make) as Tween<double>?;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final shot = widget.shot;
    final patient = shot.patient;
    final p = _presence!.evaluate(animation).clamp(0.0, 1.0);
    final noteHeight = _height!.evaluate(animation);
    final turn = _turns!.evaluate(animation);
    final flip = _flip!.evaluate(animation);
    final width = shot.page.width.toDouble();
    final height = shot.page.height.toDouble();

    final label = TextPainter(
      text: TextSpan(text: 'Add note', style: MobileType.subhead),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final buttonWidth = label.width + 16 + CruSpace.s8 + CruSpace.s16 * 2 + 2;
    label.dispose();

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s6,
        vertical: CruSpace.s8,
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final all = box.biggest;
          // The picture gives the note its room as the note takes shape.
          final area = Size(
            all.width,
            math.max(40, all.height - (noteHeight + CruSpace.s8) * p),
          );
          final angle = turn * math.pi / 2;
          final onSide = math.pow(math.sin(angle), 2).toDouble();
          // Fitted upright, fitted on its side, and between while turning.
          final size = lerpDouble(
            math.min(area.width / width, area.height / height),
            math.min(area.width / height, area.height / width),
            onSide,
          )!;
          final rect = Rect.fromCenter(
            center: area.center(Offset.zero),
            width: lerpDouble(width, height, onSide)! * size,
            height: lerpDouble(height, width, onSide)! * size,
          );
          final button = Rect.fromLTWH(
            rect.right - CruSpace.s8 - buttonWidth,
            rect.bottom - CruSpace.s8 - 44,
            buttonWidth,
            44,
          );
          final card = Rect.fromLTWH(
            0,
            all.height - noteHeight,
            all.width,
            noteHeight,
          );
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                top: 0,
                width: area.width,
                height: area.height,
                child: Semantics(
                  label: 'Photo ${widget.number}. Tap to see it full screen.',
                  image: true,
                  child: GestureDetector(
                    onTap: widget.onOpen,
                    child: Transform.scale(
                      scaleX: flip,
                      scaleY: 1,
                      child: Transform.rotate(
                        angle: angle,
                        child: OverflowBox(
                          minWidth: width * size,
                          maxWidth: width * size,
                          minHeight: height * size,
                          maxHeight: height * size,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              CruRadius.control,
                            ),
                            child: Image.memory(
                              shot.page.jpeg,
                              fit: BoxFit.fill,
                              cacheWidth: 1200,
                              gaplessPlayback: true,
                              filterQuality: FilterQuality.medium,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: math.max(0, rect.left - 4),
                top: math.max(0, rect.top - 4),
                child: CruPressable(
                  onTap: widget.onRemove,
                  semanticLabel: 'Remove photo ${widget.number}',
                  builder: (context, _) => Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.65),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                    child: const CruIcon(
                      CruIcons.close,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: rect.left + CruSpace.s8,
                bottom: all.height - rect.bottom + CruSpace.s8,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: math.max(
                      96,
                      rect.width -
                          CruSpace.s8 * 2 -
                          (buttonWidth + CruSpace.s8) * (1 - p),
                    ),
                  ),
                  child: _PatientChip(
                    patient: patient,
                    number: widget.number,
                    holdable: patient != null && widget.others,
                    fill: patient == null
                        ? c.accent
                        : Colors.black.withValues(alpha: 0.7),
                    onTap: widget.onPatient,
                    onHeld: widget.onUseForAll,
                  ),
                ),
              ),
              Positioned.fromRect(
                rect: Rect.lerp(button, card, p)!,
                child: _NoteBox(
                  shot: shot,
                  number: widget.number,
                  enabled: widget.enabled,
                  presence: p,
                  cardSize: card.size,
                  onTap: widget.onNote,
                  onDone: widget.onNoteDone,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Whose photo it is. A tap chooses; held for three and a half seconds,
/// this patient becomes every photo's.
class _PatientChip extends StatefulWidget {
  const _PatientChip({
    required this.patient,
    required this.number,
    required this.holdable,
    required this.fill,
    required this.onTap,
    required this.onHeld,
  });

  final Patient? patient;
  final int number;
  final bool holdable;
  final Color fill;
  final VoidCallback onTap;
  final VoidCallback onHeld;

  @override
  State<_PatientChip> createState() => _PatientChipState();
}

class _PatientChipState extends State<_PatientChip>
    with SingleTickerProviderStateMixin {
  static const _hold = Duration(milliseconds: 3500);

  /// Let go sooner than this and it was a tap.
  static const _tap = 0.15;

  late final AnimationController _held =
      AnimationController(vsync: this, duration: _hold)
        ..addStatusListener((status) {
          if (status != AnimationStatus.completed) return;
          _done = true;
          widget.onHeld();
        });
  bool _done = false;

  @override
  void dispose() {
    _held.dispose();
    super.dispose();
  }

  void _down(TapDownDetails _) {
    _done = false;
    if (widget.holdable) _held.forward(from: 0);
  }

  void _up(TapUpDetails _) {
    final far = _held.value;
    _held.reset();
    // Held to the end it has done its work; given up halfway, nothing.
    if (!_done && (!widget.holdable || far < _tap)) widget.onTap();
  }

  void _cancel() {
    if (!_done) _held.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final patient = widget.patient;
    return Semantics(
      button: true,
      label: patient == null
          ? 'Assign a patient to photo ${widget.number}'
          : 'Patient: ${patient.fullName}. Change.',
      onTap: widget.onTap,
      onLongPressHint: widget.holdable ? 'use for all photos' : null,
      onLongPress: widget.holdable ? widget.onHeld : null,
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: _down,
        onTapUp: _up,
        onTapCancel: _cancel,
        child: AnimatedBuilder(
          animation: _held,
          builder: (context, _) {
            final holding = _held.value >= _tap;
            return Container(
              height: 44,
              clipBehavior: Clip.antiAlias,
              decoration: ShapeDecoration(
                color: widget.fill,
                shape: StadiumBorder(
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
                ),
              ),
              child: Stack(
                children: [
                  // Fills while held: how far there is to go.
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: _held.value,
                      child: ColoredBox(
                        color: Colors.white.withValues(alpha: 0.28),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: CruSpace.s16,
                    ),
                    child: SizedBox(
                      height: 44,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CruIcon(
                            CruIcons.user,
                            size: 16,
                            color: Colors.white,
                          ),
                          const SizedBox(width: CruSpace.s8),
                          Flexible(
                            child: Text(
                              holding
                                  ? 'Hold for all photos'
                                  : patient?.fullName ?? 'Assign patient',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: MobileType.subhead.tint(Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The note's box at any point between the button on the picture
/// ([presence] 0) and the card under it (1).
class _NoteBox extends StatelessWidget {
  const _NoteBox({
    required this.shot,
    required this.number,
    required this.enabled,
    required this.presence,
    required this.cardSize,
    required this.onTap,
    required this.onDone,
  });

  final _Shot shot;
  final int number;
  final bool enabled;
  final double presence;
  final Size cardSize;
  final VoidCallback onTap;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final p = presence;
    final text = shot.note.text.trim();
    final box = Container(
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: Color.lerp(Colors.black.withValues(alpha: 0.7), Colors.white, p),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            lerpDouble(22, CruRadius.control, p)!,
          ),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.35 * (1 - p)),
          ),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The button's own face leaves as the box opens...
          if (p < 1)
            Opacity(
              opacity: (1 - p / 0.4).clamp(0.0, 1.0),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CruIcon(CruIcons.pen, size: 16, color: Colors.white),
                    const SizedBox(width: CruSpace.s8),
                    Text(
                      'Add note',
                      style: MobileType.subhead.tint(Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          // ...and the card, laid out full size and scaled with the box,
          // arrives once it is mostly open.
          if (p > 0 || shot.writing)
            Opacity(
              opacity: ((p - 0.35) / 0.5).clamp(0.0, 1.0),
              child: FittedBox(
                child: SizedBox(
                  width: cardSize.width,
                  height: cardSize.height,
                  child: AnimatedSwitcher(
                    duration: CruMotion.of(context, CruMotion.fast),
                    switchInCurve: CruMotion.curve,
                    child: shot.writing
                        ? _NoteEditor(
                            key: const ValueKey('writing'),
                            shot: shot,
                            enabled: enabled,
                            onDone: onDone,
                          )
                        : _NoteText(key: const ValueKey('written'), text: text),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    if (shot.writing) return box;
    return CruPressable(
      onTap: onTap,
      scaleOnPress: false,
      semanticLabel: text.isEmpty
          ? 'Add a note to photo $number'
          : 'Note on photo $number: $text. Change it.',
      builder: (context, _) => box,
    );
  }
}

/// A written note, read at a glance.
class _NoteText extends StatelessWidget {
  const _NoteText({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    // While the box is still the editor's height, keep to the top.
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          CruSpace.s16,
          CruSpace.s12,
          CruSpace.s12,
          CruSpace.s12,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: MobileType.subhead.tint(Colors.black),
              ),
            ),
            const SizedBox(width: CruSpace.s8),
            const CruIcon(CruIcons.pen, size: 16, color: Colors.black54),
          ],
        ),
      ),
    );
  }
}

/// Writing the note: the keyboard's key starts a new line, lines can be
/// bulleted, and it holds [kFileNoteLimit] letters.
class _NoteEditor extends StatelessWidget {
  const _NoteEditor({
    super.key,
    required this.shot,
    required this.enabled,
    required this.onDone,
  });

  final _Shot shot;
  final bool enabled;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              CruSpace.s16,
              CruSpace.s12,
              CruSpace.s16,
              0,
            ),
            child: TextField(
              controller: shot.note,
              focusNode: shot.noteFocus,
              enabled: enabled,
              expands: true,
              minLines: null,
              maxLines: null,
              maxLength: kFileNoteLimit,
              inputFormatters: const [NoteListFormatter()],
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              textCapitalization: TextCapitalization.sentences,
              textAlignVertical: TextAlignVertical.top,
              cursorColor: Colors.black,
              style: MobileType.subhead.tint(Colors.black),
              decoration: InputDecoration.collapsed(
                hintText: 'e.g. Mouth cleanup done',
                hintStyle: MobileType.subhead.tint(Colors.black45),
              ).copyWith(counterText: ''),
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: Row(
            children: [
              const SizedBox(width: CruSpace.s8),
              CruPressable(
                onTap: () =>
                    shot.note.value = NoteListFormatter.toggle(shot.note.value),
                semanticLabel: 'Bulleted list',
                builder: (context, _) => const SizedBox.square(
                  dimension: 40,
                  child: Icon(
                    Icons.format_list_bulleted_rounded,
                    size: 20,
                    color: Colors.black87,
                  ),
                ),
              ),
              const SizedBox(width: CruSpace.s8),
              ListenableBuilder(
                listenable: shot.note,
                builder: (context, _) => Text(
                  '${shot.note.text.characters.length} / $kFileNoteLimit',
                  style: MobileType.caption
                      .tint(Colors.black54)
                      .copyWith(fontFeatures: CruType.tabular),
                ),
              ),
              const Spacer(),
              CruPressable(
                onTap: onDone,
                semanticLabel: 'Finish the note',
                builder: (context, _) => Container(
                  height: 40,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: CruSpace.s16),
                  child: Text(
                    'Done',
                    style: MobileType.subhead
                        .tint(MobileBlue.neon)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
