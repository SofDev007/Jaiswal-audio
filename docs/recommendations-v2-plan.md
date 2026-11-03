# JARX recommendations v2: "JARX knows your mood"

Status: plan, waiting for approval. Layer 1 is planned for build 26.
Written 2026-10-31 from the user's idea (mood-aware music, a personal AI
companion, taste from playlists) plus the earlier Layer 1/2/3 agreement.

## The signature feature

JARX should feel like it *gets* the listener. It should know the mood of every
song, learn what each person plays in which mood and at what time, and later
let them simply say how they feel and get the right music.

That is built in three layers. Each layer is useful on its own, and each one
feeds the next.

| Layer | What | Where it runs | When |
|---|---|---|---|
| 1 | Good candidates, song "cards" (language + mood), autoplay that never runs dry | Phone | Build 26 |
| 2 | A model that learns *this* user (plays, skips, likes, playlists, time of day) | Phone | Build 27+ |
| 3 | JARX AI: mood tagging with an AI, chat companion, mood mixes | Small free server + free AI models | V2 (with Google login) |

## What is wrong today (measured 2026-10-29)

- JioSaavn "radio" (`reco.getreco`) returns only 11–16 songs and no next page.
  They are mostly the same artist or composer: 9 of 11 for "Tum Hi Ho" were
  Mithoon. Re-releases of the seed song come back too, along with off-mood
  songs (a devotional song after a ghazal).
- The ranker allows 2 songs per artist, so most of that list is thrown away,
  and autoplay starves.
- The weights are fixed by hand, so nothing really learns the user.
- Language is guessed from the script, so Hindi written in English letters
  counts as English.

## Layer 1 (build 26)

1. **Candidates from more than one source, in parallel**
   - YouTube Music radio becomes the main source for every seed. A JioSaavn
     song is matched to YouTube Music by title, artist and length; the
     cross-plugin matching already exists.
   - JioSaavn `reco`, the artist's top tracks and one related artist are extra
     sources.
   - Each source gets its own timeout. Radio results are cached per seed for
     24 h, so replaying a song doesn't wait on the network again.
2. **One song, one entry**
   - Normalise titles: drop "(From …)", "- New Version", "Reprise", year and
     label noise.
   - Treat songs as the same if their titles match, their lengths are within
     4 s and they share an artist. This follows the JioSaavn plugin's
     `rank.rs`.
3. **Adaptive variety**
   - Normally 2 songs per artist per batch.
   - When the pool is thin, allow 3, so autoplay never starves.
   - Never the same artist twice in a row.
4. **Song cards: language and mood v0, with no AI**
   - **Language:** use JioSaavn's `language` field. Otherwise use the
     language JARX has already learned for that artist. Only then fall back
     to the user's languages setting (Hindi, English, Punjabi).
   - **Mood v0, from cheap signals:**
     - keywords in the title or album (sad, lofi, remix, dance, party,
       unplugged, bhajan/aarti → devotional)
     - JioSaavn tags
     - **the names of the user's playlists** (songs in "Soothing" lean cozy;
       songs in "Party" lean dance)
   - Stored in a small `SongCard` table (song key → language, moods, tempo
     hint, source of each tag), so Layer 3 can overwrite the tags with better
     AI ones later.
   - Moods: sad, romantic, happy, joyful, dance, cozy, moody, uplifting, plus
     calm, energetic and devotional. Devotional is mainly there so it can be
     filtered out.
5. **Autoplay that never stops**
   - Start gathering when a song starts, not when the queue is nearly empty.
   - If every source fails, fall back to liked songs and the top artists'
     songs from history.
6. **Languages setting**
   - Settings → Recommendations → Languages, default Hindi, English and
     Punjabi.
   - Songs in other languages drop to the bottom, unless the user plays them.
7. **Measured, not guessed.** These are counted on the phone:
   - refill success rate
   - time to the first suggestion
   - early-skip rate (< 20 s) of recommended songs
   - share of picks that match the seed's language

   A small "Recommendation health" screen in Settings shows them, so every
   build can be compared with the last.

