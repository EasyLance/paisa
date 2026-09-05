function localParts(date, timezone) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: timezone,
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23',
  }).formatToParts(date);
  return Object.fromEntries(parts.filter((part) => part.type !== 'literal').map((part) => [part.type, Number(part.value)]));
}

function localMidnightUtc(year, monthIndex, timezone) {
  const target = Date.UTC(year, monthIndex, 1);
  let result = target;
  for (let attempt = 0; attempt < 2; attempt += 1) {
    const parts = localParts(new Date(result), timezone);
    const rendered = Date.UTC(parts.year, parts.month - 1, parts.day, parts.hour, parts.minute, parts.second);
    result -= rendered - target;
  }
  return new Date(result);
}

export function monthRangeUtc(month, timezone) {
  const year = Number(month.slice(0, 4)); const monthIndex = Number(month.slice(5, 7)) - 1;
  return { start: localMidnightUtc(year, monthIndex, timezone), end: localMidnightUtc(year, monthIndex + 1, timezone) };
}

export function isInBookMonth(date, month, timezone) {
  const { start, end } = monthRangeUtc(month, timezone);
  return date >= start && date < end;
}
