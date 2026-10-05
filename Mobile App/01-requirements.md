# 01 · Requirements

> **Last reviewed** 2026-10-05

## 1. Purpose

The dashboard is good on a laptop and cramped on a phone. The Android app is the
household's everyday view of the same ledger: check where the month stands,
clear the payments waiting for review, and be told when something needs
attention. It is not a second product; it reads and writes the same API, with the
same rules, as the dashboard.

## 2. Users

Same four personas as the web app (`docs/prd.md` §2). The app is invite-only; a
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

Legend: **M** must · **S** should, cut first if time runs short.

### 4.1 Access

| ID | Requirement | |
|---|---|---|
| X1 | Sign in with Firebase email and password | M |
| X2 | "Request access": name and email, three replies (`received`, `pending`, `granted`) shown as the server says them | M |
| X3 | Forgot password sends Firebase's reset email | M |
| X4 | A signed-in account with no household shows a plain explanation and the request-access path, not a blank screen (`403 INVITE_REQUIRED`) | M |
| X5 | Pick which book to look at when the user has more than one; remember the choice | M |
| X6 | Sign out | M |
| X7 | Biometric or device-PIN lock on cold start and after the app has been in the background for a set time | M |

### 4.2 Dashboard

| ID | Requirement | |
|---|---|---|
| D-1 | Month navigation by the book's **pay cycle**, with the window printed beside the month name exactly as the server returns it | M |
| D-2 | Tiles: income, spent, saving (money moved), balance | M |
| D-3 | "Where your money went": breakdown that accounts for every rupee, including uncategorised, split and transfers | M |
| D-4 | Budget progress per group against the % plan | M |
| D-5 | "N payments need review" with a route straight to them | M |
| D-6 | When the API is unreachable: an explicit error state with actions disabled. **Never stale numbers shown as live** (the web rule) | M |

### 4.3 Transactions

| ID | Requirement | |
|---|---|---|
| T1 | Paged ledger, newest first, filter by state (pending review, confirmed, …) | M |
| T2 | Search by merchant or note over what has been loaded | S |
| T3 | Transaction detail: amounts, source, category, splits, comments | M |
| T4 | Review: confirm, change category, "apply to future" (writes a rule), void | M |
| T5 | Edit amount, kind, date, merchant, note, account (kind and amount change together) | M |
| T6 | Split one payment across categories | M |
| T7 | Comment on a transaction | M |
| T8 | **Import a bank statement** (CSV or .xlsx) from the phone's files, show imported / duplicate counts and any balance warnings | M |
| T9 | Add a manual transaction | S |

### 4.4 Budgets and recurring

| ID | Requirement | |
|---|---|---|
| B1 | View and edit the % plan per group; total may not exceed 100% | M |
| B2 | Show expected monthly income derived from recurring plans | M |
| R1 | List recurring plans, create, edit, stop | M |

### 4.5 People and access

| ID | Requirement | |
|---|---|---|
| P1 | List members of the book with their roles | M |
| P2 | Change a role, remove a member (book owners only). The API refuses changing your own access and removing the last owner; show its message | M |
| P3 | Invite by email and role; list and revoke pending invitations | M |

### 4.6 Extras

| ID | Requirement | |
|---|---|---|
| E1 | Dark mode: follow the system by default, user can force light or dark | M |
| E2 | Push notification when payments land in pending review, one notification per import or batch, not one per row | M |
| E3 | Notification permission requested at a sensible moment (Android 13+), with the app fully usable if declined | M |

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
