import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/presentation/patient_picker_dialog.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/features/files/data/files_providers.dart';
import 'package:doctor_management_app/features/files/domain/files_models.dart';
import 'package:doctor_management_app/features/files/presentation/files_actions.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/files_patient.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/files_style.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_style.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/shared/widgets/page_search.dart';

String _count(int n, String one) => n == 1 ? '1 $one' : '$n ${one}s';

/// "Files", "128 files · 9 folders", New folder and Add files.
class FilesHeader extends StatelessWidget {
  const FilesHeader({
    super.key,
    required this.view,
    required this.onNewFolder,
    required this.onAddFiles,
    this.onTransfers,
    this.waitingTransfers = 0,
  });

  /// Null while loading (the subtitle shows a skeleton).
  final FilesView? view;

  /// Null for people who may only look (no clinical edit): no buttons.
  final VoidCallback? onNewFolder;
  final VoidCallback? onAddFiles;

  /// Opens received and sent files. Null with no colleagues (solo doctor).
  final VoidCallback? onTransfers;

  /// Received files waiting for Accept, shown on the button.
  final int waitingTransfers;

  String get _transfersLabel =>
      waitingTransfers > 0 ? 'Transfers · $waitingTransfers' : 'Transfers';

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
                  TextSpan(
                    text: ' · ',
                    style: CruType.text.tabular.tint(c.accentText),
                  ),
                  TextSpan(
                    text: _count(v.totalFolders, 'folder'),
                    style: CruType.text.tabular.tint(c.accentText),
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
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'Files',
                    style: CruType.largeTitle
                        .copyWith(fontSize: 28)
                        .tint(c.label),
                  ),
                ),
              ),
              if (onTransfers != null)
                CruCapsuleButton(
                  label: _transfersLabel,
                  icon: CruIcons.importExport,
                  onPressed: onTransfers,
                ),
            ],
          ),
          const SizedBox(height: CruSpace.s2),
          sub,
          if (onAddFiles != null) ...[
            const SizedBox(height: CruSpace.s14),
            // Thumb-sized. New folder lives beside the folder path below.
            CruButton(
              label: 'Add files',
              icon: CruIcons.plus,
              expand: true,
              onPressed: onAddFiles,
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
        if (onTransfers != null) ...[
          const SizedBox(width: CruSpace.s24),
          CruButton(
            label: _transfersLabel,
            kind: CruButtonKind.secondary,
            icon: CruIcons.importExport,
            onPressed: onTransfers,
          ),
        ],
        if (onAddFiles != null) ...[
          SizedBox(width: onTransfers != null ? CruSpace.s10 : CruSpace.s24),
          newFolder,
          const SizedBox(width: CruSpace.s10),
          addFiles,
        ],
      ],
    );
  }
}

/// Search (with list/grid and sort inside it) and patient.
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
    final search = _FilesSearchField(
      focusNode: searchFocus,
      sort: sort,
      mode: state.viewMode,
    );
    if (cruIsPhone(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          search,
          // Typing a patient's name offers them here; picking one limits
          // the list to them and slides their name in from the top.
          if (state.patientId == null)
            FilesPatientSuggestions(query: state.query),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: search),
        const SizedBox(width: CruSpace.s12),
        _PatientButton(patientId: state.patientId),
      ],
    );
  }
}

/// Filters live while typing without rebuilding on every keystroke.
const Duration _debounce = Duration(milliseconds: 150);

String _shortcut() =>
    defaultTargetPlatform == TargetPlatform.macOS ? '⌘F' : 'Ctrl F';

/// "Search files or patients", 44 px, with Ctrl F keycap, list/grid and
/// sort icons.
class _FilesSearchField extends ConsumerStatefulWidget {
  const _FilesSearchField({
    required this.focusNode,
    required this.sort,
    required this.mode,
  });

  final FocusNode focusNode;
  final FilesSort sort;
  final FilesViewMode mode;

  @override
  ConsumerState<_FilesSearchField> createState() => _FilesSearchFieldState();
}

class _FilesSearchFieldState extends ConsumerState<_FilesSearchField> {
  late final TextEditingController _text = TextEditingController(
    text: ref.read(filesControllerProvider).query,
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Ctrl F from anywhere on the desktop.
    PageSearch.add(widget.focusNode);
  }

