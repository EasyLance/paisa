# Paisa — Product Requirements

> **Status** `Phases 1–2 live` · **Users** invite-only households · **Region** India / INR / Asia-Kolkata
> **Live** <https://paisa.easylancefreelance.com> · **Last reviewed** 2026-09-20

---

## 1. The problem

An Indian household's money moves through UPI, cards, ACH mandates and bank
transfers, and the only complete record of it is a bank statement nobody reads.
Existing apps either want net-banking credentials, or assume a Western banking
model that has no idea what a VPA is.

Paisa's bet: **capture is the hard part, not charting.** If every payment lands
in one ledger with the right category and no duplicates, the reports write
themselves.

## 2. Who it is for

| Persona | Needs | Role in the app |
|---|---|---|
| **Owner** | One view of household money; corrections without losing history | `book_owner` |
| **Spouse** | Own private book, plus the shared household book | `book_owner` (own) + `editor` (shared) |
| **Chartered accountant** | Read and comment at year end; never edit amounts | `reviewer` |
| **Second household** | The same app, completely separate data | `book_owner` in its own workspace |

## 3. Principles

| # | Principle | What it rules out |
|---|---|---|
| P1 | **Never ask for bank credentials** | Account aggregation, screen scraping, stored PINs |
| P2 | **The bank's figure is a fact** | Silently rewriting an imported amount |
| P3 | **Everything is auditable** | Any change without a before/after record |
| P4 | **Capture beats data entry** | Manual-first workflows |
| P5 | **Households are sealed** | Any cross-tenant read, however convenient |
| P6 | **Not advice** | Recommendations, projections, tax positions |

## 4. Functional requirements

Legend — ✅ shipped · 🟡 partial · ⛔ not started

### 4.1 Capture

| ID | Requirement | State |
|---|---|---|
| C1 | Import a bank statement as **CSV** and turn each row into a reviewable entry | ✅ |
| C2 | Import a bank statement as **.xlsx** | ✅ |
| C3 | Import a **PDF** statement, including password-protected files | ⛔ |
| C4 | Detect columns by **header name**, so a new bank works without code | ✅ |
| C5 | Verify amounts against the statement's own **running balance** | ✅ |
| C6 | Never duplicate a row on re-import, per row, not per file | ✅ |
| C7 | Parse financial **SMS on-device**; upload only normalised fields | 🟡 built, not shipped |
| C8 | Upload captured SMS **in the background** | ⛔ |
| C9 | Reconcile an SMS capture against the same payment in a statement | ⛔ |

### 4.2 Ledger

| ID | Requirement | State |
|---|---|---|
| L1 | Integer-paise money; expenses negative, income positive | ✅ |
| L2 | Edit any entry — amount, date, type, merchant, account | ✅ |
| L3 | An imported entry keeps the bank's original figure forever | ✅ |
| L4 | **Void** an entry: it leaves every total, stays in the ledger | ✅ |
| L5 | Split one payment across categories | ✅ |
| L6 | Comment on an entry, visible to everyone with access | ✅ |
| L7 | Page through the full ledger, not just the first 100 | ✅ |
| L8 | Navigate months, not just the current one | ✅ |

### 4.3 Classification

| ID | Requirement | State |
|---|---|---|
| K1 | Confirming with "apply to future" writes a rule | ✅ |
| K2 | Rules match on merchant (exact/contains) or **VPA** | ✅ |
| K3 | Rules only affect future payments, never reviewed history | ✅ |
| K4 | Five groups: Essentials · Income · Lifestyle · Saving · Other | ✅ |
| K5 | Categories are per-workspace and editable | ✅ |

### 4.4 Money model

| ID | Requirement | State |
|---|---|---|
| M1 | **Spent** = expenses. **Saving** = transfers out. **Balance** = income − spent − saving | ✅ |
| M2 | The category breakdown accounts for every rupee that left | ✅ |
| M3 | Budget as a **% of expected income per group**, not rupees per category | ✅ |
| M4 | Expected income comes from recurring plans, so budgets work before payday | ✅ |
| M5 | Recurring plans post themselves when due, month-end sticky | ✅ |
| M6 | Show movement **between** your own accounts | ✅ |
| M7 | Refunds counted somewhere | ⛔ |

### 4.5 Access

| ID | Requirement | State |
|---|---|---|
| A1 | Firebase email/password sign-in; no public sign-up | ✅ |
| A2 | Invite someone into an existing book by email | ✅ |
| A3 | A book always keeps at least one owner; nobody edits their own access | ✅ |
| A4 | A new identity gets its own isolated household | ✅ *(flagged off)* |
| A5 | Disable a user from the dashboard | ⛔ |

## 5. Acceptance criteria that matter

| Scenario | Expected |
|---|---|
| Re-import the same statement | `imported: 0`, no duplicate rows |
| Import a statement with 172 rows | All 172 stored; the UI pages through them |
| A statement row's balance doesn't follow | A warning, and the stated amount is still imported |
| Edit an imported amount | Saved, audited, **and** `TransactionSource.importedAmount` unchanged |
| A payment to your own account | Typed Transfer → leaves Spent, appears in Saving and in account flows |
| Sign in with no membership | `403 INVITE_REQUIRED`, and the log says why |
| Another household's book id | `404` — not `403`, so it cannot be enumerated |

## 6. Out of scope

Tax calculation or filing · investment or financial advice · moving money ·
bank API integration · multi-currency · a public marketplace.

## 7. How we know it works

| Measure | Target | Today |
|---|---|---|
| Statement rows parsed correctly | 100%, proven by balance checksum | ✅ 0 warnings on SBI (17) and HDFC (172) |
| Payments needing manual categorisation | Falls each month as rules accumulate | 24 rules live |
| Duplicate entries in the ledger | Zero | Zero |
| Time from payment to ledger | Under a minute | ⛔ blocked on background upload |
