import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';

/// Message model for the chat conversation.
class ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool isError;

  const ChatMessage({
    String? id,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isError = false,
  }) : id = id ?? '';
}

/// Service that powers the CruDoc AI Assistant chatbot.
///
/// Uses the Google Gemini API (via server-side Cloud Functions) with a comprehensive system
/// prompt containing clinical knowledge and full documentation of every app feature.
/// Maintains conversation history so the model can give context-aware follow-up answers.
class ChatbotService {
  ChatbotService._();
  static final instance = ChatbotService._();

  static const String _model = 'gemini-2.0-flash';
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  /// Resolves the optional Gemini API key from explicit developer environment override.
  /// NOTE: Firebase client key is NEVER used as a fallback to prevent secret leakage.
  String get _resolvedApiKey {
    const envKey = String.fromEnvironment('GEMINI_API_KEY');
    return envKey;
  }

  /// Conversation history sent to the model for context.
  final List<Map<String, dynamic>> _history = [];

  /// The comprehensive system prompt that empowers the assistant to answer
  /// any medical, clinical, practice management, or general inquiry about CruDoc.
  static const String _systemPrompt = '''
You are **CruDoc AI Assistant**, an intelligent, highly knowledgeable, and versatile clinical & practice companion for doctors, healthcare practitioners, and clinic administrators using the CruDoc application.

## Your Mission:
You must answer ANY question asked regarding the CruDoc application, clinical workflows, patient management, medical science, pharmacology, or app navigation with complete accuracy, clarity, and helpfulness.

## Comprehensive CruDoc App Knowledge Base:

### 1. Bottom Navigation Bar (6 Tabs + Center AI Assistant)
1. 🏠 **Tab 0 — Dashboard**:
   - **Revenue Snapshot**: Interactive bar chart comparing revenue over Week or Month. Current period highlighted with blue pill.
   - **Privacy Eye (👁)**: Toggle next to Revenue to hide amounts ("₹ ••••••") for screen privacy.
   - **Live Stats Grid**: Total Patients, Monthly Revenue, Pending Payments, and Low Stock count.
   - **Quick Actions**: One-tap shortcuts for "Add Patient", "Create Invoice", "Add Medicine", and "Schedule Visit".
   - **Today's Visits**: Real-time list of appointments scheduled for today with patient status.
   - **Low Stock Banner**: Amber/Red alert card if any medicines are below reorder threshold or expiring soon.
   - **Recent Activity**: Stream of latest clinical events, visits, and billing updates.

2. 👥 **Tab 1 — Patient Records**:
   - **Add Patient**: Tap "+" in top right. Enter Full Name, Age, Gender, Phone, Email, Address, and Medical History notes.
   - **Search & Filter**: Real-time search bar by patient name or phone number.
   - **Patient Details View**: Complete demographic data, vital signs (BP, Pulse, Temp), past consultation history, and attached prescription records.
   - **Quick Contact**: One-tap WhatsApp chat button and direct phone dialer.
   - **Edit / Delete**: Long-press or menu icon on patient card. Deletions require confirmation.

3. 💊 **Tab 2 — Inventory & Pharmacy**:
   - **Add Medicine**: Tap "+" button. Enter Medicine Name, Category (Tablet, Syrup, Injection, Ointment, etc.), Quantity, Unit Price, Manufacturer, Expiry Date, and Reorder Threshold.
   - **Stock Tracking**: Color-coded stock badges (Green: Healthy, Amber: Low Stock, Red: Out of Stock).
   - **Adjust Stock**: Tap any medicine → Adjust Stock (add incoming shipments or deduct dispensed quantities).
   - **Expiry Alerts**: Flags medicines expiring within 30 days.
   - **Search & Categories**: Instant filter by drug name or pharmaceutical category.

4. 💰 **Tab 3 — Revenue & Billing**:
   - **Create Invoice**: Tap blue "+" button. Select patient, add line items/services/medicines with quantity and unit price, apply tax/discount, calculate total.
   - **Payment Status Lifecycle**: Paid (Green), Pending (Yellow), Overdue (Red). Tap invoice to update status.
   - **Filtering**: Quick status filter pills: "All", "Paid", "Pending", "Overdue".
   - **PDF Invoice Generation**: Tap PDF/Print icon to preview, download, print, or share professional branded invoices via WhatsApp/Email.

5. 📅 **Tab 4 — Appointments & Visits**:
   - **Schedule Visit**: Tap "+" button. Choose Visit Type (In-Clinic Consultation vs Home Visit), select patient, pick date & time, set duration.
   - **Home Visit Addresses**: Location field with Google Places autocomplete suggestions and map routing.
   - **Visit Lifecycle**: Scheduled → Completed → Cancelled.
   - **Consultation Session Notes**: Add clinical observation notes, symptoms, and diagnoses directly after completing a visit.
   - **Automated WhatsApp Notifications**: Sends automated appointment confirmations and 10-minute reminders to patients.

6. 📢 **Tab 5 — Patient Campaigns & Outreach**:
   - **Create Campaign**: Tap "Create Campaign" or "+".
   - **Channels**: Broadcast via **Email** or **WhatsApp**.
   - **Audience Segmentation**: Target "All Patients", "Chronic Patients", "Inactive Patients", or "Custom Selected Patients".
   - **Templates & Personalization**: Pre-built clinical templates (Health checkup, vaccination drive, clinic announcement) with dynamic tokens (`{{patient_name}}`, `{{clinic_name}}`).
   - **Scheduling**: Send immediately or schedule for a specific date and time.
   - **Delivery Tracking**: Monitor dispatched logs, success rates, and patient engagement.

7. 🎙️ **AI Voice Scribe (Ambient Clinical Dictation)**:
   - Available during patient consultations via the floating mic / scribe action.
   - **Consent Verification**: Doctor confirms patient consent before recording.
   - **Real-Time Recording**: Records consultation audio with live waveform feedback.
   - **Gemini AI Extraction**: Automatically transcribes audio into structured clinical sections: Chief Complaint, Symptoms, Suggested Diagnoses, Medicines (with dosage and instructions), Clinical Advice, Follow-up Date, and Vitals.
   - **Draft Review**: Doctor reviews, edits, and confirms note before saving to the patient record.

8. 🤖 **AI Assistant & Voice Dictation**:
   - Tap the glowing blue center AI button on the navigation bar.
   - **Voice Input**: Tap the Mic icon in the input bar → speak naturally → real-time amplitude waveform → instant Gemini speech-to-text.
   - **Markdown Bubbles**: Rich headers, bullet points, numbered steps, bold text, timestamps, and one-tap copy to clipboard.
   - **Dynamic Bar**: Seamlessly switches between Mic (when empty) and Send (when typing).
   - **New Chat**: Tap refresh icon to reset conversation context.

9. 👤 **Doctor Profile, Multi-Device & Security**:
   - Tap avatar in top-left to view doctor profile, registration/license number, specialty, and contact details.
   - **Multi-Device Session Security**: Real-time concurrent login tracking, active sessions display, and remote session termination.
   - **Multi-Tenant Isolation**: Doctor data is strictly isolated (`doctorId == currentUserId`) and sensitive fields are encrypted.

10. 🔒 **Subscription & Feature Locks**:
    - **Base Modules** (Always active even if expired): Dashboard, Patients, Appointments, Inventory.
    - **Add-on Modules**: Revenue & Invoices, AI Voice Scribe, Patient Campaigns, Omnichannel Messaging, AI Agentic Calling, Multi-Device Access.
    - If a feature is locked, doctors can request plan upgrades directly from their Super Admin.

## Disambiguation & Specific Routing Rules:
- "schedule a campaign" or "create a broadcast" → Guide to **Campaigns tab** (Tab 6).
- "schedule a visit", "book an appointment", "schedule consultation" → Guide to **Appointments tab** (Tab 5).
- "hide revenue", "revenue privacy", "eye icon" → Guide to Dashboard eye icon toggle.
- "record voice note", "ambient scribe", "transcribe patient" → Guide to AI Voice Scribe.

## Tone & Formatting Guidelines:
- Answer warmly, accurately, and professionally.
- Always provide structured, easy-to-follow steps using Markdown: headers (`###`), bullet points (`•`), numbered lists, and bold text.
- If asked about clinical topics (dosages, pharmacology, differential diagnosis), provide accurate medical knowledge with appropriate clinical reminders.
''';

