/// Riverpod provider wiring: UI / state / API layer separation.
///
/// Layers:
/// * **API** — [ApiClient] (centralized HTTP, typed models) + storage
///   adapters. Widgets never import `package:http` or read preferences
///   directly.
/// * **State** — `Notifier`s in `lib/state/*_notifier.dart`. All business
///   logic (sign-in state machine, cart math, idempotent checkout, order
///   polling) lives here and is unit/widget-testable via provider overrides.
/// * **UI** — `lib/screens/*` + `lib/widgets/*`. Widgets only `ref.watch` /
///   `ref.read` providers and render.
///
/// Why Riverpod: compile-safe providers (no runtime `ProviderNotFound`
/// surprises), `overrideWith` for hermetic widget tests, `family` providers
/// for per-restaurant/per-order state, and `ref.onDispose` for cancelling the
/// order-tracking poll timer.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../config/app_config.dart';
import '../storage/checkout_store.dart';
import '../storage/token_storage.dart';
import 'auth_notifier.dart';
import 'cart_notifier.dart';
import 'catalog_notifier.dart';
import 'checkout_notifier.dart';
import 'order_detail_notifier.dart';
import 'orders_list_notifier.dart';

// --- infrastructure --------------------------------------------------------

/// Overridden in `main()` with the real instance; tests inject a fake via
/// `SharedPreferences.setMockInitialValues`.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider not overridden'),
);

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final tokenStorageProvider = Provider<TokenStorage>((ref) => createTokenStorage());

final checkoutStoreProvider =
    Provider<CheckoutStore>((ref) => CheckoutStore(ref.watch(sharedPreferencesProvider)));

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(
    baseUrl: const AppConfig().baseUrl,
    httpClient: ref.watch(httpClientProvider),
    // A 401 anywhere means the token died: bounce back to the sign-in screen.
    onUnauthorized: () => ref.read(authProvider.notifier).handleUnauthorized(),
  );
  ref.onDispose(client.close);
  return client;
});

// --- state -----------------------------------------------------------------

final authProvider =
    NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

final restaurantListProvider =
    NotifierProvider<RestaurantListNotifier, CatalogListState>(
        RestaurantListNotifier.new);

/// Per-restaurant menu. `family` so the menu screen and the cart badge for the
/// same restaurant share one state object.
final menuProvider = NotifierProvider.family<MenuNotifier, MenuState, String>(
    MenuNotifier.new);

final cartProvider =
    NotifierProvider<CartNotifier, CartState>(CartNotifier.new);

final checkoutProvider =
    NotifierProvider<CheckoutNotifier, CheckoutState>(CheckoutNotifier.new);

/// Per-order tracking with ~2s polling while the details screen is visible.
final orderDetailProvider =
    NotifierProvider.family<OrderDetailNotifier, OrderDetailState, String>(
        OrderDetailNotifier.new);

/// Customer order history (paginated + status filter).
final ordersListProvider =
    NotifierProvider<OrdersListNotifier, OrdersListState>(
        OrdersListNotifier.new);

/// Admin read-only overview.
final adminOrdersProvider =
    NotifierProvider<AdminOrdersNotifier, AdminOrdersState>(
        AdminOrdersNotifier.new);

final adminSummaryProvider =
    NotifierProvider<AdminSummaryNotifier, AdminSummaryState>(
        AdminSummaryNotifier.new);
