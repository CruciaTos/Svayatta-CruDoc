import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/patients/data/providers/patients_list_providers.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_details_view.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/list/patient_preview_pane.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/list/patients_compact_list.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/list/patients_filter_chips.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/list/patients_first_week_panel.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/list/patients_header.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/list/patients_search_bar.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/list/patients_skeleton.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/list/patients_summary_strip.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/list/patients_table.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';

/// The Patients tab: the list (table or split mode), or Patient details
/// in its place. List state lives in [patientsListControllerProvider], so
/// coming back from details restores filter, sort, search, selection,
/// pane and scroll position.
class PatientsScreen extends ConsumerStatefulWidget {
  const PatientsScreen({super.key});

  @override
  ConsumerState<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends ConsumerState<PatientsScreen> {
  @override
  Widget build(BuildContext context) {
    final detailsId = ref.watch(
      patientsListControllerProvider.select((s) => s.detailsId),
    );
    return ColoredBox(
      color: context.cru.canvas,
      child: detailsId != null
          ? PatientDetailsView(
              key: ValueKey(detailsId),
              patientId: detailsId,
              onBack: () {
                // Opened from another screen: go back there.
                final back = ref.read(patientDetailsReturnTabProvider);
                ref.read(patientsListControllerProvider.notifier).closeDetails();
                if (back != null) {
                  ref.read(patientDetailsReturnTabProvider.notifier).state = null;
                  ref.read(shellNavigatorProvider)?.call(back);
                }
              },
            )
          : const _PatientsList(),
    );
  }
}

class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}

class _MoveSelectionIntent extends Intent {
  const _MoveSelectionIntent(this.delta);
  final int delta;
}

class _OpenSelectedIntent extends Intent {
  const _OpenSelectedIntent();
}

class _ClosePaneIntent extends Intent {
  const _ClosePaneIntent();
}

/// An action that lets its key pass through when disabled (so the search
/// field keeps Enter and the arrow keys).
class _PatientsAction<T extends Intent> extends Action<T> {
  _PatientsAction(this.enabled, this.run);

  final bool Function() enabled;
  final void Function(T intent) run;

  @override
  bool isEnabled(T intent) => enabled();

  @override
  Object? invoke(T intent) {
    run(intent);
    return null;
  }
}

class _PatientsList extends ConsumerStatefulWidget {
  const _PatientsList();

  @override
  ConsumerState<_PatientsList> createState() => _PatientsListState();
}

class _PatientsListState extends ConsumerState<_PatientsList> {
  late final ScrollController _scroll;
  final FocusNode _keysFocus = FocusNode(
    debugLabel: 'patients list',
    skipTraversal: true,
  );
  final FocusNode _searchFocus = FocusNode(debugLabel: 'patients search');
  final GlobalKey _selectedRowKey = GlobalKey(debugLabel: 'selected patient');

  String? _lastTapId;
  DateTime? _lastTapAt;
  bool _moreScheduled = false;

