part of 'colleague_strip.dart';

/// Instagram's hold-to-share row, for the phone's clinic logo: a file
/// dragged onto the logo pops out a capsule of round colleague avatars
/// under it (the ones you sent to most recently first). Sliding onto one
/// grows it and shows their name and what a release will do; releasing
/// sends over clinic Wi-Fi with Undo, and holding for a second first opens
/// the note popup instead. "+N" pages through the rest while the file rests
/// on it. The row closes when the file leaves it or is released.
class ColleagueShareFan extends StatefulWidget {
  const ColleagueShareFan({
    super.key,
    required this.members,
    required this.builder,
  });

  final List<ClinicMember> members;

  /// The logo; `open` is true while the row is out.
  final Widget Function(BuildContext context, bool open) builder;

  @override
  State<ColleagueShareFan> createState() => _ColleagueShareFanState();
}

class _ColleagueShareFanState extends State<ColleagueShareFan> {
  static const _graceToClose = Duration(milliseconds: 350);

  /// After a send: the row stays while the file flies into the avatar.
  static const _stayAfterSend = Duration(milliseconds: 260);

  static const _perPage = 4;

  /// While the file rests on "+N": the next page every so often.
  static const _pageEvery = Duration(milliseconds: 700);

  final _link = LayerLink();
  var _capsuleKey = GlobalKey<_FanCapsuleState>();
  OverlayEntry? _fan;
  Timer? _closeTimer;
  Timer? _pager;
  int _page = 0;

  bool get _open => _fan != null;

  @override
  void initState() {
    super.initState();
    ShareDragStage.spotlight = this;
    ShareDragStage.active.addListener(_dragChanged);
  }

  @override
  void didUpdateWidget(ColleagueShareFan old) {
    super.didUpdateWidget(old);
    _fan?.markNeedsBuild();
  }

  @override
  void dispose() {
    if (ShareDragStage.spotlight == this) ShareDragStage.spotlight = null;
    ShareDragStage.active.removeListener(_dragChanged);
    _closeTimer?.cancel();
    _pager?.cancel();
    _fan?.remove();
    _fan = null;
    super.dispose();
  }

  /// The file was released: the row goes (after the flight, on a send).
  void _dragChanged() {
    if (ShareDragStage.active.value || !_open) return;
    _closeTimer?.cancel();
    _closeTimer = Timer(
      ShareDragStage.landed ? _stayAfterSend : Duration.zero,
      _hide,
    );
  }

  void _show() {
    _closeTimer?.cancel();
    if (_open || !mounted || widget.members.isEmpty) return;
    HapticFeedback.lightImpact();
    _page = 0;
    // A fresh key: the last row may still be shrinking away.
    _capsuleKey = GlobalKey<_FanCapsuleState>();
    final overlay = Overlay.of(context);
    _fan = OverlayEntry(builder: _buildFan);
    // Under the floating file, so the file stays on top.
    overlay.insert(
      _fan!,
      below: identical(overlay, ShareDragStage.overlay)
          ? ShareDragStage.ghostEntry
          : null,
    );
    ShareDragStage.setFocus(this, true);
    setState(() {});
  }

  Future<void> _hide() async {
    _closeTimer?.cancel();
    _pager?.cancel();
    final fan = _fan;
    if (fan == null) return;
    _fan = null;
    ShareDragStage.setFocus(this, false);
    if (mounted) setState(() {});
    await _capsuleKey.currentState?.close();
    if (fan.mounted) fan.remove();
  }

  void _keepOpen() => _closeTimer?.cancel();

  void _closeSoon() {
    _closeTimer?.cancel();
    if (_open) _closeTimer = Timer(_graceToClose, _hide);
  }

  int get _pages {
    final n = widget.members.length;
    return n <= _perPage + 1 ? 1 : (n / _perPage).ceil();
  }

  void _nextPage() {
    if (_pages < 2 || !_open) return;
    HapticFeedback.selectionClick();
    _page = (_page + 1) % _pages;
    _fan?.markNeedsBuild();
  }

