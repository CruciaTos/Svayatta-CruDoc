import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/people/crudoc_id.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/dental/domain/tooth_numbering.dart';
import 'package:doctor_management_app/features/dental/presentation/dental_features_picker.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_icons.dart';
import 'package:doctor_management_app/features/dental/specialties/pedo/large_mode.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_settings_section.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/mobile/mobile_more.dart';
import 'package:doctor_management_app/features/shell/components/cru_sidebar.dart';
import 'package:doctor_management_app/core/models/device_session.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/core/services/auth_service.dart';
import 'package:doctor_management_app/core/services/device_session_service.dart';
import 'package:doctor_management_app/core/update/models/update_check_result.dart';
import 'package:doctor_management_app/core/utils/device_info_helper.dart';
import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/messaging/data/providers/reminder_settings_providers.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_models.dart';
import 'package:doctor_management_app/features/messaging/data/providers/gmail_auth_providers.dart';
import 'package:doctor_management_app/features/onboarding/presentation/doctor_loyalty_card.dart';
import 'package:doctor_management_app/features/subscription/data/doctor_subscription_service.dart';
import 'package:doctor_management_app/features/subscription/presentation/subscription_billing_page.dart';
import 'package:doctor_management_app/features/settings/data/appearance_preferences.dart';
import 'package:doctor_management_app/features/settings/data/appearance_provider.dart';
import 'package:doctor_management_app/features/shell/components/specialty_switcher_dialog.dart';
import 'package:doctor_management_app/features/team/presentation/clinic_invites_section.dart';
import 'package:doctor_management_app/features/settings/presentation/storage_section.dart';
import 'package:doctor_management_app/features/settings/presentation/call_forwarding_section.dart';
import 'package:doctor_management_app/features/files/presentation/nearby_sharing_settings.dart';
import 'package:doctor_management_app/features/team/presentation/team_section.dart';
import 'package:doctor_management_app/features/tutorial/domain/tutorial_step.dart';
import 'package:doctor_management_app/features/tutorial/presentation/tutorial_controller.dart';
import 'package:doctor_management_app/features/tutorial/presentation/tutorial_target.dart';
import 'package:doctor_management_app/features/update/controllers/update_controller.dart';
import 'package:doctor_management_app/features/settings/presentation/documents/documents_settings_section.dart';
import 'package:doctor_management_app/features/support/presentation/support_section.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The Settings sections, in sidebar order. Every entry does something
/// real: nothing here is a placeholder switch.
enum SettingsSection {
  profile('Profile', CruIcons.user),
  plan('Plan & billing', CruIcons.wallet),
  clinic('Clinic & documents', CruIcons.pen),

  /// People who can manage the clinic's team.
  team('Team', CruIcons.patients),

  /// Someone working in another person's clinic.
  myFeatures('My features', CruIcons.check),

  /// Everyone: the number clinics invite, being findable, open invites.
  invites('Clinic invites', CruIcons.userPlus),
  accounts('Connected accounts', CruIcons.arrowUpRight),
  devices('Devices', CruIcons.sidebar),
  appearance('Appearance', CruIcons.sun),

  /// Not on the web, which keeps nothing on the device.
  storage('Storage', CruIcons.download),

  /// Forwards the doctor's number to the clinic's AI receptionist. People
  /// who may use the AI ('ai'), which is also what the line's rules ask.
  callForwarding('Call forwarding', CruIcons.phone),

  /// Clinics whose plan includes messaging.
  reminders('Patient reminders', CruIcons.whatsapp),

  /// Dentists and dental specialists only.
  dental('Dental', DentalIcons.tooth),

  /// Oral & Maxillofacial Radiologists only.
  radiology('Radiology', RadIcons.xray),

  /// Everyone: report a problem, request a feature, share feedback.
  support('Help & feedback', CruIcons.whatsapp),
  about('About CruDoc', CruIcons.help);

  const SettingsSection(this.label, this.icon);
  final String label;
  final CruIconData icon;
}

/// Whether [s] is listed for the signed-in person (desktop and phone).
bool showSettingsSection(WidgetRef ref, SettingsSection s) {
  final access = ref.watch(clinicAccessProvider).value;
  final isOwner = access == null || access.isOwner;
  return switch (s) {
    SettingsSection.plan => access == null || access.isOwner,
    SettingsSection.radiology => ref.watch(hasDentalRadiologyProvider),
    SettingsSection.dental =>
      ref.watch(isDentalProvider) &&
          (access == null || access.can(ClinicPermission.clinicalView)),
    // The server reads reminder settings from the owner's profile.
    SettingsSection.reminders =>
      isOwner && ref.watch(whatsAppRemindersAvailableProvider),
    // Clinic & documents moved to the Documents page in the sidebar.
    SettingsSection.clinic => false,
    SettingsSection.team => access != null && access.can(ClinicPermission.team),
    SettingsSection.myFeatures => !isOwner,
    SettingsSection.storage => !kIsWeb,
    SettingsSection.callForwarding =>
      access == null || access.can(ClinicPermission.ai),
    _ => true,
  };
}

