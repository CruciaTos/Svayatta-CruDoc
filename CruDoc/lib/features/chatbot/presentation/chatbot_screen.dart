import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';
import 'package:doctor_management_app/features/chatbot/services/chatbot_service.dart';
import 'package:doctor_management_app/features/chatbot/widgets/chat_bubble.dart';
import 'package:doctor_management_app/features/chatbot/widgets/voice_input_modal.dart';

/// Full-screen or compact bottom-sheet AI chatbot screen where doctors can ask
/// questions about the CruDoc app's features in a small area overlay.
class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  /// Static helper to launch the chatbot as a compact bottom sheet.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const ChatbotScreen(),
    );
  }

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen>
    with SingleTickerProviderStateMixin {
  final _chatService = ChatbotService.instance;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  final List<ChatMessage> _messages = [];
  bool _isTyping = false;

  // Entrance animation
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  /// Quick suggestion chips shown when the chat is empty.
  static const _suggestions = [
    'How do I add a patient?',
    'How to create an invoice?',
    'How to manage inventory?',
    'How to schedule a visit?',
    'How to hide revenue?',
    'Tell me about the dashboard',
  ];

  @override
  void initState() {
    super.initState();
    _chatService.resetConversation();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();

    // Welcome message
    _messages.add(ChatMessage(
      text: '👋 **Hello, Doctor!**\n\n'
          'I\'m your CruDoc Assistant. Ask me anything about the app! 😊',
      isUser: false,
      timestamp: DateTime.now(),
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage(String text, [List<String>? enabledModules]) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    _controller.clear();

    setState(() {
      _messages.add(ChatMessage(
        text: trimmed,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _isTyping = true;
    });
    _scrollToBottom();

    final response =
        await _chatService.sendMessage(trimmed, enabledModules: enabledModules);

    if (!mounted) return;

    setState(() {
      _isTyping = false;
      _messages.add(ChatMessage(
        text: response,
        isUser: false,
        timestamp: DateTime.now(),
      ));
    });
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final screenHeight = mediaQuery.size.height;

    // Small area modal height (62% height normally, expands slightly when keyboard is up)
    final double sheetHeight = bottomInset > 0
        ? screenHeight * 0.85
        : screenHeight * 0.62;

    return StreamBuilder<List<String>>(
      stream: DoctorFeatureGuard.watchEnabledModules(),
      builder: (context, snapshot) {
        final enabledModules =
            snapshot.data ?? DoctorFeatureGuard.defaultModules;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: sheetHeight,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFEFF6FF), Color(0xFFF8FAFC)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(
              color: const Color(0xFF1E78FF).withValues(alpha: 0.2),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 24,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  // Drag handle indicator
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // ---- App Bar ----
                  _buildAppBar(),
                  // ---- Chat Body ----
                  Expanded(
                    child: _messages.length <= 1 && !_isTyping
                        ? _buildWelcomeView(enabledModules)
                        : _buildChatList(),
                  ),
                  // ---- Input Area ----
                  _buildInputArea(bottomInset, enabledModules),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 16, 8),
      child: Row(
        children: [
          // Close button
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Bot avatar
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E78FF), Color(0xFF00C6FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1E78FF).withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.smart_toy_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          // Title & subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CruDoc Assistant',
                  style: TextStyle(
                    fontFamily: AppColors.headingFontFamily,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFF22C55E),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _isTyping ? 'Typing...' : 'Online Assistant',
                      style: TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        fontSize: 12,
                        color: _isTyping
                            ? AppColors.chartBarLight
                            : AppColors.textSecondary,
                        fontWeight:
                            _isTyping ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Clear chat button
          if (_messages.length > 1)
            IconButton(
              onPressed: () {
                setState(() {
                  _chatService.resetConversation();
                  _messages.clear();
                  _messages.add(ChatMessage(
                    text: '👋 **Hello, Doctor!**\n\n'
                        'I\'m your CruDoc Assistant. Ask me anything about the app! 😊',
                    isUser: false,
                    timestamp: DateTime.now(),
                  ));
                });
              },
              icon: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.refresh_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Welcome view with bot intro and suggestion chips — shown when
  /// only the welcome message exists.
  Widget _buildWelcomeView(List<String> enabledModules) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const SizedBox(height: 12),
          // Welcome message bubble
          ChatBubble(
            text: _messages.first.text,
            isUser: false,
            timestamp: _messages.first.timestamp,
          ),
          const SizedBox(height: 20),
          // Quick suggestions header
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.chartBarLight.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lightbulb_rounded,
                      size: 15,
                      color: Colors.amber.shade700,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Quick Questions',
                      style: TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.chartBarLight,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Suggestion chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _suggestions.map((suggestion) {
              bool isLocked = false;
              final lower = suggestion.toLowerCase();
              if (lower.contains('patient') &&
                  !DoctorFeatureGuard.isEnabled(enabledModules, 'patients')) {
                isLocked = true;
              } else if ((lower.contains('invoice') || lower.contains('revenue')) &&
                  !DoctorFeatureGuard.isEnabled(enabledModules, 'revenue')) {
                isLocked = true;
              } else if (lower.contains('inventory') &&
                  !DoctorFeatureGuard.isEnabled(enabledModules, 'inventory')) {
                isLocked = true;
              } else if (lower.contains('visit') &&
                  !DoctorFeatureGuard.isEnabled(enabledModules, 'appointments')) {
                isLocked = true;
              }

              return GestureDetector(
                onTap: () => _sendMessage(suggestion, enabledModules),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isLocked
                          ? Colors.amber.shade400
                          : AppColors.chartBarLight.withValues(alpha: 0.25),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isLocked) ...[
                        const Icon(
                          Icons.lock_rounded,
                          size: 13,
                          color: Colors.amber,
                        ),
                        const SizedBox(width: 5),
                      ],
                      Text(
                        suggestion,
                        style: TextStyle(
                          fontFamily: AppColors.bodyFontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isLocked
                              ? AppColors.textSecondary
                              : AppColors.chartBarLight,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildChatList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      itemCount: _messages.length + (_isTyping ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length && _isTyping) {
          return const TypingIndicator();
        }
        final msg = _messages[index];
        return ChatBubble(
          text: msg.text,
          isUser: msg.isUser,
          timestamp: msg.timestamp,
        );
      },
    );
  }

  Widget _buildInputArea(double bottomInset, List<String> enabledModules) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 10, 10 + (bottomInset > 0 ? 0 : 6)),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                style: const TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (val) => _sendMessage(val, enabledModules),
                decoration: InputDecoration(
                  hintText: 'Ask CruDoc Assistant...',
                  hintStyle: TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    fontSize: 14,
                    color: AppColors.textSecondary.withValues(alpha: 0.6),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Voice Input Mic Button
          GestureDetector(
            onTap: () {
              VoiceInputModal.show(
                context,
                onSpeechRecognized: (voiceText) {
                  _sendMessage(voiceText, enabledModules);
                },
              );
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.chartBarLight.withValues(alpha: 0.3),
                ),
              ),
              child: const Icon(
                Icons.mic_rounded,
                color: AppColors.chartBarLight,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Send button
          GestureDetector(
            onTap: () => _sendMessage(_controller.text, enabledModules),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E78FF), Color(0xFF00C6FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1E78FF).withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.send_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
