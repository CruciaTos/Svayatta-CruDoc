import 'package:flutter/material.dart';
import 'package:doctor_management_app/features/homeopathy/data/materia_medica_data.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/tissue_salts_screen.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/widgets/homeopathy_form_helpers.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/widgets/remedy_compare_page.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Widest the page grows on desktop; it reads as a column.
const double _maxWidth = 760;

const _footer =
    'Quick reference — check your Materia Medica for the full picture';

/// Searchable list of the bundled Materia medica entries.
class MateriaMedicaScreen extends StatefulWidget {
  const MateriaMedicaScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const MateriaMedicaScreen()));

  @override
  State<MateriaMedicaScreen> createState() => _MateriaMedicaScreenState();
}

class _MateriaMedicaScreenState extends State<MateriaMedicaScreen> {
  final _search = TextEditingController();
  RemedyGroup? _group;

  /// Up to two remedies picked for the side-by-side compare page.
  final List<MateriaMedicaEntry> _compare = [];

  void _toggleCompare(MateriaMedicaEntry e) => setState(() {
    if (_compare.contains(e)) {
      _compare.remove(e);
    } else if (_compare.length < 2) {
      _compare.add(e);
    }
  });

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(MateriaMedicaEntry e, String q) {
    if (q.isEmpty) return true;
    final qn = q.replaceAll('.', '');
    return e.name.toLowerCase().contains(q) ||
        e.abbr.toLowerCase().replaceAll('.', '').contains(qn) ||
        e.mind.toLowerCase().contains(q) ||
        e.keynotes.any((k) => k.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    OutlineInputBorder ring(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(CruRadius.control),
      borderSide: BorderSide(color: color, width: 1.5),
    );
    final q = _search.text.trim().toLowerCase();
    final shown = [
      for (final e in kMateriaMedica)
        if ((_group == null || e.group == _group) && _matches(e, q)) e,
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
                          'Materia medica',
                          style: CruType.title2.tint(c.label),
                        ),
                      ),
                      // The biochemic salts are reference material too, and
                      // a different system rather than more remedies, so
                      // they sit beside this list instead of inside it.
                      CruCapsuleButton(
                        label: 'Tissue salts',
                        onPressed: () => TissueSaltsScreen.open(context),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CruSpace.s20,
                    CruSpace.s4,
                    CruSpace.s20,
                    CruSpace.s12,
                  ),
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    style: CruType.input.tint(c.label),
                    cursorColor: c.accent,
                    decoration: InputDecoration(
                      hintText: 'Search name, abbreviation or keynote',
                      hintStyle: CruType.input.tint(c.label3),
                      prefixIcon: Padding(
                        padding: const EdgeInsets.all(CruSpace.s12),
                        child: CruIcon(
                          CruIcons.search,
                          size: CruSpace.s16,
                          color: c.label3,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: CruSpace.s12,
                        vertical: CruSpace.s12,
                      ),
                      filled: true,
                      fillColor: c.inset,
                      border: ring(c.inset.withValues(alpha: 0)),
                      enabledBorder: ring(c.inset.withValues(alpha: 0)),
                      focusedBorder: ring(c.accent),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: CruSpace.s20,
                    ),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        HomeopathyChoiceChip(
                          label: 'All',
                          selected: _group == null,
                          onSelected: (_) => setState(() => _group = null),
                        ),
                        for (final g in RemedyGroup.values)
                          HomeopathyChoiceChip(
                            label: g.label,
                            selected: _group == g,
                            onSelected: (sel) =>
                                setState(() => _group = sel ? g : null),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: CruSpace.s12),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      CruSpace.s20,
                      0,
                      CruSpace.s20,
                      CruSpace.s32,
                    ),
                    children: [
                      if (shown.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: CruSpace.s24,
                          ),
                          child: Text(
                            'No remedy matches.',
                            style: CruType.text.tint(c.label2),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      for (final e in shown)
                        Padding(
                          padding: const EdgeInsets.only(bottom: CruSpace.s8),
                          child: _EntryRow(
                            entry: e,
                            compared: _compare.contains(e),
                            canCompare:
                                _compare.length < 2 || _compare.contains(e),
                            onCompare: () => _toggleCompare(e),
                            onTap: () =>
                                MateriaMedicaDetailScreen.open(context, e),
                          ),
                        ),
                      const SizedBox(height: CruSpace.s12),
                      Text(
                        _footer,
                        style: CruType.caption.tint(c.label3),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                if (_compare.isNotEmpty)
                  Container(
                    padding: EdgeInsets.fromLTRB(
                      CruSpace.s20,
                      CruSpace.s12,
                      CruSpace.s20,
                      CruSpace.s12 + MediaQuery.of(context).padding.bottom,
                    ),
                    decoration: BoxDecoration(
                      color: c.surface,
                      border: Border(top: BorderSide(color: c.hairline)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: CruButton(
                            label: _compare.length == 2
                                ? 'Compare ${_compare[0].abbr} and '
                                      '${_compare[1].abbr}'
                                : 'Pick one more remedy to compare',
                            onPressed: _compare.length == 2
                                ? () => RemedyComparePage.open(
                                    context,
                                    _compare[0],
                                    _compare[1],
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(width: CruSpace.s8),
                        CruIconButton(
                          icon: CruIcons.close,
                          onPressed: () => setState(_compare.clear),
                          semanticLabel: 'Clear compare selection',
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

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.onTap,
    required this.compared,
    required this.canCompare,
    required this.onCompare,
  });

  final MateriaMedicaEntry entry;
  final VoidCallback onTap;
  final bool compared;
  final bool canCompare;
  final VoidCallback onCompare;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruPressable(
      onTap: onTap,
      semanticLabel: entry.name,
      builder: (context, hovered) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: CruSpace.s16,
          vertical: CruSpace.s12,
        ),
        decoration: BoxDecoration(
          color: hovered ? c.hoverFill : c.surface,
          borderRadius: BorderRadius.circular(CruRadius.control),
          border: Border.all(color: c.cardBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${entry.name} · ${entry.abbr}',
                    style: CruType.callout.w600.tint(c.label),
                  ),
                  const SizedBox(height: CruSpace.s2),
                  Text(
                    '${entry.group.label} · ${entry.keynotes.first}',
                    style: CruType.caption.tint(c.label2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: CruSpace.s8),
            CruPressable(
              onTap: canCompare ? onCompare : null,
              semanticLabel: compared
                  ? 'Remove ${entry.name} from compare'
                  : 'Compare ${entry.name}',
              builder: (context, hovered) => Container(
                height: CruSize.pill,
                padding: const EdgeInsets.symmetric(horizontal: CruSpace.s10),
                decoration: ShapeDecoration(
                  color: c.inset,
                  shape: StadiumBorder(
                    side: compared
                        ? BorderSide(color: c.accent)
                        : BorderSide.none,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CruIcon(
                      compared ? CruIcons.check : CruIcons.plus,
                      size: CruSpace.s14,
                      color: compared ? c.accentText : c.label2,
                    ),
                    const SizedBox(width: CruSpace.s4),
                    Text(
                      'Compare',
                      style: CruType.caption.w600.tint(
                        !canCompare
                            ? c.label3
                            : (compared ? c.accentText : c.label2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: CruSpace.s4),
            CruIcon(CruIcons.chevronRight, size: CruSpace.s18, color: c.label3),
          ],
        ),
      ),
    );
  }
}

/// One remedy's quick-reference page.
class MateriaMedicaDetailScreen extends StatelessWidget {
  const MateriaMedicaDetailScreen({super.key, required this.entry});

  final MateriaMedicaEntry entry;

  static Future<void> open(BuildContext context, MateriaMedicaEntry entry) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MateriaMedicaDetailScreen(entry: entry),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.cru;

    Widget section(String title, Widget body) => Padding(
      padding: const EdgeInsets.only(top: CruSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: CruType.groupLabel.tint(c.label3)),
          const SizedBox(height: CruSpace.s8),
          body,
        ],
      ),
    );

    Widget line(String label, String text) => Padding(
      padding: const EdgeInsets.only(bottom: CruSpace.s6),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$label  ', style: CruType.text.w600.tint(c.label)),
            TextSpan(text: text, style: CruType.text.tint(c.label)),
          ],
        ),
      ),
    );

    Widget related(String label, List<String> names) {
      if (names.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: CruSpace.s10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: CruType.subhead.w600.tint(c.label2)),
            const SizedBox(height: CruSpace.s6),
            Wrap(
              spacing: CruSpace.s6,
              runSpacing: CruSpace.s6,
              children: [
                for (final n in names)
                  _RelatedChip(
                    name: n,
                    onTap: materiaMedicaFor(n) == null
                        ? null
                        : () => MateriaMedicaDetailScreen.open(
                            context,
                            materiaMedicaFor(n)!,
                          ),
                  ),
              ],
            ),
          ],
        ),
      );
    }

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
                          entry.name,
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
                            Wrap(
                              spacing: CruSpace.s6,
                              runSpacing: CruSpace.s4,
                              children: [
                                for (final t in [
                                  entry.abbr,
                                  entry.group.label,
                                  entry.thermal.label,
                                ])
                                  CruPill(
                                    text: t,
                                    background: c.inset,
                                    foreground: c.label2,
                                  ),
                              ],
                            ),
                            section(
                              'Keynotes',
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final k in entry.keynotes)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: CruSpace.s6,
                                      ),
                                      child: Text(
                                        '•  $k',
                                        style: CruType.text.tint(c.label),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            section(
                              'Mind',
                              Text(
                                entry.mind,
                                style: CruType.text.tint(c.label),
                              ),
                            ),
                            section(
                              'Modalities',
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  line('Worse', entry.worse),
                                  line('Better', entry.better),
                                ],
                              ),
                            ),
                            if (entry.hasRelationships)
                              section(
                                'Relationships',
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    related(
                                      'Complementary',
                                      entry.complementary,
                                    ),
                                    related('Follows well', entry.followsWell),
                                    related('Inimical', entry.inimical),
                                    related('Antidotes', entry.antidotes),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: CruSpace.s16),
                      Text(
                        _footer,
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

class _RelatedChip extends StatelessWidget {
  const _RelatedChip({required this.name, required this.onTap});

  final String name;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final pill = CruPill(
      text: name,
      background: c.inset,
      foreground: onTap == null ? c.label2 : c.label,
    );
    if (onTap == null) return pill;
    return CruPressable(
      onTap: onTap!,
      semanticLabel: name,
      builder: (context, hovered) => pill,
    );
  }
}
