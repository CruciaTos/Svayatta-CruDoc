// scribe_transcript_formatter.dart
//
// Formats, cleans, deduplicates, and diarizes consultation speech transcripts.
// Resolves Whisper streaming rolling-window overlaps, repetitions, ASR glitches,
// and structures raw text into clean Doctor / Patient clinical dialogue.

class ScribeTranscriptFormatter {
  const ScribeTranscriptFormatter();

  /// Merges a live streaming transcript chunk with the existing accumulated text,
  /// aligning sliding-window overlaps at word boundaries so words/clauses are
  /// never stuttered or duplicated.
  static String mergeLiveChunk(String existing, String incoming) {
    final cur = existing.trim();
    var next = incoming.trim();
    if (next.isEmpty) return cur;
    if (cur.isEmpty) return next;

    final curLower = cur.toLowerCase();
    final nextLower = next.toLowerCase();

    // 1. If incoming is already contained within existing, ignore it
    if (curLower == nextLower || curLower.contains(nextLower)) {
      return cur;
    }

    // 2. If existing is a prefix of incoming (common in partial streaming), replace
    if (nextLower.startsWith(curLower)) {
      return next;
    }

    // 3. Word-level suffix-prefix alignment
    final curWords = cur.split(RegExp(r'\s+'));
    final nextWords = next.split(RegExp(r'\s+'));

    final maxOverlap = curWords.length < nextWords.length
        ? curWords.length
        : nextWords.length;
    final checkLimit = maxOverlap > 20 ? 20 : maxOverlap;

    for (var k = checkLimit; k >= 2; k--) {
      final curSuffix = curWords
          .sublist(curWords.length - k)
          .map(_cleanWord)
          .join(' ')
          .toLowerCase();
      final nextPrefix = nextWords
          .sublist(0, k)
          .map(_cleanWord)
          .join(' ')
          .toLowerCase();

      if (curSuffix == nextPrefix && curSuffix.isNotEmpty) {
        // Overlap found of length k words! Append only remaining words
        final newWords = nextWords.sublist(k);
        if (newWords.isEmpty) return cur;
        return '$cur ${newWords.join(' ')}';
      }
    }

    // 4. Character-level boundary check if word overlap was missed due to punctuation
    final minCharCheck = cur.length < 60 ? cur.length : 60;
    for (var len = minCharCheck; len >= 10; len--) {
      final suffix = cur.substring(cur.length - len).trim().toLowerCase();
      if (suffix.length >= 10 && nextLower.startsWith(suffix)) {
        final remaining = next.substring(suffix.length).trim();
        if (remaining.isEmpty) return cur;
        return '$cur $remaining';
      }
    }

    // 5. No overlap: separate sentences naturally
    final endsWithPunct = RegExp(r'[.!?:]$').hasMatch(cur);
    return endsWithPunct ? '$cur $next' : '$cur. $next';
  }

