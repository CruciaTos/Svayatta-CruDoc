import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';

import 'voice_command.dart';

/// A place to go: a screen, optionally with a Schedule view and day, and
/// in-screen spots (a Settings section, an Inventory tab, a filter, the
/// theme). [tab] is null for spots that don't change screen (the theme).
class NavTarget {
  const NavTarget({this.tab, this.view, this.date, this.spots = const {}});

  final int? tab;
  final ApptsView? view;
  final DateTime? date;

  /// [VoiceSpot.id]s, plus `revenue.period.today` / `week` / `month` / `year`.
  final Set<String> spots;

  bool sameAs(NavTarget? o) =>
      o != null &&
      o.tab == tab &&
      o.view == view &&
      o.date == date &&
      o.spots.length == spots.length &&
      o.spots.containsAll(spots);
}

/// Somewhere inside a screen voice can reach directly.
class VoiceSpot {
  const VoiceSpot(this.id, this.tab, this.label, this.phrases);

  final String id;

  /// null: no screen change (the theme).
  final int? tab;
  final String label;
  final List<String> phrases;
}

const voiceSpots = <VoiceSpot>[
  VoiceSpot('settings.profile', DesktopTab.settings, 'Profile', [
    'my profile',
    'profile settings',
    'edit my profile',
  ]),
  VoiceSpot('settings.clinic', DesktopTab.settings, 'Clinic & letterhead', [
    'clinic settings',
    'letterhead',
    'clinic details',
    'clinic address',
    'prescription header',
  ]),
  VoiceSpot('settings.accounts', DesktopTab.settings, 'Connected accounts', [
    'connected accounts',
    'gmail',
    'google account',
    'linked accounts',
  ]),
  VoiceSpot('settings.devices', DesktopTab.settings, 'Devices', [
    'devices',
    'device settings',
    'logged in devices',
  ]),
  VoiceSpot('settings.appearance', DesktopTab.settings, 'Appearance', [
    'appearance',
    'theme settings',
    'display settings',
  ]),
  VoiceSpot('settings.dental', DesktopTab.settings, 'Dental settings', [
    'dental settings',
    'tooth numbering',
  ]),
  VoiceSpot('settings.radiology', DesktopTab.settings, 'Radiology settings', [
    'radiology settings',
  ]),
  VoiceSpot('settings.about', DesktopTab.settings, 'About CruDoc', [
    'about crudoc',
    'about the app',
    'app version',
    'check for updates',
  ]),
  VoiceSpot('theme.evening', null, 'Evening mode', [
    'dark mode',
    'night mode',
    'evening mode',
    'dark theme',
    'make it dark',
  ]),
  VoiceSpot('theme.day', null, 'Day mode', [
    'light mode',
    'day mode',
    'light theme',
    'make it bright',
  ]),
  VoiceSpot('theme.auto', null, 'Auto appearance', [
    'auto mode',
    'auto theme',
    'automatic theme',
  ]),
  VoiceSpot('inventory.items', DesktopTab.inventory, 'Items', [
    'all items',
    'item list',
  ]),
  VoiceSpot('inventory.orders', DesktopTab.inventory, 'Orders', [
    'orders',
    'purchase orders',
    'reorders',
  ]),
  VoiceSpot('inventory.vendors', DesktopTab.inventory, 'Vendors', [
    'vendors',
    'suppliers',
    'dealers',
  ]),
  VoiceSpot('inventory.usage', DesktopTab.inventory, 'Usage', [
    'usage',
    'consumption',
    'stock usage',
  ]),
  VoiceSpot('inventory.low', DesktopTab.inventory, 'Low stock', [
    'low stock',
    'running low',
    'out of stock',
    'running out',
    'need to reorder',
  ]),
  VoiceSpot('inventory.expiring', DesktopTab.inventory, 'Expiring soon', [
    'expiring',
    'expiring soon',
    'expiry',
    'about to expire',
  ]),
  VoiceSpot('revenue.overview', DesktopTab.revenue, 'Overview', [
    'revenue overview',
  ]),
  VoiceSpot('revenue.invoices', DesktopTab.revenue, 'Invoices', [
    'invoices',
    'bills',
    'invoice list',
  ]),
  VoiceSpot('revenue.in', DesktopTab.revenue, 'Money in', [
    'money in',
    'income',
    'payments received',
    'money received',
  ]),
  VoiceSpot('revenue.out', DesktopTab.revenue, 'Money out', [
    'money out',
    'expenses',
    'spending',
    'money spent',
  ]),
  VoiceSpot('patients.overdue', DesktopTab.patients, 'Follow-up overdue', [
    'follow up overdue',
    'overdue follow ups',
    'overdue patients',
    'missed follow ups',
  ]),
  VoiceSpot('patients.balance', DesktopTab.patients, 'Balance due', [
    'balance due',
    'pending dues',
    'dues',
    'outstanding balance',
    'pending payments',
  ]),
  VoiceSpot('patients.treatment', DesktopTab.patients, 'In treatment', [
    'in treatment',
    'under treatment',
    'ongoing treatment',
  ]),
  VoiceSpot('patients.new', DesktopTab.patients, 'New this month', [
    'new patients',
    'new this month',
  ]),
  VoiceSpot('patients.recent', DesktopTab.patients, 'Last 7 days', [
    'recent patients',
    'last 7 days',
    'last seven days',
    'seen this week',
  ]),
  VoiceSpot('patients.all', DesktopTab.patients, 'All patients', [
    'all patients',
    'every patient',
  ]),
  VoiceSpot('action.newVisit', DesktopTab.dashboard, 'New visit', [
    'new visit',
    'check in',
    'walk in',
    'check in a patient',
  ]),
];

