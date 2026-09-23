import 'package:flutter/widgets.dart';

import 'package:doctor_management_app/features/inventory/domain/inventory_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Icons the Inventory screen needs that `CruIcons` doesn't have yet
/// (requested in design/clinic-redesign/NEEDS.md, Builder 3).
abstract final class InventoryIcons {
  /// Shopping cart ("New order").
  static const cart = CruIconData(
    'M3.5 4.5h2.5l2.2 10.5h10.3l2-7.5H7',
    circles: [(9.5, 19, 1.4), (17, 19, 1.4)],
  );

  /// Bulleted list (list view toggle).
  static const list = CruIconData(
    'M9 6.5h11M9 12h11M9 17.5h11',
    circles: [(4.8, 6.5, 1.1), (4.8, 12, 1.1), (4.8, 17.5, 1.1)],
  );

  /// Four squares (grid view toggle).
  static const grid = CruIconData(
    '',
    rects: [
      (3.5, 3.5, 7, 7, 2),
      (13.5, 3.5, 7, 7, 2),
      (3.5, 13.5, 7, 7, 2),
      (13.5, 13.5, 7, 7, 2),
    ],
  );

  /// A capsule tilted 45° with its seam (tablets, capsules, strips).
  static const pill = CruIconData(
    'M18.36 10.59 10.59 18.36a3.5 3.5 0 0 1-4.95-4.95'
    'L13.41 5.64a3.5 3.5 0 0 1 4.95 4.95z'
    'M8.8 8.8l6.4 6.4',
  );
}

/// Item type is a GAP; the stored unit decides between a pill and a box.
CruIconData inventoryItemIcon(InventoryItem item) {
  final u = item.unit.trim().toLowerCase();
  const pills = ['tablet', 'capsule', 'strip', 'pill'];
  return pills.any(u.startsWith) ? InventoryIcons.pill : CruIcons.box;
}

/// The neutral chart grey of the mock-ups (#C5CDD8 in Day): stock fills
/// and usage bars. No token yet (NEEDS.md asks for `CruColors.chart`),
/// so it is mixed from two tokens and follows the appearance.
Color inventoryChartGrey(CruColors c) => Color.lerp(c.track, c.label3, 0.3)!;

/// Sizes from the Inventory mock-ups that have no token yet (NEEDS.md).
abstract final class InventorySize {
  /// List columns: In stock, Lasts, Next expiry (Item flexes; chevron is
  /// [CruSize.tableChevronColumn]).
  static const double stockColumn = 124;
  static const double lastsColumn = 116;
  static const double expiryColumn = 100;
  static const double columnGap = 20;

  /// Level bar under the stock quantity.
  static const double levelBarWidth = 96;
  static const double levelBarHeight = 4;

  /// Selection rings: list row (inset 1.5 px) and grid tile (2 px).
  static const double rowRing = 1.5;
  static const double tileRing = 2;

  /// Grid tiles.
  static const double tileHeight = 104;
  static const double tileRadius = 20;
  static const double tileGap = 14;
  static const double tileVialWidth = 14;
  static const double tileVialHeight = 78;

  /// Below this width the grid drops to two columns.
  static const double gridThreeColumns = 600;

  /// Item panel vial.
  static const double panelVialWidth = 20;
  static const double panelVialHeight = 76;

  /// Footer legend vial.
  static const double legendVialWidth = 8;
  static const double legendVialHeight = 18;

  /// Vial notch at the reorder level.
  static const double notch = 2;

  /// Usage chart: total height, day label height, gap between bars.
  static const double usageChartHeight = 64;
  static const double usageLabelHeight = 14;
  static const double usageBarGap = 6;
  static const double usageStub = 3;

  /// Batch code column in the panel.
  static const double batchCodeColumn = 76;

  /// Big numbers: grid tile quantity (22/26).
  static const double tileQuantity = 22;
}

/// Grid tile quantity (22/26, tabular). No matching type style yet.
const TextStyle inventoryTileQuantity = TextStyle(
  fontFamily: CruType.family,
  fontSize: InventorySize.tileQuantity,
  height: 26 / 22,
  fontWeight: FontWeight.w600,
  letterSpacing: -0.44,
  fontFeatures: CruType.tabular,
);
