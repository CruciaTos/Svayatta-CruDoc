import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// What kind of value an input takes, as far as voice is concerned.
enum VoiceFieldType {
  text,
  multiline,
  number,
  phone,
  email,

  /// One of [VoiceFormField.options].
  choice,

  /// On / off.
  toggle,

  /// Several short values (tags, conditions).
  list,
}

/// One input on the form on screen that voice can fill.
class VoiceFormField {
  VoiceFormField._({
    required this.id,
    required this.key,
    required this.label,
    required this.type,
    required this.element,
    required String Function() read,
    required bool Function(String value) write,
    required VoidCallback Function() snapshot,
    this.options = const [],
  }) : _read = read,
       _write = write,
       _snapshot = snapshot;

  /// Short id the extraction model refers to ("f3").
  final String id;

  /// Stays the same across scans of the same form, so voice remembers
  /// which inputs it filled itself.
  final String key;

  /// The input's label as the doctor sees it.
  final String label;
  final VoiceFieldType type;

  /// The choices of a [VoiceFieldType.choice] input, as shown.
  final List<String> options;

  final Element element;
  final String Function() _read;
  final bool Function(String value) _write;
  final VoidCallback Function() _snapshot;

  /// What the input holds now ('' when empty or gone).
  String get current => element.mounted ? _read() : '';

  /// Puts a checked, normalised [value] in the input the way typing or
  /// picking would, so the form's own listeners run. False if the input
  /// rejected it or has gone.
  bool write(String value) => element.mounted && _write(value);

  /// A callback that puts the input back the way it is now.
  VoidCallback snapshot() {
    if (!element.mounted) return () {};
    final restore = _snapshot();
    return () {
      if (element.mounted) restore();
    };
  }
}

/// The voice-fillable inputs of the form in front of the doctor.
class VoiceFormScan {
  const VoiceFormScan._({
    required this.fields,
    required this.inPopup,
    this.route,
    this.blockedReason,
  });

  static const empty = VoiceFormScan._(fields: [], inPopup: false);

  final List<VoiceFormField> fields;

  /// The form is a dialog or a bottom sheet, not a whole screen.
  final bool inPopup;

  /// The route the form is on.
  final ModalRoute<dynamic>? route;

  /// Why voice won't touch this form (a password or payment form), or null.
  final String? blockedReason;

  bool get isEmpty => fields.isEmpty && blockedReason == null;

  /// Scans the screen under [root] — the app's root navigator — for the
  /// form in front: a dialog or sheet if one is open, else the current
  /// page. Inputs on screens behind it, offstage tabs, disabled or
  /// read-only inputs, search boxes and inputs without a label are left out.
  static VoiceFormScan of(BuildContext root) {
    final top = _topRoute(root);
    final found = <({Element element, ModalRoute<dynamic>? route})>[];

    void visit(Element e) {
      final w = e.widget;
      if (w is Offstage && w.offstage) return;
      if (w is Visibility && !w.visible) return;
      if (w is TickerMode && !w.enabled) return;
      if (_isInput(w)) {
        found.add((element: e, route: ModalRoute.of(e)));
        // A Cru field or a list tile carries its own inner input.
        if (w is! EditableText) return;
      }
      e.visitChildren(visit);
    }

    (root as Element).visitChildren(visit);

    // A dialog or sheet in front: only its inputs. Otherwise the inputs on
    // whichever pages are current (the shell's nested navigators included).
    final popup = top is PopupRoute ? top : null;
    final inFront = [
      for (final f in found)
        if (popup != null
            ? identical(f.route, popup)
            : (f.route?.isCurrent ?? false))
          f,
    ];
    if (inFront.isEmpty) return empty;

    final fields = <VoiceFormField>[];
    final seen = <String, int>{};
    String? blocked;
    for (final f in inFront) {
      final built = _fieldFor(f.element, () {
        final i = fields.length;
        return 'f$i';
      }, f.route, seen);
      if (built == null) continue;
      if (built.blocked != null) blocked = built.blocked;
      if (built.field != null) fields.add(built.field!);
    }
    return VoiceFormScan._(
      fields: blocked == null ? fields : const [],
      inPopup: popup != null,
      route: popup ?? inFront.first.route,
      blockedReason: blocked,
    );
  }

