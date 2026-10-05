# Paisa Mobile

Everything about the Paisa phone apps lives in this folder. Android first, iOS
later. The web dashboard and API stay where they are (`apps/web`, `apps/api`);
this app is a client of that API and adds nothing to the data model except the
push-notification pieces in [02-technical-design.md](02-technical-design.md) §8.

> **Last reviewed** 2026-10-05 · **Status** Phase 0 built and passing; waiting on
> Arjun for the Firebase registration (0.3) and the look approval (0.7) ·
> **Owner** Arjun

## Files

| File | Read it for |
|---|---|
| [01-requirements.md](01-requirements.md) | What v1 is, who uses it, every decision made so far, and the assumptions still open |
| [02-technical-design.md](02-technical-design.md) | Stack, packages, folder layout, how each screen maps to an API route, auth, security, FCM, and what the API is missing |
| [03-development-plan.md](03-development-plan.md) | The phased flow: tasks, gates, who does each step, risks |
| [04-findings.md](04-findings.md) | Things found in the code or on this Mac that change the plan, each with a status |
| [05-firebase-android-setup.md](05-firebase-android-setup.md) | Arjun's step 0.3: registering the Android app in Firebase |
| `screenshots/` | Phase 0 look in light and dark, for approval |

Code lives in `app/` (a Flutter project). Docs stay at
this level so they are not buried in a build tree.

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
| **Look** | Matches the web dashboard (`docs/design.md`) |

## Status log

Newest first. One line per change of state, with the date.

| Date | Change |
|---|---|
| 2026-10-05 | Phase 0 built: project, API client, money and time helpers, light and dark theme, 50 tests, boots on the emulator and reads `/me` and `/books` from a local API. Open: 0.3 (Arjun), 0.7 approval (Arjun) |
| 2026-10-05 | Questions answered, planning docs written |

## When code lands

The moment `app/` exists, update these in the same turn (the repo's own rule in
`CLAUDE.md`, *Keeping the docs current*):

| Doc | Change |
|---|---|
| `CLAUDE.md` | Layout block: add `Mobile App/` and say what happens to `apps/mobile` |
| `docs/architecture.md` | Folder structure §3, technology stack §2 |
| `docs/prd.md` | Capture rows C7 / C8 stay as they are until Phase 9; add a mobile section |
| `docs/tasks.md` and `TODO.md` | The mobile phases |
| `docs/design.md` | Dark-mode tokens and the phone type scale (Phase 0 and Phase 2) |
