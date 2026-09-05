import { PrismaClient } from '@prisma/client';

const db = new PrismaClient();

const categorySeeds = [
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
  ['cat_other', 'Uncategorized', 'Other', '#a1a8a3'],
];

async function main() {
  await db.workspace.upsert({
    where: { id: 'ws_household' },
    update: {},
    create: { id: 'ws_household', name: 'Household finances' },
  });

  const people = [
    ['user_owner', process.env.SEED_OWNER_FIREBASE_UID ?? 'replace-owner-firebase-uid', process.env.SEED_OWNER_EMAIL ?? 'owner@example.com', 'Workspace owner'],
    ['user_spouse', process.env.SEED_SPOUSE_FIREBASE_UID ?? 'replace-spouse-firebase-uid', process.env.SEED_SPOUSE_EMAIL ?? 'spouse@example.com', 'Spouse'],
    ['user_ca', process.env.SEED_CA_FIREBASE_UID ?? 'replace-ca-firebase-uid', process.env.SEED_CA_EMAIL ?? 'ca@example.com', 'CA reviewer'],
  ];
  for (const [id, firebaseUid, email, displayName] of people) {
    await db.userProfile.upsert({ where: { id }, update: { firebaseUid, email, displayName }, create: { id, firebaseUid, email, displayName } });
  }
  await db.workspaceUser.upsert({ where: { workspaceId_userId: { workspaceId: 'ws_household', userId: 'user_owner' } }, update: { isAdmin: true }, create: { workspaceId: 'ws_household', userId: 'user_owner', isAdmin: true } });

  const books = [
    ['book_owner', "Owner's finances", 'private'],
    ['book_spouse', "Spouse's finances", 'private'],
    ['book_home', 'Household', 'shared'],
  ];
  for (const [id, name, visibility] of books) {
    await db.book.upsert({ where: { id }, update: { name, visibility }, create: { id, workspaceId: 'ws_household', name, visibility } });
  }
  const memberships = [
    ['book_owner', 'user_owner', 'book_owner'],
    ['book_spouse', 'user_spouse', 'book_owner'],
    ['book_home', 'user_owner', 'book_owner'],
    ['book_home', 'user_spouse', 'editor'],
    ['book_home', 'user_ca', 'reviewer'],
  ];
  for (const [bookId, userId, role] of memberships) {
    await db.bookMembership.upsert({ where: { bookId_userId: { bookId, userId } }, update: { role }, create: { bookId, userId, role } });
  }
  for (const [id, name, groupName, color] of categorySeeds) {
    await db.category.upsert({ where: { id }, update: { name, groupName, color }, create: { id, workspaceId: 'ws_household', name, groupName, color } });
  }
}

main()
  .then(() => console.log('Paisa pilot structure seeded without example financial amounts.'))
  .finally(() => db.$disconnect());
