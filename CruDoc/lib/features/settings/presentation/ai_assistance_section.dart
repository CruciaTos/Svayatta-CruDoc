import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/services/ai_consent.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';
import 'package:doctor_management_app/features/mobile/mobile_more.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';
import 'package:doctor_management_app/features/radiology/viewer_plus/ai/ai_panels.dart';
import 'package:doctor_management_app/features/settings/presentation/desktop_settings_screen.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Settings → AI assistance: clinical AI companion, ambient medical scribe,
/// autonomous voice calling receptionist, and imaging & radiology AI tools.
class AiAssistanceSection extends ConsumerWidget {
  const AiAssistanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final modules =
        ref.watch(doctorEnabledModulesStreamProvider).value ??
        DoctorFeatureGuard.defaultModules;
    final isScribeEnabled = DoctorFeatureGuard.isEnabled(
      modules,
      'ai_assistant',
    );
    final isCallingEnabled = ref.watch(isAiCallingFeatureEnabledProvider);

    const gap = SizedBox(height: CruSpace.cardGap);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Clinician-in-the-loop safety banner
        _SafetyBanner(),
        gap,

        // Cloud AI consent switch
        const _CloudAiSwitchCard(),
        gap,

        // Medical Scribe & Consultation AI
        _Card(
          title: 'Medical Scribe & Rx Generator',
          trailing: CruPill(
            text: isScribeEnabled ? 'Active' : 'AI Add-on',
            icon: isScribeEnabled ? CruIcons.check : CruIcons.sparkleSingle,
            background: isScribeEnabled ? c.greenTint : c.inset,
            foreground: isScribeEnabled ? c.greenText : c.label2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FeatureRow(
                icon: CruIcons.mic,
                title: 'Ambient consultation scribe',
              ),
              const CruSeparator(),
              _FeatureRow(
                icon: CruIcons.pen,
                title: 'Digital Rx pre-filling',
              ),
              const CruSeparator(),
              _FeatureRow(
                icon: CruIcons.sparkle,
                title: 'Clinical differentials & red flags',
              ),
            ],
          ),
        ),
        gap,

        // Autonomous AI Receptionist & Voice Calling
        _Card(
          title: 'Autonomous AI Receptionist',
          trailing: CruPill(
            text: isCallingEnabled ? 'Connected' : 'AI Add-on',
            icon: isCallingEnabled ? CruIcons.check : CruIcons.phone,
            background: isCallingEnabled ? c.greenTint : c.inset,
            foreground: isCallingEnabled ? c.greenText : c.label2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FeatureRow(
                icon: CruIcons.phone,
                title: 'Call forwarding integration',
              ),
              const SizedBox(height: CruSpace.s12),
              Align(
                alignment: Alignment.centerLeft,
                child: CruButton(
                  label: 'Configure call forwarding',
                  icon: CruIcons.phone,
                  kind: CruButtonKind.secondary,
                  onPressed: () {
                    ref.read(settingsSectionProvider.notifier).state =
                        SettingsSection.callForwarding;
                    if (cruIsPhone(context)) {
                      openMobileSettings(
                        context,
                        ref,
                        SettingsSection.callForwarding,
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        gap,

        // Imaging & Radiology AI Switches
        _Card(
          title: 'Imaging & Diagnostic AI',
          child: const RadAiSwitches(),
        ),
        gap,

        // Privacy & HIPAA Compliance
        _Card(
          title: 'Privacy & Security',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FeatureRow(
                icon: CruIcons.check,
                title: 'Never used to train public models',
              ),
              const CruSeparator(),
              _FeatureRow(
                icon: CruIcons.sparkleSingle,
                title: 'Identifiers stripped on this device',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Clinician-in-the-loop safety banner reminding doctor that AI is assistive.
class _SafetyBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruCard(
      semanticLabel: 'AI Safety and Principles',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: CruSize.iconTile,
            height: CruSize.iconTile,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: c.aiTint,
              shape: cruShape(CruRadius.iconTile),
            ),
            child: CruIcon(
              CruIcons.sparkle,
              size: 20,
              strokeWidth: 2,
              color: c.ai,
            ),
          ),
          const SizedBox(width: CruSpace.s16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You confirm every suggestion',
                  style: CruType.headline.tint(c.label),
                ),
                const SizedBox(height: CruSpace.s4),
                Text(
                  'Every suggestion needs your confirmation. It is not a diagnosis.',
                  style: CruType.text.tint(c.label2),
                ),
                const SizedBox(height: CruSpace.s12),
                Wrap(
                  spacing: CruSpace.s8,
                  runSpacing: CruSpace.s8,
                  children: [
                    CruPill(
                      text: 'Clinician confirmed',
                      icon: CruIcons.check,
                      background: c.aiTint,
                      foreground: c.ai,
                    ),
                    CruPill(
                      text: 'On-device de-identification',
                      icon: CruIcons.sparkleSingle,
                      background: c.aiTint,
                      foreground: c.ai,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.title, this.detail});

  final CruIconData icon;
  final String title;

  /// A second line, only where the title cannot carry the meaning on its own.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CruSpace.s12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CruIcon(icon, size: 18, strokeWidth: 1.8, color: c.label2),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: CruType.callout.w600.tint(c.label)),
                if (detail case final d?) ...[
                  const SizedBox(height: CruSpace.s2),
                  Text(d, style: CruType.caption.tint(c.label2)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.child,
    this.description,
    this.trailing,
  });

  final String title;
  final String? description;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruCard(
      semanticLabel: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: CruType.headline.tint(c.label)),
                    if (description != null) ...[
                      const SizedBox(height: CruSpace.s4),
                      Text(description!, style: CruType.text.tint(c.label2)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: CruSpace.s16),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: CruSpace.s20),
          child,
        ],
      ),
    );
  }
}

class _CloudAiSwitchCard extends StatefulWidget {
  const _CloudAiSwitchCard();

  @override
  State<_CloudAiSwitchCard> createState() => _CloudAiSwitchCardState();
}

class _CloudAiSwitchCardState extends State<_CloudAiSwitchCard> {
  bool _granted = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await AiConsent.read();
    if (mounted) {
      setState(() {
        _granted = v == true;
        _loaded = true;
      });
    }
  }

  Future<void> _toggle(bool value) async {
    await AiConsent.set(value);
    if (mounted) {
      setState(() => _granted = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return _Card(
      title: 'Cloud AI',
      description: 'Notes, voice and scans are sent to Google Gemini.',
      trailing: _loaded
          ? Semantics(
              toggled: _granted,
              child: CruPressable(
                onTap: () => _toggle(!_granted),
                semanticLabel: 'Use cloud AI',
                builder: (context, hovered) => AnimatedContainer(
                  duration: CruMotion.of(context, CruMotion.fast),
                  curve: CruMotion.curve,
                  width: CruSpace.s32 + CruSpace.s8,
                  height: CruSpace.s24,
                  padding: const EdgeInsets.all(CruSpace.s2),
                  alignment: _granted
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: _granted ? c.accent : c.track,
                    borderRadius: BorderRadius.circular(CruRadius.full),
                  ),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: c.surface,
                      shape: BoxShape.circle,
                      boxShadow: c.cardShadow,
                    ),
                  ),
                ),
              ),
            )
          : null,
      child: _FeatureRow(
        icon: CruIcons.sparkle,
        title: 'Use cloud AI',
        detail: _granted ? 'On' : 'Off',
      ),
    );
  }
}
