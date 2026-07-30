# VibeTube Full Bug Scan Report

_Scan date: 2026-07-30 · commit baseline before/after hotfixes_

## Summary

| Severity | Found | Fixed in follow-up |
|----------|------:|-------------------:|
| CRITICAL | 1 real (null/channel) | ✅ |
| HIGH | several | ✅ key items |
| MED | many (empty catch / mounted) | partial |
| LOW | style / product | noted |

> Automated paren-balance hits on Dart were **false positives** (generics/`=>` noise). Latest CI **build success** is the ground truth for compile health.

---

## Critical / High (actionable)

### 1. MethodChannel last-writer-wins ✅ FIXED
**Where:** `NativePlayer.ensureHandlers`  
**Bug:** PlayerScreen and MiniPlayerController each called `setMethodCallHandler`, so notification Play/Pause only reached the last registrant.  
**Fix:** Multiplexed listener lists + `removeHandlers`.

### 2. Force-unwrap `currentVideo!` in download path ✅ FIXED
**Where:** `AppProvider.resolveDownloadUrl`  
**Fix:** Use null-safe `currentVideo?.bestMuxedUrl`.

### 3. Media buttons / MediaSession flags ✅ FIXED
**Where:** `PlaybackService.kt`  
**Fix:** `FLAG_HANDLES_MEDIA_BUTTONS | FLAG_HANDLES_TRANSPORT_CONTROLS`.

### 4. POST_NOTIFICATIONS never requested ✅ FIXED
**Where:** Android 13+  
**Fix:** Best-effort `Permission.notification.request()` at startup.

### 5. Double VideoPlayer listeners (mini + full) ✅ FIXED
**Where:** `MiniPlayerController.bindExisting` / `setExpanded`  
**Fix:** Remove mini `_tick` while expanded; full player owns UI ticks.

### 6. `context` / `setState` after `await` (player) ✅ PARTIAL
**Where:** `_finishAttach` after `c.play()`  
**Fix:** `mounted` checks added around post-await work.

### 7. Public release keystore password ⚠️ ACCEPTED RISK
**Where:** `android/app/build.gradle` + committed JKS  
**Note:** Documented in README/SECURITY — needed for sideload upgrade continuity. Forks should use private keys.

### 8. Hardcoded InnerTube API key ⚠️ ACCEPTED
**Where:** `innertube_client.dart`  
**Note:** Public YouTube client key pattern (not a secret server key). Still visible in APK.

---

## Medium

| Issue | Status |
|-------|--------|
| Empty `catch (_)` hides failures | Intentional for optional side-loads; consider logging in debug |
| Search set `error = 'No results'` | ✅ cleared — empty UI only |
| Almost no unit tests | Open — add widget/player tests |
| Downloads only in app documents | By design (no gallery scan) |
| Region default `IN` | Product default |

---

## Low

- Deprecated `Switch.activeColor` → `activeTrackColor` ✅  
- `Share.share` OK with `share_plus`  
- Duration parse `[0]` guarded by length checks in practice  

---

## CI status

Latest `main` Flutter APK workflow: **success** (docs commit and prior feature commits).

---

## Recommended next scans

1. Device QA matrix: PiP play/pause, notification actions, mini expand, live URL, Shorts  
2. `flutter analyze` in CI as required check  
3. Integration test for MethodChannel fan-out  
4. Quality ladder polish (deferred by product request)
