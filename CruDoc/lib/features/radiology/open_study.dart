import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/radiology/cbct/cbct_viewer_screen.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/presentation/reports/report_editor_screen.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_screen.dart';
import 'package:doctor_management_app/features/settings/data/appearance_provider.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// A full-screen radiology page in the app's colours (Day or Evening).
Route<T> radRoute<T>(Widget page) => MaterialPageRoute<T>(
      builder: (_) => Consumer(
        builder: (context, ref, _) => Theme(
          data: CruTheme.of(ref.watch(resolvedAppearanceProvider)),
          child: page,
        ),
      ),
    );

/// Opens a study in the viewer (CBCT slices page through as a stack).
/// Marks a new study as being read.
Future<void> openRadStudy(
  BuildContext context,
  WidgetRef ref,
  RadStudy s, {
  String? imageId,
}) async {
  unawaited(ref.read(radiologyProvider).openedStudy(s));
  await Navigator.of(context, rootNavigator: true)
      .push(radRoute<void>(RadViewerScreen(studyId: s.id, initialImageId: imageId)));
}

/// Opens (or starts) the study's report.
Future<void> openRadReport(BuildContext context, RadStudy s) =>
    Navigator.of(context, rootNavigator: true)
        .push(radRoute<void>(RadReportEditorScreen(studyId: s.id)));

/// Opens a CBCT study in the 3D viewer (planned; its page says so and
/// offers the 2D slices meanwhile).
Future<void> openRadCbct3d(BuildContext context, RadStudy s) =>
    Navigator.of(context, rootNavigator: true)
        .push(radRoute<void>(CbctViewerScreen(studyId: s.id)));
