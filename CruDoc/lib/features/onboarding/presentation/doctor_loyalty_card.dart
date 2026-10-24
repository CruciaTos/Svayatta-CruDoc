import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/core/services/demo_session_service.dart';
import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/onboarding/data/loyalty_card.dart';
import 'package:doctor_management_app/features/onboarding/presentation/loyalty_card_view.dart';
import 'package:doctor_management_app/features/profile/data/doctor_name_change_policy.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The signed-in doctor's loyalty card, ready to drop into a page: it
/// reads the card and the doctor's name itself. On the phone this is the
/// doctor's whole profile card: tapping NAME changes the name (twice in
/// 6 months), and a soft shine follows the phone's tilt.
class DoctorLoyaltyCard extends ConsumerStatefulWidget {
  const DoctorLoyaltyCard({super.key});

  @override
  ConsumerState<DoctorLoyaltyCard> createState() => _DoctorLoyaltyCardState();
}

class _DoctorLoyaltyCardState extends ConsumerState<DoctorLoyaltyCard> {
  Future<void> _editName(String? current) async {
    final profile = ref.read(doctorProfileProvider).value;
    final user = ref.read(authStateProvider).value;
    final hasName = current != null && current.trim().isNotEmpty;
    final allowance = DoctorNameChangePolicy.allowance(
      DoctorNameChangePolicy.changesOf(profile),
      DateTime.now(),
    );
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: context.cru.surface,
      constraints: const BoxConstraints(maxWidth: 480),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(CruRadius.card),
        ),
      ),
      builder: (_) => _NameSheet(
        initial: current ?? '',
        // A first name is free; changing it counts.
        allowance: hasName
            ? allowance
            : const NameChangeAllowance(
                left: DoctorNameChangePolicy.maxChanges,
              ),
        onSave: (name) => DoctorNameChangePolicy.save(
          name: name,
          profile: profile,
          user: user,
        ),
      ),
    );
  }

  bool _claiming = false;

  Future<void> _claim() async {
    if (_claiming) return;
    setState(() => _claiming = true);
    try {
      await LoyaltyService.claimFreeMonth();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Free month added to your plan.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not claim. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    var card = ref.watch(loyaltyCardProvider).value;
    final user = ref.watch(authStateProvider).value;
    if (card == null) {
      if (DemoSessionService.isDemoMode) {
        card = const LoyaltyCard(
          stamps: 3,
          stampedMonths: ['2026-08', '2026-09', '2026-10'],
        );
      } else if (user != null) {
        card = const LoyaltyCard(stamps: 1, stampedMonths: []);
      }
    }
    if (card == null) return const SizedBox.shrink();
    final profile = ref.watch(doctorProfileProvider).value;
    final name = DoctorProfileHelper.tryFormatDoctorName(user, profile);
    final editable = user != null && !DemoSessionService.isDemoMode;
    return LoyaltyCardView(
      card: card,
      holderName: name,
      holderId: user?.uid,
      photoUrl: user?.photoURL,
      shine: true,
      onEditName: editable ? () => _editName(name) : null,
      onClaim: _claiming ? null : _claim,
    );
  }
}

/// The name, with how many changes are left in this 6-month window.
class _NameSheet extends StatefulWidget {
  const _NameSheet({
    required this.initial,
    required this.allowance,
    required this.onSave,
  });

  final String initial;
  final NameChangeAllowance allowance;
  final Future<void> Function(String name) onSave;

  @override
  State<_NameSheet> createState() => _NameSheetState();
}

class _NameSheetState extends State<_NameSheet> {
  late final _name = TextEditingController(text: widget.initial);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter your name first.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(name);
      if (mounted) Navigator.of(context).pop();
    } on NameChangeLimitException catch (e) {
      setState(() {
        _saving = false;
        _error =
            'You can change your name again on '
            '${DateFormat('d MMM y').format(e.nextAt)}.';
      });
    } catch (_) {
      setState(() {
        _saving = false;
        _error = 'Could not save your name. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final a = widget.allowance;
    final note = a.allowed
        ? '${a.left} ${a.left == 1 ? 'change' : 'changes'} left in this '
              '6-month window. Your name is on prescriptions and bills.'
        : 'You can change your name twice in 6 months. Next change on '
              '${DateFormat('d MMM y').format(a.nextAt!)}.';
    return Padding(
      padding: EdgeInsets.fromLTRB(
        CruSpace.s20,
        CruSpace.s20,
        CruSpace.s20,
        CruSpace.s20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Your name', style: CruType.title.tint(c.label)),
            const SizedBox(height: CruSpace.s4),
            Text(note, style: CruType.caption.tint(c.label2)),
            const SizedBox(height: CruSpace.s16),
            CruTextField(
              label: 'Full name',
              controller: _name,
              hint: 'Dr. Ananya Deshpande',
              autofocus: a.allowed,
              textCapitalization: TextCapitalization.words,
              onSubmitted: (_) => _saving || !a.allowed ? null : _save(),
            ),
            if (_error != null) ...[
              const SizedBox(height: CruSpace.s8),
              Text(_error!, style: CruType.caption.tint(c.amberText)),
            ],
            const SizedBox(height: CruSpace.s16),
            CruButton(
              label: _saving ? 'Saving…' : 'Save',
              large: true,
              onPressed: _saving || !a.allowed ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
