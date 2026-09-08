// Turns a bank's CSV statement export into ingestion-ready rows.
//
// Written against a real State Bank of India savings-account export, which is
// the awkward case: metadata above the table, a "Details" column that the bank
// hard-wraps mid-word with embedded newlines, and a summary block underneath.
// Columns are located by their header text rather than by position, so exports
// that use "Narration"/"Withdrawal"/"Deposit" (HDFC, ICICI) also parse.

import { createHash } from 'node:crypto';

export class StatementFormatError extends Error {
  constructor(message) { super(message); this.name = 'StatementFormatError'; }
}

// RFC 4180 reader. Written out because the statement's Details column contains
// both commas and newlines inside quotes, which a split(',') cannot survive.
export function parseCsv(text) {
  const source = String(text).replace(/^\uFEFF/, '');
  const rows = []; let row = []; let field = ''; let quoted = false;
  for (let index = 0; index < source.length; index += 1) {
    const char = source[index];
    if (quoted) {
      if (char !== '"') { field += char; continue; }
      if (source[index + 1] === '"') { field += '"'; index += 1; continue; }
      quoted = false; continue;
    }
    if (char === '"') { quoted = true; continue; }
    if (char === ',') { row.push(field); field = ''; continue; }
    if (char === '\r') continue;
    if (char === '\n') { row.push(field); rows.push(row); row = []; field = ''; continue; }
    field += char;
  }
  if (field !== '' || row.length) { row.push(field); rows.push(row); }
  return rows;
}

const clean = (value) => String(value ?? '').trim();
const normalise = (value) => clean(value).toLowerCase().replace(/\s+/g, ' ');

// The bank wraps Details at a fixed width, breaking tokens across lines and
// indenting the continuation. A wrap inside a token uses one leading space
// ("smohanes\n h1" is really "smohanesh1"); a real word break uses more.
function unwrap(value) {
  return String(value ?? '').replace(/\r?\n[ \t]{2,}/g, ' ').replace(/\r?\n[ \t]?/g, '').replace(/[ \t]+/g, ' ').trim();
}

// "1,000.00" and "1000.00CR" both mean 100000 paise.
export function toMinor(value) {
  const digits = clean(value).replace(/[,\s₹]/g, '').replace(/(cr|dr)$/i, '');
  if (!/^-?\d+(\.\d{1,2})?$/.test(digits)) return null;
  const negative = digits.startsWith('-');
  const [whole, fraction = ''] = digits.replace('-', '').split('.');
  const minor = BigInt(whole) * 100n + BigInt(`${fraction}00`.slice(0, 2));
  return negative ? -minor : minor;
}

// Statements carry a date with no time; anchor it to the start of the day in the
// bank's own timezone so a payment never drifts into the previous month.
export function toIsoDate(value, offset = '+05:30') {
  const match = /^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})$/.exec(clean(value));
  if (!match) return null;
  const [, day, month, year] = match;
  const fullYear = year.length === 2 ? `20${year}` : year;
  const date = new Date(`${fullYear}-${month.padStart(2, '0')}-${day.padStart(2, '0')}T00:00:00.000${offset}`);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

const COLUMNS = [
  ['date', (name) => name === 'date' || name.includes('txn date') || name.includes('value date') || name.includes('transaction date')],
  ['details', (name) => name.startsWith('detail') || name.includes('narration') || name.includes('description') || name.includes('particular') || name.includes('remark')],
  ['debit', (name) => name.startsWith('debit') || name.includes('withdrawal') || name.includes('withdrawl')],
  ['credit', (name) => name.startsWith('credit') || name.includes('deposit')],
  ['balance', (name) => name.startsWith('balance') || name.includes('closing balance')],
  ['ref', (name) => name.includes('ref') || name.includes('cheque') || name.includes('chq')],
];

function indexColumns(row) {
  const found = {};
  row.forEach((cell, index) => {
    const name = normalise(cell);
    if (!name) return;
    for (const [key, matches] of COLUMNS) if (found[key] === undefined && matches(name)) { found[key] = index; return; }
  });
  return found;
}

const isHeaderRow = (row) => {
  const columns = indexColumns(row);
  return columns.date !== undefined && columns.debit !== undefined && columns.credit !== undefined;
};

