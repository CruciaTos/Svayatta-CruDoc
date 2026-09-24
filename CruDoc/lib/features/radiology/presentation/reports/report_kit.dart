import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/viewer/measure.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Icons only the reporting screens use (24-unit viewBox, like CruIcons).
abstract final class RadReportIcons {
  /// Lesion: an outlined blob with its centre.
  static const lesion = CruIconData(
    'M12 4.5c4.4 0 7.5 2.9 7.5 7 0 4.4-3.4 8-7.8 8-4 0-7.2-3.1-7.2-7.2 0-4.4 3.1-7.8 7.5-7.8z',
    circles: [(12, 12, 2)],
  );

  /// Addendum: a page with a plus.
  static const addendum = CruIconData(
    'M14 3.5H7.5a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2h9a2 2 0 0 0 2-2V8zM14 3.5V8h4.5M12 11v6M9 14h6',
  );

  /// Signed and locked.
  static const lock = CruIconData(
    'M8 10.5V8a4 4 0 0 1 8 0v2.5',
    rects: [(5.5, 10.5, 13, 9.5, 2)],
  );

  /// Show in folder.
  static const folderOpen = CruIconData(
    'M3.5 17V7a2 2 0 0 1 2-2h4l2 2.5h6a2 2 0 0 1 2 2V11M3.5 17l2.6-5.2a1.5 1.5 0 0 1 1.3-.8H20a1 1 0 0 1 .9 1.4L18.5 17.5a2 2 0 0 1-1.8 1H5.5a2 2 0 0 1-2-1.5z',
  );
}

// ───────────────────────────── Phrases ─────────────────────────────

bool _isSpace(String ch) => ch == ' ' || ch == '\n' || ch == '\t';

/// The word being typed before the cursor when it looks like a phrase
/// shortcut (".si"), with where it starts; null otherwise.
({String word, int start})? radTypedTrigger(TextEditingValue v) {
  final sel = v.selection;
  if (!sel.isValid || !sel.isCollapsed) return null;
  final pos = sel.baseOffset;
  final text = v.text;
  if (pos < 1 || pos > text.length) return null;
  var start = pos;
  while (start > 0 && !_isSpace(text[start - 1])) {
    start--;
  }
  final word = text.substring(start, pos);
  if (!word.startsWith('.')) return null;
  return (word: word, start: start);
}

/// Expands a shortcut (".sinus") just typed before a space or a new line.
/// Returns the new value, with the first blank ("__") selected so typing
/// fills it in, or null when the word isn't a known trigger.
TextEditingValue? radExpandPhrase(TextEditingValue v, List<RadPhrase> phrases) {
  final sel = v.selection;
  if (!sel.isValid || !sel.isCollapsed) return null;
  final pos = sel.baseOffset;
  final text = v.text;
  if (pos < 3 || pos > text.length) return null;
  final end = text[pos - 1];
  if (end != ' ' && end != '\n') return null;
  final typed = radTypedTrigger(
    TextEditingValue(text: text, selection: TextSelection.collapsed(offset: pos - 1)),
  );
  if (typed == null || typed.word.length < 2) return null;
  final hit = radPhraseFor(typed.word, phrases);
  if (hit == null) return null;
  return radInsertPhrase(v, typed.start, pos, hit.text, trailing: end);
}

/// The phrase whose trigger is exactly [word] (case doesn't matter).
RadPhrase? radPhraseFor(String word, List<RadPhrase> phrases) {
  final w = word.toLowerCase();
  for (final p in phrases) {
    if (p.trigger.toLowerCase() == w) return p;
  }
  return null;
}

/// Replaces [start]–[end] of [v] with [phrase] (plus [trailing]) and
/// selects its first blank, or puts the cursor after it.
TextEditingValue radInsertPhrase(
  TextEditingValue v,
  int start,
  int end,
  String phrase, {
  String trailing = ' ',
}) {
  final out = v.text.replaceRange(start, end, '$phrase$trailing');
  final blank = RegExp('_{2,}').firstMatch(phrase);
  return TextEditingValue(
    text: out,
    selection: blank == null
        ? TextSelection.collapsed(offset: start + phrase.length + trailing.length)
        : TextSelection(baseOffset: start + blank.start, extentOffset: start + blank.end),
  );
}