  /// The route on top of the root navigator, without changing anything.
  static Route<dynamic>? _topRoute(BuildContext root) {
    Route<dynamic>? top;
    final nav = root is StatefulElement && root.state is NavigatorState
        ? root.state as NavigatorState
        : Navigator.maybeOf(root, rootNavigator: true);
    nav?.popUntil((route) {
      top = route;
      return true;
    });
    return top;
  }

  static bool _isInput(Widget w) =>
      w is EditableText ||
      w is CruTagField ||
      w is CruDropdownField ||
      w is DropdownButton ||
      w is CruSegmentedControl ||
      w is CheckboxListTile ||
      w is SwitchListTile ||
      w is Checkbox ||
      w is Switch;

  static final _sensitive = RegExp(
    r'password|passcode|\botp\b|\bpin\b|cvv|cvc|card number|expiry|upi pin',
    caseSensitive: false,
  );
  static final _search = RegExp(r'\bsearch\b|\bfilter\b', caseSensitive: false);

  static ({VoiceFormField? field, String? blocked})? _fieldFor(
    Element e,
    String Function() nextId,
    ModalRoute<dynamic>? route,
    Map<String, int> seen,
  ) {
    final w = e.widget;

    String keyFor(String label) {
      final n = seen.update(label, (v) => v + 1, ifAbsent: () => 0);
      return '${identityHashCode(route)}|$label|$n';
    }

    VoiceFormField make({
      required String label,
      required VoiceFieldType type,
      required String Function() read,
      required bool Function(String) write,
      required VoidCallback Function() snapshot,
      List<String> options = const [],
    }) => VoiceFormField._(
      id: nextId(),
      key: keyFor(label),
      label: label,
      type: type,
      element: e,
      read: read,
      write: write,
      snapshot: snapshot,
      options: options,
    );

    if (w is EditableText) {
      final meta = _textMeta(e);
      if (meta.inOwnField) return null;
      final label = meta.label;
      final hints = w.autofillHints ?? const <String>[];
      final sensitive =
          w.obscureText ||
          hints.any(
            (h) =>
                h.contains('password') ||
                h.contains('creditCard') ||
                h == AutofillHints.oneTimeCode,
          ) ||
          (label != null && _sensitive.hasMatch(label));
      if (sensitive) {
        return (
          field: null,
          blocked:
              "Voice doesn't fill sign-in or payment forms. Type these in.",
        );
      }
      if (label == null || !meta.enabled || w.readOnly) return null;
      if (_search.hasMatch(label)) return null;
      final controller = w.controller;
      return (
        field: make(
          label: label,
          type: _textType(w, label),
          read: () => controller.text,
          write: (v) {
            var next = TextEditingValue(
              text: v,
              selection: TextSelection.collapsed(offset: v.length),
            );
            // The field's own rules (digits only, length limits) apply,
            // as if the value had been typed.
            for (final f in w.inputFormatters ?? const <TextInputFormatter>[]) {
              next = f.formatEditUpdate(controller.value, next);
            }
            if (next.text.trim().isEmpty) return false;
            controller.value = next;
            w.onChanged?.call(next.text);
            return true;
          },
          snapshot: () {
            final before = controller.value;
            return () {
              controller.value = before;
              w.onChanged?.call(before.text);
            };
          },
        ),
        blocked: null,
      );
    }

    if (w is CruTagField) {
      if (_search.hasMatch(w.label)) return null;
      final dynamic d = w;
      return (
        field: make(
          label: w.label,
          type: VoiceFieldType.list,
          read: () => w.values.join(', '),
          write: (v) {
            final next = [...w.values];
            for (final item in v.split(RegExp(r',|;|\band\b'))) {
              final t = item.trim();
              if (t.isEmpty || next.length >= w.max) continue;
              if (next.any((x) => x.toLowerCase() == t.toLowerCase())) {
                continue;
              }
              next.add(t);
            }
            if (next.length == w.values.length) return false;
            d.onChanged(next);
            return true;
          },
          snapshot: () {
            final before = [...w.values];
            return () => d.onChanged(before);
          },
        ),
        blocked: null,
      );
    }

    if (w is CruDropdownField) {
      final dynamic d = w;
      if (d.onChanged == null) return null;
      final items = List<Object?>.from(d.items as List);
      final labels = [for (final i in items) (d.itemLabel(i) as Object).toString()];
      if (items.isEmpty) return null;
      return (
        field: make(
          label: w.label,
          type: VoiceFieldType.choice,
          options: labels,
          read: () {
            final v = d.value;
            final i = items.indexOf(v);
            return i < 0 ? '' : labels[i];
          },
          write: (v) {
            final i = labels.indexOf(v);
            if (i < 0) return false;
            d.onChanged(items[i]);
            return true;
          },
          snapshot: () {
            final before = d.value;
            return () {
              if (before != null) d.onChanged(before);
            };
          },
        ),
        blocked: null,
      );
    }

    if (w is DropdownButton) {
      final dynamic d = w;
      final items = (w.items ?? const <DropdownMenuItem<dynamic>>[]).toList();
      if (w.onChanged == null || items.isEmpty) return null;
      final labels = [
        for (final i in items) _textOf(i.child) ?? _plain(i.value) ?? '',
      ];
      if (labels.any((l) => l.isEmpty)) return null;
      final label =
          _decoratorLabel(e) ?? _decoratorLabelBelow(e) ?? _textOf(w.hint);
      if (label == null || _search.hasMatch(label)) return null;
      return (
        field: make(
          label: label,
          type: VoiceFieldType.choice,
          options: labels,
          read: () {
            final i = items.indexWhere((x) => x.value == d.value);
            return i < 0 ? '' : labels[i];
          },
          write: (v) {
            final i = labels.indexOf(v);
            if (i < 0) return false;
            d.onChanged(items[i].value);
            return true;
          },
          snapshot: () {
            final before = d.value;
            return () => d.onChanged(before);
          },
        ),
        blocked: null,
      );
    }

    if (w is CruSegmentedControl) {
      final dynamic d = w;
      final segments = List<dynamic>.from(d.segments as List);
      final labels = [for (final s in segments) s.label as String];
      final label =
          _nonEmpty(w.semanticLabel) ??
          _frameLabel(e) ??
          labels.join(' / ');
      return (
        field: make(
          label: label,
          type: VoiceFieldType.choice,
          options: labels,
          read: () {
            final i = segments.indexWhere((s) => s.value == d.selected);
            return i < 0 ? '' : labels[i];
          },
          write: (v) {
            final i = labels.indexOf(v);
            if (i < 0) return false;
            d.onChanged(segments[i].value);
            return true;
          },
          snapshot: () {
            final before = d.selected;
            return () => d.onChanged(before);
          },
        ),
        blocked: null,
      );
    }

    // Toggles: list tiles carry their own title; a bare checkbox or
    // switch takes the text beside it.
    final dynamic t = w;
    final String? label = switch (w) {
      CheckboxListTile(:final title) => _textOf(title),
      SwitchListTile(:final title) => _textOf(title),
      _ => _textBeside(e),
    };
    final onChanged = t.onChanged as Function?;
    if (label == null || onChanged == null) return null;
    return (
      field: make(
        label: label,
        type: VoiceFieldType.toggle,
        read: () => t.value == true ? 'yes' : 'no',
        write: (v) {
          final on = v == 'yes';
          if ((t.value == true) == on) return true;
          onChanged(on);
          return true;
        },
        snapshot: () {
          final before = t.value as bool?;
          return () => onChanged(before);
        },
      ),
      blocked: null,
    );
  }

