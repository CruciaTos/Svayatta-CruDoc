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

/// One transcript update. [isFinal] is true once the doctor lets go of the
/// talk key; partials arrive while they are still speaking.
class VoiceTranscript {
  const VoiceTranscript(this.text, {required this.isFinal, this.latencyMs});

  final String text;
  final bool isFinal;

  /// How long the model took to produce this text.
  final int? latencyMs;
}

/// Offline speech-to-text for the Windows demo build, using Parakeet or
/// Whisper through sherpa-onnx.
///
/// Neither streams, so while the talk key is held the audio so far
/// is re-transcribed every [_partialEvery]; that gives the live, filling-in
/// feel. A last pass runs when the key is released. Decoding happens in a
/// background isolate so the UI never stalls. Nothing leaves the machine.
class SpeechEngine {
  SpeechEngine._();
  static final instance = SpeechEngine._();

  /// 'server': Whisper on the laptop GPU, run by
  /// tool/voice_server/server.py (most accurate and fastest here): base.en
  /// for the live words, small.en / large-v3-turbo for the final pass.
  /// On-device fallbacks via sherpa-onnx: 'parakeet' (CPU, slow on long
  /// clips) or a Whisper size, 'base.en' / 'small.en'; their files live in
  /// assets/voice/parakeet/ or assets/voice/whisper/.
  static const model = 'server';
  static const _server = 'http://127.0.0.1:8765';
  static const _sampleRate = 16000;

  /// New audio needed before the next live pass. The GPU server is quick
  /// enough to go again almost at once; on-device models are not.
  static const _minNewSamples = model == 'server' ? 1920 : 8000;

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
  int _decodedSamples = 0;
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
  bool _stopping = false;
  double _noise = 0.01;
  DateTime? _lastVoice;
  DateTime? _began;
  static const _endSilence = Duration(milliseconds: 700);
  static const _maxUtterance = Duration(seconds: 15);

  Future<void> setHandsFree(bool on) async {
    await init();
    await _ensureMic();
    _handsFree = on;
    if (!on && _listening) await stop();
  }

  bool get isListening => _listening;
  bool get isReady => _worker != null || _serverUp;
  bool _serverUp = false;

  /// Loads the model (or starts the GPU server). Safe to call repeatedly.
  Future<void> init() => _initFuture ??= () async {
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
    if (_handsFree) _detectSpeech(f);
    if (_listening) {
      var peak = 0.0;
      for (final x in f) {
        final a = x.abs();
        if (a > peak) peak = a;
      }
      level.value = math.min(1, peak * 3);
      _audio.add(f);
      _samples += f.length;
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
        unawaited(start());
      } else {
        _noise = _noise * 0.95 + rms * 0.05;
      }
      return;
    }
    if (speaking) _lastVoice = now;
    final quiet = now.difference(_lastVoice ?? now) > _endSilence;
    final tooLong = now.difference(_began ?? now) > _maxUtterance;
    if (quiet || tooLong) unawaited(stop());
  }

  Future<bool> _ping() async {
    try {
      final r = await http
          .get(Uri.parse('$_server/health'))
          .timeout(const Duration(seconds: 2));
      return r.statusCode == 200;
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
      _serverProcess = await Process.start(
        p.join(dir, '.venv', 'Scripts', 'python.exe'),
        ['server.py'],
        workingDirectory: dir,
      );
      _serverProcess!.stdout.listen(
        (b) => debugPrint('[voice_server] ${String.fromCharCodes(b).trim()}'),
      );
      _serverProcess!.stderr.listen(
        (b) => debugPrint('[voice_server] ${String.fromCharCodes(b).trim()}'),
      );
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      while (!await _ping()) {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('Voice server did not start');
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

  /// Starts listening. Call on talk-key down.
  Future<void> start() async {
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
    _decodedSamples = 0;
    _listening = true;
    unawaited(_pump(_utterance));
  }

  /// Stops listening and emits the final text. Call on talk-key up.
  Future<void> stop() async {
    if (!_listening || _stopping) return;
    _stopping = true;
    final utterance = _utterance;
    await Future<void>.delayed(_tail);
    _stopping = false;
    if (utterance != _utterance) return;
    _listening = false;
    level.value = 0;

    if (_samples < _sampleRate ~/ 4) {
      _transcripts.add(const VoiceTranscript('', isFinal: true));
      return;
    }
    final short = _samples < _sampleRate * _shortSeconds;
    final (text, ms) = await _transcribe(
      _snapshot(),
      pass: short ? 'short' : 'accurate',
    );
    if (utterance != _utterance) return;
    _transcripts.add(VoiceTranscript(text, isFinal: true, latencyMs: ms));
  }

  /// Live passes, back to back, while the key is held.
  Future<void> _pump(int utterance) async {
    while (_listening && utterance == _utterance) {
      // Wait for new audio, and for enough of it that Whisper doesn't
      // invent words from a fraction of a second.
      if (_samples - _decodedSamples < _minNewSamples ||
          _samples < _sampleRate * 0.4) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        continue;
      }
      _decodedSamples = _samples;
      final (text, ms) = await _transcribe(_snapshot(), pass: 'fast');
      if (_listening && utterance == _utterance && text.isNotEmpty) {
        _transcripts.add(VoiceTranscript(text, isFinal: false, latencyMs: ms));
      }
    }
  }

  Float32List _snapshot() {
    final out = Float32List(_samples);
    var o = 0;
    for (final chunk in _audio) {
      out.setAll(o, chunk);
      o += chunk.length;
    }
    return out;
  }

  /// [pass]: 'fast' (live), 'short' or 'accurate' (final). Only the GPU
  /// server has more than one model; on-device modes ignore it.
  Future<(String, int)> _transcribe(
    Float32List samples, {
    required String pass,
  }) {
    if (model == 'server') return _transcribeOnServer(samples, pass);
    final id = _nextJob++;
    final done = Completer<(String, int)>();
    _replies[id] = done;
    _worker!.send((id, samples));
    return done.future.then((r) => (_clean(r.$1), r.$2));
  }

  Future<(String, int)> _transcribeOnServer(
    Float32List samples,
    String pass,
  ) async {
    final pcm = Int16List(samples.length);
    for (var i = 0; i < samples.length; i++) {
      pcm[i] = (samples[i] * 32767).round().clamp(-32768, 32767);
    }
    try {
      final r = await _http.post(
        Uri.parse('$_server/transcribe'),
        headers: {
          'X-Hints': Uri.encodeComponent(hints.join(', ')),
          'X-Model': pass,
        },
        body: pcm.buffer.asUint8List(),
      );
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      return (_clean(j['text'] as String? ?? ''), j['ms'] as int? ?? 0);
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
    if (model != 'server') return null;
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

  /// Whisper writes "Tomorrow at 5 p.m."; lower-case it for the parser,
  /// and drop the "Thank you." it sometimes invents from silence.
  static String _clean(String text) {
    final t = text.trim().toLowerCase();
    final bare = t.replaceAll(RegExp(r'[^a-z ]'), '').trim();
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
