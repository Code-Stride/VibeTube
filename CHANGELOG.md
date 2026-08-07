# Changelog

All notable changes to VibeTube are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project roughly follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Planned
- Voice search
- Playlist support
- Home-feed pagination (needs a continuation-aware browse endpoint)

## [1.12.0] - 2026-07-17

Deep bug audit. Every item below is a real defect found by reading the code,
not a refactor.

### Fixed - crashes and data loss

- **One malformed item no longer blanks an entire feed.** `_extractVideo` had
  no try/catch (unlike its siblings), so a single unexpected renderer shape
  threw out of `_parseVideosDeep` and the whole list came back empty.
- **One avatar-less comment no longer wipes the comment thread.** `.last` on an
  empty thumbnails list throws `StateError` rather than returning null.
- **A string `likeCount` no longer kills the player response.** YouTube sends
  this as a String often enough that the `as num?` cast failed, and when it
  failed on all four clients the user saw "No playable stream found".
- **Corrupt stored preferences no longer make the library unreadable**
  (`Video.fromJson` now coerces instead of casting).

### Fixed - playback

- **"Auto" is actually adaptive again.** Both `preferredPlayUrl` and the player
  offered the highest single rendition before the master playlist, pinning
  playback to 2160p and rebuffering forever on a slow connection.
- **Silent video on quality lock.** Video-only HLS renditions were being used
  as standalone streams; their audio lives in a separate `EXT-X-MEDIA` group
  that only the master playlist references. Such variants are now skipped.
- **Expired stream URLs are recovered.** googlevideo URLs expire after ~6h.
  Nothing anywhere checked `controller.value.hasError`, so resuming a
  long-paused video left a frozen frame and an endless spinner. The player now
  re-resolves the stream and resumes at the same position (max 2 attempts).
- **Fresh installs are no longer hard-locked to 1080p.** The default was
  declared as `Auto (HLS)` but `init()` fell back to `'1080p'`, and the locked
  path deliberately refuses the adaptive master - so any video without a 1080p
  rendition failed with "1080p is not available".
- **Quality/speed chosen for one video no longer becomes the global default.**
- **Exact matches now beat nearest matches** when resolving a quality, so
  asking for 360p on a `{hls: 1080, mp4: 360}` video no longer returns 1080p.

### Fixed - Shorts

- **Infinite spinner:** a bail-out path returned without setting an error, so
  the Short showed a loading indicator forever with no retry.
- **Decoder leak:** retrying replaced `_controller` without disposing the old
  one. Android has very few hardware decoders, so a few retries turned every
  Short black. The `AnimationController` was also never disposed.
- **Double audio:** Shorts ignored the audio session entirely. Opening the tab
  while the mini player was running played both at once; unplugging headphones
  kept playing on the loudspeaker; incoming calls talked over the video.
- **Double-tap no longer un-likes.** It toggled, so double-tapping an already
  liked Short quietly removed it while showing a red heart. Like state is also
  read back from storage instead of always rendering as unliked.
- **Subscribe** is a real, persisted button instead of a static rectangle.

### Fixed - navigation and state

- **Every tab switch used to destroy the whole page stack.** The `IndexedStack`
  key included `_index`, so `AnimatedSwitcher` treated each tab as a new widget
  and rebuilt everything - re-fetching feeds, recreating players, and briefly
  running two copies of the Shorts screen.
- **Feed and search no longer share loading/error state.** A home refresh spun
  the search tab, and a failed search painted its error over the home feed.
- **Pagination works.** `SearchResult.continuation` existed but was never
  populated, so "load more" re-requested page 1 and the dedupe filter dropped
  everything. Search now has infinite scroll; Shorts pages properly.
- **Search screen** no longer nests a `Scaffold` inside HomeScreen's, no longer
  rebuilds the entire results list on each keystroke, and keeps its text field
  in sync with provider state.

### Fixed - storage, downloads, updates

- `clearHistory` and `clearSearchHistory` now take the same per-key lock as the
  writers; an in-flight add could otherwise resurrect a just-deleted entry.
- Downloads: back-pressure (periodic flush) instead of unbounded memory growth,
  cancellation support, `.part` cleanup on every failure path, and
  `delete()` now removes leftover `.part` files.
- Update checks distinguish "up to date" from "check failed" - Settings used to
  claim you were on the latest version while completely offline. Build numbers
  are now compared when the three version components tie.

### Fixed - Android

- `assetlinks.json` added, plus `docs/APP_LINKS.md` explaining why App Links
  verification could never have worked from a GitHub Pages *project* site.
- `enableOnBackInvokedCallback` for predictive back on Android 13+.
- Release builds are minified and resource-shrunk with a proper
  `proguard-rules.pro` (was fully disabled).
- Localhost cleartext moved into `debug-overrides` so it no longer widens the
  release network policy.
- MediaSession publishes real position/duration and supports `SEEK_TO`,
  `REWIND` and `FAST_FORWARD`, so the lock-screen scrubber and Bluetooth seek
  controls work. The notification uses the app's own icon.

### Fixed - performance

- Related videos and comments come from one `next` request instead of two
  identical ~1 MB downloads per video.
- Caption tracks are read from the player response we already have, instead of
  scraping the 1-3 MB watch page again (which also broke on consent pages).
- Caption lookup is a binary search; it ran a linear scan over 1500+ cues four
  times a second.
- `resolveDownloadUrl` no longer refetches full details it already holds.

### Changed

- The trending feed is no longer shuffled on every load.
- Changing region reloads the feeds it controls.
- Look-alike hosts such as `evilyoutube.com` are rejected (exact host set) in
  both the Dart and Kotlin link parsers.
- Honest UI: the video-card "Share" action actually shares, the ten dead
  YouTube Music category chips now filter, and "Not interested" no longer
  claims to have done something it did not.

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
