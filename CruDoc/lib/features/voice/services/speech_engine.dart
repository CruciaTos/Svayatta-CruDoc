import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// One transcript update. [isFinal] is true once the doctor lets go of the
/// talk key; partials arrive while they are still speaking.
class VoiceTranscript {
  const VoiceTranscript(
    this.text, {
    required this.isFinal,
    this.latencyMs,
    this.source = 'fast',
    this.dictation = false,
  });

  final String text;
  final bool isFinal;

  /// How long the model took to produce this text.
  final int? latencyMs;

  /// Which stream produced this transcript: 'fast' (live) or 'accurate'.
  final String source;

  /// Part of a scribe dictation ([SpeechEngine.startDictation]): a
  /// consultation being written down, not a command.
  final bool dictation;
}

/// Speech-to-text for the Windows demo build: through
/// tool/voice_server/server.py (Sarvam saaras:v4 by default, or local
/// Whisper), or on-device with Parakeet or Whisper through sherpa-onnx.
///
/// With Sarvam, each utterance is streamed as it's spoken (the server
/// relays it to Sarvam's realtime API): live partials come back while the
/// doctor talks, and the final shortly after they stop. The others don't
/// stream, so while the talk key is held the audio so far is re-transcribed
/// every so often for that live, filling-in feel, and a last pass runs when
/// the key is released. On-device decoding happens in a background isolate
/// so the UI never stalls.
///
/// Phones have no speech server: they use the phone's own recognizer
/// (Google's on Android, Apple's on iOS), see [onPhone].
class SpeechEngine {
  SpeechEngine._();
  static final instance = SpeechEngine._();

  /// 'server': tool/voice_server/server.py, which sends the audio to
  /// Sarvam's saaras:v4 (STT_ENGINE=sarvam, the default) or runs Whisper
  /// large-v3-turbo on the laptop GPU (STT_ENGINE=whisper).
  /// On-device fallbacks via sherpa-onnx: 'parakeet' (CPU, slow on long
  /// clips) or a Whisper size, 'base.en' / 'small.en'; their files live in
  /// assets/voice/parakeet/ or assets/voice/whisper/.
  static const model = 'server';
  static const _server = 'http://127.0.0.1:8765';
  static const _sampleRate = 16000;

  /// New audio needed before the next live pass. Every pass on the server
  /// runs large-v3-turbo, so going again every 120 ms only queued live
  /// passes in front of the accurate ones; a fifth of a second is plenty.
  static const _minNewSamples = model == 'server' ? 3200 : 8000;

  /// Audio kept from just before the talk key goes down, so the first
  /// word isn't clipped, and after it comes up, for the last syllable.
  static const _prerollSamples = 4800;
  static const _tail = Duration(milliseconds: 150);

  /// Final passes shorter than this ("confirm") use the quicker model.
  static const _shortSeconds = 2.5;

  /// Patient names, passed to the server so it spells them right.
  List<String> hints = const [];
  Process? _serverProcess;

  final _recorder = AudioRecorder();
  final _transcripts = StreamController<VoiceTranscript>.broadcast();

  SendPort? _worker;
  final _replies = <int, Completer<(String, int)>>{};
  int _nextJob = 0;

  final _http = http.Client();
  bool _micOn = false;
  final _preroll = <Float32List>[];
  int _prerollCount = 0;
  final _audio = <Float32List>[];
  int _samples = 0;
  int _fastDecodedSamples = 0;
  int _accurateDecodedSamples = 0;
  bool _listening = false;
  int _utterance = 0;
  Future<void>? _initFuture;

  Stream<VoiceTranscript> get transcripts => _transcripts.stream;

  /// Fires when an utterance begins: talk key down or, hands-free, speech.
  Stream<void> get utteranceStarts => _starts.stream;
  final _starts = StreamController<void>.broadcast();

  /// How loud the mic is right now while listening, 0–1, for the pill's
  /// sound bars.
  final level = ValueNotifier<double>(0);

  /// Hands-free: always listening, utterances cut at pauses.
  bool get handsFree => _handsFree;
  bool _handsFree = false;
  bool _starting = false;
  double _noise = 0.01;
  DateTime? _lastVoice;
  DateTime? _began;
  static const _endSilence = Duration(milliseconds: 700);
  static const _maxUtterance = Duration(seconds: 15);