/// Everyday descriptions, only for the meaning-matcher: what a doctor
/// might say instead of a screen's name.
const _described = <String, List<String>>{
  'tab:0': ['main screen', 'start page', 'how is today going'],
  'tab:4': ['what does my day look like', 'my appointments', 'my calendar'],
  'tab:7': ['who is waiting', 'anyone waiting outside', 'waiting patients'],
  'tab:1': ['my patient list', 'look up a patient'],
  'tab:2': ['check my stock', 'supplies and materials'],
  'tab:3': [
    'how much money did I make',
    'how much did we collect',
    'my earnings',
    'money coming in',
  ],
  'tab:5': ['send messages to patients', 'bulk whatsapp', 'promotions'],
  'tab:6': ['record a consultation', 'dictate notes', 'take notes'],
  'tab:8': ['change settings', 'app settings'],
  'spot:inventory.low': [
    'what is running out',
    'what do I need to order',
    'supplies about to finish',
  ],
  'spot:inventory.expiring': ['what is about to expire', 'expired medicines'],
  'spot:patients.balance': [
    'who owes me money',
    'unpaid patients',
    'who has not paid',
  ],
  'spot:patients.overdue': [
    'who missed their follow up',
    'patients to call back',
  ],
  'spot:theme.evening': [
    'make the screen darker',
    'too bright, dim the screen',
  ],
  'spot:theme.day': ['make the screen brighter', 'too dark'],
  'spot:settings.clinic': ['change my clinic name', 'edit letterhead'],
  'spot:settings.accounts': ['connect my email', 'link google'],
  'spot:revenue.out': ['what did I spend', 'my expenses'],
  'spot:action.newVisit': ['a patient just walked in', 'register a walk in'],
};

/// Read-only questions answered in the voice pill.
enum VoiceQuestion {
  countAppointments,
  nextPatient,

  /// "Who was my last patient?"
  lastPatient,
  countPatients,

  /// "How much did I collect this month?"
  revenue,

  /// "When is Rahul's next appointment?"
  patientNext,

  /// "How many are waiting?"
  waiting,

  /// "Any free slot tomorrow evening?"
  freeSlot,
}

sealed class NavResult {
  const NavResult();
}

class NavNone extends NavResult {
  const NavNone();
}

class NavBack extends NavResult {
  const NavBack();
}

class NavHelp extends NavResult {
  const NavHelp();
}

class NavScreen extends NavResult {
  const NavScreen(this.target);
  final NavTarget target;
}

/// A screen this login's sidebar doesn't have ("lab cases" for a
/// periodontist).
class NavUnavailable extends NavResult {
  const NavUnavailable(this.tab);
  final int tab;
}

class NavAsk extends NavResult {
  const NavAsk(
    this.question, {
    this.date,
    this.name = '',
    this.period,
    this.slot,
  });

  /// Who the question is about (patientNext).
  final String name;

  /// 'today' / 'week' / 'month' / 'year' (revenue).
  final String? period;

  /// 'morning' / 'afternoon' / 'evening' / 'any' (freeSlot).
  final String? slot;
  final VoiceQuestion question;
  final DateTime? date;
}

