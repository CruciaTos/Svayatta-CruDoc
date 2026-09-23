import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/agenda/appointments_agenda_view.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/day/appointments_day_view.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/month/appointments_month_view.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/shell/appts_header.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/visits/appointments_home_visits_view.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/week/appointments_week_view.dart';
import 'package:doctor_management_app/features/queue/presentation/desktop_queue_screen.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:flutter/gestures.dart';

/// The Schedule tab. Live is today's queue board (it has its own header);
/// Day, Week, Month and Agenda share the calendar header. Pads itself
/// with [CruSpace.mainPadding] (the shell doesn't). No chatbot button.
///
/// Keyboard (calendar views): ← and → step one day, week or month; T
/// jumps to today (not while a text field has focus).
class AppointmentsScreen extends ConsumerStatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  ConsumerState<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends ConsumerState<AppointmentsScreen> {
  final FocusNode _keys = FocusNode(debugLabel: 'Appointments keys');

  @override
  void dispose() {
    _keys.dispose();
    super.dispose();
  }

  static bool _textFieldFocused() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText ||
        ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    if (_textFieldFocused()) return KeyEventResult.ignored;

    final controller = ref.read(apptsControllerProvider.notifier);
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      controller.step(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      controller.step(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyT && event is KeyDownEvent) {
      controller.today();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(effectiveApptsViewProvider);
    return AnimatedSwitcher(
      duration: CruMotion.of(context, CruMotion.fast),
      switchInCurve: CruMotion.curve,
      switchOutCurve: CruMotion.curve,
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, ?current]),
      child: view == ApptsView.live
          ? const DesktopQueueScreen(key: ValueKey('live'))
          : KeyedSubtree(
              key: const ValueKey('calendar'),
              child: _calendar(context, view),
            ),
    );
  }

  Widget _calendar(BuildContext context, ApptsView view) {
    final width = MediaQuery.sizeOf(context).width;
    final padding = width < CruBreakpoint.compact
        ? CruSpace.mainPaddingCompact
        : CruSpace.mainPadding;

    return Focus(
      focusNode: _keys,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Listener(
        // Clicking the page gives the keys back to the calendar (a
        // Listener, so it never competes with taps below).
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          if (!_textFieldFocused()) _keys.requestFocus();
        },
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ApptsHeader(),
              const SizedBox(height: CruSpace.cardGap),
              Expanded(
                child: _SwipeToStep(
                  onStep: ref.read(apptsControllerProvider.notifier).step,
                  child: AnimatedSwitcher(
                    duration: CruMotion.of(context, CruMotion.fast),
                    switchInCurve: CruMotion.curve,
                    switchOutCurve: CruMotion.curve,
                    // Views fill the body (the default layout loosens it).
                    layoutBuilder: (current, previous) => Stack(
                      fit: StackFit.expand,
                      children: [...previous, ?current],
                    ),
                    child: KeyedSubtree(
                      key: ValueKey(view),
                      child: switch (view) {
                        // Shown above instead (never reached).
                        ApptsView.live => const SizedBox.shrink(),
                        ApptsView.day => const AppointmentsDayView(),
                        ApptsView.week => const AppointmentsWeekView(),
                        ApptsView.month => const AppointmentsMonthView(),
                        ApptsView.agenda => const AppointmentsAgendaView(),
                        ApptsView.visits => const AppointmentsHomeVisitsView(),
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fling velocity (logical px/s) that counts as a swipe.
const double _kSwipeVelocity = 300;

/// Tablets: swipe left for the next day, week or month, right for the
/// previous one. Touch and stylus only, so dragging with a mouse on the
/// desktop does nothing new.
class _SwipeToStep extends StatelessWidget {
  const _SwipeToStep({required this.onStep, required this.child});

  final ValueChanged<int> onStep;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      supportedDevices: const {
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      },
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v.abs() < _kSwipeVelocity) return;
        HapticFeedback.selectionClick();
        onStep(v < 0 ? 1 : -1);
      },
      child: child,
    );
  }
}
