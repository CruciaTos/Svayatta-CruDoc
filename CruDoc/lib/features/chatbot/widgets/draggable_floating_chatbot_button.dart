import 'package:flutter/material.dart';
import 'package:doctor_management_app/features/chatbot/presentation/chatbot_screen.dart';

/// A free-floating, draggable AI Chatbot assistant button.
///
/// Doctors can drag this button anywhere on the screen so it never
/// obstructs "+ Add Medicine", "+ Add Patient", or any UI buttons.
/// Snaps smoothly within screen boundaries and differentiates between tap & drag.
class DraggableFloatingChatbotButton extends StatefulWidget {
  final double initialBottom;
  final double initialRight;

  const DraggableFloatingChatbotButton({
    super.key,
    this.initialBottom = 130.0,
    this.initialRight = 16.0,
  });

  @override
  State<DraggableFloatingChatbotButton> createState() =>
      _DraggableFloatingChatbotButtonState();
}

class _DraggableFloatingChatbotButtonState
    extends State<DraggableFloatingChatbotButton>
    with SingleTickerProviderStateMixin {
  Offset? _position;
  bool _isDragging = false;
  double _dragDistance = 0.0;

  static const double _buttonSize = 54.0;
  static const double _padding = 12.0;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;

    // Calculate initial position on first build
    _position ??= Offset(
      screenSize.width - _buttonSize - widget.initialRight,
      screenSize.height - _buttonSize - widget.initialBottom,
    );

    // Keep position clamped inside safe screen bounds
    final minX = _padding;
    final maxX = screenSize.width - _buttonSize - _padding;
    final minY = padding.top + _padding;
    final maxY = screenSize.height - _buttonSize - padding.bottom - 80;

    final clampedX = _position!.dx.clamp(minX, maxX);
    final clampedY = _position!.dy.clamp(minY, maxY);
    final effectivePosition = Offset(clampedX, clampedY);

    return Positioned(
      left: effectivePosition.dx,
      top: effectivePosition.dy,
      child: GestureDetector(
        onPanStart: (details) {
          setState(() {
            _isDragging = true;
            _dragDistance = 0.0;
          });
        },
        onPanUpdate: (details) {
          setState(() {
            _position = Offset(
              _position!.dx + details.delta.dx,
              _position!.dy + details.delta.dy,
            );
            _dragDistance += details.delta.distance;
          });
        },
        onPanEnd: (details) {
          setState(() {
            _isDragging = false;

            // Snap to nearest edge (left or right) for a clean, dockable feel
            final midX = screenSize.width / 2;
            final targetX = (_position!.dx + _buttonSize / 2 < midX)
                ? minX
                : maxX;

            _position = Offset(targetX, _position!.dy.clamp(minY, maxY));
          });
        },
        onTap: () {
          if (_dragDistance < 8.0) {
            ChatbotScreen.show(context);
          }
        },
        child: AnimatedScale(
          scale: _isDragging ? 1.12 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: Container(
            width: _buttonSize,
            height: _buttonSize,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E78FF), Color(0xFF00C6FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.6),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1E78FF).withValues(
                    alpha: _isDragging ? 0.6 : 0.4,
                  ),
                  blurRadius: _isDragging ? 20 : 12,
                  offset: Offset(0, _isDragging ? 8 : 4),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(
                  Icons.smart_toy_rounded,
                  color: Colors.white,
                  size: 27,
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFF4ADE80),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
