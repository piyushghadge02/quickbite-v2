/// Order lifecycle: labels, terminal detection, progress, failure explanations.
///
/// Backend state machine:
///   PENDING -> PAID -> CONFIRMED -> DRIVER_ASSIGNED   (terminal success)
///   PENDING -> PAYMENT_FAILED                         (terminal)
///   PAID / CONFIRMED -> FAILED                        (terminal)
enum OrderStatus {
  pending('PENDING'),
  paid('PAID'),
  confirmed('CONFIRMED'),
  driverAssigned('DRIVER_ASSIGNED'),
  paymentFailed('PAYMENT_FAILED'),
  failed('FAILED'),
  unknown('');

  final String wireValue;
  const OrderStatus(this.wireValue);

  static OrderStatus fromWire(String? value) => OrderStatus.values
      .firstWhere((s) => s.wireValue == value, orElse: () => OrderStatus.unknown);

  bool get isTerminal =>
      this == driverAssigned || this == paymentFailed || this == failed;

  bool get isSuccess => this == driverAssigned;

  bool get isFailure => this == paymentFailed || this == failed;

  /// Human label for chips and headers.
  String get label => switch (this) {
        OrderStatus.pending => 'Pending payment',
        OrderStatus.paid => 'Payment received',
        OrderStatus.confirmed => 'Confirmed by restaurant',
        OrderStatus.driverAssigned => 'On its way',
        OrderStatus.paymentFailed => 'Payment failed',
        OrderStatus.failed => 'Order failed',
        OrderStatus.unknown => 'Unknown status',
      };

  /// Index on the happy-path progress rail (PENDING=0 … DRIVER_ASSIGNED=3).
  /// Returns -1 for failure/unknown states (no progress rail shown).
  int get progressIndex => switch (this) {
        OrderStatus.pending => 0,
        OrderStatus.paid => 1,
        OrderStatus.confirmed => 2,
        OrderStatus.driverAssigned => 3,
        _ => -1,
      };

  /// Readable explanation for terminal failures, combining the status and the
  /// backend `failure_code` (e.g. SIMULATED_DECLINE, NO_DRIVERS_AVAILABLE).
  String failureExplanation(String? failureCode) {
    if (this == OrderStatus.paymentFailed) {
      return switch (failureCode) {
        'SIMULATED_DECLINE' || 'PAYMENT_DECLINED' =>
          'Your payment was declined by the payment provider. No money was '
              'charged. Please try a different payment method and place the '
              'order again.',
        _ =>
          'Your payment could not be completed. No money was charged. '
              'Please try again.'
      };
    }
    if (this == OrderStatus.failed) {
      return switch (failureCode) {
        'NO_DRIVERS_AVAILABLE' =>
          'We could not find a delivery partner near the restaurant, so the '
              'order was cancelled. You have not been charged.',
        'RESTAURANT_REJECTED' =>
          'The restaurant could not accept your order (for example, it may '
              'have just closed). You have not been charged.',
        'ORDER_NOT_FOUND' =>
          'Something went wrong while processing your order. Please contact '
              'support with your order ID.',
        null || '' =>
          'The order could not be completed. You have not been charged.',
        _ =>
          'The order could not be completed ($failureCode). You have not '
              'been charged.',
      };
    }
    return '';
  }
}
