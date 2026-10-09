<!-- magic_payments v0.0.8 | Updated: 2026-10-09 -->

# magic_payments Plugin

Multi-rail billing for Magic Framework: one entitlement contract over Stripe on the web and store in-app purchase on iOS and Android. A consumer asks what a customer is entitled to and where they manage it; which rail sold the subscription is the package's problem, not the caller's.

The backend half of the same contract lives in `magic-starter-laravel` (`api/v1/billing`), and the ready-made screen that consumes it is `magic_starter`'s `teams.billing` view. Change one side, keep the other in sync.

## Contents

- [Installation](#installation)
- [Upgrading from 0.0.7](#upgrading-from-007)
- [The three roles](#the-three-roles)
- [Product keys](#product-keys)
- [Payments Facade API](#payments-facade-api)
- [The store rail](#the-store-rail)
- [Typed errors](#typed-errors)
- [Models and enums](#models-and-enums)
- [Configuration](#configuration)
- [CLI commands and MCP tools](#cli-commands-and-mcp-tools)
- [Keeping the store rail on the payer](#keeping-the-store-rail-on-the-payer)
- [Swapping a rail](#swapping-a-rail)
- [Gotchas](#gotchas)

## Installation

```yaml
dependencies:
  magic_payments: ^0.0.8
```

0.0.8 pins `magic ^0.0.27` and `fluttersdk_artisan ^0.0.19`, the newest of each at that release, and `purchases_flutter ^10.15.1` for the store rail.

```bash
# Register the plugin's artisan provider with the app dispatcher (once)
dart run magic:artisan plugin:install magic_payments

# Publish lib/config/payments.dart and register the config factory
dart run magic:artisan payments:install
```

`payments:install` also registers the service provider in `lib/config/app.dart`. Without the installer, add it by hand:

```dart
'providers': [
  // ...existing providers...
  (app) => PaymentsServiceProvider(app),
],
```

`register()` binds `PaymentsManager` under the container key `'payments'`. `boot()` reads `payments.driver`, wires the rail the conditional-import factory resolved for this build, and logs which implementation answered plus which rails came with it.

## Upgrading from 0.0.7

0.0.8 is a BREAKING release of the purchase contract. Nothing compiles against it unchanged if it called a rail or implemented one.

| 0.0.7 | 0.0.8 |
|:------|:------|
| `store.purchase(plan: 'pro')` | `store.purchase('pro_monthly', context: purchaseContext)` |
| `web.checkout(plan: 'pro', cycle: BillingCycle.annual, successUrl: ..., cancelUrl: ...)` | `web.checkout(productKey: 'pro_annual', successUrl: ..., cancelUrl: ...)` |
| `web.swap(plan: 'pro', cycle: BillingCycle.annual)` | `web.swap(productKey: 'pro_annual')`, which POSTs `{product: key}` |
| matching `BillingException.message` | switch on `BillingException.code` (a `BillingErrorCode`) |
| `BillingEntitlement.aiAnalysisTrialsRemaining` | removed; read `entitlement.allowances` or `entitlement.balances` |
| a class implementing `StoreBillingService` (a test fake included) | also implements `products()`, `store` and `lastChangeTiming` |
| calling `Payments.store!.identify()` yourself, with `StoreIdentitySync.billableId` unset | set `billableId`: `purchase` and `restore` now resolve the paying subject from it and refuse with `notIdentified` while it is unset |
| calling `StoreIdentitySync.recordBinding` | `@internal` now; the rail driver is its only caller |

The migration rule for a purchase: pass the catalogue key your backend uses for that tier and cycle (`'pro'` plus `BillingCycle.annual` becomes `'pro_annual'`). On the store rail the key must also equal a RevenueCat package identifier.

## The three roles

Billing is split into three contracts, and the split is the API. `BillingService` is honourable everywhere; the two rails are nullable, and `null` means this build cannot serve that rail.

| Role | Contract | Where it exists |
|:-----|:---------|:----------------|
| Reads | `BillingService` | Everywhere. Five reads over HTTP against the backend. |
| Web rail | `WebBillingService?` | Web builds only. Hosted Stripe checkout, product swap, cancel, customer portal. |
| Store rail | `StoreBillingService?` | iOS and Android only, via RevenueCat. `null` on macOS, Windows, Linux and web. |

> [!IMPORTANT]
> A rail is CHECKED, never assumed. `if (Payments.web != null)` is what decides whether a purchase affordance renders at all. A throwing implementation would render a button that fails when tapped, which is the shape the rail split exists to prevent. Note that `dart.library.io` is true on desktop too, so the store rail asks the device question separately rather than answering from the import arm.

| Contract | Members |
|:---------|:--------|
| `BillingService` | `currentEntitlement()`, `getPlans()`, `getUsage()`, `getInvoices({cursor})`, `getPaymentMethod()` |
| `WebBillingService` | `checkout({required productKey, required successUrl, required cancelUrl})`, `swap({required productKey})`, `cancel()`, `openPortal({returnUrl})` |
| `StoreBillingService` | `identify(appUserId)`, `purchase(productKey, {context})`, `products(productKeys)`, `restore()`, `openStoreManagement()`, and the getters `store` and `lastChangeTiming` |

## Product keys

`purchase`, `checkout` and `swap` all take the same thing: the vendor's own catalogue key, such as `'pro_annual'`. It is never a store product id and never a Stripe price id. Which store product or price a key maps to belongs to the rail's catalogue (on the store rail, the RevenueCat package identifier, searched in the current offering first and then the rest; on the web rail, the backend's price table), so adding or repricing a product needs no client release.

One key names the tier AND the cycle, and that is the point of the change. A tier is not a price: `pro` sold monthly and again at a discounted annual rate is one tier and two products. When tier and cycle travelled as two words, a call that lost the second let the backend pick a price while the screen showed the other, and a customer choosing the annual discount was charged the monthly price. A single key cannot be half-sent.

`getPlans()` still returns each row verbatim (`List<Map<String, dynamic>>`), because a tier's own fields are the vendor's product. The rows `magic-starter-laravel` serves carry a `products` list, and that is where the keys live:

```json
{
  "id": "pro",
  "cycles": ["monthly", "annual"],
  "products": [
    {
      "key": "pro_monthly",
      "type": "subscription",
      "tier": "pro",
      "cycle": "monthly",
      "sellable": true,
      "store_ids": {"app_store": "com.example.pro.monthly", "play": "pro:monthly"},
      "prices": {"web": {"USD": {"amount_minor": 2900, "display": "29.00 USD"}}}
    }
  ]
}
```

A row lists every subscription product of its tier, including grandfathered ones (`sellable: false`) that a customer may still hold. Nothing may offer or price a non-sellable product, but it stays in the row so a held one can be ranked. `magic_starter` decodes these rows into `MagicStarterPlan` and `MagicStarterProduct`; see `references/plugin-starter.md`.

The web rail sends the key as `product`. The producer refuses a key it cannot sell with a 422 carrying `code: product_not_sellable`, which the driver throws as `BillingException` with `BillingErrorCode.productUnavailable` and the producer's message; any other 422 stays `unknown`.

## Payments Facade API

`Payments` is a static stub over `PaymentsManager` in magic's facade style; it forwards and decides nothing.

| Member | Return type | Description |
|:-------|:------------|:------------|
| `Payments.manager` | `PaymentsManager` | The singleton every member forwards to. |
| `Payments.billing` | `BillingService` | The five reads. Always present. |
| `Payments.web` | `WebBillingService?` | The web rail, or `null` where this build cannot serve one. |
| `Payments.store` | `StoreBillingService?` | The store rail, or `null` where this build cannot serve one. |
| `Payments.currentEntitlement()` | `Future<BillingEntitlement>` | What the customer is entitled to right now. |
| `Payments.getPlans()` | `Future<List<Map<String, dynamic>>>` | The plan catalogue, cheapest tier first, rows verbatim. |
| `Payments.getUsage()` | `Future<List<UsageStat>>` | Usage meters for the current period. |
| `Payments.getInvoices({cursor})` | `Future<BillingInvoicesPage>` | One page of invoice history. The page carries `nextCursor`; pass it back to advance. |
| `Payments.getPaymentMethod()` | `Future<PaymentMethod>` | The card on file. |
| `Payments.extend(role, factory)` | `void` | Replace a role with your own implementation or a fake. |
| `Payments.forgetDrivers()` | `void` | Drop every `extend()` override and every resolved role. Test teardown: an override registered once in `setUpAll` is gone after the first teardown. |

Every failure surfaces as `BillingException`, classified by its `code`.

## The store rail

`RevenueCatStoreService` implements `StoreBillingService`; `Payments.store` is non-null on iOS and Android. Non-null does NOT mean configured: the driver reads `payments.revenuecat.public_sdk_key` the first time it needs the SDK and throws `BillingException` with `BillingErrorCode.notConfigured` when the key is blank or absent.

A `true` from `purchase()` or `restore()` says the STORE reported a completed transaction. It says nothing about what `currentEntitlement()` answers a moment later: the rail's webhook is the authority, and the backend may not have been told yet. Re-read the entitlement and treat a stale answer as "not yet". `false` from `purchase()` is a dismissed sheet, not an error.

```dart
final StoreBillingService? store = Payments.store;
if (store != null) {
  final Map<String, StoreProductOffer> offers =
      await store.products(<String>['pro_monthly', 'pro_annual']);

  final bool bought = await store.purchase(
    'pro_annual',
    context: const PurchaseContext(
      tierOrder: <String>['free', 'pro', 'business'],
      tierOfProduct: <String, String>{'pro_monthly': 'pro', 'pro_annual': 'pro'},
      tierOfStoreProduct: <String, String>{'pro:monthly': 'pro'},
    ),
  );

  if (bought) {
    switch (store.lastChangeTiming) {
      case StoreChangeTiming.immediate:
      case null:
        await Payments.currentEntitlement(); // may still be "not yet"
      case StoreChangeTiming.atRenewal:
        // The held product runs to its period end; nothing moves now.
        break;
    }
  }
}
```

| Member | Contract |
|:-------|:---------|
| `products(List<String> productKeys)` | `Future<Map<String, StoreProductOffer>>` keyed by catalogue key. A store build renders these figures, not the catalogue's, because the store decides currency, tax and rounding. A key the store has no product for is ABSENT from the map: render it as unavailable, never with a guessed price. |
| `store` | `ManageVia.appStore` or `ManageVia.playStore`. Compare it with `BillingEntitlement.manageVia` to tell a subscription this store can change from one another rail sold, without asking the running platform. |
| `purchase(productKey, {PurchaseContext? context})` | The context carries the catalogue's tier order so the rail can tell an upgrade from a downgrade; the rail knows products, not tiers. |
| `lastChangeTiming` | `StoreChangeTiming?` for the last purchase that changed a held subscription: `immediate` or `atRenewal`. `null` for a fresh purchase, a dismissed or refused one, or a change the rail cannot rank. Treat `null` as "nothing to announce", never as either answer. |

`PurchaseContext` has three fields: `tierOrder` (lowest to highest), `tierOfProduct` (catalogue key to tier) and `tierOfStoreProduct` (store product id to tier, default empty). Build `tierOfStoreProduct` from every row's `products[].store_ids`, non-sellable products included: it is the only way the rail can rank a grandfathered product, which has no catalogue key in any current offering. A Play id is `subscriptionId:basePlanId`; the rail matches the full id first, then the bare subscription id.

On Google Play the context decides the replacement mode of a product change:

| Change | Replacement mode | `lastChangeTiming` |
|:-------|:-----------------|:-------------------|
| same subscription, longer period | `chargeFullPrice` | `immediate` |
| same subscription, same or shorter period | `withoutProration` | `immediate` |
| higher tier, price per day rises | `chargeProratedPrice` | `immediate` |
| higher tier, price per day does not rise | `chargeFullPrice` | `immediate` |
| same or lower tier | `deferred` | `atRenewal` |

Without a context a change between Play subscriptions is refused rather than guessed. An upgrade from a grandfathered Play product is charged in full, and a base-plan switch from one is refused as `unmappedActiveProduct`. On the App Store, StoreKit moves a subscription inside its group on its own; `lastChangeTiming` follows Apple's rules (a higher level now, a lower level or another duration of the same level at renewal).

The store rail refuses instead of guessing, each refusal a typed `BillingException`:

- `purchase` and `restore` first run `StoreIdentitySync.syncNow()`, then refuse with `notIdentified` when `StoreIdentitySync.billableId` answers nothing, and with `identityMismatch` when the SDK's `appUserID` is not the id it answers.
- A purchase is refused when the account's active store subscription was sold by the OTHER store: `managedElsewhere`. The rail reads only RevenueCat's active products and never `manageVia`, so it does NOT refuse a subscription Stripe bills. Check `entitlement.manageVia != ManageVia.portal` before offering a store purchase, as `magic_starter`'s `canPurchaseViaStore` does, or the customer pays on both rails.
- A purchase is refused when the account holds an active Play product nothing ranks, or more than one Play subscription: `unmappedActiveProduct`.

A RevenueCat promotional grant (`rc_promo_...`) is no store's subscription and takes part in none of these checks.

## Typed errors

`BillingException.code` is a `BillingErrorCode`. Branch on it, never on `message`, which is prose that differs per rail and per locale. A throw site that names no cause answers `unknown`. The code is client-side only and never crosses the wire.

| `BillingErrorCode` | Meaning |
|:-------------------|:--------|
| `notConfigured` | No `public_sdk_key` in this build. |
| `notIdentified` | No paying account identified before a purchase. |
| `identityMismatch` | The rail is bound to a different account than the one asking. |
| `managedElsewhere` | Another rail manages the subscription. |
| `unmappedActiveProduct` | An active product the catalogue cannot name, so no change is safe. |
| `productUnavailable` | The rail has no product for the key, or the backend will not sell it (`product_not_sellable`). |
| `pending` | The store accepted but has not settled it (parental approval, deferred payment). Not a failure to retry. |
| `receiptInUse` | The receipt belongs to another paying account. |
| `alreadyOwned` | The customer already holds the product. |
| `network` | The request or its answer never arrived. |
| `store` | The store refused for a reason none of the above names. |
| `unknown` | No cause named. |

`UnsupportedPlatformException` is a `BillingException` subtype for a rail that is present but cannot serve the running device.

## Models and enums

`BillingEntitlement` is the one a consumer reads most. Its seventeen fields: `plan`, `planStatus`, `subscribed`, `renews`, `cycle`, `provider`, `providerStatus`, `productId`, `manageVia`, `manageUrl`, `currentPeriodEnd`, `trialEndsAt`, `gracePeriodEndsAt`, `productKey`, `owned`, `balances`, `allowances`, plus `raw`.

- `productKey` (wire `product`) is the catalogue key the subscription is on, the same key `purchase` and `checkout` take; compare it with a row product's `key` to mark the current product. `productId` is the rail's own SKU or price id, a different thing.
- `owned` (`List<String>`) lists one-off product keys owned for good, `balances` (`Map<String, int>`) the remaining units per consumable, and `allowances` (`Map<String, dynamic>`) the vendor's in-product allowances, undecoded. All three default to empty; a PHP `[]` decodes as empty.
- `aiAnalysisTrialsRemaining` is gone in 0.0.8. It was one vendor's allowance on a shared model; read it from `allowances` or `balances`.

| Enum | Values | Notes |
|:-----|:-------|:------|
| `PlanStatus` | `none`, `trialing`, `active`, `pastDue`, `grace`, `canceled`, `expired`, `paused` | `pastDue` and `grace` are the two where a payment has FAILED and the customer still has access. Render a dunning notice on both. |
| `BillingProvider` | `none`, `stripe`, `appStore`, `playStore`, `manual` | Who sold the subscription. |
| `BillingCycle` | `monthly`, `annual` | What the customer bought (`entitlement.cycle`) and a product's cycle. No longer a purchase argument. |
| `ManageVia` | `none`, `portal`, `appStore`, `playStore` | Where the customer manages the subscription, and what `StoreBillingService.store` answers. |
| `ProductType` | `subscription`, `consumable`, `nonConsumable`, `physical` | What a product sells. Wire words via `toWire()` / `fromWire()`: `nonConsumable` is `non_consumable`, and an unknown word decodes to `null`, never a guess. Only a subscription has a cycle; the stores cannot sell `physical`. |
| `StoreChangeTiming` | `immediate`, `atRenewal` | Client-side only, from `lastChangeTiming`. |
| `BillingErrorCode` | see [Typed errors](#typed-errors) | Client-side only. |
| `InvoiceStatus` | `paid`, `pending`, `failed` | |

`StoreProductOffer` carries the store's own answer: `priceString` (localized, render this), `currencyCode`, `price` (for arithmetic, not display), `subscriptionPeriod` (ISO 8601, `P1M`, `null` for a product that does not renew) and the intro fields `introPrice`, `introPriceString`, `introPeriod`.

Other models: `PurchaseContext`, `BillingCheckoutSession`, `BillingInvoicesPage` (`invoices` + `nextCursor`), `Invoice`, `PaymentMethod`, `UsageStat`.

## Configuration

```dart
'payments': {
  'driver': 'platform',
  'revenuecat': {
    'public_sdk_key': env('REVENUECAT_PUBLIC_SDK_KEY', ''),
    'subject_label': 'team',
  },
},
```

| Key | Default | Read by |
|:----|:--------|:--------|
| `payments.driver` | `'platform'` | `PaymentsServiceProvider.boot()` |
| `payments.revenuecat.public_sdk_key` | none, REQUIRED on iOS and Android | `RevenueCatStoreService.ensureConfigured()`; blank or absent throws `notConfigured` |
| `payments.revenuecat.subject_label` | none in code; the published stub sets `'team'` | `RevenueCatStoreService`: when set, writes `<label>:<appUserId>` to the `magic_subject` subscriber attribute after `identify()` |

`'platform'` is the only value the package serves, and it means "resolve the driver from the build". The key exists so the choice is visible and `payments:doctor` can report it, not so it can be changed: which rail a build can serve is settled by the import graph, and a config key would be a second answer to that question. A different value is rejected by `payments:configure`, reported by `payments:doctor`, and logged as an error at boot before the platform driver is wired anyway.

The rails are deliberately NOT configurable. A driver of your own is registered in code with `Payments.extend()`, never named in config.

## CLI commands and MCP tools

| Command | Description |
|:--------|:------------|
| `dart run <app>:artisan payments:install` | Publish `lib/config/payments.dart`, register the config factory. |
| `dart run <app>:artisan payments:configure` | Update the config; rejects a `--driver` the package cannot serve. |
| `dart run <app>:artisan payments:doctor` | Diagnose config, keys, and which rails this build resolves. `--verbose` shows the path and the requirement behind each check. `--json` (0.0.8+) prints one object for an agent instead. |

`payments:doctor --json` prints `{ok, checks: [{id, status, message, fix?}]}` with `status` one of `ok`, `warn` or `error`, and exits with the same code as the human report. The check ids are `dependency_declared`, `dependency_resolved`, `config_published`, `config_valid`, `provider_registered`, `config_factory_wired` and `store_rail_key`. A key is reported only as `present`, `absent` or `blank`, never by value. Both modes are built from one list of checks, so they cannot drift.

Only `payments_doctor` is exposed as an MCP tool, and it accepts `json` and `verbose`. `payments:install` and `payments:configure` mutate the consumer's project, and the MCP surface stays read-only.

## Keeping the store rail on the payer

The store rail bills whoever `Payments.store!.identify(appUserId)` last named, and nothing re-identifies it when the paying subject changes: sign in as another user, or switch the team that pays, and purchases keep landing on the previous subject. `StoreIdentitySync` (0.0.5+) is the static keeper:

```dart
// Once, from a provider: the consumer decides who pays (here, the user).
StoreIdentitySync.billableId = () => Auth.id()?.toString();
StoreIdentitySync.attach();

// After switching the paying subject outside an auth change:
await StoreIdentitySync.syncNow();

// Stop following auth changes:
StoreIdentitySync.detach();
```

| Member | Type | Behaviour |
|:-------|:-----|:----------|
| `billableId` | `static String? Function()?` | Resolves the subject's id (a team or a user). Unset: identifies nothing, logs once at debug level, and every store `purchase` and `restore` refuses with `notIdentified`. |
| `attach()` | `static void` | Syncs on every `Auth.stateNotifier` change. |
| `syncNow()` | `static Future<void>` | Syncs on demand. |
| `detach()` | `static void` | Stops following auth. |

Syncs run one at a time in call order, and each reads `billableId` when its turn comes, so a switch landing mid-identify leaves the rail on the newer subject whatever order the vendor SDK finishes in. It skips a build with no store rail (`Payments.store == null`) and a session with no subject, identifies a repeated id once, identifies again after a sign-out, and logs a `BillingException` from the rail at error level instead of throwing, retrying that id on the next sync. `recordBinding` is `@internal` from 0.0.8: the rail driver records what it bound, and an app that recorded a binding by hand would make the sync skip the identify that fixes it. `magic_starter` sets `billableId` from its `magic_starter.billing.billable` key (`'user'` or `'team'`) in `register()` and calls `syncNow()` after a successful `MagicStarter.switchTeam()`; do not set the resolver again on top of it.

## Swapping a rail

```dart
// A fake in a test, or a rail the consumer implements itself.
Payments.extend(PaymentsManager.storeRole, () => MyStoreRail());

// Teardown: drop the overrides AND the resolved roles.
Payments.forgetDrivers();
```

Roles are `PaymentsManager.billingRole` (`'billing'`), `webRole` (`'web'`) and `storeRole` (`'store'`). An unknown role is refused at registration rather than silently kept, and an override that cannot serve its role fails loudly naming both types. A store fake implements all seven members, `products()`, `store` and `lastChangeTiming` included.

## Gotchas

| Mistake | Fix |
|:--------|:----|
| Assuming `Payments.web` or `Payments.store` is non-null | Check it. `null` is the answer for a build that cannot serve that rail, and it is what decides whether the purchase button renders. |
| Passing a tier id and a cycle, or a store SKU, to a purchase | Pass the catalogue product key (`'pro_annual'`). On the store rail it must equal a RevenueCat package identifier. |
| Offering or pricing a `sellable: false` product | Never. It is in the row only so a held product can be ranked; keep it in `tierOfStoreProduct`, out of every purchase and `products()` call. |
| Rendering the catalogue's web price in a store build | Render `StoreProductOffer.priceString` from `products()`. A key missing from that map is unavailable in this store. |
| Branching on `BillingException.message` | Switch on `BillingException.code`. |
| Reading `aiAnalysisTrialsRemaining` | Removed in 0.0.8. Read `allowances` or `balances`. |
| Treating the client as the entitlement authority | The backend is. These reads report what it says; a client-side check is advisory, exactly like magic's `Gate`. |
| Reading a store purchase's `true` as the grant | It is the store's word. Re-read `currentEntitlement()`; when `lastChangeTiming` is `atRenewal`, expect nothing to move until the period ends. |
| Reading only `active` as "has access" | `trialing`, `pastDue` and `grace` are access-bearing too. Branch on `PlanStatus`, not on a boolean you derived from it. |
| Dropping `nextCursor` from `getInvoices()` | The producer addresses its first page by sending NO cursor. Reusing a stored token on a reset fetches page two and renders it as the whole history. |
| `payments.driver` set to a rail name | The only accepted value is `'platform'`. A rail is chosen by the build, not by config. |
| Registering a rail in config | There is no key for it. Use `Payments.extend(role, factory)`. |
| Offering a store purchase to a Stripe-billed customer | The rail does not refuse it. Gate on `entitlement.manageVia != ManageVia.portal` first. |
| Calling `Payments.store!.identify` by hand on every switch | `StoreIdentitySync` does it on each auth change and orders overlapping syncs; hand-rolled calls can race, and the one that lands last wins. |

The ready-made UI for all of this is `magic_starter`'s `teams.billing` view (gated on its own `features.billing` toggle); see `references/plugin-starter.md`.
