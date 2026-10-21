import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/files/data/file_types.dart';
import 'package:doctor_management_app/features/files/data/files_repository.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/files_style.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/progressive_picture.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// A file's picture: this device's copy when it has one, else the small
/// thumbnail that syncs with the record, else its kind's icon tile. Never
/// downloads.
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
  Uint8List? _thumb;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(FileThumb old) {
    super.didUpdateWidget(old);
    if (old.file.id != widget.file.id ||
        old.file.localPath != widget.file.localPath ||
        old.file.viewPath != widget.file.viewPath ||
        old.file.thumb != widget.file.thumb) {
      _load();
    }
  }

  void _load() {
    final f = widget.file;
    final repo = FilesRepository.instance;
    _local = PatientFileTypes.isViewableImage(f.contentType)
        ? repo
              .existingLocalCopy(f)
              .then((l) async => l ?? repo.existingViewCopy(f))
        : null;
    _thumb = fileThumbBytes(f);
  }

  @override
  Widget build(BuildContext context) {
    final icon = _IconBox(
      kind: widget.file.kind,
      width: widget.width,
      height: widget.height,
      radius: widget.radius,
    );
    final thumbBytes = _thumb;
    final thumb = thumbBytes == null
        ? icon
        : ClipRSuperellipse(
            borderRadius: BorderRadius.circular(widget.radius),
            child: Image.memory(
              thumbBytes,
              width: widget.width,
              height: widget.height,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => icon,
            ),
          );
    final future = _local;
    if (future == null) return thumb;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return FutureBuilder<File?>(
      future: future,
      builder: (context, snap) {
        final file = snap.data;
        if (file == null) return thumb;
        return ClipRSuperellipse(
          borderRadius: BorderRadius.circular(widget.radius),
          child: Image.file(
            file,
            width: widget.width,
            height: widget.height,
            fit: BoxFit.cover,
            cacheWidth: (widget.width * dpr).round(),
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => thumb,
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
