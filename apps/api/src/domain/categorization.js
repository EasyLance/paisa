// Which category an incoming payment should get, from the book's own rules.
//
// One implementation, used by both stores, so in-memory and MySQL can never
// disagree about how a payment gets classified.
//
// Precedence (from the product spec): an explicit choice on the transaction wins,
// then a book-specific merchant/VPA rule, then a recurring plan, then a system
// suggestion, then the uncategorized review queue. This module covers the rule
// step; the caller handles the explicit choice by simply not asking.

const VPA = /[a-z0-9._-]+@[a-z][a-z0-9.-]*/i;

// Bank SMS rarely labels the VPA separately - it arrives inside the merchant
// text ("paid to swiggy@okicici"), so pull it back out.
export function extractVpa(text) {
  return VPA.exec(text ?? '')?.[0]?.toLowerCase() ?? null;
}

export function matchCategoryRule(rules, { merchant, vpa } = {}) {
  const targetMerchant = (merchant ?? '').trim().toLowerCase();
  const targetVpa = (vpa ?? extractVpa(merchant))?.toLowerCase() ?? '';
  if (!targetMerchant && !targetVpa) return null;

  // Lower priority number wins; ties fall back to the older rule so behaviour is
  // stable rather than dependent on row order.
  const ordered = [...rules]
    .filter((rule) => rule.enabled !== false)
    .sort((a, b) => (a.priority ?? 100) - (b.priority ?? 100) || String(a.createdAt ?? '').localeCompare(String(b.createdAt ?? '')));

  for (const rule of ordered) {
    const value = String(rule.matchValue ?? '').trim().toLowerCase();
    if (!value) continue;
    if (rule.matchType === 'vpa_exact' && targetVpa && targetVpa === value) return rule;
    if (rule.matchType === 'merchant_exact' && targetMerchant && targetMerchant === value) return rule;
    if (rule.matchType === 'merchant_contains' && targetMerchant && targetMerchant.includes(value)) return rule;
  }
  return null;
}
