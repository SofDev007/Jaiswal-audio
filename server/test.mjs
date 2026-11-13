// End-to-end check of the Worker with a real SQLite database (node:sqlite)
// and a fake Google key. Run: node test.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import worker from './src/index.js';

// D1's API over node:sqlite.
const db = new DatabaseSync(':memory:');
db.exec(readFileSync(new URL('./schema.sql', import.meta.url), 'utf8'));
const stmt = (sql, args = []) => ({
  bind: (...a) => stmt(sql, a),
  first: async () => db.prepare(sql).get(...args) ?? null,
  all: async () => ({ results: db.prepare(sql).all(...args) }),
  run: async () => (db.prepare(sql).run(...args), { success: true }),
});
const env = {
  DB: { prepare: (sql) => stmt(sql), batch: async (list) => { for (const s of list) await s.run(); } },
  GOOGLE_CLIENT_ID: 'cid', ADMIN_EMAIL: 'owner@x.com',
};

// A fake Google: our own key pair, served as Google's certs.
const pair = await crypto.subtle.generateKey(
  { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
  true, ['sign', 'verify']);
const jwk = { ...(await crypto.subtle.exportKey('jwk', pair.publicKey)), kid: 'k1', alg: 'RS256', use: 'sig' };
globalThis.fetch = async () => Response.json({ keys: [jwk] }, { headers: { 'cache-control': 'max-age=60' } });
const b64 = (x) => Buffer.from(typeof x === 'string' ? x : new Uint8Array(x)).toString('base64url');
async function googleToken(claims) {
  const head = b64(JSON.stringify({ alg: 'RS256', kid: 'k1' }));
  const body = b64(JSON.stringify({
    iss: 'https://accounts.google.com', aud: 'cid', exp: Date.now() / 1000 + 600, email_verified: true, ...claims }));
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', pair.privateKey, new TextEncoder().encode(head + '.' + body));
  return head + '.' + body + '.' + b64(sig);
}

async function call(method, path, { token, body } = {}) {
  const headers = { 'content-type': 'application/json' };
  if (token) headers.authorization = 'Bearer ' + token;
  const res = await worker.fetch(new Request('https://jarx.test' + path,
    { method, headers, body: body && JSON.stringify(body) }), env);
  return { status: res.status, body: res.headers.get('content-type').includes('json') ? await res.json() : await res.text() };
}
const signIn = async (claims, device = 'realme 5 Pro') =>
  call('POST', '/auth/google', { body: { idToken: await googleToken(claims), device, appVersion: '2.0.0+34' } });

const sis = { sub: 's1', email: 'sis@x.com', name: 'Sis', picture: 'https://p/s.jpg' };
const owner = { sub: 'o1', email: 'owner@x.com', name: 'Owner' };

// Bad tokens are refused.
assert.equal((await signIn({ ...sis, aud: 'other-app' })).status, 401, 'wrong app');
assert.equal((await signIn({ ...sis, exp: 1 })).status, 401, 'expired');
assert.equal((await signIn({ ...sis, email_verified: false })).status, 401, 'unverified email');
const good = await googleToken(sis);
const forged = good.slice(0, good.lastIndexOf('.') + 1) + b64('x'.repeat(256));
assert.equal((await call('POST', '/auth/google', { body: { idToken: forged } })).status, 401, 'bad signature');
assert.equal((await call('POST', '/auth/google', { body: { idToken: 'junk' } })).status, 401, 'junk');
assert.equal((await call('GET', '/me')).status, 401, 'no session');
assert.equal((await call('GET', '/me', { token: 'f'.repeat(64) })).status, 401, 'unknown session');

// Sign in, who am I.
const s = await signIn(sis);
assert.equal(s.status, 200);
assert.match(s.body.token, /^[0-9a-f]{64}$/);
assert.equal(s.body.user.admin, false);
const me = await call('GET', '/me', { token: s.body.token });
assert.equal(me.body.user.name, 'Sis');

// Sync: newest wins, a phone clock in the future is clamped.
const t = s.body.token;
await call('PUT', '/sync', { token: t, body: { library: { data: { playlists: ['A'] }, updatedAt: 100 } } });
await call('PUT', '/sync', { token: t, body: { library: { data: { playlists: ['old'] }, updatedAt: 50 } } });
let sync = await call('GET', '/sync', { token: t });
assert.deepEqual(sync.body.library, { data: { playlists: ['A'] }, updatedAt: 100 });
const put = await call('PUT', '/sync', { token: t, body: {
  library: { data: { playlists: ['B'] }, updatedAt: 200 }, taste: { data: { w: 1 }, updatedAt: Date.now() + 9e9 } } });
assert.ok(put.body.updatedAt.taste <= Date.now(), 'future clock clamped');
sync = await call('GET', '/sync', { token: t });
assert.deepEqual(sync.body.library.data, { playlists: ['B'] });
assert.deepEqual(sync.body.taste.data, { w: 1 });
assert.equal((await call('PUT', '/sync', { token: t, body: { taste: { data: 'x'.repeat(2e6), updatedAt: 1 } } })).status, 413);
assert.equal((await call('PUT', '/sync', { token: t, body: { taste: { data: 1, updatedAt: 'soon' } } })).status, 400);

// Only the owner sees the admin list.
assert.equal((await call('GET', '/admin/users', { token: t })).status, 403);
const o = await signIn(owner, 'admin page');
assert.equal(o.body.user.admin, true);
let users = (await call('GET', '/admin/users', { token: o.body.token })).body.users;
assert.equal(users.length, 2);
assert.equal(users.find((u) => u.id === 's1').phones, 1);
assert.equal(users.find((u) => u.id === 'o1').phones, 0, 'admin page is not a phone');
assert.equal((await call('POST', '/admin/ban', { token: o.body.token, body: { id: 'o1' } })).status, 400, 'no self-ban');

// Ban: the open session and new sign-ins are refused with the reason.
await call('POST', '/admin/ban', { token: o.body.token, body: { id: 's1', reason: 'spam' } });
assert.deepEqual((await call('GET', '/me', { token: t })).body, { error: 'banned', reason: 'spam' });
assert.equal((await signIn(sis)).status, 403);
users = (await call('GET', '/admin/users', { token: o.body.token })).body.users;
assert.equal(users.find((u) => u.id === 's1').status, 'banned');
await call('POST', '/admin/unban', { token: o.body.token, body: { id: 's1' } });
assert.equal((await call('GET', '/me', { token: t })).status, 200, 'unbanned');

// Sign out ends only that session; delete removes everything.
const t2 = (await signIn(sis, 'OPPO CPH2641')).body.token;
await call('POST', '/signout', { token: t2 });
assert.equal((await call('GET', '/me', { token: t2 })).status, 401);
assert.equal((await call('GET', '/me', { token: t })).status, 200);
await call('DELETE', '/me', { token: t });
assert.equal((await call('GET', '/me', { token: t })).status, 401);
const again = await signIn(sis);
assert.deepEqual((await call('GET', '/sync', { token: again.body.token })).body, {}, 'fresh after delete');

// The admin page is served.
const page = await call('GET', '/admin');
assert.match(page.body, /data-client_id="cid"/);
assert.equal((await call('GET', '/nope', { token: o.body.token })).status, 404);
console.log('all server checks passed');
