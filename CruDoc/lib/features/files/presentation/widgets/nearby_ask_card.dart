import 'dart:io' show Platform;
import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/files/lan/lan_startup.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Shown at the top of the Files screen on Apple devices before local network
/// sharing has been enabled, giving doctors context before iOS shows the
/// system permission dialog.
class NearbyAskCard extends StatefulWidget {
  const NearbyAskCard({super.key});

  @override
  State<NearbyAskCard> createState() => _NearbyAskCardState();
}

class _NearbyAskCardState extends State<NearbyAskCard> {
  bool _dismissedThisSession = false;
  bool _asked = true;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    if (!(Platform.isIOS || Platform.isMacOS)) return;
    final hasAsked = await LanStartup.hasAsked();
    if (mounted) {
      setState(() => _asked = hasAsked);
    }
  }

  Future<void> _onTurnOn() async {
    await LanStartup.markAsked();
    if (mounted) {
      setState(() => _asked = true);
    }
    await LanStartup.starter?.call();
  }

  void _onNotNow() {
    setState(() => _dismissedThisSession = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!(Platform.isIOS || Platform.isMacOS)) return const SizedBox.shrink();
    if (_asked || _dismissedThisSession || LanStartup.starter == null) {
      return const SizedBox.shrink();
    }

    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.only(bottom: CruSpace.s16),
      child: CruCard(
        padding: const EdgeInsets.all(CruSpace.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CruIcon(CruIcons.sparkle, size: 20, color: c.accent),
                const SizedBox(width: CruSpace.s10),
                Expanded(
                  child: Text(
                    'Send files to colleagues on clinic Wi-Fi',
                    style: CruType.title2.tint(c.label),
                  ),
                ),
              ],
            ),
            const SizedBox(height: CruSpace.s8),
            Text(
              'CruDoc will ask to find devices on your local network. Say Allow '
              'so files can go straight between your devices without the internet. '
              'You can change this later in Settings.',
              style: CruType.text.tint(c.label2),
            ),
            const SizedBox(height: CruSpace.s16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                CruButton(
                  label: 'Not now',
                  kind: CruButtonKind.secondary,
                  onPressed: _onNotNow,
                ),
                const SizedBox(width: CruSpace.s10),
                CruButton(
                  label: 'Turn on',
                  kind: CruButtonKind.primary,
                  onPressed: _onTurnOn,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

