// The starter categories every workspace gets. Kept in one place because the
// seed, the in-memory store and tenant provisioning all need the same list, and
// three copies would drift.
//
// Groups are the unit budgets are set in, so keep new categories inside the
// existing five: Essentials, Income, Lifestyle, Saving, Other.
export const DEFAULT_CATEGORIES = [
  ['cat_rent', 'Rent + maintenance', 'Essentials', '#315b46'],
  ['cat_utilities', 'Utilities', 'Essentials', '#60806f'],
  ['cat_groceries', 'Groceries', 'Essentials', '#89a55b'],
  ['cat_health', 'Health and insurance', 'Essentials', '#6d8e81'],
  ['cat_family', 'Money sent to family', 'Essentials', '#a9bd72'],
  ['cat_emi', 'EMI', 'Essentials', '#607b87'],
  ['cat_transport', 'Transportation', 'Essentials', '#6f8f83'],
  ['cat_food', 'Food delivery', 'Lifestyle', '#df8d6d'],
  ['cat_dining', 'Dining out', 'Lifestyle', '#d29a65'],
  ['cat_subscriptions', 'Subscriptions', 'Lifestyle', '#9d83a6'],
  ['cat_travel', 'Travel', 'Lifestyle', '#6399a4'],
  ['cat_salary', 'Salary', 'Income', '#397454'],
  ['cat_investment', 'Investment', 'Saving', '#4a7c8c'],
  ['cat_savings_transfer', 'Transfer to savings', 'Saving', '#5f8f9c'],
  ['cat_other', 'Uncategorized', 'Other', '#a1a8a3'],
];

// Seeded ids belong to the seeded workspace, so a second workspace gets fresh
// rows. Pass `makeId` when the store assigns ids itself (in memory); omit it and
// the id is left out for the database to generate.
export function categoriesFor(workspaceId, makeId) {
  return DEFAULT_CATEGORIES.map(([seedId, name, groupName, color]) => ({ ...(makeId ? { id: makeId(seedId) } : {}), workspaceId, name, groupName, color }));
}
