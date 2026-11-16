import 'dart:io';
import 'dart:ui' as ui;
import 'dart:ui' show DisplayFeature, DisplayFeatureType, DisplayFeatureState;

import 'package:doctor_management_app/core/services/demo_session_service.dart';
import 'package:doctor_management_app/core/utils/app_notice.dart';
import 'package:doctor_management_app/features/mobile/display_corners.dart';
import 'package:doctor_management_app/features/mobile/mobile_island.dart';
import 'package:doctor_management_app/features/mobile/island_surface.dart';
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/voice/voice_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';

const _dpr = 2.625;
const _out = r'C:\Soham\Kamachya_Goshti\Svayatta_CruDoc\CruDoc\handoff\out\island_v2';

final _ctxProvider = StateProvider<IslandContext>((ref) => _ctx(MobileTab.home));
final _voiceProvider = StateProvider<IslandVoice>((ref) => _voice());

IslandContext _ctx(int tab, {bool patient = false}) => (
  tab: tab,
  queue: (
    glance: (seen: 5, total: 12, waiting: 3),
    serving: (
      entryId: 'e1',
      name: 'Asha Rao',
      firstName: 'Asha',
      detail: '34 F · Cleaning',
    ),
    up: (
      name: 'Ravi Kumar',
      details: 'Root canal',
      waitMinutes: 12,
      isNextInCallOrder: true,
    ),
    nextBooking: DateTime(2026, 11, 15, 16, 30),
    nextBookingName: 'Meera Shah',
  ),
  patient: patient
      ? (
          id: 'p1',
          name: 'Asha Rao',
          firstName: 'Asha',
          ageSex: '34 F',
          lastVisit: DateTime(2026, 11, 2),
          balance: 1500,
        )
      : null,
);

final _level = ValueNotifier<double>(0.6);

IslandVoice _voice({
  bool listening = false,
  String heard = '',
  String? understood,
  bool ready = false,
  VoiceAsk? ask,
}) => IslandVoice(
  available: true,
  listening: listening,
  heard: heard,
  understood: understood,
  ready: ready,
  need: null,
  error: null,
  ask: ask,
  level: _level,
  onTalkStart: () {},
  onTalkEnd: () {},
  onPick: (_) {},
);

class _Overlay extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFFFF0000);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(48.76),
      ).deflate(0.5),
      p,
    );
    canvas.drawCircle(
      Offset(541 / _dpr, 60.5 / _dpr),
      10,
      Paint()..color = const Color(0xFF444444),
    );
  }

  @override
  bool shouldRepaint(_) => false;
}

