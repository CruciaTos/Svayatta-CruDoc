import 'dart:async';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/features/files/data/colleague_send.dart';
import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/files/data/file_offer_model.dart';
import 'package:doctor_management_app/features/files/data/files_repository.dart';
import 'package:doctor_management_app/features/files/domain/files_models.dart';
import 'package:doctor_management_app/features/files/lan/lan_server.dart';
import 'package:doctor_management_app/features/files/presentation/compose_transfer_dialog.dart';
import 'package:doctor_management_app/features/files/presentation/transfers_sheet.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/colleague_monogram.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/files_style.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/team/data/team_providers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Active colleagues: the ones you sent to most recently first, then the
/// rest by name.
final stripColleaguesProvider = Provider.autoDispose<List<ClinicMember>>((ref) {
  final me = FilesRepository.instance.uid;
  final members = ref.watch(clinicMembersProvider).value ?? const [];
  final sent = ref.watch(sentOffersProvider).value ?? const [];
  final lastSent = <String, DateTime>{};
  for (final o in sent) {
    final t = lastSent[o.to];
    if (t == null || o.createdAt.isAfter(t)) lastSent[o.to] = o.createdAt;
  }
  final list = [
    for (final m in members)
      if (m.active && m.uid != me) m,
  ];
  list.sort((a, b) {
    final ta = lastSent[a.uid];
    final tb = lastSent[b.uid];
    if (ta != null && tb != null) return tb.compareTo(ta);
    if (ta != null) return -1;
    if (tb != null) return 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return list;
});

/// Which strip colleagues have a device answering on this Wi-Fi, by uid
/// (missing: not checked yet). The strip sends over Wi-Fi only, so only
/// these take drops. Checked when a colleague joins the strip, when the
/// network changes and every 30 seconds, never on a rebuild.
final colleaguesOnWifiProvider =
    NotifierProvider.autoDispose<ColleaguesOnWifi, Map<String, bool>>(
      ColleaguesOnWifi.new,
    );

class ColleaguesOnWifi extends Notifier<Map<String, bool>> {
  static const _every = Duration(seconds: 30);

  /// After a network change: give the new address a moment to settle.
  static const _settle = Duration(seconds: 2);

  bool _checking = false;
  bool _again = false;

  @override
  Map<String, bool> build() {
    ref.listen(stripColleaguesProvider, (prev, next) {
      final known = {for (final m in prev ?? const <ClinicMember>[]) m.uid};
      if (next.any((m) => !known.contains(m.uid))) unawaited(refresh());
    });
    final timer = Timer.periodic(_every, (_) => unawaited(refresh()));
    final net = Connectivity().onConnectivityChanged.listen(
      (_) => Future.delayed(_settle, refresh),
    );
    ref.onDispose(() {
      timer.cancel();
      net.cancel();
    });
    Future.microtask(refresh);
    return const {};
  }

  /// Probes every strip colleague's device once. A call while one runs
  /// starts another right after it.
  Future<void> refresh() async {
    if (!ref.mounted) return;
    if (_checking) {
      _again = true;
      return;
    }
    _checking = true;
    try {
      do {
        _again = false;
        final clinicId = FilesRepository.instance.doctorId;
        final uids = [for (final m in ref.read(stripColleaguesProvider)) m.uid];
        final answers = await Future.wait([
          for (final uid in uids)
            findColleagueOnWifi(
              clinicId: clinicId,
              colleagueUid: uid,
            ).then((found) => found != null, onError: (Object _) => false),
        ]);
        if (!ref.mounted) return;
        state = {for (var i = 0; i < uids.length; i++) uids[i]: answers[i]};
      } while (_again);
    } finally {
      _checking = false;
    }
  }
}

/// Why the strip can't send to a colleague whose Wi-Fi check gave [onWifi]
/// (null: not checked yet), or null when it can.
String? offWifiReason(bool? onWifi) => switch (onWifi) {
  true => null,
  false => 'Not on this Wi-Fi',
  null => 'Checking Wi-Fi…',
};

/// The colleague a file from Explorer is over, or null. Explorer drags reach
/// the app through the Files screen's DropTarget, not Flutter's drag and
/// drop, so the screen sets this and the avatars listen.
final ValueNotifier<String?> explorerHoverUid = ValueNotifier(null);

/// The colleague whose avatar is at [globalPosition], or null (avatars in
/// an open More list count).
ClinicMember? colleagueAt(Offset globalPosition) {
  for (final s in _ColleagueDropChipState._live) {
    if (_contains(s.context, globalPosition)) return s.widget.member;
  }
  return null;
}

/// An Explorer drag moved to [globalPosition]: holding it on More opens the
/// rest of the colleagues, and leaving More and its list closes them.
void colleagueDragMoved(Offset globalPosition) {
  _MoreChipState._live?._explorerAt(globalPosition);
}

/// An Explorer drag left the window or was dropped.
void colleagueDragEnded() => _MoreChipState._live?._closeSoon();

bool _contains(BuildContext context, Offset globalPosition) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return false;
  return (box.localToGlobal(Offset.zero) & box.size).contains(globalPosition);
}

/// What became of the latest file sent to a colleague, for the ring
/// around their avatar: amber while it waits for them on clinic Wi-Fi
/// (filling with the download as it happens), green once received and grey
/// if declined (both for a day).
enum DeliveryRing { waiting, received, declined }

class ColleagueDelivery {
  const ColleagueDelivery(this.ring, {this.progress, this.waiting = const []});

  final DeliveryRing ring;

  /// How far the file downloading now has got (0 to 1), or null when none
  /// is downloading.
  final double? progress;

  /// Files still waiting for this colleague, newest first.
  final List<FileOffer> waiting;
}

/// What this device's Wi-Fi server knows (download progress, answers that
/// came over Wi-Fi), rebuilt whenever it changes.
final _wifiServerProvider =
    Provider.autoDispose<
      ({Map<String, double> progress, Map<String, String> status})
    >((ref) {
      final server = LanServer.instance;
      void changed() => ref.invalidateSelf();
      server.servedProgress.addListener(changed);
      server.lanStatus.addListener(changed);
      ref.onDispose(() {
        server.servedProgress.removeListener(changed);
        server.lanStatus.removeListener(changed);
      });
      return (
        progress: server.servedProgress.value,
        status: server.lanStatus.value,
      );
    });

final colleagueDeliveryProvider =
    Provider.autoDispose<Map<String, ColleagueDelivery>>((ref) {
      final sent = ref.watch(sentOffersProvider).value ?? const [];
      final wifi = ref.watch(_wifiServerProvider);
      final dayAgo = DateTime.now().subtract(const Duration(days: 1));
      // An answer that came over Wi-Fi counts at once (the cloud may not
      // have it yet).
      FileOfferStatus statusOf(FileOffer o) => switch (wifi.status[o.id]) {
        'accepted' => FileOfferStatus.accepted,
        'declined' => FileOfferStatus.declined,
        _ => o.status,
      };
      bool recent(FileOffer o) =>
          wifi.status.containsKey(o.id) ||
          (o.updatedAt ?? o.createdAt).isAfter(dayAgo);

      final waiting = <String, List<FileOffer>>{};
      for (final o in sent) {
        if (statusOf(o) == FileOfferStatus.sent) {
          (waiting[o.to] ??= []).add(o);
        }
      }
      final out = <String, ColleagueDelivery>{};
      final decided = <String>{};
      // Newest first: the newest offer per colleague picks the ring.
      for (final o in sent) {
        if (!decided.add(o.to)) continue;
        final list = waiting[o.to] ?? const <FileOffer>[];
        switch (statusOf(o)) {
          case FileOfferStatus.sent:
            final moving = [
              for (final w in list)
                if (wifi.progress[w.id] case final p? when p < 1) p,
            ];
            out[o.to] = ColleagueDelivery(
              DeliveryRing.waiting,
              progress: moving.isEmpty ? null : moving.reduce(math.max),
              waiting: list,
            );
          case FileOfferStatus.accepted when recent(o):
            out[o.to] = ColleagueDelivery(DeliveryRing.received, waiting: list);
          case FileOfferStatus.declined when recent(o):
            out[o.to] = ColleagueDelivery(DeliveryRing.declined, waiting: list);
          default:
            if (list.isNotEmpty) {
              out[o.to] = ColleagueDelivery(
                DeliveryRing.waiting,
                waiting: list,
              );
            }
        }
      }
      return out;
    });

/// Plays the dropped file shrinking into [uid]'s avatar from [from]
/// (global), when their avatar is on screen.
void flyFileIntoColleague(String uid, Offset from) {
  for (final s in _ColleagueDropChipState._live) {
    if (s.widget.member.uid == uid) return s._flyFrom(from);
  }
}

/// Sends [files] to [member] over clinic Wi-Fi (the strip never uses the
/// cloud), waiting for them when they aren't on it, and says so, with Undo.
Future<void> sendToColleagueWithUndo(
  ScaffoldMessengerState? messenger,
  ClinicMember member,
  List<PatientFile> files,
) async {
  final name = member.name;
  void say(String text) => messenger?.showSnackBar(
    SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
  );
  try {
    final onWifi =
        await findColleagueOnWifi(
          clinicId: FilesRepository.instance.doctorId,
          colleagueUid: member.uid,
        ) !=
        null;
    final offers = await sendFilesToColleague(
      clinicId: FilesRepository.instance.doctorId,
      colleague: member,
      files: files,
      wifiOnly: true,
    );
    final what = files.length == 1
        ? '“${files.first.name}”'
        : '${files.length} files';
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          onWifi
              ? 'Sent $what to $name on clinic Wi-Fi'
              : '$what will reach $name when they’re on clinic Wi-Fi',
        ),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => undoSend(offers),
        ),
      ),
    );
  } catch (e) {
    say("Couldn't send to $name: $e");
  }
}

