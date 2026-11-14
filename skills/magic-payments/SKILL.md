---
name: magic-payments
description: "Read the entitlement and run web or store purchases in a Magic app with the Payments facade and its two rails."
version: 1.0.0
when_to_use: "Use when code imports package:magic_payments or touches Payments, WebBillingService, StoreBillingService, StoreIdentitySync or BillingException."
---

# magic_payments

Subscription billing for a Magic app. The `Payments` facade reads what the customer is entitled to (`currentEntitlement`, `getPlans`, `getUsage`, `getInvoices`, `getPaymentMethod`) from your backend, and exposes two nullable rails: `Payments.web` (hosted checkout, plan swap, cancel, portal) and `Payments.store` (App Store and Play purchases through RevenueCat). The package calls your backend and the RevenueCat SDK; it never calls a payment vendor itself, and the backend decides who is entitled.

This skill covers `magic_payments` only. The Magic framework itself (container, facades, `Http`, `Config`, `Auth`, providers) is the `magic-framework` skill, and the dowel command line is the `dowel` skill.

## Install

```bash
flutter pub add magic_payments
dart run magic:dowel plugin:install magic_payments
dart run magic:dowel payments:doctor
```

Requires Dart >=3.13, Flutter >=3.47, `magic` ^1.0.0 and a backend that serves `/billing`. The installer publishes `lib/config/payments.dart`, registers `PaymentsServiceProvider` in `lib/config/app.dart` and adds `paymentsConfig` to `configFactories` in `lib/main.dart`. On iOS and Android fill in `payments.revenuecat.public_sdk_key`. Import only the barrel: `package:magic_payments/magic_payments.dart`.

## Facade and manager rules

1. Check `Payments.web` and `Payments.store` for `null` before you render a purchase affordance. A `null` rail is a build that cannot serve it: web builds have the web rail, iOS and Android have the store rail, macOS, Windows and Linux have neither. A button rendered and then caught when it fails is the shape this package replaced.
2. Never pick a rail or a management screen with `kIsWeb` or `Platform.is*`. The rail that sold a subscription and the platform the app runs on are different facts: a subscription bought on a phone is managed in its store when the customer opens the web app.
3. The five reads are always present on `Payments.billing` and as static methods on `Payments`. They throw `BillingException` on a failed or malformed response, and `UnsupportedPlatformException` only on a platform that is neither web nor `dart:io`.
4. `payments.driver` accepts `platform` only. Any other value is logged as an error at boot and ignored, and `payments:configure --driver=x` exits 1. Replace a role in code with `Payments.extend(PaymentsManager.storeRole, () => MyRail())`; `extend` throws `BillingException` for a role outside `billing`, `web` and `store`.
5. Register the provider before the first `Payments` call. `boot()` resolves the driver once and logs which rails exist.

## Entitlement rules

1. Branch a management screen on `BillingEntitlement.manageVia` (`portal`, `appStore`, `playStore`, `none`). It follows the rail that sold the subscription, so a store case can reach a web build where `Payments.store` is `null`: use `manageUrl` there when it is set, otherwise tell the customer which store manages it. Never end a store case on `Payments.store?.openStoreManagement()`, which does nothing on that build.
2. Read `currentEntitlement()` again after any write. The backend's answer is the grant; a `true` from `purchase` or a returned `checkout` only says something happened.
3. `getPlans()` returns each tier's row undecoded as `Map<String, dynamic>`. The product keys `purchase`, `checkout` and `swap` take are the `key` values in a row's `products` list.
4. Gate access on `PlanStatus` and not on `subscribed` alone: `trialing`, `pastDue` and `grace` still carry access, and `PlanStatus.isDunning` is `true` for `pastDue` and `grace`.
5. `getPaymentMethod()` reports a rail outage as a `PaymentMethod` with every field null. Gate the copy on `PaymentMethod.available`, not on a null `last4`.
6. `getInvoices({cursor})` addresses the first page by sending no cursor. Keep `nextCursor` from each page and send it back; do not reuse a stored one on a reset.

## Web rail rules

