import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile, readdir, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { configFromEnv, createRequestHandler } from './server.mjs';

const token = 'test-token-that-is-at-least-thirty-two-characters';
const json = value => new Response(JSON.stringify(value), { headers: { 'Content-Type': 'application/json' } });
const deferred = () => { let accept; const promise = new Promise(resolve => { accept = resolve; }); return { promise, accept }; };
const model = (intent, body = '', topic = 'unknown') => json({ status: 'completed', output: [{ type: 'message', content: [{ type: 'output_text', text: JSON.stringify({ intent, body, topic }) }] }] });
const toolInputs = {
  GMAIL_GET_PROFILE: ['user_id'], GMAIL_SEND_EMAIL: ['recipient_email', 'subject', 'body', 'is_html'],
  GMAIL_FETCH_MESSAGE_BY_MESSAGE_ID: ['user_id', 'message_id', 'format'], GMAIL_FETCH_EMAILS: ['user_id', 'query', 'max_results', 'include_payload'],
};

async function fixture(t, overrides = {}) {
  const dataDir = await mkdtemp(join(tmpdir(), 'more-jury-'));
  t.after(() => rm(dataDir, { recursive: true, force: true }));
  const config = { ...configFromEnv({ JURY_DEMO_TOKEN: token }), dataDir, openAIKey: 'not-an-api-key', elevenKey: 'not-an-api-key', voiceID: 'voice', composioKey: 'not-an-api-key', accountID: 'ca_owned', userID: 'owner', sender: 'owner@fixture.invalid', recipient: 'recipient@fixture.invalid', recipientName: 'Camille', binding: 'fixture', ...overrides };
  const state = { sendCount: 0, modelCount: 0, sent: null, model: () => model('draft', 'Bonjour Camille, je serai là à 15 h. À tout à l’heure.'), send: null, fetchMessage: null, accountUserID: config.userID, accountUpdatedAt: '2026-10-16T08:00:00Z', profile: config.sender, schema: null, audio: null, requests: [] };
  const fetchImpl = async (input, options) => {
    const url = new URL(input), body = options.body ? JSON.parse(options.body) : null;
    state.requests.push({ url: url.href, body, options });
    if (url.hostname === 'api.openai.com') {
      state.modelCount += 1;
      assert.equal(body.store, false); assert.equal(body.text.format.strict, true);
      assert.equal(body.tools, undefined);
      return state.model(body, options);
    }
    if (url.hostname === 'api.elevenlabs.io') return state.audio ? state.audio() : new Response(Buffer.alloc(30, 1), { headers: { 'Content-Type': 'audio/mpeg' } });
    assert.equal(url.hostname, 'backend.composio.dev', 'All provider URLs must be fixed in code.');
    assert.equal(options.headers['x-api-key'], config.composioKey);
    if (url.pathname.includes('connected_accounts/')) return json({ id: config.accountID, user_id: state.accountUserID, toolkit: { slug: 'gmail' }, auth_config: { id: 'ac_owned' }, status: 'ACTIVE', created_at: '2026-10-01T08:00:00Z', updated_at: state.accountUpdatedAt });
    const slug = url.pathname.split('/').at(-1);
    if (options.method === 'GET') return state.schema ? state.schema(slug) : json({ slug, version: config.version, toolkit: { slug: 'gmail' }, input_parameters: { type: 'object', properties: Object.fromEntries(toolInputs[slug].map(key => [key, {}])), required: [] } });
    assert.equal(body.connected_account_id, config.accountID); assert.equal(body.user_id, config.userID); assert.equal(body.version, config.version);
    let data;
    if (slug === 'GMAIL_GET_PROFILE') data = { emailAddress: state.profile };
    if (slug === 'GMAIL_SEND_EMAIL') {
      state.sendCount += 1; state.sent = body.arguments;
      if (state.send) return state.send(body.arguments);
      data = { id: '19ba000000000001' };
    }
    if (slug === 'GMAIL_FETCH_EMAILS') data = { messages: state.sent ? [{ messageId: '19ba000000000001' }] : [] };
    if (slug === 'GMAIL_FETCH_MESSAGE_BY_MESSAGE_ID') {
      if (state.fetchMessage) return state.fetchMessage();
      data = { id: '19ba000000000001', labelIds: ['SENT'], payload: { mimeType: 'text/plain', headers: [
        { name: 'From', value: `MORE Owner <${config.sender}>` }, { name: 'To', value: config.recipient }, { name: 'Subject', value: state.sent.subject },
      ], body: { data: Buffer.from(state.sent.body).toString('base64url') } } };
    }
    return json({ successful: true, data });
  };
  const handler = await createRequestHandler(config, { fetchImpl });
  const call = (path, payload = {}, options = {}) => handler(new Request(`http://localhost${path}`, { method: options.method ?? 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', ...options.headers }, ...(['GET', 'DELETE'].includes(options.method) ? {} : { body: JSON.stringify(payload) }) }));
  const start = async (enterMail = true) => {
    const result = await call('/v1/jury/session'); assert.equal(result.status, 201);
    if (enterMail) return (await call('/v1/jury/turn', { sessionID: result.payload.sessionID, requestID: randomUUID(), text: 'On regarde mes messages' })).payload;
    return result.payload;
  };
  const turn = (sessionID, text, requestID = randomUUID()) => call('/v1/jury/turn', { sessionID, requestID, text });
  return { state, config, handler, call, start, turn, fetchImpl };
}

test('configuration rejects missing auth, placeholder addresses and arbitrary browser destinations', () => {
  assert.throws(() => configFromEnv({}), /TOKEN/);
  assert.throws(() => configFromEnv({ JURY_DEMO_TOKEN: token, JURY_DEMO_RECIPIENT: 'somebody@example.com' }), /real/);
  assert.throws(() => configFromEnv({ JURY_DEMO_TOKEN: token, JURY_DEMO_SOCIAL_URL: 'https://instagram.com.attacker.invalid/' }), /HTTPS/);
});

test('health reveals capabilities only; authentication protects every session and speech request', async t => {
  const { call, config } = await fixture(t);
  const health = await call('/health', {}, { method: 'GET', headers: { Authorization: '' } });
  assert.equal(health.status, 200); assert.deepEqual(health.payload.configured, { conversation: true, speech: true, mail: true });
  assert.ok(!JSON.stringify(health.payload).includes(config.sender));
  for (const path of ['/v1/jury/session', '/v1/jury/turn', '/v1/jury/speech']) assert.equal((await call(path, {}, { headers: { Authorization: '' } })).status, 401);
});

test('missing configured providers produce no simulated session', async t => {
  const { call, state } = await fixture(t, { openAIKey: undefined });
  const result = await call('/v1/jury/session');
  assert.equal(result.status, 503); assert.equal(result.payload.error.code, 'demo_not_configured'); assert.equal(state.requests.length, 0);
});

test('mail is drafted, revised freely and only explicitly sent to the pinned recipient', async t => {
  const { state, start, turn, config } = await fixture(t);
  const session = await start();
  assert.match(session.text, /point produit/);
  const draft = await turn(session.sessionID, 'Oui, dis-lui que je serai là.');
  assert.equal(draft.payload.stage, 'draft'); assert.equal(state.sendCount, 0);
  assert.equal((await turn(session.sessionID, 'oui')).status, 200); assert.equal(state.sendCount, 0, 'A generic yes never sends a reviewed reply.');
  state.model = () => model('revise', 'Bonjour Camille, est-ce que 15 h 30 te conviendrait ?');
  await turn(session.sessionID, 'Propose plutôt 15 h 30 et fais plus court.');
  const requestID = randomUUID();
  const sent = await turn(session.sessionID, 'Envoie', requestID);
  assert.equal(sent.status, 200); assert.equal(sent.payload.receipt.status, 'sent'); assert.equal(state.sendCount, 1);
  assert.equal(state.sent.recipient_email, config.recipient); assert.match(state.sent.body, /15 h 30/); assert.equal(state.sent.is_html, false);
  assert.match(state.sent.subject, /MORE-/);
  assert.deepEqual(await turn(session.sessionID, 'Envoie', requestID), sent); assert.equal(state.sendCount, 1);
  const again = await turn(session.sessionID, 'Envoie');
  assert.match(again.payload.text, /déjà été envoyé/); assert.equal(state.sendCount, 1);
  const social = await turn(session.sessionID, 'oui'); assert.equal(social.payload.action.type, 'openURL');
  assert.match(social.payload.text, /connecter/);
  const end = await turn(session.sessionID, 'continue'); assert.equal(end.payload.completed, true); assert.equal(end.payload.stage, 'complete');
});

test('sending before a draft and reusing a request ID with different content cannot send', async t => {
  const { state, start, turn } = await fixture(t);
  const session = await start();
  const requestID = randomUUID();
  assert.match((await turn(session.sessionID, 'envoie', requestID)).payload.text, /d’abord te lire/);
  assert.equal((await turn(session.sessionID, 'oui', requestID)).status, 409);
  assert.equal(state.sendCount, 0); assert.equal(state.modelCount, 0);
});

test('a remote timeout journals uncertainty durably and retries reconcile without sending again', async t => {
  const { state, config, start, turn, fetchImpl } = await fixture(t);
  const session = await start(); await turn(session.sessionID, 'oui');
  state.send = () => { throw new Error('socket closed after dispatch'); };
  const result = await turn(session.sessionID, 'envoie');
  assert.equal(result.status, 200); assert.match(result.payload.text, /pas pu vérifier/); assert.equal(state.sendCount, 1);
  const ledger = JSON.parse(await readFile(join(config.dataDir, 'effects', `${session.sessionID}.json`), 'utf8'));
  assert.equal(ledger.state, 'uncertain');
  const restarted = await createRequestHandler(config, { fetchImpl });
  const retry = await restarted(new Request('http://localhost/v1/jury/turn', { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ sessionID: session.sessionID, requestID: randomUUID(), text: 'envoie' }) }));
  assert.equal(retry.payload.receipt.status, 'sent'); assert.match(retry.payload.text, /retrouvé/); assert.equal(state.sendCount, 1);
  assert.equal(retry.payload.stage, 'mail', 'Reconciliation must restore a usable conversation after a restart.');
  const social = await restarted(new Request('http://localhost/v1/jury/turn', { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ sessionID: session.sessionID, requestID: randomUUID(), text: 'oui' }) }));
  assert.equal(social.payload.stage, 'social'); assert.equal(state.sendCount, 1);
});

