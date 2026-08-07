# Android App Links setup (share links)

VibeTube shares links of the form:

```
https://code-stride.github.io/VibeTube/w/<videoId>
```

The manifest declares this with `android:autoVerify="true"`, which asks Android
to verify domain ownership before it will open the link directly in the app.

## The problem this document exists for

Android fetches the verification file from the **domain root**, never from a
path prefix:

```
https://code-stride.github.io/.well-known/assetlinks.json
```

`code-stride.github.io/VibeTube/` is a GitHub Pages **project site**. Its
content is served under the `/VibeTube/` prefix, so a file committed at
`docs/.well-known/assetlinks.json` in *this* repository is published at:

```
https://code-stride.github.io/VibeTube/.well-known/assetlinks.json   ← wrong place
```

Android will not look there. Until the file is reachable at the domain root,
verification fails silently and shared links open in a browser instead of the
app. This was the state of the repository before this change: the manifest
requested verification and no `assetlinks.json` existed anywhere.

## Option A — publish at the user-site root (recommended, free)

1. Create a repository named exactly **`Code-Stride/Code-Stride.github.io`**.
   GitHub serves it at `https://code-stride.github.io/` (the domain root).
2. Copy `docs/.well-known/assetlinks.json` from this repo to
   `.well-known/assetlinks.json` in that repo.
3. Fill in the real fingerprint (see below) and push.
4. Verify it is live:

   ```bash
   curl -sS https://code-stride.github.io/.well-known/assetlinks.json
   ```

## Option B — custom domain

Point a domain at GitHub Pages and serve `/.well-known/assetlinks.json` from
its root. Then update **all three** of these so they agree:

| Where | What to change |
|---|---|
| `lib/utils/share_links.dart` | `host` and `basePath` |
| `android/app/src/main/AndroidManifest.xml` | the `autoVerify` `<data>` entry |
| the hosting repo | `/.well-known/assetlinks.json` |
| `MainActivity.kt` | `LINK_HOST` |

If they disagree, Android quietly stops verifying and links open in a browser.

## Getting the SHA-256 fingerprint

The placeholder in `assetlinks.json` must be replaced with the fingerprint of
the keystore that signs **release** builds:

```bash
keytool -list -v \
  -keystore android/app/vibetube-release.jks \
  -alias <your-key-alias> | grep 'SHA256:'
```

Copy the value **without** the `SHA256: ` prefix, keeping the colons, e.g.
`AB:CD:EF:...`.

> If you also want debug builds to open links, add the debug keystore
> fingerprint as a second entry in the `sha256_cert_fingerprints` array
> (`~/.android/debug.keystore`, alias `androiddebugkey`, password `android`).

## Verifying on a device

```bash
# Trigger verification
adb shell pm verify-app-links --re-verify com.blazenxt.vibetube

# Inspect the result (look for "verified")
adb shell pm get-app-links com.blazenxt.vibetube

# Test the link end to end
adb shell am start -a android.intent.action.VIEW \
  -d "https://code-stride.github.io/VibeTube/w/dQw4w9WgXcQ"
```

The private `vibetube://watch?v=<id>` scheme needs no verification and works
today; it is deliberately never used for sharing because messaging apps render
it as plain text rather than a tappable link.
