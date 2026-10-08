import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/files/data/file_types.dart';
import 'package:doctor_management_app/features/files/data/files_repository.dart';
import 'package:doctor_management_app/features/files/domain/files_builder.dart';
import 'package:doctor_management_app/features/files/domain/files_models.dart';
import 'package:doctor_management_app/features/files/presentation/files_actions.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/file_thumb.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/files_list.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/files_style.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_item_panel.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The 384 px panel beside (or, below 1200 px, over) the list: the file's
/// preview, who it's for, where it is, and what can be done with it.
class FilePanel extends ConsumerWidget {
  const FilePanel({
    super.key,
    required this.entry,
    required this.now,
    this.onClose,
  });

  final FileEntry entry;
  final DateTime now;

  /// Shown as × when the panel is a sheet (Esc also closes it).
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final f = entry.file;
    final me = FilesRepository.instance.uid;
    final status = f.storagePath.isNotEmpty
        ? 'Saved to the cloud'
        : f.cloudStatus == FileCloudStatus.localOnly
        ? 'On this device only'
        : f.ownerUid == me
        ? 'Uploading…'
        : 'Waiting for the upload from the device it was added on';

    final blocks = <Widget>[
      _Head(
        eyebrow: f.kind.label.replaceFirst(RegExp(r's$'), ''),
        title: f.name,
        subtitle:
            'Added ${FilesBuilder.dateLabel(f.createdAt, now)} · '
            '${PatientFileTypes.sizeLabel(f.sizeBytes)}',
        onClose: onClose,
      ),
      LayoutBuilder(
        builder: (context, box) => FileThumb(
          key: ValueKey(f.id),
          file: f,
          width: box.maxWidth,
          height: FilesSize.panelPreview,
          radius: CruRadius.strip,
        ),
      ),
      _Facts(
        rows: [
          (
            'Patient',
            CruLink(
              label: entry.patientName,
              onPressed: () =>
                  FilesActions.openPatient(context, ref, f.patientId),
            ),
          ),
          (
            'Folder',
            _value(
              context,
              entry.folderPath.isEmpty ? 'Not in a folder' : entry.folderPath,
            ),
          ),
          (
            'Added by',
            _value(context, entry.addedBy.isEmpty ? 'You' : entry.addedBy),
          ),
          ('Status', _value(context, status)),
        ],
      ),
      CruButton(
        label: 'Open',
        kind: CruButtonKind.inset,
        icon: CruIcons.arrowUpRight,
        expand: true,
        onPressed: () =>
            FilesActions.open(context, f, patientName: entry.patientName),
      ),
      if (entry.canManage)
        Wrap(
          spacing: CruSpace.s8,
          runSpacing: CruSpace.s8,
          children: [
            _Capsule(
              label: 'Move',
              icon: FileIcons.folder,
              onTap: () => FilesActions.moveFile(context, ref, entry),
            ),
            _Capsule(
              label: 'Rename',
              icon: CruIcons.pen,
              onTap: () => FilesActions.renameFile(context, entry),
            ),
            _Capsule(
              label: 'Patient',
              icon: CruIcons.user,
              onTap: () => FilesActions.changePatient(context, entry),
            ),
            _Capsule(
              label: 'Delete',
              icon: FileIcons.trash,
              onTap: () => FilesActions.deleteFile(context, entry),
            ),
          ],
        )
      else
        Text(
          'Only the person who added this file can change it.',
          style: CruType.caption.tint(c.label2),
        ),
    ];