test('uncertain mail not found remains uncertain and never repeats an external effect', async t => {
  const { state, start, turn } = await fixture(t);
  const session = await start(); await turn(session.sessionID, 'oui');
  state.send = () => { state.sent = null; throw new Error('timeout'); };
  await turn(session.sessionID, 'envoie');
  for (let index = 0; index < 2; index++) assert.match((await turn(session.sessionID, 'envoie')).payload.text, /reste incertain/);
  assert.equal(state.sendCount, 1);
});

test('successful provider response with wrong recipient or missing SENT evidence is uncertain', async t => {
  const { state, start, turn } = await fixture(t);
  const session = await start(); await turn(session.sessionID, 'oui');
  state.fetchMessage = () => json({ successful: true, data: { id: '19ba000000000001', labelIds: ['INBOX'] } });
  const result = await turn(session.sessionID, 'envoie');
  assert.equal(result.payload.receipt, undefined); assert.match(result.payload.text, /pas pu vérifier/); assert.equal(state.sendCount, 1);
});

test('documented normalized Composio message fields verify the same exact sent reply', async t => {
  const { state, start, turn, config } = await fixture(t);
  const session = await start(); await turn(session.sessionID, 'oui');
  state.fetchMessage = () => json({ successful: true, data: { messageId: '19ba000000000001', labelIds: ['SENT'], sender: `MORE Owner <${config.sender}>`, to: config.recipient, subject: state.sent.subject, messageText: state.sent.body } });
  const result = await turn(session.sessionID, 'envoie');
  assert.equal(result.payload.receipt.status, 'sent'); assert.equal(state.sendCount, 1);
});

