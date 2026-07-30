# Architecture

VibeTube is a Flutter Android app. Playback does **not** use the official YouTube Data API key product for streams; it uses YouTube’s **InnerTube** HTTP endpoints (same family of clients used by many FOSS clients), plus optional third-party helpers.

## High-level flow

```text
UI (screens/widgets)
    │
    ▼
AppProvider / MiniPlayerController
    │
    ├── InnerTubeClient  → browse / search / player
    ├── HlsParser        → master m3u8 → per-height variants
    ├── StorageService   → SharedPreferences lists/settings
    ├── DownloadService  → progressive file cache
    ├── UpdateService    → GitHub Releases API
    └── NativePlayer     → MethodChannel → Kotlin
                              ├── PiP
                              └── PlaybackService (MediaSession)
```

## Playback pipeline

1. **Metadata & feed**  
   - `browse` / multi-`search` discover for Home (browse-only feeds are often empty without cookies).  
   - Category chips map to region-aware search queries.

2. **Stream resolution** (`InnerTubeClient.getVideoDetails`)  
   - **IOS** client → often returns **HLS** master (multi-quality).  
   - **ANDROID** client → progressive MP4 (commonly ~360p) + adaptive formats.  
   - Both fetched in parallel and merged.

3. **HLS**  
   - `HlsParser` reads the master playlist and builds `hlsVariants[height] → media playlist URL`.  
   - Player prefers locked variants / master HLS over progressive when possible.

4. **Player UI**  
   - Full screen: `PlayerScreen` owns or resumes a `VideoPlayerController`.  
   - Back: controller is **adopted** by `MiniPlayerController` (not disposed) → bottom mini bar.  
   - Tap mini: push `PlayerScreen(resumeSession: true)` and rebind the same controller.

## Native Android

| Piece | Role |
|-------|------|
| `MainActivity` | MethodChannel; PiP enter; `isPlaying` gate for auto-PiP |
| `PlaybackService` | Foreground `mediaPlayback` service + `MediaSession` + media notification |

PiP is allowed only when Flutter reports **active playback** (`setPlaying(true)`).

## State

- **AppProvider** — feeds, library, settings, downloads, update prompt.  
- **MiniPlayerController** — cross-route playback session and mini-bar visibility.

## Third-party services

| Service | Use |
|---------|-----|
| YouTube InnerTube | Catalog + streams |
| sponsor.ajay.app | SponsorBlock segments |
| returnyoutubedislikeapi.com | Dislike counts |
| api.github.com | Latest release / update APK URL |

## Project layout

See repository `lib/` tree in the root [README](../README.md).

## Known limitations

- Quality selection still being polished (adaptive HLS vs locked variants).  
- Unofficial clients can break when YouTube changes responses.  
- Public CI keystore is for sideload continuity, not strong app identity.
