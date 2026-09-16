// Read the first worksheet of an .xlsx into rows of plain strings.
//
// No dependency: an .xlsx is a ZIP of XML, and Node already has the inflate.
// The alternative was SheetJS, whose npm build is stale and has carried
// prototype-pollution and ReDoS advisories, or ExcelJS, which is a large tree
// for the one thing wanted here - turning a sheet into the same rows-of-cells
// shape the CSV reader already produces.
//
// ponytail: handles the shapes a bank export actually uses - shared strings,
// inline strings, numbers and date serials. Formulas are read as their cached
// value. Not a general spreadsheet engine.

import { inflateRawSync } from 'node:zlib';

export class XlsxFormatError extends Error {
  constructor(message) { super(message); this.name = 'XlsxFormatError'; }
}

// Minimal ZIP reader: walk the central directory, inflate the members we want.
function unzip(buffer) {
  const end = buffer.lastIndexOf(Buffer.from([0x50, 0x4b, 0x05, 0x06]));
  if (end < 0) throw new XlsxFormatError('Not a valid .xlsx file (no ZIP directory found).');
  let offset = buffer.readUInt32LE(end + 16);
  const count = buffer.readUInt16LE(end + 10);
  const files = new Map();
  for (let index = 0; index < count; index += 1) {
    if (buffer.readUInt32LE(offset) !== 0x02014b50) throw new XlsxFormatError('Damaged ZIP directory in this .xlsx file.');
    const method = buffer.readUInt16LE(offset + 10);
    const compressedSize = buffer.readUInt32LE(offset + 20);
    const nameLength = buffer.readUInt16LE(offset + 28);
    const extraLength = buffer.readUInt16LE(offset + 30);
    const commentLength = buffer.readUInt16LE(offset + 32);
    const localOffset = buffer.readUInt32LE(offset + 42);
    const name = buffer.toString('utf8', offset + 46, offset + 46 + nameLength);
    // The local header repeats the name and extra field with its own lengths.
    const localNameLength = buffer.readUInt16LE(localOffset + 26);
    const localExtraLength = buffer.readUInt16LE(localOffset + 28);
    const start = localOffset + 30 + localNameLength + localExtraLength;
    const raw = buffer.subarray(start, start + compressedSize);
    files.set(name, () => (method === 0 ? raw : inflateRawSync(raw)).toString('utf8'));
    offset += 46 + nameLength + extraLength + commentLength;
  }
  return files;
}

const XML_ENTITIES = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" };
const decode = (text) => text
  .replace(/<[^>]+>/g, '')
  .replace(/&#(\d+);/g, (_m, code) => String.fromCodePoint(Number(code)))
  .replace(/&#x([0-9a-f]+);/gi, (_m, code) => String.fromCodePoint(parseInt(code, 16)))
  .replace(/&(amp|lt|gt|quot|apos);/g, (_m, name) => XML_ENTITIES[name]);

// Excel keeps dates as days since 1899-12-30 (its leap-year bug included).
const EXCEL_EPOCH = Date.UTC(1899, 11, 30);
const serialToDate = (serial) => {
  const date = new Date(EXCEL_EPOCH + Math.round(serial) * 86400000);
  return `${String(date.getUTCDate()).padStart(2, '0')}/${String(date.getUTCMonth() + 1).padStart(2, '0')}/${date.getUTCFullYear()}`;
};

const columnIndex = (reference) => [...reference.replace(/\d+/g, '')]
  .reduce((total, letter) => total * 26 + (letter.charCodeAt(0) - 64), 0) - 1;

// A float that came from a decimal in the sheet: 79485.149999999994 is 79485.15.
// Money columns must not be rejected for the last bit of IEEE noise.
const tidyNumber = (value) => {
  const rounded = Math.round(Number(value) * 100) / 100;
  return Number.isFinite(rounded) ? String(rounded) : String(value);
};

export function readXlsxRows(buffer, { dateColumns } = {}) {
  const files = unzip(Buffer.isBuffer(buffer) ? buffer : Buffer.from(buffer));
  const sheetName = [...files.keys()].filter((name) => /^xl\/worksheets\/sheet\d+\.xml$/.test(name)).sort()[0];
  if (!sheetName) throw new XlsxFormatError('This .xlsx has no worksheet to read.');

  const sharedSource = files.get('xl/sharedStrings.xml')?.() ?? '';
  const shared = [...sharedSource.matchAll(/<si>([\s\S]*?)<\/si>/g)].map((match) => decode(match[1]));

  const rows = [];
  for (const rowMatch of files.get(sheetName)().matchAll(/<row[^>]*>([\s\S]*?)<\/row>/g)) {
    const cells = [];
    for (const cell of rowMatch[1].matchAll(/<c r="([A-Z]+\d+)"([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g)) {
      const [, reference, attributes, body = ''] = cell;
      const type = /t="([^"]+)"/.exec(attributes)?.[1];
      const value = /<v>([\s\S]*?)<\/v>/.exec(body)?.[1];
      let text = '';
      if (type === 's') text = shared[Number(value)] ?? '';
      else if (type === 'inlineStr') text = decode(body);
      else if (type === 'str') text = decode(value ?? '');
      else if (value !== undefined) {
        // A bare number in a date column is a serial, not an amount.
        text = dateColumns?.has(columnIndex(reference)) ? serialToDate(Number(value)) : tidyNumber(value);
      }
      cells[columnIndex(reference)] = text;
    }
    rows.push([...cells].map((cell) => cell ?? ''));
  }
  if (!rows.length) throw new XlsxFormatError('This .xlsx has no rows to read.');
  return rows;
}
