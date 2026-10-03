import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/models/doctor_specialty.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';
import 'package:doctor_management_app/core/widgets/subspecialty_row.dart';
import 'package:doctor_management_app/features/onboarding/data/loyalty_card.dart';
import 'package:doctor_management_app/features/onboarding/presentation/loyalty_card_view.dart';
import 'package:doctor_management_app/features/subscription/data/doctor_subscription_service.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Length of the free trial that starts when onboarding finishes.
const int kTrialDays = 30;

/// Content column width.
const double _kMaxWidth = 560;

/// Height of a specialty tile.
const double _kSpecialtyTile = 92;

enum PracticeType {
  solo('Solo practice', 'Just me, one chair or one room.', CruIcons.user),
  clinic(
    'Clinic',
    'A team: receptionist, assistants or other doctors.',
    CruIcons.patients,
  );

  const PracticeType(this.label, this.detail, this.icon);
  final String label;
  final String detail;
  final CruIconData icon;
}

/// Paid modules we switch on when the doctor takes our suggestion.
Set<String> suggestedModules(PracticeType practice, DoctorSpecialty? spec) => {
  'revenue',
  'omnichannel_messaging',
  'ai_assistant',
  if (practice == PracticeType.clinic) 'multi_device_access',
  if (spec?.rootType == DoctorSpecialtyType.physiotherapy) 'home_visits',
};

/// Answers given before the account exists (on a phone, Get started
/// comes before sign-in). Held in memory; the shell saves them once the
/// doctor has signed in.
class OnboardingAnswers {
  const OnboardingAnswers({
    required this.practice,
    required this.name,
    required this.specialty,
    required this.suggest,
    required this.picked,
  });

  final PracticeType practice;
  final String name;
  final DoctorSpecialtyType specialty;
  final bool suggest;
  final Set<String> picked;

  static OnboardingAnswers? pending;
}

