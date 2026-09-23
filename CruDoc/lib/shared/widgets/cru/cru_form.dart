import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:doctor_management_app/core/theme/cru_theme.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru_button.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru_card.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru_icons.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru_pressable.dart';

/// Desktop form dialog: header (leading tile, title, subtitle, close),
/// a scrolling body of [CruFormSection]s, an optional notice and a footer
/// with Cancel and the one filled action.
///
/// Esc (or Close) asks before throwing away edits when [dirty] is true.
/// Ctrl+Enter and Ctrl+S run [onSubmit].
class CruFormDialog extends StatelessWidget {
  const CruFormDialog({
    super.key,
    required this.title,
    required this.body,
    required this.submitLabel,
    required this.onSubmit,
    this.subtitle,
    this.leading,
    this.cancelLabel = 'Cancel',
    this.busy = false,
    this.dirty = false,
    this.notice,
    this.footerHint,
    this.width = CruSize.formDialog,
  });

  final String title;
  final String? subtitle;

  /// A monogram or icon tile left of the title.
  final Widget? leading;
  final Widget body;
  final String submitLabel;
  final String cancelLabel;
  final VoidCallback onSubmit;

  /// Saving: the action reads "Saving…" and both buttons are disabled.
  final bool busy;

  /// Unsaved edits: closing asks first.
  final bool dirty;

  /// A save failure, shown above the footer.
  final String? notice;

  /// Quiet text at the left of the footer.
  final String? footerHint;
  final double width;

