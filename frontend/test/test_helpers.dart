/// Shared helpers for widget tests: mock prefs + mock HTTP wiring.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quickbite_app/api/models.dart';
import 'package:quickbite_app/state/providers.dart';
import 'package:quickbite_app/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Builds a [ProviderScope] with a [MockClient]-backed API stack.
///
/// Returns the recorded requests for assertions (headers, bodies).
class TestHarness {
  final List<http.Request> requests = [];

  Future<Widget> wrap(
    Widget child, {
    required Future<http.Response> Function(http.Request) handler,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final client = MockClient((request) async {
      requests.add(request);
      return handler(request);
    });
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        httpClientProvider.overrideWithValue(client),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: child,
      ),
    );
  }
}

MenuItem testMenuItem({
  String id = 'mi_1',
  String restaurantId = 'r_1',
  String name = 'Paneer Tikka',
  int priceMinor = 25000,
  bool isAvailable = true,
}) =>
    MenuItem(
      id: id,
      restaurantId: restaurantId,
      name: name,
      priceMinor: priceMinor,
      currency: 'INR',
      isAvailable: isAvailable,
    );

String accepted202({String orderId = 'ord_test_1', int totalMinor = 25000}) =>
    jsonEncode({
      'order_id': orderId,
      'status': 'PENDING',
      'currency': 'INR',
      'total_amount_minor': totalMinor,
      'version': 1,
      'message': 'Order accepted and queued for processing.',
    });
