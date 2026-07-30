# Contributing to VibeTube

Thanks for helping improve VibeTube!

## Ways to contribute

- 🐛 Bug reports (with device, Android version, steps to reproduce)
- 💡 Feature ideas (check existing issues first)
- 🔧 Pull requests (fixes, UI polish, docs, tests)
- 🌍 Translations / accessibility improvements

## Development setup

1. Install Flutter stable and Android SDK  
2. `git clone https://github.com/Code-Stride/VibeTube.git && cd VibeTube`  
3. `flutter pub get`  
4. `flutter run`

Please run before opening a PR:

```bash
flutter analyze
flutter test
```

## Pull request guidelines

- Keep PRs focused (one concern per PR when possible)
- Match existing code style (Dart, Material 3)
- Update docs/CHANGELOG if user-facing behavior changes
- Do **not** commit secrets, personal keystores, or API keys beyond what’s already public InnerTube patterns
- For signing: use your own keystore locally; don’t replace the shared CI key without discussion

## Commit messages

Prefer short, descriptive subjects:

```
fix: only enter PiP while playback is active
feat: add Shorts category chip
docs: expand build instructions
```

## Code of Conduct

By participating, you agree to uphold our [Code of Conduct](CODE_OF_CONDUCT.md).

## License

Contributions are accepted under the project’s [GPL-3.0](LICENSE) license.
