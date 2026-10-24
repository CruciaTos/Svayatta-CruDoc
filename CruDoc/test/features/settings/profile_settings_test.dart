import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crudoc_shared/theme/cru_theme.dart';
import 'package:doctor_management_app/features/onboarding/presentation/doctor_loyalty_card.dart';
import 'package:doctor_management_app/features/settings/presentation/desktop_settings_screen.dart';
import 'package:doctor_management_app/features/onboarding/data/loyalty_card.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';

void main() {
  testWidgets('DoctorLoyaltyCard renders with loyalty card view', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          loyaltyCardProvider.overrideWith(
            (ref) => Stream.value(
              const LoyaltyCard(stamps: 2, stampedMonths: ['2026-09', '2026-10']),
            ),
          ),
          doctorProfileProvider.overrideWith(
            (ref) => Stream.value({
              'fullName': 'Dr. Soham Boridkar',
            }),
          ),
        ],
        child: MaterialApp(
          theme: CruTheme.day(),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: DoctorLoyaltyCard(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DoctorLoyaltyCard), findsOneWidget);
    expect(find.text('LOYALTY CARD'), findsOneWidget);
    expect(find.text('Dr. Soham Boridkar'), findsOneWidget);
  });

  testWidgets('Settings Profile tab contains DoctorLoyaltyCard and no separate name card or doctor info card', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsSectionProvider.overrideWith((ref) => SettingsSection.profile),
          loyaltyCardProvider.overrideWith(
            (ref) => Stream.value(
              const LoyaltyCard(stamps: 1, stampedMonths: ['2026-10']),
            ),
          ),
          doctorProfileProvider.overrideWith(
            (ref) => Stream.value({
              'fullName': 'Dr. Soham Boridkar',
            }),
          ),
        ],
        child: MaterialApp(
          theme: CruTheme.day(),
          home: const Scaffold(
            body: DesktopSettingsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Loyalty card is present
    expect(find.byType(DoctorLoyaltyCard), findsOneWidget);

    // Old "Your name" card title should NOT be present as a separate card
    expect(find.text('Shown on the dashboard, prescriptions and bills.'), findsNothing);

    // Old "Your profile" semantic label should NOT be present
    expect(find.bySemanticsLabel('Your profile'), findsNothing);
  });
}
