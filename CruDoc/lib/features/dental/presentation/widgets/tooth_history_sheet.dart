import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:crudoc_shared/theme/cru_colors.dart';
import '../../data/models/tooth_chart_entry_model.dart';
import '../../domain/tooth_numbering.dart';
import '../providers/dental_providers.dart';
import 'odontogram_view.dart';

/// Clean bottom sheet showing the complete chronological event history for a selected tooth.
class ToothHistorySheet extends ConsumerStatefulWidget {
  final String patientId;
  final String toothNumber;

  const ToothHistorySheet({
    super.key,
    required this.patientId,
    required this.toothNumber,
  });

  static Future<void> show(
    BuildContext context, {
    required String patientId,
    required String toothNumber,
  }) {
    final surface = Theme.of(context).extension<CruColors>()?.surface ??
        (Theme.of(context).brightness == Brightness.dark
            ? CruColors.evening.surface
            : CruColors.day.surface);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) =>
          ToothHistorySheet(patientId: patientId, toothNumber: toothNumber),
    );
  }

  @override
  ConsumerState<ToothHistorySheet> createState() => _ToothHistorySheetState();
}

class _ToothHistorySheetState extends ConsumerState<ToothHistorySheet> {
  CruColors get _c =>
      Theme.of(context).extension<CruColors>() ??
      (Theme.of(context).brightness == Brightness.dark
          ? CruColors.evening
          : CruColors.day);

  late Future<List<ToothChartEntryModel>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  void _loadHistory() {
    _historyFuture = ref
        .read(dentalRepositoryProvider)
        .getHistoryForTooth(widget.patientId, widget.toothNumber);
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, yyyy • h:mm a');
    final numbering =
        ref.watch(toothNumberingProvider).value ?? ToothNumbering.fdi;
    final toothText = toothLabel(widget.toothNumber, numbering);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [          // Header Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tooth $toothText History',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _c.label,
                    ),
                  ),
                  Text(
                    getToothName(widget.toothNumber),
                    style: TextStyle(
                      fontSize: 12,
                      color: _c.label2,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: Icon(Icons.close, color: _c.label2),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),

          Divider(height: 20, color: _c.separator),

          // Event History List
          FutureBuilder<List<ToothChartEntryModel>>(
            future: _historyFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: _c.accent,
                      strokeWidth: 2,
                    ),
                  ),
                );
              }

              final entries = snapshot.data ?? [];
              if (entries.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.history_toggle_off,
                          size: 40,
                          color: _c.label3,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No clinical events logged for Tooth $toothText yet.',
                          style: TextStyle(
                            fontSize: 13,
                            color: _c.label2,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.55,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => Divider(height: 16, color: _c.separator),
                  itemBuilder: (context, index) {
                    final item = entries[index];
                    final dateLabel = dateFormat.format(item.recordedAt);

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _c.inset,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _c.separator),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                dateLabel,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _c.label2,
                                ),
                              ),
                              if (item.surface != null &&
                                  item.surface!.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _c.surface,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: _c.separator),
                                  ),
                                  child: Text(
                                    item.surface!.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: _c.label,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              if (item.condition != null &&
                                  item.condition!.isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                                  ),
                                  child: Text(
                                    item.condition!,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.redAccent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              if (item.treatment != null &&
                                  item.treatment!.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.4)),
                                  ),
                                  child: Text(
                                    item.treatment!,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF2563EB),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (item.notes.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              item.notes,
                              style: TextStyle(
                                fontSize: 13,
                                color: _c.label,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
