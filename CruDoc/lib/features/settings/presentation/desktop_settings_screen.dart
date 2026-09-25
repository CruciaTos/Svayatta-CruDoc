import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/dental/domain/tooth_numbering.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_icons.dart';
import 'package:doctor_management_app/features/dental/specialties/pedo/large_mode.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_settings_section.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/core/models/device_session.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/core/services/auth_service.dart';
import 'package:doctor_management_app/core/services/device_session_service.dart';
import 'package:doctor_management_app/core/update/models/update_check_result.dart';
import 'package:doctor_management_app/core/utils/device_info_helper.dart';
import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_models.dart';
import 'package:doctor_management_app/features/messaging/data/providers/gmail_auth_providers.dart';
import 'package:doctor_management_app/features/settings/data/appearance_preferences.dart';
import 'package:doctor_management_app/features/settings/data/appearance_provider.dart';
import 'package:doctor_management_app/features/shell/components/specialty_switcher_dialog.dart';
import 'package:doctor_management_app/features/update/controllers/update_controller.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The Settings sections, in sidebar order. Every entry does something
/// real: nothing here is a placeholder switch.
enum SettingsSection {
  profile('Profile', CruIcons.user),
  clinic('Clinic & letterhead', CruIcons.pen),
  accounts('Connected accounts', CruIcons.arrowUpRight),
  devices('Devices', CruIcons.sidebar),
  appearance('Appearance', CruIcons.sun),

  /// Dentists and dental specialists only.
  dental('Dental', DentalIcons.tooth),

  /// Oral & Maxillofacial Radiologists only.
  radiology('Radiology', RadIcons.xray),
  about('About CruDoc', CruIcons.help);

  const SettingsSection(this.label, this.icon);
  final String label;
  final CruIconData icon;
}

/// The open section. The account menu sets it ("Profile" opens Profile).
final settingsSectionProvider = StateProvider<SettingsSection>(
  (ref) => SettingsSection.profile,
);

/// Width of the section list.
const double _kNavWidth = 248;

/// Section content never gets wider than this, so fields stay readable.
const double _kContentMaxWidth = 760;

/// Profile avatar on the identity card.
const double _kProfileMonogram = 64;

