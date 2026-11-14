---
name: magic-picker
description: "Pick files, images and videos in a Magic app with the Pick facade, and share downloads through magic_picker's PickerServiceProvider."
version: 1.0.0
when_to_use: "Use when code imports package:magic_picker or touches Pick, PickerServiceProvider, toMagicFile, toXFile or Storage.download on mobile or desktop in a Magic app."
---

# magic_picker

File and image picking for a Magic app. The `Pick` facade opens the gallery, camera, file dialog, directory dialog and save dialog, and answers with core's `MagicFile` (a `null` or an empty list when the user cancels). `PickerServiceProvider` sets `LocalAdapterContract.downloadHandler` in `boot()`, so `Storage.download` opens the share sheet on mobile, macOS and Windows and the save dialog on Linux. `XFile.toMagicFile()` and `MagicFile.toXFile()` convert between the two file types.

This skill covers `magic_picker` only. The Magic framework itself (container, `Storage`, `MagicFile`, `Http`, config) is the `magic-framework` skill.

## Install

```bash
flutter pub add magic_picker
dart run magic:dowel plugin:install magic_picker
```

Requires Dart >=3.13, Flutter >=3.47 and `magic` ^1.0.0. The installer registers `PickerServiceProvider` in `lib/config/app.dart` and publishes no config. Import only the barrel, `package:magic_picker/magic_picker.dart`, which also exports `XFile` and `CameraDevice`. The app owns the platform permissions: the photo library and camera usage descriptions in `Info.plist` and the file-access entitlements on macOS.

## Pick rules

1. Treat `null` (and an empty list from `images` and `files`) as a cancelled pick and return early. Cancelling is not an error.
2. Give `Pick.camera` and `Pick.recordVideo` an `onError`, `fallbackToGallery: true`, or both. With neither, a refused camera permission rethrows. With `onError` alone the call answers `null`.
3. Pass `extensions` without the dot (`['pdf']`). Do not pass `withData` to `Pick.file` or `Pick.files`; it no longer exists. Bytes load on demand through `readAsBytes`.
4. `Pick.directory` returns a path `String?` and is not available on the web.
5. `Pick.saveFile` requires `fileName` and `bytes` and answers a `Uri`. Check `scheme == 'file'` before `toFilePath()`: Android answers `content` and the web `blob`.
6. `MagicFile.size` is filled for every pick, but a file removed after the pick leaves `null` or `0`. Treat both as unknown when enforcing an upload limit.
7. `MagicFile` lives in `package:magic/magic.dart`; import it when you name the type.

## Download rules

1. Register `PickerServiceProvider`. Without it, `Storage.download` on mobile and desktop throws `UnsupportedError` naming `magic_picker`. The web ignores the handler and downloads through the browser.
2. On Linux `share_plus` cannot share a file, so the handler opens the save dialog with the file's bytes instead of a share sheet; expect a dialog there, not a sheet.
3. The handler is a static (`LocalAdapterContract.downloadHandler`). Assign your own after `Magic.init` has finished, because `boot()` overwrites it.
4. `PickerServiceProvider(app, share: ...)` replaces the share sheet; use it in tests only. It is never called on Linux.

## XFile rules

1. `toXFile()` is synchronous on mobile and desktop and a `Future<XFile>` on the web. In code that builds for both, wrap it in `Future.value` or `await` it.
2. It throws `UnsupportedError` for a `MagicFile` with no `path` on IO, and with no bytes on the web.

## Recipes

Pick an image and store it:

```dart
import 'package:magic_picker/magic_picker.dart';

Future<String?> chooseAvatar() async {
  final image = await Pick.image(maxWidth: 512, imageQuality: 80);
  if (image == null) return null;

  return image.store('avatars/profile.jpg');
}
```

Take a photo, falling back to the gallery:

```dart
import 'package:magic_picker/magic_picker.dart';

Future<void> takePhoto() async {
  final photo = await Pick.camera(
    fallbackToGallery: true,
    onError: (Object error) => print('Camera failed: $error'),
  );

  print(photo?.name);
}
```

Share a stored file:

```dart
import 'package:magic/magic.dart';

Future<void> export() {
  return Storage.download('reports/2024.pdf', name: 'Annual Report.pdf');
}
```

## Testing

No mocking library is needed. In `setUp()` call `MagicApp.reset()` and `Magic.flush()`. Boot the provider by hand with a recording callback, `await PickerServiceProvider(Magic.app, share: (params) async => shared.add(params)).boot()`, then call the handler or `Storage.download`. `LocalAdapterContract.downloadHandler` is a static that `Magic.flush()` does not clear, so set it to `null` in `tearDown()`. Fake the pickers by replacing `ImagePickerPlatform.instance` and `FilePickerPlatform.instance` and restoring the originals afterwards. The IO form of `toXFile` runs on the VM; the web form needs `flutter test --platform chrome`.
