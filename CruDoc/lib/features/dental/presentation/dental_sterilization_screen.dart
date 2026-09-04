import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../data/models/sterilization_log_model.dart';
import 'providers/dental_providers.dart';

const Color _accentTeal = Color(0xFF0D9488);

/// Sterilization & Autoclave Cycle Compliance Screen.
///
/// Records and monitors clinic-level autoclave sterilization runs for
/// regulatory and clinical infection-control compliance.
/// Strictly doctor/clinic-scoped, NOT patient-linked.
class DentalSterilizationScreen extends ConsumerStatefulWidget {
  const DentalSterilizationScreen({super.key});

  @override
  ConsumerState<DentalSterilizationScreen> createState() =>
      _DentalSterilizationScreenState();
}

class _DentalSterilizationScreenState
    extends ConsumerState<DentalSterilizationScreen> {
  String get _currentDoctorId =>
      FirebaseAuth.instance.currentUser?.uid ?? 'doc_dental';

  String _resultFilter = 'All';

  Future<void> _openLogCycleDialog() async {
    DateTime cycleDate = DateTime.now();
    TimeOfDay cycleTime = TimeOfDay.now();
    final operatorController = TextEditingController(
      text: FirebaseAuth.instance.currentUser?.displayName ?? 'Dr. Dentist',
    );
    final loadController = TextEditingController(
      text: 'Examination kits, Scalers, Extraction forceps',
    );
    final notesController = TextEditingController();
    String result = 'pass';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Log Autoclave Cycle'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date & Time pickers
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.calendar_today, size: 14),
                            label: Text(
                              DateFormat('dd MMM yyyy').format(cycleDate),
                              style: const TextStyle(fontSize: 12),
                            ),
                            onPressed: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: cycleDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now().add(const Duration(days: 1)),
                              );
                              if (d != null) {
                                setDialogState(() => cycleDate = d);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.access_time, size: 14),
                            label: Text(
                              cycleTime.format(context),
                              style: const TextStyle(fontSize: 12),
                            ),
                            onPressed: () async {
                              final t = await showTimePicker(
                                context: context,
                                initialTime: cycleTime,
                              );
                              if (t != null) {
                                setDialogState(() => cycleTime = t);
                              }
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    TextField(
                      controller: operatorController,
                      decoration: const InputDecoration(
                        labelText: 'Operator / Staff *',
                        hintText: 'e.g. Nurse Pooja or Dr. Dentist',
                      ),
                    ),

                    const SizedBox(height: 12),

                    TextField(
                      controller: loadController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Load Description *',
                        hintText: 'e.g. 5 Exam trays, 10 burs, 2 surgical handpieces',
                      ),
                    ),

                    const SizedBox(height: 12),

                    const Text(
                      'Sterilization Result *',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        ChoiceChip(
                          label: const Text('PASS'),
                          selected: result == 'pass',
                          selectedColor: const Color(0xFFDCFCE7),
                          labelStyle: TextStyle(
                            color: result == 'pass' ? const Color(0xFF166534) : Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                          onSelected: (sel) {
                            if (sel) setDialogState(() => result = 'pass');
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('FAIL'),
                          selected: result == 'fail',
                          selectedColor: const Color(0xFFFEE2E2),
                          labelStyle: TextStyle(
                            color: result == 'fail' ? const Color(0xFF991B1B) : Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                          onSelected: (sel) {
                            if (sel) setDialogState(() => result = 'fail');
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('INCOMPLETE'),
                          selected: result == 'incomplete',
                          selectedColor: const Color(0xFFFEF3C7),
                          labelStyle: TextStyle(
                            color: result == 'incomplete' ? const Color(0xFF92400E) : Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                          onSelected: (sel) {
                            if (sel) setDialogState(() => result = 'incomplete');
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    TextField(
                      controller: notesController,
                      decoration: const InputDecoration(
                        labelText: 'Parameters / Notes (Optional)',
                        hintText: 'e.g. 134°C, 30 psi, 15 mins. Chemical indicator passed.',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _accentTeal),
                  onPressed: () {
                    if (operatorController.text.trim().isEmpty ||
                        loadController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Operator and Load Description are required')),
                      );
                      return;
                    }
                    Navigator.pop(ctx, true);
                  },
                  child: const Text('Save Record'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true) {
      final combinedDateTime = DateTime(
        cycleDate.year,
        cycleDate.month,
        cycleDate.day,
        cycleTime.hour,
        cycleTime.minute,
      );
      final now = DateTime.now();

      final log = SterilizationLogModel(
        id: const Uuid().v4(),
        doctorId: _currentDoctorId,
        cycleDate: combinedDateTime,
        operatorName: operatorController.text.trim(),
        loadDescription: loadController.text.trim(),
        result: result,
        notes: notesController.text.trim(),
        createdAt: now,
        updatedAt: now,
        syncStatus: 'pending',
      );

      await ref.read(dentalRepositoryProvider).saveSterilizationLog(log);
      ref.invalidate(sterilizationLogProvider(_currentDoctorId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Autoclave cycle logged successfully'),
            backgroundColor: _accentTeal,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final logsAsync = ref.watch(sterilizationLogProvider(_currentDoctorId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Autoclave Sterilization Log'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _accentTeal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_task_rounded),
        label: const Text('Log Cycle'),
        onPressed: _openLogCycleDialog,
      ),
      body: Column(
        children: [
          // Filter row
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Text('Filter: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('All'),
                  selected: _resultFilter == 'All',
                  selectedColor: const Color(0xFFCCFBF1),
                  onSelected: (sel) {
                    if (sel) setState(() => _resultFilter = 'All');
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Passed'),
                  selected: _resultFilter == 'pass',
                  selectedColor: const Color(0xFFDCFCE7),
                  onSelected: (sel) {
                    if (sel) setState(() => _resultFilter = 'pass');
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Failed / Incomplete'),
                  selected: _resultFilter == 'fail',
                  selectedColor: const Color(0xFFFEE2E2),
                  onSelected: (sel) {
                    if (sel) setState(() => _resultFilter = 'fail');
                  },
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Cycle records list
          Expanded(
            child: logsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Error loading cycles: $err')),
              data: (allLogs) {
                final logs = allLogs.where((l) {
                  if (_resultFilter == 'All') return true;
                  if (_resultFilter == 'pass') return l.result == 'pass';
                  return l.result != 'pass';
                }).toList();

                final passCount = allLogs.where((l) => l.result == 'pass').length;
                final failCount = allLogs.where((l) => l.result != 'pass').length;

                return Column(
                  children: [
                    // Stats card
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      color: const Color(0xFFF8FAFC),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total Cycles: ${allLogs.length}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                          ),
                          Row(
                            children: [
                              Text(
                                '$passCount Passed',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF166534)),
                              ),
                              if (failCount > 0) ...[
                                const SizedBox(width: 10),
                                Text(
                                  '$failCount Attention Required',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF991B1B)),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),

                    const Divider(height: 1),

                    if (logs.isEmpty)
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.clean_hands_rounded, size: 48, color: Color(0xFF94A3B8)),
                              const SizedBox(height: 12),
                              const Text(
                                'No sterilization cycles recorded',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Log autoclave cycle runs to maintain clinical compliance.',
                                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                style: FilledButton.styleFrom(backgroundColor: _accentTeal),
                                icon: const Icon(Icons.add),
                                label: const Text('Log Autoclave Cycle'),
                                onPressed: _openLogCycleDialog,
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.only(bottom: 80, top: 8),
                          itemCount: logs.length,
                          separatorBuilder: (context, sepIndex) => const Divider(height: 1, indent: 16, endIndent: 16),
                          itemBuilder: (context, idx) {
                            final log = logs[idx];
                            final isPass = log.result == 'pass';
                            final isFail = log.result == 'fail';

                            return ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isPass
                                      ? const Color(0xFFDCFCE7)
                                      : (isFail ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7)),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isPass
                                      ? Icons.check
                                      : (isFail ? Icons.close : Icons.hourglass_bottom),
                                  color: isPass
                                      ? const Color(0xFF166534)
                                      : (isFail ? const Color(0xFF991B1B) : const Color(0xFF92400E)),
                                  size: 18,
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      DateFormat('dd MMM yyyy, hh:mm a').format(log.cycleDate),
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isPass
                                          ? const Color(0xFFDCFCE7)
                                          : (isFail ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7)),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      log.result.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: isPass
                                            ? const Color(0xFF166534)
                                            : (isFail ? const Color(0xFF991B1B) : const Color(0xFF92400E)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    'Operator: ${log.operatorName} • Load: ${log.loadDescription}',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF334155)),
                                  ),
                                  if (log.notes.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      log.notes,
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontStyle: FontStyle.italic),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