// UPI narrations pack the payee into slash-delimited fields:
// "UPI/DR/624417205755/SHOBHA M/FDRL/smohanesh1/Paid".
const UPI = /UPI\/(DR|CR)\/([A-Za-z0-9]+)\/([^/]*)\/([^/]*)\/([^/]*)/i;
const ACCOUNT_NUMBER = /account number\s*:\s*([A-Za-z0-9*Xx]+)/i;
const IFSC = /ifsc code\s*:\s*([A-Za-z0-9]+)/i;

// Everything after "AT <branch code> <branch>" is the bank's own booking
// location, not the payee, so it only adds noise to the merchant name.
const stripBranch = (details) => details.replace(/\s+AT\s+\d+\s+.*$/i, '').trim();

function describe(details) {
  const upi = UPI.exec(details);
  if (!upi) return { merchant: stripBranch(details).slice(0, 160) || 'Statement entry', reference: null, handle: null, bankCode: null };
  const [, , reference, payee, bankCode, handle] = upi;
  return { merchant: (clean(payee) || clean(handle) || 'UPI payment').slice(0, 160), reference, handle: clean(handle) || null, bankCode: clean(bankCode) || null };
}

function readAccount(rows) {
  const text = rows.flat().join('\n');
  return {
    number: ACCOUNT_NUMBER.exec(text)?.[1] ?? null,
    ifsc: IFSC.exec(text)?.[1] ?? null,
  };
}

export function parseStatementCsv(text, { offset = '+05:30' } = {}) {
  const rows = parseCsv(text);
  const headerIndex = rows.findIndex(isHeaderRow);
  if (headerIndex === -1) throw new StatementFormatError('No transaction table found. The statement needs a header row with Date, Debit and Credit columns.');
  const columns = indexColumns(rows[headerIndex]);
  if (columns.details === undefined) throw new StatementFormatError('No description column found. Expected a Details, Narration or Particulars column.');

  const account = readAccount(rows.slice(0, headerIndex));
  const fingerprints = new Map();
  const warnings = [];
  const entries = [];
  let previousBalance = null;

  for (const row of rows.slice(headerIndex + 1)) {
    const occurredAt = toIsoDate(row[columns.date], offset);
    if (!occurredAt) continue; // metadata, blank lines and the summary block
    const details = unwrap(row[columns.details]);
    const debit = toMinor(row[columns.debit]);
    const credit = toMinor(row[columns.credit]);
    const balance = columns.balance === undefined ? null : toMinor(row[columns.balance]);
    if (!debit && !credit) { warnings.push(`Skipped a row with no amount: ${details.slice(0, 60) || 'blank'}`); continue; }
    if (debit && credit) { warnings.push(`Skipped a row debited and credited at once: ${details.slice(0, 60)}`); continue; }

    // The running balance is the bank's own checksum on our amount parsing.
    if (balance !== null && previousBalance !== null) {
      const expected = previousBalance + (credit ?? 0n) - (debit ?? 0n);
      if (expected !== balance) warnings.push(`Balance does not follow on ${clean(row[columns.date])} (${details.slice(0, 40)}) — imported the stated amount anyway`);
    }
    if (balance !== null) previousBalance = balance;

    const { merchant, reference, handle, bankCode } = describe(details);
    // A stable identity for the row so re-importing the same statement, or a
    // longer one that overlaps it, is recognised instead of duplicated. The
    // counter only separates rows that are genuinely identical.
    const fingerprint = `${occurredAt}|${debit ?? credit}|${clean(row[columns.ref]) || reference || details}`;
    const occurrence = (fingerprints.get(fingerprint) ?? 0) + 1;
    fingerprints.set(fingerprint, occurrence);

    entries.push({
      sourceType: 'statement',
      sourceHash: createHash('sha256').update(`statement:${account.number ?? ''}:${fingerprint}:${occurrence}`).digest('hex'),
      externalRef: (clean(row[columns.ref]) || reference || null)?.slice(0, 120) ?? null,
      occurredAt,
      kind: debit ? 'expense' : 'income',
      amountMinor: String(debit ? -debit : credit),
      currency: 'INR',
      merchant,
      note: details.slice(0, 2000) || null,
      metadata: { upiHandle: handle, upiBank: bankCode, balanceAfterMinor: balance === null ? null : String(balance) },
    });
  }

  if (!entries.length) throw new StatementFormatError('Found the transaction table but no dated rows in it.');
  return { account, rows: entries, warnings };
}
