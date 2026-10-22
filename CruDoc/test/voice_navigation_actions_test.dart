import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/voice/domain/voice_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

const _visible = <({int tab, String label})>[
  (tab: DesktopTab.dashboard, label: 'Dashboard'),
  (tab: DesktopTab.appointments, label: 'Schedule'),
  (tab: DesktopTab.patients, label: 'Patients'),
  (tab: DesktopTab.files, label: 'Files'),
  (tab: DesktopTab.scribe, label: 'Scribe'),
  (tab: DesktopTab.inventory, label: 'Inventory'),
  (tab: DesktopTab.revenue, label: 'Revenue'),
  (tab: DesktopTab.campaigns, label: 'Campaigns'),
  (tab: DesktopTab.settings, label: 'Settings'),
];

NavTarget? _target(String text) {
  final r = resolveNavigation(text, _visible, DateTime(2026, 10, 15, 10));
  return r is NavScreen ? r.target : null;
}

void main() {
  group('voice opens the header actions', () {
    const cases = {
      'record payment': (DesktopTab.revenue, 'action.recordPayment'),
      'record a new payment': (DesktopTab.revenue, 'action.recordPayment'),
      'add expense': (DesktopTab.revenue, 'action.recordExpense'),
      'record expense': (DesktopTab.revenue, 'action.recordExpense'),
      'new invoice': (DesktopTab.revenue, 'action.newInvoice'),
      'create a new invoice': (DesktopTab.revenue, 'action.newInvoice'),
      'add item': (DesktopTab.inventory, 'action.addItem'),
      'add a new item': (DesktopTab.inventory, 'action.addItem'),
      'please add a new item to the inventory': (
        DesktopTab.inventory,
        'action.addItem',
      ),
      'new order': (DesktopTab.inventory, 'inventory.orders'),
      'place an order': (DesktopTab.inventory, 'inventory.orders'),
      'new campaign': (DesktopTab.campaigns, 'action.newCampaign'),
      'upload file': (DesktopTab.files, 'action.addFiles'),
      'add files': (DesktopTab.files, 'action.addFiles'),
      'create a new folder': (DesktopTab.files, 'action.newFolder'),
      'check in': (DesktopTab.dashboard, 'action.newVisit'),
    };
    cases.forEach((text, want) {
      test(text, () {
        final t = _target(text);
        expect(t?.tab, want.$1);
        expect(t?.spots, {want.$2});
      });
    });
  });

  group('screens and places still open', () {
    const cases = {
      'open inventory': DesktopTab.inventory,
      'go to revenue': DesktopTab.revenue,
      'open files': DesktopTab.files,
      'show documents': DesktopTab.files,
      'open schedule': DesktopTab.appointments,
      'open queue': DesktopTab.queue,
      'open settings': DesktopTab.settings,
      'dashboard': DesktopTab.dashboard,
    };
    cases.forEach((text, tab) {
      test(text, () {
        final t = _target(text);
        expect(t?.tab, tab);
        expect(t?.spots.where(isActionSpot), isEmpty);
      });
    });

    test('lists stay lists', () {
      expect(_target('show invoices')?.spots, {'revenue.invoices'});
      expect(_target('show expenses')?.spots, {'revenue.out'});
      expect(_target('show me low stock')?.spots, {'inventory.low'});
      expect(_target('show all the patients')?.spots, {'patients.all'});
    });
  });

  test('a near-guess never opens a form', () {
    final ids = semanticOptions(_visible).map((o) => o.id);
    expect(ids, isNot(contains('spot:action.recordPayment')));
    expect(ids, isNot(contains('spot:action.addItem')));
  });
}
