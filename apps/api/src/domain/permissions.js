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

// An imported amount is the bank's word, not ours, so it stays as it arrived -
// a wrong statement row is voided and re-entered, never edited. A manual entry
// has no such source of truth behind it, so a typo in one is just a typo.
const SOURCE_PROTECTED = ['amountMinor', 'kind', 'occurredAt', 'merchant'];

export function assertCorrectable(sourceTypes, fields) {
  const imported = sourceTypes.filter((type) => type && type !== 'manual');
  const touched = SOURCE_PROTECTED.filter((field) => fields[field] !== undefined);
  if (!imported.length || !touched.length) return;
  const error = new Error(`This entry came from ${[...new Set(imported)].join(' and ')}, so ${touched.join(', ')} cannot be edited. Void it and add a corrected entry instead.`);
  error.statusCode = 409;
  error.code = 'IMMUTABLE_SOURCE';
  throw error;
}
