import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_mobile/core/money.dart';

void main() {
  group('formatMoney', () {
    test('uses Indian grouping', () {
      expect(formatMinorString('0'), '₹0');
      expect(formatMinorString('75000'), '₹750');
      expect(formatMinorString('10417800'), '₹1,04,178');
      expect(formatMinorString('58786700'), '₹5,87,867');
      expect(formatMinorString('123456789012'), '₹1,23,45,67,890.12');
    });

    test('shows paise only when non-zero', () {
      expect(formatMinorString('190150'), '₹1,901.50');
      expect(formatMinorString('12345'), '₹123.45');
      expect(formatMinorString('5'), '₹0.05');
      expect(formatMinorString('190000'), '₹1,900');
    });

    test('a negative amount never loses its sign', () {
      expect(formatMinorString('-6914200'), '−₹69,142');
      expect(formatMinorString('-19010'), '−₹190.10');
      expect(formatMinorString('-75000'), startsWith('−'));
    });

    test('plusSign marks money coming in, never zero', () {
      expect(formatMinorString('58786700', plusSign: true), '+₹5,87,867');
      expect(formatMinorString('0', plusSign: true), '₹0');
    });

    test('does not lose precision on amounts a double cannot hold', () {
      expect(formatMoney(BigInt.parse('9007199254740993')), '₹9,00,71,99,25,47,409.93');
    });
  });

  group('parseMinor', () {
    test('reads the API wire format', () {
      expect(parseMinor('-190100'), BigInt.from(-190100));
      expect(parseMinor('0'), BigInt.zero);
    });

    test('rejects anything that is not whole paise', () {
      for (final bad in ['10.5', '1e5', 'abc', '', ' 5', '--5']) {
        expect(() => parseMinor(bad), throwsFormatException, reason: bad);
      }
    });
  });

  group('minorFromRupees', () {
    test('reads typed amounts', () {
      expect(minorFromRupees('1,234.5'), BigInt.from(123450));
      expect(minorFromRupees('750'), BigInt.from(75000));
      expect(minorFromRupees(' 0.05 '), BigInt.from(5));
    });

    test('refuses a third decimal instead of rounding it away', () {
      expect(minorFromRupees('1.234'), isNull);
    });

    test('refuses things that are not amounts', () {
      for (final bad in ['', 'abc', '-5', '1.', '.5', '1,2,3x']) {
        expect(minorFromRupees(bad), isNull, reason: bad);
      }
    });
  });

  group('signedMinor', () {
    final five = BigInt.from(500);
    test('expense is negative, income and refund positive', () {
      expect(signedMinor('expense', five), BigInt.from(-500));
      expect(signedMinor('income', five), five);
      expect(signedMinor('refund', five), five);
    });

    test('the sign comes from the kind, whatever sign went in', () {
      expect(signedMinor('expense', BigInt.from(-500)), BigInt.from(-500));
      expect(signedMinor('income', BigInt.from(-500)), five);
    });

    test('a transfer keeps the direction it was given', () {
      expect(signedMinor('transfer', five), BigInt.from(-500));
      expect(signedMinor('transfer', five, transferOut: false), five);
    });

    test('an unknown kind is a bug, not a guess', () {
      expect(() => signedMinor('gift', five), throwsArgumentError);
    });
  });
}
