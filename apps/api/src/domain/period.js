// A book's "month" is its pay cycle, which is not always a calendar month.
//
// Money arrives on payday and is spent until the next one, so for a household
// paid on the last working day, a calendar month puts the salary that funds
// November into October — the dashboard reads as a month-long deficit and then
// leaps on the 30th. `periodStartDay` moves the boundary to just before payday.
//
// A plain day number is enough even though "last working day" moves between the
// 28th and the 31st: every one of those falls inside a cycle starting on the
// 26th. Predicting payday needs a working-day calendar; bucketing it does not.
//
// A day past the 28th is clamped to the end of a short month: a cycle starting
// on the 30th starts on the 28th in February, the 29th in a leap year. Start
// and end clamp through the same function, so consecutive periods still meet
// exactly — no gap, no overlap.
export const MIN_PERIOD_START_DAY = 1;
export const MAX_PERIOD_START_DAY = 31;

export function normaliseStartDay(value) {
  const day = Number(value);
  if (!Number.isInteger(day) || day < MIN_PERIOD_START_DAY || day > MAX_PERIOD_START_DAY) return 1;
  return day;
}

function lastDayOf(year, monthIndex) {
  // Day 0 of the next month is the last day of this one, and Date.UTC
  // normalises a month index that has run off either end of the year.
  return new Date(Date.UTC(year, monthIndex + 1, 0)).getUTCDate();
}
function clampDay(year, monthIndex, day) {
  return Math.min(day, lastDayOf(year, monthIndex));
}

function localParts(date, timezone) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: timezone,
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23',
  }).formatToParts(date);
  return Object.fromEntries(parts.filter((part) => part.type !== 'literal').map((part) => [part.type, Number(part.value)]));
}

function localMidnightUtc(year, monthIndex, timezone, day = 1) {
  const target = Date.UTC(year, monthIndex, day);
  let result = target;
  for (let attempt = 0; attempt < 2; attempt += 1) {
    const parts = localParts(new Date(result), timezone);
    const rendered = Date.UTC(parts.year, parts.month - 1, parts.day, parts.hour, parts.minute, parts.second);
    result -= rendered - target;
  }
  return new Date(result);
}

// A cycle that starts after mid-month pays for the month that follows it, so
// with day 26 the period labelled 2026-11 runs 26 Oct → 25 Nov. Before
// mid-month it pays for the month it starts in: day 5, 2026-11 is 5 Nov → 4 Dec.
function startMonthOffset(day) {
  return day > 15 ? -1 : 0;
}

export function periodRangeUtc(month, timezone, periodStartDay = 1) {
  const year = Number(month.slice(0, 4));
  const monthIndex = Number(month.slice(5, 7)) - 1;
  const day = normaliseStartDay(periodStartDay);
  if (day === 1) {
    return { start: localMidnightUtc(year, monthIndex, timezone), end: localMidnightUtc(year, monthIndex + 1, timezone) };
  }
  const first = monthIndex + startMonthOffset(day);
  return {
    start: localMidnightUtc(year, first, timezone, clampDay(year, first, day)),
    end: localMidnightUtc(year, first + 1, timezone, clampDay(year, first + 1, day)),
  };
}

export function isInBookPeriod(date, month, timezone, periodStartDay = 1) {
  const { start, end } = periodRangeUtc(month, timezone, periodStartDay);
  const value = date instanceof Date ? date : new Date(date);
  return value >= start && value < end;
}

// Which label covers `at`. The dashboard opens here, and the API uses it when a
// request names no month.
export function currentPeriodLabel(at, timezone, periodStartDay = 1) {
  const day = normaliseStartDay(periodStartDay);
  const { year, month, day: today } = localParts(at ?? new Date(), timezone);
  // Compare against this month's clamped boundary, or 28 February would never
  // count as having reached a cycle that starts on the 30th.
  const startedThisMonth = today >= clampDay(year, month - 1, day);
  const monthIndex = (month - 1) + (startedThisMonth ? 0 : -1) - startMonthOffset(day);
  const anchor = new Date(Date.UTC(year, monthIndex, 1));
  return `${anchor.getUTCFullYear()}-${String(anchor.getUTCMonth() + 1).padStart(2, '0')}`;
}
