// The server stores instants in UTC and the book has a timezone. A date a person
// picks ("1 Oct") means midnight *there*, otherwise a month-end salary slips into
// the wrong period.

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

// "Sept", not "Sep": the web's en-IN formatting, so a date reads the same on both.
const _shortMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];

/// A book's clock.
///
/// ponytail: only fixed-offset zones are known (Asia/Kolkata is +05:30 with no
/// daylight saving, and Paisa is India-only per the docs). Any other name falls
/// back to Kolkata rather than guessing. Add the `timezone` package if a book
/// outside India ever exists.
class BookClock {
  BookClock(String? timezone) : offset = _offsetFor(timezone);

  final Duration offset;

  static Duration _offsetFor(String? timezone) => switch (timezone) {
    'UTC' => Duration.zero,
    _ => const Duration(hours: 5, minutes: 30),
  };

  /// Wall-clock time in the book as a UTC-flagged DateTime, so its `day`, `month`
  /// and `hour` read as the book's own. Never send this one to the API.
  DateTime wall(DateTime instant) => instant.toUtc().add(offset);

  /// Midnight on [year]-[month]-[day] in the book, as the UTC instant to send.
  DateTime dateAt(int year, int month, int day) =>
      DateTime.utc(year, month, day).subtract(offset);

  /// `26 Aug`, in the book's timezone.
  String shortDate(DateTime instant) {
    final local = wall(instant);
    return '${local.day} ${_shortMonths[local.month - 1]}';
  }

  /// `26 Aug 2026`, in the book's timezone.
  String longDate(DateTime instant) => '${shortDate(instant)} ${wall(instant).year}';
}

/// `August 2026` from a `YYYY-MM` month key.
String monthLabel(String month) {
  final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(month);
  if (match == null) throw FormatException('Not a YYYY-MM month', month);
  final index = int.parse(match.group(2)!) - 1;
  if (index < 0 || index > 11) throw FormatException('Not a YYYY-MM month', month);
  return '${_months[index]} ${match.group(1)}';
}

/// The month before or after a `YYYY-MM` key.
String shiftMonth(String month, int by) {
  final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(month);
  if (match == null) throw FormatException('Not a YYYY-MM month', month);
  final total = int.parse(match.group(1)!) * 12 + (int.parse(match.group(2)!) - 1) + by;
  final year = total ~/ 12;
  final mon = total % 12 + 1;
  return '$year-${mon.toString().padLeft(2, '0')}';
}

/// Which `YYYY-MM` label covers [at] for a book that starts its month on
/// [periodStartDay]. A faithful port of `currentPeriodLabel` in the API's
/// `domain/period.js`, which is the source of truth: `test/fixtures/period_labels.json`
/// is recorded from that function and checked against this one.
///
/// A cycle starting after mid-month pays for the month that follows it, so with
/// day 26 the period labelled 2026-11 runs 26 Oct to 25 Nov. A day past the end
/// of a short month is clamped to its last day.
String currentPeriodLabel(DateTime at, String? timezone, int periodStartDay) {
  final day = periodStartDay >= 1 && periodStartDay <= 31 ? periodStartDay : 1;
  final local = BookClock(timezone).wall(at);
  final lastDay = DateTime.utc(local.year, local.month + 1, 0).day;
  final boundary = day < lastDay ? day : lastDay;
  final startedThisMonth = local.day >= boundary;
  final startOffset = day > 15 ? -1 : 0;
  final monthIndex = (local.month - 1) + (startedThisMonth ? 0 : -1) - startOffset;
  // DateTime.utc carries a month past either end of the year into the next one.
  final anchor = DateTime.utc(local.year, monthIndex + 1, 1);
  return '${anchor.year}-${anchor.month.toString().padLeft(2, '0')}';
}