test('changed connected-account identity invalidates the reviewed draft before sending', async t => {
  const { state, start, turn } = await fixture(t);
  const session = await start(); await turn(session.sessionID, 'oui');
  state.accountUpdatedAt = '2026-10-16T08:01:00Z';
  const result = await turn(session.sessionID, 'envoie');
  assert.equal(result.status, 409); assert.equal(result.payload.error.code, 'identity_changed'); assert.equal(state.sendCount, 0);
});

test('another user Gmail account cannot start a session', async t => {
  const { call, state } = await fixture(t); state.accountUserID = 'another-user';
  const result = await call('/v1/jury/session'); assert.equal(result.status, 409); assert.equal(state.sendCount, 0);
});

test('model refusal or malformed output cannot change the session or send anything', async t => {
  const { state, start, turn } = await fixture(t);
  const session = await start();
  state.model = () => json({ status: 'completed', output: [{ type: 'message', content: [{ type: 'refusal', refusal: 'No' }] }] });
  assert.equal((await turn(session.sessionID, 'oui')).status, 502);
  state.model = () => json({ status: 'completed', output: [{ type: 'message', content: [{ type: 'output_text', text: JSON.stringify({ intent: 'send', body: 'Invented', topic: 'unknown' }) }] }] });
  assert.equal((await turn(session.sessionID, 'oui')).status, 502);
  assert.equal(state.sendCount, 0);
});

