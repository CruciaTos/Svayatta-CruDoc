import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dental/domain/tooth_numbering.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/odontogram_picture_chart.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_data.dart';

/// Odontogram in its "2D" style: both dental arches as black line art (the
/// odontogram line picture). Findings fill a tooth with a soft colour under
/// the lines. Milk teeth use the vector odontogram.
class ToothChartArches extends StatelessWidget {
  const ToothChartArches({
    super.key,
    required this.data,
    required this.child,
    required this.selected,
    required this.onSelect,
    this.onOpen,
    this.layer = ChartLayer.dental,
    this.numbering = ToothNumbering.fdi,
  });

  final ToothChartData data;
  final bool child;
  final String? selected;
  final ValueChanged<String> onSelect;
  final ValueChanged<String>? onOpen;
  final ChartLayer layer;
  final ToothNumbering numbering;

  @override
  Widget build(BuildContext context) => OdontogramPictureChart(
    art: OdontogramArt.line2d,
    data: data,
    child: child,
    selected: selected,
    onSelect: onSelect,
    onOpen: onOpen,
    layer: layer,
    numbering: numbering,
  );
}
