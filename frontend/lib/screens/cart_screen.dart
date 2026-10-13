/// Cart: quantities, removal, subtotal, delivery address, validated checkout.
///
/// Idempotency UX:
/// * The "Place order" button is disabled while a request is in flight.
/// * On timeout/network failure the pending idempotency key is kept and this
///   screen shows an "Order not confirmed" banner with **Retry safely** (same
///   key, same payload — the server de-duplicates) and **Discard**.
/// * A leftover pending checkout from a previous run is restored here too.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/cart_notifier.dart';
import '../state/checkout_notifier.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/error_view.dart';
import '../widgets/money.dart';
import '../widgets/responsive.dart';
import 'order_ack_screen.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  final _addressController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _restored = false;

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final checkout = ref.watch(checkoutProvider);

    // Surface a leftover pending checkout (e.g. app was killed mid-flight).
    if (!_restored) {
      _restored = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(checkoutProvider.notifier).restorePending();
      });
    }

    // Navigate to the acknowledgement on success.
    ref.listen<CheckoutState>(checkoutProvider, (prev, next) {
      if (next.phase == CheckoutPhase.success && next.accepted != null) {
        final accepted = next.accepted!;
        ref.read(checkoutProvider.notifier).reset();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => OrderAckScreen(accepted: accepted),
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Your cart')),
      body: ResponsiveCenter(
        child: cart.isEmpty
            ? const EmptyView(
                icon: Icons.shopping_cart_outlined,
                title: 'Your cart is empty',
                subtitle: 'Add some dishes from a restaurant to get started.',
                semanticsLabel: 'Empty cart',
              )
            : _buildCart(context, cart, checkout),
      ),
    );
  }

  Widget _buildCart(
      BuildContext context, CartState cart, CheckoutState checkout) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (cart.restaurantName != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(
                cart.restaurantName!,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ...cart.lines.values.map((line) => _CartLineCard(line: line)),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TotalRow(
                    label: 'Subtotal (${cart.itemCount} items)',
                    value: formatMoney(cart.subtotalMinor,
                        currency: cart.currency),
                    bold: true,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Delivery fee calculated by the restaurant at checkout.',
                    style: TextStyle(
                        color: AppColors.inkFaint, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Semantics(
            label: 'Delivery address',
            textField: true,
            child: TextFormField(
              controller: _addressController,
              maxLines: 2,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.fullStreetAddress],
              decoration: const InputDecoration(
                labelText: 'Delivery address',
                hintText: 'Flat, street, landmark…',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
              validator: (v) {
                final value = (v ?? '').trim();
                if (value.length < 8) {
                  return 'Enter a complete address (at least 8 characters).';
                }
                if (value.length > 500) return 'Address is too long.';
                return null;
              },
            ),
          ),
          const SizedBox(height: 8),
          if (checkout.phase == CheckoutPhase.error &&
              checkout.errorMessage != null)
            _CheckoutErrorBanner(message: checkout.errorMessage!),
          if (checkout.phase == CheckoutPhase.awaitingRetry)
            _RetryBanner(
              message: checkout.errorMessage,
              onRetry: () => ref.read(checkoutProvider.notifier).retry(),
              onDiscard: () =>
                  ref.read(checkoutProvider.notifier).discardPending(),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Continue Shopping'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  button: true,
                  label: checkout.isSubmitting
                      ? 'Placing order, please wait'
                      : 'Place order, total ${formatMoney(cart.subtotalMinor, currency: cart.currency)}',
                  child: FilledButton(
                    key: const Key('place_order_button'),
                    onPressed: checkout.isSubmitting
                        ? null
                        : () {
                            if (!(_formKey.currentState?.validate() ?? false)) {
                              return;
                            }
                            ref.read(checkoutProvider.notifier).placeOrder(
                                  deliveryAddress: _addressController.text,
                                );
                          },
                    child: checkout.isSubmitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Place order · ${formatMoney(cart.subtotalMinor, currency: cart.currency)}'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Your order is sent with a unique safety key: if the connection '
            'drops, retrying never creates a duplicate order.',
            style: TextStyle(color: AppColors.inkFaint, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _CartLineCard extends ConsumerWidget {
  final CartLine line;

  const _CartLineCard({required this.line});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line.name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    formatMoney(line.unitPriceMinor, currency: line.currency),
                    style: const TextStyle(color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
            Semantics(
              button: true,
              label: 'Decrease quantity of ${line.name}',
              child: IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                color: AppColors.orangeDeep,
                onPressed: () => ref
                    .read(cartProvider.notifier)
                    .setQuantity(line.menuItemId, line.quantity - 1),
              ),
            ),
            Semantics(
              label: '${line.quantity} ${line.name} in cart',
              child: Text('${line.quantity}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            Semantics(
              button: true,
              label: 'Increase quantity of ${line.name}',
              child: IconButton(
                icon: const Icon(Icons.add_circle_outline),
                color: AppColors.orangeDeep,
                onPressed: line.quantity >= CartNotifier.maxQtyPerLine
                    ? null
                    : () => ref
                        .read(cartProvider.notifier)
                        .setQuantity(line.menuItemId, line.quantity + 1),
              ),
            ),
            Semantics(
              button: true,
              label: 'Remove ${line.name} from cart',
              child: IconButton(
                icon: const Icon(Icons.delete_outline),
                color: AppColors.danger,
                onPressed: () =>
                    ref.read(cartProvider.notifier).remove(line.menuItemId),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _TotalRow(
      {required this.label, required this.value, this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
      fontSize: bold ? 18 : 15,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(label, style: style), Text(value, style: style)],
    );
  }
}

class _CheckoutErrorBanner extends StatelessWidget {
  final String message;

  const _CheckoutErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Checkout error: $message',
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.dangerBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: AppColors.danger),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message,
                  style: const TextStyle(
                      color: Color(0xFF7F1D1D), height: 1.35)),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Order not confirmed" — the outcome of the last attempt is unknown, so the
/// pending idempotency key is kept and the user can retry safely.
class _RetryBanner extends StatelessWidget {
  final String? message;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  const _RetryBanner({
    required this.message,
    required this.onRetry,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Order not confirmed. ${message ?? ''} '
          'You can retry safely — this will not create a duplicate order.',
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.warningBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE3B23C)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.help_outline, color: AppColors.warning),
                SizedBox(width: 8),
                Text(
                  'Order not confirmed',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF7A4D00)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${message ?? 'The connection dropped before we got an answer.'}'
              ' Your order may already exist — retrying is safe and will '
              'never create a duplicate.',
              style:
                  const TextStyle(color: Color(0xFF7A4D00), height: 1.4),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry safely'),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onDiscard,
                  child: const Text('Discard'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
