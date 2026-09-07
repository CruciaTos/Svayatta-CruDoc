import 'package:shared_preferences/shared_preferences.dart';

/// Manages local user preferences for desktop clinical settings,
/// notifications, AI scribe configuration, billing defaults, and appearance.
class DesktopSettingsPreferences {
  DesktopSettingsPreferences();

  // ---------------- Keys ----------------
  // Clinical / Scribe
  static const String _kScribeLanguageKey = 'crudoc.settings.scribe_language';
  static const String _kNoteFormatKey = 'crudoc.settings.note_format';
  static const String _kAutoGenerateRxKey = 'crudoc.settings.auto_generate_rx';
  static const String _kAutoExtractDiagnosesKey = 'crudoc.settings.auto_extract_diagnoses';
  static const String _kAudioQualityKey = 'crudoc.settings.audio_quality';

  // Billing & Invoices
  static const String _kCurrencySymbolKey = 'crudoc.settings.currency_symbol';
  static const String _kDefaultConsultationFeeKey = 'crudoc.settings.default_consultation_fee';
  static const String _kDefaultFollowUpFeeKey = 'crudoc.settings.default_follow_up_fee';
  static const String _kGstEnabledKey = 'crudoc.settings.gst_enabled';
  static const String _kGstRateKey = 'crudoc.settings.gst_rate';
  static const String _kInvoicePrefixKey = 'crudoc.settings.invoice_prefix';
  static const String _kPaymentTermsDaysKey = 'crudoc.settings.payment_terms_days';
  static const String _kDefaultPaymentModeKey = 'crudoc.settings.default_payment_mode';

  // Notifications & Alerts
  static const String _kLowStockAlertsKey = 'crudoc.settings.low_stock_alerts';
  static const String _kExpiryAlertsKey = 'crudoc.settings.expiry_alerts';
  static const String _kQueueSoundChimeKey = 'crudoc.settings.queue_sound_chime';
  static const String _kAppointmentRemindersKey = 'crudoc.settings.appointment_reminders';
  static const String _kCriticalVitalsAlertKey = 'crudoc.settings.critical_vitals_alert';

  // Appearance & Desktop
  static const String _kCompactDensityKey = 'crudoc.settings.compact_density';
  static const String _kSoundEffectsKey = 'crudoc.settings.sound_effects';
  static const String _kHardwareAccelerationKey = 'crudoc.settings.hardware_acceleration';

  // ---------------- Methods ----------------

  // Scribe Language
  Future<String> getScribeLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kScribeLanguageKey) ?? 'English (India)';
  }

  Future<void> setScribeLanguage(String language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kScribeLanguageKey, language);
  }

  // Note Format
  Future<String> getNoteFormat() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kNoteFormatKey) ?? 'SOAP (Subjective, Objective, Assessment, Plan)';
  }

  Future<void> setNoteFormat(String format) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kNoteFormatKey, format);
  }

  // Auto Generate Rx
  Future<bool> getAutoGenerateRx() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAutoGenerateRxKey) ?? true;
  }

  Future<void> setAutoGenerateRx(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoGenerateRxKey, value);
  }

  // Auto Extract Diagnoses
  Future<bool> getAutoExtractDiagnoses() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAutoExtractDiagnosesKey) ?? true;
  }

  Future<void> setAutoExtractDiagnoses(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoExtractDiagnosesKey, value);
  }

  // Audio Quality
  Future<String> getAudioQuality() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kAudioQualityKey) ?? 'High Fidelity (44.1 kHz)';
  }

  Future<void> setAudioQuality(String quality) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAudioQualityKey, quality);
  }

  // Currency Symbol
  Future<String> getCurrencySymbol() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kCurrencySymbolKey) ?? '₹';
  }

  Future<void> setCurrencySymbol(String symbol) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCurrencySymbolKey, symbol);
  }

  // Default Consultation Fee
  Future<double> getDefaultConsultationFee() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_kDefaultConsultationFeeKey) ?? 500.0;
  }

  Future<void> setDefaultConsultationFee(double fee) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kDefaultConsultationFeeKey, fee);
  }

  // Default Follow-Up Fee
  Future<double> getDefaultFollowUpFee() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_kDefaultFollowUpFeeKey) ?? 300.0;
  }

  Future<void> setDefaultFollowUpFee(double fee) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kDefaultFollowUpFeeKey, fee);
  }

  // GST Enabled
  Future<bool> getGstEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kGstEnabledKey) ?? false;
  }

  Future<void> setGstEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kGstEnabledKey, enabled);
  }

  // GST Rate
  Future<double> getGstRate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_kGstRateKey) ?? 18.0;
  }

  Future<void> setGstRate(double rate) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kGstRateKey, rate);
  }

  // Invoice Prefix
  Future<String> getInvoicePrefix() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kInvoicePrefixKey) ?? 'CRU-';
  }

  Future<void> setInvoicePrefix(String prefix) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kInvoicePrefixKey, prefix);
  }

  // Payment Terms Days
  Future<int> getPaymentTermsDays() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kPaymentTermsDaysKey) ?? 0;
  }

  Future<void> setPaymentTermsDays(int days) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPaymentTermsDaysKey, days);
  }

  // Default Payment Mode
  Future<String> getDefaultPaymentMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kDefaultPaymentModeKey) ?? 'UPI / QR Code';
  }

  Future<void> setDefaultPaymentMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDefaultPaymentModeKey, mode);
  }

  // Low Stock Alerts
  Future<bool> getLowStockAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kLowStockAlertsKey) ?? true;
  }

  Future<void> setLowStockAlerts(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLowStockAlertsKey, value);
  }

  // Expiry Alerts
  Future<bool> getExpiryAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kExpiryAlertsKey) ?? true;
  }

  Future<void> setExpiryAlerts(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kExpiryAlertsKey, value);
  }

  // Queue Sound Chime
  Future<bool> getQueueSoundChime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kQueueSoundChimeKey) ?? true;
  }

  Future<void> setQueueSoundChime(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kQueueSoundChimeKey, value);
  }

  // Appointment Reminders
  Future<bool> getAppointmentReminders() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAppointmentRemindersKey) ?? true;
  }

  Future<void> setAppointmentReminders(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAppointmentRemindersKey, value);
  }

  // Critical Vitals Alert
  Future<bool> getCriticalVitalsAlert() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kCriticalVitalsAlertKey) ?? true;
  }

  Future<void> setCriticalVitalsAlert(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kCriticalVitalsAlertKey, value);
  }

  // Compact Density
  Future<bool> getCompactDensity() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kCompactDensityKey) ?? false;
  }

  Future<void> setCompactDensity(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kCompactDensityKey, value);
  }

  // Sound Effects
  Future<bool> getSoundEffects() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kSoundEffectsKey) ?? true;
  }

  Future<void> setSoundEffects(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSoundEffectsKey, value);
  }

  // Hardware Acceleration
  Future<bool> getHardwareAcceleration() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kHardwareAccelerationKey) ?? true;
  }

  Future<void> setHardwareAcceleration(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHardwareAccelerationKey, value);
  }
}
