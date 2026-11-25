import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/homeopathy/data/tissue_salts.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The twelve biochemic tissue salts, looked up by number, by name or by
/// what they are for.
///
/// Searching by indication is the point rather than a nicety: the biochemic
/// system is prescribed by looking up a symptom and reading off the salt, so
/// typing "cramp" has to reach No. 8. Typing a bare number works too, since
/// that is how clinics and labels refer to them.
class TissueSaltsScreen extends StatefulWidget {
  const TissueSaltsScreen({super.key});

  /// Widest the page grows on desktop; it reads as a column.
  static const double _maxWidth = 760;

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
    rootNavigator: true,
  ).push(MaterialPageRoute<void>(builder: (_) => const TissueSaltsScreen()));

  @override
  State<TissueSaltsScreen> createState() => _TissueSaltsScreenState();
}

class _TissueSaltsScreenState extends State<TissueSaltsScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final shown = searchTissueSalts(_search.text);

    OutlineInputBorder ring(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(CruRadius.control),
      borderSide: BorderSide(color: color, width: 1.5),
    );

    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: TissueSaltsScreen._maxWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CruSpace.s16,
                    CruSpace.s12,
                    CruSpace.s16,
                    CruSpace.s8,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: CruIcon(
                          CruIcons.chevronLeft,
                          size: 20,
                          color: c.label2,
                        ),
                        tooltip: 'Back',
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tissue salts',
                              style: CruType.title2.tint(c.label),
                            ),
                            Text(
                              'The twelve biochemic salts, as Schuessler '
                              'numbered them',
                              style: CruType.caption.tint(c.label2),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: CruSpace.s16),
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    style: CruType.body.tint(c.label),
                    decoration: InputDecoration(
                      hintText: 'Number, name, or what it is for',
                      hintStyle: CruType.body.tint(c.label3),
                      filled: true,
                      fillColor: c.surface,
                      prefixIcon: Padding(
                        padding: const EdgeInsets.all(CruSpace.s12),
                        child: CruIcon(
                          CruIcons.search,
                          size: 18,
                          color: c.label3,
                        ),
                      ),
                      border: ring(c.hairline),
                      enabledBorder: ring(c.hairline),
                      focusedBorder: ring(c.accent),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: CruSpace.s12,
                        vertical: CruSpace.s12,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: shown.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(CruSpace.s24),
                            child: Text(
                              'No salt matches that.',
                              style: CruType.callout.tint(c.label2),
                            ),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(
                            CruSpace.s16,
                            CruSpace.s12,
                            CruSpace.s16,
                            CruSpace.s24,
                          ),
                          children: [
                            for (final s in shown) ...[
                              _SaltCard(salt: s),
                              const SizedBox(height: CruSpace.cardGap),
                            ],
                            // How they are given, once, under the list.
                            // Repeating a schedule on every salt would
                            // suggest the salts differ in dosing, and they
                            // do not.
                            CruCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'HOW THEY ARE GIVEN',
                                    style: CruType.groupLabel.tint(c.label2),
                                  ),
                                  const SizedBox(height: CruSpace.s8),
                                  Text(
                                    kTissueSaltDosing,
                                    style: CruType.subhead.tint(c.label),
                                  ),
                                  const SizedBox(height: CruSpace.s8),
                                  Text(
                                    'Quick reference — the dose is still '
                                    'the prescriber\'s.',
                                    style: CruType.caption.tint(c.label3),
                                  ),
                                ],
                              ),
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

class _SaltCard extends StatelessWidget {
  const _SaltCard({required this.salt});

  final TissueSalt salt;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruCard(
      semanticLabel: '${salt.label}, ${salt.remedy}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The number is the handle in this system, so it leads.
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.inset,
                  borderRadius: BorderRadius.circular(CruRadius.iconTile),
                ),
                child: Text(
                  '${salt.number}',
                  style: CruType.callout.w600.tabular.tint(c.label2),
                ),
              ),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(salt.abbr, style: CruType.headline.w600.tint(c.label)),
                    Text(salt.remedy, style: CruType.caption.tint(c.label2)),
                  ],
                ),
              ),
              CruPill(
                text: salt.potency,
                background: c.inset,
                foreground: c.label2,
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s12),
          Text(salt.tissue, style: CruType.subhead.tint(c.label)),
          const SizedBox(height: CruSpace.s8),
          for (final i in salt.indications)
            Padding(
              padding: const EdgeInsets.only(top: CruSpace.s4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('·  ', style: CruType.subhead.tint(c.label3)),
                  Expanded(
                    child: Text(i, style: CruType.subhead.tint(c.label2)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
