import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/inventory/data/providers/inventory_view_providers.dart';
import 'package:doctor_management_app/features/inventory/domain/inventory_models.dart';
import 'package:doctor_management_app/features/inventory/presentation/desktop_inventory_list_screen.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_actions.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_filter_chips.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_grid.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_header.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_item_panel.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_list.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_run_out_strip.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_skeleton.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_toolbar.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The Inventory tab: header, Items / Orders / Vendors / Usage, and on
/// Items the list or grid with the 384 px item panel (a sheet below
/// 1200 px). Pads itself with [CruSpace.mainPadding]. State lives in
/// [inventoryControllerProvider].
class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}

/// Moves the selection by rows ([dy]) or, in the grid, by tiles ([dx]).
class _MoveIntent extends Intent {
  const _MoveIntent({this.dx = 0, this.dy = 0});
  final int dx;
  final int dy;
}

class _OpenIntent extends Intent {
  const _OpenIntent();
}

class _CloseIntent extends Intent {
  const _CloseIntent();
}

/// An action that lets its key pass through when disabled (so the search
/// field keeps Enter and the arrow keys).
class _InventoryAction<T extends Intent> extends Action<T> {
  _InventoryAction(this.enabled, this.run);

  final bool Function(T intent) enabled;
  final void Function(T intent) run;

  @override
  bool isEnabled(T intent) => enabled(intent);

  @override
  Object? invoke(T intent) {
    run(intent);
    return null;
  }
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  final ScrollController _scroll = ScrollController();
  final FocusNode _keysFocus = FocusNode(
    debugLabel: 'inventory',
    skipTraversal: true,
  );
  final FocusNode _searchFocus = FocusNode(debugLabel: 'inventory search');
  final GlobalKey _selectedKey = GlobalKey(debugLabel: 'selected item');

  /// Width of the list/grid column at the last layout (grid arrow keys).
  double _leftWidth = 0;

  String? _lastTapId;
  DateTime? _lastTapAt;
  bool _moreScheduled = false;

  InventoryController get _controller =>
      ref.read(inventoryControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
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
    final view = ref.read(inventoryViewProvider).value;
    if (view == null || view.visible.length >= view.rows.length) return;
    _moreScheduled = true;
    _controller.showMore();
    // Wait for the longer list to be laid out before asking again.
    WidgetsBinding.instance.addPostFrameCallback((_) => _moreScheduled = false);
  }

  bool get _wide => MediaQuery.sizeOf(context).width >= CruBreakpoint.splitPane;

  /// Click selects (opening the sheet below 1200 px); a second click on
  /// the same item within the double-tap window opens its details.
  void _onTap(InventoryItem item) {
    final now = DateTime.now();
    final isDouble = _lastTapId == item.id &&
        _lastTapAt != null &&
        now.difference(_lastTapAt!) < kDoubleTapTimeout;
    _lastTapId = item.id;
    _lastTapAt = now;
    if (isDouble) {
      InventoryActions.openDetails(context, item.medicine);
      return;
    }
    _controller.select(item.id);
    _keysFocus.requestFocus();
    _revealSelected();
  }

  void _move(_MoveIntent intent) {
    final view = ref.read(inventoryViewProvider).value;
    final selected = view?.selected;
    if (view == null || selected == null || view.rows.isEmpty) return;
    final grid =
        ref.read(inventoryControllerProvider).viewMode == InventoryViewMode.grid;
    final columns = grid ? InventoryGrid.columnsFor(_leftWidth) : 1;
    final delta = intent.dy * columns + (grid ? intent.dx : 0);
    if (delta == 0) return;
    final i = view.rows.indexWhere((r) => r.id == selected.id);
    final j = math.min(math.max(i + delta, 0), view.rows.length - 1);
    if (i < 0 || j == i) return;
    if (j >= view.visible.length) _controller.showMore();
    _controller.select(view.rows[j].id);
    _revealSelected();
  }

  void _openSelected() {
    final item = ref.read(inventoryViewProvider).value?.selected;
    if (item != null) InventoryActions.openDetails(context, item.medicine);
  }

  void _closePanel() {
    _controller.closePanel();
    _keysFocus.requestFocus();
  }

  /// Scrolls the page just enough to show the selected row or tile.
  void _revealSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final rowContext = _selectedKey.currentContext;
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

  bool get _onItems =>
      ref.read(inventoryControllerProvider).tab == InventoryTab.items;

