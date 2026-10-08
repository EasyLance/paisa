# Paisa Mobile

Everything about the Paisa phone apps lives in this folder. Android first, iOS
later. The web dashboard and API stay where they are (`apps/web`, `apps/api`);
this app is a client of that API and adds nothing to the data model except the
push-notification pieces in [docs/architecture.md](docs/architecture.md) §8.

> **Last reviewed** 2026-10-08 · **Status** Phases 0, 1, 2 and 3 built, Phase 4 (statement import) in progress: .xlsx done, CSV and PDF to come; 248 tests passing.
> Production sign-in and adding a payment confirmed working by Arjun; still open: the lock with a real fingerprint (Phase 1 gate) and reviewing real payments (Phase 3 gate) ·
> **Owner** Arjun

## Files

The docs mirror the web app's `docs/` folder, one file for each question.

| File | Read it for |
|---|---|
| [docs/prd.md](docs/prd.md) | What v1 is, who uses it, every requirement with its state, what is left out, acceptance criteria |
| [docs/architecture.md](docs/architecture.md) | Stack, folder layout, how each screen maps to an API route, auth and session, security, push notifications, testing |
| [docs/rules.md](docs/rules.md) | The conventions, each with the cost of breaking it |
| [docs/design.md](docs/design.md) | Colours (light and dark), type scale, components, screen map, how it writes |
| [docs/tasks.md](docs/tasks.md) | Where we are, what is next, who owns each step, and the full phased plan with gates and risks |
| [docs/memory.md](docs/memory.md) | Facts, decisions and why, traps already paid for, open questions |
| [docs/findings.md](docs/findings.md) | Things found in the code or on this Mac that change the plan, each with a status |
| [docs/firebase-android-setup.md](docs/firebase-android-setup.md) | Registering the Android app in Firebase (done; kept for later fingerprints and iOS) |
| `docs/screenshots/` | What each phase looked like |

Code lives in `app/` (a Flutter project). Docs stay one level up so they are not
buried in a build tree.

## Decisions at a glance

| | |
|---|---|
| **Framework** | Flutter 3.38 / Dart 3.10 (both already installed on this Mac) |
| **Platform order** | Android → iOS. `app/` is created Android-only; iOS is added when its phase starts |
| **Application ID** | `com.paisa.mobile` (permanent once on Play) |
| **Project** | Fresh project in `Mobile App/app/`. The old `apps/mobile` stays untouched until the new app replaces it |
| **v1 screens** | Sign in · Request access · Live dashboard · Transactions (browse, review, import) · Budgets · Recurring plans · People & access |
| **v1 extras** | Biometric / PIN lock · Dark mode · Push notifications (FCM) |
| **Not in v1** | SMS capture (Phase 9, after v1), offline cache, reports, master admin |
| **Distribution** | Sideloaded APK **and** Play internal / closed testing |
| **Look** | The web dashboard's colours and layout, in a different typeface: **Anek Latin**, the one super.money uses, bundled in the app (`docs/design.md` §3) |

## Status log

Newest first. One line per change of state, with the date.

| Date | Change |
|---|---|
| 2026-10-08 | The whole app now uses **Anek Latin** (the typeface on super.money, confirmed from its CSS), bundled as one variable file with its OFL licence: no download at run time. It replaces both the system serif and sans. Checked on the emulator in light and dark at 360dp. A test fails if any screen names another family |
| 2026-10-08 | Phase 4, .xlsx: import a bank statement from the phone, including a **password-protected** workbook, which is opened on the phone (the password is never sent or saved). Sends the ordinary workbook under a fixed name; shows imported / already-in-ledger counts and each warning; shows the server's own words on `413` / `422`; a note says what is and is not kept. The decryption is checked against fixtures made by an independent library in two encryption schemes. Verified on the emulator through the system file picker against a local API. Found: the web cannot import protected workbooks (F19); what a statement import leaves in the database (F20). Open: Arjun's own file, then CSV, then PDF |
| 2026-10-05 | Arjun signed in against production with his own account and added a payment from the release build: both work. Open: the lock with a real fingerprint (the emulator has no sensor), reviewing real payments |
| 2026-10-05 | Phase 3 built: the ledger. Paged list with state chips and search over what is loaded; payment detail; confirm, change category (with "do the same next time") and void with a two-step confirm; edit (kind and amount together, date at the book's midnight); split editor that only saves when the parts add up; comments; add a payment with one idempotency key per form, proven to create one row after a dropped connection. Every action is offered by role. 205 tests; verified on the emulator in light and dark, including a real Confirm that the local server reported back. Found: write routes answer with different shapes (F16), the server lets a split payment's amount change (F17), comments carry only an author id (F18). Open: reviewing real payments against production |
| 2026-10-05 | Phase 2 built: the live dashboard. Pay-cycle month navigation (the Dart port of `currentPeriodLabel` agrees with the API's own function on 1,276 recorded cases), four tiles, where-the-money-went breakdown that adds up to spent plus saved, budget progress, review card, an explicit error state that shows no figures. Verified on the emulator at 360dp in light and dark, and against the API's own numbers for a calendar-month book and a book starting on the 26th. Found a web bug for start days 29–31 (F14). Open: the Phase 1 production sign-in |
| 2026-10-05 | Phase 1 built: sign-in, forgot password, request access, no-household screen, book picker, role gating, biometric / PIN lock, theme choice, sign-out. Verified on the emulator against a local API (owner and CA accounts, real system PIN prompt) and a release build checked: window is secure, no dev header or emulator address in the binary, Firebase starts. Open: production sign-in with Arjun's own account |
| 2026-10-05 | Phase 0 built: project, API client, money and time helpers, light and dark theme, 50 tests, boots on the emulator and reads `/me` and `/books` from a local API. Open: 0.3 (Arjun), 0.7 approval (Arjun) |
| 2026-10-05 | Questions answered, planning docs written |

## Keeping the docs current

A change is not finished until the docs that describe it match, in the same turn.
The table for **this folder's** docs is in [docs/rules.md](docs/rules.md) §9. A
mobile change can also touch the **repo-level** docs, which live outside this folder:

| Repo doc | Touch it when |
|---|---|
| `../CLAUDE.md` | The layout, the commands, or where things stand change |
| `../docs/architecture.md` | The mobile folder layout or stack changes, or the server gains a route the app needs (push, Phase 7) |
| `../docs/prd.md` §5.6 | A mobile requirement changes state |
| `../docs/tasks.md` and `../TODO.md` | A phase finishes or is reprioritised |
| `../docs/design.md` §12 | Only the pointer: the phone's design lives in [docs/design.md](docs/design.md) |
| `../docs/memory.md` | A mobile decision or trap also affects the web or the API |
| `../apps/web/` or `../apps/api/` | The phone finds a bug there: write it up where it lives (as `apps/web/BUG-pay-cycle-month-label.md`), do not fix it in passing |