/// The open section. The account menu sets it ("Profile" opens Profile).
final settingsSectionProvider = StateProvider<SettingsSection>(
  (ref) => SettingsSection.profile,
);

/// Width of the section list.
const double _kNavWidth = 248;

/// Section content never gets wider than this, so fields stay readable.
const double _kContentMaxWidth = 760;

/// The Settings tab, inside the desktop shell: a section list on the left
/// and the open section's cards on the right. Built on the Calm Clinical
/// tokens, so it follows Day / Evening. Pads itself like the other
/// redesigned screens.
class DesktopSettingsScreen extends ConsumerWidget {
  const DesktopSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    // Shared with the dashboard: one subscription to the profile document.
    final user = ref.watch(authStateProvider).value;
    final profile = ref.watch(doctorProfileProvider).value;
    final section = ref.watch(settingsSectionProvider);
    final width = MediaQuery.sizeOf(context).width;
    final padding = width < CruBreakpoint.compact
        ? CruSpace.mainPaddingCompact
        : CruSpace.mainPadding;

    final name = DoctorProfileHelper.formatDoctorName(user, profile);
    final email = user?.email;
    Widget body(SettingsSection section) => switch (section) {
      SettingsSection.profile => _ProfileSection(user: user, profile: profile),
      SettingsSection.plan => const _PlanSection(),
      SettingsSection.clinic => const DocumentsSettingsSection(),
      SettingsSection.team => const TeamSection(),
      SettingsSection.myFeatures => const MyFeaturesSection(),
      SettingsSection.invites => const ClinicInvitesSection(),
      SettingsSection.accounts => const _AccountsSection(),
      SettingsSection.devices => _DevicesSection(user: user),
      SettingsSection.appearance => const _AppearanceSection(),
      SettingsSection.storage => const StorageSection(),
      SettingsSection.callForwarding => const CallForwardingSection(),
      SettingsSection.reminders => const _RemindersSection(),
      SettingsSection.dental => const _DentalSection(),
      SettingsSection.radiology => const RadSettingsSection(),
      SettingsSection.support => const SupportSection(),
      SettingsSection.about => const _AboutSection(),
    };
    if (cruIsPhone(context)) {
      // Phone: one section per page (the phone lists them in More).
      return SingleChildScrollView(
        padding: CruSpace.mainPaddingPhone,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                section.label,
                style: CruType.largeTitle.copyWith(fontSize: 28).tint(c.label),
              ),
            ),
            const SizedBox(height: CruSpace.s16),
            body(section),
          ],
        ),
      );
    }
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text('Settings', style: CruType.largeTitle.tint(c.label)),
          ),
          const SizedBox(height: CruSpace.s2),
          Text(
            [name, if (email != null && email.isNotEmpty) email].join(' · '),
            style: CruType.text.tint(c.accentText),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: CruSpace.cardGap),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: _kNavWidth,
                  child: TutorialAnchor(
                    target: TutorialTarget.settingsSections,
                    radius: CruRadius.card,
                    child: _SectionList(
                      sections: [
                        for (final s in SettingsSection.values)
                          if (showSettingsSection(ref, s)) s,
                      ],
                      selected: section,
                      onSelect: (s) =>
                          ref.read(settingsSectionProvider.notifier).state = s,
                    ),
                  ),
                ),
                const SizedBox(width: CruSpace.cardGap),
                Expanded(
                  child: SingleChildScrollView(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: _kContentMaxWidth,
                        ),
                        child: AnimatedSwitcher(
                          duration: CruMotion.of(context, CruMotion.fast),
                          switchInCurve: CruMotion.curve,
                          switchOutCurve: CruMotion.curve,
                          layoutBuilder: (current, previous) => Stack(
                            alignment: Alignment.topLeft,
                            children: [...previous, ?current],
                          ),
                          child: KeyedSubtree(
                            key: ValueKey(section),
                            child: body(section),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// SECTION LIST
// =============================================================================

class _SectionList extends StatelessWidget {
  const _SectionList({
    required this.sections,
    required this.selected,
    required this.onSelect,
  });

  final List<SettingsSection> sections;
  final SettingsSection selected;
  final ValueChanged<SettingsSection> onSelect;

  @override
  Widget build(BuildContext context) {
    return CruCard(
      semanticLabel: 'Settings sections',
      padding: const EdgeInsets.all(CruSpace.s8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final s in sections)
            _SectionItem(
              section: s,
              selected: s == selected,
              onTap: () => onSelect(s),
            ),
        ],
      ),
    );
  }
}

class _SectionItem extends StatelessWidget {
  const _SectionItem({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final SettingsSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Semantics(
      selected: selected,
      child: CruPressable(
        onTap: onTap,
        semanticLabel: section.label,
        scaleOnPress: false,
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          height: CruSize.navItem,
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
          decoration: ShapeDecoration(
            color: selected
                ? c.inset
                : (hovered ? c.hoverFill : c.inset.withValues(alpha: 0)),
            shape: cruShape(CruRadius.control),
          ),
          child: Row(
            children: [
              CruIcon(
                section.icon,
                size: 18,
                color: selected ? c.accentText : c.label2,
              ),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Text(
                  section.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (selected ? CruType.nav.w600 : CruType.nav).tint(
                    c.label,
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

// =============================================================================
// SHARED PIECES
// =============================================================================

/// A settings card: a headline, an optional one-line description, then
/// the content.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.child,
    this.description,
    this.trailing,
  });

  final String title;
  final String? description;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruCard(
      semanticLabel: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: CruType.headline.tint(c.label)),
                    if (description != null) ...[
                      const SizedBox(height: CruSpace.s4),
                      Text(description!, style: CruType.text.tint(c.label2)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: CruSpace.s16),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: CruSpace.s20),
          child,
        ],
      ),
    );
  }
}

/// Cards stacked with the standard gap.
class _Stack extends StatelessWidget {
  const _Stack(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: CruSpace.cardGap),
          children[i],
        ],
      ],
    );
  }
}

