import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/presentation/patient_picker_dialog.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/features/files/data/files_providers.dart';
import 'package:doctor_management_app/features/files/domain/files_models.dart';
import 'package:doctor_management_app/features/files/presentation/files_actions.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/files_style.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_style.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

String _count(int n, String one) => n == 1 ? '1 $one' : '$n ${one}s';

/// "Files", "128 files · 9 folders", New folder and Add files.
class FilesHeader extends StatelessWidget {
  const FilesHeader({
    super.key,
    required this.view,
    required this.onNewFolder,
    required this.onAddFiles,
  });

  /// Null while loading (the subtitle shows a skeleton).
  final FilesView? view;

  /// Null for people who may only look (no clinical edit): no buttons.
  final VoidCallback? onNewFolder;
  final VoidCallback? onAddFiles;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final v = view;
    final subtitle = v == null
        ? null
        : Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: _count(v.totalFiles, 'file'),
                  style: CruType.text.tabular.tint(c.accentText),
                ),
                if (v.totalFolders > 0) ...[
                  const TextSpan(text: ' · '),
                  TextSpan(
                    text: _count(v.totalFolders, 'folder'),
                    style: CruType.text.tabular.tint(c.label2),
                  ),
                ],
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
    final sub = SizedBox(
      height: CruType.text.fontSize! * CruType.text.height!,
      child:
          subtitle ??
          const Align(
            alignment: Alignment.centerLeft,
            child: SkeletonBox(width: 160, height: 12),
          ),
    );
    final newFolder = CruButton(
      label: 'New folder',
      kind: CruButtonKind.secondary,
      icon: FileIcons.folderPlus,
      onPressed: onNewFolder,
    );
    final addFiles = CruButton(
      label: 'Add files',
      icon: CruIcons.plus,
      onPressed: onAddFiles,
    );

    if (cruIsPhone(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Files',
              style: CruType.largeTitle.copyWith(fontSize: 28).tint(c.label),
            ),
          ),
          const SizedBox(height: CruSpace.s2),
          sub,
          if (onAddFiles != null) ...[
            const SizedBox(height: CruSpace.s14),
            // Thumb-sized: both share the width.
            Row(
              children: [
                Expanded(
                  child: CruButton(
                    label: 'New folder',
                    kind: CruButtonKind.secondary,
                    icon: FileIcons.folderPlus,
                    expand: true,
                    onPressed: onNewFolder,
                  ),
                ),
                const SizedBox(width: CruSpace.s8),
                Expanded(
                  child: CruButton(
                    label: 'Add files',
                    icon: CruIcons.plus,
                    expand: true,
                    onPressed: onAddFiles,
                  ),
                ),
              ],
            ),
          ],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text('Files', style: CruType.largeTitle.tint(c.label)),
              ),
              const SizedBox(height: CruSpace.s2),
              sub,
            ],
          ),
        ),
        if (onAddFiles != null) ...[
          const SizedBox(width: CruSpace.s24),
          newFolder,
          const SizedBox(width: CruSpace.s10),
          addFiles,
        ],
      ],
    );
  }
}

/// Recent / Folders, then search, patient, list/grid and sort.
class FilesToolbar extends ConsumerWidget {
  const FilesToolbar({
    super.key,
    required this.state,
    required this.searchFocus,
    required this.sort,
  });

  final FilesState state;
  final FocusNode searchFocus;