test('DELETE interrupts an in-flight model result and cannot revive the routine', async t => {
  const { state, start, turn, call } = await fixture(t);
  const session = await start(), started = deferred(), finish = deferred();
  state.model = async () => { started.accept(); await finish.promise; return model('draft', 'Je serai là à 15 h.'); };
  const pending = turn(session.sessionID, 'oui'); await started.promise;
  const stopped = await call(`/v1/jury/session/${session.sessionID}`, {}, { method: 'DELETE' });
  assert.equal(stopped.payload.stage, 'stopped'); finish.accept();
  assert.equal((await pending).payload.stage, 'stopped');
  assert.equal((await turn(session.sessionID, 'envoie')).payload.stage, 'stopped'); assert.equal(state.sendCount, 0);
});

test('stop during tool metadata lookup prevents the subsequent Gmail dispatch', async t => {
  const { state, start, turn, call } = await fixture(t);
  const session = await start(); await turn(session.sessionID, 'oui');
  const started = deferred(), finish = deferred();
  state.schema = async slug => {
    if (slug === 'GMAIL_SEND_EMAIL') { started.accept(); await finish.promise; }
    return json({ slug, version: '20261010_00', toolkit: { slug: 'gmail' }, input_parameters: { type: 'object', properties: Object.fromEntries(toolInputs[slug].map(key => [key, {}])), required: [] } });
  };
  const pending = turn(session.sessionID, 'envoie'); await started.promise;
  await call(`/v1/jury/session/${session.sessionID}`, {}, { method: 'DELETE' }); finish.accept();
  assert.equal((await pending).payload.stage, 'stopped'); assert.equal(state.sendCount, 0);
});

test('pause invalidates the send context until the current draft is read again', async t => {
  const { state, start, turn } = await fixture(t);
  const session = await start(); await turn(session.sessionID, 'oui');
  await turn(session.sessionID, 'pause'); await turn(session.sessionID, 'envoie'); assert.equal(state.sendCount, 0);
  await turn(session.sessionID, 'reprends'); await turn(session.sessionID, 'envoie'); assert.equal(state.sendCount, 1);
});

test('skipping a draft invalidates it and a later send cannot use the stale content', async t => {
  const { state, start, turn } = await fixture(t);
  const session = await start(); await turn(session.sessionID, 'oui');
  state.model = () => model('next'); await turn(session.sessionID, 'passe aux réseaux');
  const result = await turn(session.sessionID, 'envoie'); assert.match(result.payload.text, /d’abord te lire/); assert.equal(state.sendCount, 0);
});

