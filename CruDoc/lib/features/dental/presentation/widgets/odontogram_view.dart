import 'package:flutter/material.dart';
import '../../data/models/tooth_chart_entry_model.dart';

/// Helper to get common anatomical tooth names from FDI 2-digit notation.
String getToothName(String toothNumber) {
  const toothNames = {
    '18': 'Upper Right 3rd Molar (Wisdom)',
    '17': 'Upper Right 2nd Molar',
    '16': 'Upper Right 1st Molar',
    '15': 'Upper Right 2nd Premolar',
    '14': 'Upper Right 1st Premolar',
    '13': 'Upper Right Canine',
    '12': 'Upper Right Lateral Incisor',
    '11': 'Upper Right Central Incisor',
    '21': 'Upper Left Central Incisor',
    '22': 'Upper Left Lateral Incisor',
    '23': 'Upper Left Canine',
    '24': 'Upper Left 1st Premolar',
    '25': 'Upper Left 2nd Premolar',
    '26': 'Upper Left 1st Molar',
    '27': 'Upper Left 2nd Molar',
    '28': 'Upper Left 3rd Molar (Wisdom)',
    '48': 'Lower Right 3rd Molar (Wisdom)',
    '47': 'Lower Right 2nd Molar',
    '46': 'Lower Right 1st Molar',
    '45': 'Lower Right 2nd Premolar',
    '44': 'Lower Right 1st Premolar',
    '43': 'Lower Right Canine',
    '42': 'Lower Right Lateral Incisor',
    '41': 'Lower Right Central Incisor',
    '31': 'Lower Left Central Incisor',
    '32': 'Lower Left Lateral Incisor',
    '33': 'Lower Left Canine',
    '34': 'Lower Left 1st Premolar',
    '35': 'Lower Left 2nd Premolar',
    '36': 'Lower Left 1st Molar',
    '37': 'Lower Left 2nd Molar',
    '38': 'Lower Left 3rd Molar (Wisdom)',
  };
  return toothNames[toothNumber] ?? 'Tooth $toothNumber';
}

/// Interactive FDI-compliant Odontogram (Tooth Chart) Widget.
///
/// Clean, functional visual representation of permanent (32) and primary (20) teeth.
class OdontogramView extends StatefulWidget {
  final List<ToothChartEntryModel> entries;
  final String? selectedToothNumber;
  final ValueChanged<String>? onToothSelected;

  const OdontogramView({
    super.key,
    required this.entries,
    this.selectedToothNumber,
    this.onToothSelected,
  });

  @override
  State<OdontogramView> createState() => _OdontogramViewState();
}

class _OdontogramViewState extends State<OdontogramView> {
  bool _isPrimaryDentition = false;

  // FDI Adult Quadrants
  static const _q1 = ['18', '17', '16', '15', '14', '13', '12', '11'];
  static const _q2 = ['21', '22', '23', '24', '25', '26', '27', '28'];
  static const _q4 = ['48', '47', '46', '45', '44', '43', '42', '41'];
  static const _q3 = ['31', '32', '33', '34', '35', '36', '37', '38'];

  // FDI Pediatric/Primary Quadrants
  static const _q5 = ['55', '54', '53', '52', '51'];
  static const _q6 = ['61', '62', '63', '64', '65'];
  static const _q8 = ['85', '84', '83', '82', '81'];
  static const _q7 = ['71', '72', '73', '74', '75'];

  Map<String, ToothChartEntryModel> get _latestEntryByTooth {
    final map = <String, ToothChartEntryModel>{};
    for (final entry in widget.entries) {
      if (!map.containsKey(entry.toothNumber)) {
        map[entry.toothNumber] = entry;
      }
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final latestMap = _latestEntryByTooth;
    final upperLeft = _isPrimaryDentition ? _q5 : _q1;
    final upperRight = _isPrimaryDentition ? _q6 : _q2;
    final lowerLeft = _isPrimaryDentition ? _q8 : _q4;
    final lowerRight = _isPrimaryDentition ? _q7 : _q3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top Toolbar: Dentition Mode Toggle
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _isPrimaryDentition ? 'Primary Dentition (20 Teeth)' : 'Permanent Dentition (32 Teeth)',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Adult')),
                  ButtonSegment(value: true, label: Text('Pediatric')),
                ],
                selected: {_isPrimaryDentition},
                onSelectionChanged: (set) {
                  setState(() => _isPrimaryDentition = set.first);
                },
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 6),

        // Upper Arch (Maxilla)
        _buildArchSection(
          archTitle: 'MAXILLARY ARCH (UPPER)',
          leftQuad: upperLeft,
          rightQuad: upperRight,
          leftQuadLabel: _isPrimaryDentition ? 'UR (Q5)' : 'UR (Q1)',
          rightQuadLabel: _isPrimaryDentition ? 'UL (Q6)' : 'UL (Q2)',
          latestMap: latestMap,
        ),

        const SizedBox(height: 16),

