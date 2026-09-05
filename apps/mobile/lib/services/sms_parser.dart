import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/financial_event.dart';

class SmsParser {
  static final _amount = RegExp(
    r'(?:INR|Rs\.?|₹)\s*([0-9,]+(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  );
  static final _debit = RegExp(
    r'\b(debited|spent|paid|sent|purchase|withdrawn)\b',
    caseSensitive: false,
  );
  static final _credit = RegExp(
    r'\b(credited|received|deposited|salary)\b',
    caseSensitive: false,
  );
  static final _financial = RegExp(
    r'\b(upi|a/c|acct|account|bank|txn|transaction|debited|credited)\b',
    caseSensitive: false,
  );
  static final _merchant = RegExp(
    r'\b(?:to|at|from)\s+([a-z0-9@._ -]{2,60}?)(?=\s+(?:on|ref|upi|txn|avl|bal|using|via)\b|[.,]|$)',
    caseSensitive: false,
  );
  static final _reference = RegExp(
    r'\b(?:ref(?:erence)?|utr|txn)\s*(?:no|id)?[.: -]*([a-z0-9-]{6,40})',
    caseSensitive: false,
  );

  FinancialEvent? parse({
    required String sender,
    required String body,
    required DateTime receivedAt,
  }) {
    if (!_financial.hasMatch(body) ||
        (!_debit.hasMatch(body) && !_credit.hasMatch(body))) {
      return null;
    }
    final amountMatch = _amount.firstMatch(body);
    if (amountMatch == null) return null;
    final rupees = double.tryParse(amountMatch.group(1)!.replaceAll(',', ''));
    if (rupees == null || rupees <= 0) return null;

    final kind = _debit.hasMatch(body) ? 'expense' : 'income';
    final unsignedMinor = (rupees * 100).round();
    final sourceHash = sha256
        .convert(
          utf8.encode('$sender|$body|${receivedAt.millisecondsSinceEpoch}'),
        )
        .toString();

    return FinancialEvent(
      sourceHash: sourceHash,
      kind: kind,
      amountMinor: (kind == 'expense' ? -unsignedMinor : unsignedMinor)
          .toString(),
      occurredAt: receivedAt,
      merchant: _merchant.firstMatch(body)?.group(1)?.trim(),
      externalRef: _reference.firstMatch(body)?.group(1),
    );
  }
}
