import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/files/data/files_providers.dart';
import 'package:doctor_management_app/features/files/data/files_repository.dart';
import 'package:doctor_management_app/features/files/domain/files_builder.dart';
import 'package:doctor_management_app/features/files/domain/files_models.dart';
import 'package:doctor_management_app/features/files/presentation/files_actions.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/file_thumb.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/files_bars.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/files_style.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

typedef FileEntryTap = void Function(FileEntry entry);

String _plural(int n, String one) => n == 1 ? '1 $one' : '$n ${one}s';

/// "3 files · 1 folder", "Empty".
String folderContentsLabel(FolderEntry f) {
  final parts = [
    if (f.folders > 0) _plural(f.folders, 'folder'),
    if (f.files > 0) _plural(f.files, 'file'),
  ];
  return parts.isEmpty ? 'Empty' : parts.join(' · ');
}

/// "Shared with the clinic", "Shared by Dr Rao", or null when private.
String? folderSharingLabel(FolderEntry f) {
  if (f.ownerName.isNotEmpty) return 'Shared by ${f.ownerName}';
  if (!f.folder.isShared) return null;
  return f.folder.sharing == FolderSharing.team
      ? 'Shared with the clinic'
      : 'Shared with ${_plural(f.folder.sharedWith.length, 'doctor')}';
}

/// The actions a file row offers (⋯ and right-click).
List<FilesMenuItem> fileMenuItems(
  BuildContext context,
  WidgetRef ref,
  FileEntry e,
) => [
  FilesMenuItem(
    'Open',
    () => FilesActions.open(context, e.file, patientName: e.patientName),
  ),
  FilesMenuItem(
    'Open patient',
    () => FilesActions.openPatient(context, ref, e.file.patientId),
  ),
  if (e.canManage) ...[
    FilesMenuItem('Move to…', () => FilesActions.moveFile(context, ref, e)),
    FilesMenuItem(
      'Change patient…',
      () => FilesActions.changePatient(context, e),
    ),
    FilesMenuItem('Rename…', () => FilesActions.renameFile(context, e)),
    FilesMenuItem('Delete…', () => FilesActions.deleteFile(context, e)),
  ],
];

/// The actions a folder row offers.
List<FilesMenuItem> folderMenuItems(
  BuildContext context,
  WidgetRef ref,
  FolderEntry f,
) {
  final mine = f.folder.ownerUid == FilesRepository.instance.uid;
  return [
    FilesMenuItem(
      'Open',
      () => ref.read(filesControllerProvider.notifier).openFolder(f.id),
    ),
    FilesMenuItem(
      'New folder inside…',
      () => FilesActions.newFolder(context, parentId: f.id),
    ),
    if (f.folder.isTopLevel && mine)
      FilesMenuItem('Share…', () => FilesActions.shareFolder(context, f)),
    if (f.canManage) ...[
      FilesMenuItem('Move to…', () => FilesActions.moveFolder(context, ref, f)),
      FilesMenuItem('Rename…', () => FilesActions.renameFolder(context, f)),
      FilesMenuItem(
        'Delete…',
        () => FilesActions.deleteFolder(context, ref, f),
      ),
    ],
  ];
}

/// ⋯ as a small capsule; right-click on [child] opens the same menu where
/// the pointer is.
class _RowMenu extends StatefulWidget {
  const _RowMenu({required this.items, required this.child});

  final List<FilesMenuItem> items;
  final Widget Function(BuildContext context, Widget menuButton) child;

  @override
  State<_RowMenu> createState() => _RowMenuState();
}

class _RowMenuState extends State<_RowMenu> {
  final MenuController _menu = MenuController();
  final GlobalKey _buttonKey = GlobalKey(debugLabel: 'row menu');

  @override
  Widget build(BuildContext context) {
    final button = FilesMenu(
      controller: _menu,
      items: widget.items,
      builder: (context, open) => CruIconButton(
        icon: CruIcons.more,
        size: CruSize.capsule,
        iconSize: 18,
        semanticLabel: 'More actions',
        tooltip: 'More',
        onPressed: open,
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: (d) {
        // The menu is anchored on the ⋯ button; place it at the pointer.
        final anchor = _buttonKey.currentContext?.findRenderObject();
        if (anchor is RenderBox && anchor.attached) {
          _menu.open(position: anchor.globalToLocal(d.globalPosition));
        } else {
          _menu.open();
        }
      },
      child: widget.child(
        context,
        KeyedSubtree(key: _buttonKey, child: button),
      ),
    );
  }
}

/// Lets a file row be dragged onto a folder (long-press on touch screens).
class _DraggableFile extends StatelessWidget {
  const _DraggableFile({required this.entry, required this.child});