test('negated or conditional send language never causes a dispatch', async t => {
  const { state, start, turn } = await fixture(t);
  const session = await start(); await turn(session.sessionID, 'oui');
  state.model = () => model('question');
  for (const text of ['N’envoie pas', 'Envoie si tu trouves le bon horaire', 'Dis-moi avant d’envoyer', 'Fais plus court puis envoie']) await turn(session.sessionID, text);
  assert.equal(state.sendCount, 0);
});

test('a question about reminders and prepared facts never claims fabricated external success', async t => {
  const { state, start, turn } = await fixture(t);
  const session = await start();
  state.model = () => model('reminder'); const reminder = await turn(session.sessionID, 'Est-ce que tu gères les rappels ?');
  assert.equal(reminder.payload.action, undefined); assert.equal(reminder.payload.receipt, undefined);
  state.model = () => model('question', '', 'calendar'); assert.match((await turn(session.sessionID, 'suis-je libre ?')).payload.text, /agenda disponible/);
  assert.equal(state.sendCount, 0);
});

test('an explicit reminder request prepares a pinned native action and claims nothing before acknowledgement', async t => {
  const { state, start, turn, call } = await fixture(t);
  const session = await start(); state.model = () => model('reminder');
  const result = await turn(session.sessionID, 'Rappelle-moi vingt minutes avant le rendez-vous.');
  const action = result.payload.action;
  assert.deepEqual({ ...action, requestID: 'opaque' }, { type: 'createReminder', requestID: 'opaque', title: 'Point produit', minutesBefore: 20, meetingHour: 15, meetingMinute: 0 });
  assert.match(action.requestID, /^[a-f0-9-]{36}$/); assert.equal(result.payload.receipt, undefined); assert.doesNotMatch(result.payload.text, /est créé/);
  const confirmed = await call('/v1/jury/action-result', { sessionID: session.sessionID, requestID: action.requestID, status: 'confirmed', receiptID: 'native-reminder-1' });
  assert.equal(confirmed.status, 200); assert.equal(confirmed.payload.receipt.type, 'reminder'); assert.equal(confirmed.payload.receipt.status, 'created'); assert.match(confirmed.payload.text, /est créé/);
  const another = await turn(session.sessionID, 'Crée un rappel'); assert.equal(another.payload.action, undefined); assert.equal(another.payload.receipt.id, 'native-reminder-1');
  assert.equal(state.sendCount, 0);
});

test('duplicate reminder acknowledgements are idempotent and conflicting acknowledgements are refused', async t => {
  const { state, start, turn, call } = await fixture(t);
  const session = await start(); state.model = () => model('reminder');
  const action = (await turn(session.sessionID, 'Mets un rappel')).payload.action;
  const input = { sessionID: session.sessionID, requestID: action.requestID, status: 'confirmed', receiptID: 'native-reminder-1' };
  const first = await call('/v1/jury/action-result', input); assert.deepEqual(await call('/v1/jury/action-result', input), first);
  assert.equal((await call('/v1/jury/action-result', { ...input, receiptID: 'different-reminder' })).status, 409);
  assert.equal((await call('/v1/jury/action-result', { sessionID: session.sessionID, requestID: action.requestID, status: 'unavailable' })).status, 409);
});

test('unknown, unbound, invalid and stale reminder acknowledgements cannot claim creation', async t => {
  const { state, start, turn, call } = await fixture(t);
  const session = await start(); state.model = () => model('reminder');
  const unbound = { sessionID: session.sessionID, requestID: randomUUID(), status: 'confirmed', receiptID: 'invented' };
  assert.equal((await call('/v1/jury/action-result', unbound)).status, 404);
  const action = (await turn(session.sessionID, 'Rappelle-moi')).payload.action;
  assert.equal((await call('/v1/jury/action-result', { ...unbound, requestID: action.requestID, receiptID: undefined })).status, 400);
  assert.equal((await call('/v1/jury/action-result', { ...unbound, requestID: action.requestID, title: 'Changed action' })).status, 400);
  await call(`/v1/jury/session/${session.sessionID}`, {}, { method: 'DELETE' });
  const stopped = await call('/v1/jury/action-result', { ...unbound, requestID: action.requestID });
  assert.equal(stopped.status, 409); assert.equal(stopped.payload.error.code, 'stale_action_result');
});

