/// Restaurant list (customer home). Tapping a restaurant opens its menu.
/// Features: search, cuisine filters, responsive grid of restaurant cards with images.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models.dart';
import '../state/catalog_notifier.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart'
    show AppColors, AppBreakpoints;
import '../widgets/error_view.dart';
import '../widgets/money.dart';
import '../widgets/responsive.dart';
import 'menu_screen.dart';
import 'order_history_screen.dart';

class RestaurantListScreen extends ConsumerWidget {
  const RestaurantListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(restaurantListProvider);
    final cartCount = ref.watch(cartProvider).itemCount;

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: CustomScrollView(
        slivers: [
          _HomeAppBar(cartCount: cartCount),
          SliverToBoxAdapter(
            child: ResponsiveCenter(
              maxWidth: AppBreakpoints.maxContentWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  const _SearchField(),
                  const SizedBox(height: 16),
                  const _CuisineFilterChips(),
                  const SizedBox(height: 16),
                  _buildRestaurantGrid(context, ref, state),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
      drawer: const _HomeDrawer(),
    );
  }

  Widget _buildRestaurantGrid(
      BuildContext context, WidgetRef ref, CatalogListState state) {
    if (state.isLoading && state.items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (state.errorMessage != null && state.items.isEmpty) {
      return ErrorView(
        message: state.errorMessage!,
        isNetworkError: true,
        semanticsLabel: 'Restaurants failed to load',
        onRetry: () => ref.read(restaurantListProvider.notifier).refresh(),
      );
    }
    if (state.items.isEmpty) {
      return const EmptyView(
        icon: Icons.storefront_outlined,
        title: 'No restaurants yet',
        subtitle: 'Check back soon — new kitchens are joining.',
        semanticsLabel: 'No restaurants',
      );
    }

    final filteredRestaurants = ref.watch(_filteredRestaurantsProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount;
        if (constraints.maxWidth >= 1200) {
          crossAxisCount = 4;
        } else if (constraints.maxWidth >= 800) {
          crossAxisCount = 3;
        } else if (constraints.maxWidth >= 500) {
          crossAxisCount = 2;
        } else {
          crossAxisCount = 1;
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 0.85,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: filteredRestaurants.length,
          itemBuilder: (context, index) {
            final restaurant = filteredRestaurants[index];
            return _RestaurantCard(restaurant: restaurant);
          },
        );
      },
    );
  }
}

/// Provider for filtered restaurants based on search query and cuisine filter.
final _searchQueryProvider = StateProvider<String>((ref) => '');
final _selectedCuisineProvider = StateProvider<String?>((ref) => null);

final _filteredRestaurantsProvider = Provider<List<Restaurant>>((ref) {
  final state = ref.watch(restaurantListProvider);
  final query = ref.watch(_searchQueryProvider).toLowerCase().trim();
  final cuisine = ref.watch(_selectedCuisineProvider);

  return state.items.where((restaurant) {
    final matchesQuery = query.isEmpty ||
        restaurant.name.toLowerCase().contains(query) ||
        restaurant.cuisine?.toLowerCase().contains(query) == true ||
        restaurant.address.toLowerCase().contains(query);
    final matchesCuisine = cuisine == null || cuisine == 'All' ||
        restaurant.cuisine == cuisine;
    return matchesQuery && matchesCuisine;
  }).toList();
});

/// Extract unique cuisines from the restaurant list.
final _availableCuisinesProvider = Provider<List<String>>((ref) {
  final state = ref.watch(restaurantListProvider);
  final cuisines = state.items
      .map((r) => r.cuisine)
      .whereType<String>()
      .toSet()
      .toList()
    ..sort();
  return ['All', ...cuisines];
});

class _HomeAppBar extends ConsumerWidget {
  final int cartCount;

  const _HomeAppBar({required this.cartCount});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;

    return SliverAppBar(
      pinned: true,
      floating: true,
      snap: true,
      elevation: 0,
      backgroundColor: AppColors.cream,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 16,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: AppColors.orange,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.restaurant_menu,
              size: 20,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'QuickBite',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 22,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
      actions: [
        // Search icon (expands to search field on mobile)
        if (MediaQuery.of(context).size.width < 720)
          IconButton(
            icon: const Icon(Icons.search, color: AppColors.ink),
            onPressed: () {
              // Search is always visible below app bar on mobile
            },
            tooltip: 'Search restaurants',
          ),
        // Cart
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
        // Profile menu
        PopupMenuButton<String>(
          icon: CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.orange.withValues(alpha: 0.15),
            child: Text(
              user?.name.isNotEmpty == true ? user!.name[0].toUpperCase() : 'U',
              style: const TextStyle(
                color: AppColors.orangeDeep,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          offset: const Offset(0, 56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onSelected: (value) {
            if (value == 'orders') {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const OrderHistoryScreen()),
              );
            } else if (value == 'signout') {
              ref.read(authProvider.notifier).signOut();
              Navigator.of(context).popUntil((r) => r.isFirst);
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem<String>(
              value: 'orders',
              child: Row(
                children: [
                  const Icon(Icons.receipt_long_outlined, size: 20, color: AppColors.inkSoft),
                  const SizedBox(width: 12),
                  const Text('My Orders'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              value: 'signout',
              child: Row(
                children: [
                  const Icon(Icons.logout, size: 20, color: AppColors.danger),
                  const SizedBox(width: 12),
                  const Text('Sign out', style: TextStyle(color: AppColors.danger)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

class _SearchField extends ConsumerWidget {
  const _SearchField();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(_searchQueryProvider);

    return Semantics(
      label: 'Search restaurants and cuisines',
      textField: true,
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search restaurants, cuisines...',
          prefixIcon: const Icon(Icons.search, color: AppColors.inkFaint),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD7BFA9)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD7BFA9)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.orangeDeep, width: 2),
          ),
          suffixIcon: query.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: AppColors.inkFaint),
                  onPressed: () => ref.read(_searchQueryProvider.notifier).state = '',
                )
              : null,
        ),
        onChanged: (value) => ref.read(_searchQueryProvider.notifier).state = value,
      ),
    );
  }
}

class _CuisineFilterChips extends ConsumerWidget {
  const _CuisineFilterChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cuisines = ref.watch(_availableCuisinesProvider);
    final selected = ref.watch(_selectedCuisineProvider);

    return Semantics(
      label: 'Filter by cuisine',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            for (final cuisine in cuisines)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(cuisine),
                  selected: selected == cuisine || (selected == null && cuisine == 'All'),
                  onSelected: (_) => ref.read(_selectedCuisineProvider.notifier).state = cuisine,
                  selectedColor: AppColors.orangeDeep.withValues(alpha: 0.15),
                  checkmarkColor: AppColors.orangeDeep,
                  labelStyle: TextStyle(
                    color: (selected == cuisine || (selected == null && cuisine == 'All'))
                        ? AppColors.orangeDeep
                        : AppColors.ink,
                    fontWeight: FontWeight.w600,
                  ),
                  side: const BorderSide(color: Color(0xFFD7BFA9)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  backgroundColor: AppColors.creamRaised,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RestaurantCard extends ConsumerWidget {
  final Restaurant restaurant;

  const _RestaurantCard({required this.restaurant});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      button: true,
      label: 'Open menu for ${restaurant.name}',
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: restaurant.isActive
              ? () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MenuScreen(restaurant: restaurant),
                    ),
                  )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Restaurant image
              AspectRatio(
                aspectRatio: 16 / 9,
                child: _buildImage(),
              ),
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Cuisine badge
                      if (restaurant.cuisine != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.orange.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            restaurant.cuisine!,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.orangeDeep,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      // Name
                      Text(
                        restaurant.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.ink,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // Rating + delivery time
                      Row(
                        children: [
                          if (restaurant.rating != null) ...[
                            const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                            const SizedBox(width: 3),
                            Text(
                              restaurant.rating!.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          if (restaurant.deliveryTimeMinutes != null) ...[
                            const Icon(Icons.access_time_rounded, size: 14, color: AppColors.inkFaint),
                            const SizedBox(width: 3),
                            Text(
                              '${restaurant.deliveryTimeMinutes} min',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.inkSoft,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const Spacer(),
                      // Description
                      if (restaurant.description != null)
                        Text(
                          restaurant.description!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.inkSoft,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (!restaurant.isActive) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.dangerBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Currently closed',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.danger,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImage() {
    if (restaurant.imageUrl != null && restaurant.imageUrl!.isNotEmpty) {
      return Image.network(
        restaurant.imageUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: AppColors.creamRaised,
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        },
        errorBuilder: (context, error, stackTrace) => _placeholderImage(),
      );
    }
    return _placeholderImage();
  }

  Widget _placeholderImage() {
    return Container(
      color: AppColors.creamRaised,
      child: const Center(
        child: Icon(Icons.restaurant, size: 48, color: AppColors.inkFaint),
      ),
    );
  }
}

class _HomeDrawer extends ConsumerWidget {
  const _HomeDrawer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    return Drawer(
      backgroundColor: AppColors.cream,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.account_circle, size: 48, color: AppColors.orangeDeep),
                  const SizedBox(height: 8),
                  Text(
                    user?.name ?? 'Guest',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    user?.email ?? '',
                    style: const TextStyle(color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('My orders'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const OrderHistoryScreen()),
                );
              },
            ),
            const Spacer(),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.danger),
              title: const Text('Sign out', style: TextStyle(color: AppColors.danger)),
              onTap: () {
                ref.read(authProvider.notifier).signOut();
                Navigator.of(context).popUntil((r) => r.isFirst);
              },
            ),
          ],
        ),
      ),
    );
  }
}