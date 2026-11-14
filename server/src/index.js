// JARX server: Google sign-in, ban check, sync, and the owner's admin page.
// One Cloudflare Worker + one D1 database (../schema.sql). No dependencies.
//
// ponytail: no rate limiting; fine for ~60 users on the free plan. Add a
// per-IP limit (Cloudflare rate-limiting binding) if the Worker gets abused.

const GOOGLE_CERTS = 'https://www.googleapis.com/oauth2/v3/certs';
const SESSION_DAYS = 180;
// library, history and taste are one row per user; listening is one row per
// phone (listening:<device id>) so the phones' counts can be added up.
const KIND = /^(library|history|taste|listening:[0-9a-f]{8,32})$/;
const MAX_SNAPSHOT = 1_900_000; // D1 keeps at most 2 MB in one value
// Listening rows are small; a cap on their size and number per account stops
// one account from filling the database with made-up phone ids.
const MAX_LISTENING = 256_000;
const MAX_PHONES = 10;
const ADMIN_DEVICE = 'admin page';

const json = (body, status = 200) => Response.json(body, { status });
const now = () => Date.now();
const hex = (bytes) =>
  [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, '0')).join('');
const sha256Hex = async (text) =>
  hex(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text)));
const b64url = (s) =>
  Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0));
const clip = (v, n) => (v == null ? null : String(v).slice(0, n));

// ---- Google sign-in tokens ----

let certs = { keys: [], until: 0 };
async function googleKey(kid, retry = true) {
  if (certs.until < now()) {
    const res = await fetch(GOOGLE_CERTS);
    if (!res.ok) throw new Error('google certs ' + res.status);
    const age = /max-age=(\d+)/.exec(res.headers.get('cache-control') || '');
    certs = { keys: (await res.json()).keys, until: now() + (age ? +age[1] * 1000 : 3600_000) };
  }
  const key = certs.keys.find((k) => k.kid === kid);
  if (key || !retry) return key;
  certs.until = 0; // Google rotated its keys since we cached them
  return googleKey(kid, false);
}

/** The token's claims when it is a real, current Google sign-in for this app; else null. */
export async function verifyGoogleToken(token, clientId) {
  const parts = String(token || '').split('.');
  if (parts.length !== 3) return null;
  let header, claims;
  try {
    header = JSON.parse(new TextDecoder().decode(b64url(parts[0])));
    claims = JSON.parse(new TextDecoder().decode(b64url(parts[1])));
  } catch {
    return null;
  }
  if (header.alg !== 'RS256') return null;
  const jwk = await googleKey(header.kid);
  if (!jwk) return null;
  const key = await crypto.subtle.importKey(
    'jwk', jwk, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
  const signed = new TextEncoder().encode(parts[0] + '.' + parts[1]);
  if (!(await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, b64url(parts[2]), signed))) return null;
  if (!['accounts.google.com', 'https://accounts.google.com'].includes(claims.iss)) return null;
  if (claims.aud !== clientId) return null;
  if (!(claims.exp > now() / 1000)) return null;
  if (claims.email_verified !== true && claims.email_verified !== 'true') return null;
  if (!claims.sub || !claims.email) return null;
  return claims;
}

// ---- Sessions ----

async function sessionUser(req, env) {
  const m = /^Bearer ([0-9a-f]{64})$/.exec(req.headers.get('authorization') || '');
  if (!m) return null;
  return env.DB.prepare(
    `SELECT u.*, s.token_hash FROM sessions s JOIN users u ON u.id = s.user_id
     WHERE s.token_hash = ? AND s.expires_at > ?`)
    .bind(await sha256Hex(m[1]), now()).first();
}

