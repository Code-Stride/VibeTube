# VibeTube — Bug Scan Report

_Last full audit: **2026-07-17**, against `v1.11.0+26`._
_Method: line-by-line review of `lib/`, `android/**/*.kt`, manifest, Gradle and CI,
plus `flutter test` (60/60 green at the time of the audit)._

> Supersedes the previous report. That document described a committed release
> keystore with a public password as an "accepted risk"; that is no longer
> accurate. No keystore is committed, `android/app/build.gradle` reads signing
> credentials from Gradle properties / environment only, and CI fails the build
> if the keystore secret is missing.

---

## Status

All items below were fixed in the "deep bug audit" change set unless explicitly
marked **Open**.

### High

| ID | Issue | Status |
|----|-------|--------|
| H-1 | Opening the video already playing in the mini bar from any entry point other than the mini bar built a **second** `VideoPlayerController` — two decoders, two audio tracks. `_boot` now adopts the live controller for the same video regardless of the `resumeSession` flag. | ✅ |
| H-2 | `_ShortPlayerState._heartAnimController` was never disposed → `AnimationController was disposed with an active Ticker` when swiping within 600 ms of a double-tap like. | ✅ |
| H-3 | Mini player **and** expanded player both registered media-notification and audio-focus handlers, so one notification tap ran `play()`/`pause()` twice, and notification "stop" disposed the controller the open player still used. Ownership now transfers explicitly (`_attachSystemHandlers` / `_detachSystemHandlers`). | ✅ |
| H-4 | The 250 ms position timer called `setState` on the whole player, rebuilding a non-lazy `ListView` of up to 8 comment tiles + 15 related `VideoCard`s four times a second. Position/duration moved to `ValueNotifier`s consumed by `_timeBuilder`. | ✅ |
| H-5 | `HomeScreen` watched the whole `MiniPlayerController` (notifies every 250 ms) and keyed its `IndexedStack` on the tab index, destroying all six pages on every tab switch. Now `context.select` + `ValueKey(isMusic)`, with tabs keyed by a `_Tab` enum so Music Mode no longer teleports the user to a different page. | ✅ |

### Medium

| ID | Issue | Status |
|----|-------|--------|
| M-1 | Wakelock was **inverted**: with background play on (the default) the screen was allowed to sleep while the user was watching. | ✅ |
| M-2 | `getRelatedVideos` and `getComments` issued the *same* `next` request twice per video. Replaced with a single `getNextData`. | ✅ |
| M-3 | Stream URLs were merged across IOS / ANDROID / MEDIACONNECT / WEB clients, then replayed with whichever UA the header ladder guessed → 403s masked by up to three retries. `VideoFormat.clientUserAgent` now records provenance and playback tries the correct UA first. | ✅ |
| M-4 | `isLive` fired on ordinary videos whenever a client omitted `lengthSeconds` but returned a manifest, forcing Auto (HLS), disabling the quality sheet and blocking downloads. Now only explicit live signals count. | ✅ |
| M-5 | Deep links stacked a new `PlayerScreen` (and controller) per link. A deep-linked player is now replaced, not stacked. | ✅ |
| M-6 | `AppTheme.applySystemUi` ran inside `MaterialApp`'s builder, issuing a platform-channel call on every unrelated `notifyListeners()` (~5/sec during a download). Moved to `toggleDarkMode`. | ✅ |
| M-7 | `startService()` throws on API 26+ from the background; the blanket catch silently dropped `setPlaying` / `updateBackground` / `stopBackground`, desyncing the notification. Now routed through `sendToPlaybackService()` using `startForegroundService`. | ✅ |
| M-8 | `PlaybackService.flutterChannel` is a companion-object field that was never cleared, keeping the `FlutterEngine` reachable. Cleared in `cleanUpFlutterEngine()`. | ✅ |
| M-9 | Picking a quality for one video called `setDefaultQuality`, pinning **every** future video to it. Now a session-only override. | ✅ |
| M-10 | Caption discovery scraped `youtube.com/watch` with a desktop UA — a third request that returns nothing behind consent walls / bot checks. Tracks are now parsed from the `player` response already fetched; the scrape remains only as a fallback. | ✅ |
| M-11 | `clearHistory()` bypassed the `_synchronized` write lock, so an in-flight `addToHistory` could resurrect entries. | ✅ |
| M-12 | Empty `catch (_) {}` on diagnostic paths hid *why* a feed was empty or a media command failed. The feed/search/platform-channel paths now log. Genuinely best-effort cleanup catches were left as-is. | ✅ |

### Low

| ID | Issue | Status |
|----|-------|--------|
| L-1 | Root provider used `ChangeNotifierProvider.value`, so `AppProvider.dispose()` (which closes the HTTP clients) was dead code. | ✅ |
| L-5 | Notification used `android.R.drawable.ic_media_play` while the bundled `ic_notification` asset went unused. | ✅ |
| L-6 | Dead `Build.VERSION_CODES.LOLLIPOP` guard (`minSdk` is 24). | ✅ |
| L-7 | `_isNewer` ignored build numbers, so `1.11.0+27` was never offered over `1.11.0+26`. | ✅ |
| L-8 | The user's region reached search/browse but never the player clients (`gl` was hardcoded). | ✅ |
| L-9 | `'lac'` was matched with `contains()`, so any view-count text holding that substring (e.g. "black") was multiplied by 100,000. | ✅ |
| L-2 | `trending`/`shorts`/`music` feeds are `shuffle()`d, which makes pull-to-refresh look broken. | **Open — product decision** |
| L-3 | `_toggleSubscribe` is local `setState` + a toast; nothing is persisted or sent. | **Open — needs a real feature** |
| L-4 | "Cast" and "Notifications" buttons are `SnackBar` stubs in the shipped UI. | **Open — needs a real feature** |
| L-10 | Downloads have no HTTP `Range`/resume; a failure at 95 % restarts from zero. | **Open — feature work** |
| L-11 | `minifyEnabled false` / `shrinkResources false` on release, and `android.enableJetifier=true` is likely unnecessary. | **Open — needs a verified release build** |

---

## Regression coverage

`test/audit_2026_07_test.dart` locks in the parts of this audit that are unit
testable: view-count word boundaries (L-9), update version comparison (L-7),
caption-track parsing from a player response (M-10), stream URL provenance
(M-3), and caption survival across `copyWithStreams`.

## Notes for future audits

`flutter analyze` and `flutter test` both run in CI on every push and pull
request, and are the ground truth for compile health. The historically fragile
areas — the quality ladder, HLS master parsing, view-count locales, download
integrity and deep-link ID extraction — are all covered by tests; extend those
rather than re-deriving them by hand.