  static VoiceFieldType _textType(EditableText w, String label) {
    final kind = w.keyboardType.index;
    final l = label.toLowerCase();
    if (kind == TextInputType.phone.index ||
        RegExp(r'\b(phone|mobile|whatsapp|contact number)\b').hasMatch(l)) {
      return VoiceFieldType.phone;
    }
    if (kind == TextInputType.emailAddress.index || l.contains('email')) {
      return VoiceFieldType.email;
    }
    if (kind == TextInputType.number.index) return VoiceFieldType.number;
    if (kind == TextInputType.multiline.index || w.maxLines != 1) {
      return VoiceFieldType.multiline;
    }
    return VoiceFieldType.text;
  }

  /// The label of the text input [e] belongs to, and whether it can be
  /// typed in.
  static ({String? label, bool enabled, bool inOwnField}) _textMeta(
    Element e,
  ) {
    String? label;
    String? hint;
    var enabled = true;
    var inOwnField = false;
    var depth = 0;
    e.visitAncestorElements((a) {
      final w = a.widget;
      if (w is CruTagField || w is CruDropdownField) {
        inOwnField = true;
        return false;
      }
      if (w is CruTextField) {
        label = w.label;
        if (!w.enabled) enabled = false;
        return false;
      }
      if (w is TextField) {
        if (w.enabled == false || w.readOnly) enabled = false;
        label ??= _nonEmpty(w.decoration?.labelText);
        hint ??= _nonEmpty(w.decoration?.hintText);
      }
      if (w is CruFieldFrame) {
        label ??= _nonEmpty(w.label);
        return false;
      }
      return ++depth < 40;
    });
    return (
      label: _cleanLabel(label ?? hint),
      enabled: enabled,
      inOwnField: inOwnField,
    );
  }

