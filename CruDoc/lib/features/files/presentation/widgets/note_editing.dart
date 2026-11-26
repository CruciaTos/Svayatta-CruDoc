import 'package:flutter/services.dart';

/// The most letters a file's note may have.
const int kFileNoteLimit = 250;

/// What starts a line of a list in a note.
const String kNoteBullet = '• ';

/// Lists written as one types: Enter on a bulleted line starts the next
/// bullet, Enter on an empty bullet ends the list, and "- " at the start of
/// a line becomes a bullet.
class NoteListFormatter extends TextInputFormatter {
  const NoteListFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    final at = newValue.selection.baseOffset;
    if (!newValue.selection.isCollapsed || at < 1 || at > text.length) {
      return newValue;
    }
    TextEditingValue put(String t, int cursor) => TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: cursor),
    );
    final typed = text[at - 1];
    if (typed == '\n' &&
        '\n'.allMatches(text).length ==
            '\n'.allMatches(oldValue.text).length + 1) {
      final start = _lineStart(text, at - 1);
      final line = text.substring(start, at - 1);
      if (line == kNoteBullet) {
        // An empty bullet: the list is over.
        return put(text.replaceRange(start, at, ''), start);
      }
      if (line.startsWith(kNoteBullet)) {
        return put(
          text.replaceRange(at, at, kNoteBullet),
          at + kNoteBullet.length,
        );
      }
    }
    if (typed == ' ' && text.length > oldValue.text.length) {
      final start = _lineStart(text, at - 1);
      if (text.substring(start, at) == '- ') {
        return put(text.replaceRange(start, at, kNoteBullet), at);
      }
    }
    return newValue;
  }

  /// Where the line holding position [before] begins.
  static int _lineStart(String text, int before) =>
      before <= 0 ? 0 : text.lastIndexOf('\n', before - 1) + 1;

  /// Makes the line the cursor is on a bullet, or takes its bullet away.
  static TextEditingValue toggle(TextEditingValue value) {
    final text = value.text;
    final cursor = value.selection.isValid
        ? value.selection.extentOffset
        : text.length;
    final start = _lineStart(text, cursor);
    if (text.startsWith(kNoteBullet, start)) {
      final to = cursor - kNoteBullet.length;
      return TextEditingValue(
        text: text.replaceRange(start, start + kNoteBullet.length, ''),
        selection: TextSelection.collapsed(offset: to < start ? start : to),
      );
    }
    if (text.length + kNoteBullet.length > kFileNoteLimit) return value;
    return TextEditingValue(
      text: text.replaceRange(start, start, kNoteBullet),
      selection: TextSelection.collapsed(offset: cursor + kNoteBullet.length),
    );
  }
}
