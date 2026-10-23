# JioSaavn playback and slow search: findings and plan

Investigated 2026-10-23 (phone disconnected before search could be timed).

## 1. Why JioSaavn is missing in JARX

- The JioSaavn music plugin exists in the same catalogue Bloomee uses
  (`bloom-factory`, via `hemantkarya.github.io/BloomeeTunes/repositories.json`).
- Its manifest restricts it to India: `"country_allowlist": ["IN"]`
  (read from `jisaavn.bex`, version 2).
- First-run setup installs only plugins allowed in the country chosen on the
  welcome screen. That screen guesses the country from the phone's language
  (`resolveCountryCodeFromDeviceLocale`): an English (US) phone becomes
  "United States (US)". On both installs I pressed Continue from the PC
  without changing it, so JioSaavn was skipped. My mistake: on your own
  install of Bloomee you would have picked India.
- JARX code is not missing anything: once the country is India, JioSaavn
  installs and plays exactly as in Bloomee.

### The "jisavan" typo

- The plugin's own ID and name, set by its author, are
  `content-resolver.bloomfactory.jisaavn` and `jisaavn` (missing "o").
- The ID must stay as it is: changing it would break installs and updates
  from the catalogue.
- JARX can show the correct name, "JioSaavn", wherever a plugin name is
  displayed (Plugin Manager, Plugin Defaults, album/artist/playlist source
  labels, import screen) through a small display-name map for known plugin
  IDs.

## 2. Why search is slow (44 s)

Search sends one request to the active plugin (`ContentBloc._onSearch`), so
the time is that one plugin call. Plugin requests run one at a time per
plugin (the plugin lock in `rust/src/api/plugin/plugin.rs`). Contributors
seen on the realme 5 Pro:

1. **Queueing behind other work on the same plugin.** At app start YouTube
   Music also loads the Home sections and, since the Home redesign, the
   For you row (radio, artist details, related artist and a match on the
   other plugin: about five calls). A radio call took 26 s on mobile data.
   A search typed during that time waits for all of it.
2. **Trace-level Rust logging** wrote thousands of lines during every plugin
   call. Fixed in build 10 (capped at warnings).
3. **Slow mobile data** (Wi-Fi off; single requests of 14–19 s seen).
4. YouTube Music search itself makes several HTTP requests per query.

## Plan (needs approval)

### A. Get JioSaavn now (no code, 2 minutes, on the phone)
1. JARX → Settings → Language & Country → India (or turn on Auto Detect).
2. Settings → Plugins → repository → install **jisaavn**.
3. Settings → Plugin Defaults → choose JioSaavn for Discover/search if you
   want it first (YouTube Music stays as a resolver).

### B. Code changes
1. **Country default:** stop guessing the country from the phone language;
   default to India for JARX (the app's `defaultCountryCode` is already
   `IN`), keeping the picker.
2. **Install newly allowed plugins:** when the country changes, install
   catalogue plugins that became allowed (the app-open sync only updates
   plugins already installed today).
3. **Display name fix:** show "JioSaavn" for `jisaavn`.
4. **Search first:** don't let background work hold up a search.
   - Start the For you row only after the Home sections have loaded, and
     cache its result on the device so it refreshes at most every few hours
     instead of on every launch.
   - Measure: log how long each search takes (queue wait vs plugin time).
5. Then re-measure search on Wi-Fi and mobile data, with JioSaavn and with
   YouTube Music, and report the numbers.

### Questions
- Country India: yes?
- Default search source: JioSaavn first, or keep YouTube Music first?
