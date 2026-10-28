import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/core/people/person_picker.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/glance_card.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_dialogs.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_models.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_network.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_share_flows.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/features/radiology/presentation/referrers_screen.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Where a referrer stands, for the accent beside their name.
enum ReferrerLink {
  /// Saved by hand for the records; not on CruDoc.
  saved,

  /// On CruDoc and linked.
  linked,

  /// Asked on CruDoc, no answer yet (amber).
  pending,

  /// Said no (red); leaves the list [referrerDeclineGrace] after.
  declined,
}

ReferrerLink referrerLinkOf(
  ReferralContact c,
  Map<String, ReferrerRequest> links,
) {
  if (!c.onCruDoc) return ReferrerLink.saved;
  return switch (links[c.crudocUid]?.status) {
    ReferrerRequestStatus.pending => ReferrerLink.pending,
    ReferrerRequestStatus.declined => ReferrerLink.declined,
    // Accepted, or linked before requests existed.
    _ => ReferrerLink.linked,
  };
}

/// Asks [person] (found by CruDoc ID) to be a referrer and keeps them in
/// the list meanwhile.
Future<void> addCruDocReferrer(
  BuildContext context,
  WidgetRef ref,
  CrudocPerson person,
) async {
  try {
    await saveCrudocContact(ref, person);
    final status = await ReferralNetworkApi.instance.requestReferrer(
      person.uid,
    );
    if (context.mounted) {
      recToast(
        context,
        status == 'accepted'
            ? '${drName(person.name)} is in your referrers'
            : 'Asked ${drName(person.name)}. They’ll show in amber until '
                  'they accept',
      );
    }
  } catch (e) {
    if (context.mounted) {
      recToast(context, "Couldn't add ${drName(person.name)}: $e");
    }
  }
}

/// Accepts or declines [req]. Accepting also puts the asking doctor in
/// this clinic's referrers.
Future<void> answerReferrerRequest(
  BuildContext context,
  WidgetRef ref,
  ReferrerRequest req, {
  required bool accept,
}) async {
  try {
    await ReferralNetworkApi.instance.answerReferrer(
      req.fromUid,
      accept: accept,
    );
    if (accept) await saveCrudocContact(ref, req.from);
    if (context.mounted) {
      recToast(
        context,
        accept
            ? '${drName(req.from.name)} is in your referrers'
            : 'Declined ${drName(req.from.name)}',
      );
    }
  } catch (e) {
    if (context.mounted) recToast(context, "Couldn't answer: $e");
  }
}

