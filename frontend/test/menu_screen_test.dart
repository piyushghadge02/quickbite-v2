/// Menu screen widget tests:
/// * Individual Add buttons add multiple food items
/// * Dedicated "Add to Cart" button displays correct total quantity
/// * Button is hidden when cart is empty
/// * Clicking it navigates to the existing cart screen
/// * Selected items and quantities are preserved
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quickbite_app/theme/app_theme.dart';
import 'package:quickbite_app/api/models.dart';
import 'package:quickbite_app/screens/menu_screen.dart';
import 'package:quickbite_app/screens/cart_screen.dart';
import 'package:quickbite_app/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'test_helpers.dart';

void main() {
  group('MenuScreen', () {
    late TestHarness harness;

    setUp(() {
      harness = TestHarness();
    });

    String menuJson() => '''
      {
        "items": [
          {"id": "mi_1", "restaurant_id": "r_1", "name": "Paneer Tikka", "price_minor": 25000, "currency": "INR", "is_available": true},
          {"id": "mi_2", "restaurant_id": "r_1", "name": "Butter Naan", "price_minor": 5000, "currency": "INR", "is_available": true},
          {"id": "mi_3", "restaurant_id": "r_1", "name": "Dal Makhani", "price_minor": 18000, "currency": "INR", "is_available": true}
        ],
        "has_more": false
      }
    ''';

    Future<Widget> buildMenuScreen({required TestHarness harness}) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/restaurants/r_1/menu') {
          return http.Response(menuJson(), 200);
        }
        return http.Response('not found', 404);
      });
      return ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          httpClientProvider.overrideWithValue(client),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          routes: {
            '/cart': (_) => const CartScreen(),
          },
          home: const MenuScreen(
            restaurant: Restaurant(
              id: 'r_1',
              name: 'Test Kitchen',
              address: 'Test Address',
              isActive: true,
            ),
          ),
        ),
      );
    }

    testWidgets('individual Add buttons add multiple food items',
        (tester) async {
      final app = await buildMenuScreen(harness: harness);
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Initially no add-to-cart button (cart empty)
      expect(find.text('Add to Cart'), findsNothing);

      // Tap "Add" on first item (Paneer Tikka)
      await tester.tap(find.widgetWithText(OutlinedButton, 'Add').first);
      await tester.pumpAndSettle();

      // Snackbar should appear
      expect(find.text('Paneer Tikka added to cart'), findsOneWidget);

      // Add to Cart button should now appear with count 1
      expect(find.text('Add to Cart (1 item)'), findsOneWidget);

      // Tap "Add" on second item (Butter Naan) - now at index 0 since first item has stepper
      await tester.tap(find.widgetWithText(OutlinedButton, 'Add').first);
      await tester.pumpAndSettle();

      // Add to Cart button should now show count 2
      expect(find.text('Add to Cart (2 items)'), findsOneWidget);

      // Tap "Add" on third item (Dal Makhani) - now at index 0
      await tester.tap(find.widgetWithText(OutlinedButton, 'Add').first);
      await tester.pumpAndSettle();

      // Add to Cart button should now show count 3
      expect(find.text('Add to Cart (3 items)'), findsOneWidget);
    });

    testWidgets('dedicated Add to Cart button shows correct total quantity '
        'with quantity steppers', (tester) async {
      final app = await buildMenuScreen(harness: harness);
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Add first item
      await tester.tap(find.widgetWithText(OutlinedButton, 'Add').first);
      await tester.pumpAndSettle();

      // Increase quantity of first item using stepper (+ button)
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();

      // Add to Cart button should show count 2 (quantity of first item is 2)
      expect(find.text('Add to Cart (2 items)'), findsOneWidget);

      // Add second item
      await tester.tap(find.widgetWithText(OutlinedButton, 'Add').at(1));
      await tester.pumpAndSettle();

      // Add to Cart button should show count 3 (2 + 1)
      expect(find.text('Add to Cart (3 items)'), findsOneWidget);
    });

    testWidgets('Add to Cart button is hidden when cart is empty',
        (tester) async {
      final app = await buildMenuScreen(harness: harness);
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Button should not be visible when cart is empty
      expect(find.textContaining('Add to Cart'), findsNothing);
    });

    testWidgets('clicking Add to Cart button navigates to cart screen',
        (tester) async {
      final app = await buildMenuScreen(harness: harness);
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Add an item
      await tester.tap(find.widgetWithText(OutlinedButton, 'Add').first);
      await tester.pumpAndSettle();

      // Find the Add to Cart button and directly invoke its onPressed
      final addToCartButton = tester.widget<FilledButton>(
        find.byKey(const Key('add_to_cart_bottom_button')),
      );
      addToCartButton.onPressed?.call();
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Should navigate to CartScreen
      expect(find.byType(CartScreen), findsOneWidget);
      expect(find.text('Your cart'), findsOneWidget);
    });

    testWidgets('selected items and quantities preserved when navigating to cart',
        (tester) async {
      final app = await buildMenuScreen(harness: harness);
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Add first item
      await tester.tap(find.widgetWithText(OutlinedButton, 'Add').first);
      await tester.pumpAndSettle();

      // Increase quantity to 3
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();

      // Add second item
      await tester.tap(find.widgetWithText(OutlinedButton, 'Add').first);
      await tester.pumpAndSettle();

      // Navigate to cart by directly invoking onPressed
      final addToCartButton = tester.widget<FilledButton>(
        find.byKey(const Key('add_to_cart_bottom_button')),
      );
      addToCartButton.onPressed?.call();
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Verify items in cart with correct quantities
      expect(find.text('Paneer Tikka'), findsOneWidget);
      expect(find.text('3'), findsWidgets); // quantity of first item
      expect(find.text('Butter Naan'), findsOneWidget);
      expect(find.text('1'), findsWidgets); // quantity of second item
    });

    testWidgets('cart badge in app bar updates with item count', (tester) async {
      final app = await buildMenuScreen(harness: harness);
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Badge should not be visible initially
      expect(find.byType(Badge), findsOneWidget);
      final badge = tester.widget<Badge>(find.byType(Badge));
      expect(badge.isLabelVisible, isFalse);

      // Add an item
      await tester.tap(find.widgetWithText(OutlinedButton, 'Add').first);
      await tester.pumpAndSettle();

      // Badge should now be visible with count 1
      final badgeAfter = tester.widget<Badge>(find.byType(Badge));
      expect(badgeAfter.isLabelVisible, isTrue);
      final badgeLabel = badgeAfter.label as Text;
      expect(badgeLabel.data, '1');
    });
  });
}