test('unavailable reminder acknowledgement stays truthful and never emits another write', async t => {
  const { state, start, turn, call } = await fixture(t);
  const session = await start(); state.model = () => model('reminder');
  const action = (await turn(session.sessionID, 'Crée un rappel')).payload.action;
  const input = { sessionID: session.sessionID, requestID: action.requestID, status: 'unavailable' };
  const result = await call('/v1/jury/action-result', input);
  assert.match(result.payload.text, /n’a pas été créé/); assert.equal(result.payload.receipt, undefined);
  assert.deepEqual(await call('/v1/jury/action-result', input), result);
  assert.equal((await turn(session.sessionID, 'Crée un rappel')).payload.action, undefined);
});

test('reminder GET and duplicate voice requests never replay a pending native write after restart', async t => {
  const { state, start, turn, call, config, fetchImpl } = await fixture(t);
  const session = await start(); state.model = () => model('reminder');
  const requestID = randomUUID();
  const prepared = await turn(session.sessionID, 'Rappelle-moi', requestID);
  const duplicate = await turn(session.sessionID, 'Rappelle-moi', requestID);
  assert.equal(duplicate.payload.action, undefined); assert.match(duplicate.payload.text, /reste à vérifier/);
  const restarted = await createRequestHandler(config, { fetchImpl });
  const resumed = await restarted(new Request(`http://localhost/v1/jury/session/${session.sessionID}`, { headers: { Authorization: `Bearer ${token}` } }));
  assert.equal(resumed.payload.action, undefined); assert.equal(resumed.payload.receipt, undefined); assert.match(resumed.payload.text, /reste à vérifier/);
  const recovered = await call('/v1/jury/action-result', { sessionID: session.sessionID, requestID: prepared.payload.action.requestID, status: 'confirmed', receiptID: 'verified-native-reminder' });
  assert.equal(recovered.payload.receipt.status, 'created');
});

test('reminder requests never substitute the prepared time for another explicit time or duration', async t => {
  for (const text of [
    'Rappelle-moi une heure avant le rendez-vous.',
    'Rappelle-moi 1h avant le rendez-vous.',
    'Rappelle-moi trente secondes avant le rendez-vous.',
    'Rappelle-moi vingt minutes après le rendez-vous.',
    'Rappelle-moi dans vingt minutes.',
    'Rappelle-moi à 16 h.',
    'Rappelle-moi à seize heures.',
    'Rappelle-moi à 16:00.',
    'Rappelle-moi à 14h40.',
    'Rappelle-moi vingt et une minutes avant.',
    'Rappelle-moi quatre-vingt minutes avant.',
    'Rappelle-moi vingt minutes avant et une heure avant.',
    'Rappelle-moi vingt minutes avant demain.',
    'Rappelle-moi demain.',
    'Rappelle-moi hier.',
    'Rappelle-moi yesterday.',
    'Rappelle-moi le 20 octobre 2026.',
    'Rappelle-moi vingt minutes avant le rendez-vous du 20 octobre 2026.',
  ]) {
    const { state, start, turn } = await fixture(t);
    const session = await start(); state.model = () => model('reminder');
    const result = await turn(session.sessionID, text);
    assert.equal(result.payload.action, undefined, text);
    assert.equal(result.payload.receipt, undefined, text);
    assert.equal(state.sendCount, 0);
  }
});

test('default reminders and twenty-minute requests preserve the prepared native action', async t => {
  for (const text of ['Rappelle-moi', 'Crée un rappel', 'Rappelle-moi vingt minutes avant le rendez-vous.',
    'Rappelle-moi 20 min avant le point produit.', 'Rappelle-moi 20min avant.', 'Rappelle-moi 20 minutes.',
    'Peux-tu créer un rappel vingt minutes avant le rendez-vous ?',
    'Crée-moi un rappel vingt minutes avant le point produit, s’il te plaît.']) {
    const { state, start, turn } = await fixture(t);
    const session = await start(); state.model = () => model('reminder');
    const result = await turn(session.sessionID, text);
    const action = result.payload.action;
    assert.deepEqual({ ...action, requestID: 'opaque' }, { type: 'createReminder', requestID: 'opaque',
      title: 'Point produit', minutesBefore: 20, meetingHour: 15, meetingMinute: 0 }, text);
    assert.equal(result.payload.receipt, undefined);
    assert.equal(state.sendCount, 0);
  }
});