bool _sameMonth(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month;

/// One line of the Referrers list: a saved doctor or clinic, a scan sender
/// from radiology, or both when the names match.
class _Entry {
  _Entry({this.contact, this.scanSender});

  final ReferralContact? contact;
  final RadReferrer? scanSender;
  final List<DentalReferral> referrals = [];
  final List<RadStudy> studies = [];

  String get name => contact?.name ?? scanSender!.name;
  String get clinic => contact?.clinic ?? scanSender!.clinic;
  String get city => (contact?.city.isNotEmpty ?? false)
      ? contact!.city
      : scanSender?.city ?? '';

  int inMonth(DateTime now) =>
      referrals.where((r) => _sameMonth(r.recordedAt, now)).length +
      studies.where((s) => _sameMonth(s.receivedAt, now)).length;

  int get waiting =>
      referrals.where((r) => r.status.isOpen).length +
      studies.where((s) => s.status.isOpen).length;

  DateTime? get last {
    final all = [
      for (final r in referrals) r.recordedAt,
      for (final s in studies) s.receivedAt,
    ];
    return all.isEmpty ? null : all.reduce((a, b) => a.isAfter(b) ? a : b);
  }

  double fees(DateTime now) => studies
      .where((s) => _sameMonth(s.receivedAt, now))
      .fold<double>(0, (t, s) => t + (s.fee ?? 0));

  String activity(DateTime now) {
    final parts = [
      if (referrals.isNotEmpty) DashFormat.plural(referrals.length, 'referral'),
      if (studies.isNotEmpty)
        DashFormat.plural(studies.length, 'study', 'studies'),
    ];
    if (parts.isEmpty) return 'Nothing yet';
    return '${parts.join(' · ')} · ${inMonth(now)} this month';
  }
}

/// Saved doctors and clinics, plus radiology's scan senders not saved as
/// a doctor, each with their referrals and studies.
List<_Entry> _entries({
  required List<ReferralContact> contacts,
  required List<RadReferrer> scanSenders,
  required List<DentalReferral> referrals,
  required List<RadStudy> studies,
}) {
  String key(String s) => s.trim().toLowerCase();
  final byName = <String, _Entry>{};
  final byContact = <String, _Entry>{};
  final out = <_Entry>[];
  for (final c in contacts) {
    final e = _Entry(contact: c);
    out.add(e);
    byContact[c.id] = e;
    byName.putIfAbsent(key(c.name), () => e);
  }
  final bySender = <String, _Entry>{};
  for (final r in scanSenders) {
    final same = byName[key(r.name)];
    final e = same != null && same.scanSender == null
        ? (_Entry(contact: same.contact, scanSender: r)
            ..referrals.addAll(same.referrals))
        : _Entry(scanSender: r);
    if (same != null && same.scanSender == null) {
      out[out.indexOf(same)] = e;
      byContact[same.contact!.id] = e;
      byName[key(r.name)] = e;
    } else {
      out.add(e);
    }
    bySender[r.id] = e;
  }
  for (final r in referrals) {
    (byContact[r.contactId] ?? byName[key(r.contactName)])?.referrals.add(r);
  }
  for (final s in studies) {
    if (s.referrerId.isNotEmpty) bySender[s.referrerId]?.studies.add(s);
  }
  return out;
}

/// The doctors and clinics this clinic sends referrals to or gets them
/// from: found by CruDoc ID (linked once they accept) or saved by hand for
/// the records, with what went each way. Requests from other doctors wait
/// at the top.
class ReferrersScreen extends ConsumerStatefulWidget {
  const ReferrersScreen({super.key});

  @override
  ConsumerState<ReferrersScreen> createState() => _ReferrersScreenState();
}

class _ReferrersScreenState extends ConsumerState<ReferrersScreen> {
  final _search = TextEditingController();
  final Set<String> _pruning = {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _findById() async {
    final person = await showDoctorPicker(context);
    if (person == null || !mounted) return;
    await addCruDocReferrer(context, ref, person);
  }

  /// Referrers who declined more than [referrerDeclineGrace] ago go.
  void _prune(List<ReferralContact> contacts, Map<String, ReferrerRequest> l) {
    final gone = [
      for (final c in contacts)
        if (c.onCruDoc &&
            (l[c.crudocUid]?.expired ?? false) &&
            _pruning.add(c.id))
          c,
    ];
    if (gone.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final repo = ref.read(dentalRecordsRepoProvider);
      for (final c in gone) {
        try {
          await repo.delete(c.id);
        } catch (e) {
          debugPrint('[Referrers] remove ${c.id}: $e');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final contacts = ref.watch(referralContactsProvider);
    final links = ref.watch(referrerLinksProvider);
    final incoming = ref.watch(incomingReferrerRequestsProvider);
    final requestsError = ref.watch(referrerRequestsProvider).error;
    final scanSenders =
        ref.watch(radReferrersProvider).value ?? const <RadReferrer>[];
    final studies = ref.watch(radStudiesProvider).value ?? const <RadStudy>[];
    final referrals = ref.watch(allReferralsProvider);
    _prune(contacts, links);
    final now = DateTime.now();

    bool gone(ReferralContact? x) =>
        x != null && x.onCruDoc && (links[x.crudocUid]?.expired ?? false);
    final all = _entries(
      contacts: contacts,
      scanSenders: scanSenders,
      referrals: referrals,
      studies: studies,
    ).where((e) => !gone(e.contact)).toList();

    final q = _search.text.trim().toLowerCase();
    final shown =
        all
            .where(
              (e) =>
                  q.isEmpty ||
                  [
                    e.name,
                    e.clinic,
                    e.city,
                    e.contact?.specialty ?? '',
                    e.contact?.crudocId ?? '',
                  ].any((s) => s.toLowerCase().contains(q)),
            )
            .toList()
          // Busiest this month first.
          ..sort((a, b) {
            final d = b.inMonth(now).compareTo(a.inMonth(now));
            return d != 0
                ? d
                : a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
    final onCruDoc = contacts.where((x) => x.onCruDoc).length;
    final month = all.fold<int>(0, (t, e) => t + e.inMonth(now));
    final waiting = all.fold<int>(0, (t, e) => t + e.waiting);
    final withFees = scanSenders.isNotEmpty;
    final fees = all.fold<double>(0, (t, e) => t + e.fees(now));

    Widget cell(String label, String value, Widget caption) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GlanceLabel(label),
        GlanceMetric(value),
        GlanceCaption(caption),
      ],
    );

    return Padding(
      padding: cruIsPhone(context)
          ? EdgeInsets.zero
          : desktopPagePadding(context).copyWith(bottom: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: cruIsPhone(context)
                ? const EdgeInsets.fromLTRB(16, 8, 16, 0)
                : EdgeInsets.zero,
            child: DentalPageHeader(
              title: 'Referrers',
              subtitle: all.isEmpty
                  ? 'Doctors and clinics you refer to or get referrals from'
                  : '${DashFormat.plural(all.length, 'referrer')} · '
                        '$onCruDoc on CruDoc',
              actions: [
                CruButton(
                  label: 'Find by CruDoc ID',
                  icon: CruIcons.search,
                  kind: CruButtonKind.secondary,
                  onPressed: _findById,
                ),
                const SizedBox(width: CruSpace.s8),
                CruButton(
                  label: 'Add manually',
                  icon: CruIcons.plus,
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const EditContactDialog(),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: cruIsPhone(context)
                  ? const EdgeInsets.fromLTRB(16, 16, 16, 24)
                  : EdgeInsets.only(
                      top: CruSpace.cardGap,
                      bottom: desktopPagePadding(context).bottom,
                    ),
              children: [
                if (requestsError != null) ...[
                  Text(
                    "Couldn't load referrer requests: $requestsError",
                    style: CruType.caption.tint(c.label2),
                  ),
                  const SizedBox(height: CruSpace.s12),
                ],
                if (incoming.isNotEmpty) ...[
                  Text('Requests', style: CruType.headline.tint(c.label)),
                  const SizedBox(height: CruSpace.s8),
                  for (final r in incoming) _RequestRow(request: r),
                  const SizedBox(height: CruSpace.s20),
                ],
                if (all.isNotEmpty) ...[
                  GlanceStrip(
                    semanticLabel: 'Referrers at a glance',
                    cells: [
                      cell(
                        'Referrers',
                        '${all.length}',
                        Text('$onCruDoc on CruDoc'),
                      ),
                      cell(
                        'This month',
                        '$month',
                        Text(DateFormat('MMMM').format(now)),
                      ),
                      cell(
                        'Still open',
                        '$waiting',
                        waiting == 0
                            ? const Text('None')
                            : Text(
                                'Referrals and studies not closed yet',
                                style: CruType.caption.tint(c.amberText),
                              ),
                      ),
                      if (withFees)
                        cell(
                          'Fees this month',
                          RadFormat.rupees(fees),
                          const Text('From referred studies'),
                        ),
                    ],
                  ),
                  const SizedBox(height: CruSpace.cardGap),
                ],
                DentalFilterBar(
                  filters: const [],
                  search: DentalSearchField(
                    hint: 'Search name, clinic, specialty, CruDoc ID…',
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: CruSpace.s12),
                if (shown.isEmpty)
                  DentalEmptyState(
                    icon: RadIcons.referrer,
                    title: q.isEmpty ? 'No referrers yet' : 'No matches',
                    body: q.isEmpty
                        ? 'Find a doctor by their CruDoc ID, or save any '
                              'doctor or clinic by hand for your records. '
                              'Each one shows the referrals that went each '
                              'way.'
                        : 'Try another name, clinic or CruDoc ID.',
                    actions: [
                      if (q.isEmpty)
                        CruButton(
                          label: 'Find by CruDoc ID',
                          icon: CruIcons.search,
                          onPressed: _findById,
                        ),
                    ],
                  )
                else
                  for (final e in shown)
                    _ReferrerRow(
                      entry: e,
                      link: e.contact == null
                          ? ReferrerLink.saved
                          : referrerLinkOf(e.contact!, links),
                      request: links[e.contact?.crudocUid],
                      now: now,
                      withFees: withFees,
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferrerRow extends StatelessWidget {
  const _ReferrerRow({
    required this.entry,
    required this.link,
    required this.request,
    required this.now,
    required this.withFees,
  });

  final _Entry entry;
  final ReferrerLink link;
  final ReferrerRequest? request;
  final DateTime now;
  final bool withFees;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final e = entry;
    final cnt = e.contact;
    final phone = cruIsPhone(context);
    final accent = switch (link) {
      ReferrerLink.pending => c.amber,
      ReferrerLink.declined => c.redText,
      _ => null,
    };
    final pill = cnt == null
        ? ('Sends scans', c.inset, c.label2)
        : switch (link) {
            ReferrerLink.linked => ('On CruDoc', c.accentTint, c.accentText),
            ReferrerLink.pending => (
              'Waiting to accept',
              c.amberTint,
              c.amberText,
            ),
            ReferrerLink.declined => (
              _declinedText(request),
              c.redTint,
              c.redText,
            ),
            ReferrerLink.saved => ('Saved for records', c.inset, c.label2),
          };
    final waiting = e.waiting;
    final last = e.last;
    final fees = e.fees(now);
    return DentalListRow(
      semanticLabel: e.name,
      minHeight: 60,
      onTap: () => cnt == null
          ? showRadReferrerDetail(context, e.scanSender!)
          : showDialog<void>(
              context: context,
              builder: (_) => _ReferrerDetail(contactId: cnt.id),
            ),
      child: Row(
        children: [
          // The amber or red accent of a request not yet accepted.
          AnimatedContainer(
            duration: CruMotion.of(context, CruMotion.fast),
            curve: CruMotion.curve,
            width: 3,
            height: CruSize.iconTile,
            margin: const EdgeInsets.only(right: CruSpace.s8),
            decoration: ShapeDecoration(
              color: accent ?? c.inset.withValues(alpha: 0),
              shape: const StadiumBorder(),
            ),
          ),
          CruMonogram(name: e.name, size: CruSize.monogramRow),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: CruSpace.s8,
                  runSpacing: CruSpace.s4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(e.name, style: CruType.callout.w600.tint(c.label)),
                    CruPill(
                      text: pill.$1,
                      background: pill.$2,
                      foreground: pill.$3,
                    ),
                  ],
                ),
                Text(
                  [
                    if (cnt != null && cnt.specialty.isNotEmpty) cnt.specialty,
                    if (e.clinic.isNotEmpty) e.clinic,
                    if (e.city.isNotEmpty) e.city,
                    if (cnt != null && cnt.crudocId.isNotEmpty) cnt.crudocId,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.caption.tint(c.label2),
                ),
              ],
            ),
          ),
          // Phone: name, clinic and the chevron only.
          if (!phone) ...[
            const SizedBox(width: CruSpace.s12),
            Expanded(
              flex: 2,
              child: Text(
                e.activity(now),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CruType.subhead.tabular.tint(c.label2),
              ),
            ),
            SizedBox(
              width: 120,
              child: Text(
                waiting == 0 ? 'Nothing open' : '$waiting open',
                style: CruType.subhead.tabular.tint(
                  waiting == 0 ? c.label3 : c.amberText,
                ),
              ),
            ),
            SizedBox(
              width: 110,
              child: Text(
                last == null ? '—' : RadFormat.ago(last, now),
                style: CruType.subhead.tabular.tint(c.label2),
              ),
            ),
            if (withFees)
              SizedBox(
                width: 96,
                child: Text(
                  fees == 0 ? '—' : RadFormat.rupees(fees),
                  textAlign: TextAlign.right,
                  style: CruType.subhead.w600.tabular.tint(c.label),
                ),
              ),
          ],
          const SizedBox(width: CruSpace.s8),
          CruIcon(CruIcons.chevronRight, size: 16, color: c.label3),
        ],
      ),
    );
  }

  /// "Declined · removed in 6 h".
  static String _declinedText(ReferrerRequest? r) {
    final at = r?.answeredAt;
    if (at == null) return 'Declined';
    final left = referrerDeclineGrace - DateTime.now().difference(at);
    final hours = left.inMinutes <= 60 ? 1 : (left.inMinutes / 60).ceil();
    return 'Declined · removed in $hours h';
  }
}

// ============================================================ detail

/// One referrer: contact, the referrals that went each way month by month,
/// and a printable statement. Scan senders also open their studies.
class _ReferrerDetail extends ConsumerStatefulWidget {
  const _ReferrerDetail({required this.contactId});

  final String contactId;

  @override
  ConsumerState<_ReferrerDetail> createState() => _ReferrerDetailState();
}

class _ReferrerDetailState extends ConsumerState<_ReferrerDetail> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  Future<void> _launch(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      recToast(context, "Couldn't open that.");
    }
  }

  String _patient(DentalReferral r, List<Patient> patients) =>
      patients.where((p) => p.id == r.patientId).firstOrNull?.fullName ??
      r.share?.patientName ??
      'Patient';

  Future<void> _printStatement(
    ReferralContact who,
    List<DentalReferral> list,
    List<Patient> patients,
  ) async {
    final identity = ref.read(doctorIdentityProvider);
    final month = DateFormat('MMMM yyyy').format(_month);
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (_) => [
          pw.Text(
            identity.clinicName ?? identity.fullName ?? 'Referral statement',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          if (identity.fullName != null) pw.Text(identity.fullName!),
          pw.SizedBox(height: 16),
          pw.Text(
            'Referrals with ${who.name}'
            '${who.clinic.isEmpty ? '' : ', ${who.clinic}'}',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(month),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: ['Date', 'Patient', 'Direction', 'Reason', 'Status'],
            data: [
              for (final r in list)
                [
                  RadFormat.date(r.recordedAt),
                  _patient(r, patients),
                  r.direction.label,
                  r.reason,
                  r.status.label,
                ],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              DashFormat.plural(list.length, 'referral'),
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
    await Printing.layoutPdf(
      name: 'Referrals ${who.name} $month',
      onLayout: (_) => doc.save(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final who = ref
        .watch(referralContactsProvider)
        .where((x) => x.id == widget.contactId)
        .firstOrNull;
    if (who == null) return const SizedBox.shrink();
    final patients =
        ref.watch(patientsStreamProvider).value ?? const <Patient>[];
    String key(String s) => s.trim().toLowerCase();
    final all =
        ref
            .watch(allReferralsProvider)
            .where(
              (r) =>
                  r.contactId == who.id ||
                  (r.contactId.isEmpty && key(r.contactName) == key(who.name)),
            )
            .toList()
          ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    final scanSender =
        (ref.watch(radReferrersProvider).value ?? const <RadReferrer>[])
            .where((r) => key(r.name) == key(who.name))
            .firstOrNull;
    final inMonth = all.where((r) => _sameMonth(r.recordedAt, _month)).toList();
    final phone = who.phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final isThisMonth = _sameMonth(_month, DateTime.now());

    return DentalPanelDialog(
      title: who.name,
      subtitle: [
        who.specialty,
        who.clinic,
        who.city,
        who.crudocId,
      ].where((s) => s.isNotEmpty).join(' · '),
      leading: CruMonogram(name: who.name, size: CruSize.monogramList),
      width: CruSize.formDialog,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: CruSpace.s8),
            Wrap(
              spacing: CruSpace.s8,
              runSpacing: CruSpace.s8,
              children: [
                if (phone.isNotEmpty) ...[
                  CruButton(
                    label: 'Call',
                    icon: CruIcons.phone,
                    kind: CruButtonKind.inset,
                    onPressed: () => _launch(Uri.parse('tel:$phone')),
                  ),
                  CruButton(
                    label: 'WhatsApp',
                    icon: CruIcons.whatsapp,
                    kind: CruButtonKind.inset,
                    onPressed: () => _launch(
                      Uri.parse('https://wa.me/${phone.replaceAll('+', '')}'),
                    ),
                  ),
                ],
                if (who.email.isNotEmpty)
                  CruButton(
                    label: 'Email',
                    icon: RadIcons.mail,
                    kind: CruButtonKind.inset,
                    onPressed: () =>
                        _launch(Uri(scheme: 'mailto', path: who.email)),
                  ),
                CruButton(
                  label: 'Edit',
                  icon: CruIcons.pen,
                  kind: CruButtonKind.inset,
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => EditContactDialog(contact: who),
                  ),
                ),
                if (scanSender != null)
                  CruButton(
                    label: 'Scans and fees',
                    icon: RadIcons.referrer,
                    kind: CruButtonKind.inset,
                    onPressed: () => showRadReferrerDetail(context, scanSender),
                  ),
              ],
            ),
            if (who.notes.isNotEmpty) ...[
              const SizedBox(height: CruSpace.s12),
              Text(who.notes, style: CruType.subhead.tint(c.label2)),
            ],
            const SizedBox(height: CruSpace.s16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Referrals',
                    style: CruType.headline.tint(c.label),
                  ),
                ),
                CruIconButton(
                  icon: CruIcons.chevronLeft,
                  semanticLabel: 'Previous month',
                  tooltip: 'Previous month',
                  onPressed: () => setState(
                    () => _month = DateTime(_month.year, _month.month - 1),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: Text(
                    DateFormat('MMMM yyyy').format(_month),
                    textAlign: TextAlign.center,
                    style: CruType.subhead.w600.tint(c.label),
                  ),
                ),
                CruIconButton(
                  icon: CruIcons.chevronRight,
                  semanticLabel: 'Next month',
                  tooltip: 'Next month',
                  onPressed: isThisMonth
                      ? null
                      : () => setState(
                          () =>
                              _month = DateTime(_month.year, _month.month + 1),
                        ),
                ),
              ],
            ),
            const SizedBox(height: CruSpace.s4),
            if (inMonth.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: CruSpace.s16),
                child: Text(
                  'No referrals this month.',
                  style: CruType.subhead.tint(c.label2),
                ),
              )
            else
              for (final r in inMonth)
                DentalListRow(
                  semanticLabel: _patient(r, patients),
                  minHeight: 48,
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => r.isShared
                        ? SharedReferralDialog(referral: r)
                        : ReferralEditDialog(
                            initialReferral: r,
                            initialPatient: patients
                                .where((p) => p.id == r.patientId)
                                .firstOrNull,
                          ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 64,
                        child: Text(
                          RadFormat.shortDate(r.recordedAt),
                          style: CruType.subhead.tabular.tint(c.label2),
                        ),
                      ),
                      CruPill(
                        text: r.direction.label,
                        background: c.inset,
                        foreground: c.label2,
                      ),
                      const SizedBox(width: CruSpace.s12),
                      Expanded(
                        child: Text(
                          [
                            _patient(r, patients),
                            if (r.reason.isNotEmpty) r.reason,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CruType.subhead.tint(c.label),
                        ),
                      ),
                      const SizedBox(width: CruSpace.s8),
                      _statusPill(c, r.status),
                    ],
                  ),
                ),
          ],
        ),
      ),
      footer: Row(
        children: [
          Text(
            '${DashFormat.plural(all.length, 'referral')} in all',
            style: CruType.subhead.tint(c.label2),
          ),
          const Spacer(),
          CruButton(
            label: 'Print statement',
            icon: RadIcons.print,
            onPressed: inMonth.isEmpty
                ? null
                : () => _printStatement(who, inMonth, patients),
          ),
        ],
      ),
    );
  }

  /// Open is amber (waiting), completed green (done), the rest grey.
  static Widget _statusPill(CruColors c, ReferralStatus s) {
    final (bg, fg) = s == ReferralStatus.completed
        ? (c.greenTint, c.greenText)
        : s.isOpen
        ? (c.amberTint, c.amberText)
        : (c.inset, c.label2);
    return CruPill(text: s.label, background: bg, foreground: fg);
  }
}

/// A doctor asking to be a referrer: who, and Accept / Decline.
class _RequestRow extends ConsumerStatefulWidget {
  const _RequestRow({required this.request});

  final ReferrerRequest request;

  @override
  ConsumerState<_RequestRow> createState() => _RequestRowState();
}

class _RequestRowState extends ConsumerState<_RequestRow> {
  bool _busy = false;

  Future<void> _answer(bool accept) async {
    setState(() => _busy = true);
    await answerReferrerRequest(context, ref, widget.request, accept: accept);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final from = widget.request.from;
    final d = from.doctor;
    return Padding(
      padding: const EdgeInsets.only(bottom: CruSpace.s8),
      child: CruCard(
        padding: const EdgeInsets.all(CruSpace.s16),
        semanticLabel: 'Referrer request from ${d.name}',
        child: Row(
          children: [
            CruMonogram(name: d.name, size: CruSize.iconTile),
            const SizedBox(width: CruSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${drName(d.name)} wants to add you as a referrer',
                    style: CruType.callout.w600.tint(c.label),
                  ),
                  Text(
                    [
                      if (d.specialty.isNotEmpty) d.specialty,
                      if (d.clinicName.isNotEmpty) d.clinicName,
                      if (d.city.isNotEmpty) d.city,
                      if (from.crudocId.isNotEmpty) from.crudocId,
                    ].join(' · '),
                    style: CruType.caption.tint(c.label2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: CruSpace.s12),
            if (_busy)
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else ...[
              CruCapsuleButton(
                label: 'Decline',
                onPressed: () => _answer(false),
              ),
              const SizedBox(width: CruSpace.s8),
              CruCapsuleButton(
                label: 'Accept',
                icon: CruIcons.check,
                onPressed: () => _answer(true),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
