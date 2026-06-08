# PocketStreams Roku — Session Handoff

> Handoff from: current session  
> Project: `/Users/jdj/Documents/code/PocketRadio/pocket-radio-roku/`  
> Reference spec: `../HANDOFF.md` (canonical API + milestone plan)

---

## 1. What Was Done This Session

### M3 — Up Next (podcasts) ✅ COMPLETE

| Feature | Status | Notes |
|---------|--------|-------|
| Up Next queue fetch | ✅ | `POST /up_next/sync` via relay → list episodes with title, URL, podcast, uuid, published, playedUpTo, duration |
| Up Next list UI | ✅ | `UpNextList` (`MarkupList` + `UpNextRow` component). Shows title + podcast + time remaining. Focus = `BG_SELECTED` (`0x1E333DFF`) + bold white text. |
| Resume position | ✅ | `PlayStart` set from `playedUpTo` before `Audio.control = "play"` |
| Position save | ✅ | Throttled ~30s timer (`onSaveTimer`) + immediate save on pause/stop. Posts `updateEpisode` via relay. |
| Auto-advance on finish | ✅ | `onAudioState` → `state="finished"` → mark completed (status 3), `removeFromUpNext`, `advanceQueue` plays next episode |
| playNow reorder | ✅ | `onEpisodeSelected` fires `playNowUpNext` relay call before playing (server-side queue reorder) |
| Default view | ✅ | After login, app opens `Up Next` instead of Favorites |
| Menu updated | ✅ | `Up Next` \| `Radio Favorites` \| `Browse Stations` \| `Search Stations` \| `Log Out` |
| Device ID persistence | ✅ | Generated once via `GetChannelClientId()`, stored in `roRegistrySection("device")` |

### Styling fixes (from prior session, now fully themed)
- `MainScene.xml` — `BG_DEEP` background, `BG_ELEVATED` header bar, `TEXT_SECONDARY` status at bottom
- `StationList.xml` — migrated from `LabelList` to `MarkupList` + `StationRow`
- `StationRow` / `UpNextRow` — custom focus with `BG_SURFACE`/`BG_SELECTED` + bold text (no Roku default highlight)

---

## 2. Current App State

| Feature | Status |
|---------|--------|
| M1 — Skeleton + audio | ✅ |
| M2 — Login + persistence | ✅ |
| **M3 — Up Next** | **✅** |
| M4 — Radio (favorites, browse, search, add/remove, play) | ✅ partial (no tracklist, no station detail) |
| M5 — New Releases + detail | ❌ Not started |
| M6 — Skip settings, scrub/seek UI, Now Playing screen, icons/splash | ❌ Not started |

---

## 3. Architecture

### Key Files
- `components/MainScene.xml` + `.brs` — Root scene, mode/state management, key events, Up Next + radio playback
- `components/StationList.xml` + `.brs` — Radio station list (`MarkupList` + `StationRow`)
- `components/UpNextList.xml` + `.brs` — Podcast episode list (`MarkupList` + `UpNextRow`)
- `components/StationRow.xml` + `.brs` — Custom row for stations
- `components/UpNextRow.xml` + `.brs` — Custom row for episodes (title + podcast + time remaining)
- `components/tasks/*.xml` + `.brs` — Task nodes for network I/O
- `source/main.brs` — Entry point
- `source/registry.brs` — Auth persistence
- `source/secrets.brs` — Relay URL, Supabase keys, radio-browser URL

### Relay (server-side, no deploy needed)
`../supabase/functions/pc-relay/index.ts` already implements: `login`, `upNext`, `podcastEpisodes`, `updateEpisode`, `upNextChange`, `namedSettings`, `podcastList`. Roku app calls these via JSON → relay translates to/from protobuf.

---

## 4. Next Milestone

**M4 polish** or **M5 (New Releases + episode detail)** — confirm with user.

### M4 remaining gaps
- Tracklist overlay for KCRW/KEXP (§6.11)
- Station detail screen (metadata: country, codec, bitrate, votes, homepage)

### M5 — New Releases + Detail
1. `POST /user/podcast/list` → subscribed podcast UUIDs + titles
2. `GET /cache.pocketcasts.com/mobile/podcast/full/{uuid}` → episodes (JSON, follows 302)
3. Filter episodes `published >= now-14d`, sort by published desc, merge across podcasts
4. `UpNextList`-style UI for New Releases list
5. Episode detail screen: show notes from `GET /cache.../show_notes/full/{uuid}` (§6.8)

### M6 — Polish (can be interleaved)
- Skip settings read (`namedSettings` relay action)
- Scrub/seek UI for podcasts (finite duration) vs play/pause-only for live streams
- Now Playing screen with artwork (`https://static.pocketcasts.com/discover/images/130/{podcastUUID}.jpg`)
- Channel icons + splash screens at correct Roku sizes

---

## 5. Notes / Gotchas

- **Test device:** `10.99.99.50`, username `rokudev`. Sideload via `make` → `channel.zip` → POST to dev installer. Debug: `telnet 10.99.99.50 8085`.
- `UpNextRow` uses `FormatTime` (local to component). `MainScene.brs` defines `FormatDuration`/`ZeroPad` for future use.
- Per-podcast episode resolution (`podcastEpisodes` action) is implemented in the relay but **not called client-side** — the `upNext` sync data usually has `playedUpTo`+`duration`. If missing, episodes resume from 0.
- `advanceQueue` removes the first child from the local `ContentNode` and reassigns `list.content` to force refresh. It does NOT reload from server.
- `m.currentEpisode` tracks the playing podcast; `m.currentStation` tracks the playing radio stream. Position save only fires when `m.currentEpisode <> invalid`.
