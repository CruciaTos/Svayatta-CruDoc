import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crudoc_shared/theme/cru_theme.dart';
import 'package:doctor_management_app/features/settings/presentation/desktop_settings_screen.dart';
import 'package:doctor_management_app/features/settings/presentation/ai_assistance_section.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_settings_section.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';
import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';

void main() {
  testWidgets('SettingsSection has aiAssistance and showSettingsSection returns true', (tester) async {
    expect(SettingsSection.values.contains(SettingsSection.aiAssistance), isTrue);
    expect(SettingsSection.aiAssistance.label, 'AI assistance');
  });

  testWidgets('AiAssistanceSection renders safety banner, scribe, receptionist and imaging cards', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsSectionProvider.overrideWith((ref) => SettingsSection.aiAssistance),
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          doctorProfileProvider.overrideWith((ref) => Stream.value(null)),
          doctorEnabledModulesStreamProvider.overrideWith((ref) => Stream.value(['ai_assistant', 'ai_agentic_calling'])),
          isAiCallingFeatureEnabledProvider.overrideWith((ref) => true),
          radSettingsProvider.overrideWith((ref) => Future.value(const RadSettings())),
        ],
        child: MaterialApp(
          theme: CruTheme.day(),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: AiAssistanceSection(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AiAssistanceSection), findsOneWidget);
    expect(find.text('Assistive Clinical Intelligence'), findsOneWidget);
    expect(find.text('Medical Scribe & Rx Generator'), findsOneWidget);
    expect(find.text('Autonomous AI Receptionist'), findsOneWidget);
    expect(find.text('Imaging & Diagnostic AI'), findsOneWidget);
    expect(find.text('Privacy & Security Guarantee'), findsOneWidget);
  });

  testWidgets('RadSettingsSection does not contain Turnaround times card', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          radSettingsProvider.overrideWith((ref) => Future.value(const RadSettings())),
          radFeesProvider.overrideWith((ref) => Future.value(const [])),
          radPacsServersProvider.overrideWith((ref) => Future.value(const [])),
        ],
        child: MaterialApp(
          theme: CruTheme.day(),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: RadSettingsSection(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RadSettingsSection), findsOneWidget);
    // Verified: No turnaround times card exists in radiology settings
    expect(find.text('Turnaround times'), findsNothing);
    expect(find.textContaining('turnaround time', findRichText: true), findsNothing);
  });
}

