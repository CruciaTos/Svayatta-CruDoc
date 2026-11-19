import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/services/ai_consent.dart';
import 'package:doctor_management_app/features/homeopathy/data/providers/homeopathy_providers.dart';
import 'package:doctor_management_app/features/homeopathy/data/repertory/repertory_registry.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/widgets/homeopathy_form_helpers.dart';
import 'package:doctor_management_app/features/homeopathy/services/homeopathy_rubric_suggest_service.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Opens the "Suggest from case" sheet. Returns the ids of the rubrics the
/// physician ticked and added (empty or null when nothing was added).
Future<List<String>?> showRepertorySuggestSheet(
  BuildContext context, {
  required String patientId,
  required List<String> patientNames,
  required Set<String> alreadyAdded,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.cru.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(CruRadius.card)),
    ),
    builder: (_) => _SuggestSheet(
      patientId: patientId,
      patientNames: patientNames,
      alreadyAdded: alreadyAdded,
    ),
  );
}

enum _Phase { idle, loading, failed, done }

class _SuggestSheet extends ConsumerStatefulWidget {
  const _SuggestSheet({
    required this.patientId,
    required this.patientNames,
    required this.alreadyAdded,
  });

  final String patientId;
  final List<String> patientNames;
  final Set<String> alreadyAdded;

  @override
  ConsumerState<_SuggestSheet> createState() => _SuggestSheetState();
}

class _SuggestSheetState extends ConsumerState<_SuggestSheet> {
  final _extra = TextEditingController();
  _Phase _phase = _Phase.idle;
  String _error = '';
  List<RubricSuggestion> _found = const [];
  final _ticked = <String>{};

  @override
  void initState() {
    super.initState();
    _extra.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _extra.dispose();
    super.dispose();
  }

  String _caseText() => HomeopathyRubricSuggestService.caseText(
    ref.read(homeopathyCaseSheetProvider(widget.patientId)).value,
    extra: _extra.text,
    names: widget.patientNames,
  );