  void _startPaging() {
    _keepOpen();
    _pager?.cancel();
    _pager = Timer.periodic(_pageEvery, (_) => _nextPage());
  }

  void _stopPaging() {
    _pager?.cancel();
    _closeSoon();
  }

  Widget _buildFan(BuildContext overlayContext) {
    final members = widget.members;
    final all = _pages == 1;
    final shown = all
        ? members
        : members.skip(_page * _perPage).take(_perPage).toList();
    return Positioned(
      child: CompositedTransformFollower(
        link: _link,
        targetAnchor: Alignment.bottomRight,
        followerAnchor: Alignment.topRight,
        child: Align(
          alignment: Alignment.topRight,
          child: DragTarget<FileEntry>(
            // Keeps the row open while the file is over it, also between
            // avatars; never takes the drop itself.
            onWillAcceptWithDetails: (_) {
              _keepOpen();
              return false;
            },
            onLeave: (_) => _closeSoon(),
            builder: (_, _, _) => _FanCapsule(
              key: _capsuleKey,
              page: _page,
              children: [
                for (final (i, m) in shown.indexed)
                  _FanAvatar(
                    key: ValueKey(m.uid),
                    member: m,
                    // The last two sit near the screen's edge: their label
                    // grows leftwards instead of centring.
                    tagGrowsLeft:
                        (all ? shown.length : shown.length + 1) - i <= 2,
                    host: context,
                    keepOpen: _keepOpen,
                    closeSoon: _closeSoon,
                  ),
                if (!all)
                  _FanMore(
                    others: members.length - shown.length,
                    onEnter: _startPaging,
                    onLeave: _stopPaging,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: DragTarget<FileEntry>(
        // Opens the row; a drop on the logo itself sends nothing.
        onWillAcceptWithDetails: (_) {
          _show();
          return false;
        },
        onLeave: (_) => _closeSoon(),
        builder: (context, _, _) => widget.builder(context, _open),
      ),
    );
  }
}

/// The capsule under the logo. It pops in from the logo's corner, the
/// avatars following one after another, and shrinks back on [close].
class _FanCapsule extends StatefulWidget {
  const _FanCapsule({super.key, required this.page, required this.children});

  final int page;
  final List<Widget> children;

  @override
  State<_FanCapsule> createState() => _FanCapsuleState();
}

class _FanCapsuleState extends State<_FanCapsule>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(vsync: this);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _in.duration = CruMotion.of(context);
    if (_in.status == AnimationStatus.dismissed) _in.forward();
  }

  Future<void> close() async {
    if (!mounted) return;
    _in.duration = CruMotion.of(context, CruMotion.fast);
    if (_in.duration == Duration.zero) return;
    await _in.reverse().orCancel.catchError((_) {});
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final motion = CruMotion.of(context, CruMotion.fast);
    final appear = CurvedAnimation(parent: _in, curve: CruMotion.curve);
    return FadeTransition(
      opacity: appear,
      child: ScaleTransition(
        scale: Tween(begin: 0.85, end: 1.0).animate(appear),
        alignment: Alignment.topRight,
        child: Padding(
          // The gap to the logo belongs to the row, so crossing it doesn't
          // count as leaving.
          padding: const EdgeInsets.only(top: CruSpace.s12),
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              padding: const EdgeInsets.all(CruSpace.s8),
              decoration: ShapeDecoration(
                color: c.surface,
                shadows: c.paneShadow,
                shape: StadiumBorder(side: BorderSide(color: c.cardBorder)),
              ),
              // Nothing clips: a hovered avatar grows and its label sits
              // above the capsule.
              child: AnimatedSize(
                duration: motion,
                curve: CruMotion.curve,
                alignment: Alignment.centerRight,
                clipBehavior: Clip.none,
                child: AnimatedSwitcher(
                  duration: motion,
                  layoutBuilder: (current, previous) => Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.centerRight,
                    children: [...previous, ?current],
                  ),
                  child: Row(
                    key: ValueKey(widget.page),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (i, child) in widget.children.indexed) ...[
                        if (i > 0) const SizedBox(width: CruSpace.s8),
                        _Stagger(animation: _in, index: i, child: child),
                      ],
                    ],
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

/// Avatar [index] slides in from the logo's side a beat after the one
/// before it.
class _Stagger extends StatelessWidget {
  const _Stagger({
    required this.animation,
    required this.index,
    required this.child,
  });

  final Animation<double> animation;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = (index * 0.08).clamp(0.0, 0.4);
    final a = CurvedAnimation(
      parent: animation,
      curve: Interval(start, start + 0.6, curve: CruMotion.curve),
    );
    return FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0.5, 0),
          end: Offset.zero,
        ).animate(a),
        child: child,
      ),
    );
  }
}

/// Avatar size in the row: a comfortable finger target.
const double _fanAvatar = CruSize.searchBar;

class _FanAvatar extends ConsumerStatefulWidget {
  const _FanAvatar({
    super.key,
    required this.member,
    required this.tagGrowsLeft,
    required this.host,
    required this.keepOpen,
    required this.closeSoon,
  });

  final ClinicMember member;
  final bool tagGrowsLeft;

  /// The logo's context: outlives the row, for the snack bar and the note
  /// popup.
  final BuildContext host;
  final VoidCallback keepOpen;
  final VoidCallback closeSoon;

  @override
  ConsumerState<_FanAvatar> createState() => _FanAvatarState();
}

class _FanAvatarState extends ConsumerState<_FanAvatar> {
  static const _holdForNote = Duration(seconds: 1);

  final _avatarKey = GlobalKey();
  Timer? _noteTimer;
  bool _hovering = false;
  bool _note = false;
  String? _blocked;

  @override
  void dispose() {
    _noteTimer?.cancel();
    super.dispose();
  }

  void _reset() {
    _noteTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _hovering = false;
      _note = false;
      _blocked = null;
    });
  }

  bool _onWillAccept(DragTargetDetails<FileEntry> d) {
    widget.keepOpen();
    final patients = ref.read(patientsStreamProvider).value ?? const [];
    final patient = patients
        .where((p) => p.id == d.data.file.patientId)
        .firstOrNull;
    final reason = colleagueBlockReason(widget.member, patient: patient);
    HapticFeedback.selectionClick();
    if (reason != null) {
      setState(() => _blocked = reason);
      return false;
    }
    setState(() => _hovering = true);
    _noteTimer?.cancel();
    _noteTimer = Timer(_holdForNote, () {
      if (!mounted || !_hovering) return;
      HapticFeedback.lightImpact();
      setState(() => _note = true);
    });
    return true;
  }

  void _onLeave(FileEntry? _) {
    _reset();
    widget.closeSoon();
  }

  void _onAccept(DragTargetDetails<FileEntry> d) {
    final note = _note;
    final file = d.data.file;
    final member = widget.member;
    final host = widget.host;
    _reset();
    if (note) {
      // Next frame: the drag is still finishing.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (host.mounted) {
          showComposeTransferDialog(host, to: member, files: [file]);
        }
      });
      return;
    }
    final box = _avatarKey.currentContext?.findRenderObject();
    if (box is RenderBox && box.attached) {
      ShareDragStage.landOn(box.localToGlobal(box.size.center(Offset.zero)));
    }
    HapticFeedback.mediumImpact();
    final messenger = host.mounted ? ScaffoldMessenger.maybeOf(host) : null;
    unawaited(sendToColleagueWithUndo(messenger, member, [file]));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final m = widget.member;
    final motion = CruMotion.of(context, CruMotion.fast);
    final delivery = ref.watch(
      colleagueDeliveryProvider.select((d) => d[m.uid]),
    );
    final ring = delivery?.ring;
    final ringColor = switch (ring) {
      DeliveryRing.waiting => c.amber,
      DeliveryRing.received => c.green,
      DeliveryRing.declined => c.label3,
      null => null,
    };
    final showTag = _hovering || _blocked != null;
    final status =
        _blocked ??
        (_note
            ? 'Release to add a note'
            : 'Release to send · hold for a note');
    return DragTarget<FileEntry>(
      onWillAcceptWithDetails: _onWillAccept,
      onLeave: _onLeave,
      onAcceptWithDetails: _onAccept,
      builder: (context, _, _) => SizedBox.square(
        dimension: _fanAvatar,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            AnimatedOpacity(
              opacity: _blocked != null ? 0.4 : 1,
              duration: motion,
              curve: CruMotion.curve,
              child: AnimatedSlide(
                offset: Offset(0, _hovering ? -0.18 : 0),
                duration: motion,
                curve: CruMotion.curve,
                child: AnimatedScale(
                  scale: _hovering ? (_note ? 1.4 : 1.28) : 1,
                  duration: motion,
                  curve: CruMotion.curve,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _RingFill(
                        key: _avatarKey,
                        color: ringColor,
                        fraction: ring == DeliveryRing.waiting
                            ? (delivery?.progress ?? 1)
                            : 1,
                        child: ColleagueMonogram(
                          name: m.name,
                          size: _fanAvatar - 4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Name and what a release does, above the avatar.
            Positioned(
              bottom: _fanAvatar + CruSpace.s20,
              left: widget.tagGrowsLeft ? null : -CruSpace.s32 * 3,
              right: widget.tagGrowsLeft ? -CruSpace.s8 : -CruSpace.s32 * 3,
              child: IgnorePointer(
                child: Align(
                  alignment: widget.tagGrowsLeft
                      ? Alignment.centerRight
                      : Alignment.center,
                  child: AnimatedSwitcher(
                    duration: motion,
                    child: showTag
                        ? _FanTag(
                            key: ValueKey('$status${m.uid}'),
                            title: m.name,
                            status: status,
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The dark label over a hovered avatar.
class _FanTag extends StatelessWidget {
  const _FanTag({super.key, required this.title, required this.status});

  final String title;
  final String status;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s12,
        vertical: CruSpace.s6,
      ),
      decoration: ShapeDecoration(
        color: c.label,
        shape: cruShape(CruRadius.control),
        shadows: c.paneShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: CruType.callout.w600.tint(c.surface),
          ),
          Text(
            status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: CruType.caption.tint(c.surface.withValues(alpha: 0.75)),
          ),
        ],
      ),
    );
  }
}

/// "+N": resting the file on it shows the next colleagues, and keeps doing
/// so while it stays.
class _FanMore extends StatefulWidget {
  const _FanMore({
    required this.others,
    required this.onEnter,
    required this.onLeave,
  });

  final int others;
  final VoidCallback onEnter;
  final VoidCallback onLeave;

  @override
  State<_FanMore> createState() => _FanMoreState();
}

class _FanMoreState extends State<_FanMore> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final motion = CruMotion.of(context, CruMotion.fast);
    return DragTarget<FileEntry>(
      onWillAcceptWithDetails: (_) {
        HapticFeedback.selectionClick();
        setState(() => _hovering = true);
        widget.onEnter();
        return false;
      },
      onLeave: (_) {
        if (mounted) setState(() => _hovering = false);
        widget.onLeave();
      },
      builder: (_, _, _) => AnimatedScale(
        scale: _hovering ? 1.12 : 1,
        duration: motion,
        curve: CruMotion.curve,
        child: Container(
          width: _fanAvatar,
          height: _fanAvatar,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: _hovering ? c.accentTint : c.inset,
            shape: CircleBorder(
              side: BorderSide(color: _hovering ? c.accent : c.hairline),
            ),
          ),
          child: Text(
            '+${widget.others}',
            style: CruType.callout.w600.tabular.tint(
              _hovering ? c.accentText : c.label2,
            ),
          ),
        ),
      ),
    );
  }
}