  /// The sort actually applied.
  final FilesSort sort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = CruSegmentedControl<FilesTab>(
      semanticLabel: 'Files sections',
      segments: [for (final t in FilesTab.values) CruSegment(t, t.label)],
      selected: state.tab,
      onChanged: ref.read(filesControllerProvider.notifier).setTab,
    );
    if (cruIsPhone(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              tabs,
              const Spacer(),
              _PatientButton(patientId: state.patientId, compact: true),
            ],
          ),
          const SizedBox(height: CruSpace.s10),
          Row(
            children: [
              Expanded(child: _FilesSearchField(focusNode: searchFocus)),
              const SizedBox(width: CruSpace.s8),
              _FilesSortButton(sort: sort),
            ],
          ),
        ],
      );
    }
    return Row(
      children: [
        tabs,
        const SizedBox(width: CruSpace.s12),
        Expanded(child: _FilesSearchField(focusNode: searchFocus)),
        const SizedBox(width: CruSpace.s12),
        _PatientButton(patientId: state.patientId),
        const SizedBox(width: CruSpace.s12),
        _FilesViewToggle(mode: state.viewMode),
        const SizedBox(width: CruSpace.s12),
        _FilesSortButton(sort: sort),
      ],
    );
  }
}

/// Filters live while typing without rebuilding on every keystroke.
const Duration _debounce = Duration(milliseconds: 150);

String _shortcut() =>
    defaultTargetPlatform == TargetPlatform.macOS ? '⌘F' : 'Ctrl F';

/// "Search files or patients", 44 px, with the Ctrl F keycap.
class _FilesSearchField extends ConsumerStatefulWidget {
  const _FilesSearchField({required this.focusNode});

  final FocusNode focusNode;

  @override
  ConsumerState<_FilesSearchField> createState() => _FilesSearchFieldState();
}

class _FilesSearchFieldState extends ConsumerState<_FilesSearchField> {
  late final TextEditingController _text = TextEditingController(
    text: ref.read(filesControllerProvider).query,
  );
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {}); // clear button
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      if (!mounted) return;
      ref.read(filesControllerProvider.notifier).setQuery(value);
    });
  }

  void _clear() {
    _timer?.cancel();
    _text.clear();
    setState(() {});
    ref.read(filesControllerProvider.notifier).setQuery('');
    widget.focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    // The query can be cleared from elsewhere ("Clear search", a folder).
    ref.listen(filesControllerProvider.select((s) => s.query), (_, next) {
      final pending = _timer?.isActive ?? false;
      if (!pending && next != _text.text) {
        _text.text = next;
        setState(() {});
      }
    });

    return Container(
      height: CruSize.searchBar,
      padding: const EdgeInsets.fromLTRB(CruSpace.s14, 0, CruSpace.s10, 0),
      decoration: ShapeDecoration(
        color: c.surface,
        shape: cruShape(CruRadius.control, side: BorderSide(color: c.hairline)),
        shadows: const [],
      ),
      child: Row(
        children: [
          CruIcon(CruIcons.search, size: 18, strokeWidth: 2, color: c.label3),
          const SizedBox(width: CruSpace.s10),
          Expanded(
            child: TextField(
              controller: _text,
              focusNode: widget.focusNode,
              onChanged: _onChanged,
              style: CruType.input.tint(c.label),
              cursorColor: c.accent,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                hint: Text(
                  cruIsPhone(context)
                      ? 'Search files'
                      : 'Search files, patients or folders',
                  style: CruType.input.tint(c.label3),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                ),
              ),
            ),
          ),
          const SizedBox(width: CruSpace.s10),
          if (_text.text.isNotEmpty)
            CruIconButton(
              icon: CruIcons.close,
              size: CruSize.capsule,
              iconSize: 16,
              semanticLabel: 'Clear search',
              tooltip: 'Clear search',
              onPressed: _clear,
            )
          else if (!cruIsPhone(context))
            CruKeycap(_shortcut()),
        ],
      ),
    );
  }
}

/// "Patient  All ⌄": picks one patient to show files for.
class _PatientButton extends ConsumerWidget {
  const _PatientButton({required this.patientId, this.compact = false});

