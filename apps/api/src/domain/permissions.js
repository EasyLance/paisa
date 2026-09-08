export const ROLE_CAPABILITIES = {
  viewer: new Set(['read']),
  reviewer: new Set(['read', 'comment', 'export', 'split', 'verify', 'reclassify']),
  editor: new Set(['read', 'comment', 'export', 'split', 'verify', 'reclassify', 'create', 'edit']),
  book_owner: new Set(['read', 'comment', 'export', 'split', 'verify', 'reclassify', 'create', 'edit', 'manage_book', 'delete_manual']),
  workspace_admin: new Set(['read', 'comment', 'export', 'split', 'verify', 'reclassify', 'create', 'edit', 'manage_book', 'manage_members', 'delete_manual']),
};

export function can(role, capability) {
  return Boolean(role && ROLE_CAPABILITIES[role]?.has(capability));
}

export function assertCapability(role, capability) {
  if (!can(role, capability)) {
    const error = new Error(`Role ${role ?? 'none'} cannot ${capability}`);
    error.statusCode = 403;
    error.code = 'FORBIDDEN';
    throw error;
  }
}

// An imported amount is the bank's word and stays as it arrived. Which bucket
// it belongs in is our reading of it, not the bank's - a debit to your own other
// account is a transfer, not spending - so `kind` stays editable as long as the
// amount and direction are untouched. A manual entry has no source of truth
// behind it at all, so a typo in one is just a typo.
const SOURCE_PROTECTED = ['occurredAt', 'merchant'];

export function assertCorrectable(sourceTypes, fields, currentAmountMinor) {
  const imported = [...new Set(sourceTypes.filter((type) => type && type !== 'manual'))];
  if (!imported.length) return;
  const touched = SOURCE_PROTECTED.filter((field) => fields[field] !== undefined);
  if (fields.amountMinor !== undefined && BigInt(fields.amountMinor) !== BigInt(currentAmountMinor)) touched.push('amountMinor');
  if (!touched.length) return;
  const error = new Error(`This entry came from ${imported.join(' and ')}, so ${touched.join(', ')} cannot be edited. You can change its type, or void it and add a corrected entry.`);
  error.statusCode = 409;
  error.code = 'IMMUTABLE_SOURCE';
  throw error;
}
