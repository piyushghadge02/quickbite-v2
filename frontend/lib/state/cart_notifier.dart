/// Shopping cart: one restaurant per order, quantities, local draft.
///
/// The draft is persisted to `shared_preferences` after every mutation so a
/// killed app restores the in-progress cart. Item snapshots (name/price) are
/// stored in the draft so the cart renders even before the menu reloads.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models.dart';
import '../storage/checkout_store.dart';
import 'providers.dart';

class CartLine {
  final String menuItemId;
  final String name;
  final int unitPriceMinor;
  final String currency;
  final int quantity;

  const CartLine({
    required this.menuItemId,
    required this.name,
    required this.unitPriceMinor,
    required this.currency,
    required this.quantity,
  });

  int get lineTotalMinor => unitPriceMinor * quantity;

  CartLine copyWith({int? quantity}) => CartLine(
        menuItemId: menuItemId,
        name: name,
        unitPriceMinor: unitPriceMinor,
        currency: currency,
        quantity: quantity ?? this.quantity,
      );

  Map<String, dynamic> toJson() => {
        'menu_item_id': menuItemId,
        'name': name,
        'unit_price_minor': unitPriceMinor,
        'currency': currency,
        'quantity': quantity,
      };

  factory CartLine.fromJson(Map<String, dynamic> json) => CartLine(
        menuItemId: '${json['menu_item_id']}',
        name: '${json['name'] ?? 'Item'}',
        unitPriceMinor: (json['unit_price_minor'] as num?)?.toInt() ?? 0,
        currency: '${json['currency'] ?? 'INR'}',
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      );
}

class CartState {
  final String? restaurantId;
  final String? restaurantName;
  final Map<String, CartLine> lines;

  const CartState({this.restaurantId, this.restaurantName, this.lines = const {}});

  bool get isEmpty => lines.isEmpty;
  int get itemCount => lines.values.fold(0, (n, l) => n + l.quantity);
  int get subtotalMinor => lines.values.fold(0, (n, l) => n + l.lineTotalMinor);
  String get currency =>
      lines.isEmpty ? 'INR' : lines.values.first.currency;

  CartState copyWith({
    String? restaurantId,
    String? restaurantName,
    Map<String, CartLine>? lines,
  }) =>
      CartState(
        restaurantId: restaurantId ?? this.restaurantId,
        restaurantName: restaurantName ?? this.restaurantName,
        lines: lines ?? this.lines,
      );

  /// Builds the checkout request from the current cart lines.
  CheckoutRequest toCheckoutRequest({required String deliveryAddress}) =>
      CheckoutRequest(
        restaurantId: restaurantId ?? '',
        deliveryAddress: deliveryAddress,
        items: lines.values
            .map((l) =>
                CheckoutItemInput(menuItemId: l.menuItemId, quantity: l.quantity))
            .toList(),
      );
}

class CartNotifier extends Notifier<CartState> {
  static const maxQtyPerLine = 20;

  @override
  CartState build() {
    Future.microtask(_restoreDraft);
    return const CartState();
  }

  CheckoutStore get _store => ref.read(checkoutStoreProvider);

  void _restoreDraft() {
    final draft = _store.readCartDraft();
    if (draft == null) return;
    try {
      final rawLines = (draft['lines'] as List?) ?? const [];
      final lines = <String, CartLine>{};
      for (final raw in rawLines.whereType<Map<String, dynamic>>()) {
        final line = CartLine.fromJson(raw);
        lines[line.menuItemId] = line;
      }
      if (lines.isNotEmpty) {
        state = CartState(
          restaurantId: draft['restaurant_id'] as String?,
          restaurantName: draft['restaurant_name'] as String?,
          lines: lines,
        );
      }
    } catch (_) {
      // Corrupt draft — start empty.
    }
  }

  Future<void> _persist() => _store.saveCartDraft({
        'restaurant_id': state.restaurantId,
        'restaurant_name': state.restaurantName,
        'lines': state.lines.values.map((l) => l.toJson()).toList(),
      });

  /// Adds one unit of [item]. Returns `false` when the item belongs to a
  /// different restaurant than the current cart (caller shows a confirm
  /// dialog, then calls [replaceWith]).
  bool add(MenuItem item, {required String restaurantName}) {
    if (state.restaurantId != null && state.restaurantId != item.restaurantId) {
      return false;
    }
    final lines = Map<String, CartLine>.from(state.lines);
    final existing = lines[item.id];
    if (existing != null) {
      if (existing.quantity >= maxQtyPerLine) return true;
      lines[item.id] = existing.copyWith(quantity: existing.quantity + 1);
    } else {
      lines[item.id] = CartLine(
        menuItemId: item.id,
        name: item.name,
        unitPriceMinor: item.priceMinor,
        currency: item.currency,
        quantity: 1,
      );
    }
    state = CartState(
      restaurantId: item.restaurantId,
      restaurantName: restaurantName,
      lines: lines,
    );
    _persist();
    return true;
  }

  /// Clears the cart and starts it with [item] (after user confirmation).
  void replaceWith(MenuItem item, {required String restaurantName}) {
    state = CartState(
      restaurantId: item.restaurantId,
      restaurantName: restaurantName,
      lines: {
        item.id: CartLine(
          menuItemId: item.id,
          name: item.name,
          unitPriceMinor: item.priceMinor,
          currency: item.currency,
          quantity: 1,
        ),
      },
    );
    _persist();
  }

  void setQuantity(String menuItemId, int quantity) {
    final lines = Map<String, CartLine>.from(state.lines);
    if (quantity <= 0) {
      lines.remove(menuItemId);
    } else {
      final existing = lines[menuItemId];
      if (existing == null) return;
      lines[menuItemId] =
          existing.copyWith(quantity: quantity.clamp(1, maxQtyPerLine));
    }
    state = state.copyWith(lines: lines);
    _persist();
  }

  void remove(String menuItemId) => setQuantity(menuItemId, 0);

  Future<void> clear() async {
    state = const CartState();
    await _store.clearCartDraft();
  }
}