    return InventoryPanelFrame(
      label: f.name,
      child: AnimatedSwitcher(
        duration: CruMotion.of(context, CruMotion.fast),
        switchInCurve: CruMotion.curve,
        switchOutCurve: CruMotion.curve,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [...previous, ?current],
        ),
        child: Column(
          key: ValueKey(f.id),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < blocks.length; i++) ...[
              if (i > 0) const SizedBox(height: CruSpace.s14),
              blocks[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// The open folder, when it has no files to show: what's in it, who it is
/// shared with, and its actions.
class FolderPanel extends ConsumerWidget {
  const FolderPanel({super.key, required this.entry, this.onClose});

  final FolderEntry entry;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = entry.folder;
    final mine = f.ownerUid == FilesRepository.instance.uid;
    final sharing = folderSharingLabel(entry) ?? 'Only you';
    return InventoryPanelFrame(
      label: f.name,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Head(
            eyebrow: 'Folder',
            title: f.name,
            subtitle: folderContentsLabel(entry),
            onClose: onClose,
          ),
          const SizedBox(height: CruSpace.s14),
          _Facts(
            rows: [
              ('Shared', _value(context, sharing)),
              if (!f.isTopLevel)
                ('Sharing', _value(context, 'Follows the folder it is in')),
            ],
          ),
          const SizedBox(height: CruSpace.s14),
          CruButton(
            label: 'Add files here',
            kind: CruButtonKind.inset,
            icon: FileIcons.upload,
            expand: true,
            onPressed: () => FilesActions.pickAndAdd(context, folderId: f.id),
          ),
          const SizedBox(height: CruSpace.s14),
          Wrap(
            spacing: CruSpace.s8,
            runSpacing: CruSpace.s8,
            children: [
              _Capsule(
                label: 'New folder',
                icon: FileIcons.folderPlus,
                onTap: () => FilesActions.newFolder(context, parentId: f.id),
              ),
              if (f.isTopLevel && mine)
                _Capsule(
                  label: 'Share',
                  icon: FileIcons.shared,
                  onTap: () => FilesActions.shareFolder(context, entry),
                ),
              if (entry.canManage) ...[
                _Capsule(
                  label: 'Rename',
                  icon: CruIcons.pen,
                  onTap: () => FilesActions.renameFolder(context, entry),
                ),
                _Capsule(
                  label: 'Delete',
                  icon: FileIcons.trash,
                  onTap: () => FilesActions.deleteFolder(context, ref, entry),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Loading placeholder with the panel's proportions.
class FilesPanelSkeleton extends StatelessWidget {
  const FilesPanelSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return InventoryPanelFrame(
      label: 'Loading file',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(width: 80, height: 12),
          const SizedBox(height: CruSpace.s10),
          const SkeletonBox(width: 220, height: 20),
          const SizedBox(height: CruSpace.s8),
          const SkeletonBox(width: 160, height: 12),
          const SizedBox(height: CruSpace.s14),
          Container(
            height: FilesSize.panelPreview,
            decoration: ShapeDecoration(
              color: c.inset,
              shape: cruShape(CruRadius.strip),
            ),
          ),
          const SizedBox(height: CruSpace.s14),
          const SkeletonBox(width: 200, height: 14),
          const SizedBox(height: CruSpace.s8),
          const SkeletonBox(width: 180, height: 14),
          const SizedBox(height: CruSpace.s14),
          const SkeletonBox(height: CruSize.control),
        ],
      ),
    );
  }
}

Widget _value(BuildContext context, String text) => Text(
  text,
  style: CruType.text.tint(context.cru.label),
  maxLines: 2,
  overflow: TextOverflow.ellipsis,
);

class _Head extends StatelessWidget {
  const _Head({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(eyebrow, style: CruType.caption.w600.tint(c.label2)),
              const SizedBox(height: CruSpace.s4),
              Text(
                title,
                style: CruType.title.tint(c.label),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: CruSpace.s2),
              Text(subtitle, style: CruType.subhead.tabular.tint(c.label2)),
            ],
          ),
        ),
        if (onClose != null) ...[
          const SizedBox(width: CruSpace.s8),
          CruIconButton(
            icon: CruIcons.close,
            size: CruSize.capsule,
            iconSize: 16,
            semanticLabel: 'Close',
            tooltip: 'Close (Esc)',
            onPressed: onClose,
          ),
        ],
      ],
    );
  }
}

/// Label / value pairs on an inset strip.
class _Facts extends StatelessWidget {
  const _Facts({required this.rows});

  final List<(String, Widget)> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      padding: const EdgeInsets.all(CruSpace.s14),
      decoration: ShapeDecoration(
        color: c.inset,
        shape: cruShape(CruRadius.strip),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: CruSpace.s10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 76,
                  child: Text(
                    rows[i].$1,
                    style: CruType.subhead.w500.tint(c.label2),
                  ),
                ),
                const SizedBox(width: CruSpace.s8),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: rows[i].$2,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A small list action.
class _Capsule extends StatelessWidget {
  const _Capsule({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final CruIconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) =>
      CruCapsuleButton(label: label, icon: icon, onPressed: onTap);
}