1. `checkout({productKey, successUrl, cancelUrl})` and `openPortal({returnUrl})` open the hosted page your backend returns in an in-app web view, so the customer returns to the app. A launcher that refuses the page throws `BillingException` instead of reporting success.
2. One `productKey` names the tier and the cycle (`'pro_annual'`), so a call cannot lose half of it. `swap({productKey})` sends the same key.
3. A 422 with `code: product_not_sellable` is `BillingErrorCode.productUnavailable`. A 402 whose `billing.reason` is `payment_failed` or `payment_requires_action` is `paymentDeclined` or `paymentRequiresAction`, and nothing changed. Every other refusal is `unknown`.
4. `cancel()` is normally end of period: the entitlement keeps granting until `currentPeriodEnd`.

## Store rail rules

1. Non-null `Payments.store` does not mean configured. A blank or absent `payments.revenuecat.public_sdk_key` throws `BillingErrorCode.notConfigured` the first time the SDK is needed. The key is RevenueCat's public one (`appl_...` for the App Store, `goog_...` for Play) and ships in the app bundle; the secret key never belongs in the client.
2. `purchase(productKey, {context})` returns `true` when the store completed a transaction and `false` when the customer dismissed the sheet. Neither says what `currentEntitlement()` answers next, because the backend's webhook may not have landed.
3. The product key must equal a RevenueCat package identifier in one of your offerings. A key with none throws `productUnavailable`. `products(keys)` prices through the same lookup and omits a key the store has no product for: render it as unavailable.
4. Render `StoreProductOffer.priceString`, not the catalogue's price: the store decides currency, tax and rounding. Show intro copy only when `introEligible` is `true`; it defaults to `false`, and an `introPrice` alone does not mean this customer may take the offer.
5. Pass a `PurchaseContext` (`tierOrder`, `tierOfProduct`, `tierOfStoreProduct`) when the customer already holds a subscription. Play needs it to rank an upgrade against a downgrade; without it a change between Play subscriptions is refused. After a `true`, `lastChangeTiming` is `immediate`, `atRenewal` or `null` (nothing to announce).
6. The rail refuses rather than guesses: `notIdentified`, `identityMismatch`, `managedElsewhere` (the other store sells the subscription), `unmappedActiveProduct` (a Play product nothing ranks). It does not see a web-billed subscription, so gate a store purchase on `entitlement.manageVia != ManageVia.portal`.
7. On iOS and Android never render a link or a call to action to web checkout or the web portal: App Review Guideline 3.1.3(a) restricts steering a customer to another purchase method.

## StoreIdentitySync rules

1. Set `StoreIdentitySync.billableId` (a `String? Function()`) to the paying subject, a user or a team, call `attach()` once, then `await StoreIdentitySync.syncNow()`, all after `await Magic.init(...)`. `attach()` only adds a listener for later `Auth.stateNotifier` changes, and `Magic.init` already restored a returning user's session, so without the `syncNow()` that user's rail stays unidentified; without `billableId` `purchase` and `restore` throw `notIdentified`.
2. After a switch of the paying subject that does not change auth state, `await StoreIdentitySync.syncNow()` again. Syncs run one at a time in call order, and the same id twice in a row identifies once.
3. A `BillingException` from a sync is logged and not thrown, because the login or switch that prompted it already succeeded. Do not call `identify` yourself on top of the sync, and never call `recordBinding`: it is `@internal`.

## Errors

Switch on `BillingException.code`, a `BillingErrorCode`, and never on `message`: the message is prose that differs per rail and locale. The code is client side only and never crosses the wire. Codes: `notConfigured`, `notIdentified`, `identityMismatch`, `managedElsewhere`, `unmappedActiveProduct`, `productUnavailable`, `pending`, `receiptInUse`, `alreadyOwned`, `paymentDeclined`, `paymentRequiresAction`, `network`, `store`, `unknown`. `pending` is a store purchase that has not settled, not a failure to retry.

## Command line

`payments:install` (`--dry-run`, `--force`) re-applies the install plan; `payments:configure` (`--show`, `--driver=platform`) edits the one `driver` value; `payments:doctor` (`--verbose`, `--json`) is read only. Only `payments_doctor` is an MCP tool. The doctor reports the store key as a state and never its value (`present` in `--json` and `declared` in the human report, otherwise `absent` or `blank`), a blank key warns and still exits 0, and it cannot say which rails a build serves because that is a compile-time import.

## Recipes

Read the entitlement and open the surface that owns it:

```dart
import 'package:magic_payments/magic_payments.dart';

// `openUrl` stands for your app's own URL launcher.
Future<void> manageSubscription(
  Future<void> Function(String url) openUrl,
) async {
  try {
    final BillingEntitlement entitlement = await Payments.currentEntitlement();

    if (!entitlement.subscribed) return;

    switch (entitlement.manageVia) {
      case ManageVia.portal:
        final WebBillingService? web = Payments.web;

        if (web != null) {
          // Web builds only.
          await web.openPortal();
        } else {
          // iOS, Android and desktop have no portal call, and iOS and Android
          // must not link to the web portal: say where it is managed, no link.
        }
      case ManageVia.appStore:
      case ManageVia.playStore:
        final StoreBillingService? store = Payments.store;
        final String? manageUrl = entitlement.manageUrl;

        if (store != null) {
          // iOS and Android builds.
          await store.openStoreManagement();
        } else if (manageUrl != null) {
          // The web app and desktop: `Payments.store` is null there.
          await openUrl(manageUrl);
        } else {
          // Nothing to open: say it is managed in the App Store or Google Play,
          // without a link.
        }
      case ManageVia.none:
        break;
    }
  } on BillingException catch (error) {
    // Decide what to tell the customer from `error.code`, never `error.message`.
  }
}
```

`Payments.store?.openStoreManagement()` does nothing on the web app, where `Payments.store` is `null`, so a store case never ends on a null-aware call. `openStoreManagement()` exists on iOS and Android builds only; elsewhere use `manageUrl` when the backend sent one, and otherwise only tell the customer which store manages the subscription. `manageUrl` is `null` for `portal` by design.

Upgrade on the web rail:

```dart
import 'package:magic_payments/magic_payments.dart';

Future<void> upgrade() async {
  final WebBillingService? web = Payments.web;
  if (web == null) return;

  try {
    await web.checkout(
      productKey: 'pro_annual',
      successUrl: 'https://example.com/billing?checkout=success',
      cancelUrl: 'https://example.com/billing?checkout=cancel',
    );
  } on BillingException catch (error) {
    if (error.code == BillingErrorCode.productUnavailable) {
      // The backend has no price for this key.
    }
  }
}
```

Keep the store identified, then buy:

```dart
import 'package:magic_payments/magic_payments.dart';

Future<void> wireStore(String? Function() payingId) async {
  StoreIdentitySync.billableId = payingId;
  StoreIdentitySync.attach();
  await StoreIdentitySync.syncNow();
}

Future<String> buy(String productKey) async {
  final StoreBillingService? store = Payments.store;
  if (store == null) return 'unavailable';

  try {
    // The rail cannot see a subscription billed on the web (store rule 6).
    final BillingEntitlement held = await Payments.currentEntitlement();
    if (held.manageVia == ManageVia.portal) return 'managed on the web';

    if (!await store.purchase(productKey)) return 'dismissed';

    await Payments.currentEntitlement();

    return switch (store.lastChangeTiming) {
      StoreChangeTiming.atRenewal => 'changes at renewal',
      StoreChangeTiming.immediate || null => 'done',
    };
  } on BillingException catch (error) {
    return error.code.name;
  }
}
```

## Testing

No mocking library and no network. Stand in for a rail with `Payments.extend(role, factory)` and a class that implements the contract, then drop the override in `tearDown` with `Payments.forgetDrivers()`: `PaymentsManager` is a `static final` that outlives a container reset, so a fake from one test would answer the next. A store fake implements every `StoreBillingService` member: `identify`, `purchase`, `products`, `restore`, `openStoreManagement`, `store` and `lastChangeTiming`.

```dart
import 'package:magic_payments/magic_payments.dart';

class FakeStore implements StoreBillingService {
  @override
  ManageVia get store => ManageVia.appStore;

  @override
  StoreChangeTiming? get lastChangeTiming => null;

  @override
  Future<void> identify(String appUserId) async {}

  @override
  Future<bool> purchase(String productKey, {PurchaseContext? context}) async => true;

  @override
  Future<Map<String, StoreProductOffer>> products(List<String> productKeys) async => {};

  @override
  Future<bool> restore() async => false;

  @override
  Future<void> openStoreManagement() async {}
}

void arrange() {
  Payments.extend(PaymentsManager.storeRole, () => FakeStore());
}

void tearDownPayments() {
  Payments.forgetDrivers();
}
```

Build a test fixture from what your backend really sends: the entitlement decodes `plan_status`, not `status`, and a key the producer never emits proves nothing. Loop the whole vocabulary of an enum through its `fromWire` and assert nothing lands on the fallback.
