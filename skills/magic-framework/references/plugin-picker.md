<!-- magic_picker v1.0.0 | Updated: 2026-11-14 -->

# magic_picker Plugin

File, image and video picking for a Magic app: the `Pick` facade, the `XFile` and `MagicFile` converters, and the share handler behind `Storage.download` on mobile and desktop. All of it lived in core `magic` up to 0.0.41; core 1.0.0 dropped the `file_picker`, `image_picker` and `share_plus` re-exports and the `toXFile` / `fromXFile` helpers.

## Contents

- [Installation](#installation)
- [Pick Facade API](#pick-facade-api)
- [Storage.download share handler](#storagedownload-share-handler)
- [XFile conversion](#xfile-conversion)
- [Testing](#testing)
- [Gotchas](#gotchas)

## Installation

```yaml
dependencies:
  magic_picker: ^1.0.0
```

Requires Dart >=3.13, Flutter >=3.47 and `magic ^1.0.0`.

```bash
flutter pub add magic_picker
dart run magic:dowel plugin:install magic_picker
```

The installer registers `PickerServiceProvider` in `lib/config/app.dart` and publishes no config. Import only `package:magic_picker/magic_picker.dart`, which also exports `XFile` and `CameraDevice`. The app owns the platform permissions (photo library and camera usage descriptions in `Info.plist`, file-access entitlements on macOS).

## Pick Facade API

Every method answers core's `MagicFile` (`package:magic/magic.dart`); `null` or an empty list means the user cancelled, which is not an error.

| Member | Return type | Notes |
|:-------|:------------|:------|
| `Pick.image({maxWidth, maxHeight, imageQuality})` | `Future<MagicFile?>` | One image from the gallery. |
| `Pick.images({maxWidth, maxHeight, imageQuality})` | `Future<List<MagicFile>>` | Several images. |
| `Pick.camera({preferredCamera, maxWidth, maxHeight, imageQuality, fallbackToGallery, onError})` | `Future<MagicFile?>` | Photo. With neither `onError` nor `fallbackToGallery`, a refused permission rethrows; with `onError` alone it answers `null`. |
| `Pick.media({maxWidth, maxHeight, imageQuality})` | `Future<MagicFile?>` | Image or video. |
| `Pick.video({maxDuration})` | `Future<MagicFile?>` | One video from the gallery. |
| `Pick.recordVideo({preferredCamera, maxDuration, fallbackToGallery, onError})` | `Future<MagicFile?>` | Record with the camera; same `onError` rule as `camera`. |
| `Pick.file({extensions})` | `Future<MagicFile?>` | `extensions` without the dot (`['pdf']`). No `withData`; bytes load through `readAsBytes`. |
| `Pick.files({extensions})` | `Future<List<MagicFile>>` | Several files. |
| `Pick.directory()` | `Future<String?>` | A path; not available on the web. |
| `Pick.saveFile({required fileName, required bytes, mimeType, dialogTitle})` | `Future<Uri?>` | Check `scheme == 'file'` before `toFilePath()`: Android answers `content`, the web `blob`. |

```dart
import 'package:magic_picker/magic_picker.dart';

final image = await Pick.image(maxWidth: 512, imageQuality: 80);
if (image == null) return;
await image.store('avatars/profile.jpg');
```

`MagicFile.size` is filled for every pick, but a file removed after the pick leaves `null` or `0`; treat both as unknown when enforcing an upload limit.

## Storage.download share handler

`PickerServiceProvider.boot()` sets core's `LocalAdapterContract.downloadHandler`, so `Storage.download(path, name: ...)` opens the share sheet on mobile and desktop. Without the provider the IO `download` throws `UnsupportedError` naming `magic_picker`; the web ignores the handler and downloads through the browser. The handler is a static, so assign your own only after `Magic.init` completes (`boot()` overwrites it). `PickerServiceProvider(app, share: ...)` replaces the share sheet, for tests.

## XFile conversion

`XFile.toMagicFile()` and `MagicFile.toXFile()` convert between the two types. `toXFile()` is synchronous on mobile and desktop and a `Future<XFile>` on the web, so code that builds for both wraps it in `Future.value` or awaits it. It throws `UnsupportedError` for a `MagicFile` with no `path` on IO, or no bytes on the web.

## Testing

Boot the provider by hand with a recording callback: `await PickerServiceProvider(Magic.app, share: (params) async => shared.add(params)).boot()`, then call `Storage.download`. `LocalAdapterContract.downloadHandler` is a static that `Magic.flush()` does not clear, so set it to `null` in `tearDown()`. Fake the pickers by replacing `ImagePickerPlatform.instance` and `FilePickerPlatform.instance` and restoring the originals. The IO `toXFile` runs on the VM; the web form needs `flutter test --platform chrome`.

## Gotchas

| Mistake | Fix |
|:--------|:----|
| `Storage.download` throws `UnsupportedError` on mobile or desktop | Register `PickerServiceProvider`. |
| Treating `null` as an error | It is a cancelled pick; return early. |
| `Pick.camera` with no `onError` and no `fallbackToGallery` | A refused camera permission rethrows; pass one or both. |
| `extensions: ['.pdf']` | No dot: `['pdf']`. |
| `Pick.directory()` on the web | Not available there. |
| Using `saveFile`'s result as a path | It is a `Uri`; check the scheme first. |
| Assigning `downloadHandler` before `Magic.init` finishes | `boot()` overwrites it; assign afterwards. |
