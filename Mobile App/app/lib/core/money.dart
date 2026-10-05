// Money is integer paise. The API sends it as a string ("-190100") because JSON
// numbers lose precision; here it is a BigInt. There is no `double` anywhere in
// this file on purpose.

const _minus = '−'; // a real minus, not a hyphen, so it cannot be mistaken for a dash

final _minorPattern = RegExp(r'^-?\d+$');

BigInt parseMinor(String value) {
  if (!_minorPattern.hasMatch(value)) {
    throw FormatException('Not an amount in paise', value);
  }
  return BigInt.parse(value);
}

/// `₹1,04,178`, `−₹69,142`, `₹1,901.50`. Indian digit grouping; paise are shown
/// only when non-zero. A negative amount always carries its sign.
String formatMoney(BigInt minor, {bool plusSign = false}) {
  final negative = minor.isNegative;
  final abs = minor.abs();
  final rupees = abs ~/ BigInt.from(100);
  final paise = (abs % BigInt.from(100)).toInt();
  final sign = negative ? _minus : (plusSign && abs != BigInt.zero ? '+' : '');
  final paiseText = paise == 0 ? '' : '.${paise.toString().padLeft(2, '0')}';
  return '$sign₹${_groupIndian(rupees.toString())}$paiseText';
}

String formatMinorString(String minor, {bool plusSign = false}) =>
    formatMoney(parseMinor(minor), plusSign: plusSign);

// Last three digits, then pairs: 12345678 -> 1,23,45,678.
String _groupIndian(String digits) {
  if (digits.length <= 3) return digits;
  final head = digits.substring(0, digits.length - 3);
  final tail = digits.substring(digits.length - 3);
  final pairs = <String>[];
  for (var end = head.length; end > 0; end -= 2) {
    pairs.insert(0, head.substring(end - 2 < 0 ? 0 : end - 2, end));
  }
  return '${pairs.join(',')},$tail';
}

final _rupeesPattern = RegExp(r'^\d+(\.\d{1,2})?$');

/// Typed rupees ("1,234.5") to paise, or null if it is not a plain amount with
/// at most two decimals. Rejecting a third decimal is deliberate: silently
/// rounding what somebody typed is how a ledger drifts from the bank.
BigInt? minorFromRupees(String input) {
  final cleaned = input.trim().replaceAll(',', '');
  if (!_rupeesPattern.hasMatch(cleaned)) return null;
  final parts = cleaned.split('.');
  final whole = BigInt.parse(parts[0]) * BigInt.from(100);
  if (parts.length == 1) return whole;
  return whole + BigInt.parse(parts[1].padRight(2, '0'));
}

/// The amount to send for a form: expense negative, income and refund positive.
/// `kind` and `amountMinor` must always change together, because the sign is
/// the direction. A transfer out is also negative; the caller says which way.
BigInt signedMinor(String kind, BigInt unsigned, {bool transferOut = true}) {
  final magnitude = unsigned.abs();
  switch (kind) {
    case 'expense':
      return -magnitude;
    case 'income':
    case 'refund':
      return magnitude;
    case 'transfer':
      return transferOut ? -magnitude : magnitude;
    default:
      throw ArgumentError.value(kind, 'kind', 'Unknown transaction kind');
  }
}

/// The paise as plain rupees for a text field, with no grouping or symbol:
/// `75000` -> `750`, `75050` -> `750.50`. The reverse of [minorFromRupees].
String plainRupees(BigInt minor) {
  final abs = minor.abs();
  final rupees = abs ~/ BigInt.from(100);
  final paise = (abs % BigInt.from(100)).toInt();
  return paise == 0 ? '$rupees' : '$rupees.${paise.toString().padLeft(2, '0')}';
}
