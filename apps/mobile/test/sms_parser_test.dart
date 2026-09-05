import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_mobile/services/sms_parser.dart';

void main() {
  final parser = SmsParser();

  test('extracts a UPI debit without retaining the message body', () {
    final event = parser.parse(
      sender: 'HDFCBK',
      body:
          'Rs.750.00 debited from A/c XX1234 to SWIGGY via UPI. Ref 123456789012',
      receivedAt: DateTime.utc(2026, 8, 26, 10),
    );
    expect(event, isNotNull);
    expect(event!.kind, 'expense');
    expect(event.amountMinor, '-75000');
    expect(event.merchant, 'SWIGGY');
    expect(event.externalRef, '123456789012');
    expect(event.toJson().containsKey('body'), isFalse);
  });

  test('extracts a salary credit', () {
    final event = parser.parse(
      sender: 'ICICIB',
      body:
          'INR 587867.00 credited to account XX0042 from ACME TECHNOLOGIES on 25 Aug. Txn ABC12345',
      receivedAt: DateTime.utc(2026, 8, 25),
    );
    expect(event, isNotNull);
    expect(event!.kind, 'income');
    expect(event.amountMinor, '58786700');
  });

  test('ignores non-financial and promotional messages', () {
    expect(
      parser.parse(
        sender: 'SHOP',
        body: 'Your coupon saves Rs.500 today',
        receivedAt: DateTime.now(),
      ),
      isNull,
    );
    expect(
      parser.parse(
        sender: 'FRIEND',
        body: 'Dinner at 8?',
        receivedAt: DateTime.now(),
      ),
      isNull,
    );
  });
}
