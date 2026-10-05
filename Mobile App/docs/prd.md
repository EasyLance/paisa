# 📋 Product Requirements

**Paisa Mobile — Android app**

This document defines what the phone app is for, who uses it, every v1 requirement
with its current state, and what is deliberately left out. The platform's own
requirements are in the repo's [`docs/prd.md`](../../docs/prd.md); this is the
phone's share of them.

> **Last reviewed** 2026-10-05 · **Status** Phases 0–2 built, 152 tests · **Platform** Android first, iOS later

## 1. Purpose

The dashboard is good on a laptop and cramped on a phone. The Android app is the
household's everyday view of the same ledger: check where the month stands,
clear the payments waiting for review, and be told when something needs
attention. It is not a second product; it reads and writes the same API, with the
same rules, as the dashboard.

## 2. Users

Same four personas as the platform (the repo's `docs/prd.md` §2). The app is invite-only; a
stranger can only ask for access.

| Persona | Role in a book | What the phone must let them do |
|---|---|---|
| Owner | `book_owner` | Everything, including people and budgets |
| Spouse | `book_owner` on their own book, `editor` on the shared one | Review, categorise, import |
| Chartered accountant | `reviewer` | Read, comment, confirm and reclassify; never edit amounts |
| Second household | `book_owner` of their own workspace | The same, fully separate |

The API already enforces roles (`viewer < reviewer < editor < book_owner <
admin`). The app reads the role from `GET /v1/books` and **hides or disables**
what the role cannot do rather than letting the user hit a 403.

## 3. Decisions made

| # | Question | Answer |
|---|---|---|
| D1 | Framework | **Flutter.** Already in the repo, one codebase for Android now and iOS later. Only SMS capture is Android-specific, because iOS cannot read SMS |
| D2 | Existing `apps/mobile` | **Fresh project in `Mobile App/app/`.** Old app is left alone until replaced, then removed with your OK |
| D3 | v1 scope | Sign in, request access, live dashboard, transactions (browse + review + import), budgets, recurring plans, people & access |
| D4 | SMS capture | **Phase 9, after v1.** v1 asks for no SMS permission, so Play testing needs no restricted-permission declaration |
| D5 | Extras | **Biometric / PIN lock, dark mode, push notifications.** Offline cache was not chosen |
| D6 | Application ID | `com.paisa.mobile` |
| D7 | Distribution | Sideloaded APK for the household **and** Play internal / closed testing |
| D8 | Design | Match the web dashboard: same colours, same calm tone, same words for things |

## 4. v1 functional requirements

Legend — **Pri** M must · S should, cut first if time runs short.
**State** ✅ built and verified · 🟡 built, one check outstanding · ⛔ not started.

> "Verified" means unit and widget tests **and** a run on the Android emulator
> against a local copy of the API. Nothing has yet been checked against the live
> site: that is the one outstanding sign-in in `tasks.md` Phase 1, which is why X1
> and X3 stay 🟡.

### 4.1 Access

| ID | Requirement | Pri | State |
|---|---|---|---|
| X1 | Sign in with Firebase email and password | M | 🟡 |
| X2 | "Request access": name and email, three replies (`received`, `pending`, `granted`) shown as the server says them | M | ✅ |
| X3 | Forgot password sends Firebase's reset email | M | 🟡 |
| X4 | A signed-in account with no household shows a plain explanation and the request-access path, not a blank screen (`403 INVITE_REQUIRED`) | M | ✅ |
| X5 | Pick which book to look at when the user has more than one; remember the choice | M | ✅ |
| X6 | Sign out | M | ✅ |
| X7 | Biometric or device-PIN lock on cold start and after the app has been in the background for a set time | M | ✅ |

### 4.2 Dashboard

| ID | Requirement | Pri | State |
|---|---|---|---|
| D-1 | Month navigation by the book's **pay cycle**, with the window printed beside the month name exactly as the server returns it | M | ✅ |
| D-2 | Tiles: income, spent, saving (money moved), balance | M | ✅ |
| D-3 | "Where your money went": breakdown that accounts for every rupee, including uncategorised, split and transfers | M | ✅ |
| D-4 | Budget progress per group against the % plan | M | ✅ |
| D-5 | "N payments need review" with a route straight to them (leads to the Activity tab, a placeholder until Phase 3) | M | 🟡 |
| D-6 | When the API is unreachable: an explicit error state with actions disabled. **Never stale numbers shown as live** (the web rule) | M | ✅ |

### 4.3 Transactions

| ID | Requirement | Pri | State |
|---|---|---|---|
| T1 | Paged ledger, newest first, filter by state (pending review, confirmed, …) | M | ⛔ |
| T2 | Search by merchant or note over what has been loaded | S | ⛔ |
| T3 | Transaction detail: amounts, source, category, splits, comments | M | ⛔ |
| T4 | Review: confirm, change category, "apply to future" (writes a rule), void | M | ⛔ |
| T5 | Edit amount, kind, date, merchant, note, account (kind and amount change together) | M | ⛔ |
| T6 | Split one payment across categories | M | ⛔ |
| T7 | Comment on a transaction | M | ⛔ |
| T8 | **Import a bank statement** (CSV or .xlsx) from the phone's files, show imported / duplicate counts and any balance warnings | M | ⛔ |
| T9 | Add a manual transaction | S | ⛔ |

### 4.4 Budgets and recurring

| ID | Requirement | Pri | State |
|---|---|---|---|
| B1 | View and edit the % plan per group; total may not exceed 100% | M | ⛔ |
| B2 | Show expected monthly income derived from recurring plans | M | ⛔ |
| R1 | List recurring plans, create, edit, stop | M | ⛔ |

### 4.5 People and access

| ID | Requirement | Pri | State |
|---|---|---|---|
| P1 | List members of the book with their roles | M | ⛔ |
| P2 | Change a role, remove a member (book owners only). The API refuses changing your own access and removing the last owner; show its message | M | ⛔ |
| P3 | Invite by email and role; list and revoke pending invitations | M | ⛔ |

### 4.6 Extras

| ID | Requirement | Pri | State |
|---|---|---|---|
| E1 | Dark mode: follow the system by default, user can force light or dark. Palette, Settings switch and every screen so far are done; each later screen has to pass the same check | M | 🟡 |
| E2 | Push notification when payments land in pending review, one notification per import or batch, not one per row | M | ⛔ |
| E3 | Notification permission requested at a sensible moment (Android 13+), with the app fully usable if declined | M | ⛔ |

## 5. Not in v1

| Out | Why |
|---|---|
| SMS capture and background upload | Phase 9. Needs its own permission declaration and parser consolidation |
| Reconciling SMS against statements | Server work (`TODO.md`), needs real SMS first |
| Offline reading | Not chosen; also fights the "never show stale numbers" rule |
| Reports, export, period verification | Dashboard job; add on request |
| Accounts and categorisation-rule management | Read-only on the phone (needed to pick an account or category) |
| Master admin console | Destructive to other people's records; stays on the web |
| Accepting an invitation | Stays on the web link in v1 (see A3) |
| PDF statement import | The API cannot parse PDFs yet |
| iOS | After Android v1 is stable |

## 6. Non-functional requirements

| Area | Requirement |
|---|---|
| Money | Integer paise as a string over the wire, `BigInt` in Dart. **Never `double`.** A negative amount always renders with its sign (`−₹69,142`). Indian grouping (`₹1,04,178`), paise only when non-zero |
| Time | Timestamps sent with `Z` or an offset; a naked local time is a 400. Dates a user picks anchor to midnight in the book's timezone (Asia/Kolkata) |
| Security | Tokens never logged. No financial data in logs or crash reports. No screenshots of the lock screen in the recents list (see §7 of the technical design) |
| Accessibility | Every icon-only control labelled; status is never colour alone; text scales with the system font setting; touch targets 48dp |
| Type scale | The web's 10–12px body is a desktop trade-off. On a phone the floor is 12sp, body 14sp |
| Copy | Same voice as `docs/design.md` §7: say what to do next, name the real thing, sentence case, no exclamation marks |
| Performance | Dashboard first paint after sign-in in under 2 s on a mid-range phone with a normal connection |
| Android versions | Flutter's default minimum SDK; target SDK as Play requires |

## 7. Assumptions to confirm

Defaults taken where the answers were silent. Change any of them and the plan
adjusts.

| # | Assumption | If wrong |
|---|---|---|
| A1 | "Import" means a **bank statement file** (CSV / .xlsx), the same as the web | If it also means pasting SMS text or photographing a receipt, that is new scope |
| A2 | Manual "Add transaction" is included as a should-have (T9) | Move to must, or cut |
| A3 | "People access" means owners **manage** members and invitations. Accepting an invitation stays on the web link because it needs a Firebase account with a verified email first | Mobile accept needs a deep-link and a verified-email path |
| A4 | The phone is **online only** in v1 | Add a read cache (extra phase) |
| A5 | English only, INR only | — |
| A6 | Portrait is the supported orientation | — |
| A7 | One Firebase project (`paisa-easylance`) for web and Android | — |

---

## 8. Principles

The platform's principles (P1–P6 in the repo's `docs/prd.md` §3) all hold here. The
phone adds four of its own.

