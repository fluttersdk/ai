---
name: magic-encryption
description: "Encrypt and decrypt strings in a Magic app with the Crypt facade, an APP_KEY or a Vault-backed device key, and magic_encryption's key:generate."
version: 1.0.0
when_to_use: "Use when code imports package:magic_encryption or touches Crypt, EncryptionServiceProvider, MagicEncrypter, MagicDecryptException, APP_KEY or key:generate in a Magic app."
---

# magic_encryption

AES-256-CBC for a Magic app. The `Crypt` facade encrypts a `String` with the configured `app.key` (`encrypt`, `decrypt`, synchronous) or with a per-device key kept in `Vault` (`encryptWithDeviceKey`, `decryptWithDeviceKey`, async). `EncryptionServiceProvider` binds the cipher; `key:generate` writes `APP_KEY`. The payload is `base64(iv):base64(ciphertext)`, carries no MAC and is not Laravel's format.

This skill covers `magic_encryption` only. The Magic framework itself (container, facades, `Vault`, config) is the `magic-framework` skill.

## Install

```bash
flutter pub add magic_encryption
dart run magic:dowel plugin:install magic_encryption
dart run magic:dowel key:generate
```

Requires Dart >=3.13, Flutter >=3.47 and `magic` ^1.0.0. The installer registers `EncryptionServiceProvider` in `lib/config/app.dart` and publishes no config, because `magic:install` already wires `'key': env('APP_KEY')`. It never runs `key:generate`. Import only the barrel: `package:magic_encryption/magic_encryption.dart`.

## Crypt rules

1. Register `EncryptionServiceProvider` in `providers` before calling `Crypt.encrypt` or `Crypt.decrypt`: it is not auto-registered, and the facade resolves the `encrypter` binding it creates in `boot()`. Call `Crypt` after `Magic.init` completes.
2. Never call `Crypt.encrypt('')`. An empty string throws `RangeError`, because there is no block to pad. Guard the call.
3. `Crypt` takes and returns a `String`. Encode a `Map` or `List` with `jsonEncode` before and `jsonDecode` after.
4. Catch `MagicDecryptException` from `decrypt` and answer the party that sent the payload with one generic error. Different failures shown to a sender are what a padding oracle is built from.
5. A missing or wrong-size `app.key` does not fail boot. The first `Crypt` call throws an `Exception`. A raw key is 32 bytes of UTF-8 (32 characters for ASCII); a `base64:` key decodes to 32 bytes.
6. Treat `Crypt` as confidentiality at rest and nothing more. There is no MAC, so a payload that decrypts is not proven untampered, and CBC is malleable. Verify a token, an amount or an identity on the server that issued it.
7. A payload from the wrong key almost always throws `MagicDecryptException`, but about one in 256 unpads cleanly and returns garbage text. Do not use a decrypt that did not throw as a key check.

## Key rules

1. Create `APP_KEY` with `dart run magic:dowel key:generate`: it writes `APP_KEY=base64:<32 random bytes>` to `.env`. `--show` prints it and leaves `.env` alone. Never commit it.
2. `key:generate` replaces any existing `APP_KEY`, and every value encrypted under the old key becomes unreadable. Never run it on an app with stored ciphertext. The payload has no key id, so there is no rotation: migrate by decrypting with `MagicEncrypter.fromAppKey(oldKey)` and encrypting again with `Crypt.encrypt`.
3. Device-key mode needs core's `VaultServiceProvider` and needs no `app.key`. The key is 32 random alphanumeric characters stored in `Vault` as `magic:device_encryption_key`, created on first use and cached in a static field.
4. `generateDeviceKey()` and `clearDeviceKey()` orphan everything encrypted under the old device key. The key is lost with the install's secure storage, so keep only data you can recreate.
5. A `Crypt.encrypt` payload and a device-key payload do not open each other's: keep a value with the mode that wrote it.

## Wire format

AES-256 in CBC mode, PKCS7 padding, key bytes either the UTF-8 bytes of a raw string (32 bytes, 32 characters for ASCII) or the 32 decoded bytes of a `base64:` key, a random 16-byte IV per call, UTF-8 plaintext, payload `base64(iv):base64(ciphertext)`. It is the format Magic 0.0.41 and earlier wrote, so it never changes. It is not Laravel's JSON-with-HMAC payload: neither side reads the other's. `MagicEncrypter.encrypt` has an `iv:` parameter for tests only.

## Recipes

Encrypt and decrypt with the app key:

```dart
import 'package:magic_encryption/magic_encryption.dart';

String? open(String payload) {
  try {
    return Crypt.decrypt(payload);
  } on MagicDecryptException {
    return null; // Log it; do not tell the sender why.
  }
}

String seal(String value) => Crypt.encrypt(value);
```

Keep a token on the device only:

```dart
import 'package:magic_encryption/magic_encryption.dart';

Future<String> store(String token) => Crypt.encryptWithDeviceKey(token);

Future<String> load(String stored) => Crypt.decryptWithDeviceKey(stored);
```

## Testing

No mocking library is needed. In `setUp()` call `MagicApp.reset()` and `Magic.flush()`, then bind a cipher with `Magic.singleton('encrypter', () => MagicEncrypter('0123456789abcdef0123456789abcdef'))` for config-key mode, or `Vault.fake()` for device-key mode. `Crypt` caches the device encrypter in a static field that `Magic.flush()` does not reset, so call `await Crypt.clearDeviceKey()` in `tearDown()`. Do not assert that a wrong-key payload throws, since about one in 256 does not; assert it never yields the plaintext. Pin the IV with `encrypt(value, iv: Uint8List(16))` to assert an exact payload.