  final FileEntry entry;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!entry.canManage) return child;
    final c = context.cru;
    final feedback = Material(
      color: c.surface.withValues(alpha: 0),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: CruSpace.s12,
          vertical: CruSpace.s8,
        ),
        decoration: ShapeDecoration(
          color: c.surface,
          shape: cruShape(
            CruRadius.control,
            side: BorderSide(color: c.hairline),
          ),
          shadows: [
            BoxShadow(
              color: c.label.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CruIcon(
              fileKindIcon(entry.file.kind),
              size: 18,
              strokeWidth: 1.9,
              color: c.label2,
            ),
            const SizedBox(width: CruSpace.s8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(
                entry.file.name,
                style: CruType.text.w500.tint(c.label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
    final touch =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final faded = Opacity(opacity: 0.4, child: child);
    return touch
        ? LongPressDraggable<FileEntry>(
            data: entry,
            feedback: feedback,
            childWhenDragging: faded,
            child: child,
          )
        : Draggable<FileEntry>(
            data: entry,
            feedback: feedback,
            childWhenDragging: faded,
            child: child,
          );
  }
}

/// List view: one card with Name / Patient / Folder / Added columns,
/// folders first (Folders tab), 64 px rows and "Showing N of M".
class FilesList extends ConsumerWidget {
  const FilesList({
    super.key,
    required this.view,
    required this.tab,
    required this.selectedId,
    required this.onTap,
    this.selectedKey,
    this.empty,
  });

  final FilesView view;
  final FilesTab tab;
  final String? selectedId;
  final FileEntryTap onTap;
  final GlobalKey? selectedKey;
  final Widget? empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final rows = view.visible;
    final folders = view.folders;
    final thirdLabel = tab == FilesTab.recent ? 'Folder' : 'Added by';
    final children = <Widget>[
      _Columns(
        height: CruSize.tableHeader,
        name: _header(context, 'Name'),
        patient: _header(context, 'Patient'),
        third: _header(context, thirdLabel),
        date: _header(context, 'Added'),
        trailing: const SizedBox.shrink(),
      ),
      const CruSeparator(),
      const SizedBox(height: CruSpace.s6),
    ];
    var index = 0;
    void separate(bool hideSeparator) {
      if (index++ == 0) return;
      children.add(
        Opacity(
          opacity: hideSeparator ? 0 : 1,
          child: const CruSeparator(
            indent: CruSize.patientTextInset,
            endIndent: CruSpace.s16,
          ),
        ),
      );
    }

    for (final f in folders) {
      separate(false);
      children.add(_FolderRow(entry: f));
    }
    if (rows.isEmpty && folders.isEmpty && empty != null) children.add(empty!);
    String? prev;
    for (final e in rows) {
      final selected = e.id == selectedId;
      separate(selected || prev == selectedId);
      prev = e.id;
      final row = _FileRow(
        entry: e,
        now: view.now,
        tab: tab,
        selected: selected,
        onTap: () => onTap(e),
      );
      children.add(
        selected && selectedKey != null
            ? KeyedSubtree(key: selectedKey, child: row)
            : row,
      );
    }
    if (rows.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(
            CruSpace.s16,
            CruSpace.s14,
            CruSpace.s16,
            CruSpace.s4,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Showing ${rows.length} of ${view.rows.length}',
                  style: CruType.subhead.tabular.tint(c.label3),
                ),
              ),
              if (rows.length < view.rows.length)
                Text('Scroll for more', style: CruType.subhead.tint(c.label3)),
            ],
          ),
        ),
      );
    }

    return CruCard(
      semanticLabel: 'Files',
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s12,
        CruSpace.s6,
        CruSpace.s12,
        CruSpace.s12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _header(BuildContext context, String text) => Text(
    text,
    style: CruType.caption.w600.tint(context.cru.accentText),
    maxLines: 1,
  );
}

/// The fixed column grid shared by the header and rows.
class _Columns extends StatelessWidget {
  const _Columns({
    required this.height,
    required this.name,
    required this.patient,
    required this.third,
    required this.date,
    required this.trailing,
  });

