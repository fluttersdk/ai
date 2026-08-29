<!-- magic_payments v0.0.1 | Updated: 2026-08-29 -->

# magic_payments Plugin

Multi-rail billing for Magic Framework: one entitlement contract over Stripe on the web and store in-app purchase on iOS and Android. A consumer asks what a customer is entitled to and where they manage it; which rail sold the subscription is the package's problem, not the caller's.

The backend half of the same contract lives in `magic-starter-laravel` (`api/v1/billing`), and the ready-made screen that consumes it is `magic_starter`'s `teams.billing` view. Change one side, keep the other in sync.

## Contents

- [Installation](#installation)
- [The three roles](#the-three-roles)
- [Payments Facade API](#payments-facade-api)
- [Models and enums](#models-and-enums)
- [Configuration](#configuration)
- [CLI commands and MCP tools](#cli-commands-and-mcp-tools)
- [Swapping a rail](#swapping-a-rail)
- [Gotchas](#gotchas)

## Installation

```yaml
dependencies:
  magic_payments: ^0.0.1
```

```bash
# Register the plugin's artisan provider with the app dispatcher (once)
dart run magic:artisan plugin:install magic_payments

# Publish lib/config/payments.dart and register the config factory
dart run magic:artisan payments:install
```

Register the service provider in `lib/config/app.dart`:

```dart
'providers': [
  // ...existing providers...
  (app) => PaymentsServiceProvider(app),
],
```

`register()` binds `PaymentsManager` under the container key `'payments'`. `boot()` reads `payments.driver`, wires the rail the conditional-import factory resolved for this build, and logs which implementation answered plus which rails came with it.

## The three roles

Billing is split into three contracts, and the split is the API. `BillingService` is honourable everywhere; the two rails are nullable, and `null` means this build cannot serve that rail.

| Role | Contract | Where it exists |
|:-----|:---------|:----------------|
| Reads | `BillingService` | Everywhere. Five reads over HTTP against the backend. |
| Web rail | `WebBillingService?` | Web builds only. Hosted Stripe checkout, plan swap, cancel, customer portal. |
| Store rail | `StoreBillingService?` | iOS and Android only, via RevenueCat. `null` on macOS, Windows, Linux and web. |

> [!IMPORTANT]
> A rail is CHECKED, never assumed. `if (Payments.web != null)` is what decides whether a purchase affordance renders at all. A throwing implementation would render a button that fails when tapped, which is the shape the rail split exists to prevent. Note that `dart.library.io` is true on desktop too, so the store rail asks the device question separately rather than answering from the import arm.

| Contract | Methods |
|:---------|:--------|
| `BillingService` | `currentEntitlement()`, `getPlans()`, `getUsage()`, `getInvoices({cursor})`, `getPaymentMethod()` |
| `WebBillingService` | `checkout({plan, cycle, successUrl, cancelUrl})`, `swap({plan, cycle})`, `cancel()`, `openPortal({returnUrl})` |
| `StoreBillingService` | `identify(appUserId)`, `purchase({plan})`, `restore()`, `openStoreManagement()` |

## Payments Facade API

`Payments` is a static stub over `PaymentsManager` in magic's facade style; it forwards and decides nothing.

| Member | Return type | Description |
|:-------|:------------|:------------|
| `Payments.manager` | `PaymentsManager` | The singleton every member forwards to. |
| `Payments.billing` | `BillingService` | The five reads. Always present. |
| `Payments.web` | `WebBillingService?` | The web rail, or `null` where this build cannot serve one. |
| `Payments.store` | `StoreBillingService?` | The store rail, or `null` where this build cannot serve one. |
| `Payments.currentEntitlement()` | `Future<BillingEntitlement>` | What the customer is entitled to right now. |
| `Payments.getPlans()` | `Future<List<Map<String, dynamic>>>` | The plan catalogue, cheapest tier first. |
| `Payments.getUsage()` | `Future<List<UsageStat>>` | Usage meters for the current period. |
| `Payments.getInvoices({cursor})` | `Future<BillingInvoicesPage>` | One page of invoice history. The page carries `nextCursor`; pass it back to advance. |
| `Payments.getPaymentMethod()` | `Future<PaymentMethod>` | The card on file. |
| `Payments.extend(role, factory)` | `void` | Replace a role with your own implementation or a fake. |
| `Payments.forgetDrivers()` | `void` | Drop the resolved roles so the next read re-resolves. Test teardown. |

Every failure surfaces as `BillingException`.

## Models and enums

`BillingEntitlement` is the one a consumer reads most: `plan`, `planStatus`, `subscribed`, `renews`, `cycle`, `provider`, `providerStatus`, `productId`, `manageVia`, `manageUrl`, `currentPeriodEnd`, `trialEndsAt`, `gracePeriodEndsAt`.

| Enum | Values | Notes |
|:-----|:-------|:------|
| `PlanStatus` | `none`, `trialing`, `active`, `pastDue`, `grace`, `canceled`, `expired`, `paused` | `pastDue` and `grace` are the two where a payment has FAILED and the customer still has access. Render a dunning notice on both. |
| `BillingProvider` | `none`, `stripe`, `appStore`, `playStore`, `manual` | Who sold the subscription. |
| `BillingCycle` | `monthly`, `annual` | Travels with the purchase and with the price sentence. |
| `ManageVia` | `none`, `portal`, `appStore`, `playStore` | Where the customer manages the subscription. Not the same axis as the rail this build can serve. |
| `InvoiceStatus` | `paid`, `pending`, `failed` | |

Other models: `BillingCheckoutSession`, `BillingInvoicesPage` (`invoices` + `nextCursor`), `Invoice`, `PaymentMethod`, `UsageStat`.

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
| `payments.revenuecat.public_sdk_key` | none, REQUIRED on iOS and Android | `RevenueCatStoreService.ensureConfigured()` |
| `payments.revenuecat.subject_label` | `'team'` | `RevenueCatStoreService`, in log lines only |

`'platform'` is the only value the package serves, and it means "resolve the driver from the build". The key exists so the choice is visible and `payments:doctor` can report it, not so it can be changed: which rail a build can serve is settled by the import graph, and a config key would be a second answer to that question. A different value is rejected by `payments:configure`, reported by `payments:doctor`, and logged as an error at boot before the platform driver is wired anyway.

The rails are deliberately NOT configurable. A driver of your own is registered in code with `Payments.extend()`, never named in config.

## CLI commands and MCP tools

| Command | Description |
|:--------|:------------|
| `dart run <app>:artisan payments:install` | Publish `lib/config/payments.dart`, register the config factory. |
| `dart run <app>:artisan payments:configure` | Update the config; rejects a `--driver` the package cannot serve. |
| `dart run <app>:artisan payments:doctor` | Diagnose config, keys, and which rails this build resolves. `--verbose` shows the path and the requirement behind each check. |

Only `payments_doctor` is exposed as an MCP tool. `payments:install` and `payments:configure` mutate the consumer's project, and the MCP surface stays read-only.

## Swapping a rail

```dart
// A fake in a test, or a rail the consumer implements itself.
Payments.extend(PaymentsManager.storeRole, () => MyStoreRail());

// Teardown: drop the resolved roles so the next read re-resolves.
Payments.forgetDrivers();
```

Roles are `PaymentsManager.billingRole` (`'billing'`), `webRole` (`'web'`) and `storeRole` (`'store'`). An unknown role is refused at registration rather than silently kept, and an override that cannot serve its role fails loudly naming both types.

## Gotchas

| Mistake | Fix |
|:--------|:----|
| Assuming `Payments.web` or `Payments.store` is non-null | Check it. `null` is the answer for a build that cannot serve that rail, and it is what decides whether the purchase button renders. |
| Treating the client as the entitlement authority | The backend is. These reads report what it says; a client-side check is advisory, exactly like magic's `Gate`. |
| Reading only `active` as "has access" | `trialing`, `pastDue` and `grace` are access-bearing too. Branch on `PlanStatus`, not on a boolean you derived from it. |
| Dropping `nextCursor` from `getInvoices()` | The producer addresses its first page by sending NO cursor. Reusing a stored token on a reset fetches page two and renders it as the whole history. |
| `payments.driver` set to a rail name | The only accepted value is `'platform'`. A rail is chosen by the build, not by config. |
| Registering a rail in config | There is no key for it. Use `Payments.extend(role, factory)`. |

The ready-made UI for all of this is `magic_starter`'s `teams.billing` view (gated on its own `features.billing` toggle); see `references/plugin-starter.md`.