/// One line inside a card: label + detail on the left, an action right.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.title,
    required this.action,
    this.detail,
    this.leading,
  });

  final String title;
  final String? detail;
  final Widget? leading;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: CruSpace.s12)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: CruType.callout.tint(c.label)),
              if (detail != null) ...[
                const SizedBox(height: CruSpace.s2),
                Text(detail!, style: CruType.caption.tabular.tint(c.label2)),
              ],
            ],
          ),
        ),
        const SizedBox(width: CruSpace.s16),
        action,
      ],
    );
  }
}

void _toast(BuildContext context, String message) {
  final c = context.cru;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, style: CruType.text.tint(c.surface)),
      backgroundColor: c.label,
      behavior: SnackBarBehavior.floating,
      shape: cruShape(CruRadius.control),
      margin: const EdgeInsets.all(CruSpace.s16),
      duration: const Duration(seconds: 3),
    ),
  );
}

/// A small token dialog: title, one paragraph, Keep / confirm.
Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final c = ctx.cru;
      return Dialog(
        backgroundColor: c.surface,
        surfaceTintColor: c.surface.withValues(alpha: 0),
        shape: cruShape(CruRadius.card),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: CruSize.dialog),
          child: Padding(
            padding: const EdgeInsets.all(CruSpace.s24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: CruType.headline.tint(c.label)),
                const SizedBox(height: CruSpace.s8),
                Text(message, style: CruType.text.tint(c.label2)),
                const SizedBox(height: CruSpace.s24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    CruButton(
                      label: 'Cancel',
                      kind: CruButtonKind.inset,
                      onPressed: () => Navigator.of(ctx).pop(false),
                    ),
                    const SizedBox(width: CruSpace.s10),
                    CruButton(
                      label: confirmLabel,
                      onPressed: () => Navigator.of(ctx).pop(true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return result ?? false;
}

// =============================================================================
// PROFILE
// =============================================================================

class _ProfileSection extends ConsumerStatefulWidget {
  const _ProfileSection({required this.user, required this.profile});

  final User? user;
  final Map<String, dynamic>? profile;

  @override
  ConsumerState<_ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends ConsumerState<_ProfileSection> {
  Future<void> _sendPasswordReset(String email) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) _toast(context, 'Password reset link sent to $email.');
    } catch (e) {
      if (mounted) _toast(context, 'Could not send the reset link: $e');
    }
  }

  Future<void> _signOut() async {
    final ok = await _confirm(
      context,
      title: 'Sign out of CruDoc?',
      message: 'You will need to sign in again on this computer.',
      confirmLabel: 'Sign out',
    );
    if (!ok) return;
    try {
      await AuthService().signOut();
    } catch (_) {}
    if (mounted) context.go('/auth');
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final specialty = ref.watch(activeDoctorSpecialtyProvider).value;
    final providers =
        user?.providerData.map((p) => p.providerId).toSet() ?? const {};
    final signIn = providers.contains('google.com')
        ? 'Google'
        : providers.contains('phone')
        ? 'phone number'
        : 'email and password';
    final email = user?.email;
    final canResetPassword =
        providers.contains('password') && email != null && email.isNotEmpty;

    return _Stack([
      const DoctorLoyaltyCard(),
      _SettingsCard(
        title: 'Specialty',
        description: specialty == null
            ? 'Quick actions, templates and prescription formats follow your specialty.'
            : 'Quick actions, templates and prescription formats are set up for ${specialty.label}.',
        child: _ActionRow(
          title: specialty?.label ?? 'Loading…',
          detail: specialty?.tagline,
          action: CruButton(
            label: 'Switch specialty',
            kind: CruButtonKind.secondary,
            // The switcher predates the tokens: open it on the app's Day theme.
            onPressed: () => showSpecialtySwitcherDialog(
              Navigator.of(context, rootNavigator: true).context,
            ),
          ),
        ),
      ),
      const CrudocIdCard(),
      _SettingsCard(
        title: 'Sign-in',
        description: 'You sign in with your $signIn.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (canResetPassword) ...[
              _ActionRow(
                title: 'Password',
                detail: 'We email a link to $email to set a new one.',
                action: CruCapsuleButton(
                  label: 'Send reset link',
                  kind: CruCapsuleKind.surface,
                  height: CruSize.control,
                  onPressed: () => _sendPasswordReset(email),
                ),
              ),
              const SizedBox(height: CruSpace.s16),
              const CruSeparator(),
              const SizedBox(height: CruSpace.s16),
            ],
            _ActionRow(
              title: 'Sign out',
              detail: 'Ends your session on this computer.',
              action: CruButton(
                label: 'Sign out',
                kind: CruButtonKind.inset,
                icon: CruIcons.logout,
                onPressed: _signOut,
              ),
            ),
          ],
        ),
      ),
    ]);
  }
}