  final String? patientId;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final name = ref.watch(filesViewProvider).value?.patientFilterName;
    final label = patientId == null ? 'All' : (name ?? 'One patient');
    return CruPressable(
      onTap: () async {
        final p = await showPatientPickerDialog(
          Navigator.of(context, rootNavigator: true).context,
          title: 'Show files for',
        );
        if (p != null) {
          ref.read(filesControllerProvider.notifier).setPatient(p.id);
        }
      },
      semanticLabel: 'Patient: $label',
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        height: CruSize.searchBar,
        constraints: const BoxConstraints(maxWidth: 240),
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s14),
        decoration: ShapeDecoration(
          color: hovered ? c.hoverFill : c.surface,
          shape: cruShape(
            CruRadius.control,
            side: BorderSide(color: c.hairline),
          ),
          shadows: const [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (compact)
              CruIcon(CruIcons.user, size: 18, strokeWidth: 2, color: c.label2)
            else ...[
              Text('Patient', style: CruType.text.w500.tint(c.label2)),
              const SizedBox(width: CruSpace.s6),
              Flexible(
                child: Text(
                  label,
                  style: CruType.text.w500.tint(c.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            const SizedBox(width: CruSpace.s6),
            CruIcon(
              CruIcons.chevronDown,
              size: 14,
              strokeWidth: 2.2,
              color: c.label2,
            ),
          ],
        ),
      ),
    );
  }
}

/// List / grid, remembered per device.
class _FilesViewToggle extends ConsumerWidget {
  const _FilesViewToggle({required this.mode});

  final FilesViewMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    void pick(FilesViewMode m) =>
        ref.read(filesControllerProvider.notifier).setViewMode(m);
    return Semantics(
      container: true,
      label: 'View',
      child: Container(
        height: CruSize.searchBar,
        padding: const EdgeInsets.all(CruSpace.s2 + 1),
        decoration: ShapeDecoration(
          color: c.inset,
          shape: cruShape(CruRadius.segmentOuter),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ToggleButton(
              icon: InventoryIcons.list,
              label: 'List view',
              selected: mode == FilesViewMode.list,
              onTap: () => pick(FilesViewMode.list),
            ),
            const SizedBox(width: CruSpace.s2),
            _ToggleButton(
              icon: InventoryIcons.grid,
              label: 'Grid view',
              selected: mode == FilesViewMode.grid,
              onTap: () => pick(FilesViewMode.grid),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final CruIconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Semantics(
      button: true,
      toggled: selected,
      label: label,
      excludeSemantics: true,
      child: CruPressable(
        onTap: onTap,
        tooltip: label,
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          width: CruSize.control,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: selected
                ? c.segmentSelected
                : (hovered ? c.hoverFill : c.inset.withValues(alpha: 0)),
            shape: cruShape(CruRadius.segmentInner),
            shadows: const [],
          ),
          child: CruIcon(
            icon,
            size: 18,
            strokeWidth: 1.9,
            color: selected ? c.label : c.label2,
          ),
        ),
      ),
    );
  }
}

/// "Sort  Newest first ⌄".
class _FilesSortButton extends ConsumerWidget {
  const _FilesSortButton({required this.sort});