test('a reminder classification never turns negated or conditional language into a native write', async t => {
  const { state, start, turn } = await fixture(t);
  const session = await start(); state.model = () => model('reminder');
  for (const text of ['Ne crée pas de rappel', 'Rappelle-moi si je confirme', 'C’est quoi un rappel ?', 'Rappelle-moi dix minutes avant']) assert.equal((await turn(session.sessionID, text)).payload.action, undefined);
});

test('speech returns MP3 bytes and rejects provider JSON or missing voice', async t => {
  const { state, call } = await fixture(t);
  const result = await call('/v1/jury/speech', { text: 'Bonjour.' });
  assert.equal(result.headers['Content-Type'], 'audio/mpeg'); assert.ok(Buffer.isBuffer(result.payload));
  state.audio = () => json({ error: 'not-audio' }); assert.equal((await call('/v1/jury/speech', { text: 'Bonjour.' })).status, 502);
});

test('concurrent turns and durable pending requests cannot execute twice', async t => {
  const { state, start, turn, config } = await fixture(t);
  const session = await start(), started = deferred(), finish = deferred(), requestID = randomUUID();
  state.model = async () => { started.accept(); await finish.promise; return model('draft', 'À 15 h.'); };
  const first = turn(session.sessionID, 'oui', requestID); await started.promise;
  assert.equal((await turn(session.sessionID, 'oui', requestID)).payload.error.code, 'request_uncertain');
  assert.equal((await turn(session.sessionID, 'autre demande')).payload.error.code, 'turn_in_progress');
  finish.accept(); await first;
  assert.equal(state.modelCount, 1); assert.equal(state.sendCount, 0);
  assert.equal((await readdir(join(config.dataDir, 'requests'))).length, 2);
});

test('morning starts with a short conversation then moves to the prepared message', async t => {
  const { start, turn, state } = await fixture(t);
  const session = await start(false);
  assert.equal(session.stage, 'morning'); assert.match(session.text, /Bonjour\. Tu as dormi/);
  const mail = await turn(session.sessionID, 'oui');
  assert.equal(mail.payload.stage, 'mail'); assert.match(mail.payload.text, /15 h/); assert.equal(state.modelCount, 0);
});

test('a free-form model next intention from morning presents the message without skipping to social', async t => {
  const { start, turn, state } = await fixture(t);
  const session = await start(false); state.model = () => model('next');
  const result = await turn(session.sessionID, 'On passe aux messages');
  assert.equal(result.payload.stage, 'mail'); assert.match(result.payload.text, /point produit/);
  assert.equal(result.payload.action, undefined); assert.equal(result.payload.receipt, undefined); assert.equal(state.sendCount, 0);
});

test('draft or revision requested before hearing the message first presents its context without preparing an action', async t => {
  const { start, turn, state } = await fixture(t);
  for (const intent of ['draft', 'revise']) {
    const session = await start(false); state.model = () => model(intent, 'This draft must not be used.');
    const result = await turn(session.sessionID, 'Réponds-lui que je suis disponible');
    assert.equal(result.payload.stage, 'mail'); assert.match(result.payload.text, /point produit/);
    assert.equal(result.payload.action, undefined); assert.equal(result.payload.receipt, undefined);
    assert.match((await turn(session.sessionID, 'envoie')).payload.text, /d’abord te lire/);
  }
  assert.equal(state.sendCount, 0);
});