// =============================================================================
// PLAN & BILLING
// =============================================================================

class _PlanSection extends StatefulWidget {
  const _PlanSection();

  @override
  State<_PlanSection> createState() => _PlanSectionState();
}

class _PlanSectionState extends State<_PlanSection> {
  final _service = DoctorSubscriptionService();
  bool _busy = false;

  Future<void> _cancelSubscription(DateTime? expiresDate) async {
    final expiry = expiresDate != null
        ? DateFormat('d MMM y').format(expiresDate)
        : 'the end of your billing cycle';
    final ok = await _confirm(
      context,
      title: 'Cancel subscription?',
      message:
          'Your plan stays on until $expiry. After that, paid features turn off and we won\'t remind you to renew.',
      confirmLabel: 'Cancel subscription',
    );
    if (!ok) return;

    setState(() => _busy = true);
    try {
      await _service.setCancelled(true);
      if (mounted) _toast(context, 'Subscription cancelled.');
    } catch (e) {
      if (mounted) _toast(context, 'Could not cancel subscription: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resumeSubscription() async {
    setState(() => _busy = true);
    try {
      await _service.setCancelled(false);
      if (mounted) _toast(context, 'Subscription resumed.');
    } catch (e) {
      if (mounted) _toast(context, 'Could not resume subscription: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DoctorSubscriptionInfo>(
      stream: _service.watchSubscriptionInfo(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        if (info == null) {
          return const SizedBox.shrink();
        }

        final expiry = info.expiresDate != null
            ? DateFormat('d MMM y').format(info.expiresDate!)
            : null;
        final isCancelled = info.isCancelled;
        final isActive = info.doctorStatus.toLowerCase() == 'active';

        return _Stack([
          _SettingsCard(
            title: 'Plan & billing',
            description: 'Your subscription status and billing settings.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ActionRow(
                  title: 'Plan',
                  detail: info.planName,
                  action: const SizedBox.shrink(),
                ),
                if (info.doctorStatus.isNotEmpty) ...[
                  const SizedBox(height: CruSpace.s12),
                  _ActionRow(
                    title: 'Status',
                    detail: isCancelled
                        ? (expiry != null
                              ? 'Cancelled · ends $expiry'
                              : 'Cancelled')
                        : info.doctorStatus,
                    action: const SizedBox.shrink(),
                  ),
                ],
                if (expiry != null && !isCancelled) ...[
                  const SizedBox(height: CruSpace.s12),
                  _ActionRow(
                    title: 'Expires',
                    detail: expiry,
                    action: const SizedBox.shrink(),
                  ),
                ],
                const SizedBox(height: CruSpace.s20),
                Wrap(
                  spacing: CruSpace.s12,
                  runSpacing: CruSpace.s12,
                  children: [
                    CruButton(
                      label: 'Choose features',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SubscriptionBillingPage(),
                        ),
                      ),
                    ),
                    if (isCancelled)
                      CruButton(
                        label: 'Resume subscription',
                        onPressed: _busy ? null : _resumeSubscription,
                      )
                    else if (isActive)
                      CruButton(
                        label: 'Cancel subscription',
                        kind: CruButtonKind.secondary,
                        onPressed: _busy
                            ? null
                            : () => _cancelSubscription(info.expiresDate),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ]);
      },
    );
  }
}





// =============================================================================
// CONNECTED ACCOUNTS
// =============================================================================

class _AccountsSection extends ConsumerWidget {
  const _AccountsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final gmail = ref.watch(gmailConnectionProvider);
    final notifier = ref.read(gmailConnectionProvider.notifier);
    final email = gmail.value;

    final Widget action;
    final String detail;
    if (gmail.isLoading) {
      detail = 'Checking…';
      action = SizedBox.square(
        dimension: CruSpace.s20,
        child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
      );
    } else if (email != null) {
      detail = 'Connected as $email';
      action = CruButton(
        label: 'Disconnect',
        kind: CruButtonKind.inset,
        onPressed: notifier.disconnect,
      );
    } else {
      detail = gmail.hasError
          ? 'Could not connect. Try again.'
          : 'Not connected';
      action = CruButton(
        label: 'Connect Gmail',
        kind: CruButtonKind.secondary,
        onPressed: notifier.connect,
      );
    }

    return _Stack([
      _SettingsCard(
        title: 'Gmail',
        description:
            'Email bills, prescriptions and reports to patients from your own address.',
        child: _ActionRow(
          leading: const CruIconTile(
            icon: CruIcons.arrowUpRight,
            tone: CruTileTone.neutral,
          ),
          title: email != null ? 'Connected' : 'Gmail',
          detail: detail,
          action: action,
        ),
      ),
    ]);
  }
}

// =============================================================================
// DEVICES
// =============================================================================

class _DevicesSection extends StatelessWidget {
  const _DevicesSection({required this.user});

  final User? user;

  Future<void> _revoke(BuildContext context, DeviceSession s) async {
    final ok = await _confirm(
      context,
      title: 'Sign out ${s.deviceName}?',
      message: 'CruDoc on that device signs out straight away.',
      confirmLabel: 'Sign out',
    );
    if (!ok) return;
    try {
      await DeviceSessionService.instance.revokeSession(
        s.doctorId,
        s.sessionId,
      );
      if (context.mounted) _toast(context, '${s.deviceName} signed out.');
    } catch (e) {
      if (context.mounted) _toast(context, 'Could not sign it out: $e');
    }
  }

  Future<void> _revokeOthers(BuildContext context, String doctorId) async {
    final ok = await _confirm(
      context,
      title: 'Sign out every other device?',
      message: 'Only this computer stays signed in.',
      confirmLabel: 'Sign out others',
    );
    if (!ok) return;
    try {
      await DeviceSessionService.instance.revokeAllOtherSessions(doctorId);
      if (context.mounted) _toast(context, 'Other devices signed out.');
    } catch (e) {
      if (context.mounted) _toast(context, 'Could not sign them out: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final uid = user?.uid;
    if (uid == null) {
      return const _SettingsCard(title: 'Devices', child: SizedBox.shrink());
    }
    return StreamBuilder<List<DeviceSession>>(
      stream: DeviceSessionService.instance.watchActiveSessions(uid),
      builder: (context, snapshot) {
        final sessions =
            (snapshot.data ?? const <DeviceSession>[])
                .where((s) => s.isActive)
                .toList()
              ..sort((a, b) {
                if (a.isCurrentDevice != b.isCurrentDevice) {
                  return a.isCurrentDevice ? -1 : 1;
                }
                return b.lastActiveAt.compareTo(a.lastActiveAt);
              });
        final others = sessions.where((s) => !s.isCurrentDevice).length;

        final card = _SettingsCard(
          title: 'Signed-in devices',
          description: 'Where CruDoc is signed in to your account right now.',
          trailing: others > 0
              ? CruButton(
                  label: 'Sign out others',
                  kind: CruButtonKind.inset,
                  onPressed: () => _revokeOthers(context, uid),
                )
              : null,
          child:
              snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData
              ? Text('Loading…', style: CruType.text.tint(c.label2))
              : snapshot.hasError
              ? Text(
                  'Could not load devices.',
                  style: CruType.text.tint(c.label2),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < sessions.length; i++) ...[
                      if (i > 0)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: CruSpace.s12),
                          child: CruSeparator(
                            indent: CruSize.attentionTextInset - CruSpace.s12,
                          ),
                        ),
                      _DeviceRow(
                        session: sessions[i],
                        onRevoke: () => _revoke(context, sessions[i]),
                      ),
                    ],
                  ],
                ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            card,
            const SizedBox(height: CruSpace.s20),
            const NearbySharingSettingsCard(),
          ],
        );
      },
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.session, required this.onRevoke});

  final DeviceSession session;
  final VoidCallback onRevoke;

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 2) return 'active now';
    if (d.inHours < 1) return 'active ${d.inMinutes} min ago';
    if (d.inDays < 1) return 'active ${d.inHours} h ago';
    return 'last active ${DateFormat('d MMM').format(t)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final s = session;
    return _ActionRow(
      leading: CruIconTile(
        icon:
            s.platform.toLowerCase().contains('android') ||
                s.platform.toLowerCase().contains('ios')
            ? CruIcons.phone
            : CruIcons.sidebar,
        tone: s.isCurrentDevice ? CruTileTone.accent : CruTileTone.neutral,
      ),
      title: s.deviceName,
      detail: [
        s.platform,
        if (s.appVersion != null && s.appVersion!.isNotEmpty)
          'v${s.appVersion}',
        _ago(s.lastActiveAt),
      ].join(' · '),
      action: s.isCurrentDevice
          ? CruPill(
              text: cruIsPhone(context) ? 'This phone' : 'This computer',
              background: c.accentTint,
              foreground: c.accentText,
            )
          : CruCapsuleButton(label: 'Sign out', onPressed: onRevoke),
    );
  }
}

