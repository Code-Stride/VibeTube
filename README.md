# 🎬 VibeTube

[![Build Flutter APK](https://github.com/Code-Stride/VibeTube/actions/workflows/build.yml/badge.svg)](https://github.com/Code-Stride/VibeTube/actions/workflows/build.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Latest Release](https://img.shields.io/github/v/release/Code-Stride/VibeTube)](https://github.com/Code-Stride/VibeTube/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/Code-Stride/VibeTube/total)](https://github.com/Code-Stride/VibeTube/releases)

**VibeTube** is a free & open-source Flutter YouTube client for Android with premium-style features: ad-free playback, mini player, PiP, background media controls, SponsorBlock, and more.

> ⚠️ **Not affiliated with YouTube or Google.**  
> This is an unofficial third-party client. Use at your own risk and respect [YouTube’s Terms of Service](https://www.youtube.com/t/terms) and local laws.

---

## ✨ Features

| Feature | Description |
|--------|-------------|
| 🚫 **Ad-free streams** | Plays via InnerTube clients (no official YouTube ads in-stream) |
| 📺 **Mini player** | YouTube-style bottom bar when you press Back |
| 🖼️ **Picture-in-Picture** | System PiP **only while video is playing** |
| 🎧 **Background play** | MediaSession — lock screen / notification / Bluetooth controls |
| ⏭️ **SponsorBlock** | Auto-skip sponsored segments (configurable categories) |
| 👎 **Return YouTube Dislike** | Shows dislike counts when available |
| 📚 **Library** | History, Liked, Watch Later, Downloads |
| 🔴 **Live & Shorts** | Live HLS playback + Shorts chip / badges |
| ⚡ **Speed control** | 0.25× – 3× (scrollable sheet) |
| 🎨 **Themes** | Full dark / light Material themes |
| 🔄 **In-app updates** | Checks GitHub Releases and prompts on older builds |

---

## 📱 Install (Android)

1. Open the [**latest Release**](https://github.com/Code-Stride/VibeTube/releases/latest)
2. Download `VibeTube-v*.*.*-release.apk`
3. Allow **Install unknown apps** for your browser/file manager
4. Install and open

**Requirements:** Android 7.0+ (API 24)

> **Package conflict?** Uninstall any older VibeTube build first.  
> From **v1.2.0** onward, signing uses a stable release keystore so updates should install over previous v1.2+ builds.

---

## 🛠️ Build from source

### Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) stable (3.x)
- JDK 17
- Android SDK (compileSdk 36)

### Debug

```bash
git clone https://github.com/Code-Stride/VibeTube.git
cd VibeTube
flutter pub get
flutter run
```

### Release APK

```bash
flutter pub get
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

The repo includes `android/app/vibetube-release.jks` for **consistent sideload upgrades** in CI.  
For your own distribution fork, **generate a new keystore** and do not reuse public demo keys for production identity.

More detail: [docs/BUILD.md](docs/BUILD.md)

---

## 🏗️ Architecture

```
lib/
├── api/                 # InnerTube HTTP client (browse / search / player)
├── models/              # Video, formats, comments, update info
├── providers/           # App state + mini-player session
├── screens/             # Home, Search, Player, Library, Downloads, Settings
├── services/            # Downloads, HLS parse, storage, updates, native bridge
├── utils/               # Theme (light/dark)
└── widgets/             # Video cards, mini player bar, update dialog
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for stream pipeline, PiP, and mini-player notes.

---

## 🤝 Contributing

Contributions are welcome!

1. Fork the repo  
2. Create a branch: `git checkout -b feature/my-change`  
3. Commit with a clear message  
4. Open a Pull Request  

Please read [CONTRIBUTING.md](CONTRIBUTING.md) and follow the [Code of Conduct](CODE_OF_CONDUCT.md).

---

## 🔒 Security

Found a vulnerability? Please see [SECURITY.md](SECURITY.md) — **do not** open a public issue for sensitive reports.

---

## 📜 License

This project is licensed under the **GNU General Public License v3.0**.  
See [LICENSE](LICENSE) for the full text.

```
VibeTube — YouTube client with premium-style features
Copyright (C) 2026 BlazeNXT / Code-Stride

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.
```

---

## ⚖️ Disclaimer

- VibeTube is **not** endorsed by YouTube, Google LLC, or any related entity.  
- “YouTube” is a trademark of Google LLC.  
- Streaming unofficially may violate YouTube’s ToS; you are responsible for how you use this software.  
- No warranty — see GPL §15–17.

---

## 🔗 Links

- **Releases:** https://github.com/Code-Stride/VibeTube/releases  
- **Issues:** https://github.com/Code-Stride/VibeTube/issues  
- **Actions (CI):** https://github.com/Code-Stride/VibeTube/actions  

Made with ❤️ by **BlazeNXT** / [Code-Stride](https://github.com/Code-Stride)
