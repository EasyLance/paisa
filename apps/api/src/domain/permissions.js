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