  /// Dictation pauses mid-thought more than commands do, and a sentence
  /// can run long; each piece is still one final pass with full context.
  static const _dictationEndSilence = Duration(milliseconds: 900);
  static const _dictationMaxUtterance = Duration(seconds: 25);

  /// The scribe is writing down a consultation: speech is cut into
  /// sentences at pauses, and push-to-talk can't stop it.
  bool get isDictating => _dictating;
  bool _dictating = false;

  /// The end of what has been dictated so far, sent with each piece so
  /// Whisper keeps names and spellings consistent across pauses.
  String _dictationContext = '';

  Future<void> setHandsFree(bool on) async {
    // Phones listen only while the island is held (or after a tap).
    if (onPhone) return;
    await init();
    await _ensureMic();
    _handsFree = on;
    if (!on && _listening) await stop();
  }

  /// Starts writing down a consultation. Transcripts arrive with
  /// [VoiceTranscript.dictation] set: live partials for the sentence being
  /// spoken, and a final for each sentence once the speaker pauses.
  Future<void> startDictation() async {
    // The phone's recognizer stops at every pause and can't share the mic
    // with the scribe's recording.
    if (onPhone) {
      throw StateError('Live transcription needs the clinic PC');
    }
    await init();
    await _ensureMic();
    if (_dictating) return;
    // A command half-spoken when the scribe opened is dropped.
    if (_listening) {
      _utterance++;
      _listening = false;
      level.value = 0;
      _dropStream();
    }
    _dictationContext = '';
    _dictating = true;
  }

  /// Stops dictation. With [keepLast], the sentence still being spoken is
  /// transcribed first; the returned future completes once its final is
  /// out, so a listener can wait for it before closing the transcript.
  Future<void> stopDictation({bool keepLast = true}) async {
    if (!_dictating) return;
    // Off at once, so a quick resume can start dictating again while the
    // last sentence is still being transcribed.
    _dictating = false;
    if (!_listening) return;
    if (keepLast) {
      await _end(dictation: true);
    } else {
      _utterance++;
      _listening = false;
      level.value = 0;
      _dropStream();
    }
  }

  bool get isListening => _listening;
  bool get isReady => _worker != null || _serverUp || _phoneReady;
  bool _serverUp = false;

  /// The server sends audio to Sarvam: each pass is a paid API call, so
  /// there is no separate fast stream and live passes are spaced out.
  bool _cloud = false;

  /// Port of the server's relay to Sarvam's realtime stream; 0 when it has
  /// none. With it, each utterance is streamed as it's spoken instead of
  /// being re-sent every second.
  int _streamPort = 0;

  /// This utterance's stream, once connected and caught up: mic chunks
  /// then go straight out.
  WebSocket? _stream;
  Future<WebSocket?>? _streamReady;
  Completer<(String, int)>? _streamFinal;

  /// Loads the model (or starts the GPU server). Safe to call repeatedly.
  Future<void> init() => _initFuture ??= () async {
    if (onPhone) return _initPhone();
    await (model == 'server' ? _startServer() : _spawnWorker());
    try {
      await _ensureMic();
    } catch (e) {
      debugPrint('[SpeechEngine] mic not ready yet: $e');
    }
  }();

