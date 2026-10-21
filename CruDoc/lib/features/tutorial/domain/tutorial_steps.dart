import 'package:flutter/foundation.dart';

import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/tutorial/domain/tutorial_step.dart';
import 'package:doctor_management_app/features/tutorial/presentation/tutorial_target.dart';

// The tours, as data. Core features only, at most 8 steps per platform,
// one short sentence each. Specialty steps (dental, radiology, homeopathy,
// therapy) can be added here later behind a guard.

bool _seesPatients(TutorialScope s) =>
    s.desktopTab(DesktopTab.patients) && s.planHas('patients');

bool _books(TutorialScope s) =>
    s.desktopTab(DesktopTab.appointments) &&
    (s.planHas('appointments') || s.planHas('queue'));

bool _usesScribe(TutorialScope s) =>
    s.desktopTab(DesktopTab.scribe) && s.planHas('ai_assistant');

bool _ownsPlan(TutorialScope s) => s.isOwner;

bool _phoneSchedule(TutorialScope s) =>
    s.mobileTab(MobileTab.schedule) &&
    (s.planHas('appointments') || s.planHas('queue'));

bool _phonePatients(TutorialScope s) =>
    s.mobileTab(MobileTab.patients) && s.planHas('patients');

/// As More's revenue card.
bool _phoneRevenue(TutorialScope s) =>
    s.planHas('revenue') &&
    s.roleAllows('revenue') &&
    s.can(ClinicPermission.revenue);

/// The desktop tour (window at least `kDesktopBreakpoint` wide).
List<TutorialStep> desktopTutorialSteps() {
  final search = defaultTargetPlatform == TargetPlatform.macOS
      ? '⌘ K'
      : 'Ctrl + K';
  return [
    const TutorialStep(
      id: 'welcome',
      title: 'Welcome to CruDoc',
      body: 'A 1-minute tour of the essentials. Skip any time.',
      tab: DesktopTab.dashboard,
    ),
    const TutorialStep(
      id: 'sidebar',
      title: 'Everything lives here',
      body: 'Today, Patients and Clinic tools. Ctrl + B hides it.',
      spots: [TutorialSpot(TutorialTarget.sidebar)],
      tab: DesktopTab.dashboard,
    ),
    TutorialStep(
      id: 'search',
      title: 'Find anyone fast',
      body: 'Search patients by name or phone. Press $search from anywhere.',
      spots: const [TutorialSpot(TutorialTarget.search)],
      tab: DesktopTab.dashboard,
      when: _seesPatients,
    ),
    const TutorialStep(
      id: 'add_patient',
      title: 'Add a patient',
      body: 'Register a new patient in under a minute.',
      spots: [TutorialSpot(TutorialTarget.addPatient)],
      tab: DesktopTab.dashboard,
      when: _seesPatients,
    ),
    const TutorialStep(
      id: 'new_appointment',
      title: 'Book a visit',
      body: 'Schedule appointments; they show up in Schedule and the queue.',
      spots: [TutorialSpot(TutorialTarget.newAppointment)],
      tab: DesktopTab.dashboard,
      when: _books,
    ),
    const TutorialStep(
      id: 'up_next',
      title: "Who's next",
      body: 'Your next patient, always at the top of the dashboard.',
      spots: [
        TutorialSpot(TutorialTarget.upNext),
        // No one waiting, so no Up next card: open Schedule instead.
        TutorialSpot(
          TutorialTarget.scheduleViews,
          title: 'Your schedule',
          body:
              "Today's appointments and walk-ins. Switch between Live and the calendar.",
          tab: DesktopTab.appointments,
          when: _books,
        ),
        TutorialSpot(
          TutorialTarget.sidebarSchedule,
          title: 'Your schedule',
          body: "Today's appointments and walk-ins, in order.",
          tab: DesktopTab.appointments,
          when: _books,
        ),
      ],
      tab: DesktopTab.dashboard,
    ),
    const TutorialStep(
      id: 'scribe',
      title: 'AI scribe',
      body: 'Speak during the visit; CruDoc drafts the notes for you.',
      spots: [
        TutorialSpot(
          TutorialTarget.scribePanel,
          body: 'Pick a visit and record; CruDoc drafts the notes for you.',
        ),
        TutorialSpot(TutorialTarget.sidebarScribe),
      ],
      tab: DesktopTab.scribe,
      when: _usesScribe,
      ai: true,
    ),
    const TutorialStep(
      id: 'account',
      title: "You're set",
      body:
          'Plan, profile and this tour again. Open Settings from your name, bottom left.',
      spots: [
        TutorialSpot(TutorialTarget.settingsSections, when: _ownsPlan),
        // The plan is the clinic owner's; their team doesn't see it.
        TutorialSpot(
          TutorialTarget.settingsSections,
          body:
              'Profile and this tour again. Open Settings from your name, bottom left.',
        ),
        TutorialSpot(
          TutorialTarget.account,
          body: 'Settings and this tour again live here.',
        ),
      ],
      tab: DesktopTab.settings,
    ),
  ];
}