// =============================================================================
// APPEARANCE
// =============================================================================

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  static String _explain(AppearanceMode m) => switch (m) {
    AppearanceMode.auto =>
      'Light during the day, dark from ${_hour(kEveningSessionStartHour)} '
          'to ${_hour(kDaySessionStartHour)}.',
    AppearanceMode.day => 'Always light.',
    AppearanceMode.evening => 'Always dark.',
  };

  /// 17 → "5 PM".
  static String _hour(int h) =>
      DateFormat('h a').format(DateTime(2000, 1, 1, h));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final mode = ref.watch(appearanceModeProvider);
    final textSize = ref.watch(textSizePreferenceProvider);
    return _Stack([
      _SettingsCard(
        title: 'Appearance',
        description:
            'Evening is a dark palette that is easier on the eyes after hours.',
        child: Row(
          children: [
            CruSegmentedControl<AppearanceMode>(
              semanticLabel: 'Appearance',
              segments: [
                for (final m in AppearanceMode.values) CruSegment(m, m.label),
              ],
              selected: mode,
              onChanged: ref.read(appearanceModeProvider.notifier).select,
            ),
            const SizedBox(width: CruSpace.s16),
            Expanded(
              child: Text(
                _explain(mode),
                style: CruType.caption.tint(c.label2),
              ),
            ),
          ],
        ),
      ),
      _SettingsCard(
        title: 'Text size',
        description: 'Choose a text size used throughout CruDoc.',
        child: Row(
          children: [
            CruSegmentedControl<TextSizePreference>(
              semanticLabel: 'Text size',
              segments: [
                for (final size in TextSizePreference.values)
                  CruSegment(size, size.label),
              ],
              selected: textSize,
              onChanged: ref.read(textSizePreferenceProvider.notifier).select,
            ),
          ],
        ),
      ),
      _SettingsCard(
        title: 'Day background',
        description:
            'Choose a preset or enter a custom hex color. Evening mode stays unchanged.',
        child: const _DayBackgroundColorControl(),
      ),
    ]);
  }
}

