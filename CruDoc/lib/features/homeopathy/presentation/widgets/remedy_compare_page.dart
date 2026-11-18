import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/homeopathy/data/materia_medica_data.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Widest the page grows on desktop; it reads as a column.
const double _maxWidth = 760;

String _norm(String s) => s.trim().toLowerCase();

bool _sameText(String a, String b) => _norm(a) == _norm(b);

bool _sameList(List<String> a, List<String> b) {
  final x = {for (final s in a) _norm(s)};
  final y = {for (final s in b) _norm(s)};
  return x.length == y.length && x.containsAll(y);
}

/// Two Materia medica entries side by side. Used from the Materia medica list
/// and from the repertory result grid, so both reach the same page.
class RemedyComparePage extends StatelessWidget {
  const RemedyComparePage({super.key, required this.a, required this.b});

  final MateriaMedicaEntry a;
  final MateriaMedicaEntry b;

  static Future<void> open(
    BuildContext context,
    MateriaMedicaEntry a,
    MateriaMedicaEntry b,
  ) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => RemedyComparePage(a: a, b: b),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.cru;

    Widget bullets(List<String> items) => items.isEmpty
        ? Text('None listed', style: CruType.text.tint(c.label3))
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final k in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: CruSpace.s4),
                  child: Text('•  $k', style: CruType.text.tint(c.label)),
                ),
            ],
          );

    Widget plain(String text) => Text(
      text.isEmpty ? 'None listed' : text,
      style: CruType.text.tint(text.isEmpty ? c.label3 : c.label),
    );

    Widget row(
      String title, {
      required bool differs,
      required Widget left,
      required Widget right,
    }) => Padding(
      padding: const EdgeInsets.only(top: CruSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: CruType.groupLabel.tint(c.label3)),
              if (differs) ...[
                const SizedBox(width: CruSpace.s8),
                CruPill(
                  text: 'Differs',
                  background: c.inset,
                  foreground: c.label,
                ),
              ],
            ],
          ),
          const SizedBox(height: CruSpace.s8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              const SizedBox(width: CruSpace.s16),
              Expanded(child: right),
            ],
          ),
        ],
      ),
    );

    final relationships = <(String, List<String>, List<String>)>[
      ('Complementary', a.complementary, b.complementary),
      ('Follows well', a.followsWell, b.followsWell),
      ('Inimical', a.inimical, b.inimical),
      ('Antidotes', a.antidotes, b.antidotes),
    ];

    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CruSpace.s12,
                    vertical: CruSpace.s8,
                  ),
                  child: Row(
                    children: [
                      CruIconButton(
                        icon: CruIcons.chevronLeft,
                        onPressed: () => Navigator.pop(context),
                        semanticLabel: 'Back',
                      ),
                      const SizedBox(width: CruSpace.s4),
                      Expanded(
                        child: Text(
                          'Compare remedies',
                          style: CruType.title2.tint(c.label),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      CruSpace.s20,
                      CruSpace.s4,
                      CruSpace.s20,
                      CruSpace.s32,
                    ),
                    children: [
                      CruCard(
                        padding: const EdgeInsets.all(CruSpace.s16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final e in [a, b]) ...[
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          e.name,
                                          style: CruType.callout.w600.tint(
                                            c.label,
                                          ),
                                        ),
                                        const SizedBox(height: CruSpace.s2),
                                        Text(
                                          e.abbr,
                                          style: CruType.caption.tint(c.label2),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (e == a)
                                    const SizedBox(width: CruSpace.s16),
                                ],
                              ],
                            ),
                            row(
                              'Source',
                              differs: a.group != b.group,
                              left: plain(a.group.label),
                              right: plain(b.group.label),
                            ),
                            row(
                              'Thermal',
                              differs: a.thermal != b.thermal,
                              left: plain(a.thermal.label),
                              right: plain(b.thermal.label),
                            ),
                            row(
                              'Keynotes',
                              differs: !_sameList(a.keynotes, b.keynotes),
                              left: bullets(a.keynotes),
                              right: bullets(b.keynotes),
                            ),
                            row(
                              'Mind',
                              differs: !_sameText(a.mind, b.mind),
                              left: plain(a.mind),
                              right: plain(b.mind),
                            ),
                            row(
                              'Worse',
                              differs: !_sameText(a.worse, b.worse),
                              left: plain(a.worse),
                              right: plain(b.worse),
                            ),
                            row(
                              'Better',
                              differs: !_sameText(a.better, b.better),
                              left: plain(a.better),
                              right: plain(b.better),
                            ),
                            for (final (title, x, y) in relationships)
                              row(
                                title,
                                differs: !_sameList(x, y),
                                left: bullets(x),
                                right: bullets(y),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: CruSpace.s16),
                      Text(
                        'Quick reference — check your Materia Medica for the '
                        'full picture',
                        style: CruType.caption.tint(c.label3),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
