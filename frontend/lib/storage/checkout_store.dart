/// Local persistence for the idempotent checkout protocol and the cart draft.
///
/// All records are JSON in `shared_preferences` — no secrets here (the bearer
/// token lives in [TokenStorage], not in this store).
///
/// Pending-checkout protocol:
/// 1. When the user taps "Place order", the app generates a UUID
///    idempotency key, persists `{key, requestJson, savedAt}` and only then
///    fires `POST /api/v1/orders` with the `Idempotency-Key` header.
/// 2. If the response arrives, the pending record is deleted:
///    * success → order accepted;
///    * 4xx validation/conflict → the key must not be reused blindly, so the
///      record is deleted and the error is surfaced.
/// 3. If the request fails with a timeout/network error, the outcome is
///    UNKNOWN — the record is kept and the UI offers "Retry safely", which
///    re-sends the *same* key and the *same* canonical request JSON. The
///    server either returns the original 202 (key seen before) or processes
///    the retried request — never a second order.
/// 4. On app start, a leftover record is surfaced so the user can retry or
///    discard it explicitly. The app never auto-retries.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class PendingCheckout {
  final String idempotencyKey;
  final Map<String, dynamic> requestJson;
  final DateTime savedAt;

  const PendingCheckout({
    required this.idempotencyKey,
    required this.requestJson,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'idempotency_key': idempotencyKey,
        'request_json': requestJson,
        'saved_at': savedAt.toIso8601String(),
      };

  factory PendingCheckout.fromJson(Map<String, dynamic> json) =>
      PendingCheckout(
        idempotencyKey: '${json['idempotency_key']}',
        requestJson:
            (json['request_json'] as Map?)?.cast<String, dynamic>() ?? const {},
        savedAt: DateTime.tryParse('${json['saved_at']}') ?? DateTime.now(),
      );
}

class CheckoutStore {
  static const _pendingKey = 'quickbite.pending_checkout.v1';
  static const _cartDraftKey = 'quickbite.cart_draft.v1';

  final SharedPreferences _prefs;

  CheckoutStore(this._prefs);

  // --- pending idempotent checkout --------------------------------------

  Future<void> savePending(PendingCheckout pending) => _prefs.setString(
        _pendingKey,
        jsonEncode(pending.toJson()),
      );

  PendingCheckout? readPending() {
    final raw = _prefs.getString(_pendingKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return PendingCheckout.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearPending() => _prefs.remove(_pendingKey);

  // --- cart draft --------------------------------------------------------

  Future<void> saveCartDraft(Map<String, dynamic> draft) =>
      _prefs.setString(_cartDraftKey, jsonEncode(draft));

  Map<String, dynamic>? readCartDraft() {
    final raw = _prefs.getString(_cartDraftKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearCartDraft() => _prefs.remove(_cartDraftKey);
}
