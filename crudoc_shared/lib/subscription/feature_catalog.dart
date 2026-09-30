/// Information about a purchasable feature module.
class FeaturePricingItem {
  final String moduleKey;
  final String title;
  final String description;
  final double monthlyPriceInr;
  final bool isBaseModule;
  final String iconName;

  const FeaturePricingItem({
    required this.moduleKey,
    required this.title,
    required this.description,
    required this.monthlyPriceInr,
    this.isBaseModule = false,
    required this.iconName,
  });
}

/// Every module a doctor can have, shared by the clinic app (upgrade
/// screen) and Super Admin (upgrade requests).
const List<FeaturePricingItem> featureCatalog = [
  FeaturePricingItem(
    moduleKey: 'dashboard',
    title: 'Practice Dashboard',
    description: 'Daily visit metrics, quick calendar access & notifications',
    monthlyPriceInr: 0,
    isBaseModule: true,
    iconName: 'dashboard',
  ),
  FeaturePricingItem(
    moduleKey: 'patients',
    title: 'Patient Records & EMR',
    description:
        'Complete patient profiles, medical history & encounter logs',
    monthlyPriceInr: 0,
    isBaseModule: true,
    iconName: 'groups',
  ),
  FeaturePricingItem(
    moduleKey: 'appointments',
    title: 'Appointments & Calendar',
    description: 'Schedule management, multi-slot booking & calendar sheets',
    monthlyPriceInr: 0,
    isBaseModule: true,
    iconName: 'calendar',
  ),
  FeaturePricingItem(
    moduleKey: 'inventory',
    title: 'Clinic Pharmacy & Inventory',
    description: 'Stock tracking, low-stock alerts & dispense auditing',
    monthlyPriceInr: 0,
    isBaseModule: true,
    iconName: 'inventory',
  ),
  FeaturePricingItem(
    moduleKey: 'revenue',
    title: 'Revenue Analytics & Invoicing',
    description:
        'Income tracking, digital receipts, billing sheets & financial summaries',
    monthlyPriceInr: 999,
    iconName: 'payments',
  ),
  FeaturePricingItem(
    moduleKey: 'home_visits',
    title: 'Home Visitations & Maps GPS',
    description: 'Home consultation tracking, geocoding & route planning',
    monthlyPriceInr: 1499,
    iconName: 'home',
  ),
  FeaturePricingItem(
    moduleKey: 'omnichannel_messaging',
    title: 'WhatsApp, SMS & Gmail Messaging',
    description:
        'Automated 10-min appointment reminders & digital Rx dispatch to patients',
    monthlyPriceInr: 1999,
    iconName: 'chat',
  ),
  FeaturePricingItem(
    moduleKey: 'ai_assistant',
    title: 'AI Medical Scribe & Rx Generator',
    description:
        'Voice clinical dictation, SOAP generation & instant structured prescriptions',
    monthlyPriceInr: 2499,
    iconName: 'smart_toy',
  ),
  FeaturePricingItem(
    moduleKey: 'ai_agentic_calling',
    title: 'Autonomous AI Voice Calling',
    description:
        'AI phone agent to call patients for automated confirmations & follow-ups',
    monthlyPriceInr: 3999,
    iconName: 'phone',
  ),
  FeaturePricingItem(
    moduleKey: 'multi_device_access',
    title: 'Multi-Device & Receptionist Access',
    description:
        'Simultaneous login across mobile, tablet, desktop & staff kiosks',
    monthlyPriceInr: 799,
    iconName: 'devices',
  ),
];
