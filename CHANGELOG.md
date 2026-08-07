# Changelog

All notable changes to VibeTube are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project roughly follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Planned
- Further video quality selection polish
- Voice search
- Playlist support

## [1.12.1] - 2026-07-17

Third-pass audit. Focused on defects that survived the previous two rounds.

### Fixed

- **A single malformed API item no longer blanks an entire list.**
  `_extractVideo()` had no `try/catch` while its two siblings did, and it
  indexed `thumbs.last['url']` without checking the shape. Running inside the
  `walk()` recursion, any throw escaped to the caller's catch and turned the
  whole response into an empty list.
- **A comment with no avatar no longer removes every comment.**
  `(list as List?)?.last?['url']` reads as null-safe, but `.last` throws
  `StateError` on an *empty* list rather than returning null.
- **"Auto" quality is adaptive again.** `preferredPlayUrl` returned the single
  highest variant instead of the master playlist, pinning playback to the top
  rendition: continuous rebuffering on slow connections with no ability to
  step down. The player's Auto path had the same ordering.
- **Silent video on locked qualities.** HLS variants are only used for a
  quality lock when they carry their own audio. YouTube commonly lists
  video-only renditions with the audio in a separate `#EXT-X-MEDIA` group;
  handing one straight to the player produced picture with no sound.
- **Lookalike domains rejected.** `host.endsWith("youtube.com")` also matched
  `evilyoutube.com`. Both the Dart and Kotlin paths now use an exact
  allowlist.
- **Lock-screen scrubber works.** The MediaSession reported
  `PLAYBACK_POSITION_UNKNOWN`, so no system surface could draw progress.
  Real position/duration/speed are published and `ACTION_SEEK_TO` plus
  rewind/fast-forward are handled.
- **Update check distinguishes failure from success.** Both "already latest"
  and "network failed" returned null, so Settings claimed "You are on the
  latest version" with no connectivity at all.
- **Downloads no longer leak `.part` files.** `delete()` removed only the
  `.mp4`, leaving orphaned partials the user could not reclaim. Added
  periodic flushing so a fast network feeding slow storage cannot buffer the
  difference in memory.
- **"Share" in the video card menu now shares.** It previously only closed
  the sheet.
- Predictive back enabled (`enableOnBackInvokedCallback`) for Android 13+.
- The localhost cleartext exemption moved into `debug-overrides` so it no
  longer ships in release builds.

### Added

- `docs/.well-known/assetlinks.json` and `docs/APP_LINKS.md`. App Links have
  never actually verified: `autoVerify` is declared but no `assetlinks.json`
  existed, and a GitHub Pages *project* site cannot serve `/.well-known/` at
  the domain root. The doc states plainly what remains to be done — the file
  must be published from a `code-stride.github.io` user repo with the real
  release fingerprint. **App Links stay broken until that is published.**
- `test/audit_round3_test.dart` covering each fix above.

## [1.12.0] - 2026-07-17

Deep bug audit: 39 findings triaged, 37 fixed. See PR "Deep bug audit" for the
full analysis.

### Fixed — playback
- **Screen no longer sleeps mid-video.** Background play defaults to on, and
  that code path called `WakelockPlus.disable()`, so with stock settings the
  display slept ~30s into every video while audio kept going. The wakelock now
  tracks "is playing" (and is released in PiP), independently of background
  play.
- **Locked quality no longer reports false success.** `_attachController` now
  returns whether it actually attached instead of letting callers read a stale
  `_ready` field, so a failed quality switch reports the failure rather than
  silently keeping the old stream.
- **Dead stream URLs removed.** `signatureCipher` formats were emitted with the
  signature stripped, producing URLs that always 403 — and they outranked the
  working unciphered ones from the IOS/ANDROID clients. They are now skipped.
- **Back button can close the player.** Backing out of a *paused* video closes
  it; only actively playing video is handed to the mini player.
- **Live detection fixed.** Any video whose text contained "live" ("Delivery",
  "Oliver") was badged LIVE and routed down the live-only HLS path. Detection
  now looks at real badge/overlay markers.
