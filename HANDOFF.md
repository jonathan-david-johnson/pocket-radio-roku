# PocketRadio for Roku — Build Handoff

> Seed doc for a fresh session. Goal: build a Roku channel with **feature parity to the macOS menubar app** (NOT the full iOS app). Self-contained: every endpoint, protobuf wire format, key, and credential needed is below.

---

## 1. Goal & Scope

Build a Roku channel ("PocketStreams") that plays:
- The user's **Pocket Casts Up Next** podcast queue (with resume position + progress sync).
- The user's **favorite radio streams** (from Supabase → radio-browser.info).

Match the **menubar app** feature set, listed in §8. Do **not** attempt full iOS-app features (folders, downloads, filters, etc.).

The macOS menubar app is the reference implementation. If its source is present in the workspace at `../pocket-radio-menubar/`, treat `PocketRadio/Services/APIService.swift` as the canonical API spec and `PocketRadio/View Models/PlayerViewModel.swift` as the canonical playback/state logic. Everything essential from those files is transcribed below so this doc stands alone.

---

## 2. Roku device & toolchain

- **Test device (dev mode ON):** `http://10.99.99.50`  — username `rokudev`, password = whatever you set when enabling dev mode (ask the user if needed).
- **Sideload:** zip the channel (`manifest` + `source/` + `components/` + `images/` at the zip root, no wrapping folder) and POST it at the **Development Application Installer** web UI: `http://10.99.99.50` → Upload → Install. Or script it with curl (digest auth):
  ```bash
  curl -s --user "rokudev:PASSWORD" --digest \
    -F "mysubmit=Install" -F "archive=@channel.zip" \
    http://10.99.99.50/plugin_install | grep -o 'Install Success\|Identical\|Failed'
  ```
- **Debug console:** `telnet 10.99.99.50 8085` — BrightScript `print` output + crash backtraces land here. This is your primary debugging tool. **There is no emulator** — all testing is on the physical device.
- **Language/UI:** BrightScript + **SceneGraph** (XML components + a render thread). 10-foot UI driven by the Roku remote (D-pad + OK + Back + `*`/Options + transport keys).
- **Docs:** developer.roku.com/docs — SceneGraph nodes (`Audio`, `RowList`, `MarkupList`, `Label`, `Poster`, `ButtonGroup`), `roUrlTransfer`, `roByteArray`, `roRegistrySection`, `Task` node.

### Minimum project layout
```
manifest                      # channel metadata (title, icons, splash, ui_resolutions)
source/main.brs               # Sub Main() -> create screen + SceneGraph scene
components/MainScene.xml(.brs) # root SceneGraph scene
components/*.xml(.brs)         # sub-views
components/tasks/*.xml(.brs)   # Task nodes for all network I/O
images/                       # channel icons + splash
```
`manifest` essentials: `title=PocketStreams`, `major_version`, `mm_icon_focus_hd=pkg:/images/icon_hd.png` (290x218), `_fhd` (336x210), `splash_screen_hd` (1280x720) / `_fhd` (1920x1080), `ui_resolutions=fhd`.

---

## 3. Critical Roku gotchas (read before coding)

1. **All network I/O must run on a `Task` node**, never the render thread. Block the render thread and the UI freezes / the channel is killed. Pattern: scene sets Task input fields → Task does `roUrlTransfer` → writes result to an output field → scene observes the field.
2. **Protobuf is binary; `roUrlTransfer` string methods corrupt it.** `PostFromString`/`GetToString` mangle bytes ≥ 0x80 and nulls. So:
   - **POST protobuf:** build a `roByteArray`, write it to `tmp:/req.bin` (`bytes.WriteFile(...)`), then `xfer.PostFromFile("tmp:/req.bin")`. To capture the binary **response**, use `xfer.AsyncGetToFile`/`PostFromFile` variants that write to a file, then read it back with `roByteArray.ReadFile`.
   - Simpler reliable recipe: `xfer.SetRequest("POST")`, headers set, `xfer.AsyncPostFromFile("tmp:/req.bin")`; in the port message, you get the body as a string — but for binary responses prefer `AsyncGetToFile("tmp:/resp.bin")` then `ba.ReadFile("tmp:/resp.bin")`.
