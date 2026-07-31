# Changelog

All notable changes to VibeTube are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project roughly follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Planned
- Further video quality selection polish

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
