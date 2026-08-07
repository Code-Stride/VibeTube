# VibeTube — Bug Scan Report

_Last audit: **2026-07-17** (round 2), against the "37 fixes" audit baseline._
_Method: line-by-line review of `lib/`, `android/**/*.kt`, manifest, Gradle and
CI, plus the full test suite._

> This supersedes the earlier report, which described a committed release
> keystore with a public password as an "accepted risk". That is no longer
> accurate: no keystore is committed, `android/app/build.gradle` reads signing
> credentials from Gradle properties / environment only, and CI fails the build
> if the keystore secret is missing.

---

## Round 2 — fixed here

These survived the previous audit. Nothing below is a compile error; the
analyzer and the test suite were green, which is exactly why they persisted.

### High

| Issue | Detail |
|-------|--------|
| **Two players, one video** | The mini-session was only adopted when `resumeSession: true`, which only the mini bar passes. Opening the already-playing video from the feed, search, the related list or a deep link fell through and built a **second** `VideoPlayerController` on the same URL — two decoders, two audio tracks. `_boot` now adopts on video-id match regardless of the flag, and tears down any session it does not adopt. |
| **Duplicate media/audio handlers** | `MiniPlayerController.adopt()` registered notification and audio-focus handlers and only released them in `close()`, while `PlayerScreen._boot()` unconditionally registered its own. Both were live on the *same* controller: one notification tap ran `play()`/`pause()` twice, and notification "stop" disposed a controller the expanded player was still using. Ownership now transfers explicitly (`_attachSystemHandlers` / `_detachSystemHandlers`), with a `dispose()` safety net that hands control back. |
| **Player rebuild storm** | The 250 ms position timer called `setState` on the whole screen, rebuilding the non-lazy info `ListView` — up to 8 comment tiles and 15 related `VideoCard`s, each with a network image — four times a second. Position/duration moved to `ValueNotifier`s consumed by `_timeBuilder`, so only the timestamp widgets rebuild. |
| **HomeScreen rebuild storm** | `context.watch<MiniPlayerController>()` subscribed the whole shell to a notifier that fires every 250 ms during mini playback. Now `context.select` for the two booleans actually used. |
| **Music Mode tab teleport** | Tabs were tracked by integer index, and Music Mode removes the Shorts tab — so index 2 meant Shorts normally and Library in Music Mode. Clamping kept it in range but still moved the user. Tabs now have stable identity via a `_Tab` enum. |

### Medium

| Issue | Detail |
|-------|--------|
| **Stream URL provenance** | Formats were merged across IOS / ANDROID / MEDIACONNECT / WEB and then replayed with whichever UA the header ladder guessed. googlevideo binds a URL to its requesting client, so this produced 403s masked by up to three failed `initialize()` round-trips per candidate. `VideoFormat.clientUserAgent` now records the origin and playback presents it first. |
| **Deep links stacked players** | Each incoming link pushed another `PlayerScreen` (and another controller). A deep-linked player is now replaced rather than stacked. |
| **Platform call inside `build()`** | `AppTheme.applySystemUi` ran in `MaterialApp`'s builder, so every unrelated `notifyListeners()` — including throttled download progress, ~5/sec — rebuilt `MaterialApp` and issued a `SystemChrome` call. Moved to `toggleDarkMode`. |
| **Dropped background service commands** | `startService()` throws `IllegalStateException` on API 26+ when the app is backgrounded, and a blanket catch swallowed it — so `setPlaying`, `updateBackground` and `stopBackground` could all vanish, leaving the notification showing the wrong state or a zombie notification. Routed through `sendToPlaybackService()` using `startForegroundService`. |
| **Flutter engine leak** | `PlaybackService.flutterChannel` is a companion-object (process-global) field that was never cleared, keeping the `BinaryMessenger` and therefore the engine reachable; `notifyFlutter()` then invoked into a dead engine. Cleared in `cleanUpFlutterEngine()`. |
| **Captions scraped the watch page** | A third request, with a desktop UA, that returns nothing behind consent interstitials and bot checks — failing silently. Tracks now come from the `player` response already fetched (`VideoDetails.captionTracks`), with the scrape kept only as a fallback. |
| **Region ignored by the player** | The region setting reached search and browse but never the player clients, whose `gl` was hardcoded. |

### Low

- `"lac"` was matched with `contains()`, so any view-count text holding that
  substring — most obviously "black" — was multiplied by 100,000. Now
  word-boundary matched.
- Root providers used `.value`, so `AppProvider.dispose()` (which closes the
  HTTP clients) was unreachable dead code.
- The media notification used a stock Android icon while the bundled
  `ic_notification` asset went unused.
- Dead `Build.VERSION_CODES.LOLLIPOP` guard (`minSdk` is 24).

---

## Still open (deliberately)

| Issue | Why it is not patched here |
|-------|----------------------------|
| `_toggleSubscribe` is local `setState` + a toast; nothing is persisted or sent. | Needs a real feature, not a patch. |
| "Cast" and "Notifications" in the home app bar are `SnackBar` stubs. | Same. |
| Downloads have no HTTP `Range`/resume, so a failure at 95 % restarts from zero. | Feature work. |
| `minifyEnabled false` / `shrinkResources false` on release, and `android.enableJetifier=true` is probably unnecessary. | Enabling R8 without being able to smoke-test a release APK on a device risks shipping a broken build. Worth doing deliberately, with a manual verification pass. |

---

## Regression coverage

`test/audit_round2_test.dart` locks in the unit-testable parts of this round:
view-count word boundaries, caption-track parsing from a player response,
stream URL provenance, and caption survival across `copyWithStreams`.

`flutter analyze` and `flutter test` run in CI on every push and pull request
and are the ground truth for compile health. The historically fragile areas —
the quality ladder, HLS master parsing, view-count locales, download integrity,
continuation tokens and deep-link ID extraction — are all covered by tests;
extend those rather than re-deriving them by hand.

---

## Round 4 — pending release

- Guarded Shorts playback across async audio-focus/platform calls and disposed
  failed/stale native controllers.
- Added stable video keys to Shorts player state.
- Removed the unobserved `_fetchNext().catchError` future.
- Added region and caption request invalidation.
- Made update prompting response-driven and Music query years dynamic.
- Added a capability nonce to pre-Android 13 PiP broadcasts.
- Pinned CI actions, fixed fork debug artifact upload, and added signing
  certificate fingerprint verification.
- Corrected stale signing documentation and added
  `docs/SIGNING_KEY_MIGRATION.md`.

The historical Android signing identity remains compromised and requires the
owner migration decision documented above; this cannot be repaired by source
code alone.