  bool get _hasRows =>
      (ref.read(inventoryViewProvider).value?.rows.isNotEmpty ?? false);

  bool get _searchFocused => _searchFocus.hasPrimaryFocus;

  bool _sheetOpen() {
    final s = ref.read(inventoryControllerProvider);
    final view = ref.read(inventoryViewProvider).value;
    return !_wide &&
        s.panelOpen &&
        (view?.selectedExplicit ?? false) &&
        s.tab == InventoryTab.items;
  }

  Map<ShortcutActivator, Intent> get _shortcuts => {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            const _FocusSearchIntent(),
        if (defaultTargetPlatform == TargetPlatform.macOS)
          const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
              const _FocusSearchIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowDown):
            const _MoveIntent(dy: 1),
        const SingleActivator(LogicalKeyboardKey.arrowUp):
            const _MoveIntent(dy: -1),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            const _MoveIntent(dx: 1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            const _MoveIntent(dx: -1),
        const SingleActivator(LogicalKeyboardKey.enter): const _OpenIntent(),
        const SingleActivator(LogicalKeyboardKey.numpadEnter):
            const _OpenIntent(),
        const SingleActivator(LogicalKeyboardKey.escape): const _CloseIntent(),
      };

  Map<Type, Action<Intent>> get _actions => {
        _FocusSearchIntent: _InventoryAction<_FocusSearchIntent>(
          (_) => _onItems && _searchFocus.context != null,
          (_) => _searchFocus.requestFocus(),
        ),
        _MoveIntent: _InventoryAction<_MoveIntent>(
          (intent) {
            if (_searchFocused || !_onItems || !_hasRows) return false;
            // Left and right only move tiles in the grid.
            if (intent.dy == 0) {
              return ref.read(inventoryControllerProvider).viewMode ==
                  InventoryViewMode.grid;
            }
            return true;
          },
          _move,
        ),
        _OpenIntent: _InventoryAction<_OpenIntent>(
          (_) => !_searchFocused && _onItems && _hasRows,
          (_) => _openSelected(),
        ),
        _CloseIntent: _InventoryAction<_CloseIntent>(
          (_) => _sheetOpen(),
          (_) => _closePanel(),
        ),
      };

  // ---- Layout ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final state = ref.watch(inventoryControllerProvider);
    final async = ref.watch(inventoryViewProvider);
    final view = async.value;
    final width = MediaQuery.sizeOf(context).width;
    final padding = width < CruBreakpoint.compact
        ? CruSpace.mainPaddingCompact
        : CruSpace.mainPadding;

    final header = InventoryHeader(
      view: view,
      onNewOrder: () => _controller.setTab(InventoryTab.orders),
      onAddItem: () => InventoryActions.addItem(context, ref),
    );
    final toolbar = InventoryToolbar(
      tab: state.tab,
      searchFocus: _searchFocus,
      viewMode: state.viewMode,
      sort: view?.sort ?? state.sort,
      hasUsage: view?.hasUsage ?? true,
    );

