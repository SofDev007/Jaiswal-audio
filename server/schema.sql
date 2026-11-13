-- JARX server database (Cloudflare D1). Safe to run again.

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,                    -- Google account id ("sub")
  email TEXT NOT NULL,
  name TEXT,
  photo TEXT,
  first_seen INTEGER NOT NULL,            -- ms since epoch
  last_seen INTEGER NOT NULL,
  app_version TEXT,
  status TEXT NOT NULL DEFAULT 'active',  -- active | banned
  ban_reason TEXT
);

CREATE TABLE IF NOT EXISTS sessions (
  token_hash TEXT PRIMARY KEY,            -- sha256 of the token the app holds
  user_id TEXT NOT NULL REFERENCES users(id),
  device TEXT,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS sessions_user ON sessions(user_id);

-- One row per user and kind: 'library' (playlists + Liked), 'taste'
-- (what JARX learned), 'listening' (listening time). Newest wins.
CREATE TABLE IF NOT EXISTS user_data (
  user_id TEXT NOT NULL REFERENCES users(id),
  kind TEXT NOT NULL,
  json TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, kind)
);
