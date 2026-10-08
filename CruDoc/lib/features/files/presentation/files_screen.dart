import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/features/files/data/files_providers.dart';
import 'package:doctor_management_app/features/files/domain/files_models.dart';
import 'package:doctor_management_app/features/files/presentation/file_viewer.dart';
import 'package:doctor_management_app/features/files/presentation/files_actions.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/files_bars.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/files_list.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/files_panel.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/files_style.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The Files tab, laid out like Inventory: header, Recent / Folders,
/// search and filters, then the list or grid with the 384 px panel (a
/// sheet below 1200 px). Tapping a file opens it. Files dragged in from
/// the computer are added after choosing their patient. Pads itself with
/// [CruSpace.mainPadding]. State lives in [filesControllerProvider].
class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key});

  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
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
class _FilesAction<T extends Intent> extends Action<T> {
  _FilesAction(this.enabled, this.run);

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

class _FilesScreenState extends ConsumerState<FilesScreen> {
  final ScrollController _scroll = ScrollController();
  final FocusNode _keysFocus = FocusNode(
    debugLabel: 'files',
    skipTraversal: true,
  );
  final FocusNode _searchFocus = FocusNode(debugLabel: 'files search');
  final GlobalKey _selectedKey = GlobalKey(debugLabel: 'selected file');

  /// Width of the list/grid column at the last layout (grid arrow keys).
  double _leftWidth = 0;
  bool _moreScheduled = false;

  /// Files from the computer are over the window.
  bool _dragging = false;

  FilesController get _controller => ref.read(filesControllerProvider.notifier);

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
    final view = ref.read(filesViewProvider).value;
    if (view == null || view.visible.length >= view.rows.length) return;
    _moreScheduled = true;
    _controller.showMore();
    WidgetsBinding.instance.addPostFrameCallback((_) => _moreScheduled = false);
  }

  bool get _wide => MediaQuery.sizeOf(context).width >= CruBreakpoint.splitPane;

  /// Tap opens the file. On wide screens it also becomes the panel's file,
  /// so its details are there when the viewer closes.
  void _onTap(FileEntry entry) {
    if (_wide) _controller.select(entry.id);
    _open(entry);
  }

  void _open(FileEntry entry) =>
      FilesActions.open(context, entry.file, patientName: entry.patientName);