3. **No Keychain.** Persist the auth token in `roRegistrySection` (e.g. section `"auth"`, keys `token`,`userid`,`email`). Call `.Flush()` after writes.
4. **No ATS restriction** — http is allowed, but prefer https. radio-browser favicons are sometimes http; fine on Roku.
5. **radio-browser requires a descriptive User-Agent** — set `User-Agent: PocketRadio/1.0` on every radio-browser request or you get rate-limited/blocked.
6. **Audio playback = the `Audio` SceneGraph node** (not deprecated `roAudioPlayer`). It does buffering, trickplay position/duration, and HLS/MP3/AAC. See §7.
7. **JSON** is built-in: `ParseJSON(str)` / `FormatJSON(obj)`. The Pocket Casts **cache** endpoints (full feed, show notes) and **radio-browser** and **Supabase** are all JSON — only the `api.pocketcasts.com` endpoints are protobuf.
8. `roUrlTransfer` follows 302 redirects by default (needed for the cache full-feed 302).

---

## 4. Auth, identity, persistence

- **Test account (dev only):** credentials live in `SECRETS.local.md` (gitignored, never committed). Ask the user if the file is missing.
  The account has ~3 Up Next episodes and 3 favorite stations (KCRW Eclectic 24, KEXP, NPR Hourly Newscast).
- **Device ID** (needed for up_next requests): generate a UUID once and persist in the registry, or use `CreateObject("roDeviceInfo").GetChannelClientId()`.
- **Token** from login is used as `Authorization: Bearer <token>` on all `api.pocketcasts.com` calls except `/user/login`. `userId` (uuid) is used as the Supabase `x-user-uuid` header.

---

## 5. Protobuf primer (manual, no library)

Wire types: **0 = varint**, **2 = length-delimited** (string / sub-message). Tag byte = `(fieldNumber << 3) | wireType`. Field numbers here are all ≤ 15, so each tag is a single byte.

Helpers to implement over `roByteArray`:
```
encodeVarint(n)              -> bytes (unsigned LEB128: low 7 bits, high bit = continue)
encodeStringField(fn, s)     -> [tag=(fn<<3)|2] + encodeVarint(len(s)) + utf8bytes(s)
encodeVarintField(fn, n)     -> [tag=(fn<<3)|0] + encodeVarint(n)
encodeLenDelimField(fn, buf) -> [tag=(fn<<3)|2] + encodeVarint(len(buf)) + buf
```
Decoding: walk bytes; read tag → fieldNumber=`tag>>3`, wireType=`tag and 7`; wireType 0 → read varint; wireType 2 → read length varint then that many bytes (string or recurse into sub-message); wireType 1 → skip 8 bytes; wireType 5 → skip 4 bytes; skip unknown fields.

`Int32Value` is a protobuf wrapper = a sub-message with a single `field 1 (varint) = the int`.
`Timestamp` = sub-message with `field 1 (varint) = unix seconds`.

---

## 6. API spec (everything)

Base: `https://api.pocketcasts.com`. Headers on protobuf calls: `Content-Type: application/octet-stream`, `Accept: application/octet-stream`, `User-Agent: PocketRadio/1.0`, plus `Authorization: Bearer <token>` (all except login).

### 6.1 Login — `POST /user/login`  (protobuf, no auth)
Request `Api_UserLoginRequest`: `f1=email (string)`, `f2=password (string)`, `f3=scope (string)="mobile"`.
Response 200 (protobuf): `f1=token (string)`, `f2=uuid/userId (string)`, `f3=email (string)`.
`401/403` → invalid credentials.