/// First-run setup after sign-in: practice type, name and specialty,
/// features, then the loyalty card with its first stamp. Writes the
/// profile, starts the trial and stamps the card; calls [onDone] when the
/// doctor opens the app.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({
    super.key,
    required this.onDone,
    this.initialName,
    this.answers,
    this.onAnswered,
    this.onHaveAccount,
  });

  final VoidCallback onDone;
  final String? initialName;

  /// Answers from before sign-in: saved straight away, then the card.
  final OnboardingAnswers? answers;

  /// Set before sign-in: the last step hands the answers here instead of
  /// saving (there is no account yet).
  final ValueChanged<OnboardingAnswers>? onAnswered;

  /// "I already have an account" on the first step (before sign-in).
  final VoidCallback? onHaveAccount;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  static const _questionSteps = 3;

  int _step = 0;
  PracticeType? _practice;
  late final TextEditingController _name;
  DoctorSpecialtyType? _specialty;

  /// Null until the doctor answers; true = take our suggestion.
  bool? _suggest;
  final Set<String> _picked = {};

  bool _saving = false;
  String? _error;
  LoyaltyCard? _card;

  @override
  void initState() {
    super.initState();
    final a = widget.answers;
    _name = TextEditingController(
      text:
          a?.name ??
          widget.initialName ??
          (widget.onAnswered != null
              ? null
              : FirebaseAuth.instance.currentUser?.displayName),
    );
    if (a != null) {
      _practice = a.practice;
      _specialty = a.specialty;
      _suggest = a.suggest;
      _picked.addAll(a.picked);
      _step = _questionSteps - 1;
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  DoctorSpecialty? get _spec =>
      _specialty == null ? null : DoctorSpecialty.ofType(_specialty!);

  Set<String> get _modules => _suggest == true
      ? suggestedModules(_practice ?? PracticeType.solo, _spec)
      : _picked;

  bool get _canContinue => switch (_step) {
    0 => _practice != null,
    1 => _name.text.trim().isNotEmpty && _specialty != null,
    _ => _suggest != null,
  };

  Future<void> _next() async {
    if (!_canContinue || _saving) return;
    if (_step < _questionSteps - 1) {
      setState(() => _step++);
      return;
    }
    if (widget.onAnswered != null) {
      widget.onAnswered!(
        OnboardingAnswers(
          practice: _practice!,
          name: _name.text.trim(),
          specialty: _specialty!,
          suggest: _suggest!,
          picked: {..._picked},
        ),
      );
      return;
    }
    await _finish();
  }

  Future<void> _finish() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final name = _name.text.trim();
      final spec = _spec!;
      final modules = <String>{
        ...DoctorFeatureGuard.baseModules,
        'queue',
        ..._modules,
      }.toList();
      await saveDoctorSpecialty(spec, user: user);
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'displayName': name,
        'practiceType': _practice!.name,
        'status': 'trial',
        'subscriptionPlan': 'Trial',
        'expiresDate': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: kTrialDays)),
        ),
        'enabledModules': modules,
        'allowMultiDevice': modules.contains('multi_device_access'),
        // What the Super Admin reads to see how each doctor started.
        'onboarding': {
          'practiceType': _practice!.name,
          'featureChoice': _suggest! ? 'suggested' : 'picked',
          'chosenModules': _modules.toList(),
          'completedAt': FieldValue.serverTimestamp(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (user.displayName != name) await user.updateDisplayName(name);
      final card = await LoyaltyService.stampThisMonth();
      if (!mounted) return;
      setState(() {
        _card = card;
        _step = _questionSteps;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save. Check the connection and try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final done = _step == _questionSteps;
    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kMaxWidth),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                CruSpace.s16,
                CruSpace.s24,
                CruSpace.s16,
                CruSpace.s16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!done) ...[
                    Text(
                      'Step ${_step + 1} of $_questionSteps',
                      style: CruType.caption.tabular.tint(c.label3),
                    ),
                    const SizedBox(height: CruSpace.s8),
                    CruProgressBar(value: (_step + 1) / _questionSteps),
                    const SizedBox(height: CruSpace.s24),
                  ],
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeOutCubic,
                      layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.topCenter,
                        children: [...previous, ?current],
                      ),
                      child: SingleChildScrollView(
                        key: ValueKey(_step),
                        child: switch (_step) {
                          0 => _practiceStep(),
                          1 => _aboutStep(),
                          2 => _featuresStep(),
                          _ => _loyaltyStep(),
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: CruSpace.s16),
                  if (_error != null) ...[
                    Text(_error!, style: CruType.text.tint(c.label)),
                    const SizedBox(height: CruSpace.s8),
                  ],
                  if (done)
                    CruButton(
                      label: 'Open CruDoc',
                      large: true,
                      expand: true,
                      onPressed: widget.onDone,
                    )
                  else
                    Row(
                      children: [
                        if (_step > 0) ...[
                          CruButton(
                            label: 'Back',
                            kind: CruButtonKind.inset,
                            large: true,
                            onPressed: _saving
                                ? null
                                : () => setState(() => _step--),
                          ),
                          const SizedBox(width: CruSpace.s12),
                        ],
                        Expanded(
                          child: CruButton(
                            label: _saving
                                ? 'Setting up…'
                                : _step == _questionSteps - 1
                                ? (widget.onAnswered != null
                                      ? 'Create account'
                                      : 'Start free trial')
                                : 'Continue',
                            large: true,
                            expand: true,
                            onPressed: _canContinue && !_saving ? _next : null,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(String title, String lead) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.only(bottom: CruSpace.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: CruType.largeTitle.tint(c.label)),
          ),
          const SizedBox(height: CruSpace.s6),
          Text(lead, style: CruType.lead.tint(c.label2)),
        ],
      ),
    );
  }

  Widget _practiceStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          'Welcome to CruDoc',
          'A few questions so the app fits how you work. Takes a minute.',
        ),
        for (final p in PracticeType.values) ...[
          _OptionTile(
            icon: p.icon,
            title: p.label,
            detail: p.detail,
            selected: _practice == p,
            onTap: () => setState(() => _practice = p),
          ),
          const SizedBox(height: CruSpace.s12),
        ],
        if (widget.onHaveAccount != null) ...[
          const SizedBox(height: CruSpace.s8),
          Center(
            child: CruLink(
              label: 'I already have an account',
              onPressed: widget.onHaveAccount,
            ),
          ),
        ],
      ],
    );
  }

  Widget _aboutStep() {
    final c = context.cru;
    final spec = _spec;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading('About you', 'Shown on your prescriptions and to your patients.'),
        CruTextField(
          label: 'Your name',
          controller: _name,
          hint: 'Dr. Priya Sharma',
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: CruSpace.s20),
        Text('Specialty', style: CruType.subhead.tint(c.label2)),
        const SizedBox(height: CruSpace.s8),
        LayoutBuilder(
          builder: (context, box) {
            final columns = box.maxWidth > 440 ? 4 : 3;
            final w =
                (box.maxWidth - CruSpace.s8 * (columns - 1)) / columns;
            return Wrap(
              spacing: CruSpace.s8,
              runSpacing: CruSpace.s8,
              children: [
                for (final s in DoctorSpecialty.all)
                  SizedBox(
                    width: w,
                    height: _kSpecialtyTile,
                    child: _SpecialtyTile(
                      spec: s,
                      selected: spec != null && spec.isUnder(s.type),
                      onTap: () => setState(() => _specialty = s.type),
                    ),
                  ),
              ],
            );
          },
        ),
        if (spec != null &&
            DoctorSpecialty.subspecialtiesOf(spec.rootType).isNotEmpty) ...[
          const SizedBox(height: CruSpace.s12),
          SubspecialtyRow(
            selected: spec,
            onSelected: (s) => setState(() => _specialty = s.type),
          ),
        ],
      ],
    );
  }

  Widget _featuresStep() {
    final c = context.cru;
    final paid = featureCatalog.where((f) => !f.isBaseModule).toList();
    final on = _modules;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          'Your features',
          'Patients, appointments, queue and inventory are always included. '
              'Everything you turn on is free for $kTrialDays days.',
        ),
        _OptionTile(
          icon: CruIcons.sparkle,
          title: 'Use what we suggest',
          detail: [
            _practice == PracticeType.clinic ? 'Picked for a clinic' : 'Picked for a solo practice',
            ?_spec?.label,
          ].join(' · '),
          selected: _suggest == true,
          onTap: () => setState(() => _suggest = true),
        ),
        const SizedBox(height: CruSpace.s12),
        _OptionTile(
          icon: CruIcons.check,
          title: "I'll pick myself",
          detail: 'Choose from the list below.',
          selected: _suggest == false,
          onTap: () => setState(() {
            if (_suggest != false && _picked.isEmpty) {
              _picked.addAll(
                suggestedModules(_practice ?? PracticeType.solo, _spec),
              );
            }
            _suggest = false;
          }),
        ),
        if (_suggest != null) ...[
          const SizedBox(height: CruSpace.s20),
          CruCard(
            padding: const EdgeInsets.symmetric(vertical: CruSpace.s8),
            child: Column(
              children: [
                for (var i = 0; i < paid.length; i++) ...[
                  if (i > 0) const CruSeparator(indent: CruSpace.s16),
                  _FeatureRow(
                    item: paid[i],
                    on: on.contains(paid[i].moduleKey),
                    onTap: _suggest == false
                        ? () => setState(() {
                            final k = paid[i].moduleKey;
                            if (!_picked.remove(k)) _picked.add(k);
                          })
                        : null,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: CruSpace.s8),
          Text(
            'You can change these any time from your plan.',
            style: CruType.caption.tint(c.label3),
          ),
        ],
      ],
    );
  }

  Widget _loyaltyStep() {
    final name = _name.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          "You're in${name.isEmpty ? '' : ', $name'}",
          'Your $kTrialDays-day trial has started, and joining earned your first stamp.',
        ),
        LoyaltyCardView(
          card:
              _card ??
              LoyaltyCard(
                stamps: 1,
                stampedMonths: [loyaltyMonthKey(DateTime.now())],
              ),
          animateLast: true,
        ),
      ],
    );
  }
}

