import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_doctors_provider.dart';
import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/files/data/files_repository.dart';
import 'package:doctor_management_app/features/files/domain/files_builder.dart';
import 'package:doctor_management_app/features/files/domain/files_models.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/files_style.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// A name for a new folder, or a new name for a file or folder. Returns
/// the name, or null when cancelled.
Future<String?> showFilesNameDialog(
  BuildContext context, {
  required String title,
  required String submitLabel,
  String initial = '',
  CruIconData icon = FileIcons.folder,
}) => showDialog<String>(
  context: context,
  builder: (_) => _NameDialog(
    title: title,
    submitLabel: submitLabel,
    initial: initial,
    icon: icon,
  ),
);

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.submitLabel,
    required this.initial,
    required this.icon,
  });

  final String title;
  final String submitLabel;
  final String initial;
  final CruIconData icon;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial,
  );
  String? _notice;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final name = FilesRepository.cleanName(_text.text);
    if (name.isEmpty) {
      setState(() => _notice = 'Type a name.');
      return;
    }
    if (name.length > 120) {
      setState(() => _notice = 'Keep the name under 120 characters.');
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return CruFormDialog(
      title: widget.title,
      leading: CruIconTile(icon: widget.icon, tone: CruTileTone.neutral),
      submitLabel: widget.submitLabel,
      onSubmit: _save,
      notice: _notice,
      dirty: _text.text != widget.initial,
      width: CruSize.dialog + 60,
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: CruSpace.s12),
        child: CruTextField(
          label: 'Name',
          controller: _text,
          autofocus: true,
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _save(),
        ),
      ),
    );
  }
}

/// "Delete …?" with Cancel and Delete. True when confirmed.
Future<bool> confirmFilesDelete(
  BuildContext context, {
  required String title,
  required String body,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => CruFormDialog(
      title: title,
      leading: const CruIconTile(
        icon: FileIcons.trash,
        tone: CruTileTone.neutral,
      ),
      submitLabel: 'Delete',
      onSubmit: () => Navigator.of(ctx).pop(true),
      width: CruSize.dialog + 60,
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: CruSpace.s12),
        child: Text(body, style: CruType.text.tint(ctx.cru.label2)),
      ),
    ),
  );
  return ok == true;
}

/// Picks a folder to move into. Returns the folder id ('' for no folder),
/// or null when cancelled. [exclude] (a folder being moved) and the folders
/// inside it are left out.
Future<String?> showMoveToFolderDialog(
  BuildContext context, {
  required List<FolderEntry> folders,
  required String currentFolderId,
  required String title,
  String? exclude,
  bool allowNone = true,
}) => showDialog<String>(
  context: context,
  builder: (_) => _MoveDialog(
    folders: folders,
    current: currentFolderId,
    title: title,
    exclude: exclude,
    allowNone: allowNone,
  ),
);

class _MoveDialog extends StatefulWidget {
  const _MoveDialog({
    required this.folders,
    required this.current,
    required this.title,
    required this.exclude,
    required this.allowNone,
  });

  final List<FolderEntry> folders;
  final String current;
  final String title;
  final String? exclude;
  final bool allowNone;

  @override
  State<_MoveDialog> createState() => _MoveDialogState();
}

class _MoveDialogState extends State<_MoveDialog> {
  late String _choice = widget.current;

  /// [exclude] and everything inside it.
  Set<String> get _excluded {
    final root = widget.exclude;
    if (root == null) return const {};
    final out = {root};
    var grew = true;
    while (grew) {
      grew = false;
      for (final f in widget.folders) {
        if (!out.contains(f.id) && out.contains(f.folder.parentId)) {
          out.add(f.id);
          grew = true;
        }
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final excluded = _excluded;
    final options = [
      if (widget.allowNone) '',
      for (final f in widget.folders)
        if (!excluded.contains(f.id)) f.id,
    ];
    return CruFormDialog(
      title: widget.title,
      leading: const CruIconTile(
        icon: FileIcons.folder,
        tone: CruTileTone.neutral,
      ),
      submitLabel: 'Move here',
      onSubmit: () => Navigator.of(context).pop(_choice),
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: CruSpace.s8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (options.isEmpty)
              Padding(
                padding: const EdgeInsets.all(CruSpace.s8),
                child: Text(
                  'Make a folder first.',
                  style: CruType.text.tint(context.cru.label2),
                ),
              ),
            for (final id in options)
              _ChoiceRow(
                icon: FileIcons.folder,
                label: id.isEmpty
                    ? 'No folder (only you)'
                    : FilesBuilder.pathOf(id, widget.folders),
                detail: id == widget.current ? 'Here now' : null,
                selected: id == _choice,
                onTap: () => setState(() => _choice = id),
              ),
          ],
        ),
      ),
    );
  }
}

