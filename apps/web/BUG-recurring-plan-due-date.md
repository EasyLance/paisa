# Bug: a recurring plan's first due date is UTC midnight, not the book's midnight

> **Found** 2026-10-17, while building the phone's recurring plans ·
> **Status** Open · **Severity** Low (5 h 30 m off; shows on the day of the first post)
> **Where** [`app/page.tsx`](app/page.tsx) `saveRecurring()` (line ~245)

## Summary

The recurring-plan form builds the first due date from the picked day like this:

```ts
nextDueAt: new Date(`${String(form.get('nextDueAt'))}T00:00:00.000Z`).toISOString()
```

`T00:00:00.000Z` is midnight **UTC**. The rule everywhere else in Paisa (`CLAUDE.md`,
"Timezone is Asia/Kolkata. Dates from a form anchor to midnight in the book's timezone via
`dateAt()`") is midnight **in the book's timezone**, which for an Indian book is
18:30 UTC on the day before. A plan made on the web is therefore due 5 h 30 m later in
India than a plan made on the phone for the same picked day.

## Effect

- A plan due "1 November" from the web is due at 05:30 India time on 1 November, not at
  00:00. Nothing breaks, because plans post when `nextDueAt` has passed and 05:30 is still
  that day.
- For an **Indian** book the plan still falls on the right calendar day. For a book in a
  timezone behind UTC it would fall on the *previous* evening there. Paisa is India-only
  today (the phone's `BookClock` is marked `ponytail:` for exactly that), so this is a rule
  being broken more than a bug anyone sees.
- The phone and the web now disagree for the same picked day, which shows when someone edits
  a plan on the other one.

## A related default

The same form defaults the category to `categories[0]` (`categoryId: categories[0]?.id ?? ''`
in both the create and edit forms), so a plan saved without touching the category is filed
under whichever category happens to be first. The server does not require a category.

## Fix

Anchor the date with the same helper the rest of the dashboard uses for form dates
(`dateAt()` in the book's timezone), and offer "No category" instead of defaulting to the
first one.

Do not change the API: it accepts any ISO timestamp with `Z` or an offset, which is correct.

## Related

- `Mobile App/docs/findings.md` F29 — where this was found.
- `Mobile App/app/lib/features/budgets/recurring_form_screen.dart` — the phone sends the
  book's midnight with `BookClock.dateAt`.
