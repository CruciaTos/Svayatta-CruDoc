import 'dart:io';

import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/files/data/file_types.dart';
import 'package:doctor_management_app/features/files/data/files_repository.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/files_style.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// A file's picture when this device has it, else its kind's icon tile.
/// Never downloads: a picture added on another computer shows its icon
/// until it is opened here once.
class FileThumb extends StatefulWidget {
  const FileThumb({
    super.key,
    required this.file,
    this.width = CruSize.iconTile,
    this.height = CruSize.iconTile,
    this.radius = CruRadius.iconTile,
  });

  final PatientFile file;
  final double width;
  final double height;
  final double radius;

  @override
  State<FileThumb> createState() => _FileThumbState();
}

class _FileThumbState extends State<FileThumb> {
  Future<File?>? _local;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(FileThumb old) {
    super.didUpdateWidget(old);
    if (old.file.id != widget.file.id ||
        old.file.localPath != widget.file.localPath) {
      _load();
    }
  }

  void _load() {
    _local = PatientFileTypes.isViewableImage(widget.file.contentType)
        ? FilesRepository.instance.existingLocalCopy(widget.file)
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final icon = _IconBox(
      kind: widget.file.kind,
      width: widget.width,
      height: widget.height,
      radius: widget.radius,
    );
    final future = _local;
    if (future == null) return icon;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return FutureBuilder<File?>(
      future: future,
      builder: (context, snap) {
        final file = snap.data;
        if (file == null) return icon;
        return ClipRSuperellipse(
          borderRadius: BorderRadius.circular(widget.radius),
          child: Image.file(
            file,
            width: widget.width,
            height: widget.height,
            fit: BoxFit.cover,
            cacheWidth: (widget.width * dpr).round(),
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => icon,
          ),
        );
      },
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox({
    required this.kind,
    required this.width,
    required this.height,
    required this.radius,
  });

  final FileKind kind;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (width == CruSize.iconTile && height == CruSize.iconTile) {
      return CruIconTile(icon: fileKindIcon(kind), tone: CruTileTone.neutral);
    }
    final c = context.cru;
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: ShapeDecoration(color: c.inset, shape: cruShape(radius)),
      child: CruIcon(
        fileKindIcon(kind),
        size: 32,
        strokeWidth: 1.6,
        color: c.label3,
      ),
    );
  }
}

/// A folder's icon tile: teal when shared, so shared folders stand out.
class FolderTile extends StatelessWidget {
  const FolderTile({super.key, required this.shared});

  final bool shared;

  @override
  Widget build(BuildContext context) => CruIconTile(
    icon: FileIcons.folder,
    tone: shared ? CruTileTone.teal : CruTileTone.neutral,
  );
}
