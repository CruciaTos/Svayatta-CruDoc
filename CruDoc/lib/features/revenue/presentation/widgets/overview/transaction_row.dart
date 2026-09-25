import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/revenue/domain/revenue_models.dart';
import 'package:doctor_management_app/features/revenue/presentation/widgets/overview/revenue_icons.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Transaction row height (html/Revenue.dc.html). Not a token yet; see
/// NEEDS.md (Builder 4).
const double kTxnRowHeight = 56;

/// Width of the day and time column.
const double kTxnWhenWidth = 76;

/// Where row separators start: padding 12 + when 76 + gap 12 + tile 36
/// + gap 12.
const double kTxnTextInset =
    CruSpace.s12 + kTxnWhenWidth + CruSpace.s12 + CruSize.iconTile + CruSpace.s12;

/// Day and time, icon tile, payer or item with what it was for, amount.
/// The amount is green (+) for money in and red (−) for money out.
class TransactionRow extends StatelessWidget {
  const TransactionRow({super.key, required this.row, required this.onTap});

  final TxnRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruPressable(
      onTap: onTap,
      scaleOnPress: false,
      semanticLabel:
          '${row.title}, ${row.amount}, ${row.dayLabel} ${row.time} ${row.meridiem}',
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        height: kTxnRowHeight,
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
        decoration: ShapeDecoration(
          color: hovered ? c.hoverFill : c.hoverFill.withValues(alpha: 0),
          shape: cruShape(CruRadius.control),
        ),
        child: Row(
          children: [
            SizedBox(
              width: kTxnWhenWidth,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.dayLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CruType.subhead.tint(c.label2),
                  ),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: row.time,
                        style: CruType.subhead.w600.tabular.tint(c.label),
                      ),
                      TextSpan(
                        text: ' ${row.meridiem}',
                        style: CruType.micro.tint(c.label3),
                      ),
                    ]),
                    maxLines: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: CruSpace.s12),
            CruIconTile(
              icon: row.moneyOut ? RevenueIcons.receipt : CruIcons.rupee,
              tone: CruTileTone.accent,
            ),
            const SizedBox(width: CruSpace.s12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CruType.callout.tint(c.label),
                  ),
                  Text(
                    row.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CruType.subhead.tint(c.label2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: CruSpace.s12),
            Text(
              row.amount,
              style: CruType.row.tabular
                  .tint(row.moneyOut ? c.redText : c.greenText),
            ),
          ],
        ),
      ),
    );
  }
}
