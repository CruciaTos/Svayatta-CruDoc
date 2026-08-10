import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';

/// Message model for the chat conversation.
class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  const ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}

/// Service that powers the CruDoc AI Assistant chatbot.
///
/// Uses the Google Gemini API (via REST) with a comprehensive system
/// prompt containing full documentation of every app feature. Maintains
/// conversation history so the model can give context-aware follow-up
/// answers.
///
/// Security: The bot ONLY knows about app features and how-to guides.
/// It never accesses actual patient, invoice, or inventory data.
class ChatbotService {
  ChatbotService._();
  static final instance = ChatbotService._();

  // TODO: Replace with your actual Gemini API key before shipping.
  static const String _apiKey = 'YOUR_GEMINI_API_KEY';
  static const String _model = 'gemini-2.0-flash';
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  /// Conversation history sent to the model for context.
  final List<Map<String, dynamic>> _history = [];

  /// The comprehensive system prompt that teaches the model everything
  /// about the CruDoc app.
  static const String _systemPrompt = '''
You are **CruDoc Assistant**, an intelligent in-app help bot for the CruDoc medical practice management app. You help doctors understand and use every feature of the app. Answer concisely, warmly, and professionally. Use bullet points and numbered steps when explaining how-to instructions. If you don't know something, say so honestly.

## App Overview
CruDoc is a mobile-first doctor management app built with Flutter. It helps doctors manage their daily practice — patients, inventory, revenue, appointments, and profile — all in one place. The app has a beautiful blue-gradient theme with a floating bottom navigation bar.

## Navigation
The app has 5 main tabs accessible from the bottom navigation bar:
1. **Dashboard** (Home icon) — Overview of the practice
2. **Patient Records** (People icon) — Manage patients
3. **Inventory** (Box icon) — Medicine stock management
4. **Revenue** (Payments icon) — Invoices & billing
5. **Appointments** (Calendar icon) — Visit scheduling & management

## Feature Details

### 1. Dashboard
- **Revenue Snapshot**: A bar chart showing revenue for the current week or month. Toggle between "Week" and "Month" views. The current day/month is highlighted with a blue pill indicator. Tap any bar to see that day/month's revenue amount.
- **Stats Grid**: Shows key metrics like Total Patients, Total Revenue, Pending Invoices, and Low Stock count.
- **Quick Actions**: One-tap buttons to quickly Add Patient, Add Medicine, Create Invoice, or Schedule Visit.
- **Today's Visits**: Shows a list of visits scheduled for today with patient name, time, and status.
- **Low Stock Banner**: An alert banner appears at the top if any medicines are running low or expiring soon.
- **Recent Activity**: Shows recent actions like new patients added, invoices created, etc.
- **Revenue Toggle Eye**: An eye icon next to "Revenue" lets you hide/show the revenue amount for privacy.

### 2. Patient Records
- **Add Patient**: Tap the "+" button to add a new patient. Fill in name, age, gender, phone number, email, and address.
- **Patient List**: Scrollable list of all patients with search functionality. Each card shows patient name, ID, and contact info.
- **Patient Details**: Tap a patient to see their full profile, visit history, and invoices.
- **Search**: Search patients by name or phone number using the search bar at the top.
- **Edit/Delete**: Long-press or use the menu on a patient card to edit or remove a patient.

### 3. Inventory (Medicine Management)
- **Add Medicine**: Tap "+" to add a new medicine. Fill in medicine name, category, quantity, unit price, manufacturer, expiry date, and reorder level.
- **Medicine List**: Shows all medicines with stock level indicators (green = OK, yellow = low, red = critical).
- **Stock Adjustment**: Tap a medicine to adjust stock — add stock (received shipment) or reduce stock (dispensed/damaged).
- **Low Stock Alerts**: Medicines below their reorder level appear in the low-stock section with a warning badge.
- **Expiry Tracking**: Medicines expiring within 30 days are flagged with an expiry warning.
- **Search & Filter**: Search medicines by name. Filter by category or stock status.
- **Medicine Details**: Tap a medicine to see full details including stock history, expiry date, and manufacturer info.
- **Inventory Badge**: The inventory tab icon shows a red badge with the count of low-stock + expiring medicines.

### 4. Revenue & Invoices
- **Create Invoice**: Tap the "+" gradient button next to the search bar. Fill in patient name, items/services, amounts, and payment status.
- **Invoice List**: Shows all invoices in a paginated table with columns for Invoice #, Patient, Amount, Date, and Status.
- **Status Filters**: Filter invoices by All, Paid, Pending, or Overdue using the pill buttons below the search bar.
- **Search Invoices**: Search by invoice number or patient name.
- **Invoice Details**: Tap an invoice to see full details, edit, or generate a PDF.
- **PDF Generation**: Generate and share a professional PDF invoice with your practice details.
- **Revenue Metrics**: Top section shows total revenue, paid amount, pending amount, and overdue amount in colored metric cards.
- **Payment Status**: Invoices can be Paid (green), Pending (yellow), or Overdue (red).

### 5. Appointments & Visits
- **Schedule Visit**: Tap "+" or use the "Schedule Visit" quick action to create a new visit. Select patient, date, time, duration, and optionally add the visit address.
- **Visit Calendar**: A calendar view showing visits by date. Tap a date to see visits for that day.
- **Visit Details**: Tap a visit to see full details including patient info, time, location (with map), and session notes.
- **Visit Status**: Visits can be Scheduled (upcoming), Completed (done), or Cancelled.
- **Location Map**: If a visit address is provided, a Google Map preview shows the location.
- **Session Notes**: Add clinical notes to a visit after it's completed.
- **Address Autocomplete**: When entering a visit address, the app suggests addresses as you type (Google Places).

### 6. Profile
- **Doctor Profile**: Shows your name, specialty, email, phone, and authentication method.
- **Profile Card**: A premium hero card with gradient avatar ring and verified practitioner badge.
- **Account Details**: Color-coded detail cards showing Email, Phone, Auth Method, and Account ID.
- **Logout**: Tap the logout button to sign out of the app.
- **Edit Profile**: (Coming soon) Edit your name, specialty, and contact details.

## Feature Locking & Upgrade Notice
If a doctor asks about a feature that is locked for their account, inform them politely:
"🔒 **Feature Locked**
The feature is currently locked for your account. You have to upgrade your subscription plan or contact your Super Admin to unlock and use this feature! 🚀"

## Tone Guidelines
- Be friendly, professional, and concise
- Use "you" to address the doctor
- Use emojis sparingly for visual clarity
- If asked about something outside the app's scope, politely redirect to app features
- Never provide medical advice — you're an app assistant, not a medical AI
''';