### 6.2 Up Next — `POST /up_next/sync`  (Bearer)
Request `Api_UpNextSyncRequest`: `f1=deviceTime (varint, ms since epoch)`, `f2="2" (string)`, `f6=deviceID (string)`.
Response `Api_UpNextResponse`:
- `f4 = repeated EpisodeResponse` sub-msg: `f1=title`, `f2=url`, `f3=podcast (=podcastUUID)`, `f4=uuid`, `f5=published (Timestamp{f1=seconds})`.
- `f5 = repeated EpisodeSyncResponse` sub-msg: `f1=uuid (string)`, `f6=playedUpTo (Int32Value)`, `f7=duration (Int32Value)`.
Merge sync data into episodes by uuid. The first episode in `f4` order is the top of the queue / currently playing.
(Note: `up_next/sync` often returns few/no `f5` sync entries → fall back to §6.3 to get playedUpTo+duration per podcast.)

### 6.3 Per-podcast playback data — `POST /user/podcast/episodes`  (Bearer)
Request `Api_UuidRequest`: `f1="2"`, `f2="mobile"`, `f3=podcastUUID`.
Response `Api_SyncEpisodesResponse`: `f1 = repeated` sub-msg `{ f1=uuid (string), f3=playedUpTo (int32 varint), f6=duration (int32 varint) }`.
Call once per distinct podcastUUID in Up Next; merge by uuid to fill missing playedUpTo/duration.

### 6.4 Save position — `POST /sync/update_episode`  (Bearer)
Request `Api_UpdateEpisodeRequest`: `f1=uuid (string)`, `f2=podcast (string)`, `f3=position (Int32Value{f1=seconds})`, `f4=status (int32 varint: 1=notPlayed, 2=inProgress, 3=completed)`, `f5=duration (int32 varint)`.
Throttle to ~once/30s while playing, plus on pause/stop. On natural end → status `3` (completed) and remove from Up Next (§6.5).

### 6.5 Up Next change actions (reorder / remove) — `POST /up_next/sync`  (Bearer)
`Change` sub-msg: `f1=uuid`, `f2=action (varint: 1=playNow, 4=remove)`, `f3=modified (ms)`, `f4=title`, `f5=url`, `f6=podcast`.
`Api_UpNextChanges`: `f2 = the Change` (length-delimited).
Body `Api_UpNextSyncRequest`: `f1=deviceTime(ms)`, `f2="2"`, `f4=UpNextChanges (length-delimited)`, `f6=deviceID`.
- **playNow (action 1):** when the user picks an episode to play now (bubbles to top server-side).
- **remove (action 4):** when an episode finishes.

