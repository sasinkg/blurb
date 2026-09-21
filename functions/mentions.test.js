const {test} = require('node:test');
const assert = require('node:assert/strict');
const {mentionRecipients, notificationRecipients} = require('./mentions');
const members = [{id: 'a', displayName: 'Sasin Gudipati'}, {id: 'b', displayName: 'Neha Jagathesan'}, {id: 'c', displayName: 'Raj Pulugurtha'}];
test('unique first names, punctuation, repeat mentions, and case', () => {
  assert.deepEqual(mentionRecipients('Hi @Neha! @NEHA and @Raj.', members, 'a'), ['b', 'c']);
});
test('self mentions, email addresses, and nonmembers do not notify', () => {
  assert.deepEqual(mentionRecipients('@Sasin test@Neha.com @Nobody', members, 'a'), []);
});
test('ambiguous names never fan out to unrelated namesakes', () => {
  assert.deepEqual(mentionRecipients('@Raj', [...members, {id: 'd', displayName: 'Raj Smith'}], 'a'), []);
});
test('reply author mentioned receives just one notification', () => {
  assert.deepEqual([...notificationRecipients({text: '@Neha @Raj', members, senderID: 'a', postAuthorID: 'b'})], [['b', 'mention'], ['c', 'mention']]);
});
test('replying to yourself can still notify another mentioned person', () => {
  assert.deepEqual([...notificationRecipients({text: '@Neha', members, senderID: 'a', postAuthorID: 'a'})], [['b', 'mention']]);
});
test('edits only notify newly mentioned people', () => {
  assert.deepEqual(mentionRecipients('@Neha @Raj', members, 'a', '@neha'), ['c']);
});
test('unicode first names resolve consistently', () => {
  assert.deepEqual(mentionRecipients('@José', [{id: 'j', displayName: 'José Smith'}], 'a'), ['j']);
});
test('former post author is not notified', () => {
  assert.equal(notificationRecipients({text: 'Hello', members, senderID: 'a', postAuthorID: 'former'}).size, 0);
});
