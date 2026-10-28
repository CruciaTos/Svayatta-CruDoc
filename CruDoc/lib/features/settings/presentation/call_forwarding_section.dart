import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/settings/data/call_forwarding_platform.dart';
import 'package:doctor_management_app/features/settings/domain/call_forwarding.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Settings → Call forwarding: sends the doctor's own number to the clinic's
/// AI receptionist in one tap.
///
/// Android opens the dialler with the code filled in, so the doctor only
/// presses call. iOS will not open dialler links containing * or #, so the
/// iPhone gets the code with a copy button. Jio blocks the code for
/// forwarding every call, so Jio gets the phone-settings steps for that one.
class CallForwardingSection extends ConsumerStatefulWidget {
  const CallForwardingSection({super.key, this.platform});

  /// For tests; this device otherwise.
  final ForwardPlatform? platform;

  @override
  ConsumerState<CallForwardingSection> createState() =>
      _CallForwardingSectionState();
}

class _CallForwardingSectionState extends ConsumerState<CallForwardingSection> {
  ForwardMode _mode = ForwardMode.all;

  /// The doctor's own pick; until then, what the SIM says.
  PhoneNetwork? _network;

  ForwardPlatform get _platform => widget.platform ?? currentForwardPlatform;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final line = ref.watch(clinicVoiceLineProvider);
    return line.when(
      loading: () => _Card(
        title: 'AI receptionist',
        child: Text('Loading…', style: CruType.text.tint(c.label2)),
      ),
      error: (_, _) => _Card(
        title: 'AI receptionist',
        child: Text(
          "Couldn't load your AI number. Check the connection.",
          style: CruType.text.tint(c.label2),
        ),
      ),
      data: (line) => line == null
          ? const _Card(
              title: 'No AI number yet',
              description:
                  'Your AI receptionist number shows here once CruDoc sets '
                  'it up. Then you can forward your calls to it in one tap.',
            )
          : _body(line),
    );
  }

  Widget _body(VoiceLine line) {
    final sim = ref.watch(callingSimProvider).value;
    final network = _network ?? sim?.network ?? PhoneNetwork.other;
    final detected = _network == null && sim != null;
    final method = forwardMethod(
      platform: _platform,
      network: network,
      mode: _mode,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LineCard(line: line),
        if (line.waitingForTestCall) ...[
          const SizedBox(height: CruSpace.cardGap),
          _TestCallCard(line: line, platform: _platform),
        ],
        const SizedBox(height: CruSpace.cardGap),
        _Card(
          title: 'Turn on forwarding',
          description: _platform == ForwardPlatform.other
              ? 'Do this on the phone whose calls should reach the AI.'
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Choice<ForwardMode>(
                label: 'Forward',
                values: ForwardMode.values,
                labelOf: (m) => m.label,
                selected: _mode,
                onChanged: (m) => setState(() => _mode = m),
                caption: switch (_mode) {
                  ForwardMode.all =>
                    'The AI answers every call. Your phone does not ring.',
                  ForwardMode.missed =>
                    'Your phone rings first. The AI answers when you are '
                        'busy, do not pick up, or are out of reach.',
                },
              ),
              const SizedBox(height: CruSpace.s20),
              _Choice<PhoneNetwork>(
                label: 'Your network',
                values: PhoneNetwork.values,
                labelOf: (n) => n.label,
                selected: network,
                onChanged: (n) => setState(() => _network = n),
                caption: detected
                    ? (sim.sure
                          ? 'Picked from the SIM this phone calls from.'
                          : 'Picked from this phone. Change it if you call '
                                'from your other SIM.')
                    : null,
              ),
              const SizedBox(height: CruSpace.s20),
              const CruSeparator(),
              const SizedBox(height: CruSpace.s20),
              _TurnOn(
                method: method,
                mode: _mode,
                line: line,
                platform: _platform,
                primary: !line.waitingForTestCall,
              ),
            ],
          ),
        ),
        const SizedBox(height: CruSpace.cardGap),
        _Card(
          title: 'Turn off forwarding',
          child: _TurnOff(method: method, mode: _mode, platform: _platform),
        ),
      ],
    );
  }
}

// =============================================================================
// THE LINE
// =============================================================================

class _LineCard extends StatelessWidget {
  const _LineCard({required this.line});

  final VoiceLine line;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final (text, bg, fg) = line.paused
        ? ('Paused', c.inset, c.label2)
        : line.waitingForTestCall
        ? ('Waiting for test call', c.amberTint, c.amberText)
        : ('Active', c.greenTint, c.greenText);
    final from = line.publishedNumber;
    return _Card(
      title: 'AI receptionist',
      description: from == null
          ? 'Forwarded calls are answered by your AI receptionist.'
          : 'Calls to ${formatIndianNumber(from)} that you forward are '
                'answered by your AI receptionist.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CruIconTile(icon: CruIcons.phone, tone: CruTileTone.neutral),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatIndianNumber(line.aiNumber),
                      style: CruType.callout.tabular.tint(c.label),
                    ),
                    const SizedBox(height: CruSpace.s2),
                    Text('AI number', style: CruType.caption.tint(c.label2)),
                  ],
                ),
              ),
              const SizedBox(width: CruSpace.s12),
              _CopyButton(
                text: dialableIndianNumber(line.aiNumber),
                done: 'AI number copied',
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s12),
          CruPill(text: text, background: bg, foreground: fg),
          if (line.paused) ...[
            const SizedBox(height: CruSpace.s8),
            Text(
              'The AI is paused, so forwarded callers hear that it is not '
              'available. Keep forwarding off until it is back on.',
              style: CruType.caption.tint(c.label2),
            ),
          ],
        ],
      ),
    );
  }
}

