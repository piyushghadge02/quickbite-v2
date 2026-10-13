/// Checkout flow widget tests:
/// * the checkout button is disabled while a request is in flight;
/// * the `Idempotency-Key` header is sent;
/// * success navigates to the acknowledgement screen;
/// * a network failure surfaces "Retry safely", and the retry reuses the
///   SAME idempotency key (never a second order).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quickbite_app/screens/cart_screen.dart';
import 'package:quickbite_app/screens/order_ack_screen.dart';
import 'package:quickbite_app/state/providers.dart';

import 'test_helpers.dart';

/// The checkout button carries a stable key because its label text is
/// replaced by a spinner while the request is in flight.
Finder _placeOrderButton() => find.byKey(const Key('place_order_button'));

/// Pumps the cart screen with one item already in the cart.
Future<void> _pumpCartWithItem(WidgetTester tester, Widget scoped) async {
  await tester.pumpWidget(scoped);
  // CartScreen is the home; add the item through the real notifier.
  final container = ProviderScope.containerOf(
    tester.element(find.byType(CartScreen)),
  );
  container.read(cartProvider.notifier).add(
        testMenuItem(),
        restaurantName: 'Test Kitchen',
      );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('checkout button disables while request is in flight, '
      'sends Idempotency-Key, then shows acknowledgement', (tester) async {
    final harness = TestHarness();
    final inFlight = Completer<http.Response>();
    final app = await harness.wrap(
      const CartScreen(),
      handler: (request) async {
        if (request.url.path == '/api/v1/orders') return inFlight.future;
        return http.Response('not found', 404);
      },
    );
    await _pumpCartWithItem(tester, app);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Delivery address'),
        '221B Baker Street, Mumbai 400001');
    await tester.pump();

    // Tap "Place order" and keep the request hanging.
    await tester.tap(_placeOrderButton());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Button is disabled while submitting.
    final button = tester.widget<FilledButton>(
      _placeOrderButton(),
    );
    expect(button.onPressed, isNull,
        reason: 'checkout button must be disabled while in flight');

    // Complete the request → acknowledgement screen.
    inFlight.complete(http.Response(accepted202(), 202));
    await tester.pumpAndSettle();

    expect(find.byType(OrderAckScreen), findsOneWidget);
    expect(find.textContaining('ord_test_1'), findsWidgets);

    // The idempotency key was actually sent.
    final orderCalls = harness.requests
        .where((r) => r.url.path == '/api/v1/orders')
        .toList();
    expect(orderCalls, hasLength(1));
    final key = orderCalls.single.headers['Idempotency-Key'];
    expect(key, isNotNull);
    expect(key, isNotEmpty);
  });

  testWidgets('network failure offers "Retry safely" reusing the same key',
      (tester) async {
    final harness = TestHarness();
    var calls = 0;
    final app = await harness.wrap(
      const CartScreen(),
      handler: (request) async {
        if (request.url.path != '/api/v1/orders') {
          return http.Response('not found', 404);
        }
        calls++;
        if (calls == 1) {
          throw const SocketException('connection dropped');
        }
        return http.Response(accepted202(orderId: 'ord_retry_1'), 202);
      },
    );
    await _pumpCartWithItem(tester, app);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Delivery address'),
        '221B Baker Street, Mumbai 400001');
    await tester.pump();

    await tester.tap(_placeOrderButton());
    await tester.pumpAndSettle();

    // "Retry safely" banner appears — no second order was created.
    expect(find.text('Retry safely'), findsOneWidget);
    expect(find.text('Order not confirmed'), findsOneWidget);
    expect(calls, 1);

    final firstKey = harness.requests
        .firstWhere((r) => r.url.path == '/api/v1/orders')
        .headers['Idempotency-Key'];
    expect(firstKey, isNotNull);

    // Retry → same key, same payload → success.
    await tester.tap(find.text('Retry safely'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.byType(OrderAckScreen), findsOneWidget);
    final secondKey = harness.requests
        .where((r) => r.url.path == '/api/v1/orders')
        .last
        .headers['Idempotency-Key'];
    expect(secondKey, firstKey,
        reason: 'retry must reuse the same idempotency key');

    // Same request bytes as well.
    final bodies = harness.requests
        .where((r) => r.url.path == '/api/v1/orders')
        .map((r) => r.body)
        .toList();
    expect(bodies[0], bodies[1]);
  });

  testWidgets('validation error (422) clears pending and shows the message',
      (tester) async {
    final harness = TestHarness();
    final app = await harness.wrap(
      const CartScreen(),
      handler: (request) async {
        if (request.url.path == '/api/v1/orders') {
          return http.Response(
            jsonEncode({
              'code': 'VALIDATION_ERROR',
              'message': 'Request validation failed',
              'details': [
                {
                  'loc': ['body', 'delivery_address'],
                  'msg': 'too short',
                }
              ],
              'request_id': 'req_test',
            }),
            422,
          );
        }
        return http.Response('not found', 404);
      },
    );
    await _pumpCartWithItem(tester, app);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Delivery address'),
        '221B Baker Street, Mumbai 400001');
    await tester.pump();

    await tester.tap(_placeOrderButton());
    await tester.pumpAndSettle();

    // Deterministic server verdict: error shown, no "Retry safely".
    expect(find.textContaining('Request validation failed'), findsOneWidget);
    expect(find.text('Retry safely'), findsNothing);
  });
}