/// The next blank ("__") after the cursor, for Tab.
TextSelection? radNextBlank(TextEditingValue v) {
  final from = v.selection.isValid ? v.selection.end : 0;
  for (final m in RegExp('_{2,}').allMatches(v.text)) {
    if (m.start >= from) return TextSelection(baseOffset: m.start, extentOffset: m.end);
  }
  return null;
}

// ─────────────────────── Comma-separated terms ───────────────────────

List<String> _terms(String text) =>
    text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

/// Whether a comma-separated field already holds [term].
bool radHasTerm(String text, String term) =>
    _terms(text).any((t) => t.toLowerCase() == term.toLowerCase());

/// Adds [term] to a comma-separated field, or takes it out if it's there
/// (the descriptor chips on lesions and teeth).
String radToggleTerm(String text, String term) {
  final parts = _terms(text);
  final i = parts.indexWhere((t) => t.toLowerCase() == term.toLowerCase());
  if (i >= 0) {
    parts.removeAt(i);
  } else {
    parts.add(term);
  }
  return parts.join(', ');
}

// ───────────────────────────── Ceph values ─────────────────────────────

/// One value of a cephalometric analysis as the report shows it.
class RadCephRow {
  const RadCephRow({
    required this.name,
    required this.value,
    required this.norm,
    required this.deviates,
  });

  final String name;

  /// "84.2°", "3.1 mm".
  final String value;

  /// "82 ± 2", or empty when the analysis gave no norm.
  final String norm;

  /// Outside one standard deviation of the norm (shown amber, not red).
  final bool deviates;
}

/// The values of one traced image (the ceph screen saves them in
/// `study.extras['ceph'][imageId]`).
class RadCephTable {
  const RadCephTable({required this.imageId, required this.analysis, required this.rows});

  final String imageId;
  final String analysis;
  final List<RadCephRow> rows;
}

