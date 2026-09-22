const test = require('node:test');
const assert = require('node:assert/strict');
const {Store, matches, tagColor, formatTime} = require('../Resources/Web/app.js');
const entry = (n, session = 'a') => ({sessionID:session, sequence:n, level:'info', tag:'Network', message:'Hello 世界', context:{statusCode:500}});
test('bounded history, deduplication, reconnect and new session', () => {
  const store = new Store(); store.begin('a');
  store.add(Array.from({length:3000}, (_, i) => entry(i + 1)));
  assert.equal(store.entries.length, 2000); assert.equal(store.entries[0].sequence, 1001);
  store.add([entry(2999), entry(3000), entry(3001)]); assert.equal(store.entries.at(-1).sequence, 3001);
  store.clear(); store.add([entry(3000), entry(3002)]); assert.equal(store.entries.length, 1);
  store.begin('b'); store.add([entry(1, 'b')]); assert.equal(store.entries.length, 1);
});
test('filters AND dimensions, context search and stable tag colors', () => {
  assert(matches(entry(1), new Set(['info']), new Set(), 'STATUSCODE'));
  assert(matches(entry(1), new Set(['info']), new Set(), '500'));
  assert(!matches(entry(1), new Set(['error']), new Set(), '500'));
  assert(!matches(entry(1), new Set(['info']), new Set(['Network']), ''));
  assert.equal(tagColor('Network'), tagColor('Network'));
});

test('timestamp includes hours, minutes, seconds and milliseconds', () => {
  assert.match(formatTime('2026-09-21T07:30:45.123Z'), /\d{2}:\d{2}:\d{2}/);
  assert(formatTime('2026-09-21T07:30:45.123Z').includes('123'));
});

test('plain logs preserve multiline text and include only nonempty context', () => {
  const {formatLogs} = require('../Resources/Web/app.js');
  const first = {...entry(1), timestamp:'2026-09-21T07:30:45.123Z', message:'你好 <script> &\n第二行', context:{nested:{ok:true}}};
  const second = {...first, level:'warning', tag:'UI', message:'empty context', context:{}};
  assert.equal(formatLogs([first, second]),
    `${formatTime(first.timestamp)} [INFO] [Network] 你好 <script> &\n第二行\n${JSON.stringify(first.context, null, 2)}\n\n${formatTime(first.timestamp)} [WARNING] [UI] empty context`);
  assert.equal(formatLogs([]), '');
});

test('source location is displayed and searchable while old entries remain compatible', () => {
  const {formatLogs, sourceLocation} = require('../Resources/Web/app.js');
  const located = {...entry(1), timestamp:'2026-09-21T07:30:45.123Z', file:'Player.swift', line:42};
  assert.equal(sourceLocation(located), 'Player.swift:42');
  assert(formatLogs([located]).includes('[Network] [Player.swift:42] Hello 世界'));
  assert(matches(located, new Set(['info']), new Set(), 'PLAYER.SWIFT:42'));
  assert.equal(sourceLocation(entry(1)), '');
  assert(!formatLogs([{...located, file:undefined}]).includes('undefined'));
});

test('UI translations cover both languages, region matching, fallback and counts', () => {
  const {messages, resolveLanguage, translate} = require('../Resources/Web/app.js');
  assert.deepEqual(Object.keys(messages.en).sort(), Object.keys(messages.zh).sort());
  for (const code of ['en', 'zh']) for (const key of Object.keys(messages.en)) {
    assert.equal(typeof messages[code][key], 'string'); assert(messages[code][key].length > 0);
  }
  assert.equal(resolveLanguage(null, 'zh-TW'), 'zh');
  assert.equal(resolveLanguage(null, 'en-GB'), 'en');
  assert.equal(resolveLanguage(null, 'fr-FR'), 'en');
  assert.equal(resolveLanguage('zh', 'en-US'), 'zh');
  assert.equal(resolveLanguage('invalid', 'zh-CN'), 'zh');
  assert.equal(translate('en', 'count', {visible:2, total:30}), '2 / 30 logs');
  assert.equal(translate('zh', 'count', {visible:2, total:30}), '2 / 30 条日志');
  assert.equal(translate('unsupported', 'live'), 'Live Logs');
});
