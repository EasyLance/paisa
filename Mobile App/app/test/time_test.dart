import 'dart:convert';
import 'dart:io';

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

  test('September is abbreviated the way the web does it', () {
    expect(clock.shortDate(DateTime.utc(2026, 9, 26, 6)), '26 Sept');
  });

  group('currentPeriodLabel', () {
    // Recorded from apps/api/src/domain/period.js, the source of truth, for 11
    // start days across month ends, a leap February and a year end.
    final recorded = jsonDecode(File('test/fixtures/period_labels.json').readAsStringSync()) as Map<String, dynamic>;
    final instants = (recorded['instants'] as List).cast<String>();
    final labels = recorded['labels'] as Map<String, dynamic>;

    for (final entry in labels.entries) {
      test('start day ${entry.key} agrees with the API on all ${instants.length} instants', () {
        final expected = (entry.value as List).cast<String>();
        final wrong = <String>[];
        for (var i = 0; i < instants.length; i++) {
          final got = currentPeriodLabel(DateTime.parse(instants[i]), 'Asia/Kolkata', int.parse(entry.key));
          if (got != expected[i]) wrong.add('${instants[i]}: got $got, API says ${expected[i]}');
        }
        expect(wrong, isEmpty);
      });
    }

    test('a salary cycle starting on the 26th is named for the month it pays for', () {
      expect(currentPeriodLabel(DateTime.parse('2026-10-25T12:00:00+05:30'), 'Asia/Kolkata', 26), '2026-10');
      expect(currentPeriodLabel(DateTime.parse('2026-10-26T12:00:00+05:30'), 'Asia/Kolkata', 26), '2026-11');
      expect(currentPeriodLabel(DateTime.parse('2026-12-31T12:00:00+05:30'), 'Asia/Kolkata', 26), '2027-01');
    });

    test('the book\'s clock decides the day, not the phone\'s', () {
      // 20:00 UTC on 30 Sept is already 1 Oct in India.
      expect(currentPeriodLabel(DateTime.utc(2026, 9, 30, 20), 'Asia/Kolkata', 1), '2026-10');
      expect(currentPeriodLabel(DateTime.utc(2026, 9, 30, 20), 'UTC', 1), '2026-09');
    });

    test('a nonsense start day falls back to calendar months', () {
      expect(currentPeriodLabel(DateTime.utc(2026, 10, 10), 'Asia/Kolkata', 0), '2026-10');
      expect(currentPeriodLabel(DateTime.utc(2026, 10, 10), 'Asia/Kolkata', 40), '2026-10');
    });
  });
}