String _num(num v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// Mean and SD from a norm in any shape the ceph screen may store it:
/// a number, "82 ± 2", {mean, sd} or [mean, sd].
({double? mean, double? sd, String text}) _norm(Object? raw) {
  if (raw is num) return (mean: raw.toDouble(), sd: null, text: _num(raw));
  if (raw is List && raw.isNotEmpty && raw.first is num) {
    final mean = (raw.first as num).toDouble();
    final sd = raw.length > 1 && raw[1] is num ? (raw[1] as num).toDouble() : null;
    return (mean: mean, sd: sd, text: sd == null ? _num(mean) : '${_num(mean)} ± ${_num(sd)}');
  }
  if (raw is Map) {
    final mean = raw['mean'] is num ? (raw['mean'] as num).toDouble() : null;
    final sd = raw['sd'] is num ? (raw['sd'] as num).toDouble() : null;
    if (mean == null) return (mean: null, sd: null, text: '');
    return (mean: mean, sd: sd, text: sd == null ? _num(mean) : '${_num(mean)} ± ${_num(sd)}');
  }
  if (raw is String && raw.trim().isNotEmpty) {
    final m = RegExp(r'(-?\d+(?:\.\d+)?)\s*(?:±|\+/-|\+-)\s*(\d+(?:\.\d+)?)').firstMatch(raw);
    if (m != null) {
      return (mean: double.parse(m.group(1)!), sd: double.parse(m.group(2)!), text: raw.trim());
    }
    return (mean: double.tryParse(raw.trim()), sd: null, text: raw.trim());
  }
  return (mean: null, sd: null, text: '');
}

/// Every traced image's values, for the report and the PDF. Empty when the
/// study has no ceph tracing.
List<RadCephTable> radCephTables(RadStudy s) {
  final raw = s.extras['ceph'];
  if (raw is! Map) return const [];
  final out = <RadCephTable>[];
  for (final e in raw.entries) {
    final v = e.value;
    if (v is! Map) continue;
    final values = v['values'];
    if (values is! List) continue;
    final rows = <RadCephRow>[];
    for (final item in values) {
      if (item is! Map) continue;
      final name = '${item['name'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      final unit = '${item['unit'] ?? ''}'.trim();
      final rawValue = item['value'];
      final value = rawValue is num
          ? '${rawValue.toStringAsFixed(1)}${unit.isEmpty ? '' : unit == '°' ? '°' : ' $unit'}'
          : '${rawValue ?? ''}${unit.isEmpty ? '' : ' $unit'}'.trim();
      final norm = _norm(item['norm']);
      final deviates = rawValue is num &&
          norm.mean != null &&
          norm.sd != null &&
          (rawValue - norm.mean!).abs() > norm.sd!;
      rows.add(RadCephRow(name: name, value: value, norm: norm.text, deviates: deviates));
    }
    if (rows.isEmpty) continue;
    final analysis = '${v['analysis'] ?? ''}'.trim();
    out.add(RadCephTable(imageId: '${e.key}', analysis: analysis, rows: rows));
  }
  return out;
}

/// The measurement rows the report can list. Ceph values are left out
/// when the ceph table shows them already.
List<({String id, String label, String value})> radMeasurementRows(RadStudy s) {
  final rows = RadMeasure.reportRows(s);
  if (radCephTables(s).isEmpty) return rows;
  return rows.where((r) => !r.id.startsWith('ceph_')).toList();
}

// ───────────────────────────── Widgets ─────────────────────────────

/// A popup menu item in the Calm Clinical style.
PopupMenuItem<T> radMenuItem<T>(CruColors c, T value, String label, {bool enabled = true}) =>
    PopupMenuItem<T>(
      value: value,
      enabled: enabled,
      height: CruSize.control,
      child: Text(label, style: CruType.text.tint(enabled ? c.label : c.label3)),
    );

/// A multi-line report field: inset box, accent ring on focus, phrase
/// shortcuts (".sinus" + space), Tab to the next blank, and matching
/// shortcuts offered underneath while one is being typed. Signed
/// reports show the text as it prints.
class RadTextArea extends StatefulWidget {
  const RadTextArea({
    super.key,
    required this.controller,
    this.phrases = const [],
    this.hint,
    this.readOnly = false,
    this.minLines = 2,
    this.focusNode,
    this.onChanged,
    this.style,
    this.below,
  });

  final TextEditingController controller;
  final List<RadPhrase> phrases;
  final String? hint;
  final bool readOnly;
  final int minLines;
  final FocusNode? focusNode;
  final VoidCallback? onChanged;
  final TextStyle? style;

  /// Shown under the box (the dictation note).
  final Widget? below;

  @override
  State<RadTextArea> createState() => _RadTextAreaState();
}

class _RadTextAreaState extends State<RadTextArea> {
  FocusNode? _own;
  FocusNode get _focus => widget.focusNode ?? (_own ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_refresh);
  }

  @override
  void didUpdateWidget(RadTextArea old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _own)?.removeListener(_refresh);
      _focus.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_refresh);
    _own?.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _changed(String _) {
    final expanded = radExpandPhrase(widget.controller.value, widget.phrases);
    if (expanded != null) widget.controller.value = expanded;
    widget.onChanged?.call();
    setState(() {});
  }

  void _insert(RadPhrase p) {
    final typed = radTypedTrigger(widget.controller.value);
    if (typed == null) return;
    widget.controller.value = radInsertPhrase(
      widget.controller.value,
      typed.start,
      widget.controller.selection.baseOffset,
      p.text,
    );
    _focus.requestFocus();
    widget.onChanged?.call();
    setState(() {});
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyDownEvent &&
        e.logicalKey == LogicalKeyboardKey.tab &&
        !HardwareKeyboard.instance.isShiftPressed &&
        _focus.hasFocus) {
      final next = radNextBlank(widget.controller.value);
      if (next != null) {
        widget.controller.selection = next;
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final style = (widget.style ?? CruType.note).tint(c.label);
    if (widget.readOnly) {
      final text = widget.controller.text.trim();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectableText(
            text.isEmpty ? '—' : text,
            style: text.isEmpty ? style.tint(c.label3) : style,
          ),
          ?widget.below,
        ],
      );
    }
    final focused = _focus.hasFocus;
    final typed = focused ? radTypedTrigger(widget.controller.value) : null;
    final matches = typed == null
        ? const <RadPhrase>[]
        : widget.phrases
            .where((p) => p.trigger.toLowerCase().startsWith(typed.word.toLowerCase()))
            .take(6)
            .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _onKey,
          child: AnimatedContainer(
            duration: CruMotion.of(context, CruMotion.fast),
            curve: CruMotion.curve,
            padding: const EdgeInsets.symmetric(
              horizontal: CruSpace.s14,
              vertical: CruSpace.s10,
            ),
            decoration: ShapeDecoration(
              color: focused ? c.surface : c.inset,
              shape: cruShape(
                CruRadius.control,
                side: BorderSide(
                  color: focused ? c.accent : c.inset.withValues(alpha: 0),
                  width: 1.5,
                ),
              ),
            ),
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              minLines: widget.minLines,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              textCapitalization: TextCapitalization.sentences,
              cursorColor: c.accent,
              style: style,
              onChanged: _changed,
              decoration: InputDecoration.collapsed(
                hintText: widget.hint,
                hintStyle: style.tint(c.label3),
              ),
            ),
          ),
        ),
        if (matches.isNotEmpty) ...[
          const SizedBox(height: CruSpace.s8),
          Wrap(
            spacing: CruSpace.s6,
            runSpacing: CruSpace.s6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final p in matches)
                Tooltip(
                  message: p.text,
                  waitDuration: const Duration(milliseconds: 400),
                  child: CruCapsuleButton(
                    label: p.trigger,
                    height: CruSize.rowCapsule,
                    onPressed: () => _insert(p),
                  ),
                ),
              Text(
                radPhraseFor(typed!.word, matches) != null
                    ? 'Space expands it'
                    : 'Pick a phrase',
                style: CruType.caption.tint(c.label3),
              ),
            ],
          ),
        ],
        ?widget.below,
      ],
    );
  }
}

