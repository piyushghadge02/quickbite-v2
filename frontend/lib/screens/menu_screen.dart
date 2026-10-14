/// Restaurant menu: names, prices, currency, availability, empty state.
///
/// * Unavailable items are greyed out and cannot be added.
/// * Adding an item from a *different* restaurant than the current cart asks
///   for confirmation before replacing the cart (one restaurant per order).
/// * On wide screens (≥1100px) a two-pane layout shows the cart summary next
///   to the menu; on phones the cart lives behind the FAB / app-bar action.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models.dart';
import '../state/cart_notifier.dart';
import '../state/catalog_notifier.dart'
    show MenuState;
import '../state/providers.dart';
import '../theme/app_theme.dart'
    show AppColors;
import '../widgets/error_view.dart';
import '../widgets/money.dart'
    show formatMoney;
import '../widgets/responsive.dart'
    show ResponsiveCenter, TwoPane, PagedListView, AppBreakpoints;
import 'cart_screen.dart';

class MenuScreen extends ConsumerWidget {
  final Restaurant restaurant;

  const MenuScreen({super.key, required this.restaurant});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menu = ref.watch(menuProvider(restaurant.id));
    final cartCount = ref.watch(cartProvider).itemCount;

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: CustomScrollView(
        slivers: [
          _MenuAppBar(restaurant: restaurant, cartCount: cartCount),
          SliverToBoxAdapter(
            child: ResponsiveCenter(
              maxWidth: AppBreakpoints.maxContentWidth,
              child: _buildBody(context, ref, menu),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _AddToCartBottomButton(cartCount: cartCount),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, MenuState menu) {
    if (menu.isLoading && menu.items.isEmpty) {
      return const SizedBox(
        height: 300,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (menu.errorMessage != null && menu.items.isEmpty) {
      return SizedBox(
        height: 300,
        child: ErrorView(
          message: menu.errorMessage!,
          isNetworkError: true,
          semanticsLabel: 'Menu failed to load',
          onRetry: () =>
              ref.read(menuProvider(restaurant.id).notifier).refresh(),
        ),
      );
    }
    if (menu.items.isEmpty) {
      return SizedBox(
        height: 300,
        child: const EmptyView(
          icon: Icons.menu_book_outlined,
          title: 'No dishes on the menu yet',
          subtitle: 'This kitchen hasn\'t published its menu. Try another restaurant.',
          semanticsLabel: 'Empty menu',
        ),
      );
    }
    return PagedListView(
      itemCount: menu.items.length,
      isLoadingMore: menu.isLoadingMore,
      hasMore: menu.hasMore,
      onLoadMore: () =>
          ref.read(menuProvider(restaurant.id).notifier).loadMore(),
      itemBuilder: (context, index) {
        final item = menu.items[index];
        return _MenuItemCard(item: item, restaurant: restaurant);
      },
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
    );
  }
}

class _MenuAppBar extends StatelessWidget {
  final Restaurant restaurant;
  final int cartCount;

  const _MenuAppBar({required this.restaurant, required this.cartCount});

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      floating: true,
      snap: true,
      expandedHeight: 220,
      elevation: 0,
      backgroundColor: AppColors.cream,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(Icons.arrow_back, color: AppColors.ink),
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
      actions: [
        Semantics(
          button: true,
          label: cartCount > 0 ? 'Open cart, $cartCount items' : 'Open cart',
          child: IconButton(
            icon: Badge(
              isLabelVisible: cartCount > 0,
              label: Text('$cartCount'),
              backgroundColor: AppColors.orange,
              child: const Icon(Icons.shopping_cart_outlined, color: AppColors.ink),
            ),
            onPressed: () => Navigator.of(context).pushNamed('/cart'),
            tooltip: 'Cart',
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Restaurant image
            if (restaurant.imageUrl != null && restaurant.imageUrl!.isNotEmpty)
              Image.network(
                restaurant.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    Container(color: AppColors.creamRaised),
              )
            else
              Container(color: AppColors.creamRaised),
            // Gradient overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.6),
                  ],
                  stops: const [0.5, 1.0],
                ),
              ),
            ),
            // Restaurant info at bottom
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (restaurant.cuisine != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.orange,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        restaurant.cuisine!,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    restaurant.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.black54,
                          offset: Offset(0, 1),
                          blurRadius: 3,
                        ),
                      ],
                    ),
                  ),
                  if (restaurant.description != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      restaurant.description!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white70,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (restaurant.rating != null) ...[
                        const Icon(Icons.star_rounded, size: 16, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(
                          '${restaurant.rating!.toStringAsFixed(1)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 16),
                      ],
                      if (restaurant.deliveryTimeMinutes != null) ...[
                        const Icon(Icons.access_time_rounded, size: 16, color: Colors.white70),
                        const SizedBox(width: 4),
                        Text(
                          '${restaurant.deliveryTimeMinutes} min delivery',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItemCard extends ConsumerWidget {
  final MenuItem item;
  final Restaurant restaurant;

  const _MenuItemCard({required this.item, required this.restaurant});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final ok = ref
        .read(cartProvider.notifier)
        .add(item, restaurantName: restaurant.name);
    if (!ok && context.mounted) {
      final cart = ref.read(cartProvider);
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Start a new order?'),
          content: Text(
            'Your cart has items from ${cart.restaurantName ?? 'another restaurant'}. '
            'QuickBite allows one restaurant per order — adding this dish will '
            'clear your current cart.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep cart'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Start new order'),
            ),
          ],
        ),
      );
      if (replace == true) {
        ref
            .read(cartProvider.notifier)
            .replaceWith(item, restaurantName: restaurant.name);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cart cleared — new order started.')),
          );
        }
      }
    } else if (ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.name} added to cart')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final qty = ref.watch(
      cartProvider.select((c) => c.lines[item.id]?.quantity ?? 0),
    );
    final available = item.isAvailable;

    return Semantics(
      label:
          '${item.name}, ${formatMoney(item.priceMinor, currency: item.currency)}'
          '${available ? '' : ', currently unavailable'}'
          '${qty > 0 ? ', $qty in cart' : ''}',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: available
                            ? AppColors.ink
                            : AppColors.inkFaint,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatMoney(item.priceMinor, currency: item.currency),
                      style: TextStyle(
                        color: available
                            ? AppColors.orangeDeep
                            : AppColors.inkFaint,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (!available)
                      const Text(
                        'Currently unavailable',
                        style: TextStyle(
                          color: AppColors.inkFaint,
                          fontStyle: FontStyle.italic,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
              if (!available)
                const Text(
                  '—',
                  style: TextStyle(color: AppColors.inkFaint, fontSize: 20),
                )
              else if (qty == 0)
                Semantics(
                  button: true,
                  label: 'Add ${item.name} to cart',
                  child: OutlinedButton(
                    onPressed: () => _add(context, ref),
                    child: const Text('Add'),
                  ),
                )
              else
                _QtyStepper(
                  quantity: qty,
                  itemName: item.name,
                  onChanged: (q) => ref
                      .read(cartProvider.notifier)
                      .setQuantity(item.id, q),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  final int quantity;
  final String itemName;
  final ValueChanged<int> onChanged;

  const _QtyStepper({
    required this.quantity,
    required this.itemName,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.orangeDeep,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            label: 'Remove one $itemName from cart',
            child: IconButton(
              icon: const Icon(Icons.remove, color: Colors.white),
              onPressed: () => onChanged(quantity - 1),
              constraints:
                  const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
          ),
          Semantics(
            label: '$quantity $itemName in cart',
            child: Text(
              '$quantity',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
          Semantics(
            button: true,
            label: 'Add one more $itemName to cart',
            child: IconButton(
              icon: const Icon(Icons.add, color: Colors.white),
              onPressed: quantity >= CartNotifier.maxQtyPerLine
                  ? null
                  : () => onChanged(quantity + 1),
              constraints:
                  const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cart summary panel shown in the wide two-pane layout.
class _CartSidePanel extends ConsumerWidget {
  const _CartSidePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    if (cart.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              cart.restaurantName ?? 'Your cart',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '${cart.itemCount} items · ${formatMoney(cart.subtotalMinor, currency: cart.currency)}',
              style: const TextStyle(color: AppColors.inkSoft),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).pushNamed('/cart'),
              child: const Text('Review cart & checkout'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dedicated bottom "Add to Cart" button showing total item count.
/// Disabled when cart is empty. Navigates to cart screen on tap.
class _AddToCartBottomButton extends ConsumerWidget {
  final int cartCount;

  const _AddToCartBottomButton({required this.cartCount});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (cartCount == 0) {
      return const SizedBox.shrink();
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Semantics(
          button: true,
          label: 'Open cart with $cartCount items',
          child: FilledButton(
            key: const Key('add_to_cart_bottom_button'),
            onPressed: () => Navigator.of(context).pushNamed('/cart'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              'Add to Cart ($cartCount ${cartCount == 1 ? 'item' : 'items'})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}
