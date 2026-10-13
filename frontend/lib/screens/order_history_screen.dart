/// Customer order history: status filters, pagination, pull-to-refresh,
/// tap-through to live tracking.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models.dart';
import '../domain/order_status.dart';
import '../state/orders_list_notifier.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/error_view.dart';
import '../widgets/money.dart';
import '../widgets/responsive.dart';
import '../widgets/status_widgets.dart';
import 'order_detail_screen.dart';

const _statusFilters = <String?>[
  null, // All
  'PENDING',
  'PAID',
  'CONFIRMED',
  'DRIVER_ASSIGNED',
  'PAYMENT_FAILED',
  'FAILED',
];

class OrderHistoryScreen extends ConsumerWidget {
  const OrderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ordersListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My orders')),
      body: ResponsiveCenter(
        child: Column(
          children: [
            _FilterChips(
              selected: state.statusFilter,
              onSelected: (s) =>
                  ref.read(ordersListProvider.notifier).setStatusFilter(s),
            ),
            Expanded(child: _buildList(context, ref, state)),
          ],
        ),
      ),
    );
  }

  Widget _buildList(
      BuildContext context, WidgetRef ref, OrdersListState state) {
    if (state.isLoading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.errorMessage != null && state.items.isEmpty) {
      return ErrorView(
        message: state.errorMessage!,
        isNetworkError: true,
        semanticsLabel: 'Order history failed to load',
        onRetry: () => ref.read(ordersListProvider.notifier).refresh(),
      );
    }
    if (state.items.isEmpty) {
      return const EmptyView(
        icon: Icons.receipt_long_outlined,
        title: 'No orders yet',
        subtitle: 'Your placed orders will show up here.',
        semanticsLabel: 'No orders',
      );
    }
    return RefreshIndicator(
      onRefresh: () => ref.read(ordersListProvider.notifier).refresh(),
      child: PagedListView(
        itemCount: state.items.length,
        isLoadingMore: state.isLoadingMore,
        hasMore: state.hasMore,
        onLoadMore: () => ref.read(ordersListProvider.notifier).loadMore(),
        itemBuilder: (context, index) {
          final order = state.items[index];
          return _OrderRow(order: order);
        },
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onSelected;

  const _FilterChips({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Filter orders by status',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            for (final value in _statusFilters)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(value == null
                      ? 'All'
                      : OrderStatus.fromWire(value).label),
                  selected: selected == value,
                  onSelected: (_) => onSelected(value),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  final OrderListItem order;

  const _OrderRow({required this.order});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label:
          'Order ${order.id}, ${OrderStatus.fromWire(order.status).label}, '
          'total ${formatMoney(order.totalMinor, currency: order.currency)}',
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => OrderDetailScreen(orderId: order.id),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '#${order.id.length > 8 ? order.id.substring(0, 8) : order.id}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace'),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formatMoney(order.totalMinor,
                            currency: order.currency),
                        style: const TextStyle(
                            color: AppColors.inkSoft, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                OrderStatusChip(statusWire: order.status),
                const Icon(Icons.chevron_right,
                    color: AppColors.inkFaint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
