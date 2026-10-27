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
import 'package:doctor_management_app/shared/widgets/swipe_pages.dart';

/// The Schedule tab. Live is today's queue board (it has its own header);
/// Day, Week, Month and Agenda share the calendar header. Pads itself
/// with [CruSpace.mainPadding] (the shell doesn't).
///
/// The views sit side by side as [SwipePages] (Live, Week, Month, Agenda,
/// Visits); Day shares Week's page, so a day opened from Week swipes
/// exactly as Week does. Week ⇄ Day stays on its page and keeps its fold.
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

  bool get _live => ref.read(effectiveApptsViewProvider) == ApptsView.live;

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
    if (_live) return KeyEventResult.ignored;
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
    final controller = ref.read(apptsControllerProvider.notifier);

    return Focus(
      focusNode: _keys,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Listener(
        // Clicking the page gives the keys back to the calendar (a
        // Listener, so it never competes with taps below).
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          if (!_live && !_textFieldFocused()) _keys.requestFocus();
        },
        child: SwipePages<ApptsView>(
          values: ref.watch(availableApptsViewsProvider),
          value: view,
          pageOf: (v) => v == ApptsView.day ? ApptsView.week : v,
          // Week ⇄ Day from a date folds in place instead.
          slides: (_, _) => !controller.isWeekDayMorph,
          onChanged: (v) {
            controller.setView(v, fold: false);
            if (v != ApptsView.live && !_textFieldFocused()) {
              _keys.requestFocus();
            }
          },
          builder: (context, v) => ScheduleViewPage(
            view: v,
            child: v == ApptsView.live
                ? const DesktopQueueScreen()
                : _calendar(context, v),
          ),
        ),
      ),
    );
  }

  Widget _calendar(BuildContext context, ApptsView view) {
    final width = MediaQuery.sizeOf(context).width;
    final padding = width < CruBreakpoint.compact
        ? CruSpace.mainPaddingCompact
        : CruSpace.mainPadding;

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ApptsHeader(),
          const SizedBox(height: CruSpace.cardGap),
          Expanded(
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
        ],
      ),
    );
  }
}