/// Voice on the desktop: the pill at the top of the window.
const List<TutorialStep> desktopVoiceSteps = [
  TutorialStep(
    id: 'voice_welcome',
    title: 'Meet your voice assistant',
    body: 'Talk to CruDoc to add patients, book visits and fill forms.',
    tab: DesktopTab.dashboard,
  ),
  TutorialStep(
    id: 'voice_hold',
    title: 'Hold Space to talk',
    body: 'Hold Space, say what you need, then let go. Works on any screen.',
    spots: [TutorialSpot(TutorialTarget.voicePill)],
    tab: DesktopTab.dashboard,
  ),
  TutorialStep(
    id: 'voice_hands_free',
    title: 'Hands-free',
    body: 'Tap Space, or the mic here, to keep listening. Tap again to stop.',
    spots: [TutorialSpot(TutorialTarget.voicePill)],
    tab: DesktopTab.dashboard,
  ),
  TutorialStep(
    id: 'voice_forms',
    title: 'Fill forms by voice',
    body: 'Open a form, hold Space and say the details. It fills itself.',
    spots: [TutorialSpot(TutorialTarget.addPatient)],
    tab: DesktopTab.dashboard,
    when: _seesPatients,
  ),
  TutorialStep(
    id: 'voice_confirm',
    title: 'Check, then confirm',
    body: 'Say "confirm" or press Enter to save. Nothing saves before that.',
    spots: [TutorialSpot(TutorialTarget.voicePill)],
    tab: DesktopTab.dashboard,
  ),
];

/// Voice on the phone: the floating mic and the black pill.
const List<TutorialStep> mobileVoiceSteps = [
  TutorialStep(
    id: 'voice_welcome',
    title: 'Meet your voice assistant',
    body: 'Talk to CruDoc to add patients and book visits.',
    tab: MobileTab.home,
  ),
  TutorialStep(
    id: 'voice_hold',
    title: 'Hold to talk',
    body: 'Hold the mic, say what you need, then let go. Drag it anywhere.',
    spots: [TutorialSpot(TutorialTarget.voiceBubble)],
  ),
  TutorialStep(
    id: 'voice_pill',
    title: 'See what it heard',
    body: 'Your words show here. Holding the pill talks too.',
    spots: [TutorialSpot(TutorialTarget.island)],
  ),
  TutorialStep(
    id: 'voice_confirm',
    title: 'Check, then confirm',
    body: 'Say "confirm" to save a form. Nothing saves before that.',
    spots: [
      TutorialSpot(TutorialTarget.island),
      TutorialSpot(TutorialTarget.voiceBubble),
    ],
  ),
];

/// The phone tour (MobileShell). The gestures named here match
/// `showMobileGestureGuide`.
const List<TutorialStep> mobileTutorialSteps = [
  TutorialStep(
    id: 'welcome',
    title: 'Welcome to CruDoc',
    body: 'A quick look at the essentials. Skip any time.',
    tab: MobileTab.home,
  ),
  TutorialStep(
    id: 'up_next',
    title: 'Your day at a glance',
    body: "Who's next and what's waiting, right on Home.",
    spots: [
      TutorialSpot(TutorialTarget.mobileUpNext),
      TutorialSpot(TutorialTarget.navHome),
    ],
    tab: MobileTab.home,
  ),
  TutorialStep(
    id: 'schedule',
    title: 'Schedule',
    body: "Today's visits. Swipe a row right for its next step.",
    spots: [TutorialSpot(TutorialTarget.navSchedule)],
    tab: MobileTab.schedule,
    when: _phoneSchedule,
  ),
  TutorialStep(
    id: 'patients',
    title: 'Patients',
    body: 'All your patients. Tap + to add a new one.',
    spots: [
      TutorialSpot(TutorialTarget.mobileAddPatient),
      TutorialSpot(
        TutorialTarget.navPatients,
        body: 'All your patients, in one list.',
      ),
    ],
    tab: MobileTab.patients,
    when: _phonePatients,
  ),
  TutorialStep(
    id: 'tasks',
    title: 'Tasks',
    body: 'Follow-ups and to-dos so nothing slips.',
    spots: [TutorialSpot(TutorialTarget.navTasks)],
    tab: MobileTab.tasks,
  ),
  TutorialStep(
    id: 'island',
    title: 'The black pill',
    body: "Tap it for who's next and the live queue.",
    spots: [TutorialSpot(TutorialTarget.island)],
  ),
  TutorialStep(
    id: 'more',
    title: "You're set",
    body: 'Revenue, settings and this tour again are in More.',
    spots: [
      TutorialSpot(TutorialTarget.navMore, when: _phoneRevenue),
      TutorialSpot(
        TutorialTarget.navMore,
        body: 'Settings and this tour again are in More.',
      ),
    ],
    tab: MobileTab.more,
  ),
];

/// The steps of [platform]'s [tour], in order.
List<TutorialStep> tutorialStepsFor(
  TutorialPlatform platform, [
  TutorialTour tour = TutorialTour.app,
]) => switch ((platform, tour)) {
  (TutorialPlatform.desktop, TutorialTour.app) => desktopTutorialSteps(),
  (TutorialPlatform.mobile, TutorialTour.app) => mobileTutorialSteps,
  (TutorialPlatform.desktop, TutorialTour.voice) => desktopVoiceSteps,
  (TutorialPlatform.mobile, TutorialTour.voice) => mobileVoiceSteps,
};
