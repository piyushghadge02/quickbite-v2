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

http.Response _loginSuccess() =>
    http.Response(
      jsonEncode({
        'access_token': 'demo_token_123',
        'token_type': 'bearer',
        'expires_at': '2026-10-14T12:00:00.000Z',
        'role': 'customer',
        'user': {
          'id': 'user_aarav',
          'email': 'aarav@quickbite.test',
          'name': 'Aarav Sharma',
          'role': 'customer',
        },
      }),
      200,
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

  group('SignInScreen demo login', () {
    testWidgets('successful demo login triggers auth flow',
        (tester) async {
      final harness = TestHarness();
      final app = await harness.wrap(
        const SignInScreen(),
        handler: (request) async {
          if (request.url.path == '/api/v1/auth/login') {
            return _loginSuccess();
          }
          return http.Response('not found', 404);
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Find and tap the Demo Login button
      await tester.tap(find.widgetWithText(OutlinedButton, 'Demo Login'));
      await tester.pump(const Duration(milliseconds: 100));

      // Should show loading state
      expect(find.text('Demo login...'), findsOneWidget);

      // Wait for login to complete
      await tester.pump(const Duration(seconds: 2));

      // Error banner should not be shown
      expect(find.text('Incorrect email or password'), findsNothing);
      expect(find.text('Connection problem'), findsNothing);
    });

    testWidgets('demo login shows error on invalid credentials',
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

      await tester.tap(find.widgetWithText(OutlinedButton, 'Demo Login'));
      await tester.pumpAndSettle();

      expect(find.text('Incorrect email or password'), findsOneWidget);
      expect(find.text('Demo Login'), findsOneWidget); // Button re-enabled
    });

    testWidgets('demo login shows network error on connection failure',
        (tester) async {
      final harness = TestHarness();
      final app = await harness.wrap(
        const SignInScreen(),
        handler: (_) async => throw const SocketException('unreachable'),
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Demo Login'));
      await tester.pumpAndSettle();

      expect(find.text('Connection problem'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget); // Retry for network error
    });

    testWidgets('demo login button disabled during loading',
        (tester) async {
      final harness = TestHarness();
      var loginCalled = 0;
      final app = await harness.wrap(
        const SignInScreen(),
        handler: (request) async {
          if (request.url.path == '/api/v1/auth/login') {
            loginCalled++;
            // Slow response to test loading state
            await Future.delayed(const Duration(milliseconds: 100));
            return _loginSuccess();
          }
          return http.Response('not found', 404);
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Tap demo login
      await tester.tap(find.widgetWithText(OutlinedButton, 'Demo Login'));
      await tester.pump(const Duration(milliseconds: 100)); // Check loading state

      // Button should show loading state
      expect(find.text('Demo login...'), findsOneWidget);

      // Try to tap again - should be disabled (button is disabled when isLoading)
      await tester.tap(find.widgetWithText(OutlinedButton, 'Demo login...'));
      await tester.pump(const Duration(milliseconds: 50));

      // Wait for completion
      await tester.pump(const Duration(seconds: 2));

      // Login should only be called once (button disabled prevents double-click)
      expect(loginCalled, 1);
    });
  });
}