  PatientsListController get _controller =>
      ref.read(patientsListControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController(
      initialScrollOffset: ref.read(patientsListControllerProvider).scrollOffset,
    )..addListener(_onScroll);
    // The shell holds focus by default; take it so our shortcuts see keys.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_keysFocus.hasFocus) _keysFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _keysFocus.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ---- Behaviour ---------------------------------------------------------

  /// Reveals the next page when the list nears its end.
  void _onScroll() {
    if (_moreScheduled || !_scroll.hasClients) return;
    if (_scroll.position.extentAfter > 400) return;
    final view = ref.read(patientsListViewProvider).value;
    if (view == null || view.visible.length >= view.rows.length) return;
    _moreScheduled = true;
    _controller.showMore();
    // Wait for the longer list to be laid out before asking again.
    WidgetsBinding.instance.addPostFrameCallback((_) => _moreScheduled = false);
  }

  void _openDetails(String id) {
    _controller.saveScroll(_scroll.hasClients ? _scroll.offset : 0);
    _controller.openDetails(id);
  }

  void _closePane() {
    _controller.closePane();
    _keysFocus.requestFocus();
  }

  /// Click selects (split mode); a second click on the same row within
  /// the double-tap window opens details. Below [CruBreakpoint.phone] a
  /// tap opens details directly.
  void _onRowTap(PatientSummary s) {
    final now = DateTime.now();
    final isDouble = _lastTapId == s.id &&
        _lastTapAt != null &&
        now.difference(_lastTapAt!) < kDoubleTapTimeout;
    _lastTapId = s.id;
    _lastTapAt = now;
    if (isDouble || MediaQuery.sizeOf(context).width < CruBreakpoint.phone) {
      _openDetails(s.id);
      return;
    }
    _controller.select(s.id);
    _keysFocus.requestFocus();
    // Compact rows are shorter than table rows: keep the row on screen.
    _revealSelected();
  }

  void _moveSelection(int delta) {
    final view = ref.read(patientsListViewProvider).value;
    final selected = view?.selected;
    if (view == null || selected == null) return;
    final i = view.rows.indexWhere((r) => r.id == selected.id);
    final j = math.min(math.max(i + delta, 0), view.rows.length - 1);
    if (i < 0 || j == i) return;
    if (j >= view.visible.length) _controller.showMore();
    _controller.select(view.rows[j].id);
    _revealSelected();
  }

  /// Scrolls the page just enough to show the selected row.
  void _revealSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final rowContext = _selectedRowKey.currentContext;
      if (rowContext == null) return;
      final row = rowContext.findRenderObject();
      final scrollable = Scrollable.maybeOf(rowContext);
      final viewport = scrollable?.context.findRenderObject();
      if (row is! RenderBox || viewport is! RenderBox) return;
      if (!row.attached || !viewport.attached) return;
      final top = row.localToGlobal(Offset.zero, ancestor: viewport).dy;
      final bottom = top + row.size.height;
      final height = viewport.size.height;
      const margin = CruSpace.s12;
      var delta = 0.0;
      if (top < margin) {
        delta = top - margin;
      } else if (bottom > height - margin) {
        delta = bottom - (height - margin);
      }
      if (delta == 0) return;
      final pos = _scroll.position;
      final target = clampDouble(
        pos.pixels + delta,
        pos.minScrollExtent,
        pos.maxScrollExtent,
      );
      final d = CruMotion.of(context, CruMotion.fast);
      if (d == Duration.zero) {
        _scroll.jumpTo(target);
      } else {
        _scroll.animateTo(target, duration: d, curve: CruMotion.curve);
      }
    });
  }

  bool get _searchFocused => _searchFocus.hasPrimaryFocus;

  bool _paneVisible() {
    final view = ref.read(patientsListViewProvider).value;
    return view?.selected != null &&
        MediaQuery.sizeOf(context).width >= CruBreakpoint.phone;
  }

  Map<ShortcutActivator, Intent> get _shortcuts => {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            const _FocusSearchIntent(),
        if (defaultTargetPlatform == TargetPlatform.macOS)
          const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
              const _FocusSearchIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowDown):
            const _MoveSelectionIntent(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp):
            const _MoveSelectionIntent(-1),
        const SingleActivator(LogicalKeyboardKey.enter):
            const _OpenSelectedIntent(),
        const SingleActivator(LogicalKeyboardKey.numpadEnter):
            const _OpenSelectedIntent(),
        const SingleActivator(LogicalKeyboardKey.escape):
            const _ClosePaneIntent(),
      };

  Map<Type, Action<Intent>> get _actions => {
        _FocusSearchIntent: _PatientsAction<_FocusSearchIntent>(
          () => _searchFocus.context != null,
          (_) => _searchFocus.requestFocus(),
        ),
        _MoveSelectionIntent: _PatientsAction<_MoveSelectionIntent>(
          () => !_searchFocused && _paneVisible(),
          (intent) => _moveSelection(intent.delta),
        ),
        _OpenSelectedIntent: _PatientsAction<_OpenSelectedIntent>(
          () => !_searchFocused && _paneVisible(),
          (_) {
            final id = ref.read(patientsListViewProvider).value?.selected?.id;
            if (id != null) _openDetails(id);
          },
        ),
        _ClosePaneIntent: _PatientsAction<_ClosePaneIntent>(
          _paneVisible,
          (_) => _closePane(),
        ),
      };

  // ---- Layout ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(patientsListControllerProvider);
    final async = ref.watch(patientsListViewProvider);
    final now = ref.watch(dashboardNowProvider);
    final view = async.value;
    final width = MediaQuery.sizeOf(context).width;
    final padding = width < CruBreakpoint.compact
        ? CruSpace.mainPaddingCompact
        : CruSpace.mainPadding;

    // The filter actually applied: a stale or hidden chip falls back to
    // All (as patientsListViewProvider does).
    var filter = state.filter;
    if (view != null &&
        (view.firstWeek ||
            (filter != PatientFilter.all && (view.counts[filter] ?? 0) == 0))) {
      filter = PatientFilter.all;
    }
    final sort = filter == state.filter ? state.sort : PatientSort.lastVisit;

    final selected = width >= CruBreakpoint.phone ? view?.selected : null;
    final split = selected != null && width >= CruBreakpoint.splitPane;
    final sheet = selected != null && !split;
    final empty = view != null && view.total == 0;

    final top = <Widget>[
      PatientsHeader(
        total: view?.total,
        newThisMonth: view?.newThisMonth ?? 0,
      ),
      if (!empty) ...[
        const SizedBox(height: CruSpace.s20),
        PatientsSearchBar(
          focusNode: _searchFocus,
          sort: sort,
          showSort: view != null && !view.firstWeek,
        ),
      ],
      if (view != null && !view.firstWeek) ...[
        const SizedBox(height: CruSpace.s20),
        PatientsFilterChips(counts: view.counts, active: filter),
      ],
      if (view?.balanceStrip != null) ...[
        const SizedBox(height: CruSpace.s20),
        PatientsSummaryStrip.balance(
          key: const ValueKey('balance strip'),
          balance: view!.balanceStrip!,
          rows: view.rows,
        ),
      ] else if (view?.followUpStrip != null) ...[
        const SizedBox(height: CruSpace.s20),
        PatientsSummaryStrip.followUp(
          key: const ValueKey('follow-up strip'),
          followUp: view!.followUpStrip!,
          rows: view.rows,
        ),
      ],
    ];

    return Shortcuts(
      shortcuts: _shortcuts,
      child: Actions(
        actions: _actions,
        child: Focus(
          focusNode: _keysFocus,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scrollView = CustomScrollView(
                controller: _scroll,
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        padding.left,
                        padding.top,
                        padding.right,
                        0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: top,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    // In split mode both columns add s12 themselves, so the
                    // pinned pane keeps a margin at the top of the window.
                    child: SizedBox(
                      height: split ? CruSpace.s20 - CruSpace.s12 : CruSpace.s20,
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.only(
                      left: padding.left,
                      right: padding.right,
                    ),
                    sliver: _listSliver(
                      context,
                      async: async,
                      view: view,
                      filter: filter,
                      now: now,
                      width: width,
                      split: split,
                      sheet: sheet,
                      query: state.query,
                      paneMaxHeight: math.max(
                        0,
                        constraints.maxHeight - 2 * CruSpace.s12,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(child: SizedBox(height: padding.bottom)),
                ],
              );
              if (!sheet) return scrollView;
              return Stack(
                children: [
                  scrollView,
                  Positioned.fill(child: _Backdrop(onTap: _closePane)),
                  Positioned(
                    top: CruSpace.s12,
                    bottom: CruSpace.s12,
                    right: padding.right,
                    width: math.min(
                      CruSize.previewPane,
                      constraints.maxWidth - 2 * CruSpace.s16,
                    ),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: _pane(selected, now),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _pane(PatientSummary summary, DateTime now) => PatientPreviewPane(
        summary: summary,
        now: now,
        onOpen: () => _openDetails(summary.id),
        onClose: _closePane,
      );

  Widget _listSliver(
    BuildContext context, {
    required AsyncValue<PatientsListView> async,
    required PatientsListView? view,
    required PatientFilter filter,
    required DateTime now,
    required double width,
    required bool split,
    required bool sheet,
    required String query,
    required double paneMaxHeight,
  }) {
    if (view == null) {
      if (async.hasError) {
        return const SliverToBoxAdapter(child: _LoadError());
      }
      return const SliverToBoxAdapter(child: PatientsSkeleton());
    }

    if (view.total == 0) {
      return const SliverToBoxAdapter(
        child: CruCard(
          semanticLabel: 'Patient list',
          padding: EdgeInsets.all(CruSpace.s12),
          child: PatientsFirstWeekPanel(),
        ),
      );
    }

    if (split) {
      return SliverCrossAxisGroup(
        slivers: [
          SliverCrossAxisExpanded(
            flex: 1,
            sliver: SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: CruSpace.s12),
                child: PatientsCompactList(
                  view: view,
                  filter: filter,
                  now: now,
                  onTap: _onRowTap,
                  selectedRowKey: _selectedRowKey,
                ),
              ),
            ),
          ),
          SliverConstrainedCrossAxis(
            maxExtent: CruSize.previewPane + CruSpace.cardGap,
            // Pinned: the pane stays in view while the list scrolls, and
            // leaves with it at the end.
            sliver: PinnedHeaderSliver(
              child: Padding(
                padding: const EdgeInsets.only(
                  left: CruSpace.cardGap,
                  top: CruSpace.s12,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: paneMaxHeight),
                  child: _pane(view.selected!, now),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return SliverToBoxAdapter(
      child: PatientsTable(
        view: view,
        now: now,
        onTap: _onRowTap,
        selectedId: sheet ? view.selected?.id : null,
        selectedRowKey: _selectedRowKey,
        showFooter: !view.firstWeek,
        hint: width >= CruBreakpoint.phone ? 'Click a patient to preview' : null,
        trailing: view.firstWeek ? const PatientsFirstWeekPanel() : null,
        empty: _NoMatches(
          query: query,
          onClear: () => _controller.setQuery(''),
        ),
      ),
    );
  }
}

/// Dims the list behind the narrow-width preview sheet; tap to close.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Semantics(
      button: true,
      label: 'Close preview',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: CruMotion.of(context, CruMotion.pane),
          curve: CruMotion.curve,
          builder: (context, t, _) => ColoredBox(
            color: c.label.withValues(alpha: 0.24 * t),
          ),
        ),
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.query, required this.onClear});

  final String query;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final q = query.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s16,
        vertical: CruSpace.s24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            q.isEmpty ? 'No patients in this list.' : 'No patients match “$q”.',
            style: CruType.text.tint(c.label2),
          ),
          if (q.isNotEmpty) ...[
            const SizedBox(height: CruSpace.s8),
            CruLink(label: 'Clear search', onPressed: onClear),
          ],
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError();

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruCard(
      semanticLabel: 'Patient list',
      child: Text(
        "Couldn't load patients. Try again in a moment.",
        style: CruType.text.tint(c.label2),
      ),
    );
  }
}
