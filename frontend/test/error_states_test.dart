/// Error-state tests:
/// * ApiClient maps the backend error envelope to typed exceptions
///   (401 → invalid credentials, 422 → validation details, transport
///   failures → NetworkException);
/// * the sign-in screen shows distinct banners for invalid credentials vs.
///   network errors, plus a retry action for network errors.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quickbite_app/api/api_client.dart';
import 'package:quickbite_app/api/api_exception.dart';
import 'package:quickbite_app/api/models.dart';
import 'package:quickbite_app/screens/sign_in_screen.dart';

import 'test_helpers.dart';

http.Response _envelope(int status, String code, String message,
        {Object? details}) =>
    http.Response(
      jsonEncode({
        'code': code,
        'message': message,
        'details': details,
        'request_id': 'req_test_1',
      }),
      status,
    );

void main() {
  group('ApiClient error mapping', () {
    test('401 maps to UnauthorizedException with the envelope message',
        () async {
      final api = ApiClient(
        baseUrl: 'http://localhost:8000',
        httpClient: MockClient((_) async => _envelope(
            401, 'INVALID_CREDENTIALS', 'Invalid email or password.')),
      );
      await expectLater(
        api.login(email: 'a@b.c', password: 'wrong'),
        throwsA(isA<UnauthorizedException>().having(
            (e) => e.message, 'message', contains('Invalid email'))),
      );
    });

    test('422 maps to ValidationException exposing field details', () async {
      final api = ApiClient(
        baseUrl: 'http://localhost:8000',
        httpClient: MockClient((_) async => _envelope(
              422,
              'VALIDATION_ERROR',
              'Request validation failed',
              details: [
                {
                  'loc': ['body', 'delivery_address'],
                  'msg': 'too short'
                }
              ],
            )),
      );
      await expectLater(
        api.login(email: 'a@b.c', password: 'x'),
        throwsA(isA<ValidationException>().having(
            (e) => e.message, 'message', contains('delivery_address'))),
      );
    });

    test('409 maps to ConflictException', () async {
      final api = ApiClient(
        baseUrl: 'http://localhost:8000',
        httpClient: MockClient((_) async => _envelope(
            409, 'IDEMPOTENCY_CONFLICT', 'Same key, different payload.')),
      );
      await expectLater(
        api.login(email: 'a@b.c', password: 'x'),
        throwsA(isA<ConflictException>()),
      );
    });

    test('SocketException maps to NetworkException', () async {
      final api = ApiClient(
        baseUrl: 'http://localhost:8000',
        httpClient: MockClient(
            (_) async => throw const SocketException('down')),
      );
      await expectLater(
        api.login(email: 'a@b.c', password: 'x'),
        throwsA(isA<NetworkException>()),
      );
    });

    test('checkout sends the Idempotency-Key header', () async {
      http.Request? captured;
      final api = ApiClient(
        baseUrl: 'http://localhost:8000',
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response(accepted202(), 202);
        }),
      );
      await api.createOrder(
        const CheckoutRequest(
          restaurantId: 'r_1',
          deliveryAddress: '221B Baker Street, Mumbai 400001',
          items: [CheckoutItemInput(menuItemId: 'mi_1', quantity: 1)],
        ),
        idempotencyKey: 'key-123',
      );
      expect(captured?.headers['Idempotency-Key'], 'key-123');
    });
  });

  group('SignInScreen states', () {
    testWidgets('invalid credentials show the credentials banner',
        (tester) async {
      final harness = TestHarness();
      final app = await harness.wrap(
        const SignInScreen(),
        handler: (request) async {
          if (request.url.path == '/api/v1/auth/login') {
            return _envelope(
                401, 'INVALID_CREDENTIALS', 'Invalid email or password.');
          }
          return http.Response('not found', 404);
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'a@b.c');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'wrong');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Incorrect email or password'), findsOneWidget);
      expect(find.text('Connection problem'), findsNothing);
    });

    testWidgets('network failure shows the connection banner with retry',
        (tester) async {
      final harness = TestHarness();
      var calls = 0;
      final app = await harness.wrap(
        const SignInScreen(),
        handler: (_) async {
          calls++;
          throw const SocketException('unreachable');
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'a@b.c');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'x');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Connection problem'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(calls, 2);
    });
  });
}
