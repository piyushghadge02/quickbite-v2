/// Admin overview — read-only.
///
/// Shows the pipeline summary (`GET /api/v1/admin/summary`): orders grouped
/// by status plus outbox/retry/quarantine counters, and the paginated admin
/// order list with status filters. Tapping an order opens the same read-only
/// [OrderDetailScreen] customers see. No mutating actions exist here by
/// design — the backend contract for this app is read-only for admins.
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
  null,
  'PENDING',
  'PAID',
  'CONFIRMED',
  'DRIVER_ASSIGNED',
  'PAYMENT_FAILED',
  'FAILED',
];

class AdminOverviewScreen extends ConsumerWidget {
  const AdminOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(adminSummaryProvider);
    final orders = ref.watch(adminOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin overview'),
        actions: [
          Semantics(
            button: true,
            label: 'Sign out',
            child: IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () =>
                  ref.read(authProvider.notifier).signOut(),
            ),
          ),
        ],
      ),
      body: ResponsiveCenter(
        child: RefreshIndicator(
          onRefresh: () async {
            await ref.read(adminSummaryProvider.notifier).refresh();
            await ref.read(adminOrdersProvider.notifier).refresh();
          },
          child: ListView(
            children: [
              const SizedBox(height: 8),
              _SummarySection(state: summary),
              const SizedBox(height: 8),
              _FilterChips(
                selected: orders.statusFilter,
                onSelected: (s) => ref
                    .read(adminOrdersProvider.notifier)
                    .setStatusFilter(s),
              ),
              _OrdersSection(state: orders),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummarySection extends ConsumerWidget {
  final AdminSummaryState state;

  const _SummarySection({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.isLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (state.errorMessage != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(state.errorMessage!,
                  style: const TextStyle(color: AppColors.danger)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () =>
                    ref.read(adminSummaryProvider.notifier).refresh(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final summary = state.summary!;
    return Semantics(
      label: 'Pipeline summary',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pipeline summary',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in summary.ordersByStatus.entries)
                    _StatChip(
                      label: OrderStatus.fromWire(entry.key).label,
                      value: '${entry.value}',
                      statusWire: entry.key,
                    ),
                ],
              ),
              const Divider(height: 28),
              Wrap(
                spacing: 20,
                runSpacing: 12,
                children: [
                  _Counter(
                      label: 'Outbox pending',
                      value: summary.outboxPending),
                  _Counter(
                      label: 'Outbox scheduled',
                      value: summary.outboxScheduled),
                  _Counter(
                      label: 'Retries scheduled',
                      value: summary.retriesScheduled),
                  _Counter(
                      label: 'Quarantined',
                      value: summary.quarantineTotal,
                      alert: summary.quarantineTotal > 0),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final String statusWire;

  const _StatChip({
    required this.label,
    required this.value,
    required this.statusWire,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value orders',
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: (AppColors.statusColors[statusWire]?.$1) ??
              AppColors.creamRaised,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 18)),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  final String label;
  final int value;
  final bool alert;

  const _Counter(
      {required this.label, required this.value, this.alert = false});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  color: alert ? AppColors.danger : AppColors.ink)),
          Text(label,
              style: const TextStyle(
                  color: AppColors.inkSoft, fontSize: 13)),
        ],
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

class _OrdersSection extends ConsumerWidget {
  final AdminOrdersState state;

  const _OrdersSection({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.isLoading && state.items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.errorMessage != null && state.items.isEmpty) {
      return ErrorView(
        message: state.errorMessage!,
        isNetworkError: true,
        semanticsLabel: 'Admin orders failed to load',
        onRetry: () =>
            ref.read(adminOrdersProvider.notifier).refresh(),
      );
    }
    if (state.items.isEmpty) {
      return const EmptyView(
        icon: Icons.inbox_outlined,
        title: 'No orders match',
        semanticsLabel: 'No orders',
      );
    }
    return Column(
      children: [
        for (final order in state.items) _AdminOrderRow(order: order),
        if (state.hasMore)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: state.isLoadingMore
                ? const CircularProgressIndicator()
                : OutlinedButton(
                    onPressed: () => ref
                        .read(adminOrdersProvider.notifier)
                        .loadMore(),
                    child: const Text('Load more'),
                  ),
          ),
      ],
    );
  }
}

class _AdminOrderRow extends StatelessWidget {
  final OrderListItem order;

  const _AdminOrderRow({required this.order});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Order ${order.id}, '
          '${OrderStatus.fromWire(order.status).label}',
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => OrderDetailScreen(orderId: order.id),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        order.id,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 13),
                      ),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
