/// Turns what the dentist says during a perio exam into chart commands.
/// Pure Dart: no Flutter, no speech engine, so it is easy to test.
sealed class PerioVoiceCommand {
  const PerioVoiceCommand();
}

/// One pocket depth, 0-15 mm, for the current site.
class PerioDepth extends PerioVoiceCommand {
  const PerioDepth(this.mm);
  final int mm;
}

/// Marks bleeding on the last filled site.
class PerioBleeding extends PerioVoiceCommand {
  const PerioBleeding();
}

/// Marks suppuration on the last filled site.
class PerioSuppuration extends PerioVoiceCommand {
  const PerioSuppuration();
}

/// Gingival margin on the last filled site. [mm] is negative when the margin
/// sits above the CEJ ("minus 2").
class PerioRecession extends PerioVoiceCommand {
  const PerioRecession(this.mm);
  final int mm;
}

class PerioNextTooth extends PerioVoiceCommand {
  const PerioNextTooth();
}

class PerioPreviousTooth extends PerioVoiceCommand {
  const PerioPreviousTooth();
}

/// "tooth 36": jump to an FDI tooth number.
class PerioGoToTooth extends PerioVoiceCommand {
  const PerioGoToTooth(this.tooth);
  final String tooth;
}

class PerioMissing extends PerioVoiceCommand {
  const PerioMissing();
}

/// Leaves the current site empty and moves to the next one.
class PerioSkip extends PerioVoiceCommand {
  const PerioSkip();
}

class PerioUndo extends PerioVoiceCommand {
  const PerioUndo();
}

class PerioStopListening extends PerioVoiceCommand {
  const PerioStopListening();
}

abstract final class PerioVoiceParser {
  static const _ones = <String, int>{
    'zero': 0,
    'oh': 0,
    'nought': 0,
    'one': 1,
    'won': 1,
    'two': 2,
    'to': 2,
    'too': 2,
    'three': 3,
    'tree': 3,
    'four': 4,
    'for': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'ate': 8,
    'nine': 9,
    'ten': 10,
    'eleven': 11,
    'twelve': 12,
    'thirteen': 13,
    'fourteen': 14,
    'fifteen': 15,
  };

  static const _tens = <String, int>{'twenty': 20, 'thirty': 30, 'forty': 40};

  static final _digits = RegExp(r'^\d+$');

  /// Depths a token stands for: a word or digit gives one value (0-15); a
  /// longer digit run such as "324" is read digit by digit.
  static List<int>? _values(String tok) {
    if (_digits.hasMatch(tok)) {
      final n = int.parse(tok);
      if (tok.length <= 2 && n <= 15) return [n];
      return [for (final ch in tok.split('')) int.parse(ch)];
    }
    final w = _ones[tok];
    return w == null ? null : [w];
  }

  /// Reads an FDI number after "tooth": "36", "three six", "thirty six".
  /// Returns the number and how many tokens it used, or null.
  static (String, int)? _tooth(List<String> t, int i) {
    if (i >= t.length) return null;
    final first = t[i];
    if (_digits.hasMatch(first) && first.length == 2) return (first, 1);
    final ten = _tens[first];
    if (ten != null) {
      final unit = i + 1 < t.length ? _ones[t[i + 1]] : null;
      if (unit != null && unit >= 1 && unit <= 9) return ('${ten + unit}', 2);
      return null;
    }
    int? d(String s) {
      final v = _digits.hasMatch(s) && s.length == 1 ? int.parse(s) : _ones[s];
      return v != null && v <= 9 ? v : null;
    }

    final a = d(first);
    final b = i + 1 < t.length ? d(t[i + 1]) : null;
    if (a != null && b != null) return ('$a$b', 2);
    return null;
  }

  static List<PerioVoiceCommand> parse(String text) {
    final t = text
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((s) => s.isNotEmpty)
        .toList();
    final out = <PerioVoiceCommand>[];
    var i = 0;
    String? at(int k) => k < t.length ? t[k] : null;
    while (i < t.length) {
      final w = t[i];
      switch (w) {
        case 'undo':
          out.add(const PerioUndo());
        case 'stop':
          out.add(const PerioStopListening());
          return out;
        case 'bleeding' || 'bleed' || 'bleeds' || 'blood':
          out.add(const PerioBleeding());
        case 'suppuration' || 'suppurating' || 'pus':
          out.add(const PerioSuppuration());
        case 'missing':
          out.add(const PerioMissing());
        case 'next':
          if (at(i + 1) == 'site') {
            out.add(const PerioSkip());
            i++;
          } else {
            out.add(const PerioNextTooth());
            if (at(i + 1) == 'tooth') i++;
          }
        case 'previous' || 'prev' || 'back':
          if (w == 'back' && at(i + 1) != 'tooth') break;
          out.add(const PerioPreviousTooth());
          if (at(i + 1) == 'tooth') i++;
        case 'skip':
          if (at(i + 1) == 'tooth') {
            out.add(const PerioNextTooth());
            i++;
          } else {
            out.add(const PerioSkip());
          }
        case 'tooth':
          final r = _tooth(t, i + 1);
          if (r != null) {
            out.add(PerioGoToTooth(r.$1));
            i += r.$2;
          }
        case 'recession' || 'minus' || 'negative':
          var neg = w != 'recession';
          var k = i + 1;
          if (w == 'recession' && (at(k) == 'minus' || at(k) == 'negative')) {
            neg = true;
            k++;
          }
          final v = at(k) == null ? null : _values(t[k]);
          if (v != null) {
            out.add(PerioRecession(neg ? -v.first : v.first));
            i = k;
          }
        default:
          final v = _values(w);
          if (v != null) {
            for (final n in v) {
              out.add(PerioDepth(n));
            }
          }
      }
      i++;
    }
    return out;
  }
}
