# JARX V2 plan

**Status:** proposal (2026-11-09). Nothing is built until the user approves.

V2 turns JARX from an app that lives on one phone into an app with an
**account**: you sign in with Google, your music follows you to any phone, and
JARX AI can talk to you. It builds on v1 (builds 23–32) and on the approved
recommendations plan (`docs/recommendations-v2-plan.md`, Layer 3).

## What V2 contains

1. **Security first (V2.0).** The quick fixes from the post-v1 security
   survey, done before any account or server exists:
   - Stop allowing plain `http` traffic everywhere (keep it only for Last.fm,
     which needs it).
   - Turn off Android's automatic app backup, so the database can't be pulled
     off the phone with a cable.
   - Check every plugin file against a fingerprint (sha256) published in the
     plugin list before installing it. This stops a tampered plugin.
   - Run the planned scans (MobSF, gitleaks, osv-scanner, cargo audit) and
     fix what they find.
2. **Google login (V2.1).**
   - Optional: "Continue without an account" keeps today's JARX exactly as is.
   - Signing in shows your name and photo on Home, and "Created by Arnav" on
     playlists you made.
   - Signing out keeps everything on the phone.
3. **Your music on every phone (V2.2).**
   - Playlists and Liked songs are saved to your account and restored when you
     sign in on another phone (your sister's phone is the test case).
   - Two phones stay in sync: changes upload in the background and download
     on start.
   - Downloads do **not** sync (files stay on the phone that downloaded them).
4. **Your corner (V2.3).** The stats screen planned on 29 Oct:
   - your top artists and how much you played them
   - total minutes listened
   - a silly comparison ("1,240 min = 31 Titanic movies")
   - It greets you by your Google name.
   - Listening time isn't recorded today, so recording starts first (it can
     ship in the very next build, so data builds up before the screen exists).
5. **JARX AI, part 1: mood tags (V2.4).**
   - A free AI labels each song's moods (romantic, sad, dance, ...).
   - The labels are stored on the server and shared by all users, so each song
     is labelled once.
   - They replace today's word-based mood guess and make autoplay and mixes
     better.
6. **JARX AI, part 2: the companion chat (V2.5).**
   - Off until you turn it on, with a clear privacy note.
   - Warm and honest. It picks real songs from your mood. It shows the
     Tele-MANAS helpline (14416) if someone sounds really low. It has
     "Report this reply".
   - A short profile summary lives on the phone, where you can see, correct or
     delete it.
   - Raw chats are not stored on the server.

## The server: one small Cloudflare Worker

The AI keys must never be inside the APK (the repo is public), so V2 needs a
small server. The proposal is **one** server for everything:

- **Cloudflare Workers** (free plan: about 100,000 requests a day), with:
  - **D1** (Cloudflare's database, free 5 GB): accounts, playlists, liked
    songs, mood tags
  - Secrets storage for the AI keys
- **Login:** the app signs in with Google on the phone; the Worker checks
  Google's sign-in token and gives the app its own session. No passwords,
  nothing stored but your Google id, name, email and photo.
- **AI fallback chain** (approved 31 Oct): Groq, then OpenRouter, then
  Cloudflare Workers AI, then no AI (Layers 1 and 2 still work). There's a
  daily limit per device so one phone can't use up the free quota.

The alternative is **Firebase** (Google's ready-made login + database). It is
quicker to set up for login and sync. But it adds Google's SDK to the app
(bigger APK) and puts the data in a second place, since the AI gateway has to
be on Cloudflare anyway. The recommendation is Cloudflare for everything.

## What the user has to set up (accounts I can't create)

- A **Google Cloud project**: OAuth consent screen and an Android OAuth client
  for `com.jaiswal.jarx` with the signing key's SHA-1 (from key 2ca44331).
- A **Cloudflare account** (free): to deploy the Worker and D1.
- **API keys:** Groq and OpenRouter (free tiers).
- A **privacy policy** page: required by Google sign-in and the Play Store.
  JARX can host it on GitHub Pages; I can write the text.

## Order

1. V2.0 security fixes, plus "start recording listening time".
2. V2.1 Google login + Worker + D1.
3. V2.2 sync of playlists and Liked.
4. V2.3 Your corner.
5. V2.4 mood tags.
6. V2.5 JARX AI chat.
7. V2.6 JARX Connect (control one device from another), before or with the
   desktop app.
8. V2.7 Jam (listen together with friends by link).

Each step is its own build with a phone test, as in v1. Version numbers become
2.0.0+N.

## Still separate

- **First-run redesign:** pending the user's picks. Google login will become
  one of its steps ("Sign in to keep your music on every phone · Skip").
- **Old is Gold duplicates:** pending the user's choice (group only, or group +
  delete extra copies).

## V2.1 design (decided 2026-11-13)

Decisions: Cloudflare for the server; **login is mandatory** (no listening
without signing in); sync = all playlists + Liked + what JARX learned about
the user (Layer 2 weights, time-of-day moods, languages, listening time); the
owner can see every user and ban anyone. About 0–60 users.

### Server (one Cloudflare Worker + D1 database)

Tables:

- `users`: Google id, email, name, photo, first seen, last seen, app
  version, status (`active`, `pending`, `banned`), ban reason.
- `sessions`: a random session token (stored hashed), user, device, expiry.
- `user_data`: one row per user holding three JSON snapshots (playlists +
  Liked, taste, listening time) and when each was last updated.

Endpoints:

- `POST /auth/google`: the app sends Google's sign-in token; the Worker checks
  it with Google's public keys, creates or updates the user, and returns a
  JARX session token, unless the user is banned (or pending, see below).
- `GET /me`: who am I, am I still allowed. Called at start and every few hours.
- `GET /sync`, `PUT /sync`: download / upload the snapshots (newest wins).
- `DELETE /me`: delete my account and data (Play Store requires this).
- `/admin`: the owner's page (below).

### Admin page (for the owner only)

A web page at the Worker's address, opened in any browser. You sign in with
Google; only the owner's email gets in. It shows every user (photo, name,
email, first and last seen, app version, phones) with **Ban** / **Unban**
(with a reason) and **Approve** buttons.