  final FilesSort sort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    return FilesMenu(
      items: [
        for (final s in FilesSort.values)
          FilesMenuItem(
            s.label,
            () => ref.read(filesControllerProvider.notifier).setSort(s),
            checked: s == sort,
          ),
      ],
      builder: (context, open) => CruPressable(
        onTap: open,
        semanticLabel: 'Sort by ${sort.label}',
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          height: CruSize.searchBar,
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s14),
          decoration: ShapeDecoration(
            color: hovered ? c.hoverFill : c.surface,
            shape: cruShape(
              CruRadius.control,
              side: BorderSide(color: c.hairline),
            ),
            shadows: const [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!cruIsPhone(context)) ...[
                Text('Sort', style: CruType.text.w500.tint(c.label2)),
                const SizedBox(width: CruSpace.s6),
              ],
              Text(sort.label, style: CruType.text.w500.tint(c.label)),
              const SizedBox(width: CruSpace.s6),
              CruIcon(
                CruIcons.chevronDown,
                size: 14,
                strokeWidth: 2.2,
                color: c.label2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One entry in a [FilesMenu].
class FilesMenuItem {
  const FilesMenuItem(this.label, this.onSelected, {this.checked = false});

  final String label;
  final VoidCallback onSelected;
  final bool checked;
}

/// A small on-token menu (sort, a row's actions). [builder] gets a
/// callback that opens it; right-click opens it where the pointer is.
class FilesMenu extends StatelessWidget {
  const FilesMenu({
    super.key,
    required this.items,
    required this.builder,
    this.controller,
    this.endAlignedWidth,
  });

  final List<FilesMenuItem> items;
  final Widget Function(BuildContext context, VoidCallback open) builder;

  /// When set, the menu is this wide and lines up with the button's right
  /// edge, so it opens inward (a button at the right of a dialog).
  final double? endAlignedWidth;

  /// Lets the owner open the menu at a point (right-click on a row).
  final MenuController? controller;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final itemShape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(CruRadius.control - CruSpace.s6),
    );
    final endWidth = endAlignedWidth;
    return MenuAnchor(
      controller: controller,
      alignmentOffset: Offset(endWidth == null ? 0 : -endWidth, CruSpace.s6),
      style: MenuStyle(
        alignment: endWidth == null ? null : AlignmentDirectional.bottomEnd,
        minimumSize: endWidth == null
            ? null
            : WidgetStatePropertyAll(Size(endWidth, 0)),
        maximumSize: endWidth == null
            ? null
            : WidgetStatePropertyAll(Size(endWidth, double.infinity)),
        backgroundColor: WidgetStatePropertyAll(c.surface),
        surfaceTintColor: WidgetStatePropertyAll(
          c.surface.withValues(alpha: 0),
        ),
        shadowColor: WidgetStatePropertyAll(c.label.withValues(alpha: 0.18)),
        // Raised when it opens over other controls inside a form.
        elevation: WidgetStatePropertyAll(endWidth == null ? 0 : 6),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(CruSpace.s6)),
        shape: WidgetStatePropertyAll(
          RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(CruRadius.control),
            side: BorderSide(color: c.hairline),
          ),
        ),
      ),
      menuChildren: [
        for (final item in items)
          MenuItemButton(
            onPressed: item.onSelected,
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(
                Size(0, CruSize.control),
              ),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: CruSpace.s12),
              ),
              shape: WidgetStatePropertyAll(itemShape),
              overlayColor: WidgetStatePropertyAll(
                c.hoverFill.withValues(alpha: 0),
              ),
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) =>
                    states.contains(WidgetState.hovered) ||
                        states.contains(WidgetState.focused)
                    ? c.hoverFill
                    : c.surface,
              ),
            ),
            trailingIcon: item.checked
                ? CruIcon(
                    CruIcons.check,
                    size: 16,
                    strokeWidth: 2.2,
                    color: c.accentText,
                  )
                : null,
            child: Text(
              item.label,
              style: (item.checked ? CruType.text.w600 : CruType.text.w500)
                  .tint(c.label),
            ),
          ),
      ],
      builder: (context, menu, _) =>
          builder(context, () => menu.isOpen ? menu.close() : menu.open()),
    );
  }
}

/// All, then one chip per kind of file, each with its count; and the
/// patient the list is limited to, with ×.
class FilesChips extends ConsumerWidget {
  const FilesChips({super.key, required this.view});

