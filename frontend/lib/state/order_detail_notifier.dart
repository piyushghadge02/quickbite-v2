/// Order tracking with adaptive polling.
///
/// Behaviour:
/// * On start (and on every app-resume) fetches `GET /api/v1/orders/{id}`
///   immediately, plus the status history and notifications.
/// * While the order is non-terminal and the screen is visible, re-fetches
///   every ~2s.
/// * Stops when the status becomes terminal (DRIVER_ASSIGNED, PAYMENT_FAILED,
///   FAILED), when the provider is disposed (screen popped), or when the app
///   is backgrounded (`AppLifecycleState.paused`).
/// * Backs off on consecutive failures: 2s → 4s → 8s → 16s (cap); any
///   success resets the backoff. A failed poll never clears good data — the
///   last known order stays on screen with a "reconnecting" note.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../api/models.dart';
import '../domain/order_status.dart';
import 'providers.dart';

class OrderDetailState {
  final OrderDetail? order;
  final List<HistoryEntry> history;
  final List<AppNotification> notifications;
  final bool isLoading;
  final String? errorMessage;
  final bool isPolling;
  final bool isReconnecting;

  const OrderDetailState({
    this.order,
    this.history = const [],
    this.notifications = const [],
    this.isLoading = false,
    this.errorMessage,
    this.isPolling = false,
    this.isReconnecting = false,
  });

  OrderStatus get status => OrderStatus.fromWire(order?.status);

  OrderDetailState copyWith({
    OrderDetail? order,
    List<HistoryEntry>? history,
    List<AppNotification>? notifications,
    bool? isLoading,
    String? errorMessage,
    bool? isPolling,
    bool? isReconnecting,
  }) =>
      OrderDetailState(
        order: order ?? this.order,
        history: history ?? this.history,
        notifications: notifications ?? this.notifications,
        isLoading: isLoading ?? this.isLoading,
        errorMessage: errorMessage,
        isPolling: isPolling ?? this.isPolling,
        isReconnecting: isReconnecting ?? this.isReconnecting,
      );
}

/// App lifecycle as a provider so notifiers can pause/resume work.
final _lifecycleProvider = StreamProvider<AppLifecycleState>((ref) {
  final controller = StreamController<AppLifecycleState>.broadcast();
  final observer = _LifecycleObserver(controller.add);
  final binding = WidgetsBinding.instance;
  binding.addObserver(observer);
  ref.onDispose(() {
    binding.removeObserver(observer);
    controller.close();
  });
  return controller.stream;
});

class _LifecycleObserver extends WidgetsBindingObserver {
  final void Function(AppLifecycleState) onChange;
  _LifecycleObserver(this.onChange);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => onChange(state);
}

class OrderDetailNotifier extends FamilyNotifier<OrderDetailState, String> {
  static const _baseInterval = Duration(seconds: 2);
  static const _maxBackoff = Duration(seconds: 16);

  Timer? _timer;
  int _consecutiveFailures = 0;
  bool _backgrounded = false;
  // Riverpod 2.x Notifier has no `mounted`; track disposal manually.
  bool _disposed = false;
  late final String _orderId;
  ProviderSubscription<AsyncValue<AppLifecycleState>>? _lifecycleSub;

  @override
  OrderDetailState build(String orderId) {
    _orderId = orderId;
    // Watch lifecycle for pause/resume.
    _lifecycleSub = ref.listen<AsyncValue<AppLifecycleState>>(
      _lifecycleProvider,
      (_, next) => next.whenData(_onLifecycle),
      fireImmediately: false,
    );
    ref.onDispose(() {
      _disposed = true;
      _disposePolling();
    });
    Future.microtask(_start);
    return const OrderDetailState(isLoading: true);
  }

  ApiClient get _api => ref.read(apiClientProvider);

  void _onLifecycle(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) {
      _backgrounded = false;
      _refreshNow(); // refresh on resume
      _scheduleNext(immediate: false);
    } else if (lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.inactive ||
        lifecycle == AppLifecycleState.detached) {
      _backgrounded = true;
      _timer?.cancel();
      _timer = null;
      if (!_disposed) {
        state = state.copyWith(isPolling: false);
      }
    }
  }

  void _disposePolling() {
    _timer?.cancel();
    _timer = null;
    _lifecycleSub?.close();
  }

  Future<void> _start() async {
    await _refreshNow();
    _scheduleNext(immediate: false);
  }

  /// Public pull-to-refresh.
  Future<void> refresh() => _refreshNow();

  Future<void> _refreshNow() async {
    if (_disposed) return;
    try {
      final results = await Future.wait([
        _api.order(_orderId),
        _api.orderHistory(_orderId),
        _api.orderNotifications(_orderId, pageSize: 20),
      ]);
      if (_disposed) return;
      _consecutiveFailures = 0;
      final order = results[0] as OrderDetail;
      final history = results[1] as List<HistoryEntry>;
      final notifications = (results[2] as PagedResult<AppNotification>).items;
      state = state.copyWith(
        order: order,
        history: history,
        notifications: notifications,
        isLoading: false,
        errorMessage: null,
        isReconnecting: false,
      );
      if (OrderStatus.fromWire(order.status).isTerminal) {
        // Terminal: stop polling, keep the final snapshot.
        _timer?.cancel();
        _timer = null;
        state = state.copyWith(isPolling: false);
      }
    } on ApiException catch (e) {
      if (_disposed) return;
      _consecutiveFailures += 1;
      final hadData = state.order != null;
      state = state.copyWith(
        isLoading: !hadData,
        errorMessage: hadData ? null : e.message,
        isReconnecting: hadData,
      );
      // The timer callback's `.then` re-schedules with the grown backoff;
      // do not schedule here to avoid overlapping timers.
    } catch (_) {
      // Non-API failure (bug / unexpected). Keep the last good data and
      // back off like any other failure.
      if (_disposed) return;
      _consecutiveFailures += 1;
      final hadData = state.order != null;
      state = state.copyWith(
        isLoading: !hadData,
        errorMessage:
            hadData ? null : 'Something went wrong. Please retry.',
        isReconnecting: hadData,
      );
    }
  }

  void _scheduleNext({required bool immediate}) {
    _timer?.cancel();
    if (_backgrounded || _disposed) return;
    if (state.order != null &&
        OrderStatus.fromWire(state.order!.status).isTerminal) {
      state = state.copyWith(isPolling: false);
      return;
    }
    final failures = _consecutiveFailures;
    final delay = failures == 0
        ? _baseInterval
        : Duration(
            seconds: (_baseInterval.inSeconds * (1 << (failures - 1)))
                .clamp(2, _maxBackoff.inSeconds),
          );
    state = state.copyWith(isPolling: true);
    _timer = Timer(immediate ? Duration.zero : delay, () async {
      if (_disposed || _backgrounded) return;
      try {
        await _refreshNow();
      } finally {
        // Always re-arm: failures are retried with backoff, terminal
        // states stop the chain inside _scheduleNext.
        _scheduleNext(immediate: false);
      }
    });
  }
}
