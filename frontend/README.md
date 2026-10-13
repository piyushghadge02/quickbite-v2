# QuickBite v2 — Flutter client

Flutter frontend for the QuickBite v2 food-delivery order processing system
(assignment §5). Targets **web**, **Android**, and **iOS** from one codebase.

Backend contract: `POST /api/v1/auth/login`, `GET /api/v1/me`,
`GET /api/v1/restaurants[/{id}/menu]`, `POST /api/v1/orders` (202 +
`Idempotency-Key`), `GET /api/v1/orders[/{id}[/history|/notifications]]`,
`GET /api/v1/admin/orders`, `GET /api/v1/admin/summary`. Money is integer
paise; errors arrive as `{code,message,details,request_id}`.

## Quick start

```bash
# 1. Get packages
PUB_CACHE=~/workspace/quickbite-build/pubcache flutter pub get

# 2. Run (web / iOS simulator — API on localhost)
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000

# Android emulator (host loopback alias):
flutter run -d emulator-5554 \
  --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

**API base URL.** Injected at build time:

| Target | `--dart-define` value |
|---|---|
| Web, iOS simulator | `API_BASE_URL=http://localhost:8000` (default — no flag needed) |
| Android emulator | `API_BASE_URL=http://10.0.2.2:8000` |

The Android emulator cannot reach the host's `localhost`; `10.0.2.2` is the
documented host-loopback alias. Code: `lib/config/app_config.dart`.

**Demo accounts** (fictional, seeded by the backend): customer
`aarav@quickbite.test / customer123` (also `diya@quickbite.test`), admin
`admin@quickbite.test / admin123`.

## Architecture

```
lib/
  main.dart            # entry: ProviderScope wiring, AuthGate, routes
  config/              # API_BASE_URL from --dart-define
  api/                 # ApiClient (centralized HTTP), typed models,
                       # typed ApiException hierarchy — UI never touches http
  domain/              # OrderStatus: labels, terminal detection, failure
                       # explanations, progress rail index
  storage/             # TokenStorage (conditional import) + CheckoutStore
                       # (pending idempotency key + cart draft in prefs)
  state/               # Riverpod Notifiers: auth, catalog, cart, checkout,
                       # order polling, history, admin
  theme/               # cream/orange ThemeData
  widgets/             # responsive helpers, status chips, error/empty views
  screens/             # sign-in, restaurants, menu, cart, ack, details,
                       # history, admin
```

**Why Riverpod.** Compile-safe providers (no runtime lookup misses),
`overrideWith` for hermetic widget tests, `family` providers for
per-restaurant/per-order state, and `ref.onDispose` for cancelling the
order-tracking poll timer — all without threading `BuildContext` through
business logic.

## Key behaviours

**Idempotent checkout** (`lib/state/checkout_notifier.dart`,
`lib/storage/checkout_store.dart`): a UUID `Idempotency-Key` is generated per
attempt and persisted with the canonical request JSON in `shared_preferences`
*before* the network call; the button is disabled in flight; on timeout /
network error the outcome is unknown so the pending record is kept and the UI
offers **“Retry safely”**, which re-sends the *same* key and *same* bytes —
the server de-duplicates, a second order is impossible. On success the record
is cleared and the cart emptied; on 4xx the record is cleared and the error
surfaced. A leftover record from a killed app is surfaced on next launch
(retry or discard — never auto-retried). The cart draft is also persisted
locally.

**Live tracking** (`lib/state/order_detail_notifier.dart`): polls
`GET /api/v1/orders/{id}` every ~2s while the details screen is visible;
stops on terminal status (`DRIVER_ASSIGNED`, `PAYMENT_FAILED`, `FAILED`), on
dispose, and when the app is backgrounded; refreshes immediately on resume;
backs off 2s → 4s → 8s → 16s on consecutive failures without clearing the
last good data.

**Token storage** (`lib/storage/token_storage.dart`): web keeps the bearer
token **in memory only** (survives no reload; documented trade-off against
persistent-storage XSS). Mobile uses `flutter_secure_storage`
(Keychain/Keystore) behind a conditional import, so the web build never
imports or links the mobile-only plugin. A 401 anywhere signs the user out.

**Responsive**: `LayoutBuilder` breakpoints — phone (<720px) single column,
wide (≥720px) centered max-width content, two-pane (≥1100px) menu + cart
panel. No fixed text heights; the OS text scaler is respected (no clamps).

**Accessibility**: `Semantics` labels on key controls (status chips announce
“Order status: …”, steppers announce quantities), dark-on-tint chip colors
(≥4.5:1), the filled-button primary is the darker `#B34A0E` (≈5.9:1 white
text — white on the brand `#E8641B` is only ~3.1:1, so it is reserved for
accents), keyboard-navigable web (real buttons/fields, autofocus on email).

## Screens

Sign-in (loading / invalid-credentials / network-error states) →
restaurants → menu (prices, availability, empty state) → cart (quantities,
subtotal, validated address) → acknowledgement (server order ID, accepted
total) → order details (timeline, driver, failure explanation, notifications,
live polling) → order history (filters, pagination, refresh). Admins get a
**read-only** overview: pipeline summary (orders by status, outbox/retry/
quarantine counters) + filterable order list.

## Tests

```bash
PUB_CACHE=~/workspace/quickbite-build/pubcache flutter test        # widget + unit
PUB_CACHE=~/workspace/quickbite-build/pubcache \
  flutter test integration_test                                    # needs backend
```

`test/`: checkout flow (in-flight disable, idempotency-key header, retry
reuses the same key, 422 handling), status display (labels, failure
explanations, progress rail), error states (envelope → typed exceptions,
sign-in banners). `integration_test/app_test.dart`: sign-in → menu →
checkout → tracking → history against a seeded backend (see file header for
prerequisites).

## Builds

```bash
flutter build web --dart-define=API_BASE_URL=http://localhost:8000
# → ✓ builds (41 MB in build/web)
flutter build apk --dart-define=API_BASE_URL=http://10.0.2.2:8000
# → blocked in this Linux sandbox: no Android SDK ships with the image, and
#   the manually installed SDK's Gradle daemon cannot do localhost IPC here
#   ("Could not dispatch a message to the daemon", broken pipe). Build the
#   APK on a dev machine with Android Studio instead.
```

**iOS**: cannot be built in this Linux environment (no macOS/Xcode) — pending
on a Mac. The `ios/` folder is standard `flutter create` scaffolding and the
code has no platform-specific branches beyond the token-storage conditional
import, so no code changes are expected.

## Sandbox notes

* `/tmp` is a tiny tmpfs: set `TMPDIR=~/workspace/quickbite-build/piptmp`
  for tooling that needs temp space.
* Keep the pub cache under the workspace:
  `PUB_CACHE=~/workspace/quickbite-build/pubcache`.
