import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';
import 'package:doctor_management_app/features/chatbot/services/chatbot_service.dart';
import 'package:doctor_management_app/features/chatbot/widgets/chat_bubble.dart';
import 'package:doctor_management_app/features/chatbot/widgets/voice_input_modal.dart';

/// Production-grade AI Chatbot screen for mobile doctors in CruDoc.
///
/// Features:
/// - WhatsApp & ChatGPT-style dynamic input bar (instant Mic / Send button morphing).
/// - Real Voice Input integration with live microphone capture & Gemini transcription.
/// - Full Markdown rendering with copy-to-clipboard, timestamps, and message retry.
/// - Intelligent suggestion chips and locked module guardrails.
/// - Smooth keyboard handling and auto-scrolling.
class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  /// Static helper to launch the chatbot as a responsive bottom sheet on mobile.
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
  bool _hasInputText = false;

  // Entrance animation
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  /// Quick suggestion chips shown when the chat is empty.
  static const _suggestions = [
    'How do I add a patient?',
    'How to create an invoice?',
    'How to manage inventory?',
    'How to schedule a visit?',
    'How to hide revenue on dashboard?',
    'Tell me about patient campaigns',
  ];

  @override
  void initState() {
    super.initState();
    _chatService.resetConversation();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();

    _controller.addListener(_onInputChanged);

    // Initial welcome message
    _messages.add(ChatMessage(
      id: const Uuid().v4(),
      text: '👋 **Hello, Doctor!**\n\n'
          'I\'m your CruDoc Assistant. Ask me anything about your practice or use the mic for instant voice queries! 😊',
      isUser: false,
      timestamp: DateTime.now(),
    ));
  }

  void _onInputChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasInputText) {
      setState(() {
        _hasInputText = hasText;
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onInputChanged);
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
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _sendMessage(String text, [List<String>? enabledModules]) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    _controller.clear();
    setState(() {
      _hasInputText = false;
    });

    final userMsgId = const Uuid().v4();
    setState(() {
      _messages.add(ChatMessage(
        id: userMsgId,
        text: trimmed,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _isTyping = true;
    });
    _scrollToBottom();

    try {
      final response = await _chatService.sendMessage(
        trimmed,
        enabledModules: enabledModules,
      );

      if (!mounted) return;

      setState(() {
        _isTyping = false;
        _messages.add(ChatMessage(
          id: const Uuid().v4(),
          text: response,
          isUser: false,
          timestamp: DateTime.now(),
        ));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isTyping = false;
        _messages.add(ChatMessage(
          id: const Uuid().v4(),
          text: '⚠️ Could not reach CruDoc Assistant. Please check your connection and tap to retry.',
          isUser: false,
          timestamp: DateTime.now(),
          isError: true,
        ));
      });
    }

    _scrollToBottom();
  }

  void _openVoiceInput(List<String> enabledModules) {
    VoiceInputModal.show(
      context,
      onSpeechRecognized: (voiceText) {
        if (voiceText.trim().isNotEmpty) {
          _sendMessage(voiceText, enabledModules);
        }
      },
    );
  }

  void _resetChat() {
    setState(() {
      _chatService.resetConversation();
      _messages.clear();
      _messages.add(ChatMessage(
        id: const Uuid().v4(),
        text: '👋 **Hello, Doctor!**\n\n'
            'I\'m your CruDoc Assistant. Ask me anything about the app or use voice dictation! 😊',
        isUser: false,
        timestamp: DateTime.now(),
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final screenHeight = mediaQuery.size.height;

    // Responsive sheet height
    final double sheetHeight = bottomInset > 0
        ? screenHeight * 0.88
        : screenHeight * 0.65;

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
                color: Colors.black.withValues(alpha: 0.16),
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

                  // App Bar
                  _buildAppBar(),

                  // Chat Body
                  Expanded(
                    child: _messages.length <= 1 && !_isTyping
                        ? _buildWelcomeView(enabledModules)
                        : _buildChatList(enabledModules),
                  ),

                  // Modern Dynamic Input Area
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

          // Title & Status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CruDoc Assistant',
                  style: TextStyle(
                    fontFamily: AppColors.headingFontFamily,
                    fontSize: 16.5,
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
                      _isTyping ? 'Generating response...' : 'Online & Ready',
                      style: TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        fontSize: 12,
                        color: _isTyping
                            ? const Color(0xFF1E78FF)
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

          // Reset Conversation Button
          if (_messages.length > 1)
            IconButton(
              tooltip: 'New Conversation',
              onPressed: _resetChat,
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

  /// Welcome view with bot intro and suggestion chips.
  Widget _buildWelcomeView(List<String> enabledModules) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const SizedBox(height: 12),
          ChatBubble(
            text: _messages.first.text,
            isUser: false,
            timestamp: _messages.first.timestamp,
          ),
          const SizedBox(height: 18),

          // Quick Questions header
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF1E78FF).withValues(alpha: 0.25),
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
                      'Quick Clinical & Practice Questions',
                      style: TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E78FF),
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
                          : const Color(0xFF1E78FF).withValues(alpha: 0.25),
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
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: isLocked
                              ? AppColors.textSecondary
                              : const Color(0xFF1E78FF),
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

  Widget _buildChatList(List<String> enabledModules) {
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
          isError: msg.isError,
          onRetry: msg.isError
              ? () => _sendMessage(msg.text, enabledModules)
              : null,
        );
      },
    );
  }

  /// Modern WhatsApp & ChatGPT-style dynamic input bar:
  /// - When empty: Mic button for instant voice recording.
  /// - When typing: Send button with smooth animation.
  Widget _buildInputArea(double bottomInset, List<String> enabledModules) {
    return Container(
      padding: EdgeInsets.fromLTRB(14, 8, 10, 8 + (bottomInset > 0 ? 2 : 8)),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Text Input Field
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 110),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                style: const TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  fontSize: 14.5,
                  color: AppColors.textPrimary,
                ),
                maxLines: null,
                minLines: 1,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.send,
                onSubmitted: (val) => _sendMessage(val, enabledModules),
                decoration: InputDecoration(
                  hintText: 'Ask doctor assistant or tap mic...',
                  hintStyle: TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    fontSize: 13.5,
                    color: AppColors.textSecondary.withValues(alpha: 0.6),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 11,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Dynamic Action Button: Mic (when empty) OR Send (when typing)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: _hasInputText
                ? GestureDetector(
                    key: const ValueKey('send_btn'),
                    onTap: () =>
                        _sendMessage(_controller.text, enabledModules),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1E78FF), Color(0xFF00C6FF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF1E78FF).withValues(alpha: 0.38),
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
                  )
                : GestureDetector(
                    key: const ValueKey('mic_btn'),
                    onTap: () => _openVoiceInput(enabledModules),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF1E78FF).withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Icon(
                        Icons.mic_rounded,
                        color: Color(0xFF1E78FF),
                        size: 22,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