  @override
  void dispose() {
    PageSearch.remove(widget.focusNode);
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

    final phone = cruIsPhone(context);
    final text = phone ? CruType.body : CruType.input;
    return Container(
      height: phone ? CruSize.searchBarPhone : CruSize.searchBar,
      padding: phone
          ? const EdgeInsets.fromLTRB(CruSpace.s16, 0, CruSpace.s4, 0)
          : const EdgeInsets.fromLTRB(CruSpace.s14, 0, CruSpace.s6, 0),
      decoration: ShapeDecoration(
        color: c.surface,
        shape: cruShape(CruRadius.control, side: BorderSide(color: c.hairline)),
        shadows: const [],
      ),
      child: Row(
        children: [
          CruIcon(
            CruIcons.search,
            size: phone ? CruSize.searchIconPhone : 18,
            strokeWidth: 2,
            color: c.label3,
          ),
          SizedBox(width: phone ? CruSpace.s12 : CruSpace.s10),
          Expanded(
            child: TextField(
              controller: _text,
              focusNode: widget.focusNode,
              onChanged: _onChanged,
              style: text.tint(c.label),
              cursorColor: c.accent,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                hint: Text(
                  // The phone's two tools leave room for little more.
                  phone ? 'Search files' : 'Search files, patients or folders',
                  style: text.tint(c.label3),
                  maxLines: 1,
                  softWrap: false,
                  overflow: phone ? TextOverflow.ellipsis : TextOverflow.clip,
                ),
              ),
            ),
          ),
          if (!phone) const SizedBox(width: CruSpace.s8),
          if (_text.text.isNotEmpty) ...[
            CruIconButton(
              icon: CruIcons.close,
              size: phone ? CruSize.searchToolPhone : CruSize.capsule,
              iconSize: phone ? CruSize.searchClearIconPhone : 16,
              semanticLabel: 'Clear search',
              tooltip: 'Clear search',
              onPressed: _clear,
            ),
            if (!phone) const SizedBox(width: CruSpace.s4),
          ] else if (!phone) ...[
            CruKeycap(_shortcut()),
            const SizedBox(width: CruSpace.s6),
          ],
          _FilesViewModeIcon(mode: widget.mode),
          const SizedBox(width: CruSpace.s2),
          _FilesSortIcon(sort: widget.sort),
        ],
      ),
    );
  }
}

/// "Patient  All ⌄": picks one patient to show files for.
class _PatientButton extends ConsumerWidget {
  const _PatientButton({required this.patientId});

  final String? patientId;

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

/// List / grid icon inside the search field, remembered per device. It
/// shows the view a tap switches to.
class _FilesViewModeIcon extends ConsumerWidget {
  const _FilesViewModeIcon({required this.mode});

  final FilesViewMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toGrid = mode == FilesViewMode.list;
    final label = toGrid ? 'Grid view' : 'List view';
    final phone = cruIsPhone(context);
    return CruIconButton(
      icon: toGrid ? InventoryIcons.grid : InventoryIcons.list,
      size: phone ? CruSize.searchToolPhone : CruSize.capsule,
      iconSize: phone ? CruSize.searchToolIconPhone : 16,
      semanticLabel: label,
      tooltip: label,
      onPressed: () => ref
          .read(filesControllerProvider.notifier)
          .setViewMode(toGrid ? FilesViewMode.grid : FilesViewMode.list),
    );
  }
}

/// Sort icon button inside the search field.
class _FilesSortIcon extends ConsumerWidget {
  const _FilesSortIcon({required this.sort});

  final FilesSort sort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FilesMenu(
      endAlignedWidth: 160,
      items: [
        for (final s in FilesSort.values)
          FilesMenuItem(
            s.label,
            () => ref.read(filesControllerProvider.notifier).setSort(s),
            checked: s == sort,
          ),
      ],
      builder: (context, open) => CruIconButton(
        icon: FileIcons.sort,
        size: cruIsPhone(context) ? CruSize.searchToolPhone : CruSize.capsule,
        iconSize: cruIsPhone(context) ? CruSize.searchToolIconPhone : 16,
        semanticLabel: 'Sort: ${sort.label}',
        tooltip: 'Sort: ${sort.label}',
        onPressed: open,
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
  const FilesChips({super.key, required this.view, this.showPatient = true});

  final FilesView view;

  /// False on phones, where the patient shows in the top banner instead.
  final bool showPatient;

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
          if (showPatient && view.patientFilterName != null)
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
      onWillAcceptWithDetails: (d) =>
          d.data.canManage && d.data.file.folderId != folderId,
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
