# Contributing

Thanks for helping. This is a small project, so the process is light.

## Before you start

- For anything bigger than a bug fix, open an issue first so we can agree on the approach.
- Read [docs/architecture.md](docs/architecture.md). Most changes belong either in the Dart layer (`lib/`) or in the plugin (`packages/scan3d_native/`), and the boundary between them matters.

## Development

```bash
flutter pub get
flutter analyze        # must be clean
flutter test           # must pass
```

Native code has no formatter or linter configured. Match the style of the file you're editing: 4-space indent in Kotlin, 2-space indent in Swift.

## Testing on a device

None of the AR code runs in CI or in widget tests, so any change to `ScanEngine`, the plugin or `ScanScreen` needs a device run. In the pull request, say what you tested on:

- iPhone/iPad with LiDAR
- iPhone without LiDAR
- Android with Depth API
- Android without Depth API

One platform is fine if the change only touches that platform. Use `flutter run --release` for anything performance-related, because debug builds are several times slower when accumulating points.

## Changing the channel protocol

Keep both platforms in step. A key added on Android must also be added on iOS, even if the iOS value is always `null`. Update [docs/native-bridge.md](docs/native-bridge.md) in the same pull request.

## Brand assets

Don't edit the PNGs or SVGs in `assets/brand/` or the app icons by hand. Change `tool/brand/generate.py` and run it. See [docs/brand.md](docs/brand.md).

## Commits and pull requests

- Keep each pull request to one logical change.
- Write commit messages in the imperative mood ("Add OBJ export", not "Added OBJ export").
- Add a line under **Unreleased** in [CHANGELOG.md](CHANGELOG.md) for anything a user would notice.

By contributing, you agree that your work is released under the [MIT License](LICENSE).
