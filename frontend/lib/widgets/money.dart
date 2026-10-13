/// Money formatting: integer minor units (paise) → Indian-rupee string.
///
/// Never formats money from doubles — the backend deals in integer paise and
/// so does the UI. Uses the `en_IN` grouping (₹1,00,000) via package:intl.
library;

import 'package:intl/intl.dart';

final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

/// Formats [minor] paise as e.g. `₹1,250.00`.
String formatMoney(int minor, {String currency = 'INR'}) {
  if (currency != 'INR') {
    // Only INR exists today; keep the raw figure readable for anything else.
    return '${(minor / 100).toStringAsFixed(2)} $currency';
  }
  return _inr.format(minor / 100);
}
