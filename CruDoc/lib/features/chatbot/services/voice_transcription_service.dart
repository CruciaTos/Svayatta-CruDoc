import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:doctor_management_app/firebase_options.dart';

/// Exception thrown when audio recording or transcription fails.
class VoiceTranscriptionException implements Exception {
  final String message;
  const VoiceTranscriptionException(this.message);

  @override
  String toString() => message;
}

/// Service that handles microphone audio recording and speech-to-text
/// transcription using Gemini 2.0 Flash multimodal audio processing.
class VoiceTranscriptionService {
  VoiceTranscriptionService._();
  static final instance = VoiceTranscriptionService._();

  final AudioRecorder _recorder = AudioRecorder();
  String? _currentAudioPath;
  DateTime? _recordingStartTime;

  static const String _model = 'gemini-2.0-flash';
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  String get _apiKey {
    const envKey = String.fromEnvironment('GEMINI_API_KEY');
    if (envKey.isNotEmpty) return envKey;
    try {
      final key = DefaultFirebaseOptions.currentPlatform.apiKey;
      if (key.isNotEmpty) return key;
    } catch (_) {}
    return '';
  }

  /// Checks if microphone permission is granted. Requests permission if not.
  Future<bool> hasPermission() async {
    try {
      return await _recorder.hasPermission();
    } catch (e) {
      debugPrint('[VoiceTranscriptionService] Permission check error: $e');
      return false;
    }
  }

  /// Starts recording microphone audio to a local AAC file.
  Future<void> startRecording() async {
    try {
      final hasPerm = await hasPermission();
      if (!hasPerm) {
        throw const VoiceTranscriptionException(
          'Microphone permission was denied. Please allow microphone access in Settings.',
        );
      }

      // If already recording, stop first
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }

      final tempDir = await getTemporaryDirectory();
      final id = const Uuid().v4();
      _currentAudioPath = '${tempDir.path}/chat_voice_$id.m4a';
      _recordingStartTime = DateTime.now();

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _currentAudioPath!,
      );
    } catch (e) {
      debugPrint('[VoiceTranscriptionService] Start recording failed: $e');
      if (e is VoiceTranscriptionException) rethrow;
      throw VoiceTranscriptionException('Could not start recording: $e');
    }
  }

  /// Retrieves the current audio amplitude for waveform visualization.
  Future<Amplitude> getAmplitude() async {
    try {
      return await _recorder.getAmplitude();
    } catch (_) {
      return Amplitude(current: -160.0, max: -160.0);
    }
  }

  /// Stops audio recording, validates audio length, and transcribes the speech.
  Future<String> stopAndTranscribe() async {
    try {
      final audioPath = await _recorder.stop();
      final path = audioPath ?? _currentAudioPath;

      if (path == null) {
        throw const VoiceTranscriptionException('No audio recording found.');
      }

      final file = File(path);
      if (!await file.exists()) {
        throw const VoiceTranscriptionException('Audio file could not be found.');
      }

      final fileSizeBytes = await file.length();
      final duration = _recordingStartTime != null
          ? DateTime.now().difference(_recordingStartTime!)
          : Duration.zero;

      // Validate audio length and minimum bytes
      if (duration.inMilliseconds < 400 || fileSizeBytes < 800) {
        throw const VoiceTranscriptionException(
          'Recording was too short. Please hold the mic and speak clearly.',
        );
      }

      final audioBytes = await file.readAsBytes();

      // Transcribe via Gemini
      final transcript = await _transcribeAudio(audioBytes);

      // Clean up temporary audio file
      try {
        await file.delete();
      } catch (_) {}

      if (transcript.trim().isEmpty) {
        throw const VoiceTranscriptionException(
          'No clear speech detected. Please speak louder or closer to the microphone.',
        );
      }

      return transcript.trim();
    } catch (e) {
      debugPrint('[VoiceTranscriptionService] Stop & transcribe failed: $e');
      if (e is VoiceTranscriptionException) rethrow;
      throw VoiceTranscriptionException('Voice transcription failed: $e');
    } finally {
      _currentAudioPath = null;
      _recordingStartTime = null;
    }
  }

  /// Cancels and deletes the current audio recording without transcribing.
  Future<void> cancelRecording() async {
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
      if (_currentAudioPath != null) {
        final file = File(_currentAudioPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e) {
      debugPrint('[VoiceTranscriptionService] Cancel recording error: $e');
    } finally {
      _currentAudioPath = null;
      _recordingStartTime = null;
    }
  }

  /// Internal speech-to-text transcription engine using Gemini multimodal audio.
  Future<String> _transcribeAudio(Uint8List audioBytes) async {
    const prompt =
        'Transcribe the spoken audio query verbatim. '
        'The speaker is a doctor asking a question or giving a command. '
        'Return ONLY the direct transcribed text. '
        'Do NOT include formatting tags, quotes, explanations, or timestamps.';

    // Try Firebase AI first
    try {
      final model = FirebaseAI.googleAI().generativeModel(
        model: _model,
      );

      final audioPart = InlineDataPart('audio/mp4', audioBytes);
      final response = await model.generateContent([
        Content.multi([TextPart(prompt), audioPart]),
      ]).timeout(const Duration(seconds: 8));

      final text = response.text?.trim() ?? '';
      if (text.isNotEmpty) {
        return _cleanTranscript(text);
      }
    } catch (e) {
      debugPrint('[VoiceTranscriptionService] FirebaseAI error, trying REST: $e');
    }

    // Fallback to Gemini REST API
    try {
      final apiKey = _apiKey;
      final url = Uri.parse('$_baseUrl/$_model:generateContent?key=$apiKey');
      final base64Audio = base64Encode(audioBytes);

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': prompt},
                {
                  'inline_data': {
                    'mime_type': 'audio/mp4',
                    'data': base64Audio,
                  }
                }
              ]
            }
          ],
          'generationConfig': {
            'temperature': 0.1,
            'maxOutputTokens': 256,
          },
        }),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final candidates = body['candidates'] as List<dynamic>?;
        if (candidates != null && candidates.isNotEmpty) {
          final content = candidates[0]['content'] as Map<String, dynamic>?;
          final parts = content?['parts'] as List<dynamic>?;
          if (parts != null && parts.isNotEmpty) {
            final text = parts[0]['text'] as String? ?? '';
            return _cleanTranscript(text);
          }
        }
      }
    } catch (e) {
      debugPrint('[VoiceTranscriptionService] REST fallback error: $e');
    }

    return '';
  }

  String _cleanTranscript(String text) {
    var cleaned = text.trim();
    // Remove surrounding quotes if model returned '"How to add patient"'
    if ((cleaned.startsWith('"') && cleaned.endsWith('"')) ||
        (cleaned.startsWith("'") && cleaned.endsWith("'"))) {
      cleaned = cleaned.substring(1, cleaned.length - 1).trim();
    }
    // Remove potential "Transcript:" prefix
    if (cleaned.toLowerCase().startsWith('transcript:')) {
      cleaned = cleaned.substring(11).trim();
    }
    return cleaned;
  }

  /// Disposes the internal recorder resource.
  void dispose() {
    _recorder.dispose();
  }
}