async function signIn(req, env) {
  const body = await req.json().catch(() => ({}));
  const g = await verifyGoogleToken(body.idToken, env.GOOGLE_CLIENT_ID);
  if (!g) return json({ error: 'bad_token' }, 401);
  const t = now();
  await env.DB.prepare(
    `INSERT INTO users (id, email, name, photo, first_seen, last_seen, app_version, status)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(id) DO UPDATE SET email = excluded.email, name = excluded.name,
       photo = excluded.photo, last_seen = excluded.last_seen,
       app_version = coalesce(excluded.app_version, users.app_version)`)
    .bind(g.sub, g.email, clip(g.name, 200), clip(g.picture, 500), t, t, clip(body.appVersion, 40),
      // New people wait for the owner's OK while approval is on.
      env.APPROVAL === 'on' && g.email !== env.ADMIN_EMAIL ? 'pending' : 'active')
    .run();
  const user = await env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(g.sub).first();
  if (user.status === 'banned') return json({ error: 'banned', reason: user.ban_reason || '' }, 403);

  const token = hex(crypto.getRandomValues(new Uint8Array(32)));
  await env.DB.batch([
    env.DB.prepare('DELETE FROM sessions WHERE expires_at < ?').bind(t),
    env.DB.prepare(
      'INSERT INTO sessions (token_hash, user_id, device, created_at, expires_at) VALUES (?, ?, ?, ?, ?)')
      .bind(await sha256Hex(token), g.sub, clip(body.device, 100), t, t + SESSION_DAYS * 86400_000),
  ]);
  return json({ token, user: publicUser(user, env) });
}

const publicUser = (u, env) => ({
  id: u.id, email: u.email, name: u.name, photo: u.photo, status: u.status,
  admin: u.email === env.ADMIN_EMAIL,
});

// ---- Sync: newest snapshot wins, per kind (the app merges before it uploads) ----

// ?library=<ms>&history=<ms>...: a kind not newer than the time the phone
// already has comes back without its data, so syncs stay small.
async function getSync(req, env, user) {
  const have = Object.fromEntries(new URL(req.url).searchParams);
  const { results } = await env.DB.prepare(
    'SELECT kind, json, updated_at FROM user_data WHERE user_id = ?').bind(user.id).all();
  const out = {};
  for (const r of results) {
    out[r.kind] = Number(have[r.kind]) >= r.updated_at
      ? { updatedAt: r.updated_at }
      : { data: JSON.parse(r.json), updatedAt: r.updated_at };
  }
  return json(out);
}

async function putSync(req, env, user) {
  const body = await req.json().catch(() => null);
  if (!body || typeof body !== 'object') return json({ error: 'bad_body' }, 400);
  const writes = [];
  const { results: rows } = await env.DB.prepare(
    "SELECT kind FROM user_data WHERE user_id = ? AND kind LIKE 'listening:%'").bind(user.id).all();
  const phones = new Set(rows.map((r) => r.kind));
  for (const [kind, snap] of Object.entries(body)) {
    if (!KIND.test(kind) || !snap) continue;
    const listening = kind.startsWith('listening:');
    if (listening && !phones.has(kind)) {
      phones.add(kind);
      if (phones.size > MAX_PHONES) return json({ error: 'too_many_phones' }, 413);
    }
    const text = JSON.stringify(snap.data ?? null);
    const size = new TextEncoder().encode(text).length;
    if (size > (listening ? MAX_LISTENING : MAX_SNAPSHOT)) return json({ error: 'too_big', kind }, 413);
    const at = Number(snap.updatedAt);
    if (!Number.isFinite(at) || at <= 0) return json({ error: 'bad_time', kind }, 400);
    // A phone whose clock runs ahead must not win every future sync.
    // The phone cap is checked again inside the write itself, so parallel
    // requests can't each squeeze in a new phone.
    writes.push(env.DB.prepare(
      `INSERT INTO user_data (user_id, kind, json, updated_at)
       SELECT ?1, ?2, ?3, ?4
       WHERE ?2 NOT LIKE 'listening:%'
          OR EXISTS (SELECT 1 FROM user_data WHERE user_id = ?1 AND kind = ?2)
          OR (SELECT count(*) FROM user_data WHERE user_id = ?1 AND kind LIKE 'listening:%') < ?5
       ON CONFLICT(user_id, kind) DO UPDATE SET json = excluded.json, updated_at = excluded.updated_at
       WHERE excluded.updated_at > user_data.updated_at`)
      .bind(user.id, kind, text, Math.min(at, now()), MAX_PHONES));
  }
  if (writes.length) await env.DB.batch(writes);
  const { results } = await env.DB.prepare(
    'SELECT kind, updated_at FROM user_data WHERE user_id = ?').bind(user.id).all();
  return json({ updatedAt: Object.fromEntries(results.map((r) => [r.kind, r.updated_at])) });
}