class _DayBackgroundColorControl extends ConsumerStatefulWidget {
  const _DayBackgroundColorControl();

  @override
  ConsumerState<_DayBackgroundColorControl> createState() =>
      _DayBackgroundColorControlState();
}

class _DayBackgroundColorControlState
    extends ConsumerState<_DayBackgroundColorControl> {
  static const _presets = [
    (label: 'Current', value: 0xFFEEF1F6),
    (label: 'Reference', value: 0xFFF1F8FC),
  ];

  late final TextEditingController _hexController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _hexController = TextEditingController(
      text: _formatColor(AppearancePreferences.defaultDayBackgroundColor),
    );
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  static String _formatColor(int argb) =>
      '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  void _selectColor(int argb) {
    _hexController.text = _formatColor(argb);
    setState(() => _error = null);
    ref.read(dayBackgroundColorProvider.notifier).select(argb);
  }

  void _applyCustomColor() {
    final entered = _hexController.text.trim();
    final hex = entered.startsWith('#') ? entered.substring(1) : entered;
    if (!RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(hex)) {
      setState(() => _error = 'Enter a six-digit hex color, such as #EEF1F6.');
      return;
    }
    _selectColor(0xFF000000 | int.parse(hex, radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final selectedColor = ref.watch(dayBackgroundColorProvider);
    ref.listen(dayBackgroundColorProvider, (previous, next) {
      if (previous == next) return;
      _hexController.text = _formatColor(next);
      if (_error != null) setState(() => _error = null);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: CruSpace.s16,
          runSpacing: CruSpace.s12,
          children: [
            for (final preset in _presets)
              _BackgroundColorSwatch(
                label: preset.label,
                color: preset.value,
                selected: selectedColor == preset.value,
                onTap: () => _selectColor(preset.value),
              ),
          ],
        ),
        const SizedBox(height: CruSpace.s20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: CruTextField(
                label: 'Custom hex color',
                controller: _hexController,
                hint: '#EEF1F6',
                keyboardType: TextInputType.text,
                textCapitalization: TextCapitalization.characters,
                onSubmitted: (_) => _applyCustomColor(),
              ),
            ),
            const SizedBox(width: CruSpace.s10),
            Padding(
              padding: const EdgeInsets.only(top: 22),
              child: CruButton(label: 'Apply', onPressed: _applyCustomColor),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: CruSpace.s6),
          Text(_error!, style: CruType.caption.tint(c.redText)),
        ],
      ],
    );
  }
}

