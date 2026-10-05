import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_mobile/core/time.dart';

void main() {
  final clock = BookClock('Asia/Kolkata');

  test('midnight in the book is the previous evening in UTC', () {
    expect(clock.dateAt(2026, 10, 1), DateTime.utc(2026, 9, 30, 18, 30));
  });

  test('a late-evening UTC instant is already tomorrow in India', () {
    final instant = DateTime.utc(2026, 9, 30, 20, 0);
    expect(clock.wall(instant).day, 1);
    expect(clock.shortDate(instant), '1 Oct');
    expect(clock.longDate(instant), '1 Oct 2026');
  });

  test('a salary stamped at month-end midnight stays in its own month', () {
    final salary = clock.dateAt(2026, 10, 31);
    expect(clock.shortDate(salary), '31 Oct');
  });

  test('dateAt and wall round-trip', () {
    final instant = clock.dateAt(2026, 2, 28);
    final wall = clock.wall(instant);
    expect([wall.year, wall.month, wall.day, wall.hour, wall.minute], [2026, 2, 28, 0, 0]);
  });

  test('UTC books have no offset', () {
    expect(BookClock('UTC').dateAt(2026, 10, 1), DateTime.utc(2026, 10, 1));
  });

  group('month keys', () {
    test('label', () => expect(monthLabel('2026-08'), 'August 2026'));
    test('shift forward across a year', () => expect(shiftMonth('2026-12', 1), '2027-01'));
    test('shift back across a year', () => expect(shiftMonth('2026-01', -1), '2025-12'));
    test('shift by many', () => expect(shiftMonth('2026-10', -13), '2025-09'));
    test('bad keys are rejected', () {
      for (final bad in ['2026-13', '2026-00', '26-08', 'August']) {
        expect(() => monthLabel(bad), throwsFormatException, reason: bad);
      }
    });
  });
}
