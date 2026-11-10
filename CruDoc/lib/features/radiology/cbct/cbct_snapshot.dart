import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';

final _snapName = RegExp(r'^snap_\d{1,9}\.png$');

/// Moves the page's snapshot `{packDir}/[file]` into the study as a key
/// image named `cbct.<view>` and shows a short confirmation.
///
/// The 2D viewer's key-image writer renders a 2D pane, which a 3D snapshot
/// doesn't have, so this does the smallest equivalent: the PNG goes to
/// `keys/<id>.png` in the study folder, a [RadKeyImage] is appended and the
/// study is saved through the same controller (with the same audit entry).
Future<void> saveCbctSnapshot({
  required BuildContext context,
  required WidgetRef ref,
  required String studyId,
  required Directory packDir,
  required String file,
  required String view,
}) async {
  try {
    if (!_snapName.hasMatch(file)) return;
    final src = File(p.join(packDir.path, file));
    if (!await src.exists()) return;
    final ctl = ref.read(radiologyProvider);
    final study = await ref.read(radStudyProvider(studyId).future);
    if (study == null) return;
    final id = radId('key_');
    final rel = 'keys/$id.png';
    final dir = await ctl.studyDir(study.id);
    final dest = File(p.join(dir.path, rel));
    await dest.parent.create(recursive: true);
    try {
      await src.rename(dest.path);
    } on FileSystemException {
      await src.copy(dest.path);
      await src.delete();
    }
    final safeView = view.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    final key = RadKeyImage(
      id: id,
      imageId: 'cbct.$safeView',
      pngPath: rel,
      createdAt: DateTime.now(),
    );
    final latest = await ref.read(radStudyProvider(studyId).future) ?? study;
    await ctl.saveStudy(
      latest.copyWith(keyImages: [...latest.keyImages, key]),
      auditAction: 'Marked key image',
      detail: '${study.modality == RadModality.cbct ? "CBCT" : "3D"} $safeView',
    );
    if (context.mounted) radToast(context, 'Saved key image');
  } on Object catch (e) {
    debugPrint('[cbct] snapshot failed: $e');
    if (context.mounted) radToast(context, "Couldn't save the key image");
  }
}
