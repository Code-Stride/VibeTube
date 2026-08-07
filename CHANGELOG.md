# Changelog

All notable changes to VibeTube are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project roughly follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed

Deep audit pass — lifecycle, audio-session and platform-behaviour bugs that the
analyzer cannot see. Each item was reproduced by reading the failing path; the
ones with a pure decision rule now have regression tests.

**Critical**
- **Cold start could hang on the splash screen.** The Android 13+ notification
  permission was requested with `await` *before* `runApp()`, so nothing was
  drawn until the user answered — and nothing ever was if the dialog was
  suppressed by OEM policy or a restricted profile. Moved after the first frame.
- **Deep links were silently dropped on cold start.** Dart told native it was
  "ready" before `runApp()`, native immediately replayed the buffered link, and
  `navigatorKey.currentState` was still null so `?.push` discarded it. The
  ready signal now waits for the first frame, and links arriving early are
  buffered on the Dart side too.
- **Mini player and full player both handled the same media events.** The mini
  player registered its media-button and audio-interruption handlers in
  `adopt()` but only removed them in `close()`, so after minimise → reopen both
  were live on one controller: a single notification "Pause" fired twice, and
  un-ducking reset the volume to 1.0, un-muting a muted video. Ownership is now
  explicit and handed over on expand/collapse.
- **Shorts bypassed the audio session entirely.** No focus request, no
  interruption handling — a Short played on top of an active mini-player
  session, kept playing out of the loudspeaker after a headset unplug, and
  talked over incoming calls. Shorts now take audio focus and honour
  noisy/pause/resume/duck, and opening the tab pauses the mini player.
- **Truncated downloads were recorded as complete.** An expiring googlevideo URL
  ends the stream cleanly, and the partial file still has a valid `ftyp`
  header, so it passed validation, was renamed to `.mp4` and cached forever —
  re-downloading returned the broken file. Byte count is now checked against
  `Content-Length`.
- **FlutterEngine and Activity leaked on every recreate.** `PlaybackService`
  held a static `MethodChannel` that was never cleared, retaining the whole
  engine; a service outliving its Activity also pushed media-button callbacks
  into a dead messenger, silently breaking the notification Play button.

**High**
- **The screen switched off during playback.** Background play defaults to on,
  and the code disabled the wakelock whenever it was on — including while the
  user was watching. The wakelock now tracks "playing and visible"; background
  audio is held up by the foreground service, which never needed one.
- **One thrown exception disabled interruption handling for the session.** The
  `_requestingFocus` guard was cleared after an unguarded `await` (and inside a
  `.then()` with no `catchError`), so a single failure left it stuck on and
  every handler early-returned from then on. Now released from `finally`.
- **"Ad blocker" setting did nothing.** The flag was stored, persisted and
  toggled but never read. Ad-free playback is a property of streaming via
  InnerTube, not something the user can switch off, so it is now shown as
  status rather than a control that lies.
- **Pagination was dead code.** `SearchResult.continuation` was never populated,
  so feeds stopped at one page and `loadMoreShorts` re-ran the first-page query
  and deduped the entire result away. Continuation tokens are now extracted
  (modern and legacy shapes) and followed.
- **Every video made two identical `/next` requests.** Related videos and
  comments were fetched separately from the same endpoint with the same body.
  Now one request, both parsed.
- **`startService()` used where Android 8+ requires `startForegroundService()`**
  in three of four call sites, with the resulting `IllegalStateException`
  swallowed by an empty catch — play/pause state stopped reaching the
  MediaSession with nothing in the log.
- **Swiping away a paused notification left a zombie service** holding audio
  focus with no remaining control surface. Added a delete intent.
- **Raw exception text reached the UI**, which can embed signed
  `googlevideo.com` URLs. Messages are now generic; detail goes to the log.

**Medium / low**
- Region setting only reached two of the browse calls; search, `/next` and the
  WEB player fallback stayed pinned to India.
- Trending is no longer shuffled on every refresh (it is a ranked list).
- `clearHistory()` now takes the same per-key lock as every other mutator, so an
  in-flight write cannot resurrect a cleared entry.
