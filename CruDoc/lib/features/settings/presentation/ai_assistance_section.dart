import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

        // Medical Scribe & Consultation AI
        _Card(
          title: 'Medical Scribe & Rx Generator',
          description:
              'Voice clinical dictation, SOAP progress notes generation, and automated prescription drafting.',
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
                detail:
                    'Listens to doctor-patient conversation and creates structured Subjective, Objective, Assessment & Plan notes in real time.',
              ),
              const CruSeparator(),
              _FeatureRow(
                icon: CruIcons.pen,
                title: 'Digital Rx pre-filling',
                detail:
                    'Extracts medication names, dosages, timings, and durations mentioned during the consultation into prescription cards.',
              ),
              const CruSeparator(),
              _FeatureRow(
                icon: CruIcons.sparkle,
                title: 'Clinical differentials & red flags',
                detail:
                    'Surfaces relevant ICD-10 differential diagnosis considerations and alerts for drug-allergy contraindications.',
              ),
            ],
          ),
        ),
        gap,

        // Autonomous AI Receptionist & Voice Calling
        _Card(
          title: 'Autonomous AI Receptionist',
          description:
              'Autonomous phone agent to call patients for automated confirmations & follow-ups.',
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
                detail:
                    'Forward missed or clinic calls to your AI receptionist with one tap. Patients speak naturally to book appointments.',
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
          description:
              'Multi-modal computer vision tools for dental X-rays, CBCT volumes, and cephalometric analysis.',
          child: const RadAiSwitches(),
        ),
        gap,

        // Privacy & HIPAA Compliance
        _Card(
          title: 'Privacy & Security Guarantee',
          description:
              'Patient health records and imaging are protected under enterprise healthcare compliance standards.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FeatureRow(
                icon: CruIcons.check,
                title: 'Zero public training retention',
                detail:
                    'Patient audio, notes, and radiographs are never used to train or refine public AI models.',
              ),
              const CruSeparator(),
              _FeatureRow(
                icon: CruIcons.sparkleSingle,
                title: 'Local PHI de-identification',
                detail:
                    'Personal identifiers (names, contacts, government IDs) are stripped on-device before any model evaluation.',
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
                  'Assistive Clinical Intelligence',
                  style: CruType.headline.tint(c.label),
                ),
                const SizedBox(height: CruSpace.s4),
                Text(
                  'CruDoc AI features are designed to support and accelerate your practice. '
                  'Every suggestion, drafted note, and detection requires your review and confirmation; '
                  'it is never an autonomous diagnosis on its own.',
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
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final CruIconData icon;
  final String title;
  final String detail;

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
                const SizedBox(height: CruSpace.s2),
                Text(detail, style: CruType.caption.tint(c.label2)),
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