  void _move(_MoveIntent intent) {
    final view = ref.read(filesViewProvider).value;
    final selected = view?.selected;
    if (view == null || selected == null || view.rows.isEmpty) return;
    final grid =
        ref.read(filesControllerProvider).viewMode == FilesViewMode.grid;
    final columns = grid ? FilesGrid.columnsFor(_leftWidth) : 1;
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
    final entry = ref.read(filesViewProvider).value?.selected;
    if (entry != null) _open(entry);
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

  bool get _hasRows =>
      (ref.read(filesViewProvider).value?.rows.isNotEmpty ?? false);

  bool get _searchFocused => _searchFocus.hasPrimaryFocus;

  bool _sheetOpen() {
    final s = ref.read(filesControllerProvider);
    final view = ref.read(filesViewProvider).value;
    return !_wide && s.panelOpen && (view?.selectedExplicit ?? false);
  }

  /// Folders tab inside a folder: Esc goes up one.
  bool _canGoUp() {
    final s = ref.read(filesControllerProvider);
    return s.tab == FilesTab.folders && s.folderId.isNotEmpty;
  }

  void _goUp() {
    final view = ref.read(filesViewProvider).value;
    _controller.openFolder(view?.current?.folder.parentId ?? '');
  }

  Map<ShortcutActivator, Intent> get _shortcuts => {
    const SingleActivator(LogicalKeyboardKey.keyF, control: true):
        const _FocusSearchIntent(),
    if (defaultTargetPlatform == TargetPlatform.macOS)
      const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
          const _FocusSearchIntent(),
    const SingleActivator(LogicalKeyboardKey.arrowDown): const _MoveIntent(
      dy: 1,
    ),
    const SingleActivator(LogicalKeyboardKey.arrowUp): const _MoveIntent(
      dy: -1,
    ),
    const SingleActivator(LogicalKeyboardKey.arrowRight): const _MoveIntent(
      dx: 1,
    ),
    const SingleActivator(LogicalKeyboardKey.arrowLeft): const _MoveIntent(
      dx: -1,
    ),
    const SingleActivator(LogicalKeyboardKey.enter): const _OpenIntent(),
    const SingleActivator(LogicalKeyboardKey.numpadEnter): const _OpenIntent(),
    const SingleActivator(LogicalKeyboardKey.escape): const _CloseIntent(),
  };

  Map<Type, Action<Intent>> get _actions => {
    _FocusSearchIntent: _FilesAction<_FocusSearchIntent>(
      (_) => _searchFocus.context != null,
      (_) => _searchFocus.requestFocus(),
    ),
    _MoveIntent: _FilesAction<_MoveIntent>((intent) {
      if (_searchFocused || !_hasRows) return false;
      // Left and right only move tiles in the grid.
      if (intent.dy == 0) {
        return ref.read(filesControllerProvider).viewMode == FilesViewMode.grid;
      }
      return true;
    }, _move),
    _OpenIntent: _FilesAction<_OpenIntent>(
      (_) => !_searchFocused && _hasRows,
      (_) => _openSelected(),
    ),
    _CloseIntent: _FilesAction<_CloseIntent>(
      (_) => !_searchFocused && (_sheetOpen() || _canGoUp()),
      (_) => _sheetOpen() ? _closePanel() : _goUp(),
    ),
  };

  // ---- Adding ------------------------------------------------------------

  /// Where new files go: the open folder on the Folders tab.
  String get _targetFolder {
    final s = ref.read(filesControllerProvider);
    return s.tab == FilesTab.folders ? s.folderId : '';
  }

  void _addFiles() => FilesActions.pickAndAdd(
    context,
    patientId: ref.read(filesControllerProvider).patientId,
    folderId: _targetFolder,
  );

  void _newFolder() => FilesActions.newFolder(context, parentId: _targetFolder);

  void _onDropped(List<String> paths) {
    if (paths.isEmpty) return;
    FilesActions.addPaths(
      context,
      paths,
      patientId: ref.read(filesControllerProvider).patientId,
      folderId: _targetFolder,
    );
  }

  // ---- Layout ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(filesControllerProvider);
    final async = ref.watch(filesViewProvider);
    final view = async.value;
    final width = MediaQuery.sizeOf(context).width;
    final padding = cruIsPhone(context)
        ? CruSpace.mainPaddingPhone
        : width < CruBreakpoint.compact
        ? CruSpace.mainPaddingCompact
        : CruSpace.mainPadding;

    final canEdit = ref.watch(clinicCanProvider(ClinicPermission.clinicalEdit));
    final top = <Widget>[
      FilesHeader(
        view: view,
        onNewFolder: canEdit ? _newFolder : null,
        onAddFiles: canEdit ? _addFiles : null,
      ),
      const SizedBox(height: CruSpace.s20),
      FilesToolbar(
        state: state,
        searchFocus: _searchFocus,
        sort: view?.sort ?? state.sort,
      ),
      if (view != null && !view.isEmpty) ...[
        const SizedBox(height: CruSpace.s20),
        FilesChips(view: view),
      ],
      if (view != null && state.tab == FilesTab.folders) ...[
        const SizedBox(height: CruSpace.s16),
        FilesBreadcrumbs(view: view),
      ],
    ];

    Widget body = _items(
      context,
      state: state,
      async: async,
      view: view,
      padding: padding,
      width: width,
      top: top,
    );

    if (filesOnDesktop && canEdit) {
      body = DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (detail) {
          setState(() => _dragging = false);
          _onDropped([for (final f in detail.files) f.path]);
        },
        child: Stack(
          children: [
            body,
            if (_dragging)
              Positioned.fill(
                child: IgnorePointer(
                  child: _DropOverlay(
                    folderName: state.tab == FilesTab.folders
                        ? view?.current?.folder.name
                        : null,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Shortcuts(
      shortcuts: _shortcuts,
      child: Actions(
        actions: _actions,
        child: Focus(focusNode: _keysFocus, child: body),
      ),
    );
  }

  Widget _items(
    BuildContext context, {
    required FilesState state,
    required AsyncValue<FilesView> async,
    required FilesView? view,
    required EdgeInsets padding,
    required double width,
    required List<Widget> top,
  }) {
    final wide = width >= CruBreakpoint.splitPane;
    final selected = view?.selected;
    final loading = view == null && !async.hasError;
    // The open folder's details when it has no files to show.
    final folderPanel = view != null && selected == null ? view.current : null;
    final split = wide && (loading || selected != null || folderPanel != null);
    final sheet =
        !wide &&
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
                          ? const FilesPanelSkeleton()
                          : selected != null
                          ? FilePanel(entry: selected, now: view.now)
                          : FolderPanel(entry: folderPanel!),
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
                  child: FilePanel(
                    entry: selected,
                    now: view!.now,
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
    required FilesState state,
    required AsyncValue<FilesView> async,
    required FilesView? view,
    required String? highlightId,
  }) {
    if (view == null) {
      if (async.hasError) return const _LoadError();
      return const FilesListSkeleton();
    }
    if (view.isEmpty) {
      final canEdit = ref.read(
        clinicCanProvider(ClinicPermission.clinicalEdit),
      );
      return _EmptyFiles(onAdd: canEdit ? _addFiles : null);
    }

    final empty = _NoMatches(
      query: state.query,
      inFolder: state.tab == FilesTab.folders && view.current != null,
      filtered: view.filter != null || view.patientFilterName != null,
      onClear: () => _controller.setQuery(''),
    );
    return state.viewMode == FilesViewMode.grid
        ? FilesGrid(
            view: view,
            selectedId: highlightId,
            onTap: _onTap,
            selectedKey: _selectedKey,
            empty: empty,
          )
        : FilesList(
            view: view,
            tab: state.tab,
            selectedId: highlightId,
            onTap: _onTap,
            selectedKey: _selectedKey,
            empty: empty,
          );
  }
}

/// Covers the screen while files from the computer are dragged over it.
class _DropOverlay extends StatelessWidget {
  const _DropOverlay({this.folderName});

  final String? folderName;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.all(CruSpace.s16),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: c.accentWash.withValues(alpha: 0.92),
          shape: cruShape(
            CruRadius.card,
            side: BorderSide(color: c.accent, width: FilesSize.tileRing),
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CruIcon(
                FileIcons.upload,
                size: 40,
                strokeWidth: 1.6,
                color: c.accentText,
              ),
              const SizedBox(height: CruSpace.s12),
              Text(
                folderName == null
                    ? 'Drop to add files'
                    : 'Drop to add files to $folderName',
                style: CruType.headline.tint(c.accentText),
              ),
              const SizedBox(height: CruSpace.s4),
              Text(
                'You will choose the patient next.',
                style: CruType.text.tint(c.label2),
              ),
            ],
          ),
        ),
      ),
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

/// Dims the list behind the narrow-width sheet; tap to close.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Semantics(
      button: true,
      label: 'Close file details',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: CruMotion.of(context, CruMotion.pane),
          curve: CruMotion.curve,
          builder: (context, t, _) =>
              ColoredBox(color: c.label.withValues(alpha: 0.24 * t)),
        ),
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({
    required this.query,
    required this.inFolder,
    required this.filtered,
    required this.onClear,
  });

  final String query;
  final bool inFolder;
  final bool filtered;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final q = query.trim();
    final text = q.isNotEmpty
        ? 'No files match “$q”.'
        : filtered
        ? 'No files here for this filter.'
        : inFolder
        ? 'This folder is empty. Drag files here, or use Add files.'
        : 'No files here yet.';
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s16,
        vertical: CruSpace.s24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: CruType.text.tint(c.label2)),
          if (q.isNotEmpty) ...[
            const SizedBox(height: CruSpace.s8),
            CruLink(label: 'Clear search', onPressed: onClear),
          ],
        ],
      ),
    );
  }
}

class _EmptyFiles extends StatelessWidget {
  const _EmptyFiles({required this.onAdd});

  /// Null for people who may only look.
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruCard(
      semanticLabel: 'Files',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('No files yet', style: CruType.headline.tint(c.label)),
          const SizedBox(height: CruSpace.s4),
          Text(
            onAdd == null
                ? 'X-rays, photos and reports your colleagues share with you '
                      'will show here.'
                : filesOnDesktop
                ? 'Drag X-rays, photos and reports here, or use Add files. '
                      'Each file is saved to a patient.'
                : 'Use Add files for X-rays, photos and reports. Each file '
                      'is saved to a patient.',
            style: CruType.text.tint(c.label2),
          ),
          if (onAdd != null) ...[
            const SizedBox(height: CruSpace.s16),
            CruButton(
              label: 'Add files',
              kind: CruButtonKind.inset,
              icon: FileIcons.upload,
              onPressed: onAdd,
            ),
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
      semanticLabel: 'Files',
      child: Text(
        "Couldn't load files. Try again in a moment.",
        style: CruType.text.tint(c.label2),
      ),
    );
  }
}