### 6.6 Skip amounts (READ-ONLY) — `POST /user/named_settings/update`  (Bearer)
The "update" endpoint returns current settings even when you send none, so this is effectively a read — send only the device field, no settings, so nothing is written.
Request `Api_NamedSettingsRequest`: `f2 = "PocketRadio" (string)`.
Response `Api_NamedSettingsResponse`: `f5 = skipForward`, `f6 = skipBack`, each an `Api_Int32Setting{ f1=value (Int32Value{f1=int32}), f2=changed, f3=modifiedAt }`. Unwrap `f5/f6 → f1 → f1` = seconds.
**Defaults if missing/failure:** back=10, forward=45. (This user's account = back **15**, forward **30**.)
UI: use generic skip glyphs/labels; show the actual numbers (don't hardcode "10"/"45").

### 6.7 New Releases (subscribed podcasts, last 14 days)
1. `POST /user/podcast/list` (Bearer). Request: `f1="2"`, `f2="mobile"`. Response `Api_UserPodcastListResponse`: `f1 = repeated UserPodcastResponse { f1=uuid, f4=title }`.
2. For each podcast: `GET https://cache.pocketcasts.com/mobile/podcast/full/{podcastUUID}` (no auth; follows a 302). JSON:
   ```json
   { "podcast": { "title": "...", "episodes": [
       { "uuid": "...", "title": "...", "url": "...", "duration": 1234, "published": "2026-05-30T12:00:00Z" } ] } }
   ```
   Keep episodes with `published >= now-14d`, sort by `published` desc, merge across podcasts.

### 6.8 Episode detail / show notes — `GET https://cache.pocketcasts.com/mobile/show_notes/full/{podcastUUID}`  (no auth)
JSON: `{ "podcast": { "episodes": [ { "uuid": "...", "show_notes": "<html>", "image": "https://..." } ] } }`.
Find the episode by uuid; strip HTML to plain text for display (drop tags, decode `&amp; &lt; &gt; &quot; &#39; &nbsp; &hellip;`, collapse blank lines).

### 6.9 Radio favorites (Supabase)
Base `https://brvtspdculqyvdrmdtef.supabase.co`. Anon (publishable, safe) key:
`sb_publishable_1MRvFzvB6O7f2zDPfs2nkA_p18FSLUF`
Headers on all: `apikey: <anon key>`, `x-user-uuid: <userId>`.
- **List:** `GET /rest/v1/radio_favorites?select=station_id` → `[{ "station_id": "<uuid>" }]`.
- **Add:** `POST /rest/v1/radio_favorites` + `Content-Type: application/json` + `Prefer: return=minimal,resolution=merge-duplicates`; body `{ "user_uuid": "<userId>", "station_id": "<id>" }`.
- **Remove:** `DELETE /rest/v1/radio_favorites?station_id=eq.<id>&user_uuid=eq.<userId>` + `Prefer: return=minimal`.

### 6.10 Station metadata + browse (radio-browser.info)
Base `https://de1.api.radio-browser.info/json` — **always** send `User-Agent: PocketRadio/1.0`.
- **By UUID** (resolve a favorite): `GET /stations/byuuid/{stationuuid}` → array (usually 1).
- **Search:** `GET /stations/search?name=<q>&limit=40&hidebroken=true&order=votes&reverse=true`.
- **Top (default browse):** `GET /stations/topvote?limit=50&hidebroken=true`.
- Fields: `stationuuid`, `name`, `url_resolved` (stream URL; `byuuid` may use `url`), `favicon` (logo), `country`, `language`, `tags` (comma list), `codec`, `bitrate`, `votes`, `homepage`. Skip rows with empty name/stream.

### 6.11 Tracklist for enhanced streams (match by station name)
- If station name contains **"kcrw"**: `GET https://tracklist-api.kcrw.com/Music/all/1?page_size=10` → array `[{ title, artist, album, album_image, album_image_large, datetime }]`. Skip entries where artist is empty or `"[BREAK]"`.
- If station name contains **"kexp"**: `GET https://api.kexp.org/v2/plays/?limit=10` → `{ "results": [{ play_type, song, artist, album, thumbnail_uri, airdate }] }`. Keep only `play_type == "trackplay"`.
- Poll ~every 30s while that stream is the active source. Show "Title — Artist".

### 6.12 Fallback stream
KCRW Eclectic 24 MP3: `https://streams.kcrw.com/e24_mp3` — good hardcoded stream for the M1 skeleton.

---

## 7. Audio playback on Roku

Use an `Audio` SceneGraph node:
```
m.audio = m.top.createChild("Audio")
content = createObject("roSGNode","ContentNode")
content.url = streamUrl
content.streamformat = "mp3"      ' "hls" for .m3u8; "mp3"/"aac" for direct; try "hls" if .m3u8
m.audio.content = content
m.audio.control = "play"          ' "pause" / "resume" / "stop"
```
- **Resume:** for podcasts with `playedUpTo > 0`, set `content.PlayStart = playedUpTo` (seconds) before play, or `m.audio.seek = playedUpTo` once `state="playing"`.
- **Progress / scrub:** observe `m.audio.position` (seconds) and `m.audio.duration`. Live streams report duration 0 / indefinite → that's the signal to hide the scrub bar and show play/pause only (mirrors menubar's `shouldUseMuteControls`: radio + indefinite duration → no seek).
- **Seek / skip:** `m.audio.seek = newPositionSeconds`. Skip back/fwd amounts come from §6.6 (this user: 15 / 30).
- **End detection:** observe `m.audio.state` for `"finished"` → mark completed + advance queue.
- Remote transport keys (FF/REW/Play) can map to seek/skip; D-pad+OK navigates lists.

---

## 8. Feature parity checklist (the menubar app)

1. **Login** with Pocket Casts (protobuf), persist token in registry, auto-login on launch, handle 401.
2. **Up Next playback**: play queue episodes; **seek to `playedUpTo`** on start; **save position** every ~30s + on pause/stop (§6.4); on finish → mark completed, **remove** (§6.5), auto-advance to next; **playNow** reorder when user picks an episode.
3. **New Releases**: list subscribed-podcast episodes from the last 14 days (§6.7); play (via playNow).
4. **Radio favorites**: list (Supabase→radio-browser), play; add/remove favorite.
5. **Browse / Search** stations (radio-browser top + name search).
6. **Tracklist** overlay/list for KCRW & KEXP while playing (§6.11).
7. **Skip amounts** read from account settings (§6.6); used for skip back/fwd.
8. **Scrub/seek + play/pause** for seekable content (podcasts + finite MP3 like NPR hourly); **play/pause only** for live streams.
9. **Detail screens**: episode show notes (§6.8); station metadata (country/language/genre/codec·bitrate/votes/homepage).
10. **Now Playing**: artwork + scrolling title + progress. Podcast artwork URL: `https://static.pocketcasts.com/discover/images/130/{podcastUUID}.jpg`.

### Menubar → 10-foot UX mapping
- The menubar's 4 artwork "pills" (Podcast + 3 streams) + ⋮ → a top **selector row** (Podcast | Stream 1–3 | Browse) navigated with the D-pad.
- "Hover detail card" (menubar) → there is no hover on Roku. Use **OK** (or `*`/Options) on a row to push a **detail screen**; **Back** returns. (The user already iterated the menubar away from hover for exactly this reason.)
- Up Next / New Releases / station lists → `MarkupList`/`RowList`; OK plays.
- Scrub bar → progress bar on a Now-Playing screen + transport-key seek.

---

## 9. Suggested milestones

- **M1 — Skeleton + audio.** Channel installs, SceneGraph scene, plays the hardcoded KCRW stream (§6.12) via the `Audio` node. Validates sideload + telnet debug + audio.
- **M2 — Login + persistence.** Protobuf login over file-based POST (§3.2, §6.1), store token in registry, auto-login, 401 handling.
- **M3 — Up Next.** Fetch+decode (§6.2/§6.3), list UI, play with resume + position save (§6.4), auto-advance + remove on finish (§6.5), playNow reorder.
- **M4 — Radio.** Favorites (Supabase §6.9 → radio-browser §6.10), play, Browse/Search.
- **M5 — New Releases + detail.** §6.7 list + play; episode show-notes detail §6.8.
- **M6 — Polish.** Skip settings §6.6, scrub/seek + live-vs-seekable logic §7, tracklist §6.11, station detail §6.10, Now-Playing artwork/title, channel icons/splash.

---

## 10. Assets

- App identity: **PocketStreams**, blue Pocket Casts mark (the iOS/menubar icon was recolored red→blue, hue +156°, white logo preserved). The 1024px blue source can be regenerated or pulled from the menubar assets if present; downscale for the Roku channel icons (HD 290x218, FHD 336x210) and splash.

---

## 11. Reference implementation (if available in workspace)

Sibling repo `../pocket-radio-menubar/PocketRadio/`:
- `Services/APIService.swift` — **canonical** API + manual protobuf (every encode/decode above came from here).
- `View Models/PlayerViewModel.swift` — playback state machine: resume-on-start, 30s position-save throttle, finish→remove→advance, skip logic, tracklist polling, skip-settings fetch.
- `ContentView.swift` — feature inventory + UX (pills, lists, scrub bar, detail panels) to mirror at a high level.

Treat the Swift as spec, not code to port — the Roku app is a from-scratch BrightScript/SceneGraph build.