### In the app

- **Sign-in screen** before anything else (JARX logo, "Continue with Google").
  Without signing in, nothing plays.
- The session is kept in Android's secure storage (Keystore).
- **Offline:** once signed in, JARX works offline (downloads) for up to 10 days
  before it must reach the server again to confirm the account.
- **Ban:** checked at start and every few hours while online. A banned user is
  signed out at once and sees "This account can't use JARX" with the reason.
- **Settings › Account:** name and photo, Sign out, Delete my account.
- **Sync:** after sign-in on a new phone, playlists, Liked and the learned
  taste come back. Changes upload in the background (a few seconds after they
  happen) and download at start.

### Honest limits

- The JARX code is public (GPL), so someone could build their own copy with
  the login removed. A ban stops the account in the real JARX app; it can't
  stop a person who builds their own version.
- A banned person could sign in with a different Google account. An
  **"approve new users"** switch stops that: new accounts wait as `pending`
  until the owner approves them on the admin page.
- Storing names, emails and listening taste needs a privacy policy, and the
  app must offer account deletion.

### Owner setup (needs the owner's accounts)

1. **Google Cloud** (console.cloud.google.com): new project "JARX" →
   OAuth consent screen (External, app name JARX, your email; publish it) →
   Credentials:
   - OAuth client ID, type **Android**: package `com.jaiswal.jarx`, SHA-1
     `E1:B1:43:97:FE:6B:0B:BB:19:CB:71:54:90:3A:C9:C2:24:51:D5:8D`.
   - OAuth client ID, type **Web application** (name "JARX server"): copy its
     **Client ID** (not secret; it goes into the app and the Worker).
2. **Cloudflare**: create a free account, then run `npx wrangler login` once
   so the Worker and database can be deployed from this PC.

### Setup done (2026-11-13)

- Google Cloud project `jarx-514521` (number 269249413715). Clients:
  Android `269249413715-3u61455uug0p8t3j84s38as09eh5tpeg`, Web ("JARX server")
  `269249413715-d5fb6ac76r9jngrmfadrk4oausldiv22` (both `.apps.googleusercontent.com`).
- Cloudflare: Worker live at https://jarx.jarx-backend.workers.dev (pages `/`,
  `/privacy`, `/admin`); D1 database `jarx` (ad415196-419e-47b8-a74a-9871ce8a3400, APAC).
- Server code: `server/` (Worker `src/index.js`, `schema.sql`, `test.mjs`;
  run `node test.mjs`). No approval mode: `pending` status is unused.

## V2.6 JARX Connect and V2.7 Jam (planned 2026-11-13, user approved the order)

Both need a live connection between devices: one Cloudflare Durable Object
("room") with WebSockets on the existing Worker. Free plan, fine for ~60 users.

### V2.6 JARX Connect: control one device from another (about one build)

- Every JARX signed in with the same account joins that account's room while
  it is open.
- Other devices show "Playing on <device> · <song>"; tapping it opens a remote:
  play/pause, next/previous, seek, play any song or playlist there, add to its
  queue, and volume (the playing phone sets its own media volume).
- "Play here" moves the song to this device at the same position and stops it
  on the other one.
- Audio always plays and streams on the playing device; the remote only sends
  small commands.
- Main use: desktop app plays, phone is the remote (and the other way round).
- Limits: the playing device must have JARX open or playing in the background
  (waking a closed app would need push notifications). Desktop Google sign-in
  goes through the browser (part of the desktop work).

### V2.7 Jam: listen together in real time (about two builds, after Connect)

- Start a Jam: a link `https://jarx.jarx-backend.workers.dev/jam/<code>` and a
  QR code; the link opens JARX directly (Android App Links, `assetlinks.json`
  served by the Worker).
- One shared queue; anyone adds songs; the host chooses whether others may
  skip/pause. Members shown with their Google photos. Ends when the host leaves.
- Each phone streams the song itself; JARX agrees on one clock and corrects
  drift by seeking (target: within about half a second).
- Limits: every listener needs JARX and an approved account (approval is on);
  a link opened without JARX shows a "Get JARX" page. Not sample-perfect (not
  for two speakers in one room). A song missing on a friend's source (e.g.
  JioSaavn outside India) plays from another source via the existing
  replacement logic. Downloaded files are never sent between phones.
