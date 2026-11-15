import 'package:doctor_management_app/core/clinic/clinic_doctors_provider.dart';
import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_billing_provider.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/queue/data/model/queue_entry_model.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';
import 'package:doctor_management_app/features/revenue/data/providers/revenue_view_providers.dart';

import '../core/ai_tool.dart';
import 'patient_tools.dart';

/// Screen name the model may pick, mapped to a voice-navigation target id:
/// `tab:<DesktopTab>` or `spot:<VoiceSpot.id>` (same ids the voice
/// meaning-matcher uses; see voice_navigation.dart `targetFromOption`).
const _screens = <String, String>{
  'dashboard': 'tab:${DesktopTab.dashboard}',
  'patients': 'tab:${DesktopTab.patients}',
  'schedule': 'tab:${DesktopTab.appointments}',
  'queue': 'tab:${DesktopTab.queue}',
  'inventory': 'tab:${DesktopTab.inventory}',
  'revenue': 'tab:${DesktopTab.revenue}',
  'campaigns': 'tab:${DesktopTab.campaigns}',
  'scribe': 'tab:${DesktopTab.scribe}',
  'files': 'tab:${DesktopTab.files}',
  'settings': 'tab:${DesktopTab.settings}',
  'todos': 'tab:${DesktopTab.todos}',
  'documents': 'tab:${DesktopTab.documents}',
  'treatment_plans': 'tab:${DesktopTab.treatmentPlans}',
  'sterilization': 'tab:${DesktopTab.sterilization}',
  'procedures': 'tab:${DesktopTab.procedures}',
  'recalls': 'tab:${DesktopTab.recalls}',
  'referrals': 'tab:${DesktopTab.dentalReferrals}',
  'lab_cases': 'tab:${DesktopTab.labCases}',
  'charting': 'tab:${DesktopTab.charting}',
  'low_stock': 'spot:inventory.low',
  'expiring_stock': 'spot:inventory.expiring',
  'inventory_orders': 'spot:inventory.orders',
  'inventory_vendors': 'spot:inventory.vendors',
  'invoices': 'spot:revenue.invoices',
  'money_in': 'spot:revenue.in',
  'money_out': 'spot:revenue.out',
  'patients_balance_due': 'spot:patients.balance',
  'patients_follow_up_overdue': 'spot:patients.overdue',
  'patients_in_treatment': 'spot:patients.treatment',
  'patients_recent': 'spot:patients.recent',
  'settings_clinic': 'spot:settings.clinic',
  'settings_profile': 'spot:settings.profile',
  'settings_appearance': 'spot:settings.appearance',
  'new_visit_form': 'spot:action.newVisit',
  'new_invoice_form': 'spot:action.newInvoice',
  'record_payment_form': 'spot:action.recordPayment',
  'record_expense_form': 'spot:action.recordExpense',
  'add_inventory_item_form': 'spot:action.addItem',
  'new_campaign_form': 'spot:action.newCampaign',
};

