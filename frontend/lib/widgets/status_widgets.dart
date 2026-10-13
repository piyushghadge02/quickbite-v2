/// Order status chip + failure explanation card.
///
/// Chip colors are dark text on tinted backgrounds (see [AppColors.statusColors])
/// to keep ≥ 4.5:1 contrast. The chip carries a [Semantics] label so screen
/// readers announce e.g. "Order status: on its way".
library;

import 'package:flutter/material.dart';

import '../domain/order_status.dart';
import '../theme/app_theme.dart';

class OrderStatusChip extends StatelessWidget {
  final String statusWire;
  final bool large;

  const OrderStatusChip({super.key, required this.statusWire, this.large = false});

  @override
  Widget build(BuildContext context) {
    final status = OrderStatus.fromWire(statusWire);
    final colors = AppColors.statusColors[status.wireValue] ??
        (AppColors.creamRaised, AppColors.inkSoft);
    return Semantics(
      // ExcludeSemantics keeps the announcement to a single label instead of
      // "Order status: X" + "X" merged from the child Text.
      label: 'Order status: ${status.label}',
      child: ExcludeSemantics(
        child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: large ? 16 : 10, vertical: large ? 8 : 4),
        decoration: BoxDecoration(
          color: colors.$1,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          status.label,
          style: TextStyle(
            color: colors.$2,
            fontWeight: FontWeight.w700,
            fontSize: large ? 15 : 12,
          ),
        ),
        ),
      ),
    );
  }
}

/// Readable explanation for terminal failure states, with the raw failure
/// code kept visible (small, muted) for support conversations.
class FailureExplanationCard extends StatelessWidget {
  final String statusWire;
  final String? failureCode;

  const FailureExplanationCard({
    super.key,
    required this.statusWire,
    required this.failureCode,
  });

  @override
  Widget build(BuildContext context) {
    final status = OrderStatus.fromWire(statusWire);
    if (!status.isFailure) return const SizedBox.shrink();
    final explanation = status.failureExplanation(failureCode);
    return Semantics(
      label: 'Order failed: $explanation',
      child: Card(
        color: AppColors.dangerBg,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.error_outline, color: AppColors.danger),
                  SizedBox(width: 8),
                  Text(
                    'What happened',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Color(0xFF7F1D1D),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                explanation,
                style: const TextStyle(color: Color(0xFF7F1D1D), height: 1.4),
              ),
              if (failureCode != null && failureCode!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Reference: $failureCode',
                  style: const TextStyle(
                      color: Color(0xFF7F1D1D), fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Happy-path progress rail: Placed → Paid → Confirmed → On its way.
/// Hidden for failure/unknown states (progressIndex == -1).
class OrderProgressRail extends StatelessWidget {
  final String statusWire;

  const OrderProgressRail({super.key, required this.statusWire});

  static const _steps = [
    'Placed',
    'Paid',
    'Confirmed',
    'On its way',
  ];

  @override
  Widget build(BuildContext context) {
    final status = OrderStatus.fromWire(statusWire);
    final current = status.progressIndex;
    if (current < 0) return const SizedBox.shrink();
    return Semantics(
      label: 'Order progress: ${_steps[current]}, step ${current + 1} of 4',
      child: Row(
        children: [
          for (int i = 0; i < _steps.length; i++) ...[
            _Dot(done: i <= current, isCurrent: i == current),
            if (i < _steps.length - 1)
              Expanded(
                child: Container(
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: i < current
                        ? AppColors.success
                        : AppColors.creamPressed,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final bool done;
  final bool isCurrent;

  const _Dot({required this.done, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: isCurrent ? 18 : 14,
      height: isCurrent ? 18 : 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? AppColors.success : AppColors.creamPressed,
        border: isCurrent
            ? Border.all(color: AppColors.success, width: 3)
            : null,
      ),
      child: done && !isCurrent
          ? const Icon(Icons.check, size: 10, color: Colors.white)
          : null,
    );
  }
}