- **`likeCount` is parsed, not cast.** InnerTube returns it as a string, so the
  `as num?` cast always yielded 0.

### Fixed — feeds and navigation
- **Infinite scroll works.** `SearchResult.continuation` was never populated,
  so every "load more" re-requested page 1. Home, search and Shorts now follow
  real continuation tokens; the Shorts feed no longer dead-ends at ~20 videos.
- **Tabs keep their state.** The `IndexedStack` key included the tab index, so
  every switch destroyed and rebuilt all tabs, losing scroll position and typed
  search text.
- **Search and Home no longer share a spinner.** Split into `isSearching` /
  `isLoading`; the shared request-ID guard could also strand a spinner forever.
- **Feed order is stable.** Trending is no longer reshuffled on every load.
- **The mini player bar is reachable again.** Overlay ownership moved to a
  `NavigatorObserver`; the old flag was only set in `HomeScreen.dispose()`,
  which never runs because HomeScreen is `MaterialApp.home`.
- **Region setting reaches search.** It was hard-coded to the client default,
  and changing it now refreshes the feeds.
- **Music Mode chips do something.** They were decorative (`onSelected: (_) {}`).
- **No more duplicate music rows.** "More for you" skipped 6 while "Quick picks"
  showed 10, repeating four videos.

### Fixed — data integrity
- **Partial downloads are no longer marked complete.** A dropped connection
  ends the stream without an error; the received byte count is now checked
  against `Content-Length` before the `.part` file is promoted to `.mp4`.
- **`clearHistory` takes the storage lock**, so an in-flight write can no longer
  resurrect a just-cleared entry.
- **Per-video quality/speed no longer rewrites the global default.**
- **Build-number-only updates are detected** (`1.11.0+27` over `1.11.0+26`).
- **Locale-aware view counts.** `1.234.567` (de/es) parsed as 1; comma-decimal
  and space-grouped locales are handled too.

### Fixed — resources and correctness
- **Shorts `AnimationController` is disposed** (Ticker leak + debug assertion).
- **Shorts take audio focus** and pause the mini player instead of playing over
  it; they also respond to headphone unplug.
- **Shorts cost ~1 request instead of 5.** A dedicated single-client stream
  lookup replaces the full `getVideoDetails` fan-out per card.
- **Shorts like button reflects real state** instead of blind-toggling.
- **Media/audio handlers register synchronously**, closing a race where a
  quickly-dismissed player leaked a listener forever.
- **`/next` is fetched once per video**, not twice (related + comments).
- **Request-ID guards added** to `loadShorts` / `loadMusic`.
- **Caption lookup is a binary search**, not a per-frame linear scan.
- **Sponsor markers stay inside the progress bar.**
- **Position timer pauses** in PiP and while backgrounded.
- **Avatar initials are emoji-safe** (`name[0]` returned a lone surrogate).
- **"Next" cycles** through related videos instead of replaying the first.
- **Audio-focus guard no longer races itself** on rapid play/pause.

### Changed
- **SponsorBlock uses the privacy-preserving hash-prefix endpoint**, so the
  exact video ID never leaves the device.
- **Update checks are throttled to once every 6 hours** instead of every cold
  start (the unauthenticated GitHub API allows 60 requests/hour/IP).
- **Notification permission is requested in context**, when background playback
  first needs it, rather than over the splash screen on every cold start.
- **Release builds are minified and resource-shrunk** with a new
  `proguard-rules.pro`. *Needs a device smoke test before shipping.*
- **"Ad blocker" is now an honest status row**, not a toggle that did nothing —
  ad-free playback is a property of the InnerTube clients.
- Debug logging is compiled out of release builds; it was writing signed stream
  URLs to logcat.
- Added `crypto` dependency (SponsorBlock hash prefix).

### Known / deferred
- **PoToken**: the InnerTube clients still run without one. If Google tightens
  enforcement, playback breaks. Tracked separately — it needs a real
  integrity-token flow, not a patch.
- **Stream-URL expiry**: no mid-playback re-resolve yet.
- **Download resume**: no `Range` header support; a failed 200MB download still
  restarts from zero.
- **Captions** are still scraped from the watch page HTML.

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