String? _str(Map<String, Object?> args, String key) {
  final v = args[key];
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Future<AiToolResult> _go(
  AiToolContext ctx,
  String target,
  Map<String, Object?> navArgs,
  Map<String, Object?> data,
  String summary,
) async {
  final nav = ctx.navigate;
  if (nav == null) {
    return AiToolResult.ok({...data, 'navigated': false});
  }
  await nav(target, args: navArgs);
  return AiToolResult.ok({...data, 'navigated': true}, summary: summary);
}

List<AiTool> coreTools() => [
  AiTool(
    name: 'open_screen',
    description:
        'Move the app to a screen or a section of one (for example '
        '"low_stock", "invoices", "schedule"). Use when the user asks to go '
        'somewhere or to see a list. Pass patientId only to open that '
        "patient's details instead.",
    group: AiToolGroup.core,
    risk: AiToolRisk.read,
    params: {
      'screen': AiParam.enumOf(
        _screens.keys.toList(),
        'Where to go',
        required: false,
      ),
      'patientId': AiParam.string(
        'Open this patient instead of a screen',
        required: false,
      ),
    },
    run: (ctx, args) async {
      final pid = _str(args, 'patientId');
      if (pid != null) {
        if (!ctx.can(ClinicPermission.patientsView)) {
          return AiToolResult.error('You do not have access to patients.');
        }
        return _go(
          ctx,
          'patient',
          {'patientId': pid},
          {'patientId': pid},
          'Opened patient',
        );
      }
      final screen = _str(args, 'screen');
      final target = screen == null ? null : _screens[screen];
      if (screen == null || target == null) {
        return AiToolResult.error('Pick a screen from the list.');
      }
      return _go(ctx, target, const {}, {
        'screen': screen,
      }, 'Opened ${screen.replaceAll('_', ' ')}');
    },
  ),
  AiTool(
    name: 'open_patient',
    description:
        "Open a patient's details screen, optionally on one tab. Needs "
        'patientId from find_patient.',
    group: AiToolGroup.core,
    risk: AiToolRisk.read,
    permission: ClinicPermission.patientsView,
    params: const {
      'patientId': AiParam.string('Patient id'),
      'tab': AiParam.enumOf(
        ['overview', 'clinical', 'visits', 'files', 'payments'],
        'Tab to show',
        required: false,
      ),
    },
    run: (ctx, args) async {
      final id = _str(args, 'patientId');
      if (id == null) return AiToolResult.error('patientId is required.');
      final p = await ctx.read(patientRepositoryProvider).getPatient(id);
      if (p == null) return AiToolResult.error('Patient not found.');
      final tab = _str(args, 'tab');
      return _go(
        ctx,
        'patient',
        {'patientId': id, 'tab': ?tab},
        {'patientId': id, 'name': p.fullName.trim()},
        'Opened ${p.fullName.trim()}',
      );
    },
  ),
  AiTool(
    name: 'search_everything',
    description:
        'Search patients and invoices at once for a word, name, phone or '
        'invoice number. Use when the user is not sure what kind of record '
        'they want.',
    group: AiToolGroup.core,
    risk: AiToolRisk.read,
    permission: ClinicPermission.patientsView,
    params: const {'query': AiParam.string('Text to search for')},
    run: (ctx, args) async {
      final q = _str(args, 'query');
      if (q == null) return AiToolResult.error('query is required.');
      final patients = matchPatientsForAi(
        await ctx.read(patientsStreamProvider.future),
        q,
      );
      final invoices = <Map<String, Object?>>[];
      if (ctx.can(ClinicPermission.billing)) {
        final low = q.toLowerCase();
        try {
          final all = await ctx.read(invoicesStreamProvider.future);
          for (final i in all) {
            if (i.patientName.toLowerCase().contains(low) ||
                i.invoiceNumber.toLowerCase().contains(low) ||
                i.service.toLowerCase().contains(low)) {
              invoices.add({
                'invoiceId': i.id,
                'number': i.invoiceNumber,
                'patient': i.patientName,
                'amount': i.amount,
                'status': i.status,
                'date': _ymd(i.date),
              });
              if (invoices.length >= 5) break;
            }
          }
        } catch (_) {}
      }
      return AiToolResult.ok({
        'patients': patients.take(5).map(patientBrief).toList(),
        'patientTotal': patients.length,
        'invoices': invoices,
        'note': 'Files and visits are not searched here.',
      });
    },
  ),
  AiTool(
    name: 'get_today_overview',
    description:
        'Counts for today: appointments by status, patients waiting in the '
        'queue, the next appointment, and total money still owed. Use for '
        '"how is today going".',
    group: AiToolGroup.core,
    risk: AiToolRisk.read,
    permission: ClinicPermission.schedule,
    run: (ctx, args) async {
      final visits = (await ctx.read(
        todaysVisitsProvider.future,
      )).where((v) => !v.isDeleted).toList();
      final queue = await ctx.read(todaysQueueProvider.future);
      var owed = 0.0;
      if (ctx.can(ClinicPermission.billing)) {
        try {
          final pending = await ctx.read(pendingPaymentsProvider.future);
          for (final p in pending) {
            if (!p.isPaid) owed += p.amount;
          }
        } catch (_) {}
      }
      int n(VisitStatus s) => visits.where((v) => v.status == s).length;
      final now = DateTime.now();
      final upcoming =
          visits
              .where(
                (v) =>
                    v.status == VisitStatus.scheduled &&
                    v.scheduledStart.isAfter(now),
              )
              .toList()
            ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
      return AiToolResult.ok({
        'date': _ymd(now),
        'appointments': visits.length,
        'scheduled': n(VisitStatus.scheduled),
        'completed': n(VisitStatus.completed),
        'cancelled': n(VisitStatus.cancelled),
        'missed': n(VisitStatus.missed),
        'waitingInQueue': queue
            .where((e) => e.status == QueueStatus.waiting)
            .length,
        'inConsultation': queue
            .where((e) => e.status == QueueStatus.inConsultation)
            .length,
        if (upcoming.isNotEmpty)
          'nextAppointment': upcoming.first.scheduledStart.toIso8601String(),
        if (ctx.can(ClinicPermission.billing)) 'totalOwed': owed,
      });
    },
  ),
  AiTool(
    name: 'get_current_context',
    description:
        'What the user is looking at right now: screen, open patient and '
        'selected date. Use to resolve "this patient" or "today".',
    group: AiToolGroup.core,
    risk: AiToolRisk.read,
    run: (ctx, args) async => AiToolResult.ok({
      'screen': ctx.screen,
      'openPatientId': ctx.openPatientId,
      'selectedDate': ctx.selectedDate == null ? null : _ymd(ctx.selectedDate!),
    }),
  ),
  AiTool(
    name: 'get_clinic_info',
    description:
        "The clinic's name and specialty and how many doctors work there.",
    group: AiToolGroup.core,
    risk: AiToolRisk.read,
    phoneSafe: true,
    run: (ctx, args) async {
      final clinic = await ctx.read(activeClinicProvider.future);
      final doctors = await ctx.read(clinicDoctorsProvider.future);
      if (clinic == null) {
        return AiToolResult.ok({
          'solo': true,
          'doctorCount': doctors.length,
          'note': 'Solo practice: no clinic record.',
        });
      }
      return AiToolResult.ok({
        'name': clinic.name,
        'specialty': clinic.specialty,
        'doctorCount': doctors.length,
      });
    },
  ),
  AiTool(
    name: 'list_doctors',
    description:
        'Doctors at this clinic with their ids and specialty. Use to get a '
        'doctorId for scheduling.',
    group: AiToolGroup.core,
    risk: AiToolRisk.read,
    permission: ClinicPermission.schedule,
    phoneSafe: true,
    run: (ctx, args) async {
      final doctors = await ctx.read(clinicDoctorsProvider.future);
      return AiToolResult.ok({
        'doctors': [
          for (final d in doctors.take(10))
            {
              'doctorId': d.uid,
              'name': d.name,
              if (d.specialty.isNotEmpty) 'specialty': d.specialty,
            },
        ],
        'total': doctors.length,
      });
    },
  ),
];