    Widget body;
    if (state.tab != InventoryTab.items) {
      body = Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: CruSpace.s20),
            toolbar,
            const SizedBox(height: CruSpace.s20),
            Expanded(
              child: switch (state.tab) {
                InventoryTab.orders => const InventoryOrdersTab(),
                InventoryTab.vendors => const InventoryVendorsTab(),
                _ => const InventoryUsageTab(),
              },
            ),
          ],
        ),
      );
    } else {
      body = _items(
        context,
        state: state,
        async: async,
        view: view,
        padding: padding,
        width: width,
        top: [
          header,
          const SizedBox(height: CruSpace.s20),
          toolbar,
          if (view != null && view.all.isNotEmpty) ...[
            const SizedBox(height: CruSpace.s20),
            InventoryFilterChips(chips: view.chips, active: view.filter),
          ],
        ],
      );
    }

    return ColoredBox(
      color: c.canvas,
      child: Shortcuts(
        shortcuts: _shortcuts,
        child: Actions(
          actions: _actions,
          child: Focus(focusNode: _keysFocus, child: body),
        ),
      ),
    );
  }

  Widget _items(
    BuildContext context, {
    required InventoryState state,
    required AsyncValue<InventoryView> async,
    required InventoryView? view,
    required EdgeInsets padding,
    required double width,
    required List<Widget> top,
  }) {
    final wide = width >= CruBreakpoint.splitPane;
    final selected = view?.selected;
    final loading = view == null && !async.hasError;
    final hasItems = view != null && view.all.isNotEmpty;
    final split = wide && (loading || (hasItems && selected != null));
    final sheet = !wide &&
        state.panelOpen &&
        (view?.selectedExplicit ?? false) &&
        selected != null;
    final highlightId = split || sheet ? selected?.id : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final paneMaxHeight = math.max(
          0.0,
          constraints.maxHeight - 2 * CruSpace.s12,
        );
        final left = LayoutBuilder(
          builder: (context, box) {
            _leftWidth = box.maxWidth;
            return _leftColumn(
              state: state,
              async: async,
              view: view,
              highlightId: highlightId,
            );
          },
        );

        final Widget content;
        if (split) {
          content = SliverCrossAxisGroup(
            slivers: [
              SliverCrossAxisExpanded(
                flex: 1,
                sliver: SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: CruSpace.s12),
                    child: left,
                  ),
                ),
              ),
              SliverConstrainedCrossAxis(
                maxExtent: CruSize.rightColumn + CruSpace.cardGap,
                // Pinned: the panel stays in view while the list scrolls.
                sliver: PinnedHeaderSliver(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: CruSpace.cardGap,
                      top: CruSpace.s12,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: paneMaxHeight),
                      child: view == null
                          ? const InventoryPanelSkeleton()
                          : InventoryItemPanel(
                              item: selected!,
                              now: view.now,
                              hasUsage: view.hasUsage,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          );
        } else {
          content = SliverToBoxAdapter(child: left);
        }

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
              // pinned panel keeps a margin at the top of the window.
              child: SizedBox(
                height: split ? CruSpace.s20 - CruSpace.s12 : CruSpace.s20,
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.only(
                left: padding.left,
                right: padding.right,
              ),
              sliver: content,
            ),
            SliverToBoxAdapter(child: SizedBox(height: padding.bottom)),
          ],
        );

        if (!sheet) return scrollView;
        return Stack(
          children: [
            scrollView,
            Positioned.fill(child: _Backdrop(onTap: _closePanel)),
            Positioned(
              top: CruSpace.s12,
              bottom: CruSpace.s12,
              right: padding.right,
              width: math.min(
                CruSize.rightColumn,
                constraints.maxWidth - 2 * CruSpace.s16,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: _SlideIn(
                  child: InventoryItemPanel(
                    item: selected,
                    now: view!.now,
                    hasUsage: view.hasUsage,
                    onClose: _closePanel,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _leftColumn({
    required InventoryState state,
    required AsyncValue<InventoryView> async,
    required InventoryView? view,
    required String? highlightId,
  }) {
    if (view == null) {
      if (async.hasError) return const _LoadError();
      return const InventoryListSkeleton();
    }
    if (view.all.isEmpty) return const _EmptyInventory();

    final empty = _NoMatches(
      query: state.query,
      onClear: () => _controller.setQuery(''),
    );
    final Widget items = state.viewMode == InventoryViewMode.grid
        ? InventoryGrid(
            view: view,
            selectedId: highlightId,
            onTap: _onTap,
            selectedKey: _selectedKey,
            empty: empty,
          )
        : InventoryList(
            view: view,
            selectedId: highlightId,
            onTap: _onTap,
            selectedKey: _selectedKey,
            empty: empty,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (view.runOut != null) ...[
          InventoryRunOutStrip(strip: view.runOut!),
          const SizedBox(height: CruSpace.s16),
        ],
        items,
      ],
    );
  }
}

/// Opacity plus 16 px from the right, once, as the sheet appears.
class _SlideIn extends StatelessWidget {
  const _SlideIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: CruMotion.of(context, CruMotion.pane),
      curve: CruMotion.curve,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(CruSpace.s16 * (1 - t), 0),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Dims the list behind the narrow-width item sheet; tap to close.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Semantics(
      button: true,
      label: 'Close item',
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
            q.isEmpty ? 'No items in this list.' : 'No items match “$q”.',
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

class _EmptyInventory extends StatelessWidget {
  const _EmptyInventory();

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruCard(
      semanticLabel: 'Items',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('No items yet', style: CruType.headline.tint(c.label)),
          const SizedBox(height: CruSpace.s4),
          Text(
            'Add your first item to track its stock, expiry and use.',
            style: CruType.text.tint(c.label2),
          ),
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
      semanticLabel: 'Items',
      child: Text(
        "Couldn't load inventory. Try again in a moment.",
        style: CruType.text.tint(c.label2),
      ),
    );
  }
}