test('model next transitions skip only the current mail or draft and finish only from social', async t => {
  const { start, turn, state } = await fixture(t);
  const mail = await start(); state.model = () => model('next');
  const social = await turn(mail.sessionID, 'Je préfère regarder mes vidéos pour le moment');
  assert.equal(social.payload.stage, 'social'); assert.equal(social.payload.action.type, 'openURL');
  const complete = await turn(mail.sessionID, 'Ça me suffit pour ce matin');
  assert.equal(complete.payload.stage, 'complete'); assert.equal(complete.payload.action, undefined); assert.equal(complete.payload.completed, true);
  const another = await start(); state.model = () => model('draft', 'Je serai disponible.'); await turn(another.sessionID, 'Réponds que je serai disponible');
  state.model = () => model('next'); const skipped = await turn(another.sessionID, 'Finalement laisse ce brouillon et passe à mes vidéos');
  assert.equal(skipped.payload.stage, 'social'); assert.equal(skipped.payload.receipt, undefined); assert.equal(state.sendCount, 0);
});

test('GET resumes the current draft after process restart without invoking the model or sending', async t => {
  const { state, start, turn, config, fetchImpl } = await fixture(t);
  const session = await start(); await turn(session.sessionID, 'oui');
  const modelCalls = state.modelCount;
  const restarted = await createRequestHandler(config, { fetchImpl });
  const result = await restarted(new Request(`http://localhost/v1/jury/session/${session.sessionID}`, { headers: { Authorization: `Bearer ${token}` } }));
  assert.equal(result.payload.stage, 'draft'); assert.match(result.payload.text, /brouillon actuel/);
  assert.equal(state.modelCount, modelCalls); assert.equal(state.sendCount, 0); assert.equal(result.payload.action, undefined);
});

test('GET reconciles uncertain mail in read-only mode and preserves stopped state', async t => {
  const { state, start, turn, call, config, fetchImpl } = await fixture(t);
  const session = await start(); await turn(session.sessionID, 'oui');
  state.send = () => { throw new Error('connection lost after dispatch'); };
  await turn(session.sessionID, 'envoie');
  await call(`/v1/jury/session/${session.sessionID}`, {}, { method: 'DELETE' });
  const restarted = await createRequestHandler(config, { fetchImpl });
  const result = await restarted(new Request(`http://localhost/v1/jury/session/${session.sessionID}`, { headers: { Authorization: `Bearer ${token}` } }));
  assert.equal(result.payload.stage, 'stopped'); assert.equal(result.payload.completed, true);
  assert.equal(result.payload.receipt.status, 'sent'); assert.equal(state.sendCount, 1); assert.match(result.payload.text, /arrêté/);
});

test('GET never invents a receipt for missing uncertain mail or silently recreates unknown sessions', async t => {
  const { state, start, turn, call } = await fixture(t);
  const session = await start(); await turn(session.sessionID, 'oui');
  state.send = () => { state.sent = null; throw new Error('timeout before any confirmed result'); };
  await turn(session.sessionID, 'envoie');
  const result = await call(`/v1/jury/session/${session.sessionID}`, {}, { method: 'GET' });
  assert.equal(result.payload.receipt, undefined); assert.match(result.payload.text, /incertain/); assert.equal(state.sendCount, 1);
  const unknown = await call(`/v1/jury/session/${randomUUID()}`, {}, { method: 'GET' }); assert.equal(unknown.status, 404);
});

test('expired persisted sessions require an explicit new start and GET remains authenticated', async t => {
  const { start, config, fetchImpl } = await fixture(t);
  const session = await start();
  const path = join(config.dataDir, 'sessions', `${session.sessionID}.json`);
  const stored = JSON.parse(await readFile(path, 'utf8')); stored.expiresAt = Date.now() - 1;
  await writeFile(path, JSON.stringify(stored));
  const restarted = await createRequestHandler(config, { fetchImpl });
  const denied = await restarted(new Request(`http://localhost/v1/jury/session/${session.sessionID}`)); assert.equal(denied.status, 401);
  const expired = await restarted(new Request(`http://localhost/v1/jury/session/${session.sessionID}`, { headers: { Authorization: `Bearer ${token}` } })); assert.equal(expired.status, 404);
});
