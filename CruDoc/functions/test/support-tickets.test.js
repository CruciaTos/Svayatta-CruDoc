/**
 * Tests for the "your issue is resolved" push (src/support_tickets.ts).
 *
 * Run with:  npm run build && node test/support-tickets.test.js
 */
const assert = require('assert');
const {ticketResolvedNews} = require('../lib/support_tickets');

const open = {doctorId: 'doc1', category: 'bug', status: 'open'};

// Resolving a bug report tells its sender.
assert.deepStrictEqual(
  ticketResolvedNews(open, {...open, status: 'resolved'}),
  {uid: 'doc1', title: 'Your issue is resolved', body: 'Thanks for letting us know.'},
);

// From In progress too, and the Super Admin's note is the message.
assert.deepStrictEqual(
  ticketResolvedNews(
    {...open, status: 'inProgress'},
    {...open, status: 'resolved', resolution: '  Fixed in the next update.  '},
  ),
  {uid: 'doc1', title: 'Your issue is resolved', body: 'Fixed in the next update.'},
);

// Feedback gets its own wording.
assert.strictEqual(
  ticketResolvedNews(
    {...open, category: 'feedback'},
    {...open, category: 'feedback', status: 'resolved'},
  ).title,
  'Your feedback was looked at',
);

// Nothing to say: still open, already resolved, closed, or no sender.
assert.strictEqual(ticketResolvedNews(open, {...open, status: 'inProgress'}), null);
assert.strictEqual(
  ticketResolvedNews({...open, status: 'resolved'}, {...open, status: 'resolved', isArchived: true}),
  null,
);
assert.strictEqual(ticketResolvedNews(open, {...open, status: 'closed'}), null);
assert.strictEqual(
  ticketResolvedNews(open, {category: 'bug', status: 'resolved'}),
  null,
);
assert.strictEqual(ticketResolvedNews(open, undefined), null);

console.log('support-tickets tests passed');
