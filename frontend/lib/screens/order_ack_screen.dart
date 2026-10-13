/// Order acknowledgement: shown right after a 202 from POST /api/v1/orders.
///
/// Displays the server-issued order ID (selectable for support), the accepted
/// total, and the initial status — then hands off to live tracking.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/models.dart';
import '../theme/app_theme.dart';
import '../widgets/money.dart';
import '../widgets/responsive.dart';
import '../widgets/status_widgets.dart';
import 'order_detail_screen.dart';
import 'order_history_screen.dart';

class OrderAckScreen extends StatelessWidget {
  final CheckoutAccepted accepted;

  const OrderAckScreen({super.key, required this.accepted});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Order placed'),
        automaticallyImplyLeading: false,
      ),
      body: ResponsiveCenter(
        maxWidth: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Semantics(
                label: 'Order accepted',
                header: true,
                child: const Icon(
                  Icons.check_circle,
                  size: 88,
                  color: AppColors.success,
                  semanticLabel: 'Order accepted',
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Order accepted!',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                accepted.message.isNotEmpty
                    ? accepted.message
                    : 'The restaurant has your order and payment is being processed.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.inkSoft, height: 1.4),
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      _Row(
                        label: 'Order ID',
                        value: SelectableText(
                          accepted.orderId,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontFamily: 'monospace',
                              fontSize: 15),
                        ),
                        copyValue: accepted.orderId,
                      ),
                      const Divider(height: 24),
                      _Row(
                        label: 'Total',
                        value: Text(
                          formatMoney(accepted.totalAmountMinor,
                              currency: accepted.currency),
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 20),
                        ),
                      ),
                      const Divider(height: 24),
                      _Row(
                        label: 'Status',
                        value: OrderStatusChip(
                            statusWire: accepted.status),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Semantics(
                button: true,
                label: 'Track order live',
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) =>
                          OrderDetailScreen(orderId: accepted.orderId),
                    ),
                  ),
                  icon: const Icon(Icons.timeline),
                  label: const Text('Track order live'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                      builder: (_) => const OrderHistoryScreen()),
                  (route) => route.isFirst,
                ),
                child: const Text('View my orders'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final Widget value;
  final String? copyValue;

  const _Row({required this.label, required this.value, this.copyValue});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 96,
          child: Text(label,
              style: const TextStyle(color: AppColors.inkSoft)),
        ),
        Expanded(child: value),
        if (copyValue != null)
          Semantics(
            button: true,
            label: 'Copy order ID',
            child: IconButton(
              icon: const Icon(Icons.copy, size: 18),
              color: AppColors.inkFaint,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: copyValue!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Order ID copied.')),
                );
              },
            ),
          ),
      ],
    );
  }
}