        // Lower Arch (Mandible)
        _buildArchSection(
          archTitle: 'MANDIBULAR ARCH (LOWER)',
          leftQuad: lowerLeft,
          rightQuad: lowerRight,
          leftQuadLabel: _isPrimaryDentition ? 'LR (Q8)' : 'LR (Q4)',
          rightQuadLabel: _isPrimaryDentition ? 'LL (Q7)' : 'LL (Q3)',
          latestMap: latestMap,
        ),

        const SizedBox(height: 14),

        // Quick Legend
        _buildLegend(),
      ],
    );
  }

  Widget _buildArchSection({
    required String archTitle,
    required List<String> leftQuad,
    required List<String> rightQuad,
    required String leftQuadLabel,
    required String rightQuadLabel,
    required Map<String, ToothChartEntryModel> latestMap,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                archTitle,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: Color(0xFF64748B),
                ),
              ),
              Row(
                children: [
                  Text(leftQuadLabel, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                  const SizedBox(width: 8),
                  const Text('|', style: TextStyle(fontSize: 11, color: Color(0xFFCBD5E1))),
                  const SizedBox(width: 8),
                  Text(rightQuadLabel, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Left Quadrant (e.g. 18 -> 11)
                Row(
                  children: leftQuad.map((tooth) {
                    final entry = latestMap[tooth];
                    final isSelected = widget.selectedToothNumber == tooth;
                    return _ToothCell(
                      toothNumber: tooth,
                      entry: entry,
                      isSelected: isSelected,
                      onTap: () => widget.onToothSelected?.call(tooth),
                    );
                  }).toList(),
                ),
                // Center Midline Divider
                Container(
                  width: 2,
                  height: 60,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: const Color(0xFF0D9488).withValues(alpha: 0.4),
                ),
                // Right Quadrant (e.g. 21 -> 28)
                Row(
                  children: rightQuad.map((tooth) {
                    final entry = latestMap[tooth];
                    final isSelected = widget.selectedToothNumber == tooth;
                    return _ToothCell(
                      toothNumber: tooth,
                      entry: entry,
                      isSelected: isSelected,
                      onTap: () => widget.onToothSelected?.call(tooth),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: const [
        _LegendItem(color: Color(0xFFF1F5F9), label: 'Healthy/Unrecorded'),
        _LegendItem(color: Color(0xFFFEE2E2), label: 'Caries'),
        _LegendItem(color: Color(0xFFDBEAFE), label: 'Filling / Restored'),
        _LegendItem(color: Color(0xFFFEF3C7), label: 'Crown / Bridge'),
        _LegendItem(color: Color(0xFFCCFBF1), label: 'Root Canal (RCT)'),
        _LegendItem(color: Color(0xFFE2E8F0), label: 'Missing / Extracted'),
      ],
    );
  }
}

class _ToothCell extends StatelessWidget {
  final String toothNumber;
  final ToothChartEntryModel? entry;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToothCell({
    required this.toothNumber,
    required this.entry,
    required this.isSelected,
    required this.onTap,
  });

  Color _getBackgroundColor() {
    if (entry == null) return const Color(0xFFF8FAFC);

    final condition = entry!.condition?.toLowerCase() ?? '';
    final treatment = entry!.treatment?.toLowerCase() ?? '';

    if (condition.contains('missing') || treatment.contains('extraction')) {
      return const Color(0xFFE2E8F0);
    }
    if (condition.contains('caries')) {
      return const Color(0xFFFEE2E2);
    }
    if (treatment.contains('rct') || condition.contains('rootcanal')) {
      return const Color(0xFFCCFBF1);
    }
    if (treatment.contains('crown') || treatment.contains('bridge')) {
      return const Color(0xFFFEF3C7);
    }
    if (treatment.contains('filling') || condition.contains('restored')) {
      return const Color(0xFFDBEAFE);
    }
    return const Color(0xFFF1F5F9);
  }

  Color _getTextColor() {
    if (entry?.condition?.toLowerCase().contains('caries') == true) {
      return const Color(0xFFB91C1C);
    }
    return const Color(0xFF1E293B);
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _getBackgroundColor();
    final textColor = _getTextColor();
    final hasCondition = entry?.condition != null && entry!.condition!.isNotEmpty;
    final hasTreatment = entry?.treatment != null && entry!.treatment!.isNotEmpty;

    return Tooltip(
      message: '${getToothName(toothNumber)}'
          '${hasCondition ? ' | Cond: ${entry!.condition}' : ''}'
          '${hasTreatment ? ' | Tx: ${entry!.treatment}' : ''}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 44,
          height: 60,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF0D9488)
                  : (hasCondition || hasTreatment)
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFFE2E8F0),
              width: isSelected ? 2.5 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF0D9488).withValues(alpha: 0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                toothNumber,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 2),
              if (hasCondition || hasTreatment)
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: hasCondition ? const Color(0xFFEF4444) : const Color(0xFF0D9488),
                    shape: BoxShape.circle,
                  ),
                )
              else
                const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
        ),
      ],
    );
  }
}