/// Letterhead preview: a sheet of paper, always on the Day palette.
const double _kPreviewMinHeight = 260;

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
            style: CruType.text.tint(c.label2),
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
                  child: _SectionList(
                    sections: [
                      for (final s in SettingsSection.values)
                        if ((s != SettingsSection.radiology ||
                                ref.watch(isOralRadiologistProvider)) &&
                            (s != SettingsSection.dental ||
                                ref.watch(isDentistProvider)))
                          s,
                    ],
                    selected: section,
                    onSelect: (s) =>
                        ref.read(settingsSectionProvider.notifier).state = s,
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
                            child: switch (section) {
                              SettingsSection.profile => _ProfileSection(
                                user: user,
                                profile: profile,
                              ),
                              SettingsSection.clinic => _ClinicSection(
                                user: user,
                                profile: profile,
                              ),
                              SettingsSection.accounts =>
                                const _AccountsSection(),
                              SettingsSection.devices => _DevicesSection(
                                user: user,
                              ),
                              SettingsSection.appearance =>
                                const _AppearanceSection(),
                              SettingsSection.dental => const _DentalSection(),
                              SettingsSection.radiology =>
                                const RadSettingsSection(),
                              SettingsSection.about => const _AboutSection(),
                            },
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
  final _name = TextEditingController();
  bool _nameLoaded = false;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadName();
  }

  @override
  void didUpdateWidget(_ProfileSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadName();
  }

  /// Fills the field once the profile arrives; never overwrites typing.
  void _loadName() {
    if (_nameLoaded || widget.profile == null) return;
    _nameLoaded = true;
    _name.text =
        DoctorProfileHelper.tryFormatDoctorName(widget.user, widget.profile) ??
        '';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _toast(context, 'Enter your name first.');
      return;
    }
    setState(() => _saving = true);
    try {
      await DoctorProfileHelper.updateProfile(
        doctorName: name,
        specialty: DoctorProfileHelper.formatSpecialty(
          widget.profile,
          widget.user,
        ),
      );
      if (mounted) _toast(context, 'Name saved.');
    } catch (e) {
      if (mounted) _toast(context, 'Could not save your name: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

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
    final c = context.cru;
    final user = widget.user;
    final name = DoctorProfileHelper.formatDoctorName(user, widget.profile);
    final clinic = DoctorProfileHelper.tryFormatClinicName(
      user,
      widget.profile,
    );
    final specialty = ref.watch(activeDoctorSpecialtyProvider).value;
    final providers =
        user?.providerData.map((p) => p.providerId).toSet() ?? const {};
    final signIn = providers.contains('google.com')
        ? 'Google'
        : providers.contains('phone')
        ? 'phone number'
        : 'email and password';
    final email = user?.email;
    final phone = user?.phoneNumber;
    final canResetPassword =
        providers.contains('password') && email != null && email.isNotEmpty;

    return _Stack([
      CruCard(
        semanticLabel: 'Your profile',
        child: Row(
          children: [
            CruMonogram(name: name, size: _kProfileMonogram),
            const SizedBox(width: CruSpace.s20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: CruType.title.tint(c.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: CruSpace.s4),
                  Text(
                    [
                      if (specialty != null) specialty.label,
                      ?clinic,
                    ].join(' · '),
                    style: CruType.text.tint(c.label2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: CruSpace.s12),
                  Wrap(
                    spacing: CruSpace.s8,
                    runSpacing: CruSpace.s8,
                    children: [
                      if (email != null && email.isNotEmpty)
                        CruInfoPill(
                          text: email,
                          tone: CruInfoPillTone.outlined,
                        ),
                      if (phone != null && phone.isNotEmpty)
                        CruInfoPill(
                          text: phone,
                          icon: CruIcons.phone,
                          tone: CruInfoPillTone.outlined,
                          tabular: true,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      _SettingsCard(
        title: 'Your name',
        description: 'Shown on the dashboard, prescriptions and bills.',
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: CruTextField(
                label: 'Full name',
                controller: _name,
                hint: 'Dr. Ananya Deshpande',
                textCapitalization: TextCapitalization.words,
                onSubmitted: (_) => _saveName(),
              ),
            ),
            const SizedBox(width: CruSpace.s12),
            CruButton(
              label: _saving ? 'Saving…' : 'Save',
              large: true,
              onPressed: _saving ? null : _saveName,
            ),
          ],
        ),
      ),
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
// CLINIC & LETTERHEAD
// =============================================================================

class _ClinicSection extends StatefulWidget {
  const _ClinicSection({required this.user, required this.profile});

  final User? user;
  final Map<String, dynamic>? profile;

  @override
  State<_ClinicSection> createState() => _ClinicSectionState();
}

class _ClinicSectionState extends State<_ClinicSection> {
  final _clinicName = TextEditingController();
  final _tagline = TextEditingController();
  final _qualifications = TextEditingController();
  final _registration = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _footer = TextEditingController();
  bool _loaded = false;
  bool _saving = false;

  List<TextEditingController> get _all => [
    _clinicName,
    _tagline,
    _qualifications,
    _registration,
    _phone,
    _email,
    _address,
    _footer,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_ClinicSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  /// Fills the form once the profile arrives; never overwrites typing.
  void _load() {
    final d = widget.profile;
    if (_loaded || d == null) return;
    _loaded = true;
    String read(List<String> keys, [String? fallback]) {
      for (final k in keys) {
        final v = d[k];
        if (v is String && v.trim().isNotEmpty) return v;
      }
      return fallback ?? '';
    }

    _clinicName.text = read(['clinicName', 'practiceName']);
    _tagline.text = read(['letterheadTagline']);
    _qualifications.text = read(['qualifications', 'doctorQualifications']);
    _registration.text = read([
      'registrationNumber',
      'doctorRegistrationNumber',
    ]);
    _phone.text = read(['clinicPhone'], widget.user?.phoneNumber);
    _email.text = read(['clinicEmail'], widget.user?.email);
    _address.text = read(['clinicAddress']);
    _footer.text = read(['letterheadFooterDisclaimer']);
  }

  @override
  void dispose() {
    for (final t in _all) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await DoctorProfileHelper.updateLetterheadBranding(
        clinicName: _clinicName.text,
        doctorQualifications: _qualifications.text,
        registrationNumber: _registration.text,
        clinicAddress: _address.text,
        clinicPhone: _phone.text,
        clinicEmail: _email.text,
        tagline: _tagline.text,
        footerDisclaimer: _footer.text,
      );
      if (mounted) _toast(context, 'Clinic details and letterhead saved.');
    } catch (e) {
      if (mounted) _toast(context, 'Could not save the letterhead: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doctor = DoctorProfileHelper.formatDoctorName(
      widget.user,
      widget.profile,
    );
    return _Stack([
      _SettingsCard(
        title: 'Letterhead preview',
        description: 'The top and bottom of every prescription and bill.',
        child: ListenableBuilder(
          listenable: Listenable.merge(_all),
          builder: (context, _) => _LetterheadPreview(
            doctor: doctor,
            clinicName: _clinicName.text,
            tagline: _tagline.text,
            qualifications: _qualifications.text,
            registration: _registration.text,
            phone: _phone.text,
            email: _email.text,
            address: _address.text,
            footer: _footer.text,
          ),
        ),
      ),
      _SettingsCard(
        title: 'Clinic details',
        trailing: CruButton(
          label: _saving ? 'Saving…' : 'Save',
          onPressed: _saving ? null : _save,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CruFieldRow(
              children: [
                CruTextField(
                  label: 'Clinic name',
                  controller: _clinicName,
                  hint: 'Sanjeevani Clinic',
                  textCapitalization: TextCapitalization.words,
                ),
                CruTextField(
                  label: 'Tagline',
                  controller: _tagline,
                  optional: true,
                  hint: 'Family medicine and diabetes care',
                ),
              ],
            ),
            const SizedBox(height: CruSpace.s16),
            CruFieldRow(
              children: [
                CruTextField(
                  label: 'Qualifications',
                  controller: _qualifications,
                  hint: 'MBBS, MD (Medicine)',
                ),
                CruTextField(
                  label: 'Registration number',
                  controller: _registration,
                  hint: 'MMC 2014/05/1234',
                ),
              ],
            ),
            const SizedBox(height: CruSpace.s16),
            CruFieldRow(
              children: [
                CruTextField(
                  label: 'Clinic phone',
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  tabular: true,
                ),
                CruTextField(
                  label: 'Clinic email',
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                ),
              ],
            ),
            const SizedBox(height: CruSpace.s16),
            CruTextField(
              label: 'Address',
              controller: _address,
              maxLines: 2,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: CruSpace.s16),
            CruTextField(
              label: 'Footer note',
              controller: _footer,
              optional: true,
              maxLines: 2,
              help: 'Printed at the bottom of every document.',
            ),
          ],
        ),
      ),
    ]);
  }
}

/// A sheet of paper: always the Day palette, whatever the appearance,
/// because that is what prints.
class _LetterheadPreview extends StatelessWidget {
  const _LetterheadPreview({
    required this.doctor,
    required this.clinicName,
    required this.tagline,
    required this.qualifications,
    required this.registration,
    required this.phone,
    required this.email,
    required this.address,
    required this.footer,
  });

  final String doctor;
  final String clinicName;
  final String tagline;
  final String qualifications;
  final String registration;
  final String phone;
  final String email;
  final String address;
  final String footer;

  @override
  Widget build(BuildContext context) {
    const p = CruColors.day;
    final c = context.cru;
    String? clean(String s) => s.trim().isEmpty ? null : s.trim();
    final credentials = [
      ?clean(qualifications),
      if (clean(registration) != null) 'Reg. no. ${registration.trim()}',
    ].join(' · ');
    final contact = [?clean(phone), ?clean(email)].join(' · ');

    return Container(
      constraints: const BoxConstraints(minHeight: _kPreviewMinHeight),
      padding: const EdgeInsets.all(CruSpace.s24),
      decoration: ShapeDecoration(
        color: p.surface,
        shape: cruShape(CruRadius.control, side: BorderSide(color: c.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clean(clinicName) ?? 'Your clinic name',
                      style: CruType.title2.tint(
                        clean(clinicName) == null ? p.label3 : p.label,
                      ),
                    ),
                    if (clean(tagline) != null)
                      Text(
                        tagline.trim(),
                        style: CruType.caption.tint(p.label2),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: CruSpace.s16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(doctor, style: CruType.callout.tint(p.label)),
                  if (credentials.isNotEmpty)
                    Text(credentials, style: CruType.caption.tint(p.label2)),
                ],
              ),
            ],
          ),
          if (clean(address) != null || contact.isNotEmpty) ...[
            const SizedBox(height: CruSpace.s8),
            Text(
              [?clean(address), if (contact.isNotEmpty) contact].join('\n'),
              style: CruType.caption.tabular.tint(p.label2),
            ),
          ],
          const SizedBox(height: CruSpace.s12),
          Container(height: 1, color: p.separator),
          const SizedBox(height: CruSpace.s24),
          // Where the prescription or bill goes.
          for (final w in const [0.7, 0.5, 0.6]) ...[
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: w,
              child: Container(
                height: CruSpace.s8,
                decoration: ShapeDecoration(
                  color: p.inset,
                  shape: const StadiumBorder(),
                ),
              ),
            ),
            const SizedBox(height: CruSpace.s12),
          ],
          const SizedBox(height: CruSpace.s12),
          Container(height: 1, color: p.separator),
          const SizedBox(height: CruSpace.s8),
          Text(
            clean(footer) ?? 'No footer note',
            style: CruType.caption.tint(
              clean(footer) == null ? p.label3 : p.label2,
            ),
          ),
        ],
      ),
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

        return _SettingsCard(
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
              text: 'This computer',
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
    ]);
  }
}

// =============================================================================
// DENTAL
// =============================================================================

/// Dental-only settings. F3, P and PD add their own cards to this _Stack.
class _DentalSection extends ConsumerWidget {
  const _DentalSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final numbering =
        ref.watch(toothNumberingProvider).value ?? ToothNumbering.fdi;
    final large = ref.watch(largeModeProvider).value ?? false;

    return _Stack([
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
            'Makes the text and icons in the main area 20% larger, for '
            'reading at the chair (for example with children). The sidebar '
            'stays as it is.',
        child: Row(
          children: [
            CruSegmentedControl<bool>(
              semanticLabel: 'Larger text and icons',
              segments: const [
                CruSegment(false, 'Off'),
                CruSegment(true, 'On'),
              ],
              selected: large,
              onChanged: (v) => setLargeMode(ref, v),
            ),
          ],
        ),
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
    ]);
  }
}