- JSON walkers are depth-capped, so a malformed payload cannot overflow the
  stack.
- Update check compares build numbers, so a `1.11.0+27` hotfix over `1.11.0+26`
  is detected.
- Default quality had two disagreeing defaults (`Auto (HLS)` vs `1080p`);
  there is now one constant.
- Removed the dead duplicate `loadCaptions()` path.
- `isDownloaded()` caches its header check instead of opening the file on every
  Downloads-list rebuild.
- `_heartAnimController` in the Shorts player was never disposed.
- View counts read `1K` rather than `1.0K`; `parseCount` no longer reads
  `"1.2.3"` as `1.2`.
- Mini-bar `Dismissible` key no longer includes the controller hash, which
  cancelled in-progress swipes.
- `HomeScreen.dispose()` no longer reaches for `context.read` behind a
  try/catch.

### Changed
- **Declared the real toolchain floor.** `lib/screens/settings_screen.dart` uses
  `activeThumbColor`, which requires Flutter 3.35 / Dart 3.9, but the pubspec
  claimed `sdk: >=3.0.0` and set no Flutter bound — building on 3.32 failed with
  a bare "No named parameter" error. Now `sdk: >=3.9.0` and `flutter: >=3.35.0`.

### Added
- `test/compile_coverage_test.dart` imports every library under `lib/`, so
  `flutter test` type-checks the whole app. The `settings_screen` breakage above
  survived precisely because no test imported it.
- Regression tests for download truncation, continuation extraction, compact
  view counts, `parseCount`, and same-version hotfix detection. The update
  comparison tests now exercise the shipped implementation instead of a copy of
  it. 60 tests → 74.

### Planned
- Further video quality selection polish
- Voice search
- Playlist support

## [1.7.1] - 2026-07-31

### Fixed
- **Video playback**: InnerTube now uses 4 clients (IOS, ANDROID, MEDIACONNECT, WEB) in parallel for maximum stream availability. Added WEB client player fallback and updated client versions.
- **Subscribe button**: Now toggles between Subscribe/Subscribed state.
- **All analyze warnings**: 0 issues, 38 tests pass.

### Changed
- InnerTube client version updated to 2025.07.13
- Better metadata merging from multiple clients
- Version 1.7.1+16

## [1.7.0] - 2026-07-31

### Added
- **Shorts section**: Dedicated YouTube-style vertical Shorts feed with swipe navigation, separate bottom tab, and auto-loading.
- **Caption/CC system**: Full subtitle support with track selection, auto-generated captions, and overlay rendering during playback.
- **YouTube-style search bar**: Search bar moved to top of home screen (like YouTube), with voice search placeholder and notification icon.
- **Settings upgrade**: Reorganized settings with section headers (Playback, SponsorBlock, Appearance, Default settings, Updates, About), account card, and dedicated quality/speed/region pickers.
- **UI improvements**: Cleaner home screen layout, improved search results display with count, better visual hierarchy.

### Fixed
- Search screen now has proper YouTube-style top search bar with voice search icon.
- Player caption overlay properly integrated with Provider state management.
- Shorts loading from InnerTube with proper short detection.
- Settings screen now uses SliverAppBar for better scrolling behavior.

### Changed
- Bottom navigation now has 6 tabs: Home, Search, Shorts, Library, Downloads, Settings.
- Removed Shorts from category chips (now has its own dedicated tab).
- Captions toggle added to player controls and settings.

## [1.6.0] - 2026-07-31

### Added
- **Share links now open in VibeTube.** Sharing a video used to hand out
  a `youtu.be` link, which opened YouTube — the app VibeTube exists to
  replace. Shares are now VibeTube links of the form
  `https://code-stride.github.io/VibeTube/w/<id>`, registered as verified
  Android App Links so they open the video straight in the app with no
  browser bounce and no chooser dialog.
- Anyone without the app gets a small landing page with the video
  thumbnail and a link to install VibeTube.