  static String? _decoratorLabel(Element e) {
    String? label;
    var depth = 0;
    e.visitAncestorElements((a) {
      final w = a.widget;
      if (w is InputDecorator) {
        label = _nonEmpty(w.decoration.labelText) ??
            _nonEmpty(w.decoration.hintText);
        if (label != null) return false;
      }
      if (w is CruFieldFrame) {
        label = _nonEmpty(w.label);
        return false;
      }
      return ++depth < 30;
    });
    return _cleanLabel(label);
  }

  /// A form dropdown draws its labelled box inside itself.
  static String? _decoratorLabelBelow(Element e) {
    String? label;
    void find(Element x) {
      if (label != null) return;
      final w = x.widget;
      if (w is InputDecorator) {
        label =
            _nonEmpty(w.decoration.labelText) ??
            _nonEmpty(w.decoration.hintText);
        return;
      }
      x.visitChildren(find);
    }

    e.visitChildren(find);
    return _cleanLabel(label);
  }

  static String? _frameLabel(Element e) {
    String? label;
    var depth = 0;
    e.visitAncestorElements((a) {
      if (a.widget is CruFieldFrame) {
        label = _nonEmpty((a.widget as CruFieldFrame).label);
        return false;
      }
      return ++depth < 8;
    });
    return _cleanLabel(label);
  }

  /// The first text in the row a bare checkbox or switch sits in.
  static String? _textBeside(Element e) {
    Element? row;
    var depth = 0;
    e.visitAncestorElements((a) {
      if (a.widget is Flex || a.widget is ListTile) {
        row = a;
        return false;
      }
      return ++depth < 4;
    });
    if (row == null) return null;
    String? text;
    void find(Element x) {
      if (text != null || identical(x, e)) return;
      final w = x.widget;
      if (w is Text) {
        text = _nonEmpty(w.data ?? w.textSpan?.toPlainText());
        return;
      }
      x.visitChildren(find);
    }

    row!.visitChildren(find);
    return _cleanLabel(text);
  }

  /// The text a small widget tree shows: a dropdown item, a tile title.
  static String? _textOf(Widget? w, [int depth = 0]) {
    if (w == null || depth > 6) return null;
    if (w is Text) return _nonEmpty(w.data ?? w.textSpan?.toPlainText());
    if (w is RichText) return _nonEmpty(w.text.toPlainText());
    if (w is Flex) {
      final parts = [for (final c in w.children) ?_textOf(c, depth + 1)];
      return parts.isEmpty ? null : parts.join(' ');
    }
    if (w is SingleChildRenderObjectWidget) return _textOf(w.child, depth + 1);
    if (w is ProxyWidget) return _textOf(w.child, depth + 1);
    if (w is Container) return _textOf(w.child, depth + 1);
    return null;
  }

  static String? _plain(Object? v) => switch (v) {
    String() => _nonEmpty(v),
    num() => '$v',
    Enum() => v.name,
    _ => null,
  };

  static String? _nonEmpty(String? s) {
    final t = s?.trim();
    return t == null || t.isEmpty ? null : t;
  }

  /// "Dose *", "Phone (optional)", "Email:" → "Dose", "Phone", "Email".
  static String? _cleanLabel(String? s) {
    if (s == null) return null;
    final t = s
        .replaceAll(RegExp(r'\((optional|required)\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'[*:]+\s*$'), '')
        .trim();
    return t.isEmpty || t.length > 60 ? null : t;
  }
}
