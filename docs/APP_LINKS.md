# App Links — current status and what is required

**Status: NOT working in production.** Shared VibeTube links currently resolve
in a browser, not in the app. This document explains exactly why and what has
to happen to fix it. The `assetlinks.json` in this repo is a template with a
placeholder fingerprint — publishing this repo alone does not enable App Links.

## The problem

`AndroidManifest.xml` declares:

```xml
<intent-filter android:autoVerify="true">
    <data android:scheme="https"
          android:host="code-stride.github.io"
          android:pathPrefix="/VibeTube/w/"/>
</intent-filter>
```

With `autoVerify="true"`, Android fetches:

```
https://code-stride.github.io/.well-known/assetlinks.json
```

Note the path: **the domain root**, not the `pathPrefix`. Two things block it:

1. No `assetlinks.json` existed anywhere in the repository, so verification
   could never succeed.
2. `docs/` is published as a GitHub Pages **project site**, served under
   `https://code-stride.github.io/VibeTube/`. A project site physically cannot
   serve a file at `https://code-stride.github.io/.well-known/...` — that path
   belongs to the **user/organisation site**.

So `docs/.well-known/assetlinks.json` in this repo is published at
`https://code-stride.github.io/VibeTube/.well-known/assetlinks.json`, which is
**not** the URL Android checks. It is included here as the canonical source of
truth to copy from.

## What needs to happen

### 1. Publish the file at the domain root

Create a repository named **`Code-Stride/code-stride.github.io`** (the
user/organisation Pages repo) and commit this file to it:

```
.well-known/assetlinks.json
```

It must then be reachable at exactly:

```
https://code-stride.github.io/.well-known/assetlinks.json
```

Served as `application/json`, HTTP 200, no redirect. A 301/302 fails
verification silently.

### 2. Fill in the real signing fingerprint

Replace `REPLACE_WITH_RELEASE_KEYSTORE_SHA256_FINGERPRINT` with the SHA-256
fingerprint of the **release** keystore that actually signs the published APK:

```bash
keytool -list -v -keystore android/app/vibetube-release.jks -alias <your-alias> \
  | grep 'SHA256:'
```

Use the colon-separated uppercase hex, e.g. `AB:CD:EF:...`.

> If you distribute through Google Play with Play App Signing, use the
> fingerprint Play shows under **Release → Setup → App signing**, not your
> upload key. Using the upload key is the single most common reason App Links
> silently fail for Play-distributed apps.

### 3. Verify

```bash
# The file Android will actually read
curl -sS https://code-stride.github.io/.well-known/assetlinks.json

# Google's verification endpoint
curl -sS "https://digitalassetlinks.googleapis.com/v1/statements:list?\
source.web.site=https://code-stride.github.io&\
relation=delegate_permission/common.handle_all_urls"
```

On a device (Android 12+):

```bash
adb shell pm verify-app-links --re-verify com.blazenxt.vibetube
adb shell pm get-app-links com.blazenxt.vibetube
```

You want `verified` for `code-stride.github.io`. Then:

```bash
adb shell am start -a android.intent.action.VIEW \
  -d "https://code-stride.github.io/VibeTube/w/dQw4w9WgXcQ"
```

This should land in VibeTube with no chooser dialog.

## Keeping the three in sync

These must always agree, or Android silently stops verifying and links open in
a browser:

| Item | Location |
|---|---|
| Host + path prefix | `AndroidManifest.xml` intent-filter |
| Host + path prefix | `ShareLinks.host` / `ShareLinks.basePath` |
| Host (root) + fingerprint | `.well-known/assetlinks.json` on the Pages site |
| Host | `MainActivity.LINK_HOST` |

## Until this is done

Sharing still works — recipients get the `docs/w/` landing page, which offers
the app and a YouTube fallback. They just do not get the seamless
straight-into-the-app jump that `autoVerify` is supposed to provide.