  /// Keeps the mic open (audio is dropped unless the talk key is held),
  /// so pressing the key starts instantly.
  Future<void> _ensureMic() async {
    if (_micOn) return;
    if (!await _recorder.hasPermission()) {
      throw StateError('Microphone permission denied.');
    }
    final mic = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
      ),
    );
    _micOn = true;
    mic.listen(
      _onMic,
      onDone: () => _micOn = false,
      onError: (_) => _micOn = false,
    );
  }

  void _onMic(Uint8List bytes) {
    final f = _toFloat32(bytes);
    if (_handsFree || _dictating) _detectSpeech(f);
    if (_listening) {
      var peak = 0.0;
      for (final x in f) {
        final a = x.abs();
        if (a > peak) peak = a;
      }
      level.value = math.min(1, peak * 3);
      _audio.add(f);
      _samples += f.length;
      _stream?.add(bytes);
      return;
    }
    _preroll.add(f);
    _prerollCount += f.length;
    while (_preroll.length > 1 &&
        _prerollCount - _preroll.first.length >= _prerollSamples) {
      _prerollCount -= _preroll.removeAt(0).length;
    }
  }

  /// Loudness against a slowly tracked noise floor: speech starts an
  /// utterance, 0.7 s of quiet ends it.
  void _detectSpeech(Float32List f) {
    var sum = 0.0;
    for (final x in f) {
      sum += x * x;
    }
    final rms = f.isEmpty ? 0.0 : math.sqrt(sum / f.length);
    final speaking = rms > math.max(0.012, _noise * 3);
    final now = DateTime.now();
    if (!_listening) {
      if (speaking) {
        _lastVoice = now;
        unawaited(_begin());
      } else {
        _noise = _noise * 0.95 + rms * 0.05;
      }
      return;
    }
    if (speaking) _lastVoice = now;
    final quiet =
        now.difference(_lastVoice ?? now) >
        (_dictating ? _dictationEndSilence : _endSilence);
    final tooLong =
        now.difference(_began ?? now) >
        (_dictating ? _dictationMaxUtterance : _maxUtterance);
    if (quiet || tooLong) unawaited(_end());
  }

  Future<bool> _ping() async {
    try {
      final r = await http
          .get(Uri.parse('$_server/health'))
          .timeout(const Duration(seconds: 2));
      if (r.statusCode != 200) return false;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      _cloud = j['engine'] == 'sarvam';
      _streamPort = (j['stream_port'] as num?)?.toInt() ?? 0;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Reuses a running server, otherwise launches it from
  /// tool/voice_server/.venv and waits for the model to load.
  Future<void> _startServer() async {
    if (!await _ping()) {
      final dir = _serverDir();
      if (dir == null) {
        throw StateError(
          'tool/voice_server not found; start server.py by hand',
        );
      }
      final python = p.join(dir, '.venv', 'Scripts', 'python.exe');
      if (!File(python).existsSync()) {
        throw StateError(
          'voice server not installed — see tool/voice_server/README.md',
        );
      }
      // -u: unbuffered, so the server's log (and a crash) shows up here
      // as it happens instead of when the process ends.
      _serverProcess = await Process.start(python, [
        '-u',
        'server.py',
      ], workingDirectory: dir);
      // The last lines it printed: on a crash they say why.
      final tail = <String>[];
      void log(String line) {
        if (line.trim().isEmpty) return;
        debugPrint('[voice_server] $line');
        tail.add(line.trim());
        if (tail.length > 3) tail.removeAt(0);
      }

      for (final out in [_serverProcess!.stdout, _serverProcess!.stderr]) {
        out.transform(utf8.decoder).transform(const LineSplitter()).listen(log);
      }
      int? exitCode;
      unawaited(_serverProcess!.exitCode.then((c) => exitCode = c));
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      while (!await _ping()) {
        if (exitCode != null) {
          _serverProcess = null;
          _initFuture = null; // let a later init try again
          throw StateError(
            'Voice server stopped (exit $exitCode): '
            '${tail.isEmpty ? 'no output' : tail.last}',
          );
        }
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('Voice server did not start within 3 minutes');
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    _serverUp = true;
  }

  /// Project folder: the working directory under `flutter run`, else
  /// walk up from the build/windows/x64/runner folder.
  static String? _serverDir() {
    var d = Directory.current;
    for (var i = 0; i < 2; i++) {
      final c = p.join(d.path, 'tool', 'voice_server');
      if (File(p.join(c, 'server.py')).existsSync()) return c;
      d = File(Platform.resolvedExecutable).parent;
    }
    for (var i = 0; i < 6; i++) {
      final c = p.join(d.path, 'tool', 'voice_server');
      if (File(p.join(c, 'server.py')).existsSync()) return c;
      d = d.parent;
    }
    return null;
  }

  Future<void> _spawnWorker() async {
    final fromWorker = ReceivePort();
    final ready = Completer<SendPort>();
    fromWorker.listen((msg) {
      if (msg is SendPort) {
        ready.complete(msg);
      } else if (msg is (int, String, int)) {
        _replies.remove(msg.$1)?.complete((msg.$2, msg.$3));
      } else if (msg is String && !ready.isCompleted) {
        ready.completeError(StateError(msg));
      }
    });
    await Isolate.spawn(_workerMain, (fromWorker.sendPort, _modelDir(), model));
    _worker = await ready.future;
  }

  /// Starts listening. Call on talk-key down. Ignored while dictating:
  /// the scribe owns the mic then, and cuts sentences itself.
  Future<void> start() async {
    if (_dictating) return;
    if (onPhone) {
      _phoneHeld = true;
      return _beginOnPhone(held: true);
    }
    await _begin();
  }

  /// Phones: listens until the speaker pauses, for a tap on the mic
  /// rather than a hold.
  Future<void> listenOnce() async {
    if (_dictating || !onPhone) return;
    _phoneHeld = false;
    await _beginOnPhone(held: false);
  }

  /// Stops listening and emits the final text. Call on talk-key up.
  /// Ignored while dictating, so Space (or a space typed in a field)
  /// can't cut the consultation's transcript short.
  Future<void> stop() async {
    if (_dictating) return;
    if (onPhone) _phoneHeld = false;
    await _end();
  }

  Future<void> _begin() async {
    if (_listening || _starting) return;
    _starting = true;
    try {
      await init();
      await _ensureMic();
    } finally {
      _starting = false;
    }
    if (_listening) return;
    _utterance++;
    _began = DateTime.now();
    _starts.add(null);
    _audio
      ..clear()
      ..addAll(_preroll);
    _samples = _prerollCount;
    _preroll.clear();
    _prerollCount = 0;
    _fastDecodedSamples = 0;
    _accurateDecodedSamples = 0;
    _listening = true;
    _stream = null;
    if (_streamPort != 0) {
      _streamReady = _openStream(_utterance, _dictating);
      return;
    }
    // Dictation only needs the accurate partials; a second live stream
    // would just compete with them for the GPU.
    if (!_dictating && !_cloud) unawaited(_pumpFast(_utterance));
    if (model == 'server') {
      unawaited(_pumpAccurate(_utterance));
    }
  }

  /// The final pass in progress, so a second caller waits for the same one.
  Future<void>? _ending;

  Future<void> _end({bool? dictation}) {
    if (!_listening) return _ending ?? Future<void>.value();
    if (onPhone) return _endOnPhone();
    return _ending ??= _finish(
      dictation ?? _dictating,
    ).whenComplete(() => _ending = null);
  }

  Future<void> _finish(bool dictation) async {
    final utterance = _utterance;
    await Future<void>.delayed(_tail);
    if (utterance != _utterance) return;
    _listening = false;
    level.value = 0;

    // This utterance's stream; the next one may start while it finishes.
    final ready = _streamReady;
    final done = _streamFinal;
    _stream = null;
    _streamReady = null;
    _streamFinal = null;

    if (_samples < _sampleRate ~/ 4) {
      unawaited(ready?.then((ws) => ws?.close()));
      _transcripts.add(
        VoiceTranscript(
          '',
          isFinal: true,
          source: 'accurate',
          dictation: dictation,
        ),
      );
      return;
    }
    final short = _samples < _sampleRate * _shortSeconds;
    // Taken now: a new utterance may reset the buffer while this one waits.
    final clip = _snapshot(maxSamples: _maxWindow);
    final pass = short && !dictation ? 'short' : 'accurate';
    final (text, ms) =
        await _streamedFinal(ready, done) ??
        await _transcribe(clip, pass: pass, dictation: dictation);
    if (utterance != _utterance) return;
    if (dictation && text.isNotEmpty) {
      final all = '$_dictationContext $text'.trim();
      _dictationContext = all.length > 400
          ? all.substring(all.length - 400)
          : all;
    }
    _transcripts.add(
      VoiceTranscript(
        text,
        isFinal: true,
        latencyMs: ms,
        source: 'accurate',
        dictation: dictation,
      ),
    );
  }

  /// Whisper always decodes a padded 30 s window, so sending less audio
  /// saves nothing; cutting it only loses the start of the sentence.
  /// Sarvam's REST endpoint also takes up to 30 s.
  static const _maxWindow = _sampleRate * 30;

  /// Streams this utterance to Sarvam through the server's relay: live
  /// partials as it's spoken, and the final soon after [_streamedFinal]
  /// says it ended. Null when the relay can't be reached.
  Future<WebSocket?> _openStream(int utterance, bool dictation) async {
    final done = Completer<(String, int)>();
    // A stream that fails while nobody waits is not an error to report.
    done.future.ignore();
    _streamFinal = done;
    final WebSocket ws;
    try {
      ws = await WebSocket.connect(
        'ws://127.0.0.1:$_streamPort',
      ).timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('[SpeechEngine] stream unavailable: $e');
      return null;
    }
    if (utterance != _utterance) {
      unawaited(ws.close());
      return null;
    }
    ws.listen(
      (msg) {
        final j = jsonDecode(msg as String) as Map<String, dynamic>;
        final text = _clean(j['text'] as String? ?? '', keepCase: dictation);
        switch (j['type']) {
          case 'partial':
            if (_listening && utterance == _utterance && text.isNotEmpty) {
              _transcripts.add(
                VoiceTranscript(
                  text,
                  isFinal: false,
                  source: 'accurate',
                  dictation: dictation,
                ),
              );
            }
          case 'final':
            if (!done.isCompleted) {
              done.complete((text, (j['ms'] as num?)?.toInt() ?? 0));
            }
          case 'error':
            debugPrint('[SpeechEngine] stream error: ${j['message']}');
            if (!done.isCompleted) done.completeError(StateError('stream'));
        }
      },
      onDone: () {
        if (!done.isCompleted) done.completeError(StateError('closed'));
      },
      onError: (Object e) {
        if (!done.isCompleted) done.completeError(e);
      },
    );
    ws.add(
      jsonEncode({
        'hints': hints.join(', '),
        'mode': dictation ? 'dictation' : '',
        'context': dictation ? _dictationContext : '',
      }),
    );
    // Everything heard so far (pre-roll included); from here on, the mic
    // sends each chunk as it arrives.
    final caughtUp = _pcm16(_snapshot(maxSamples: _maxWindow));
    if (caughtUp.isNotEmpty) ws.add(caughtUp);
    if (_listening) _stream = ws;
    return ws;
  }

  /// The streamed utterance's final text, or null to fall back to a
  /// one-off transcription (no stream, or it failed).
  Future<(String, int)?> _streamedFinal(
    Future<WebSocket?>? ready,
    Completer<(String, int)>? done,
  ) async {
    if (ready == null || done == null) return null;
    final ws = await ready;
    if (ws == null) return null;
    try {
      ws.add(jsonEncode({'event': 'end'}));
      return await done.future.timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[SpeechEngine] stream final failed, transcribing whole: $e');
      return null;
    } finally {
      unawaited(ws.close());
    }
  }

  /// Hangs up the stream of an utterance being dropped (its counter has
  /// already moved on, so one still connecting closes itself).
  void _dropStream() {
    unawaited(_stream?.close());
    _stream = null;
    _streamReady = null;
    _streamFinal = null;
  }

  /// Live passes for the words as they're spoken.
  Future<void> _pumpFast(int utterance) async {
    while (_listening && utterance == _utterance) {
      // Wait for new audio, and for enough of it that Whisper doesn't
      // invent words from a fraction of a second.
      if (_samples - _fastDecodedSamples < _minNewSamples ||
          _samples < _sampleRate * 0.4) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        continue;
      }
      _fastDecodedSamples = _samples;
      final (text, ms) = await _transcribe(
        _snapshot(maxSamples: _maxWindow),
        pass: 'fast',
      );
      if (_listening && utterance == _utterance && text.isNotEmpty) {
        _transcripts.add(
          VoiceTranscript(text, isFinal: false, latencyMs: ms, source: 'fast'),
        );
      }
    }
  }

  /// Live accurate passes in parallel: clean field values. Fires whenever
  /// the last one is done and at least ~0.5 s of new audio is ready
  /// (1 s with Sarvam).
  Future<void> _pumpAccurate(int utterance) async {
    final dictation = _dictating;
    final every = _cloud ? _sampleRate : 8000;
    while (_listening && utterance == _utterance && _dictating == dictation) {
      if (_samples - _accurateDecodedSamples < every ||
          _samples < _sampleRate * 0.6) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        continue;
      }
      _accurateDecodedSamples = _samples;
      final (text, ms) = await _transcribe(
        _snapshot(maxSamples: _maxWindow),
        pass: 'accurate',
        dictation: dictation,
      );
      if (_listening && utterance == _utterance && text.isNotEmpty) {
        _transcripts.add(
          VoiceTranscript(
            text,
            isFinal: false,
            latencyMs: ms,
            source: 'accurate',
            dictation: dictation,
          ),
        );
      }
    }
  }

  Float32List _snapshot({int? maxSamples}) {
    final count = maxSamples != null
        ? math.min(_samples, maxSamples)
        : _samples;
    if (count <= 0) return Float32List(0);
    final out = Float32List(count);
    final skip = _samples - count;
    var current = 0;
    var written = 0;
    for (final chunk in _audio) {
      final chunkStart = current;
      final chunkEnd = current + chunk.length;
      current = chunkEnd;
      if (chunkEnd <= skip) continue;
      final offsetInChunk = math.max(0, skip - chunkStart);
      final take = math.min(chunk.length - offsetInChunk, count - written);
      out.setRange(written, written + take, chunk, offsetInChunk);
      written += take;
      if (written >= count) break;
    }
    return out;
  }

  /// [pass]: 'fast' (live), 'short' or 'accurate' (final). Only the GPU
  /// server has more than one model; on-device modes ignore it.
  ///
  /// [dictation]: a consultation, not a command; the server steers the
  /// model with clinical words (and, for Whisper, what was said before).
  Future<(String, int)> _transcribe(
    Float32List samples, {
    required String pass,
    bool dictation = false,
  }) {
    if (model == 'server') {
      return _transcribeOnServer(samples, pass, dictation);
    }
    final id = _nextJob++;
    final done = Completer<(String, int)>();
    _replies[id] = done;
    _worker!.send((id, samples));
    return done.future.then((r) => (_clean(r.$1, keepCase: dictation), r.$2));
  }

  Future<(String, int)> _transcribeOnServer(
    Float32List samples,
    String pass,
    bool dictation,
  ) async {
    try {
      final r = await _http.post(
        Uri.parse('$_server/transcribe'),
        headers: {
          'X-Hints': Uri.encodeComponent(hints.join(', ')),
          'X-Model': pass,
          if (dictation) 'X-Mode': 'dictation',
          if (dictation && _dictationContext.isNotEmpty)
            'X-Context': Uri.encodeComponent(_dictationContext),
        },
        body: _pcm16(samples),
      );
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      return (
        _clean(j['text'] as String? ?? '', keepCase: dictation),
        j['ms'] as int? ?? 0,
      );
    } catch (e) {
      debugPrint('[SpeechEngine] server error: $e');
      return ('', 0);
    }
  }

  /// The option closest in meaning to [text], with a 0–1 score, from the
  /// GPU server's sentence matcher. Null when the server isn't in use.
  Future<(String, double)?> closestMeaning(
    String text,
    List<({String id, List<String> phrases})> options,
  ) async {
    if (model != 'server' || !_serverUp) return null;
    try {
      final r = await _http
          .post(
            Uri.parse('$_server/intent'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'text': text,
              'options': [
                for (final o in options) {'id': o.id, 'phrases': o.phrases},
              ],
            }),
          )
          .timeout(const Duration(seconds: 2));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final id = j['id'] as String?;
      if (id == null) return null;
      return (id, (j['score'] as num).toDouble());
    } catch (e) {
      debugPrint('[SpeechEngine] meaning match failed: $e');
      return null;
    }
  }

  // ── Phones ─────────────────────────────────────────────────────────

  /// Android and iOS: no speech server, so the phone's own recognizer
  /// (Google's or Apple's) is used, with live partials. It owns the mic
  /// while it listens, so the always-open mic, pre-roll and hands-free
  /// are clinic-PC only.
  static bool get onPhone =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  final _phone = stt.SpeechToText();
  bool _phoneReady = false;
  String? _phoneLocale;

  /// The island is still held: when the recognizer stops at a pause it is
  /// started again, and the pieces make one utterance.
  bool _phoneHeld = false;

  /// This utterance's finished pieces, and the piece being spoken.
  String _phoneSaid = '';
  String _phoneHeard = '';

  /// Completes when the piece being listened to has ended.
  Completer<void>? _phonePiece;
  Timer? _phoneQuiet;

  /// Asks for the mic the first time voice is used, not at launch.
  Future<void> _initPhone() async {
    final ok = await _phone.initialize(
      onStatus: _onPhoneStatus,
      onError: (e) => debugPrint('[SpeechEngine] phone: ${e.errorMsg}'),
    );
    if (!ok) {
      _initFuture = null; // ask again on the next hold
      throw StateError(
        await _phone.hasPermission
            ? "This phone doesn't have speech recognition"
            : 'Allow the microphone to talk to CruDoc',
      );
    }
    // Indian English when the phone has it: names, "5 p.m.", rupees.
    try {
      final locales = await _phone.locales();
      _phoneLocale = locales
          .map((l) => l.localeId)
          .where((id) => id.toLowerCase().replaceAll('-', '_') == 'en_in')
          .firstOrNull;
    } catch (e) {
      debugPrint('[SpeechEngine] phone locales: $e');
    }
    _phoneReady = true;
  }

  /// [held]: started by a hold, so a release while the mic permission
  /// prompt was up means it shouldn't start at all.
  Future<void> _beginOnPhone({required bool held}) async {
    if (_listening || _starting) return;
    _starting = true;
    try {
      await init();
    } finally {
      _starting = false;
    }
    if (_listening || (held && !_phoneHeld)) return;
    _utterance++;
    _began = DateTime.now();
    _starts.add(null);
    _listening = true;
    _phoneSaid = '';
    unawaited(_listenOnPhone(_utterance));
  }

  /// One piece: until the recognizer stops at a pause, or the island is
  /// let go.
  Future<void> _listenOnPhone(int utterance) async {
    final piece = _phonePiece = Completer<void>();
    _phoneHeard = '';
    // A recognizer that never starts (busy, unavailable) ends the piece;
    // "listening" calls this off.
    _phoneQuiet?.cancel();
    _phoneQuiet = Timer(const Duration(seconds: 3), _endPhonePiece);
    try {
      await _phone.listen(
        onResult: (r) => _onPhoneResult(utterance, r),
        // Android reports roughly -2 to 10 dB.
        onSoundLevelChange: (db) =>
            level.value = ((db + 2) / 12).clamp(0.0, 1.0),
        listenOptions: stt.SpeechListenOptions(
          localeId: _phoneLocale,
          listenMode: stt.ListenMode.dictation,
          cancelOnError: true,
        ),
      );
    } catch (e) {
      debugPrint('[SpeechEngine] phone listen failed: $e');
      _endPhonePiece();
    }
    await piece.future;
    if (utterance != _utterance || !_listening) return;
    final words = _phoneHeard;
    _phoneSaid = '$_phoneSaid $words'.trim();
    // Still held after a pause: keep going, as one utterance. A piece
    // that heard nothing (silence, an error) ends it, so a recognizer
    // that keeps failing can't spin.
    final tooLong = DateTime.now().difference(_began!) > _maxUtterance;
    if (_phoneHeld && words.isNotEmpty && !tooLong) {
      return _listenOnPhone(utterance);
    }
    _listening = false;
    _phoneHeld = false;
    level.value = 0;
    _transcripts.add(
      VoiceTranscript(_clean(_phoneSaid), isFinal: true, source: 'accurate'),
    );
  }

  void _onPhoneResult(int utterance, SpeechRecognitionResult r) {
    if (utterance != _utterance || !_listening) return;
    _phoneHeard = r.recognizedWords.trim();
    // A piece ends with "done", below, once its last words are in.
    if (r.finalResult) return;
    final text = _clean('$_phoneSaid $_phoneHeard');
    if (text.isNotEmpty) {
      _transcripts.add(
        VoiceTranscript(text, isFinal: false, source: 'accurate'),
      );
    }
  }

  /// "done" comes once the recognizer has stopped and its last words are
  /// in. One that stops without them is given a moment, then ended.
  void _onPhoneStatus(String status) {
    if (status == stt.SpeechToText.listeningStatus) {
      _phoneQuiet?.cancel();
    } else if (status == stt.SpeechToText.doneStatus) {
      _endPhonePiece();
    } else if (status == stt.SpeechToText.notListeningStatus) {
      _phoneQuiet?.cancel();
      _phoneQuiet = Timer(const Duration(seconds: 2), _endPhonePiece);
    }
  }

  void _endPhonePiece() {
    _phoneQuiet?.cancel();
    final piece = _phonePiece;
    if (piece != null && !piece.isCompleted) piece.complete();
  }

  /// The island is let go: the recognizer finishes the last words.
  Future<void> _endOnPhone() async {
    final utterance = _utterance;
    await Future<void>.delayed(_tail);
    if (utterance != _utterance || !_listening) return;
    await _phone.stop();
    if (utterance != _utterance || !_listening) return;
    // A recognizer that never answers still ends the utterance.
    _phoneQuiet?.cancel();
    _phoneQuiet = Timer(const Duration(seconds: 3), () {
      if (utterance != _utterance || !_listening) return;
      unawaited(_phone.cancel());
      _endPhonePiece();
    });
  }

  /// Whisper writes "Tomorrow at 5 p.m."; lower-case it for the parser,
  /// and drop the "Thank you." it sometimes invents from silence.
  static String _clean(String text, {bool keepCase = false}) {
    final t = keepCase ? text.trim() : text.trim().toLowerCase();
    final bare = t.toLowerCase().replaceAll(RegExp(r'[^a-z ]'), '').trim();
    const invented = {
      'thank you',
      'thanks for watching',
      'thank you for watching',
      'thank you so much',
      'bye',
      'you',
      '',
    };
    return invented.contains(bare) ? '' : t;
  }

  /// Floats in [-1, 1] → PCM16 little-endian.
  static Uint8List _pcm16(Float32List samples) {
    final pcm = Int16List(samples.length);
    for (var i = 0; i < samples.length; i++) {
      pcm[i] = (samples[i] * 32767).round().clamp(-32768, 32767);
    }
    return pcm.buffer.asUint8List();
  }

  /// PCM16 little-endian → floats in [-1, 1].
  static Float32List _toFloat32(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final out = Float32List(bytes.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }

  /// On Windows the bundled assets sit next to the exe, so the model is
  /// read in place instead of being copied out of the asset bundle.
  static String _modelDir() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final dir = p.join(
      exeDir,
      'data',
      'flutter_assets',
      'assets',
      'voice',
      model == 'parakeet' ? 'parakeet' : 'whisper',
    );
    if (!Directory(dir).existsSync()) {
      debugPrint('[SpeechEngine] model folder missing: $dir');
    }
    return dir;
  }
}