| # | Principle | What it rules out |
|---|---|---|
| M1 | **Never show stale numbers as live** | A cached figure under a "this month" label; a zeroed screen beside an error banner |
| M2 | **The phone adds no rules** | Recomputing totals, categorising, or deciding what counts as spending. The server decides; the phone displays and submits |
| M3 | **The lock is a UI gate, never the session** | A Paisa PIN, a lock that signs you out, or a lock you cannot get out of |
| M4 | **One install channel per phone** | Updating a sideloaded APK with a Play build, or the reverse (different signing keys) |

---

## 9. Acceptance Criteria That Matter

| Scenario | Expected |
|---|---|
| Dashboard for August in a calendar-month book | Income ₹5,87,867, spent ₹39,324.50, saved ₹10,000, balance ₹5,38,542.50 — exactly the API's figures |
| The breakdown for that month | Sums to spent plus saved (₹49,324.50), including the uncategorised payment and the transfer |
| A book whose month starts on the 26th, viewed on 5 October | "October 2026 · 26 Sept – 25 Oct" |
| The same book, one period back | "September 2026 · 26 Aug – 25 Sept" holds the 26 August payments; "August 2026 · 26 Jul – 25 Aug" holds the 25 August salary |
| The API cannot be reached | An explicit error, no figures, nothing zeroed |
| A viewer opens the dashboard | The review card is shown, with no Review button |
| A reviewer opens it | The Review button is there (a reviewer can confirm by choosing a category) |
| Sign in with no household | "No household yet", with a request-access path — never a blank screen |
| The lock is on and the app returns after the grace period | The phone's own prompt appears; cancelling it leaves the lock screen; unlocking returns to the same screen |
| The phone has no screen lock | The lock cannot be turned on, and says why |
| A release build | Window is secure (no screenshots or recents thumbnail), no development header or emulator address in the binary, Firebase starts |

---

## 10. How We Know It Works

| Measure | Target | Today |
|---|---|---|
| Automated checks | All green before any phase is called done | ✅ 152 tests, analyzer clean |
| Month logic agrees with the API | 100% on recorded cases | ✅ 1,276 of 1,276 |
| Dashboard figures equal the API's | Every book and period checked | ✅ 2 books, 4 periods, incl. a pay-cycle boundary |
| Sign in against production | Done once with a real account | ⛔ needs Arjun's own password |
| First paint after sign-in | Under 2 s on a mid-range phone | ⛔ not measured (emulator only) |
| Payment to ledger | Under a minute | ⛔ blocked on SMS capture (Phase 9) |