  Future<void> _run() async {
    final text = _caseText();
    if (text.isEmpty) return;
    setState(() => _phase = _Phase.loading);
    try {
      final found = await HomeopathyRubricSuggestService().suggest(text);
      if (!mounted) return;
      final fresh = [
        for (final s in found)
          if (!widget.alreadyAdded.contains(s.rubricId)) s,
      ];
      setState(() {
        _found = fresh;
        _ticked.clear();
        _phase = _Phase.done;
      });
    } on AiConsentRequired catch (e) {
      _fail('$e');
    } on FormatException {
      _fail("The AI's answer couldn't be read.");
    } catch (_) {
      _fail("Couldn't reach the AI. Check the connection.");
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _phase = _Phase.failed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    // Rebuild when the case sheet finishes loading.
    ref.watch(homeopathyCaseSheetProvider(widget.patientId));
    final hasText = _caseText().isNotEmpty;
    final rep = Repertory.instance;

    return Padding(
      padding: EdgeInsets.only(
        left: CruSpace.s20,
        right: CruSpace.s20,
        top: CruSpace.s14,
        bottom: MediaQuery.of(context).viewInsets.bottom + CruSpace.s20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: CruSpace.s32 + CruSpace.s12,
                height: CruSpace.s4,
                margin: const EdgeInsets.only(bottom: CruSpace.s16),
                decoration: ShapeDecoration(
                  color: c.track,
                  shape: cruShape(CruRadius.full),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Suggest from case',
                    style: CruType.title2.tint(c.label),
                  ),
                ),
                CruPill(
                  text: 'AI',
                  background: c.aiTint,
                  foreground: c.ai,
                  icon: CruIcons.sparkle,
                ),
              ],
            ),
            const SizedBox(height: CruSpace.s6),
            Text(
              'Reads the symptom text of the case sheet, without the name or '
              'contact details, and matches it to the rubrics in this '
              'repertory. Nothing is added until you tick it.',
              style: CruType.caption.tint(c.label2),
            ),
            const SizedBox(height: CruSpace.s14),
            HomeopathyFormField(
              controller: _extra,
              label: 'Anything to add (optional)',
              hint: 'Type or dictate symptoms not on the case sheet',
              maxLines: 4,
            ),
            const SizedBox(height: CruSpace.s12),
            if (!hasText)
              Padding(
                padding: const EdgeInsets.only(bottom: CruSpace.s12),
                child: Text(
                  'The case sheet has no symptom text yet. Add a few words '
                  'above.',
                  style: CruType.text.tint(c.label2),
                ),
              ),
            if (_phase != _Phase.done)
              CruButton(
                label: _phase == _Phase.loading
                    ? 'Reading the case...'
                    : 'Find rubrics',
                icon: CruIcons.sparkle,
                expand: true,
                onPressed: hasText && _phase != _Phase.loading ? _run : null,
              ),
            if (_phase == _Phase.failed) ...[
              const SizedBox(height: CruSpace.s12),
              Row(
                children: [
                  Expanded(
                    child: Text(_error, style: CruType.text.tint(c.label2)),
                  ),
                  CruLink(label: 'Try again', onPressed: _run),
                ],
              ),
            ],
            if (_phase == _Phase.done) ...[
              if (_found.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: CruSpace.s12),
                  child: Text(
                    'No rubric in this repertory clearly matches the case '
                    'text. Search the rubrics by hand.',
                    style: CruType.text.tint(c.label2),
                  ),
                )
              else ...[
                Text(
                  'Suggested by AI. Tick the ones that fit.',
                  style: CruType.subhead.w600.tint(c.ai),
                ),
                const SizedBox(height: CruSpace.s8),
                for (final s in _found)
                  _SuggestionRow(
                    path: rep.byId(s.rubricId)?.path ?? s.rubricId,
                    why: s.why,
                    ticked: _ticked.contains(s.rubricId),
                    onTap: () => setState(() {
                      if (!_ticked.remove(s.rubricId)) _ticked.add(s.rubricId);
                    }),
                  ),
                const SizedBox(height: CruSpace.s12),
                CruButton(
                  label: _ticked.isEmpty
                      ? 'Add selected'
                      : 'Add selected (${_ticked.length})',
                  expand: true,
                  onPressed: _ticked.isEmpty
                      ? null
                      : () => Navigator.pop(context, [
                          for (final s in _found)
                            if (_ticked.contains(s.rubricId)) s.rubricId,
                        ]),
                ),
              ],
              const SizedBox(height: CruSpace.s8),
              Center(
                child: CruLink(label: 'Run again', onPressed: _run),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A checkable AI suggestion: violet mark, rubric path, the quote that led
/// to it.
class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.path,
    required this.why,
    required this.ticked,
    required this.onTap,
  });

  final String path;
  final String why;
  final bool ticked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.only(bottom: CruSpace.s8),
      child: CruPressable(
        onTap: onTap,
        semanticLabel: '${ticked ? 'Untick' : 'Tick'} $path',
        builder: (context, hovered) => Container(
          padding: const EdgeInsets.all(CruSpace.s12),
          decoration: ShapeDecoration(
            color: c.aiTint,
            shape: cruShape(
              CruRadius.control,
              side: BorderSide(
                color: ticked ? c.ai : c.ai.withValues(alpha: 0),
                width: 1.5,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: CruSpace.s20,
                height: CruSpace.s20,
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: ticked ? c.ai : c.surface,
                  shape: cruShape(
                    CruRadius.keycap,
                    side: BorderSide(color: c.ai, width: 1.5),
                  ),
                ),
                child: ticked
                    ? CruIcon(
                        CruIcons.check,
                        size: CruSpace.s14,
                        strokeWidth: 2.4,
                        color: c.surface,
                      )
                    : null,
              ),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(path, style: CruType.text.w600.tint(c.label)),
                    if (why.isNotEmpty) ...[
                      const SizedBox(height: CruSpace.s2),
                      Text('"$why"', style: CruType.caption.tint(c.ai)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
