import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/radiology/cbct/cbct_viewer_screen.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/presentation/fmx_series_view.dart';
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
  if (imageId == null && isFmxSeriesStudy(s)) {
    // A full-mouth series opens in its mount; a film opens from there.
    await Navigator.of(context, rootNavigator: true).push(
      radRoute<void>(FmxSeriesViewScreen(study: s)),
    );
    return;
  }
  await Navigator.of(context, rootNavigator: true).push(
    radRoute<void>(
      RadViewerScreen(studyId: s.id, initialStudy: s, initialImageId: imageId),
    ),
  );
}

/// Opens (or starts) the study's report.
Future<void> openRadReport(BuildContext context, RadStudy s) => Navigator.of(
  context,
  rootNavigator: true,
).push(radRoute<void>(RadReportEditorScreen(studyId: s.id)));

/// Opens a CBCT study in the 3D viewer: a 320 ms fade with the page growing
/// from 98.5 % to full size (fade only for reduced motion).
Future<void> openRadCbct3d(BuildContext context, RadStudy s) {
  final reduced = MediaQuery.disableAnimationsOf(context);
  final dur = reduced
      ? const Duration(milliseconds: 80)
      : const Duration(milliseconds: 320);
  return Navigator.of(
    context,
    rootNavigator: true,
  ).push(
    PageRouteBuilder<void>(
      transitionDuration: dur,
      reverseTransitionDuration: dur,
      pageBuilder: (_, _, _) => Consumer(
        builder: (context, ref, _) => Theme(
          data: CruTheme.of(ref.watch(resolvedAppearanceProvider)),
          child: CbctViewerScreen(studyId: s.id),
        ),
      ),
      transitionsBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        final fade = FadeTransition(opacity: curved, child: child);
        if (MediaQuery.disableAnimationsOf(context)) {
          return fade;
        }
        return ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
          child: fade,
        );
      },
    ),
  );
}