/// Words people use for each screen besides its sidebar name.
const _synonyms = <int, List<String>>{
  DesktopTab.dashboard: [
    'dashboard',
    'home',
    'home screen',
    'main screen',
    'overview',
  ],
  DesktopTab.appointments: [
    'schedule',
    'calendar',
    'appointments',
    'bookings',
    'diary',
  ],
  DesktopTab.queue: [
    'queue',
    'waiting room',
    'waiting list',
    'live board',
    'live queue',
    'waiting patients',
  ],
  DesktopTab.patients: ['patients', 'patient list', 'all patients'],
  DesktopTab.inventory: ['inventory', 'stock', 'supplies', 'store'],
  DesktopTab.revenue: [
    'revenue',
    'payments',
    'billing',
    'collections',
    'earnings',
    'income',
    'accounts',
    'invoices',
    'money',
    'finance',
  ],
  DesktopTab.campaigns: ['campaigns', 'marketing', 'broadcasts'],
  DesktopTab.scribe: ['scribe', 'dictation', 'voice notes'],
  DesktopTab.settings: ['settings', 'preferences', 'setting'],
  DesktopTab.treatmentPlans: ['treatment plans', 'plans'],
  DesktopTab.recalls: ['recalls', 'recall list', 'due for recall'],
  DesktopTab.dentalReferrals: ['referrals', 'referral'],
  DesktopTab.sterilization: [
    'sterilization',
    'sterilisation',
    'autoclave',
    'sterilizer',
  ],
  DesktopTab.procedures: ['procedures', 'procedure list'],
  DesktopTab.perioPatients: ['perio patients', 'perio', 'periodontal'],
  DesktopTab.rootCanals: ['root canals', 'rct cases', 'endo cases'],
  DesktopTab.pedoChildren: ['children', 'kids', 'pediatric patients'],
  DesktopTab.biopsies: ['biopsies', 'biopsy'],
  DesktopTab.oralMedLesions: ['lesions', 'lesion'],
  DesktopTab.oralMedForms: ['forms', 'clinical forms'],
  DesktopTab.sedationCases: ['sedation cases', 'sedation'],
  DesktopTab.emergency: ['emergency', 'emergency protocols'],
  DesktopTab.labCases: ['lab cases', 'lab work', 'lab'],
  DesktopTab.orthoPatients: ['ortho patients', 'ortho', 'braces patients'],
  DesktopTab.healthCamps: ['camps', 'health camps'],
  DesktopTab.population: ['population'],
  DesktopTab.surgeries: ['surgeries', 'surgery list', 'operations'],
  DesktopTab.implants: ['implants', 'implant cases'],
  DesktopTab.worklist: ['worklist', 'work list'],
  DesktopTab.reports: ['reports', 'radiology reports'],
  DesktopTab.referrers: ['referrers', 'referring doctors'],
};

const _navVerbs = {
  'go',
  'open',
  'show',
  'take',
  'navigate',
  'switch',
  'jump',
  'view',
  'display',
  'bring',
  'pull',
  'visit',
  'see',
  'check',
  'turn',
  'enable',
  'use',
  'filter',
  'list',
};

/// Words that mean the doctor is booking or editing, not moving around.
const _actionWords = {
  'book',
  'add',
  'new',
  'create',
  'register',
  'fix',
  'reschedule',
  'move',
  'postpone',
  'prepone',
  'shift',
  'push',
  'rebook',
  'cancel',
};

String _singular(String w) =>
    w.length > 3 && w.endsWith('s') && !w.endsWith('ss')
    ? w.substring(0, w.length - 1)
    : w;

List<String> _words(String phrase) => phrase.split(' ').map(_singular).toList();

/// The spots this login can reach: in-screen places of visible screens,
/// Dental / Radiology settings only for those specialists, and the theme.
List<VoiceSpot> visibleSpots(List<({int tab, String label})> visible) {
  final allowed = {for (final v in visible) v.tab};
  return [
    for (final s in voiceSpots)
      if ((s.tab == null || allowed.contains(s.tab)) &&
          (s.id != 'settings.dental' ||
              allowed.contains(DesktopTab.treatmentPlans)) &&
          (s.id != 'settings.radiology' ||
              allowed.contains(DesktopTab.worklist)))
        s,
  ];
}