  final double height;
  final Widget name;
  final Widget patient;
  final Widget third;
  final Widget date;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(width: FilesSize.columnGap);
    final width = MediaQuery.sizeOf(context).width;
    if (cruIsPhone(context)) {
      // Phone: the name with patient and date under it.
      return SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s8),
          child: Row(
            children: [
              Expanded(child: name),
              const SizedBox(width: CruSpace.s8),
              SizedBox(width: CruSize.capsule, child: trailing),
            ],
          ),
        ),
      );
    }
    // Narrow desktop: the third column goes first.
    final showThird = width >= CruBreakpoint.splitPane - 200;
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s16),
        child: Row(
          children: [
            Expanded(child: name),
            gap,
            SizedBox(width: FilesSize.patientColumn, child: patient),
            if (showThird) ...[
              gap,
              SizedBox(width: FilesSize.folderColumn, child: third),
            ],
            gap,
            SizedBox(width: FilesSize.dateColumn, child: date),
            const SizedBox(width: CruSpace.s8),
            SizedBox(width: CruSize.capsule, child: trailing),
          ],
        ),
      ),
    );
  }
}

class _RowShell extends StatelessWidget {
  const _RowShell({
    required this.selected,
    required this.onTap,
    required this.semanticLabel,
    required this.child,
  });