  final FilesView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(filesControllerProvider.notifier);
    return Semantics(
      container: true,
      label: 'File kinds',
      child: Wrap(
        spacing: CruSpace.s8,
        runSpacing: CruSpace.s8,
        children: [
          if (view.patientFilterName != null)
            _Chip(
              label: view.patientFilterName!,
              selected: true,
              icon: CruIcons.user,
              trailing: CruIcons.close,
              semanticLabel: 'Showing ${view.patientFilterName}. Show everyone',
              onTap: () => controller.setPatient(null),
            ),
          for (final chip in view.chips)
            _Chip(
              label: chip.label,
              count: chip.count,
              selected: chip.kind == view.filter,
              semanticLabel: '${chip.label}, ${chip.count}',
              onTap: () => controller.setFilter(chip.kind),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.semanticLabel,
    this.count,
    this.icon,
    this.trailing,
  });

  final String label;
  final int? count;
  final bool selected;
  final CruIconData? icon;
  final CruIconData? trailing;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final fg = selected ? c.accentText : c.label;
    return Semantics(
      selected: selected,
      child: CruPressable(
        onTap: onTap,
        semanticLabel: semanticLabel,
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          height: CruSize.filterChip,
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s14),
          decoration: ShapeDecoration(
            color: selected
                ? c.accentTint
                : (hovered ? c.hoverFill : c.surface),
            shape: StadiumBorder(
              side: BorderSide(
                color: selected ? c.hairline.withValues(alpha: 0) : c.hairline,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                CruIcon(icon!, size: 14, strokeWidth: 2.2, color: fg),
                const SizedBox(width: CruSpace.s6),
              ],
              Text(
                label,
                style: (selected ? CruType.chip.w600 : CruType.chip).tint(fg),
              ),
              if (count != null) ...[
                const SizedBox(width: CruSpace.s8),
                Text(
                  '$count',
                  style: CruType.chip.tabular.tint(
                    selected ? c.accentText : c.label2,
                  ),
                ),
              ],
              if (trailing != null) ...[
                const SizedBox(width: CruSpace.s6),
                CruIcon(trailing!, size: 14, strokeWidth: 2.2, color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "All folders › X-rays › 2026". Each step opens that folder, and takes
/// files dropped on it.
class FilesBreadcrumbs extends ConsumerWidget {
  const FilesBreadcrumbs({super.key, required this.view});

  final FilesView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final controller = ref.read(filesControllerProvider.notifier);
    final steps = <(String, String)>[
      ('', 'All folders'),
      for (final b in view.breadcrumbs) (b.id, b.folder.name),
    ];
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: CruSpace.s4,
      runSpacing: CruSpace.s4,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0)
            CruIcon(
              CruIcons.chevronRight,
              size: 14,
              strokeWidth: 2,
              color: c.label3,
            ),
          FileDropTarget(
            folderId: steps[i].$1,
            child: i == steps.length - 1
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: CruSpace.s6,
                      vertical: CruSpace.s4,
                    ),
                    child: Text(
                      steps[i].$2,
                      style: CruType.text.w600.tint(c.label),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: CruSpace.s6,
                      vertical: CruSpace.s4,
                    ),
                    child: CruLink(
                      label: steps[i].$2,
                      onPressed: () => controller.openFolder(steps[i].$1),
                    ),
                  ),
          ),
        ],
      ],
    );
  }
}

/// Takes a file row dragged onto it and moves the file into [folderId]
/// ('' for no folder). Highlights while a file is over it.
class FileDropTarget extends StatelessWidget {
  const FileDropTarget({
    super.key,
    required this.folderId,
    required this.child,
  });

  final String folderId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return DragTarget<FileEntry>(
      onWillAcceptWithDetails: (d) => d.data.file.folderId != folderId,
      onAcceptWithDetails: (d) =>
          FilesActions.dropOnFolder(context, d.data, folderId),
      builder: (context, candidates, _) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        decoration: ShapeDecoration(
          color: candidates.isEmpty
              ? c.accentWash.withValues(alpha: 0)
              : c.accentWash,
          shape: cruShape(
            CruRadius.control,
            side: BorderSide(
              color: candidates.isEmpty
                  ? c.accent.withValues(alpha: 0)
                  : c.accent,
              width: FilesSize.rowRing,
            ),
          ),
        ),
        child: child,
      ),
    );
  }
}