/// A new line starts as "pending test": the doctor calls the AI once from
/// their own number, the AI confirms, and the line turns active.
class _TestCallCard extends StatelessWidget {
  const _TestCallCard({required this.line, required this.platform});

  final VoiceLine line;
  final ForwardPlatform platform;

  @override
  Widget build(BuildContext context) {
    final from = line.publishedNumber;
    return _Card(
      title: 'First, a test call',
      description:
          'Call your AI number once from '
          '${from == null ? 'your own number' : formatIndianNumber(from)}. '
          'It confirms your number and hangs up. Then turn on forwarding.',
      child: platform == ForwardPlatform.other
          ? const SizedBox.shrink()
          : Align(
              alignment: Alignment.centerLeft,
              child: CruButton(
                label: 'Call AI number',
                icon: CruIcons.phone,
                onPressed: () async {
                  final ok = await CallForwardingPlatform.dial(
                    dialableIndianNumber(line.aiNumber),
                  );
                  if (!ok && context.mounted) {
                    _toast(context, "Couldn't open the dialler.");
                  }
                },
              ),
            ),
    );
  }
}

// =============================================================================
// TURN ON / OFF
// =============================================================================

class _TurnOn extends StatelessWidget {
  const _TurnOn({
    required this.method,
    required this.mode,
    required this.line,
    required this.platform,
    required this.primary,
  });

  final ForwardMethod method;
  final ForwardMode mode;
  final VoiceLine line;
  final ForwardPlatform platform;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final code = forwardOnCode(mode, line.aiNumber)!;
    final number = formatIndianNumber(line.aiNumber);
    switch (method) {
      case ForwardMethod.dial:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CruButton(
              label: 'Turn on: ${mode.label.toLowerCase()}',
              icon: CruIcons.phone,
              large: true,
              kind: primary ? CruButtonKind.primary : CruButtonKind.secondary,
              onPressed: () => _dial(context, code),
            ),
            const SizedBox(height: CruSpace.s12),
            Text(
              'Your dialler opens with $code filled in. Press call once. '
              'A dual-SIM phone asks which SIM: pick the one patients call.',
              style: CruType.caption.tint(c.label2),
            ),
          ],
        );
      case ForwardMethod.copyCode:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CodeBox(code: code),
            const SizedBox(height: CruSpace.s16),
            _Steps([
              'Tap Copy.',
              platform == ForwardPlatform.ios
                  ? 'Open the Phone app and go to Keypad.'
                  : 'On your phone, open the Phone app keypad.',
              'Paste the code (or type it) and press call.',
            ]),
          ],
        );
      case ForwardMethod.phoneSettings:
        final ios = platform == ForwardPlatform.ios;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Jio blocks the code for forwarding every call, so set it in '
              "your phone's settings instead.",
              style: CruType.text.tint(c.label2),
            ),
            const SizedBox(height: CruSpace.s16),
            _Steps(
              ios
                  ? [
                      'Open Settings, then Apps, then Phone (on older '
                          'iPhones, Settings, then Phone).',
                      'Tap Call Forwarding and switch it on.',
                      'Tap Forward To and enter $number.',
                    ]
                  : [
                      platform == ForwardPlatform.android
                          ? 'Tap Open call settings below.'
                          : 'Open the Phone app, tap ⋮, then Settings.',
                      'Open Call forwarding (on some phones it is under '
                          'Supplementary services or More settings).',
                      'Pick your Jio SIM, then Voice calls.',
                      'Tap Always forward, enter $number and tap '
                          'Turn on (or Enable).',
                    ],
            ),
            const SizedBox(height: CruSpace.s16),
            Wrap(
              spacing: CruSpace.s12,
              runSpacing: CruSpace.s12,
              children: [
                if (platform == ForwardPlatform.android)
                  CruButton(
                    label: 'Open call settings',
                    kind: primary
                        ? CruButtonKind.primary
                        : CruButtonKind.secondary,
                    onPressed: () => _openCallSettings(context),
                  ),
                _CopyButton(
                  text: dialableIndianNumber(line.aiNumber),
                  label: 'Copy AI number',
                  done: 'AI number copied',
                ),
              ],
            ),
          ],
        );
    }
  }
}

class _TurnOff extends StatelessWidget {
  const _TurnOff({
    required this.method,
    required this.mode,
    required this.platform,
  });

