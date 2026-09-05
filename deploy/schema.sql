-- Paisa database schema for MySQL 8
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
-- Without it, the next `prisma migrate deploy` would try to create these tables a
-- second time and fail. Do not remove it, and do not edit the checksums.
--
-- Usage:
--     mysql -u paisa -p paisa < deploy/schema.sql
-- or import through phpMyAdmin into an EMPTY `paisa` database.

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ============================================================
-- migration: 20260827000100_initial
-- ============================================================

CREATE TABLE `Workspace` (
  `id` VARCHAR(191) NOT NULL,
  `name` VARCHAR(191) NOT NULL,
  `currency` CHAR(3) NOT NULL DEFAULT 'INR',
  `timezone` VARCHAR(191) NOT NULL DEFAULT 'Asia/Kolkata',
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,
  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `UserProfile` (
  `id` VARCHAR(191) NOT NULL,
  `firebaseUid` VARCHAR(191) NOT NULL,
  `email` VARCHAR(191) NOT NULL,
  `displayName` VARCHAR(191) NULL,
  `disabledAt` DATETIME(3) NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,
  UNIQUE INDEX `UserProfile_firebaseUid_key` (`firebaseUid`),
  UNIQUE INDEX `UserProfile_email_key` (`email`),
  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `WorkspaceUser` (
  `workspaceId` VARCHAR(191) NOT NULL,
  `userId` VARCHAR(191) NOT NULL,
  `isAdmin` BOOLEAN NOT NULL DEFAULT false,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`workspaceId`, `userId`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `Book` (
  `id` VARCHAR(191) NOT NULL,
  `workspaceId` VARCHAR(191) NOT NULL,
  `name` VARCHAR(191) NOT NULL,
  `visibility` ENUM('private', 'shared') NOT NULL DEFAULT 'private',
  `currency` CHAR(3) NOT NULL DEFAULT 'INR',
  `timezone` VARCHAR(191) NOT NULL DEFAULT 'Asia/Kolkata',
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,
  INDEX `Book_workspaceId_idx` (`workspaceId`),
  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `BookMembership` (
  `bookId` VARCHAR(191) NOT NULL,
  `userId` VARCHAR(191) NOT NULL,
  `role` ENUM('workspace_admin', 'book_owner', 'editor', 'reviewer', 'viewer') NOT NULL,
  `invitedById` VARCHAR(191) NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  INDEX `BookMembership_userId_idx` (`userId`),
  PRIMARY KEY (`bookId`, `userId`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `FinancialAccount` (
  `id` VARCHAR(191) NOT NULL,
  `workspaceId` VARCHAR(191) NOT NULL,
  `bookId` VARCHAR(191) NOT NULL,
  `name` VARCHAR(191) NOT NULL,
  `institution` VARCHAR(191) NULL,
  `accountMask` VARCHAR(191) NULL,
  `accountType` VARCHAR(191) NOT NULL,
  `currency` CHAR(3) NOT NULL DEFAULT 'INR',
  `openingBalance` BIGINT NOT NULL DEFAULT 0,
  `archivedAt` DATETIME(3) NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  INDEX `FinancialAccount_workspaceId_bookId_idx` (`workspaceId`, `bookId`),
  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `IngestionEvent` (
  `id` VARCHAR(191) NOT NULL,
  `workspaceId` VARCHAR(191) NOT NULL,
  `bookId` VARCHAR(191) NOT NULL,
  `accountId` VARCHAR(191) NULL,
  `sourceType` ENUM('sms', 'statement', 'manual', 'recurring') NOT NULL,
  `sourceHash` VARCHAR(191) NOT NULL,
  `externalRef` VARCHAR(191) NULL,
  `direction` ENUM('expense', 'income', 'transfer', 'refund') NOT NULL,
  `amountMinor` BIGINT NOT NULL,
  `currency` CHAR(3) NOT NULL DEFAULT 'INR',
  `merchant` VARCHAR(191) NULL,
  `occurredAt` DATETIME(3) NOT NULL,
  `state` ENUM('received', 'matched', 'needs_review', 'rejected') NOT NULL DEFAULT 'received',
  `metadata` JSON NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  INDEX `IngestionEvent_bookId_occurredAt_idx` (`bookId`, `occurredAt`),
  UNIQUE INDEX `IngestionEvent_workspaceId_sourceHash_key` (`workspaceId`, `sourceHash`),
  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `Transaction` (
  `id` VARCHAR(191) NOT NULL,
  `workspaceId` VARCHAR(191) NOT NULL,
  `bookId` VARCHAR(191) NOT NULL,
  `accountId` VARCHAR(191) NULL,
  `categoryId` VARCHAR(191) NULL,
  `kind` ENUM('expense', 'income', 'transfer', 'refund') NOT NULL,
  `state` ENUM('pending_review', 'confirmed', 'reconciled', 'excluded', 'voided') NOT NULL DEFAULT 'pending_review',
  `amountMinor` BIGINT NOT NULL,
  `currency` CHAR(3) NOT NULL DEFAULT 'INR',
  `merchant` VARCHAR(191) NULL,
  `note` TEXT NULL,
  `occurredAt` DATETIME(3) NOT NULL,
  `transferGroupId` VARCHAR(191) NULL,
  `refundOfId` VARCHAR(191) NULL,
  `createdById` VARCHAR(191) NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,
  INDEX `Transaction_workspaceId_bookId_occurredAt_idx` (`workspaceId`, `bookId`, `occurredAt`),
  INDEX `Transaction_bookId_state_idx` (`bookId`, `state`),
  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `TransactionSource` (
  `id` VARCHAR(191) NOT NULL,
  `transactionId` VARCHAR(191) NOT NULL,
  `ingestionEventId` VARCHAR(191) NULL,
  `sourceType` ENUM('sms', 'statement', 'manual', 'recurring') NOT NULL,
  `sourceReference` VARCHAR(191) NOT NULL,
  `importedAmount` BIGINT NOT NULL,
  `importedAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UNIQUE INDEX `TransactionSource_ingestionEventId_key` (`ingestionEventId`),
  UNIQUE INDEX `TransactionSource_sourceType_sourceReference_key` (`sourceType`, `sourceReference`),
  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `TransactionSplit` (
  `id` VARCHAR(191) NOT NULL,
  `transactionId` VARCHAR(191) NOT NULL,
  `categoryId` VARCHAR(191) NOT NULL,
  `amountMinor` BIGINT NOT NULL,
  `note` VARCHAR(191) NULL,
  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `Category` (
  `id` VARCHAR(191) NOT NULL,
  `workspaceId` VARCHAR(191) NOT NULL,
  `name` VARCHAR(191) NOT NULL,
  `groupName` VARCHAR(191) NOT NULL,
  `color` VARCHAR(191) NOT NULL,
  `archivedAt` DATETIME(3) NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UNIQUE INDEX `Category_workspaceId_name_key` (`workspaceId`, `name`),
  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `CategorizationRule` (
  `id` VARCHAR(191) NOT NULL,
  `bookId` VARCHAR(191) NOT NULL,
  `categoryId` VARCHAR(191) NOT NULL,
  `matchType` VARCHAR(191) NOT NULL,
  `matchValue` VARCHAR(191) NOT NULL,
  `priority` INTEGER NOT NULL DEFAULT 100,
  `enabled` BOOLEAN NOT NULL DEFAULT true,
  `createdById` VARCHAR(191) NOT NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  INDEX `CategorizationRule_bookId_priority_idx` (`bookId`, `priority`),
  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `Budget` (
  `id` VARCHAR(191) NOT NULL,
  `bookId` VARCHAR(191) NOT NULL,
  `categoryId` VARCHAR(191) NOT NULL,
  `month` DATE NOT NULL,
  `amountMinor` BIGINT NOT NULL,
  `currency` CHAR(3) NOT NULL DEFAULT 'INR',
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,
  UNIQUE INDEX `Budget_bookId_categoryId_month_key` (`bookId`, `categoryId`, `month`),
  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `RecurringPlan` (
  `id` VARCHAR(191) NOT NULL,
  `bookId` VARCHAR(191) NOT NULL,
  `categoryId` VARCHAR(191) NULL,
  `name` VARCHAR(191) NOT NULL,
  `kind` ENUM('expense', 'income', 'transfer', 'refund') NOT NULL,
  `amountMinor` BIGINT NOT NULL,
  `currency` CHAR(3) NOT NULL DEFAULT 'INR',
  `cadence` VARCHAR(191) NOT NULL,
  `nextDueAt` DATETIME(3) NOT NULL,
  `active` BOOLEAN NOT NULL DEFAULT true,
  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `PeriodReview` (
  `id` VARCHAR(191) NOT NULL,
  `bookId` VARCHAR(191) NOT NULL,
  `month` DATE NOT NULL,
  `status` VARCHAR(191) NOT NULL,
  `reviewedById` VARCHAR(191) NULL,
  `reviewedAt` DATETIME(3) NULL,
  `note` TEXT NULL,
  UNIQUE INDEX `PeriodReview_bookId_month_key` (`bookId`, `month`),
  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `Comment` (
  `id` VARCHAR(191) NOT NULL,
  `transactionId` VARCHAR(191) NOT NULL,
  `authorId` VARCHAR(191) NOT NULL,
  `body` TEXT NOT NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `Attachment` (
  `id` VARCHAR(191) NOT NULL,
  `bookId` VARCHAR(191) NOT NULL,
  `transactionId` VARCHAR(191) NULL,
  `storageKey` VARCHAR(191) NOT NULL,
  `contentType` VARCHAR(191) NOT NULL,
  `sizeBytes` INTEGER NOT NULL,
  `sha256` VARCHAR(191) NOT NULL,
  `expiresAt` DATETIME(3) NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UNIQUE INDEX `Attachment_storageKey_key` (`storageKey`),
  INDEX `Attachment_bookId_idx` (`bookId`),
  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `AuditEvent` (
  `id` VARCHAR(191) NOT NULL,
  `workspaceId` VARCHAR(191) NOT NULL,
  `bookId` VARCHAR(191) NULL,
  `actorId` VARCHAR(191) NULL,
  `action` VARCHAR(191) NOT NULL,
  `entityType` VARCHAR(191) NOT NULL,
  `entityId` VARCHAR(191) NOT NULL,
  `before` JSON NULL,
  `after` JSON NULL,
  `ipHash` VARCHAR(191) NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  INDEX `AuditEvent_workspaceId_createdAt_idx` (`workspaceId`, `createdAt`),
  INDEX `AuditEvent_bookId_createdAt_idx` (`bookId`, `createdAt`),
  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

ALTER TABLE `WorkspaceUser` ADD CONSTRAINT `WorkspaceUser_workspaceId_fkey` FOREIGN KEY (`workspaceId`) REFERENCES `Workspace` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `WorkspaceUser` ADD CONSTRAINT `WorkspaceUser_userId_fkey` FOREIGN KEY (`userId`) REFERENCES `UserProfile` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `Book` ADD CONSTRAINT `Book_workspaceId_fkey` FOREIGN KEY (`workspaceId`) REFERENCES `Workspace` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `BookMembership` ADD CONSTRAINT `BookMembership_bookId_fkey` FOREIGN KEY (`bookId`) REFERENCES `Book` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `BookMembership` ADD CONSTRAINT `BookMembership_userId_fkey` FOREIGN KEY (`userId`) REFERENCES `UserProfile` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `FinancialAccount` ADD CONSTRAINT `FinancialAccount_workspaceId_fkey` FOREIGN KEY (`workspaceId`) REFERENCES `Workspace` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `FinancialAccount` ADD CONSTRAINT `FinancialAccount_bookId_fkey` FOREIGN KEY (`bookId`) REFERENCES `Book` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `IngestionEvent` ADD CONSTRAINT `IngestionEvent_bookId_fkey` FOREIGN KEY (`bookId`) REFERENCES `Book` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `IngestionEvent` ADD CONSTRAINT `IngestionEvent_accountId_fkey` FOREIGN KEY (`accountId`) REFERENCES `FinancialAccount` (`id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `Transaction` ADD CONSTRAINT `Transaction_bookId_fkey` FOREIGN KEY (`bookId`) REFERENCES `Book` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `Transaction` ADD CONSTRAINT `Transaction_accountId_fkey` FOREIGN KEY (`accountId`) REFERENCES `FinancialAccount` (`id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `Transaction` ADD CONSTRAINT `Transaction_categoryId_fkey` FOREIGN KEY (`categoryId`) REFERENCES `Category` (`id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `TransactionSource` ADD CONSTRAINT `TransactionSource_transactionId_fkey` FOREIGN KEY (`transactionId`) REFERENCES `Transaction` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `TransactionSource` ADD CONSTRAINT `TransactionSource_ingestionEventId_fkey` FOREIGN KEY (`ingestionEventId`) REFERENCES `IngestionEvent` (`id`) ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE `TransactionSplit` ADD CONSTRAINT `TransactionSplit_transactionId_fkey` FOREIGN KEY (`transactionId`) REFERENCES `Transaction` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `TransactionSplit` ADD CONSTRAINT `TransactionSplit_categoryId_fkey` FOREIGN KEY (`categoryId`) REFERENCES `Category` (`id`) ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE `Category` ADD CONSTRAINT `Category_workspaceId_fkey` FOREIGN KEY (`workspaceId`) REFERENCES `Workspace` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `CategorizationRule` ADD CONSTRAINT `CategorizationRule_bookId_fkey` FOREIGN KEY (`bookId`) REFERENCES `Book` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `CategorizationRule` ADD CONSTRAINT `CategorizationRule_categoryId_fkey` FOREIGN KEY (`categoryId`) REFERENCES `Category` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `Budget` ADD CONSTRAINT `Budget_bookId_fkey` FOREIGN KEY (`bookId`) REFERENCES `Book` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `Budget` ADD CONSTRAINT `Budget_categoryId_fkey` FOREIGN KEY (`categoryId`) REFERENCES `Category` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `RecurringPlan` ADD CONSTRAINT `RecurringPlan_bookId_fkey` FOREIGN KEY (`bookId`) REFERENCES `Book` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `RecurringPlan` ADD CONSTRAINT `RecurringPlan_categoryId_fkey` FOREIGN KEY (`categoryId`) REFERENCES `Category` (`id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `PeriodReview` ADD CONSTRAINT `PeriodReview_bookId_fkey` FOREIGN KEY (`bookId`) REFERENCES `Book` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `Comment` ADD CONSTRAINT `Comment_transactionId_fkey` FOREIGN KEY (`transactionId`) REFERENCES `Transaction` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `Comment` ADD CONSTRAINT `Comment_authorId_fkey` FOREIGN KEY (`authorId`) REFERENCES `UserProfile` (`id`) ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE `Attachment` ADD CONSTRAINT `Attachment_bookId_fkey` FOREIGN KEY (`bookId`) REFERENCES `Book` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `Attachment` ADD CONSTRAINT `Attachment_transactionId_fkey` FOREIGN KEY (`transactionId`) REFERENCES `Transaction` (`id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `AuditEvent` ADD CONSTRAINT `AuditEvent_workspaceId_fkey` FOREIGN KEY (`workspaceId`) REFERENCES `Workspace` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `AuditEvent` ADD CONSTRAINT `AuditEvent_bookId_fkey` FOREIGN KEY (`bookId`) REFERENCES `Book` (`id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `AuditEvent` ADD CONSTRAINT `AuditEvent_actorId_fkey` FOREIGN KEY (`actorId`) REFERENCES `UserProfile` (`id`) ON DELETE SET NULL ON UPDATE CASCADE;

-- ============================================================
-- migration: 20260827000200_book_invitations
-- ============================================================

CREATE TABLE `BookInvitation` (
  `id` VARCHAR(191) NOT NULL,
  `workspaceId` VARCHAR(191) NOT NULL,
  `bookId` VARCHAR(191) NOT NULL,
  `email` VARCHAR(191) NOT NULL,
  `role` ENUM('workspace_admin', 'book_owner', 'editor', 'reviewer', 'viewer') NOT NULL,
  `tokenHash` VARCHAR(191) NOT NULL,
  `status` ENUM('pending', 'accepted', 'revoked', 'expired') NOT NULL DEFAULT 'pending',
  `invitedById` VARCHAR(191) NOT NULL,
  `expiresAt` DATETIME(3) NOT NULL,
  `acceptedAt` DATETIME(3) NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,
  UNIQUE INDEX `BookInvitation_tokenHash_key` (`tokenHash`),
  INDEX `BookInvitation_bookId_status_idx` (`bookId`, `status`),
  INDEX `BookInvitation_email_status_idx` (`email`, `status`),
  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

ALTER TABLE `BookInvitation` ADD CONSTRAINT `BookInvitation_workspaceId_fkey` FOREIGN KEY (`workspaceId`) REFERENCES `Workspace` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `BookInvitation` ADD CONSTRAINT `BookInvitation_bookId_fkey` FOREIGN KEY (`bookId`) REFERENCES `Book` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `BookInvitation` ADD CONSTRAINT `BookInvitation_invitedById_fkey` FOREIGN KEY (`invitedById`) REFERENCES `UserProfile` (`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- ============================================================
-- migration: 20260829000100_idempotency_records
-- ============================================================

CREATE TABLE `IdempotencyRecord` (
  `id` VARCHAR(191) NOT NULL,
  `workspaceId` VARCHAR(191) NOT NULL,
  `actorId` VARCHAR(191) NOT NULL,
  `operation` VARCHAR(191) NOT NULL,
  `keyHash` CHAR(64) NOT NULL,
  `requestHash` CHAR(64) NOT NULL,
  `transactionId` VARCHAR(191) NOT NULL,
  `expiresAt` DATETIME(3) NOT NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UNIQUE INDEX `IdempotencyRecord_workspaceId_actorId_operation_keyHash_key` (`workspaceId`, `actorId`, `operation`, `keyHash`),
  INDEX `IdempotencyRecord_expiresAt_idx` (`expiresAt`),
  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- ============================================================
-- Prisma migration bookkeeping - required, see note at the top
-- ============================================================

CREATE TABLE IF NOT EXISTS `_prisma_migrations` (
    `id` VARCHAR(36) NOT NULL,
    `checksum` VARCHAR(64) NOT NULL,
    `finished_at` DATETIME(3) NULL,
    `migration_name` VARCHAR(255) NOT NULL,
    `logs` TEXT NULL,
    `rolled_back_at` DATETIME(3) NULL,
    `started_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `applied_steps_count` INTEGER UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

INSERT INTO `_prisma_migrations` (`id`, `checksum`, `finished_at`, `migration_name`, `started_at`, `applied_steps_count`)
VALUES (UUID(), 'd346a19c0f4e46e7a6be74bdb96efd04e2ba26088dc31b170b434e6fcbadf5d1', NOW(3), '20260827000100_initial', NOW(3), 1);
INSERT INTO `_prisma_migrations` (`id`, `checksum`, `finished_at`, `migration_name`, `started_at`, `applied_steps_count`)
VALUES (UUID(), '96f356d16d69c92d8bd0ebe04b254669c9a988baa0923e926f6e83238513461f', NOW(3), '20260827000200_book_invitations', NOW(3), 1);
INSERT INTO `_prisma_migrations` (`id`, `checksum`, `finished_at`, `migration_name`, `started_at`, `applied_steps_count`)
VALUES (UUID(), 'dd95d592505428d4af16ff7c2a47c925f354f2f1cf99206f00f4a854432569df', NOW(3), '20260829000100_idempotency_records', NOW(3), 1);

SET FOREIGN_KEY_CHECKS = 1;
