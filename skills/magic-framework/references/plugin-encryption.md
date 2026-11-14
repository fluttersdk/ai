<!-- magic_encryption v1.0.0 | Updated: 2026-11-14 -->

# magic_encryption Plugin

AES-256-CBC for a Magic app: the `Crypt` facade, `MagicEncrypter`, `EncryptionServiceProvider`, `MagicDecryptException` and the `key:generate` command. They lived in core `magic` up to 0.0.41 and moved here in core 1.0.0, with the wire format unchanged, so ciphertext written by 0.0.41 still decrypts.

## Contents

- [Installation](#installation)
- [Crypt Facade API](#crypt-facade-api)
- [Wire format](#wire-format)
- [Key management](#key-management)
- [Testing](#testing)
- [Gotchas](#gotchas)

## Installation

```yaml
dependencies:
  magic_encryption: ^1.0.0
```

Requires Dart >=3.13, Flutter >=3.47 and `magic ^1.0.0`.

```bash
flutter pub add magic_encryption
dart run magic:dowel plugin:install magic_encryption
dart run magic:dowel key:generate
```

The installer registers `EncryptionServiceProvider` in `lib/config/app.dart` and publishes no config (`magic:install` already wires `'key': env('APP_KEY')`). It never runs `key:generate`. Import only the barrel `package:magic_encryption/magic_encryption.dart`; it exports `Crypt`, `MagicEncrypter`, `EncryptionServiceProvider` and `MagicDecryptException`.

## Crypt Facade API

`Crypt` resolves `MagicEncrypter` from the container key `'encrypter'`, bound by `EncryptionServiceProvider.boot()`. The provider is NOT auto-registered.

| Member | Return type | Notes |
|:-------|:------------|:------|
| `Crypt.encrypt(String value)` | `String` | AES-256-CBC with `app.key`. Synchronous. An empty string throws `RangeError`. |
| `Crypt.decrypt(String payload)` | `String` | Throws `MagicDecryptException` on a bad payload. |
| `Crypt.encryptWithDeviceKey(String value)` | `Future<String>` | Uses a per-device key kept in `Vault` (`magic:device_encryption_key`), created on first use. Needs core's `VaultServiceProvider`, no `app.key`. |
| `Crypt.decryptWithDeviceKey(String payload)` | `Future<String>` | Counterpart of the above. |
| `Crypt.hasDeviceKey()` | `Future<bool>` | Whether a device key exists. |
| `Crypt.generateDeviceKey()` | `Future<void>` | Generates or replaces the key; orphans data under the old one. |
| `Crypt.clearDeviceKey()` | `Future<void>` | Removes the key; data under it is unrecoverable. |

```dart
import 'package:magic_encryption/magic_encryption.dart';

final sealed = Crypt.encrypt('sensitive');
final plain = Crypt.decrypt(sealed);

final pin = await Crypt.encryptWithDeviceKey('pin:1234');
```

## Wire format

AES-256-CBC, PKCS7 padding, a random 16-byte IV per call, UTF-8 plaintext, payload `base64(iv):base64(ciphertext)`. The key is either the UTF-8 bytes of a 32-character string or the 32 decoded bytes of a `base64:` key. There is no MAC and it is not Laravel's JSON-with-HMAC format. `MagicEncrypter.encrypt` has an `iv:` parameter for tests only.

## Key management

`dart run magic:dowel key:generate` writes `APP_KEY=base64:<32 random bytes>` to `.env`; `--show` prints it instead. It replaces any existing `APP_KEY`, and the payload has no key id, so there is no rotation: decrypt with `MagicEncrypter.fromAppKey(oldKey)` and re-encrypt with `Crypt.encrypt`. A missing or wrong-size `app.key` does not fail boot; the first `Crypt` call throws.

## Testing

Bind a cipher by hand: `Magic.singleton('encrypter', () => MagicEncrypter('0123456789abcdef0123456789abcdef'))` for config-key mode, or `Vault.fake()` for device-key mode. `Crypt` caches the device encrypter in a static field that `Magic.flush()` does not clear, so call `await Crypt.clearDeviceKey()` in `tearDown()`.

## Gotchas

| Mistake | Fix |
|:--------|:----|
| Calling `Crypt` without `EncryptionServiceProvider` | Register it in `providers`; the facade resolves the binding it creates in `boot()`. |
| `Crypt.encrypt('')` | Guard the call; an empty string throws `RangeError`. |
| Encrypting a `Map` or `List` | `jsonEncode` before and `jsonDecode` after; `Crypt` takes and returns a `String`. |
| Showing the sender why a decrypt failed | Catch `MagicDecryptException` and answer one generic error (padding oracle). |
| Treating a decrypt that did not throw as a key check | About one wrong-key payload in 256 unpads cleanly to garbage. |
| Reading `Crypt` as authentication | No MAC: confidentiality at rest only. Verify tokens and amounts on the server. |
| Mixing modes | A config-key payload and a device-key payload do not open each other's. |
| Running `key:generate` on an app with stored ciphertext | It replaces `APP_KEY` and orphans everything encrypted under the old one. |
