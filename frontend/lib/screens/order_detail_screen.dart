/// Order details with live tracking.
///
/// * Polls `GET /api/v1/orders/{id}` every ~2s while visible (see
///   [OrderDetailNotifier]); polling stops on terminal status, on dispose, and
///   when the app is backgrounded; failures back off without clearing data.
/// * Shows: status chip + progress rail, timeline (status history), driver
///   card when assigned, readable failure explanation for terminal failures,
///   and the order's notifications.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../api/models.dart';
import '../domain/order_status.dart';
import '../state/order_detail_notifier.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/error_view.dart';
import '../widgets/money.dart';
import '../widgets/responsive.dart';
import '../widgets/status_widgets.dart';

final _timeFormat = DateFormat('d MMM, h:mm a');

class OrderDetailScreen extends ConsumerWidget {
  final String orderId;

  const OrderDetailScreen({super.key, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(orderDetailProvider(orderId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order details'),
        actions: [
          Semantics(
            button: true,
            label: 'Refresh order status',
            child: IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => ref
                  .read(orderDetailProvider(orderId).notifier)
                  .refresh(),
            ),
          ),
        ],
      ),
      body: ResponsiveCenter(
        child: _buildBody(context, ref, state),
      ),
    );
  }

  Widget _buildBody(
      BuildContext context, WidgetRef ref, OrderDetailState state) {
    if (state.isLoading && state.order == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.errorMessage != null && state.order == null) {
      return ErrorView(
        message: state.errorMessage!,
        isNetworkError: true,
        semanticsLabel: 'Order failed to load',
        onRetry: () =>
            ref.read(orderDetailProvider(orderId).notifier).refresh(),
      );
    }
    final order = state.order!;

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(orderDetailProvider(orderId).notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _StatusHeader(order: order, state: state),
          const SizedBox(height: 8),
          FailureExplanationCard(
            statusWire: order.status,
            failureCode: order.failureCode,
          ),
          if (order.driverName != null || order.driverId != null)
            _DriverCard(order: order),
          _ItemsCard(order: order),
          _TimelineCard(history: state.history),
          _NotificationsCard(notifications: state.notifications),
        ],
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  final OrderDetail order;
  final OrderDetailState state;

  const _StatusHeader({required this.order, required this.state});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Status',
                          style: TextStyle(
                              color: AppColors.inkSoft, fontSize: 13)),
                      const SizedBox(height: 4),
                      OrderStatusChip(
                          statusWire: order.status, large: true),
                    ],
                  ),
                ),
                if (state.isPolling)
                  Semantics(
                    label: 'Live updates on',
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 6),
                        Text('Live',
                            style: TextStyle(
                                color: AppColors.inkFaint, fontSize: 12)),
                      ],
                    ),
                  ),
              ],
            ),
            if (state.isReconnecting)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Reconnecting… showing the last known status.',
                  style: TextStyle(
                      color: AppColors.warning, fontSize: 13),
                ),
              ),
            const SizedBox(height: 14),
            OrderProgressRail(statusWire: order.status),
            const SizedBox(height: 14),
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                _Fact(
                    label: 'Total',
                    value: formatMoney(order.totalMinor,
                        currency: order.currency)),
                _Fact(
                    label: 'Placed',
                    value: _timeFormat.format(order.createdAt.toLocal())),
                _Fact(label: 'Updates', value: 'v${order.version}'),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Deliver to: ${order.deliveryAddress}',
              style: const TextStyle(color: AppColors.inkSoft, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  final String label;
  final String value;

  const _Fact({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                const TextStyle(color: AppColors.inkFaint, fontSize: 12)),
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _DriverCard extends StatelessWidget {
  final OrderDetail order;

  const _DriverCard({required this.order});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Delivery driver: ${order.driverName ?? 'assigned'}',
      child: Card(
        color: AppColors.successBg,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.delivery_dining,
                  color: AppColors.success, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Your delivery partner',
                        style: TextStyle(
                            color: AppColors.inkSoft, fontSize: 13)),
                    Text(
                      order.driverName ?? 'Driver assigned',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 17),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemsCard extends StatelessWidget {
  final OrderDetail order;

  const _ItemsCard({required this.order});

  @override
  Widget build(BuildContext context) {
    if (order.items.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Items',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ...order.items.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                          '${item.quantity} × ${item.itemName}'),
                    ),
                    Text(
                      formatMoney(
                          item.unitPriceMinor * item.quantity,
                          currency: order.currency),
                      style:
                          const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  final List<HistoryEntry> history;

  const _TimelineCard({required this.history});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Timeline',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (history.isEmpty)
              const Text('No updates yet.',
                  style: TextStyle(color: AppColors.inkSoft))
            else
              Semantics(
                label: 'Order timeline, ${history.length} updates',
                child: Column(
                  children: [
                    for (int i = 0; i < history.length; i++)
                      _TimelineRow(
                        entry: history[i],
                        isLast: i == history.length - 1,
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

class _TimelineRow extends StatelessWidget {
  final HistoryEntry entry;
  final bool isLast;

  const _TimelineRow({required this.entry, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final status = OrderStatus.fromWire(entry.toStatus);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: status.isFailure
                      ? AppColors.danger
                      : status.isSuccess
                          ? AppColors.success
                          : AppColors.orange,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: AppColors.creamPressed,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status.label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (entry.fromStatus != null)
                    Text(
                      'from ${OrderStatus.fromWire(entry.fromStatus).label}',
                      style: const TextStyle(
                          color: AppColors.inkFaint, fontSize: 13),
                    ),
                  if (entry.note != null && entry.note!.isNotEmpty)
                    Text(entry.note!,
                        style: const TextStyle(
                            color: AppColors.inkSoft, height: 1.35)),
                  Text(
                    _timeFormat.format(entry.createdAt.toLocal()),
                    style: const TextStyle(
                        color: AppColors.inkFaint, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationsCard extends StatelessWidget {
  final List<AppNotification> notifications;

  const _NotificationsCard({required this.notifications});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Notifications',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (notifications.isEmpty)
              const Text('No notifications yet.',
                  style: TextStyle(color: AppColors.inkSoft))
            else
              ...notifications.map(
                (n) => Semantics(
                  label: 'Notification: ${n.title}. ${n.body}',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.notifications_outlined,
                            color: AppColors.orangeDeep, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(n.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              Text(n.body,
                                  style: const TextStyle(
                                      color: AppColors.inkSoft,
                                      height: 1.35)),
                              Text(
                                _timeFormat
                                    .format(n.createdAt.toLocal()),
                                style: const TextStyle(
                                    color: AppColors.inkFaint,
                                    fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