class _BackgroundColorSwatch extends StatelessWidget {
  const _BackgroundColorSwatch({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CruRadius.control),
      child: Padding(
        padding: const EdgeInsets.all(CruSpace.s2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 104,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Color(color),
                borderRadius: BorderRadius.circular(CruRadius.control),
                border: Border.all(
                  color: selected ? c.accent : c.cardBorder,
                  width: selected ? 2 : 1,
                ),
              ),
              child: selected
                  ? CruIcon(CruIcons.check, size: 16, color: c.accent)
                  : null,
            ),
            const SizedBox(height: CruSpace.s6),
            Text(label, style: CruType.caption.w600.tint(c.label)),
            Text(
              _DayBackgroundColorControlState._formatColor(color),
              style: CruType.micro.tabular.tint(c.label3),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// DENTAL
// =============================================================================

/// Dental-only settings. F3, P and PD add their own cards to this _Stack.
/// Opens a dental set-up page: in the desktop shell (with a link back to
/// Settings), or pushed on the phone.
void _openDentalPage(BuildContext context, WidgetRef ref, int tab) {
  final navigate = ref.read(shellNavigatorProvider);
  if (navigate != null && navigate(tab)) return;
  openMobileDestination(context, tab, backLabel: 'Dental');
}

class _DentalSection extends ConsumerWidget {
  const _DentalSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final dentalFeatures = ref.watch(dentalFeaturesProvider);
    final numbering =
        ref.watch(toothNumberingProvider).value ?? ToothNumbering.fdi;
    final large = ref.watch(largeModeProvider).value ?? false;
    final tabs = {
      for (final t in sidebarTabs(
        dental: dentalFeatures,
        access: ref.watch(clinicAccessProvider).value,
      ))
        t.tab,
    };
    return _Stack([
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Your dental work', style: CruType.headline.tint(c.label)),
          const SizedBox(height: CruSpace.s12),
          DentalFeaturesPicker(
            selected: dentalFeatures,
            onChanged: (features) => saveDentalFeatures(features),
          ),
        ],
      ),
      // Set up once, so they live here rather than in the sidebar.
      if (tabs.contains(DesktopTab.procedures))
        _SettingsCard(
          title: 'Procedures & fees',
          description:
              'What can be picked when logging a procedure or planning '
              'treatment, and what each costs.',
          trailing: CruButton(
            label: 'Open',
            kind: CruButtonKind.secondary,
            onPressed: () => _openDentalPage(context, ref, DesktopTab.procedures),
          ),
          child: const SizedBox.shrink(),
        ),
      if (tabs.contains(DesktopTab.oralMedForms))
        _SettingsCard(
          title: 'Form templates',
          description:
              'Questionnaires to fill for a patient from their record '
              '(Forms in the dental record).',
          trailing: CruButton(
            label: 'Open',
            kind: CruButtonKind.secondary,
            onPressed: () =>
                _openDentalPage(context, ref, DesktopTab.oralMedForms),
          ),
          child: const SizedBox.shrink(),
        ),
      _SettingsCard(
        title: 'Tooth numbering',
        description:
            'FDI is the two-digit system the clinic records in: 18–11, '
            '21–28, 38–31, 41–48 (55–51 … for milk teeth). Universal runs '
            '1–32 for permanent teeth and A–T for milk teeth.',
        child: Row(
          children: [
            CruSegmentedControl<ToothNumbering>(
              semanticLabel: 'Tooth numbering',
              segments: [
                for (final n in ToothNumbering.values) CruSegment(n, n.label),
              ],
              selected: numbering,
              onChanged: (n) => setToothNumbering(ref, n),
            ),
            const SizedBox(width: CruSpace.s16),
            Expanded(
              child: Text(
                numbering == ToothNumbering.fdi
                    ? 'Charts, plans and reports show FDI numbers.'
                    : 'Charts, plans and reports show Universal numbers '
                          '(1–32) and letters (A–T).',
                style: CruType.caption.tint(c.label2),
              ),
            ),
          ],
        ),
      ),
      _SettingsCard(
        title: 'Larger text and icons (chairside)',
        description:
            'Enlarges the dentist work area for chairside viewing. The '
            'Appearance text-size setting still applies across all specialties.',
        child: Row(
          children: [
            CruSegmentedControl<bool>(
              semanticLabel: 'Larger text and icons',
              segments: const [
                CruSegment(false, 'Off'),
                CruSegment(true, 'On'),
              ],
              selected: large,
              onChanged: (value) => setLargeMode(ref, value),
            ),
          ],
        ),
      ),
    ]);
  }
}