// ---- Admin ----

async function listUsers(env, admin) {
  const { results } = await env.DB.prepare(
    `SELECT u.id, u.email, u.name, u.photo, u.first_seen, u.last_seen, u.app_version,
            u.status, u.ban_reason, u.id = ? AS self,
            (SELECT count(DISTINCT s.device) FROM sessions s
              WHERE s.user_id = u.id AND s.expires_at > ? AND s.device IS NOT ?) AS phones
     FROM users u ORDER BY u.last_seen DESC`)
    .bind(admin.id, now(), ADMIN_DEVICE).all();
  return json({ users: results });
}

async function setStatus(req, env, admin, status) {
  const body = await req.json().catch(() => ({}));
  if (!body.id || body.id === admin.id) return json({ error: 'bad_user' }, 400);
  const banned = status === 'banned';
  await env.DB.prepare('UPDATE users SET status = ?, ban_reason = ? WHERE id = ?')
    .bind(status, banned ? clip(body.reason, 300) || '' : null, body.id).run();
  return json({ ok: true });
}

// ---- Routes ----

async function route(req, env) {
  const path = req.method + ' ' + new URL(req.url).pathname;
  const page = { 'GET /': HOME_PAGE, 'GET /privacy': PRIVACY_PAGE, 'GET /admin': path === 'GET /admin' && adminPage(env) }[path];
  if (page) return new Response(page, { headers: { 'content-type': 'text/html; charset=utf-8', ...PAGE_HEADERS } });
  if (path === 'POST /auth/google') return signIn(req, env);

  const user = await sessionUser(req, env);
  if (!user) return json({ error: 'signed_out' }, 401);
  // Banned or waiting for approval: may only leave (sign out, delete the account).
  const leaving = path === 'POST /signout' || path === 'DELETE /me';
  if (user.status === 'banned' && !leaving) return json({ error: 'banned', reason: user.ban_reason || '' }, 403);
  if (user.status === 'pending' && !leaving) return json({ error: 'pending' }, 403);
  const isAdmin = user.email === env.ADMIN_EMAIL;

  switch (path) {
    case 'GET /me':
      await env.DB.prepare('UPDATE users SET last_seen = ?, app_version = coalesce(?, app_version) WHERE id = ?')
        .bind(now(), clip(req.headers.get('x-jarx-version'), 40), user.id).run();
      return json({ user: publicUser(user, env) });
    case 'POST /signout':
      await env.DB.prepare('DELETE FROM sessions WHERE token_hash = ?').bind(user.token_hash).run();
      return json({ ok: true });
    case 'DELETE /me':
      await env.DB.batch(['user_data', 'sessions'].map((t) =>
        env.DB.prepare(`DELETE FROM ${t} WHERE user_id = ?`).bind(user.id))
        .concat(user.status === 'banned'
          // A ban outlives the account: keep a bare record so signing in
          // again is refused (name and photo are dropped).
          ? env.DB.prepare('UPDATE users SET name = NULL, photo = NULL WHERE id = ?').bind(user.id)
          : env.DB.prepare('DELETE FROM users WHERE id = ?').bind(user.id)));
      return json({ ok: true });
    case 'GET /sync':
      return getSync(req, env, user);
    case 'PUT /sync':
      return putSync(req, env, user);
    case 'GET /admin/users':
      return isAdmin ? listUsers(env, user) : json({ error: 'not_admin' }, 403);
    case 'POST /admin/ban':
    case 'POST /admin/unban':
    case 'POST /admin/approve':
      if (!isAdmin) return json({ error: 'not_admin' }, 403);
      return setStatus(req, env, user, path.endsWith('/ban') ? 'banned' : 'active');
  }
  return json({ error: 'not_found' }, 404);
}