/// Who a top-level folder is shared with: only its owner, everyone in the
/// clinic, or chosen doctors. Saves on Share.
Future<void> showShareFolderDialog(
  BuildContext context, {
  required FileFolder folder,
}) => showDialog<void>(
  context: context,
  builder: (_) => _ShareDialog(folder: folder),
);

class _ShareDialog extends ConsumerStatefulWidget {
  const _ShareDialog({required this.folder});

  final FileFolder folder;

  @override
  ConsumerState<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends ConsumerState<_ShareDialog> {
  late FolderSharing _sharing = widget.folder.sharing;
  late final Set<String> _people = widget.folder.sharedWith.toSet();
  bool _saving = false;
  String? _notice;

  Future<void> _save() async {
    if (_sharing == FolderSharing.people && _people.isEmpty) {
      setState(() => _notice = 'Choose at least one doctor.');
      return;
    }
    setState(() {
      _saving = true;
      _notice = null;
    });
    try {
      await FilesRepository.instance.shareFolder(
        widget.folder.id,
        _sharing,
        people: _people,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _saving = false;
        _notice = e is FilesException
            ? e.message
            : "Couldn't share. Try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final me = FilesRepository.instance.uid;
    final doctors = [
      for (final d in ref.watch(clinicDoctorsProvider).value ?? const [])
        if (d.uid != me && d.active) d,
    ];
    return CruFormDialog(
      title: 'Share “${widget.folder.name}”',
      subtitle: 'Folders and files inside it are shared the same way',
      leading: const CruIconTile(
        icon: FileIcons.shared,
        tone: CruTileTone.teal,
      ),
      submitLabel: 'Save',
      onSubmit: _save,
      busy: _saving,
      notice: _notice,
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: CruSpace.s8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final s in FolderSharing.values)
              if (s != FolderSharing.people || doctors.isNotEmpty)
                _ChoiceRow(
                  icon: s == FolderSharing.private
                      ? CruIcons.user
                      : FileIcons.shared,
                  label: s.label,
                  detail: switch (s) {
                    FolderSharing.private => 'Nobody else sees it',
                    FolderSharing.team =>
                      'Anyone in the clinic who may see clinical records',
                    FolderSharing.people => 'Only the doctors you tick',
                  },
                  selected: _sharing == s,
                  onTap: () => setState(() => _sharing = s),
                ),
            if (_sharing == FolderSharing.people) ...[
              const SizedBox(height: CruSpace.s8),
              const CruSeparator(),
              const SizedBox(height: CruSpace.s8),
              for (final d in doctors)
                _ChoiceRow(
                  icon: CruIcons.user,
                  label: d.name.isEmpty ? 'Doctor' : d.name,
                  detail: d.specialty.isEmpty ? null : d.specialty,
                  selected: _people.contains(d.uid),
                  multi: true,
                  onTap: () => setState(
                    () => _people.contains(d.uid)
                        ? _people.remove(d.uid)
                        : _people.add(d.uid),
                  ),
                ),
            ],
            if (doctors.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  CruSpace.s8,
                  CruSpace.s12,
                  CruSpace.s8,
                  0,
                ),
                child: Text(
                  'Add doctors to your clinic in Settings › Team to share '
                  'with them one by one.',
                  style: CruType.caption.tint(c.label2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A row that can be chosen: a radio choice, or a tick when [multi].
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.detail,
    this.multi = false,
  });

  final CruIconData icon;
  final String label;
  final String? detail;
  final bool selected;
  final bool multi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: !multi,
      child: CruPressable(
        onTap: onTap,
        scaleOnPress: false,
        semanticLabel: label,
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          padding: const EdgeInsets.symmetric(
            horizontal: CruSpace.s12,
            vertical: CruSpace.s10,
          ),
          decoration: ShapeDecoration(
            color: selected
                ? c.accentWash
                : (hovered ? c.hoverFill : c.hoverFill.withValues(alpha: 0)),
            shape: cruShape(CruRadius.control),
          ),
          child: Row(
            children: [
              CruIcon(icon, size: 18, strokeWidth: 1.9, color: c.label2),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: (selected ? CruType.text.w600 : CruType.text.w500)
                          .tint(c.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (detail != null)
                      Text(
                        detail!,
                        style: CruType.caption.tint(c.label2),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: CruSpace.s12),
              SizedBox(
                width: 18,
                child: selected
                    ? CruIcon(
                        CruIcons.check,
                        size: 16,
                        strokeWidth: 2.2,
                        color: c.accentText,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
