import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/core/legal_links.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

class LegalLinksRow extends StatelessWidget {
  const LegalLinksRow({super.key});

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPrivacy = kPrivacyPolicyUrl.trim().isNotEmpty;
    final hasTerms = kTermsUrl.trim().isNotEmpty;
    if (!hasPrivacy && !hasTerms) return const SizedBox.shrink();

    final c = context.cru;
    final style = CruType.caption.tint(c.label3);

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: CruSpace.s12,
      children: [
        if (hasPrivacy)
          CruPressable(
            onTap: () => _open(kPrivacyPolicyUrl),
            scaleOnPress: false,
            semanticLabel: 'Privacy policy',
            builder: (context, hovered) => Text(
              'Privacy policy',
              style: hovered ? style.tint(c.label) : style,
            ),
          ),
        if (hasPrivacy && hasTerms) Text('·', style: style),
        if (hasTerms)
          CruPressable(
            onTap: () => _open(kTermsUrl),
            scaleOnPress: false,
            semanticLabel: 'Terms',
            builder: (context, hovered) =>
                Text('Terms', style: hovered ? style.tint(c.label) : style),
          ),
      ],
    );
  }
}