/// Drop targets for the colleagues you sent to most recently, right-aligned
/// under the patient filter: drag a file onto one to send it on clinic
/// Wi-Fi. The rest are behind More.
class ColleagueStrip extends ConsumerWidget {
  const ColleagueStrip({super.key});

  static const _shown = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final colleagues = ref.watch(stripColleaguesProvider);
    if (colleagues.isEmpty) {
      // A refused or failed member list is not "no colleagues".
      final members = ref.watch(clinicMembersProvider);
      if (!members.hasError) return const SizedBox.shrink();
      return Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: CruSpace.s8),
          child: Text(
            "Couldn't load your colleagues: ${members.error}",
            style: CruType.caption.tint(c.label2),
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerRight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        // A lifted avatar grows past the row; don't cut it off.
        clipBehavior: Clip.none,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final m in colleagues.take(_shown)) ...[
              const SizedBox(width: CruSpace.s8),
              ColleagueDropChip(member: m),
            ],
            if (colleagues.length > _shown) ...[
              const SizedBox(width: CruSpace.s8),
              _MoreChip(rest: colleagues.skip(_shown).toList()),
            ],
          ],
        ),
      ),
    );
  }
}

class ColleagueDropChip extends ConsumerStatefulWidget {
  const ColleagueDropChip({super.key, required this.member});