  final ForwardMethod method;
  final ForwardMode mode;
  final ForwardPlatform platform;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final code = forwardOffCode(mode);
    switch (method) {
      case ForwardMethod.dial:
        return _OffRow(
          detail: 'Opens your dialler with $code. Press call once.',
          action: CruButton(
            label: 'Turn off',
            kind: CruButtonKind.inset,
            onPressed: () => _dial(context, code),
          ),
        );
      case ForwardMethod.copyCode:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CodeBox(code: code),
            const SizedBox(height: CruSpace.s12),
            Text(
              'Copy, paste in the Phone keypad and press call.',
              style: CruType.caption.tint(c.label2),
            ),
          ],
        );
      case ForwardMethod.phoneSettings:
        final ios = platform == ForwardPlatform.ios;
        final how = ios
            ? 'Open Settings, then Phone, then Call Forwarding, and switch '
                  'it off.'
            : 'Go back to Call forwarding, tap Always forward and tap Turn off '
                  '(or Disable).';
        return platform == ForwardPlatform.android
            ? _OffRow(
                detail: how,
                action: CruButton(
                  label: 'Open call settings',
                  kind: CruButtonKind.inset,
                  onPressed: () => _openCallSettings(context),
                ),
              )
            : Text(how, style: CruType.text.tint(c.label2));
    }
  }
}

class _OffRow extends StatelessWidget {
  const _OffRow({required this.detail, required this.action});

  final String detail;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(detail, style: CruType.text.tint(c.label2)),
        const SizedBox(height: CruSpace.s12),
        action,
      ],
    );
  }
}

Future<void> _dial(BuildContext context, String code) async {
  final ok = await CallForwardingPlatform.dial(code);
  if (!ok && context.mounted) {
    await Clipboard.setData(ClipboardData(text: code));
    if (context.mounted) {
      _toast(
        context,
        "Couldn't open the dialler. The code is copied: paste it in the "
        'Phone keypad and press call.',
      );
    }
  }
}

Future<void> _openCallSettings(BuildContext context) async {
  final ok = await CallForwardingPlatform.openCallSettings();
  if (!ok && context.mounted) {
    _toast(context, 'Open the Phone app, tap ⋮, then Settings.');
  }
}

// =============================================================================
// PIECES
// =============================================================================

class _Card extends StatelessWidget {
  const _Card({required this.title, this.description, this.child});

  final String title;
  final String? description;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruCard(
      semanticLabel: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: CruType.headline.tint(c.label)),
          if (description != null) ...[
            const SizedBox(height: CruSpace.s4),
            Text(description!, style: CruType.text.tint(c.label2)),
          ],
          if (child != null) ...[const SizedBox(height: CruSpace.s20), child!],
        ],
      ),
    );
  }
}

/// A labelled segmented choice with an optional caption under it.
class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.values,
    required this.labelOf,
    required this.selected,
    required this.onChanged,
    this.caption,
  });

  final String label;
  final List<T> values;
  final String Function(T) labelOf;
  final T selected;
  final ValueChanged<T> onChanged;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: CruType.caption.w600.tint(c.label2)),
        const SizedBox(height: CruSpace.s8),
        CruSegmentedControl<T>(
          semanticLabel: label,
          segments: [for (final v in values) CruSegment(v, labelOf(v))],
          selected: selected,
          onChanged: onChanged,
        ),
        if (caption != null) ...[
          const SizedBox(height: CruSpace.s8),
          Text(caption!, style: CruType.caption.tint(c.label2)),
        ],
      ],
    );
  }
}

/// The code, large enough to read back, with Copy beside it.
class _CodeBox extends StatelessWidget {
  const _CodeBox({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s16,
        CruSpace.s12,
        CruSpace.s12,
        CruSpace.s12,
      ),
      decoration: ShapeDecoration(
        color: c.inset,
        shape: cruShape(CruRadius.control),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              code,
              style: CruType.headline.tabular.tint(c.label),
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          _CopyButton(text: code, done: 'Code copied'),
        ],
      ),
    );
  }
}

class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.text, required this.done, this.label});

  final String text;
  final String done;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return CruCapsuleButton(
      label: label ?? 'Copy',
      kind: CruCapsuleKind.surface,
      height: CruSize.control,
      onPressed: () {
        Clipboard.setData(ClipboardData(text: text));
        _toast(context, done);
      },
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps(this.steps);

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : CruSpace.s8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: CruSpace.s20,
                  child: Text(
                    '${i + 1}.',
                    style: CruType.text.tabular.tint(c.label3),
                  ),
                ),
                Expanded(
                  child: Text(steps[i], style: CruType.text.tint(c.label)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

void _toast(BuildContext context, String message) {
  final c = context.cru;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(message, style: CruType.text.tint(c.surface)),
      backgroundColor: c.label,
      behavior: SnackBarBehavior.floating,
      shape: cruShape(CruRadius.control),
      margin: const EdgeInsets.all(CruSpace.s16),
      duration: const Duration(seconds: 3),
    ),
  );
}