  /// Resets the conversation history (e.g. when the user opens a new chat).
  void resetConversation() {
    _history.clear();
  }

  /// Sends a user message to the Gemini API and returns the bot's response.
  ///
  /// Takes optional [enabledModules] to check if requested feature is locked.
  /// Returns a friendly fallback message on any failure — never throws.
  Future<String> sendMessage(String userMessage,
      {List<String>? enabledModules}) async {
    // Check if the user is asking about a locked feature first
    final lockedMsg = _checkLockedFeature(userMessage, enabledModules);
    if (lockedMsg != null) {
      return lockedMsg;
    }

    if (_apiKey == 'YOUR_GEMINI_API_KEY') {
      return _offlineResponse(userMessage, enabledModules: enabledModules);
    }

    // Add the user message to history.
    _history.add({
      'role': 'user',
      'parts': [
        {'text': userMessage}
      ],
    });

    final url = Uri.parse('$_baseUrl/$_model:generateContent?key=$_apiKey');

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
          final content =
              candidates[0]['content'] as Map<String, dynamic>?;
          final parts = content?['parts'] as List<dynamic>?;
          if (parts != null && parts.isNotEmpty) {
            final text = parts[0]['text'] as String? ?? '';

            // Add the assistant response to history for context continuity.
            _history.add({
              'role': 'model',
              'parts': [
                {'text': text}
              ],
            });

            return text;
          }
        }
      }

      return _offlineResponse(userMessage, enabledModules: enabledModules);
    } catch (_) {
      return _offlineResponse(userMessage, enabledModules: enabledModules);
    }
  }

  List<String> _getLockedFeatureNames(List<String> enabledModules) {
    final locked = <String>[];
    final allModules = {
      'patients': 'Patient Records',
      'inventory': 'Inventory Management',
      'revenue': 'Revenue & Invoices',
      'appointments': 'Appointments & Visits',
      'home_visits': 'Appointments & Visits',
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

  /// Smart offline response engine that works without an API key.
  ///
  /// Uses keyword matching to provide helpful answers from the built-in
  /// knowledge base. This ensures the chatbot is always useful even
  /// before a Gemini API key is configured.
  String _offlineResponse(String query, {List<String>? enabledModules}) {
    final lockedMsg = _checkLockedFeature(query, enabledModules);
    if (lockedMsg != null) {
      return lockedMsg;
    }
    final q = query.toLowerCase().trim();

    // ---- Patient-related ----
    if (q.contains('patient') && (q.contains('add') || q.contains('new') || q.contains('create'))) {
      return '📋 **Adding a New Patient**\n\n'
          '1. Go to the **Patient Records** tab (2nd icon in the bottom bar)\n'
          '2. Tap the **"+"** button in the top-right corner\n'
          '3. Fill in the patient\'s details — name, age, gender, phone, email, and address\n'
          '4. Tap **Save** to add the patient\n\n'
          'The patient will appear in your records immediately! ✅';
    }
    if (q.contains('patient') && (q.contains('search') || q.contains('find'))) {
      return '🔍 **Searching Patients**\n\n'
          'Use the search bar at the top of the **Patient Records** tab. '
          'You can search by patient name or phone number. Results update as you type!';
    }
    if (q.contains('patient') && (q.contains('edit') || q.contains('update') || q.contains('delete') || q.contains('remove'))) {
      return '✏️ **Editing or Deleting a Patient**\n\n'
          '1. Go to the **Patient Records** tab\n'
          '2. Find the patient you want to modify\n'
          '3. Long-press or tap the menu icon on the patient card\n'
          '4. Choose **Edit** to update details or **Delete** to remove\n\n'
          '⚠️ Deleting a patient is permanent, so please be careful!';
    }

    // ---- Invoice-related ----
    if (q.contains('invoice') && (q.contains('create') || q.contains('add') || q.contains('new') || q.contains('make'))) {
      return '🧾 **Creating an Invoice**\n\n'
          '1. Go to the **Revenue** tab (4th icon — payments icon)\n'
          '2. Tap the blue **"+"** gradient button next to the search bar\n'
          '3. Fill in patient name, items/services, amounts, and payment status\n'
          '4. Tap **Create** to save the invoice\n\n'
          'Your invoice will appear in the list immediately! ✅';
    }
    if (q.contains('invoice') && (q.contains('pdf') || q.contains('print') || q.contains('share') || q.contains('generate'))) {
      return '📄 **Generating Invoice PDF**\n\n'
          '1. Go to the **Revenue** tab\n'
          '2. Tap on the invoice you want to export\n'
          '3. In the invoice details, tap the **PDF/Print** icon\n'
          '4. A professional PDF will be generated that you can share or print\n\n'
          'The PDF includes your practice details and a clean layout! 🖨️';
    }
    if (q.contains('invoice') && (q.contains('filter') || q.contains('paid') || q.contains('pending') || q.contains('overdue'))) {
      return '🏷️ **Filtering Invoices**\n\n'
          'Below the search bar in the Revenue tab, you\'ll see filter pills:\n'
          '• **All** — Shows every invoice\n'
          '• **Paid** (green) — Only paid invoices\n'
          '• **Pending** (yellow) — Awaiting payment\n'
          '• **Overdue** (red) — Past due date\n\n'
          'Tap any pill to filter your invoice list!';
    }

    // ---- Inventory-related ----
    if (q.contains('medicine') && (q.contains('add') || q.contains('new') || q.contains('create'))) {
      return '💊 **Adding a Medicine**\n\n'
          '1. Go to the **Inventory** tab (3rd icon — box icon)\n'
          '2. Tap the **"+"** button\n'
          '3. Fill in: medicine name, category, quantity, unit price, manufacturer, expiry date, and reorder level\n'
          '4. Tap **Save**\n\n'
          'The medicine will appear in your inventory list! ✅';
    }
    if (q.contains('stock') || q.contains('low stock') || q.contains('reorder')) {
      return '📦 **Stock Management**\n\n'
          '• **Low Stock Alerts**: Medicines below their reorder level show a warning badge\n'
          '• **Expiry Tracking**: Medicines expiring within 30 days are flagged\n'
          '• **Stock Adjustment**: Tap a medicine → adjust stock (add received / reduce dispensed)\n'
          '• **Dashboard Badge**: The red badge on the Inventory tab shows the total count of low-stock + expiring medicines\n\n'
          'You can also see the low stock banner on the Dashboard! 📊';
    }
    if (q.contains('inventory') || q.contains('medicine')) {
      return '💊 **Inventory Management**\n\n'
          'The Inventory tab (3rd icon) lets you:\n'
          '• **Add medicines** with full details (name, qty, price, expiry, etc.)\n'
          '• **Track stock levels** with color-coded indicators\n'
          '• **Adjust stock** — add received shipments or reduce dispensed amounts\n'
          '• **Monitor expiry dates** — get alerts for medicines expiring soon\n'
          '• **Search & filter** by name or category\n\n'
          'The tab badge shows how many medicines need attention! ⚠️';
    }

    // ---- Visit/Appointment-related ----
    if (q.contains('visit') || q.contains('appointment') || q.contains('schedule')) {
      return '📅 **Scheduling a Visit**\n\n'
          '1. Go to the **Appointments** tab (5th icon — calendar)\n'
          '2. Tap **"+"** to create a new visit\n'
          '3. Select the patient, pick a date & time, set the duration\n'
          '4. Optionally add the visit address (with autocomplete suggestions)\n'
          '5. Tap **Save**\n\n'
          '**Visit Statuses**: Scheduled → Completed → Cancelled\n\n'
          'You can view visits in a calendar layout and add session notes after completion! ✅';
    }

    // ---- Revenue-related ----
    if (q.contains('revenue') && (q.contains('hide') || q.contains('eye') || q.contains('privacy'))) {
      return '👁️ **Hiding Revenue**\n\n'
          'On the Dashboard, you\'ll see an eye icon (👁) next to "Revenue".\n'
          'Tap it to toggle revenue visibility:\n'
          '• **Visible**: Shows your actual revenue amount\n'
          '• **Hidden**: Shows "₹ ••••••" for privacy\n\n'
          'Great for when someone might glance at your screen! 🔒';
    }
    if (q.contains('revenue') || q.contains('earning') || q.contains('income')) {
      return '📊 **Revenue Overview**\n\n'
          'The Dashboard shows a Revenue Snapshot chart:\n'
          '• Toggle between **Week** and **Month** views\n'
          '• The current day/month is highlighted with a blue pill\n'
          '• Tap any bar to see that period\'s revenue\n'
          '• Use the eye icon to hide/show amounts for privacy\n\n'
          'The Revenue tab shows detailed metrics: Total Revenue, Paid, Pending, and Overdue amounts.';
    }

    // ---- Dashboard-related ----
    if (q.contains('dashboard') || q.contains('home')) {
      return '🏠 **Dashboard Overview**\n\n'
          'Your Dashboard (1st tab) gives you a quick overview:\n'
          '• **Revenue Chart** — Weekly/Monthly bar chart of earnings\n'
          '• **Stats Grid** — Key numbers (patients, revenue, pending, low stock)\n'
          '• **Quick Actions** — One-tap buttons for common tasks\n'
          '• **Today\'s Visits** — Scheduled appointments for today\n'
          '• **Low Stock Banner** — Alert for medicines running low\n'
          '• **Recent Activity** — Latest actions in your practice\n\n'
          'Everything you need at a glance! 👀';
    }

    // ---- Profile-related ----
    if (q.contains('profile') || q.contains('logout') || q.contains('sign out') || q.contains('account')) {
      return '👤 **Profile & Account**\n\n'
          '• Tap your profile avatar on the Dashboard top bar\n'
          '• View your name, specialty, email, phone, and auth method\n'
          '• Your profile has a premium card with a gradient avatar ring\n'
          '• Tap **Logout** to sign out of the app\n\n'
          'Profile editing will be available in a future update! 🔜';
    }

    // ---- Navigation help ----
    if (q.contains('navigate') || q.contains('tab') || q.contains('where') || q.contains('find') || q.contains('go to')) {
      return '🧭 **App Navigation**\n\n'
          'Use the bottom navigation bar with 5 tabs:\n'
          '1. 🏠 **Dashboard** — Home overview\n'
          '2. 👥 **Patients** — Patient records\n'
          '3. 💊 **Inventory** — Medicine stock\n'
          '4. 💰 **Revenue** — Invoices & billing\n'
          '5. 📅 **Appointments** — Visit scheduling\n\n'
          'Tap any icon to switch tabs. The active tab glows blue!';
    }

    // ---- General greeting / fallback ----
    if (q.contains('hello') || q.contains('hi') || q.contains('hey') || q.contains('help')) {
      return '👋 **Hello, Doctor!**\n\n'
          'I\'m your CruDoc Assistant. I can help you with:\n\n'
          '• 📋 **Patient Records** — Adding, searching, editing patients\n'
          '• 💊 **Inventory** — Medicine stock, low stock alerts, expiry tracking\n'
          '• 🧾 **Invoices** — Creating invoices, PDF generation, payment status\n'
          '• 📅 **Appointments** — Scheduling visits, calendar, session notes\n'
          '• 📊 **Revenue** — Revenue charts, hiding amounts, metrics\n'
          '• 👤 **Profile** — Account settings, logout\n\n'
          'Just ask me anything about the app! 😊';
    }

    // ---- Catch-all ----
    return '🤔 I\'m not sure about that specific topic, but I can help you with:\n\n'
        '• Adding patients, medicines, invoices, or visits\n'
        '• Navigating the app\n'
        '• Understanding dashboard metrics\n'
        '• Managing inventory & stock alerts\n'
        '• Generating invoice PDFs\n\n'
        'Try asking something like "How do I add a patient?" or "How do I create an invoice?" 💡';
  }
}
