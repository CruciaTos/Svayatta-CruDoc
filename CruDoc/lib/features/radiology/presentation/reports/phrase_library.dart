import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Shortcut phrases: typing the trigger (".sinus") and a space in any
/// report field puts in the text.
Future<void> showRadPhraseLibrary(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _PhraseLibrary());

class _PhraseLibrary extends ConsumerStatefulWidget {
  const _PhraseLibrary();

  @override
  ConsumerState<_PhraseLibrary> createState() => _PhraseLibraryState();
}

class _PhraseLibraryState extends ConsumerState<_PhraseLibrary> {
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
    final phrases = ref.watch(radPhrasesProvider).value ?? const <RadPhrase>[];
    final q = _query.trim().toLowerCase();
    final shown = phrases
        .where((p) =>
            q.isEmpty || p.trigger.toLowerCase().contains(q) || p.text.toLowerCase().contains(q))
        .toList();
    return DentalPanelDialog(
      title: 'Phrases',
      subtitle: 'Type a shortcut and a space in any report field to expand it',
      leading: const CruIconTile(icon: RadIcons.phrase, tone: CruTileTone.accent),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (phrases.length > 6)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CruSpace.s8,
                CruSpace.s8,
                CruSpace.s8,
                CruSpace.s4,
              ),
              child: DentalSearchField(
                controller: _search,
                hint: 'Search shortcuts and wording',
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
          if (phrases.isEmpty)
            DentalEmptyState(
              icon: RadIcons.phrase,
              title: 'No phrases yet',
              body: 'Save the sentences you write again and again, with a short '
                  'trigger like .sinus. Blanks written as __ are selected after '
                  'expanding, and Tab jumps to the next one.',
              actions: [
                CruButton(
                  label: 'New phrase',
                  icon: CruIcons.plus,
                  onPressed: () => _showPhraseEditor(context, phrases: phrases),
                ),
              ],
            )
          else if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.all(CruSpace.s24),
              child: Text(
                'No phrase matches "$_query".',
                textAlign: TextAlign.center,
                style: CruType.subhead.tint(c.label2),
              ),
            )
          else
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0) const CruSeparator(indent: CruSpace.s12),
              DentalListRow(
                semanticLabel: '${shown[i].trigger}: ${shown[i].text}',
                onTap: () => _showPhraseEditor(context, phrases: phrases, existing: shown[i]),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(
                        shown[i].trigger,
                        style: CruType.callout.tint(c.label),
                      ),
                    ),
                    const SizedBox(width: CruSpace.s12),
                    Expanded(
                      child: Text(
                        shown[i].text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: CruType.subhead.tint(c.label2),
                      ),
                    ),
                  ],
                ),
              ),
            ],
        ],
      ),
      footer: phrases.isEmpty
          ? null
          : Row(
              children: [
                Expanded(
                  child: Text(
                    'Blanks written as __ are selected after expanding; Tab jumps to the next.',
                    style: CruType.caption.tint(c.label3),
                  ),
                ),
                const SizedBox(width: CruSpace.s12),
                CruButton(
                  label: 'New phrase',
                  icon: CruIcons.plus,
                  onPressed: () => _showPhraseEditor(context, phrases: phrases),
                ),
              ],
            ),
    );
  }
}

Future<void> _showPhraseEditor(
  BuildContext context, {
  required List<RadPhrase> phrases,
  RadPhrase? existing,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _PhraseEditor(phrases: phrases, existing: existing),
    );

class _PhraseEditor extends ConsumerStatefulWidget {
  const _PhraseEditor({required this.phrases, this.existing});

  final List<RadPhrase> phrases;
  final RadPhrase? existing;

  @override
  ConsumerState<_PhraseEditor> createState() => _PhraseEditorState();
}

class _PhraseEditorState extends ConsumerState<_PhraseEditor> {
  final _form = GlobalKey<FormState>();
  late final _trigger = TextEditingController(text: widget.existing?.trigger ?? '.');
  late final _text = TextEditingController(text: widget.existing?.text ?? '');
  bool _dirty = false;
  bool _busy = false;
  bool _submitted = false;
  String? _notice;

  @override
  void dispose() {
    _trigger.dispose();
    _text.dispose();
    super.dispose();
  }

  void _edited() {
    if (!_dirty) setState(() => _dirty = true);
  }

  /// ".sinus": a dot, then letters or digits, no spaces, not taken.
  String? _checkTrigger(String? v) {
    final t = (v ?? '').trim();
    if (t.length < 2 || !t.startsWith('.')) return 'Start with a dot, like .sinus';
    if (t.contains(RegExp(r'\s'))) return 'No spaces in a shortcut.';
    final taken = widget.phrases.any((p) =>
        p.id != widget.existing?.id && p.trigger.toLowerCase() == t.toLowerCase());
    return taken ? '$t is already used.' : null;
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      await ref.read(radiologyProvider).savePhrase(RadPhrase(
            id: widget.existing?.id ?? radId('phr_'),
            trigger: _trigger.text.trim(),
            text: _text.text.trim(),
          ));
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      setState(() {
        _busy = false;
        _notice = "Couldn't save the phrase. Try again.";
      });
    }
  }

  Future<void> _delete() async {
    final e = widget.existing;
    if (e == null) return;
    final ok = await confirmDental(
      context,
      title: 'Delete ${e.trigger}?',
      body: 'The shortcut stops expanding. Reports already written keep their text.',
      action: 'Delete',
    );
    if (!ok || !mounted) return;
    await ref.read(radiologyProvider).deletePhrase(e);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return CruFormDialog(
      title: widget.existing == null ? 'New phrase' : 'Edit phrase',
      subtitle: widget.existing?.trigger,
      leading: const CruIconTile(icon: RadIcons.phrase, tone: CruTileTone.accent),
      submitLabel: widget.existing == null ? 'Add phrase' : 'Save phrase',
      onSubmit: _save,
      busy: _busy,
      dirty: _dirty,
      notice: _notice,
      footerHint: 'Ctrl + Enter to save',
      width: CruSize.formDialog - 80,
      body: Form(
        key: _form,
        autovalidateMode:
            _submitted ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
        child: CruFormSection(
          first: true,
          title: 'Phrase',
          description: 'Write __ where a value goes: it is selected after expanding, and '
              'Tab moves to the next one.',
          children: [
            CruTextField(
              label: 'Shortcut',
              controller: _trigger,
              hint: '.sinus',
              autofocus: widget.existing == null,
              inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
              validator: _checkTrigger,
              onChanged: (_) => _edited(),
            ),
            CruTextField(
              label: 'Expands to',
              controller: _text,
              maxLines: 5,
              hint: 'Both maxillary sinuses are well pneumatised and clear.',
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => (v ?? '').trim().isEmpty ? 'Write the text it puts in.' : null,
              onChanged: (_) => _edited(),
            ),
            if (widget.existing != null)
              Align(
                alignment: Alignment.centerLeft,
                child: CruLink(label: 'Delete this phrase', onPressed: _delete),
              ),
          ],
        ),
      ),
    );
  }
}
