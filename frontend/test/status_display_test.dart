/// Status display widget tests:
/// * every order status renders its human label in the chip;
/// * terminal failures show a readable explanation (not the raw code);
/// * the progress rail is hidden for failure states.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickbite_app/widgets/status_widgets.dart';

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

void main() {
  testWidgets('status chip shows a human label for every status',
      (tester) async {
    final semantics = tester.ensureSemantics();
    const expectations = {
      'PENDING': 'Pending payment',
      'PAID': 'Payment received',
      'CONFIRMED': 'Confirmed by restaurant',
      'DRIVER_ASSIGNED': 'On its way',
      'PAYMENT_FAILED': 'Payment failed',
      'FAILED': 'Order failed',
    };
    for (final entry in expectations.entries) {
      await _pump(
          tester, OrderStatusChip(statusWire: entry.key));
      expect(find.text(entry.value), findsOneWidget,
          reason: 'chip for ${entry.key}');
      // Screen readers hear the full label.
      expect(
        find.bySemanticsLabel('Order status: ${entry.value}'),
        findsOneWidget,
      );
    }
    semantics.dispose();
  });

  testWidgets('failure card explains a declined payment in plain language',
      (tester) async {
    await _pump(
      tester,
      const FailureExplanationCard(
        statusWire: 'PAYMENT_FAILED',
        failureCode: 'SIMULATED_DECLINE',
      ),
    );
    expect(find.text('What happened'), findsOneWidget);
    expect(find.textContaining('declined by the payment provider'),
        findsOneWidget);
    expect(find.textContaining('No money was charged'), findsOneWidget);
  });

  testWidgets('failure card explains missing drivers', (tester) async {
    await _pump(
      tester,
      const FailureExplanationCard(
        statusWire: 'FAILED',
        failureCode: 'NO_DRIVERS_AVAILABLE',
      ),
    );
    expect(find.textContaining('delivery partner'), findsOneWidget);
    // The raw code stays visible for support, but is not the headline.
    expect(find.textContaining('NO_DRIVERS_AVAILABLE'), findsOneWidget);
  });

  testWidgets('failure card renders nothing for non-failure states',
      (tester) async {
    await _pump(
      tester,
      const FailureExplanationCard(
        statusWire: 'CONFIRMED',
        failureCode: null,
      ),
    );
    expect(find.text('What happened'), findsNothing);
  });

  testWidgets('progress rail hidden for failure states', (tester) async {
    await _pump(tester, const OrderProgressRail(statusWire: 'FAILED'));
    expect(find.byType(OrderProgressRail), findsOneWidget);
    // No dots rendered for failures.
    expect(find.bySemanticsLabel(RegExp(r'Order progress.*')),
        findsNothing);
  });

  testWidgets('progress rail announces current step for active orders',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, const OrderProgressRail(statusWire: 'CONFIRMED'));
    expect(
      find.bySemanticsLabel('Order progress: Confirmed, step 3 of 4'),
      findsOneWidget,
    );
    semantics.dispose();
  });
}