Tests: title normalisation, dedupe, adaptive cap and mood v0 keywords, each
as a small unit test file. Then a device test on JioSaavn and YouTube Music
seeds, with autoplay running for 20 minutes.

## Layer 2 (build 27+): learns this user

- **Outcomes per recommended song:**
  - played > 20 s → positive
  - skipped < 20 s → negative
  - liked, added to a playlist or replayed → strong positive
  - "Never suggest" → hard negative
- **Features:**
  - artist affinity
  - language
  - mood
  - era
  - source
  - similarity to the seed
  - newness
  - **time of day and day of week**
- **The model:** a small logistic-regression model, updated after every song,
  replaces the fixed weights. It is tiny, works offline, and its "why this
  song" reasons stay explainable.
- **Cold start from playlists (the user's idea):**
  - On the first run, JARX reads the user's own playlists, plus imported
    Spotify, YouTube and CSV playlists, and builds a starting profile from
    them: top artists, languages, moods and eras.
  - With no playlists, it starts from the languages setting and learns as the
    user listens.
- **Mood patterns:** "romantic at night", "dance on Saturdays", "cozy on rainy
  mornings" become weights. Home's mood chips and "For you" use them.

## Layer 3 (V2): JARX AI

- **AI mood tags.** A free AI labels each song's moods from its title, artist,
  album and lyrics. JARX already has a lyrics plugin.
  - Tags are cached on the server and shared by all users, so each song is
    classified once.
  - This replaces mood v0.
- **The companion chat.** The user can talk about anything. The AI:
  - reads their mood from the conversation
  - picks a mix from songs that **really exist**: it names moods and seeds,
    and JARX finds the songs, so the AI never invents songs
  - learns how the user talks and feels over time
- **Personality: warm, encouraging, honest.** "Always positive" in spirit,
  but not dismissive.
  - If someone sounds really low, it stays kind.
  - It offers calming music.
  - It shows a helpline: Tele-MANAS 14416 in India.
  - It is not a therapist.
- **Memory**
  - A short profile summary is kept **on the phone**. The user can see,
    correct or delete it.
  - Raw chats are not stored on the server.
- **Consent**
  - Chat is off until the user turns it on.
  - The privacy note says chats go to an outside AI provider, and that some
    free tiers use data to improve their products.
  - Never send name, email or contacts.
- **Play Store.** Apps with AI chat need a way to report a bad AI reply.
  Planned as a "Report this reply" option on a long-press.
- **Name ideas:** JARX AI, Jax, Aura, Vibe, Saathi ("companion"). The user
  decides.

### Free models with fallback

Keys must **never** be inside the APK: the APK and repo are public, so anyone
could take the keys and use up the free limits. So there is one tiny gateway on
**Cloudflare Workers** (free plan: about 100,000 requests a day). It:

- holds the keys
- tries the providers in order
- applies a per-device daily limit

That gateway is the first piece of the V2 server.

Fallback order:

1. **Groq.** Fast, with about 1,000 requests a day per model on the free tier
   (e.g. `gpt-oss-120b`), and other models as extra capacity.
2. **Google Gemini Flash-Lite.** Its free tier is good with Hindi and
   Hinglish. But free-tier data may be used to improve Google's products, so
   use it for **song mood tagging** (not personal), and for chat only if the
   user agreed.
3. **OpenRouter `:free` models.** 50 requests a day, or 1,000 a day after a
   one-time $10 credit purchase.
4. **Cloudflare Workers AI.** 10,000 "neurons" a day, in the same place as the
   gateway.
5. **No AI at all.** JARX still answers with a mood mix from Layers 1 and 2,
   and a friendly "JARX AI is taking a break" note.

All free limits are shared by everyone using JARX. That is fine for the user,
friends and family (tens of people), not for thousands. Limits change often:
check each provider's own rate-limit page when Layer 3 starts.

## Order and approvals

1. Approve this plan.
2. Build 26: Layer 1, then device test and the health screen numbers.
3. Build 27+: Layer 2.
4. V2: Google login + gateway, then Layer 3 (mood tags first, chat second).