/// A heading and its content in the report column.
class RadBlock extends StatelessWidget {
  const RadBlock({
    super.key,
    required this.title,
    required this.child,
    this.trailing = const [],
    this.caption,
  });

  /// Usually a [Text]; sections pass an editable heading.
  final Widget title;
  final Widget child;
  final List<Widget> trailing;

  /// Quiet text under the heading.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CruSpace.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: DefaultTextStyle(
                  style: CruType.headline.tint(c.label),
                  child: title,
                ),
              ),
              for (final t in trailing) ...[const SizedBox(width: CruSpace.s6), t],
            ],
          ),
          if (caption != null) ...[
            const SizedBox(height: CruSpace.s2),
            Text(caption!, style: CruType.caption.tint(c.label3)),
          ],
          const SizedBox(height: CruSpace.s12),
          child,
        ],
      ),
    );
  }
}

/// A 20 px tick box (ink fill when on, like the dental choice chips).
class RadCheck extends StatelessWidget {
  const RadCheck({
    super.key,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Semantics(
      checked: value,
      child: CruPressable(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        semanticLabel: semanticLabel,
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          width: CruSpace.s20,
          height: CruSpace.s20,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: value ? c.label : (hovered ? c.hoverFill : c.surface),
            shape: cruShape(
              CruRadius.keycap,
              side: value ? BorderSide.none : BorderSide(color: c.separator, width: 1.5),
            ),
          ),
          child: value
              ? CruIcon(CruIcons.check, size: 14, strokeWidth: 2.4, color: c.surface)
              : null,
        ),
      ),
    );
  }
}

/// A violet AI action that can't run yet: no AI key is connected. Shown
/// only when the doctor turned the feature on.
class RadAiPending extends StatelessWidget {
  const RadAiPending({super.key, required this.label, required this.explain});

  final String label;

  /// What it will do once connected (tooltip).
  final String explain;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Tooltip(
      message: '$explain\nNo AI key connected.',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: 0.6,
            child: Container(
              height: CruSize.capsule,
              padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
              decoration: ShapeDecoration(color: c.aiTint, shape: const StadiumBorder()),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CruIcon(CruIcons.sparkle, size: 14, strokeWidth: 1.8, color: c.ai),
                  const SizedBox(width: CruSpace.s6),
                  Text(label, style: CruType.subhead.w600.tint(c.ai)),
                ],
              ),
            ),
          ),
          const SizedBox(width: CruSpace.s8),
          Text('No AI key connected', style: CruType.caption.tint(c.label3)),
        ],
      ),
    );
  }
}
