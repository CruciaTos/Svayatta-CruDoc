import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/router/app_router.dart';
import 'package:doctor_management_app/core/theme/cru_colors.dart';
import 'package:doctor_management_app/core/theme/cru_tokens.dart';
import 'package:doctor_management_app/core/theme/cru_type.dart';

import '../services/speech_engine.dart';
import '../voice_controller.dart';

/// Hold F2 anywhere in the app to talk. A pill at the top shows the words
/// live while talking, then what the app understood, and prompts for
/// "confirm" once a form is ready.
class VoiceOverlay extends ConsumerStatefulWidget {
  const VoiceOverlay({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<VoiceOverlay> createState() => _VoiceOverlayState();
}

class _VoiceOverlayState extends ConsumerState<VoiceOverlay> {
  final _engine = SpeechEngine.instance;
  // This overlay sits above the app's Navigator (MaterialApp.builder), so
  // forms and screens are opened from the router's navigator instead.
  late final VoiceController _voice = VoiceController(
    ref,
    () => appRouter.routerDelegate.navigatorKey.currentContext ?? context,
  );
  StreamSubscription<VoiceTranscript>? _sub;
  String _heard = '';
  int? _ms;
  bool _loaded = false;
  String? _error;
  bool _listening = false;
  bool _isDuplicate = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The shell can mount a second copy; only the outermost one listens.
    final hasAncestor =
        context.findAncestorStateOfType<_VoiceOverlayState>() != null;
    if (hasAncestor && !_isDuplicate) {
      _isDuplicate = true;
      HardwareKeyboard.instance.removeHandler(_onKey);
      _sub?.cancel();
    }
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _voice.understood.addListener(_onUnderstood);
    // Every utterance, key-held or hands-free, starts here.
    _startSub = _engine.utteranceStarts.listen((_) {
      _voice.beginUtterance();
      if (mounted) {
        setState(() {
          _listening = true;
          _heard = '';
        });
      }
    });
    _sub = _engine.transcripts.listen((t) {
      _voice.onTranscript(t);
      if (mounted) {
        setState(() {
          _heard = t.text;
          _ms = t.latencyMs ?? _ms;
          if (t.isFinal) _listening = false;
        });
      }
    });
    _engine.init().then(
      (_) => mounted ? setState(() => _loaded = true) : null,
      onError: (Object e) =>
          mounted ? setState(() => _error = 'Voice model failed: $e') : null,
    );
  }

  StreamSubscription<void>? _startSub;
  DateTime? _keyDownAt;

  /// The last result stays up a few seconds, then the pill shrinks back
  /// to its resting size, like the iPhone's island.
  bool _showResult = true;
  Timer? _shrink;

  void _onUnderstood() {
    _shrink?.cancel();
    if (mounted && !_showResult) setState(() => _showResult = true);
    _shrink = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      // Still in use: a form waiting for "confirm", a missing field, an
      // open question, or speech. Check again later.
      final busy =
          _voice.ready.value ||
          _voice.hint.value != null ||
          _voice.asking.value != null ||
          _listening;
      if (busy) {
        _onUnderstood();
      } else {
        setState(() => _showResult = false);
      }
    });
  }

  /// Space held while typing: the field and what it held before the key.
  EditableText? _field;
  TextEditingValue? _fieldBefore;
  bool _fromField = false;

  /// The text field being typed in, if any.
  static EditableText? _typingField() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return null;
    final w = ctx.widget;
    if (w is EditableText) return w;
    return ctx.findAncestorWidgetOfExactType<EditableText>();
  }

  /// Hold Space (or F2): push-to-talk. Tap it: hands-free on or off. In a
  /// text field a tap still types a space; holding it switches to voice.
  bool _onKey(KeyEvent e) {
    // 1–4 answer the question on the pill.
    final ask = _voice.asking.value;
    if (ask != null && e is KeyDownEvent && _typingField() == null) {
      const keys = [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
      ];
      final i = keys.indexOf(e.logicalKey);
      if (i >= 0 && i < ask.options.length) {
        _voice.pickChoice(i);
        return true;
      }
    }
    final space = e.logicalKey == LogicalKeyboardKey.space;
    if (!space && e.logicalKey != LogicalKeyboardKey.f2) return false;
    if (!_loaded) return false;

    if (e is KeyDownEvent) {
      final field = space ? _typingField() : null;
      _keyDownAt = DateTime.now();
      _fromField = field != null;
      if (field != null) {
        // Might just be typing a space: wait to see if it's held.
        _field = field;
        _fieldBefore = field.controller.value;
        return false;
      }
      if (!_engine.handsFree) _talk();
      return true;
    }
    if (e is KeyRepeatEvent) {
      if (_fromField && !_engine.isListening && !_engine.handsFree) {
        // Held in a text field: talk instead of typing. Leave the field
        // and take back the spaces the hold typed.
        FocusManager.instance.primaryFocus?.unfocus();
        final before = _fieldBefore;
        if (before != null) _field?.controller.value = before;
        _talk();
      }
      return _keyDownAt != null;
    }
    if (e is KeyUpEvent && _keyDownAt != null) {
      final held = DateTime.now().difference(_keyDownAt!);
      _keyDownAt = null;
      _field = null;
      _fieldBefore = null;
      if (_fromField) {
        _fromField = false;
        if (_engine.isListening && !_engine.handsFree) _engine.stop();
        return false;
      }
      if (held < const Duration(milliseconds: 300)) {
        _toggleHandsFree();
      } else if (!_engine.handsFree) {
        _engine.stop();
      }
      return true;
    }
    return false;
  }

  void _talk() {
    _engine.start().catchError((Object err) {
      if (mounted) setState(() => _error = 'Microphone failed: $err');
    });
  }

  Future<void> _toggleHandsFree() async {
    final on = !_engine.handsFree;
    // A tap also started push-to-talk; drop that sliver of audio.
    if (_engine.isListening) await _engine.stop();
    await _engine.setHandsFree(on);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _sub?.cancel();
    _startSub?.cancel();
    _shrink?.cancel();
    _voice.understood.removeListener(_onUnderstood);
    _voice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isDuplicate) return widget.child;
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: CruSpace.s16,
          right: CruSpace.s16,
          top: CruSpace.s12,
          child: Center(
            child: Material(
              type: MaterialType.transparency,
              child: Center(
                child: ListenableBuilder(
                  listenable: Listenable.merge([
                    _voice.understood,
                    _voice.ready,
                    _voice.hint,
                    _voice.asking,
                  ]),
                  builder: (context, _) => _Strip(
                    listening: _listening,
                    loaded: _loaded,
                    error: _error,
                    understood: _showResult ? _voice.understood.value : null,
                    ready: _voice.ready.value,
                    need: _voice.hint.value,
                    heard: _heard,
                    ms: _ms,
                    handsFree: _engine.handsFree,
                    onMic: _loaded ? _toggleHandsFree : null,
                    ask: _voice.asking.value,
                    level: _engine.level,
                    onPick: (i) => _voice.pickChoice(i),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// What the pill is doing; each has its own contents and size.
enum _Mode { resting, listening, result, question }

/// The voice pill: one rounded surface that grows and shrinks to fit what
/// it is doing, like the iPhone's island. At rest it is a small capsule;
/// while listening it widens with the words and sound bars; with a result
/// it shows one line; with a question it opens into a card of choices
/// (say one, tap it, or press its number). The old contents fade out
/// inside while the new ones fade and settle in, so it reads as the same
/// object changing shape rather than one widget swapped for another.
class _Strip extends StatelessWidget {
  const _Strip({
    required this.listening,
    required this.loaded,
    required this.error,
    required this.understood,
    required this.ready,
    required this.need,
    required this.heard,
    required this.ms,
    required this.handsFree,
    required this.onMic,
    required this.ask,
    required this.onPick,
    required this.level,
  });

  /// Always listening; utterances end at pauses.
  final bool handsFree;

  /// Tapping the mic switches hands-free on or off.
  final VoidCallback? onMic;

  final bool listening;
  final bool loaded;
  final String? error;
  final String? understood;
  final bool ready;

  /// Required fields the open form still needs.
  final String? need;
  final String heard;
  final int? ms;

  /// The question waiting for an answer, if any.
  final VoiceAsk? ask;
  final void Function(int index) onPick;

  /// Mic loudness while listening, for the sound bars.
  final ValueListenable<double> level;

  /// Shape changes: a little longer than a fade so the resize reads as
  /// one continuous movement.
  static const _morph = Duration(milliseconds: 280);

  /// Contents never overlap: the old ones are gone in [_fadeOut], and
  /// the new ones only start appearing after that ([_fadeIn]).
  static const _fadeIn = Duration(milliseconds: 260);
  static const _fadeOut = Duration(milliseconds: 90);
  static const _inCurve = Interval(0.35, 1, curve: Curves.easeOutCubic);

  /// Half the capsule's height, so it stays a true capsule, and close to
  /// the card radius so the corners ease rather than snap.
  static const _capsuleRadius = 20.0;
  static const _maxWidth = 560.0;
  static const _cardWidth = 400.0;

  /// Keeps the newest words in view, like a live caption.
  static String _tail(String s, int max) =>
      s.length <= max ? s : '…${s.substring(s.length - max)}';

  _Mode get _mode {
    if (ask != null) return _Mode.question;
    if (listening) return _Mode.listening;
    final hasLine = understood != null && understood!.isNotEmpty;
    if (error != null || !loaded || hasLine) return _Mode.result;
    return _Mode.resting;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final mode = _mode;

    final Widget contents = switch (mode) {
      _Mode.resting => _resting(c),
      _Mode.listening => _listening(c),
      _Mode.result => _result(c),
      _Mode.question => _question(c),
    };

    return AnimatedContainer(
      duration: _morph,
      curve: Curves.easeOutCubic,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(
          mode == _Mode.question ? CruRadius.card : _capsuleRadius,
        ),
        border: Border.all(
          color: listening || ready || ask != null ? c.ai : c.hairline,
        ),
      ),
      child: AnimatedSize(
        duration: _morph,
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: _fadeIn,
          reverseDuration: _fadeOut,
          switchInCurve: _inCurve,
          switchOutCurve: Curves.easeOutCubic,
          // The new contents set the size; the old ones fade out on top
          // without holding the surface at their size.
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [
              for (final p in previous)
                Positioned.fill(
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minWidth: 0,
                    maxWidth: _maxWidth,
                    minHeight: 0,
                    maxHeight: double.infinity,
                    child: p,
                  ),
                ),
              ?current,
            ],
          ),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              alignment: Alignment.topCenter,
              scale: Tween(begin: 0.96, end: 1.0).animate(animation),
              child: child,
            ),
          ),
          child: KeyedSubtree(
            key: ValueKey(
              mode == _Mode.question ? 'question:${ask!.prompt}' : mode,
            ),
            child: contents,
          ),
        ),
      ),
    );
  }

  Widget _micIcon(CruColors c, IconData icon, {required bool lit}) =>
      GestureDetector(
        onTap: onMic,
        child: MouseRegion(
          cursor: onMic == null ? MouseCursor.defer : SystemMouseCursors.click,
          child: Icon(icon, size: 18, color: lit ? c.ai : c.label3),
        ),
      );

  TextStyle _lineStyle(CruColors c) => CruType.callout.copyWith(
    color: c.label,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// Small capsule: how to start.
  Widget _resting(CruColors c) => Padding(
    padding: const EdgeInsets.fromLTRB(
      CruSpace.s12,
      CruSpace.s8,
      CruSpace.s16,
      CruSpace.s8,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _micIcon(c, handsFree ? Icons.hearing : Icons.mic_none, lit: handsFree),
        const SizedBox(width: CruSpace.s8),
        Text(
          handsFree ? 'Hands-free' : 'Hold Space',
          style: CruType.callout.copyWith(color: c.label2),
        ),
      ],
    ),
  );

  /// Wider capsule: sound bars and the words as they come, and under
  /// them, live, what the app makes of them.
  Widget _listening(CruColors c) {
    final response = understood;
    final hasResponse = response != null && response.isNotEmpty;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 280, maxWidth: _maxWidth),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CruSpace.s16,
          vertical: CruSpace.s10,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Bars(level: level),
                const SizedBox(width: CruSpace.s12),
                Flexible(
                  child: Text(
                    heard.isEmpty ? 'Listening…' : _tail(heard, 56),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: hasResponse
                        ? CruType.caption.copyWith(color: c.label3)
                        : _lineStyle(c),
                  ),
                ),
              ],
            ),
            if (hasResponse) ...[
              const SizedBox(height: CruSpace.s4),
              Padding(
                // Lines up with the words, past the sound bars.
                padding: const EdgeInsets.only(left: 18 + CruSpace.s12),
                child: Text(
                  response,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _lineStyle(c),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Capsule with what happened, and what's next ("say confirm").
  Widget _result(CruColors c) {
    final String line;
    if (error != null) {
      line = error!;
    } else if (!loaded) {
      line = 'Loading voice model…';
    } else {
      line = understood!;
    }
    final hint = ready
        ? 'say "confirm"'
        : need ?? (ms != null && loaded && error == null ? '$ms ms' : null);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: _maxWidth),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CruSpace.s16,
          vertical: CruSpace.s10,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _micIcon(
              c,
              handsFree ? Icons.hearing : Icons.mic_none,
              lit: ready || handsFree,
            ),
            const SizedBox(width: CruSpace.s8),
            Flexible(
              // A new result fades in over the last one.
              child: AnimatedSwitcher(
                duration: _fadeIn,
                reverseDuration: _fadeOut,
                switchInCurve: _inCurve,
                switchOutCurve: Curves.easeOutCubic,
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [...previous, ?current],
                ),
                child: Text(
                  line,
                  key: ValueKey(line),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _lineStyle(c),
                ),
              ),
            ),
            if (hint != null) ...[
              const SizedBox(width: CruSpace.s12),
              Text(
                hint,
                style: CruType.caption.copyWith(
                  color: ready
                      ? c.ai
                      : need != null
                      ? c.amberText
                      : c.label3,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Card: the question and its choices.
  Widget _question(CruColors c) => SizedBox(
    width: _cardWidth,
    child: Padding(
      padding: const EdgeInsets.all(CruSpace.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CruSpace.s4),
            child: Row(
              children: [
                Icon(Icons.help_outline, size: 18, color: c.ai),
                const SizedBox(width: CruSpace.s8),
                Expanded(
                  child: Text(
                    ask!.prompt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: CruType.headline.copyWith(color: c.label),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: CruSpace.s12),
          for (var i = 0; i < ask!.options.length; i++) ...[
            if (i > 0) const SizedBox(height: CruSpace.s4),
            _ChoiceRow(
              index: i,
              choice: ask!.options[i],
              onTap: () => onPick(i),
            ),
          ],
          const SizedBox(height: CruSpace.s8),
          Text(
            'Say it, tap it, or press its number',
            textAlign: TextAlign.center,
            style: CruType.caption.copyWith(color: c.label3),
          ),
        ],
      ),
    ),
  );
}

/// One answer in the open pill: its number, what it is, and a detail line.
class _ChoiceRow extends StatefulWidget {
  const _ChoiceRow({
    required this.index,
    required this.choice,
    required this.onTap,
  });

  final int index;
  final VoiceChoice choice;
  final VoidCallback onTap;

  @override
  State<_ChoiceRow> createState() => _ChoiceRowState();
}

class _ChoiceRowState extends State<_ChoiceRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final detail = widget.choice.detail;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(
            horizontal: CruSpace.s12,
            vertical: CruSpace.s8,
          ),
          decoration: BoxDecoration(
            color: _hover ? c.hoverFill : c.inset,
            borderRadius: BorderRadius.circular(CruRadius.control),
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.aiTint,
                  borderRadius: BorderRadius.circular(CruRadius.full),
                ),
                child: Text(
                  '${widget.index + 1}',
                  style: CruType.caption.copyWith(
                    color: c.ai,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.choice.label,
                      style: CruType.callout.copyWith(color: c.label),
                    ),
                    if (detail != null)
                      Text(
                        detail,
                        style: CruType.caption.copyWith(
                          color: c.label3,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Four bars that rise and fall with the doctor's voice.
class _Bars extends StatelessWidget {
  const _Bars({required this.level});

  final ValueListenable<double> level;

  static const _shape = [0.55, 1.0, 0.75, 0.4];
  static const _height = 16.0;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return SizedBox(
      height: _height,
      child: ValueListenableBuilder<double>(
        valueListenable: level,
        builder: (context, v, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _shape.length; i++) ...[
              if (i > 0) const SizedBox(width: CruSpace.s2),
              AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                curve: Curves.easeOutCubic,
                width: 3,
                height: 4 + (_height - 4) * (0.2 + 0.8 * v) * _shape[i],
                decoration: BoxDecoration(
                  color: c.ai,
                  borderRadius: BorderRadius.circular(CruRadius.full),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
