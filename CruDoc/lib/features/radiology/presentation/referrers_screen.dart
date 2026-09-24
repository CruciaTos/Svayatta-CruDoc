import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/glance_card.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/open_study.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_dialogs.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

bool _sameMonth(DateTime a, DateTime b) => a.year == b.year && a.month == b.month;

/// The dentists and clinics who send scans: how many, what's waiting,
/// what they owe this month.
class RadReferrersScreen extends ConsumerStatefulWidget {
  const RadReferrersScreen({super.key});

  @override
  ConsumerState<RadReferrersScreen> createState() => _RadReferrersScreenState();
}

class _RadReferrersScreenState extends ConsumerState<RadReferrersScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final referrers = ref.watch(radReferrersProvider).value;
    final studies = ref.watch(radStudiesProvider).value ?? const <RadStudy>[];
    final now = DateTime.now();

    final byReferrer = <String, List<RadStudy>>{};
    for (final s in studies) {
      if (s.referrerId.isNotEmpty) (byReferrer[s.referrerId] ??= []).add(s);
    }
    final month = studies.where((s) => s.referrerId.isNotEmpty && _sameMonth(s.receivedAt, now));
    final waiting = studies.where((s) => s.referrerId.isNotEmpty && s.status.isOpen).length;
    final billed = month.fold<double>(0, (t, s) => t + (s.fee ?? 0));

    final q = _query.trim().toLowerCase();
    final shown = (referrers ?? const <RadReferrer>[])
        .where((r) =>
            q.isEmpty ||
            r.name.toLowerCase().contains(q) ||
            r.clinic.toLowerCase().contains(q) ||
            r.city.toLowerCase().contains(q))
        .toList()
      // Busiest this month first.
      ..sort((a, b) {
        int n(RadReferrer r) =>
            (byReferrer[r.id] ?? const []).where((s) => _sameMonth(s.receivedAt, now)).length;
        final d = n(b).compareTo(n(a));
        return d != 0 ? d : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    Widget cell(String label, String value, Widget caption) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [GlanceLabel(label), GlanceMetric(value), GlanceCaption(caption)],
        );

    return Padding(
      padding: CruSpace.mainPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DentalPageHeader(
            title: 'Referrers',
            subtitle: referrers == null || referrers.isEmpty
                ? 'Dentists and clinics who send you scans'
                : '${DashFormat.plural(referrers.length, 'referrer')} · '
                    '${DashFormat.plural(month.length, 'study', 'studies')} this month',
            actions: [
              CruButton(
                label: 'Add referrer',
                icon: CruIcons.plus,
                onPressed: () => showRadReferrerDialog(context),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.cardGap),
          if (referrers == null)
            const SkeletonCard(rows: 1, rowHeight: 72)
          else
            GlanceStrip(
              semanticLabel: 'Referrers at a glance',
              cells: [
                cell('Referrers', '${referrers.length}',
                    Text('${byReferrer.keys.length} have sent studies')),
                cell('This month', '${month.length}',
                    Text(DateFormat('MMMM').format(now))),
                cell(
                  'Waiting for a report',
                  '$waiting',
                  waiting == 0
                      ? const Text('None')
                      : Text('Referred studies not signed yet',
                          style: CruType.caption.tint(c.amberText)),
                ),
                cell('Fees this month', RadFormat.rupees(billed),
                    const Text('From referred studies')),
              ],
            ),
          const SizedBox(height: CruSpace.cardGap),
          Row(
            children: [
              const Spacer(),
              SizedBox(
                width: 300,
                child: DentalSearchField(
                  controller: _search,
                  hint: 'Search name, clinic or city',
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.cardGap),
          Expanded(
            child: CruCard(
              semanticLabel: 'Referrers',
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: referrers == null
                  ? const SizedBox.shrink()
                  : shown.isEmpty
                      ? Center(
                          child: SingleChildScrollView(
                            child: DentalEmptyState(
                              icon: RadIcons.referrer,
                              title: referrers.isEmpty ? 'No referrers yet' : 'No one here',
                              body: referrers.isEmpty
                                  ? 'Add the dentists who send you scans. Each study shows '
                                      'who referred it, reports go back to them, and their '
                                      'monthly statement adds itself up.'
                                  : 'Try another search.',
                              actions: [
                                if (referrers.isEmpty)
                                  CruButton(
                                    label: 'Add referrer',
                                    icon: CruIcons.plus,
                                    onPressed: () => showRadReferrerDialog(context),
                                  ),
                              ],
                            ),
                          ),
                        )
                      : ListView(
                          children: [
                            const SizedBox(height: CruSpace.s8),
                            for (var i = 0; i < shown.length; i++) ...[
                              if (i > 0) const CruSeparator(indent: 12 + 34 + 12),
                              _ReferrerRow(
                                referrer: shown[i],
                                studies: byReferrer[shown[i].id] ?? const [],
                                now: now,
                              ),
                            ],
                          ],
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferrerRow extends StatelessWidget {
  const _ReferrerRow({required this.referrer, required this.studies, required this.now});

  final RadReferrer referrer;
  final List<RadStudy> studies;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final month = studies.where((s) => _sameMonth(s.receivedAt, now)).toList();
    final waiting = studies.where((s) => s.status.isOpen).length;
    final last = studies.isEmpty
        ? null
        : studies.map((s) => s.receivedAt).reduce((a, b) => a.isAfter(b) ? a : b);
    final fees = month.fold<double>(0, (t, s) => t + (s.fee ?? 0));
    return DentalListRow(
      semanticLabel: referrer.name,
      onTap: () => showRadReferrerDetail(context, referrer),
      minHeight: 60,
      child: Row(
        children: [
          CruMonogram(name: referrer.name, size: CruSize.monogramRow),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(referrer.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CruType.callout.tint(c.label)),
                Text(
                  [referrer.clinic, referrer.city].where((s) => s.isNotEmpty).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.subhead.tint(c.label2),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${DashFormat.plural(studies.length, 'study', 'studies')} · ${month.length} this month',
              style: CruType.subhead.tabular.tint(c.label2),
            ),
          ),
          SizedBox(
            width: 120,
            child: Text(
              waiting == 0 ? 'Nothing waiting' : '$waiting waiting',
              style: CruType.subhead.tabular.tint(waiting == 0 ? c.label3 : c.amberText),
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              last == null ? 'No studies yet' : RadFormat.ago(last, now),
              style: CruType.subhead.tabular.tint(c.label2),
            ),
          ),
          SizedBox(
            width: 96,
            child: Text(
              fees == 0 ? '—' : RadFormat.rupees(fees),
              textAlign: TextAlign.right,
              style: CruType.subhead.w600.tabular.tint(c.label),
            ),
          ),
          const SizedBox(width: CruSpace.s8),
          CruIcon(CruIcons.chevronRight, size: 16, color: c.label3),
        ],
      ),
    );
  }
}

// ============================================================ detail

/// One referrer: contact, their studies and the monthly statement.
Future<void> showRadReferrerDetail(BuildContext context, RadReferrer referrer) =>
    showDialog<void>(context: context, builder: (_) => _ReferrerDetail(referrerId: referrer.id));

class _ReferrerDetail extends ConsumerStatefulWidget {
  const _ReferrerDetail({required this.referrerId});

  final String referrerId;

  @override
  ConsumerState<_ReferrerDetail> createState() => _ReferrerDetailState();
}

class _ReferrerDetailState extends ConsumerState<_ReferrerDetail> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  Future<void> _launch(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      radToast(context, "Couldn't open that.");
    }
  }

  Future<void> _printStatement(RadReferrer r, List<RadStudy> studies) async {
    final identity = ref.read(doctorIdentityProvider);
    final month = DateFormat('MMMM yyyy').format(_month);
    final total = studies.fold<double>(0, (t, s) => t + (s.fee ?? 0));
    String inr(double v) => 'Rs ${NumberFormat('#,##,##0', 'en_IN').format(v)}';
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (_) => [
        pw.Text(identity.clinicName ?? identity.fullName ?? 'Radiology statement',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        if (identity.fullName != null) pw.Text(identity.fullName!),
        pw.SizedBox(height: 16),
        pw.Text('Statement for ${r.name}${r.clinic.isEmpty ? '' : ', ${r.clinic}'}',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.Text(month),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: ['Date', 'Patient', 'Study', 'Status', 'Fee'],
          data: [
            for (final s in studies)
              [
                RadFormat.date(s.receivedAt),
                s.patientName,
                s.modality.label,
                s.status.label,
                s.fee == null ? '-' : inr(s.fee!),
              ],
          ],
          cellAlignments: {4: pw.Alignment.centerRight},
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Total ${inr(total)}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
        ),
      ],
    ));
    await Printing.layoutPdf(
      name: 'Statement ${r.name} $month',
      onLayout: (_) => doc.save(),
    );
    await ref.read(radiologyProvider).log('Printed statement',
        targetKind: 'referrer', targetId: r.id, detail: '${r.name} · $month');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final r = ref.watch(radReferrerByIdProvider)[widget.referrerId];
    if (r == null) return const SizedBox.shrink();
    final all = (ref.watch(radStudiesProvider).value ?? const <RadStudy>[])
        .where((s) => s.referrerId == r.id)
        .toList()
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    final inMonth = all.where((s) => _sameMonth(s.receivedAt, _month)).toList();
    final total = inMonth.fold<double>(0, (t, s) => t + (s.fee ?? 0));
    final phone = r.phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final now = DateTime.now();
    final isThisMonth = _sameMonth(_month, now);

    return DentalPanelDialog(
      title: r.name,
      subtitle: [r.clinic, r.city, if (r.regNo.isNotEmpty) 'Reg. ${r.regNo}']
          .where((s) => s.isNotEmpty)
          .join(' · '),
      leading: CruMonogram(name: r.name, size: CruSize.monogramList),
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
                        Uri.parse('https://wa.me/${phone.replaceAll('+', '')}')),
                  ),
                ],
                if (r.email.isNotEmpty)
                  CruButton(
                    label: 'Email',
                    icon: RadIcons.mail,
                    kind: CruButtonKind.inset,
                    onPressed: () => _launch(Uri(scheme: 'mailto', path: r.email)),
                  ),
                CruButton(
                  label: 'Edit',
                  icon: CruIcons.pen,
                  kind: CruButtonKind.inset,
                  onPressed: () => showRadReferrerDialog(context, existing: r),
                ),
              ],
            ),
            if (r.notes.isNotEmpty) ...[
              const SizedBox(height: CruSpace.s12),
              Text(r.notes, style: CruType.subhead.tint(c.label2)),
            ],
            const SizedBox(height: CruSpace.s16),
            Row(
              children: [
                Expanded(
                  child: Text('Statement', style: CruType.headline.tint(c.label)),
                ),
                CruIconButton(
                  icon: CruIcons.chevronLeft,
                  semanticLabel: 'Previous month',
                  tooltip: 'Previous month',
                  onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
                ),
                SizedBox(
                  width: 120,
                  child: Text(DateFormat('MMMM yyyy').format(_month),
                      textAlign: TextAlign.center, style: CruType.subhead.w600.tint(c.label)),
                ),
                CruIconButton(
                  icon: CruIcons.chevronRight,
                  semanticLabel: 'Next month',
                  tooltip: 'Next month',
                  onPressed: isThisMonth
                      ? null
                      : () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
                ),
              ],
            ),
            const SizedBox(height: CruSpace.s4),
            if (inMonth.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: CruSpace.s16),
                child: Text('No studies this month.', style: CruType.subhead.tint(c.label2)),
              )
            else ...[
              for (final s in inMonth)
                DentalListRow(
                  semanticLabel: s.patientName,
                  minHeight: 48,
                  onTap: () {
                    Navigator.of(context).pop();
                    openRadStudy(context, ref, s);
                  },
                  child: Row(
                    children: [
                      SizedBox(
                        width: 64,
                        child: Text(RadFormat.shortDate(s.receivedAt),
                            style: CruType.subhead.tabular.tint(c.label2)),
                      ),
                      RadModalityBadge(s.modality),
                      const SizedBox(width: CruSpace.s12),
                      Expanded(
                        child: Text(s.patientName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CruType.subhead.tint(c.label)),
                      ),
                      radStatusPill(c, s.status),
                      SizedBox(
                        width: 90,
                        child: Text(
                          s.fee == null ? '—' : RadFormat.rupees(s.fee!),
                          textAlign: TextAlign.right,
                          style: CruType.subhead.tabular.tint(c.label),
                        ),
                      ),
                    ],
                  ),
                ),
              const CruSeparator(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12, vertical: CruSpace.s10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(DashFormat.plural(inMonth.length, 'study', 'studies'),
                          style: CruType.subhead.tint(c.label2)),
                    ),
                    Text(RadFormat.rupees(total),
                        style: CruType.headline.tabular.tint(c.label)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      footer: Row(
        children: [
          Text('${DashFormat.plural(all.length, 'study', 'studies')} in all',
              style: CruType.subhead.tint(c.label2)),
          const Spacer(),
          CruButton(
            label: 'Print statement',
            icon: RadIcons.print,
            onPressed: inMonth.isEmpty ? null : () => _printStatement(r, inMonth),
          ),
        ],
      ),
    );
  }
}