  final ClinicMember member;

  @override
  ConsumerState<ColleagueDropChip> createState() => _ColleagueDropChipState();
}

class _ColleagueDropChipState extends ConsumerState<ColleagueDropChip> {
  static const _holdToLift = Duration(seconds: 1);
  static const _swipeToCompose = 32.0;

  /// A shorter swipe counts when it carries the pointer off the avatar
  /// (the avatar is narrow, so a swipe often does).
  static const _swipeOffAvatar = 16.0;

  Timer? _holdTimer;
  bool _hovering = false;
  bool _lifted = false;
  bool _sending = false;

  /// Set once the compose popup opened for this drag: the drop that ends
  /// the drag must not also send.
  bool _composeOpened = false;

  /// Why the file being dragged can't go to this colleague.
  String? _blocked;

  /// Left edge of the dragged file, now and when the avatar lifted.
  double _lastX = 0;
  double _liftX = 0;

  /// Avatars on screen, for [colleagueAt].
  static final Set<_ColleagueDropChipState> _live = {};

  /// Bumped when this colleague comes onto the Wi-Fi with files waiting:
  /// the amber ring pulses once.
  int _pulse = 0;

  final _avatarKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _live.add(this);
    explorerHoverUid.addListener(_onExplorerHover);
  }

  void _onExplorerHover() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _live.remove(this);
    explorerHoverUid.removeListener(_onExplorerHover);
    _holdTimer?.cancel();
    super.dispose();
  }

  void _reset() {
    _holdTimer?.cancel();
    _holdTimer = null;
    if (!mounted) return;
    setState(() {
      _hovering = false;
      _lifted = false;
      _blocked = null;
    });
  }

  bool _onWillAccept(DragTargetDetails<FileEntry> d) {
    final patients = ref.read(patientsStreamProvider).value ?? const [];
    final patient = patients
        .where((p) => p.id == d.data.file.patientId)
        .firstOrNull;
    final reason = colleagueBlockReason(widget.member, patient: patient);
    if (reason != null) {
      setState(() => _blocked = reason);
      return false;
    }
    _composeOpened = false;
    _lastX = d.offset.dx;
    setState(() => _hovering = true);
    _holdTimer?.cancel();
    _holdTimer = Timer(_holdToLift, () {
      if (!mounted || !_hovering) return;
      setState(() {
        _lifted = true;
        _liftX = _lastX;
      });
    });
    return true;
  }

  void _onMove(DragTargetDetails<FileEntry> d) {
    _lastX = d.offset.dx;
    if (_lifted && !_composeOpened && _lastX - _liftX >= _swipeToCompose) {
      _openCompose(d.data.file);
    }
  }

  void _onLeave(FileEntry? data) {
    if (data != null &&
        _lifted &&
        !_composeOpened &&
        _lastX - _liftX >= _swipeOffAvatar) {
      _openCompose(data.file);
      return;
    }
    _reset();
  }

  void _openCompose(PatientFile file) {
    _composeOpened = true;
    _reset();
    // Next frame: the drag is still running while the popup opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showComposeTransferDialog(context, to: widget.member, files: [file]);
    });
  }

  Future<void> _onAccept(DragTargetDetails<FileEntry> d) async {
    final opened = _composeOpened;
    _reset();
    if (opened) return;
    _flyFrom(d.offset);
    await _sendNow([d.data.file]);
  }

  /// A small file shrinks from [from] (global) into the avatar.
  void _flyFrom(Offset from) {
    final box = _avatarKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    final overlay = Overlay.of(context);
    final to = box.localToGlobal(box.size.center(Offset.zero));
    final c = context.cru;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        onEnd: () => entry.remove(),
        builder: (_, t, _) {
          final at = Offset.lerp(from, to, t)!;
          const size = 36.0;
          return Positioned(
            left: at.dx - size / 2,
            top: at.dy - size / 2,
            child: IgnorePointer(
              child: Opacity(
                opacity: 1 - t * 0.6,
                child: Transform.scale(
                  scale: 1 - t * 0.7,
                  child: Container(
                    width: size,
                    height: size,
                    alignment: Alignment.center,
                    decoration: ShapeDecoration(
                      color: c.surface,
                      shadows: c.paneShadow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(CruRadius.iconTile),
                        side: BorderSide(color: c.cardBorder),
                      ),
                    ),
                    child: CruIcon(FileIcons.upload, size: 18, color: c.label2),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    overlay.insert(entry);
  }

  /// The files still waiting for this colleague, with Cancel.
  void _showWaiting(List<FileOffer> waiting) {
    showDialog<void>(
      context: context,
      builder: (_) => _WaitingDialog(member: widget.member, waiting: waiting),
    );
  }

  Future<void> _sendNow(List<PatientFile> files) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _sending = true);
    try {
      await sendToColleagueWithUndo(messenger, widget.member, files);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final m = widget.member;
    final motion = CruMotion.of(context, CruMotion.fast);
    final offWifi = offWifiReason(
      ref.watch(colleaguesOnWifiProvider.select((on) => on[m.uid])),
    );
    // A file from Explorer hovering here looks the same as one from Files.
    final explorerOver = explorerHoverUid.value == m.uid;
    final hovering = _hovering || explorerOver;
    final delivery = ref.watch(
      colleagueDeliveryProvider.select((d) => d[m.uid]),
    );
    final ring = delivery?.ring;
    final waiting = delivery?.waiting ?? const <FileOffer>[];
    final progress = delivery?.progress;
    // Coming onto the Wi-Fi with files waiting: one pulse, then they go.
    ref.listen(colleaguesOnWifiProvider.select((on) => on[m.uid]), (
      prev,
      next,
    ) {
      if (prev != true && next == true && waiting.isNotEmpty) {
        setState(() => _pulse++);
      }
    });
    final caption =
        _blocked ??
        (_lifted
            ? 'Swipe right for a note'
            : hovering
            ? (offWifi == null ? 'Drop to send' : 'Sends on Wi-Fi')
            : colleagueShortName(m.name));
    final ringColor = switch (ring) {
      DeliveryRing.waiting => c.amber,
      DeliveryRing.received => c.green,
      DeliveryRing.declined => c.label3,
      null => null,
    };
    final status = switch (ring) {
      DeliveryRing.waiting when progress != null =>
        'receiving, ${(progress * 100).round()} %',
      DeliveryRing.waiting =>
        '${waiting.length == 1 ? '1 file' : '${waiting.length} files'} '
            'waiting for clinic Wi-Fi. Click to see',
      DeliveryRing.received => 'received',
      DeliveryRing.declined => 'declined your last file',
      null => offWifi?.toLowerCase(),
    };
    return DragTarget<FileEntry>(
      onWillAcceptWithDetails: _onWillAccept,
      onMove: _onMove,
      onLeave: _onLeave,
      onAcceptWithDetails: _onAccept,
      builder: (context, _, _) => Tooltip(
        message: status == null ? m.name : '${m.name}: $status',
        child: AnimatedOpacity(
          opacity: _blocked != null ? 0.4 : 1,
          duration: motion,
          curve: CruMotion.curve,
          child: AnimatedSlide(
            offset: Offset(0, _lifted ? -0.12 : 0),
            duration: motion,
            curve: CruMotion.curve,
            child: AnimatedScale(
              scale: _lifted ? 1.08 : (hovering ? 1.03 : 1),
              duration: motion,
              curve: CruMotion.curve,
              child: _ColleaguePill(
                hovering: hovering,
                lifted: _lifted,
                leading: _sending
                    ? SizedBox.square(
                        dimension: _ColleaguePill.avatar,
                        child: Padding(
                          padding: const EdgeInsets.all(CruSpace.s6),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: c.label2,
                          ),
                        ),
                      )
                    : _WaitingBadge(
                        count: waiting.length,
                        child: GestureDetector(
                          onTap: waiting.isEmpty
                              ? null
                              : () => _showWaiting(waiting),
                          child: _RingFill(
                            key: _avatarKey,
                            color: ringColor,
                            fraction: ring == DeliveryRing.waiting
                                ? (progress ?? 1)
                                : 1,
                            pulse: _pulse,
                            child: ColleagueMonogram(
                              name: m.name,
                              size: _ColleaguePill.avatar - 4,
                            ),
                          ),
                        ),
                      ),
                label: caption,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A capsule the height of the filter chips: avatar, then a caption that
/// says what a drop will do.
class _ColleaguePill extends StatelessWidget {
  const _ColleaguePill({
    required this.leading,
    required this.label,
    this.hovering = false,
    this.lifted = false,
    this.trailing,
  });

  static const double avatar = 28;

  final Widget leading;
  final String label;
  final bool hovering;
  final bool lifted;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final motion = CruMotion.of(context, CruMotion.fast);
    return AnimatedContainer(
      duration: motion,
      curve: CruMotion.curve,
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s4,
        CruSpace.s4,
        CruSpace.s12,
        CruSpace.s4,
      ),
      decoration: ShapeDecoration(
        color: hovering ? c.accentTint : c.inset,
        shape: StadiumBorder(
          side: BorderSide(
            color: hovering ? c.accent : c.accent.withValues(alpha: 0),
          ),
        ),
        shadows: [
          BoxShadow(
            color: c.label.withValues(alpha: lifted ? 0.18 : 0),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: CruSpace.s8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CruType.callout.tint(hovering ? c.accentText : c.label),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: CruSpace.s4),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// The colleagues past the first three. Holding a dragged file on it for a
/// second (or clicking it) opens them in a list below, each a drop target;
/// the list closes once the drag leaves both.
class _MoreChip extends StatefulWidget {
  const _MoreChip({required this.rest});

  final List<ClinicMember> rest;

  @override
  State<_MoreChip> createState() => _MoreChipState();
}

class _MoreChipState extends State<_MoreChip> {
  static const _holdToOpen = Duration(seconds: 1);
  static const _graceToClose = Duration(milliseconds: 400);

  /// The More chip on screen, for Explorer drags.
  static _MoreChipState? _live;

  final _link = LayerLink();
  final _menuKey = GlobalKey();
  OverlayEntry? _menu;
  Timer? _openTimer;
  Timer? _closeTimer;
  bool _hovering = false;

  bool get _open => _menu != null;

  @override
  void initState() {
    super.initState();
    _live = this;
  }

  @override
  void didUpdateWidget(_MoreChip old) {
    super.didUpdateWidget(old);
    _menu?.markNeedsBuild();
  }

  @override
  void dispose() {
    if (_live == this) _live = null;
    _openTimer?.cancel();
    _closeTimer?.cancel();
    _menu?.remove();
    _menu = null;
    super.dispose();
  }

  void _show() {
    _openTimer?.cancel();
    _closeTimer?.cancel();
    if (_open || !mounted) return;
    _menu = OverlayEntry(builder: _buildMenu);
    Overlay.of(context).insert(_menu!);
    setState(() {});
  }

  void _hide() {
    _openTimer?.cancel();
    _closeTimer?.cancel();
    _menu?.remove();
    _menu = null;
    if (mounted) setState(() => _hovering = false);
  }

  void _closeSoon() {
    _openTimer?.cancel();
    _closeTimer?.cancel();
    if (!_open) {
      if (mounted && _hovering) setState(() => _hovering = false);
      return;
    }
    _closeTimer = Timer(_graceToClose, _hide);
  }

  void _holdStarted() {
    _closeTimer?.cancel();
    if (!_hovering) setState(() => _hovering = true);
    if (_open || (_openTimer?.isActive ?? false)) return;
    _openTimer = Timer(_holdToOpen, _show);
  }

  /// An Explorer drag (it sends no Flutter drag events) is at [p].
  void _explorerAt(Offset p) {
    final menu = _menuKey.currentContext;
    if (_contains(context, p)) {
      _holdStarted();
    } else if (menu != null && _contains(menu, p)) {
      _closeTimer?.cancel();
    } else if (_hovering || _open) {
      _closeSoon();
    }
  }

  Widget _buildMenu(BuildContext overlayContext) {
    final c = context.cru;
    return Positioned(
      width: 240,
      child: CompositedTransformFollower(
        link: _link,
        targetAnchor: Alignment.bottomRight,
        followerAnchor: Alignment.topRight,
        offset: const Offset(0, CruSpace.s8),
        child: TapRegion(
          groupId: _link,
          onTapOutside: (_) => _hide(),
          // Keeps the list open while a drag is over it, also between
          // avatars; never takes the drop itself.
          child: DragTarget<FileEntry>(
            onWillAcceptWithDetails: (_) {
              _closeTimer?.cancel();
              return false;
            },
            onLeave: (_) => _closeSoon(),
            builder: (_, _, _) => Material(
              key: _menuKey,
              type: MaterialType.transparency,
              child: Container(
                padding: const EdgeInsets.all(CruSpace.s8),
                decoration: ShapeDecoration(
                  color: c.surface,
                  shadows: c.paneShadow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      _ColleaguePill.avatar / 2 + CruSpace.s12,
                    ),
                    side: BorderSide(color: c.cardBorder),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final m in widget.rest) ...[
                      if (m != widget.rest.first)
                        const SizedBox(height: CruSpace.s4),
                      ColleagueDropChip(member: m),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final hovering = _hovering || _open;
    return CompositedTransformTarget(
      link: _link,
      child: TapRegion(
        groupId: _link,
        child: DragTarget<FileEntry>(
          // Opens the list; a drop on More itself does nothing.
          onWillAcceptWithDetails: (_) {
            _holdStarted();
            return false;
          },
          onLeave: (_) => _closeSoon(),
          builder: (_, _, _) => Tooltip(
            message:
                '${widget.rest.length} more: hold a file here for a second',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => _open ? _hide() : _show(),
                child: _ColleaguePill(
                  hovering: hovering,
                  leading: Container(
                    width: _ColleaguePill.avatar,
                    height: _ColleaguePill.avatar,
                    alignment: Alignment.center,
                    decoration: ShapeDecoration(
                      color: c.surface,
                      shape: CircleBorder(side: BorderSide(color: c.hairline)),
                    ),
                    child: Text(
                      '+${widget.rest.length}',
                      style: CruType.caption.w600.tabular.tint(c.label2),
                    ),
                  ),
                  label: 'More',
                  trailing: CruIcon(
                    CruIcons.chevronDown,
                    size: 16,
                    color: hovering ? c.accentText : c.label3,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 2 px delivery ring around [child]. It fills clockwise from twelve
/// o'clock when its [color] changes (amber sweeps in on a send, green over
/// amber once received), follows [fraction] while a file downloads (over a
/// faint track), pulses once when [pulse] changes, and fades out when it
/// goes away.
class _RingFill extends StatefulWidget {
  const _RingFill({
    super.key,
    required this.color,
    required this.child,
    this.fraction = 1,
    this.pulse = 0,
  });

  final Color? color;
  final double fraction;
  final int pulse;
  final Widget child;

  @override
  State<_RingFill> createState() => _RingFillState();
}

class _RingFillState extends State<_RingFill> with TickerProviderStateMixin {
  static const _fill = Duration(milliseconds: 600);

  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: _fill,
    value: 1,
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );
  Color? _from;
  Color? _to;

  @override
  void initState() {
    super.initState();
    _to = widget.color;
  }

  @override
  void didUpdateWidget(_RingFill old) {
    super.didUpdateWidget(old);
    if (widget.pulse != old.pulse) _pulse.forward(from: 0);
    if (widget.color == old.color) return;
    // What showed most (a finished or mostly drawn ring) becomes the base.
    _from = _sweep.value > 0.5 ? _to : _from;
    _to = widget.color;
    _sweep.forward(from: 0);
  }

  @override
  void dispose() {
    _sweep.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: widget.fraction.clamp(0, 1).toDouble()),
      duration: CruMotion.of(context, CruMotion.fast),
      curve: CruMotion.curve,
      builder: (_, fraction, child) => AnimatedBuilder(
        animation: Listenable.merge([_sweep, _pulse]),
        builder: (_, child) {
          // Up and back down: 1 → 1.15 → 1.
          final p = _pulse.isAnimating ? math.sin(_pulse.value * math.pi) : 0;
          return Transform.scale(
            scale: 1 + 0.15 * p,
            child: CustomPaint(
              foregroundPainter: _RingPainter(
                from: _from,
                to: _to,
                t: CruMotion.curve.transform(_sweep.value),
                fraction: fraction,
              ),
              child: child,
            ),
          );
        },
        child: child,
      ),
      child: Padding(padding: const EdgeInsets.all(2), child: widget.child),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.from,
    required this.to,
    required this.t,
    required this.fraction,
  });

  final Color? from;
  final Color? to;
  final double t;
  final double fraction;

  static const _width = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(_width / 2);
    Paint stroke(Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _width
      ..strokeCap = StrokeCap.round
      ..color = c;
    const full = math.pi * 2;
    const top = -math.pi / 2;
    if (to == null) {
      // Ring removed: the old one fades.
      if (from != null && t < 1) {
        canvas.drawArc(
          rect,
          0,
          full,
          false,
          stroke(from!.withValues(alpha: 1 - t)),
        );
      }
      return;
    }
    if (fraction < 1) {
      // Downloading: a faint track, filled as far as it has got.
      canvas.drawArc(rect, 0, full, false, stroke(to!.withValues(alpha: 0.25)));
    } else if (from != null && t < 1) {
      canvas.drawArc(rect, 0, full, false, stroke(from!));
    }
    final sweep = full * t * fraction;
    if (sweep <= 0) return;
    canvas.drawArc(rect, top, sweep, false, stroke(to!));
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.t != t ||
      old.from != from ||
      old.to != to ||
      old.fraction != fraction;
}

/// A small amber count on the avatar's corner when more than one file
/// waits for that colleague.
class _WaitingBadge extends StatelessWidget {
  const _WaitingBadge({required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (count < 2) return child;
    final c = context.cru;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -CruSpace.s4,
          right: -CruSpace.s4,
          child: Container(
            constraints: const BoxConstraints(minWidth: 16),
            height: 16,
            padding: const EdgeInsets.symmetric(horizontal: CruSpace.s4),
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: c.amberTint,
              shape: StadiumBorder(side: BorderSide(color: c.surface)),
            ),
            child: Text(
              count > 9 ? '9+' : '$count',
              style: CruType.micro.w600.tabular.tint(c.amberText),
            ),
          ),
        ),
      ],
    );
  }
}

/// The files still waiting for a colleague: what each is doing, and Cancel.
class _WaitingDialog extends ConsumerWidget {
  const _WaitingDialog({required this.member, required this.waiting});

  final ClinicMember member;
  final List<FileOffer> waiting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    // Live: rows leave as files arrive or are cancelled.
    final live = ref.watch(
      colleagueDeliveryProvider.select((d) => d[member.uid]),
    );
    final progress = ref.watch(_wifiServerProvider).progress;
    final files = live?.waiting ?? const <FileOffer>[];
    return Dialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CruRadius.card),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(CruSpace.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Waiting for ${colleagueShortName(member.name)}',
                style: CruType.headline.tint(c.label),
              ),
              const SizedBox(height: CruSpace.s4),
              Text(
                files.isEmpty
                    ? 'Everything has arrived.'
                    : 'These arrive when you’re both on clinic Wi-Fi.',
                style: CruType.callout.tint(c.label2),
              ),
              const SizedBox(height: CruSpace.s16),
              for (final o in files)
                Padding(
                  padding: const EdgeInsets.only(bottom: CruSpace.s8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              o.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: CruType.body.tint(c.label),
                            ),
                            Text(
                              switch (progress[o.id]) {
                                final p? when p < 1 =>
                                  'Receiving, ${(p * 100).round()} %',
                                _ => 'Waiting for Wi-Fi',
                              },
                              style: CruType.caption.tabular.tint(c.amberText),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: CruSpace.s12),
                      CruButton(
                        label: 'Cancel',
                        kind: CruButtonKind.secondary,
                        onPressed: () => undoSend([o]),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: CruSpace.s8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (files.length > 1) ...[
                    CruButton(
                      label: 'Cancel all',
                      kind: CruButtonKind.secondary,
                      onPressed: () => undoSend(files),
                    ),
                    const SizedBox(width: CruSpace.s8),
                  ],
                  CruButton(
                    label: 'Done',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
