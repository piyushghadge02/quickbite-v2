/// Idempotent checkout.
///
/// Protocol (see `lib/storage/checkout_store.dart` for the full rationale):
/// * A UUID idempotency key is generated per checkout *attempt* and persisted
///   together with the canonical request JSON in `shared_preferences` BEFORE
///   the network call.
/// * The checkout button is disabled while a request is in flight
///   ([CheckoutPhase.submitting]) — no double taps, no double orders.
/// * On timeout/network failure the outcome is unknown: the pending record is
///   kept and the UI offers **"Retry safely"**, which re-sends the SAME key
///   with the SAME bytes. The server de-duplicates; a second order is
///   impossible.
/// * On success the pending record is cleared and the cart is emptied.
/// * On 4xx (validation/conflict/…) the pending record is cleared — retrying
///   the same payload would be pointless — and the error is surfaced.
/// * A leftover record from a killed app is surfaced on start so the user
///   can retry or discard it explicitly. The app never auto-retries.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../api/models.dart';
import '../storage/checkout_store.dart';
import 'providers.dart';

enum CheckoutPhase {
  idle,
  submitting,
  awaitingRetry,
  success,
  error,
}

class CheckoutState {
  final CheckoutPhase phase;
  final CheckoutAccepted? accepted;
  final PendingCheckout? pending;
  final String? errorMessage;

  const CheckoutState({
    required this.phase,
    this.accepted,
    this.pending,
    this.errorMessage,
  });

  const CheckoutState.idle() : this(phase: CheckoutPhase.idle);

  bool get isSubmitting => phase == CheckoutPhase.submitting;
  bool get canRetry =>
      phase == CheckoutPhase.awaitingRetry && pending != null;
}

class CheckoutNotifier extends Notifier<CheckoutState> {
  static const _uuid = Uuid();

  @override
  CheckoutState build() => const CheckoutState.idle();

  ApiClient get _api => ref.read(apiClientProvider);
  CheckoutStore get _store => ref.read(checkoutStoreProvider);

  /// Surfaces a leftover pending checkout from a previous run (if any).
  void restorePending() {
    if (state.phase != CheckoutPhase.idle) return;
    final pending = _store.readPending();
    if (pending != null) {
      state = CheckoutState(
          phase: CheckoutPhase.awaitingRetry, pending: pending);
    }
  }

  Future<void> placeOrder({required String deliveryAddress}) async {
    if (state.isSubmitting) return;
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) {
      state = const CheckoutState(
        phase: CheckoutPhase.error,
        errorMessage: 'Your cart is empty.',
      );
      return;
    }

    final request =
        cart.toCheckoutRequest(deliveryAddress: deliveryAddress.trim());
    final canonicalJson = request.toJson();

    // Reuse the persisted key when the payload is identical to the pending
    // one (e.g. user tapped checkout, app died, user taps again).
    final existing = _store.readPending();
    final String key;
    if (existing != null &&
        jsonEncode(existing.requestJson) == jsonEncode(canonicalJson)) {
      key = existing.idempotencyKey;
    } else {
      key = _uuid.v4();
      await _store.savePending(PendingCheckout(
        idempotencyKey: key,
        requestJson: canonicalJson,
        savedAt: DateTime.now(),
      ));
    }

    await _submit(
      request: request,
      idempotencyKey: key,
      clearCartOnSuccess: true,
    );
  }

  /// "Retry safely": re-sends the persisted key + request bytes verbatim.
  Future<void> retry() async {
    final pending = _store.readPending() ?? state.pending;
    if (pending == null || state.isSubmitting) return;
    final request = _requestFromJson(pending.requestJson);
    if (request == null) {
      await _store.clearPending();
      state = const CheckoutState(
        phase: CheckoutPhase.error,
        errorMessage: 'The saved checkout was corrupted and was discarded.',
      );
      return;
    }
    await _submit(
      request: request,
      idempotencyKey: pending.idempotencyKey,
      clearCartOnSuccess: false, // cart may already have been cleared
    );
  }

  Future<void> discardPending() async {
    await _store.clearPending();
    state = const CheckoutState.idle();
  }

  void reset() => state = const CheckoutState.idle();

  CheckoutRequest? _requestFromJson(Map<String, dynamic> json) {
    try {
      final items = (json['items'] as List?) ?? const [];
      return CheckoutRequest(
        restaurantId: '${json['restaurant_id']}',
        deliveryAddress: '${json['delivery_address']}',
        items: items
            .whereType<Map<String, dynamic>>()
            .map((i) => CheckoutItemInput(
                  menuItemId: '${i['menu_item_id']}',
                  quantity: (i['quantity'] as num?)?.toInt() ?? 1,
                ))
            .toList(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _submit({
    required CheckoutRequest request,
    required String idempotencyKey,
    required bool clearCartOnSuccess,
  }) async {
    state = CheckoutState(
      phase: CheckoutPhase.submitting,
      pending: _store.readPending(),
    );
    try {
      final accepted =
          await _api.createOrder(request, idempotencyKey: idempotencyKey);
      await _store.clearPending();
      if (clearCartOnSuccess) {
        await ref.read(cartProvider.notifier).clear();
      }
      state = CheckoutState(
        phase: CheckoutPhase.success,
        accepted: accepted,
      );
    } on NetworkException catch (e) {
      // Outcome unknown — keep the pending record, offer "Retry safely".
      state = CheckoutState(
        phase: CheckoutPhase.awaitingRetry,
        pending: _store.readPending(),
        errorMessage: e.message,
      );
    } on ApiException catch (e) {
      // Deterministic server verdict — the key must not be blindly reused.
      await _store.clearPending();
      state = CheckoutState(
        phase: CheckoutPhase.error,
        errorMessage: e.message,
      );
    }
  }
}
