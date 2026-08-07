# Build guide

## Requirements

| Tool | Notes |
|------|--------|
| Flutter | Stable channel, 3.x |
| Java | 17 (Temurin recommended) |
| Android SDK | compileSdk **36**, build-tools recent |
| Linux / macOS / Windows | CI uses `ubuntu-latest` |

```bash
flutter doctor -v
```

## Get dependencies

```bash
flutter pub get
```

## Run (debug)

```bash
flutter run
# or pick a device
flutter devices
flutter run -d <deviceId>
```

## Analyze & test

```bash
flutter analyze
flutter test
```

## Release APK

```bash
flutter build apk --release
```

Artifact path:

```text
build/app/outputs/flutter-apk/app-release.apk
```

### Split per ABI (smaller downloads)

```bash
flutter build apk --release --split-per-abi
```

## Signing

### CI / official Code-Stride sideload builds

- Workflow: `.github/workflows/build.yml`
- Decodes the private keystore from `VIBETUBE_KEYSTORE_BASE64`; no keystore is committed.
- Verifies its SHA-256 certificate fingerprint against the protected
  `VIBETUBE_EXPECTED_CERT_SHA256` secret before signing.
- Requires `VIBETUBE_STORE_PASSWORD`, `VIBETUBE_KEY_ALIAS`, and
  `VIBETUBE_KEY_PASSWORD` as protected secrets.
- **Security note:** a keystore in a public repo is not a secret. Anyone can sign APKs that look like “updates”. For a trusted brand identity, use a **private** key and GitHub Actions secrets.

### Your own fork / store build

1. Generate a keystore:

```bash
keytool -genkeypair -v \
  -keystore ~/vibetube-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias vibetube
```

2. Create `android/key.properties` (gitignored):

```properties
storePassword=***
keyPassword=***
keyAlias=vibetube
storeFile=/absolute/path/to/vibetube-upload.jks
```

3. Point `android/app/build.gradle` at `key.properties` (or replace the demo keystore block).

4. Never commit real upload keys.

## CI

On every push to `main` and on tags `v*`:

1. Checkout  
2. Java 17 + Flutter stable  
3. `flutter pub get`  
4. Verify release keystore  
5. `flutter build apk --release`  
6. Upload artifact `VibeTube-Flutter-APK`  
7. On version tags, attach APK to GitHub Release  

## Troubleshooting

| Issue | What to try |
|-------|-------------|
| `package conflicts with an existing package` | Uninstall old APK; or use same signing key as previous install |
| Empty Home feed | Needs network; pull to refresh; check logs for InnerTube HTTP errors |
| PiP doesn’t open | Video must be **playing**; device must support PiP (API 26+) |
| Gradle / SDK errors | Align with `compileSdk 36`, AGP/Gradle versions in `android/` |

More: [ARCHITECTURE.md](ARCHITECTURE.md)