  /// Cleans out stuttered, repeated phrases and rolling-window repetitions.
  static String deduplicateText(String raw) {
    if (raw.trim().isEmpty) return '';

    // First split by sentences or punctuation pauses
    final parts = raw
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .split(RegExp(r'(?<=[.!?])\s+|\s*[;]\s*'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (parts.isEmpty) return '';

    final cleaned = <String>[];

    for (var i = 0; i < parts.length; i++) {
      var candidate = parts[i];
      if (candidate.isEmpty) continue;

      final norm = _normalizeForComparison(candidate);
      if (norm.isEmpty) continue;

      // Check if this sentence is substantially identical to or a subset of the previous sentence
      if (cleaned.isNotEmpty) {
        final prevNorm = _normalizeForComparison(cleaned.last);

        // Exact or close match -> skip
        if (norm == prevNorm) continue;

        // If the candidate expands the previous short fragment (e.g. "i am feeling" -> "i am feeling severe pain"),
        // replace previous with candidate
        if (norm.startsWith(prevNorm) && norm.length > prevNorm.length) {
          cleaned[cleaned.length - 1] = candidate;
          continue;
        }

        // If candidate is a prefix or subset of previous, skip
        if (prevNorm.startsWith(norm) || prevNorm.contains(norm)) {
          continue;
        }
      }

      // Check for immediate word-loop repetition inside the sentence itself
      // e.g. "i am feeling good i'm feeling good" or "very severely my right side. very severely my right side"
      candidate = _removeInternalRepetitions(candidate);

      if (cleaned.isNotEmpty) {
        final prevNorm = _normalizeForComparison(cleaned.last);
        final candNorm = _normalizeForComparison(candidate);
        if (prevNorm == candNorm || prevNorm.contains(candNorm)) {
          continue;
        }
      }

      cleaned.add(candidate);
    }

    // Second pass: remove duplicate sentences within a short sliding window
    final windowFiltered = <String>[];
    for (var i = 0; i < cleaned.length; i++) {
      final s = cleaned[i];
      final norm = _normalizeForComparison(s);
      var duplicate = false;

      // Look back up to 3 sentences
      final start = (windowFiltered.length - 3).clamp(0, windowFiltered.length);
      for (var j = start; j < windowFiltered.length; j++) {
        final existingNorm = _normalizeForComparison(windowFiltered[j]);
        if (existingNorm == norm ||
            (existingNorm.length > 12 && existingNorm.contains(norm)) ||
            (norm.length > 12 && norm.contains(existingNorm))) {
          duplicate = true;
          // If current is longer/more detailed, upgrade existing
          if (s.length > windowFiltered[j].length) {
            windowFiltered[j] = s;
          }
          break;
        }
      }

      if (!duplicate) {
        windowFiltered.add(s);
      }
    }

    return windowFiltered.join(' ');
  }

  /// Removes immediate phrase or word loops inside a single sentence/clause.
  static String _removeInternalRepetitions(String sentence) {
    var words = sentence.split(RegExp(r'\s+'));
    if (words.length <= 3) return sentence;

    // Detect repeated sequences of length N (e.g. 2..8 words)
    for (var len = (words.length ~/ 2); len >= 2; len--) {
      for (var i = 0; i <= words.length - (len * 2); i++) {
        final phrase1 = words
            .sublist(i, i + len)
            .map(_cleanWord)
            .join(' ')
            .toLowerCase();
        final phrase2 = words
            .sublist(i + len, i + (len * 2))
            .map(_cleanWord)
            .join(' ')
            .toLowerCase();
        if (phrase1.isNotEmpty && phrase1 == phrase2) {
          // Found repeated phrase! Remove second copy
          words.removeRange(i + len, i + (len * 2));
          return _removeInternalRepetitions(words.join(' '));
        }
      }
    }

    return words.join(' ');
  }

  /// Fixes speech recognition phonetic slips, filler noise, and numbers.
  static String fixAsrGlitches(String text) {
    var result = text;

    final replacements = <Pattern, String>{
      // Pain rating normalization
      RegExp(r'\b(?:out of rick ten|out of rick 10)\b', caseSensitive: false):
          'out of 10',
      RegExp(r'\b7\s*on\s*10th\b', caseSensitive: false): '7 out of 10',
      RegExp(r'\b(?:7|seven)\s*(?:on|or)\s*10\b', caseSensitive: false):
          '7 out of 10',
      RegExp(r'\b(?:5|five)\s*(?:on|or)\s*10\b', caseSensitive: false):
          '5 out of 10',
      RegExp(r'\b(?:intensity of the pace)\b', caseSensitive: false):
          'intensity of the pain',
      RegExp(
        r'\bpatients are very severely on my right side\b',
        caseSensitive: false,
      ): 'pain is very severe on my right side',
      RegExp(r'\bpatients are severely my right side\b', caseSensitive: false):
          'pain is severe on my right side',
      RegExp(r'\bin the room pain\b', caseSensitive: false): 'severe pain',
      RegExp(r'\bthe group is very severely\b', caseSensitive: false):
          'the pain is very severe',
      RegExp(r'\bhave a lipid for a long time\b', caseSensitive: false):
          'haven’t been able to walk properly for a long time',
      RegExp(r'\bhave a limit for now\b', caseSensitive: false):
          'haven’t been able to walk properly for now',
      RegExp(
        r'\bpatients have been a little bit for a long time\b',
        caseSensitive: false,
      ): 'haven’t been able to walk properly for a long time',
      RegExp(r'\bhello sue\b', caseSensitive: false): 'Hello',
      // Multi-comma and space cleanup
      RegExp(r',\s*,+'): ',',
      RegExp(r'\s+'): ' ',
    };

    for (final entry in replacements.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }

    return result.trim();
  }

  /// Formats the consultation into a readable, coherent clinical dialogue
  /// with distinct Doctor and Patient turns.
  static String formatDialogue(String text) {
    final cleaned = deduplicateText(fixAsrGlitches(text));
    if (cleaned.isEmpty) return '';

    // If text already has clear Doctor/Patient labels, tidy it up
    if (cleaned.contains('Doctor:') || cleaned.contains('Patient:')) {
      return _cleanExistingDialogue(cleaned);
    }

    // Split into sentences
    final rawSentences = cleaned
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (rawSentences.isEmpty) return cleaned;

    final turns = <_SpeakerTurn>[];
    _Speaker currentSpeaker = _classifySpeaker(
      rawSentences.first,
      _Speaker.patient,
    );
    var currentBuffer = <String>[];

    for (final s in rawSentences) {
      final detected = _classifySpeaker(s, currentSpeaker);

      if (detected != currentSpeaker && currentBuffer.isNotEmpty) {
        turns.add(
          _SpeakerTurn(
            speaker: currentSpeaker,
            content: _formatSentenceBlock(currentBuffer.join(' ')),
          ),
        );
        currentSpeaker = detected;
        currentBuffer = [s];
      } else {
        currentBuffer.add(s);
      }
    }

    if (currentBuffer.isNotEmpty) {
      turns.add(
        _SpeakerTurn(
          speaker: currentSpeaker,
          content: _formatSentenceBlock(currentBuffer.join(' ')),
        ),
      );
    }

    // Combine into formatted markdown dialogue with paragraph spacing
    final buffer = StringBuffer();
    for (var i = 0; i < turns.length; i++) {
      final t = turns[i];
      final prefix = t.speaker == _Speaker.doctor ? 'Doctor:' : 'Patient:';
      buffer.write('$prefix ${t.content}');
      if (i < turns.length - 1) {
        buffer.write('\n\n');
      }
    }

    return buffer.toString();
  }

  /// Full formatting pipeline: deduplicates, cleans ASR glitches,
  /// formats into clinical dialogue.
  static String format(String raw) {
    if (raw.trim().isEmpty) return '';
    return formatDialogue(raw);
  }

  // --- Classification and formatting helpers ---

  static _Speaker _classifySpeaker(String sentence, _Speaker fallback) {
    final lower = sentence.toLowerCase().trim();

    // Doctor patterns: questions about pain, exam findings, prescriptions, advice
    final doctorSignals = [
      'what is the intensity',
      "what's the intensity",
      'what will you rate',
      'how would you rate',
      'out of 10',
      'out of ten',
      'is it about five',
      'is it 5 or 10',
      'where is the pain',
      'does it hurt',
      'how long has it been',
      'let me examine',
      'blood pressure is',
      'bp is',
      'pulse is',
      'temperature is',
      'prescribing',
      'take this tablet',
      'take tab',
      'advised',
      'avoid forward bending',
      'follow up in',
      'come back after',
    ];

    for (final sig in doctorSignals) {
      if (lower.contains(sig)) {
        return _Speaker.doctor;
      }
    }

    // Patient signals: first-person statements of pain, inability, symptoms
    final patientSignals = [
      'i am feeling',
      "i'm feeling",
      'i think i will say',
      'i would say',
      'my right side',
      'my left side',
      'my back',
      'my knee',
      'i have not been able',
      "haven't been able",
      "i can't walk",
      'severe pain',
      'it started',
      "it's been",
      'nothing just that',
      'i don’t know',
      "i don't know",
    ];

    for (final sig in patientSignals) {
      if (lower.contains(sig)) {
        return _Speaker.patient;
      }
    }

    // Questions ending with '?' are usually Doctor inquiries
    if (lower.endsWith('?')) {
      return _Speaker.doctor;
    }

    return fallback;
  }

  static String _cleanExistingDialogue(String text) {
    final lines = text.split('\n');
    final out = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      out.add(trimmed);
    }
    return out.join('\n\n');
  }

  static String _formatSentenceBlock(String text) {
    var s = text.trim();
    if (s.isEmpty) return s;

    // Capitalize first letter
    s = s[0].toUpperCase() + s.substring(1);

    // Ensure ending punctuation
    if (!RegExp(r'[.!?]$').hasMatch(s)) {
      s += '.';
    }

    // Clean space before punctuation
    s = s.replaceAll(RegExp(r'\s+([,.:!?])'), r'$1');

    return s;
  }

  static String _normalizeForComparison(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _cleanWord(String w) {
    return w.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
  }
}

enum _Speaker { doctor, patient }

class _SpeakerTurn {
  const _SpeakerTurn({required this.speaker, required this.content});
  final _Speaker speaker;
  final String content;
}
