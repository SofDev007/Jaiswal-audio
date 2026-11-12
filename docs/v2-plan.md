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

Each step is its own build with a phone test, as in v1. Version numbers become
2.0.0+N.

## Still separate

- **First-run redesign:** pending the user's picks. Google login will become
  one of its steps ("Sign in to keep your music on every phone · Skip").
- **Old is Gold duplicates:** pending the user's choice (group only, or group +
  delete extra copies).
