import { PrismaClient } from '@prisma/client';
import { DEFAULT_CATEGORIES } from '../src/domain/default-categories.js';

const db = new PrismaClient();

const categorySeeds = DEFAULT_CATEGORIES;

async function main() {
  await db.workspace.upsert({
    where: { id: 'ws_household' },
    update: {},
    create: { id: 'ws_household', name: 'Household finances' },
  });

  // `||` not `??`: an unset variable in an env file arrives as an empty string, and
  // firebaseUid is unique - two blank ones collide on the second insert.
  const people = [
    ['user_owner', process.env.SEED_OWNER_FIREBASE_UID || 'replace-owner-firebase-uid', process.env.SEED_OWNER_EMAIL || 'owner@example.com', 'Workspace owner'],
    ['user_spouse', process.env.SEED_SPOUSE_FIREBASE_UID || 'replace-spouse-firebase-uid', process.env.SEED_SPOUSE_EMAIL || 'spouse@example.com', 'Spouse'],
    ['user_ca', process.env.SEED_CA_FIREBASE_UID || 'replace-ca-firebase-uid', process.env.SEED_CA_EMAIL || 'ca@example.com', 'CA reviewer'],
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
    // Someone may already have created this category by hand. Seeding a second
    // one with the same name would leave two indistinguishable rows in every
    // picker, so leave theirs alone.
    const sameName = await db.category.findFirst({ where: { workspaceId: 'ws_household', name, id: { not: id } } });
    if (sameName) continue;
    await db.category.upsert({ where: { id }, update: { name, groupName, color }, create: { id, workspaceId: 'ws_household', name, groupName, color } });
  }
}

main()
  .then(() => console.log('Paisa pilot structure seeded without example financial amounts.'))
  .finally(() => db.$disconnect());