- A `vibetube://watch?v=<id>` scheme is accepted for deep linking. It is
  never shared, because messaging apps render it as plain text rather
  than a tappable link.

### Fixed
- Deep links from `youtube.com/live/…` and `youtube.com/v/…` were
  ignored; only `/shorts/` and `/embed/` were recognised.
- Video ids are now validated against `[A-Za-z0-9_-]{11}` rather than
  just their length, so malformed links fail cleanly instead of loading
  a broken player.
- `vibetube://<id>` lost the id's capitalisation, because URI parsing
  lowercases the authority — the video would never be found.

### Changed
- Release notes are generated from this changelog, so the GitHub release
  page and the in-app update prompt list what actually changed instead
  of showing a bare compare link.

## [1.5.2] - 2026-07-31

### Fixed
- **Player controls were unreadable as a group**: the seek slider was
  positioned at the bottom of the same stack as the action chips, so the
  two overlapped. The scrubber now sits in its own tier and, while the
  controls are hidden, is replaced by a slim progress line instead of a
  full slider with a floating thumb.
- **Light mode info pane**: the area below the video was written against
  hardcoded dark colours while the rest of the app is theme-aware, so
  text and cards were near-unreadable on a light background. All colours
  now resolve from the active theme.
- Sponsor markers drifted away from the seek bar at the edges; they are
  now drawn on the track's centre line with a matching inset.
- Centre transport glyphs washed out on bright frames; they now sit on a
  subtle scrim.

### Changed
- Overlay controls are grouped into three tiers — scrubber, playback
  settings (mute / loop / speed / quality / PiP / fullscreen), then
  actions — instead of sharing one strip. No control was removed.
- The duplicate -10s / +10s chips are gone; the same seek is already on
  the centre buttons and on double-tap.
- Action chips are hidden in fullscreen, where the identical actions are
  a swipe away in the info pane.
- The minimise button is a chevron rather than a back arrow, matching
  what it does.
- PiP is only offered when the device reports support for it.
- Description gained an explicit "Show more / Show less" affordance, and
  comments now show like counts.

### Security
- The release keystore is no longer committed. CI decodes it from the
  `VIBETUBE_KEYSTORE_BASE64` secret at build time and deletes it before
  uploading artifacts; signing passwords come from repository secrets
  with no inline fallbacks. See SECURITY.md for the exposure window —
  the signing key itself is unchanged, so updates install normally.

## [1.5.1] - 2026-07-31

### Fixed
- **Mini player crash**: resuming a video and leaving without minimising
  disposed the controller the mini bar still held, crashing on the next
  frame. Controller ownership is now tracked explicitly.
- **Background service crash**: `startForeground()` was only reached from
  one branch of `onStartCommand`, so Android 8+ could kill the app with
  `ForegroundServiceDidNotStartInTimeException`.
- **Picture-in-Picture**: the full UI and control overlay rendered inside
  the tiny PiP window; it now shows only the video surface.
- **Silent playback**: collapsing the full player left audio running with
  no mini bar and no way to control it.
- **Lock-screen controls**: pausing from the mini player tore down the
  MediaSession, so playback could not be resumed from the notification.
- **Fake downloads**: an HLS/DASH manifest could be saved as `.mp4`,
  reporting "Download complete" for a file that never plays. Manifests
  and live streams are now rejected up front.
- **Deep links**: YouTube URLs opened from other apps were lost on cold
  start due to a hardcoded 800 ms delay; links are now buffered natively
  and delivered when the Dart handler is ready.
- **Update prompt loop**: `1.5.0` compared as newer than `1.5.0+11`, and
  a `v` anywhere in a release tag was stripped.
- Removed `BuildContext` use across async gaps in the player.

### Changed
- Download progress notifications are throttled instead of firing once
  per network chunk, and report sensibly when the server sends no
  `Content-Length`.
- `compileSdk` 35 -> 36 (required by androidx.core 1.17 /
  androidx.browser 1.9). `targetSdk` stays at 35.