export default {
  async fetch(req, env) {
    try {
      // ponytail: one limit per address for everything; a shared Wi-Fi with
      // many JARX users stays far below it.
      if (env.LIMITER) {
        const ip = req.headers.get('cf-connecting-ip') || 'unknown';
        if (!(await env.LIMITER.limit({ key: ip })).success) return json({ error: 'slow_down' }, 429);
      }
      const res = await route(req, env);
      res.headers.set('x-content-type-options', 'nosniff');
      return res;
    } catch (e) {
      console.error(e);
      return json({ error: 'server' }, 500);
    }
  },
};

// ---- The owner's page: sign in with Google, see everyone, ban/unban ----

function adminPage(env) {
  return `<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>JARX users</title>
<script src="https://accounts.google.com/gsi/client" async></script>
<style>
body{font:15px system-ui,sans-serif;margin:0;padding:16px;background:#121212;color:#eee}
h1{font-size:22px}.wrap{overflow-x:auto}table{border-collapse:collapse;width:100%}
td,th{padding:8px;border-bottom:1px solid #333;text-align:left;vertical-align:middle;white-space:nowrap}
img{width:32px;height:32px;border-radius:50%}button{padding:6px 12px;border-radius:6px;border:0;cursor:pointer}
.ban{background:#c62828;color:#fff}.unban{background:#2e7d32;color:#fff}.muted{color:#999;font-size:13px}
</style></head><body>
<h1>JARX users</h1>
<div id="g_id_onload" data-client_id="${env.GOOGLE_CLIENT_ID}" data-callback="signedIn"></div>
<div class="g_id_signin"></div>
<p id="msg" class="muted"></p>
<div class="wrap"><table id="users"></table></div>
<script>
let token = sessionStorage.getItem('jarxAdmin');
const msg = (t) => { document.getElementById('msg').textContent = t; };
async function api(method, path, body) {
  const r = await fetch(path, { method, body: body && JSON.stringify(body),
    headers: { authorization: 'Bearer ' + token, 'content-type': 'application/json' } });
  const j = await r.json();
  if (!r.ok) throw new Error(j.error || r.status);
  return j;
}
async function signedIn(resp) {
  const r = await fetch('/auth/google', { method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ idToken: resp.credential, device: '${ADMIN_DEVICE}' }) });
  const j = await r.json();
  if (!r.ok) return msg('Sign-in failed: ' + j.error);
  token = j.token;
  sessionStorage.setItem('jarxAdmin', token);
  load();
}
const when = (ms) => (ms ? new Date(ms).toLocaleString() : '');
function cell(tr, v) { const td = tr.insertCell(); if (v instanceof Node) td.append(v); else td.textContent = v == null ? '' : v; }
async function load() {
  if (!token) return msg('Sign in with the owner account.');
  let j;
  try { j = await api('GET', '/admin/users'); }
  catch (e) { return msg(e.message === 'not_admin' ? 'This Google account is not the owner.' : 'Could not load users: ' + e.message); }
  msg(j.users.length + ' users');
  const t = document.getElementById('users');
  t.innerHTML = '<tr><th></th><th>Name</th><th>Email</th><th>First seen</th><th>Last seen</th><th>Version</th><th>Phones</th><th>Status</th><th></th></tr>';
  for (const u of j.users) {
    const tr = t.insertRow();
    const img = new Image(); img.referrerPolicy = 'no-referrer'; if (u.photo) img.src = u.photo;
    cell(tr, img); cell(tr, u.name); cell(tr, u.email); cell(tr, when(u.first_seen)); cell(tr, when(u.last_seen));
    cell(tr, u.app_version); cell(tr, u.phones);
    cell(tr, u.status === 'banned' ? 'Banned' + (u.ban_reason ? ': ' + u.ban_reason : '')
      : u.status === 'pending' ? 'Waiting for approval' : 'Active');
    if (u.self) { cell(tr, 'You'); continue; }
    const td = tr.insertCell();
    if (u.status === 'pending') {
      const a = document.createElement('button');
      a.textContent = 'Approve'; a.className = 'unban'; a.style.marginRight = '8px';
      a.onclick = async () => { await api('POST', '/admin/approve', { id: u.id }); load(); };
      td.append(a);
    }
    const b = document.createElement('button');
    if (u.status === 'banned') {
      b.textContent = 'Unban'; b.className = 'unban';
      b.onclick = async () => { await api('POST', '/admin/unban', { id: u.id }); load(); };
    } else {
      b.textContent = 'Ban'; b.className = 'ban';
      b.onclick = async () => {
        const reason = prompt('Reason shown to ' + (u.name || u.email) + ':');
        if (reason === null) return;
        await api('POST', '/admin/ban', { id: u.id, reason }); load();
      };
    }
    td.append(b);
  }
}
load();
</script></body></html>`;
}

