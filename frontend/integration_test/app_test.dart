/// End-to-end: sign in → restaurants → menu → checkout → acknowledgement →
/// live tracking → order history.
///
/// Prerequisites (the test does NOT start these):
/// * Backend + workers running and reachable at API_BASE_URL
///   (`--dart-define=API_BASE_URL=…`; default `http://localhost:8000`);
/// * seed data present (restaurants with menus), e.g. `scripts/seed.py`;
/// * a customer account `aarav@quickbite.test / customer123`.
///
/// Run on a device/emulator: `flutter test integration_test`
/// (VM platform), or `flutter drive` for a real device. The polling timer on
/// the details screen fires every ~2s, so this test uses explicit pumps
/// rather than `pumpAndSettle` once tracking starts.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quickbite_app/main.dart' as app;
import 'package:quickbite_app/screens/cart_screen.dart';
import 'package:quickbite_app/screens/order_ack_screen.dart';
import 'package:quickbite_app/screens/order_detail_screen.dart';
import 'package:quickbite_app/screens/order_history_screen.dart';
import 'package:quickbite_app/screens/restaurant_list_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'sign in → menu → checkout → tracking → history', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await tester.pumpWidget(app.buildApp(prefs: prefs));
    await tester.pumpAndSettle();

    // --- sign in --------------------------------------------------------
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'), 'aarav@quickbite.test');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), 'customer123');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.byType(RestaurantListScreen), findsOneWidget,
        reason: 'lands on the restaurant list after sign-in');

    // --- open the first restaurant's menu -------------------------------
    await tester.tap(find.byType(Card).first);
    await tester.pumpAndSettle();
    expect(find.text('Your cart').hitTestable(), findsNothing);

    // --- add the first available dish -----------------------------------
    final addButtons = find.widgetWithText(OutlinedButton, 'Add');
    expect(addButtons, findsWidgets,
        reason: 'menu has at least one available dish');
    await tester.tap(addButtons.first);
    await tester.pumpAndSettle();

    // --- open the cart ---------------------------------------------------
    await tester.tap(find.byIcon(Icons.shopping_cart_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(CartScreen), findsOneWidget);

    // --- address + checkout ----------------------------------------------
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Delivery address'),
        '221B Baker Street, Andheri West, Mumbai 400053');
    await tester.tap(find.textContaining('Place order'));
    // Explicit pumps: the ack screen arrives after the 202.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));

    expect(find.byType(OrderAckScreen), findsOneWidget,
        reason: 'acknowledgement after the 202');
    expect(find.text('Order accepted!'), findsOneWidget);

    // --- live tracking ---------------------------------------------------
    await tester.tap(find.text('Track order live'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(OrderDetailScreen), findsOneWidget);
    // Polling shows the current status chip (PENDING at minimum).
    expect(find.textContaining('Pending payment'), findsWidgets);

    // Let one poll cycle run; the screen must not crash on refresh.
    await tester.pump(const Duration(seconds: 3));

    // --- history ----------------------------------------------------------
    // Stack is list → menu → cart → details (ack replaced twice); pop to root.
    tester.state<NavigatorState>(find.byType(Navigator)).popUntil(
      (route) => route.isFirst,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My orders'));
    await tester.pumpAndSettle();

    expect(find.byType(OrderHistoryScreen), findsOneWidget);
    expect(find.byType(Card), findsWidgets,
        reason: 'history contains the just-placed order');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
