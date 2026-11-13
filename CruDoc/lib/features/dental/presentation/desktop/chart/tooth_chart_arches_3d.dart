import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dental/domain/tooth_numbering.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/odontogram_picture_chart.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_data.dart';

/// Odontogram in its "3D" style: both dental arches as a grey clay picture (the
/// odontogram clay picture). Findings tint a tooth and colour its outline.
/// Milk teeth use the vector odontogram.
class ToothChartArches3d extends StatelessWidget {
  const ToothChartArches3d({
    super.key,
    required this.data,
    required this.child,
    required this.selected,
    required this.onSelect,
    this.onOpen,
    this.onDeselect,
    this.layer = ChartLayer.dental,
    this.numbering = ToothNumbering.fdi,
  });

  final ToothChartData data;
  final bool child;
  final String? selected;
  final ValueChanged<String> onSelect;
  final ValueChanged<String>? onOpen;
  final VoidCallback? onDeselect;
  final ChartLayer layer;
  final ToothNumbering numbering;

  @override
  Widget build(BuildContext context) => OdontogramPictureChart(
    art: OdontogramArt.clay3d,
    data: data,
    child: child,
    selected: selected,
    onSelect: onSelect,
    onOpen: onOpen,
    onDeselect: onDeselect,
    layer: layer,
    numbering: numbering,
  );
}