// No framing by other sites, scripts only from here and Google's sign-in.
const PAGE_HEADERS = {
  'content-security-policy': [
    "default-src 'self'",
    "script-src 'self' 'unsafe-inline' https://accounts.google.com/gsi/client",
    "style-src 'self' 'unsafe-inline' https://accounts.google.com/gsi/style",
    'frame-src https://accounts.google.com/gsi/',
    "connect-src 'self' https://accounts.google.com/gsi/",
    'img-src https: data:',
    "frame-ancestors 'none'",
  ].join('; '),
  'x-frame-options': 'DENY',
  'referrer-policy': 'no-referrer',
  'cross-origin-opener-policy': 'same-origin-allow-popups',
};

// ---- Public pages Google asks for (homepage, privacy policy) ----

const STYLE = `<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<style>body{font:16px/1.6 system-ui,sans-serif;max-width:720px;margin:0 auto;padding:24px 16px;background:#121212;color:#eee}
a{color:#ff7ab6}h1{font-size:26px}h2{font-size:19px;margin-top:28px}</style>`;

const HOME_PAGE = `<!doctype html><html><head>${STYLE}<title>JARX</title></head><body>
<h1>JARX</h1>
<p>JARX is a free music player for Android, made by Arnav Jaiswal. It is open source
(GPL-2.0), built on BloomeeTunes:
<a href="https://github.com/SofDev007/Jaiswal-audio">github.com/SofDev007/Jaiswal-audio</a>.</p>
<p>You sign in with Google so your playlists, Liked songs and what JARX learned about
your taste follow you to any phone.</p>
<p><a href="/privacy">Privacy policy</a> · Contact: arnavjaiswal.aj@gmail.com</p>
</body></html>`;

const PRIVACY_PAGE = `<!doctype html><html><head>${STYLE}<title>JARX privacy policy</title></head><body>
<h1>JARX privacy policy</h1>
<p>Last updated 13 November 2026. JARX is run by Arnav Jaiswal (arnavjaiswal.aj@gmail.com).</p>

<h2>What JARX stores about you</h2>
<ul>
<li><b>From your Google account:</b> your Google account id, email address, name and
profile photo. JARX never sees your Google password.</li>
<li><b>Your music:</b> your playlists, Liked songs, what JARX learned about your taste
(artists, languages and moods you play, and when), and how long you have listened.</li>
<li><b>Your phones:</b> the phone model name, the JARX version, and when you first and
last used JARX.</li>
</ul>

<h2>Why</h2>
<p>To sign you in, to bring your music back on another phone, to suggest songs you
will like, and so the owner can stop accounts that misuse JARX.</p>

<h2>Where it is kept</h2>
<p>On a server run on Cloudflare (Cloudflare Workers and D1). Connections are encrypted
(HTTPS). Your sign-in on the phone is kept in Android's secure storage.</p>

<h2>Who sees it</h2>
<p>Only you and the owner of JARX. It is not sold, not used for ads and not given to
anyone else, unless the law requires it.</p>

<h2>Other services JARX talks to</h2>
<p>Songs, pictures and lyrics come from music services through JARX plugins, which
contact those services directly from your phone (for example YouTube). JARX looks up
your country from your internet address to choose plugins that work there, and
downloads plugins from GitHub. Those services have their own privacy policies.</p>

<h2>Deleting your data</h2>
<p>In JARX, open Settings › Account › Delete my account. That removes everything above
from the server at once. You can also email arnavjaiswal.aj@gmail.com and ask for
deletion. Signing out keeps your music on the phone but ends that phone's sign-in.</p>

<h2>Children</h2>
<p>JARX is not meant for children under 13.</p>

<h2>Changes</h2>
<p>If this policy changes, the new version will be posted here with a new date.</p>
</body></html>`;
