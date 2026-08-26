export function parseMinor(value, field = 'amountMinor') {
  if (typeof value !== 'string' || !/^-?\d+$/.test(value)) {
    const error = new Error(`${field} must be an integer string`);
    error.statusCode = 400;
    error.code = 'INVALID_MONEY';
    throw error;
  }
  return BigInt(value);
}

export function serializeMoney(value) {
  return typeof value === 'bigint' ? value.toString() : String(value);
}

export function jsonSafe(value) {
  return JSON.parse(JSON.stringify(value, (_key, item) => typeof item === 'bigint' ? item.toString() : item));
}
