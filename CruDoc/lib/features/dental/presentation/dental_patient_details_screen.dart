import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:doctor_management_app/features/shell/components/shell_background.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/patients/presentation/add_patient.dart';
import '../data/models/tooth_chart_entry_model.dart';
import 'providers/dental_providers.dart';
import 'dental_procedure_catalog_screen.dart';
import 'widgets/odontogram_view.dart';
import 'widgets/tooth_condition_editor_sheet.dart';
import 'widgets/tooth_history_sheet.dart';
import 'widgets/dental_procedure_log_sheet.dart';
import 'widgets/dental_treatment_plan_sheet.dart';

const Color _accentTeal = Color(0xFF0D9488);
const Color _accentTealLight = Color(0xFFCCFBF1);

/// Specialty-specific Patient Details Screen for Dentists.
///
/// Houses the interactive Odontogram (Tooth Chart), tooth condition logging,
/// per-tooth history, sessions stats, and clinical notes.
class DentalPatientDetailsScreen extends ConsumerStatefulWidget {
  final Patient patient;

  const DentalPatientDetailsScreen({
    super.key,
    required this.patient,
  });

  @override
  ConsumerState<DentalPatientDetailsScreen> createState() =>
      _DentalPatientDetailsScreenState();
}

class _DentalPatientDetailsScreenState
    extends ConsumerState<DentalPatientDetailsScreen> {
  String? _selectedToothNumber;
  late String _note = widget.patient.notes;

  String get _currentDoctorId =>
      FirebaseAuth.instance.currentUser?.uid ?? 'doc_dental';

  Future<void> _openNoteEditor() async {
    final controller = TextEditingController(text: _note);
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Doctor\'s Note',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 4,
              autofocus: true,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'General dental notes...',
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _accentTeal,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Save Note'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    final trimmed = result.trim();
    setState(() => _note = trimmed);
    try {
      await ref.read(patientRepositoryProvider).updateDoctorsNote(widget.patient.id, trimmed);
    } catch (_) {}
  }

  Future<void> _editPatient(Patient patient) async {
    final updated = await showEditPatientSheet(
      context,
      patient: patient,
      repository: ref.read(patientRepositoryProvider),
    );
    if (updated == true && mounted) {
      ref.invalidate(patientsStreamProvider);
    }
  }

  Future<void> _deletePatient(Patient patient) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Patient'),
        content: Text('Are you sure you want to delete ${patient.fullName}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    try {
      await ref.read(patientRepositoryProvider).deletePatient(patient.id);
      if (!mounted) return;
      ref.invalidate(patientsStreamProvider);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final patientsAsync = ref.watch(patientsStreamProvider);
    final patient = patientsAsync.maybeWhen(
      data: (list) {
        for (final p in list) {
          if (p.id == widget.patient.id) return p;
        }
        return widget.patient;
      },
      orElse: () => widget.patient,
    );

    final visitsAsync = ref.watch(visitsForPatientProvider(patient.id));
    final toothChartAsync = ref.watch(patientToothChartProvider(patient.id));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ShellBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Top Navigation Bar
              _buildTopBar(patient),

              // Scrollable Body
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                  children: [
                    // Patient Header Card
                    _buildPatientHeaderCard(patient),

                    const SizedBox(height: 12),

                    // Sessions Stats Row
                    _buildSessionsRow(visitsAsync),

                    const SizedBox(height: 16),

                    // Section: Tooth Chart (Odontogram)
                    _buildOdontogramSection(toothChartAsync),

                    const SizedBox(height: 16),

                    // Section: Dental Procedures Log
                    _buildProcedureLogSection(patient),

                    const SizedBox(height: 16),

                    // Section: Dental Treatment Plan & Quotes
                    _buildTreatmentPlanSection(patient),

                    const SizedBox(height: 16),

                    // Doctor's Note
                    _buildDoctorNoteCard(),

                    const SizedBox(height: 16),

                    // Contact Card
                    _buildContactCard(patient),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(Patient patient) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B)),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _accentTealLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.sentiment_satisfied_alt_rounded, size: 14, color: _accentTeal),
                    SizedBox(width: 4),
                    Text(
                      'DENTAL CLINIC',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: _accentTeal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.menu_book_outlined, color: _accentTeal),
                tooltip: 'Procedure Catalog',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DentalProcedureCatalogScreen(),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: Color(0xFF64748B)),
                onPressed: () => _editPatient(patient),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () => _deletePatient(patient),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPatientHeaderCard(Patient patient) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: _accentTealLight,
            child: Text(
              patient.fullName.isNotEmpty ? patient.fullName[0].toUpperCase() : 'P',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: _accentTeal,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  patient.fullName,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${patient.gender} • ${patient.age} yrs • ID: ${patient.id.substring(0, patient.id.length > 8 ? 8 : patient.id.length)}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionsRow(AsyncValue<List<Visit>> visitsAsync) {
    return visitsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (visits) {
        final completed = visits.where((v) => v.status == VisitStatus.completed).length;
        final lastVisitStr = visits.isNotEmpty
            ? DateFormat('MMM d, yyyy').format(visits.first.scheduledStart)
            : 'None yet';

        return Row(
          children: [
            Expanded(
              child: _buildStatItem('Sessions Attended', '$completed', Icons.check_circle_outline),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatItem('Last Consultation', lastVisitStr, Icons.calendar_today_outlined),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: _accentTeal),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOdontogramSection(AsyncValue<List<ToothChartEntryModel>> toothChartAsync) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.dashboard_outlined, size: 18, color: _accentTeal),
                  SizedBox(width: 6),
                  Text(
                    'Tooth Chart (Odontogram)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              if (_selectedToothNumber != null)
                TextButton(
                  onPressed: () => setState(() => _selectedToothNumber = null),
                  child: const Text('Clear Selection', style: TextStyle(fontSize: 12, color: _accentTeal)),
                ),
            ],
          ),

          const SizedBox(height: 12),

          // Odontogram View
          toothChartAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(child: CircularProgressIndicator(color: _accentTeal, strokeWidth: 2)),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('Failed to load chart: $e', style: const TextStyle(color: Colors.red))),
            ),
            data: (entries) {
              return Column(
                children: [
                  OdontogramView(
                    entries: entries,
                    selectedToothNumber: _selectedToothNumber,
                    onToothSelected: (tooth) {
                      setState(() => _selectedToothNumber = tooth);
                    },
                  ),
                  if (_selectedToothNumber != null) ...[
                    const SizedBox(height: 14),
                    _buildSelectedToothActionCard(entries),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedToothActionCard(List<ToothChartEntryModel> entries) {
    final tooth = _selectedToothNumber!;
    final matchingEntries = entries.where((e) => e.toothNumber == tooth).toList();
    final latestEntry = matchingEntries.isNotEmpty ? matchingEntries.first : null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _accentTeal.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Selected: Tooth $tooth',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
              Text(
                getToothName(tooth),
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
            ],
          ),
          if (latestEntry != null) ...[
            const SizedBox(height: 6),
            Text(
              'Current: ${latestEntry.condition ?? 'None'} • ${latestEntry.treatment ?? 'No treatment'}'
              '${latestEntry.surface != null ? ' (${latestEntry.surface!.toUpperCase()})' : ''}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF334155)),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    ToothConditionEditorSheet.show(
                      context,
                      doctorId: _currentDoctorId,
                      patientId: widget.patient.id,
                      toothNumber: tooth,
                      existingEntry: latestEntry,
                    );
                  },
                  icon: const Icon(Icons.add_circle_outline, size: 16),
                  label: const Text('Log Condition', style: TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    backgroundColor: _accentTeal,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => DentalProcedureLogSheet(
                      patientId: widget.patient.id,
                      preselectedToothNumber: tooth,
                    ),
                  );
                },
                icon: const Icon(Icons.medical_services_outlined, size: 16),
                label: const Text('Log Procedure', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                onPressed: () {
                  ToothHistorySheet.show(
                    context,
                    patientId: widget.patient.id,
                    toothNumber: tooth,
                  );
                },
                icon: const Icon(Icons.history, size: 16),
                tooltip: 'History',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProcedureLogSection(Patient patient) {
    final logsAsync = ref.watch(patientProcedureLogProvider(patient.id));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.medical_services_rounded, size: 18, color: _accentTeal),
                  SizedBox(width: 8),
                  Text(
                    'Procedures Log',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _accentTeal,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Log Procedure', style: TextStyle(fontSize: 12)),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => DentalProcedureLogSheet(patientId: patient.id),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          logsAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: CircularProgressIndicator(color: _accentTeal, strokeWidth: 2),
              ),
            ),
            error: (err, _) => Text('Error loading procedures: $err', style: const TextStyle(color: Colors.red)),
            data: (logs) {
              if (logs.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text(
                      'No procedures logged yet.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                    ),
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: logs.length > 5 ? 5 : logs.length,
                separatorBuilder: (context, sepIndex) => const Divider(height: 12),
                itemBuilder: (context, idx) {
                  final log = logs[idx];
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFCCFBF1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.done_all_rounded, size: 16, color: _accentTeal),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    log.procedureName,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                ),
                                Text(
                                  DateFormat('dd MMM yyyy').format(log.performedAt),
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                if (log.toothNumbers.isNotEmpty)
                                  Text(
                                    'Tooth ${log.toothNumbers.join(", ")} • ',
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                  ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: log.status == 'completed'
                                        ? const Color(0xFFDCFCE7)
                                        : const Color(0xFFFEF08A),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    log.status.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: log.status == 'completed'
                                          ? const Color(0xFF166534)
                                          : const Color(0xFF854D0E),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (log.notes.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                log.notes,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontStyle: FontStyle.italic),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTreatmentPlanSection(Patient patient) {
    final itemsAsync = ref.watch(patientTreatmentPlanProvider(patient.id));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.request_quote_rounded, size: 18, color: _accentTeal),
                  SizedBox(width: 8),
                  Text(
                    'Treatment Plan & Quote',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.open_in_new, size: 14),
                label: const Text('Manage Quote', style: TextStyle(fontSize: 12)),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => DentalTreatmentPlanSheet(
                      patientId: patient.id,
                      patientName: patient.fullName,
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          itemsAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CircularProgressIndicator(color: _accentTeal, strokeWidth: 2),
              ),
            ),
            error: (err, _) => Text('Error loading plan: $err', style: const TextStyle(color: Colors.red)),
            data: (items) {
              if (items.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text(
                      'No treatment quote items created yet.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                    ),
                  ),
                );
              }

              final total = items
                  .where((i) => i.status == 'proposed' || i.status == 'accepted')
                  .fold<double>(0.0, (sum, i) => sum + i.estimatedPrice);

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${items.length} proposed procedure${items.length == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${items.where((i) => i.status == "invoiced").length} invoiced',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                  Text(
                    '₹${total.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: _accentTeal,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDoctorNoteCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Doctor\'s Note',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
              TextButton(
                onPressed: _openNoteEditor,
                child: const Text('Edit Note', style: TextStyle(fontSize: 12, color: _accentTeal)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _note.trim().isNotEmpty ? _note : 'No general clinical notes added yet.',
            style: TextStyle(
              fontSize: 13,
              color: _note.trim().isNotEmpty ? const Color(0xFF334155) : const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard(Patient patient) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Contact Information',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.phone_outlined, size: 16, color: Color(0xFF64748B)),
              const SizedBox(width: 8),
              Text(
                patient.phone.isNotEmpty ? patient.phone : 'No phone number',
                style: const TextStyle(fontSize: 13, color: Color(0xFF334155)),
              ),
            ],
          ),
          if (patient.email.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.email_outlined, size: 16, color: Color(0xFF64748B)),
                const SizedBox(width: 8),
                Text(
                  patient.email,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF334155)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