/// A large choice row: icon tile, title and one line of detail.
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.title,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  final CruIconData icon;
  final String title;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruPressable(
      onTap: onTap,
      semanticLabel: title,
      builder: (context, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(CruSpace.s16),
        decoration: ShapeDecoration(
          color: hovered && !selected ? c.hoverFill : c.surface,
          shape: cruShape(
            CruRadius.control,
            side: BorderSide(
              color: selected ? c.label : c.cardBorder,
              width: selected ? 1.5 : 1,
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: CruSize.iconTile,
              height: CruSize.iconTile,
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: selected ? c.label : c.inset,
                shape: cruShape(CruRadius.iconTile),
              ),
              child: CruIcon(
                icon,
                size: 18,
                color: selected ? c.surface : c.label2,
              ),
            ),
            const SizedBox(width: CruSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: CruType.row.w600.tint(c.label)),
                  const SizedBox(height: CruSpace.s2),
                  Text(detail, style: CruType.text.tint(c.label2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpecialtyTile extends StatelessWidget {
  const _SpecialtyTile({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  final DoctorSpecialty spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruPressable(
      onTap: onTap,
      semanticLabel: spec.label,
      builder: (context, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(CruSpace.s8),
        decoration: ShapeDecoration(
          color: hovered && !selected ? c.hoverFill : c.surface,
          shape: cruShape(
            CruRadius.control,
            side: BorderSide(
              color: selected ? c.label : c.cardBorder,
              width: selected ? 1.5 : 1,
            ),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(spec.icon, size: 22, color: selected ? c.label : c.label2),
            const SizedBox(height: CruSpace.s6),
            Text(
              spec.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: CruType.caption
                  .copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  )
                  .tint(selected ? c.label : c.label2),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.item, required this.on, this.onTap});

  final FeaturePricingItem item;
  final bool on;

  /// Null in "suggested" mode: the list is a read-only preview.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s16,
        vertical: CruSpace.s12,
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? c.green : c.inset,
              border: on ? null : Border.all(color: c.separator),
            ),
            child: on
                ? CruIcon(
                    CruIcons.check,
                    size: 14,
                    color: c.onAccent,
                    strokeWidth: 2.4,
                  )
                : null,
          ),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: CruType.row.tint(c.label)),
                const SizedBox(height: CruSpace.s2),
                Text(
                  item.description,
                  style: CruType.caption.tint(c.label2),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          Text(
            '₹${NumberFormat.decimalPattern('en_IN').format(item.monthlyPriceInr)}/mo',
            style: CruType.caption.tabular.tint(c.label3),
          ),
        ],
      ),
    );
    return onTap == null ? row : CruPressable(onTap: onTap, builder: (_, _) => row);
  }
}
