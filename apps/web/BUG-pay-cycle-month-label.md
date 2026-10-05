# Bug: the dashboard's month label is wrong for pay-cycle start days 29–31

> **Found** 2026-10-05, while porting the pay-cycle logic to the phone app ·
> **Status** Open · **Severity** Low (narrow, but it shows the wrong month's money)
> **Where** [`app/page.tsx:132`](app/page.tsx) `currentPeriod()`

## Summary

A book's "month" is its pay cycle: `Book.periodStartDay` (1–31) moves the boundary
to just before payday. The API decides which period is current in
`apps/api/src/domain/period.js` → `currentPeriodLabel()`. The dashboard mirrors
that function in `currentPeriod()` so its month arrows know what to ask for.

The mirror is not faithful for start days above 28. A book whose month starts on
the **29th, 30th or 31st** is treated as calendar months, so on the days around
the end of the month the dashboard opens, and its arrows start, **one period
behind** the one the server considers current.

## Root cause

`app/page.tsx:137`:

```ts
const day=Number.isInteger(startDay)&&startDay>=1&&startDay<=28?startDay:1;
```

Anything above 28 falls back to `1`. That was correct when the API capped the
start day at 28; it no longer does. `docs/memory.md` records the change ("Start day
clamps, it does not cap"): the API accepts 1–31 and clamps the boundary to the last
day of a short month, so a cycle starting on the 30th starts on 28 February.

Two differences from the API's function:

| | API (`period.js`) | Web (`page.tsx`) |
|---|---|---|
| Accepted start days | 1–31 | 1–28, otherwise treated as 1 |
| Has the cycle started this month? | `today >= clampDay(year, month - 1, day)`, where `clampDay` is the smaller of the day and the month's last day | `today >= day`, never clamped |

## Evidence

Both functions were run for every day of 2026 (Asia/Kolkata) at nine start days:

- **3,285 comparisons, 61 mismatches.**
- All mismatches are at start day **29 (30 days)**, **30 (19 days)** and **31 (12 days)**.
- **Zero** mismatches at start days 1, 5, 15, 16, 26 and 28.

Examples, start day 30 (API versus web):

| Date | API says | Web says |
|---|---|---|
| 2026-01-30 | `2026-02` | `2026-01` |
| 2026-01-31 | `2026-02` | `2026-01` |
| 2026-02-28 | `2026-03` | `2026-02` |
| 2026-03-30 | `2026-04` | `2026-03` |

On 28 February a book starting on the 30th has already begun the cycle that pays
for March (the boundary clamps to the 28th). The web still shows February.

## Effect

- The dashboard opens on the previous period on those days.
- The month arrows start from the wrong place, so "this month" is last month's
  figures until the calendar catches up.
- **The figures themselves are not wrong.** Only the label is computed on the web;
  the period window and every total come from the summary response. That is why the
  header never contradicts the numbers, and why this went unnoticed.

Nobody in the live data is affected today: the owner's books use start day 1. It
matters the moment someone sets a start day of 29, 30 or 31, which the Pay cycle
control allows.

## Reproduce

From the repo root, with Node 22+:

```js
// repro.mjs — run with: node repro.mjs
import { currentPeriodLabel } from './apps/api/src/domain/period.js';

function web(at, timezone, startDay) {            // apps/web/app/page.tsx currentPeriod(), label only
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone: timezone, year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(at);
  const year = Number(parts.find((p) => p.type === 'year').value);
  const month = Number(parts.find((p) => p.type === 'month').value);
  const today = Number(parts.find((p) => p.type === 'day').value);
  const day = Number.isInteger(startDay) && startDay >= 1 && startDay <= 28 ? startDay : 1;
  const index = (month - 1) + (today >= day ? 0 : -1) - (day > 15 ? -1 : 0);
  const a = new Date(Date.UTC(year, index, 1));
  return `${a.getUTCFullYear()}-${String(a.getUTCMonth() + 1).padStart(2, '0')}`;
}

const at = new Date('2026-01-30T06:30:00Z');       // 30 Jan, noon in India
console.log('API', currentPeriodLabel(at, 'Asia/Kolkata', 30)); // 2026-02
console.log('web', web(at, 'Asia/Kolkata', 30));                // 2026-01
```

In the app: set a book's pay cycle to day 30 (Settings → Pay cycle), then open the
dashboard on 30 or 31 January. It opens on January; the API's current period is
February.

## Fix

Make the TypeScript mirror match `period.js` exactly. It should stay a mirror of the
API function, not a new rule:

1. Accept 1–31 (fall back to 1 only for a value outside that range).
2. Work out the last day of the current month and compare against the clamped
   boundary: `today >= Math.min(day, lastDayOfMonth)`.
3. Keep the rest (`day > 15` shifts the label back a month) as it is.

```ts
const day = Number.isInteger(startDay) && startDay >= 1 && startDay <= 31 ? startDay : 1;
const lastDay = new Date(Date.UTC(year, month, 0)).getUTCDate();   // last day of this month
const startedThisMonth = today >= Math.min(day, lastDay);
const index = (month - 1) + (startedThisMonth ? 0 : -1) - (day > 15 ? -1 : 0);
```

Do not change the API; it is the source of truth.

**Already checked:** the snippet above, run against `period.js` for every day of 2026
and of the leap year 2028 at every start day from 1 to 31, gives **0 mismatches in
22,661 comparisons**. The repro in the previous section prints `API 2026-02` and
`web 2026-01`.

## Verify

- Re-run the comparison above across all of 2026 and 2028 (a leap year) for start
  days 1–31: expect **0 mismatches**.
- A ready-made table of the API's own outputs is in
  [`../../Mobile App/app/test/fixtures/period_labels.json`](../../Mobile%20App/app/test/fixtures/period_labels.json):
  116 instants and the label `period.js` returned for each of 11 start days (1, 2, 5,
  15, 16, 20, 26, 28, 29, 30, 31), across month ends, a leap February and a year
  end. Check the fixed `currentPeriod()` against it. The phone app's Dart port
  agrees with it on all 1,276 cases.
- The API tests (`apps/api/test/api.test.js`) are the repo's only suite. Either add a
  test there that asserts the web function's table, or keep the comparison as a small
  script, so the two cannot drift again.
- Per `CLAUDE.md`: `npm run test`, `npm run lint`, `npx tsc --noEmit` in this
  folder, a build with the Firebase env sourced (`rm -rf dist .vinext` first), and
  update `docs/memory.md` (the traps table) and `TODO.md`.

## Related

- API source of truth: `apps/api/src/domain/period.js` (`currentPeriodLabel`,
  `periodRangeUtc`, `clampDay`).
- `docs/memory.md` decisions: "A plain day number, not a working-day calendar",
  "Start day clamps, it does not cap", "A cycle past mid-month is labelled by the
  month after".
- `Mobile App/docs/findings.md` F14 — where this was found, and the evidence that the
  phone follows the API.
