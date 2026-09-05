#!/usr/bin/env node
// Regenerates deploy/schema.sql from the Prisma migrations.
//
//   npm run build:schema-sql
//
// deploy/schema.sql is a convenience for creating the database by hand (phpMyAdmin
// or an existing SQL workflow). `prisma migrate deploy` remains the supported path.
// This script exists so the file can never drift from the migrations: it is derived,
// never edited. `npm test` fails if it is out of date.
import { createHash } from 'node:crypto';
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const MIGRATIONS_DIR = 'apps/api/prisma/migrations';
const OUTPUT = 'deploy/schema.sql';

export function buildSchemaSql() {
  const names = readdirSync(MIGRATIONS_DIR, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort();

  const header = `-- Paisa database schema for MySQL 8
--
-- YOU PROBABLY DO NOT NEED THIS FILE.
--
-- The supported way to create these tables on the droplet is:
--
--     npm --workspace @paisa/api run prisma:deploy
--
-- That applies the same migrations this file was generated from, and records them
-- so future schema changes apply cleanly. Use this file only if you would rather
-- create the schema by hand (phpMyAdmin, an existing SQL workflow, or a managed
-- database whose console you use instead of a shell).
--
-- GENERATED FILE - do not edit. Regenerate with:
--     npm run build:schema-sql
--
-- IMPORTANT: the final section fills Prisma's _prisma_migrations bookkeeping table.
-- Without it, the next \`prisma migrate deploy\` would try to create these tables a
-- second time and fail. Do not remove it, and do not edit the checksums.
--
-- Usage:
--     mysql -u paisa -p paisa < deploy/schema.sql
-- or import through phpMyAdmin into an EMPTY \`paisa\` database.

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

`;

  const migrations = names.map((name) => {
    const sql = readFileSync(join(MIGRATIONS_DIR, name, 'migration.sql'), 'utf8').trim();
    return `-- ============================================================\n-- migration: ${name}\n-- ============================================================\n\n${sql}\n\n`;
  });

  const bookkeeping = `-- ============================================================
-- Prisma migration bookkeeping - required, see note at the top
-- ============================================================

CREATE TABLE IF NOT EXISTS \`_prisma_migrations\` (
    \`id\` VARCHAR(36) NOT NULL,
    \`checksum\` VARCHAR(64) NOT NULL,
    \`finished_at\` DATETIME(3) NULL,
    \`migration_name\` VARCHAR(255) NOT NULL,
    \`logs\` TEXT NULL,
    \`rolled_back_at\` DATETIME(3) NULL,
    \`started_at\` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    \`applied_steps_count\` INTEGER UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (\`id\`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

`;

  const rows = names.map((name) => {
    const checksum = createHash('sha256').update(readFileSync(join(MIGRATIONS_DIR, name, 'migration.sql'))).digest('hex');
    return `INSERT INTO \`_prisma_migrations\` (\`id\`, \`checksum\`, \`finished_at\`, \`migration_name\`, \`started_at\`, \`applied_steps_count\`)\nVALUES (UUID(), '${checksum}', NOW(3), '${name}', NOW(3), 1);`;
  });

  return `${header}${migrations.join('')}${bookkeeping}${rows.join('\n')}\n\nSET FOREIGN_KEY_CHECKS = 1;\n`;
}

export function currentSchemaSql() {
  return readFileSync(OUTPUT, 'utf8');
}

if (process.argv[1] && process.argv[1].endsWith('build-schema-sql.mjs')) {
  const sql = buildSchemaSql();
  writeFileSync(OUTPUT, sql);
  console.log(`Wrote ${OUTPUT} (${sql.length} bytes)`);
}