/// Background isolate: owns the recognizer and transcribes each
/// clip it is sent, replying (job id, text, milliseconds).
void _workerMain((SendPort, String, String) args) {
  final (reply, dir, model) = args;
  final sherpa.OfflineRecognizer recognizer;
  try {
    sherpa.initBindings();
    String f(String name) => p.join(dir, '$model-$name');
    String g(String name) => p.join(dir, name);
    recognizer = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(
        model: model == 'parakeet'
            ? sherpa.OfflineModelConfig(
                transducer: sherpa.OfflineTransducerModelConfig(
                  encoder: g('encoder.int8.onnx'),
                  decoder: g('decoder.int8.onnx'),
                  joiner: g('joiner.int8.onnx'),
                ),
                tokens: g('tokens.txt'),
                modelType: 'nemo_transducer',
                numThreads: 4,
              )
            : sherpa.OfflineModelConfig(
                whisper: sherpa.OfflineWhisperModelConfig(
                  encoder: f('encoder.int8.onnx'),
                  decoder: f('decoder.int8.onnx'),
                  language: 'en',
                  task: 'transcribe',
                ),
                tokens: f('tokens.txt'),
                numThreads: 4,
              ),
      ),
    );
  } catch (e) {
    reply.send('Speech model failed to load: $e');
    return;
  }

  final inbox = ReceivePort();
  reply.send(inbox.sendPort);
  inbox.listen((msg) {
    final (id, samples) = msg as (int, Float32List);
    final watch = Stopwatch()..start();
    final stream = recognizer.createStream();
    stream.acceptWaveform(samples: samples, sampleRate: 16000);
    recognizer.decode(stream);
    final text = recognizer.getResult(stream).text;
    stream.free();
    reply.send((id, text, watch.elapsedMilliseconds));
  });
}