  final bool selected;
  final VoidCallback onTap;
  final String semanticLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Semantics(
      selected: selected,
      child: CruPressable(
        onTap: onTap,
        scaleOnPress: false,
        semanticLabel: semanticLabel,
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          height: CruSize.tableRow,
          decoration: ShapeDecoration(
            color: selected
                ? c.accentWash
                : (hovered ? c.hoverFill : c.hoverFill.withValues(alpha: 0)),
            shape: cruShape(CruRadius.control),
          ),
          // The ring is a foreground so it never changes the padding.
          foregroundDecoration: ShapeDecoration(
            shape: cruShape(
              CruRadius.control,
              side: BorderSide(
                color: selected ? c.accent : c.accent.withValues(alpha: 0),
                width: FilesSize.rowRing,
              ),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

Widget _twoLines(
  BuildContext context,
  String top,
  String? bottom, {
  TextStyle? topStyle,
}) {
  final c = context.cru;
  return Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        top,
        style: topStyle ?? CruType.row.tint(c.label),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      if (bottom != null && bottom.isNotEmpty)
        Text(
          bottom,
          style: CruType.subhead.tint(c.label2),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
    ],
  );
}

/// One 64 px file row. Tap opens the file.
class _FileRow extends ConsumerWidget {
  const _FileRow({
    required this.entry,
    required this.now,
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final FileEntry entry;
  final DateTime now;
  final FilesTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final f = entry.file;
    final date = FilesBuilder.dateLabel(f.createdAt, now);
    final phone = cruIsPhone(context);
    final dash = Text('—', style: CruType.text.tint(c.label3));
    final third = tab == FilesTab.recent
        ? entry.folderPath
        : (entry.addedBy.isEmpty ? 'You' : entry.addedBy);

    final nameCell = Row(
      children: [
        FileThumb(file: f),
        const SizedBox(width: CruSpace.s12),
        Expanded(
          child: _twoLines(
            context,
            f.name,
            phone ? '${entry.patientName} · $date' : FilesBuilder.typeLabel(f),
          ),
        ),
      ],
    );

    return _DraggableFile(
      entry: entry,
      child: _RowMenu(
        items: fileMenuItems(context, ref, entry),
        child: (context, menu) => _RowShell(
          selected: selected,
          onTap: onTap,
          semanticLabel:
              '${f.name}, ${entry.patientName}, added $date. Opens the file',
          child: _Columns(
            height: CruSize.tableRow,
            name: nameCell,
            patient: Text(
              entry.patientName,
              style: CruType.text.w500.tint(c.label),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            third: third.isEmpty
                ? dash
                : Text(
                    third,
                    style: CruType.text.tint(c.label2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
            date: Text(
              date,
              style: CruType.text.tabular.tint(c.label),
              maxLines: 1,
            ),
            trailing: menu,
          ),
        ),
      ),
    );
  }
}

/// A folder row: tap opens it; drop a file on it to move the file in.
class _FolderRow extends ConsumerWidget {
  const _FolderRow({required this.entry});

  final FolderEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final sharing = folderSharingLabel(entry);
    final dash = Text('—', style: CruType.text.tint(c.label3));
    return FileDropTarget(
      folderId: entry.id,
      child: _RowMenu(
        items: folderMenuItems(context, ref, entry),
        child: (context, menu) => _RowShell(
          selected: false,
          onTap: () =>
              ref.read(filesControllerProvider.notifier).openFolder(entry.id),
          semanticLabel:
              'Folder ${entry.folder.name}, ${folderContentsLabel(entry)}',
          child: _Columns(
            height: CruSize.tableRow,
            name: Row(
              children: [
                FolderTile(shared: entry.folder.isShared),
                const SizedBox(width: CruSpace.s12),
                Expanded(
                  child: _twoLines(
                    context,
                    entry.folder.name,
                    cruIsPhone(context) && sharing != null
                        ? '${folderContentsLabel(entry)} · $sharing'
                        : folderContentsLabel(entry),
                  ),
                ),
              ],
            ),
            patient: dash,
            third: sharing == null
                ? dash
                : Text(
                    sharing,
                    style: CruType.text.tint(c.tealText),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
            date: dash,
            trailing: menu,
          ),
        ),
      ),
    );
  }
}

/// Grid view: tiles with a picture preview (when this device has the
/// picture), the name, the patient and the date. Folders first.
class FilesGrid extends ConsumerWidget {
  const FilesGrid({
    super.key,
    required this.view,
    required this.selectedId,
    required this.onTap,
    this.selectedKey,
    this.empty,
  });

  final FilesView view;
  final String? selectedId;
  final FileEntryTap onTap;
  final GlobalKey? selectedKey;
  final Widget? empty;

  static int columnsFor(double width) => width >= FilesSize.gridFourColumns
      ? 4
      : width >= FilesSize.gridThreeColumns
      ? 3
      : 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final items = view.visible;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = columnsFor(constraints.maxWidth);
        final tiles = <Widget>[
          for (final f in view.folders) _FolderTileCard(entry: f),
          for (final e in items)
            e.id == selectedId && selectedKey != null
                ? KeyedSubtree(
                    key: selectedKey,
                    child: _FileTile(
                      entry: e,
                      now: view.now,
                      selected: true,
                      onTap: () => onTap(e),
                    ),
                  )
                : _FileTile(
                    entry: e,
                    now: view.now,
                    selected: e.id == selectedId,
                    onTap: () => onTap(e),
                  ),
        ];
        final rows = <Widget>[];
        for (var start = 0; start < tiles.length; start += columns) {
          if (start > 0) rows.add(const SizedBox(height: FilesSize.tileGap));
          rows.add(
            SizedBox(
              height: FilesSize.tileHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = start; i < start + columns; i++) ...[
                    if (i > start) const SizedBox(width: FilesSize.tileGap),
                    Expanded(
                      child: i < tiles.length
                          ? tiles[i]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (tiles.isEmpty && empty != null)
              CruCard(
                semanticLabel: 'Files',
                padding: const EdgeInsets.all(CruSpace.s12),
                child: empty!,
              )
            else
              Semantics(
                container: true,
                label: 'Files',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: rows,
                ),
              ),
            if (items.isNotEmpty) ...[
              const SizedBox(height: CruSpace.s16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: CruSpace.s4),
                child: Text(
                  'Showing ${items.length} of ${view.rows.length}',
                  textAlign: TextAlign.end,
                  style: CruType.subhead.tabular.tint(c.label3),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _TileShell extends StatelessWidget {
  const _TileShell({
    required this.selected,
    required this.onTap,
    required this.semanticLabel,
    required this.child,
  });

  final bool selected;
  final VoidCallback onTap;
  final String semanticLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Semantics(
      selected: selected,
      child: CruPressable(
        onTap: onTap,
        semanticLabel: semanticLabel,
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          padding: const EdgeInsets.all(CruSpace.s12),
          decoration: ShapeDecoration(
            color: selected
                ? c.accentWash
                : (hovered ? cruHoverShade(c.surface, c) : c.surface),
            shape: cruShape(FilesSize.tileRadius),
            shadows: const [],
          ),
          foregroundDecoration: ShapeDecoration(
            shape: cruShape(
              FilesSize.tileRadius,
              side: selected
                  ? BorderSide(color: c.accent, width: FilesSize.tileRing)
                  : BorderSide(color: c.hairline),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _FileTile extends ConsumerWidget {
  const _FileTile({
    required this.entry,
    required this.now,
    required this.selected,
    required this.onTap,
  });

  final FileEntry entry;
  final DateTime now;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = entry.file;
    final date = FilesBuilder.dateLabel(f.createdAt, now);
    return _DraggableFile(
      entry: entry,
      child: _RowMenu(
        items: fileMenuItems(context, ref, entry),
        child: (context, menu) => _TileShell(
          selected: selected,
          onTap: onTap,
          semanticLabel: '${f.name}, ${entry.patientName}, added $date',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, box) => FileThumb(
                  file: f,
                  width: box.maxWidth,
                  height: FilesSize.tilePreview,
                  radius: FilesSize.tileRadius - CruSpace.s12,
                ),
              ),
              const SizedBox(height: CruSpace.s10),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _twoLines(
                        context,
                        f.name,
                        '${entry.patientName} · $date',
                        topStyle: CruType.callout.tint(context.cru.label),
                      ),
                    ),
                    menu,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderTileCard extends ConsumerWidget {
  const _FolderTileCard({required this.entry});

  final FolderEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final sharing = folderSharingLabel(entry);
    return FileDropTarget(
      folderId: entry.id,
      child: _RowMenu(
        items: folderMenuItems(context, ref, entry),
        child: (context, menu) => _TileShell(
          selected: false,
          onTap: () =>
              ref.read(filesControllerProvider.notifier).openFolder(entry.id),
          semanticLabel: 'Folder ${entry.folder.name}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: FilesSize.tilePreview,
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: entry.folder.isShared ? c.tealTint : c.inset,
                  shape: cruShape(FilesSize.tileRadius - CruSpace.s12),
                ),
                child: CruIcon(
                  FileIcons.folder,
                  size: 40,
                  strokeWidth: 1.5,
                  color: entry.folder.isShared ? c.tealText : c.label3,
                ),
              ),
              const SizedBox(height: CruSpace.s10),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _twoLines(
                        context,
                        entry.folder.name,
                        sharing ?? folderContentsLabel(entry),
                        topStyle: CruType.callout.tint(c.label),
                      ),
                    ),
                    menu,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The list card while files load: same header and 64 px rows, so nothing
/// shifts when they arrive. Phone rows drop the columns, like the list.
class FilesListSkeleton extends StatelessWidget {
  const FilesListSkeleton({super.key, this.rows = 7});

  final int rows;

  @override
  Widget build(BuildContext context) {
    final phone = cruIsPhone(context);
    return Semantics(
      label: 'Loading files',
      child: CruCard(
        padding: const EdgeInsets.fromLTRB(
          CruSpace.s12,
          CruSpace.s6,
          CruSpace.s12,
          CruSpace.s12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(
              height: CruSize.tableHeader,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: CruSpace.s16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SkeletonBox(width: 64, height: 10),
                ),
              ),
            ),
            const CruSeparator(),
            const SizedBox(height: CruSpace.s6),
            for (var i = 0; i < rows; i++)
              SizedBox(
                height: CruSize.tableRow,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: CruSpace.s16),
                  child: Row(
                    children: [
                      const SkeletonBox(
                        width: CruSize.iconTile,
                        height: CruSize.iconTile,
                      ),
                      const SizedBox(width: CruSpace.s12),
                      const Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(width: 160, height: 12),
                            SizedBox(height: CruSpace.s8),
                            SkeletonBox(width: 96, height: 10),
                          ],
                        ),
                      ),
                      if (!phone) ...const [
                        SizedBox(width: FilesSize.columnGap),
                        SizedBox(
                          width: FilesSize.patientColumn,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SkeletonBox(width: 120, height: 12),
                          ),
                        ),
                        SizedBox(width: FilesSize.columnGap),
                        SizedBox(
                          width: FilesSize.dateColumn,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SkeletonBox(width: 64, height: 12),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
