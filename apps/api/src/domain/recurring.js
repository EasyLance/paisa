// When a recurring plan is due, and what it owes.
//
// One implementation for both stores. The interesting part is month arithmetic:
// naively adding a month to the 31st spills into the month after next, so a rent
// plan on the 31st would silently drift. Days are clamped to the month instead.

const MONTHS = { monthly: 1, quarterly: 3, yearly: 12 };

const lastDayOf = (year, month) => new Date(Date.UTC(year, month + 1, 0)).getUTCDate();

export function advance(from, cadence) {
  const date = new Date(from);
  if (cadence === 'weekly') { date.setUTCDate(date.getUTCDate() + 7); return date; }
  const months = MONTHS[cadence];
  if (!months) { const error = new Error(`Unknown cadence: ${cadence}`); error.statusCode = 400; error.code = 'INVALID_CADENCE'; throw error; }
  const day = date.getUTCDate();
  // A plan that falls on the last day of its month means "month end", so it must
  // stay at month end. Clamping alone drifts backwards and never recovers:
  // 31 Jan would become 28 Feb, then 28 Mar, then 28 Apr.
  const endOfMonth = day === lastDayOf(date.getUTCFullYear(), date.getUTCMonth());
  // Move on the 1st, then set the day, so the intermediate date always exists.
  date.setUTCDate(1);
  date.setUTCMonth(date.getUTCMonth() + months);
  const last = lastDayOf(date.getUTCFullYear(), date.getUTCMonth());
  date.setUTCDate(endOfMonth ? last : Math.min(day, last));
  return date;
}

// Every posting a plan owes, oldest first, plus where it lands next. A plan can
// be months behind if the API was down, so this catches up instead of skipping
// to the next date and quietly losing the months in between.
//
// ponytail: capped at 24 postings per run; a plan two years stale catches up
// over several runs rather than in one long transaction.
export function duePostings(plan, now = new Date(), limit = 24) {
  if (plan.active === false) return { postings: [], nextDueAt: new Date(plan.nextDueAt) };
  const postings = [];
  let due = new Date(plan.nextDueAt);
  while (due.getTime() <= now.getTime() && postings.length < limit) {
    postings.push(new Date(due));
    due = advance(due, plan.cadence);
  }
  return { postings, nextDueAt: due };
}

// Deterministic, so a retry, a restart mid-run, or two overlapping ticks can
// never post the same month twice.
export function postingKey(planId, dueAt) {
  return `recurring:${planId}:${new Date(dueAt).toISOString().slice(0, 10)}`;
}
