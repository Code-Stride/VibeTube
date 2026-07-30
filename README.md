# 🎬 VibeTube - YouTube Premium Features Unlocked

<p align="center">
  <img src="app/src/main/res/drawable/ic_launcher_foreground.xml" width="120" height="120" alt="VibeTube Logo">
</p>

<p align="center">
  <b>Free YouTube Premium Experience for Android</b><br>
  Ad-Free • Background Play • PiP • Downloads • SponsorBlock
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Android-24+-green?style=flat-square&logo=android" alt="Android">
  <img src="https://img.shields.io/badge/Kotlin-1.9-blue?style=flat-square&logo=kotlin" alt="Kotlin">
  <img src="https://img.shields.io/badge/License-GPL--3.0-orange?style=flat-square" alt="License">
  <img src="https://img.shields.io/badge/Version-1.0.0-red?style=flat-square" alt="Version">
</p>

---

## ✨ Premium Features (All Unlocked!)

### 🚫 Ad-Free Experience
- Zero video ads
- No banner ads
- No popup ads
- Clean, distraction-free viewing

### 🎵 Background Playback
- Play videos in background
- Lock screen controls
- Notification controls
- Audio-only mode for music

### 📺 Picture-in-Picture (PiP)
- Floating mini player
- Resize and move window
- Works across all apps
- Auto-PiP when pressing home

### ⬇️ Download Manager
- Download videos in any quality (144p - 4K)
- Download audio only (MP3)
- Batch downloads
- Pause & resume support
- Wi-Fi only option
- Background download support

### ⏭️ SponsorBlock Integration
- Auto-skip sponsored segments
- Skip intros & outros
- Skip self-promotion
- Skip interaction reminders
- Skip preview segments
- Community-driven database
- Customizable category selection

### 👎 Return YouTube Dislike
- See dislike counts on all videos
- Uses Return YouTube Dislike API

### 🎨 Additional Features
- **Dark Mode** - Beautiful dark theme
- **Playback Speed** - 0.25x to 3x
- **Quality Selection** - Up to 4K
- **Deep Links** - Open YouTube links directly
- **Share Intent** - Share videos to VibeTube
- **No Login Required** - Works without Google account
- **Privacy Focused** - No tracking

---

## 📱 Screenshots

<p align="center">
  <img src="screenshots/home.png" width="200" alt="Home">
  <img src="screenshots/player.png" width="200" alt="Player">
  <img src="screenshots/downloads.png" width="200" alt="Downloads">
  <img src="screenshots/settings.png" width="200" alt="Settings">
</p>

---

## 🛠️ Tech Stack

- **Language**: Kotlin
- **Architecture**: MVVM + Clean Architecture
- **DI**: Hilt
- **UI**: Material Design 3 + Jetpack Compose
- **Video Player**: Media3 ExoPlayer
- **Database**: Room
- **Network**: Retrofit + OkHttp
- **Backend**: Piped API (privacy-focused YouTube frontend)
- **SponsorBlock**: Official SponsorBlock API
- **Image Loading**: Coil
- **Async**: Coroutines + Flow

---

## 🚀 Building from Source

### Prerequisites
- Android Studio Hedgehog (2023.1.1) or later
- JDK 17
- Android SDK 34

### Build Steps

```bash
# Clone the repository
git clone https://github.com/BlazeNext/VibeTube.git
cd VibeTube

# Build debug APK
./gradlew assembleDebug

# Build release APK
./gradlew assembleRelease
```

### Install on Device
```bash
adb install app/build/outputs/apk/debug/app-debug.apk
```

---

## 📁 Project Structure

```
VibeTube/
├── app/
│   └── src/main/
│       ├── java/com/blazenxt/vibetube/
│       │   ├── data/
│       │   │   ├── api/          # API services
│       │   │   ├── db/           # Room database
│       │   │   ├── model/        # Data models
│       │   │   └── repository/   # Repositories
│       │   ├── di/               # Hilt modules
│       │   ├── download/         # Download manager
│       │   ├── player/           # Video player
│       │   ├── sponsorblock/     # SponsorBlock
│       │   ├── ui/               # UI components
│       │   │   ├── home/
│       │   │   ├── search/
│       │   │   ├── library/
│       │   │   ├── downloads/
│       │   │   └── settings/
│       │   └── utils/            # Utilities
│       └── res/
│           ├── layout/
│           ├── drawable/
│           ├── values/
│           └── navigation/
├── gradle/
└── build.gradle
```

---

## 🔧 Configuration

### SponsorBlock Categories
Choose which segments to auto-skip:
- ✅ Sponsor
- ✅ Self-Promotion
- ✅ Interaction Reminder
- ⬜ Intro
- ⬜ Outro
- ⬜ Preview
- ⬜ Filler

### Default Quality
Set your preferred streaming quality:
- Auto (recommended)
- 1080p / 720p / 480p / 360p

### Download Quality
Choose default download quality separately

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## 📄 License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- [Piped](https://github.com/TeamPiped/Piped) - Privacy-friendly YouTube frontend
- [SponsorBlock](https://sponsor.ajay.app/) - Skip sponsor segments
- [NewPipe](https://github.com/TeamNewPipe/NewPipe) - YouTube extraction
- [Return YouTube Dislike](https://returnyoutubedislike.com/) - Dislike counter

---

## ⚠️ Disclaimer

VibeTube is an independent application and is not affiliated with, endorsed by, or connected to YouTube or Google LLC in any way. This app is developed for educational purposes only.

---

<p align="center">
  Made with ❤️ by <a href="https://github.com/BlazeNext">BlazeNext</a>
</p>