  Future<void> _close(BuildContext context) async {
    if (busy) return;
    if (dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => const _DiscardDialog(),
      );
      if (discard != true || !context.mounted) return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final maxHeight = MediaQuery.sizeOf(context).height - CruSpace.s32 * 2;
    final submit = busy ? null : onSubmit;
    return PopScope(
      canPop: !dirty && !busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close(context);
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
              submit?.call(),
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
              submit?.call(),
        },
        child: Dialog(
          backgroundColor: c.surface,
          surfaceTintColor: c.surface.withValues(alpha: 0),
          insetPadding: const EdgeInsets.all(CruSpace.s32),
          shape: cruShape(CruRadius.card, side: BorderSide(color: c.hairline)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width, maxHeight: maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  title: title,
                  subtitle: subtitle,
                  leading: leading,
                  onClose: () => _close(context),
                ),
                const CruSeparator(),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      CruSpace.s24,
                      CruSpace.s8,
                      CruSpace.s24,
                      CruSpace.s8,
                    ),
                    child: body,
                  ),
                ),
                if (notice != null) CruFormNotice(notice!),
                const CruSeparator(),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CruSpace.s24,
                    vertical: CruSpace.s16,
                  ),
                  child: Row(
                    children: [
                      if (footerHint != null)
                        Expanded(
                          child: Text(
                            footerHint!,
                            style: CruType.caption.tint(c.label3),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      else
                        const Spacer(),
                      const SizedBox(width: CruSpace.s12),
                      CruButton(
                        label: cancelLabel,
                        kind: CruButtonKind.secondary,
                        onPressed: busy ? null : () => _close(context),
                      ),
                      const SizedBox(width: CruSpace.s10),
                      CruButton(
                        label: busy ? 'Saving…' : submitLabel,
                        onPressed: submit,
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

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.leading,
    required this.onClose,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s24,
        CruSpace.s20,
        CruSpace.s16,
        CruSpace.s20,
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: CruSpace.s14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: CruType.title2.tint(c.label)),
                if (subtitle != null) ...[
                  const SizedBox(height: CruSpace.s2),
                  Text(
                    subtitle!,
                    style: CruType.subhead.tint(c.label2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          CruIconButton(
            icon: CruIcons.close,
            onPressed: onClose,
            semanticLabel: 'Close',
            tooltip: 'Close (Esc)',
            size: CruSize.control,
            iconSize: 18,
          ),
        ],
      ),
    );
  }
}

class _DiscardDialog extends StatelessWidget {
  const _DiscardDialog();

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Dialog(
      backgroundColor: c.surface,
      surfaceTintColor: c.surface.withValues(alpha: 0),
      shape: cruShape(CruRadius.card, side: BorderSide(color: c.hairline)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: CruSize.dialog),
        child: Padding(
          padding: const EdgeInsets.all(CruSpace.s24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Discard changes?', style: CruType.title2.tint(c.label)),
              const SizedBox(height: CruSpace.s8),
              Text(
                'What you typed in this form will be lost.',
                style: CruType.text.tint(c.label2),
              ),
              const SizedBox(height: CruSpace.s24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CruButton(
                    label: 'Keep editing',
                    kind: CruButtonKind.secondary,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: CruSpace.s10),
                  CruButton(
                    label: 'Discard',
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A form section: title and a short description on the left, fields on
/// the right. Sections after the first get a separator above.
class CruFormSection extends StatelessWidget {
  const CruFormSection({
    super.key,
    required this.title,
    required this.children,
    this.description,
    this.first = false,
  });

  final String title;
  final String? description;
  final List<Widget> children;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!first) const CruSeparator(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: CruSpace.s20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: CruSize.formSectionLabel,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: CruType.callout.tint(c.label)),
                    if (description != null) ...[
                      const SizedBox(height: CruSpace.s4),
                      Text(
                        description!,
                        style: CruType.caption.tint(c.label3),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: CruSpace.s24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < children.length; i++) ...[
                      if (i > 0) const SizedBox(height: CruSpace.s16),
                      children[i],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Fields side by side with a 12 px gap, each taking [flex] share.
class CruFieldRow extends StatelessWidget {
  const CruFieldRow({super.key, required this.children, this.flex});

  final List<Widget> children;
  final List<int>? flex;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: CruSpace.s12),
          Expanded(flex: flex?[i] ?? 1, child: children[i]),
        ],
      ],
    );
  }
}

/// Label (with "Optional" or a trailing widget), the control, then help
/// or error text.
class CruFieldFrame extends StatelessWidget {
  const CruFieldFrame({
    super.key,
    required this.label,
    required this.child,
    this.optional = false,
    this.trailing,
    this.help,
    this.error,
  });

  final String label;
  final Widget child;
  final bool optional;
  final Widget? trailing;
  final String? help;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      label,
                      style: CruType.subhead.w500.tint(c.label2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (optional) ...[
                    const SizedBox(width: CruSpace.s6),
                    Text('Optional', style: CruType.caption.tint(c.label3)),
                  ],
                ],
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: CruSpace.s6),
        child,
        if (error != null)
          CruFieldError(error!)
        else if (help != null) ...[
          const SizedBox(height: CruSpace.s6),
          Text(help!, style: CruType.caption.tint(c.label3)),
        ],
      ],
    );
  }
}

/// Amber inline error under a field.
class CruFieldError extends StatelessWidget {
  const CruFieldError(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.only(top: CruSpace.s6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: CruIcon(CruIcons.warning, size: 14, color: c.amberText),
          ),
          const SizedBox(width: CruSpace.s6),
          Expanded(
            child: Text(text, style: CruType.caption.w500.tint(c.amberText)),
          ),
        ],
      ),
    );
  }
}

/// A 44 px inset text field (radius 12) that works inside a [Form].
///
/// Focus draws a 1.5 px accent ring on a surface fill; an error draws an
/// amber ring and the message below.
class CruTextField extends StatefulWidget {
  const CruTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.optional = false,
    this.help,
    this.prefix,
    this.icon,
    this.trailing,
    this.maxLines = 1,
    this.autofocus = false,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.tabular = false,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool optional;
  final String? help;

  /// Short text before the value, e.g. "₹" or "+91".
  final String? prefix;
  final CruIconData? icon;

  /// A widget at the right of the label row.
  final Widget? trailing;
  final int maxLines;
  final bool autofocus;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;

  /// Tabular figures for numbers.
  final bool tabular;

  @override
  State<CruTextField> createState() => _CruTextFieldState();
}