/// Everything the meaning-matcher may choose from, as (`tab:N` or
/// `spot:ID`, phrases).
List<({String id, List<String> phrases})> semanticOptions(
  List<({int tab, String label})> visible,
) {
  final allowed = {for (final v in visible) v.tab};
  List<String> extra(String id) => _described[id] ?? const [];
  return [
    for (final v in visible)
      (
        id: 'tab:${v.tab}',
        phrases: [
          v.label.toLowerCase(),
          ...?_synonyms[v.tab],
          ...extra('tab:${v.tab}'),
        ],
      ),
    if (allowed.contains(DesktopTab.appointments))
      (
        id: 'tab:${DesktopTab.queue}',
        phrases: [..._synonyms[DesktopTab.queue]!, ...extra('tab:7')],
      ),
    for (final s in visibleSpots(visible))
      (
        id: 'spot:${s.id}',
        phrases: [
          s.label.toLowerCase(),
          ...s.phrases,
          ...extra('spot:${s.id}'),
        ],
      ),
  ];
}

/// Turns a meaning-matcher answer back into a place to go.
NavTarget? targetFromOption(String id) {
  if (id.startsWith('tab:')) {
    final tab = int.tryParse(id.substring(4));
    return tab == null ? null : NavTarget(tab: tab);
  }
  if (id.startsWith('spot:')) {
    final spot = voiceSpots.where((s) => 'spot:${s.id}' == id).firstOrNull;
    return spot == null ? null : NavTarget(tab: spot.tab, spots: {spot.id});
  }
  return null;
}

