import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/support/presentation/support_ticket_watcher.dart';

void main() {
  const open = WatchedTicket(id: 't1', status: 'open');
  const resolved = WatchedTicket(id: 't1', status: 'resolved');

  List<String> run(
    List<WatchedTicket> tickets, {
    Set<String>? announced,
    Set<String>? seenOpen,
    bool fresh = false,
    bool phone = false,
  }) => [
    for (final t in ticketsToAnnounce(
      tickets,
      announced: announced ?? {},
      seenOpen: seenOpen ?? {},
      fresh: fresh,
      phone: phone,
    ))
      t.id,
  ];

  test('desktop: a resolved ticket is news once', () {
    final announced = <String>{};
    expect(run([resolved], announced: announced), ['t1']);
    expect(run([resolved], announced: announced), isEmpty);
  });

  test('first run on a device: tickets already resolved are history', () {
    final announced = <String>{};
    expect(run([resolved], announced: announced, fresh: true), isEmpty);
    expect(announced, {'t1'});
  });

  test('open tickets are never news', () {
    expect(run([open]), isEmpty);
  });

  test('phone: only a ticket seen open while the app ran', () {
    // Resolved while the app was closed: the push already told them.
    expect(run([resolved], phone: true), isEmpty);

    final announced = <String>{};
    final seenOpen = <String>{};
    expect(
      run([open], announced: announced, seenOpen: seenOpen, phone: true),
      isEmpty,
    );
    expect(
      run([resolved], announced: announced, seenOpen: seenOpen, phone: true),
      ['t1'],
    );
  });

  test('wording matches the push', () {
    expect(resolved.news.title, 'Your issue is resolved');
    expect(resolved.news.body, 'Thanks for letting us know.');
    const feedback = WatchedTicket(
      id: 't2',
      status: 'resolved',
      category: 'feedback',
      resolution: ' Added in the next update. ',
    );
    expect(feedback.news.title, 'Your feedback was looked at');
    expect(feedback.news.body, 'Added in the next update.');
  });
}