  /// Resets the conversation history.
  void resetConversation() {
    _history.clear();
  }

  /// Sends a user message to the Gemini API and returns the bot's response.
  Future<String> sendMessage(String userMessage,
      {List<String>? enabledModules}) async {
    // Check if the user is asking about a locked feature first
    final lockedMsg = _checkLockedFeature(userMessage, enabledModules);
    if (lockedMsg != null) {
      return lockedMsg;
    }

    _history.add({
      'role': 'user',
      'parts': [
        {'text': userMessage}
      ],
    });

    // 1. Production Secure Route: Firebase Cloud Function (Server-Side Secret Management)
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('chatWithAssistant');
      final result = await callable.call({
        'message': userMessage,
        'history': _history,
        'enabledModules': enabledModules,
      }).timeout(const Duration(seconds: 12));

      final data = result.data;
      if (data is Map && data['reply'] is String) {
        final reply = (data['reply'] as String).trim();
        if (reply.isNotEmpty) {
          _history.add({
            'role': 'model',
            'parts': [
              {'text': reply}
            ],
          });
          return reply;
        }
      }
    } catch (e) {
      debugPrint('[ChatbotService] Cloud Function route skipped/failed: $e');
    }

    // 2. Development Direct REST fallback (only if explicit developer key provided via --dart-define)
    final apiKey = _resolvedApiKey;
    if (apiKey.isNotEmpty) {
      final url = Uri.parse('$_baseUrl/$_model:generateContent?key=$apiKey');
      final String activePrompt = enabledModules == null
          ? _systemPrompt
          : '$_systemPrompt\n\n'
              '## CURRENT DOCTOR LOCKED FEATURES\n'
              'The following features are currently LOCKED for this doctor: '
              '${_getLockedFeatureNames(enabledModules).join(', ')}.\n'
              'If the doctor asks how to use or access any of these locked features, explicitly inform them: '
              '"You have to upgrade your subscription plan or contact your Super Admin to unlock and use this feature."';

      try {
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'system_instruction': {
              'parts': [
                {'text': activePrompt}
              ]
            },
            'contents': _history,
            'generationConfig': {
              'temperature': 0.7,
              'topP': 0.95,
              'topK': 40,
              'maxOutputTokens': 1024,
            },
          }),
        );

        if (response.statusCode == 200) {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          final candidates = body['candidates'] as List<dynamic>?;
          if (candidates != null && candidates.isNotEmpty) {
            final content = candidates[0]['content'] as Map<String, dynamic>?;
            final parts = content?['parts'] as List<dynamic>?;
            if (parts != null && parts.isNotEmpty) {
              final text = parts[0]['text'] as String? ?? '';

              _history.add({
                'role': 'model',
                'parts': [
                  {'text': text}
                ],
              });

              return text;
            }
          }
        } else {
          debugPrint('[ChatbotService] Gemini HTTP ${response.statusCode}: ${response.body}');
        }
      } catch (e) {
        debugPrint('[ChatbotService] Direct REST error: $e');
      }
    }

    // 3. Clinical & App Knowledge Base Offline Fallback
    return _offlineResponse(userMessage, enabledModules: enabledModules);
  }

  List<String> _getLockedFeatureNames(List<String> enabledModules) {
    final locked = <String>[];
    final allModules = {
      'patients': 'Patient Records',
      'inventory': 'Inventory Management',
      'revenue': 'Revenue & Invoices',
      'appointments': 'Appointments & Visits',
      'home_visits': 'Appointments & Visits',
      'campaigns': 'Patient Campaigns',
      'ai_assistant': 'AI Assistant',
      'ai_agentic_calling': 'AI Agentic Calling',
      'omnichannel_messaging': 'Omnichannel Messaging',
    };

    allModules.forEach((key, title) {
      if (!DoctorFeatureGuard.isEnabled(enabledModules, key) &&
          !locked.contains(title)) {
        locked.add(title);
      }
    });

    return locked;
  }

  String? _checkLockedFeature(String query, List<String>? enabledModules) {
    if (enabledModules == null) return null;

    final q = query.toLowerCase().trim();

    // Patient Records
    if (q.contains('patient') &&
        !DoctorFeatureGuard.isEnabled(enabledModules, 'patients')) {
      return _lockedResponse('Patient Records');
    }

    // Inventory Management
    if ((q.contains('inventory') ||
            q.contains('medicine') ||
            q.contains('stock') ||
            q.contains('reorder')) &&
        !DoctorFeatureGuard.isEnabled(enabledModules, 'inventory')) {
      return _lockedResponse('Inventory Management');
    }

    // Revenue & Invoices
    if ((q.contains('invoice') ||
            q.contains('revenue') ||
            q.contains('billing') ||
            q.contains('payment')) &&
        !DoctorFeatureGuard.isEnabled(enabledModules, 'revenue')) {
      return _lockedResponse('Revenue & Invoices');
    }

    // Patient Campaigns
    if ((q.contains('campaign') ||
            q.contains('broadcast') ||
            q.contains('newsletter') ||
            q.contains('outreach')) &&
        !DoctorFeatureGuard.isEnabled(enabledModules, 'campaigns') &&
        !DoctorFeatureGuard.isEnabled(enabledModules, 'omnichannel_messaging')) {
      return _lockedResponse('Patient Campaigns');
    }

    // Appointments & Visits
    if ((q.contains('visit') ||
            q.contains('appointment') ||
            q.contains('schedule') ||
            q.contains('calendar')) &&
        !DoctorFeatureGuard.isEnabled(enabledModules, 'appointments') &&
        !DoctorFeatureGuard.isEnabled(enabledModules, 'home_visits')) {
      return _lockedResponse('Appointments & Visits');
    }

    // AI Agentic Calling
    if ((q.contains('calling') || q.contains('agentic') || q.contains('call')) &&
        !DoctorFeatureGuard.isEnabled(enabledModules, 'ai_agentic_calling')) {
      return _lockedResponse('AI Agentic Calling');
    }

    // Omnichannel Messaging
    if ((q.contains('messaging') || q.contains('omnichannel')) &&
        !DoctorFeatureGuard.isEnabled(enabledModules, 'omnichannel_messaging')) {
      return _lockedResponse('Omnichannel Messaging');
    }

    return null;
  }

  String _lockedResponse(String featureTitle) {
    return '🔒 **Feature Locked**\n\n'
        'The **$featureTitle** feature is currently locked for your account.\n\n'
        'You have to upgrade your subscription plan or contact your Super Admin to unlock and use this feature! 🚀';
  }

  /// Smart offline response engine that works even without network/API keys.
  ///
  /// Contains exhaustive documentation for every screen, tab, button, and workflow.
  String _offlineResponse(String query, {List<String>? enabledModules}) {
    final lockedMsg = _checkLockedFeature(query, enabledModules);
    if (lockedMsg != null) {
      return lockedMsg;
    }
    final q = query.toLowerCase().trim();

    // 1. AI Voice Scribe & Ambient Consultation
    if (q.contains('scribe') ||
        q.contains('ambient') ||
        (q.contains('voice') && (q.contains('record') || q.contains('consultation') || q.contains('note')))) {
      return '🎙️ **AI Voice Scribe (Consultation Dictation)**\n\n'
          'The AI Voice Scribe ambiently transcribes and structures your doctor-patient consultations:\n\n'
          '1. **Start Recording**: Open the patient consultation and tap the **Voice Scribe** mic button.\n'
          '2. **Patient Consent**: Check the consent confirmation checkbox.\n'
          '3. **Speak Naturally**: Conduct your patient consultation normally while the live waveform tracks speech.\n'
          '4. **Stop & Extract**: Tap **Stop Recording**. Gemini AI structures the audio into:\n'
          '   • **Chief Complaint & Symptoms**\n'
          '   • **Suggested Diagnoses**\n'
          '   • **Prescription Medicines** (with dosage and instructions)\n'
          '   • **Clinical Advice & Follow-Up Date**\n'
          '   • **Vitals** (BP, Pulse, Temp)\n'
          '5. **Review & Save**: Edit any fields as needed, then tap **Confirm & Save** to attach to the patient record! ✅';
    }

    // 2. Patient Campaigns & Broadcast Messaging
    if (q.contains('campaign') ||
        q.contains('broadcast') ||
        q.contains('newsletter') ||
        q.contains('outreach')) {
      return '📢 **Scheduling & Running a Campaign**\n\n'
          'The Campaigns tab (6th icon on the navigation bar) lets you run patient engagement broadcasts:\n\n'
          '1. Go to the **Campaigns** tab\n'
          '2. Tap **"Create Campaign"** or the blue **"+"** button\n'
          '3. Set campaign title and select channel (**Email** or **WhatsApp**)\n'
          '4. Choose target **Audience** (All Patients, Chronic Patients, Inactive Patients, or Custom Selection)\n'
          '5. Pick a medical template or write your message with tokens (`{{patient_name}}`, `{{clinic_name}}`)\n'
          '6. Select **Send Now** or **Schedule** for a future date/time\n'
          '7. Tap **Launch Campaign**\n\n'
          'You can monitor real-time delivery logs, open rates, and engagement from the Campaigns dashboard! 📊';
    }

    // 3. Appointments & Visits (Disambiguated from campaigns)
    if (q.contains('visit') ||
        q.contains('appointment') ||
        (q.contains('schedule') && !q.contains('campaign') && !q.contains('broadcast')) ||
        q.contains('calendar')) {
      return '📅 **Scheduling & Managing Appointments**\n\n'
          '1. Go to the **Appointments** tab (5th icon — calendar)\n'
          '2. Tap the **"+"** button to create a new visit\n'
          '3. Select **In-Clinic** or **Home Visit**\n'
          '4. Choose the patient, pick date & time, set duration\n'
          '5. For home visits, enter the patient address (with Google Places autocomplete)\n'
          '6. Tap **Save**\n\n'
          '• **Automated Alerts**: Sends automated WhatsApp confirmations and reminders to patients.\n'
          '• **Status Updates**: Scheduled → Completed → Cancelled.\n'
          '• **Session Notes**: Add clinical observation notes after completing the visit! ✅';
    }

    // 4. Patient Records (Add, Search, Edit, Vitals, History, WhatsApp/Call)
    if (q.contains('patient') && (q.contains('add') || q.contains('new') || q.contains('create') || q.contains('register'))) {
      return '📋 **Adding a New Patient**\n\n'
          '1. Go to the **Patient Records** tab (2nd icon in the bottom bar)\n'
          '2. Tap the **"+"** button in the top-right corner\n'
          '3. Fill in details: Name, Age, Gender, Phone, Email, Address, and Medical History\n'
          '4. Tap **Save**\n\n'
          'The patient is immediately added to your searchable patient registry! ✅';
    }
    if (q.contains('patient') && (q.contains('search') || q.contains('find') || q.contains('filter'))) {
      return '🔍 **Searching Patients**\n\n'
          '• Use the search bar at the top of the **Patient Records** tab.\n'
          '• Search in real time by **Patient Name** or **Phone Number**.\n'
          '• Tap any patient to open their comprehensive medical profile.';
    }
    if (q.contains('patient') && (q.contains('vital') || q.contains('bp') || q.contains('history') || q.contains('detail') || q.contains('record'))) {
      return '🩺 **Patient Medical Details & History**\n\n'
          'Tap any patient in **Patient Records** to access:\n'
          '• **Demographics**: Name, Age, Gender, Contact, Address\n'
          '• **Vitals Tracking**: Blood Pressure (BP), Pulse Rate, Temperature\n'
          '• **Medical History**: Past conditions, allergies, and diagnostic notes\n'
          '• **Past Consultations**: List of completed visits and attached prescriptions\n'
          '• **Quick Actions**: One-tap WhatsApp chat and direct phone calling! 📞';
    }
    if (q.contains('patient') && (q.contains('edit') || q.contains('update') || q.contains('delete') || q.contains('remove'))) {
      return '✏️ **Editing or Deleting Patients**\n\n'
          '1. Open the **Patient Records** tab\n'
          '2. Locate the patient card\n'
          '3. Tap the menu options or long-press the card\n'
          '4. Choose **Edit** to modify details or **Delete** to remove the record\n\n'
          '⚠️ Deletion is permanent to protect clinical data integrity.';
    }

    // 5. Invoices, Revenue & Billing
    if (q.contains('invoice') && (q.contains('create') || q.contains('add') || q.contains('new') || q.contains('bill') || q.contains('make'))) {
      return '🧾 **Creating an Invoice**\n\n'
          '1. Go to the **Revenue** tab (4th icon — currency icon)\n'
          '2. Tap the blue **"+"** gradient button next to the search bar\n'
          '3. Select the patient, add billable items/services with quantity and unit price\n'
          '4. Apply discounts or taxes if needed, and set payment status (**Paid**, **Pending**, **Overdue**)\n'
          '5. Tap **Create**\n\n'
          'The invoice is instantly saved and available for PDF printing and sharing! 📄';
    }
    if (q.contains('invoice') && (q.contains('pdf') || q.contains('print') || q.contains('share') || q.contains('download') || q.contains('receipt'))) {
      return '📄 **Exporting & Sharing Invoice PDFs**\n\n'
          '1. Go to the **Revenue** tab\n'
          '2. Tap on the desired invoice from the list\n'
          '3. Tap the **PDF / Print** icon in the details view\n'
          '4. Preview the clean branded invoice receipt\n'
          '5. Tap **Share** to send directly via WhatsApp/Email or **Print** to a thermal/A4 printer! 🖨️';
    }
    if (q.contains('revenue') && (q.contains('hide') || q.contains('eye') || q.contains('privacy') || q.contains('show'))) {
      return '👁️ **Hiding Revenue on Dashboard**\n\n'
          'On the Dashboard, find the eye icon (👁) next to the "Revenue" title:\n'
          '• **Tap Eye Icon**: Toggles between visible amount (e.g. "₹ 45,200") and private mode ("₹ ••••••")\n'
          '• Perfect for keeping financial figures confidential in front of patients! 🔒';
    }
    if (q.contains('revenue') || q.contains('earning') || q.contains('income') || q.contains('billing')) {
      return '📊 **Revenue & Invoicing Overview**\n\n'
          'The **Revenue** tab and **Dashboard Chart** provide full financial visibility:\n'
          '• **Weekly / Monthly Analytics**: Compare earnings over time\n'
          '• **Payment Statuses**: Filter by **Paid** (green), **Pending** (yellow), and **Overdue** (red)\n'
          '• **Summary Metrics**: Total collected revenue, pending dues, and overdue counts.';
    }

    // 6. Inventory & Medicine Management
    if (q.contains('medicine') && (q.contains('add') || q.contains('new') || q.contains('create'))) {
      return '💊 **Adding a Medicine to Inventory**\n\n'
          '1. Go to the **Inventory** tab (3rd icon — box icon)\n'
          '2. Tap the **"+"** button\n'
          '3. Enter: Medicine Name, Category, Stock Quantity, Unit Price, Manufacturer, Expiry Date, and Reorder Level\n'
          '4. Tap **Save**\n\n'
          'The medicine is immediately tracked in your pharmacy stock! ✅';
    }
    if (q.contains('stock') || q.contains('low stock') || q.contains('reorder') || q.contains('expiry') || q.contains('inventory')) {
      return '📦 **Inventory & Stock Management**\n\n'
          'The Inventory tab (3rd icon) provides end-to-end stock control:\n'
          '• **Low Stock Warnings**: Medicines below their reorder threshold display an amber warning\n'
          '• **Expiry Tracking**: Medicines expiring within 30 days are flagged with red alerts\n'
          '• **Adjust Stock**: Tap any medicine → **Adjust Stock** to add incoming shipments or deduct dispensed amounts\n'
          '• **Dashboard Alert Banner**: Real-time summary banner on Dashboard showing total low-stock items! ⚠️';
    }

    // 7. Dashboard Overview
    if (q.contains('dashboard') || q.contains('home')) {
      return '🏠 **Dashboard Overview**\n\n'
          'Your home command center (1st tab):\n'
          '• **Revenue Snapshot Chart**: Weekly and Monthly interactive earnings graph\n'
          '• **Privacy Eye (👁)**: Instant hide/show for revenue amounts\n'
          '• **Stats Grid**: Live counts for Patients, Revenue, Pending Payments, and Low Stock\n'
          '• **Quick Actions**: One-tap shortcuts for adding patients, creating invoices, medicines, or visits\n'
          '• **Today\'s Appointments**: Active list of today\'s scheduled visits\n'
          '• **Low Stock Banner**: Pharmacy alert for items needing reorder.';
    }

    // 8. Doctor Profile, Account & Security
    if (q.contains('profile') || q.contains('account') || q.contains('logout') || q.contains('sign out') || q.contains('device') || q.contains('session')) {
      return '👤 **Doctor Profile & Multi-Device Security**\n\n'
          '• **View Profile**: Tap your avatar on the Dashboard top bar\n'
          '• **Details**: View Doctor Name, Specialty, Clinic Name, Email, Phone, and License Number\n'
          '• **Multi-Device Sessions**: CruDoc monitors active devices for security to prevent unauthorized access\n'
          '• **Logout**: Tap **Logout** at the bottom of the profile sheet to safely sign out.';
    }

    // 9. Subscription & Unlocking Features
    if (q.contains('upgrade') || q.contains('subscription') || q.contains('plan') || q.contains('unlock') || q.contains('module')) {
      return '⭐ **CruDoc Subscriptions & Module Upgrades**\n\n'
          '• **Core Base Modules** (Always active): Dashboard, Patients, Appointments, Inventory\n'
          '• **Add-On Features**: Revenue & Invoices, AI Voice Scribe, Patient Campaigns, AI Calling, Multi-Device\n'
          '• **How to Unlock**: If a module is locked, contact your Super Admin or tap the upgrade prompt to activate the module for your account! 🚀';
    }

    // 10. Voice Input & Chatbot Features
    if (q.contains('mic') || q.contains('voice input') || q.contains('chatbot') || q.contains('assistant')) {
      return '🤖 **CruDoc AI Assistant & Voice Dictation**\n\n'
          '• **Voice Dictation**: Tap the blue **Mic icon** in the chat input bar to speak your queries naturally with live waveform feedback\n'
          '• **Dynamic Input**: The button automatically morphs between Mic (when empty) and Send (when typing)\n'
          '• **Markdown Formatting**: Clinical responses include clear headers, bullet points, and code snippets\n'
          '• **Copy to Clipboard**: Tap the copy icon on any response to copy it\n'
          '• **New Conversation**: Tap the refresh icon at the top to reset conversation history.';
    }

    // 11. Navigation Guide
    if (q.contains('navigate') || q.contains('tab') || q.contains('where') || q.contains('find') || q.contains('go to') || q.contains('menu')) {
      return '🧭 **CruDoc App Navigation Guide**\n\n'
          'CruDoc features 6 primary bottom navigation tabs + center AI Assistant:\n'
          '1. 🏠 **Dashboard** — Practice overview, revenue chart, and today\'s visits\n'
          '2. 👥 **Patients** — Patient records, medical history, and vitals\n'
          '3. 💊 **Inventory** — Medicine stock, low-stock warnings, and expiry alerts\n'
          '4. 💰 **Revenue** — Invoicing, payment statuses, and PDF generation\n'
          '5. 📅 **Appointments** — In-clinic and home visit scheduling\n'
          '6. 📢 **Campaigns** — Email & WhatsApp broadcast outreach\n'
          '🤖 **AI Assistant** — Glowing blue button for instant clinical & app help!';
    }

    // 12. General Greetings
    if (q.contains('hello') || q.contains('hi') || q.contains('hey') || q.contains('help')) {
      return '👋 **Hello, Doctor!**\n\n'
          'I\'m your CruDoc Clinical & Practice Assistant. I can answer any question about:\n\n'
          '• 📋 **Patient Management** — Adding patients, vitals, medical history\n'
          '• 🎙️ **AI Voice Scribe** — Ambient consultation recording & structured notes\n'
          '• 💊 **Inventory & Pharmacy** — Adding medicines, low-stock alerts, expiry tracking\n'
          '• 🧾 **Invoices & Billing** — Creating invoices, PDF receipts, tracking payments\n'
          '• 📅 **Appointments** — Scheduling in-clinic/home visits, WhatsApp reminders\n'
          '• 📢 **Patient Campaigns** — Email & WhatsApp broadcast outreach\n'
          '• 🩺 **Clinical Questions** — Pharmacology, dosages, differential diagnoses\n\n'
          'Ask me anything or tap the mic to speak! 😊';
    }

    // 13. Smart Catch-All with Relevant App Suggestions
    return '💡 **CruDoc Assistant Knowledge Index**\n\n'
        'I can assist you with any feature in CruDoc or clinical inquiry. Here are common topics you can ask:\n\n'
        '• *"How do I add a new patient?"*\n'
        '• *"How does AI Voice Scribe work?"*\n'
        '• *"How to create and share an invoice PDF?"*\n'
        '• *"How to schedule a patient campaign?"*\n'
        '• *"How to check low stock medicines?"*\n'
        '• *"How to schedule an appointment or home visit?"*\n'
        '• *"How to hide revenue on dashboard?"*\n\n'
        'Feel free to ask your question in detail or tap the microphone to dictate! 🎙️';
  }
}