class _CruTextFieldState extends State<CruTextField> {
  FocusNode? _ownFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _ownFocus?.dispose();
    super.dispose();
  }

  void _onFocus() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final multiline = widget.maxLines > 1;
    return FormField<String>(
      initialValue: widget.controller.text,
      validator: widget.validator == null
          ? null
          : (_) => widget.validator!(widget.controller.text),
      builder: (field) {
        final focused = _focus.hasFocus;
        final ring = field.hasError
            ? BorderSide(color: c.amber, width: 1.5)
            : focused
                ? BorderSide(color: c.accent, width: 1.5)
                : BorderSide(color: c.inset.withValues(alpha: 0), width: 1.5);
        final base = CruType.input.tint(c.label);
        return CruFieldFrame(
          label: widget.label,
          optional: widget.optional,
          trailing: widget.trailing,
          help: widget.help,
          error: field.errorText,
          child: AnimatedContainer(
            duration: CruMotion.of(context, CruMotion.fast),
            curve: CruMotion.curve,
            constraints: const BoxConstraints(minHeight: CruSize.actionButton),
            padding: EdgeInsets.symmetric(
              horizontal: CruSpace.s14,
              vertical: multiline ? CruSpace.s10 : 0,
            ),
            decoration: ShapeDecoration(
              color: focused ? c.surface : c.inset,
              shape: cruShape(CruRadius.control, side: ring),
            ),
            alignment: multiline ? Alignment.topLeft : Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: multiline
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  CruIcon(widget.icon!, size: 17, strokeWidth: 2, color: c.label3),
                  const SizedBox(width: CruSpace.s10),
                ],
                if (widget.prefix != null) ...[
                  Text(widget.prefix!, style: CruType.input.w500.tint(c.label2)),
                  const SizedBox(width: CruSpace.s6),
                ],
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focus,
                    autofocus: widget.autofocus,
                    minLines: multiline ? widget.maxLines : 1,
                    maxLines: widget.maxLines,
                    keyboardType: multiline
                        ? TextInputType.multiline
                        : widget.keyboardType,
                    textInputAction: widget.textInputAction ??
                        (multiline ? TextInputAction.newline : TextInputAction.next),
                    textCapitalization: widget.textCapitalization,
                    inputFormatters: widget.inputFormatters,
                    cursorColor: c.accent,
                    style: widget.tabular ? base.tabular : base,
                    onChanged: (v) {
                      field.didChange(v);
                      widget.onChanged?.call(v);
                    },
                    onSubmitted: widget.onSubmitted,
                    decoration: InputDecoration.collapsed(
                      hintText: widget.hint,
                      hintStyle: CruType.input.tint(c.label3),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A 44 px inset field that opens a picker: icon, value (or placeholder),
/// an optional trailing widget and a chevron.
class CruPickerField extends StatelessWidget {
  const CruPickerField({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    required this.placeholder,
    required this.onTap,
    this.optional = false,
    this.trailing,
    this.error,
  });

  final String label;
  final CruIconData icon;
  final String? value;
  final String placeholder;
  final VoidCallback onTap;
  final bool optional;

  /// Inside the field, before the chevron (e.g. an age pill).
  final Widget? trailing;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final hasValue = value != null;
    return CruFieldFrame(
      label: label,
      optional: optional,
      error: error,
      child: CruPressable(
        onTap: onTap,
        semanticLabel: '$label, ${value ?? placeholder}',
        scaleOnPress: false,
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          height: CruSize.actionButton,
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s14),
          decoration: ShapeDecoration(
            color: hovered ? cruHoverShade(c.inset, c) : c.inset,
            shape: cruShape(
              CruRadius.control,
              side: BorderSide(
                color: error != null ? c.amber : c.inset.withValues(alpha: 0),
                width: 1.5,
              ),
            ),
          ),
          child: Row(
            children: [
              CruIcon(icon, size: 17, strokeWidth: 2, color: c.label3),
              const SizedBox(width: CruSpace.s10),
              Expanded(
                child: Text(
                  value ?? placeholder,
                  style: CruType.input.tabular.tint(hasValue ? c.label : c.label3),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trailing != null) ...[
                trailing!,
                const SizedBox(width: CruSpace.s8),
              ],
              CruIcon(CruIcons.chevronDown, size: 16, color: c.label3),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chips inside an inset box with a text input at the end. Enter or a
/// comma adds; Backspace on an empty input removes the last chip.
/// [suggestions] show underneath as capsules while there is room.
class CruTagField extends StatefulWidget {
  const CruTagField({
    super.key,
    required this.label,
    required this.values,
    required this.onChanged,
    required this.max,
    this.hint,
    this.suggestions = const [],
    this.optional = false,
  });

  final String label;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final int max;
  final String? hint;
  final List<String> suggestions;
  final bool optional;

  @override
  State<CruTagField> createState() => _CruTagFieldState();
}

class _CruTagFieldState extends State<CruTagField> {
  final _input = TextEditingController();
  final _focus = FocusNode();

  bool get _full => widget.values.length >= widget.max;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    _focus.onKeyEvent = (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.backspace &&
          _input.text.isEmpty &&
          widget.values.isNotEmpty) {
        _remove(widget.values.last);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add(String raw) {
    final v = raw.replaceAll(',', '').trim();
    _input.clear();
    if (v.isEmpty || _full) return;
    if (widget.values.any((e) => e.toLowerCase() == v.toLowerCase())) return;
    widget.onChanged([...widget.values, v]);
  }

  void _remove(String v) =>
      widget.onChanged(widget.values.where((e) => e != v).toList());

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final focused = _focus.hasFocus;
    final lower = widget.values.map((e) => e.toLowerCase()).toSet();
    final open = widget.suggestions
        .where((s) => !lower.contains(s.toLowerCase()))
        .take(5)
        .toList();
    return CruFieldFrame(
      label: widget.label,
      optional: widget.optional,
      trailing: Text(
        '${widget.values.length} of ${widget.max}',
        style: CruType.caption.tabular.tint(c.label3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _focus.requestFocus,
            child: AnimatedContainer(
              duration: CruMotion.of(context, CruMotion.fast),
              curve: CruMotion.curve,
              constraints: const BoxConstraints(minHeight: CruSize.actionButton),
              padding: const EdgeInsets.symmetric(
                horizontal: CruSpace.s8,
                vertical: CruSpace.s6,
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
              child: Wrap(
                spacing: CruSpace.s6,
                runSpacing: CruSpace.s6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final v in widget.values)
                    _Tag(label: v, onRemove: () => _remove(v)),
                  if (!_full)
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: CruSize.formTagInput,
                      ),
                      child: IntrinsicWidth(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: CruSpace.s6,
                            vertical: CruSpace.s6,
                          ),
                          child: TextField(
                            controller: _input,
                            focusNode: _focus,
                            cursorColor: c.accent,
                            textCapitalization: TextCapitalization.sentences,
                            style: CruType.input.tint(c.label),
                            onChanged: (v) {
                              if (v.endsWith(',')) _add(v);
                            },
                            onSubmitted: (v) {
                              _add(v);
                              _focus.requestFocus();
                            },
                            decoration: InputDecoration.collapsed(
                              hintText:
                                  widget.values.isEmpty ? widget.hint : 'Add another',
                              hintStyle: CruType.input.tint(c.label3),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (!_full && open.isNotEmpty) ...[
            const SizedBox(height: CruSpace.s8),
            Wrap(
              spacing: CruSpace.s6,
              runSpacing: CruSpace.s6,
              children: [
                for (final s in open)
                  IntrinsicWidth(
                    child: CruCapsuleButton(
                      label: s,
                      icon: CruIcons.plus,
                      height: CruSize.rowCapsule,
                      onPressed: () => _add(s),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.onRemove});
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      height: CruSize.pill,
      padding: const EdgeInsets.only(left: CruSpace.s10, right: CruSpace.s4),
      decoration: ShapeDecoration(
        color: c.surface,
        shape: cruShape(CruRadius.full, side: BorderSide(color: c.separator)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: CruType.caption.w500.tint(c.label)),
          const SizedBox(width: CruSpace.s2),
          CruPressable(
            onTap: onRemove,
            semanticLabel: 'Remove $label',
            builder: (context, hovered) => Container(
              width: CruSize.formTagClose,
              height: CruSize.formTagClose,
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: hovered ? c.inset : c.inset.withValues(alpha: 0),
                shape: cruShape(CruRadius.full),
              ),
              child: CruIcon(CruIcons.close, size: 12, strokeWidth: 2, color: c.label2),
            ),
          ),
        ],
      ),
    );
  }
}

/// Amber notice strip above the footer (a failed save).
class CruFormNotice extends StatelessWidget {
  const CruFormNotice(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      color: c.amberTint,
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s24,
        vertical: CruSpace.s12,
      ),
      child: Row(
        children: [
          CruIcon(CruIcons.warning, size: 16, color: c.amberText),
          const SizedBox(width: CruSpace.s10),
          Expanded(
            child: Text(text, style: CruType.subhead.w500.tint(c.amberText)),
          ),
        ],
      ),
    );
  }
}