void main() {
  testWidgets('render island states', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('crudoc/display'),
          (c) async => c.method == 'cornerRadius' ? (48.76 * _dpr).round() : null,
        );
    DisplayCorners.android.value = 48.76;
    DemoSessionService.startDemoSession();
    Directory(_out).createSync(recursive: true);

    final loader = FontLoader('Geist');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/Geist/Geist-$w.ttf'));
    }
    await loader.load();

    tester.view.devicePixelRatio = _dpr;
    tester.view.physicalSize = const Size(412 * _dpr, 915 * _dpr);
    tester.view.viewPadding = const FakeViewPadding(top: 46 * _dpr);
    tester.view.padding = const FakeViewPadding(top: 46 * _dpr);
    tester.view.displayFeatures = [
      DisplayFeature(
        bounds: Rect.fromLTRB(486 / _dpr, 0, 596 / _dpr, 121 / _dpr),
        type: DisplayFeatureType.cutout,
        state: DisplayFeatureState.unknown,
      ),
    ];
    addTearDown(() {
      tester.view.reset();
      debugDefaultTargetPlatformOverride = null;
      DemoSessionService.endDemoSession();
    });

    final boundary = GlobalKey();
    var gen = 0;

    Future<void> mount() async {
      gen++;
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpWidget(
        ProviderScope(
          key: ValueKey(gen),
          overrides: [
            islandContextProvider.overrideWith((ref) => ref.watch(_ctxProvider)),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'Geist'),
            home: RepaintBoundary(
              key: boundary,
              child: Consumer(
                builder: (context, ref, _) { return Stack(
                  children: [
                    Positioned.fill(child: Container(color: const Color(0xFFF2F2F7))),
                    for (var i = 0; i < 5; i++)
                      Positioned(
                        left: 16,
                        right: 16,
                        top: 130.0 + i * 110,
                        height: 90,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFD8D8DE),
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ),
                    Positioned.fill(
                      child: MobileIsland(
                        voice: ref.watch(_voiceProvider),
                        navContext: () => context,
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(painter: _Overlay()),
                      ),
                    ),
                  ],
                ); },
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    ProviderContainer container() => ProviderScope.containerOf(
      tester.element(find.byType(MobileIsland)),
    );

    Future<void> shot(String name) async {
      await tester.runAsync(() async {
        final ro =
            boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await ro.toImage(pixelRatio: _dpr);
        final bd = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$_out/$name.png').writeAsBytesSync(bd!.buffer.asUint8List());
      });
    }

    Future<void> settle() async {
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }

    Future<void> tapPill() async {
      await tester.tapAt(const Offset(541 / _dpr, 60.5 / _dpr));
    }

    // rest
    await mount();
    await settle();
    await shot('rest');

    // ask
    await mount();
    container().read(_voiceProvider.notifier).state = _voice(
      ask: VoiceAsk(
        prompt: 'Book Asha for 4:30 tomorrow?',
        options: const [VoiceChoice('Yes'), VoiceChoice('No')],
        onPick: (_) async {},
      ),
    );
    await settle();
    await shot('ask');

    // listening
    await mount();
    container().read(_voiceProvider.notifier).state = _voice(
      listening: true,
      heard: 'book a cleaning for asha tomorrow at',
    );
    await settle();
    await shot('listening');

    // thinking
    await mount();
    container().read(_voiceProvider.notifier).state = _voice(
      heard: 'book a cleaning for asha tomorrow at 4:30',
      understood: 'Thinking…',
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));
    await shot('thinking');

    // reply
    await mount();
    container().read(_voiceProvider.notifier).state = _voice(
      understood: 'Booked Asha Rao tomorrow 4:30 PM',
      ready: true,
    );
    await settle();
    await shot('reply');

    // notice
    await mount();
    AppNotices.show(
      AppNotice(text: 'Visit marked done', actionLabel: 'Undo', onAction: () {}),
    );
    await settle();
    await shot('notice');
    AppNotices.clear();
    await tester.pump(const Duration(seconds: 1));

    // peeks
    for (final e in {
      'peekSchedule': _ctx(MobileTab.schedule),
      'peekQueue': _ctx(MobileTab.home),
      'peekPatient': _ctx(MobileTab.patients, patient: true),
    }.entries) {
      await mount();
      container().read(_ctxProvider.notifier).state = e.value;
      await tester.pump(const Duration(milliseconds: 600));
      await tapPill();
      await settle();
      await shot(e.key);
    }

    // morph sequences
    Future<void> sequence(String prefix, Future<void> Function() trigger,
        {Future<void> Function()? pre}) async {
      await mount();
      await tester.pump(const Duration(milliseconds: 600));
      if (pre != null) {
        await pre();
        await settle();
      }
      await trigger();
      await tester.pump();
      var t = 0;
      await shot('${prefix}_0');
      for (var i = 1; i <= 40; i++) {
        await tester.pump(const Duration(milliseconds: 13));
        t += 13;
        if ([104, 208, 312, 416, 520].contains(t)) await shot('${prefix}_$t');
      }
    }

    await sequence('morph', tapPill);
    await sequence('morphclose', tapPill, pre: tapPill);
    await sequence('morphvoice', () async {
      container().read(_voiceProvider.notifier).state = _voice(
        listening: true,
        heard: 'book a cleaning for asha tomorrow at',
      );
    });
    debugDefaultTargetPlatformOverride = null;
  });
}