### CI
- APK workflow was failing on every push at `checkReleaseAarMetadata`;
  fixed alongside the signing credentials it never passed through.
- `flutter analyze` and `flutter test` now gate the build.

## [1.5.0] - 2026-07-30

### Fixed
- **Background play**: audio session + MediaSession; no wakelock fighting screen-off
- **Shorts feed**: proper InnerTube shorts filter + reel/shorts parsers
- **Live playback**: prefer ANDROID HLS/DASH (works for live)

### Added
- YouTube-style player actions: mute, loop, ±10s, next, like, dislike, share, save, download, audio-only, more sheet
- Shorts / Live discover improvements

## [1.4.2] - 2026-07-30

### Fixed
- MethodChannel handler fan-out (notification media buttons work with mini + full player)
- Null-safe download URL resolution
- MediaSession flags for hardware/Bluetooth media buttons
- Android 13+ notification permission request
- Mini-player listener double-attach while full player expanded
- Search empty results no longer treated as hard error
- Extra mounted guards after async play attach

## [1.4.1] - 2026-07-30

### Added
- MediaSession + media-style notification (lock screen / Bluetooth / shade)
- Notification Play / Pause / Stop actions synced with in-app player
- Live stream path (HLS adaptive) and Shorts chip / badges
- Vertical-friendly aspect for Shorts

### Fixed
- Picture-in-Picture only while playback is active (no idle PiP)
- Auto-PiP on Home gated on playing state
- Various player / mini-player function bugs

## [1.4.0] - 2026-07-30

### Added
- YouTube-style in-app **mini player** (Back keeps playback; bottom bar above nav)
- Expand mini → full player without reloading stream
- Swipe / close on mini bar

## [1.3.3] - 2026-07-30

### Fixed
- Playback stuck at 360p: force IOS HLS + per-quality HLS variant locks
- Parallel IOS/ANDROID stream fetch; correct headers for m3u8

## [1.3.2] - 2026-07-30

### Added
- HLS master playlist parser for multi-quality ladder UI

## [1.3.1] - 2026-07-30

### Fixed
- Empty Home / All feed (browse APIs empty without cookies)
- Multi-search discover feed + category chips

## [1.3.0] - 2026-07-30

### Added
- Native PiP + auto-PiP hooks
- Background foreground service (early version)
- Scrollable speed & quality sheets
- Full light/dark themes (`VibeColors`)

## [1.2.0] - 2026-07-30

### Fixed
- Package install conflicts via **stable release keystore**
- Real offline download paths
- Working Like / Watch Later / Share / Download actions

## [1.1.0] - 2026-07-30

### Added
- Multi-client InnerTube playback
- SponsorBlock, dislikes, library basics
- In-app update check (GitHub Releases)
- UI redesign

## [1.0.0] - 2026-07-30

### Added
- Initial Flutter app + CI APK build

[Unreleased]: https://github.com/Code-Stride/VibeTube/compare/v1.5.0...HEAD
[1.5.0]: https://github.com/Code-Stride/VibeTube/releases/tag/v1.5.0
[1.4.2]: https://github.com/Code-Stride/VibeTube/releases/tag/v1.4.2
[1.4.1]: https://github.com/Code-Stride/VibeTube/releases/tag/v1.4.1
[1.4.0]: https://github.com/Code-Stride/VibeTube/releases/tag/v1.4.0
[1.3.3]: https://github.com/Code-Stride/VibeTube/releases/tag/v1.3.3
[1.3.2]: https://github.com/Code-Stride/VibeTube/releases/tag/v1.3.2
[1.3.1]: https://github.com/Code-Stride/VibeTube/releases/tag/v1.3.1
[1.3.0]: https://github.com/Code-Stride/VibeTube/releases/tag/v1.3.0
[1.2.0]: https://github.com/Code-Stride/VibeTube/releases/tag/v1.2.0
[1.1.0]: https://github.com/Code-Stride/VibeTube/releases/tag/v1.1.0
[1.0.0]: https://github.com/Code-Stride/VibeTube/releases/tag/v1.0.0