// =============================================================================
// PATIENT REMINDERS
// =============================================================================

/// The clinic's one control over WhatsApp reminders.
///
/// Deliberately a single switch. Reminders go out the evening before every
/// appointment without anybody choosing to send them, so the only decision a
/// clinic has to make is whether they want them at all.
class _RemindersSection extends ConsumerWidget {
  const _RemindersSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final enabled = ref.watch(whatsAppRemindersEnabledProvider);

    return _Stack([
      _SettingsCard(
        title: 'WhatsApp appointment reminders',
        description:
            'Patients get one WhatsApp message the evening before their '
            'appointment, with the date, the time and your number to call if '
            'they need to change it. Nothing to send by hand, and nothing '
            'about their treatment is included.',
        child: Row(
          children: [
            CruSegmentedControl<bool>(
              semanticLabel: 'WhatsApp appointment reminders',
              segments: const [
                CruSegment(false, 'Off'),
                CruSegment(true, 'On'),
              ],
              selected: enabled,
              onChanged: (value) => setWhatsAppRemindersEnabled(value),
            ),
            const SizedBox(width: CruSpace.s16),
            Expanded(
              child: Text(
                enabled
                    ? 'Sent at 6:00 pm the day before, from the CruDoc number.'
                    : 'No reminders are being sent. Patients will only hear '
                          'from you directly.',
                style: CruType.caption.tint(c.label2),
              ),
            ),
          ],
        ),
      ),
      _SettingsCard(
        title: 'If a patient opts out',
        description:
            'Every reminder tells the patient they can reply STOP, and that '
            'stops them immediately. A patient who opts out stays opted out '
            'until they reply START, and you will see "Skipped" against their '
            'appointment rather than a message that never arrived.',
        child: const SizedBox.shrink(),
      ),
    ]);
  }
}

// =============================================================================
// ABOUT
// =============================================================================

class _AboutSection extends ConsumerStatefulWidget {
  const _AboutSection();

  @override
  ConsumerState<_AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends ConsumerState<_AboutSection> {
  String? _version;
  String? _device;
  bool _checking = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final version = await DeviceInfoHelper.getAppVersion();
    final device = await DeviceInfoHelper.getDeviceDisplayName();
    if (!mounted) return;
    setState(() {
      _version = version;
      _device = device;
    });
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _status = null;
    });
    try {
      await ref
          .read(updateControllerProvider.notifier)
          .checkForUpdate(force: true);
      final result = ref.read(updateControllerProvider).checkResult;
      if (!mounted) return;
      setState(() {
        _status = switch (result) {
          UpToDate() => 'You have the latest version.',
          UpdateAvailable(:final release) =>
            'Version ${release.version} is available.',
          CheckFailed(:final reason) => 'Could not check: $reason',
          _ => 'Checked.',
        };
      });
    } catch (e) {
      if (mounted) setState(() => _status = 'Could not check: $e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Stack([
      _SettingsCard(
        title: 'CruDoc',
        description: [
          if (_version != null) 'Version $_version',
          ?_device,
        ].join(' · '),
        child: _ActionRow(
          title: 'Updates',
          detail: _status ?? 'See whether a newer version is out.',
          action: CruButton(
            label: _checking ? 'Checking…' : 'Check for updates',
            kind: CruButtonKind.secondary,
            onPressed: _checking ? null : _check,
          ),
        ),
      ),
      _SettingsCard(
        title: 'Guided tour',
        child: _ActionRow(
          leading: const CruIconTile(
            icon: CruIcons.help,
            tone: CruTileTone.neutral,
          ),
          title: 'Take the tour again',
          detail: 'A 1-minute look at the essentials, from the Dashboard.',
          action: CruButton(
            label: 'Start tour',
            kind: CruButtonKind.secondary,
            // Opens the Dashboard and starts from the first card.
            onPressed: () => ref
                .read(tutorialControllerProvider.notifier)
                .requestReplay(TutorialPlatform.desktop),
          ),
        ),
      ),
      _SettingsCard(
        title: 'Voice tour',
        child: _ActionRow(
          leading: const CruIconTile(
            icon: CruIcons.mic,
            tone: CruTileTone.neutral,
          ),
          title: 'Learn to use voice',
          detail: 'Hold Space to talk, hands-free, and filling forms by voice.',
          action: CruButton(
            label: 'Start tour',
            kind: CruButtonKind.secondary,
            onPressed: () => ref
                .read(tutorialControllerProvider.notifier)
                .requestReplay(
                  TutorialPlatform.desktop,
                  tour: TutorialTour.voice,
                ),
          ),
        ),
      ),
    ]);
  }
}