/// Works out whether [text] asks to move around the app, and where to.
/// [visible] is this login's sidebar, so each specialty reaches exactly
/// its own screens.
NavResult resolveNavigation(
  String text,
  List<({int tab, String label})> visible,
  DateTime now,
) {
  final raw = tokenize(text);
  final t = raw.map(_singular).toList();
  if (t.isEmpty) return const NavNone();
  bool has(String w) => t.contains(w);
  bool seq(List<String> ws) {
    for (var i = 0; i + ws.length <= t.length; i++) {
      var ok = true;
      for (var k = 0; k < ws.length; k++) {
        if (t[i + k] != ws[k]) {
          ok = false;
          break;
        }
      }
      if (ok) return true;
    }
    return false;
  }

  if (has('help') ||
      seq(['what', 'can', 'i', 'say']) ||
      seq(['what', 'can', 'you', 'do'])) {
    return const NavHelp();
  }

  final cmd = VoiceCommand.parse(text, now);

  // Questions.
  final asking =
      has('how') ||
      has('who') ||
      has('whos') ||
      has('what') ||
      has('whats') ||
      has('any') ||
      has('when') ||
      seq(['is', 'there']) ||
      seq(['do', 'i', 'have']);
  if (asking) {
    if ((has('who') || has('whos')) &&
        (has('last') || has('previous')) &&
        (has('patient') || has('see') || has('saw') || has('seen'))) {
      return const NavAsk(VoiceQuestion.lastPatient);
    }
    if ((has('who') || has('whos')) && (has('next') || seq(['up', 'next']))) {
      return const NavAsk(VoiceQuestion.nextPatient);
    }
    if (seq(['how', 'many']) &&
        (has('appointment') ||
            has('booking') ||
            has('visit') ||
            has('patient') && cmd.date != null)) {
      return NavAsk(
        VoiceQuestion.countAppointments,
        date: cmd.date ?? DateTime(now.year, now.month, now.day),
      );
    }
    if (seq(['how', 'many']) && (has('waiting') || has('queue'))) {
      return const NavAsk(VoiceQuestion.waiting);
    }
    if (has('free') || has('available') || has('slot')) {
      return NavAsk(
        VoiceQuestion.freeSlot,
        date: cmd.date,
        slot: cmd.slot ?? 'any',
      );
    }
    if ((seq(['how', 'much']) || has('what')) &&
        t.any(
          const {
            'collect',
            'collected',
            'collection',
            'earn',
            'earned',
            'make',
            'made',
            'revenue',
            'income',
            'earning',
          }.contains,
        )) {
      final period = has('year') || has('yearly') || has('annual')
          ? 'year'
          : has('month')
          ? 'month'
          : has('week')
          ? 'week'
          : has('today') || has('daily')
          ? 'today'
          : null;
      return NavAsk(VoiceQuestion.revenue, period: period);
    }
    if (has('when') &&
        t.any(
          const {'next', 'appointment', 'coming', 'visit', 'due'}.contains,
        )) {
      return NavAsk(VoiceQuestion.patientNext, name: cmd.name);
    }
    if (seq(['how', 'many']) && has('patient')) {
      return const NavAsk(VoiceQuestion.countPatients);
    }
  }

  // In-screen spots: sections, tabs, filters, the theme.
  final spots = visibleSpots(visible);
  final spotHits = <(VoiceSpot, int)>[];
  for (final s in spots) {
    for (final p in s.phrases) {
      final w = _words(p);
      if (seq(w)) {
        spotHits.add((s, w.length));
        break;
      }
    }
  }
  spotHits.sort((a, b) => b.$2.compareTo(a.$2));

  if (t.any(_actionWords.contains) && spotHits.isEmpty) return const NavNone();

  // "go back", "back"
  if (t.length <= 3 && has('back') && !t.any((w) => _isScreenWord(w))) {
    return const NavBack();
  }

  // The longest screen name or synonym said.
  final allowed = {for (final v in visible) v.tab};
  int? tab;
  var bestLen = 0;
  final phrases = <(int, List<String>)>[
    for (final v in visible) (v.tab, _words(v.label.toLowerCase())),
    for (final e in _synonyms.entries)
      if (allowed.contains(e.key) ||
          (e.key == DesktopTab.queue &&
              allowed.contains(DesktopTab.appointments)))
        for (final s in e.value) (e.key, _words(s)),
  ];
  for (final (tb, words) in phrases) {
    if (words.length > bestLen && seq(words)) {
      tab = tb;
      bestLen = words.length;
    }
  }

  // A spot said more precisely than the screen ("low stock" beats
  // "stock") decides the screen.
  final topSpot = spotHits.isEmpty ? null : spotHits.first;
  var themeOnly = false;
  if (topSpot != null && (tab == null || topSpot.$2 > bestLen)) {
    if (topSpot.$1.tab == null) {
      themeOnly = tab == null;
    } else {
      tab = topSpot.$1.tab;
    }
    bestLen = topSpot.$2 > bestLen ? topSpot.$2 : bestLen;
  }

  // Schedule views and days: "this week", "month view", "what's on Friday".
  ApptsView? view;
  if (has('week') || has('weekly')) view = ApptsView.week;
  if (has('month') || has('monthly')) view = ApptsView.month;
  if (has('agenda')) view = ApptsView.agenda;
  if (seq(['day', 'view']) || has('daily')) view = ApptsView.day;
  if (has('live')) view = ApptsView.live;
  final whatsOn = (has('what') || has('whats')) && cmd.date != null;

  final verb = t.any(_navVerbs.contains);
  if (tab == null && !themeOnly && (whatsOn || (view != null && verb))) {
    tab = DesktopTab.appointments;
  }
  if (tab == null && !themeOnly) {
    if (!verb) return const NavNone();
    for (final e in _synonyms.entries) {
      for (final s in e.value) {
        final words = _words(s);
        if (words.length >= bestLen && seq(words)) return NavUnavailable(e.key);
      }
    }
    return const NavNone();
  }

  // Without "go to / open / show", only a bare place name counts.
  if (!verb && !whatsOn && t.length > bestLen + 2) return const NavNone();

  final chosen = <String>{
    for (final (s, _) in spotHits)
      if (s.tab == null || s.tab == tab) s.id,
  };

  DateTime? date;
  if (tab == DesktopTab.appointments || tab == DesktopTab.queue) {
    date = cmd.date;
    if (date != null && view == null) view = ApptsView.day;
  } else if (tab == DesktopTab.revenue) {
    // Revenue periods: "today's collections", "this month's revenue".
    final period = view == ApptsView.week
        ? 'week'
        : view == ApptsView.month
        ? 'month'
        : has('year') || has('yearly') || has('annual')
        ? 'year'
        : cmd.date != null && _sameDay(cmd.date!, now)
        ? 'today'
        : null;
    if (period != null) chosen.add('revenue.period.$period');
    view = null;
  } else {
    view = null;
  }
  if (tab == DesktopTab.queue) view = null;
  return NavScreen(NavTarget(tab: tab, view: view, date: date, spots: chosen));
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool _isScreenWord(String w) =>
    _synonyms.values.any((list) => list.any((s) => s.split(' ').contains(w)));
